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

-- Include Verification IPs
library p2l2_vip_pwm;
use p2l2_vip_pwm.pwm_bfm_pkg.all;

use work.pwm_tb_pkg.all;

--hdlregression:tb
-- Test case entity
-- BFM TB without VVCs: p_main calls the BFM procedures on 'pwm', p_edge_logger records every event on 'pwm'. The
-- expected edges come from the reference model in pwm_tb_pkg. For the observation tests, p_stimulus drives 'pwm_obs'
-- with segments or the generator BFM, and p_main observes it. Test case IDs refer to doc/pwm_vvc_reqs.md.
entity pwm_bfm_tb is
  generic(
    GC_TESTCASE : string := "UVVM"
  );
end entity;

-- Test case architecture
architecture func of pwm_bfm_tb is

  constant C_SCOPE      : string := C_TB_SCOPE_DEFAULT;
  constant C_RESOLUTION : time   := std.env.resolution_limit;

  type t_time_array is array (natural range <>) of time;
  constant C_PERIODS : t_time_array := (10 ns, 1 us, 1 ms);

  signal pwm : std_logic := 'U';

  shared variable shared_edge_log : t_edge_log;

  -- Observation tests: the line and the stimulus requests from p_main to p_stimulus
  signal pwm_obs          : std_logic := '0';
  signal stim_start       : boolean   := false; -- toggled by p_main, starts a new stimulus (also during one)
  signal stim_busy        : boolean   := false;
  signal stim_segments    : t_segment_array(0 to C_MAX_SEGMENTS - 1);
  signal stim_count       : natural   := 0;
  signal stim_final       : std_logic := '0';   -- level after the segments
  signal stim_use_bfm     : boolean   := false; -- generate with pwm_generate() instead of segments
  signal stim_period      : time      := 0 ns;
  signal stim_active_time : time      := 0 ns;
  signal stim_num_periods : natural   := 0;
  signal stim_config      : t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT;

begin

  p_edge_logger : process is
  begin
    wait on pwm;
    shared_edge_log.add(now, pwm);
  end process p_edge_logger;

  -- Drives the stimulus requested by p_main on pwm_obs. A new request ends a segment stimulus at once.
  p_stimulus : process is
    variable v_restart : boolean;
  begin
    wait on stim_start;
    loop
      stim_busy <= true;
      v_restart := false;
      if stim_use_bfm then
        pwm_generate(stim_period, stim_active_time, stim_num_periods, "stimulus", pwm_obs, "STIMULUS", shared_msg_id_panel,
                     stim_config);
      else
        for i in 0 to stim_count - 1 loop
          pwm_obs <= stim_segments(i).level;
          wait on stim_start for stim_segments(i).duration;
          if stim_start'event then
            v_restart := true;
            exit;
          end if;
        end loop;
        if not v_restart then
          pwm_obs <= stim_final;
        end if;
      end if;
      if not v_restart then
        stim_busy <= false;
        wait on stim_start;
      end if;
    end loop;
  end process p_stimulus;

  p_main : process is
    variable v_config : t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT;
    variable v_seed1  : positive;
    variable v_seed2  : positive;
    variable v_start  : time;
    variable v_level  : std_logic;
    variable v_edges_a : t_edge_array(0 to 1999);
    variable v_edges_b : t_edge_array(0 to 1999);
    variable v_first   : time;
    variable v_last    : time;
    variable v_differs : boolean;

    -- Lets the last assignment to 'pwm' take effect and p_edge_logger record it
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
      return (2 * count * period + resolution * C_RESOLUTION) / (2 * resolution);
    end function;

    -- Starts a new edge log at the current time, with the line idle
    procedure start_test is
    begin
      settle;
      v_level := pwm;
      shared_edge_log.clear;
      v_start := now;
    end procedure;

    -- Checks the completion time and the final idle level of a pwm_generate() call started by start_test, and the
    -- edges against the reference model for 'params'
    procedure check_generated(
      constant params : t_period_param_array;
      constant msg    : string) is
      variable v_end : time := v_start;
    begin
      for i in params'range loop
        v_end := v_end + params(i).period;
      end loop;
      check_value(now, v_end, ERROR, "completion time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      settle;
      check_value(pwm, tb_idle_value(v_config.polarity, v_config.idle_level), MATCH_EXACT, ERROR, "idle after: " & msg, C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_edges(shared_edge_log, expected_edges(v_start, v_level, params, v_config.alignment,
                                           tb_active_level(v_config.polarity),
                                           tb_idle_value(v_config.polarity, v_config.idle_level)), msg, C_SCOPE);
    end procedure;

    -- Generates num_periods periods with pwm_generate(active_time) and checks them
    procedure test_generate(
      constant period      : time;
      constant active_time : time;
      constant num_periods : positive;
      constant msg         : string) is
    begin
      start_test;
      pwm_generate(period, active_time, num_periods, msg, pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(period, active_time, num_periods), msg);
    end procedure;

    -- Checks the logged edges against a hard-coded list, relative to v_start
    procedure check_edges_rel(
      constant times  : t_time_array;
      constant levels : std_logic_vector;
      constant msg    : string) is
      variable v_expected : t_edge_array(times'range);
    begin
      for i in times'range loop
        v_expected(i) := (v_start + times(i), levels(levels'low + i - times'low));
      end loop;
      check_edges(shared_edge_log, v_expected, msg, C_SCOPE);
    end procedure;

    -- Checks an invalid call of a generate procedure: called right after start_test, it must not use time or touch
    -- the line. The TB_ERROR is expected by the caller.
    procedure check_rejected(
      constant msg : string) is
    begin
      check_value(now, v_start, ERROR, "no time used: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      settle;
      check_value(shared_edge_log.count, 0, ERROR, "line unchanged: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- TC-001 / TC-004: all periods with the active times 1 unit, T/4, T/2, T - 1 unit
    procedure test_period_set(
      constant msg : string) is
    begin
      for i in C_PERIODS'range loop
        test_generate(C_PERIODS(i), C_RESOLUTION, 3, msg & ", T=" & to_string(C_PERIODS(i)) & ", t_on=1 unit");
        test_generate(C_PERIODS(i), C_PERIODS(i) / 4, 3, msg & ", T=" & to_string(C_PERIODS(i)) & ", t_on=T/4");
        test_generate(C_PERIODS(i), C_PERIODS(i) / 2, 3, msg & ", T=" & to_string(C_PERIODS(i)) & ", t_on=T/2");
        test_generate(C_PERIODS(i), C_PERIODS(i) - C_RESOLUTION, 3, msg & ", T=" & to_string(C_PERIODS(i)) & ", t_on=T-1 unit");
      end loop;
    end procedure;

    -- TC-006: the periods given back to back with pwm_drive_period(), no idle in between
    procedure test_drive_periods(
      constant params : t_period_param_array;
      constant msg    : string) is
    begin
      start_test;
      v_seed1 := v_config.jitter_seed1;
      v_seed2 := v_config.jitter_seed2;
      for i in params'range loop
        pwm_drive_period(params(i).period, params(i).active_time, pwm, v_config, v_seed1, v_seed2);
      end loop;
      pwm_drive_idle(pwm, v_config);
      check_generated(params, msg);
    end procedure;

    -- TC-012: generates num_periods periods with jitter and checks them against the ideal (unjittered) edges
    procedure test_jitter(
      constant period      : time;
      constant active_time : time;
      constant num_periods : positive;
      constant msg         : string) is
    begin
      start_test;
      pwm_generate(period, active_time, num_periods, msg, pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_value(now, v_start + num_periods * period, ERROR, "completion time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      settle;
      check_jittered_edges(shared_edge_log, expected_edges(v_start, v_level, repeat_period(period, active_time, num_periods),
                                                    v_config.alignment, tb_active_level(v_config.polarity),
                                                    tb_idle_value(v_config.polarity, v_config.idle_level)),
                           v_config.jitter, msg, C_SCOPE);
    end procedure;

    -- TC-012: the logged edges relative to v_start
    procedure save_edges(
      variable edges : out t_edge_array) is
      variable v_edge : t_edge;
    begin
      for i in 0 to minimum(shared_edge_log.count, edges'length) - 1 loop
        v_edge := shared_edge_log.get(i);
        edges(edges'low + i) := (v_edge.time_stamp - v_start, v_edge.level);
      end loop;
    end procedure;

    constant C_DUTY_SEQUENCE : t_period_param_array := ((10 ns, 5 ns), (10 ns, 0 ns), (10 ns, 5 ns), (10 ns, 10 ns), (10 ns, 5 ns));

    variable v_result : t_pwm_measurement;

    -- Observation tests: starts p_stimulus with the segments, then 'final_level'. The first segment starts now.
    procedure stimulate(
      constant segments    : t_segment_array;
      constant final_level : std_logic := '0') is
    begin
      stim_use_bfm                            <= false;
      stim_segments(0 to segments'length - 1) <= segments;
      stim_count                              <= segments'length;
      stim_final                              <= final_level;
      stim_start                              <= not stim_start;
      v_start                                 := now;
    end procedure;

    -- Observation tests: starts pwm_generate() in p_stimulus now
    procedure stimulate_bfm(
      constant period      : time;
      constant active_time : time;
      constant num_periods : positive;
      constant config      : t_pwm_bfm_config) is
    begin
      stim_use_bfm     <= true;
      stim_period      <= period;
      stim_active_time <= active_time;
      stim_num_periods <= num_periods;
      stim_config      <= config;
      stim_start       <= not stim_start;
      v_start          := now;
    end procedure;

    -- Lets the stimulus end
    procedure await_stimulus is
    begin
      settle;
      if stim_busy then
        wait until not stim_busy;
      end if;
    end procedure;

    -- Sets pwm_obs to a constant level and waits 10 ns
    procedure set_line(
      constant level : std_logic) is
    begin
      stimulate(seg(level, 0 ns), level);
      wait for 10 ns;
    end procedure;

    procedure check_measurement(
      constant period      : time;
      constant active_time : time;
      constant msg         : string) is
      constant C_DUTY : real := tb_units(active_time) / tb_units(period);
    begin
      check_value(v_result.is_constant, false, ERROR, "is_constant: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.period, period, ERROR, "period: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.active_time, active_time, ERROR, "active_time: " & msg, C_SCOPE, ID_NEVER);
      check_value_in_range(v_result.duty_cycle, C_DUTY - 1.0e-9, C_DUTY + 1.0e-9, ERROR, "duty_cycle: " & msg, C_SCOPE, ID_NEVER);
    end procedure;

    procedure check_constant_result(
      constant level : std_logic;
      constant duty  : real;
      constant msg   : string) is
    begin
      check_value(v_result.is_constant, true, ERROR, "is_constant: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.constant_level, level, MATCH_EXACT, ERROR, "constant_level: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.duty_cycle, duty, ERROR, "duty_cycle: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.period, 0 ns, ERROR, "period: " & msg, C_SCOPE, ID_NEVER);
      check_value(v_result.active_time, 0 ns, ERROR, "active_time: " & msg, C_SCOPE, ID_NEVER);
    end procedure;

    -- The observation call returned 'delay' after v_start
    procedure check_completion(
      constant delay : time;
      constant msg   : string) is
    begin
      check_value(now, v_start + delay, ERROR, "completion time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- TC-101/102: measures the output of pwm_generate() (3 periods) and checks the result and the completion time
    procedure test_measure_generated(
      constant period      : time;
      constant active_time : time;
      constant msg         : string) is
      constant C_OFF_TIME : time := period - active_time;
      variable v_first    : time; -- first active-going edge after v_start
    begin
      stimulate_bfm(period, active_time, 3, v_config);
      pwm_measure(v_result, msg, pwm_obs, 2 * period, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(period, active_time, msg);
      case v_config.alignment is
        when LEFT_ALIGNED   => v_first := 0 ns;
        when RIGHT_ALIGNED  => v_first := C_OFF_TIME;
        when CENTER_ALIGNED => v_first := C_OFF_TIME / 2; -- whole resolution units, rounded down
      end case;
      check_completion(v_first + period, msg);
      await_stimulus;
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

    pwm_drive_idle(pwm, v_config);
    settle;

    --============================================================================================================================
    if GC_TESTCASE = "TC_001" then
      -- REQ-001, REQ-009, REQ-010: left-aligned, active-high
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-001: left-aligned, active-high, exact edge times", C_SCOPE);
      test_period_set("TC-001");

      log(ID_LOG_HDR, "TC-001: k=1 and k=5 periods, hard-coded edges", C_SCOPE);
      start_test;
      pwm_generate(10 ns, 3 ns, 1, "k=1", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((0 ns, 3 ns), "10", "k=1");
      start_test;
      pwm_generate(10 ns, 3 ns, 5, "k=5", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_value(now, v_start + 50 ns, ERROR, "k=5 completion time", C_SCOPE, ID_SEQUENCER_SUB);
      settle;
      check_edges_rel((0 ns, 3 ns, 10 ns, 13 ns, 20 ns, 23 ns, 30 ns, 33 ns, 40 ns, 43 ns), "1010101010", "k=5");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_002" then
      -- REQ-002: active time, ratio and counter value give the same waveform
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-002: t_on 25 ns, D 0.25 and 64/256 at T 100 ns", C_SCOPE);
      start_test;
      pwm_generate(100 ns, 25 ns, 2, "t_on", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((0 ns, 25 ns, 100 ns, 125 ns), "1010", "t_on 25 ns");
      start_test;
      pwm_generate(100 ns, 0.25, 2, "duty", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((0 ns, 25 ns, 100 ns, 125 ns), "1010", "D 0.25");
      start_test;
      pwm_generate(100 ns, 64, 256, 2, "count", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((0 ns, 25 ns, 100 ns, 125 ns), "1010", "64/256");

      log(ID_LOG_HDR, "TC-002: rounding to the nearest resolution unit", C_SCOPE);
      -- Periods of a few resolution units give time stamps with more decimals than the log shows: UVVM warns once
      increment_expected_alerts(TB_WARNING, 1, "log time stamp truncated");
      start_test;
      pwm_generate(10 ns, 1.0 / 3.0, 2, "D 1/3", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 ns, rounded_units(10 ns, 1, 3), 2), "D 1/3 at T 10 ns");
      start_test;
      pwm_generate(10 ns, 1, 3, 2, "1/3", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 ns, rounded_units(10 ns, 1, 3), 2), "count 1/3 at T 10 ns");
      start_test;
      pwm_generate(100 ns, 0.29, 2, "D 0.29", pwm, C_SCOPE, shared_msg_id_panel, v_config); -- 0.29 is not exact in binary
      check_generated(repeat_period(100 ns, 29 ns, 2), "D 0.29 at T 100 ns");
      start_test;
      pwm_generate(10 * C_RESOLUTION, 1, 4, 2, "1/4 of 10 units", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 * C_RESOLUTION, 3 * C_RESOLUTION, 2), "count 1/4 of 10 units: 2.5 rounds up to 3");
      -- More than 2**31 resolution units in the period
      start_test;
      pwm_generate(4 ms, 1.0 / 3.0, 1, "D 1/3", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(4 ms, rounded_units(4 ms, 1, 3), 1), "D 1/3 at T 4 ms");
      start_test;
      pwm_generate(4 ms, 1, 3, 1, "1/3", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(4 ms, rounded_units(4 ms, 1, 3), 1), "count 1/3 at T 4 ms");
      start_test;
      pwm_generate(4 ms, 2, 3, 1, "2/3", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(4 ms, rounded_units(4 ms, 2, 3), 1), "count 2/3 at T 4 ms");
      start_test;
      pwm_generate(10 ns, 0, 8, 2, "0/8", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 ns, 0 ns, 2), "count 0/8");
      start_test;
      pwm_generate(10 ns, 8, 8, 2, "8/8", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 ns, 10 ns, 2), "count 8/8");
      start_test;
      pwm_generate(10 ns, 1.0, 2, "D 1.0", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_generated(repeat_period(10 ns, 10 ns, 2), "D 1.0");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_003" then
      -- REQ-003: invalid generation parameters, one TB_ERROR each, line unchanged
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-003: invalid generation parameters", C_SCOPE);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "period 0 ns");
      start_test;
      pwm_generate(0 ns, 0 ns, 1, "period 0 ns", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("period 0 ns");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "period < 0 ns");
      start_test;
      pwm_generate(-1 ns, 0 ns, 1, "period -1 ns", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("period -1 ns");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "t_on < 0 ns");
      start_test;
      pwm_generate(10 ns, -1 ns, 1, "t_on -1 ns", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("t_on -1 ns");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "t_on > T");
      start_test;
      pwm_generate(10 ns, 10 ns + C_RESOLUTION, 1, "t_on > T", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("t_on > T");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "D < 0");
      start_test;
      pwm_generate(10 ns, -0.1, 1, "D -0.1", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("D -0.1");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "D > 1");
      start_test;
      pwm_generate(10 ns, 1.1, 1, "D 1.1", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("D 1.1");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "N < 1");
      start_test;
      pwm_generate(10 ns, 0, 0, 1, "N 0", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("N 0");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "n < 0");
      start_test;
      pwm_generate(10 ns, -1, 4, 1, "n -1", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("n -1");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "n > N");
      start_test;
      pwm_generate(10 ns, 5, 4, 1, "n 5 of 4", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("n 5 of 4");

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "k < 1");
      start_test;
      pwm_generate(10 ns, 5 ns, 0, "k 0", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("k 0");

      log(ID_LOG_HDR, "TC-003: a valid call afterwards still works", C_SCOPE);
      test_generate(10 ns, 5 ns, 2, "valid after invalid");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_004" then
      -- REQ-004: active-low
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-004: active-low, idle level inverted", C_SCOPE);
      v_config.polarity := ACTIVE_LOW;
      pwm_drive_idle(pwm, v_config);
      settle;
      check_value(pwm, '1', MATCH_EXACT, ERROR, "active-low idle", C_SCOPE);
      test_period_set("TC-004 active-low");
      start_test;
      pwm_generate(10 ns, 3 ns, 2, "hard-coded", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((0 ns, 3 ns, 10 ns, 13 ns), "0101", "active-low hard-coded");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_005" then
      -- REQ-005, REQ-006: right- and center-aligned
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-005: right-aligned", C_SCOPE);
      v_config.alignment := RIGHT_ALIGNED;
      start_test;
      pwm_generate(10 ns, 3 ns, 2, "right", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((7 ns, 10 ns, 17 ns, 20 ns), "1010", "right-aligned T 10 ns, t_on 3 ns");
      test_period_set("TC-005 right-aligned");

      log(ID_LOG_HDR, "TC-005: center-aligned", C_SCOPE);
      -- Periods of a few resolution units give time stamps with more decimals than the log shows: UVVM warns once
      increment_expected_alerts(TB_WARNING, 1, "log time stamp truncated");
      v_config.alignment := CENTER_ALIGNED;
      start_test;
      pwm_generate(10 ns, 4 ns, 1, "center", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((3 ns, 7 ns), "10", "center-aligned T 10 ns, t_on 4 ns");
      start_test;
      pwm_generate(10 * C_RESOLUTION, 3 * C_RESOLUTION, 1, "center odd", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      check_edges_rel((3 * C_RESOLUTION, 6 * C_RESOLUTION), "10", "center-aligned, odd t_off: extra unit in the second gap");
      start_test;
      pwm_generate(10 ns, 3 ns, 1, "center spec 7", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      settle;
      if C_RESOLUTION <= 100 ps then
        check_edges_rel((3.5 ns, 6.5 ns), "10", "center-aligned T 10 ns, t_on 3 ns (spec section 7)");
      end if;
      test_period_set("TC-005 center-aligned");

      log(ID_LOG_HDR, "TC-005: right- and center-aligned, active-low", C_SCOPE);
      v_config.polarity  := ACTIVE_LOW;
      v_config.alignment := RIGHT_ALIGNED;
      pwm_drive_idle(pwm, v_config);
      test_generate(10 ns, 3 ns, 3, "right-aligned active-low");
      v_config.alignment := CENTER_ALIGNED;
      test_generate(10 ns, 3 ns, 3, "center-aligned active-low");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_006" then
      -- REQ-007: 0 % and 100 %, no glitches when switching
      --============================================================================================================================
      for alignment in t_pwm_alignment loop
        v_config.alignment := alignment;
        log(ID_LOG_HDR, "TC-006: 0 % and 100 % for 10 periods, " & to_string(alignment), C_SCOPE);
        start_test;
        pwm_generate(10 ns, 0 ns, 10, "0 %", pwm, C_SCOPE, shared_msg_id_panel, v_config);
        check_generated(repeat_period(10 ns, 0 ns, 10), "0 % " & to_string(alignment));
        check_value(shared_edge_log.count, 0, ERROR, "0 %: no edges", C_SCOPE);
        start_test;
        pwm_generate(10 ns, 10 ns, 10, "100 %", pwm, C_SCOPE, shared_msg_id_panel, v_config);
        check_generated(repeat_period(10 ns, 10 ns, 10), "100 % " & to_string(alignment));
        check_value(shared_edge_log.count, 2, ERROR, "100 %: only the edges from and to idle", C_SCOPE);

        log(ID_LOG_HDR, "TC-006: 50 % -> 0 % -> 50 % -> 100 % -> 50 % back to back, " & to_string(alignment), C_SCOPE);
        test_drive_periods(C_DUTY_SEQUENCE, "duty sequence " & to_string(alignment));
      end loop;

      log(ID_LOG_HDR, "TC-006: duty sequence, hard-coded edges", C_SCOPE);
      v_config.alignment := LEFT_ALIGNED;
      test_drive_periods(C_DUTY_SEQUENCE, "duty sequence left");
      check_edges_rel((0 ns, 5 ns, 20 ns, 25 ns, 30 ns, 45 ns), "101010", "duty sequence left, hard-coded");
      v_config.alignment := RIGHT_ALIGNED;
      test_drive_periods(C_DUTY_SEQUENCE, "duty sequence right");
      check_edges_rel((5 ns, 10 ns, 25 ns, 40 ns, 45 ns, 50 ns), "101010", "duty sequence right, hard-coded");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_007" then
      -- REQ-008: idle level options (BFM part; initial and after-abort idle are tested on the VVC)
      --============================================================================================================================
      for polarity in t_pwm_polarity loop
        for idle_level in t_pwm_idle_level loop
          log(ID_LOG_HDR, "TC-007: " & to_string(polarity) & ", " & to_string(idle_level), C_SCOPE);
          v_config.polarity   := polarity;
          v_config.idle_level := idle_level;
          pwm_drive_idle(pwm, v_config);
          settle;
          check_value(pwm, tb_idle_value(polarity, idle_level), MATCH_EXACT, ERROR, "pwm_drive_idle()", C_SCOPE);
          test_generate(10 ns, 3 ns, 2, "idle after generate, " & to_string(polarity) & ", " & to_string(idle_level));
        end loop;
      end loop;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_012" then
      -- REQ-015: bounded, non-accumulating, reproducible jitter
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-012: j = 5 ns, T = 100 ns, t_on = 50 ns, 1000 periods", C_SCOPE);
      v_config.jitter := 5 ns;
      test_jitter(100 ns, 50 ns, 1000, "j 5 ns");
      save_edges(v_edges_a);
      -- No drift: the mean period between the first and the last active-going edge. Each edge is within +-j of its ideal
      -- time, so the mean of 999 periods can differ from T by at most 2j/999 (plus rounding).
      v_first := v_edges_a(0).time_stamp;
      v_last  := v_edges_a(1998).time_stamp;
      log(ID_SEQUENCER, "Mean period over 999 periods: " & to_string((v_last - v_first) / 999), C_SCOPE);
      check_value_in_range((v_last - v_first) / 999, 100 ns - (2 * 5 ns) / 999 - C_RESOLUTION,
                           100 ns + (2 * 5 ns) / 999 + C_RESOLUTION, ERROR, "mean period (no drift)", C_SCOPE);
      -- The jitter is random: at least two different offsets
      v_differs := false;
      for i in 1 to 1999 loop
        v_differs := v_differs or (v_edges_a(i).time_stamp - v_edges_a(0).time_stamp /= (i / 2) * 100 ns + (i mod 2) * 50 ns);
      end loop;
      check_value(v_differs, ERROR, "at least two different edge offsets", C_SCOPE);

      log(ID_LOG_HDR, "TC-012: the same seeds give the same waveform, other seeds a different one", C_SCOPE);
      test_jitter(100 ns, 50 ns, 1000, "j 5 ns, same seeds");
      save_edges(v_edges_b);
      check_value(v_edges_a = v_edges_b, ERROR, "same seeds: identical edges", C_SCOPE);
      v_config.jitter_seed1 := 12345;
      test_jitter(100 ns, 50 ns, 1000, "j 5 ns, other seeds");
      save_edges(v_edges_b);
      check_value(v_edges_a /= v_edges_b, ERROR, "other seeds: different edges", C_SCOPE);
      v_config.jitter_seed1 := C_PWM_BFM_CONFIG_DEFAULT.jitter_seed1;

      log(ID_LOG_HDR, "TC-012: j = 30 ns with t_on = 50 ns: no pulse or gap below 1 unit, no missing pulse", C_SCOPE);
      v_config.jitter := 30 ns;
      test_jitter(100 ns, 50 ns, 1000, "j 30 ns");

      log(ID_LOG_HDR, "TC-012: jitter larger than the pulse and the gap", C_SCOPE);
      v_config.jitter := 5 ns;
      test_jitter(100 ns, C_RESOLUTION, 500, "j 5 ns, t_on 1 unit");
      test_jitter(100 ns, 100 ns - C_RESOLUTION, 500, "j 5 ns, t_on T - 1 unit");
      -- 501 periods of 10 units end at a time stamp with more decimals than the log shows (ps and fs resolution)
      increment_expected_alerts(TB_WARNING, 1, "log time stamp truncated");
      test_jitter(10 * C_RESOLUTION, 5 * C_RESOLUTION, 501, "j 5 ns, T 10 units");

      log(ID_LOG_HDR, "TC-012: right- and center-aligned, active-low", C_SCOPE);
      for alignment in RIGHT_ALIGNED to CENTER_ALIGNED loop
        v_config.alignment := alignment;
        test_jitter(100 ns, 30 ns, 500, "j 5 ns, " & to_string(alignment));
      end loop;
      v_config.polarity := ACTIVE_LOW;
      pwm_drive_idle(pwm, v_config);
      test_jitter(100 ns, 30 ns, 500, "j 5 ns, center-aligned, active-low");
      v_config := C_PWM_BFM_CONFIG_DEFAULT;
      pwm_drive_idle(pwm, v_config);

      log(ID_LOG_HDR, "TC-012: 0 % and 100 % are not affected by jitter", C_SCOPE);
      v_config.jitter := 5 ns;
      test_generate(100 ns, 0 ns, 10, "j 5 ns, 0 %");
      test_generate(100 ns, 100 ns, 10, "j 5 ns, 100 %");

      log(ID_LOG_HDR, "TC-012: j = 0 ns gives exact edges", C_SCOPE);
      v_config.jitter := 0 ns;
      test_generate(100 ns, 50 ns, 10, "j 0 ns");

      log(ID_LOG_HDR, "TC-012: j < 0 ns is rejected", C_SCOPE);
      v_config.jitter := -1 ns;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "jitter < 0 ns");
      start_test;
      pwm_generate(100 ns, 50 ns, 1, "j -1 ns", pwm, C_SCOPE, shared_msg_id_panel, v_config);
      check_rejected("j -1 ns");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_101" then
      -- REQ-101: measure one complete period, starting at the next active-going edge
      --============================================================================================================================
      -- Periods of a few resolution units give time stamps with more decimals than the log shows: UVVM warns once
      increment_expected_alerts(TB_WARNING, 1, "log time stamp truncated");
      for alignment in t_pwm_alignment loop
        v_config.alignment := alignment;
        log(ID_LOG_HDR, "TC-101: measure the generator BFM output, " & to_string(alignment), C_SCOPE);
        for i in C_PERIODS'range loop
          test_measure_generated(C_PERIODS(i), C_RESOLUTION, "T=" & to_string(C_PERIODS(i)) & ", t_on=1 unit, " & to_string(alignment));
          test_measure_generated(C_PERIODS(i), C_PERIODS(i) / 4, "T=" & to_string(C_PERIODS(i)) & ", t_on=T/4, " & to_string(alignment));
          test_measure_generated(C_PERIODS(i), C_PERIODS(i) / 2, "T=" & to_string(C_PERIODS(i)) & ", t_on=T/2, " & to_string(alignment));
          test_measure_generated(C_PERIODS(i), C_PERIODS(i) - C_RESOLUTION, "T=" & to_string(C_PERIODS(i)) & ", t_on=T-1 unit, " &
                                 to_string(alignment));
        end loop;
      end loop;
      v_config.alignment := LEFT_ALIGNED;

      log(ID_LOG_HDR, "TC-101: request mid-pulse and mid-gap: the period in progress is ignored", C_SCOPE);
      -- Three different periods: 40/100, 30/100, 20/100
      stimulate(seg('1', 40 ns) & seg('0', 60 ns) & seg('1', 30 ns) & seg('0', 70 ns) & seg('1', 20 ns) & seg('0', 80 ns));
      wait for 10 ns;
      pwm_measure(v_result, "mid-pulse", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 30 ns, "request mid-pulse");
      check_completion(200 ns, "request mid-pulse");
      stimulate(seg('1', 40 ns) & seg('0', 60 ns) & seg('1', 30 ns) & seg('0', 70 ns) & seg('1', 20 ns) & seg('0', 80 ns));
      wait for 50 ns;
      pwm_measure(v_result, "mid-gap", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 30 ns, "request mid-gap");
      check_completion(200 ns, "request mid-gap");
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_102" then
      -- REQ-102: measurement respects the polarity
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-102: active-low gives the same T and t_on as active-high", C_SCOPE);
      v_config.polarity := ACTIVE_LOW;
      set_line('1');
      for i in C_PERIODS'range loop
        test_measure_generated(C_PERIODS(i), C_PERIODS(i) / 4, "active-low, T=" & to_string(C_PERIODS(i)) & ", t_on=T/4");
      end loop;
      v_config.alignment := CENTER_ALIGNED;
      test_measure_generated(100 ns, 30 ns, "active-low, center-aligned");
      v_config.alignment := LEFT_ALIGNED;

      log(ID_LOG_HDR, "TC-102: an active-low signal measured as active-high gives t_on = T - t_on", C_SCOPE);
      stimulate_bfm(100 ns, 30 ns, 3, v_config);
      v_config.polarity := ACTIVE_HIGH;
      pwm_measure(v_result, "active-low line, active-high config", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 70 ns, "active-low line, active-high config");
      check_completion(130 ns, "active-low line, active-high config");
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_103" then
      -- REQ-103, REQ-106: constant level (0 % / 100 %)
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-103: pwm_measure() on a constant line reports the constant level, no alert", C_SCOPE);
      set_line('0');
      v_start := now;
      pwm_measure(v_result, "constant 0", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('0', 0.0, "constant 0");
      check_completion(500 ns, "constant 0");
      set_line('1');
      v_start := now;
      pwm_measure(v_result, "constant 1", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('1', 1.0, "constant 1");
      check_completion(500 ns, "constant 1");
      v_config.polarity := ACTIVE_LOW;
      set_line('0');
      pwm_measure(v_result, "constant 0, active-low", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('0', 1.0, "constant 0, active-low");
      v_config.polarity := ACTIVE_HIGH;
      -- A falling edge first, then constant: the line held '0' for the timeout after that edge
      stimulate(seg('1', 50 ns), '0');
      wait for 10 ns;
      pwm_measure(v_result, "1 then constant 0", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('0', 0.0, "1 then constant 0");
      check_completion(550 ns, "1 then constant 0");

      log(ID_LOG_HDR, "TC-103: constant 'Z' is a result if idle_level is IDLE_HIGH_Z, else an ERROR", C_SCOPE);
      set_line('Z');
      v_config.idle_level := IDLE_HIGH_Z;
      pwm_measure(v_result, "constant Z, IDLE_HIGH_Z", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('Z', 0.0, "constant Z, IDLE_HIGH_Z");
      v_config.idle_level := IDLE_INACTIVE;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "constant Z, IDLE_INACTIVE");
      pwm_measure(v_result, "constant Z, IDLE_INACTIVE", pwm_obs, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_constant_result('Z', 0.0, "constant Z, IDLE_INACTIVE");

      log(ID_LOG_HDR, "TC-103: pwm_check() and pwm_check_duty() of 0 % and 100 %", C_SCOPE);
      set_line('0');
      v_start := now;
      pwm_check(100 ns, 0 ns, 1, "0 % on 0", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(500 ns, "0 % on 0");
      v_start := now;
      pwm_check(100 ns, 0 ns, 1, "0 % on 0, default timeout 2T", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(200 ns, "0 % on 0, default timeout 2T");
      v_start := now;
      pwm_check_duty(0.0, 1, "D 0.0 on 0", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(500 ns, "D 0.0 on 0");
      set_line('1');
      pwm_check(100 ns, 100 ns, 1, "100 % on 1", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      pwm_check_duty(1.0, 1, "D 1.0 on 1", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.polarity := ACTIVE_LOW;
      pwm_check(100 ns, 0 ns, 1, "0 % on 1, active-low", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.polarity := ACTIVE_HIGH;

      log(ID_LOG_HDR, "TC-103: wrong level and an edge inside the window raise one alert each", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "0 % on 1");
      v_start := now;
      pwm_check(100 ns, 0 ns, 1, "0 % on 1", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(0 ns, "0 % on 1: returns at once");
      increment_expected_alerts_and_stop_limit(ERROR, 1, "D 0.0 on 1");
      pwm_check_duty(0.0, 1, "D 0.0 on 1", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts(WARNING, 1, "0 % on 1, alert_level WARNING");
      pwm_check(100 ns, 0 ns, 1, "0 % on 1", pwm_obs, WARNING, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "edge inside the window");
      stimulate(seg('0', 100 ns), '1');
      settle; -- the line is '1' before the stimulus
      pwm_check(100 ns, 0 ns, 1, "0 %, edge after 100 ns", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(100 ns, "0 %, edge after 100 ns");
      increment_expected_alerts_and_stop_limit(ERROR, 1, "edge inside the window, D 1.0");
      stimulate(seg('1', 100 ns), '0');
      pwm_check_duty(1.0, 1, "D 1.0, edge after 100 ns", pwm_obs, ERROR, 500 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(100 ns, "D 1.0, edge after 100 ns");

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_104" then
      -- REQ-104, REQ-105: check T and t_on with inclusive tolerances
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-104: correct signal, no alert", C_SCOPE);
      stimulate(pwm_wave(100 ns, 25 ns, 3) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 3, "exact", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(300 ns, "exact, k=3");
      await_stimulus;

      log(ID_LOG_HDR, "TC-104: T off by more than the tolerance", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "T 101 ns, tolerance 0 ns");
      stimulate(pwm_wave(101 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 101 ns, tolerance 0 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(101 ns, "T 101 ns");
      await_stimulus;
      increment_expected_alerts(WARNING, 1, "T 101 ns, alert_level WARNING");
      stimulate(pwm_wave(101 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 101 ns, WARNING", pwm_obs, WARNING, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-104: period tolerance 1 ns: +-1 ns passes, +-(1 ns + 1 unit) fails", C_SCOPE);
      -- Edges 1 resolution unit off give time stamps with more decimals than the log shows: UVVM warns once
      increment_expected_alerts(TB_WARNING, 1, "log time stamp truncated");
      v_config.period_tolerance := 1 ns;
      stimulate(pwm_wave(101 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 101 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      stimulate(pwm_wave(99 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 99 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "T 101 ns + 1 unit");
      stimulate(pwm_wave(101 ns + C_RESOLUTION, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 101 ns + 1 unit", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "T 99 ns - 1 unit");
      stimulate(pwm_wave(99 ns - C_RESOLUTION, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 99 ns - 1 unit", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.period_tolerance := 0 ns;

      log(ID_LOG_HDR, "TC-104: active time tolerance 1 ns: +-1 ns passes, +-(1 ns + 1 unit) fails", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "t_on 26 ns, tolerance 0 ns");
      stimulate(pwm_wave(100 ns, 26 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "t_on 26 ns, tolerance 0 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.active_time_tolerance := 1 ns;
      stimulate(pwm_wave(100 ns, 26 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "t_on 26 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      stimulate(pwm_wave(100 ns, 24 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "t_on 24 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "t_on 26 ns + 1 unit");
      stimulate(pwm_wave(100 ns, 26 ns + C_RESOLUTION, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "t_on 26 ns + 1 unit", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "t_on 24 ns - 1 unit");
      stimulate(pwm_wave(100 ns, 24 ns - C_RESOLUTION, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "t_on 24 ns - 1 unit", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.active_time_tolerance := 0 ns;

      log(ID_LOG_HDR, "TC-104: T and t_on wrong in the same period: one alert", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "T and t_on wrong");
      stimulate(pwm_wave(110 ns, 30 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "T 110 ns, t_on 30 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_105" then
      -- REQ-107: k consecutive periods, one alert per failing period
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-105: k=5, all correct", C_SCOPE);
      stimulate(pwm_wave(100 ns, 25 ns, 5) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 5, "k=5 correct", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(500 ns, "k=5 correct");
      await_stimulus;

      log(ID_LOG_HDR, "TC-105: k=5, T of period 3 wrong: one alert naming period 3/5", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "period 3/5");
      stimulate(pwm_wave(100 ns, 25 ns, 2) & pwm_wave(110 ns, 25 ns, 1) & pwm_wave(100 ns, 25 ns, 2) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 5, "k=5, period 3 wrong", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(510 ns, "k=5, period 3 wrong");
      await_stimulus;

      log(ID_LOG_HDR, "TC-105: k=5, t_on of periods 2 and 5 wrong: two alerts", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 2, "periods 2/5 and 5/5");
      stimulate(pwm_wave(100 ns, 25 ns, 1) & pwm_wave(100 ns, 30 ns, 1) & pwm_wave(100 ns, 25 ns, 2) & pwm_wave(100 ns, 20 ns, 1) &
                seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 5, "k=5, periods 2 and 5 wrong", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_106" then
      -- REQ-108: invalid levels during a measurement
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-106: 1 ns of X, U, Z, W, - inside the pulse: one ERROR each, timing unaffected", C_SCOPE);
      for value in std_ulogic loop
        if value /= '0' and value /= '1' and value /= 'L' and value /= 'H' then
          increment_expected_alerts_and_stop_limit(ERROR, 1, "'" & to_string(value) & "' inside the pulse");
          stimulate(seg('1', 10 ns) & seg(value, 1 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
          pwm_measure(v_result, "'" & to_string(value) & "' inside the pulse", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
          check_measurement(100 ns, 25 ns, "'" & to_string(value) & "' inside the pulse");
          await_stimulus;
        end if;
      end loop;

      log(ID_LOG_HDR, "TC-106: X inside the gap, and inside a pwm_check() at alert_level WARNING", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "X inside the gap");
      stimulate(seg('1', 25 ns) & seg('0', 30 ns) & seg('X', 1 ns) & seg('0', 44 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "X inside the gap", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 25 ns, "X inside the gap");
      await_stimulus;
      increment_expected_alerts(WARNING, 1, "X inside period 2 of a check");
      stimulate(pwm_wave(100 ns, 25 ns, 1) & seg('1', 10 ns) & seg('X', 1 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 2, "X in period 2", pwm_obs, WARNING, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-106: before the first active-going edge, 'Z' is legal only with IDLE_HIGH_Z", C_SCOPE);
      v_config.idle_level := IDLE_HIGH_Z;
      set_line('Z');
      stimulate(seg('0', 10 ns) & seg('Z', 10 ns) & pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns), 'Z');
      pwm_measure(v_result, "Z before the period, IDLE_HIGH_Z", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 25 ns, "Z before the period, IDLE_HIGH_Z");
      await_stimulus;
      v_config.idle_level := IDLE_INACTIVE;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "Z before the period, IDLE_INACTIVE");
      stimulate(seg('0', 10 ns) & seg('Z', 10 ns) & pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_measure(v_result, "Z before the period, IDLE_INACTIVE", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 25 ns, "Z before the period, IDLE_INACTIVE");
      await_stimulus;
      log(ID_LOG_HDR, "TC-106: 'Z' inside the period is an ERROR also with IDLE_HIGH_Z", C_SCOPE);
      v_config.idle_level := IDLE_HIGH_Z;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "Z inside the pulse, IDLE_HIGH_Z");
      stimulate(seg('1', 10 ns) & seg('Z', 1 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "Z inside the pulse, IDLE_HIGH_Z", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 25 ns, "Z inside the pulse, IDLE_HIGH_Z");
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_107" then
      -- REQ-109: runt pulses and gaps
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-107: min_pulse_width 2 ns: 1 ns gap and 1 ns pulse raise one ERROR each, 2 ns none", C_SCOPE);
      v_config.min_pulse_width := 2 ns;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "1 ns gap");
      stimulate(seg('1', 10 ns) & seg('0', 1 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "1 ns gap", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(11 ns, 10 ns, "1 ns gap");
      await_stimulus;
      stimulate(seg('1', 10 ns) & seg('0', 2 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "2 ns gap", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(12 ns, 10 ns, "2 ns gap");
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "1 ns pulse");
      stimulate(seg('1', 1 ns) & seg('0', 99 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "1 ns pulse", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 1 ns, "1 ns pulse");
      await_stimulus;
      stimulate(seg('1', 2 ns) & seg('0', 98 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "2 ns pulse", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 2 ns, "2 ns pulse");
      await_stimulus;

      log(ID_LOG_HDR, "TC-107: runt in a pwm_check() at alert_level WARNING (the timing mismatch is a second WARNING)", C_SCOPE);
      increment_expected_alerts(WARNING, 2, "1 ns pulse in a check");
      stimulate(seg('1', 1 ns) & seg('0', 99 ns) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "1 ns pulse", pwm_obs, WARNING, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-107: min_pulse_width 0 ns: detection off", C_SCOPE);
      v_config.min_pulse_width := 0 ns;
      stimulate(seg('1', 10 ns) & seg('0', 1 ns) & seg('1', 14 ns) & seg('0', 75 ns) & seg('1', 25 ns));
      pwm_measure(v_result, "1 ns gap, detection off", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(11 ns, 10 ns, "1 ns gap, detection off");
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_108" then
      -- REQ-110: missing activity
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-108: line stuck after period 1 of 3: one ERROR at the last edge + timeout", C_SCOPE);
      increment_expected_alerts_and_stop_limit(ERROR, 1, "stuck after period 1");
      stimulate(pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 3, "stuck after period 1", pwm_obs, ERROR, 200 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(325 ns, "stuck after period 1");

      log(ID_LOG_HDR, "TC-108: line stuck from the request: missing activity, not 0 % / 100 %", C_SCOPE);
      set_line('0');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "stuck at 0");
      v_start := now;
      pwm_check(100 ns, 25 ns, 1, "stuck at 0", pwm_obs, ERROR, 300 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(300 ns, "stuck at 0");
      increment_expected_alerts_and_stop_limit(ERROR, 1, "stuck at 0, default timeout 2T");
      v_start := now;
      pwm_check(100 ns, 25 ns, 1, "stuck at 0, default timeout", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(200 ns, "stuck at 0, default timeout 2T");
      increment_expected_alerts_and_stop_limit(ERROR, 1, "stuck at 0, pwm_check_duty");
      v_start := now;
      pwm_check_duty(0.25, 1, "stuck at 0", pwm_obs, ERROR, 300 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(300 ns, "stuck at 0, pwm_check_duty");
      set_line('1');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "stuck at 1");
      v_start := now;
      pwm_check(100 ns, 25 ns, 1, "stuck at 1", pwm_obs, ERROR, 300 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(300 ns, "stuck at 1");

      log(ID_LOG_HDR, "TC-108: timeout_severity WARNING", C_SCOPE);
      v_config.timeout_severity := WARNING;
      increment_expected_alerts(WARNING, 1, "stuck at 1, timeout_severity WARNING");
      pwm_check(100 ns, 25 ns, 1, "stuck at 1", pwm_obs, ERROR, 300 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.timeout_severity := ERROR;

      log(ID_LOG_HDR, "TC-108: pwm_measure() with the line stuck after the active-going edge", C_SCOPE);
      set_line('0');
      increment_expected_alerts_and_stop_limit(ERROR, 1, "measure, stuck active");
      stimulate(seg('1', 0 ns), '1');
      pwm_measure(v_result, "stuck active", pwm_obs, 200 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(200 ns, "measure, stuck active");
      check_value(v_result = C_PWM_MEASUREMENT_DEFAULT, ERROR, "measure, stuck active: default result", C_SCOPE);

      log(ID_LOG_HDR, "TC-108: the next call runs normally", C_SCOPE);
      set_line('0');
      stimulate(pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "after missing activity", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_109" then
      -- REQ-111: invalid observation parameters, one TB_ERROR each, no time used
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-109: invalid observation parameters", C_SCOPE);
      v_start := now;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "measure without timeout");
      pwm_measure(v_result, "no timeout", pwm_obs, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "measure, timeout < 0 ns");
      pwm_measure(v_result, "timeout -2 ns", pwm_obs, -2 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.min_pulse_width := -1 ns;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "measure, min_pulse_width < 0 ns");
      pwm_measure(v_result, "min_pulse_width -1 ns", pwm_obs, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.min_pulse_width := 0 ns;

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, T 0 ns");
      pwm_check(0 ns, 0 ns, 1, "T 0 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, T < 0 ns");
      pwm_check(-1 ns, 0 ns, 1, "T -1 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, t_on < 0 ns");
      pwm_check(100 ns, -1 ns, 1, "t_on -1 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, t_on > T");
      pwm_check(100 ns, 100 ns + C_RESOLUTION, 1, "t_on > T", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, k 0");
      pwm_check(100 ns, 25 ns, 0, "k 0", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, timeout < 0 ns");
      pwm_check(100 ns, 25 ns, 1, "timeout -2 ns", pwm_obs, ERROR, -2 ns, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check 0 %, timeout 0 ns");
      pwm_check(100 ns, 0 ns, 1, "0 %, timeout 0 ns", pwm_obs, ERROR, 0 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.period_tolerance := -1 ns;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, period_tolerance < 0 ns");
      pwm_check(100 ns, 25 ns, 1, "period_tolerance -1 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.period_tolerance := 0 ns;
      v_config.active_time_tolerance := -1 ns;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check, active_time_tolerance < 0 ns");
      pwm_check(100 ns, 25 ns, 1, "active_time_tolerance -1 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.active_time_tolerance := 0 ns;

      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, D < 0");
      pwm_check_duty(-0.1, 1, "D -0.1", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, D > 1");
      pwm_check_duty(1.1, 1, "D 1.1", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, k 0");
      pwm_check_duty(0.5, 0, "k 0", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty without timeout");
      pwm_check_duty(0.5, 1, "no timeout", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty 1.0, timeout 0 ns");
      pwm_check_duty(1.0, 1, "D 1.0, timeout 0 ns", pwm_obs, ERROR, 0 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.duty_tolerance := -0.1;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, duty_tolerance < 0");
      pwm_check_duty(0.5, 1, "duty_tolerance -0.1", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.duty_tolerance := 1.1;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, duty_tolerance > 1");
      pwm_check_duty(0.5, 1, "duty_tolerance 1.1", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.duty_tolerance := 0.0;
      v_config.duty_rounding_margin := -1.0e-12;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "check_duty, duty_rounding_margin < 0");
      pwm_check_duty(0.5, 1, "duty_rounding_margin -1e-12", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.duty_rounding_margin := C_PWM_BFM_CONFIG_DEFAULT.duty_rounding_margin;
      check_completion(0 ns, "rejected calls use no time");

      log(ID_LOG_HDR, "TC-109: a valid call afterwards still works", C_SCOPE);
      stimulate(pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "valid after invalid", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_110" then
      -- REQ-112: duty cycle check, independent of the period
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-110: D = 0.25 +-0.01", C_SCOPE);
      v_config.duty_tolerance := 0.01;
      stimulate(pwm_wave(100 ns, 25 ns, 3) & seg('1', 25 ns));
      pwm_check_duty(0.25, 3, "25/100 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(300 ns, "25/100 ns, k=3");
      await_stimulus;
      stimulate(pwm_wave(1 us, 250 ns, 3) & seg('1', 25 ns));
      pwm_check_duty(0.25, 3, "250 ns/1 us", pwm_obs, ERROR, 3 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      stimulate(pwm_wave(100 ns, 26 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "26/100 ns: deviation equal to the tolerance", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      stimulate(pwm_wave(100 ns, 24 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "24/100 ns: deviation equal to the tolerance", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "27/100 ns");
      stimulate(pwm_wave(100 ns, 27 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "27/100 ns", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "24 ns - 1 unit");
      stimulate(pwm_wave(100 ns, 24 ns - C_RESOLUTION, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "24 ns - 1 unit", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      increment_expected_alerts(WARNING, 1, "27/100 ns in period 2/3, WARNING");
      stimulate(pwm_wave(100 ns, 25 ns, 1) & pwm_wave(100 ns, 27 ns, 1) & pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 3, "period 2 wrong", pwm_obs, WARNING, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-110: duty_rounding_margin 0.0: real rounding fails a deviation equal to the tolerance", C_SCOPE);
      v_config.duty_rounding_margin := 0.0;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "26/100 ns without rounding margin");
      stimulate(pwm_wave(100 ns, 26 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "26/100 ns, no rounding margin", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.duty_rounding_margin := C_PWM_BFM_CONFIG_DEFAULT.duty_rounding_margin;

      log(ID_LOG_HDR, "TC-110: tolerance 0.0: exact duty passes", C_SCOPE);
      v_config.duty_tolerance := 0.0;
      stimulate(pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check_duty(0.25, 1, "exact", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-110: active-low", C_SCOPE);
      v_config.polarity := ACTIVE_LOW;
      set_line('1');
      stimulate(pwm_wave(100 ns, 25 ns, 2, '0') & seg('0', 25 ns), '1');
      pwm_check_duty(0.25, 2, "active-low", pwm_obs, ERROR, 1 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

    --============================================================================================================================
    elsif GC_TESTCASE = "TC_111" then
      -- REQ-113: per-edge timeout, per-call override, 0 ns = never
      --============================================================================================================================
      log(ID_LOG_HDR, "TC-111: config.timeout 50 ns is too short for the 75 ns gap; the per-call 200 ns overrides it", C_SCOPE);
      v_config.timeout := 50 ns;
      increment_expected_alerts_and_stop_limit(ERROR, 1, "config.timeout 50 ns");
      stimulate(pwm_wave(100 ns, 25 ns, 2) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 2, "config.timeout 50 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(75 ns, "config.timeout 50 ns: inactive edge at 25 ns + 50 ns");
      await_stimulus;
      stimulate(pwm_wave(100 ns, 25 ns, 2) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 2, "per-call 200 ns", pwm_obs, ERROR, 200 ns, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.timeout := 200 ns;
      stimulate(pwm_wave(100 ns, 25 ns, 2) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 2, "config.timeout 200 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;
      v_config.timeout := C_UNDEFINED_TIME;

      log(ID_LOG_HDR, "TC-111: the timeout is per edge: k=100, T=1 us, timeout 2 us", C_SCOPE);
      stimulate(pwm_wave(1 us, 250 ns, 100) & seg('1', 250 ns));
      pwm_check(1 us, 250 ns, 100, "k=100", pwm_obs, ERROR, 2 us, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(100 us, "k=100");
      await_stimulus;
      stimulate(pwm_wave(1 us, 250 ns, 100) & seg('1', 250 ns));
      pwm_check_duty(0.25, 100, "k=100", pwm_obs, ERROR, 2 us, C_SCOPE, shared_msg_id_panel, v_config);
      await_stimulus;

      log(ID_LOG_HDR, "TC-111: timeout 0 ns waits without limit (10 us of constant level first)", C_SCOPE);
      stimulate(seg('0', 10 us) & pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_measure(v_result, "timeout 0 ns", pwm_obs, 0 ns, C_SCOPE, shared_msg_id_panel, v_config);
      check_measurement(100 ns, 25 ns, "timeout 0 ns");
      check_completion(10.1 us, "timeout 0 ns");
      await_stimulus;
      v_config.timeout := 0 ns;
      stimulate(seg('0', 10 us) & pwm_wave(100 ns, 25 ns, 1) & seg('1', 25 ns));
      pwm_check(100 ns, 25 ns, 1, "config.timeout 0 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      check_completion(10.1 us, "config.timeout 0 ns");
      await_stimulus;
      v_config.timeout := C_UNDEFINED_TIME;

      log(ID_LOG_HDR, "TC-111: negative timeout", C_SCOPE);
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "timeout -5 ns");
      pwm_measure(v_result, "timeout -5 ns", pwm_obs, -5 ns, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.timeout := -5 ns;
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, "config.timeout -5 ns");
      pwm_check(100 ns, 25 ns, 1, "config.timeout -5 ns", pwm_obs, ERROR, C_UNDEFINED_TIME, C_SCOPE, shared_msg_id_panel, v_config);
      v_config.timeout := C_UNDEFINED_TIME;

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
