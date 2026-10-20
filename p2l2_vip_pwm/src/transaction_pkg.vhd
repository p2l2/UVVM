--==========================================================================================
-- This VVC was generated with UVVM VVC Generator
--==========================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

--==========================================================================================
--==========================================================================================
package transaction_pkg is

  --==========================================================================================
  -- t_operation
  -- - VVC and BFM operations
  --==========================================================================================
  type t_operation is (
    -- UVVM common
    NO_OPERATION,
    AWAIT_COMPLETION,
    AWAIT_ANY_COMPLETION,
    ENABLE_LOG_MSG,
    DISABLE_LOG_MSG,
    FLUSH_COMMAND_QUEUE,
    FETCH_RESULT,
    INSERT_DELAY,
    TERMINATE_CURRENT_COMMAND,
    -- VVC local
    -- Generator role ('generate' is a VHDL reserved word, hence GENERATE_PERIODS)
    GENERATE_PERIODS, START, UPDATE, STOP, ABORT,
    -- Observer role
    MEASURE, CHECK, CHECK_DUTY
  );

  constant C_VVC_CMD_STRING_MAX_LENGTH : natural := 300;
  constant C_VVC_MAX_INSTANCE_NUM      : natural := C_MAX_VVC_INSTANCE_NUM;

  --==========================================================================================
  -- Transaction info types, constants and global signal
  --==========================================================================================

  -- VVC Meta
  type t_vvc_meta is record
    msg     : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    cmd_idx : integer;
  end record t_vvc_meta;

  constant C_VVC_META_DEFAULT : t_vvc_meta := (
    msg     => (others => ' '),
    cmd_idx => -1
  );

  -- NOTE:
  --   If compound transaction is needed see example usage in Bitvis VIP SBI.
  --   If sub transaction is needed see example usage in Bitvis VIP Avalon-MM.
  -- Base transaction
  type t_base_transaction is record
    operation           : t_operation;
    period              : time;    -- Generator: generated period; observer: expected period
    active_time         : time;    -- Generator: generated active time; observer: expected active time
    duty                : real;    -- CHECK_DUTY: expected duty cycle
    num_periods         : integer; -- GENERATE_PERIODS, CHECK, CHECK_DUTY; 0 otherwise
    vvc_meta            : t_vvc_meta;
    transaction_status  : t_transaction_status;
  end record t_base_transaction;

  constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
    operation           => NO_OPERATION,
    period              => 0 ns,
    active_time         => 0 ns,
    duty                => 0.0,
    num_periods         => 0,
    vvc_meta            => C_VVC_META_DEFAULT,
    transaction_status  => INACTIVE
  );

  -- Transaction group
  type t_transaction_group is record
    bt : t_base_transaction;
  end record t_transaction_group;

  constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
    bt => C_BASE_TRANSACTION_SET_DEFAULT
  );

  -- Global vvc_transaction_info trigger signal
  type t_pwm_transaction_trigger_array is array (natural range <>) of std_logic;
  signal global_pwm_vvc_transaction_trigger : t_pwm_transaction_trigger_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => '0');

  -- Shared vvc_transaction_info info variable
  type t_pwm_transaction_group_array is array (natural range <>) of t_transaction_group;
  shared variable shared_pwm_vvc_transaction_info : t_pwm_transaction_group_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => C_TRANSACTION_GROUP_DEFAULT);

end package transaction_pkg;
