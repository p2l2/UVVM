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
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--==========================================================================================
--==========================================================================================
package vvc_methods_pkg is

  --==========================================================================================
  -- Types and constants for the ROTARY_ENCODER VVC
  --==========================================================================================
  constant C_VVC_NAME     : string := "ROTARY_ENCODER_VVC";

  signal ROTARY_ENCODER_VVCT: t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias  THIS_VVCT         : t_vvc_target_record is ROTARY_ENCODER_VVCT;
  alias  t_bfm_config is t_rotary_encoder_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_ROTARY_ENCODER_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay                       : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    cmd_queue_count_max                   : natural;           -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    cmd_queue_count_threshold             : natural;           -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    cmd_queue_count_threshold_severity    : t_alert_level;     -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    result_queue_count_max                : natural;           -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    result_queue_count_threshold          : natural;           -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    result_queue_count_threshold_severity : t_alert_level;     -- DEPRECATED: will be removed in v3. Use entity generic constants instead.
    bfm_config                            : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    msg_id_panel                          : t_msg_id_panel;    -- VVC dedicated message ID panel.
    stop_when_idle_severity               : t_alert_level;     -- Alert of rotary_encoder_stop_rotation() while no rotation is active
  end record t_vvc_config;

  type t_vvc_config_array is array (natural range <>) of t_vvc_config;

  constant C_ROTARY_ENCODER_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_ROTARY_ENCODER_INTER_BFM_DELAY_DEFAULT,
    cmd_queue_count_max                   => C_CMD_QUEUE_COUNT_MAX, --  from adaptation package
    cmd_queue_count_threshold             => C_CMD_QUEUE_COUNT_THRESHOLD,
    cmd_queue_count_threshold_severity    => C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_max                => C_RESULT_QUEUE_COUNT_MAX,
    result_queue_count_threshold          => C_RESULT_QUEUE_COUNT_THRESHOLD,
    result_queue_count_threshold_severity => C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
    bfm_config                            => C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT,
    msg_id_panel                          => C_VVC_MSG_ID_PANEL_DEFAULT,
    stop_when_idle_severity               => TB_WARNING
  );

  type t_vvc_status is record
    current_cmd_idx  : natural;
    previous_cmd_idx : natural;
    pending_cmd_cnt  : natural;
  end record t_vvc_status;

  type t_vvc_status_array is array (natural range <>) of t_vvc_status;

  constant C_VVC_STATUS_DEFAULT : t_vvc_status := (
    current_cmd_idx  => 0,
    previous_cmd_idx => 0,
    pending_cmd_cnt  => 0
  );

  shared variable shared_rotary_encoder_vvc_config : t_vvc_config_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => C_ROTARY_ENCODER_VVC_CONFIG_DEFAULT);
  shared variable shared_rotary_encoder_vvc_status : t_vvc_status_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => C_VVC_STATUS_DEFAULT);

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --==========================================================================================

  -- Moves. The speed is given in rpm (> 0.0) or as time_per_edge (> 0 ns). A move completes when the shaft is at rest at
  -- its end.
  procedure rotary_encoder_move_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_move_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Turns the shaft by angle degrees (>= 0.0) and ends exactly there
  procedure rotary_encoder_move_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant angle               : in    real;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_move_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant angle               : in    real;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Turns the shaft to the centre of the occurrence-th following state (>= 1) equal to target_state (pin levels). The
  -- state the shaft is in when the command is executed is never counted.
  procedure rotary_encoder_move_to_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant target_state        : in    std_logic_vector(1 downto 0);
    constant occurrence          : in    natural;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_move_to_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant target_state        : in    std_logic_vector(1 downto 0);
    constant occurrence          : in    natural;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Places the shaft at the centre of the state it is in, in zero time, without an output event
  procedure rotary_encoder_center_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Continuous rotation. A start or speed change takes effect at once, at the current angle, and completes at the first
  -- edge at the new speed (at once for 0.0 rpm; for a profile at the end of its first pass if that pass has no edge). The
  -- rotation then runs on while the VVC executes later commands. rpm is signed (> 0.0 forward, 0.0 at rest); the time form
  -- takes time_per_edge (> 0 ns) and a direction; a profile is a list of signed rpm entries (1 to
  -- C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH), each valid for time_per_entry, with profile_end after the last entry.
  -- While a rotation is active, moves, centre state, fault events and a second start are rejected.
  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant profile             : in    real_vector;
    constant time_per_entry      : in    time;
    constant profile_end         : in    t_rotary_encoder_profile_end;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Changes the speed of the running rotation (replaces a running profile); rejected while no rotation is active
  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant profile             : in    real_vector;
    constant time_per_entry      : in    time;
    constant profile_end         : in    t_rotary_encoder_profile_end;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Stops the rotation at once; the shaft stays at the reached angle. While no rotation is active it raises an alert of
  -- severity stop_when_idle_severity (VVC configuration) and does nothing else.
  procedure rotary_encoder_stop_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Fault events. set_angle: to an absolute angle in degrees, in zero time. jump_edges: num_edges from the angle at
  -- execution time, in zero time.
  procedure rotary_encoder_set_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant angle               : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure rotary_encoder_jump_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );


  -- Stores the t_rotary_encoder_status at execution time in the result queue; read it with fetch_result()
  procedure rotary_encoder_get_status(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info (
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout t_transaction_group;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_global_vvc_transaction_info (
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout t_transaction_group;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant edges                        : in natural;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure reset_vvc_transaction_info (
    variable vvc_transaction_info_group : inout t_transaction_group;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==========================================================================================
  -- Methods dedicated to this VVC
  --==========================================================================================

  -- Decimals of reals in proc_call strings
  constant C_REAL_DIGITS   : natural := 4;
  -- Larger reals are printed with 'image (to_string(real, digits) fails for them on some simulators)
  constant C_MAX_PRINTABLE : real    := 1.0e15;

  function real_image(
    constant value : in real
  ) return string is
  begin
    if abs(value) < C_MAX_PRINTABLE then
      return to_string(value, C_REAL_DIGITS);
    else
      return real'image(value);
    end if;
  end function;

  -- Queues a command; the operation's parameters are in motion
  procedure send_command(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant proc_call           : in    string;
    constant operation           : in    t_operation;
    constant motion              : in    t_rotary_encoder_motion;
    constant msg                 : in    string;
    constant scope               : in    string;
    constant parent_msg_id_panel : in    t_msg_id_panel;
    constant has_profile         : in    boolean := false
  ) is
    variable v_msg_id_panel : t_msg_id_panel := shared_msg_id_panel;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, operation);
    shared_vvc_cmd.motion              := motion;
    shared_vvc_cmd.has_profile         := has_profile;
    shared_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- A move of kind in direction; the remaining motion fields are set by the caller
  function move_motion(
    constant kind      : in t_rotary_encoder_motion_kind;
    constant direction : in t_rotary_encoder_direction
  ) return t_rotary_encoder_motion is
    variable v_motion : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.kind      := kind;
    v_motion.direction := direction;
    return v_motion;
  end function;

  -- motion with the speed in rpm
  function with_rpm(
    constant motion : in t_rotary_encoder_motion;
    constant rpm    : in real
  ) return t_rotary_encoder_motion is
    variable v_motion : t_rotary_encoder_motion := motion;
  begin
    v_motion.speed_form := SPEED_RPM;
    v_motion.rpm        := rpm;
    return v_motion;
  end function;

  -- motion with the speed as time_per_edge
  function with_time_per_edge(
    constant motion        : in t_rotary_encoder_motion;
    constant time_per_edge : in time
  ) return t_rotary_encoder_motion is
    variable v_motion : t_rotary_encoder_motion := motion;
  begin
    v_motion.speed_form    := SPEED_TIME_PER_EDGE;
    v_motion.time_per_edge := time_per_edge;
    return v_motion;
  end function;

  procedure rotary_encoder_move_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_edges";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(num_edges) & ", " & real_image(rpm) & " rpm)";
    variable v_motion    : t_rotary_encoder_motion := with_rpm(move_motion(MOTION_EDGES, direction), rpm);
  begin
    v_motion.num := num_edges;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_EDGES, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_edges";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(num_edges) & ", " & to_string(time_per_edge, ns) & ")";
    variable v_motion    : t_rotary_encoder_motion := with_time_per_edge(move_motion(MOTION_EDGES, direction), time_per_edge);
  begin
    v_motion.num := num_edges;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_EDGES, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant angle               : in    real;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_angle";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & real_image(angle) & " deg, " & real_image(rpm) & " rpm)";
    variable v_motion    : t_rotary_encoder_motion := with_rpm(move_motion(MOTION_ANGLE, direction), rpm);
  begin
    v_motion.angle := angle;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_ANGLE, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant angle               : in    real;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_angle";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & real_image(angle) & " deg, " & to_string(time_per_edge, ns) & ")";
    variable v_motion    : t_rotary_encoder_motion := with_time_per_edge(move_motion(MOTION_ANGLE, direction), time_per_edge);
  begin
    v_motion.angle := angle;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_ANGLE, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_to_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant target_state        : in    std_logic_vector(1 downto 0);
    constant occurrence          : in    natural;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_to_state";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(target_state) & ", " & to_string(occurrence) & ", " & real_image(rpm) & " rpm)";
    variable v_motion    : t_rotary_encoder_motion := with_rpm(move_motion(MOTION_TO_STATE, direction), rpm);
  begin
    v_motion.target_state := target_state;
    v_motion.num          := occurrence;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_TO_STATE, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_move_to_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant target_state        : in    std_logic_vector(1 downto 0);
    constant occurrence          : in    natural;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_move_to_state";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(target_state) & ", " & to_string(occurrence) & ", " &
                                     to_string(time_per_edge, ns) & ")";
    variable v_motion    : t_rotary_encoder_motion := with_time_per_edge(move_motion(MOTION_TO_STATE, direction), time_per_edge);
  begin
    v_motion.target_state := target_state;
    v_motion.num          := occurrence;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, MOVE_TO_STATE, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_center_state(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_center_state";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, CENTER_STATE, C_ROTARY_ENCODER_MOTION_DEFAULT, msg, scope,
                 parent_msg_id_panel);
  end procedure;

  -- A rotation at a signed rpm
  function rotation_rpm(
    constant rpm : in real
  ) return t_rotary_encoder_motion is
    variable v_motion : t_rotary_encoder_motion := with_rpm(C_ROTARY_ENCODER_MOTION_DEFAULT, rpm);
  begin
    v_motion.kind := MOTION_ROTATION;
    return v_motion;
  end function;

  -- A rotation at time_per_edge in direction
  function rotation_time(
    constant direction     : in t_rotary_encoder_direction;
    constant time_per_edge : in time
  ) return t_rotary_encoder_motion is
  begin
    return with_time_per_edge(move_motion(MOTION_ROTATION, direction), time_per_edge);
  end function;

  -- A rotation along a profile. A profile longer than the motion record holds keeps its length, so that the VVC rejects it.
  function rotation_profile(
    constant profile        : in real_vector;
    constant time_per_entry : in time;
    constant profile_end    : in t_rotary_encoder_profile_end
  ) return t_rotary_encoder_motion is
    variable v_motion : t_rotary_encoder_motion := rotation_rpm(0.0);
  begin
    for i in 0 to minimum(profile'length, C_VVC_CMD_PROFILE_MAX_LENGTH) - 1 loop
      v_motion.profile(i) := profile(profile'low + i);
    end loop;
    v_motion.profile_length := profile'length;
    v_motion.time_per_entry := time_per_entry;
    v_motion.profile_end    := profile_end;
    return v_motion;
  end function;

  function profile_string(
    constant profile        : in real_vector;
    constant time_per_entry : in time;
    constant profile_end    : in t_rotary_encoder_profile_end
  ) return string is
  begin
    return "profile of " & to_string(profile'length) & " entries, " & to_string(time_per_entry, ns) & " per entry, " &
           to_upper(to_string(profile_end));
  end function;

  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_start_rotation";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & real_image(rpm) & " rpm)";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, START_ROTATION, rotation_rpm(rpm), msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_start_rotation";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(time_per_edge, ns) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, START_ROTATION, rotation_time(direction, time_per_edge), msg, scope,
                 parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_start_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant profile             : in    real_vector;
    constant time_per_entry      : in    time;
    constant profile_end         : in    t_rotary_encoder_profile_end;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_start_rotation";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " &
                                     profile_string(profile, time_per_entry, profile_end) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, START_ROTATION, rotation_profile(profile, time_per_entry, profile_end), msg,
                 scope, parent_msg_id_panel, has_profile => true);
  end procedure;

  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant rpm                 : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_set_speed";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & real_image(rpm) & " rpm)";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, SET_SPEED, rotation_rpm(rpm), msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant time_per_edge       : in    time;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_set_speed";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(time_per_edge, ns) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, SET_SPEED, rotation_time(direction, time_per_edge), msg, scope,
                 parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_set_speed(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant profile             : in    real_vector;
    constant time_per_entry      : in    time;
    constant profile_end         : in    t_rotary_encoder_profile_end;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_set_speed";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " &
                                     profile_string(profile, time_per_entry, profile_end) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, SET_SPEED, rotation_profile(profile, time_per_entry, profile_end), msg,
                 scope, parent_msg_id_panel, has_profile => true);
  end procedure;

  procedure rotary_encoder_stop_rotation(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_stop_rotation";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, STOP_ROTATION, C_ROTARY_ENCODER_MOTION_DEFAULT, msg, scope,
                 parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_set_angle(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant angle               : in    real;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_set_angle";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & real_image(angle) & " deg)";
    variable v_motion    : t_rotary_encoder_motion := C_ROTARY_ENCODER_MOTION_DEFAULT;
  begin
    v_motion.angle := angle;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, SET_ANGLE, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_jump_edges(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant direction           : in    t_rotary_encoder_direction;
    constant num_edges           : in    natural;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_jump_edges";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ", " & to_upper(to_string(direction)) &
                                     ", " & to_string(num_edges) & ")";
    variable v_motion    : t_rotary_encoder_motion := move_motion(MOTION_EDGES, direction);
  begin
    v_motion.num := num_edges;
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, JUMP_EDGES, v_motion, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure rotary_encoder_get_status(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in    integer;
    constant msg                 : in    string;
    constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "rotary_encoder_get_status";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) & ")";
  begin
    send_command(VVCT, vvc_instance_idx, C_PROC_CALL, GET_STATUS, C_ROTARY_ENCODER_MOTION_DEFAULT, msg, scope,
                 parent_msg_id_panel);
  end procedure;

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info (
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout t_transaction_group;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
  begin
    case vvc_cmd.operation is
      when MOVE_EDGES | MOVE_ANGLE | MOVE_TO_STATE | CENTER_STATE | SET_ANGLE | JUMP_EDGES | GET_STATUS |
           START_ROTATION | SET_SPEED | STOP_ROTATION =>
        vvc_transaction_info_group.bt.operation          := vvc_cmd.operation;
        vvc_transaction_info_group.bt.direction          := vvc_cmd.motion.direction;
        vvc_transaction_info_group.bt.num_edges          := 0;
        vvc_transaction_info_group.bt.occurrence         := 0;
        if vvc_cmd.operation = MOVE_EDGES or vvc_cmd.operation = JUMP_EDGES then
          vvc_transaction_info_group.bt.num_edges        := vvc_cmd.motion.num;
        elsif vvc_cmd.operation = MOVE_TO_STATE then
          vvc_transaction_info_group.bt.occurrence       := vvc_cmd.motion.num;
        end if;
        vvc_transaction_info_group.bt.target_state       := vvc_cmd.motion.target_state;
        vvc_transaction_info_group.bt.angle              := vvc_cmd.motion.angle;
        vvc_transaction_info_group.bt.rpm                := 0.0;
        vvc_transaction_info_group.bt.time_per_edge      := 0 ns;
        -- The speed as given: moves and rotations at a constant speed (a profile has its entries in rpm)
        if (vvc_cmd.operation = MOVE_EDGES or vvc_cmd.operation = MOVE_ANGLE or vvc_cmd.operation = MOVE_TO_STATE or
            vvc_cmd.operation = START_ROTATION or vvc_cmd.operation = SET_SPEED) and not vvc_cmd.has_profile then
          if vvc_cmd.motion.speed_form = SPEED_RPM then
            vvc_transaction_info_group.bt.rpm            := vvc_cmd.motion.rpm;
          else
            vvc_transaction_info_group.bt.time_per_edge  := vvc_cmd.motion.time_per_edge;
          end if;
        end if;
        vvc_transaction_info_group.bt.profile_length     := vvc_cmd.motion.profile_length;
        vvc_transaction_info_group.bt.time_per_entry     := vvc_cmd.motion.time_per_entry;
        vvc_transaction_info_group.bt.profile_end        := vvc_cmd.motion.profile_end;
        vvc_transaction_info_group.bt.edges              := C_BASE_TRANSACTION_SET_DEFAULT.edges;
        vvc_transaction_info_group.bt.status             := C_BASE_TRANSACTION_SET_DEFAULT.status;
        vvc_transaction_info_group.bt.vvc_meta.msg       := vvc_cmd.msg;
        vvc_transaction_info_group.bt.vvc_meta.cmd_idx   := vvc_cmd.cmd_idx;
        vvc_transaction_info_group.bt.transaction_status := transaction_status;
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation not recognized", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_global_vvc_transaction_info (
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout t_transaction_group;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant edges                        : in natural;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
  begin
    -- The effect of the command: the encoder state at its end and, for a move, the edges emitted
    case vvc_cmd.operation is
      when MOVE_EDGES | MOVE_ANGLE | MOVE_TO_STATE | CENTER_STATE | SET_ANGLE | JUMP_EDGES | GET_STATUS |
           START_ROTATION | SET_SPEED | STOP_ROTATION =>
        vvc_transaction_info_group.bt.edges              := edges;
        vvc_transaction_info_group.bt.status             := vvc_result;
        vvc_transaction_info_group.bt.transaction_status := transaction_status;
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation does not update vvc_result ", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info (
    variable vvc_transaction_info_group : inout t_transaction_group;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
  begin
    case vvc_cmd.operation is
      when MOVE_EDGES | MOVE_ANGLE | MOVE_TO_STATE | CENTER_STATE | SET_ANGLE | JUMP_EDGES | GET_STATUS |
           START_ROTATION | SET_SPEED | STOP_ROTATION =>
        vvc_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;

      when others =>
        null;
    end case;

    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

end package body vvc_methods_pkg;
