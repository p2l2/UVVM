--================================================================================================================================
-- Copyright 2026 UVVM
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and in the provided LICENSE.TXT.
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and limitations under the License.
--================================================================================================================================
-- Note : Any functionality not explicitly described in the documentation is subject to change at any time
----------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library p2l2_vip_rotary_encoder;
use p2l2_vip_rotary_encoder.rotary_encoder_bfm_pkg.all;

use work.rotary_encoder_tb_pkg.all;
use work.rotary_encoder_th_pkg.all;

--hdlregression:tb
-- Test case entity
-- BFM TB: p_main calls the BFM procedures directly on enc_if; p_logger records every change in shared_th_event_log
-- (id 1). Test case IDs refer to doc/rotary_encoder_vvc_tb_arch.md.
entity rotary_encoder_bfm_tb is
  generic(
    GC_TESTCASE : string := "UVVM"
  );
end entity;

-- Test case architecture
architecture func of rotary_encoder_bfm_tb is

  constant C_SCOPE : string   := C_TB_SCOPE_DEFAULT;
  constant C_ID    : positive := 1;

  -- Geometry of the default configuration (spec 2), computed here rather than taken from the BFM
  constant C_DEFAULT       : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
  constant C_CPR           : positive := C_DEFAULT.cycles_per_rev;                   -- 20
  constant C_EDGES_PER_REV : positive := C_EDGES_PER_CYCLE * C_CPR;                   -- 80
  constant C_DEG_PER_EDGE  : real     := real(C_DEG_PER_REV) / real(C_EDGES_PER_REV); -- 4.5

  -- Speeds. C_TPE where the timing is not under test. Angle tests run at C_TIME_PER_DEG per degree, so expected times
  -- read as angles (4.5 us per edge: 1 deg = 1 us).
  constant C_TPE               : time := 100 ns;
  constant C_TIME_PER_DEG      : time := 1 us;
  constant C_TPE_ANGLE         : time := C_TIME_PER_DEG * C_DEG_PER_EDGE;
  constant C_TIME_PER_DEG_FAST : time := 100 ns;
  constant C_TPE_ANGLE_FAST    : time := C_TIME_PER_DEG_FAST * C_DEG_PER_EDGE;

  constant C_QUIET_TIME : time := 1 us;     -- Interval checked for the absence of events
  constant C_IDLE_TIME  : time := C_TPE;    -- Before each re-init, so the previous end state shows in the waveform
  constant C_REAL_TOL   : real := 1.0e-9;   -- Tolerance of status angles and converted speeds

  type t_state_array is array (natural range <>) of std_logic_vector(1 downto 0);

  -- TC_001: start-angle matrix (REQ-002) with the default zero state 11 and the default index (Z active at position 0
  -- only). Hand-computed: position = start angle / 4.5 deg rounded to the nearest state centre; the states from position 0
  -- are 11 -> 01 -> 00 -> 10.
  type t_start_case is record
    start_angle : real;
    position    : integer;
    ab          : std_logic_vector(1 downto 0);
    z           : std_logic;
  end record t_start_case;
  type t_start_case_array is array (natural range <>) of t_start_case;
  constant C_START_CASES : t_start_case_array := (
    (0.0, 0, "11", '1'),
    (-10.0, -2, "00", '0'),
    (30.0, 7, "10", '0'),
    (400.0, 89, "01", '0'));

  -- TC_001: zero states (REQ-006). With the default index (index state 11 on the pins, width 1, index position 0), Z is
  -- active at position 0 only for the zero state 11.
  constant C_STATES          : t_state_array                := ("00", "10", "11", "01");
  constant C_Z_AT_ZERO       : std_logic_vector(0 to 3)     := "0010"; -- Z at position 0 per entry of C_STATES
  constant C_BAD_ZERO_STATE  : std_logic_vector(1 downto 0) := "0X";
  constant C_OTHER_ZERO_STATE : std_logic_vector(1 downto 0) := "00";

  -- Test vectors from the requirement criteria
  constant C_NUM_EDGES  : integer_vector := (1, 2, 3, 4, 5, 1000);   -- REQ-010
  constant C_TIMING_TPE : time_vector    := (1 ns, 1 us, 1 ms);      -- REQ-012, time form
  constant C_TIMING_RPM : integer_vector := (7, 6000);               -- REQ-012, rpm form
  constant C_LONG_RUN   : positive       := 1000;                    -- REQ-012, rpm form
  constant C_CURVE_TPE  : time_vector    := (1 us, 3 us);            -- REQ-013, time form
  constant C_CURVE_RPM  : integer_vector := (60, 120);               -- REQ-013, rpm form
  constant C_ANGLE_10   : real           := 10.0;                    -- REQ-090: 2 edges, ends at 10 deg
  constant C_ANGLE_1    : real           := 1.0;                     -- REQ-090, REQ-092: crosses no edge
  constant C_ANGLE_RPM  : positive       := 60;                      -- REQ-092, rpm form
  constant C_SMALL_STEP : real           := 0.1;                     -- REQ-091

  -- TC_094: move to state (REQ-096), time form T = 1 us. Default zero state 11: positions 0 to 3 are 11, 01, 00, 10.
  -- start_position is the state the shaft is in at start_angle, end_position the expected target centre (hand-computed).
  constant C_TO_STATE_TPE : time := 1 us;
  type t_to_state_case is record
    start_angle    : real;
    start_position : integer;
    direction      : t_rotary_encoder_direction;
    target         : std_logic_vector(1 downto 0);
    occurrence     : positive;
    end_position   : integer;
  end record t_to_state_case;
  type t_to_state_case_array is array (natural range <>) of t_to_state_case;
  constant C_TO_STATE_CASES : t_to_state_case_array := (
    (0.0, 0, FORWARD, "00", 1, 2),    -- 9 deg
    (1.125, 0, FORWARD, "00", 1, 2),  -- 9 deg, edges at 0.25 T and 1.25 T
    (10.0, 2, FORWARD, "00", 1, 6),   -- already in 00: the next one, 27 deg
    (0.0, 0, FORWARD, "00", 2, 6),    -- second occurrence, 27 deg
    (0.0, 0, REVERSE, "00", 1, -2),   -- -9 deg
    (0.0, 0, FORWARD, "10", 1, 3));   -- 13.5 deg
  constant C_BAD_TARGET : std_logic_vector(1 downto 0) := "0X"; -- REQ-098

  -- TC_095: centre state (REQ-097)
  constant C_CENTER_FROM     : real      := 10.0;         -- In position 2: centred to 9 deg
  constant C_BOUNDARY_ANGLE  : real      := 6.75;         -- Boundary between positions 1 and 2 (1.5 edge angles)
  constant C_OFFSET_ANGLES   : real_vector := (1.0, 3.5); -- Start angles of the edge-offset cases
  constant C_EDGE_OFFSET     : real      := 44.0;         -- Electrical degrees, all four edges, + and -

  signal enc_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);

  -- Debug only (waveform): shaft position and angle after each init and move, from rotary_encoder_get_status()
  signal dbg_position : integer := 0;
  signal dbg_angle    : real    := 0.0;

begin

  -- Event logger: every change on A, B or Z. The checker is armed by p_main.
  p_logger : process is
  begin
    wait on enc_if.a, enc_if.b, enc_if.z;
    shared_th_event_log.add(C_ID, enc_if, enc_if.a'event, enc_if.b'event, enc_if.z'event);
  end process p_logger;

  p_main : process is
    variable v_start : time;
    variable v_state      : t_rotary_encoder_state;
    variable v_config     : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    variable v_bad_config : t_rotary_encoder_bfm_config;
    variable v_status     : t_rotary_encoder_status;
    variable v_t_start    : time;
    variable v_alerts     : natural;
    variable v_rej_alerts : natural;
    variable v_rej_time   : time;
    variable v_rej_count  : natural;
    variable v_time_out   : time;
    variable v_real_out   : real;
    variable v_num        : natural;
    variable v_count_start : natural;
    variable v_dir        : integer;

    -- Default configuration with start angle
    function config_with(
      constant start_angle : in real) return t_rotary_encoder_bfm_config is
      variable v_result : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    begin
      v_result.start_angle := start_angle;
      return v_result;
    end function;

    function dir_sign(
      constant direction : in t_rotary_encoder_direction) return integer is
    begin
      if direction = FORWARD then
        return 1;
      else
        return -1;
      end if;
    end function;

    -- Updates the debug signals from the BFM state (after an init or a move)
    procedure update_debug is
      variable v_debug : t_rotary_encoder_status;
    begin
      v_debug      := rotary_encoder_get_status(v_state);
      dbg_position <= v_debug.position;
      dbg_angle    <= v_debug.angle;
    end procedure;

    -- Initializes the encoder with config, lets the logger record the init, then arms and clears the checker. Waits
    -- C_IDLE_TIME first, so that dbg_position/dbg_angle hold the previous end state visibly.
    procedure init_encoder(
      constant config : in t_rotary_encoder_bfm_config) is
    begin
      wait for C_IDLE_TIME;
      v_config := config;
      rotary_encoder_init(v_state, "init", enc_if, config => v_config);
      update_debug;
      wait for 0 ns;
      wait for 0 ns;
      shared_th_event_log.arm(C_ID, enc_if);
      shared_th_event_log.clear(C_ID);
    end procedure;

    procedure edges(
      constant direction     : in t_rotary_encoder_direction;
      constant num_edges     : in natural;
      constant time_per_edge : in time) is
    begin
      rotary_encoder_move_edges(direction, num_edges, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure edges(
      constant direction : in t_rotary_encoder_direction;
      constant num_edges : in natural;
      constant rpm       : in real) is
    begin
      rotary_encoder_move_edges(direction, num_edges, rpm, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure angle(
      constant direction     : in t_rotary_encoder_direction;
      constant degrees       : in real;
      constant time_per_edge : in time) is
    begin
      rotary_encoder_move_angle(direction, degrees, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure angle(
      constant direction : in t_rotary_encoder_direction;
      constant degrees   : in real;
      constant rpm       : in real) is
    begin
      rotary_encoder_move_angle(direction, degrees, rpm, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure move_to_state(
      constant direction     : in t_rotary_encoder_direction;
      constant target        : in std_logic_vector(1 downto 0);
      constant occurrence    : in natural;
      constant time_per_edge : in time) is
    begin
      rotary_encoder_move_to_state(direction, target, occurrence, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    -- Records the time and the event count before the call, for check_zero_time_no_event. The two deltas let the logger
    -- record the last edge of a preceding move first (no simulation time passes).
    procedure center is
    begin
      wait for 0 ns;
      wait for 0 ns;
      v_t_start     := now;
      v_count_start := shared_th_event_log.count(C_ID);
      rotary_encoder_center_state(v_state, "centre", config => v_config);
      update_debug;
    end procedure;

    -- Power-up with config: AB and Z at the first delta, the status, and no event afterwards (REQ-001, REQ-002)
    procedure check_power_up(
      constant config : in t_rotary_encoder_bfm_config;
      constant ab     : in std_logic_vector(1 downto 0);
      constant z      : in std_logic;
      constant msg    : in string) is
    begin
      v_config := config;
      rotary_encoder_init(v_state, "power-up", enc_if, config => v_config);
      update_debug;
      wait for 0 ns;                    -- first delta after the init
      check_value(std_logic_vector'(enc_if.a & enc_if.b), ab, MATCH_EXACT, ERROR, "AB at " & msg, C_SCOPE,
                  msg_id => ID_SEQUENCER_SUB);
      check_value(enc_if.z, z, MATCH_EXACT, ERROR, "Z at " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      wait for 0 ns;
      shared_th_event_log.arm(C_ID, enc_if);
      shared_th_event_log.clear(C_ID);
      v_t_start := now;
      wait for C_QUIET_TIME;
      check_no_event(shared_th_event_log, C_ID, v_t_start, now, "no event after " & msg);
      check_checker(shared_th_event_log, C_ID, 0, msg);
    end procedure;

    -- The first C_EDGES_PER_CYCLE logged events pass the forward sequence from zero_state and end in it (REQ-006)
    procedure check_forward_cycle(
      constant zero_state : in std_logic_vector(1 downto 0);
      constant msg        : in string) is
      constant C_ZERO_GRAY : integer := gray_index(zero_state(1), zero_state(0));
      variable v_event     : t_enc_event;
    begin
      check_value(shared_th_event_log.num_edges(C_ID), C_EDGES_PER_CYCLE, ERROR, "edge count: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      for k in 1 to C_EDGES_PER_CYCLE loop
        v_event := shared_th_event_log.get(C_ID, k - 1);
        check_value(gray_index(v_event.a, v_event.b), (C_ZERO_GRAY + k) mod C_EDGES_PER_CYCLE, ERROR,
                    "Gray index after forward edge " & to_string(k) & ": " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      end loop;
      check_value(std_logic_vector'(enc_if.a & enc_if.b), zero_state, MATCH_EXACT, ERROR, "ends in the zero state: " & msg,
                  C_SCOPE, msg_id => ID_SEQUENCER_SUB);
    end procedure;

    -- After center: no time consumed, no new event within C_QUIET_TIME. Counted from the call on, not by time: a move that
    -- ends on a boundary emits its last edge at the time of the call (A-13).
    procedure check_zero_time_no_event(
      constant msg : in string) is
    begin
      check_value(now, v_t_start, ERROR, "zero time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(C_ID), v_count_start, ERROR, "no event: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- Rejected call (tb arch 3.5): exactly one new TB_ERROR, no time consumed, no event
    procedure begin_reject(
      constant msg : in string) is
    begin
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, msg);
      v_rej_alerts := get_alert_counter(TB_ERROR);
      v_rej_time   := now;
      v_rej_count  := shared_th_event_log.count(C_ID);
    end procedure;

    procedure end_reject(
      constant msg : in string) is
    begin
      check_value(get_alert_counter(TB_ERROR) - v_rej_alerts, 1, ERROR, "one TB_ERROR: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_value(now, v_rej_time, ERROR, "no time consumed: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(C_ID), v_rej_count, ERROR, "no event: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    procedure check_status(
      constant exp_position : in integer;
      constant exp_angle    : in real;
      constant msg          : in string) is
    begin
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, exp_position, ERROR, "status position: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_value_in_range(v_status.angle, exp_angle - C_REAL_TOL, exp_angle + C_REAL_TOL, ERROR, "status angle: " & msg, C_SCOPE,
                           ID_SEQUENCER_SUB);
    end procedure;

    -- Logged event idx at expected +- tolerance
    procedure check_event_time(
      constant idx       : in natural;
      constant expected  : in time;
      constant tolerance : in time;
      constant msg       : in string) is
    begin
      if shared_th_event_log.count(C_ID) <= idx then
        alert(ERROR, "event " & to_string(idx) & " missing: " & msg, C_SCOPE);
      else
        check_value_in_range(shared_th_event_log.get(C_ID, idx).time_stamp, expected - tolerance, expected + tolerance, ERROR,
                             "event " & to_string(idx) & " time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      end if;
    end procedure;

    procedure check_duration(
      constant expected  : in time;
      constant tolerance : in time;
      constant msg       : in string) is
    begin
      check_value_in_range(now - v_t_start, expected - tolerance, expected + tolerance, ERROR, "duration: " & msg, C_SCOPE,
                           ID_SEQUENCER_SUB);
    end procedure;

    -- TC_000: drives the interface directly (testbench self-test, no BFM procedure involved)
    procedure drive(
      constant a : in std_logic;
      constant b : in std_logic;
      constant z : in std_logic) is
    begin
      enc_if <= (a, b, z);
      wait for C_TPE;
    end procedure;

    procedure check_edge_time(
      constant t_start        : in time;
      constant k              : in positive;
      constant rpm            : in positive;
      constant cycles_per_rev : in positive;
      constant exp_ps         : in time;   -- expected value at ps resolution
      constant exp_fs         : in time) is -- expected value at fs resolution
    begin
      if C_RESOLUTION = 1 fs then
        check_value(ideal_edge_time(t_start, k, rpm, cycles_per_rev), exp_fs, ERROR,
                    "ideal_edge_time(" & to_string(k) & ", " & to_string(rpm) & " rpm, " & to_string(cycles_per_rev) & " cpr)",
                    C_SCOPE, ID_SEQUENCER_SUB);
      else
        check_value(ideal_edge_time(t_start, k, rpm, cycles_per_rev), exp_ps, ERROR,
                    "ideal_edge_time(" & to_string(k) & ", " & to_string(rpm) & " rpm, " & to_string(cycles_per_rev) & " cpr)",
                    C_SCOPE, ID_SEQUENCER_SUB);
      end if;
    end procedure;

  begin
    -- To avoid that log files from different test cases (run in separate simulations) overwrite each other.
    set_log_file_name(GC_TESTCASE & "_Log.txt");
    set_alert_file_name(GC_TESTCASE & "_Alert.txt");

    -- Print the configuration to the log
    report_global_ctrl(VOID);
    report_msg_id_panel(VOID);

    -- Verbosity control
    enable_log_msg(ALL_MESSAGES);
    disable_log_msg(ID_POS_ACK);

    log(ID_LOG_HDR_LARGE, "Simulating " & GC_TESTCASE & ", resolution " & to_string(C_RESOLUTION), C_SCOPE);

    --============================================================================================================================
    if GC_TESTCASE = "TC_000" then
      -- Testbench self-test (Stage 5.2): decoder checker on hand-driven sequences, ideal_edge_time() against hand values
      log(ID_LOG_HDR, "TC_000: Gray index", C_SCOPE);
      check_value(gray_index('0', '0'), 0, ERROR, "gray_index 00", C_SCOPE);
      check_value(gray_index('1', '0'), 1, ERROR, "gray_index 10", C_SCOPE);
      check_value(gray_index('1', '1'), 2, ERROR, "gray_index 11", C_SCOPE);
      check_value(gray_index('0', '1'), 3, ERROR, "gray_index 01", C_SCOPE);
      check_value(gray_index('X', '1'), -1, ERROR, "gray_index X1", C_SCOPE);

      log(ID_LOG_HDR, "TC_000: checker on forward, reverse, illegal and invalid-level sequences", C_SCOPE);
      drive('1', '1', '0');
      shared_th_event_log.arm(C_ID, enc_if);
      shared_th_event_log.clear(C_ID);
      -- 4 forward edges: 11 -> 01 -> 00 -> 10 -> 11
      drive('0', '1', '0');
      drive('0', '0', '0');
      drive('1', '0', '0');
      drive('1', '1', '0');
      check_checker(shared_th_event_log, C_ID, 4, "4 forward edges");
      -- 2 reverse edges: 11 -> 10 -> 00
      drive('1', '0', '0');
      drive('0', '0', '0');
      check_checker(shared_th_event_log, C_ID, 2, "4 forward, 2 reverse edges");
      -- Illegal transition: 00 -> 11 in one delta, position unchanged
      drive('1', '1', '0');
      check_checker(shared_th_event_log, C_ID, 2, "illegal transition", exp_illegal => 1);
      -- Invalid level on A, then back
      drive('X', '1', '0');
      drive('1', '1', '0');
      check_checker(shared_th_event_log, C_ID, 2, "invalid level", exp_illegal => 1, exp_invalid => 1);
      -- Index pulse
      drive('1', '1', '1');
      drive('1', '1', '0');
      check_value(shared_th_event_log.num_edges(C_ID), 6, ERROR, "number of edges", C_SCOPE);
      check_value(shared_th_event_log.num_z_events(C_ID), 2, ERROR, "number of Z events", C_SCOPE);
      check_value(shared_th_event_log.count(C_ID), 11, ERROR, "number of log entries", C_SCOPE);

      log(ID_LOG_HDR, "TC_000: zero-length state (two events in different deltas at the same time)", C_SCOPE);
      shared_th_event_log.clear(C_ID);
      enc_if.a <= '0';
      wait for 0 ns;
      enc_if.a <= '1';
      wait for C_TPE;
      check_value(shared_th_event_log.count(C_ID), 2, ERROR, "two log entries", C_SCOPE);
      check_value(shared_th_event_log.get(C_ID, 0).time_stamp, shared_th_event_log.get(C_ID, 1).time_stamp, ERROR,
                  "same time stamp", C_SCOPE);
      check_value(shared_th_event_log.num_edges(C_ID), 2, ERROR, "two edges", C_SCOPE);
      check_checker(shared_th_event_log, C_ID, 0, "forward and back");

      log(ID_LOG_HDR, "TC_000: check_no_event", C_SCOPE);
      v_start := now;
      wait for C_QUIET_TIME;
      check_no_event(shared_th_event_log, C_ID, v_start, now, "quiet interval");
      drive('0', '1', '0');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "check_no_event must detect the event");
      check_no_event(shared_th_event_log, C_ID, v_start, now, "event expected to be detected");

      -- Hand-computed reference values (exact fractions at 20 cycles/rev), independent of the default configuration
      log(ID_LOG_HDR, "TC_000: ideal_edge_time against exact values (floor to the resolution)", C_SCOPE);
      check_edge_time(0 ns, 1, 60, 20, 6250 us, 6250 us);
      check_edge_time(0 ns, 2, 60, 20, 18750 us, 18750 us);
      check_edge_time(0 ns, 1, 7, 20, 53 ms + 571 us + 428 ns + 571 ps, 53 ms + 571 us + 428 ns + 571 ps + 428 fs);
      check_edge_time(0 ns, 1000, 7, 20, 107 sec + 89 ms + 285 us + 714 ns + 285 ps,
                      107 sec + 89 ms + 285 us + 714 ns + 285 ps + 714 fs);
      check_edge_time(0 ns, 3, 6000, 20, 312500 ns, 312500 ns);
      check_edge_time(0 ns, 7, 6000, 1024, 15 us + 869 ns + 140 ps, 15 us + 869 ns + 140 ps + 625 fs);
      check_edge_time(1 us, 1, 60, 20, 6251 us, 6251 us);

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_001" then
      -- REQ-001, REQ-002, REQ-006: power-up state per start angle and per zero state, no A/B event before the first move;
      -- invalid and changed zero state
      log(ID_LOG_HDR, "TC_001: start-angle matrix", C_SCOPE);
      for i in C_START_CASES'range loop
        check_power_up(config_with(C_START_CASES(i).start_angle), C_START_CASES(i).ab, C_START_CASES(i).z,
                       "start angle " & to_string(C_START_CASES(i).start_angle, 1));
        check_status(C_START_CASES(i).position, C_START_CASES(i).start_angle, "power-up " & to_string(i));
      end loop;

      log(ID_LOG_HDR, "TC_001: the four zero states, each followed by one forward cycle", C_SCOPE);
      for i in C_STATES'range loop
        v_bad_config            := C_DEFAULT;
        v_bad_config.zero_state := C_STATES(i);
        check_power_up(v_bad_config, C_STATES(i), C_Z_AT_ZERO(i), "zero state " & to_string(C_STATES(i)));
        check_status(0, 0.0, "zero state " & to_string(C_STATES(i)));
        edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE);
        check_forward_cycle(C_STATES(i), "zero state " & to_string(C_STATES(i)));
        check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE, "forward cycle from zero state " & to_string(C_STATES(i)));
      end loop;

      log(ID_LOG_HDR, "TC_001: invalid zero state at init", C_SCOPE);
      init_encoder(C_DEFAULT);
      v_bad_config            := C_DEFAULT;
      v_bad_config.zero_state := C_BAD_ZERO_STATE;
      begin_reject("init with zero state " & to_string(C_BAD_ZERO_STATE));
      rotary_encoder_init(v_state, "invalid zero state", enc_if, config => v_bad_config);
      end_reject("init with zero state " & to_string(C_BAD_ZERO_STATE));

      log(ID_LOG_HDR, "TC_001: invalid and changed zero state after init", C_SCOPE);
      for i in 0 to 1 loop
        if i = 0 then
          v_bad_config.zero_state := C_BAD_ZERO_STATE;
        else
          v_bad_config.zero_state := C_OTHER_ZERO_STATE;
        end if;
        begin_reject("edge move with zero state " & to_string(v_bad_config.zero_state));
        rotary_encoder_move_edges(FORWARD, 1, C_TPE, v_state, "zero state changed", enc_if, config => v_bad_config);
        end_reject("edge move with zero state " & to_string(v_bad_config.zero_state));
        begin_reject("centre state with zero state " & to_string(v_bad_config.zero_state));
        rotary_encoder_center_state(v_state, "zero state changed", config => v_bad_config);
        end_reject("centre state with zero state " & to_string(v_bad_config.zero_state));
      end loop;
      check_status(0, 0.0, "after the rejected calls");
      edges(FORWARD, 1, C_TPE);
      check_checker(shared_th_event_log, C_ID, 1, "the kept zero state still works");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_010" then
      -- REQ-010, REQ-011, REQ-070: N edges forward/reverse from all four states
      log(ID_LOG_HDR, "TC_010: forward and reverse edge moves from all four states", C_SCOPE);
      for s in 0 to C_EDGES_PER_CYCLE - 1 loop
        for i in C_NUM_EDGES'range loop
          init_encoder(config_with(real(s) * C_DEG_PER_EDGE));
          edges(FORWARD, C_NUM_EDGES(i), C_TPE);
          check_checker(shared_th_event_log, C_ID, C_NUM_EDGES(i), "forward " & to_string(C_NUM_EDGES(i)) & " from state " & to_string(s));
          check_value(shared_th_event_log.num_edges(C_ID), C_NUM_EDGES(i), ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
          check_status(s + C_NUM_EDGES(i), real(s + C_NUM_EDGES(i)) * C_DEG_PER_EDGE, "forward");
          init_encoder(config_with(real(s) * C_DEG_PER_EDGE));
          edges(REVERSE, C_NUM_EDGES(i), C_TPE);
          check_checker(shared_th_event_log, C_ID, -C_NUM_EDGES(i), "reverse " & to_string(C_NUM_EDGES(i)) & " from state " & to_string(s));
          check_value(shared_th_event_log.num_edges(C_ID), C_NUM_EDGES(i), ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
          check_status(s - C_NUM_EDGES(i), real(s - C_NUM_EDGES(i)) * C_DEG_PER_EDGE, "reverse");
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_011" then
      -- REQ-012, REQ-013: edge timing in both forms, back to back, speed curves
      log(ID_LOG_HDR, "TC_011: time form, 10 edges per speed", C_SCOPE);
      for i in C_TIMING_TPE'range loop
        init_encoder(config_with(0.0));
        v_t_start := now;
        edges(FORWARD, 10, C_TIMING_TPE(i));
        check_duration(10 * C_TIMING_TPE(i), 0 ns, "10 edges at " & to_string(C_TIMING_TPE(i), ns));
        check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 10, C_TIMING_TPE(i), "10 edges at " & to_string(C_TIMING_TPE(i), ns));
        check_checker(shared_th_event_log, C_ID, 10, "timing");
      end loop;

      log(ID_LOG_HDR, "TC_011: back to back with direction changes: +3 -2 +2", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, C_TPE);
      edges(REVERSE, 2, C_TPE);
      edges(FORWARD, 2, C_TPE);
      check_duration(7 * C_TPE, 0 ns, "3 + 2 + 2 edges");
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 7, C_TPE, "back to back");
      check_checker(shared_th_event_log, C_ID, 3, "back to back");

      log(ID_LOG_HDR, "TC_011: rpm form, " & to_string(C_LONG_RUN) & " edges per speed", C_SCOPE);
      increment_expected_alerts(TB_WARNING, 1, "UVVM time stamp truncation (7 rpm ends between whole ns, shown once)");
      for i in C_TIMING_RPM'range loop
        init_encoder(config_with(0.0));
        v_t_start := now;
        edges(FORWARD, C_LONG_RUN, real(C_TIMING_RPM(i)));
        check_duration(ideal_move_time(0 ns, C_LONG_RUN, C_TIMING_RPM(i), C_CPR), C_RESOLUTION,
                       to_string(C_LONG_RUN) & " edges at " & to_string(C_TIMING_RPM(i)) & " rpm");
        check_edge_times_rpm(shared_th_event_log, C_ID, 0, v_t_start, C_LONG_RUN, C_TIMING_RPM(i), C_CPR, to_string(C_TIMING_RPM(i)) & " rpm");
        check_checker(shared_th_event_log, C_ID, C_LONG_RUN, "rpm form");
      end loop;

      log(ID_LOG_HDR, "TC_011: speed curve, time form: 3 edges per speed", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, C_CURVE_TPE(0));
      edges(FORWARD, 3, C_CURVE_TPE(1));
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 3, C_CURVE_TPE(0), "first speed");
      check_edge_times(shared_th_event_log, C_ID, 3, v_t_start + 3 * C_CURVE_TPE(0), 3, C_CURVE_TPE(1), "second speed");
      check_value(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                  (C_CURVE_TPE(0) + C_CURVE_TPE(1)) / 2, ERROR, "interval at the speed change = mean of the two time_per_edge",
                  C_SCOPE, ID_SEQUENCER_SUB);

      log(ID_LOG_HDR, "TC_011: speed curve, rpm form: 3 edges per speed", C_SCOPE);
      init_encoder(config_with(0.0));
      edges(FORWARD, 3, real(C_CURVE_RPM(0)));
      edges(FORWARD, 3, real(C_CURVE_RPM(1)));
      v_time_out := (ideal_move_time(0 ns, 1, C_CURVE_RPM(0), C_CPR) + ideal_move_time(0 ns, 1, C_CURVE_RPM(1), C_CPR)) / 2;
      check_value_in_range(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                           v_time_out - 2 * C_RESOLUTION, v_time_out + 2 * C_RESOLUTION, ERROR,
                           "interval at the speed change = mean of the two time_per_edge", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 6, "speed curves");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_012" then
      -- REQ-004, REQ-014: reversal from each state, continuity over a mixed sequence
      log(ID_LOG_HDR, "TC_012: +1/-1 edge, 10 times from each state", C_SCOPE);
      for s in 0 to C_EDGES_PER_CYCLE - 1 loop
        init_encoder(config_with(real(s) * C_DEG_PER_EDGE));
        for i in 1 to 10 loop
          edges(FORWARD, 1, C_TPE);
          edges(REVERSE, 1, C_TPE);
        end loop;
        check_checker(shared_th_event_log, C_ID, 0, "reversals from state " & to_string(s));
        check_value(shared_th_event_log.num_edges(C_ID), 20, ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
        check_status(s, real(s) * C_DEG_PER_EDGE, "back at the start");
      end loop;

      log(ID_LOG_HDR, "TC_012: mixed sequence +5 -3 +7 -10", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 5, C_TPE);
      edges(REVERSE, 3, C_TPE);
      edges(FORWARD, 7, C_TPE);
      edges(REVERSE, 10, C_TPE);
      check_checker(shared_th_event_log, C_ID, -1, "mixed sequence");
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 25, C_TPE, "mixed sequence, continuous timing");
      check_status(-1, -C_DEG_PER_EDGE, "mixed sequence");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_013" then
      -- REQ-015: 0-edge move
      log(ID_LOG_HDR, "TC_013: moves of 0 edges and 0 deg", C_SCOPE);
      init_encoder(C_DEFAULT);
      v_t_start := now;
      edges(FORWARD, 0, C_TPE);
      edges(REVERSE, 0, real(C_ANGLE_RPM));
      angle(REVERSE, 0.0, C_TPE);
      check_duration(0 ns, 0 ns, "0 edges, 0 deg");
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(0, 0.0, "0 edges");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_014" then
      -- REQ-016: invalid speeds
      log(ID_LOG_HDR, "TC_014: invalid speeds", C_SCOPE);
      init_encoder(C_DEFAULT);
      begin_reject("time_per_edge 0 ns");
      edges(FORWARD, 4, 0 ns);
      end_reject("time_per_edge 0 ns");
      begin_reject("time_per_edge -1 ns");
      edges(FORWARD, 4, -1 ns);
      end_reject("time_per_edge -1 ns");
      begin_reject("0 rpm");
      rotary_encoder_move_edges(FORWARD, 4, 0.0, v_state, "0 rpm", enc_if, config => v_config);
      end_reject("0 rpm");
      begin_reject("-60 rpm");
      rotary_encoder_move_edges(FORWARD, 4, -60.0, v_state, "-60 rpm", enc_if, config => v_config);
      end_reject("-60 rpm");
      begin_reject("rpm not finite");
      rotary_encoder_move_edges(FORWARD, 4, real'high, v_state, "real'high rpm", enc_if, config => v_config);
      end_reject("rpm not finite");
      begin_reject("angle move at 0 rpm");
      rotary_encoder_move_angle(FORWARD, C_ANGLE_10, 0.0, v_state, "0 rpm", enc_if, config => v_config);
      end_reject("angle move at 0 rpm");
      check_status(0, 0.0, "after the rejected calls");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_090" then
      -- REQ-090, REQ-092: edges at the boundary crossings, the end exactly at the target, durations in both forms
      log(ID_LOG_HDR, "TC_090: three 1 deg moves, the edge at half an edge angle", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      for i in 1 to 3 loop
        angle(FORWARD, C_ANGLE_1, C_TPE_ANGLE);
        check_duration(i * C_TIME_PER_DEG, i * C_RESOLUTION, to_string(i) & " x 1 deg");
        check_value(shared_th_event_log.count(C_ID), i / 3, ERROR, "edges after " & to_string(i) & " moves", C_SCOPE, ID_SEQUENCER_SUB);
      end loop;
      check_event_time(0, v_t_start + C_TIME_PER_DEG * (0.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at half an edge angle");
      check_checker(shared_th_event_log, C_ID, 1, "3 x 1 deg");
      check_status(1, 3.0 * C_ANGLE_1, "3 x 1 deg");

      log(ID_LOG_HDR, "TC_090: " & to_string(C_ANGLE_10, 1) & " deg from 0 deg: 2 edges, ends at the target", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(FORWARD, C_ANGLE_10, C_TPE_ANGLE);
      check_duration(C_TIME_PER_DEG * C_ANGLE_10, C_RESOLUTION, "time form");
      check_event_time(0, v_t_start + C_TIME_PER_DEG * (0.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at 0.5 edge angles");
      check_event_time(1, v_t_start + C_TIME_PER_DEG * (1.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at 1.5 edge angles");
      check_value(shared_th_event_log.num_edges(C_ID), 2, ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 2, "forward");
      check_status(2, C_ANGLE_10, "forward");
      init_encoder(config_with(0.0));
      angle(REVERSE, C_ANGLE_10, C_TPE_ANGLE);
      check_checker(shared_th_event_log, C_ID, -2, "reverse");
      check_status(-2, -C_ANGLE_10, "reverse");

      log(ID_LOG_HDR, "TC_090: durations in the rpm form, also without an edge", C_SCOPE);
      increment_expected_alerts(TB_WARNING, 1, "UVVM time stamp truncation (moves end between whole ns, shown once)");
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(FORWARD, C_ANGLE_10, real(C_ANGLE_RPM));
      check_duration(ideal_angle_time(integer(C_ANGLE_10), C_ANGLE_RPM), C_RESOLUTION, to_string(C_ANGLE_10, 1) & " deg");
      v_t_start := now;
      angle(FORWARD, C_ANGLE_1, real(C_ANGLE_RPM));
      check_duration(ideal_angle_time(integer(C_ANGLE_1), C_ANGLE_RPM), C_RESOLUTION, to_string(C_ANGLE_1, 1) & " deg, no edge");
      check_checker(shared_th_event_log, C_ID, 2, "rpm-form moves");
      check_status(2, C_ANGLE_10 + C_ANGLE_1, "rpm-form moves");

      log(ID_LOG_HDR, "TC_090: duration in the time form without an edge", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(REVERSE, C_ANGLE_1, C_TPE_ANGLE);
      check_duration(C_TIME_PER_DEG * C_ANGLE_1, C_RESOLUTION, to_string(C_ANGLE_1, 1) & " deg, no edge");
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(0, -C_ANGLE_1, "time-form move without an edge");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_091" then
      -- REQ-091, REQ-093: no drift; mixed edge and angle moves keep the sub-edge fraction. Moves at C_TPE_ANGLE_FAST.
      disable_log_msg(ID_BFM);
      log(ID_LOG_HDR, "TC_091: one revolution in 1 deg moves", C_SCOPE);
      init_encoder(config_with(0.0));
      for i in 1 to C_DEG_PER_REV loop
        angle(FORWARD, 1.0, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "1 deg moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);

      log(ID_LOG_HDR, "TC_091: one revolution in " & to_string(C_SMALL_STEP, 1) & " deg moves", C_SCOPE);
      init_encoder(config_with(0.0));
      for i in 1 to integer(real(C_DEG_PER_REV) / C_SMALL_STEP) loop
        angle(FORWARD, C_SMALL_STEP, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "small moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after small moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after small moves", C_SCOPE, ID_SEQUENCER_SUB);

      log(ID_LOG_HDR, "TC_091: one revolution in pairs of (1 edge, 1 edge angle)", C_SCOPE);
      init_encoder(config_with(0.0));
      for i in 1 to C_EDGES_PER_REV / 2 loop
        edges(FORWARD, 1, C_TPE_ANGLE_FAST);
        angle(FORWARD, C_DEG_PER_EDGE, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "mixed");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after the mixed sequence", C_SCOPE, ID_SEQUENCER_SUB);
      enable_log_msg(ID_BFM);

      log(ID_LOG_HDR, "TC_091: 2 deg, 1 edge, 1 deg: edges at 0.5 and 1.5 edge angles", C_SCOPE);
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(FORWARD, 2.0, C_TPE_ANGLE_FAST);
      edges(FORWARD, 1, C_TPE_ANGLE_FAST);
      angle(FORWARD, 1.0, C_TPE_ANGLE_FAST);
      check_event_time(0, v_t_start + C_TIME_PER_DEG_FAST * (0.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge during the edge move");
      check_event_time(1, v_t_start + C_TIME_PER_DEG_FAST * (1.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge during the second angle move");
      check_duration(C_TIME_PER_DEG_FAST * (2.0 + C_DEG_PER_EDGE + 1.0), 3 * C_RESOLUTION, "2 deg + 1 edge + 1 deg");
      check_status(2, 2.0 + C_DEG_PER_EDGE + 1.0, "2 deg + 1 edge + 1 deg");
      check_checker(shared_th_event_log, C_ID, 2, "mixed");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_092" then
      -- REQ-094: invalid angles; REQ-098: invalid move-to-state parameters
      log(ID_LOG_HDR, "TC_092: invalid angles", C_SCOPE);
      init_encoder(C_DEFAULT);
      begin_reject("angle -1.0");
      angle(FORWARD, -C_ANGLE_1, C_TPE);
      end_reject("angle -1.0");
      begin_reject("angle not finite");
      angle(REVERSE, real'high, C_TPE);
      end_reject("angle not finite");
      begin_reject("angle -1.0, rpm form");
      rotary_encoder_move_angle(FORWARD, -C_ANGLE_1, real(C_ANGLE_RPM), v_state, "-1 deg", enc_if, config => v_config);
      end_reject("angle -1.0, rpm form");
      check_status(0, 0.0, "after the rejected angle moves");

      log(ID_LOG_HDR, "TC_092: invalid move-to-state parameters", C_SCOPE);
      begin_reject("occurrence 0");
      move_to_state(FORWARD, C_STATES(0), 0, C_TPE);
      end_reject("occurrence 0");
      begin_reject("target state " & to_string(C_BAD_TARGET));
      move_to_state(FORWARD, C_BAD_TARGET, 1, C_TPE);
      end_reject("target state " & to_string(C_BAD_TARGET));
      begin_reject("time_per_edge 0 ns");
      move_to_state(REVERSE, C_STATES(0), 1, 0 ns);
      end_reject("time_per_edge 0 ns");
      begin_reject("-60 rpm");
      rotary_encoder_move_to_state(FORWARD, C_STATES(0), 1, -real(C_ANGLE_RPM), v_state, "-60 rpm", enc_if, config => v_config);
      end_reject("-60 rpm");
      check_status(0, 0.0, "after the rejected move-to-state calls");
      check_value(rotary_encoder_get_status(v_state).ab, C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "status AB unchanged",
                  C_SCOPE, msg_id => ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_093" then
      -- REQ-095: conversion functions. Expected values are the literal values of the REQ-095 criteria.
      log(ID_LOG_HDR, "TC_093: rpm <-> time_per_edge, rpm <-> deg/s", C_SCOPE);
      check_value(rotary_encoder_rpm_to_time_per_edge(1.0, C_CPR), 750 ms, ERROR, "1 rpm", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_rpm_to_time_per_edge(60.0, C_CPR), 12500 us, ERROR, "60 rpm", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_rpm_to_time_per_edge(6000.0, C_CPR), 125 us, ERROR, "6000 rpm", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_rpm_to_time_per_edge(-60.0, C_CPR), 12500 us, ERROR, "-60 rpm (magnitude)", C_SCOPE, ID_SEQUENCER_SUB);
      check_value_in_range(rotary_encoder_time_per_edge_to_rpm(750 ms, C_CPR), 1.0 - C_REAL_TOL, 1.0 + C_REAL_TOL, ERROR,
                           "750 ms", C_SCOPE, ID_SEQUENCER_SUB);
      check_value_in_range(rotary_encoder_time_per_edge_to_rpm(12500 us, C_CPR), 60.0 - C_REAL_TOL, 60.0 + C_REAL_TOL, ERROR,
                           "12.5 ms", C_SCOPE, ID_SEQUENCER_SUB);
      check_value_in_range(rotary_encoder_time_per_edge_to_rpm(125 us, C_CPR), 6000.0 * (1.0 - C_REAL_TOL),
                           6000.0 * (1.0 + C_REAL_TOL), ERROR, "125 us", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_rpm_to_deg_per_sec(60.0), 360.0, ERROR, "60 rpm = 360 deg/s", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_deg_per_sec_to_rpm(360.0), 60.0, ERROR, "360 deg/s = 60 rpm", C_SCOPE, ID_SEQUENCER_SUB);

      log(ID_LOG_HDR, "TC_093: invalid arguments", C_SCOPE);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 5, "invalid conversions");
      v_alerts   := get_alert_counter(TB_ERROR);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(60.0, 0);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(0.0, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(0 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(-1 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(1 ms, 0);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 5, ERROR, "one TB_ERROR per invalid call", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_094" then
      -- REQ-096: move to state. Expected edges at the boundaries between the start angle and the target centre, each
      -- (distance to the boundary) / edge angle * T after the start; the move completes at the target centre.
      log(ID_LOG_HDR, "TC_094: move to state, time form " & to_string(C_TO_STATE_TPE, ns), C_SCOPE);
      increment_expected_alerts(TB_WARNING, 1, "UVVM time stamp truncation (the 10 deg case ends between whole ns, shown once)");
      for i in C_TO_STATE_CASES'range loop
        init_encoder(config_with(C_TO_STATE_CASES(i).start_angle));
        v_t_start := now;
        move_to_state(C_TO_STATE_CASES(i).direction, C_TO_STATE_CASES(i).target, C_TO_STATE_CASES(i).occurrence, C_TO_STATE_TPE);
        v_num := abs(C_TO_STATE_CASES(i).end_position - C_TO_STATE_CASES(i).start_position);
        v_dir := dir_sign(C_TO_STATE_CASES(i).direction);
        check_duration(C_TO_STATE_TPE * (abs(real(C_TO_STATE_CASES(i).end_position) * C_DEG_PER_EDGE - C_TO_STATE_CASES(i).start_angle) /
                       C_DEG_PER_EDGE), C_RESOLUTION, "case " & to_string(i));
        for k in 1 to v_num loop
          -- Boundary k in the move direction: (start_position + dir * (k - 1/2)) edge angles
          check_event_time(k - 1, v_t_start + C_TO_STATE_TPE * (abs((real(C_TO_STATE_CASES(i).start_position) + real(v_dir) * (real(k) - 0.5)) *
                           C_DEG_PER_EDGE - C_TO_STATE_CASES(i).start_angle) / C_DEG_PER_EDGE), C_RESOLUTION, "case " & to_string(i));
        end loop;
        check_value(shared_th_event_log.num_edges(C_ID), v_num, ERROR, "edge count, case " & to_string(i), C_SCOPE, ID_SEQUENCER_SUB);
        check_checker(shared_th_event_log, C_ID, v_dir * v_num, "case " & to_string(i));
        check_status(C_TO_STATE_CASES(i).end_position, real(C_TO_STATE_CASES(i).end_position) * C_DEG_PER_EDGE, "case " & to_string(i));
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_095" then
      -- REQ-097: centre state
      log(ID_LOG_HDR, "TC_095: from " & to_string(C_CENTER_FROM, 1) & " deg", C_SCOPE);
      init_encoder(config_with(C_CENTER_FROM));
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "centred");
      check_zero_time_no_event("centre state");
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "already on the centre: unchanged");
      check_zero_time_no_event("centre state on the centre");

      log(ID_LOG_HDR, "TC_095: on the boundary at " & to_string(C_BOUNDARY_ANGLE, 2) & " deg: the state moved into", C_SCOPE);
      init_encoder(config_with(0.0));
      angle(FORWARD, C_BOUNDARY_ANGLE, C_TPE_ANGLE);
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "forward move ending on the boundary");
      check_zero_time_no_event("centre state after the forward move");
      check_checker(shared_th_event_log, C_ID, 2, "forward move ending on the boundary");
      init_encoder(config_with(2.0 * C_DEG_PER_EDGE));
      angle(REVERSE, 2.0 * C_DEG_PER_EDGE - C_BOUNDARY_ANGLE, C_TPE_ANGLE);
      center;
      check_status(1, C_DEG_PER_EDGE, "reverse move ending on the boundary");
      check_zero_time_no_event("centre state after the reverse move");
      check_checker(shared_th_event_log, C_ID, -1, "reverse move ending on the boundary");

      -- Edge offsets are implemented in increment 3 (REQ-075); this step then also covers centring with displaced boundaries
      log(ID_LOG_HDR, "TC_095: with all four edge offsets at +-" & to_string(C_EDGE_OFFSET, 1) & " deg", C_SCOPE);
      for s in -1 to 1 loop
        next when s = 0;
        for i in C_OFFSET_ANGLES'range loop
          v_bad_config               := config_with(C_OFFSET_ANGLES(i));
          v_bad_config.a_rise_offset := real(s) * C_EDGE_OFFSET;
          v_bad_config.a_fall_offset := real(s) * C_EDGE_OFFSET;
          v_bad_config.b_rise_offset := real(s) * C_EDGE_OFFSET;
          v_bad_config.b_fall_offset := real(s) * C_EDGE_OFFSET;
          init_encoder(v_bad_config);
          v_t_start := now;
          center;
          check_zero_time_no_event("offsets " & to_string(real(s) * C_EDGE_OFFSET, 1) & " deg, from " & to_string(C_OFFSET_ANGLES(i), 1) & " deg");
        end loop;
      end loop;

      log(ID_LOG_HDR, "TC_095: from " & to_string(C_OFFSET_ANGLES(0), 1) & " deg, centre, then 1 edge", C_SCOPE);
      init_encoder(config_with(C_OFFSET_ANGLES(0)));
      center;
      v_t_start := now;
      edges(FORWARD, 1, C_TPE);
      check_event_time(0, v_t_start + C_TPE / 2, 0 ns, "edge 0.5 time_per_edge after the start");
      check_checker(shared_th_event_log, C_ID, 1, "centre state, then 1 edge");

    else
      alert(TB_ERROR, "Unsupported test case: " & GC_TESTCASE, C_SCOPE);
    end if;

    --==================================================================================================
    -- Ending the simulation
    --------------------------------------------------------------------------------------
    wait for 1000 ns;                   -- to allow some time for completion
    report_alert_counters(FINAL);       -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait;                               -- to stop completely
  end process p_main;

end architecture func;
