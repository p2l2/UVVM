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

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

-- Include Verification IPs
library p2l2_vip_rotary_encoder;
context p2l2_vip_rotary_encoder.vvc_context;

use work.rotary_encoder_tb_pkg.all;
use work.rotary_encoder_th_pkg.all;

--hdlregression:tb
-- Test case entity
-- VVC TB: p_main sends commands to the VVCs in rotary_encoder_th and checks the events recorded by the loggers there
-- with the decoder checker in rotary_encoder_tb_pkg. Test case IDs refer to doc/rotary_encoder_vvc_tb_arch.md.
entity rotary_encoder_vvc_tb is
  generic(
    GC_TESTCASE : string := "UVVM"
  );
end entity;

-- Test case architecture
architecture func of rotary_encoder_vvc_tb is

  constant C_SCOPE : string := C_TB_SCOPE_DEFAULT;

  -- vvc_instances_execute_commands
  constant C_DELAY   : time := 100 ns; -- insert_delay in every instance
  constant C_TIMEOUT : time := 1 us;   -- await_completion; well above C_DELAY

  -- Debug only (waveform): the current test step, i.e. the last header written with log_step()
  signal dbg_step : string(1 to C_DBG_STEP_LENGTH) := dbg_text("");

begin

  -----------------------------------------------------------------------------
  -- Instantiate test harness
  -----------------------------------------------------------------------------
  i_test_harness : entity work.rotary_encoder_th;

  p_main : process is
    -- Logs a test-step header and shows it in the waveform as dbg_step
    procedure log_step(
      constant msg : in string) is
    begin
      log(ID_LOG_HDR, msg, C_SCOPE);
      dbg_step <= dbg_text(msg);
    end procedure;
  begin
    -- To avoid that log files from different test cases (run in separate simulations) overwrite each other.
    set_log_file_name(GC_TESTCASE & "_Log.txt");
    set_alert_file_name(GC_TESTCASE & "_Alert.txt");

    -- Wait for UVVM to finish initialization
    await_uvvm_initialization(VOID);

    -- Print the configuration to the log
    report_global_ctrl(VOID);
    report_msg_id_panel(VOID);

    -- Verbosity control
    enable_log_msg(ALL_MESSAGES);
    disable_log_msg(ID_POS_ACK);
    disable_log_msg(ROTARY_ENCODER_VVCT, ALL_INSTANCES, ID_CMD_INTERPRETER_WAIT);
    disable_log_msg(ROTARY_ENCODER_VVCT, ALL_INSTANCES, ID_CMD_EXECUTOR_WAIT);

    log(ID_LOG_HDR_LARGE, "Simulating " & GC_TESTCASE & ", resolution " & to_string(C_RESOLUTION), C_SCOPE);

    --============================================================================================================================
    if GC_TESTCASE = "vvc_instances_execute_commands" then
      -- Testbench plumbing: the three VVC instances accept and execute a command; the loggers are connected
      log_step("VVC instances execute insert_delay");
      for i in 1 to C_NUM_LOGS loop
        insert_delay(ROTARY_ENCODER_VVCT, i, C_DELAY, "plumbing");
      end loop;
      for i in 1 to C_NUM_LOGS loop
        await_completion(ROTARY_ENCODER_VVCT, i, C_TIMEOUT, "plumbing");
      end loop;
      check_value(now >= C_DELAY, ERROR, "insert_delay took effect", C_SCOPE);

      log_step("No interface driver yet, so the event logs are empty");
      for i in 1 to C_NUM_LOGS loop
        check_value(shared_th_event_log.count(i), 0, ERROR, "events of encoder " & to_string(i), C_SCOPE);
        check_checker(shared_th_event_log, i, 0, "skeleton VVC");
      end loop;

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
