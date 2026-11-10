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

  -- Geometry of the default configuration, computed here rather than taken from the BFM
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

  -- power_up_state: start-angle matrix with the default zero state 11 and the default index (Z active at position 0
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

  -- power_up_state: zero states. With the default index (index state 11 on the pins, width 1, index position 0), Z is
  -- active at position 0 only for the zero state 11.
  constant C_STATES          : t_state_array                := ("00", "10", "11", "01");
  constant C_Z_AT_ZERO       : std_logic_vector(0 to 3)     := "0010"; -- Z at position 0 per entry of C_STATES
  constant C_BAD_ZERO_STATE  : std_logic_vector(1 downto 0) := "0X";
  constant C_OTHER_ZERO_STATE : std_logic_vector(1 downto 0) := "00";

  -- Move and timing test vectors
  constant C_NUM_EDGES  : integer_vector := (1, 2, 3, 4, 5, 1000);
  constant C_TIMING_TPE : time_vector    := (1 ns, 1 us, 1 ms);  -- time form
  constant C_TIMING_RPM : integer_vector := (7, 6000);  -- rpm form
  constant C_LONG_RUN   : positive       := 1000;  -- rpm form
  constant C_CURVE_TPE  : time_vector    := (1 us, 3 us);  -- time form
  constant C_CURVE_RPM  : integer_vector := (60, 120);  -- rpm form
  constant C_ANGLE_10   : real           := 10.0;                    -- 2 edges, ends at 10 deg
  constant C_ANGLE_1    : real           := 1.0;                     -- Crosses no edge
  constant C_ANGLE_RPM  : positive       := 60;  -- rpm form
  constant C_SMALL_STEP : real           := 0.1;

  -- move_to_state: time form T = 1 us. Default zero state 11: positions 0 to 3 are 11, 01, 00, 10.
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
  constant C_BAD_TARGET : std_logic_vector(1 downto 0) := "0X";

  -- center_state
  constant C_CENTER_FROM     : real      := 10.0;         -- In position 2: centred to 9 deg
  constant C_BOUNDARY_ANGLE  : real      := 6.75;         -- Boundary between positions 1 and 2 (1.5 edge angles)
  constant C_OFFSET_ANGLES   : real_vector := (1.0, 3.5); -- Start angles of the edge-offset cases
  constant C_EDGE_OFFSET     : real      := 44.0;         -- Electrical degrees, all four edges, + and -

  -- Run-to-run comparisons (index_polarity, bounce_placement, bounce_with_jitter, jitter): the second run is logged into C_ID_CMP
  constant C_ID_CMP : positive := 2;

  -- index_polarity, index_once_per_revolution, index_width_and_state. Stimulus: C_INDEX_REVS revolutions plus C_INDEX_EXTRA edges forward, then the same back
  constant C_INDEX_REVS      : positive       := 3;                  -- At least 3 revolutions per direction
  constant C_INDEX_EXTRA     : positive       := C_EDGES_PER_CYCLE;
  constant C_INDEX_CPRS      : integer_vector := (1, 3, 24);
  constant C_INDEX_POSITIONS : integer_vector := (0, 5, -3);
  constant C_INDEX_STATES    : t_state_array  := ("00", "10");
  constant C_WIDE_INDEX      : positive       := 2;                  -- Hand-checked case: Z active while B is low
  -- Hand-checked case (zero state 00, index state 00, width 2): Z at positions 0, 1, 2, -1 (hand values)
  constant C_WIDE_POSITIONS  : integer_vector := (0, 1, 2, -1);
  constant C_WIDE_Z          : std_logic_vector(0 to 3) := "1100";
  -- Index state 00, width 1: Z at positions 0 to 3 with zero state 00 and with zero state 11 (hand values)
  constant C_Z_ZERO_00       : std_logic_vector(0 to 3) := "1000";
  constant C_Z_ZERO_11       : std_logic_vector(0 to 3) := "0010";
  -- invalid_index_configuration
  constant C_BAD_WIDTHS      : integer_vector := (0, C_EDGES_PER_CYCLE + 1);
  constant C_BAD_INDEX_STATE : std_logic_vector(1 downto 0) := "0X";
  constant C_AB_00           : std_logic_vector(1 downto 0) := "00";
  constant C_AB_11           : std_logic_vector(1 downto 0) := "11";

  -- bounce, bounce_placement, bounce_cut_off_and_invalid_window. Edges C_BOUNCE_TPE apart; C_BOUNCE_WINDOW ends before the next edge.
  constant C_BOUNCE_TPE     : time     := 10 us;
  constant C_BOUNCE_EDGES   : positive := 20;
  constant C_BOUNCE_PULSES  : positive := 2;                    -- 4 extra toggles
  constant C_BOUNCE_WINDOW  : time     := 4 us;
  constant C_EVEN_PULSES    : positive := 3;                    -- 6 toggles, spacing C_EVEN_WINDOW / 7
  constant C_EVEN_WINDOW    : time     := 7 us;
  constant C_EVEN_EDGES     : positive := 4;
  constant C_CUT_WINDOW     : time     := 2 * C_BOUNCE_TPE;     -- Settled again at the next edge
  constant C_CUT_WINDOW_ODD : time     := 3 * C_BOUNCE_TPE;     -- One toggle before the next edge: settled one delta before it
  constant C_CUT_WINDOWS    : time_vector    := (C_CUT_WINDOW, C_CUT_WINDOW_ODD);
  constant C_CUT_EDGES      : integer_vector := (6, 4);         -- Two commands
  constant C_BAD_WINDOWS    : time_vector    := (0 ns, -1 ns);
  constant C_OTHER_SEED     : positive := 12345;
  -- bounce_with_jitter: C_BOUNCE_JITTER keeps every bounce before the earliest next edge
  -- (C_BOUNCE_WINDOW < C_BOUNCE_TPE - 2 * amplitude); C_CUT_JITTER with C_JITTER_CUT_WINDOW lets edges pulled early by
  -- jitter cut the bounce off, although the window fits at ideal timing.
  constant C_BOUNCE_JITTER     : real     := 20.0;              -- Electrical degrees
  constant C_CUT_JITTER        : real     := 40.0;
  constant C_JITTER_CUT_WINDOW : time     := 6 us;
  constant C_JITTER_CUT_EDGES  : positive := 100;               -- Per command, so that jitter cuts off at least one bounce
  constant C_JITTER_CUT_CMDS   : positive := 2;

  -- jitter, invalid_jitter
  constant C_JITTER        : real           := 40.0;            -- Electrical degrees
  constant C_JITTER_TPE    : time           := 1 us;
  constant C_JITTER_EDGES  : positive       := 10_000;
  constant C_JITTER_RPMS   : integer_vector := (60, 600);       -- Scaling with time_per_edge
  constant C_SCALING_EDGES : positive       := 1000;
  constant C_REPRO_EDGES   : positive       := 100;
  constant C_JITTER_LIMIT  : real           := C_DEG_ELECTRICAL_PER_EDGE / 2.0;                -- 45 deg
  constant C_B_OFFSET      : real           := 30.0;            -- Narrowest state 60 deg
  constant C_JITTER_LIMIT_B : real          := (C_DEG_ELECTRICAL_PER_EDGE - C_B_OFFSET) / 2.0; -- 30 deg
  constant C_JITTER_BELOW_B : real          := C_JITTER_LIMIT_B - 1.0;                       -- 29 deg: accepted
  constant C_BAD_JITTERS    : real_vector   := (C_JITTER_LIMIT, -1.0, real'high);

  signal enc_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);
  signal log_id : positive            := C_ID; -- Log that p_logger writes to

  -- Debug only (waveform): shaft position and angle after each init and move, from rotary_encoder_get_status()
  signal dbg_position     : integer := 0;
  signal dbg_angle        : real    := 0.0;
  -- Debug only (waveform): Z active before index_inverted, after each init and move, from rotary_encoder_get_status()
  signal dbg_index_active : boolean := false;
  -- Debug only (waveform): the configuration passed to the last BFM call, set when the call starts
  signal dbg_config       : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
  -- Debug only (waveform): the current test step, i.e. the last header written with log_step()
  signal dbg_step         : string(1 to C_DBG_STEP_LENGTH) := dbg_text("");

begin

  -- Event logger: every change on A, B or Z. The checker is armed by p_main.
  p_logger : process is
  begin
    wait on enc_if.a, enc_if.b, enc_if.z;
    shared_th_event_log.add(log_id, enc_if, enc_if.a'event, enc_if.b'event, enc_if.z'event);
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
    variable v_run_start  : time_vector(0 to 2);
    variable v_match      : boolean;
    variable v_activations : natural;
    variable v_expected   : time_vector(1 to C_JITTER_EDGES);
    variable v_edge_t     : time;

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

    -- Logs a test-step header and shows it in the waveform as dbg_step
    procedure log_step(
      constant msg : in string) is
    begin
      log(ID_LOG_HDR, msg, C_SCOPE);
      dbg_step <= dbg_text(msg);
      wait for 0 ns;
    end procedure;

    -- Updates the debug signals from the BFM state (after an init or a move)
    procedure update_debug is
      variable v_debug : t_rotary_encoder_status;
    begin
      v_debug          := rotary_encoder_get_status(v_state);
      dbg_position     <= v_debug.position;
      dbg_angle        <= v_debug.angle;
      dbg_index_active <= v_debug.index_active;
    end procedure;

    -- Shows config in the waveform as dbg_config; called right before each BFM call that takes it
    procedure show_config(
      constant config : in t_rotary_encoder_bfm_config) is
    begin
      dbg_config <= config;
    end procedure;

    -- Initializes the encoder with config, lets the logger record the init, then arms and clears the checker. Waits
    -- C_IDLE_TIME first, so that dbg_position/dbg_angle hold the previous end state visibly.
    procedure init_encoder(
      constant config : in t_rotary_encoder_bfm_config) is
    begin
      wait for C_IDLE_TIME;
      v_config := config;
      show_config(v_config);
      rotary_encoder_init(v_state, "init", enc_if, config => v_config);
      update_debug;
      wait for 0 ns;
      wait for 0 ns;
      shared_th_event_log.arm(log_id, enc_if);
      shared_th_event_log.clear(log_id);
    end procedure;

    -- Selects the log that p_logger writes to (and init_encoder arms and clears)
    procedure select_log(
      constant id : in positive) is
    begin
      log_id <= id;
      wait for 0 ns;
    end procedure;

    -- Default configuration with an index configuration
    function index_config(
      constant zero_state  : in std_logic_vector(1 downto 0);
      constant index_state : in std_logic_vector(1 downto 0);
      constant index_width : in positive) return t_rotary_encoder_bfm_config is
      variable v_result : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    begin
      v_result.zero_state  := zero_state;
      v_result.index_state := index_state;
      v_result.index_width := index_width;
      return v_result;
    end function;

    -- Default configuration with bounce
    function bounce_config(
      constant placement : in t_rotary_encoder_bounce_placement;
      constant pulses    : in natural;
      constant window    : in time) return t_rotary_encoder_bfm_config is
      variable v_result : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    begin
      v_result.bounce_enabled   := true;
      v_result.bounce_placement := placement;
      v_result.bounce_pulses    := pulses;
      v_result.bounce_window    := window;
      return v_result;
    end function;

    -- Z now equals the index model at position (tb_index_active) for v_config
    procedure check_z_model(
      constant position : in integer;
      constant msg      : in string) is
      variable v_exp : std_logic := '0';
    begin
      if v_config.index_enabled and tb_index_active(position, v_config.zero_state, v_config.index_state, v_config.index_width,
                                                    v_config.index_position, v_config.cycles_per_rev) then
        v_exp := '1';
      end if;
      if v_config.index_inverted then
        v_exp := not v_exp;
      end if;
      check_value(enc_if.z, v_exp, MATCH_EXACT, ERROR, "Z at position " & to_string(position) & ": " & msg, C_SCOPE,
                  ID_SEQUENCER_SUB);
    end procedure;

    procedure edges(
      constant direction     : in t_rotary_encoder_direction;
      constant num_edges     : in natural;
      constant time_per_edge : in time) is
    begin
      show_config(v_config);
      rotary_encoder_move_edges(direction, num_edges, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure edges(
      constant direction : in t_rotary_encoder_direction;
      constant num_edges : in natural;
      constant rpm       : in real) is
    begin
      show_config(v_config);
      rotary_encoder_move_edges(direction, num_edges, rpm, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure angle(
      constant direction     : in t_rotary_encoder_direction;
      constant degrees       : in real;
      constant time_per_edge : in time) is
    begin
      show_config(v_config);
      rotary_encoder_move_angle(direction, degrees, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure angle(
      constant direction : in t_rotary_encoder_direction;
      constant degrees   : in real;
      constant rpm       : in real) is
    begin
      show_config(v_config);
      rotary_encoder_move_angle(direction, degrees, rpm, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure move_to_state(
      constant direction     : in t_rotary_encoder_direction;
      constant target        : in std_logic_vector(1 downto 0);
      constant occurrence    : in natural;
      constant time_per_edge : in time) is
    begin
      show_config(v_config);
      rotary_encoder_move_to_state(direction, target, occurrence, time_per_edge, v_state, "move", enc_if, config => v_config);
      update_debug;
    end procedure;

    -- Index stimulus: C_INDEX_REVS revolutions plus C_INDEX_EXTRA edges in direction, then back to the start
    procedure index_stimulus(
      constant direction : in t_rotary_encoder_direction) is
      constant C_EDGES : positive := C_INDEX_REVS * C_EDGES_PER_CYCLE * v_config.cycles_per_rev + C_INDEX_EXTRA;
    begin
      if direction = FORWARD then
        edges(FORWARD, C_EDGES, C_TPE);
        edges(REVERSE, C_EDGES, C_TPE);
      else
        edges(REVERSE, C_EDGES, C_TPE);
        edges(FORWARD, C_EDGES, C_TPE);
      end if;
    end procedure;

    -- A move with config whose call must be accepted: no new TB_ERROR, the checker sees num_edges edges forward
    procedure check_accepted(
      constant config : in t_rotary_encoder_bfm_config;
      constant msg    : in string) is
    begin
      v_alerts := get_alert_counter(TB_ERROR);
      shared_th_event_log.clear(C_ID);
      show_config(config);
      rotary_encoder_move_edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE, v_state, msg, enc_if, config => config);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 0, ERROR, "no TB_ERROR: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE, msg);
    end procedure;

    -- Edge move (C_TPE) from the current position to position
    procedure go_to_position(
      constant position : in integer) is
      constant C_DIFF : integer := position - rotary_encoder_get_status(v_state).position;
    begin
      if C_DIFF > 0 then
        edges(FORWARD, C_DIFF, C_TPE);
      elsif C_DIFF < 0 then
        edges(REVERSE, -C_DIFF, C_TPE);
      end if;
    end procedure;

    -- Records the time and the event count before the call, for check_zero_time_no_event. The two deltas let the logger
    -- record the last edge of a preceding move first (no simulation time passes).
    procedure center is
    begin
      wait for 0 ns;
      wait for 0 ns;
      v_t_start     := now;
      v_count_start := shared_th_event_log.count(C_ID);
      show_config(v_config);
      rotary_encoder_center_state(v_state, "centre", config => v_config);
      update_debug;
    end procedure;

    -- Power-up with config: AB and Z at the first delta, the status, and no event afterwards
    procedure check_power_up(
      constant config : in t_rotary_encoder_bfm_config;
      constant ab     : in std_logic_vector(1 downto 0);
      constant z      : in std_logic;
      constant msg    : in string) is
    begin
      v_config := config;
      show_config(v_config);
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

    -- The first C_EDGES_PER_CYCLE logged events pass the forward sequence from zero_state and end in it
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
    -- ends on a boundary emits its last edge at the time of the call.
    procedure check_zero_time_no_event(
      constant msg : in string) is
    begin
      check_value(now, v_t_start, ERROR, "zero time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(C_ID), v_count_start, ERROR, "no event: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- Rejected call: exactly one new TB_ERROR, no time consumed, no event
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

    -- An edge move with config is rejected: one TB_ERROR, no time, no event
    procedure reject_move(
      constant config : in t_rotary_encoder_bfm_config;
      constant msg    : in string) is
    begin
      begin_reject(msg);
      show_config(config);
      rotary_encoder_move_edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE, v_state, msg, enc_if, config => config);
      end_reject(msg);
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

    -- testbench_self_test: drives the interface directly (testbench self-test, no BFM procedure involved)
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
    if GC_TESTCASE = "testbench_self_test" then
      -- Testbench self-test: decoder checker on hand-driven sequences, ideal_edge_time() against hand values
      log_step("Gray index");
      check_value(gray_index('0', '0'), 0, ERROR, "gray_index 00", C_SCOPE);
      check_value(gray_index('1', '0'), 1, ERROR, "gray_index 10", C_SCOPE);
      check_value(gray_index('1', '1'), 2, ERROR, "gray_index 11", C_SCOPE);
      check_value(gray_index('0', '1'), 3, ERROR, "gray_index 01", C_SCOPE);
      check_value(gray_index('X', '1'), -1, ERROR, "gray_index X1", C_SCOPE);

      log_step("Checker on forward, reverse, illegal and invalid-level sequences");
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

      log_step("Zero-length state (two events in different deltas at the same time)");
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

      log_step("Check_no_event");
      v_start := now;
      wait for C_QUIET_TIME;
      check_no_event(shared_th_event_log, C_ID, v_start, now, "quiet interval");
      drive('0', '1', '0');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "check_no_event must detect the event");
      check_no_event(shared_th_event_log, C_ID, v_start, now, "event expected to be detected");

      -- Hand-computed reference values (exact fractions at 20 cycles/rev), independent of the default configuration
      log_step("Ideal_edge_time against exact values (floor to the resolution)");
      check_edge_time(0 ns, 1, 60, 20, 6250 us, 6250 us);
      check_edge_time(0 ns, 2, 60, 20, 18750 us, 18750 us);
      check_edge_time(0 ns, 1, 7, 20, 53 ms + 571 us + 428 ns + 571 ps, 53 ms + 571 us + 428 ns + 571 ps + 428 fs);
      check_edge_time(0 ns, 1000, 7, 20, 107 sec + 89 ms + 285 us + 714 ns + 285 ps,
                      107 sec + 89 ms + 285 us + 714 ns + 285 ps + 714 fs);
      check_edge_time(0 ns, 3, 6000, 20, 312500 ns, 312500 ns);
      check_edge_time(0 ns, 7, 6000, 1024, 15 us + 869 ns + 140 ps, 15 us + 869 ns + 140 ps + 625 fs);
      check_edge_time(1 us, 1, 60, 20, 6251 us, 6251 us);

    --============================================================================================================================
    elsif GC_TESTCASE = "power_up_state" then
      -- Power-up state per start angle and per zero state, no A/B event before the first move;
      -- invalid and changed zero state
      log_step("Start-angle matrix");
      for i in C_START_CASES'range loop
        check_power_up(config_with(C_START_CASES(i).start_angle), C_START_CASES(i).ab, C_START_CASES(i).z,
                       "start angle " & to_string(C_START_CASES(i).start_angle, 1));
        check_status(C_START_CASES(i).position, C_START_CASES(i).start_angle, "power-up " & to_string(i));
      end loop;

      log_step("The four zero states, each followed by one forward cycle");
      for i in C_STATES'range loop
        v_bad_config            := C_DEFAULT;
        v_bad_config.zero_state := C_STATES(i);
        check_power_up(v_bad_config, C_STATES(i), C_Z_AT_ZERO(i), "zero state " & to_string(C_STATES(i)));
        check_status(0, 0.0, "zero state " & to_string(C_STATES(i)));
        edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE);
        check_forward_cycle(C_STATES(i), "zero state " & to_string(C_STATES(i)));
        check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE, "forward cycle from zero state " & to_string(C_STATES(i)));
      end loop;

      log_step("Invalid zero state at init");
      init_encoder(C_DEFAULT);
      v_bad_config            := C_DEFAULT;
      v_bad_config.zero_state := C_BAD_ZERO_STATE;
      begin_reject("init with zero state " & to_string(C_BAD_ZERO_STATE));
      show_config(v_bad_config);
      rotary_encoder_init(v_state, "invalid zero state", enc_if, config => v_bad_config);
      end_reject("init with zero state " & to_string(C_BAD_ZERO_STATE));

      log_step("Invalid and changed zero state after init");
      for i in 0 to 1 loop
        if i = 0 then
          v_bad_config.zero_state := C_BAD_ZERO_STATE;
        else
          v_bad_config.zero_state := C_OTHER_ZERO_STATE;
        end if;
        begin_reject("edge move with zero state " & to_string(v_bad_config.zero_state));
        show_config(v_bad_config);
        rotary_encoder_move_edges(FORWARD, 1, C_TPE, v_state, "zero state changed", enc_if, config => v_bad_config);
        end_reject("edge move with zero state " & to_string(v_bad_config.zero_state));
        begin_reject("centre state with zero state " & to_string(v_bad_config.zero_state));
        show_config(v_bad_config);
        rotary_encoder_center_state(v_state, "zero state changed", config => v_bad_config);
        end_reject("centre state with zero state " & to_string(v_bad_config.zero_state));
      end loop;
      check_status(0, 0.0, "after the rejected calls");
      edges(FORWARD, 1, C_TPE);
      check_checker(shared_th_event_log, C_ID, 1, "the kept zero state still works");

    --============================================================================================================================
    elsif GC_TESTCASE = "move_edges_forward_and_reverse" then
      -- N edges forward/reverse from all four states
      log_step("Forward and reverse edge moves from all four states");
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
    elsif GC_TESTCASE = "edge_timing" then
      -- Edge timing in both forms, back to back, speed curves
      log_step("Time form, 10 edges per speed");
      for i in C_TIMING_TPE'range loop
        init_encoder(config_with(0.0));
        v_t_start := now;
        edges(FORWARD, 10, C_TIMING_TPE(i));
        check_duration(10 * C_TIMING_TPE(i), 0 ns, "10 edges at " & to_string(C_TIMING_TPE(i), ns));
        check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 10, C_TIMING_TPE(i), "10 edges at " & to_string(C_TIMING_TPE(i), ns));
        check_checker(shared_th_event_log, C_ID, 10, "timing");
      end loop;

      log_step("Back to back with direction changes: +3 -2 +2");
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, C_TPE);
      edges(REVERSE, 2, C_TPE);
      edges(FORWARD, 2, C_TPE);
      check_duration(7 * C_TPE, 0 ns, "3 + 2 + 2 edges");
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 7, C_TPE, "back to back");
      check_checker(shared_th_event_log, C_ID, 3, "back to back");

      log_step("Rpm form, " & to_string(C_LONG_RUN) & " edges per speed");
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

      log_step("Speed curve, time form: 3 edges per speed");
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, C_CURVE_TPE(0));
      edges(FORWARD, 3, C_CURVE_TPE(1));
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 3, C_CURVE_TPE(0), "first speed");
      check_edge_times(shared_th_event_log, C_ID, 3, v_t_start + 3 * C_CURVE_TPE(0), 3, C_CURVE_TPE(1), "second speed");
      check_value(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                  (C_CURVE_TPE(0) + C_CURVE_TPE(1)) / 2, ERROR, "interval at the speed change = mean of the two time_per_edge",
                  C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Speed curve, rpm form: 3 edges per speed");
      init_encoder(config_with(0.0));
      edges(FORWARD, 3, real(C_CURVE_RPM(0)));
      edges(FORWARD, 3, real(C_CURVE_RPM(1)));
      v_time_out := (ideal_move_time(0 ns, 1, C_CURVE_RPM(0), C_CPR) + ideal_move_time(0 ns, 1, C_CURVE_RPM(1), C_CPR)) / 2;
      check_value_in_range(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                           v_time_out - 2 * C_RESOLUTION, v_time_out + 2 * C_RESOLUTION, ERROR,
                           "interval at the speed change = mean of the two time_per_edge", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 6, "speed curves");

    --============================================================================================================================
    elsif GC_TESTCASE = "direction_reversal" then
      -- Reversal from each state, continuity over a mixed sequence
      log_step("+1/-1 edge, 10 times from each state");
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

      log_step("Mixed sequence +5 -3 +7 -10");
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
    elsif GC_TESTCASE = "zero_edge_move" then
      -- 0-edge move
      log_step("Moves of 0 edges and 0 deg");
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
    elsif GC_TESTCASE = "invalid_speed" then
      -- Invalid speeds
      log_step("Invalid speeds");
      init_encoder(C_DEFAULT);
      begin_reject("time_per_edge 0 ns");
      edges(FORWARD, 4, 0 ns);
      end_reject("time_per_edge 0 ns");
      begin_reject("time_per_edge -1 ns");
      edges(FORWARD, 4, -1 ns);
      end_reject("time_per_edge -1 ns");
      begin_reject("0 rpm");
      show_config(v_config);
      rotary_encoder_move_edges(FORWARD, 4, 0.0, v_state, "0 rpm", enc_if, config => v_config);
      end_reject("0 rpm");
      begin_reject("-60 rpm");
      show_config(v_config);
      rotary_encoder_move_edges(FORWARD, 4, -60.0, v_state, "-60 rpm", enc_if, config => v_config);
      end_reject("-60 rpm");
      begin_reject("rpm not finite");
      show_config(v_config);
      rotary_encoder_move_edges(FORWARD, 4, real'high, v_state, "real'high rpm", enc_if, config => v_config);
      end_reject("rpm not finite");
      begin_reject("angle move at 0 rpm");
      show_config(v_config);
      rotary_encoder_move_angle(FORWARD, C_ANGLE_10, 0.0, v_state, "0 rpm", enc_if, config => v_config);
      end_reject("angle move at 0 rpm");
      check_status(0, 0.0, "after the rejected calls");

    --============================================================================================================================
    elsif GC_TESTCASE = "index_polarity" then
      -- The same stimulus without and with index_inverted: Z inverted, A and B identical (run 1 in log C_ID, run 2
      -- in log C_ID_CMP, compared entry by entry)
      log_step("Z polarity, the same stimulus without and with index_inverted");
      for run in 0 to 1 loop
        v_bad_config                := C_DEFAULT;
        v_bad_config.index_inverted := (run = 1);
        select_log(C_ID + run);
        init_encoder(v_bad_config);
        check_z_model(0, "power-up, index_inverted " & to_string(v_config.index_inverted));
        v_run_start(run) := now;
        index_stimulus(FORWARD);
        check_checker(shared_th_event_log, C_ID + run, 0, "index_inverted " & to_string(v_config.index_inverted));
        check_z_follows_ab(shared_th_event_log, C_ID + run, 0, v_config.zero_state, v_config.index_state, v_config.index_width,
                           v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations,
                           "index_inverted " & to_string(v_config.index_inverted));
      end loop;
      select_log(C_ID);
      compare_logs(shared_th_event_log, C_ID, v_run_start(0), C_ID_CMP, v_run_start(1), true, v_match);
      check_value(v_match, ERROR, "inverted run: Z inverted, A and B identical, entry by entry", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "index_once_per_revolution" then
      -- Index disabled: Z holds its inactive level ('0', or '1' with index_inverted), no Z event
      log_step("Index disabled");
      for inverted in boolean loop
        v_bad_config                := C_DEFAULT;
        v_bad_config.index_enabled  := false;
        v_bad_config.index_inverted := inverted;
        init_encoder(v_bad_config);
        check_z_model(0, "index disabled, index_inverted " & to_string(inverted));
        index_stimulus(FORWARD);
        check_value(shared_th_event_log.num_z_events(C_ID), 0, ERROR, "no Z event, index_inverted " & to_string(inverted),
                    C_SCOPE, ID_SEQUENCER_SUB);
        check_z_model(0, "index disabled, after the moves");
        check_checker(shared_th_event_log, C_ID, 0, "index disabled");
      end loop;

      -- Once per revolution at the index position, both directions
      log_step("Once per revolution, cycles_per_rev x index_position x direction");
      for c in C_INDEX_CPRS'range loop
        for p in C_INDEX_POSITIONS'range loop
          for d in t_rotary_encoder_direction loop
            v_bad_config                := C_DEFAULT;
            v_bad_config.cycles_per_rev := C_INDEX_CPRS(c);
            v_bad_config.index_position := C_INDEX_POSITIONS(p);
            init_encoder(v_bad_config);
            check_z_model(0, "power-up");
            index_stimulus(d);
            check_z_follows_ab(shared_th_event_log, C_ID, 0, v_config.zero_state, v_config.index_state, v_config.index_width,
                               v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations,
                               "cycles_per_rev " & to_string(C_INDEX_CPRS(c)) & ", index_position " & to_string(C_INDEX_POSITIONS(p)) &
                               ", " & to_string(d));
            check_value(v_activations >= 2 * C_INDEX_REVS, ERROR, "at least " & to_string(C_INDEX_REVS) &
                        " index pulses per direction", C_SCOPE, ID_SEQUENCER_SUB);
            check_checker(shared_th_event_log, C_ID, 0, "index stimulus");
          end loop;
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "index_width_and_state" then
      -- Index widths 1 to 4 x index states x directions, checked against the testbench index model
      log_step("Index width x index state x direction");
      for w in 1 to C_EDGES_PER_CYCLE loop
        for s in C_INDEX_STATES'range loop
          for d in t_rotary_encoder_direction loop
            init_encoder(index_config(C_DEFAULT.zero_state, C_INDEX_STATES(s), w));
            check_z_model(0, "power-up");
            index_stimulus(d);
            check_z_follows_ab(shared_th_event_log, C_ID, 0, v_config.zero_state, v_config.index_state, v_config.index_width,
                               v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations,
                               "width " & to_string(w) & ", index state " & to_string(C_INDEX_STATES(s)) & ", " & to_string(d));
            check_value(v_activations >= 2 * C_INDEX_REVS, ERROR, "index pulses seen", C_SCOPE, ID_SEQUENCER_SUB);
            check_checker(shared_th_event_log, C_ID, 0, "index stimulus");
          end loop;
        end loop;
      end loop;

      log_step("Width 2 at 00, zero state 00: Z active while B is low, at positions 0 and 1");
      init_encoder(index_config(C_AB_00, C_AB_00, C_WIDE_INDEX));
      for i in C_WIDE_POSITIONS'range loop
        go_to_position(C_WIDE_POSITIONS(i));
        check_value(enc_if.z, C_WIDE_Z(i), MATCH_EXACT, ERROR, "Z at position " & to_string(C_WIDE_POSITIONS(i)), C_SCOPE,
                    ID_SEQUENCER_SUB);
        if C_WIDE_Z(i) = '1' then
          check_value(enc_if.b, '0', MATCH_EXACT, ERROR, "B low while Z is active", C_SCOPE, ID_SEQUENCER_SUB);
        end if;
      end loop;

      -- The index is placed relative to the zero state (index state 00, width 1)
      log_step("Index state 00 with zero state 00 (Z at 0 deg) and 11 (Z at 9 deg, position 2)");
      for z in 0 to 1 loop
        if z = 0 then
          init_encoder(index_config(C_AB_00, C_AB_00, 1));
        else
          init_encoder(index_config(C_AB_11, C_AB_00, 1));
        end if;
        for p in 0 to C_EDGES_PER_CYCLE - 1 loop
          go_to_position(p);
          if z = 0 then
            check_value(enc_if.z, C_Z_ZERO_00(p), MATCH_EXACT, ERROR, "zero state 00, Z at position " & to_string(p), C_SCOPE,
                        ID_SEQUENCER_SUB);
          else
            check_value(enc_if.z, C_Z_ZERO_11(p), MATCH_EXACT, ERROR, "zero state 11, Z at position " & to_string(p), C_SCOPE,
                        ID_SEQUENCER_SUB);
          end if;
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "invalid_index_configuration" then
      -- Invalid index configuration with index enabled: one TB_ERROR per call, no edge
      log_step("Invalid index configuration");
      init_encoder(C_DEFAULT);
      v_bad_config                := C_DEFAULT;
      v_bad_config.cycles_per_rev := 0;
      reject_move(v_bad_config, "cycles_per_rev 0");
      for i in C_BAD_WIDTHS'range loop
        v_bad_config             := C_DEFAULT;
        v_bad_config.index_width := C_BAD_WIDTHS(i);
        reject_move(v_bad_config, "index_width " & to_string(C_BAD_WIDTHS(i)));
      end loop;
      v_bad_config             := C_DEFAULT;
      v_bad_config.index_state := C_BAD_INDEX_STATE;
      reject_move(v_bad_config, "index_state " & to_string(C_BAD_INDEX_STATE));
      begin_reject("init with index_state " & to_string(C_BAD_INDEX_STATE));
      show_config(v_bad_config);
      rotary_encoder_init(v_state, "invalid index state", enc_if, config => v_bad_config);
      end_reject("init with index_state " & to_string(C_BAD_INDEX_STATE));
      check_status(0, 0.0, "after the rejected calls");

      log_step("With index disabled, width and index state are not checked");
      v_bad_config               := C_DEFAULT;
      v_bad_config.index_enabled := false;
      v_bad_config.index_width   := C_BAD_WIDTHS(0);
      v_bad_config.index_state   := C_BAD_INDEX_STATE;
      check_accepted(v_bad_config, "index disabled, width " & to_string(C_BAD_WIDTHS(0)) & ", index state " &
                     to_string(C_BAD_INDEX_STATE));

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce" then
      -- Bounce disabled: one event per edge
      log_step("Bounce disabled");
      init_encoder(C_DEFAULT);
      edges(FORWARD, C_BOUNCE_EDGES, C_BOUNCE_TPE);
      v_num := 0;
      for i in 0 to shared_th_event_log.count(C_ID) - 1 loop
        if shared_th_event_log.get(C_ID, i).a_changed or shared_th_event_log.get(C_ID, i).b_changed then
          v_num := v_num + 1;
        end if;
      end loop;
      check_value(v_num, C_BOUNCE_EDGES, ERROR, "A/B events = edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_BOUNCE_EDGES, "bounce disabled");

      -- Random placement over one revolution that crosses the index once
      log_step("Bounce enabled, random placement, one revolution across the index");
      v_bad_config             := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
      v_bad_config.start_angle := real(C_EDGES_PER_REV / 2) * C_DEG_PER_EDGE; -- Half a revolution away from the index
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_EDGES_PER_REV, C_BOUNCE_TPE);
      check_bounce(shared_th_event_log, C_ID, v_t_start, C_EDGES_PER_REV, C_BOUNCE_TPE, 2 * C_BOUNCE_PULSES, C_BOUNCE_WINDOW,
                   "random placement");
      check_value(shared_th_event_log.num_z_events(C_ID), 2, ERROR, "Z does not bounce: 2 events for one index pulse",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "bounce enabled");

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce_placement" then
      -- Even placement: toggle i at i * window / (toggles + 1)
      log_step("Even placement");
      init_encoder(bounce_config(BOUNCE_EVEN, C_EVEN_PULSES, C_EVEN_WINDOW));
      v_t_start := now;
      edges(FORWARD, C_EVEN_EDGES, C_BOUNCE_TPE);
      wait for C_EVEN_WINDOW; -- The window outlasts the move (half an edge interval after the last edge)
      check_bounce(shared_th_event_log, C_ID, v_t_start, C_EVEN_EDGES, C_BOUNCE_TPE, 2 * C_EVEN_PULSES, C_EVEN_WINDOW,
                   "even placement");
      for k in 1 to C_EVEN_EDGES loop
        v_edge_t := v_t_start + (2 * k - 1) * C_BOUNCE_TPE / 2;
        for i in 1 to 2 * C_EVEN_PULSES loop
          check_event_time((k - 1) * (1 + 2 * C_EVEN_PULSES) + i, v_edge_t + i * C_EVEN_WINDOW / (2 * C_EVEN_PULSES + 1),
                           C_RESOLUTION, "edge " & to_string(k) & ", even toggle " & to_string(i));
        end loop;
      end loop;

      -- Random placement, the same seed twice (logs C_ID and C_ID_CMP), then another seed (log C_ID_CMP)
      log_step("Random placement: same seed, same times; another seed, other times");
      for run in 0 to 2 loop
        v_bad_config := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
        if run = 2 then
          v_bad_config.rand_seed1 := C_OTHER_SEED;
        end if;
        if run = 0 then
          select_log(C_ID);
        else
          select_log(C_ID_CMP);
        end if;
        init_encoder(v_bad_config);
        v_run_start(run) := now;
        edges(FORWARD, C_REPRO_EDGES, C_BOUNCE_TPE);
        check_bounce(shared_th_event_log, log_id, v_run_start(run), C_REPRO_EDGES, C_BOUNCE_TPE, 2 * C_BOUNCE_PULSES,
                     C_BOUNCE_WINDOW, "random placement, run " & to_string(run + 1));
        if run > 0 then
          compare_logs(shared_th_event_log, C_ID, v_run_start(0), C_ID_CMP, v_run_start(run), false, v_match);
          check_value(v_match, run = 1, ERROR, "toggle times equal to run 1: " & to_string(run = 1), C_SCOPE, ID_SEQUENCER_SUB);
        end if;
      end loop;
      select_log(C_ID);

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce_cut_off_and_invalid_window" then
      -- Bounce_window <= 0 ns with bounce enabled
      log_step("Invalid bounce window");
      init_encoder(C_DEFAULT);
      for i in C_BAD_WINDOWS'range loop
        v_bad_config := bounce_config(BOUNCE_EVEN, C_BOUNCE_PULSES, C_BAD_WINDOWS(i));
        reject_move(v_bad_config, "bounce_window " & to_string(C_BAD_WINDOWS(i), ns));
      end loop;
      v_bad_config.bounce_enabled := false;
      check_accepted(v_bad_config, "bounce disabled, bounce_window " & to_string(v_bad_config.bounce_window, ns));

      -- The bounce window outlasts the next edge. C_CUT_WINDOW: the channel is settled again at the next edge;
      -- C_CUT_WINDOW_ODD: it is at its bounced level and settles one delta before the edge. One alert per command.
      for w in C_CUT_WINDOWS'range loop
        log_step("Cut-off, bounce_window " & to_string(C_CUT_WINDOWS(w), ns) & ", two commands");
        init_encoder(bounce_config(BOUNCE_EVEN, C_BOUNCE_PULSES, C_CUT_WINDOWS(w)));
        v_t_start := now;
        v_num     := 0;
        for cmd in C_CUT_EDGES'range loop
          increment_expected_alerts(TB_WARNING, 1, "bounce cut-off, once per command");
          v_alerts := get_alert_counter(TB_WARNING);
          edges(FORWARD, C_CUT_EDGES(cmd), C_BOUNCE_TPE);
          check_value(get_alert_counter(TB_WARNING) - v_alerts, 1, ERROR, "one cut-off alert in command " & to_string(cmd + 1),
                      C_SCOPE, ID_SEQUENCER_SUB);
          v_num := v_num + C_CUT_EDGES(cmd);
        end loop;
        wait for C_CUT_WINDOWS(w); -- The bounce of the last edge ends
        check_settled_before_edges(shared_th_event_log, C_ID, v_t_start, v_num, C_BOUNCE_TPE, v_config.zero_state, 0, 1,
                                   "bounce_window " & to_string(C_CUT_WINDOWS(w), ns));
        check_checker(shared_th_event_log, C_ID, v_num, "cut-off, bounce_window " & to_string(C_CUT_WINDOWS(w), ns));
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce_with_jitter" then
      -- Bounce follows the jittered edge: one revolution across the index, random placement
      log_step("Bounce with jitter " & to_string(C_BOUNCE_JITTER, 1) & " deg, one revolution across the index");
      v_bad_config             := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
      v_bad_config.jitter      := C_BOUNCE_JITTER;
      v_bad_config.start_angle := real(C_EDGES_PER_REV / 2) * C_DEG_PER_EDGE; -- Half a revolution away from the index
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_EDGES_PER_REV, C_BOUNCE_TPE);
      check_duration(C_EDGES_PER_REV * C_BOUNCE_TPE, 0 ns, "completion unchanged by bounce and jitter");
      check_bounce(shared_th_event_log, C_ID, v_t_start, C_EDGES_PER_REV, C_BOUNCE_TPE, 2 * C_BOUNCE_PULSES, C_BOUNCE_WINDOW,
                   "bounce with jitter", C_SCOPE, C_BOUNCE_TPE * (C_BOUNCE_JITTER / C_DEG_ELECTRICAL_PER_EDGE));
      check_value(shared_th_event_log.num_z_events(C_ID), 2, ERROR, "Z does not bounce: 2 events for one index pulse",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "bounce with jitter");

      -- The same seeds and configuration give the same events (logs C_ID and C_ID_CMP)
      log_step("Bounce with jitter reproducible with the same seed");
      for run in 0 to 1 loop
        select_log(C_ID + run);
        init_encoder(v_bad_config);
        v_run_start(run) := now;
        edges(FORWARD, C_REPRO_EDGES, C_BOUNCE_TPE);
      end loop;
      compare_logs(shared_th_event_log, C_ID, v_run_start(0), C_ID_CMP, v_run_start(1), false, v_match);
      check_value(v_match, ERROR, "same seed: same edge and toggle times", C_SCOPE, ID_SEQUENCER_SUB);

      -- Bounce and jitter share one random stream: with bounce enabled, the jitter of the same seed differs.
      -- Log C_ID holds the bounced run (edge k at entry (k - 1) * (1 + toggles)); log C_ID_CMP gets the run without bounce.
      log_step("Enabling bounce changes the jitter of the same seed (one random stream)");
      v_bad_config.bounce_enabled := false;
      select_log(C_ID_CMP);
      init_encoder(v_bad_config);
      v_run_start(1) := now;
      edges(FORWARD, C_REPRO_EDGES, C_BOUNCE_TPE);
      select_log(C_ID);
      v_num := 0;
      for k in 0 to C_REPRO_EDGES - 1 loop
        if shared_th_event_log.get(C_ID, k * (1 + 2 * C_BOUNCE_PULSES)).time_stamp - v_run_start(0) /=
           shared_th_event_log.get(C_ID_CMP, k).time_stamp - v_run_start(1) then
          v_num := v_num + 1;
        end if;
      end loop;
      check_value(v_num > 0, ERROR, "edge times differ with and without bounce: " & to_string(v_num) & " of " &
                  to_string(C_REPRO_EDGES), C_SCOPE, ID_SEQUENCER_SUB);

      -- Edges pulled early by jitter cut off a bounce whose window fits at ideal timing. One alert per
      -- command, every edge still from a settled state, so the decoder sees only legal forward edges.
      log_step("Jitter " & to_string(C_CUT_JITTER, 1) & " deg cuts off bounce_window " &
               to_string(C_JITTER_CUT_WINDOW, ns) & ", " & to_string(C_JITTER_CUT_CMDS) & " commands");
      v_bad_config        := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_JITTER_CUT_WINDOW);
      v_bad_config.jitter := C_CUT_JITTER;
      init_encoder(v_bad_config);
      for cmd in 1 to C_JITTER_CUT_CMDS loop
        increment_expected_alerts(TB_WARNING, 1, "bounce cut-off by a jittered edge, once per command");
        v_alerts := get_alert_counter(TB_WARNING);
        edges(FORWARD, C_JITTER_CUT_EDGES, C_BOUNCE_TPE);
        check_value(get_alert_counter(TB_WARNING) - v_alerts, 1, ERROR, "one cut-off alert in command " & to_string(cmd),
                    C_SCOPE, ID_SEQUENCER_SUB);
      end loop;
      wait for C_JITTER_CUT_WINDOW; -- The bounce of the last edge ends
      check_value(std_logic_vector'(enc_if.a & enc_if.b), tb_state(v_config.zero_state, C_JITTER_CUT_CMDS * C_JITTER_CUT_EDGES),
                  MATCH_EXACT, ERROR, "settled at the final state", C_SCOPE, msg_id => ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_JITTER_CUT_CMDS * C_JITTER_CUT_EDGES, "jitter cuts off bounce");

    --============================================================================================================================
    elsif GC_TESTCASE = "jitter" then
      -- Statistics over C_JITTER_EDGES edges, time form
      v_bad_config        := C_DEFAULT;
      v_bad_config.jitter := C_JITTER;
      log_step("Jitter " & to_string(C_JITTER, 1) & " deg, " & to_string(C_JITTER_EDGES) & " edges at " &
               to_string(C_JITTER_TPE, ns));
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_JITTER_EDGES, C_JITTER_TPE);
      check_duration(C_JITTER_EDGES * C_JITTER_TPE, 0 ns, "completion unchanged by jitter");
      for k in 1 to C_JITTER_EDGES loop
        v_expected(k) := v_t_start + (2 * k - 1) * C_JITTER_TPE / 2;
      end loop;
      check_jitter_stats(shared_th_event_log, C_ID, 0, v_expected, C_JITTER_TPE * (C_JITTER / C_DEG_ELECTRICAL_PER_EDGE),
                         C_RESOLUTION, "time form");
      check_value(shared_th_event_log.count(C_ID), C_JITTER_EDGES, ERROR, "edge count exact", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_JITTER_EDGES, "jitter, time form");

      -- The same jitter in electrical degrees scales with time_per_edge
      for r in C_JITTER_RPMS'range loop
        log_step("Jitter at " & to_string(C_JITTER_RPMS(r)) & " rpm");
        init_encoder(v_bad_config);
        v_t_start := now;
        edges(FORWARD, C_SCALING_EDGES, real(C_JITTER_RPMS(r)));
        for k in 1 to C_SCALING_EDGES loop
          v_expected(k) := ideal_edge_time(v_t_start, k, C_JITTER_RPMS(r), C_CPR);
        end loop;
        check_jitter_stats(shared_th_event_log, C_ID, 0, v_expected(1 to C_SCALING_EDGES),
                           ideal_move_time(0 ns, 1, C_JITTER_RPMS(r), C_CPR) * (C_JITTER / C_DEG_ELECTRICAL_PER_EDGE),
                           2 * C_RESOLUTION, to_string(C_JITTER_RPMS(r)) & " rpm");
        check_checker(shared_th_event_log, C_ID, C_SCALING_EDGES, to_string(C_JITTER_RPMS(r)) & " rpm");
      end loop;

      -- The same seed gives the same edge times (logs C_ID and C_ID_CMP)
      log_step("Jitter reproducible with the same seed");
      for run in 0 to 1 loop
        select_log(C_ID + run);
        init_encoder(v_bad_config);
        v_run_start(run) := now;
        edges(FORWARD, C_REPRO_EDGES, C_JITTER_TPE);
      end loop;
      select_log(C_ID);
      compare_logs(shared_th_event_log, C_ID, v_run_start(0), C_ID_CMP, v_run_start(1), false, v_match);
      check_value(v_match, ERROR, "same seed: same edge times", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "invalid_jitter" then
      -- Jitter < 0, not finite, or at least half the narrowest state
      log_step("Invalid jitter");
      init_encoder(C_DEFAULT);
      for i in C_BAD_JITTERS'range loop
        v_bad_config        := C_DEFAULT;
        v_bad_config.jitter := C_BAD_JITTERS(i);
        reject_move(v_bad_config, "jitter " & real'image(C_BAD_JITTERS(i))); -- 'image: to_string(real'high, n) fails on NVC
      end loop;

      -- The jitter limit follows from the configured edge offsets
      log_step("B offset " & to_string(C_B_OFFSET, 1) & " deg: narrowest state " &
               to_string(C_DEG_ELECTRICAL_PER_EDGE - C_B_OFFSET, 1) & " deg");
      v_bad_config               := C_DEFAULT;
      v_bad_config.b_rise_offset := C_B_OFFSET;
      v_bad_config.b_fall_offset := C_B_OFFSET;
      v_bad_config.jitter        := C_JITTER_LIMIT_B;
      reject_move(v_bad_config, "jitter " & to_string(C_JITTER_LIMIT_B, 1) & " with B offset");
      v_bad_config.jitter := C_JITTER_BELOW_B;
      check_accepted(v_bad_config, "jitter " & to_string(C_JITTER_BELOW_B, 1) & " with B offset");

    --============================================================================================================================
    elsif GC_TESTCASE = "move_angle" then
      -- Edges at the boundary crossings, the end exactly at the target, durations in both forms
      log_step("Three 1 deg moves, the edge at half an edge angle");
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

      log_step("" & to_string(C_ANGLE_10, 1) & " deg from 0 deg: 2 edges, ends at the target");
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

      log_step("Durations in the rpm form, also without an edge");
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

      log_step("Duration in the time form without an edge");
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(REVERSE, C_ANGLE_1, C_TPE_ANGLE);
      check_duration(C_TIME_PER_DEG * C_ANGLE_1, C_RESOLUTION, to_string(C_ANGLE_1, 1) & " deg, no edge");
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(0, -C_ANGLE_1, "time-form move without an edge");

    --============================================================================================================================
    elsif GC_TESTCASE = "move_angle_without_drift" then
      -- No drift; mixed edge and angle moves keep the sub-edge fraction. Moves at C_TPE_ANGLE_FAST.
      disable_log_msg(ID_BFM);
      log_step("One revolution in 1 deg moves");
      init_encoder(config_with(0.0));
      for i in 1 to C_DEG_PER_REV loop
        angle(FORWARD, 1.0, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "1 deg moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("One revolution in " & to_string(C_SMALL_STEP, 1) & " deg moves");
      init_encoder(config_with(0.0));
      for i in 1 to integer(real(C_DEG_PER_REV) / C_SMALL_STEP) loop
        angle(FORWARD, C_SMALL_STEP, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "small moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after small moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after small moves", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("One revolution in pairs of (1 edge, 1 edge angle)");
      init_encoder(config_with(0.0));
      for i in 1 to C_EDGES_PER_REV / 2 loop
        edges(FORWARD, 1, C_TPE_ANGLE_FAST);
        angle(FORWARD, C_DEG_PER_EDGE, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "mixed");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after the mixed sequence", C_SCOPE, ID_SEQUENCER_SUB);
      enable_log_msg(ID_BFM);

      log_step("2 deg, 1 edge, 1 deg: edges at 0.5 and 1.5 edge angles");
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
    elsif GC_TESTCASE = "invalid_angle_and_move_to_state" then
      -- Invalid angles; invalid move-to-state parameters
      log_step("Invalid angles");
      init_encoder(C_DEFAULT);
      begin_reject("angle -1.0");
      angle(FORWARD, -C_ANGLE_1, C_TPE);
      end_reject("angle -1.0");
      begin_reject("angle not finite");
      angle(REVERSE, real'high, C_TPE);
      end_reject("angle not finite");
      begin_reject("angle -1.0, rpm form");
      show_config(v_config);
      rotary_encoder_move_angle(FORWARD, -C_ANGLE_1, real(C_ANGLE_RPM), v_state, "-1 deg", enc_if, config => v_config);
      end_reject("angle -1.0, rpm form");
      check_status(0, 0.0, "after the rejected angle moves");

      log_step("Invalid move-to-state parameters");
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
      show_config(v_config);
      rotary_encoder_move_to_state(FORWARD, C_STATES(0), 1, -real(C_ANGLE_RPM), v_state, "-60 rpm", enc_if, config => v_config);
      end_reject("-60 rpm");
      check_status(0, 0.0, "after the rejected move-to-state calls");
      check_value(rotary_encoder_get_status(v_state).ab, C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "status AB unchanged",
                  C_SCOPE, msg_id => ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "speed_conversion" then
      -- Conversion functions. Expected values are hand-calculated.
      log_step("Rpm <-> time_per_edge, rpm <-> deg/s");
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

      log_step("Invalid arguments");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 5, "invalid conversions");
      v_alerts   := get_alert_counter(TB_ERROR);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(60.0, 0);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(0.0, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(0 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(-1 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(1 ms, 0);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 5, ERROR, "one TB_ERROR per invalid call", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "move_to_state" then
      -- Move to state. Expected edges at the boundaries between the start angle and the target centre, each
      -- (distance to the boundary) / edge angle * T after the start; the move completes at the target centre.
      log_step("Move to state, time form " & to_string(C_TO_STATE_TPE, ns));
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
    elsif GC_TESTCASE = "center_state" then
      -- Centre state
      log_step("From " & to_string(C_CENTER_FROM, 1) & " deg");
      init_encoder(config_with(C_CENTER_FROM));
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "centred");
      check_zero_time_no_event("centre state");
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "already on the centre: unchanged");
      check_zero_time_no_event("centre state on the centre");

      log_step("On the boundary at " & to_string(C_BOUNDARY_ANGLE, 2) & " deg: the state moved into");
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

      -- With edge offsets that move the boundaries, centring must still give the ideal centre
      log_step("With all four edge offsets at +-" & to_string(C_EDGE_OFFSET, 1) & " deg");
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

      log_step("From " & to_string(C_OFFSET_ANGLES(0), 1) & " deg, centre, then 1 edge");
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
    log_step("SIMULATION COMPLETED");

    -- Finish the simulation
    std.env.stop;
    wait;                               -- to stop completely
  end process p_main;

end architecture func;
