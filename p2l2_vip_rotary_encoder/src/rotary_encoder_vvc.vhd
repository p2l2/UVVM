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

use work.rotary_encoder_bfm_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;
use work.transaction_pkg.all;

--==========================================================================================
--==========================================================================================
entity rotary_encoder_vvc is
  generic (
    GC_INSTANCE_IDX                          : natural                     := 1;
    GC_ROTARY_ENCODER_BFM_CONFIG             : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    GC_CMD_QUEUE_COUNT_MAX                   : natural                     := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural                     := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level               := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural                     := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural                     := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level               := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port (
    rotary_encoder_vvc_if : inout t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID)
  );
end entity rotary_encoder_vvc;

--==========================================================================================
--==========================================================================================
architecture behave of rotary_encoder_vvc is

  constant C_SCOPE      : string       := get_scope_for_log(C_VVC_NAME, GC_INSTANCE_IDX);
  constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_SCOPE, C_VVC_NAME, GC_INSTANCE_IDX, NA);

  signal executor_is_busy                   : boolean := false;
  signal queue_is_increasing                : boolean := false;
  signal last_cmd_idx_executed              : natural := 0;
  signal terminate_current_cmd              : t_flag_record;
  signal entry_num_in_vvc_activity_register : integer;

  -- Executor -> p_motion. p_motion is the only driver of the port and owns the encoder state; the executor sends one
  -- request at a time (a REQ_HALT may follow a REQ_MOTION that is still running) and waits for its response.
  type t_motion_req_kind is (REQ_MOTION, REQ_HALT, REQ_STATUS, REQ_CENTER_STATE, REQ_SET_ANGLE, REQ_JUMP_EDGES);
  type t_motion_req is record
    idx          : natural;          -- Incremented with every request
    kind         : t_motion_req_kind;
    cmd          : t_vvc_cmd_record; -- The command with its parameters, proc_call and msg
    msg_id_panel : t_msg_id_panel;
  end record t_motion_req;
  constant C_MOTION_REQ_DEFAULT : t_motion_req := (0, REQ_STATUS, C_VVC_CMD_DEFAULT, C_VVC_MSG_ID_PANEL_DEFAULT);

  -- p_motion -> executor: request idx is complete, i.e. a move is at rest, a zero-time operation is done, or a
  -- request was rejected
  type t_motion_rsp is record
    idx      : natural;
    accepted : boolean;                 -- REQ_MOTION: false after a TB_ERROR, nothing moved
    edges    : natural;                 -- Edges of the current or last move
    status   : t_rotary_encoder_status; -- At the response time
  end record t_motion_rsp;
  constant C_MOTION_RSP_DEFAULT : t_motion_rsp := (0, false, 0, (0, 0.0, "00", false, false, 0.0));

  signal motion_req       : t_motion_req := C_MOTION_REQ_DEFAULT;
  signal motion_rsp       : t_motion_rsp := C_MOTION_RSP_DEFAULT;
  signal motion_interrupt : natural      := 0; -- Interrupts a running motion in p_motion: an event for every request

  -- Instantiation of the element dedicated executor
  shared variable command_queue : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable result_queue  : work.td_result_queue_pkg.t_generic_queue;

  alias vvc_config : t_vvc_config is shared_rotary_encoder_vvc_config(GC_INSTANCE_IDX);
  alias vvc_status : t_vvc_status is shared_rotary_encoder_vvc_status(GC_INSTANCE_IDX);
  -- Transaction info
  alias vvc_transaction_info_trigger        : std_logic           is global_rotary_encoder_vvc_transaction_trigger(GC_INSTANCE_IDX);
  alias vvc_transaction_info                : t_transaction_group is shared_rotary_encoder_vvc_transaction_info(GC_INSTANCE_IDX);

begin

  --==========================================================================================
  -- Constructor
  -- - Set up the defaults and show constructor if enabled
  --==========================================================================================
  work.td_vvc_entity_support_pkg.vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, vvc_config, command_queue, result_queue, GC_ROTARY_ENCODER_BFM_CONFIG,
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
    variable v_timestamp_start_of_current_bfm_access  : time    := 0 ns;
    variable v_timestamp_start_of_last_bfm_access     : time    := 0 ns;
    variable v_timestamp_end_of_last_bfm_access       : time    := 0 ns;
    variable v_command_is_bfm_access                  : boolean := false;
    variable v_prev_command_was_bfm_access            : boolean := false;
    variable v_msg_id_panel                           : t_msg_id_panel;
    variable v_rsp                                    : t_motion_rsp;
    variable v_terminated                             : boolean;

    -- Decimals of the angle in the log
    constant C_ANGLE_DIGITS : natural := 4;

    -- Sends a request for the current command to p_motion and waits for its response in v_rsp. A
    -- terminate_current_command halts a running move at once, at the current angle (v_terminated).
    procedure request(
      constant kind : in t_motion_req_kind
    ) is
      variable v_idx : natural := motion_req.idx + 1;
    begin
      v_terminated := false;
      motion_req   <= (v_idx, kind, v_cmd, v_msg_id_panel);
      wait until motion_rsp.idx = v_idx or terminate_current_cmd.is_active = '1';
      if motion_rsp.idx /= v_idx then
        v_terminated := true;
        v_idx        := v_idx + 1;
        motion_req   <= (v_idx, REQ_HALT, v_cmd, v_msg_id_panel);
        wait until motion_rsp.idx = v_idx;
      end if;
      v_rsp := motion_rsp;
    end procedure;

    -- Transaction info of the current command: IN_PROGRESS with its parameters
    procedure set_transaction_info(
      constant status : t_transaction_status
    ) is
    begin
      set_global_vvc_transaction_info(vvc_transaction_info_trigger, vvc_transaction_info, v_cmd, vvc_config, status, C_SCOPE);
    end procedure;

    -- Transaction info at the end of the current command: its effect from v_rsp (edges only for a move)
    procedure complete_transaction_info(
      constant edges  : natural;
      constant status : t_transaction_status
    ) is
    begin
      set_global_vvc_transaction_info(vvc_transaction_info_trigger, vvc_transaction_info, v_cmd, v_rsp.status, edges, status, C_SCOPE);
    end procedure;

    -- Runs a move in p_motion and logs its end
    procedure execute_move is
    begin
      set_transaction_info(IN_PROGRESS);
      request(REQ_MOTION);
      if v_rsp.accepted then
        if v_terminated then
          log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & "=> Terminated after " & to_string(v_rsp.edges) &
              " edges, position " & to_string(v_rsp.status.position) & ", angle " &
              to_string(v_rsp.status.angle, C_ANGLE_DIGITS) & " deg." & format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
        else
          log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & "=> " & to_string(v_rsp.edges) & " edges, position " &
              to_string(v_rsp.status.position) & ", angle " & to_string(v_rsp.status.angle, C_ANGLE_DIGITS) & " deg." &
              format_msg(v_cmd), C_SCOPE, v_msg_id_panel);
        end if;
        complete_transaction_info(v_rsp.edges, COMPLETED);
      else
        complete_transaction_info(0, FAILED); -- Rejected with a TB_ERROR: nothing moved
      end if;
    end procedure;

    -- Runs a zero-time operation in p_motion; the BFM procedure called there logs it
    procedure execute_operation(
      constant kind : in t_motion_req_kind
    ) is
    begin
      set_transaction_info(IN_PROGRESS);
      request(kind);
      complete_transaction_info(0, COMPLETED);
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
      -- Moves and fault events act on the interface; centre state and the status read do not
      if v_cmd.operation = MOVE_EDGES or v_cmd.operation = MOVE_ANGLE or v_cmd.operation = MOVE_TO_STATE or
         v_cmd.operation = SET_ANGLE or v_cmd.operation = JUMP_EDGES then
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

        -- The interface is driven by p_motion; the executor only requests and awaits
        when MOVE_EDGES | MOVE_ANGLE | MOVE_TO_STATE =>
          execute_move;

        when CENTER_STATE =>
          execute_operation(REQ_CENTER_STATE);

        when SET_ANGLE =>
          execute_operation(REQ_SET_ANGLE);

        when JUMP_EDGES =>
          execute_operation(REQ_JUMP_EDGES);

        when GET_STATUS =>
          set_transaction_info(IN_PROGRESS);
          request(REQ_STATUS);
          log(vvc_config.bfm_config.id_for_bfm, to_string(v_cmd.proc_call) & "=> " & to_string(v_rsp.status) & "." & format_msg(v_cmd),
              C_SCOPE, v_msg_id_panel);
          work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                      cmd_idx      => v_cmd.cmd_idx,
                                                      result       => v_rsp.status);
          complete_transaction_info(0, COMPLETED);

        -- UVVM common operations
        --===================================
        when INSERT_DELAY =>
          log(ID_INSERTED_DELAY, "Running: " & to_string(v_cmd.proc_call) & " " & format_command_idx(v_cmd), C_SCOPE, v_msg_id_panel);
          if v_cmd.gen_integer_array(0) = -1 then
            -- Delay specified using time
            wait until terminate_current_cmd.is_active = '1' for v_cmd.delay;
          else
            -- Delay specified using integer: there is no clock
            alert(TB_ERROR, "insert_delay() with a number of clock cycles is not supported, the rotary encoder VVC has no clock. " &
                  "Use a time." & format_msg(v_cmd), C_SCOPE);
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
  -- Motion process
  -- - The only driver of rotary_encoder_vvc_if and the owner of the encoder state. Initializes the encoder from the
  --   generic at time 0 (vvc_config may not be set up yet then) and executes the requests of the executor.
  -- - A move runs edge by edge with rotary_encoder_run_motion(), which returns at every edge and at every new
  --   request, so a halt takes effect at once. A move keeps the configuration of its start; a configuration change
  --   takes effect at the next command.
  -- - Pending requests are detected by their index: a delta wait inside rotary_encoder_run_motion() can absorb the event
  --   of motion_interrupt.
  --==========================================================================================
  motion_interrupt <= motion_req.idx;

  p_motion : process is
    variable v_state          : t_rotary_encoder_state;
    variable v_req            : t_motion_req;
    variable v_motion_req     : t_motion_req;           -- The request of the active motion
    variable v_handled_idx    : natural := 0;
    variable v_motion_active  : boolean := false;
    variable v_accepted       : boolean;
    variable v_start_position : integer := 0;           -- Position at the start of the last move
    variable v_motion_config  : t_rotary_encoder_bfm_config; -- Configuration of the active motion, taken at its start
    variable v_event          : t_rotary_encoder_motion_event;

    -- Completes request idx
    procedure respond(
      constant idx      : in natural;
      constant accepted : in boolean
    ) is
      constant C_STATUS : t_rotary_encoder_status := rotary_encoder_get_status(v_state);
    begin
      motion_rsp <= (idx, accepted, abs(C_STATUS.position - v_start_position), C_STATUS);
    end procedure;

  begin
    rotary_encoder_init(v_state, "", rotary_encoder_vvc_if, C_SCOPE, vvc_config.msg_id_panel, GC_ROTARY_ENCODER_BFM_CONFIG);

    loop
      if motion_req.idx = v_handled_idx and not v_motion_active then
        wait on motion_interrupt;       -- Idle: wait for the next request
      end if;

      if motion_req.idx /= v_handled_idx then
        v_req         := motion_req;
        v_handled_idx := v_req.idx;
        case v_req.kind is
          when REQ_MOTION =>
            v_start_position := rotary_encoder_get_status(v_state).position;
            v_motion_config  := vvc_config.bfm_config;
            rotary_encoder_set_motion(v_req.cmd.motion, v_state, v_accepted, format_msg(v_req.cmd), C_SCOPE, v_req.msg_id_panel,
                                      v_motion_config);
            if v_accepted then
              v_motion_req    := v_req;
              v_motion_active := true;
            else
              respond(v_req.idx, false);
            end if;

          when REQ_HALT =>
            rotary_encoder_halt_motion(v_state);
            v_motion_active := false;
            respond(v_req.idx, true);

          when REQ_STATUS =>
            respond(v_req.idx, true);

          when REQ_CENTER_STATE =>
            rotary_encoder_center_state(v_state, format_msg(v_req.cmd), C_SCOPE, v_req.msg_id_panel, vvc_config.bfm_config);
            respond(v_req.idx, true);

          when REQ_SET_ANGLE =>
            rotary_encoder_set_angle(v_req.cmd.motion.angle, v_state, format_msg(v_req.cmd), rotary_encoder_vvc_if, C_SCOPE,
                                     v_req.msg_id_panel, vvc_config.bfm_config);
            respond(v_req.idx, true);

          when REQ_JUMP_EDGES =>
            rotary_encoder_jump_edges(v_req.cmd.motion.direction, v_req.cmd.motion.num, v_state, format_msg(v_req.cmd),
                                      rotary_encoder_vvc_if, C_SCOPE, v_req.msg_id_panel, vvc_config.bfm_config);
            respond(v_req.idx, true);

        end case;
      end if;

      if v_motion_active then
        -- Until the next edge, the end of the move or a new request
        rotary_encoder_run_motion(v_state, v_event, format_msg(v_motion_req.cmd), rotary_encoder_vvc_if, motion_interrupt, C_SCOPE,
                                  v_motion_req.msg_id_panel, v_motion_config);
        if v_event = MOTION_DONE then
          v_motion_active := false;
          respond(v_motion_req.idx, true);
        end if;
      end if;
    end loop;
  end process p_motion;
  --==========================================================================================

  --==========================================================================================
  -- Command termination handler
  -- - Handles the termination request record (sets and resets terminate flag on request)
  --==========================================================================================
  cmd_terminator : uvvm_vvc_framework.ti_vvc_framework_support_pkg.flag_handler(terminate_current_cmd);  -- flag: is_active, set, reset
  --==========================================================================================

end architecture behave;
