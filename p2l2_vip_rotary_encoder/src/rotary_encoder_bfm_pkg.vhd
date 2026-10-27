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
  constant C_BFM_SCOPE : string := "ROTARY_ENCODER BFM";

  -- Optional interface record for BFM signals
  -- type t_rotary_encoder_if is record
    --<USER_INPUT> Insert all BFM signals here
    -- Example:
    -- cs      : std_logic;          -- to dut
    -- addr    : unsigned;           -- to dut
    -- rena    : std_logic;          -- to dut
    -- wena    : std_logic;          -- to dut
    -- wdata   : std_logic_vector;   -- to dut
    -- ready   : std_logic;          -- from dut
    -- rdata   : std_logic_vector;   -- from dut
  -- end record t_rotary_encoder_if;

  -- Configuration record to be assigned in the test harness.
  type t_rotary_encoder_bfm_config is record
    --<USER_INPUT> Insert all BFM config parameters here
    -- Example:
    id_for_bfm               : t_msg_id; -- To replace default log msg IDs. <USER_INPUT> Adapt name to msg IDs used in this BFM
    -- id_for_bfm_wait          : t_msg_id; -- To replace default log msg IDs. <USER_INPUT> Adapt name to msg IDs used in this BFM
    -- id_for_bfm_poll          : t_msg_id; -- To replace default log msg IDs. <USER_INPUT> Adapt name to msg IDs used in this BFM
    -- max_wait_cycles          : natural;
    -- max_wait_cycles_severity : t_alert_level;
    -- clock_period             : time;
  end record t_rotary_encoder_bfm_config;

  -- Define the default value for the BFM config
  constant C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT : t_rotary_encoder_bfm_config := (
    --<USER_INPUT> Insert defaults for all BFM config parameters here
    -- Example:
    id_for_bfm               => ID_BFM      --<USER_INPUT> Adapt name and ID to msg IDs used in this BFM
    -- id_for_bfm_wait          => ID_BFM_WAIT, --<USER_INPUT> Adapt name and ID to msg IDs used in this BFM
    -- id_for_bfm_poll          => ID_BFM_POLL, --<USER_INPUT> Adapt name and ID to msg IDs used in this BFM
    -- max_wait_cycles          => 1000,
    -- max_wait_cycles_severity => failure,
    -- clock_period             => C_UNDEFINED_TIME
  );

  --==========================================================================================
  -- BFM procedures
  --==========================================================================================
  --<USER_INPUT> Insert BFM procedure declarations here, e.g. read and write operations
  -- It is recommended to also have an init function which sets the BFM signals to their default state

end package rotary_encoder_bfm_pkg;

package body rotary_encoder_bfm_pkg is

  --<USER_INPUT> Insert BFM procedure implementation here.

end package body rotary_encoder_bfm_pkg;
