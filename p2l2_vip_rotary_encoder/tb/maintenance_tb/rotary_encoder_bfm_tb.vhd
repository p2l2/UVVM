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
-- (id 1). GC_TESTCASE selects the test case by name.
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

  constant C_QUIET_TIME         : time     := 1 us;   -- Interval checked for the absence of events
  constant C_IDLE_TIME          : time     := C_TPE;  -- Before each re-init, so the previous end state shows in the waveform
  constant C_REAL_TOL           : real     := 1.0e-9; -- Tolerance of status angles and converted speeds
  constant C_Z_EVENTS_PER_PULSE : positive := 2;      -- One index pulse: Z rises and falls

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

  -- Move and timing test vectors
  constant C_NUM_EDGES    : integer_vector := (1, 2, 3, 4, 5, 1000);
  constant C_TIMING_TPE   : time_vector    := (1 ns, 1 us, 1 ms); -- time form
  constant C_TIMING_RPM   : integer_vector := (7, 6000);          -- rpm form
  constant C_RPM_EDGE_TOL : time           := 2 * C_RESOLUTION;   -- Interval of two rpm-form edges, each rounded once
  constant C_BAD_TPES     : time_vector    := (0 ns, -1 ns);      -- Invalid time_per_edge
  constant C_BAD_RPMS     : real_vector    := (0.0, -60.0, real'high); -- Invalid speeds
  constant C_ANGLE_10     : real           := 10.0;               -- 2 edges, ends at 10 deg
  constant C_ANGLE_1      : real           := 1.0;                -- Crosses no edge
  constant C_ANGLE_RPM    : positive       := 60;                 -- rpm form

  -- move_to_state: time form T = 1 us. Default zero state 11: positions 0 to 3 are 11, 01, 00, 10.
  -- start_position is the state the shaft is in at start_angle, end_position the expected target centre (hand-computed).
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

  -- center_state: start angles of the edge-offset cases
  constant C_OFFSET_ANGLES   : real_vector := (1.0, 3.5);

  -- Run-to-run comparisons (index_polarity, bounce_placement, bounce_with_jitter, jitter): the second run is logged into C_ID_CMP
  constant C_ID_CMP : positive := 2;

  -- index_polarity, index_once_per_revolution, index_width_and_state. Stimulus: C_INDEX_REVS revolutions plus C_INDEX_EXTRA edges forward, then the same back
  constant C_INDEX_REVS      : positive       := 3;                  -- At least 3 revolutions per direction
  constant C_INDEX_EXTRA     : positive       := C_EDGES_PER_CYCLE;
  constant C_INDEX_CPRS      : integer_vector := (1, 3, 24);
  constant C_INDEX_POSITIONS : integer_vector := (0, 5, -3);
  constant C_INDEX_STATES    : t_state_array  := ("00", "10");
  -- Hand-checked case (zero state 00, index state 00, width 2): Z at positions 0, 1, 2, -1 (hand values)
  constant C_WIDE_POSITIONS  : integer_vector := (0, 1, 2, -1);
  constant C_WIDE_Z          : std_logic_vector(0 to 3) := "1100";
  -- Index state 00, width 1: Z at positions 0 to 3 with zero state 00 and with zero state 11 (hand values)
  type t_z_pattern_array is array (natural range <>) of std_logic_vector(0 to 3);
  constant C_PLACEMENT_ZERO_STATES : t_state_array     := ("00", "11");
  constant C_PLACEMENT_Z           : t_z_pattern_array := ("1000", "0010");
  -- invalid_index_configuration
  constant C_BAD_WIDTHS      : integer_vector := (0, C_EDGES_PER_CYCLE + 1);
  constant C_BAD_CPR         : integer        := 0; -- Also an invalid argument of the conversion functions

  -- bounce, bounce_placement, bounce_cut_off_and_invalid_window. Edges C_BOUNCE_TPE apart; C_BOUNCE_WINDOW ends before the next edge.
  constant C_BOUNCE_TPE     : time     := 10 us;
  constant C_BOUNCE_PULSES  : positive := 2;                    -- 4 extra toggles
  constant C_BOUNCE_WINDOW  : time     := 4 us;
  -- Bounce windows that outlast the next edge: with 2 * C_BOUNCE_TPE the channel is settled again at the next edge;
  -- with 3 * C_BOUNCE_TPE it is at its bounced level and settles one delta before the edge
  constant C_CUT_WINDOWS    : time_vector    := (2 * C_BOUNCE_TPE, 3 * C_BOUNCE_TPE);
  constant C_CUT_EDGES      : integer_vector := (6, 4);         -- Two commands
  constant C_BAD_WINDOWS    : time_vector    := (0 ns, -1 ns);

  -- jitter, invalid_jitter
  constant C_JITTER_EDGES  : positive       := 10_000;
  constant C_JITTER_RPMS   : integer_vector := (60, 600);       -- Same jitter in degrees, scaling with time_per_edge
  constant C_REPRO_EDGES   : positive       := 100;
  constant C_JITTER_LIMIT  : real           := C_DEG_ELECTRICAL_PER_EDGE / 2.0;                -- 45 deg
  constant C_B_OFFSET      : real           := 30.0;            -- Narrowest state 60 deg
  constant C_JITTER_LIMIT_B : real          := (C_DEG_ELECTRICAL_PER_EDGE - C_B_OFFSET) / 2.0; -- 30 deg
  constant C_JITTER_BELOW_B : real          := C_JITTER_LIMIT_B - 1.0;                       -- 29 deg: accepted
  constant C_BAD_JITTERS    : real_vector   := (C_JITTER_LIMIT, -1.0, real'high);

  -- set_angle_and_jump_edges: jump distances and what the decoder sees for a forward jump (hand values: N mod 4 = 1 is
  -- one edge forward, 2 an illegal transition, 3 one edge back, 0 nothing; one revolution changes neither A/B nor Z)
  constant C_JUMP_EDGES        : integer_vector := (1, 2, 3, 4, C_EDGES_PER_REV);
  constant C_JUMP_DECODED      : integer_vector := (1, 0, -1, 0, 0);
  constant C_JUMP_ILLEGAL      : integer_vector := (0, 1, 0, 0, 0);
  constant C_JUMP_AB_EVENTS    : integer_vector := (1, 1, 1, 0, 0);
  constant C_SET_ANGLE_FROM    : integer        := 5;     -- Position before the set-angle steps
  constant C_SET_ANGLE_30      : real           := 30.0;  -- Position 7
  constant C_SET_ANGLE_30_POS  : integer        := 7;

  -- glitch, invalid_fault_event
  constant C_GLITCH_WIDTH      : time        := 30 ns;
  constant C_BAD_WIDTHS_GLITCH : time_vector := (0 ns, -1 ns);
  constant C_BAD_ANGLES        : real_vector := (real'high, real'low);

  -- edge_offsets: time form 1 us per edge; offsets in electrical degrees
  constant C_OFFSET_TPE        : time        := 1 us;
  constant C_OFFSET_EDGES      : positive    := 2 * C_EDGES_PER_CYCLE;
  constant C_DUTY_OFFSET       : real        := 20.0;  -- A rise +20 deg, A fall -20 deg: A high 40 deg shorter
  constant C_MAX_OFFSET_OK     : real        := 44.0;  -- Largest offset tested inside the open interval +-45 deg
  constant C_OFFSET_RPMS       : integer_vector := (60, 600);
  constant C_BAD_OFFSETS       : real_vector := (C_DEG_ELECTRICAL_PER_EDGE / 2.0, -C_DEG_ELECTRICAL_PER_EDGE / 2.0, real'high);

  -- stuck_outputs
  constant C_STUCK_REVS        : positive := 3;
  constant C_BAD_STUCK         : std_logic_vector(0 to 2) := "XUH"; -- Invalid stuck levels for a_stuck, b_stuck, z_stuck

  -- bfm_only_flow_and_rotate. Rpm form at 60 rpm (12.5 ms per edge) and 120 rpm (6.25 ms per edge); time form 1 us per edge.
  constant C_ROTATE_TIME       : time        := 50 ms;   -- 4 edge angles at 60 rpm, 8 at 120 rpm
  constant C_ROTATE_RPM        : positive    := 60;
  constant C_ROTATE_RPM_FAST   : positive    := 120;
  constant C_ROTATE_TPE        : time        := 1 us;
  constant C_ROTATE_TPE_TIME   : time        := 2.75 us; -- 2.75 edge angles in reverse: 3 edges, position -3
  constant C_ENTRY_TIME        : time        := 25 ms;
  constant C_PROFILE           : real_vector := (60.0, 120.0);
  constant C_PROFILE_ZERO      : real_vector := (0.0, 60.0);
  -- Hand values: (60, 120) rpm, 25 ms per entry, from the centre of a state
  constant C_PROFILE_EDGES     : time_vector := (6.25 ms, 18.75 ms, 28.125 ms, 34.375 ms, 40.625 ms, 46.875 ms);
  constant C_PROFILE_HOLD_EDGES   : time_vector := (53.125 ms, 59.375 ms);           -- Then every 6.25 ms
  constant C_PROFILE_REPEAT_EDGES : time_vector := (56.25 ms, 68.75 ms, 78.125 ms);  -- The profile again from 50 ms
  constant C_PROFILE_ZERO_EDGES   : time_vector := (31.25 ms, 43.75 ms);
  constant C_PROFILE_END       : time        := 2 * C_ENTRY_TIME;
  constant C_EMPTY_PROFILE     : real_vector(1 to 0) := (others => 0.0);

  -- linear_ramp_rotation: slow start-up from standstill, 0 to C_RAMP_RPM_END rpm in steps of 1 rpm. An entry of
  -- C_RAMP_ENTRY_TIME at j rpm covers j * 4 edge angles, so every entry starts and ends in a state centre.
  constant C_RAMP_RPM_END      : positive    := 60;
  constant C_RAMP_ENTRY_TIME   : time        := 3 sec;

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
    variable v_pos        : integer;
    variable v_event      : t_enc_event;

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

    procedure jump(
      constant direction : in t_rotary_encoder_direction;
      constant num_edges : in natural) is
    begin
      show_config(v_config);
      rotary_encoder_jump_edges(direction, num_edges, v_state, "jump", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure set_angle(
      constant degrees : in real) is
    begin
      show_config(v_config);
      rotary_encoder_set_angle(degrees, v_state, "set angle", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure glitch(
      constant channel : in t_rotary_encoder_channel;
      constant width   : in time) is
    begin
      show_config(v_config);
      rotary_encoder_glitch(channel, width, v_state, "glitch", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure rotate(
      constant rpm      : in real;
      constant duration : in time) is
    begin
      show_config(v_config);
      rotary_encoder_rotate(rpm, duration, v_state, "rotate", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure rotate(
      constant direction     : in t_rotary_encoder_direction;
      constant time_per_edge : in time;
      constant duration      : in time) is
    begin
      show_config(v_config);
      rotary_encoder_rotate(direction, time_per_edge, duration, v_state, "rotate", enc_if, config => v_config);
      update_debug;
    end procedure;

    procedure rotate(
      constant profile        : in real_vector;
      constant time_per_entry : in time;
      constant profile_end    : in t_rotary_encoder_profile_end;
      constant duration       : in time) is
    begin
      show_config(v_config);
      rotary_encoder_rotate(profile, time_per_entry, profile_end, duration, v_state, "rotate with profile", enc_if,
                            config => v_config);
      update_debug;
    end procedure;

    -- Log entries (since the last clear) in which channel changed
    impure function num_events(
      constant channel : in t_rotary_encoder_channel) return natural is
      variable v_count : natural := 0;
    begin
      for i in 0 to shared_th_event_log.count(C_ID) - 1 loop
        if (channel = CHANNEL_A and shared_th_event_log.get(C_ID, i).a_changed) or
           (channel = CHANNEL_B and shared_th_event_log.get(C_ID, i).b_changed) then
          v_count := v_count + 1;
        end if;
      end loop;
      return v_count;
    end function;

    -- Log entries (since the last clear) in which A or B changed
    impure function num_ab_events return natural is
      variable v_count : natural := 0;
    begin
      for i in 0 to shared_th_event_log.count(C_ID) - 1 loop
        if shared_th_event_log.get(C_ID, i).a_changed or shared_th_event_log.get(C_ID, i).b_changed then
          v_count := v_count + 1;
        end if;
      end loop;
      return v_count;
    end function;

    -- Default configuration with the same offset on both edges of B
    function b_offset_config(
      constant offset : in real) return t_rotary_encoder_bfm_config is
      variable v_result : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    begin
      v_result.b_rise_offset := offset;
      v_result.b_fall_offset := offset;
      return v_result;
    end function;

    -- The edge from position to position + 1 is on B (the B level differs between the two states)
    function is_b_edge(
      constant zero_state : in std_logic_vector(1 downto 0);
      constant position   : in integer) return boolean is
    begin
      return tb_state(zero_state, position)(0) /= tb_state(zero_state, position + 1)(0);
    end function;

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

    -- Lets the logger record an edge driven at the current time: a move whose last edge lies on its end (a jittered
    -- edge clamped to the end, or an end on a boundary) returns in the delta of that edge
    procedure wait_for_logger is
    begin
      wait for 0 ns;
      wait for 0 ns;
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
      wait_for_logger;
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

    -- linear_ramp: actual equals expected entry by entry (exact: the hand values are exact in binary floating point)
    procedure check_ramp(
      constant actual   : in real_vector;
      constant expected : in real_vector;
      constant msg      : in string) is
    begin
      check_value(actual'length, expected'length, ERROR, "length: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      if actual'length = expected'length then
        for j in 0 to expected'length - 1 loop
          check_value(actual(actual'low + j), expected(expected'low + j), ERROR, "entry " & to_string(j) & ": " & msg, C_SCOPE,
                      ID_SEQUENCER_SUB);
        end loop;
      end if;
    end procedure;

    -- Rotation status at rest after a timed rotation
    procedure check_at_rest(
      constant msg : in string) is
    begin
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.is_rotating, false, ERROR, "status is_rotating: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.rpm, 0.0, ERROR, "status rpm: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
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
      -- 6 edges (4 forward, 2 reverse), the illegal transition, 'X' and back, Z up and down: 11 log entries
      check_value(shared_th_event_log.num_edges(C_ID), 6, ERROR, "number of edges", C_SCOPE);
      check_value(shared_th_event_log.num_z_events(C_ID), C_Z_EVENTS_PER_PULSE, ERROR, "number of Z events", C_SCOPE);
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

      -- Hand-computed: (k - 1/2) * 60 s / (rpm * 4 * cycles_per_rev) after t_start, floored to the resolution
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
      v_bad_config.zero_state := "0X";  -- Invalid level
      begin_reject("init with zero state " & to_string(v_bad_config.zero_state));
      show_config(v_bad_config);
      rotary_encoder_init(v_state, "invalid zero state", enc_if, config => v_bad_config);
      end_reject("init with zero state " & to_string(v_bad_config.zero_state));

      log_step("Invalid and changed zero state after init");
      for i in 0 to 1 loop
        if i = 0 then
          v_bad_config.zero_state := "0X";  -- Invalid level
        else
          v_bad_config.zero_state := "00";  -- Valid, but not the zero state kept at init
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

      -- 3 + 2 + 2 = 7 edges without a gap; net position +3 - 2 + 2 = 3
      log_step("Back to back with direction changes: +3 -2 +2");
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, C_TPE);
      edges(REVERSE, 2, C_TPE);
      edges(FORWARD, 2, C_TPE);
      check_duration(7 * C_TPE, 0 ns, "3 + 2 + 2 edges");
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 7, C_TPE, "back to back");
      check_checker(shared_th_event_log, C_ID, 3, "back to back");

      log_step("Rpm form, 1000 edges per speed");
      increment_expected_alerts(TB_WARNING, 1, "UVVM time stamp truncation (7 rpm ends between whole ns, shown once)");
      for i in C_TIMING_RPM'range loop
        init_encoder(config_with(0.0));
        v_t_start := now;
        edges(FORWARD, 1000, real(C_TIMING_RPM(i)));
        check_duration(ideal_move_time(0 ns, 1000, C_TIMING_RPM(i), C_CPR), C_RESOLUTION,
                       "1000 edges at " & to_string(C_TIMING_RPM(i)) & " rpm");
        check_edge_times_rpm(shared_th_event_log, C_ID, 0, v_t_start, 1000, C_TIMING_RPM(i), C_CPR, to_string(C_TIMING_RPM(i)) & " rpm");
        check_checker(shared_th_event_log, C_ID, 1000, "rpm form");
      end loop;

      -- 3 edges at 1 us, then 3 at 3 us; log entries 2 and 3 are the last edge at the first speed and the first at the second
      log_step("Speed curve, time form: 3 edges per speed");
      init_encoder(config_with(0.0));
      v_t_start := now;
      edges(FORWARD, 3, 1 us);
      edges(FORWARD, 3, 3 us);
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 3, 1 us, "first speed");
      check_edge_times(shared_th_event_log, C_ID, 3, v_t_start + 3 * 1 us, 3, 3 us, "second speed");
      check_value(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                  (1 us + 3 us) / 2, ERROR, "interval at the speed change = mean of the two time_per_edge",
                  C_SCOPE, ID_SEQUENCER_SUB);

      -- The same with 3 edges at 60 rpm, then 3 at 120 rpm
      log_step("Speed curve, rpm form: 3 edges per speed");
      init_encoder(config_with(0.0));
      edges(FORWARD, 3, 60.0);
      edges(FORWARD, 3, 120.0);
      v_time_out := (ideal_move_time(0 ns, 1, 60, C_CPR) + ideal_move_time(0 ns, 1, 120, C_CPR)) / 2;
      check_value_in_range(shared_th_event_log.get(C_ID, 3).time_stamp - shared_th_event_log.get(C_ID, 2).time_stamp,
                           v_time_out - C_RPM_EDGE_TOL, v_time_out + C_RPM_EDGE_TOL, ERROR,
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

      -- 5 + 3 + 7 + 10 = 25 edges without a gap; net position +5 - 3 + 7 - 10 = -1
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
      for i in C_BAD_TPES'range loop
        begin_reject("time_per_edge " & to_string(C_BAD_TPES(i), ns));
        edges(FORWARD, C_EDGES_PER_CYCLE, C_BAD_TPES(i));
        end_reject("time_per_edge " & to_string(C_BAD_TPES(i), ns));
      end loop;
      for i in C_BAD_RPMS'range loop
        begin_reject("rpm " & real'image(C_BAD_RPMS(i)));
        show_config(v_config);
        rotary_encoder_move_edges(FORWARD, C_EDGES_PER_CYCLE, C_BAD_RPMS(i), v_state, "invalid rpm", enc_if, config => v_config);
        end_reject("rpm " & real'image(C_BAD_RPMS(i)));
      end loop;
      begin_reject("angle move at " & real'image(C_BAD_RPMS(0)) & " rpm");
      show_config(v_config);
      rotary_encoder_move_angle(FORWARD, C_ANGLE_10, C_BAD_RPMS(0), v_state, "invalid rpm", enc_if, config => v_config);
      end_reject("angle move at " & real'image(C_BAD_RPMS(0)) & " rpm");
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
            -- index_stimulus goes forward and back: at least C_INDEX_REVS pulses each way
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
      init_encoder(index_config("00", "00", 2));  -- zero state 00, index state 00, width 2
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
      for z in C_PLACEMENT_ZERO_STATES'range loop
        init_encoder(index_config(C_PLACEMENT_ZERO_STATES(z), "00", 1));  -- index state 00, width 1
        for p in 0 to C_EDGES_PER_CYCLE - 1 loop
          go_to_position(p);
          check_value(enc_if.z, C_PLACEMENT_Z(z)(p), MATCH_EXACT, ERROR, "zero state " & to_string(C_PLACEMENT_ZERO_STATES(z)) &
                      ", Z at position " & to_string(p), C_SCOPE, ID_SEQUENCER_SUB);
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "invalid_index_configuration" then
      -- Invalid index configuration with index enabled: one TB_ERROR per call, no edge
      log_step("Invalid index configuration");
      init_encoder(C_DEFAULT);
      v_bad_config                := C_DEFAULT;
      v_bad_config.cycles_per_rev := C_BAD_CPR;
      reject_move(v_bad_config, "cycles_per_rev " & to_string(C_BAD_CPR));
      for i in C_BAD_WIDTHS'range loop
        v_bad_config             := C_DEFAULT;
        v_bad_config.index_width := C_BAD_WIDTHS(i);
        reject_move(v_bad_config, "index_width " & to_string(C_BAD_WIDTHS(i)));
      end loop;
      v_bad_config             := C_DEFAULT;
      v_bad_config.index_state := "0X";  -- Invalid level
      reject_move(v_bad_config, "index_state " & to_string(v_bad_config.index_state));
      begin_reject("init with index_state " & to_string(v_bad_config.index_state));
      show_config(v_bad_config);
      rotary_encoder_init(v_state, "invalid index state", enc_if, config => v_bad_config);
      end_reject("init with index_state " & to_string(v_bad_config.index_state));
      check_status(0, 0.0, "after the rejected calls");

      log_step("With index disabled, width and index state are not checked");
      v_bad_config               := C_DEFAULT;
      v_bad_config.index_enabled := false;
      v_bad_config.index_width   := C_BAD_WIDTHS(0);
      v_bad_config.index_state   := "0X";
      check_accepted(v_bad_config, "index disabled, width " & to_string(C_BAD_WIDTHS(0)) & ", index state " &
                     to_string(v_bad_config.index_state));

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce" then
      -- Bounce disabled: one event per edge
      log_step("Bounce disabled");
      init_encoder(C_DEFAULT);
      edges(FORWARD, 20, C_BOUNCE_TPE);
      v_num := 0;
      for i in 0 to shared_th_event_log.count(C_ID) - 1 loop
        if shared_th_event_log.get(C_ID, i).a_changed or shared_th_event_log.get(C_ID, i).b_changed then
          v_num := v_num + 1;
        end if;
      end loop;
      check_value(v_num, 20, ERROR, "A/B events = edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 20, "bounce disabled");

      -- Random placement over one revolution that crosses the index once
      log_step("Bounce enabled, random placement, one revolution across the index");
      v_bad_config             := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
      v_bad_config.start_angle := real(C_EDGES_PER_REV / 2) * C_DEG_PER_EDGE; -- Half a revolution away from the index
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_EDGES_PER_REV, C_BOUNCE_TPE);
      check_bounce(shared_th_event_log, C_ID, v_t_start, C_EDGES_PER_REV, C_BOUNCE_TPE, 2 * C_BOUNCE_PULSES, C_BOUNCE_WINDOW,
                   "random placement");
      check_value(shared_th_event_log.num_z_events(C_ID), C_Z_EVENTS_PER_PULSE, ERROR, "Z does not bounce: one index pulse",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "bounce enabled");

    --============================================================================================================================
    elsif GC_TESTCASE = "bounce_placement" then
      -- Even placement: toggle i at i * window / (toggles + 1)
      log_step("Even placement");
      -- 3 pulses (6 toggles) in a 7 us window: toggle i at i * 1 us after each of 4 edges
      init_encoder(bounce_config(BOUNCE_EVEN, 3, 7 us));
      v_t_start := now;
      edges(FORWARD, 4, C_BOUNCE_TPE);
      wait for 7 us; -- The window outlasts the move (half an edge interval after the last edge)
      check_bounce(shared_th_event_log, C_ID, v_t_start, 4, C_BOUNCE_TPE, 6, 7 us,
                   "even placement");
      for k in 1 to 4 loop
        v_edge_t := v_t_start + (2 * k - 1) * C_BOUNCE_TPE / 2;
        for i in 1 to 6 loop
          check_event_time((k - 1) * (1 + 6) + i, v_edge_t + i * 1 us,
                           C_RESOLUTION, "edge " & to_string(k) & ", even toggle " & to_string(i));
        end loop;
      end loop;

      -- Random placement, the same seed twice (logs C_ID and C_ID_CMP), then another seed (log C_ID_CMP)
      log_step("Random placement: same seed, same times; another seed, other times");
      -- Run 0: reference (log C_ID); run 1: same seed, run 2: another seed (both log C_ID_CMP)
      for run in 0 to 2 loop
        v_bad_config := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
        if run = 2 then
          v_bad_config.rand_seed1 := 12345;
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
                     C_BOUNCE_WINDOW, "random placement, run " & to_string(run));
        if run > 0 then
          compare_logs(shared_th_event_log, C_ID, v_run_start(0), C_ID_CMP, v_run_start(run), false, v_match);
          check_value(v_match, run = 1, ERROR, "toggle times equal to run 0: " & to_string(run = 1), C_SCOPE, ID_SEQUENCER_SUB);
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
      -- 20 deg jitter at C_BOUNCE_TPE = 10 us moves an edge by up to 2.22 us, so the 4 us bounce window always ends
      -- before the earliest next edge
      log_step("Bounce with jitter 20 deg, one revolution across the index");
      v_bad_config             := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
      v_bad_config.jitter      := 20.0;
      v_bad_config.start_angle := real(C_EDGES_PER_REV / 2) * C_DEG_PER_EDGE; -- Half a revolution away from the index
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_EDGES_PER_REV, C_BOUNCE_TPE);
      check_duration(C_EDGES_PER_REV * C_BOUNCE_TPE, 0 ns, "completion unchanged by bounce and jitter");
      check_bounce(shared_th_event_log, C_ID, v_t_start, C_EDGES_PER_REV, C_BOUNCE_TPE, 2 * C_BOUNCE_PULSES, C_BOUNCE_WINDOW,
                   "bounce with jitter", C_SCOPE, C_BOUNCE_TPE * (v_config.jitter / C_DEG_ELECTRICAL_PER_EDGE));
      check_value(shared_th_event_log.num_z_events(C_ID), C_Z_EVENTS_PER_PULSE, ERROR, "Z does not bounce: one index pulse",
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
      -- A 6 us window fits at ideal timing (10 us per edge); 40 deg jitter pulls edges up to 4.44 us early. 2 commands
      -- of 100 edges, so that jitter cuts off at least one bounce per command.
      log_step("Jitter 40 deg cuts off bounce_window 6 us, 2 commands");
      v_bad_config        := bounce_config(BOUNCE_RANDOM, C_BOUNCE_PULSES, 6 us);
      v_bad_config.jitter := 40.0;
      init_encoder(v_bad_config);
      for cmd in 1 to 2 loop
        increment_expected_alerts(TB_WARNING, 1, "bounce cut-off by a jittered edge, once per command");
        v_alerts := get_alert_counter(TB_WARNING);
        edges(FORWARD, 100, C_BOUNCE_TPE);
        check_value(get_alert_counter(TB_WARNING) - v_alerts, 1, ERROR, "one cut-off alert in command " & to_string(cmd),
                    C_SCOPE, ID_SEQUENCER_SUB);
      end loop;
      wait for 6 us; -- The bounce of the last edge ends
      check_value(std_logic_vector'(enc_if.a & enc_if.b), tb_state(v_config.zero_state, 200),
                  MATCH_EXACT, ERROR, "settled at the final state", C_SCOPE, msg_id => ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 200, "jitter cuts off bounce");

    --============================================================================================================================
    elsif GC_TESTCASE = "jitter" then
      -- Statistics over C_JITTER_EDGES edges, time form
      v_bad_config        := C_DEFAULT;
      v_bad_config.jitter := 40.0;  -- Electrical degrees
      log_step("Jitter 40 deg, " & to_string(C_JITTER_EDGES) & " edges at 1 us");
      init_encoder(v_bad_config);
      v_t_start := now;
      edges(FORWARD, C_JITTER_EDGES, 1 us);
      check_duration(C_JITTER_EDGES * 1 us, 0 ns, "completion unchanged by jitter");
      for k in 1 to C_JITTER_EDGES loop
        v_expected(k) := v_t_start + (2 * k - 1) * 1 us / 2;
      end loop;
      check_jitter_stats(shared_th_event_log, C_ID, 0, v_expected, 1 us * (v_config.jitter / C_DEG_ELECTRICAL_PER_EDGE),
                         C_RESOLUTION, "time form");
      check_value(shared_th_event_log.count(C_ID), C_JITTER_EDGES, ERROR, "edge count exact", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_JITTER_EDGES, "jitter, time form");

      -- The same jitter in electrical degrees scales with time_per_edge
      for r in C_JITTER_RPMS'range loop
        log_step("Jitter at " & to_string(C_JITTER_RPMS(r)) & " rpm");
        init_encoder(v_bad_config);
        v_t_start := now;
        edges(FORWARD, 1000, real(C_JITTER_RPMS(r)));
        for k in 1 to 1000 loop
          v_expected(k) := ideal_edge_time(v_t_start, k, C_JITTER_RPMS(r), C_CPR);
        end loop;
        check_jitter_stats(shared_th_event_log, C_ID, 0, v_expected(1 to 1000),
                           ideal_move_time(0 ns, 1, C_JITTER_RPMS(r), C_CPR) * (v_config.jitter / C_DEG_ELECTRICAL_PER_EDGE),
                           C_RPM_EDGE_TOL, to_string(C_JITTER_RPMS(r)) & " rpm");
        check_checker(shared_th_event_log, C_ID, 1000, to_string(C_JITTER_RPMS(r)) & " rpm");
      end loop;

      -- The same seed gives the same edge times (logs C_ID and C_ID_CMP)
      log_step("Jitter reproducible with the same seed");
      for run in 0 to 1 loop
        select_log(C_ID + run);
        init_encoder(v_bad_config);
        v_run_start(run) := now;
        edges(FORWARD, C_REPRO_EDGES, 1 us);
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
      -- Edges at the boundary crossings, the end exactly at the target, durations in both forms. Boundaries lie at
      -- +-2.25, +-6.75, ... deg (half an edge angle around each state centre).
      log_step("Three 1 deg moves, the edge at half an edge angle");
      init_encoder(config_with(0.0));
      v_t_start := now;
      for i in 1 to 3 loop
        angle(FORWARD, C_ANGLE_1, C_TPE_ANGLE);
        check_duration(i * C_TIME_PER_DEG, i * C_RESOLUTION, to_string(i) & " x 1 deg");
        -- The first boundary (2.25 deg) is crossed in the third move
        check_value(shared_th_event_log.count(C_ID), i / 3, ERROR, "edges after " & to_string(i) & " moves", C_SCOPE, ID_SEQUENCER_SUB);
      end loop;
      check_event_time(0, v_t_start + C_TIME_PER_DEG * (0.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at half an edge angle");
      check_checker(shared_th_event_log, C_ID, 1, "3 x 1 deg");
      check_status(1, 3.0 * C_ANGLE_1, "3 x 1 deg");

      -- 10 deg crosses the boundaries at 2.25 and 6.75 deg: 2 edges, position 2
      log_step(to_string(C_ANGLE_10, 1) & " deg from 0 deg: 2 edges, ends at the target");
      init_encoder(config_with(0.0));
      v_t_start := now;
      angle(FORWARD, C_ANGLE_10, C_TPE_ANGLE);
      check_duration(C_TIME_PER_DEG * C_ANGLE_10, C_RESOLUTION, "time form");
      check_event_time(0, v_t_start + C_TIME_PER_DEG * (0.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at 0.5 edge angles");
      check_event_time(1, v_t_start + C_TIME_PER_DEG * (1.5 * C_DEG_PER_EDGE), C_RESOLUTION, "edge at 1.5 edge angles");
      check_value(shared_th_event_log.num_edges(C_ID), 2, ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 2, "forward");
      check_status(2, C_ANGLE_10, "forward");
      -- The other status fields at rest: the state of position 2, Z inactive (the default index is at position 0)
      check_value(v_status.ab, tb_state(C_DEFAULT.zero_state, 2), MATCH_EXACT, ERROR, "status ab", C_SCOPE,
                  msg_id => ID_SEQUENCER_SUB);
      check_value(v_status.index_active, false, ERROR, "status index_active", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.is_rotating, false, ERROR, "status is_rotating", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.rpm, 0.0, ERROR, "status rpm", C_SCOPE, ID_SEQUENCER_SUB);
      init_encoder(config_with(0.0));
      angle(REVERSE, C_ANGLE_10, C_TPE_ANGLE);
      check_checker(shared_th_event_log, C_ID, -2, "reverse");
      check_status(-2, -C_ANGLE_10, "reverse");

      -- 10 deg (2 edges), then 1 deg (11 deg, no further edge)
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
        angle(FORWARD, C_ANGLE_1, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "1 deg moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after 1 deg moves", C_SCOPE, ID_SEQUENCER_SUB);

      -- 3600 moves of 0.1 deg: 0.1 is not exact in binary floating point
      log_step("One revolution in 0.1 deg moves");
      init_encoder(config_with(0.0));
      for i in 1 to 3600 loop
        angle(FORWARD, 0.1, C_TPE_ANGLE_FAST);
      end loop;
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "small moves");
      v_status := rotary_encoder_get_status(v_state);
      check_value(v_status.position, C_EDGES_PER_REV, ERROR, "position after small moves", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.angle, real(C_DEG_PER_REV), ERROR, "angle exactly one revolution after small moves", C_SCOPE, ID_SEQUENCER_SUB);

      -- Each pair moves 2 edge angles
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

      -- 2 deg + 4.5 deg + 1 deg = 7.5 deg: boundaries at 2.25 deg (during the edge move) and 6.75 deg (during the last
      -- angle move); position 2. Three moves, each rounded once.
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
      begin_reject("target state 0X");
      move_to_state(FORWARD, "0X", 1, C_TPE);
      end_reject("target state 0X");
      begin_reject("time_per_edge " & to_string(C_BAD_TPES(0), ns));
      move_to_state(REVERSE, C_STATES(0), 1, C_BAD_TPES(0));
      end_reject("time_per_edge " & to_string(C_BAD_TPES(0), ns));
      begin_reject("rpm " & real'image(-real(C_ANGLE_RPM)));
      show_config(v_config);
      rotary_encoder_move_to_state(FORWARD, C_STATES(0), 1, -real(C_ANGLE_RPM), v_state, "negative rpm", enc_if, config => v_config);
      end_reject("rpm " & real'image(-real(C_ANGLE_RPM)));
      check_status(0, 0.0, "after the rejected move-to-state calls");
      check_value(rotary_encoder_get_status(v_state).ab, C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "status AB unchanged",
                  C_SCOPE, msg_id => ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "speed_conversion" then
      -- Conversion functions. Expected values are hand-calculated for C_CPR = 20 (80 edges per revolution):
      -- time_per_edge = 60 s / (rpm * 80), e.g. 60 rpm -> 12.5 ms; 60 rpm = one revolution per second = 360 deg/s.
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

      -- The 5 invalid calls below: cycles_per_rev 0 (twice), 0 rpm, time_per_edge 0 ns and -1 ns
      log_step("Invalid arguments");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 5, "invalid conversions");
      v_alerts   := get_alert_counter(TB_ERROR);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(60.0, C_BAD_CPR);
      v_time_out := rotary_encoder_rpm_to_time_per_edge(0.0, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(0 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(-1 ns, C_CPR);
      v_real_out := rotary_encoder_time_per_edge_to_rpm(1 ms, C_BAD_CPR);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 5, ERROR, "one TB_ERROR per invalid call", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "move_to_state" then
      -- Move to state. Expected edges at the boundaries between the start angle and the target centre, each
      -- (distance to the boundary) / edge angle * T after the start; the move completes at the target centre.
      log_step("Move to state, time form 1 us");
      increment_expected_alerts(TB_WARNING, 1, "UVVM time stamp truncation (the 10 deg case ends between whole ns, shown once)");
      for i in C_TO_STATE_CASES'range loop
        init_encoder(config_with(C_TO_STATE_CASES(i).start_angle));
        v_t_start := now;
        move_to_state(C_TO_STATE_CASES(i).direction, C_TO_STATE_CASES(i).target, C_TO_STATE_CASES(i).occurrence, 1 us);
        v_num := abs(C_TO_STATE_CASES(i).end_position - C_TO_STATE_CASES(i).start_position);
        v_dir := dir_sign(C_TO_STATE_CASES(i).direction);
        check_duration(1 us * (abs(real(C_TO_STATE_CASES(i).end_position) * C_DEG_PER_EDGE - C_TO_STATE_CASES(i).start_angle) /
                       C_DEG_PER_EDGE), C_RESOLUTION, "case " & to_string(i));
        for k in 1 to v_num loop
          -- Boundary k in the move direction: (start_position + dir * (k - 1/2)) edge angles
          check_event_time(k - 1, v_t_start + 1 us * (abs((real(C_TO_STATE_CASES(i).start_position) + real(v_dir) * (real(k) - 0.5)) *
                           C_DEG_PER_EDGE - C_TO_STATE_CASES(i).start_angle) / C_DEG_PER_EDGE), C_RESOLUTION, "case " & to_string(i));
        end loop;
        check_value(shared_th_event_log.num_edges(C_ID), v_num, ERROR, "edge count, case " & to_string(i), C_SCOPE, ID_SEQUENCER_SUB);
        check_checker(shared_th_event_log, C_ID, v_dir * v_num, "case " & to_string(i));
        check_status(C_TO_STATE_CASES(i).end_position, real(C_TO_STATE_CASES(i).end_position) * C_DEG_PER_EDGE, "case " & to_string(i));
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "center_state" then
      -- 10 deg lies in position 2 (6.75 to 11.25 deg): centred to 9 deg
      log_step("From 10.0 deg");
      init_encoder(config_with(10.0));
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "centred");
      check_zero_time_no_event("centre state");
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "already on the centre: unchanged");
      check_zero_time_no_event("centre state on the centre");

      -- 6.75 deg is the boundary between positions 1 and 2 (1.5 edge angles): a forward move ending there is in
      -- position 2, a reverse move from position 2 ending there is in position 1
      log_step("On the boundary at 6.75 deg: the state moved into");
      init_encoder(config_with(0.0));
      angle(FORWARD, 1.5 * C_DEG_PER_EDGE, C_TPE_ANGLE);
      center;
      check_status(2, 2.0 * C_DEG_PER_EDGE, "forward move ending on the boundary");
      check_zero_time_no_event("centre state after the forward move");
      check_checker(shared_th_event_log, C_ID, 2, "forward move ending on the boundary");
      init_encoder(config_with(2.0 * C_DEG_PER_EDGE));
      angle(REVERSE, 0.5 * C_DEG_PER_EDGE, C_TPE_ANGLE);
      center;
      check_status(1, C_DEG_PER_EDGE, "reverse move ending on the boundary");
      check_zero_time_no_event("centre state after the reverse move");
      check_checker(shared_th_event_log, C_ID, -1, "reverse move ending on the boundary");

      -- With edge offsets that move the boundaries (44 deg electrical, all four edges, + and -), centring must still
      -- give the ideal centre
      log_step("With all four edge offsets at +-44.0 deg");
      for s in -1 to 1 loop
        next when s = 0;
        for i in C_OFFSET_ANGLES'range loop
          v_bad_config               := config_with(C_OFFSET_ANGLES(i));
          v_bad_config.a_rise_offset := real(s) * 44.0;
          v_bad_config.a_fall_offset := real(s) * 44.0;
          v_bad_config.b_rise_offset := real(s) * 44.0;
          v_bad_config.b_fall_offset := real(s) * 44.0;
          init_encoder(v_bad_config);
          v_t_start := now;
          center;
          check_zero_time_no_event("offsets " & to_string(real(s) * 44.0, 1) & " deg, from " & to_string(C_OFFSET_ANGLES(i), 1) & " deg");
        end loop;
      end loop;

      log_step("From " & to_string(C_OFFSET_ANGLES(0), 1) & " deg, centre, then 1 edge");
      init_encoder(config_with(C_OFFSET_ANGLES(0)));
      center;
      v_t_start := now;
      edges(FORWARD, 1, C_TPE);
      check_event_time(0, v_t_start + C_TPE / 2, 0 ns, "edge 0.5 time_per_edge after the start");
      check_checker(shared_th_event_log, C_ID, 1, "centre state, then 1 edge");

    --============================================================================================================================
    elsif GC_TESTCASE = "set_angle_and_jump_edges" then
      -- Jumps from each of the four states, both directions: the outputs change in one delta, in zero time
      log_step("Jump of 1, 2, 3, 4 edges and one revolution, from each state, both directions");
      for s in 0 to C_EDGES_PER_CYCLE - 1 loop
        for i in C_JUMP_EDGES'range loop
          for d in t_rotary_encoder_direction loop
            v_dir := dir_sign(d);
            v_pos := s + v_dir * C_JUMP_EDGES(i);
            init_encoder(config_with(real(s) * C_DEG_PER_EDGE));
            v_t_start := now;
            jump(d, C_JUMP_EDGES(i));
            check_value(now, v_t_start, ERROR, "zero time", C_SCOPE, ID_SEQUENCER_SUB);
            wait_for_logger;
            check_value(num_ab_events, C_JUMP_AB_EVENTS(i), ERROR, "entries with an A/B change", C_SCOPE, ID_SEQUENCER_SUB);
            check_checker(shared_th_event_log, C_ID, v_dir * C_JUMP_DECODED(i), "jump " & to_string(d) & " " &
                          to_string(C_JUMP_EDGES(i)) & " from state " & to_string(s), exp_illegal => C_JUMP_ILLEGAL(i));
            check_status(v_pos, real(v_pos) * C_DEG_PER_EDGE, "jump " & to_string(d) & " " & to_string(C_JUMP_EDGES(i)));
            check_z_model(v_pos, "after the jump");
            if C_JUMP_EDGES(i) = C_EDGES_PER_REV then
              check_value(shared_th_event_log.count(C_ID), 0, ERROR, "one revolution: no event, no index pulse", C_SCOPE,
                          ID_SEQUENCER_SUB);
            end if;
          end loop;
        end loop;
      end loop;

      -- The index stays consistent: Z follows the model from the new position
      log_step("After a jump of 2 edges, one revolution forward from the new state");
      init_encoder(C_DEFAULT);
      jump(FORWARD, 2);
      wait_for_logger;
      shared_th_event_log.clear(C_ID);
      edges(FORWARD, C_EDGES_PER_REV, C_TPE);
      check_z_follows_ab(shared_th_event_log, C_ID, 2, v_config.zero_state, v_config.index_state, v_config.index_width,
                         v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations,
                         "revolution after the jump");
      check_value(v_activations, 1, ERROR, "one index pulse in the revolution", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "revolution after the jump");

      log_step("Set angle from position " & to_string(C_SET_ANGLE_FROM) & " to 0 deg and to " & to_string(C_SET_ANGLE_30, 1) & " deg");
      init_encoder(C_DEFAULT);
      go_to_position(C_SET_ANGLE_FROM);
      shared_th_event_log.clear(C_ID);
      v_t_start := now;
      set_angle(0.0);
      check_value(now, v_t_start, ERROR, "zero time", C_SCOPE, ID_SEQUENCER_SUB);
      wait_for_logger;
      check_value(std_logic_vector'(enc_if.a & enc_if.b), C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "AB = zero state at 0 deg",
                  C_SCOPE, msg_id => ID_SEQUENCER_SUB);
      check_z_model(0, "set angle 0 deg");
      check_status(0, 0.0, "set angle 0 deg");
      -- 5 edges back: one edge on one channel
      check_value(num_ab_events, 1, ERROR, "one A/B entry", C_SCOPE, ID_SEQUENCER_SUB);
      set_angle(C_SET_ANGLE_30);
      wait_for_logger;
      check_status(C_SET_ANGLE_30_POS, C_SET_ANGLE_30, "set angle " & to_string(C_SET_ANGLE_30, 1) & " deg");
      check_value(std_logic_vector'(enc_if.a & enc_if.b), tb_state(C_DEFAULT.zero_state, C_SET_ANGLE_30_POS), MATCH_EXACT, ERROR,
                  "AB at " & to_string(C_SET_ANGLE_30, 1) & " deg", C_SCOPE, msg_id => ID_SEQUENCER_SUB);

      -- The boundary between positions 0 and 1 lies at half an edge angle
      log_step("Set angle onto a boundary: the shaft stays on the side of the old angle");
      init_encoder(C_DEFAULT);
      set_angle(0.5 * C_DEG_PER_EDGE);
      check_status(0, 0.5 * C_DEG_PER_EDGE, "from 0 deg");
      init_encoder(config_with(C_DEG_PER_EDGE));
      set_angle(0.5 * C_DEG_PER_EDGE);
      check_status(1, 0.5 * C_DEG_PER_EDGE, "from one edge angle");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event: the state is unchanged", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Set the current angle again: nothing changes");
      set_angle(0.5 * C_DEG_PER_EDGE);
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(1, 0.5 * C_DEG_PER_EDGE, "unchanged");

      log_step("After set angle " & to_string(C_SET_ANGLE_30, 1) & " deg, one revolution forward");
      set_angle(C_SET_ANGLE_30);
      wait_for_logger;
      shared_th_event_log.clear(C_ID);
      edges(FORWARD, C_EDGES_PER_REV, C_TPE);
      check_z_follows_ab(shared_th_event_log, C_ID, C_SET_ANGLE_30_POS, v_config.zero_state, v_config.index_state,
                         v_config.index_width, v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted,
                         v_activations, "revolution after set angle");
      check_value(v_activations, 1, ERROR, "one index pulse in the revolution", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "revolution after set angle");

    --============================================================================================================================
    elsif GC_TESTCASE = "glitch" then
      -- A pulse on one channel, back to the previous level; position and state unchanged
      for c in t_rotary_encoder_channel loop
        log_step("Glitch on " & to_string(c));
        init_encoder(C_DEFAULT);
        v_t_start := now;
        glitch(c, C_GLITCH_WIDTH);
        check_duration(C_GLITCH_WIDTH, 0 ns, "glitch");
        wait_for_logger;
        check_value(shared_th_event_log.count(C_ID), 2, ERROR, "two entries", C_SCOPE, ID_SEQUENCER_SUB);
        check_value(num_events(c), 2, ERROR, "both on " & to_string(c), C_SCOPE, ID_SEQUENCER_SUB);
        check_event_time(0, v_t_start, 0 ns, "pulse start");
        check_event_time(1, v_t_start + C_GLITCH_WIDTH, 0 ns, "pulse end");
        check_value(std_logic_vector'(enc_if.a & enc_if.b), C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "back to the previous state",
                    C_SCOPE, msg_id => ID_SEQUENCER_SUB);
        check_status(0, 0.0, "position unchanged");
        check_checker(shared_th_event_log, C_ID, 0, "glitch decodes as one edge forth and back");
        shared_th_event_log.clear(C_ID);
        edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE);
        check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE, "move after the glitch");
      end loop;

      log_step("Glitch on a stuck channel: no pulse, no alert, completes after the width");
      v_bad_config         := C_DEFAULT;
      v_bad_config.a_stuck := '0';
      init_encoder(v_bad_config);
      v_alerts  := get_alert_counter(TB_WARNING) + get_alert_counter(TB_ERROR);
      v_t_start := now;
      glitch(CHANNEL_A, C_GLITCH_WIDTH);
      check_duration(C_GLITCH_WIDTH, 0 ns, "glitch on a stuck channel");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(get_alert_counter(TB_WARNING) + get_alert_counter(TB_ERROR) - v_alerts, 0, ERROR, "no alert", C_SCOPE,
                  ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "invalid_fault_event" then
      log_step("Invalid glitch width");
      init_encoder(C_DEFAULT);
      for i in C_BAD_WIDTHS_GLITCH'range loop
        begin_reject("glitch width " & to_string(C_BAD_WIDTHS_GLITCH(i), ns));
        glitch(CHANNEL_A, C_BAD_WIDTHS_GLITCH(i));
        end_reject("glitch width " & to_string(C_BAD_WIDTHS_GLITCH(i), ns));
      end loop;

      log_step("Set angle not finite");
      for i in C_BAD_ANGLES'range loop
        begin_reject("set angle " & real'image(C_BAD_ANGLES(i)));
        set_angle(C_BAD_ANGLES(i));
        end_reject("set angle " & real'image(C_BAD_ANGLES(i)));
      end loop;
      check_status(0, 0.0, "after the rejected calls");

    --============================================================================================================================
    elsif GC_TESTCASE = "edge_offsets" then
      -- An offset is an angle: the same in both directions, so a positive offset makes the edge later going forward and
      -- earlier going in reverse. Edge k crosses the boundary between positions p and p + 1.
      for d in t_rotary_encoder_direction loop
        log_step("B offset " & to_string(C_B_OFFSET, 1) & " deg, time form, " & to_string(d));
        v_dir        := dir_sign(d);
        v_bad_config := b_offset_config(C_B_OFFSET);
        if d = REVERSE then
          v_bad_config.start_angle := real(C_OFFSET_EDGES) * C_DEG_PER_EDGE;
        end if;
        init_encoder(v_bad_config);
        v_t_start := now;
        edges(d, C_OFFSET_EDGES, C_OFFSET_TPE);
        check_duration(C_OFFSET_EDGES * C_OFFSET_TPE, 0 ns, "completion unchanged by the offset");
        for k in 1 to C_OFFSET_EDGES loop
          if d = FORWARD then
            v_pos := k - 1;
          else
            v_pos := C_OFFSET_EDGES - k;
          end if;
          v_edge_t := v_t_start + (2 * k - 1) * C_OFFSET_TPE / 2;
          if is_b_edge(v_config.zero_state, v_pos) then
            v_edge_t := v_edge_t + v_dir * C_OFFSET_TPE * (C_B_OFFSET / C_DEG_ELECTRICAL_PER_EDGE);
          end if;
          check_event_time(k - 1, v_edge_t, C_RESOLUTION, to_string(d) & " edge " & to_string(k));
        end loop;
        check_checker(shared_th_event_log, C_ID, v_dir * C_OFFSET_EDGES, "B offset, " & to_string(d));
      end loop;

      -- With zero state 11 the A rise lies at 2.5 and the A fall at 4.5 edge angles
      log_step("A rise +" & to_string(C_DUTY_OFFSET, 1) & " deg, A fall -" & to_string(C_DUTY_OFFSET, 1) & " deg: A high time shorter");
      v_bad_config               := C_DEFAULT;
      v_bad_config.a_rise_offset := C_DUTY_OFFSET;
      v_bad_config.a_fall_offset := -C_DUTY_OFFSET;
      init_encoder(v_bad_config);
      edges(FORWARD, C_OFFSET_EDGES, C_OFFSET_TPE);
      v_num := 0;  -- 0: looking for an A rise, 1: for the following A fall, 2: found
      for i in 0 to shared_th_event_log.count(C_ID) - 1 loop
        v_event := shared_th_event_log.get(C_ID, i);
        if v_event.a_changed and v_event.a = '1' and v_num = 0 then
          v_edge_t := v_event.time_stamp;
          v_num    := 1;
        elsif v_event.a_changed and v_event.a = '0' and v_num = 1 then
          v_time_out := v_event.time_stamp - v_edge_t;
          v_num      := 2;
        end if;
      end loop;
      check_value(v_num, 2, ERROR, "A rise and fall found", C_SCOPE, ID_SEQUENCER_SUB);
      -- High for two edge angles minus the two offsets; each edge rounded once
      v_edge_t := 2 * C_OFFSET_TPE - C_OFFSET_TPE * (2.0 * C_DUTY_OFFSET / C_DEG_ELECTRICAL_PER_EDGE);
      check_value_in_range(v_time_out, v_edge_t - C_RPM_EDGE_TOL, v_edge_t + C_RPM_EDGE_TOL, ERROR, "A high time", C_SCOPE,
                           ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, C_OFFSET_EDGES, "duty error");

      -- The displacement scales with time_per_edge
      for r in C_OFFSET_RPMS'range loop
        log_step("B offset " & to_string(C_B_OFFSET, 1) & " deg at " & to_string(C_OFFSET_RPMS(r)) & " rpm");
        init_encoder(b_offset_config(C_B_OFFSET));
        v_t_start := now;
        edges(FORWARD, C_OFFSET_EDGES, real(C_OFFSET_RPMS(r)));
        for k in 1 to C_OFFSET_EDGES loop
          v_edge_t := ideal_edge_time(v_t_start, k, C_OFFSET_RPMS(r), C_CPR);
          if is_b_edge(v_config.zero_state, k - 1) then
            v_edge_t := v_edge_t + ideal_move_time(0 ns, 1, C_OFFSET_RPMS(r), C_CPR) * (C_B_OFFSET / C_DEG_ELECTRICAL_PER_EDGE);
          end if;
          check_event_time(k - 1, v_edge_t, C_RPM_EDGE_TOL, to_string(C_OFFSET_RPMS(r)) & " rpm, edge " & to_string(k));
        end loop;
        check_checker(shared_th_event_log, C_ID, C_OFFSET_EDGES, to_string(C_OFFSET_RPMS(r)) & " rpm");
      end loop;

      for s in -1 to 1 loop
        next when s = 0;
        log_step("All four offsets at " & to_string(real(s) * C_MAX_OFFSET_OK, 1) & " deg: a 4-edge move ends in the zero state");
        v_bad_config               := C_DEFAULT;
        v_bad_config.a_rise_offset := real(s) * C_MAX_OFFSET_OK;
        v_bad_config.a_fall_offset := real(s) * C_MAX_OFFSET_OK;
        v_bad_config.b_rise_offset := real(s) * C_MAX_OFFSET_OK;
        v_bad_config.b_fall_offset := real(s) * C_MAX_OFFSET_OK;
        init_encoder(v_bad_config);
        v_t_start := now;
        edges(FORWARD, C_EDGES_PER_CYCLE, C_OFFSET_TPE);
        check_duration(C_EDGES_PER_CYCLE * C_OFFSET_TPE, 0 ns, "duration as without offsets");
        wait_for_logger;
        check_value(std_logic_vector'(enc_if.a & enc_if.b), C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "ends in the zero state",
                    C_SCOPE, msg_id => ID_SEQUENCER_SUB);
        check_status(C_EDGES_PER_CYCLE, real(C_EDGES_PER_CYCLE) * C_DEG_PER_EDGE, "offsets " & to_string(real(s) * C_MAX_OFFSET_OK, 1));
        check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE, "offsets " & to_string(real(s) * C_MAX_OFFSET_OK, 1));
      end loop;

      log_step("Invalid edge offsets");
      init_encoder(C_DEFAULT);
      for i in C_BAD_OFFSETS'range loop
        v_bad_config := C_DEFAULT;
        if i = 0 then
          v_bad_config.a_rise_offset := C_BAD_OFFSETS(i);
        elsif i = 1 then
          v_bad_config.b_fall_offset := C_BAD_OFFSETS(i);
        else
          v_bad_config.a_fall_offset := C_BAD_OFFSETS(i);
        end if;
        reject_move(v_bad_config, "edge offset " & real'image(C_BAD_OFFSETS(i)));
      end loop;

      log_step("Z with a B offset: Z changes together with the displaced A/B edges");
      init_encoder(b_offset_config(C_B_OFFSET));
      index_stimulus(FORWARD);
      check_z_follows_ab(shared_th_event_log, C_ID, 0, v_config.zero_state, v_config.index_state, v_config.index_width,
                         v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations,
                         "B offset " & to_string(C_B_OFFSET, 1));
      check_value(v_activations >= 2 * C_INDEX_REVS, ERROR, "index pulses seen", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, 0, "index stimulus with B offset");

    --============================================================================================================================
    elsif GC_TESTCASE = "stuck_outputs" then
      log_step("B stuck at '0' during " & to_string(C_STUCK_REVS) & " revolutions");
      init_encoder(C_DEFAULT);
      v_config.b_stuck := '0';
      edges(FORWARD, 0, C_TPE);  -- The stuck setting is applied at the start of a command
      wait_for_logger;
      check_value(enc_if.b, '0', MATCH_EXACT, ERROR, "B stuck at '0' from the start of the command", C_SCOPE, ID_SEQUENCER_SUB);
      shared_th_event_log.clear(C_ID);
      v_num := C_STUCK_REVS * C_EDGES_PER_REV;
      edges(FORWARD, v_num, C_TPE);
      wait_for_logger;
      check_value(num_events(CHANNEL_B), 0, ERROR, "no event on B", C_SCOPE, ID_SEQUENCER_SUB);
      -- A changes at every second edge
      check_value(num_events(CHANNEL_A), v_num / 2, ERROR, "A toggles as without the fault", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(v_num, real(v_num) * C_DEG_PER_EDGE, "the model keeps running");
      check_checker(shared_th_event_log, C_ID, 0, "A alone decodes as one edge forth and back");

      log_step("B released: the next command drives B to the level of the current state at its start");
      v_config.b_stuck := '-';
      shared_th_event_log.clear(C_ID);
      v_t_start := now;
      edges(FORWARD, 1, C_TPE);
      check_event_time(0, v_t_start, 0 ns, "B released at the start of the command");
      check_value(shared_th_event_log.get(C_ID, 0).b, tb_state(C_DEFAULT.zero_state, v_num)(0), MATCH_EXACT, ERROR,
                  "B at the level of the current state", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(v_num + 1, real(v_num + 1) * C_DEG_PER_EDGE, "after the release");
      -- The release itself decodes as one edge, then the move's edge
      check_checker(shared_th_event_log, C_ID, 2, "release and one edge");

      log_step("Z stuck at 'Z' during one revolution");
      v_bad_config         := C_DEFAULT;
      v_bad_config.z_stuck := 'Z';
      init_encoder(v_bad_config);
      check_value(enc_if.z, 'Z', MATCH_EXACT, ERROR, "Z stuck at 'Z' from init", C_SCOPE, ID_SEQUENCER_SUB);
      edges(FORWARD, C_EDGES_PER_REV, C_TPE);
      wait_for_logger;
      check_value(enc_if.z, 'Z', MATCH_EXACT, ERROR, "Z still 'Z'", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.num_z_events(C_ID), 0, ERROR, "no Z event", C_SCOPE, ID_SEQUENCER_SUB);
      -- Every entry carries the 'Z' on Z: an invalid level for the decoder
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_REV, "Z stuck at 'Z'", exp_invalid => C_EDGES_PER_REV);

      log_step("Z stuck at '1' ignores index_inverted");
      v_bad_config                := C_DEFAULT;
      v_bad_config.z_stuck        := '1';
      v_bad_config.index_inverted := true;
      init_encoder(v_bad_config);
      edges(FORWARD, C_EDGES_PER_REV, C_TPE);
      wait_for_logger;
      check_value(enc_if.z, '1', MATCH_EXACT, ERROR, "Z stuck at '1'", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.num_z_events(C_ID), 0, ERROR, "no Z event", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Bounce with A stuck at '1': no bounce on the stuck output");
      v_bad_config         := bounce_config(BOUNCE_EVEN, C_BOUNCE_PULSES, C_BOUNCE_WINDOW);
      v_bad_config.a_stuck := '1';
      init_encoder(v_bad_config);
      edges(FORWARD, 2 * C_EDGES_PER_CYCLE, C_BOUNCE_TPE);  -- 4 edges on each channel
      wait for C_BOUNCE_WINDOW;
      check_value(num_events(CHANNEL_A), 0, ERROR, "no event on A", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(num_events(CHANNEL_B), C_EDGES_PER_CYCLE * (1 + 2 * C_BOUNCE_PULSES), ERROR, "B edges with bounce", C_SCOPE,
                  ID_SEQUENCER_SUB);

      log_step("Invalid stuck levels");
      init_encoder(C_DEFAULT);
      v_bad_config         := C_DEFAULT;
      v_bad_config.a_stuck := C_BAD_STUCK(0);
      reject_move(v_bad_config, "a_stuck " & to_string(C_BAD_STUCK(0)));
      v_bad_config         := C_DEFAULT;
      v_bad_config.b_stuck := C_BAD_STUCK(1);
      reject_move(v_bad_config, "b_stuck " & to_string(C_BAD_STUCK(1)));
      v_bad_config         := C_DEFAULT;
      v_bad_config.z_stuck := C_BAD_STUCK(2);
      reject_move(v_bad_config, "z_stuck " & to_string(C_BAD_STUCK(2)));

    --============================================================================================================================
    elsif GC_TESTCASE = "bfm_only_flow_and_rotate" then
      -- Edges with timing, index and an angle move by direct BFM calls
      log_step("BFM-only flow: edges, index, angle move");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      edges(FORWARD, C_EDGES_PER_CYCLE, C_TPE);
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, C_EDGES_PER_CYCLE, C_TPE, "edges");
      check_z_follows_ab(shared_th_event_log, C_ID, 0, v_config.zero_state, v_config.index_state, v_config.index_width,
                         v_config.index_position, v_config.cycles_per_rev, v_config.index_inverted, v_activations, "edges");
      -- 18 deg + 10 deg = 28 deg crosses the boundaries at 20.25 and 24.75 deg
      angle(FORWARD, C_ANGLE_10, C_TPE_ANGLE);
      check_status(C_EDGES_PER_CYCLE + 2, real(C_EDGES_PER_CYCLE) * C_DEG_PER_EDGE + C_ANGLE_10, "edges and angle move");
      check_checker(shared_th_event_log, C_ID, C_EDGES_PER_CYCLE + 2, "BFM-only flow");

      log_step("Rotate at +" & to_string(C_ROTATE_RPM) & " rpm for " & to_string(C_ROTATE_TIME, ms) & ", stop at the reached angle");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(real(C_ROTATE_RPM), C_ROTATE_TIME);
      check_duration(C_ROTATE_TIME, 0 ns, "rotate");
      v_num := C_ROTATE_TIME / ideal_move_time(0 ns, 1, C_ROTATE_RPM, C_CPR);  -- Edge angles in the rotation time
      check_edge_times_rpm(shared_th_event_log, C_ID, 0, v_t_start, v_num, C_ROTATE_RPM, C_CPR, "rotate");
      check_status(v_num, real(v_num) * C_DEG_PER_EDGE, "stopped at the reached angle");
      check_at_rest("after rotate");
      wait for C_ROTATE_TIME;
      check_value(shared_th_event_log.count(C_ID), v_num, ERROR, "no edge after the stop", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ID, v_num, "rotate forward");

      log_step("Rotate at -" & to_string(C_ROTATE_RPM_FAST) & " rpm for " & to_string(C_ROTATE_TIME, ms));
      v_pos := v_num;
      shared_th_event_log.clear(C_ID);
      v_t_start := now;
      rotate(-real(C_ROTATE_RPM_FAST), C_ROTATE_TIME);
      v_num := C_ROTATE_TIME / ideal_move_time(0 ns, 1, C_ROTATE_RPM_FAST, C_CPR);
      check_edge_times_rpm(shared_th_event_log, C_ID, 0, v_t_start, v_num, C_ROTATE_RPM_FAST, C_CPR, "rotate reverse");
      check_status(v_pos - v_num, real(v_pos - v_num) * C_DEG_PER_EDGE, "reverse");
      check_checker(shared_th_event_log, C_ID, -v_num, "rotate reverse");

      -- Edges at 0.5, 1.5 and 2.5 time_per_edge; at 2.75 edge angles the shaft is past the third boundary
      log_step("Rotate in reverse at " & to_string(C_ROTATE_TPE, ns) & " per edge for " & to_string(C_ROTATE_TPE_TIME, ns));
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(REVERSE, C_ROTATE_TPE, C_ROTATE_TPE_TIME);
      check_duration(C_ROTATE_TPE_TIME, 0 ns, "rotate, time form");
      check_edge_times(shared_th_event_log, C_ID, 0, v_t_start, 3, C_ROTATE_TPE, "rotate, time form");
      check_status(-3, -2.75 * C_DEG_PER_EDGE, "rotate, time form");
      check_checker(shared_th_event_log, C_ID, -3, "rotate, time form");

      log_step("Profile (60, 120) rpm, " & to_string(C_ENTRY_TIME, ms) & " per entry, PROFILE_STOP: returns at its end");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(C_PROFILE, C_ENTRY_TIME, PROFILE_STOP, 2 * C_PROFILE_END);
      check_duration(C_PROFILE_END, 0 ns, "returns at the end of the profile");
      for k in C_PROFILE_EDGES'range loop
        check_event_time(k, v_t_start + C_PROFILE_EDGES(k), C_RESOLUTION, "profile edge " & to_string(k + 1));
      end loop;
      check_value(shared_th_event_log.count(C_ID), C_PROFILE_EDGES'length, ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
      -- At rest at 27 deg: 2 edge angles at 60 rpm, then 4 at 120 rpm
      check_status(C_PROFILE_EDGES'length, real(C_PROFILE_EDGES'length) * C_DEG_PER_EDGE, "PROFILE_STOP");
      check_at_rest("after PROFILE_STOP");

      -- Two more edges at the last speed; at 60 ms the shaft is at 7.6 edge angles
      log_step("The same profile with PROFILE_HOLD for 60 ms");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(C_PROFILE, C_ENTRY_TIME, PROFILE_HOLD, 60 ms);
      check_duration(60 ms, 0 ns, "PROFILE_HOLD");
      for k in C_PROFILE_EDGES'range loop
        check_event_time(k, v_t_start + C_PROFILE_EDGES(k), C_RESOLUTION, "profile edge " & to_string(k + 1));
      end loop;
      for k in C_PROFILE_HOLD_EDGES'range loop
        check_event_time(C_PROFILE_EDGES'length + k, v_t_start + C_PROFILE_HOLD_EDGES(k), C_RESOLUTION, "hold edge " & to_string(k + 1));
      end loop;
      check_value(shared_th_event_log.count(C_ID), C_PROFILE_EDGES'length + C_PROFILE_HOLD_EDGES'length, ERROR, "edge count",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_status(8, 7.6 * C_DEG_PER_EDGE, "PROFILE_HOLD");

      -- The second pass starts at 50 ms; at 80 ms the shaft is at 8.8 edge angles
      log_step("The same profile with PROFILE_REPEAT for 80 ms");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(C_PROFILE, C_ENTRY_TIME, PROFILE_REPEAT, 80 ms);
      check_duration(80 ms, 0 ns, "PROFILE_REPEAT");
      for k in C_PROFILE_EDGES'range loop
        check_event_time(k, v_t_start + C_PROFILE_EDGES(k), C_RESOLUTION, "profile edge " & to_string(k + 1));
      end loop;
      for k in C_PROFILE_REPEAT_EDGES'range loop
        check_event_time(C_PROFILE_EDGES'length + k, v_t_start + C_PROFILE_REPEAT_EDGES(k), C_RESOLUTION,
                         "repeat edge " & to_string(k + 1));
      end loop;
      check_value(shared_th_event_log.count(C_ID), C_PROFILE_EDGES'length + C_PROFILE_REPEAT_EDGES'length, ERROR, "edge count",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_status(9, 8.8 * C_DEG_PER_EDGE, "PROFILE_REPEAT");

      -- No edge in the first entry; at rest at 2 edge angles
      log_step("Profile (0, 60) rpm, PROFILE_STOP");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(C_PROFILE_ZERO, C_ENTRY_TIME, PROFILE_STOP, 2 * C_PROFILE_END);
      check_duration(C_PROFILE_END, 0 ns, "returns at the end of the profile");
      for k in C_PROFILE_ZERO_EDGES'range loop
        check_event_time(k, v_t_start + C_PROFILE_ZERO_EDGES(k), C_RESOLUTION, "edge " & to_string(k + 1));
      end loop;
      check_value(shared_th_event_log.count(C_ID), C_PROFILE_ZERO_EDGES'length, ERROR, "edge count", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(C_PROFILE_ZERO_EDGES'length, real(C_PROFILE_ZERO_EDGES'length) * C_DEG_PER_EDGE, "profile (0, 60)");

      log_step("A profile of the maximum length is accepted");
      init_encoder(C_DEFAULT);
      v_alerts := get_alert_counter(TB_ERROR);
      rotate((0 to C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH - 1 => real(C_ROTATE_RPM)), C_ENTRY_TIME, PROFILE_HOLD, C_ENTRY_TIME);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 0, ERROR, "no TB_ERROR", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(2, 2.0 * C_DEG_PER_EDGE, "maximum profile, one entry at 60 rpm");

      log_step("Rotate at 0 rpm: no event");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(0.0, C_QUIET_TIME);
      check_duration(C_QUIET_TIME, 0 ns, "0 rpm");
      check_value(shared_th_event_log.count(C_ID), 0, ERROR, "no event", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(0, 0.0, "0 rpm");

      log_step("Invalid rotate parameters");
      init_encoder(C_DEFAULT);
      begin_reject("rpm not finite");
      rotate(real'high, C_ROTATE_TIME);
      end_reject("rpm not finite");
      begin_reject("time_per_edge " & to_string(C_BAD_TPES(0), ns));
      rotate(FORWARD, C_BAD_TPES(0), C_ROTATE_TIME);
      end_reject("time_per_edge " & to_string(C_BAD_TPES(0), ns));
      begin_reject("empty profile");
      rotate(C_EMPTY_PROFILE, C_ENTRY_TIME, PROFILE_HOLD, C_ROTATE_TIME);
      end_reject("empty profile");
      begin_reject("profile longer than the maximum");
      rotate((0 to C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH => real(C_ROTATE_RPM)), C_ENTRY_TIME, PROFILE_HOLD, C_ROTATE_TIME);
      end_reject("profile longer than the maximum");
      begin_reject("time_per_entry " & to_string(C_BAD_TPES(0), ns));
      rotate(C_PROFILE, C_BAD_TPES(0), PROFILE_HOLD, C_ROTATE_TIME);
      end_reject("time_per_entry " & to_string(C_BAD_TPES(0), ns));
      begin_reject("profile entry not finite");
      rotate(real_vector'(real(C_ROTATE_RPM), real'high), C_ENTRY_TIME, PROFILE_HOLD, C_ROTATE_TIME);
      end_reject("profile entry not finite");
      for i in C_BAD_TPES'range loop
        begin_reject("duration " & to_string(C_BAD_TPES(i), ns));
        rotate(real(C_ROTATE_RPM), C_BAD_TPES(i));
        end_reject("duration " & to_string(C_BAD_TPES(i), ns));
      end loop;
      check_status(0, 0.0, "after the rejected calls");

    --============================================================================================================================
    elsif GC_TESTCASE = "linear_ramp" then
      -- Hand values: 0 to 3000 rpm in 4 entries, -60 to 60 rpm in 3, a single entry is the start value
      log_step("Linear ramps");
      check_ramp(rotary_encoder_linear_ramp(0.0, 3000.0, 4), (0.0, 1000.0, 2000.0, 3000.0), "0 to 3000 rpm, 4 entries");
      check_ramp(rotary_encoder_linear_ramp(-60.0, 60.0, 3), (-60.0, 0.0, 60.0), "-60 to 60 rpm, 3 entries");
      check_ramp(rotary_encoder_linear_ramp(60.0, 120.0, 1), (0 => 60.0), "one entry");

      -- The 3 invalid calls below: 0 and -1 entries, a start speed that is not finite
      log_step("Invalid arguments: one TB_ERROR each, an empty profile");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 3, "invalid linear ramps");
      v_alerts := get_alert_counter(TB_ERROR);
      check_value(rotary_encoder_linear_ramp(0.0, 60.0, 0)'length, 0, ERROR, "0 entries", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_linear_ramp(0.0, 60.0, -1)'length, 0, ERROR, "-1 entries", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(rotary_encoder_linear_ramp(real'high, 60.0, 2)'length, 0, ERROR, "start not finite", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(get_alert_counter(TB_ERROR) - v_alerts, 3, ERROR, "one TB_ERROR per invalid call", C_SCOPE, ID_SEQUENCER_SUB);

    --============================================================================================================================
    elsif GC_TESTCASE = "linear_ramp_rotation" then
      -- A linear ramp as the profile of a rotation: entry j (from the ramp start) turns at j rpm, so its edges lie at the
      -- rpm-form times counted from the entry start
      log_step("Linear ramp 0 to " & to_string(C_RAMP_RPM_END) & " rpm, " & to_string(C_RAMP_RPM_END + 1) & " entries of " &
               to_string(C_RAMP_ENTRY_TIME, sec) & ", PROFILE_STOP");
      init_encoder(C_DEFAULT);
      v_t_start := now;
      rotate(rotary_encoder_linear_ramp(0.0, real(C_RAMP_RPM_END), C_RAMP_RPM_END + 1), C_RAMP_ENTRY_TIME, PROFILE_STOP,
             2 * (C_RAMP_RPM_END + 1) * C_RAMP_ENTRY_TIME);
      check_duration((C_RAMP_RPM_END + 1) * C_RAMP_ENTRY_TIME, 0 ns, "returns at the end of the ramp");
      -- Entry 0 at 0 rpm has no edge; v_num counts the edges of the entries before entry j
      v_num := 0;
      for j in 1 to C_RAMP_RPM_END loop
        v_pos := j * C_EDGES_PER_REV * (C_RAMP_ENTRY_TIME / 1 sec) / C_SEC_PER_MIN;  -- Edge angles in entry j
        check_edge_times_rpm(shared_th_event_log, C_ID, v_num, v_t_start + j * C_RAMP_ENTRY_TIME, v_pos, j, C_CPR,
                             "ramp entry at " & to_string(j) & " rpm");
        v_num := v_num + v_pos;
      end loop;
      check_value(shared_th_event_log.count(C_ID), v_num, ERROR, "edge count of the ramp", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(v_num, real(v_num) * C_DEG_PER_EDGE, "at rest after the ramp");
      check_at_rest("after the ramp");
      check_checker(shared_th_event_log, C_ID, v_num, "linear ramp");

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
