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
use ieee.numeric_std.all;
use ieee.math_real.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

--==========================================================================================
--==========================================================================================
package rotary_encoder_bfm_pkg is

  --==========================================================================================
  -- Types and constants for ROTARY_ENCODER BFM
  --==========================================================================================
  constant C_BFM_SCOPE : string := "ROTARY ENCODER BFM";

  -- Interface record of the encoder outputs
  type t_rotary_encoder_if is record
    a : std_logic; -- Quadrature channel A
    b : std_logic; -- Quadrature channel B
    z : std_logic; -- Index pulse, leave unconnected if the encoder has none
  end record t_rotary_encoder_if;

  type t_rotary_encoder_direction is (FORWARD, REVERSE);
  type t_rotary_encoder_channel is (CHANNEL_A, CHANNEL_B);
  type t_rotary_encoder_bounce_placement is (BOUNCE_RANDOM, BOUNCE_EVEN);
  type t_rotary_encoder_profile_end is (PROFILE_HOLD, PROFILE_STOP, PROFILE_REPEAT);

  -- Configuration record to be assigned in the test harness.
  type t_rotary_encoder_bfm_config is record
    cycles_per_rev      : integer;                      -- Quadrature cycles per revolution
    zero_state          : std_logic_vector(1 downto 0); -- AB pin levels at angle 0; taken at init, must not change
    start_angle         : real;                         -- Power-up angle in degrees
    index_enabled       : boolean;                      -- Z pulses at the index position
    index_width         : integer;                      -- Index pulse width: 1 to 4 states
    index_state         : std_logic_vector(1 downto 0); -- AB pin levels where Z starts
    index_position      : integer;                      -- First position of the index cycle, in edges from position 0
    index_inverted      : boolean;                      -- Z active low
    bounce_enabled      : boolean;                      -- Contact bounce after each edge
    bounce_pulses       : natural;                      -- Bounce pulses per edge
    bounce_window       : time;                         -- Time after the edge in which the bounce pulses lie
    bounce_placement    : t_rotary_encoder_bounce_placement;
    jitter              : real;                         -- Edge jitter in electrical degrees, 0.0 = off
    a_rise_offset       : real;                         -- Edge offsets in electrical degrees (device fault)
    a_fall_offset       : real;
    b_rise_offset       : real;
    b_fall_offset       : real;
    a_stuck             : std_logic;                    -- Stuck output level (device fault), '-' = not stuck
    b_stuck             : std_logic;
    z_stuck             : std_logic;
    rand_seed1          : positive;                     -- Seeds for bounce and jitter
    rand_seed2          : positive;
    bounce_cut_severity : t_alert_level;                -- Bounce cut off by the next edge
    id_for_bfm          : t_msg_id;                     -- The message ID used as a general message ID in the BFM
    id_for_bfm_wait     : t_msg_id;                     -- The message ID used for logging waits in the BFM
  end record t_rotary_encoder_bfm_config;

  -- Define the default value for the BFM config
  constant C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT : t_rotary_encoder_bfm_config := (
    cycles_per_rev      => 20,
    zero_state          => "11",
    start_angle         => 0.0,
    index_enabled       => true,
    index_width         => 1,
    index_state         => "11",
    index_position      => 0,
    index_inverted      => false,
    bounce_enabled      => false,
    bounce_pulses       => 2,
    bounce_window       => 1 ms,
    bounce_placement    => BOUNCE_RANDOM,
    jitter              => 0.0,
    a_rise_offset       => 0.0,
    a_fall_offset       => 0.0,
    b_rise_offset       => 0.0,
    b_fall_offset       => 0.0,
    a_stuck             => '-',
    b_stuck             => '-',
    z_stuck             => '-',
    rand_seed1          => C_RAND_INIT_SEED_1,
    rand_seed2          => C_RAND_INIT_SEED_2,
    bounce_cut_severity => TB_WARNING,
    id_for_bfm          => ID_BFM,
    id_for_bfm_wait     => ID_BFM_WAIT
  );

  -- Result of rotary_encoder_get_status() and of the VVC's rotary_encoder_get_status() via fetch_result()
  type t_rotary_encoder_status is record
    position     : integer;                      -- Edges from position 0
    angle        : real;                         -- Degrees, sub-edge precision
    ab           : std_logic_vector(1 downto 0); -- State (pin levels)
    index_active : boolean;                      -- Z active (before index_inverted)
    is_rotating  : boolean;
    rpm          : real;                         -- Signed current speed, 0.0 when not rotating
  end record t_rotary_encoder_status;

  --==========================================================================================
  -- Motion description. Used by the VVC.
  --==========================================================================================
  type t_rotary_encoder_motion_kind is (MOTION_EDGES, MOTION_ANGLE, MOTION_TO_STATE, MOTION_ROTATION); -- Used by the VVC.
  type t_rotary_encoder_speed_form is (SPEED_RPM, SPEED_TIME_PER_EDGE); -- Used by the VVC.
  type t_rotary_encoder_motion_event is (MOTION_EDGE, MOTION_PROFILE_PASS, MOTION_DONE, MOTION_INTERRUPTED); -- Used by the VVC.

  -- One motion: a move or a rotation. Used by the VVC.
  type t_rotary_encoder_motion is record
    kind           : t_rotary_encoder_motion_kind;
    direction      : t_rotary_encoder_direction;   -- Moves; rotation in SPEED_TIME_PER_EDGE
    num            : natural;                      -- Edges (MOTION_EDGES), occurrence (MOTION_TO_STATE)
    target_state   : std_logic_vector(1 downto 0); -- MOTION_TO_STATE, pin levels
    angle          : real;                         -- MOTION_ANGLE, degrees
    speed_form     : t_rotary_encoder_speed_form;
    rpm            : real;                       -- > 0 for moves, signed for rotations
    time_per_edge  : time;
    profile        : real_vector(0 to C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH - 1);
    profile_length : natural;                    -- 0: constant speed
    time_per_entry : time;
    profile_end    : t_rotary_encoder_profile_end;
  end record t_rotary_encoder_motion;

  constant C_ROTARY_ENCODER_MOTION_DEFAULT : t_rotary_encoder_motion := ( -- Used by the VVC.
    kind           => MOTION_EDGES,
    direction      => FORWARD,
    num            => 0,
    target_state   => "00",
    angle          => 0.0,
    speed_form     => SPEED_RPM,
    rpm            => 60.0,
    time_per_edge  => 0 ns,
    profile        => (others => 0.0),
    profile_length => 0,
    time_per_entry => 0 ns,
    profile_end    => PROFILE_HOLD
  );

  -- BFM state: one variable per encoder, initialized with rotary_encoder_init(). All fields are private: declare the
  -- variable, pass it to the procedures and read it with rotary_encoder_get_status().
  type t_rotary_encoder_state is record
    initialized    : boolean;
    zero_gray      : natural;                      -- Gray index of the zero state (logical state at position 0), kept from init
    position       : integer;                      -- Edges from position 0
    offset         : integer;                      -- Quanta from the centre of position
    ab             : std_logic_vector(1 downto 0); -- Logical state last driven
    z_active       : boolean;                      -- Logical Z last driven
    cycles_per_rev : integer;                      -- Geometry latched at init and at each motion start
    motion_active  : boolean;
    motion         : t_rotary_encoder_motion;
    seg_t0         : time;                         -- Segment anchor
    seg_p0         : integer;
    seg_o0         : integer;
    seg_dir        : integer;                      -- +1 forward, -1 reverse
    seg_len        : real;                         -- Segment length in quanta
    tpe_int        : time;                         -- time_per_edge: whole resolution units
    tpe_frac       : real;                         -- time_per_edge: fraction of a resolution unit
    tpe_res        : real;                         -- time_per_edge in resolution units
    speed_rpm      : real;                         -- Unsigned speed of the motion
    edges          : natural;                      -- Edges emitted by the current motion
    rpm            : real;                         -- Signed current speed, 0.0 at rest
    last_rpm       : real;                         -- Last non-zero signed speed
    last_edge_time : time;
  end record t_rotary_encoder_state;

  --==========================================================================================
  -- BFM procedures
  --==========================================================================================
  function init_rotary_encoder_if_signals(
    constant dummy : t_void
  ) return t_rotary_encoder_if;

  ---------------------------------------------------------------------------------
  -- Conversions
  ---------------------------------------------------------------------------------
  -- 60 s / (|rpm| * 4 * cycles_per_rev), rounded to the simulator resolution
  impure function rotary_encoder_rpm_to_time_per_edge(
    constant rpm            : in real;
    constant cycles_per_rev : in integer
  ) return time;

  impure function rotary_encoder_time_per_edge_to_rpm(
    constant time_per_edge  : in time;
    constant cycles_per_rev : in integer
  ) return real;

  -- 1 rpm = 6 degrees per second
  function rotary_encoder_rpm_to_deg_per_sec(
    constant rpm : in real
  ) return real;

  function rotary_encoder_deg_per_sec_to_rpm(
    constant deg_per_sec : in real
  ) return real;

  ---------------------------------------------------------------------------------
  -- Status at the current time
  ---------------------------------------------------------------------------------
  impure function rotary_encoder_get_status(
    constant state : in t_rotary_encoder_state
  ) return t_rotary_encoder_status;

  ---------------------------------------------------------------------------------
  -- Init: takes config.zero_state, places the shaft at config.start_angle and drives A/B/Z. No edges.
  ---------------------------------------------------------------------------------
  procedure rotary_encoder_init(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Moves. Each exists with rpm : real (> 0) and with time_per_edge : time (> 0 ns).
  ---------------------------------------------------------------------------------
  -- num_edges edges
  procedure rotary_encoder_move_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_move_edges(
    constant direction     : in    t_rotary_encoder_direction;
    constant num_edges     : in    natural;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Turns the shaft by angle (degrees, >= 0.0) and ends exactly there
  procedure rotary_encoder_move_angle(
    constant direction    : in    t_rotary_encoder_direction;
    constant angle        : in    real;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_move_angle(
    constant direction     : in    t_rotary_encoder_direction;
    constant angle         : in    real;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Turns the shaft to the centre of the occurrence-th following state equal to target_state (pin levels). The
  -- state the shaft is in is never counted.
  procedure rotary_encoder_move_to_state(
    constant direction    : in    t_rotary_encoder_direction;
    constant target_state : in    std_logic_vector(1 downto 0);
    constant occurrence   : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_move_to_state(
    constant direction     : in    t_rotary_encoder_direction;
    constant target_state  : in    std_logic_vector(1 downto 0);
    constant occurrence    : in    natural;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Places the shaft at the centre of the state it is in, in zero time. No output event.
  procedure rotary_encoder_center_state(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Low-level motion engine. Used by the VVC; testbenches normally use the procedures above or the VVC.
  -- Calling sequence: set_motion, then run_motion in a loop in the same time step; halt_motion to stop.
  ---------------------------------------------------------------------------------
  -- Makes motion the active motion at the current time: ends a running motion at the current angle, validates the
  -- motion, checks the zero state, latches the geometry, resolves MOTION_TO_STATE and anchors the first segment. Drives
  -- no output; rotary_encoder_run_motion() must follow in the same time step. Used by the VVC.
  procedure rotary_encoder_set_motion(
    constant motion       : in    t_rotary_encoder_motion;
    variable state        : inout t_rotary_encoder_state;
    variable accepted     : out   boolean;    -- false after a TB_ERROR; the previous motion is unchanged
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Runs the active motion until its next edge, the end of a profile pass, its end, or an event on interrupt.
  -- Used by the VVC.
  procedure rotary_encoder_run_motion(
    variable state        : inout t_rotary_encoder_state;
    variable event        : out   t_rotary_encoder_motion_event;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    signal   interrupt    : in    natural;    -- Any event returns MOTION_INTERRUPTED
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Ends the active motion at the current angle (stop, terminate). Used by the VVC.
  procedure rotary_encoder_halt_motion(
    variable state : inout t_rotary_encoder_state
  );

end package rotary_encoder_bfm_pkg;

package body rotary_encoder_bfm_pkg is

  --==========================================================================================
  -- Physical constants
  --==========================================================================================
  constant C_EDGES_PER_CYCLE     : positive := 4;      -- Quadrature: 4 edges (and 4 states) per cycle
  constant C_SEC_PER_MIN         : positive := 60;
  constant C_MINUTE              : time     := C_SEC_PER_MIN * 1 sec;
  constant C_DEG_PER_REV         : real     := 360.0;
  constant C_DEG_PER_SEC_PER_RPM : real     := C_DEG_PER_REV / real(C_SEC_PER_MIN);
  constant C_DEG_ELECTRICAL_EDGE : real     := C_DEG_PER_REV / real(C_EDGES_PER_CYCLE); -- One edge = 90 electrical degrees

  --==========================================================================================
  -- Angle model (arch 6.1): K quanta per edge, so cycles_per_rev * 1e7 quanta per degree
  --==========================================================================================
  constant C_K               : integer := 900_000_000;
  constant C_HALF_K          : integer := C_K / 2;
  constant C_K_REAL          : real    := real(C_K);
  constant C_QUANTA_PER_DEG  : real    := C_K_REAL / C_DEG_ELECTRICAL_EDGE; -- Per cycle per revolution: 1e7
  constant C_MAX_EXACT       : real    := 9.0e15;         -- Largest distance in quanta held exactly (< 2**53)

  --==========================================================================================
  -- Time arithmetic
  --==========================================================================================
  constant C_RES             : time    := std.env.resolution_limit;
  constant C_SPLIT           : positive := 1_000_000_000; -- Large unit counts are split into C_SPLIT parts
  constant C_SPLIT_REAL      : real    := real(C_SPLIT);
  constant C_SPLIT_UNITS     : time    := C_RES * C_SPLIT;
  constant C_MAX_TPE         : real    := 1.0e18;         -- Largest time_per_edge in resolution units
  constant C_MAX_DIVISOR     : real    := 2.0e9;          -- Largest divisor handled as integer (< integer'high)
  constant C_FLOOR_SPLIT     : real    := 2.0 ** 30;      -- math_real floor is used below this magnitude only
  constant C_MAX_PRINTABLE   : real    := 1.0e15;         -- Larger reals are printed with 'image (F-011)
  constant C_REAL_DIGITS     : natural := 4;              -- Decimals of reals in log and alert messages

  type t_angle is record
    position : integer;
    offset   : integer;
  end record t_angle;

  function units_per_second return real is
    variable v_time  : time := C_RES;
    variable v_units : real := 1.0;
  begin
    while v_time < 1 sec loop
      v_time  := v_time * 10;
      v_units := v_units * 10.0;
    end loop;
    return v_units;
  end function;

  constant C_UNITS_PER_SEC : real := units_per_second;
  constant C_UNITS_PER_MIN : real := real(C_SEC_PER_MIN) * C_UNITS_PER_SEC;

  -- Edges per minute at rpm: rpm * 4 * cycles_per_rev
  function edges_per_minute(
    constant rpm            : in real;
    constant cycles_per_rev : in integer
  ) return real is
  begin
    return rpm * real(C_EDGES_PER_CYCLE * cycles_per_rev);
  end function;

  --==========================================================================================
  -- Arithmetic helpers. math_real floor is not reliable above integer'high on all simulators (GHDL), so large values
  -- are split.
  --==========================================================================================
  function floor_big(
    constant value : in real
  ) return real is
    variable v_high : real;
  begin
    if abs(value) < C_FLOOR_SPLIT then
      return floor(value);
    end if;
    v_high := floor_big(value / C_FLOOR_SPLIT);
    return v_high * C_FLOOR_SPLIT + floor(value - v_high * C_FLOOR_SPLIT);
  end function;

  -- Rounds half up
  function round_big(
    constant value : in real
  ) return real is
  begin
    return floor_big(value + 0.5);
  end function;

  -- Resolution units (>= 0) to time, rounded
  function units_to_time(
    constant num_units : in real
  ) return time is
    constant C_ROUNDED : real := round_big(num_units);
    constant C_HIGH    : real := floor_big(C_ROUNDED / C_SPLIT_REAL);
  begin
    return integer(C_HIGH) * C_SPLIT_UNITS + integer(C_ROUNDED - C_HIGH * C_SPLIT_REAL) * C_RES;
  end function;

  -- Time (>= 0) to resolution units
  function time_to_units(
    constant value : in time
  ) return real is
    constant C_HIGH : integer := value / C_SPLIT_UNITS;
  begin
    return real(C_HIGH) * C_SPLIT_REAL + real((value - C_HIGH * C_SPLIT_UNITS) / C_RES);
  end function;

  function is_finite(
    constant value : in real
  ) return boolean is
  begin
    return value > real'low and value < real'high;
  end function;

  -- to_string with C_REAL_DIGITS for printable values; 'image for huge ones (to_string(real'high, 6) fails on NVC)
  function real_image(
    constant value : in real
  ) return string is
  begin
    if abs(value) < C_MAX_PRINTABLE then
      return to_string(value, C_REAL_DIGITS);
    else
      return real'image(value);
    end if;
  end function;

  --==========================================================================================
  -- Gray sequence 00 -> 10 -> 11 -> 01 (AB, A leads B)
  --==========================================================================================
  function gray_index(
    constant ab : in std_logic_vector(1 downto 0)
  ) return integer is
  begin
    if ab = "00" then
      return 0;
    elsif ab = "10" then
      return 1;
    elsif ab = "11" then
      return 2;
    elsif ab = "01" then
      return 3;
    else
      return -1;
    end if;
  end function;

  function gray_state(
    constant index : in natural
  ) return std_logic_vector is
  begin
    case index mod C_EDGES_PER_CYCLE is
      when 0      => return "00";
      when 1      => return "10";
      when 2      => return "11";
      when others => return "01";
    end case;
  end function;

  -- Gray index of the logical state at position
  function logical_gray(
    constant state    : in t_rotary_encoder_state;
    constant position : in integer
  ) return natural is
  begin
    return (state.zero_gray + position mod C_EDGES_PER_CYCLE) mod C_EDGES_PER_CYCLE;
  end function;

  -- The zero state of config is the one kept at init (REQ-006, D-32)
  function is_zero_state_kept(
    constant state  : in t_rotary_encoder_state;
    constant config : in t_rotary_encoder_bfm_config
  ) return boolean is
  begin
    return gray_index(config.zero_state) = state.zero_gray;
  end function;

  -- Moves offset_real (quanta from the centre of position, any size) into [-K/2, K/2) by changing position
  procedure normalize(
    variable position    : inout integer;
    constant offset_real : in    real;
    variable offset      : out   integer
  ) is
    variable v_steps : real := floor_big((offset_real + real(C_HALF_K)) / C_K_REAL);
    variable v_rest  : real := offset_real - v_steps * C_K_REAL;
  begin
    if v_rest >= real(C_HALF_K) then
      v_steps := v_steps + 1.0;
      v_rest  := v_rest - C_K_REAL;
    elsif v_rest < -real(C_HALF_K) then
      v_steps := v_steps - 1.0;
      v_rest  := v_rest + C_K_REAL;
    end if;
    position := position + integer(v_steps);
    offset   := integer(v_rest);
  end procedure;

  function angle_degrees(
    constant state : in t_rotary_encoder_state;
    constant angle : in t_angle
  ) return real is
  begin
    return (real(angle.position) + real(angle.offset) / C_K_REAL) * C_DEG_PER_REV / real(C_EDGES_PER_CYCLE * state.cycles_per_rev);
  end function;

  --==========================================================================================
  -- Outputs (arch 6.3, 6.4)
  --==========================================================================================
  -- Index decision (arch 6.4). Index cycle: positions index_position .. index_position + 3; q is the one whose state is
  -- index_state. Z is active at q .. q + index_width - 1, every 4 * cycles_per_rev positions. An invalid index configuration gives an inactive Z (its TB_ERROR
  -- and the last valid configuration follow with REQ-045, increment 2).
  function index_active(
    constant state    : in t_rotary_encoder_state;
    constant position : in integer;
    constant config   : in t_rotary_encoder_bfm_config
  ) return boolean is
    constant C_INDEX_GRAY : integer := gray_index(config.index_state);
    constant C_PERIOD     : integer := C_EDGES_PER_CYCLE * state.cycles_per_rev;
    variable v_q          : integer := config.index_position;
  begin
    if not config.index_enabled or C_INDEX_GRAY < 0 or config.index_width < 1 or config.index_width > C_EDGES_PER_CYCLE then
      return false;
    end if;
    for i in 0 to C_EDGES_PER_CYCLE - 1 loop
      if logical_gray(state, config.index_position + i) = C_INDEX_GRAY then
        v_q := config.index_position + i;
      end if;
    end loop;
    return (position - v_q) mod C_PERIOD < config.index_width;
  end function;

  -- Drives the state at state.position on A and B (states are pin levels); Z from the index decision and index_inverted
  procedure drive_outputs(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config
  ) is
  begin
    state.ab       := gray_state(logical_gray(state, state.position));
    state.z_active := index_active(state, state.position, config);
    encoder_if.a   <= state.ab(1);
    encoder_if.b   <= state.ab(0);
    if state.z_active xor config.index_inverted then
      encoder_if.z <= '1';
    else
      encoder_if.z <= '0';
    end if;
  end procedure;

  --==========================================================================================
  -- Motion engine (arch 6.2, 6.5)
  --==========================================================================================
  -- Time at which the segment reaches distance (quanta) from its anchor: t0 + n * tpe_int + round(n * tpe_frac +
  -- r / K * tpe_res), n whole edges, r the rest. Computed from scratch for every edge, so nothing accumulates.
  function segment_time(
    constant state    : in t_rotary_encoder_state;
    constant distance : in real
  ) return time is
    constant C_N : real := floor_big(distance / C_K_REAL);
    constant C_R : real := distance - C_N * C_K_REAL;
  begin
    return state.seg_t0 + integer(C_N) * state.tpe_int + units_to_time(C_N * state.tpe_frac + C_R / C_K_REAL * state.tpe_res);
  end function;

  -- Distance from the segment anchor to the next boundary in the segment direction
  function boundary_distance(
    constant state : in t_rotary_encoder_state
  ) return real is
  begin
    if state.seg_dir > 0 then
      return real(state.position - state.seg_p0) * C_K_REAL + real(C_HALF_K - state.seg_o0);
    else
      return real(state.seg_p0 - state.position) * C_K_REAL + real(C_HALF_K + state.seg_o0);
    end if;
  end function;

  -- Time of the next event of the active motion: an edge (a boundary is reached) or the end of the segment
  procedure next_motion_event(
    constant state   : in  t_rotary_encoder_state;
    variable at_time : out time;
    variable is_edge : out boolean
  ) is
    constant C_DISTANCE : real := boundary_distance(state);
  begin
    if state.seg_len > 0.0 and C_DISTANCE <= state.seg_len then
      at_time := segment_time(state, C_DISTANCE);
      is_edge := true;
    else
      at_time := segment_time(state, state.seg_len);
      is_edge := false;
    end if;
  end procedure;

  procedure start_segment(
    variable state  : inout t_rotary_encoder_state;
    constant dir    : in    integer;
    constant length : in    real
  ) is
  begin
    state.seg_t0  := now;
    state.seg_p0  := state.position;
    state.seg_o0  := state.offset;
    state.seg_dir := dir;
    state.seg_len := length;
    state.rpm     := real(dir) * state.speed_rpm;
    if state.rpm /= 0.0 then
      state.last_rpm := state.rpm;
    end if;
  end procedure;

  -- Angle at the current time, rounded once to a quantum (arch 6.2)
  impure function current_angle(
    constant state : in t_rotary_encoder_state
  ) return t_angle is
    variable v_distance : real;
    variable v_offset   : real;
  begin
    if not state.motion_active then
      return (state.position, state.offset);
    end if;
    v_distance := time_to_units(now - state.seg_t0) / state.tpe_res * C_K_REAL;
    if v_distance > state.seg_len then
      v_distance := state.seg_len;
    end if;
    v_offset   := real(state.seg_o0) + real(state.seg_dir) * v_distance - real(state.position - state.seg_p0) * C_K_REAL;
    v_offset   := round_big(v_offset);
    if v_offset > real(C_HALF_K) then
      v_offset := real(C_HALF_K);
    elsif v_offset < -real(C_HALF_K) then
      v_offset := -real(C_HALF_K);
    end if;
    return (state.position, integer(v_offset));
  end function;

  -- Ends the current segment at its end angle and the motion with it
  procedure end_segment(
    variable state : inout t_rotary_encoder_state
  ) is
  begin
    state.offset        := integer(real(state.seg_o0) + real(state.seg_dir) * state.seg_len -
                                   real(state.position - state.seg_p0) * C_K_REAL);
    state.motion_active := false;
    state.rpm           := 0.0;
  end procedure;

  -- Executes the next event of the active motion at the current time
  procedure motion_step(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config;
    variable is_edge    : out   boolean
  ) is
    variable v_time : time;
    variable v_edge : boolean;
  begin
    next_motion_event(state, v_time, v_edge);
    if v_edge then
      state.position       := state.position + state.seg_dir;
      state.offset         := -state.seg_dir * C_HALF_K; -- On the boundary, in the state moved into (arch 6.1)
      state.edges          := state.edges + 1;
      state.last_edge_time := now;
      drive_outputs(state, encoder_if, config);
    else
      end_segment(state);
    end if;
    is_edge := v_edge;
  end procedure;

  function dir_sign(
    constant direction : in t_rotary_encoder_direction
  ) return integer is
  begin
    if direction = FORWARD then
      return 1;
    else
      return -1;
    end if;
  end function;

  -- Checks that the state is initialized and that config.zero_state is the one kept at init (REQ-006, D-32). Raises one
  -- TB_ERROR and returns false otherwise.
  impure function is_call_valid(
    constant state     : in t_rotary_encoder_state;
    constant proc_call : in string;
    constant msg       : in string;
    constant scope     : in string;
    constant config    : in t_rotary_encoder_bfm_config
  ) return boolean is
  begin
    if not state.initialized then
      alert(TB_ERROR, proc_call & "=> Failed. The state is not initialized. Call rotary_encoder_init() first." &
                      add_msg_delimiter(msg), scope);
      return false;
    elsif not is_zero_state_kept(state, config) then
      alert(TB_ERROR, proc_call & "=> Failed. zero_state is " & to_string(config.zero_state) & ", but " &
                      to_string(gray_state(state.zero_gray)) & " was taken at init. The zero state must not change." &
                      add_msg_delimiter(msg), scope);
      return false;
    end if;
    return true;
  end function;

  -- Distance in quanta from (position, offset) to the centre of the occurrence-th following position in direction dir whose
  -- state is target_gray (arch 6.5, AD-19). The current position is never counted. Every 4 consecutive positions hold
  -- each state once, so the first match k1 lies in 1..4 and the n-th at k1 + 4 * (n - 1).
  function to_state_distance(
    constant state       : in t_rotary_encoder_state;
    constant position    : in integer;
    constant offset      : in integer;
    constant dir         : in integer;
    constant target_gray : in natural;
    constant occurrence  : in positive
  ) return real is
    variable v_k1 : natural := C_EDGES_PER_CYCLE;
  begin
    for k in C_EDGES_PER_CYCLE downto 1 loop
      if logical_gray(state, position + dir * k) = target_gray then
        v_k1 := k;
      end if;
    end loop;
    return (real(v_k1) + real(C_EDGES_PER_CYCLE) * real(occurrence - 1)) * C_K_REAL - real(dir * offset);
  end function;

  -- Validates a motion and makes it the active one at the current time (rotary_encoder_set_motion and the user-level
  -- procedures, arch 6.5)
  procedure activate_motion(
    constant motion       : in    t_rotary_encoder_motion;
    constant proc_call    : in    string;
    variable state        : inout t_rotary_encoder_state;
    variable accepted     : out   boolean;
    constant msg          : in    string;
    constant scope        : in    string;
    constant msg_id_panel : in    t_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config
  ) is
    constant C_DIR      : integer := dir_sign(motion.direction);
    variable v_tpe_res  : real;
    variable v_length   : real;
    variable v_angle    : t_angle;
    variable v_den      : real;

    procedure fail(
      constant reason : in string
    ) is
    begin
      alert(TB_ERROR, proc_call & "=> Failed. " & reason & add_msg_delimiter(msg), scope);
      accepted := false;
    end procedure;
  begin
    accepted := false;
    -- Validation: one TB_ERROR, no change
    if not is_call_valid(state, proc_call, msg, scope, config) then
      return;
    elsif config.cycles_per_rev < 1 then
      fail("cycles_per_rev must be at least 1, was " & to_string(config.cycles_per_rev) & ".");
      return;
    elsif motion.kind = MOTION_ROTATION then
      fail(to_string(motion.kind) & " is not supported yet.");
      return;
    end if;
    if motion.speed_form = SPEED_RPM then
      if not (motion.rpm > 0.0 and is_finite(motion.rpm)) then
        fail("rpm must be positive and finite, was " & real_image(motion.rpm) & ".");
        return;
      end if;
      v_tpe_res := C_UNITS_PER_MIN / edges_per_minute(motion.rpm, config.cycles_per_rev);
    else
      if motion.time_per_edge <= 0 ns then
        fail("time_per_edge must be positive, was " & to_string(motion.time_per_edge, ns) & ".");
        return;
      end if;
      v_tpe_res := time_to_units(motion.time_per_edge);
    end if;
    if v_tpe_res > C_MAX_TPE then
      fail("Speed too low: time_per_edge above " & real_image(C_MAX_TPE / C_UNITS_PER_SEC) & " s.");
      return;
    end if;

    -- The angle at the current time: a running motion is replaced there
    v_angle := current_angle(state);

    case motion.kind is
      when MOTION_EDGES =>
        v_length := real(motion.num) * C_K_REAL;
      when MOTION_ANGLE =>
        if not (motion.angle >= 0.0 and is_finite(motion.angle)) then
          fail("angle must be >= 0.0 and finite (the direction is a separate argument), was " & real_image(motion.angle) & ".");
          return;
        end if;
        v_length := round_big(motion.angle * real(config.cycles_per_rev) * C_QUANTA_PER_DEG);
      when others => -- MOTION_TO_STATE: resolved here into an angle move from the angle at the current time (AD-19)
        if motion.num = 0 then
          fail("occurrence must be at least 1, was 0.");
          return;
        elsif gray_index(motion.target_state) < 0 then
          fail("target_state must be a 2-bit state of '0'/'1', was " & to_string(motion.target_state) & ".");
          return;
        end if;
        v_length := to_state_distance(state, v_angle.position, v_angle.offset, C_DIR, gray_index(motion.target_state),
                                      motion.num);
    end case;
    if v_length > C_MAX_EXACT then
      fail("Move too long for one command.");
      return;
    end if;
    accepted := true;

    -- End a running motion at the current angle and latch the geometry
    state.position       := v_angle.position;
    state.offset         := v_angle.offset;
    state.cycles_per_rev := config.cycles_per_rev;

    -- Speed
    state.motion  := motion;
    state.tpe_res := v_tpe_res;
    v_den         := edges_per_minute(motion.rpm, config.cycles_per_rev);
    if motion.speed_form = SPEED_RPM and v_den < C_MAX_DIVISOR and v_den = floor(v_den) then
      -- 1 min / den with an integer den: whole units and remainder exact in time arithmetic, so that the fraction does
      -- not carry the rounding error of the real time_per_edge (multiplied by the edge count in segment_time)
      state.tpe_int  := C_MINUTE / integer(v_den);
      state.tpe_frac := real((C_MINUTE - state.tpe_int * integer(v_den)) / C_RES) / v_den;
    else
      state.tpe_int  := units_to_time(floor_big(v_tpe_res));
      state.tpe_frac := v_tpe_res - floor_big(v_tpe_res);
    end if;
    state.speed_rpm := C_UNITS_PER_MIN / (v_tpe_res * real(C_EDGES_PER_CYCLE * state.cycles_per_rev));

    state.edges         := 0;
    state.motion_active := true;
    start_segment(state, C_DIR, v_length);
  end procedure;

  -- Runs a move to its end (user-level procedures) and logs it
  procedure execute_move(
    constant motion       : in    t_rotary_encoder_motion;
    constant proc_call    : in    string;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string;
    constant msg_id_panel : in    t_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config
  ) is
    variable v_accepted : boolean;
    variable v_time     : time;
    variable v_edge     : boolean;
  begin
    activate_motion(motion, proc_call, state, v_accepted, msg, scope, msg_id_panel, config);
    if not v_accepted then
      return;
    end if;
    while state.motion_active loop
      next_motion_event(state, v_time, v_edge);
      if v_time > now then
        wait for v_time - now;
      elsif v_edge and state.last_edge_time = now then
        wait for 0 ns; -- Two edges at one time step: one delta each, never both channels in one delta
      end if;
      motion_step(state, encoder_if, config, v_edge);
    end loop;
    log(config.id_for_bfm, proc_call & "=> " & to_string(state.edges) & " edges, position " & to_string(state.position) &
                           ", angle " & real_image(angle_degrees(state, (state.position, state.offset))) & " deg." &
                           add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  function speed_string(
    constant motion : in t_rotary_encoder_motion
  ) return string is
  begin
    if motion.speed_form = SPEED_RPM then
      return real_image(motion.rpm) & " rpm";
    else
      return to_string(motion.time_per_edge, ns);
    end if;
  end function;

  --==========================================================================================
  -- Public subprograms
  --==========================================================================================
  function init_rotary_encoder_if_signals(
    constant dummy : t_void
  ) return t_rotary_encoder_if is
    variable v_result : t_rotary_encoder_if;
  begin
    v_result.a := 'Z';
    v_result.b := 'Z';
    v_result.z := 'Z';
    return v_result;
  end function;

  impure function rotary_encoder_rpm_to_time_per_edge(
    constant rpm            : in real;
    constant cycles_per_rev : in integer
  ) return time is
    constant C_PROC_CALL : string := "rotary_encoder_rpm_to_time_per_edge(" & real_image(rpm) & ", " & to_string(cycles_per_rev) & ")";
    variable v_units     : real;
  begin
    if cycles_per_rev < 1 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. cycles_per_rev must be at least 1.", C_BFM_SCOPE);
      return 0 ns;
    elsif rpm = 0.0 or not is_finite(rpm) then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. rpm must be non-zero and finite.", C_BFM_SCOPE);
      return 0 ns;
    end if;
    v_units := C_UNITS_PER_MIN / edges_per_minute(abs(rpm), cycles_per_rev);
    if v_units > C_MAX_TPE then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. Speed too low.", C_BFM_SCOPE);
      return 0 ns;
    end if;
    return units_to_time(v_units);
  end function;

  impure function rotary_encoder_time_per_edge_to_rpm(
    constant time_per_edge  : in time;
    constant cycles_per_rev : in integer
  ) return real is
    constant C_PROC_CALL : string := "rotary_encoder_time_per_edge_to_rpm(" & to_string(time_per_edge, ns) & ", " & to_string(cycles_per_rev) & ")";
  begin
    if cycles_per_rev < 1 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. cycles_per_rev must be at least 1.", C_BFM_SCOPE);
      return 0.0;
    elsif time_per_edge <= 0 ns then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. time_per_edge must be positive.", C_BFM_SCOPE);
      return 0.0;
    end if;
    return C_UNITS_PER_MIN / (time_to_units(time_per_edge) * real(C_EDGES_PER_CYCLE * cycles_per_rev));
  end function;

  function rotary_encoder_rpm_to_deg_per_sec(
    constant rpm : in real
  ) return real is
  begin
    return rpm * C_DEG_PER_SEC_PER_RPM;
  end function;

  function rotary_encoder_deg_per_sec_to_rpm(
    constant deg_per_sec : in real
  ) return real is
  begin
    return deg_per_sec / C_DEG_PER_SEC_PER_RPM;
  end function;

  impure function rotary_encoder_get_status(
    constant state : in t_rotary_encoder_state
  ) return t_rotary_encoder_status is
    variable v_angle  : t_angle;
    variable v_result : t_rotary_encoder_status := (0, 0.0, "00", false, false, 0.0);
  begin
    if not state.initialized then
      alert(TB_ERROR, "rotary_encoder_get_status()=> Failed. The state is not initialized. Call rotary_encoder_init() first.", C_BFM_SCOPE);
      return v_result;
    end if;
    v_angle               := current_angle(state);
    v_result.position     := v_angle.position;
    v_result.angle        := angle_degrees(state, v_angle);
    v_result.ab           := state.ab;
    v_result.index_active := state.z_active;
    v_result.is_rotating  := state.motion_active and state.motion.kind = MOTION_ROTATION;
    v_result.rpm          := state.rpm;
    return v_result;
  end function;

  procedure rotary_encoder_init(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_CALL : string  := "rotary_encoder_init(start_angle " & real_image(config.start_angle) & ")";
    constant C_ZERO_GRAY : integer := gray_index(config.zero_state);
    variable v_quanta    : real;
    variable v_offset    : integer;
  begin
    if config.cycles_per_rev < 1 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. cycles_per_rev must be at least 1, was " & to_string(config.cycles_per_rev) &
                      "." & add_msg_delimiter(msg), scope);
      return;
    elsif C_ZERO_GRAY < 0 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. zero_state must be a 2-bit state of '0'/'1', was " & to_string(config.zero_state) &
                      "." & add_msg_delimiter(msg), scope);
      return;
    end if;
    v_quanta := round_big(config.start_angle * real(config.cycles_per_rev) * C_QUANTA_PER_DEG);
    if not is_finite(config.start_angle) or abs(v_quanta) > C_MAX_EXACT then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. start_angle out of range." & add_msg_delimiter(msg), scope);
      return;
    end if;

    state.initialized    := true;
    state.zero_gray      := C_ZERO_GRAY;    -- Angle 0 is the centre of the zero state (A-13), kept from here on (D-32)
    state.cycles_per_rev := config.cycles_per_rev;
    state.motion_active  := false;
    state.motion         := C_ROTARY_ENCODER_MOTION_DEFAULT;
    state.edges          := 0;
    state.rpm            := 0.0;
    state.last_rpm       := 0.0;
    state.last_edge_time := time'low;
    state.position       := 0;
    normalize(state.position, v_quanta, v_offset); -- The start angle as given (A-16)
    state.offset := v_offset;
    drive_outputs(state, encoder_if, config);
    log(config.id_for_bfm, C_PROC_CALL & "=> position " & to_string(state.position) & ", angle " &
                           real_image(angle_degrees(state, (state.position, state.offset))) & " deg, AB " & to_string(state.ab) &
                           "." & add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind       := MOTION_EDGES;
    v_motion.direction  := direction;
    v_motion.num        := num_edges;
    v_motion.speed_form := SPEED_RPM;
    v_motion.rpm        := rpm;
    execute_move(v_motion, "rotary_encoder_move_edges(" & to_upper(to_string(direction)) & ", " & to_string(num_edges) & ", " &
                 speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_move_edges(
    constant direction     : in    t_rotary_encoder_direction;
    constant num_edges     : in    natural;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind          := MOTION_EDGES;
    v_motion.direction     := direction;
    v_motion.num           := num_edges;
    v_motion.speed_form    := SPEED_TIME_PER_EDGE;
    v_motion.time_per_edge := time_per_edge;
    execute_move(v_motion, "rotary_encoder_move_edges(" & to_upper(to_string(direction)) & ", " & to_string(num_edges) & ", " &
                 speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_move_angle(
    constant direction    : in    t_rotary_encoder_direction;
    constant angle        : in    real;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind       := MOTION_ANGLE;
    v_motion.direction  := direction;
    v_motion.angle      := angle;
    v_motion.speed_form := SPEED_RPM;
    v_motion.rpm        := rpm;
    execute_move(v_motion, "rotary_encoder_move_angle(" & to_upper(to_string(direction)) & ", " & real_image(angle) & " deg, " &
                 speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_move_angle(
    constant direction     : in    t_rotary_encoder_direction;
    constant angle         : in    real;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind          := MOTION_ANGLE;
    v_motion.direction     := direction;
    v_motion.angle         := angle;
    v_motion.speed_form    := SPEED_TIME_PER_EDGE;
    v_motion.time_per_edge := time_per_edge;
    execute_move(v_motion, "rotary_encoder_move_angle(" & to_upper(to_string(direction)) & ", " & real_image(angle) & " deg, " &
                 speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_move_to_state(
    constant direction    : in    t_rotary_encoder_direction;
    constant target_state : in    std_logic_vector(1 downto 0);
    constant occurrence   : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind         := MOTION_TO_STATE;
    v_motion.direction    := direction;
    v_motion.target_state := target_state;
    v_motion.num          := occurrence;
    v_motion.speed_form   := SPEED_RPM;
    v_motion.rpm          := rpm;
    execute_move(v_motion, "rotary_encoder_move_to_state(" & to_upper(to_string(direction)) & ", " & to_string(target_state) &
                 ", " & to_string(occurrence) & ", " & speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel,
                 config);
  end procedure;

  procedure rotary_encoder_move_to_state(
    constant direction     : in    t_rotary_encoder_direction;
    constant target_state  : in    std_logic_vector(1 downto 0);
    constant occurrence    : in    natural;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind          := MOTION_TO_STATE;
    v_motion.direction     := direction;
    v_motion.target_state  := target_state;
    v_motion.num           := occurrence;
    v_motion.speed_form    := SPEED_TIME_PER_EDGE;
    v_motion.time_per_edge := time_per_edge;
    execute_move(v_motion, "rotary_encoder_move_to_state(" & to_upper(to_string(direction)) & ", " & to_string(target_state) &
                 ", " & to_string(occurrence) & ", " & speed_string(v_motion) & ")", state, msg, encoder_if, scope, msg_id_panel,
                 config);
  end procedure;

  procedure rotary_encoder_center_state(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_CALL : string := "rotary_encoder_center_state()";
  begin
    if not is_call_valid(state, C_PROC_CALL, msg, scope, config) then
      return;
    elsif state.motion_active then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. Not allowed while a motion is active." & add_msg_delimiter(msg), scope);
      return;
    end if;
    -- Only the sub-edge offset changes; the position (the state the shaft is in, A-13) and the outputs stay (A-28)
    state.offset := 0;
    log(config.id_for_bfm, C_PROC_CALL & "=> position " & to_string(state.position) & ", angle " &
                           real_image(angle_degrees(state, (state.position, state.offset))) & " deg." & add_msg_delimiter(msg),
        scope, msg_id_panel);
  end procedure;

  procedure rotary_encoder_set_motion(
    constant motion       : in    t_rotary_encoder_motion;
    variable state        : inout t_rotary_encoder_state;
    variable accepted     : out   boolean;
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
  begin
    activate_motion(motion, "rotary_encoder_set_motion(" & to_upper(to_string(motion.kind)) & ")", state, accepted, msg, scope,
                    msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_run_motion(
    variable state        : inout t_rotary_encoder_state;
    variable event        : out   t_rotary_encoder_motion_event;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    signal   interrupt    : in    natural;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_time : time;
    variable v_edge : boolean;
  begin
    while state.motion_active loop
      next_motion_event(state, v_time, v_edge);
      if v_time > now then
        wait on interrupt for v_time - now;
        if now < v_time then
          event := MOTION_INTERRUPTED;
          return;
        end if;
      elsif v_edge and state.last_edge_time = now then
        wait on interrupt for 0 ns; -- One delta per edge. An interrupt at the edge time comes after the edge (D-25)
      end if;
      motion_step(state, encoder_if, config, v_edge);
      if v_edge then
        event := MOTION_EDGE;
        return;
      end if;
    end loop;
    event := MOTION_DONE;
  end procedure;

  procedure rotary_encoder_halt_motion(
    variable state : inout t_rotary_encoder_state
  ) is
    variable v_angle : t_angle;
  begin
    if state.motion_active then
      v_angle             := current_angle(state);
      state.position      := v_angle.position;
      state.offset        := v_angle.offset;
      state.motion_active := false;
      state.rpm           := 0.0;
    end if;
  end procedure;

end package body rotary_encoder_bfm_pkg;
