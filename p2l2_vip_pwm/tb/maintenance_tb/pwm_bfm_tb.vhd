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
-- expected edges come from the reference model in pwm_tb_pkg. Test case IDs refer to doc/pwm_vvc_reqs.md.
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

  shared variable edge_log : t_edge_log;

begin

  p_edge_logger : process
  begin
    wait on pwm;
    edge_log.add(now, pwm);
  end process p_edge_logger;

  p_main : process
    variable v_config : t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT;
    variable v_seed1  : positive;
    variable v_seed2  : positive;
    variable v_start  : time;
    variable v_level  : std_logic;
    variable v_edges_a : t_edge_array(0 to 1999);
    variable v_edges_b : t_edge_array(0 to 1999);
    variable v_edge    : t_edge;
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
      return ((2 * (period / C_RESOLUTION) * count + resolution) / (2 * resolution)) * C_RESOLUTION;
    end function;

    -- Starts a new edge log at the current time, with the line idle
    procedure start_test is
    begin
      settle;
      v_level := pwm;
      edge_log.clear;
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
      check_edges(edge_log, expected_edges(v_start, v_level, params, v_config.alignment,
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
      check_edges(edge_log, v_expected, msg, C_SCOPE);
    end procedure;

    -- Checks an invalid call of a generate procedure: called right after start_test, it must not use time or touch
    -- the line. The TB_ERROR is expected by the caller.
    procedure check_rejected(
      constant msg : string) is
    begin
      check_value(now, v_start, ERROR, "no time used: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      settle;
      check_value(edge_log.count, 0, ERROR, "line unchanged: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
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
      check_jittered_edges(edge_log, expected_edges(v_start, v_level, repeat_period(period, active_time, num_periods),
                                                    v_config.alignment, tb_active_level(v_config.polarity),
                                                    tb_idle_value(v_config.polarity, v_config.idle_level)),
                           v_config.jitter, msg, C_SCOPE);
    end procedure;

    -- TC-012: the logged edges relative to v_start
    procedure save_edges(
      variable edges : out t_edge_array) is
      variable v_edge : t_edge;
    begin
      for i in 0 to minimum(edge_log.count, edges'length) - 1 loop
        v_edge := edge_log.get(i);
        edges(edges'low + i) := (v_edge.time_stamp - v_start, v_edge.level);
      end loop;
    end procedure;

    constant C_DUTY_SEQUENCE : t_period_param_array := ((10 ns, 5 ns), (10 ns, 0 ns), (10 ns, 5 ns), (10 ns, 10 ns), (10 ns, 5 ns));

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
        check_value(edge_log.count, 0, ERROR, "0 %: no edges", C_SCOPE);
        start_test;
        pwm_generate(10 ns, 10 ns, 10, "100 %", pwm, C_SCOPE, shared_msg_id_panel, v_config);
        check_generated(repeat_period(10 ns, 10 ns, 10), "100 % " & to_string(alignment));
        check_value(edge_log.count, 2, ERROR, "100 %: only the edges from and to idle", C_SCOPE);

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
      test_jitter(10 * C_RESOLUTION, 5 * C_RESOLUTION, 500, "j 5 ns, T 10 units");

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
