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

use work.rotary_encoder_bfm_pkg.all;

--==========================================================================================
--==========================================================================================
package transaction_pkg is

  --==========================================================================================
  -- t_operation
  -- - VVC and BFM operations
  --==========================================================================================
  type t_operation is (
    -- UVVM common
    NO_OPERATION,
    AWAIT_COMPLETION,
    AWAIT_ANY_COMPLETION,
    ENABLE_LOG_MSG,
    DISABLE_LOG_MSG,
    FLUSH_COMMAND_QUEUE,
    FETCH_RESULT,
    INSERT_DELAY,
    TERMINATE_CURRENT_COMMAND,
    -- VVC local
    MOVE_EDGES,
    MOVE_ANGLE,
    MOVE_TO_STATE,
    CENTER_STATE,
    SET_ANGLE,
    JUMP_EDGES,
    GET_STATUS,
    START_ROTATION,
    SET_SPEED,
    STOP_ROTATION
  );

  -- Constants for the maximum sizes to use in this VVC. Can be modified in adaptations_pkg.
  alias C_VVC_CMD_PROFILE_MAX_LENGTH is C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH;
  alias C_VVC_CMD_STRING_MAX_LENGTH  is C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH;
  alias C_VVC_MAX_INSTANCE_NUM       is C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM;

  --==========================================================================================
  -- Transaction info types, constants and global signal
  --==========================================================================================

  -- VVC Meta
  type t_vvc_meta is record
    msg     : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    cmd_idx : integer;
  end record t_vvc_meta;

  constant C_VVC_META_DEFAULT : t_vvc_meta := (
    msg     => (others => ' '),
    cmd_idx => -1
  );

  -- NOTE:
  --   If compound transaction is needed see example usage in Bitvis VIP SBI.
  --   If sub transaction is needed see example usage in Bitvis VIP Avalon-MM.
  -- Base transaction
  type t_base_transaction is record
    operation           : t_operation;
    direction           : t_rotary_encoder_direction;   -- Moves, jump; rotation with time_per_edge
    num_edges           : natural;                      -- Moves, jump
    target_state        : std_logic_vector(1 downto 0); -- Move to state, pin levels
    occurrence          : natural;                      -- Move to state
    angle               : real;                         -- Angle move, set angle
    rpm                 : real;                         -- Speed in rpm; 0.0 when given as time_per_edge
    time_per_edge       : time;                         -- Speed as time per edge; 0 ns when given in rpm
    profile_length      : natural;                      -- Speed profile entries; 0 for a constant speed
    time_per_entry      : time;
    profile_end         : t_rotary_encoder_profile_end;
    edges               : natural;                      -- Edges emitted by a move (0 for other commands); valid at
                                                        -- COMPLETED or FAILED
    status              : t_rotary_encoder_status;      -- Encoder state at the end of the command (for a status read: its
                                                        -- result); valid at COMPLETED or FAILED
    vvc_meta            : t_vvc_meta;
    transaction_status  : t_transaction_status;
  end record t_base_transaction;

  constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
    operation           => NO_OPERATION,
    direction           => FORWARD,
    num_edges           => 0,
    target_state        => "00",
    occurrence          => 0,
    angle               => 0.0,
    rpm                 => 0.0,
    time_per_edge       => 0 ns,
    profile_length      => 0,
    time_per_entry      => 0 ns,
    profile_end         => PROFILE_HOLD,
    edges               => 0,
    status              => (0, 0.0, "00", false, false, 0.0),
    vvc_meta            => C_VVC_META_DEFAULT,
    transaction_status  => INACTIVE
  );

  -- Transaction group
  type t_transaction_group is record
    bt : t_base_transaction;
  end record t_transaction_group;

  constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
    bt => C_BASE_TRANSACTION_SET_DEFAULT
  );

  -- Global vvc_transaction_info trigger signal
  type t_rotary_encoder_transaction_trigger_array is array (natural range <>) of std_logic;
  signal global_rotary_encoder_vvc_transaction_trigger : t_rotary_encoder_transaction_trigger_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => '0');

  -- Shared vvc_transaction_info info variable
  type t_rotary_encoder_transaction_group_array is array (natural range <>) of t_transaction_group;
  shared variable shared_rotary_encoder_vvc_transaction_info : t_rotary_encoder_transaction_group_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => C_TRANSACTION_GROUP_DEFAULT);

end package transaction_pkg;
