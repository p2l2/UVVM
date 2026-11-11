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
    edge_offset    : integer_vector(0 to 3);       -- Geometry: boundary offsets in quanta, by the Gray index of the state below
    a_stuck        : std_logic;                    -- Stuck levels last applied to the outputs, '-' = not stuck
    b_stuck        : std_logic;
    z_stuck        : std_logic;
    motion_active  : boolean;
    motion         : t_rotary_encoder_motion;
    seg_t0         : time;                         -- Segment anchor
    seg_p0         : integer;
    seg_o0         : integer;
    seg_dir        : integer;                      -- +1 forward, -1 reverse
    seg_moving     : boolean;                      -- false: the segment has 0 rpm
    seg_bounded    : boolean;                      -- true: a move that ends after seg_len
    seg_len        : real;                         -- Segment length in quanta (moves)
    seg_end        : time;                         -- End of the current profile entry; time'high if none
    profile_idx    : natural;                      -- Current profile entry
    profile_t0     : time;                         -- Start of the current profile pass
    tpe_int        : time;                         -- time_per_edge: whole resolution units
    tpe_frac       : real;                         -- time_per_edge: fraction of a resolution unit
    tpe_res        : real;                         -- time_per_edge in resolution units
    speed_rpm      : real;                         -- Unsigned speed of the motion
    edges          : natural;                      -- Edges emitted by the current motion
    rpm            : real;                         -- Signed current speed, 0.0 at rest
    last_edge_time : time;
    seed1          : positive;                     -- Random seeds of bounce and jitter, taken from config at init
    seed2          : positive;
    jitter_limit   : real;                         -- Jitter limit (electrical degrees) of the latched edge offsets
    jitter_drawn   : boolean;                      -- jitter_u is drawn for the next edge
    jitter_u       : real;                         -- Jitter of the next edge, in amplitudes (-1.0 to 1.0)
    bounce_pending : boolean;                      -- Bounce toggles of the last edge may still be scheduled
    bounce_channel : t_rotary_encoder_channel;     -- Channel of that bounce
    bounce_level   : std_logic;                    -- Its settled level
    bounce_end     : time;                         -- Time of its last toggle
    bounce_cut_reported : boolean;                 -- Bounce cut-off alert raised in the current command
    valid_config     : t_rotary_encoder_bfm_config; -- Last valid signal configuration, kept for a running motion when the configuration becomes invalid
    invalid_reported : boolean;                     -- TB_ERROR raised for invalid_config
    invalid_config   : t_rotary_encoder_bfm_config;
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

  -- Speed profile of num_entries entries from rpm_start to rpm_end, linear in rpm: entry j = rpm_start + (rpm_end -
  -- rpm_start) * j / (num_entries - 1). One entry returns rpm_start.
  impure function rotary_encoder_linear_ramp(
    constant rpm_start   : in real;
    constant rpm_end     : in real;
    constant num_entries : in integer
  ) return real_vector;

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
  -- Timed rotation: rotates for duration (> 0 ns), then stops at once at the reached angle
  ---------------------------------------------------------------------------------
  -- Signed rpm (positive = forward), 0.0 is legal
  procedure rotary_encoder_rotate(
    constant rpm          : in    real;
    constant duration     : in    time;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_rotate(
    constant direction     : in    t_rotary_encoder_direction;
    constant time_per_edge : in    time;
    constant duration      : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Speed profile: signed rpm entries, each for time_per_entry; profile_end selects hold, stop or repeat after the last
  -- entry. With PROFILE_STOP the procedure returns at the end of the profile if that comes before duration.
  procedure rotary_encoder_rotate(
    constant profile        : in    real_vector;
    constant time_per_entry : in    time;
    constant profile_end    : in    t_rotary_encoder_profile_end;
    constant duration       : in    time;
    variable state          : inout t_rotary_encoder_state;
    constant msg            : in    string;
    signal   encoder_if     : inout t_rotary_encoder_if;
    constant scope          : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel   : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config         : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Fault events. Device faults (edge offsets, stuck outputs) are set in the configuration.
  ---------------------------------------------------------------------------------
  -- Places the shaft at angle (degrees) in zero time; the outputs change from the old to the new state in one delta
  procedure rotary_encoder_set_angle(
    constant angle        : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Moves the shaft by num_edges in zero time, keeping the sub-edge fraction. 2 edges (mod 4) give an illegal transition.
  procedure rotary_encoder_jump_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
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
  -- Angle model: K quanta per edge, so cycles_per_rev * 1e7 quanta per degree
  --==========================================================================================
  constant C_K               : integer := 900_000_000;
  constant C_HALF_K          : integer := C_K / 2;
  constant C_K_REAL          : real    := real(C_K);
  -- Quanta per electrical degree: 1e7. A mechanical degree is cycles_per_rev electrical degrees.
  constant C_QUANTA_PER_DEG_ELECTRICAL : real := C_K_REAL / C_DEG_ELECTRICAL_EDGE;
  constant C_MAX_EXACT       : real    := 9.0e15;         -- Largest distance in quanta held exactly (< 2**53)
  constant C_MAX_EDGE_OFFSET : real    := C_DEG_ELECTRICAL_EDGE / 2.0; -- Edge offsets lie in the open interval +-45 deg
  constant C_MAX_POSITION    : integer := integer'high / 2; -- Largest position a jump may reach, so that edge counts fit
  constant C_NOT_STUCK       : std_logic := '-';

  -- Next event of the active motion
  type t_next_event is (NEXT_EDGE, NEXT_SEGMENT_END, NEXT_NONE);
  constant C_NO_END          : time    := time'high;      -- Segment without an end time

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
  constant C_MAX_PRINTABLE   : real    := 1.0e15;         -- Larger reals are printed with 'image (to_string(real, digits) fails for them on some simulators)
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

  -- The zero state of config is the one kept at init (angle 0 is defined by it, so it must not change afterwards)
  function is_zero_state_kept(
    constant state  : in t_rotary_encoder_state;
    constant config : in t_rotary_encoder_bfm_config
  ) return boolean is
  begin
    return gray_index(config.zero_state) = state.zero_gray;
  end function;

  --==========================================================================================
  -- Signal configuration: index, bounce, jitter
  --==========================================================================================
  -- Half the narrowest state in electrical degrees for the edge offsets of config. In the forward direction
  -- the boundaries of a cycle are A rise, B rise, A fall, B fall; the state after boundary i is 90 degrees wide plus the
  -- offset of boundary i + 1 minus the offset of boundary i. Offsets outside +-90 degrees (also non-finite ones) give 0.0;
  -- the edge offsets themselves are validated separately.
  function jitter_limit(
    constant config : in t_rotary_encoder_bfm_config
  ) return real is
    constant C_OFFSETS   : real_vector(0 to C_EDGES_PER_CYCLE - 1) := (config.a_rise_offset, config.b_rise_offset,
                                                                       config.a_fall_offset, config.b_fall_offset);
    variable v_width     : real;
    variable v_narrowest : real := C_DEG_ELECTRICAL_EDGE;
  begin
    for i in C_OFFSETS'range loop
      if not (abs(C_OFFSETS(i)) < C_DEG_ELECTRICAL_EDGE) then
        return 0.0;
      end if;
    end loop;
    for i in C_OFFSETS'range loop
      v_width := C_DEG_ELECTRICAL_EDGE + C_OFFSETS((i + 1) mod C_EDGES_PER_CYCLE) - C_OFFSETS(i);
      if v_width < v_narrowest then
        v_narrowest := v_width;
      end if;
    end loop;
    return 0.5 * v_narrowest;
  end function;

  function is_stuck_level(
    constant level : in std_logic
  ) return boolean is
  begin
    return level = '0' or level = '1' or level = 'Z' or level = C_NOT_STUCK;
  end function;

  function stuck_error(
    constant name  : in string;
    constant level : in std_logic
  ) return string is
  begin
    return name & " must be '0', '1', 'Z' or '" & to_string(C_NOT_STUCK) & "' (not stuck), was '" & to_string(level) & "'.";
  end function;

  -- Why the signal configuration of config is invalid; "" if it is valid
  function signal_config_error(
    constant config     : in t_rotary_encoder_bfm_config;
    constant max_jitter : in real
  ) return string is
  begin
    if not is_stuck_level(config.a_stuck) then
      return stuck_error("a_stuck", config.a_stuck);
    elsif not is_stuck_level(config.b_stuck) then
      return stuck_error("b_stuck", config.b_stuck);
    elsif not is_stuck_level(config.z_stuck) then
      return stuck_error("z_stuck", config.z_stuck);
    elsif config.index_enabled and (config.index_width < 1 or config.index_width > C_EDGES_PER_CYCLE) then
      return "index_width must be 1 to " & to_string(C_EDGES_PER_CYCLE) & ", was " & to_string(config.index_width) & ".";
    elsif config.index_enabled and gray_index(config.index_state) < 0 then
      return "index_state must be a 2-bit state of '0'/'1', was " & to_string(config.index_state) & ".";
    elsif config.bounce_enabled and config.bounce_window <= 0 ns then
      return "bounce_window must be positive with bounce enabled, was " & to_string(config.bounce_window, ns) & ".";
    elsif not (config.jitter >= 0.0 and is_finite(config.jitter)) then
      return "jitter must be >= 0.0 and finite, was " & real_image(config.jitter) & ".";
    elsif config.jitter > 0.0 and config.jitter >= max_jitter then
      return "jitter must be below " & real_image(max_jitter) & " deg (half the narrowest state), was " &
             real_image(config.jitter) & ".";
    end if;
    return "";
  end function;

  -- The fields that signal_config_error() checks are equal (an invalid value is reported once, not at every edge)
  function is_same_signal_config(
    constant left_config  : in t_rotary_encoder_bfm_config;
    constant right_config : in t_rotary_encoder_bfm_config
  ) return boolean is
  begin
    return left_config.index_enabled = right_config.index_enabled and left_config.index_width = right_config.index_width and
           left_config.index_state = right_config.index_state and left_config.bounce_enabled = right_config.bounce_enabled and
           left_config.bounce_window = right_config.bounce_window and left_config.jitter = right_config.jitter and
           left_config.a_stuck = right_config.a_stuck and left_config.b_stuck = right_config.b_stuck and
           left_config.z_stuck = right_config.z_stuck;
  end function;

  -- Why the edge offsets of config are invalid; "" if they are valid
  function edge_offset_error(
    constant config : in t_rotary_encoder_bfm_config
  ) return string is
    function check(
      constant name   : in string;
      constant offset : in real
    ) return string is
    begin
      if abs(offset) < C_MAX_EDGE_OFFSET then
        return "";
      end if;
      return name & " must lie within (-" & real_image(C_MAX_EDGE_OFFSET) & ", " & real_image(C_MAX_EDGE_OFFSET) &
             ") deg, was " & real_image(offset) & ".";
    end function;
    constant C_A_RISE : string := check("a_rise_offset", config.a_rise_offset);
    constant C_A_FALL : string := check("a_fall_offset", config.a_fall_offset);
    constant C_B_RISE : string := check("b_rise_offset", config.b_rise_offset);
    constant C_B_FALL : string := check("b_fall_offset", config.b_fall_offset);
  begin
    return C_A_RISE & C_A_FALL & C_B_RISE & C_B_FALL;
  end function;

  -- Latches the geometry of config: cycles_per_rev, the edge offsets as boundary offsets in quanta and the jitter limit
  -- they give. Boundary offsets are indexed by the Gray index of the state below the boundary: 00 -> 10 is the A rise,
  -- 10 -> 11 the B rise, 11 -> 01 the A fall, 01 -> 00 the B fall.
  procedure latch_geometry(
    variable state  : inout t_rotary_encoder_state;
    constant config : in    t_rotary_encoder_bfm_config
  ) is
    constant C_OFFSETS : real_vector(0 to C_EDGES_PER_CYCLE - 1) := (config.a_rise_offset, config.b_rise_offset,
                                                                    config.a_fall_offset, config.b_fall_offset);
  begin
    state.cycles_per_rev := config.cycles_per_rev;
    for i in C_OFFSETS'range loop
      state.edge_offset(i) := integer(round(C_OFFSETS(i) * C_QUANTA_PER_DEG_ELECTRICAL));
    end loop;
    state.jitter_limit := jitter_limit(config);
  end procedure;

  -- Signal configuration for the next edge of a running motion: config if it is valid, otherwise
  -- the last valid one, with one TB_ERROR per invalid value. A motion is only started with a valid configuration, so this
  -- alerts only when the configuration changes during a motion (a VVC rotation re-reads it at every edge).
  procedure resolve_signal_config(
    variable state     : inout t_rotary_encoder_state;
    constant config    : in    t_rotary_encoder_bfm_config;
    variable effective : out   t_rotary_encoder_bfm_config;
    constant proc_call : in    string;
    constant msg       : in    string;
    constant scope     : in    string
  ) is
    constant C_ERROR : string := signal_config_error(config, state.jitter_limit);
  begin
    if C_ERROR'length = 0 then
      state.valid_config     := config;
      state.invalid_reported := false;
      effective              := config;
    else
      if not (state.invalid_reported and is_same_signal_config(config, state.invalid_config)) then
        alert(TB_ERROR, proc_call & "=> Invalid configuration during a motion: " & C_ERROR &
                        " The last valid configuration is kept." & add_msg_delimiter(msg), scope);
        state.invalid_reported := true;
        state.invalid_config   := config;
      end if;
      effective := state.valid_config;
    end if;
  end procedure;

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

  -- Offsets (quanta from the centre of position) of the boundaries of the state at position, with the latched edge
  -- offsets. The upper boundary is the one to position + 1.
  function upper_bound(
    constant state    : in t_rotary_encoder_state;
    constant position : in integer
  ) return integer is
  begin
    return C_HALF_K + state.edge_offset(logical_gray(state, position));
  end function;

  function lower_bound(
    constant state    : in t_rotary_encoder_state;
    constant position : in integer
  ) return integer is
  begin
    return -C_HALF_K + state.edge_offset(logical_gray(state, position - 1));
  end function;

  -- Moves (position, offset) into the state that contains the angle, using the latched edge offsets. On a boundary the
  -- shaft is in the lower state if below_wins, otherwise in the upper one.
  procedure settle(
    constant state      : in    t_rotary_encoder_state;
    variable position   : inout integer;
    variable offset     : inout integer;
    constant below_wins : in    boolean
  ) is
  begin
    loop
      if offset > upper_bound(state, position) or (offset = upper_bound(state, position) and not below_wins) then
        position := position + 1;
        offset   := offset - C_K;
      elsif offset < lower_bound(state, position) or (offset = lower_bound(state, position) and below_wins) then
        position := position - 1;
        offset   := offset + C_K;
      else
        exit;
      end if;
    end loop;
  end procedure;

  function angle_degrees(
    constant state : in t_rotary_encoder_state;
    constant angle : in t_angle
  ) return real is
  begin
    return (real(angle.position) + real(angle.offset) / C_K_REAL) * C_DEG_PER_REV / real(C_EDGES_PER_CYCLE * state.cycles_per_rev);
  end function;

  --==========================================================================================
  -- Outputs
  --==========================================================================================
  -- Index decision. Index cycle: positions index_position .. index_position + 3; q is the one whose state is
  -- index_state. Z is active at q .. q + index_width - 1, every 4 * cycles_per_rev positions. The callers pass a validated
  -- configuration; an invalid one gives an inactive Z.
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

  -- Level of Z for the logical index state z_active and index_inverted
  function z_level(
    constant z_active : in boolean;
    constant config   : in t_rotary_encoder_bfm_config
  ) return std_logic is
  begin
    if z_active xor config.index_inverted then
      return '1';
    else
      return '0';
    end if;
  end function;

  -- level, or the stuck level if stuck is not C_NOT_STUCK
  function output_level(
    constant level : in std_logic;
    constant stuck : in std_logic
  ) return std_logic is
  begin
    if stuck = C_NOT_STUCK then
      return level;
    else
      return stuck;
    end if;
  end function;

  -- Drives the state at state.position on A and B (states are pin levels); Z from the index decision and index_inverted.
  -- A stuck output drives its stuck level instead.
  procedure drive_outputs(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config
  ) is
  begin
    state.ab       := gray_state(logical_gray(state, state.position));
    state.z_active := index_active(state, state.position, config);
    encoder_if.a   <= output_level(state.ab(1), config.a_stuck);
    encoder_if.b   <= output_level(state.ab(0), config.b_stuck);
    encoder_if.z   <= output_level(z_level(state.z_active, config), config.z_stuck);
    state.a_stuck  := config.a_stuck;
    state.b_stuck  := config.b_stuck;
    state.z_stuck  := config.z_stuck;
  end procedure;

  -- Applies a changed stuck setting at the start of a command: a newly stuck output drives its stuck level, a released
  -- one the level of the current state. Outputs whose setting is unchanged are not driven, so a running bounce
  -- continues.
  procedure apply_stuck(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config
  ) is
  begin
    if config.a_stuck /= state.a_stuck then
      encoder_if.a  <= output_level(state.ab(1), config.a_stuck);
      state.a_stuck := config.a_stuck;
    end if;
    if config.b_stuck /= state.b_stuck then
      encoder_if.b  <= output_level(state.ab(0), config.b_stuck);
      state.b_stuck := config.b_stuck;
    end if;
    if config.z_stuck /= state.z_stuck then
      encoder_if.z  <= output_level(z_level(state.z_active, config), config.z_stuck);
      state.z_stuck := config.z_stuck;
    end if;
  end procedure;

  -- Schedules the bounce of channel after its edge to level: 2 * bounce_pulses
  -- toggles at sorted uniform positions (BOUNCE_RANDOM) or evenly spaced (BOUNCE_EVEN) in bounce_window, as transport
  -- transactions, ending at level. Toggles that round to the same resolution step are moved one step later, so the
  -- number of toggles is always exact.
  procedure schedule_bounce(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config;
    constant channel    : in    t_rotary_encoder_channel;
    constant level      : in    std_logic
  ) is
    constant C_TOGGLES      : positive := 2 * config.bounce_pulses; -- Each bounce pulse is two toggles
    constant C_WINDOW_UNITS : real     := time_to_units(config.bounce_window);
    variable v_pos          : real_vector(1 to C_TOGGLES);          -- Toggle positions as fractions of the window
    variable v_value        : real;
    variable v_j            : natural;
    variable v_delay        : time      := 0 ns;
    variable v_prev         : time      := 0 ns;
    variable v_level        : std_logic := level;
  begin
    for i in v_pos'range loop
      if config.bounce_placement = BOUNCE_RANDOM then
        uniform(state.seed1, state.seed2, v_pos(i)); -- In (0, 1)
      else
        v_pos(i) := real(i) / real(C_TOGGLES + 1);
      end if;
    end loop;
    -- Insertion sort (the even positions are sorted already)
    for i in 2 to C_TOGGLES loop
      v_value := v_pos(i);
      v_j     := i - 1;
      while v_j >= 1 and v_pos(v_j) > v_value loop
        v_pos(v_j + 1) := v_pos(v_j);
        v_j            := v_j - 1;
      end loop;
      v_pos(v_j + 1) := v_value;
    end loop;
    for i in v_pos'range loop
      v_delay := units_to_time(v_pos(i) * C_WINDOW_UNITS);
      if v_delay <= v_prev then
        v_delay := v_prev + C_RES; -- Strictly after the edge and after the previous toggle
      end if;
      v_level := not v_level;
      if channel = CHANNEL_A then
        encoder_if.a <= transport v_level after v_delay;
      else
        encoder_if.b <= transport v_level after v_delay;
      end if;
      v_prev := v_delay;
    end loop;
    state.bounce_pending := true;
    state.bounce_channel := channel;
    state.bounce_level   := level;
    state.bounce_end     := now + v_prev;
  end procedure;

  -- Ends a bounce that is still running: drives the settled level, which deletes the remaining toggles. settled is
  -- true when the channel was at its bounced level, i.e. it changes back now.
  procedure settle_bounce(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    variable settled    : out   boolean
  ) is
  begin
    settled := false;
    if state.bounce_pending and state.bounce_end > now then
      if state.bounce_channel = CHANNEL_A then
        settled      := encoder_if.a /= state.bounce_level;
        encoder_if.a <= transport state.bounce_level;
      else
        settled      := encoder_if.b /= state.bounce_level;
        encoder_if.b <= transport state.bounce_level;
      end if;
    end if;
    state.bounce_pending := false;
  end procedure;

  -- Cuts off a bounce that has not ended before the next edge: drives the settled level, which
  -- deletes the remaining toggles, and raises bounce_cut_severity once per command. settled is true when the channel was
  -- at its bounced level, i.e. it changes back now: the caller then waits one delta before the edge, so that the edge
  -- never changes in the same delta as the other channel (no illegal transition).
  procedure cut_bounce(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config;
    variable settled    : out   boolean;
    constant proc_call  : in    string;
    constant msg        : in    string;
    constant scope      : in    string
  ) is
    constant C_CUT : boolean := state.bounce_pending and state.bounce_end > now;
  begin
    settle_bounce(state, encoder_if, settled);
    if C_CUT then
      if not state.bounce_cut_reported then
        alert(config.bounce_cut_severity, proc_call & "=> Bounce of " & to_upper(to_string(state.bounce_channel)) &
                                          " cut off by the next edge at " & to_string(now, ns) &
                                          ": bounce_window is longer than the time to the next edge. Reported once per command." &
                                          add_msg_delimiter(msg), scope);
        state.bounce_cut_reported := true;
      end if;
    end if;
  end procedure;

  --==========================================================================================
  -- Motion engine
  --==========================================================================================
  -- Time at which the segment reaches whole edges plus rest quanta from its anchor: t0 + n * tpe_int + round(n *
  -- tpe_frac + r / K * tpe_res + extra_units), with n whole edges and 0 <= r < K. Computed from scratch for every edge,
  -- so nothing accumulates. whole is an integer value; rest may lie outside 0 .. K (boundaries with edge offsets).
  -- extra_units (resolution units, may be negative) is the jitter of the edge.
  function segment_time(
    constant state       : in t_rotary_encoder_state;
    constant whole       : in real;
    constant rest        : in real;
    constant extra_units : in real := 0.0
  ) return time is
    constant C_CARRY : real := floor_big(rest / C_K_REAL);
    constant C_N     : real := whole + C_CARRY;
    constant C_R     : real := rest - C_CARRY * C_K_REAL;
    constant C_UNITS : real := C_N * state.tpe_frac + C_R / C_K_REAL * state.tpe_res + extra_units;
    constant C_BASE  : time := state.seg_t0 + integer(C_N) * state.tpe_int;
  begin
    if C_UNITS >= 0.0 then
      return C_BASE + units_to_time(C_UNITS);
    else
      return C_BASE - units_to_time(-C_UNITS);
    end if;
  end function;

  -- End time of a move segment (seg_len quanta)
  function move_end_time(
    constant state : in t_rotary_encoder_state
  ) return time is
    constant C_WHOLE : real := floor_big(state.seg_len / C_K_REAL);
  begin
    return segment_time(state, C_WHOLE, state.seg_len - C_WHOLE * C_K_REAL);
  end function;

  -- Whole edges and rest (quanta) from the segment anchor to the next boundary in the segment direction
  procedure boundary_distance(
    constant state : in  t_rotary_encoder_state;
    variable whole : out real;
    variable rest  : out real
  ) is
  begin
    if state.seg_dir > 0 then
      whole := real(state.position - state.seg_p0);
      rest  := real(upper_bound(state, state.position) - state.seg_o0);
    else
      whole := real(state.seg_p0 - state.position);
      rest  := real(state.seg_o0 - lower_bound(state, state.position));
    end if;
  end procedure;

  -- Time and kind of the next event of the active motion: an edge (a boundary is reached), the end of the segment (end
  -- of a move or of a profile entry), or none (a rotation at 0 rpm without a profile). With jitter (amplitude in
  -- electrical degrees), the edge is displaced by jitter_u * jitter / 90 * time_per_edge; jitter_u is drawn once per
  -- edge, so the time does not change when the call is repeated. The displaced edge stays inside its segment: not
  -- before its start, and for a move not after its end. An edge at the end of a profile entry comes first.
  procedure next_motion_event(
    variable state      : inout t_rotary_encoder_state;
    constant jitter     : in    real;
    variable at_time    : out   time;
    variable next_event : out   t_next_event
  ) is
    variable v_whole : real;
    variable v_rest  : real;
    variable v_rand  : real;
    variable v_time  : time;
  begin
    if state.seg_moving then
      boundary_distance(state, v_whole, v_rest);
      if not state.seg_bounded or v_whole * C_K_REAL + v_rest <= state.seg_len then
        if jitter > 0.0 then
          if not state.jitter_drawn then
            uniform(state.seed1, state.seed2, v_rand); -- In (0, 1)
            state.jitter_u     := 2.0 * v_rand - 1.0;
            state.jitter_drawn := true;
          end if;
          v_time := segment_time(state, v_whole, v_rest, state.jitter_u * jitter / C_DEG_ELECTRICAL_EDGE * state.tpe_res);
          if v_time < state.seg_t0 then
            v_time := state.seg_t0;
          elsif state.seg_bounded and v_time > move_end_time(state) then
            v_time := move_end_time(state);
          end if;
        else
          v_time := segment_time(state, v_whole, v_rest);
        end if;
        if v_time <= state.seg_end then
          at_time    := v_time;
          next_event := NEXT_EDGE;
          return;
        end if;
      end if;
    end if;
    if state.seg_bounded then
      at_time    := move_end_time(state);
      next_event := NEXT_SEGMENT_END;
    elsif state.seg_end /= C_NO_END then
      at_time    := state.seg_end;
      next_event := NEXT_SEGMENT_END;
    else
      at_time    := C_NO_END;
      next_event := NEXT_NONE;
    end if;
  end procedure;

  -- Anchors a new segment at the current time and angle. moving is false at 0 rpm; bounded marks a move of length quanta;
  -- seg_end is the end of a profile entry or C_NO_END.
  procedure start_segment(
    variable state   : inout t_rotary_encoder_state;
    constant dir     : in    integer;
    constant moving  : in    boolean;
    constant bounded : in    boolean;
    constant length  : in    real;
    constant seg_end : in    time
  ) is
  begin
    state.seg_t0      := now;
    state.seg_p0      := state.position;
    state.seg_o0      := state.offset;
    state.seg_dir     := dir;
    state.seg_moving  := moving;
    state.seg_bounded := bounded;
    state.seg_len     := length;
    state.seg_end     := seg_end;
    if moving then
      state.rpm := real(dir) * state.speed_rpm;
    else
      state.rpm := 0.0;
    end if;
  end procedure;

  -- Angle at the current time, rounded once to a quantum
  impure function current_angle(
    constant state : in t_rotary_encoder_state
  ) return t_angle is
    variable v_distance : real;
    variable v_offset   : real;
  begin
    if not state.motion_active then
      return (state.position, state.offset);
    elsif not state.seg_moving then
      return (state.seg_p0, state.seg_o0);
    end if;
    v_distance := time_to_units(now - state.seg_t0) / state.tpe_res * C_K_REAL;
    if state.seg_bounded and v_distance > state.seg_len then
      v_distance := state.seg_len;
    end if;
    v_offset := round_big(real(state.seg_o0) + real(state.seg_dir) * v_distance -
                          real(state.position - state.seg_p0) * C_K_REAL);
    if v_offset > real(upper_bound(state, state.position)) then
      v_offset := real(upper_bound(state, state.position));
    elsif v_offset < real(lower_bound(state, state.position)) then
      v_offset := real(lower_bound(state, state.position));
    end if;
    return (state.position, integer(v_offset));
  end function;

  -- Ends a move segment at its end angle and the motion with it
  procedure end_segment(
    variable state : inout t_rotary_encoder_state
  ) is
  begin
    state.offset        := integer(real(state.seg_o0) + real(state.seg_dir) * state.seg_len -
                                   real(state.position - state.seg_p0) * C_K_REAL);
    state.motion_active := false;
    state.rpm           := 0.0;
  end procedure;

  -- Ends the active motion at the current angle
  procedure halt(
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
      state.jitter_drawn  := false;
    end if;
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

  -- time_per_edge in resolution units: from |rpm| (SPEED_RPM, rpm /= 0.0) or from time_per_edge
  function speed_units(
    constant form           : in t_rotary_encoder_speed_form;
    constant rpm            : in real;
    constant time_per_edge  : in time;
    constant cycles_per_rev : in integer
  ) return real is
  begin
    if form = SPEED_RPM then
      return C_UNITS_PER_MIN / edges_per_minute(abs(rpm), cycles_per_rev);
    else
      return time_to_units(time_per_edge);
    end if;
  end function;

  -- Why a speed is invalid; "" if it is valid. Moves need rpm > 0; rotations take a signed rpm, 0.0 included.
  function speed_error(
    constant form           : in t_rotary_encoder_speed_form;
    constant rpm            : in real;
    constant time_per_edge  : in time;
    constant cycles_per_rev : in integer;
    constant is_rotation    : in boolean
  ) return string is
  begin
    if form = SPEED_RPM then
      if is_rotation and not is_finite(rpm) then
        return "rpm must be finite, was " & real_image(rpm) & ".";
      elsif is_rotation and rpm = 0.0 then
        return "";
      elsif not is_rotation and not (rpm > 0.0 and is_finite(rpm)) then
        return "rpm must be positive and finite, was " & real_image(rpm) & ".";
      end if;
    elsif time_per_edge <= 0 ns then
      return "time_per_edge must be positive, was " & to_string(time_per_edge, ns) & ".";
    end if;
    if speed_units(form, rpm, time_per_edge, cycles_per_rev) > C_MAX_TPE then
      return "Speed too low: time_per_edge above " & real_image(C_MAX_TPE / C_UNITS_PER_SEC) & " s.";
    end if;
    return "";
  end function;

  -- Speed of the next segment: time_per_edge from |rpm| (SPEED_RPM) or from time_per_edge, split into whole resolution
  -- units and a fraction of a unit
  procedure set_speed(
    variable state         : inout t_rotary_encoder_state;
    constant form          : in    t_rotary_encoder_speed_form;
    constant rpm           : in    real;
    constant time_per_edge : in    time
  ) is
    constant C_TPE_RES : real := speed_units(form, rpm, time_per_edge, state.cycles_per_rev);
    variable v_den     : real := 0.0;
  begin
    if form = SPEED_RPM then
      v_den := edges_per_minute(abs(rpm), state.cycles_per_rev);
    end if;
    state.tpe_res := C_TPE_RES;
    if form = SPEED_RPM and v_den < C_MAX_DIVISOR and v_den = floor(v_den) then
      -- 1 min / den with an integer den: whole units and remainder exact in time arithmetic, so that the fraction does
      -- not carry the rounding error of the real time_per_edge (multiplied by the edge count in segment_time)
      state.tpe_int  := C_MINUTE / integer(v_den);
      state.tpe_frac := real((C_MINUTE - state.tpe_int * integer(v_den)) / C_RES) / v_den;
    else
      state.tpe_int  := units_to_time(floor_big(C_TPE_RES));
      state.tpe_frac := C_TPE_RES - floor_big(C_TPE_RES);
    end if;
    state.speed_rpm := C_UNITS_PER_MIN / (C_TPE_RES * real(C_EDGES_PER_CYCLE * state.cycles_per_rev));
  end procedure;

  -- Starts a rotation segment at the current time: signed rpm (SPEED_RPM, 0.0 = at rest) or time_per_edge in
  -- direction. seg_end is the end of the profile entry or C_NO_END.
  procedure start_rotation_segment(
    variable state         : inout t_rotary_encoder_state;
    constant form          : in    t_rotary_encoder_speed_form;
    constant rpm           : in    real;
    constant time_per_edge : in    time;
    constant direction     : in    t_rotary_encoder_direction;
    constant seg_end       : in    time
  ) is
  begin
    if form = SPEED_RPM and rpm = 0.0 then
      state.speed_rpm := 0.0;
      start_segment(state, 1, false, false, 0.0, seg_end);
    elsif form = SPEED_RPM then
      set_speed(state, form, rpm, time_per_edge);
      if rpm > 0.0 then
        start_segment(state, 1, true, false, 0.0, seg_end);
      else
        start_segment(state, -1, true, false, 0.0, seg_end);
      end if;
    else
      set_speed(state, form, rpm, time_per_edge);
      start_segment(state, dir_sign(direction), true, false, 0.0, seg_end);
    end if;
  end procedure;

  -- Starts entry profile_idx of the active profile at the current time
  procedure start_profile_entry(
    variable state : inout t_rotary_encoder_state
  ) is
  begin
    start_rotation_segment(state, SPEED_RPM, state.motion.profile(state.profile_idx), state.motion.time_per_edge,
                           state.motion.direction, state.profile_t0 + (state.profile_idx + 1) * state.motion.time_per_entry);
  end procedure;

  -- End of the current profile entry, at the current time: the next entry starts at the current angle (a speed change),
  -- or after the last entry the end behaviour applies. pass_end is true at the end of a pass.
  procedure advance_profile(
    variable state    : inout t_rotary_encoder_state;
    variable pass_end : out   boolean
  ) is
    constant C_ANGLE : t_angle := current_angle(state);
  begin
    pass_end := state.profile_idx + 1 >= state.motion.profile_length;
    if not pass_end then
      state.position    := C_ANGLE.position;
      state.offset      := C_ANGLE.offset;
      state.profile_idx := state.profile_idx + 1;
      start_profile_entry(state);
      return;
    end if;
    case state.motion.profile_end is
      when PROFILE_HOLD =>
        state.seg_end := C_NO_END; -- The speed of the last entry continues in the same segment
      when PROFILE_STOP =>
        halt(state);
      when PROFILE_REPEAT =>
        state.position    := C_ANGLE.position;
        state.offset      := C_ANGLE.offset;
        state.profile_idx := 0;
        state.profile_t0  := now;
        start_profile_entry(state);
    end case;
  end procedure;

  -- Executes the next event of the active motion at the current time: an edge (outputs, then the bounce of the changed
  -- channel unless that output is stuck) or the end of the segment. A bounce of the previous edge has been cut off by
  -- the caller (cut_bounce). executed is the kind of event; pass_end is true at the end of a profile pass.
  procedure motion_step(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant config     : in    t_rotary_encoder_bfm_config;
    variable executed   : out   t_next_event;
    variable pass_end   : out   boolean
  ) is
    variable v_time   : time;
    variable v_next   : t_next_event;
    variable v_old_ab : std_logic_vector(1 downto 0);
  begin
    pass_end := false;
    next_motion_event(state, config.jitter, v_time, v_next);
    if v_next = NEXT_EDGE then
      v_old_ab       := state.ab;
      state.position := state.position + state.seg_dir;
      -- On the boundary, in the state moved into
      if state.seg_dir > 0 then
        state.offset := lower_bound(state, state.position);
      else
        state.offset := upper_bound(state, state.position);
      end if;
      state.edges          := state.edges + 1;
      state.last_edge_time := now;
      state.jitter_drawn   := false;
      drive_outputs(state, encoder_if, config);
      if config.bounce_enabled and config.bounce_pulses > 0 then
        if v_old_ab(1) /= state.ab(1) then
          if config.a_stuck = C_NOT_STUCK then
            schedule_bounce(state, encoder_if, config, CHANNEL_A, state.ab(1));
          end if;
        elsif config.b_stuck = C_NOT_STUCK then
          schedule_bounce(state, encoder_if, config, CHANNEL_B, state.ab(0));
        end if;
      end if;
    elsif v_next = NEXT_SEGMENT_END then
      if state.seg_bounded then
        end_segment(state);
      else
        advance_profile(state, pass_end);
      end if;
    end if;
    executed := v_next;
  end procedure;

  -- Checks that the state is initialized and that config.zero_state is the one kept at init. Raises one
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

  -- Checks a command: is_call_valid; with latch also the geometry of config (cycles_per_rev, edge offsets); then the
  -- signal configuration against the jitter limit of the geometry the command uses. Raises one TB_ERROR and returns
  -- false otherwise.
  impure function is_command_valid(
    constant state     : in t_rotary_encoder_state;
    constant latch     : in boolean;
    constant proc_call : in string;
    constant msg       : in string;
    constant scope     : in string;
    constant config    : in t_rotary_encoder_bfm_config
  ) return boolean is
    constant C_OFFSET_ERROR : string := edge_offset_error(config);
    variable v_limit        : real;
  begin
    if not is_call_valid(state, proc_call, msg, scope, config) then
      return false;
    end if;
    v_limit := state.jitter_limit;
    if latch then
      if config.cycles_per_rev < 1 then
        alert(TB_ERROR, proc_call & "=> Failed. cycles_per_rev must be at least 1, was " & to_string(config.cycles_per_rev) &
                        "." & add_msg_delimiter(msg), scope);
        return false;
      elsif C_OFFSET_ERROR'length > 0 then
        alert(TB_ERROR, proc_call & "=> Failed. " & C_OFFSET_ERROR & add_msg_delimiter(msg), scope);
        return false;
      end if;
      v_limit := jitter_limit(config);
    end if;
    if signal_config_error(config, v_limit)'length > 0 then
      alert(TB_ERROR, proc_call & "=> Failed. " & signal_config_error(config, v_limit) & add_msg_delimiter(msg), scope);
      return false;
    end if;
    return true;
  end function;

  -- Distance in quanta from (position, offset) to the centre of the occurrence-th following position in direction dir whose
  -- state is target_gray. The current position is never counted. Every 4 consecutive positions hold
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
  -- procedures). A rotation that replaces a running rotation (speed change) keeps the geometry latched at its start.
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
    constant C_LATCH  : boolean := not (state.motion_active and state.motion.kind = MOTION_ROTATION and
                                        motion.kind = MOTION_ROTATION);
    constant C_DIR    : integer := dir_sign(motion.direction);
    constant C_IS_ROT : boolean := motion.kind = MOTION_ROTATION;
    variable v_cpr    : integer;
    variable v_length : real    := 0.0;
    variable v_angle  : t_angle;

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
    if not is_command_valid(state, C_LATCH, proc_call, msg, scope, config) then
      return;
    end if;
    if C_LATCH then
      v_cpr := config.cycles_per_rev;
    else
      v_cpr := state.cycles_per_rev;
    end if;
    if C_IS_ROT and motion.profile_length > 0 then
      if motion.profile_length > C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH then
        fail("The profile has " & to_string(motion.profile_length) & " entries, the maximum is " &
             to_string(C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH) & ".");
        return;
      elsif motion.time_per_entry <= 0 ns then
        fail("time_per_entry must be positive, was " & to_string(motion.time_per_entry, ns) & ".");
        return;
      end if;
      for i in 0 to motion.profile_length - 1 loop
        if speed_error(SPEED_RPM, motion.profile(i), motion.time_per_edge, v_cpr, true)'length > 0 then
          fail("Profile entry " & to_string(i) & ": " & speed_error(SPEED_RPM, motion.profile(i), motion.time_per_edge, v_cpr, true));
          return;
        end if;
      end loop;
    elsif speed_error(motion.speed_form, motion.rpm, motion.time_per_edge, v_cpr, C_IS_ROT)'length > 0 then
      fail(speed_error(motion.speed_form, motion.rpm, motion.time_per_edge, v_cpr, C_IS_ROT));
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
        v_length := round_big(motion.angle * real(v_cpr) * C_QUANTA_PER_DEG_ELECTRICAL);
      when MOTION_TO_STATE => -- Resolved here into an angle move from the angle at the current time
        if motion.num = 0 then
          fail("occurrence must be at least 1, was 0.");
          return;
        elsif gray_index(motion.target_state) < 0 then
          fail("target_state must be a 2-bit state of '0'/'1', was " & to_string(motion.target_state) & ".");
          return;
        end if;
        v_length := to_state_distance(state, v_angle.position, v_angle.offset, C_DIR, gray_index(motion.target_state),
                                      motion.num);
      when MOTION_ROTATION =>
        null;
    end case;
    if v_length > C_MAX_EXACT then
      fail("Move too long for one command.");
      return;
    end if;
    accepted := true;

    -- End a running motion at the current angle and latch the geometry
    state.position := v_angle.position;
    state.offset   := v_angle.offset;
    if C_LATCH then
      latch_geometry(state, config);
    end if;

    -- Signal configuration: valid from here on; a new command reports a bounce cut-off again
    state.valid_config        := config;
    state.invalid_reported    := false;
    state.bounce_cut_reported := false;
    state.jitter_drawn        := false;

    state.motion        := motion;
    state.edges         := 0;
    state.motion_active := true;
    if not C_IS_ROT then
      set_speed(state, motion.speed_form, motion.rpm, motion.time_per_edge);
      start_segment(state, C_DIR, true, true, v_length, C_NO_END);
    elsif motion.profile_length = 0 then
      start_rotation_segment(state, motion.speed_form, motion.rpm, motion.time_per_edge, motion.direction, C_NO_END);
    else
      state.profile_idx := 0;
      state.profile_t0  := now;
      start_profile_entry(state);
    end if;
  end procedure;

  -- Runs the active motion until it is at rest, or until deadline, where it stops at the reached angle (user-level
  -- procedures, which have no interrupt)
  procedure run_to_end(
    variable state      : inout t_rotary_encoder_state;
    signal   encoder_if : inout t_rotary_encoder_if;
    constant deadline   : in    time;
    constant proc_call  : in    string;
    constant msg        : in    string;
    constant scope      : in    string;
    constant config     : in    t_rotary_encoder_bfm_config
  ) is
    variable v_time    : time;
    variable v_next    : t_next_event;
    variable v_settled : boolean;
    variable v_pass    : boolean;
  begin
    while state.motion_active loop
      next_motion_event(state, config.jitter, v_time, v_next);
      if v_next = NEXT_NONE or v_time > deadline then
        if deadline > now then
          wait for deadline - now;
        end if;
        halt(state);
        exit;
      end if;
      if v_time > now then
        wait for v_time - now;
      elsif v_next = NEXT_EDGE and state.last_edge_time = now then
        wait for 0 ns; -- Two edges at one time step: one delta each, never both channels in one delta
      end if;
      if v_next = NEXT_EDGE then
        cut_bounce(state, encoder_if, config, v_settled, proc_call, msg, scope);
        if v_settled then
          wait for 0 ns; -- The bounced channel settles one delta before the edge
        end if;
      end if;
      motion_step(state, encoder_if, config, v_next, v_pass);
    end loop;
  end procedure;

  procedure log_motion(
    constant state        : in t_rotary_encoder_state;
    constant proc_call    : in string;
    constant msg          : in string;
    constant scope        : in string;
    constant msg_id_panel : in t_msg_id_panel;
    constant config       : in t_rotary_encoder_bfm_config
  ) is
  begin
    log(config.id_for_bfm, proc_call & "=> " & to_string(state.edges) & " edges, position " & to_string(state.position) &
                           ", angle " & real_image(angle_degrees(state, (state.position, state.offset))) & " deg." &
                           add_msg_delimiter(msg), scope, msg_id_panel);
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
  begin
    activate_motion(motion, proc_call, state, v_accepted, msg, scope, msg_id_panel, config);
    if not v_accepted then
      return;
    end if;
    apply_stuck(state, encoder_if, config);
    run_to_end(state, encoder_if, C_NO_END, proc_call, msg, scope, config);
    log_motion(state, proc_call, msg, scope, msg_id_panel, config);
  end procedure;

  -- Rotates for duration, then stops at once at the reached angle (rotary_encoder_rotate), and logs it
  procedure execute_rotation(
    constant motion       : in    t_rotary_encoder_motion;
    constant duration     : in    time;
    constant proc_call    : in    string;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string;
    constant msg_id_panel : in    t_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config
  ) is
    variable v_accepted : boolean;
  begin
    if duration <= 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. duration must be positive, was " & to_string(duration, ns) & "." &
                      add_msg_delimiter(msg), scope);
      return;
    end if;
    activate_motion(motion, proc_call, state, v_accepted, msg, scope, msg_id_panel, config);
    if not v_accepted then
      return;
    end if;
    apply_stuck(state, encoder_if, config);
    run_to_end(state, encoder_if, now + duration, proc_call, msg, scope, config);
    log_motion(state, proc_call, msg, scope, msg_id_panel, config);
  end procedure;

  -- Places the shaft at (position, offset) in zero time and drives the new state in one delta (set angle, jump). A
  -- running bounce is settled first, one delta earlier if its channel is at the bounced level.
  procedure place_shaft(
    variable state        : inout t_rotary_encoder_state;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant position     : in    integer;
    constant offset       : in    integer;
    constant proc_call    : in    string;
    constant msg          : in    string;
    constant scope        : in    string;
    constant msg_id_panel : in    t_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config
  ) is
    constant C_EDGES   : integer := position - state.position;
    variable v_settled : boolean;
  begin
    settle_bounce(state, encoder_if, v_settled);
    if v_settled then
      wait for 0 ns; -- The bounced channel settles one delta before the new state
    end if;
    state.position := position;
    state.offset   := offset;
    drive_outputs(state, encoder_if, config);
    if C_EDGES >= 0 then
      log(config.id_for_bfm, proc_call & "=> " & to_string(C_EDGES) & " edges forward in zero time, position " &
                             to_string(state.position) & ", angle " & real_image(angle_degrees(state, (state.position, state.offset))) &
                             " deg, AB " & to_string(state.ab) & "." & add_msg_delimiter(msg), scope, msg_id_panel);
    else
      log(config.id_for_bfm, proc_call & "=> " & to_string(-C_EDGES) & " edges reverse in zero time, position " &
                             to_string(state.position) & ", angle " & real_image(angle_degrees(state, (state.position, state.offset))) &
                             " deg, AB " & to_string(state.ab) & "." & add_msg_delimiter(msg), scope, msg_id_panel);
    end if;
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

  impure function rotary_encoder_linear_ramp(
    constant rpm_start   : in real;
    constant rpm_end     : in real;
    constant num_entries : in integer
  ) return real_vector is
    constant C_PROC_CALL : string := "rotary_encoder_linear_ramp(" & real_image(rpm_start) & ", " & real_image(rpm_end) & ", " &
                                     to_string(num_entries) & ")";
    constant C_EMPTY     : real_vector(0 to -1) := (others => 0.0);
    variable v_result    : real_vector(0 to num_entries - 1);
  begin
    if num_entries < 1 or not is_finite(rpm_start) or not is_finite(rpm_end) then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. num_entries must be at least 1 and the speeds finite. Returns an empty profile.",
            C_BFM_SCOPE);
      return C_EMPTY;
    elsif num_entries = 1 then
      return (0 => rpm_start);
    end if;
    for j in v_result'range loop
      v_result(j) := rpm_start + (rpm_end - rpm_start) * real(j) / real(num_entries - 1);
    end loop;
    return v_result;
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
    constant C_PROC_CALL    : string  := "rotary_encoder_init(start_angle " & real_image(config.start_angle) & ")";
    constant C_ZERO_GRAY    : integer := gray_index(config.zero_state);
    constant C_JITTER_LIMIT : real    := jitter_limit(config);
    constant C_SIGNAL_ERROR : string  := signal_config_error(config, C_JITTER_LIMIT);
    constant C_OFFSET_ERROR : string  := edge_offset_error(config);
    variable v_quanta       : real;
    variable v_offset       : integer;
  begin
    if config.cycles_per_rev < 1 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. cycles_per_rev must be at least 1, was " & to_string(config.cycles_per_rev) &
                      "." & add_msg_delimiter(msg), scope);
      return;
    elsif C_ZERO_GRAY < 0 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. zero_state must be a 2-bit state of '0'/'1', was " & to_string(config.zero_state) &
                      "." & add_msg_delimiter(msg), scope);
      return;
    elsif C_OFFSET_ERROR'length > 0 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. " & C_OFFSET_ERROR & add_msg_delimiter(msg), scope);
      return;
    elsif C_SIGNAL_ERROR'length > 0 then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. " & C_SIGNAL_ERROR & add_msg_delimiter(msg), scope);
      return;
    end if;
    v_quanta := round_big(config.start_angle * real(config.cycles_per_rev) * C_QUANTA_PER_DEG_ELECTRICAL);
    if not is_finite(config.start_angle) or abs(v_quanta) > C_MAX_EXACT then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. start_angle out of range." & add_msg_delimiter(msg), scope);
      return;
    end if;

    state.initialized    := true;
    state.zero_gray      := C_ZERO_GRAY;    -- Angle 0 is the centre of the zero state, kept from here on
    latch_geometry(state, config);
    state.motion_active  := false;
    state.seg_moving     := false;
    state.seg_bounded    := false;
    state.seg_end        := C_NO_END;
    state.profile_idx    := 0;
    state.motion         := C_ROTARY_ENCODER_MOTION_DEFAULT;
    state.edges          := 0;
    state.rpm            := 0.0;
    state.last_edge_time := time'low;
    state.seed1          := config.rand_seed1;
    state.seed2          := config.rand_seed2;
    state.jitter_drawn   := false;
    state.jitter_u       := 0.0;
    state.bounce_pending := false; -- drive_outputs() deletes toggles still scheduled from before
    state.bounce_cut_reported := false;
    state.valid_config        := config;
    state.invalid_reported    := false;
    state.position       := 0;
    normalize(state.position, v_quanta, v_offset); -- The start angle as given
    settle(state, state.position, v_offset, false);  -- In the state above a boundary, also with edge offsets
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
    -- Only the sub-edge offset changes; the position (the state the shaft is in) and the outputs stay
    state.offset := 0;
    log(config.id_for_bfm, C_PROC_CALL & "=> position " & to_string(state.position) & ", angle " &
                           real_image(angle_degrees(state, (state.position, state.offset))) & " deg." & add_msg_delimiter(msg),
        scope, msg_id_panel);
  end procedure;

  procedure rotary_encoder_rotate(
    constant rpm          : in    real;
    constant duration     : in    time;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind       := MOTION_ROTATION;
    v_motion.speed_form := SPEED_RPM;
    v_motion.rpm        := rpm;
    execute_rotation(v_motion, duration, "rotary_encoder_rotate(" & speed_string(v_motion) & ", " & to_string(duration, ns) & ")",
                     state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_rotate(
    constant direction     : in    t_rotary_encoder_direction;
    constant time_per_edge : in    time;
    constant duration      : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind          := MOTION_ROTATION;
    v_motion.direction     := direction;
    v_motion.speed_form    := SPEED_TIME_PER_EDGE;
    v_motion.time_per_edge := time_per_edge;
    execute_rotation(v_motion, duration, "rotary_encoder_rotate(" & to_upper(to_string(direction)) & ", " & speed_string(v_motion) &
                     ", " & to_string(duration, ns) & ")", state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_rotate(
    constant profile        : in    real_vector;
    constant time_per_entry : in    time;
    constant profile_end    : in    t_rotary_encoder_profile_end;
    constant duration       : in    time;
    variable state          : inout t_rotary_encoder_state;
    constant msg            : in    string;
    signal   encoder_if     : inout t_rotary_encoder_if;
    constant scope          : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel   : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config         : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_CALL : string := "rotary_encoder_rotate(profile of " & to_string(profile'length) & " entries, " &
                                     to_string(time_per_entry, ns) & " per entry, " & to_upper(to_string(profile_end)) & ", " &
                                     to_string(duration, ns) & ")";
    variable v_motion    : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    if profile'length = 0 or profile'length > C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. The profile must have 1 to " & to_string(C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH) &
                      " entries." & add_msg_delimiter(msg), scope);
      return;
    end if;
    v_motion.kind           := MOTION_ROTATION;
    v_motion.speed_form     := SPEED_RPM;
    v_motion.profile_length := profile'length;
    for i in 0 to profile'length - 1 loop
      v_motion.profile(i) := profile(profile'low + i);
    end loop;
    v_motion.time_per_entry := time_per_entry;
    v_motion.profile_end    := profile_end;
    execute_rotation(v_motion, duration, C_PROC_CALL, state, msg, encoder_if, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_set_angle(
    constant angle        : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_CALL : string := "rotary_encoder_set_angle(" & real_image(angle) & " deg)";
    variable v_quanta    : real    := 0.0;
    variable v_position  : integer := 0;
    variable v_offset    : integer;
  begin
    if not is_command_valid(state, true, C_PROC_CALL, msg, scope, config) then
      return;
    elsif state.motion_active then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. Not allowed while a motion is active." & add_msg_delimiter(msg), scope);
      return;
    end if;
    if is_finite(angle) then
      v_quanta := round_big(angle * real(config.cycles_per_rev) * C_QUANTA_PER_DEG_ELECTRICAL);
    end if;
    if not is_finite(angle) or abs(v_quanta) > C_MAX_EXACT then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. angle must be finite and within +-" &
                      real_image(C_MAX_EXACT / (real(config.cycles_per_rev) * C_QUANTA_PER_DEG_ELECTRICAL)) & " deg." & add_msg_delimiter(msg),
            scope);
      return;
    end if;
    latch_geometry(state, config);
    apply_stuck(state, encoder_if, config);
    -- On a boundary the shaft stays on the side of the old angle
    normalize(v_position, v_quanta, v_offset);
    settle(state, v_position, v_offset, v_quanta > real(state.position) * C_K_REAL + real(state.offset));
    if v_position = state.position and v_offset = state.offset then
      log(config.id_for_bfm, C_PROC_CALL & "=> Already at this angle, nothing changes. Position " & to_string(state.position) & "." &
                             add_msg_delimiter(msg), scope, msg_id_panel);
      return;
    end if;
    place_shaft(state, encoder_if, v_position, v_offset, C_PROC_CALL, msg, scope, msg_id_panel, config);
  end procedure;

  procedure rotary_encoder_jump_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_CALL : string  := "rotary_encoder_jump_edges(" & to_upper(to_string(direction)) & ", " & to_string(num_edges) & ")";
    constant C_DIR       : integer := dir_sign(direction);
    variable v_position  : integer;
    variable v_offset    : integer;
  begin
    if not is_command_valid(state, true, C_PROC_CALL, msg, scope, config) then
      return;
    elsif state.motion_active then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. Not allowed while a motion is active." & add_msg_delimiter(msg), scope);
      return;
    elsif abs(real(state.position) + real(C_DIR) * real(num_edges)) > real(C_MAX_POSITION) then
      alert(TB_ERROR, C_PROC_CALL & "=> Failed. The position after the jump would lie beyond +-" & to_string(C_MAX_POSITION) & "." &
                      add_msg_delimiter(msg), scope);
      return;
    end if;
    latch_geometry(state, config);
    apply_stuck(state, encoder_if, config);
    if num_edges = 0 then
      log(config.id_for_bfm, C_PROC_CALL & "=> 0 edges, nothing changes. Position " & to_string(state.position) & "." &
                             add_msg_delimiter(msg), scope, msg_id_panel);
      return;
    end if;
    -- The sub-edge fraction is kept; on a boundary the shaft stays on the side of the old angle
    v_position := state.position + C_DIR * num_edges;
    v_offset   := state.offset;
    settle(state, v_position, v_offset, C_DIR > 0);
    place_shaft(state, encoder_if, v_position, v_offset, C_PROC_CALL, msg, scope, msg_id_panel, config);
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
    constant C_PROC_CALL : string := "rotary_encoder_run_motion()";
    variable v_config    : t_rotary_encoder_bfm_config;
    variable v_time      : time;
    variable v_next      : t_next_event;
    variable v_settled   : boolean;
    variable v_pass      : boolean;
  begin
    if state.motion_active then
      -- The signal configuration of this call (re-read by the VVC at every call), or the last valid one
      resolve_signal_config(state, config, v_config, C_PROC_CALL, msg, scope);
      -- A changed stuck setting shows at once: at the start of a motion and before the next edge
      apply_stuck(state, encoder_if, v_config);
    end if;
    while state.motion_active loop
      next_motion_event(state, v_config.jitter, v_time, v_next);
      if v_next = NEXT_NONE then
        wait on interrupt; -- A rotation at 0 rpm without a profile: nothing happens until the next request
        event := MOTION_INTERRUPTED;
        return;
      elsif v_time > now then
        wait on interrupt for v_time - now;
        if now < v_time then
          event := MOTION_INTERRUPTED;
          return;
        end if;
      elsif v_next = NEXT_EDGE and state.last_edge_time = now then
        wait on interrupt for 0 ns; -- One delta per edge. An interrupt at the edge time comes after the edge
      end if;
      if v_next = NEXT_EDGE then
        cut_bounce(state, encoder_if, v_config, v_settled, C_PROC_CALL, msg, scope);
        if v_settled then
          wait on interrupt for 0 ns; -- The bounced channel settles one delta before the edge
        end if;
      end if;
      motion_step(state, encoder_if, v_config, v_next, v_pass);
      if v_next = NEXT_EDGE then
        event := MOTION_EDGE;
        return;
      elsif v_pass and state.motion_active then
        event := MOTION_PROFILE_PASS;
        return;
      end if;
    end loop;
    event := MOTION_DONE;
  end procedure;

  procedure rotary_encoder_halt_motion(
    variable state : inout t_rotary_encoder_state
  ) is
  begin
    halt(state);
  end procedure;

end package body rotary_encoder_bfm_pkg;
