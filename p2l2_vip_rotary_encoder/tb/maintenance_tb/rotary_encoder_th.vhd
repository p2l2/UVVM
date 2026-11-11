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
-- Description   : Test harness of rotary_encoder_vvc_tb:
--                 - i1_rotary_encoder_vvc (idx 1, default configuration) on enc1_if
--                 - i2_rotary_encoder_vvc (idx 2, default configuration) on enc2_if, for the concurrency tests
--                 - i3_rotary_encoder_vvc (idx 3, start angle 30 deg) on enc3_if, for the power-up tests
--                 - one logger process per interface, recording every change in shared_th_event_log (ids 1 to 3).
--                   Each checker is armed at the first event, i.e. the VVC's initialization.
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library p2l2_vip_rotary_encoder;
context p2l2_vip_rotary_encoder.vvc_context;

use work.rotary_encoder_tb_pkg.all;
use work.rotary_encoder_th_pkg.all;

entity rotary_encoder_th is
end entity rotary_encoder_th;

architecture struct of rotary_encoder_th is

  -- Instance 3: power-up through the generic at 30 deg (position 7) with zero state 00, i.e. a start angle that is not a
  -- state centre and a zero state other than the default
  constant C_ENC3_START_ANGLE : real                         := 30.0;
  constant C_ENC3_ZERO_STATE  : std_logic_vector(1 downto 0) := "00";

  function enc3_config return t_rotary_encoder_bfm_config is
    variable v_config : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
  begin
    v_config.start_angle := C_ENC3_START_ANGLE;
    v_config.zero_state  := C_ENC3_ZERO_STATE;
    return v_config;
  end function;

  constant C_ENC3_CONFIG : t_rotary_encoder_bfm_config := enc3_config;

  signal enc1_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);
  signal enc2_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);
  signal enc3_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);

  -- Records one event and arms the checker at the first one
  procedure log_event(
    constant id      : in positive;
    signal enc_if    : in t_rotary_encoder_if;
    variable v_armed : inout boolean) is
  begin
    shared_th_event_log.add(id, enc_if, enc_if.a'event, enc_if.b'event, enc_if.z'event);
    if not v_armed then
      shared_th_event_log.arm(id, enc_if);
      v_armed := true;
    end if;
  end procedure;

begin

  -----------------------------------------------------------------------------
  -- Instantiate the concurrent procedure that initializes UVVM
  -----------------------------------------------------------------------------
  i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

  -----------------------------------------------------------------------------
  -- Rotary encoder VVCs
  -----------------------------------------------------------------------------
  i1_rotary_encoder_vvc : entity p2l2_vip_rotary_encoder.rotary_encoder_vvc
    generic map(
      GC_INSTANCE_IDX => 1
    )
    port map(
      rotary_encoder_vvc_if => enc1_if
    );

  i2_rotary_encoder_vvc : entity p2l2_vip_rotary_encoder.rotary_encoder_vvc
    generic map(
      GC_INSTANCE_IDX => 2
    )
    port map(
      rotary_encoder_vvc_if => enc2_if
    );

  i3_rotary_encoder_vvc : entity p2l2_vip_rotary_encoder.rotary_encoder_vvc
    generic map(
      GC_INSTANCE_IDX              => 3,
      GC_ROTARY_ENCODER_BFM_CONFIG => C_ENC3_CONFIG
    )
    port map(
      rotary_encoder_vvc_if => enc3_if
    );

  -----------------------------------------------------------------------------
  -- Event loggers: every change on A, B or Z, from time 0
  -----------------------------------------------------------------------------
  p_logger_1 : process is
    variable v_armed : boolean := false;
  begin
    wait on enc1_if.a, enc1_if.b, enc1_if.z;
    log_event(1, enc1_if, v_armed);
  end process p_logger_1;

  p_logger_2 : process is
    variable v_armed : boolean := false;
  begin
    wait on enc2_if.a, enc2_if.b, enc2_if.z;
    log_event(2, enc2_if, v_armed);
  end process p_logger_2;

  p_logger_3 : process is
    variable v_armed : boolean := false;
  begin
    wait on enc3_if.a, enc3_if.b, enc3_if.z;
    log_event(3, enc3_if, v_armed);
  end process p_logger_3;

end architecture struct;
