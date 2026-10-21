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

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.pwm_bfm_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;
use work.transaction_pkg.all;

--==========================================================================================
--==========================================================================================
entity pwm_vvc is
  generic (
    GC_INSTANCE_IDX                          : natural                   := 1;
    GC_ROLE                                  : t_pwm_role                := GENERATOR; -- Fixed at elaboration
    GC_PWM_BFM_CONFIG                        : t_pwm_bfm_config          := C_PWM_BFM_CONFIG_DEFAULT;
    GC_CMD_QUEUE_COUNT_MAX                   : natural                   := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural                   := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level             := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural                   := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural                   := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level             := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port (
    -- GENERATOR: driven with the idle level from time 0 and the waveform. OBSERVER: always driven 'Z', only read.
    pwm_vvc_if                  : inout std_logic := 'Z'
  );
end entity pwm_vvc;

--==========================================================================================
--==========================================================================================
architecture behave of pwm_vvc is

  constant C_SCOPE      : string       := get_scope_for_log(C_VVC_NAME, GC_INSTANCE_IDX);
  constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_SCOPE, C_VVC_NAME, GC_INSTANCE_IDX, NA);

  signal executor_is_busy                   : boolean := false;
  signal queue_is_increasing                : boolean := false;
  signal last_cmd_idx_executed              : natural := 0;
  signal terminate_current_cmd              : t_flag_record;
  signal entry_num_in_vvc_activity_register : integer;

  -- Generator role: run state shared by the executor and p_waveform
  type t_run_mode is (IDLE, BOUNDED, CONTINUOUS);
  type t_run_request is record
    idx         : natural;              -- incremented with every request
    period      : time;
    active_time : time;
    num_periods : natural;              -- 0: continuous
  end record t_run_request;
  constant C_RUN_REQUEST_DEFAULT : t_run_request := (0, 0 ns, 0 ns, 0);

  -- Executor -> p_waveform
  signal start_req  : t_run_request := C_RUN_REQUEST_DEFAULT; -- GENERATE_PERIODS, START
  signal update_req : t_run_request := C_RUN_REQUEST_DEFAULT; -- UPDATE, latched at the next period boundary
  signal stop_req   : natural       := 0;                     -- incremented by STOP, checked at the period boundaries
  signal abort_req  : boolean       := false;                 -- toggled by ABORT and terminate_current_command
  -- p_waveform -> executor
  signal run_mode   : t_run_mode    := IDLE;
  signal start_ack  : natural       := 0; -- idx of the last start request whose first period has begun
  signal update_ack : natural       := 0; -- idx of the last update request latched at a period boundary

  -- Instantiation of the element dedicated executor
  shared variable command_queue : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable result_queue  : work.td_result_queue_pkg.t_generic_queue;

  alias vvc_config : t_vvc_config is shared_pwm_vvc_config(GC_INSTANCE_IDX);
  alias vvc_status : t_vvc_status is shared_pwm_vvc_status(GC_INSTANCE_IDX);
  -- Transaction info
  alias vvc_transaction_info_trigger        : std_logic           is global_pwm_vvc_transaction_trigger(GC_INSTANCE_IDX);
  alias vvc_transaction_info                : t_transaction_group is shared_pwm_vvc_transaction_info(GC_INSTANCE_IDX);

begin

  --==========================================================================================
  -- Constructor
  -- - Set up the defaults and show constructor if enabled
  --==========================================================================================
  work.td_vvc_entity_support_pkg.vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, vvc_config, command_queue, result_queue, GC_PWM_BFM_CONFIG,
                  GC_CMD_QUEUE_COUNT_MAX, GC_CMD_QUEUE_COUNT_THRESHOLD, GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  GC_RESULT_QUEUE_COUNT_MAX, GC_RESULT_QUEUE_COUNT_THRESHOLD, GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  C_VVC_MAX_INSTANCE_NUM);
  --==========================================================================================

  --==========================================================================================
  -- Command interpreter
  -- - Interpret, decode and acknowledge commands from the central sequencer
  --==========================================================================================
  p_cmd_interpreter : process is
    variable v_cmd_has_been_acked : boolean; -- Indicates if acknowledge_cmd() has been called for the current shared_vvc_cmd
    variable v_local_vvc_cmd      : t_vvc_cmd_record := C_VVC_CMD_DEFAULT;
    variable v_msg_id_panel       : t_msg_id_panel;
    variable v_temp_msg_id_panel  : t_msg_id_panel; --UVVM: temporary fix for HVVC, remove in v3.0
  begin

    -- 0. Initialize the process prior to first command
    work.td_vvc_entity_support_pkg.initialize_interpreter(terminate_current_cmd, global_awaiting_completion);
    -- initialise shared_vvc_last_received_cmd_idx for channel and instance
    shared_vvc_last_received_cmd_idx(NA, GC_INSTANCE_IDX) := 0;

    -- Register VVC in vvc activity register
    entry_num_in_vvc_activity_register <= shared_vvc_activity_register.priv_register_vvc(name     => C_VVC_NAME,
                                                                                         instance => GC_INSTANCE_IDX);
    -- Set initial value of v_msg_id_panel to msg_id_panel in config
    v_msg_id_panel := vvc_config.msg_id_panel;

    -- Then for every single command from the sequencer
    loop  -- basically as long as new commands are received

      -- 1. wait until command targeted at this VVC. Must match VVC name, instance and channel (if applicable)
      --    releases global semaphore
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.await_cmd_from_sequencer(C_VVC_LABELS, vvc_config, THIS_VVCT, VVC_BROADCAST, global_vvc_busy, global_vvc_ack, v_local_vvc_cmd);
      v_cmd_has_been_acked := false; -- Clear flag
      -- Update shared_vvc_last_received_cmd_idx with received command index
      shared_vvc_last_received_cmd_idx(NA, GC_INSTANCE_IDX) := v_local_vvc_cmd.cmd_idx;
      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_local_vvc_cmd, vvc_config);

      -- 2a. Put command on the executor if intended for the executor
      -------------------------------------------------------------------------
      if v_local_vvc_cmd.command_type = QUEUED then
        work.td_vvc_entity_support_pkg.put_command_on_queue(v_local_vvc_cmd, command_queue, vvc_status, queue_is_increasing);

      -- 2b. Otherwise command is intended for immediate response
      -------------------------------------------------------------------------
      elsif v_local_vvc_cmd.command_type = IMMEDIATE then

        --UVVM: temporary fix for HVVC, remove two lines below in v3.0
        if v_local_vvc_cmd.operation /= DISABLE_LOG_MSG and v_local_vvc_cmd.operation /= ENABLE_LOG_MSG then
          v_temp_msg_id_panel     := vvc_config.msg_id_panel;
          vvc_config.msg_id_panel := v_msg_id_panel;
        end if;

        case v_local_vvc_cmd.operation is

          when DISABLE_LOG_MSG =>
            uvvm_util.methods_pkg.disable_log_msg(v_local_vvc_cmd.msg_id, vvc_config.msg_id_panel, to_string(v_local_vvc_cmd.msg) & format_command_idx(v_local_vvc_cmd), C_SCOPE, v_local_vvc_cmd.quietness);

          when ENABLE_LOG_MSG =>
            uvvm_util.methods_pkg.enable_log_msg(v_local_vvc_cmd.msg_id, vvc_config.msg_id_panel, to_string(v_local_vvc_cmd.msg) & format_command_idx(v_local_vvc_cmd), C_SCOPE, v_local_vvc_cmd.quietness);

          when FLUSH_COMMAND_QUEUE =>
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, command_queue, vvc_config, vvc_status, C_VVC_LABELS);

          when TERMINATE_CURRENT_COMMAND =>
            work.td_vvc_entity_support_pkg.interpreter_terminate_current_command(v_local_vvc_cmd, vvc_config, C_VVC_LABELS, terminate_current_cmd, executor_is_busy);

          when FETCH_RESULT =>
            work.td_vvc_entity_support_pkg.interpreter_fetch_result(result_queue, entry_num_in_vvc_activity_register, v_local_vvc_cmd, vvc_config, C_VVC_LABELS, shared_vvc_response);

          when others =>
            tb_error("Unsupported command received for IMMEDIATE execution: '" & to_string(v_local_vvc_cmd.operation) & "'", C_SCOPE);

        end case;

        --UVVM: temporary fix for HVVC, remove line below in v3.0
        if v_local_vvc_cmd.operation /= DISABLE_LOG_MSG and v_local_vvc_cmd.operation /= ENABLE_LOG_MSG then
          vvc_config.msg_id_panel := v_temp_msg_id_panel;
        end if;

      else
        tb_error("command_type is not IMMEDIATE or QUEUED", C_SCOPE);
      end if;

      -- 3. Acknowledge command after running or queuing the command
      -------------------------------------------------------------------------
      if not v_cmd_has_been_acked then
        work.td_target_support_pkg.acknowledge_cmd(global_vvc_ack, v_local_vvc_cmd.cmd_idx);
      end if;

    end loop;
    wait;
  end process p_cmd_interpreter;
  --==========================================================================================

  --==========================================================================================
  -- Command executor
  -- - Fetch and execute the commands
  --==========================================================================================
  p_cmd_executor : process is
    constant C_EXECUTOR_ID                            : natural := 0;
    variable v_cmd                                    : t_vvc_cmd_record;
    variable v_result                                 : t_vvc_result; -- See vvc_cmd_pkg
    variable v_timestamp_start_of_current_bfm_access  : time    := 0 ns;
    variable v_timestamp_start_of_last_bfm_access     : time    := 0 ns;
    variable v_timestamp_end_of_last_bfm_access       : time    := 0 ns;
    variable v_command_is_bfm_access                  : boolean := false;
    variable v_prev_command_was_bfm_access            : boolean := false;
    variable v_msg_id_panel                           : t_msg_id_panel;
    variable v_request_idx                            : natural;

    -- Wrong role: an ERROR, and the command is skipped (as I2C master commands in slave mode)
    impure function role_is(
      constant role : t_pwm_role
    ) return boolean is
    begin
      if GC_ROLE /= role then
        alert(ERROR, to_string(v_cmd.proc_call) & " called when VVC is in " & to_upper(to_string(GC_ROLE)) & " role." & format_msg(v_cmd), C_SCOPE);
        return false;
      end if;
      return true;
    end function;

    -- Run-state error: a TB_ERROR, and the command is skipped
    impure function run_mode_is(
      constant expected : t_run_mode;
      constant problem  : string
    ) return boolean is
    begin
      if run_mode /= expected then
        alert(TB_ERROR, to_string(v_cmd.proc_call) & "=> Failed. " & problem & format_msg(v_cmd), C_SCOPE);
        return false;
      end if;
      return true;
    end function;

    -- Parameter check of GENERATE_PERIODS, START and UPDATE. Raises at most one TB_ERROR.
    impure function parameters_are_valid(
      constant check_num_periods : boolean;
      constant check_jitter      : boolean
    ) return boolean is
      constant C_FAILED : string := to_string(v_cmd.proc_call) & "=> Failed. ";
    begin
      if v_cmd.period <= 0 ns then
        alert(TB_ERROR, C_FAILED & "period must be > 0 ns, was " & to_string(v_cmd.period, ns) & "." & format_msg(v_cmd), C_SCOPE);
      elsif v_cmd.active_time < 0 ns then
        alert(TB_ERROR, C_FAILED & "active_time must be >= 0 ns, was " & to_string(v_cmd.active_time, ns) & "." & format_msg(v_cmd), C_SCOPE);
      elsif v_cmd.active_time > v_cmd.period then
        alert(TB_ERROR, C_FAILED & "active_time (" & to_string(v_cmd.active_time, ns) & ") must not exceed period (" &
              to_string(v_cmd.period, ns) & ")." & format_msg(v_cmd), C_SCOPE);
      elsif check_num_periods and v_cmd.num_periods < 1 then
        alert(TB_ERROR, C_FAILED & "num_periods must be >= 1, was " & to_string(v_cmd.num_periods) & "." & format_msg(v_cmd), C_SCOPE);
      elsif check_jitter and vvc_config.bfm_config.jitter < 0 ns then
        alert(TB_ERROR, C_FAILED & "config.jitter must be >= 0 ns, was " & to_string(vvc_config.bfm_config.jitter, ns) & "." &
              format_msg(v_cmd), C_SCOPE);
      else
        return true;
      end if;
      return false;
    end function;

    -- Generator settings for the log
    impure function config_to_string return string is
    begin
      return to_upper(to_string(vvc_config.bfm_config.polarity)) & ", " & to_upper(to_string(vvc_config.bfm_config.alignment)) & ", " &
             to_upper(to_string(vvc_config.bfm_config.idle_level)) & ", jitter " & to_string(vvc_config.bfm_config.jitter, ns);
    end function;

    -- Starts a run in p_waveform and waits until its first period has begun
    procedure start_run(
      constant num_periods : natural
    ) is
    begin
      v_request_idx := start_req.idx + 1;
      start_req     <= (v_request_idx, v_cmd.period, v_cmd.active_time, num_periods);
      wait until start_ack = v_request_idx;
    end procedure;

    -- Aborts the run in p_waveform: idle level at once
    procedure abort_run is
    begin
      abort_req <= not abort_req;
      wait until run_mode = IDLE;
    end procedure;

    -- Transaction info of the current command
    procedure set_transaction_info(
      constant status : t_transaction_status
    ) is
    begin
      set_global_vvc_transaction_info(vvc_transaction_info_trigger, vvc_transaction_info, v_cmd, vvc_config, status, C_SCOPE);
    end procedure;

  begin

    -- 0. Initialize the process prior to first command
    -------------------------------------------------------------------------
    work.td_vvc_entity_support_pkg.initialize_executor(terminate_current_cmd);

    -- Set initial value of v_msg_id_panel to msg_id_panel in config
    v_msg_id_panel := vvc_config.msg_id_panel;

    loop

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, vvc_status, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_cmd_idx_executed, command_queue.is_empty(VOID), C_SCOPE);

      -- 1. Set defaults, fetch command and log
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_queue, vvc_config, vvc_status, queue_is_increasing, executor_is_busy, C_VVC_LABELS);

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, vvc_status, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_cmd_idx_executed, command_queue.is_empty(VOID), C_SCOPE);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, vvc_config);

      -- Check if command is a BFM access
      v_prev_command_was_bfm_access := v_command_is_bfm_access; -- save for inter_bfm_delay
      -- UPDATE, STOP and ABORT act on a running generation and are not delayed
      if v_cmd.operation = GENERATE_PERIODS or v_cmd.operation = START or v_cmd.operation = MEASURE or
         v_cmd.operation = CHECK or v_cmd.operation = CHECK_DUTY then
        v_command_is_bfm_access := true;
      else
        v_command_is_bfm_access := false;
      end if;

      -- Insert delay if needed
      work.td_vvc_entity_support_pkg.insert_inter_bfm_delay_if_requested(vvc_config                         => vvc_config,
                                                                         command_is_bfm_access              => v_prev_command_was_bfm_access,
                                                                         timestamp_start_of_last_bfm_access => v_timestamp_start_of_last_bfm_access,
                                                                         timestamp_end_of_last_bfm_access   => v_timestamp_end_of_last_bfm_access,
                                                                         scope                              => C_SCOPE,
                                                                         msg_id_panel                       => v_msg_id_panel);

      if v_command_is_bfm_access then
        v_timestamp_start_of_current_bfm_access := now;
      end if;

      -- 2. Execute the fetched command
      -------------------------------------------------------------------------
      case v_cmd.operation is  -- Only operations in the dedicated record are relevant

        -- VVC dedicated operations
        --===================================

        -- Generator role. The waveform is driven by p_waveform; the executor only requests and awaits.
        when GENERATE_PERIODS =>
          if role_is(GENERATOR) and run_mode_is(IDLE, "Not allowed while a continuous generation is active.") and
             parameters_are_valid(true, true) then
            set_transaction_info(IN_PROGRESS);
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " started (" & config_to_string & ")." & format_msg(v_cmd),
                C_SCOPE, v_msg_id_panel);
            start_run(v_cmd.num_periods);
            wait until run_mode = IDLE or terminate_current_cmd.is_active = '1';
            if run_mode /= IDLE then
              abort_run;                -- terminate_current_command
            end if;
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " completed." & format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
            set_transaction_info(COMPLETED);
          end if;

        when START =>
          if role_is(GENERATOR) and run_mode_is(IDLE, "A continuous generation is already active.") and
             parameters_are_valid(false, true) then
            set_transaction_info(IN_PROGRESS);
            start_run(0);
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " started (" & config_to_string & ")." & format_msg(v_cmd),
                C_SCOPE, v_msg_id_panel);
            set_transaction_info(COMPLETED);
          end if;

        when UPDATE =>
          if role_is(GENERATOR) and run_mode_is(CONTINUOUS, "No continuous generation is active.") and
             parameters_are_valid(false, false) then
            set_transaction_info(IN_PROGRESS);
            v_request_idx := update_req.idx + 1;
            update_req    <= (v_request_idx, v_cmd.period, v_cmd.active_time, 0);
            wait until update_ack = v_request_idx or run_mode = IDLE or terminate_current_cmd.is_active = '1';
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " took effect." & format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
            set_transaction_info(COMPLETED);
          end if;

        when STOP =>
          if role_is(GENERATOR) and run_mode_is(CONTINUOUS, "No continuous generation is active.") then
            set_transaction_info(IN_PROGRESS);
            stop_req <= stop_req + 1;
            wait until run_mode = IDLE or terminate_current_cmd.is_active = '1';
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " completed." & format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
            set_transaction_info(COMPLETED);
          end if;

        when ABORT =>
          if role_is(GENERATOR) and run_mode_is(CONTINUOUS, "No continuous generation is active.") then
            set_transaction_info(IN_PROGRESS);
            abort_run;
            log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & " completed." & format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
            set_transaction_info(COMPLETED);
          end if;

        -- Observer role: the BFM procedures observe the line directly
        when MEASURE =>
          if role_is(OBSERVER) then
            set_transaction_info(IN_PROGRESS);
            pwm_measure(result       => v_result,
                        msg          => format_msg(v_cmd),
                        pwm          => pwm_vvc_if,
                        terminate    => terminate_current_cmd.is_active,
                        timeout      => v_cmd.timeout,
                        scope        => C_SCOPE,
                        msg_id_panel => v_msg_id_panel,
                        config       => vvc_config.bfm_config);
            work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                        cmd_idx      => v_cmd.cmd_idx,
                                                        result       => v_result);
            set_global_vvc_transaction_info(vvc_transaction_info_trigger, vvc_transaction_info, v_cmd, v_result, COMPLETED, C_SCOPE);
          end if;

        when CHECK =>
          if role_is(OBSERVER) then
            set_transaction_info(IN_PROGRESS);
            pwm_check(period       => v_cmd.period,
                      active_time  => v_cmd.active_time,
                      num_periods  => v_cmd.num_periods,
                      msg          => format_msg(v_cmd),
                      pwm          => pwm_vvc_if,
                      terminate    => terminate_current_cmd.is_active,
                      alert_level  => v_cmd.alert_level,
                      timeout      => v_cmd.timeout,
                      scope        => C_SCOPE,
                      msg_id_panel => v_msg_id_panel,
                      config       => vvc_config.bfm_config);
            set_transaction_info(COMPLETED);
          end if;

        when CHECK_DUTY =>
          if role_is(OBSERVER) then
            set_transaction_info(IN_PROGRESS);
            pwm_check_duty(duty         => v_cmd.duty,
                           num_periods  => v_cmd.num_periods,
                           msg          => format_msg(v_cmd),
                           pwm          => pwm_vvc_if,
                           terminate    => terminate_current_cmd.is_active,
                           alert_level  => v_cmd.alert_level,
                           timeout      => v_cmd.timeout,
                           scope        => C_SCOPE,
                           msg_id_panel => v_msg_id_panel,
                           config       => vvc_config.bfm_config);
            set_transaction_info(COMPLETED);
          end if;

        -- UVVM common operations
        --===================================
        when INSERT_DELAY =>
          log(ID_INSERTED_DELAY, "Running: " & to_string(v_cmd.proc_call) & " " & format_command_idx(v_cmd), C_SCOPE, v_msg_id_panel);
          if v_cmd.gen_integer_array(0) = -1 then
            -- Delay specified using time
            wait until terminate_current_cmd.is_active = '1' for v_cmd.delay;
          else
            -- Delay specified using integer: there is no clock (A-03)
            alert(TB_ERROR, "insert_delay() with a number of clock cycles is not supported, the PWM VVC has no clock. Use a time." &
                  format_msg(v_cmd), C_SCOPE);
          end if;

        when others =>
          tb_error("Unsupported local command received for execution: '" & to_string(v_cmd.operation) & "'", C_SCOPE);
      end case;

      if v_command_is_bfm_access then
        v_timestamp_end_of_last_bfm_access   := now;
        v_timestamp_start_of_last_bfm_access := v_timestamp_start_of_current_bfm_access;
        if ((vvc_config.inter_bfm_delay.delay_type = TIME_START2START) and
           ((now - v_timestamp_start_of_current_bfm_access) > vvc_config.inter_bfm_delay.delay_in_time)) then
          alert(vvc_config.inter_bfm_delay.inter_bfm_delay_violation_severity, "BFM access exceeded specified start-to-start inter-bfm delay, " &
                to_string(vvc_config.inter_bfm_delay.delay_in_time) & ".", C_SCOPE);
        end if;
      end if;

      -- Reset terminate flag if any occurred
      if (terminate_current_cmd.is_active = '1') then
        log(ID_CMD_EXECUTOR, "Termination request received", C_SCOPE, v_msg_id_panel);
        uvvm_vvc_framework.ti_vvc_framework_support_pkg.reset_flag(terminate_current_cmd);
      end if;

      last_cmd_idx_executed <= v_cmd.cmd_idx;

      -- Set vvc_transaction_info back to default values
      reset_vvc_transaction_info(vvc_transaction_info, v_cmd);

    end loop;
  end process p_cmd_executor;
  --==========================================================================================

  --==========================================================================================
  -- Waveform generator (GENERATOR role)
  -- - Drives the idle level from time 0 and runs the generation requested by the executor, period by period, so that
  --   the executor stays free for UPDATE, STOP and ABORT during a continuous generation.
  -- - Latches update_req and vvc_config.bfm_config at every period boundary.
  -- OBSERVER role: drives 'Z' permanently.
  --==========================================================================================
  p_waveform : process is
    variable v_config         : t_pwm_bfm_config;
    variable v_period         : time;
    variable v_active_time    : time;
    variable v_continuous     : boolean;
    variable v_remaining      : natural;
    variable v_update_idx     : natural := 0;
    variable v_stop_idx       : natural := 0;
    variable v_seed1          : positive;
    variable v_seed2          : positive;
    variable v_aborted        : boolean;
    variable v_jitter_alerted : boolean;
  begin
    if GC_ROLE = OBSERVER then
      pwm_vvc_if <= 'Z';
      wait;
    end if;

    -- From the generic: vvc_config may not be set up yet at time 0
    pwm_drive_idle(pwm_vvc_if, GC_PWM_BFM_CONFIG);

    loop
      wait on start_req;
      v_period         := start_req.period;
      v_active_time    := start_req.active_time;
      v_continuous     := start_req.num_periods = 0;
      v_remaining      := start_req.num_periods;
      v_update_idx     := update_req.idx;
      v_stop_idx       := stop_req;
      v_config         := vvc_config.bfm_config;
      -- Every run starts from the configured seeds, so it is reproducible
      v_seed1          := v_config.jitter_seed1;
      v_seed2          := v_config.jitter_seed2;
      v_jitter_alerted := false;
      if v_continuous then
        run_mode <= CONTINUOUS;
      else
        run_mode <= BOUNDED;
      end if;
      start_ack <= start_req.idx;

      loop
        pwm_drive_period(v_period, v_active_time, pwm_vvc_if, v_config, v_seed1, v_seed2, abort_req, v_aborted);
        exit when v_aborted;
        if not v_continuous then
          v_remaining := v_remaining - 1;
          exit when v_remaining = 0;
        end if;
        exit when stop_req /= v_stop_idx;

        -- Period boundary: latch a pending update and the config
        if update_req.idx /= v_update_idx then
          v_update_idx  := update_req.idx;
          v_period      := update_req.period;
          v_active_time := update_req.active_time;
          update_ack    <= v_update_idx;
        end if;
        if vvc_config.bfm_config.jitter >= 0 ns then
          v_config := vvc_config.bfm_config;
        elsif not v_jitter_alerted then
          alert(TB_ERROR, "config.jitter must be >= 0 ns, was " & to_string(vvc_config.bfm_config.jitter, ns) &
                ". The generation continues with the previous config.", C_SCOPE);
          v_jitter_alerted := true;
        end if;
      end loop;

      pwm_drive_idle(pwm_vvc_if, vvc_config.bfm_config);
      run_mode <= IDLE;
    end loop;
  end process p_waveform;
  --==========================================================================================

  --==========================================================================================
  -- Command termination handler
  -- - Handles the termination request record (sets and resets terminate flag on request)
  --==========================================================================================
  cmd_terminator : uvvm_vvc_framework.ti_vvc_framework_support_pkg.flag_handler(terminate_current_cmd);  -- flag: is_active, set, reset
--==========================================================================================

end architecture behave;
