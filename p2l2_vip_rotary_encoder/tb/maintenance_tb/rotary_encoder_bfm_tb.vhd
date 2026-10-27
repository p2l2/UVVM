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

  signal enc_if : t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID);

begin

  -- Event logger: every change on A, B or Z. The checker is armed by p_main.
  p_logger : process is
  begin
    wait on enc_if.a, enc_if.b, enc_if.z;
    shared_th_event_log.add(C_ID, enc_if, enc_if.a'event, enc_if.b'event, enc_if.z'event);
  end process p_logger;

  p_main : process is
    variable v_start : time;

    -- TC_000: drives the interface directly (testbench self-test, no BFM procedure involved)
    procedure drive(
      constant a : in std_logic;
      constant b : in std_logic;
      constant z : in std_logic) is
    begin
      enc_if <= (a, b, z);
      wait for 10 ns;
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
      wait for 10 ns;
      check_value(shared_th_event_log.count(C_ID), 2, ERROR, "two log entries", C_SCOPE);
      check_value(shared_th_event_log.get(C_ID, 0).time_stamp, shared_th_event_log.get(C_ID, 1).time_stamp, ERROR,
                  "same time stamp", C_SCOPE);
      check_value(shared_th_event_log.num_edges(C_ID), 2, ERROR, "two edges", C_SCOPE);
      check_checker(shared_th_event_log, C_ID, 0, "forward and back");

      log(ID_LOG_HDR, "TC_000: check_no_event", C_SCOPE);
      v_start := now;
      wait for 100 ns;
      check_no_event(shared_th_event_log, C_ID, v_start, now, "quiet interval");
      drive('0', '1', '0');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "check_no_event must detect the event");
      check_no_event(shared_th_event_log, C_ID, v_start, now, "event expected to be detected");

      log(ID_LOG_HDR, "TC_000: ideal_edge_time against exact values (floor to the resolution)", C_SCOPE);
      check_edge_time(0 ns, 1, 60, 20, 6250 us, 6250 us);
      check_edge_time(0 ns, 2, 60, 20, 18750 us, 18750 us);
      check_edge_time(0 ns, 1, 7, 20, 53 ms + 571 us + 428 ns + 571 ps, 53 ms + 571 us + 428 ns + 571 ps + 428 fs);
      check_edge_time(0 ns, 1000, 7, 20, 107 sec + 89 ms + 285 us + 714 ns + 285 ps,
                      107 sec + 89 ms + 285 us + 714 ns + 285 ps + 714 fs);
      check_edge_time(0 ns, 3, 6000, 20, 312500 ns, 312500 ns);
      check_edge_time(0 ns, 7, 6000, 1024, 15 us + 869 ns + 140 ps, 15 us + 869 ns + 140 ps + 625 fs);
      check_edge_time(1 us, 1, 60, 20, 6251 us, 6251 us);

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
