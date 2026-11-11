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
-- with the decoder checker in rotary_encoder_tb_pkg. GC_TESTCASE selects the test case by name.
entity rotary_encoder_vvc_tb is
  generic(
    GC_TESTCASE : string := "UVVM"
  );
end entity;

-- Test case architecture
architecture func of rotary_encoder_vvc_tb is

  constant C_SCOPE : string := C_TB_SCOPE_DEFAULT;

  -- VVC instances of the test harness; each logs under its own id
  constant C_ENC1 : positive := 1;
  constant C_ENC2 : positive := 2;
  constant C_ENC3 : positive := 3;

  -- Geometry of the default configuration, computed here rather than taken from the BFM
  constant C_DEFAULT       : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
  constant C_CPR           : positive := C_DEFAULT.cycles_per_rev;                   -- 20
  constant C_EDGES_PER_REV : positive := C_EDGES_PER_CYCLE * C_CPR;                   -- 80
  constant C_DEG_PER_EDGE  : real     := real(C_DEG_PER_REV) / real(C_EDGES_PER_REV); -- 4.5

  -- Speeds. C_TPE where the timing is not under test. Angle moves run at C_TIME_PER_DEG per degree, so expected times
  -- read as angles (4.5 us per edge: 1 deg = 1 us).
  constant C_TPE          : time := 100 ns;
  constant C_TIME_PER_DEG : time := 1 us;
  constant C_TPE_ANGLE    : time := C_TIME_PER_DEG * C_DEG_PER_EDGE;
  -- rpm form: integer rpm, so that every edge and end time is a whole number of ns
  constant C_RPM_FAST     : positive := 6000; -- 125 us per edge
  constant C_RPM_SLOW     : positive := 60;   -- 12.5 ms per edge, 360 deg per second

  constant C_QUIET_TIME    : time := 1 us;    -- Interval checked for the absence of events
  constant C_AWAIT_TIMEOUT : time := 1 sec;   -- Longer than any command of this testbench
  constant C_REAL_TOL      : real := 1.0e-9;  -- Tolerance of status angles

  -- Power-up of instance 3 through its generic in the test harness (30 deg, zero state 00). Hand values: the states from
  -- position 0 are 00 -> 10 -> 11 -> 01, so position 7 is 01; the default index (state 11, width 1, index position 0) is
  -- at position 2, so Z is inactive.
  constant C_ENC3_POSITION : integer                      := 7;
  constant C_ENC3_ANGLE    : real                         := 30.0;
  constant C_ENC3_AB       : std_logic_vector(1 downto 0) := "01";

  -- Debug only (waveform): the current test step, i.e. the last header written with log_step()
  signal dbg_step : string(1 to C_DBG_STEP_LENGTH) := dbg_text("");

begin

  -----------------------------------------------------------------------------
  -- Instantiate test harness
  -----------------------------------------------------------------------------
  i_test_harness : entity work.rotary_encoder_th;

  p_main : process is
    variable v_status     : t_rotary_encoder_status;
    variable v_cmd_idx    : natural;
    variable v_t_start    : time;
    variable v_count      : natural;
    variable v_rej_alerts : natural;
    variable v_rej_time   : time;
    variable v_rej_count  : natural;
    variable v_config     : t_rotary_encoder_bfm_config;
    variable v_edge       : natural;
    variable v_dir        : integer;
    variable v_position   : integer;

    -- Logs a test-step header and shows it in the waveform as dbg_step
    procedure log_step(
      constant msg : in string) is
    begin
      log(ID_LOG_HDR, msg, C_SCOPE);
      dbg_step <= dbg_text(msg);
    end procedure;

    procedure await(
      constant idx : in positive;
      constant msg : in string) is
    begin
      await_completion(ROTARY_ENCODER_VVCT, idx, C_AWAIT_TIMEOUT, msg);
    end procedure;

    -- Lets the logger record the events of the current time step (no simulation time passes)
    procedure wait_for_logger is
    begin
      wait for 0 ns;
      wait for 0 ns;
    end procedure;

    -- Reads the status of instance idx through the VVC into v_status
    procedure read_status(
      constant idx : in positive;
      constant msg : in string) is
    begin
      rotary_encoder_get_status(ROTARY_ENCODER_VVCT, idx, msg);
      v_cmd_idx := get_last_received_cmd_idx(ROTARY_ENCODER_VVCT, idx);
      await(idx, msg);
      fetch_result(ROTARY_ENCODER_VVCT, idx, v_cmd_idx, v_status, msg);
    end procedure;

    procedure check_status(
      constant idx          : in positive;
      constant exp_position : in integer;
      constant exp_angle    : in real;
      constant msg          : in string) is
    begin
      read_status(idx, msg);
      check_value(v_status.position, exp_position, ERROR, "status position: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_value_in_range(v_status.angle, exp_angle - C_REAL_TOL, exp_angle + C_REAL_TOL, ERROR, "status angle: " & msg, C_SCOPE,
                           ID_SEQUENCER_SUB);
    end procedure;

    -- Logged event event_idx of instance idx at expected +- tolerance
    procedure check_event_time(
      constant idx       : in positive;
      constant event_idx : in natural;
      constant expected  : in time;
      constant tolerance : in time;
      constant msg       : in string) is
    begin
      if shared_th_event_log.count(idx) <= event_idx then
        alert(ERROR, "event " & to_string(event_idx) & " missing: " & msg, C_SCOPE);
      else
        check_value_in_range(shared_th_event_log.get(idx, event_idx).time_stamp, expected - tolerance, expected + tolerance, ERROR,
                             "event " & to_string(event_idx) & " time: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      end if;
    end procedure;

    -- Direction of the A/B edge in log entry event_idx (>= 1) of instance idx, from the state of the entry before it:
    -- +1 forward, -1 reverse, 0 otherwise
    impure function edge_direction(
      constant idx       : in positive;
      constant event_idx : in positive) return integer is
      constant C_OLD : t_enc_event := shared_th_event_log.get(idx, event_idx - 1);
      constant C_NEW : t_enc_event := shared_th_event_log.get(idx, event_idx);
      constant C_STEP : integer := (gray_index(C_NEW.a, C_NEW.b) - gray_index(C_OLD.a, C_OLD.b) + C_EDGES_PER_CYCLE) mod
                                   C_EDGES_PER_CYCLE;
    begin
      if C_STEP = 1 then
        return 1;
      elsif C_STEP = C_EDGES_PER_CYCLE - 1 then
        return -1;
      end if;
      return 0;
    end function;

    -- Waits for the transaction info update of instance idx with status (the trigger pulses at every update)
    procedure await_transaction(
      constant idx    : in positive;
      constant status : in t_transaction_status;
      constant msg    : in string) is
    begin
      wait until global_rotary_encoder_vvc_transaction_trigger(idx) = '1' and
                 shared_rotary_encoder_vvc_transaction_info(idx).bt.transaction_status = status for C_AWAIT_TIMEOUT;
      check_value(shared_rotary_encoder_vvc_transaction_info(idx).bt.transaction_status = status, ERROR,
                  "transaction status " & to_upper(to_string(status)) & ": " & msg, C_SCOPE, ID_SEQUENCER_SUB);
    end procedure;

    -- Back to 0 deg (position 0) through the VVC and an empty log of instance idx
    procedure go_to_zero(
      constant idx : in positive) is
    begin
      rotary_encoder_set_angle(ROTARY_ENCODER_VVCT, idx, 0.0, "back to 0 deg");
      await(idx, "back to 0 deg");
      wait_for_logger;
      shared_th_event_log.clear(idx);
    end procedure;

    -- Rejected command on instance idx: exactly one new TB_ERROR, no time consumed, no event
    procedure begin_reject(
      constant idx : in positive;
      constant msg : in string) is
    begin
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1, msg);
      v_rej_alerts := get_alert_counter(TB_ERROR);
      v_rej_time   := now;
      v_rej_count  := shared_th_event_log.count(idx);
    end procedure;

    procedure end_reject(
      constant idx : in positive;
      constant msg : in string) is
    begin
      await(idx, msg);
      check_value(get_alert_counter(TB_ERROR) - v_rej_alerts, 1, ERROR, "one TB_ERROR: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      check_value(now, v_rej_time, ERROR, "no time consumed: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(idx), v_rej_count, ERROR, "no event: " & msg, C_SCOPE, ID_SEQUENCER_SUB);
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
    if GC_TESTCASE = "vvc_power_up_state" then
      -- The VVCs initialize from their generic at time 0: one logged entry each, at time 0, then nothing until the first move
      log_step("Instance 1 (defaults) and instance 3 (30 deg, zero state 00) at power-up");
      check_value(shared_th_event_log.count(C_ENC1), 1, ERROR, "one power-up entry of instance 1", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.get(C_ENC1, 0).time_stamp, 0 ns, ERROR, "instance 1 at time 0", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(std_logic_vector'(shared_th_event_log.get(C_ENC1, 0).a & shared_th_event_log.get(C_ENC1, 0).b),
                  C_DEFAULT.zero_state, MATCH_EXACT, ERROR, "instance 1 AB = zero state", C_SCOPE, msg_id => ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.get(C_ENC1, 0).z, '1', MATCH_EXACT, ERROR, "instance 1 Z active at 0 deg", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.count(C_ENC3), 1, ERROR, "one power-up entry of instance 3", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.get(C_ENC3, 0).time_stamp, 0 ns, ERROR, "instance 3 at time 0", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(std_logic_vector'(shared_th_event_log.get(C_ENC3, 0).a & shared_th_event_log.get(C_ENC3, 0).b), C_ENC3_AB,
                  MATCH_EXACT, ERROR, "instance 3 AB at 30 deg", C_SCOPE, msg_id => ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.get(C_ENC3, 0).z, '0', MATCH_EXACT, ERROR, "instance 3 Z inactive", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(C_ENC1, 0, 0.0, "instance 1 at power-up");
      check_status(C_ENC3, C_ENC3_POSITION, C_ENC3_ANGLE, "instance 3 at power-up");

      log_step("No event before the first move");
      wait for C_QUIET_TIME;
      for i in 1 to C_NUM_LOGS loop
        check_value(shared_th_event_log.count(i), 1, ERROR, "only the power-up entry of instance " & to_string(i), C_SCOPE,
                    ID_SEQUENCER_SUB);
        check_checker(shared_th_event_log, i, 0, "power-up of instance " & to_string(i));
      end loop;

      log_step("Zero state changed in the shared configuration: TB_ERROR at the next command, no edge");
      v_config            := shared_rotary_encoder_vvc_config(C_ENC1).bfm_config;
      v_config.zero_state := "00";      -- Valid, but not the zero state taken at power-up
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := v_config;
      begin_reject(C_ENC1, "edge move with a changed zero state");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1, C_TPE, "zero state changed");
      end_reject(C_ENC1, "edge move with a changed zero state");
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := C_DEFAULT;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1, C_TPE, "zero state restored");
      await(C_ENC1, "zero state restored");
      check_checker(shared_th_event_log, C_ENC1, 1, "the kept zero state still works");
      check_status(C_ENC1, 1, C_DEG_PER_EDGE, "after one edge");

    --============================================================================================================================
    elsif GC_TESTCASE = "hold_between_commands" then
      -- Between commands the outputs hold; each move continues from where the previous one ended
      log_step("Hold during insert_delay and an idle period after a move");
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 3, C_TPE, "3 edges");
      insert_delay(ROTARY_ENCODER_VVCT, C_ENC1, 100 * C_TPE, "hold for 100 edge intervals");
      await(C_ENC1, "move and delay");
      check_value(now - v_t_start, 103 * C_TPE, ERROR, "move and delay duration", C_SCOPE, ID_SEQUENCER_SUB);
      wait for 100 * C_TPE;               -- Idle, no command queued
      check_no_event(shared_th_event_log, C_ENC1, v_t_start + 3 * C_TPE, now, "hold after the move");
      check_checker(shared_th_event_log, C_ENC1, 3, "3 edges");

      log_step("Mixed forward and reverse moves back to back: every transition legal, edges evenly spaced");
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, 5, C_TPE, "5 back");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 2, C_TPE, "2 forward");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, 1, C_TPE, "1 back");
      await(C_ENC1, "mixed moves");
      check_edge_times(shared_th_event_log, C_ENC1, 0, v_t_start, 8, C_TPE, "mixed moves");
      check_checker(shared_th_event_log, C_ENC1, -4, "mixed moves");
      check_status(C_ENC1, -1, -C_DEG_PER_EDGE, "after the mixed moves");

    --============================================================================================================================
    elsif GC_TESTCASE = "vvc_commands" then
      log_step("A queue of 10 moves completes in order");
      -- Move i: i edges, forward for odd i, reverse for even i. Every move starts and ends in a state centre, so the edges
      -- of the whole queue lie at (k - 1/2) * C_TPE. The log still holds the power-up entry, so edge k is entry k.
      v_t_start := now;
      for i in 1 to 10 loop
        if i mod 2 = 1 then
          rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, i, C_TPE, "queued move " & to_string(i));
        else
          rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, i, C_TPE, "queued move " & to_string(i));
        end if;
      end loop;
      await(C_ENC1, "queue of 10 moves");
      check_value(now - v_t_start, 55 * C_TPE, ERROR, "queue duration: 1 + 2 + ... + 10 = 55 edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_edge_times(shared_th_event_log, C_ENC1, 1, v_t_start, 55, C_TPE, "queue of 10 moves");
      v_edge := 1;
      for i in 1 to 10 loop
        v_dir := 1 - 2 * ((i + 1) mod 2);
        for k in 1 to i loop
          check_value(edge_direction(C_ENC1, v_edge), v_dir, ERROR, "direction of edge " & to_string(k) & " of move " & to_string(i),
                      C_SCOPE, ID_SEQUENCER_SUB);
          v_edge := v_edge + 1;
        end loop;
      end loop;
      check_checker(shared_th_event_log, C_ENC1, -5, "queue of 10 moves");  -- 1 - 2 + 3 - ... - 10

      log_step("insert_delay and flush_command_queue");
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      insert_delay(ROTARY_ENCODER_VVCT, C_ENC1, C_QUIET_TIME, "delay before the move");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, C_TPE, "move after the delay");
      wait for C_QUIET_TIME + C_TPE;    -- The move is running
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, C_TPE, "flushed move 1");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, 4, C_TPE, "flushed move 2");
      flush_command_queue(ROTARY_ENCODER_VVCT, C_ENC1, "remove the two queued moves");
      await(C_ENC1, "the running move only");
      check_value(now - v_t_start, C_QUIET_TIME + 4 * C_TPE, ERROR, "the delay, then one move", C_SCOPE, ID_SEQUENCER_SUB);
      check_edge_times(shared_th_event_log, C_ENC1, 0, v_t_start + C_QUIET_TIME, 4, C_TPE, "move after the delay");
      wait for C_QUIET_TIME;
      check_checker(shared_th_event_log, C_ENC1, 4, "the flushed moves did not run");

      log_step("Transaction info: the parameters during a move, its effect at the end");
      read_status(C_ENC1, "position before the move");
      v_position := v_status.position;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, 4, C_TPE, "move with transaction info");
      wait for C_TPE;
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.operation = MOVE_EDGES, ERROR, "operation MOVE_EDGES",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.direction = REVERSE, ERROR, "direction", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.num_edges, 4, ERROR, "num_edges", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.time_per_edge, C_TPE, ERROR, "time_per_edge", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.transaction_status = IN_PROGRESS, ERROR, "IN_PROGRESS",
                  C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.edges, 0, ERROR, "no edge count while in progress",
                  C_SCOPE, ID_SEQUENCER_SUB);
      await_transaction(C_ENC1, COMPLETED, "move with transaction info");
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.edges, 4, ERROR, "edges at the end", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.status.position, v_position - 4, ERROR,
                  "position at the end", C_SCOPE, ID_SEQUENCER_SUB);
      await(C_ENC1, "move with transaction info");
      wait_for_logger;
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.transaction_status = INACTIVE, ERROR,
                  "INACTIVE after the move", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Transaction info: a rejected move ends with FAILED and no change");
      begin_reject(C_ENC1, "move with time_per_edge 0 ns");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1, 0 ns, "invalid speed");
      await_transaction(C_ENC1, FAILED, "rejected move");
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.edges, 0, ERROR, "no edge", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.status.position, v_position - 4, ERROR,
                  "position unchanged", C_SCOPE, ID_SEQUENCER_SUB);
      end_reject(C_ENC1, "move with time_per_edge 0 ns");

      log_step("Transaction info: the result of a status read");
      rotary_encoder_get_status(ROTARY_ENCODER_VVCT, C_ENC1, "status into the transaction info");
      await_transaction(C_ENC1, COMPLETED, "status read");
      check_value(shared_rotary_encoder_vvc_transaction_info(C_ENC1).bt.status.position, v_position - 4, ERROR,
                  "status position", C_SCOPE, ID_SEQUENCER_SUB);
      await(C_ENC1, "status read");

      log_step("Angle move, time form, from 0 deg: 2 edges, ends at 10 deg; status fields");
      go_to_zero(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_angle(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 10.0, C_TPE_ANGLE, "10 deg");
      await(C_ENC1, "10 deg");
      check_value(now - v_t_start, 10 * C_TIME_PER_DEG, ERROR, "10 deg duration", C_SCOPE, ID_SEQUENCER_SUB);
      -- Boundaries at 2.25 and 6.75 deg
      check_event_time(C_ENC1, 0, v_t_start + C_TIME_PER_DEG * (0.5 * C_DEG_PER_EDGE), 0 ns, "edge at 2.25 deg");
      check_event_time(C_ENC1, 1, v_t_start + C_TIME_PER_DEG * (1.5 * C_DEG_PER_EDGE), 0 ns, "edge at 6.75 deg");
      check_checker(shared_th_event_log, C_ENC1, 2, "10 deg");
      check_status(C_ENC1, 2, 10.0, "after 10 deg");
      check_value(v_status.ab, tb_state(C_DEFAULT.zero_state, 2), MATCH_EXACT, ERROR, "status ab", C_SCOPE,
                  msg_id => ID_SEQUENCER_SUB);
      check_value(v_status.index_active, false, ERROR, "status index_active", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.is_rotating, false, ERROR, "status is_rotating", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(v_status.rpm, 0.0, ERROR, "status rpm", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Centre state from 10 deg: 9 deg, position 2, zero time, no event");
      v_t_start := now;
      v_count   := shared_th_event_log.count(C_ENC1);
      rotary_encoder_center_state(ROTARY_ENCODER_VVCT, C_ENC1, "centre");
      await(C_ENC1, "centre");
      check_value(now, v_t_start, ERROR, "centre state in zero time", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(C_ENC1, 2, 2.0 * C_DEG_PER_EDGE, "after centre state");
      wait for C_QUIET_TIME;
      check_value(shared_th_event_log.count(C_ENC1), v_count, ERROR, "no event from centre state", C_SCOPE, ID_SEQUENCER_SUB);

      log_step("Angle move, rpm form: 9 deg at 60 rpm");
      go_to_zero(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_angle(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 9.0, real(C_RPM_SLOW), "9 deg at 60 rpm");
      await(C_ENC1, "9 deg at 60 rpm");
      check_value(now - v_t_start, ideal_angle_time(9, C_RPM_SLOW), ERROR, "9 deg duration", C_SCOPE, ID_SEQUENCER_SUB);
      check_edge_times_rpm(shared_th_event_log, C_ENC1, 0, v_t_start, 2, C_RPM_SLOW, C_CPR, "9 deg at 60 rpm");
      check_checker(shared_th_event_log, C_ENC1, 2, "9 deg at 60 rpm");

      log_step("Edge move, rpm form: 4 edges at 6000 rpm");
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, real(C_RPM_FAST), "4 edges at 6000 rpm");
      await(C_ENC1, "4 edges at 6000 rpm");
      check_value(now, ideal_move_time(v_t_start, 4, C_RPM_FAST, C_CPR), ERROR, "end of 4 edges at 6000 rpm", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_edge_times_rpm(shared_th_event_log, C_ENC1, 0, v_t_start, 4, C_RPM_FAST, C_CPR, "4 edges at 6000 rpm");
      check_checker(shared_th_event_log, C_ENC1, 4, "4 edges at 6000 rpm");

      log_step("Move to state queued after a 1.125 deg angle move: resolved at execution time");
      -- Time form, 1 us per edge (T). From 1.125 deg (a quarter edge angle) to the centre of the next 00 at 9 deg: edges at
      -- 0.25 T and 1.25 T after the move to state starts, which is 0.25 T after the angle move started.
      go_to_zero(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_angle(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1.125, 1 us, "a quarter edge angle");
      rotary_encoder_move_to_state(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, "00", 1, 1 us, "to the next 00");
      await(C_ENC1, "to the next 00");
      check_value(now - v_t_start, 2 us, ERROR, "0.25 T + 1.75 T", C_SCOPE, ID_SEQUENCER_SUB);
      check_event_time(C_ENC1, 0, v_t_start + 500 ns, 0 ns, "first edge at 0.25 T + 0.25 T");
      check_event_time(C_ENC1, 1, v_t_start + 1500 ns, 0 ns, "second edge at 0.25 T + 1.25 T");
      check_checker(shared_th_event_log, C_ENC1, 2, "to the next 00");
      check_status(C_ENC1, 2, 2.0 * C_DEG_PER_EDGE, "at the centre of 00");

      log_step("Move to state, rpm form: forward to the next 10 at 60 rpm");
      -- From position 2 (00) the next 10 is position 3: one edge at half an edge interval, done after one interval
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_to_state(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, "10", 1, real(C_RPM_SLOW), "to the next 10");
      await(C_ENC1, "to the next 10");
      check_value(now, ideal_move_time(v_t_start, 1, C_RPM_SLOW, C_CPR), ERROR, "end of the move to 10", C_SCOPE, ID_SEQUENCER_SUB);
      check_edge_times_rpm(shared_th_event_log, C_ENC1, 0, v_t_start, 1, C_RPM_SLOW, C_CPR, "to the next 10");
      check_status(C_ENC1, 3, 3.0 * C_DEG_PER_EDGE, "at the centre of 10");

      log_step("Fault events: set angle, jump");
      shared_th_event_log.clear(C_ENC1);
      -- From position 3 to 30 deg (position 7): 4 edges apart, so A and B end where they were
      rotary_encoder_set_angle(ROTARY_ENCODER_VVCT, C_ENC1, 30.0, "to 30 deg");
      await(C_ENC1, "to 30 deg");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ENC1), 0, ERROR, "no A/B event for 4 edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_status(C_ENC1, 7, 30.0, "after set angle");
      -- 2 edges in zero time: A and B change in one delta, an illegal transition
      v_t_start := now;
      rotary_encoder_jump_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 2, "jump 2 edges");
      await(C_ENC1, "jump 2 edges");
      wait_for_logger;
      check_value(now, v_t_start, ERROR, "jump in zero time", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ENC1, 0, "jump 2 edges", exp_illegal => 1);
      check_status(C_ENC1, 9, 30.0 + 2.0 * C_DEG_PER_EDGE, "after the jump");

      log_step("Logging: the move log with ID_BFM disabled, then enabled (see the log file)");
      disable_log_msg(ROTARY_ENCODER_VVCT, C_ENC1, ID_BFM, "no move log");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1, C_TPE, "move without log");
      await(C_ENC1, "move without log");
      enable_log_msg(ROTARY_ENCODER_VVCT, C_ENC1, ID_BFM, "move log again");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, REVERSE, 1, C_TPE, "move with log");
      await(C_ENC1, "move with log");

    --============================================================================================================================
    elsif GC_TESTCASE = "terminate_move" then
      -- terminate_current_command halts a move at once, at the current angle
      log_step("Terminate a 20-edge move after 10.25 edge intervals");
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 20, C_TPE, "20 edges");
      wait for 10 * C_TPE + C_TPE / 4;
      terminate_current_command(ROTARY_ENCODER_VVCT, C_ENC1, "stop the move");
      await(C_ENC1, "terminated move");
      check_value(now - v_t_start, 10 * C_TPE + C_TPE / 4, ERROR, "the move completes at the terminate", C_SCOPE, ID_SEQUENCER_SUB);
      v_t_start := now;
      wait for C_QUIET_TIME;
      check_no_event(shared_th_event_log, C_ENC1, v_t_start, now, "no edge after the terminate");
      check_checker(shared_th_event_log, C_ENC1, 10, "10 edges before the terminate");
      check_status(C_ENC1, 10, 10.25 * C_DEG_PER_EDGE, "at the reached angle");

      log_step("The next move continues from the reached angle");
      -- A quarter edge angle past the centre of position 10: the next boundary is a quarter edge interval away
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 2, C_TPE, "2 edges");
      await(C_ENC1, "2 edges");
      check_event_time(C_ENC1, 0, v_t_start + C_TPE / 4, 0 ns, "first edge after a quarter interval");
      check_checker(shared_th_event_log, C_ENC1, 2, "2 edges after the terminate");

    --============================================================================================================================
    elsif GC_TESTCASE = "multiple_instances" then
      -- Two instances move at the same time at different speeds; each log sees only its own edges
      log_step("Instance 1: 8 edges forward at 100 ns, instance 2: 6 edges reverse at 150 ns, at the same time");
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 8, C_TPE, "instance 1");
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC2, REVERSE, 6, 150 ns, "instance 2");
      await(C_ENC1, "instance 1");
      await(C_ENC2, "instance 2");
      -- Entry 0 of each log is the power-up
      check_edge_times(shared_th_event_log, C_ENC1, 1, v_t_start, 8, C_TPE, "instance 1");
      check_edge_times(shared_th_event_log, C_ENC2, 1, v_t_start, 6, 150 ns, "instance 2");
      check_value(shared_th_event_log.count(C_ENC1), 1 + 8, ERROR, "instance 1: only its own edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.count(C_ENC2), 1 + 6, ERROR, "instance 2: only its own edges", C_SCOPE, ID_SEQUENCER_SUB);
      check_value(shared_th_event_log.count(C_ENC3), 1, ERROR, "instance 3: no edge", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ENC1, 8, "instance 1");
      check_checker(shared_th_event_log, C_ENC2, -6, "instance 2");
      check_status(C_ENC1, 8, 8.0 * C_DEG_PER_EDGE, "instance 1");
      check_status(C_ENC2, -6, -6.0 * C_DEG_PER_EDGE, "instance 2");

    --============================================================================================================================
    elsif GC_TESTCASE = "config_change_between_moves" then
      -- A change of the shared configuration during a move takes effect at the next command
      log_step("Bounce enabled in the shared configuration during a move: only the next move bounces");
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, 1 us, "move without bounce");
      wait for 1500 ns;                 -- Between edge 1 and edge 2
      v_config                := C_DEFAULT;
      v_config.bounce_enabled := true;
      v_config.bounce_pulses  := 1;
      v_config.bounce_window  := 200 ns; -- Ends long before the next edge
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := v_config;
      await(C_ENC1, "move without bounce");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ENC1), 1 + 4, ERROR, "power-up entry and 4 edges, no bounce", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_edge_times(shared_th_event_log, C_ENC1, 1, v_t_start, 4, 1 us, "move without bounce");
      check_checker(shared_th_event_log, C_ENC1, 4, "move without bounce");

      shared_th_event_log.clear(C_ENC1);
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, 1 us, "move with bounce");
      await(C_ENC1, "move with bounce");
      wait_for_logger;
      -- Each edge plus 2 toggles of one bounce pulse
      check_value(shared_th_event_log.count(C_ENC1), 4 * (1 + 2), ERROR, "4 edges with one bounce pulse each", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ENC1, 4, "move with bounce");
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := C_DEFAULT;

      log_step("Stuck B set between moves: B goes to the stuck level at the start of the next move");
      -- At position 8 the state is 11 (8 = 2 cycles), so B is high. Forward from 11: 01, 00, 10, 11, i.e. A, B, A, B edges;
      -- with B stuck only the two A edges remain.
      v_config         := C_DEFAULT;
      v_config.b_stuck := '0';
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := v_config;
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 4, 1 us, "move with B stuck");
      await(C_ENC1, "move with B stuck");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ENC1), 1 + 2, ERROR, "B to its stuck level, then the two A edges", C_SCOPE,
                  ID_SEQUENCER_SUB);
      check_event_time(C_ENC1, 0, v_t_start, 0 ns, "B stuck at the move start");
      check_value(shared_th_event_log.get(C_ENC1, 0).b_changed and not shared_th_event_log.get(C_ENC1, 0).a_changed and
                  shared_th_event_log.get(C_ENC1, 0).b = '0', ERROR, "first entry: B to '0' only", C_SCOPE, ID_SEQUENCER_SUB);
      check_checker(shared_th_event_log, C_ENC1, -1, "B stuck: decoded as reverse, reverse, forward");

      log_step("Stuck B released between moves: B follows the state at the start of the next move");
      -- Position 12: state 11 again, B high. One edge forward to 01 changes A.
      shared_rotary_encoder_vvc_config(C_ENC1).bfm_config := C_DEFAULT;
      shared_th_event_log.clear(C_ENC1);
      v_t_start := now;
      rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, C_ENC1, FORWARD, 1, 1 us, "move after the release");
      await(C_ENC1, "move after the release");
      wait_for_logger;
      check_value(shared_th_event_log.count(C_ENC1), 2, ERROR, "B released, then one A edge", C_SCOPE, ID_SEQUENCER_SUB);
      check_event_time(C_ENC1, 0, v_t_start, 0 ns, "B released at the move start");
      check_value(shared_th_event_log.get(C_ENC1, 0).b_changed and shared_th_event_log.get(C_ENC1, 0).b = '1', ERROR,
                  "first entry: B back to '1'", C_SCOPE, ID_SEQUENCER_SUB);
      check_event_time(C_ENC1, 1, v_t_start + 500 ns, 0 ns, "the A edge at half an edge interval");
      check_status(C_ENC1, 13, 13.0 * C_DEG_PER_EDGE, "the edges during the stuck period count");

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
