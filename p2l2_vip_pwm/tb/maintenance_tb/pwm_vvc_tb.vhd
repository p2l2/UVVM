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
library p2l2_vip_pwm;
context p2l2_vip_pwm.vvc_context;

use work.pwm_tb_pkg.all;
use work.pwm_th_pkg.all;

--hdlregression:tb
-- Test case entity
-- VVC TB: p_main sends commands to the VVCs in pwm_th. The generation tests compare the edges recorded by the edge
-- logger in pwm_th with the reference model in pwm_tb_pkg or with hard-coded edge lists. Test case IDs refer to
-- doc/pwm_vvc_reqs.md.
entity pwm_vvc_tb is
  generic(
    GC_TESTCASE : string := "UVVM"
  );
end entity;

-- Test case architecture
architecture func of pwm_vvc_tb is

  constant C_SCOPE      : string := C_TB_SCOPE_DEFAULT;
  constant C_RESOLUTION : time   := std.env.resolution_limit;

  constant C_GEN : natural := 1;        -- i1_pwm_vvc, GENERATOR on pwm_loop
  constant C_OBS : natural := 2;        -- i2_pwm_vvc, OBSERVER on pwm_loop

  type t_time_array is array (natural range <>) of time;

  signal pwm_inject : std_logic := 'Z';

begin

  -----------------------------------------------------------------------------
  -- Instantiate test harness
  -----------------------------------------------------------------------------
  i_test_harness : entity work.pwm_th
    port map(
      pwm_inject => pwm_inject
    );

  p_main : process
    alias pwm_loop is << signal i_test_harness.pwm_loop : std_logic >>;

    variable v_config  : t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT;
    variable v_start   : time;
    variable v_level   : std_logic;
    variable v_edge    : t_edge;
    variable v_edges_a : t_edge_array(0 to 199);
    variable v_edges_b : t_edge_array(0 to 199);
    variable v_differs : boolean;

    -- Lets the last assignment to pwm_loop take effect and the edge logger record it
    procedure settle is
    begin
      wait for 0 ns;
      wait for 0 ns;
    end procedure;

    -- Rounds units * count / resolution to whole resolution units, half a unit up (integer arithmetic, independent of
    -- the real arithmetic in the BFM)
    function rounded_units(
      constant period     : time;
      constant count      : natural;
      constant resolution : positive) return time is
    begin
      return ((2 * (period / C_RESOLUTION) * count + resolution) / (2 * resolution)) * C_RESOLUTION;
    end function;

    -- Writes v_config to the generator VVC
    procedure set_config is
    begin
      shared_pwm_vvc_config(C_GEN).bfm_config := v_config;
    end procedure;

    -- Starts a new edge log at the current time
    procedure start_test is
    begin
      settle;
      v_level := pwm_loop;
      shared_th_edge_log.clear;
      v_start := now;
    end procedure;

    procedure check_time(
      constant delay : time;
      constant msg   : string) is
    begin
      check_value(now, v_start + delay, ERROR, "time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    procedure check_idle(
      constant msg : string) is
    begin
      settle;
      check_value(pwm_loop, tb_idle_value(v_config.polarity, v_config.idle_level), MATCH_EXACT, ERROR, "idle: " & msg, C_SCOPE,
                  ID_SEQUENCER_SUB);
    end procedure;

    -- The logged edges against the reference model for 'params', generated from v_start with v_config
    procedure check_expected(
      constant params : t_period_param_array;
      constant msg    : string) is
    begin
      settle;
      check_edges(shared_th_edge_log, expected_edges(v_start, v_level, params, v_config.alignment,
                                                     tb_active_level(v_config.polarity),
                                                     tb_idle_value(v_config.polarity, v_config.idle_level)), msg, C_SCOPE);
    end procedure;

    -- The logged edges against a hard-coded list, relative to v_start
    procedure check_edges_rel(
      constant times  : t_time_array;
      constant levels : std_logic_vector;
      constant msg    : string) is
      variable v_expected : t_edge_array(times'range);
    begin
      settle;
      for i in times'range loop
        v_expected(i) := (v_start + times(i), levels(levels'low + i - times'low));
      end loop;
      check_edges(shared_th_edge_log, v_expected, msg, C_SCOPE);
    end procedure;

    -- pwm_generate() on the VVC: completion time, idle level and edges
    procedure test_generate(
      constant period      : time;
      constant active_time : time;
      constant num_periods : positive;
      constant msg         : string) is
    begin
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, period, active_time, num_periods, msg);
      await_completion(PWM_VVCT, C_GEN, num_periods * period + 1 us, msg);
      check_time(num_periods * period, "completion, " & msg);
      check_idle(msg);
      check_expected(repeat_period(period, active_time, num_periods), msg);
    end procedure;

    -- A rejected command (the alert is expected by the caller): no time used and the line unchanged
    procedure check_rejected(
      constant vvc_instance_idx : natural;
      constant msg              : string) is
    begin
      await_completion(PWM_VVCT, vvc_instance_idx, 1 us, msg);
      check_time(0 ns, "no time used, " & msg);
      settle;
      check_value(shared_th_edge_log.count, 0, ERROR, "line unchanged: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- Waits until 'delay' after v_start
    procedure wait_until_rel(
      constant delay : time) is
    begin
      wait for v_start + delay - now;
    end procedure;

    procedure save_edges(
      variable edges : out t_edge_array) is
    begin
      for i in 0 to minimum(shared_th_edge_log.count, edges'length) - 1 loop
        v_edge := shared_th_edge_log.get(i);
        edges(edges'low + i) := (v_edge.time_stamp - v_start, v_edge.level);
      end loop;
    end procedure;

    -- TC-202: pwm_generate() with jitter, checked against the ideal edges; the edges relative to v_start in 'edges'
    procedure test_jitter(
      variable edges : out t_edge_array;
      constant msg   : string) is
    begin
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 100 ns, 50 ns, 50, msg);
      await_completion(PWM_VVCT, C_GEN, 6 us, msg);
      check_time(50 * 100 ns, "completion, " & msg);
      settle;
      check_jittered_edges(shared_th_edge_log, expected_edges(v_start, v_level, repeat_period(100 ns, 50 ns, 50),
                                                              v_config.alignment, tb_active_level(v_config.polarity),
                                                              tb_idle_value(v_config.polarity, v_config.idle_level)),
                           v_config.jitter, msg, C_SCOPE);
      save_edges(edges);
    end procedure;

    constant C_DUTY_SEQUENCE : t_period_param_array := ((10 ns, 5 ns), (10 ns, 0 ns), (10 ns, 5 ns), (10 ns, 10 ns), (10 ns, 5 ns));
    constant C_UPDATE_POINTS : t_time_array         := (10 ns, 50 ns, 99 ns);

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
    disable_log_msg(PWM_VVCT, ALL_INSTANCES, ID_CMD_INTERPRETER_WAIT);
    disable_log_msg(PWM_VVCT, ALL_INSTANCES, ID_CMD_EXECUTOR_WAIT);

    log(ID_LOG_HDR_LARGE, "Simulating " & GC_TESTCASE & ", resolution " & to_string(C_RESOLUTION), C_SCOPE);

    --============================================================================================================================
    if GC_TESTCASE = "TC_003" then
      -- REQ-003 (VVC part): invalid parameters; arch 7.1: run-state errors and wrong role
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-003: invalid generation parameters, line unchanged", C_SCOPE);
      start_test;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "period 0 ns");
      pwm_generate(PWM_VVCT, C_GEN, 0 ns, 0 ns, 1, "period 0 ns");
      check_rejected(C_GEN, "period 0 ns");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "period -10 ns");
      pwm_generate(PWM_VVCT, C_GEN, -10 ns, 0 ns, 1, "period -10 ns");
      check_rejected(C_GEN, "period -10 ns");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "active_time -1 ns");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, -1 ns, 1, "active_time -1 ns");
      check_rejected(C_GEN, "active_time -1 ns");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "active_time > period");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 11 ns, 1, "active_time > period");
      check_rejected(C_GEN, "active_time > period");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "num_periods 0");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 3 ns, 0, "num_periods 0");
      check_rejected(C_GEN, "num_periods 0");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "duty -0.1");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, -0.1, 1, "duty -0.1");
      check_rejected(C_GEN, "duty -0.1");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "duty 1.1");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 1.1, 1, "duty 1.1");
      check_rejected(C_GEN, "duty 1.1");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "resolution 0");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 0, 0, 1, "resolution 0");
      check_rejected(C_GEN, "resolution 0");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "count -1");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, -1, 4, 1, "count -1");
      check_rejected(C_GEN, "count -1");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "count > resolution");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 5, 4, 1, "count > resolution");
      check_rejected(C_GEN, "count > resolution");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "start, period 0 ns");
      pwm_start(PWM_VVCT, C_GEN, 0 ns, 0 ns, "start, period 0 ns");
      check_rejected(C_GEN, "start, period 0 ns");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "start, duty 1.5");
      pwm_start(PWM_VVCT, C_GEN, 10 ns, 1.5, "start, duty 1.5");
      check_rejected(C_GEN, "start, duty 1.5");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "start, count 2/1");
      pwm_start(PWM_VVCT, C_GEN, 10 ns, 2, 1, "start, count 2/1");
      check_rejected(C_GEN, "start, count 2/1");
      v_config.jitter := -1 ns;
      set_config;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "generate, jitter -1 ns");
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 3 ns, 1, "generate, jitter -1 ns");
      check_rejected(C_GEN, "generate, jitter -1 ns");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "start, jitter -1 ns");
      pwm_start(PWM_VVCT, C_GEN, 10 ns, 3 ns, "start, jitter -1 ns");
      check_rejected(C_GEN, "start, jitter -1 ns");
      v_config.jitter := 0 ns;
      set_config;

      log(ID_LOG_HDR, "TC-003: update, stop and abort without a continuous generation", C_SCOPE);
      start_test;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "update, no run");
      pwm_update(PWM_VVCT, C_GEN, 10 ns, 3 ns, "update, no run");
      check_rejected(C_GEN, "update, no run");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "stop, no run");
      pwm_stop(PWM_VVCT, C_GEN, "stop, no run");
      check_rejected(C_GEN, "stop, no run");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "abort, no run");
      pwm_abort(PWM_VVCT, C_GEN, "abort, no run");
      check_rejected(C_GEN, "abort, no run");

      log(ID_LOG_HDR, "TC-003: errors during a continuous generation leave it unchanged", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "continuous");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "start while running");
      pwm_start(PWM_VVCT, C_GEN, 50 ns, 10 ns, "start while running");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "generate while running");
      pwm_generate(PWM_VVCT, C_GEN, 50 ns, 10 ns, 2, "generate while running");
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "update, period 0 ns");
      pwm_update(PWM_VVCT, C_GEN, 0 ns, 0 ns, "update, period 0 ns");
      await_completion(PWM_VVCT, C_GEN, 1 us, "errors while running");
      check_time(0 ns, "errors while running");
      -- A negative jitter set during the run: one TB_ERROR at the next boundary, the previous config is kept
      wait_until_rel(50 ns);
      v_config.jitter := -1 ns;
      set_config;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "jitter -1 ns during the run");
      wait_until_rel(350 ns);
      v_config.jitter := 0 ns;
      set_config;
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(400 ns, "stop");
      check_expected(repeat_period(100 ns, 30 ns, 4), "errors while running");

      log(ID_LOG_HDR, "TC-003: generator commands on an OBSERVER instance", C_SCOPE);
      start_test;
      increment_expected_alerts_and_stop_limit(ERROR, 5, "wrong role");
      pwm_generate(PWM_VVCT, C_OBS, 10 ns, 3 ns, 1, "generate on observer");
      pwm_start(PWM_VVCT, C_OBS, 10 ns, 3 ns, "start on observer");
      pwm_update(PWM_VVCT, C_OBS, 10 ns, 3 ns, "update on observer");
      pwm_stop(PWM_VVCT, C_OBS, "stop on observer");
      pwm_abort(PWM_VVCT, C_OBS, "abort on observer");
      check_rejected(C_OBS, "wrong role");

      log(ID_LOG_HDR, "TC-003: insert_delay() in clock cycles", C_SCOPE);
      start_test;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "insert_delay in clock cycles");
      insert_delay(PWM_VVCT, C_GEN, 10, "insert_delay in clock cycles");
      check_rejected(C_GEN, "insert_delay in clock cycles");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_007" then
      -- REQ-008 (VVC part): idle level from time 0 and after generate, stop and abort
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-007: idle level from time 0", C_SCOPE);
      check_value(now, 0 ns, ERROR, "still at time 0", C_SCOPE);
      check_value(pwm_loop, '0', MATCH_EXACT, ERROR, "idle at time 0", C_SCOPE);
      check_value(shared_th_edge_log.count, 1, ERROR, "one event at time 0", C_SCOPE);
      v_edge := shared_th_edge_log.get(0);
      check_value(v_edge.time_stamp, 0 ns, ERROR, "event at time 0", C_SCOPE);
      check_value(v_edge.level, '0', MATCH_EXACT, ERROR, "event at time 0: idle level", C_SCOPE);

      for polarity in t_pwm_polarity loop
        for idle_level in t_pwm_idle_level loop
          log(ID_LOG_HDR, "TC-007: " & to_string(polarity) & ", " & to_string(idle_level), C_SCOPE);
          v_config.polarity   := polarity;
          v_config.idle_level := idle_level;
          set_config;
          test_generate(10 ns, 3 ns, 1, "after generate, " & to_string(polarity) & ", " & to_string(idle_level));

          start_test;
          pwm_start(PWM_VVCT, C_GEN, 10 ns, 3 ns, "start");
          wait_until_rel(25 ns);
          pwm_stop(PWM_VVCT, C_GEN, "stop");
          await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
          check_time(30 ns, "stop");
          check_idle("after stop, " & to_string(polarity) & ", " & to_string(idle_level));

          start_test;
          pwm_start(PWM_VVCT, C_GEN, 10 ns, 3 ns, "start");
          wait_until_rel(21 ns);
          pwm_abort(PWM_VVCT, C_GEN, "abort");
          await_completion(PWM_VVCT, C_GEN, 1 us, "abort");
          check_time(21 ns, "abort");
          check_idle("after abort, " & to_string(polarity) & ", " & to_string(idle_level));
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_008" then
      -- REQ-009, REQ-010: bounded generation starts at once and ends after k periods; REQ-002 and REQ-007 on the VVC
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-008: k=1 and k=5, first edge when the command starts", C_SCOPE);
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 3 ns, 1, "k=1");
      check_time(0 ns, "command queued and started");
      await_completion(PWM_VVCT, C_GEN, 1 us, "k=1");
      check_time(10 ns, "k=1 completion");
      check_idle("k=1");
      check_edges_rel((0 ns, 3 ns), "10", "k=1");
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 3 ns, 5, "k=5");
      await_completion(PWM_VVCT, C_GEN, 1 us, "k=5");
      check_time(50 ns, "k=5 completion");
      check_idle("k=5");
      check_edges_rel((0 ns, 3 ns, 10 ns, 13 ns, 20 ns, 23 ns, 30 ns, 33 ns, 40 ns, 43 ns), "1010101010", "k=5");

      for alignment in t_pwm_alignment loop
        log(ID_LOG_HDR, "TC-008: T 10 ns / 1 us, t_on 1 unit, T/4, T/2, T-1 unit, " & to_string(alignment), C_SCOPE);
        v_config.alignment := alignment;
        set_config;
        for i in 0 to 1 loop
          test_generate(10 ns * 100 ** i, C_RESOLUTION, 3, to_string(alignment) & ", t_on 1 unit");
          test_generate(10 ns * 100 ** i, 10 ns * 100 ** i / 4, 3, to_string(alignment) & ", t_on T/4");
          test_generate(10 ns * 100 ** i, 10 ns * 100 ** i / 2, 3, to_string(alignment) & ", t_on T/2");
          test_generate(10 ns * 100 ** i, 10 ns * 100 ** i - C_RESOLUTION, 3, to_string(alignment) & ", t_on T-1 unit");
        end loop;
        test_generate(10 ns, 0 ns, 3, to_string(alignment) & ", 0 %");
        check_value(shared_th_edge_log.count, 0, ERROR, "0 %: no edges", C_SCOPE);
        test_generate(10 ns, 10 ns, 3, to_string(alignment) & ", 100 %");
        check_value(shared_th_edge_log.count, 2, ERROR, "100 %: only the edges from and to idle", C_SCOPE);
      end loop;
      v_config.alignment := LEFT_ALIGNED;
      set_config;

      log(ID_LOG_HDR, "TC-008: duty 0.25 and count 64/256 as t_on 25 ns, duty 1/3 and count 1/3 rounded", C_SCOPE);
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 100 ns, 0.25, 2, "duty 0.25");
      await_completion(PWM_VVCT, C_GEN, 1 us, "duty 0.25");
      check_expected(repeat_period(100 ns, 25 ns, 2), "duty 0.25");
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 100 ns, 64, 256, 2, "count 64/256");
      await_completion(PWM_VVCT, C_GEN, 1 us, "count 64/256");
      check_expected(repeat_period(100 ns, 25 ns, 2), "count 64/256");
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 1.0 / 3.0, 1, "duty 1/3");
      await_completion(PWM_VVCT, C_GEN, 1 us, "duty 1/3");
      check_expected(repeat_period(10 ns, rounded_units(10 ns, 1, 3), 1), "duty 1/3");
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 1, 3, 1, "count 1/3");
      await_completion(PWM_VVCT, C_GEN, 1 us, "count 1/3");
      check_expected(repeat_period(10 ns, rounded_units(10 ns, 1, 3), 1), "count 1/3");

      log(ID_LOG_HDR, "TC-008: two queued commands, the second starts when the first completes", C_SCOPE);
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 10 ns, 3 ns, 2, "first");
      pwm_generate(PWM_VVCT, C_GEN, 20 ns, 5 ns, 1, "second");
      await_completion(PWM_VVCT, C_GEN, 1 us, "queued");
      check_time(40 ns, "queued completion");
      check_expected(((10 ns, 3 ns), (10 ns, 3 ns), (20 ns, 5 ns)), "queued");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_009" then
      -- REQ-011, REQ-013, REQ-201: continuous generation while other commands run, stop at the next boundary
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-009: 100 periods continuous, other commands in between, stop mid-period", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "continuous");
      await_completion(PWM_VVCT, C_GEN, 1 us, "start");
      check_time(0 ns, "start completes when the first period begins");
      insert_delay(PWM_VVCT, C_GEN, 1234 ns, "executor free during the run");
      await_completion(PWM_VVCT, C_GEN, 2 us, "insert_delay");
      check_time(1234 ns, "insert_delay");
      for i in 0 to 2 loop
        pwm_update(PWM_VVCT, C_GEN, 100 ns, 30 ns, "same values");
        await_completion(PWM_VVCT, C_GEN, 1 us, "update");
        check_time(1300 ns + i * 100 ns, "update completes at the next boundary");
      end loop;
      insert_delay(PWM_VVCT, C_OBS, 500 ns, "other instance");
      await_completion(PWM_VVCT, C_OBS, 1 us, "other instance");
      check_time(2000 ns, "other instance");
      wait_until_rel(99 * 100 ns + 50 ns);
      pwm_stop(PWM_VVCT, C_GEN, "stop mid-period");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(100 * 100 ns, "stop completes at the end of the period");
      check_idle("after stop");
      check_expected(repeat_period(100 ns, 30 ns, 100), "100 periods");

      for alignment in t_pwm_alignment loop
        log(ID_LOG_HDR, "TC-009: stop 80 % into the third period, " & to_string(alignment), C_SCOPE);
        v_config.alignment := alignment;
        set_config;
        start_test;
        pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "continuous");
        wait_until_rel(280 ns);
        pwm_stop(PWM_VVCT, C_GEN, "stop");
        await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
        check_time(300 ns, "stop, " & to_string(alignment));
        check_idle("after stop, " & to_string(alignment));
        check_expected(repeat_period(100 ns, 30 ns, 3), "stop, " & to_string(alignment));
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_010" then
      -- REQ-012, REQ-201: updates and config changes take effect at the next period boundary
      --============================================================================================================================
      for i in C_UPDATE_POINTS'range loop
        log(ID_LOG_HDR, "TC-010: update " & to_string(C_UPDATE_POINTS(i), ns) & " into a 100 ns period", C_SCOPE);
        start_test;
        pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "start");
        wait_until_rel(100 ns + C_UPDATE_POINTS(i));
        pwm_update(PWM_VVCT, C_GEN, 60 ns, 20 ns, "update");
        await_completion(PWM_VVCT, C_GEN, 1 us, "update");
        check_time(200 ns, "update completes at the next boundary");
        wait_until_rel(230 ns);
        pwm_stop(PWM_VVCT, C_GEN, "stop");
        await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
        check_time(260 ns, "stop");
        check_expected(((100 ns, 30 ns), (100 ns, 30 ns), (60 ns, 20 ns)), "update at " & to_string(C_UPDATE_POINTS(i), ns));
      end loop;

      log(ID_LOG_HDR, "TC-010: start and update with duty and count", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 0.5, "start, duty 0.5");
      wait_until_rel(150 ns);
      pwm_update(PWM_VVCT, C_GEN, 50 ns, 1, 5, "update, count 1/5");
      pwm_update(PWM_VVCT, C_GEN, 50 ns, 0.8, "update, duty 0.8");
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "duty and count");
      check_time(300 ns, "duty and count");
      check_expected(((100 ns, 50 ns), (100 ns, 50 ns), (50 ns, 10 ns), (50 ns, 40 ns)), "duty and count");

      log(ID_LOG_HDR, "TC-010: 50 % -> 0 % -> 50 % -> 100 % -> 50 % with updates, no glitches", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 10 ns, 5 ns, "start");
      for i in 1 to C_DUTY_SEQUENCE'high loop
        pwm_update(PWM_VVCT, C_GEN, C_DUTY_SEQUENCE(i).period, C_DUTY_SEQUENCE(i).active_time, "update");
      end loop;
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "duty sequence");
      check_time(50 ns, "duty sequence");
      check_expected(C_DUTY_SEQUENCE, "duty sequence");
      check_edges_rel((0 ns, 5 ns, 20 ns, 25 ns, 30 ns, 45 ns), "101010", "duty sequence, hard-coded");

      log(ID_LOG_HDR, "TC-010: polarity changed 40 % into period 2 takes effect in period 3", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "start");
      wait_until_rel(140 ns);
      v_config.polarity := ACTIVE_LOW;
      set_config;
      wait_until_rel(240 ns);
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(300 ns, "stop");
      check_idle("active-low idle");
      check_edges_rel((0 ns, 30 ns, 100 ns, 130 ns, 230 ns), "10101", "polarity change");
      v_config.polarity := ACTIVE_HIGH;
      set_config;
      -- Back to the active-high idle level
      test_generate(10 ns, 3 ns, 1, "back to active-high");

      log(ID_LOG_HDR, "TC-010: two alignment changes in period 2, the last one (right) takes effect in period 3", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "start");
      wait_until_rel(120 ns);
      v_config.alignment := CENTER_ALIGNED;
      set_config;
      wait_until_rel(160 ns);
      v_config.alignment := RIGHT_ALIGNED;
      set_config;
      wait_until_rel(250 ns);
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(300 ns, "stop");
      check_edges_rel((0 ns, 30 ns, 100 ns, 130 ns, 270 ns, 300 ns), "101010", "two alignment changes");
      v_config.alignment := LEFT_ALIGNED;
      set_config;

      log(ID_LOG_HDR, "TC-010: polarity changed and changed back in period 2: no change", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "start");
      wait_until_rel(120 ns);
      v_config.polarity := ACTIVE_LOW;
      set_config;
      wait_until_rel(140 ns);
      v_config.polarity := ACTIVE_HIGH;
      set_config;
      wait_until_rel(250 ns);
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(300 ns, "stop");
      check_expected(repeat_period(100 ns, 30 ns, 3), "polarity changed back");

      log(ID_LOG_HDR, "TC-010: update and alignment change in the same period take effect together", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 30 ns, "start");
      wait_until_rel(150 ns);
      v_config.alignment := CENTER_ALIGNED;
      set_config;
      pwm_update(PWM_VVCT, C_GEN, 50 ns, 10 ns, "update");
      await_completion(PWM_VVCT, C_GEN, 1 us, "update");
      check_time(200 ns, "update");
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_time(250 ns, "stop");
      check_edges_rel((0 ns, 30 ns, 100 ns, 130 ns, 220 ns, 230 ns), "101010", "update and alignment change");
      v_config.alignment := LEFT_ALIGNED;
      set_config;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_011" then
      -- REQ-014: abort drives the idle level at once
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-011: abort mid-pulse", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 50 ns, "start");
      wait_until_rel(120 ns);
      pwm_abort(PWM_VVCT, C_GEN, "abort mid-pulse");
      await_completion(PWM_VVCT, C_GEN, 1 us, "abort");
      check_time(120 ns, "abort completes at once");
      check_idle("after abort mid-pulse");
      check_edges_rel((0 ns, 50 ns, 100 ns, 120 ns), "1010", "abort mid-pulse");

      log(ID_LOG_HDR, "TC-011: abort mid-gap", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 50 ns, "start");
      wait_until_rel(170 ns);
      pwm_abort(PWM_VVCT, C_GEN, "abort mid-gap");
      await_completion(PWM_VVCT, C_GEN, 1 us, "abort");
      check_time(170 ns, "abort mid-gap");
      check_edges_rel((0 ns, 50 ns, 100 ns, 150 ns), "1010", "abort mid-gap");

      log(ID_LOG_HDR, "TC-011: abort at 100 %", C_SCOPE);
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 100 ns, "start 100 %");
      wait_until_rel(150 ns);
      pwm_abort(PWM_VVCT, C_GEN, "abort at 100 %");
      await_completion(PWM_VVCT, C_GEN, 1 us, "abort");
      check_time(150 ns, "abort at 100 %");
      check_edges_rel((0 ns, 150 ns), "10", "abort at 100 %");

      log(ID_LOG_HDR, "TC-011: terminate_current_command during pwm_generate() aborts it", C_SCOPE);
      start_test;
      pwm_generate(PWM_VVCT, C_GEN, 100 ns, 50 ns, 10, "generate 10 periods");
      wait_until_rel(230 ns);
      terminate_current_command(PWM_VVCT, C_GEN, "terminate");
      await_completion(PWM_VVCT, C_GEN, 1 us, "terminated");
      check_time(230 ns, "terminated");
      check_idle("after terminate");
      check_edges_rel((0 ns, 50 ns, 100 ns, 150 ns, 200 ns, 230 ns), "101010", "terminate");

      log(ID_LOG_HDR, "TC-011: generation works again after abort and terminate", C_SCOPE);
      test_generate(100 ns, 50 ns, 2, "after abort");
      start_test;
      pwm_start(PWM_VVCT, C_GEN, 100 ns, 50 ns, "start after abort");
      wait_until_rel(250 ns);
      pwm_stop(PWM_VVCT, C_GEN, "stop");
      await_completion(PWM_VVCT, C_GEN, 1 us, "stop");
      check_expected(repeat_period(100 ns, 50 ns, 3), "start after abort");

      for alignment in t_pwm_alignment loop
        log(ID_LOG_HDR, "TC-011: abort in the active pulse of period 2, " & to_string(alignment), C_SCOPE);
        v_config.alignment := alignment;
        set_config;
        start_test;
        pwm_start(PWM_VVCT, C_GEN, 100 ns, 40 ns, "start");
        -- Active pulse of period 2: left [100, 140), right [160, 200), center [130, 170)
        case alignment is
          when LEFT_ALIGNED   => wait_until_rel(120 ns);
          when RIGHT_ALIGNED  => wait_until_rel(180 ns);
          when CENTER_ALIGNED => wait_until_rel(150 ns);
        end case;
        v_start := now;
        pwm_abort(PWM_VVCT, C_GEN, "abort");
        await_completion(PWM_VVCT, C_GEN, 1 us, "abort");
        check_time(0 ns, "abort, " & to_string(alignment));
        check_idle("abort, " & to_string(alignment));
        v_edge := shared_th_edge_log.get(shared_th_edge_log.count - 1);
        check_value(v_edge.time_stamp, now, ERROR, "last edge at the abort, " & to_string(alignment), C_SCOPE);
        check_value(v_edge.level, '0', MATCH_EXACT, ERROR, "last edge to idle, " & to_string(alignment), C_SCOPE);
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_202" then
      -- REQ-203 (VVC part): config changes between commands take effect for the next command; jitter per run
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-202: polarity changed between two commands", C_SCOPE);
      test_generate(100 ns, 30 ns, 2, "active-high");
      v_config.polarity := ACTIVE_LOW;
      set_config;
      test_generate(100 ns, 30 ns, 2, "active-low");
      check_edges_rel((30 ns, 100 ns, 130 ns), "101", "active-low, hard-coded");

      log(ID_LOG_HDR, "TC-202: alignment and idle level changed between two commands", C_SCOPE);
      v_config.polarity   := ACTIVE_HIGH;
      v_config.alignment  := RIGHT_ALIGNED;
      v_config.idle_level := IDLE_ACTIVE;
      set_config;
      test_generate(100 ns, 30 ns, 2, "right-aligned, idle active");
      v_config.alignment  := LEFT_ALIGNED;
      v_config.idle_level := IDLE_INACTIVE;
      set_config;
      test_generate(100 ns, 30 ns, 1, "back to default");

      log(ID_LOG_HDR, "TC-202: jitter 5 ns, each run starts from the configured seeds", C_SCOPE);
      v_config.jitter := 5 ns;
      set_config;
      test_jitter(v_edges_a, "jitter, run 1");
      test_jitter(v_edges_b, "jitter, run 2");
      check_value(v_edges_a = v_edges_b, true, ERROR, "same seeds: identical edges", C_SCOPE);
      v_config.jitter_seed1 := 7;
      v_config.jitter_seed2 := 77;
      set_config;
      test_jitter(v_edges_b, "jitter, other seeds");
      v_differs := v_edges_a /= v_edges_b;
      check_value(v_differs, true, ERROR, "other seeds: different edges", C_SCOPE);
      v_config := C_PWM_BFM_CONFIG_DEFAULT;
      set_config;

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
