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
  type t_rotary_encoder_index_mode is (INDEX_GATED_QUARTER, INDEX_GATED_HALF, INDEX_UNGATED);
  type t_rotary_encoder_bounce_placement is (BOUNCE_RANDOM, BOUNCE_EVEN);
  type t_rotary_encoder_profile_end is (PROFILE_HOLD, PROFILE_STOP, PROFILE_REPEAT);

  -- Configuration record to be assigned in the test harness.
  type t_rotary_encoder_bfm_config is record
    cycles_per_rev      : integer;                      -- Quadrature cycles per revolution
    edges_per_detent    : integer;                      -- Edges between two detents
    detents_enabled     : boolean;                      -- Moves end on detents
    rest_state          : std_logic_vector(1 downto 0); -- Logical AB state at a detent
    start_angle         : real;                         -- Power-up angle in degrees
    direction_swap      : boolean;                      -- A and B exchanged
    ab_inverted         : boolean;                      -- A and B driven inverted
    index_enabled       : boolean;                      -- Z pulses at the index position
    index_mode          : t_rotary_encoder_index_mode;  -- Width of the index pulse
    index_state         : std_logic_vector(1 downto 0); -- Logical AB state during a gated index pulse
    index_position      : integer;                      -- Index cycle, in edges from position 0
    index_inverted      : boolean;                      -- Z driven inverted
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
    default_snap_rpm    : real;                         -- Speed of the detent snap after a stop
    off_detent_severity : t_alert_level;                -- A move starts away from a detent
    bounce_cut_severity : t_alert_level;                -- Bounce cut off by the next edge
    id_for_bfm          : t_msg_id;                     -- The message ID used as a general message ID in the BFM
    id_for_bfm_wait     : t_msg_id;                     -- The message ID used for logging waits in the BFM
  end record t_rotary_encoder_bfm_config;

  -- Define the default value for the BFM config
  constant C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT : t_rotary_encoder_bfm_config := (
    cycles_per_rev      => 20,
    edges_per_detent    => 4,
    detents_enabled     => true,
    rest_state          => "11",
    start_angle         => 0.0,
    direction_swap      => false,
    ab_inverted         => false,
    index_enabled       => true,
    index_mode          => INDEX_GATED_QUARTER,
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
    default_snap_rpm    => 60.0,
    off_detent_severity => TB_WARNING,
    bounce_cut_severity => TB_WARNING,
    id_for_bfm          => ID_BFM,
    id_for_bfm_wait     => ID_BFM_WAIT
  );

  -- Result of rotary_encoder_get_status() and of the VVC's rotary_encoder_get_status() via fetch_result()
  type t_rotary_encoder_status is record
    position     : integer;                      -- Edges from position 0
    angle        : real;                         -- Degrees, sub-edge precision
    ab           : std_logic_vector(1 downto 0); -- Logical state (before swap and inversion)
    index_active : boolean;                      -- Logical Z (before inversion)
    is_rotating  : boolean;
    rpm          : real;                         -- Signed current speed, 0.0 when not rotating
  end record t_rotary_encoder_status;

  --==========================================================================================
  -- BFM procedures
  --==========================================================================================
  --<USER_INPUT> Insert BFM procedure declarations here, e.g. read and write operations

  function init_rotary_encoder_if_signals(
    constant dummy : t_void
  ) return t_rotary_encoder_if;

end package rotary_encoder_bfm_pkg;

package body rotary_encoder_bfm_pkg is

  --<USER_INPUT> Insert BFM procedure implementation here.

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

end package body rotary_encoder_bfm_pkg;
