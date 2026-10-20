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
use ieee.math_real.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

--==========================================================================================
package pwm_bfm_pkg is

  --==========================================================================================
  -- Types and constants for PWM BFM
  --==========================================================================================
  constant C_BFM_SCOPE : string := "PWM BFM";

  type t_pwm_role       is (GENERATOR, OBSERVER);
  type t_pwm_polarity   is (ACTIVE_HIGH, ACTIVE_LOW);
  type t_pwm_alignment  is (LEFT_ALIGNED, RIGHT_ALIGNED, CENTER_ALIGNED);
  type t_pwm_idle_level is (IDLE_INACTIVE, IDLE_ACTIVE, IDLE_HIGH_Z);

  -- Configuration record to be assigned in the test harness.
  type t_pwm_bfm_config is record
    polarity              : t_pwm_polarity;   -- Active level of the line (both roles)
    alignment             : t_pwm_alignment;  -- Position of the pulse within the period (generator)
    idle_level            : t_pwm_idle_level; -- Line level when no waveform is generated (generator)
    jitter                : time;             -- Max. random offset of each generated edge, 0 ns = off (generator)
    jitter_seed1          : positive;         -- Seeds of the jitter randomization (generator)
    jitter_seed2          : positive;
    period_tolerance      : time;             -- Absolute tolerance on the checked period (observer)
    active_time_tolerance : time;             -- Absolute tolerance on the checked active time (observer)
    duty_tolerance        : real;             -- Absolute tolerance on the checked duty cycle (observer)
    duty_rounding_margin  : real;             -- Added to duty_tolerance against real rounding, e.g. 0.26 - 0.25 > 0.01 (observer)
    min_pulse_width       : time;             -- Shorter pulses/gaps are reported as glitches, 0 ns = off (observer)
    timeout               : time;             -- Max. wait for each required edge, C_UNDEFINED_TIME = derived, 0 ns = never (observer)
    timeout_severity      : t_alert_level;    -- Alert level of a timeout (observer)
    id_for_bfm            : t_msg_id;         -- The message ID used as a general message ID in the PWM BFM
    id_for_bfm_wait       : t_msg_id;         -- The message ID used for logging waits in the PWM BFM
  end record t_pwm_bfm_config;

  -- Define the default value for the BFM config
  constant C_PWM_BFM_CONFIG_DEFAULT : t_pwm_bfm_config := (
    polarity              => ACTIVE_HIGH,
    alignment             => LEFT_ALIGNED,
    idle_level            => IDLE_INACTIVE,
    jitter                => 0 ns,
    jitter_seed1          => C_RAND_INIT_SEED_1,
    jitter_seed2          => C_RAND_INIT_SEED_2,
    period_tolerance      => 0 ns,
    active_time_tolerance => 0 ns,
    duty_tolerance        => 0.0,
    duty_rounding_margin  => 1.0e-12,
    min_pulse_width       => 0 ns,
    timeout               => C_UNDEFINED_TIME,
    timeout_severity      => ERROR,
    id_for_bfm            => ID_BFM,
    id_for_bfm_wait       => ID_BFM_WAIT
  );

  -- Result of pwm_measure()
  type t_pwm_measurement is record
    period         : time;      -- Active-going edge to active-going edge, 0 ns when is_constant
    active_time    : time;      -- Active-going edge to inactive-going edge, 0 ns when is_constant
    duty_cycle     : real;      -- active_time / period; 0.0 or 1.0 when is_constant
    is_constant    : boolean;   -- No edge within the timeout: the line held constant_level
    constant_level : std_logic; -- Line level when is_constant, else 'U'
  end record t_pwm_measurement;

  -- Also the result after a missing-activity alert
  constant C_PWM_MEASUREMENT_DEFAULT : t_pwm_measurement := (
    period         => 0 ns,
    active_time    => 0 ns,
    duty_cycle     => 0.0,
    is_constant    => false,
    constant_level => 'U'
  );

  --==========================================================================================
  -- Level and duty conversion functions
  --==========================================================================================
  function pwm_active_level(
    constant config : in t_pwm_bfm_config
  ) return std_logic;

  function pwm_inactive_level(
    constant config : in t_pwm_bfm_config
  ) return std_logic;

  -- The value driven on the line when idle
  function pwm_idle_value(
    constant config : in t_pwm_bfm_config
  ) return std_logic;

  -- Returns duty * period, rounded to the nearest simulator resolution unit (half a unit is rounded up).
  -- Requires 0.0 <= duty <= 1.0 and period > 0 ns.
  function pwm_duty_to_active_time(
    constant duty   : in real;
    constant period : in time
  ) return time;

  -- Returns (count / resolution) * period, rounded as pwm_duty_to_active_time().
  -- Requires 0 <= count <= resolution and period > 0 ns.
  function pwm_count_to_active_time(
    constant count      : in natural;
    constant resolution : in positive;
    constant period     : in time
  ) return time;

  --==========================================================================================
  -- BFM procedures
  --==========================================================================================

  ---------------------------------------------------------------------------------
  -- drive idle
  ---------------------------------------------------------------------------------
  -- Drives the idle level given by config.idle_level and config.polarity.
  procedure pwm_drive_idle(
    signal   pwm    : inout std_logic;
    constant config : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- drive period
  ---------------------------------------------------------------------------------
  -- Drives one complete period according to config.polarity and config.alignment and returns at the end of the period.
  -- 0 ns and period as active_time give a constant level without edges. Parameters are not checked, they must be valid
  -- (period > 0 ns, 0 ns <= active_time <= period, config.jitter >= 0 ns). This is the timing core used by
  -- pwm_generate() and the VVC.
  -- With config.jitter > 0 ns, every edge is moved by a random offset in [-jitter, +jitter] from its ideal time, drawn
  -- with seed1/seed2. An edge at the period start is not moved before the period start, and every pulse and gap stays
  -- at least one resolution unit long.
  procedure pwm_drive_period(
    constant period      : in time;
    constant active_time : in time;
    signal   pwm         : inout std_logic;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive
  );

  -- As above, but returns at once with aborted = true when 'abort' has an event during the period. The line keeps its
  -- level; the caller drives the idle level. Used by the VVC for pwm_abort() and terminate_current_command.
  procedure pwm_drive_period(
    constant period      : in time;
    constant active_time : in time;
    signal   pwm         : inout std_logic;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive;
    signal   abort       : in boolean;
    variable aborted     : out boolean
  );

  ---------------------------------------------------------------------------------
  -- generate
  ---------------------------------------------------------------------------------
  -- Generates num_periods complete periods, then drives the idle level. Returns at the end of the last period.
  -- The jitter randomization starts from config.jitter_seed1/2 in every call, so a call is reproducible.
  procedure pwm_generate(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  -- Duty cycle given as ratio 0.0 to 1.0
  procedure pwm_generate(
    constant period       : in time;
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  -- Duty cycle given as counter value 'count' out of 'resolution' steps
  procedure pwm_generate(
    constant period       : in time;
    constant count        : in integer;
    constant resolution   : in integer;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Observation: common rules
  ---------------------------------------------------------------------------------
  -- * A period is measured from the first active-going edge after the call; a period in progress is ignored.
  -- * The timeout applies to each required edge: counted from the call for the first edge, from the previous edge after
  --   that. The per-call timeout overrides config.timeout; C_UNDEFINED_TIME means "not set" and 0 ns means "never".
  --   If neither is set, pwm_check() uses 2 * period; pwm_measure() and pwm_check_duty() need one.
  -- * While waiting for the first active-going edge, the line may be 'Z' if config.idle_level = IDLE_HIGH_Z. Any other
  --   value than '0'/'1' raises an alert each time the line changes to it; edges are changes between '0' and '1'.
  -- * With config.min_pulse_width > 0 ns, every measured pulse or gap shorter than it raises an alert.

  ---------------------------------------------------------------------------------
  -- measure
  ---------------------------------------------------------------------------------
  -- Measures one complete period. If the line does not change before the first active-going edge for the timeout,
  -- the result is the constant level (0 % or 100 %), without an alert. A timeout after the first active-going edge
  -- raises a missing-activity alert at config.timeout_severity and returns C_PWM_MEASUREMENT_DEFAULT. Invalid levels
  -- and pulses shorter than config.min_pulse_width raise an ERROR.
  procedure pwm_measure(
    variable result       : out t_pwm_measurement;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- check
  ---------------------------------------------------------------------------------
  -- Checks num_periods consecutive periods against period and active_time, within config.period_tolerance and
  -- config.active_time_tolerance (inclusive). Each failing period raises one alert at alert_level, naming its index.
  -- active_time = 0 ns or = period checks that the line holds the inactive or active level for the timeout, which
  -- must then be > 0 ns. A missing edge raises a missing-activity alert at config.timeout_severity and ends the check.
  procedure pwm_check(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  -- Checks the duty cycle of num_periods consecutive periods within config.duty_tolerance (inclusive), independent
  -- of the period. duty = 0.0 or 1.0 checks for a constant level as pwm_check().
  procedure pwm_check_duty(
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  -- Overloads with a terminate signal: terminate = '1' ends the observation at once, without an alert (logged with
  -- ID_TERMINATE_CMD). pwm_measure() then returns C_PWM_MEASUREMENT_DEFAULT. Used by the VVC for
  -- terminate_current_command, e.g. with timeout = 0 ns on a stuck line.
  procedure pwm_measure(
    variable result       : out t_pwm_measurement;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  procedure pwm_check(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

  procedure pwm_check_duty(
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  );

end package pwm_bfm_pkg;

--==========================================================================================
--==========================================================================================
package body pwm_bfm_pkg is

  ---------------------------------------------------------------------------------
  -- Internal: conversion between time and a number of resolution units.
  -- Time is split into two parts so that the time / time divisions stay within
  -- the 32-bit integer range for long times and fine resolutions.
  ---------------------------------------------------------------------------------
  constant C_UNITS_SPLIT : positive := 2**30;

  function time_to_units(
    constant value : in time
  ) return real is
    constant C_RESOLUTION : time := std.env.resolution_limit;
    constant C_HIGH_UNIT  : time := C_RESOLUTION * C_UNITS_SPLIT;
    variable v_high       : integer;
  begin
    v_high := value / C_HIGH_UNIT;
    return real(v_high) * real(C_UNITS_SPLIT) + real((value - v_high * C_HIGH_UNIT) / C_RESOLUTION);
  end function;

  -- Rounds to the nearest whole number of resolution units, half a unit up
  function units_to_time(
    constant num_units : in real
  ) return time is
    constant C_RESOLUTION : time := std.env.resolution_limit;
    constant C_HIGH_UNIT  : time := C_RESOLUTION * C_UNITS_SPLIT;
    variable v_units      : real;
    variable v_high       : integer;
  begin
    v_units := floor(num_units + 0.5);
    v_high  := integer(floor(v_units / real(C_UNITS_SPLIT)));
    return v_high * C_HIGH_UNIT + integer(v_units - real(v_high) * real(C_UNITS_SPLIT)) * C_RESOLUTION;
  end function;

  ---------------------------------------------------------------------------------
  -- Internal: parameter check of the generate procedures. Raises at most one alert.
  ---------------------------------------------------------------------------------
  procedure check_generate_parameters(
    constant proc_call   : in string;
    constant period      : in time;
    constant active_time : in time;
    constant num_periods : in integer;
    constant config      : in t_pwm_bfm_config;
    constant msg         : in string;
    constant scope       : in string;
    variable valid       : out boolean
  ) is
  begin
    valid := false;
    if period <= 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. period must be > 0 ns, was " & to_string(period, ns) & "." & add_msg_delimiter(msg), scope);
    elsif active_time < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. active_time must be >= 0 ns, was " & to_string(active_time, ns) & "." & add_msg_delimiter(msg), scope);
    elsif active_time > period then
      alert(TB_ERROR, proc_call & "=> Failed. active_time (" & to_string(active_time, ns) & ") must not exceed period (" &
            to_string(period, ns) & ")." & add_msg_delimiter(msg), scope);
    elsif num_periods < 1 then
      alert(TB_ERROR, proc_call & "=> Failed. num_periods must be >= 1, was " & to_string(num_periods) & "." & add_msg_delimiter(msg), scope);
    elsif config.jitter < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. config.jitter must be >= 0 ns, was " & to_string(config.jitter, ns) & "." & add_msg_delimiter(msg), scope);
    else
      valid := true;
    end if;
  end procedure;

  ---------------------------------------------------------------------------------
  -- Internal: common part of the pwm_generate() overloads
  ---------------------------------------------------------------------------------
  procedure generate_periods(
    constant proc_call    : in string;
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string;
    constant msg_id_panel : in t_msg_id_panel;
    constant config       : in t_pwm_bfm_config
  ) is
    variable v_valid : boolean;
    variable v_seed1 : positive := config.jitter_seed1;
    variable v_seed2 : positive := config.jitter_seed2;
  begin
    check_generate_parameters(proc_call, period, active_time, num_periods, config, msg, scope, v_valid);
    if not v_valid then
      return;
    end if;

    for i in 1 to num_periods loop
      pwm_drive_period(period, active_time, pwm, config, v_seed1, v_seed2);
    end loop;
    pwm_drive_idle(pwm, config);
    log(config.id_for_bfm, proc_call & " completed (active_time " & to_string(active_time, ns) & ")." & add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  ---------------------------------------------------------------------------------
  -- Internal: observation
  ---------------------------------------------------------------------------------
  -- The edge timeout (arch 6.4): the per-call value, else config.timeout, else 2 * period if a period is given
  -- (period > 0 ns), else C_UNDEFINED_TIME.
  function resolve_timeout(
    constant timeout : in time;
    constant period  : in time;
    constant config  : in t_pwm_bfm_config
  ) return time is
  begin
    if timeout /= C_UNDEFINED_TIME then
      return timeout;
    elsif config.timeout /= C_UNDEFINED_TIME then
      return config.timeout;
    elsif period > 0 ns then
      return 2 * period;
    else
      return C_UNDEFINED_TIME;
    end if;
  end function;

  function duty_of(
    constant active_time : in time;
    constant period      : in time
  ) return real is
  begin
    return time_to_units(active_time) / time_to_units(period);
  end function;

  function is_valid_level(
    constant value : in std_logic
  ) return boolean is
  begin
    return value = '0' or value = '1';
  end function;

  -- Parameter check of the observation procedures, after the procedure-specific checks. Raises at most one alert.
  procedure check_observe_parameters(
    constant proc_call      : in string;
    constant timeout        : in time;    -- resolved
    constant needs_window   : in boolean; -- constant-level check: timeout 0 ns (never) is not allowed
    constant time_tolerance : in boolean; -- the period/active time tolerances are used
    constant duty_tolerance : in boolean; -- the duty tolerance is used
    constant config         : in t_pwm_bfm_config;
    constant msg            : in string;
    constant scope          : in string;
    variable valid          : out boolean
  ) is
  begin
    valid := false;
    if timeout = C_UNDEFINED_TIME then
      alert(TB_ERROR, proc_call & "=> Failed. timeout must be set, per call or in config.timeout." & add_msg_delimiter(msg), scope);
    elsif timeout < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. timeout must be >= 0 ns, was " & to_string(timeout, ns) & "." & add_msg_delimiter(msg), scope);
    elsif needs_window and timeout = 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. A constant-level check needs a timeout > 0 ns as observation window." & add_msg_delimiter(msg), scope);
    elsif config.min_pulse_width < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. config.min_pulse_width must be >= 0 ns, was " & to_string(config.min_pulse_width, ns) & "." &
            add_msg_delimiter(msg), scope);
    elsif time_tolerance and config.period_tolerance < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. config.period_tolerance must be >= 0 ns, was " & to_string(config.period_tolerance, ns) & "." &
            add_msg_delimiter(msg), scope);
    elsif time_tolerance and config.active_time_tolerance < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. config.active_time_tolerance must be >= 0 ns, was " &
            to_string(config.active_time_tolerance, ns) & "." & add_msg_delimiter(msg), scope);
    elsif duty_tolerance and (config.duty_tolerance < 0.0 or config.duty_tolerance > 1.0) then
      alert(TB_ERROR, proc_call & "=> Failed. config.duty_tolerance must be within 0.0 to 1.0, was " & to_string(config.duty_tolerance, 6) &
            "." & add_msg_delimiter(msg), scope);
    elsif duty_tolerance and config.duty_rounding_margin < 0.0 then
      alert(TB_ERROR, proc_call & "=> Failed. config.duty_rounding_margin must be >= 0.0, was " &
            to_string(config.duty_rounding_margin, 15) & "." & add_msg_delimiter(msg), scope);
    else
      valid := true;
    end if;
  end procedure;

  -- Termination of the observation procedures: 'terminate' = '1' ends the wait at once (terminated = true, no alert).
  -- The overloads without a terminate signal pass 'pwm' as terminate with use_terminate = false: a signal parameter
  -- needs a signal as actual, and waiting on pwm twice changes nothing.

  -- Waits for the next edge: a change of the valid level ('0'/'1') of pwm, for at most 'timeout' (0 ns = no limit).
  -- 'level' is the last valid level ('U' = none yet) and is updated. A change to any other value raises an alert at
  -- alert_level, except 'Z' when allow_z is true. timed_out is true if no edge came within the timeout.
  procedure await_edge(
    signal   pwm           : in std_logic;
    constant timeout       : in time;
    constant allow_z       : in boolean;
    constant alert_level   : in t_alert_level;
    constant proc_call     : in string;
    constant msg           : in string;
    constant scope         : in string;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    variable level         : inout std_logic;
    variable timed_out     : out boolean;
    variable terminated    : out boolean
  ) is
    constant C_START : time := now;
  begin
    timed_out  := false;
    terminated := false;
    loop
      if use_terminate and terminate = '1' then
        terminated := true;
        return;
      elsif timeout /= 0 ns and now - C_START >= timeout then
        timed_out := true;
        return;
      end if;
      if timeout = 0 ns then
        wait on pwm, terminate;
      else
        wait on pwm, terminate for timeout - (now - C_START);
      end if;
      if pwm'event then
        if is_valid_level(pwm) then
          if pwm /= level then
            level := pwm;
            return;
          end if;
        elsif not (allow_z and pwm = 'Z') then
          alert(alert_level, proc_call & "=> Failed. Invalid level '" & to_string(pwm) & "' on the line." & add_msg_delimiter(msg), scope);
        end if;
      end if;
    end loop;
  end procedure;

  -- Waits for the next active-going edge (A-15). Each edge on the way restarts the timeout. timed_out is true if the
  -- line did not change for the timeout; it then holds a constant level.
  procedure await_period_start(
    signal   pwm           : in std_logic;
    constant timeout       : in time;
    constant alert_level   : in t_alert_level;
    constant proc_call     : in string;
    constant msg           : in string;
    constant scope         : in string;
    constant config        : in t_pwm_bfm_config;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    variable timed_out     : out boolean;
    variable terminated    : out boolean
  ) is
    variable v_level      : std_logic := 'U';
    variable v_timed_out  : boolean;
    variable v_terminated : boolean;
  begin
    if is_valid_level(pwm) then
      v_level := pwm;
    end if;
    loop
      await_edge(pwm, timeout, config.idle_level = IDLE_HIGH_Z, alert_level, proc_call, msg, scope, terminate, use_terminate, v_level,
                 v_timed_out, v_terminated);
      exit when v_timed_out or v_terminated or v_level = pwm_active_level(config);
    end loop;
    timed_out  := v_timed_out;
    terminated := v_terminated;
  end procedure;

  -- Raises an alert if a pulse or gap is shorter than config.min_pulse_width
  procedure check_min_pulse_width(
    constant duration    : in time;
    constant is_pulse    : in boolean;
    constant edge_time   : in time; -- end of the pulse or gap
    constant alert_level : in t_alert_level;
    constant proc_call   : in string;
    constant msg         : in string;
    constant scope       : in string;
    constant config      : in t_pwm_bfm_config
  ) is
  begin
    if config.min_pulse_width > 0 ns and duration < config.min_pulse_width then
      if is_pulse then
        alert(alert_level, proc_call & "=> Failed. Pulse of " & to_string(duration, ns) & " ending at " & to_string(edge_time, ns) &
              " is shorter than config.min_pulse_width (" & to_string(config.min_pulse_width, ns) & ")." & add_msg_delimiter(msg), scope);
      else
        alert(alert_level, proc_call & "=> Failed. Gap of " & to_string(duration, ns) & " ending at " & to_string(edge_time, ns) &
              " is shorter than config.min_pulse_width (" & to_string(config.min_pulse_width, ns) & ")." & add_msg_delimiter(msg), scope);
      end if;
    end if;
  end procedure;

  -- Measures the period that starts with the active-going edge just seen (now): waits for the inactive-going and the
  -- next active-going edge, each within the timeout. A timeout raises a missing-activity alert at
  -- config.timeout_severity and returns timed_out = true. 'period_info' is added to the alert messages.
  procedure measure_period(
    signal   pwm           : in std_logic;
    constant timeout       : in time;
    constant alert_level   : in t_alert_level;
    constant period_info   : in string;
    constant proc_call     : in string;
    constant msg           : in string;
    constant scope         : in string;
    constant config        : in t_pwm_bfm_config;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    variable period        : out time;
    variable active_time   : out time;
    variable timed_out     : out boolean;
    variable terminated    : out boolean
  ) is
    constant C_START      : time := now;
    variable v_level      : std_logic := pwm_active_level(config);
    variable v_inactive   : time;
    variable v_timed_out  : boolean;
    variable v_terminated : boolean;
  begin
    timed_out  := false;
    terminated := false;
    await_edge(pwm, timeout, false, alert_level, proc_call, msg, scope, terminate, use_terminate, v_level, v_timed_out, v_terminated);
    if v_terminated then
      terminated := true;
      return;
    elsif v_timed_out then
      alert(config.timeout_severity, proc_call & "=> Failed. Missing activity" & period_info & ": no inactive-going edge within " &
            to_string(timeout, ns) & " after the active-going edge at " & to_string(C_START, ns) & "." & add_msg_delimiter(msg), scope);
      timed_out := true;
      return;
    end if;
    v_inactive := now;
    check_min_pulse_width(v_inactive - C_START, true, now, alert_level, proc_call, msg, scope, config);

    await_edge(pwm, timeout, false, alert_level, proc_call, msg, scope, terminate, use_terminate, v_level, v_timed_out, v_terminated);
    if v_terminated then
      terminated := true;
      return;
    elsif v_timed_out then
      alert(config.timeout_severity, proc_call & "=> Failed. Missing activity" & period_info & ": no active-going edge within " &
            to_string(timeout, ns) & " after the inactive-going edge at " & to_string(v_inactive, ns) & "." & add_msg_delimiter(msg), scope);
      timed_out := true;
      return;
    end if;
    check_min_pulse_width(now - v_inactive, false, now, alert_level, proc_call, msg, scope, config);

    period      := now - C_START;
    active_time := v_inactive - C_START;
  end procedure;

  -- Checks that the line holds 'expected' (0 % or 100 %) without any change for 'window'. Raises at most one alert and
  -- returns at the first violation.
  procedure check_constant_level(
    constant expected      : in std_logic;
    constant window        : in time;
    constant alert_level   : in t_alert_level;
    constant proc_call     : in string;
    constant msg           : in string;
    signal   pwm           : in std_logic;
    constant scope         : in string;
    constant msg_id_panel  : in t_msg_id_panel;
    constant config        : in t_pwm_bfm_config;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    variable terminated    : out boolean
  ) is
    constant C_START : time := now;
  begin
    terminated := false;
    if pwm /= expected then
      alert(alert_level, proc_call & "=> Failed. Expected the constant level '" & to_string(expected) & "', the line was '" &
            to_string(pwm) & "'." & add_msg_delimiter(msg), scope);
      return;
    end if;
    while now - C_START < window loop
      if use_terminate and terminate = '1' then
        terminated := true;
        return;
      end if;
      wait on pwm, terminate for window - (now - C_START);
      if pwm'event then
        alert(alert_level, proc_call & "=> Failed. Expected the constant level '" & to_string(expected) & "' for " & to_string(window, ns) &
              ", the line changed to '" & to_string(pwm) & "' after " & to_string(now - C_START, ns) & "." & add_msg_delimiter(msg), scope);
        return;
      end if;
    end loop;
    log(config.id_for_bfm, proc_call & "=> OK, constant level '" & to_string(expected) & "' for " & to_string(window, ns) & "." &
        add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  function time_mismatch(
    constant name      : in string;
    constant measured  : in time;
    constant expected  : in time;
    constant tolerance : in time
  ) return string is
  begin
    return name & " was " & to_string(measured, ns) & ", expected " & to_string(expected, ns) & " +-" & to_string(tolerance, ns);
  end function;

  -- Checks num_periods consecutive periods: period and active_time, or the duty cycle if check_duty is true
  procedure check_periods(
    constant period        : in time;
    constant active_time   : in time;
    constant duty          : in real;
    constant check_duty    : in boolean;
    constant num_periods   : in positive;
    constant timeout       : in time;
    constant alert_level   : in t_alert_level;
    constant proc_call     : in string;
    constant msg           : in string;
    signal   pwm           : in std_logic;
    constant scope         : in string;
    constant msg_id_panel  : in t_msg_id_panel;
    constant config        : in t_pwm_bfm_config;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    variable terminated    : out boolean
  ) is
    variable v_timed_out   : boolean;
    variable v_terminated  : boolean;
    variable v_period      : time;
    variable v_active_time : time;
    variable v_duty        : real;
    variable v_period_ok   : boolean;
    variable v_active_ok   : boolean;
    variable v_num_failed  : natural := 0;
  begin
    terminated := false;
    await_period_start(pwm, timeout, alert_level, proc_call, msg, scope, config, terminate, use_terminate, v_timed_out, v_terminated);
    if v_terminated then
      terminated := true;
      return;
    elsif v_timed_out then
      alert(config.timeout_severity, proc_call & "=> Failed. Missing activity: no edge within " & to_string(timeout, ns) &
            " (line at '" & to_string(pwm) & "')." & add_msg_delimiter(msg), scope);
      return;
    end if;

    for i in 1 to num_periods loop
      measure_period(pwm, timeout, alert_level, " in period " & to_string(i) & "/" & to_string(num_periods), proc_call, msg, scope,
                     config, terminate, use_terminate, v_period, v_active_time, v_timed_out, v_terminated);
      if v_terminated then
        terminated := true;
        return;
      elsif v_timed_out then
        return;
      end if;
      if check_duty then
        v_duty := duty_of(v_active_time, v_period);
        if abs (v_duty - duty) > config.duty_tolerance + config.duty_rounding_margin then
          alert(alert_level, proc_call & "=> Failed in period " & to_string(i) & "/" & to_string(num_periods) & ". Duty cycle was " &
                to_string(v_duty, 6) & " (t_on " & to_string(v_active_time, ns) & ", T " & to_string(v_period, ns) & "), expected " &
                to_string(duty, 6) & " +-" & to_string(config.duty_tolerance, 6) & "." & add_msg_delimiter(msg), scope);
          v_num_failed := v_num_failed + 1;
        end if;
      else
        v_period_ok := abs (v_period - period) <= config.period_tolerance;
        v_active_ok := abs (v_active_time - active_time) <= config.active_time_tolerance;
        if not v_period_ok and not v_active_ok then
          alert(alert_level, proc_call & "=> Failed in period " & to_string(i) & "/" & to_string(num_periods) & ". " &
                time_mismatch("T", v_period, period, config.period_tolerance) & "; " &
                time_mismatch("t_on", v_active_time, active_time, config.active_time_tolerance) & "." & add_msg_delimiter(msg), scope);
        elsif not v_period_ok then
          alert(alert_level, proc_call & "=> Failed in period " & to_string(i) & "/" & to_string(num_periods) & ". " &
                time_mismatch("T", v_period, period, config.period_tolerance) & "." & add_msg_delimiter(msg), scope);
        elsif not v_active_ok then
          alert(alert_level, proc_call & "=> Failed in period " & to_string(i) & "/" & to_string(num_periods) & ". " &
                time_mismatch("t_on", v_active_time, active_time, config.active_time_tolerance) & "." & add_msg_delimiter(msg), scope);
        end if;
        if not (v_period_ok and v_active_ok) then
          v_num_failed := v_num_failed + 1;
        end if;
      end if;
    end loop;

    if v_num_failed = 0 then
      log(config.id_for_bfm, proc_call & "=> OK, " & to_string(num_periods) & " period(s) checked." & add_msg_delimiter(msg), scope,
          msg_id_panel);
    end if;
  end procedure;

  --==========================================================================================
  -- Level and duty conversion functions
  --==========================================================================================
  function pwm_active_level(
    constant config : in t_pwm_bfm_config
  ) return std_logic is
  begin
    if config.polarity = ACTIVE_HIGH then
      return '1';
    else
      return '0';
    end if;
  end function;

  function pwm_inactive_level(
    constant config : in t_pwm_bfm_config
  ) return std_logic is
  begin
    if config.polarity = ACTIVE_HIGH then
      return '0';
    else
      return '1';
    end if;
  end function;

  function pwm_idle_value(
    constant config : in t_pwm_bfm_config
  ) return std_logic is
  begin
    case config.idle_level is
      when IDLE_INACTIVE => return pwm_inactive_level(config);
      when IDLE_ACTIVE   => return pwm_active_level(config);
      when IDLE_HIGH_Z   => return 'Z';
    end case;
  end function;

  function pwm_duty_to_active_time(
    constant duty   : in real;
    constant period : in time
  ) return time is
  begin
    return units_to_time(duty * time_to_units(period));
  end function;

  function pwm_count_to_active_time(
    constant count      : in natural;
    constant resolution : in positive;
    constant period     : in time
  ) return time is
  begin
    return units_to_time(time_to_units(period) * real(count) / real(resolution));
  end function;

  --==========================================================================================
  -- BFM procedures
  --==========================================================================================
  procedure pwm_drive_idle(
    signal   pwm    : inout std_logic;
    constant config : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    pwm <= pwm_idle_value(config);
  end procedure;

  -- Internal: the assignments of one period, as time relative to the period start and level. The first one is at the
  -- period boundary (an edge only if the previous period ended at the other level). 0 % and 100 % give one assignment
  -- of a constant level, so no edges and no jitter. With config.jitter > 0 ns the times are already jittered.
  type t_period_times is array (0 to 2) of time;

  procedure plan_period(
    constant period      : in time;
    constant active_time : in time;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive;
    variable times       : out t_period_times;
    variable levels      : out std_logic_vector(0 to 2);
    variable last        : out natural
  ) is
    constant C_RESOLUTION : time      := std.env.resolution_limit;
    constant C_ACTIVE     : std_logic := pwm_active_level(config);
    constant C_INACTIVE   : std_logic := pwm_inactive_level(config);
    constant C_OFF_TIME   : time      := period - active_time;
    variable v_ideal      : t_period_times;
    variable v_level      : std_logic_vector(0 to 2);
    variable v_last       : natural;
    variable v_first_gap  : time;
    variable v_offset     : time;
    variable v_time       : time;
    variable v_prev       : time := 0 ns;
  begin
    if active_time = 0 ns then
      times(0)  := 0 ns;
      levels(0) := C_INACTIVE;
      last      := 0;
      return;
    elsif active_time = period then
      times(0)  := 0 ns;
      levels(0) := C_ACTIVE;
      last      := 0;
      return;
    end if;

    case config.alignment is
      when LEFT_ALIGNED =>
        v_ideal(0 to 1) := (0 ns, active_time);
        v_level(0 to 1) := C_ACTIVE & C_INACTIVE;
        v_last          := 1;
      when RIGHT_ALIGNED =>
        v_ideal(0 to 1) := (0 ns, C_OFF_TIME);
        v_level(0 to 1) := C_INACTIVE & C_ACTIVE;
        v_last          := 1;
      when CENTER_ALIGNED =>
        -- An odd number of resolution units in the off time: the extra unit goes to the second gap
        v_first_gap := units_to_time(floor(time_to_units(C_OFF_TIME) / 2.0));
        v_ideal     := (0 ns, v_first_gap, v_first_gap + active_time);
        v_level     := C_INACTIVE & C_ACTIVE & C_INACTIVE;
        v_last      := 2;
    end case;

    for i in 0 to v_last loop
      v_time := v_ideal(i);
      if config.jitter > 0 ns then
        -- Offset relative to the ideal time, so the jitter does not accumulate. Clamped so that the edges keep their
        -- order, every pulse and gap is at least one resolution unit and every edge stays within its period.
        random(-config.jitter, config.jitter, C_RESOLUTION, seed1, seed2, v_offset, "pwm_drive_period");
        v_time := v_time + v_offset;
        if i = 0 then
          v_time := maximum(v_time, 0 ns);
        else
          v_time := maximum(v_time, v_prev + C_RESOLUTION);
        end if;
        v_time := minimum(v_time, period - (v_last + 1 - i) * C_RESOLUTION);
      end if;
      times(i) := v_time;
      v_prev   := v_time;
    end loop;
    levels := v_level;
    last   := v_last;
  end procedure;

  procedure pwm_drive_period(
    constant period      : in time;
    constant active_time : in time;
    signal   pwm         : inout std_logic;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive
  ) is
    variable v_times  : t_period_times;
    variable v_levels : std_logic_vector(0 to 2);
    variable v_last   : natural;
    variable v_now    : time := 0 ns;
  begin
    plan_period(period, active_time, config, seed1, seed2, v_times, v_levels, v_last);
    for i in 0 to v_last loop
      if v_times(i) > v_now then
        wait for v_times(i) - v_now;
      end if;
      pwm   <= v_levels(i);
      v_now := v_times(i);
    end loop;
    wait for period - v_now;
  end procedure;

  procedure pwm_drive_period(
    constant period      : in time;
    constant active_time : in time;
    signal   pwm         : inout std_logic;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive;
    signal   abort       : in boolean;
    variable aborted     : out boolean
  ) is
    variable v_times  : t_period_times;
    variable v_levels : std_logic_vector(0 to 2);
    variable v_last   : natural;
    variable v_now    : time := 0 ns;
  begin
    aborted := false;
    plan_period(period, active_time, config, seed1, seed2, v_times, v_levels, v_last);
    for i in 0 to v_last loop
      if v_times(i) > v_now then
        wait on abort for v_times(i) - v_now;
        if abort'event then
          aborted := true;
          return;
        end if;
      end if;
      pwm   <= v_levels(i);
      v_now := v_times(i);
    end loop;
    wait on abort for period - v_now;
    aborted := abort'event;
  end procedure;

  procedure pwm_generate(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period, ns) & ", " & to_string(active_time, ns) & ", " &
                                     to_string(num_periods) & ")";
  begin
    generate_periods(C_PROC_NAME, period, active_time, num_periods, msg, pwm, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_generate(
    constant period       : in time;
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period, ns) & ", duty " & to_string(duty, 6) & ", " &
                                     to_string(num_periods) & ")";
  begin
    if duty < 0.0 or duty > 1.0 then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. duty must be within 0.0 to 1.0." & add_msg_delimiter(msg), scope);
      return;
    end if;
    generate_periods(C_PROC_NAME, period, pwm_duty_to_active_time(duty, period), num_periods, msg, pwm, scope,
                     msg_id_panel, config);
  end procedure;

  procedure pwm_generate(
    constant period       : in time;
    constant count        : in integer;
    constant resolution   : in integer;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : inout std_logic;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period, ns) & ", count " & to_string(count) & "/" &
                                     to_string(resolution) & ", " & to_string(num_periods) & ")";
  begin
    if resolution < 1 then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. resolution must be >= 1." & add_msg_delimiter(msg), scope);
      return;
    elsif count < 0 or count > resolution then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. count must be within 0 to resolution." & add_msg_delimiter(msg), scope);
      return;
    end if;
    generate_periods(C_PROC_NAME, period, pwm_count_to_active_time(count, resolution, period), num_periods, msg, pwm,
                     scope, msg_id_panel, config);
  end procedure;

  ---------------------------------------------------------------------------------
  -- Internal: the observation procedures, with or without a terminate signal
  ---------------------------------------------------------------------------------
  procedure log_terminated(
    constant proc_call    : in string;
    constant msg          : in string;
    constant scope        : in string;
    constant msg_id_panel : in t_msg_id_panel
  ) is
  begin
    log(ID_TERMINATE_CMD, proc_call & "=> terminated." & add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  procedure measure_impl(
    variable result        : out t_pwm_measurement;
    constant msg           : in string;
    signal   pwm           : in std_logic;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    constant timeout       : in time;
    constant scope         : in string;
    constant msg_id_panel  : in t_msg_id_panel;
    constant config        : in t_pwm_bfm_config
  ) is
    constant C_PROC_NAME   : string := "pwm_measure()";
    constant C_TIMEOUT     : time   := resolve_timeout(timeout, 0 ns, config);
    variable v_valid       : boolean;
    variable v_timed_out   : boolean;
    variable v_period      : time;
    variable v_active_time : time;
    variable v_result      : t_pwm_measurement := C_PWM_MEASUREMENT_DEFAULT;
    variable v_terminated  : boolean;
  begin
    result := C_PWM_MEASUREMENT_DEFAULT;
    check_observe_parameters(C_PROC_NAME, C_TIMEOUT, false, false, false, config, msg, scope, v_valid);
    if not v_valid then
      return;
    end if;

    await_period_start(pwm, C_TIMEOUT, ERROR, C_PROC_NAME, msg, scope, config, terminate, use_terminate, v_timed_out, v_terminated);
    if v_terminated then
      log_terminated(C_PROC_NAME, msg, scope, msg_id_panel);
      return;
    elsif v_timed_out then
      -- No edge within the timeout: a constant level (spec 5.2), reported as result
      v_result.is_constant    := true;
      v_result.constant_level := pwm;
      if pwm = pwm_active_level(config) then
        v_result.duty_cycle := 1.0;
      elsif not (is_valid_level(pwm) or (pwm = 'Z' and config.idle_level = IDLE_HIGH_Z)) then
        alert(ERROR, C_PROC_NAME & "=> Failed. Invalid constant level '" & to_string(pwm) & "' on the line." & add_msg_delimiter(msg), scope);
      end if;
      result := v_result;
      log(config.id_for_bfm, C_PROC_NAME & "=> constant level '" & to_string(pwm) & "' (no edge within " & to_string(C_TIMEOUT, ns) &
          "), duty cycle " & to_string(v_result.duty_cycle, 1) & "." & add_msg_delimiter(msg), scope, msg_id_panel);
      return;
    end if;

    measure_period(pwm, C_TIMEOUT, ERROR, "", C_PROC_NAME, msg, scope, config, terminate, use_terminate, v_period, v_active_time,
                   v_timed_out, v_terminated);
    if v_terminated then
      log_terminated(C_PROC_NAME, msg, scope, msg_id_panel);
      return;
    elsif v_timed_out then
      return;
    end if;
    v_result.period      := v_period;
    v_result.active_time := v_active_time;
    v_result.duty_cycle  := duty_of(v_active_time, v_period);
    result               := v_result;
    log(config.id_for_bfm, C_PROC_NAME & "=> T " & to_string(v_period, ns) & ", t_on " & to_string(v_active_time, ns) & ", duty cycle " &
        to_string(v_result.duty_cycle, 6) & "." & add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure;

  procedure check_impl(
    constant period        : in time;
    constant active_time   : in time;
    constant num_periods   : in integer;
    constant msg           : in string;
    signal   pwm           : in std_logic;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    constant alert_level   : in t_alert_level;
    constant timeout       : in time;
    constant scope         : in string;
    constant msg_id_panel  : in t_msg_id_panel;
    constant config        : in t_pwm_bfm_config
  ) is
    constant C_PROC_NAME : string  := "pwm_check(" & to_string(period, ns) & ", " & to_string(active_time, ns) & ", " &
                                      to_string(num_periods) & ")";
    constant C_CONSTANT  : boolean := active_time = 0 ns or active_time = period;
    constant C_TIMEOUT   : time    := resolve_timeout(timeout, period, config);
    variable v_valid     : boolean;
    variable v_terminated : boolean;
  begin
    if period <= 0 ns then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. period must be > 0 ns, was " & to_string(period, ns) & "." & add_msg_delimiter(msg), scope);
      return;
    elsif active_time < 0 ns then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. active_time must be >= 0 ns, was " & to_string(active_time, ns) & "." & add_msg_delimiter(msg), scope);
      return;
    elsif active_time > period then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. active_time (" & to_string(active_time, ns) & ") must not exceed period (" &
            to_string(period, ns) & ")." & add_msg_delimiter(msg), scope);
      return;
    elsif num_periods < 1 then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. num_periods must be >= 1, was " & to_string(num_periods) & "." & add_msg_delimiter(msg), scope);
      return;
    end if;
    check_observe_parameters(C_PROC_NAME, C_TIMEOUT, C_CONSTANT, not C_CONSTANT, false, config, msg, scope, v_valid);
    if not v_valid then
      return;
    end if;

    if active_time = 0 ns then
      check_constant_level(pwm_inactive_level(config), C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope, msg_id_panel, config, terminate,
                           use_terminate, v_terminated);
    elsif active_time = period then
      check_constant_level(pwm_active_level(config), C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope, msg_id_panel, config, terminate,
                           use_terminate, v_terminated);
    else
      check_periods(period, active_time, 0.0, false, num_periods, C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope,
                    msg_id_panel, config, terminate, use_terminate, v_terminated);
    end if;
    if v_terminated then
      log_terminated(C_PROC_NAME, msg, scope, msg_id_panel);
    end if;
  end procedure;

  procedure check_duty_impl(
    constant duty          : in real;
    constant num_periods   : in integer;
    constant msg           : in string;
    signal   pwm           : in std_logic;
    signal   terminate     : in std_logic;
    constant use_terminate : in boolean;
    constant alert_level   : in t_alert_level;
    constant timeout       : in time;
    constant scope         : in string;
    constant msg_id_panel  : in t_msg_id_panel;
    constant config        : in t_pwm_bfm_config
  ) is
    constant C_PROC_NAME : string  := "pwm_check_duty(" & to_string(duty, 6) & ", " & to_string(num_periods) & ")";
    constant C_CONSTANT  : boolean := duty = 0.0 or duty = 1.0;
    constant C_TIMEOUT   : time    := resolve_timeout(timeout, 0 ns, config);
    variable v_valid     : boolean;
    variable v_terminated : boolean;
  begin
    if duty < 0.0 or duty > 1.0 then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. duty must be within 0.0 to 1.0." & add_msg_delimiter(msg), scope);
      return;
    elsif num_periods < 1 then
      alert(TB_ERROR, C_PROC_NAME & "=> Failed. num_periods must be >= 1, was " & to_string(num_periods) & "." & add_msg_delimiter(msg), scope);
      return;
    end if;
    check_observe_parameters(C_PROC_NAME, C_TIMEOUT, C_CONSTANT, false, not C_CONSTANT, config, msg, scope, v_valid);
    if not v_valid then
      return;
    end if;

    if duty = 0.0 then
      check_constant_level(pwm_inactive_level(config), C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope, msg_id_panel, config, terminate,
                           use_terminate, v_terminated);
    elsif duty = 1.0 then
      check_constant_level(pwm_active_level(config), C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope, msg_id_panel, config, terminate,
                           use_terminate, v_terminated);
    else
      check_periods(0 ns, 0 ns, duty, true, num_periods, C_TIMEOUT, alert_level, C_PROC_NAME, msg, pwm, scope, msg_id_panel, config,
                    terminate, use_terminate, v_terminated);
    end if;
    if v_terminated then
      log_terminated(C_PROC_NAME, msg, scope, msg_id_panel);
    end if;
  end procedure;

  ---------------------------------------------------------------------------------
  -- Observation procedures
  ---------------------------------------------------------------------------------
  procedure pwm_measure(
    variable result       : out t_pwm_measurement;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    measure_impl(result, msg, pwm, pwm, false, timeout, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_check(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    check_impl(period, active_time, num_periods, msg, pwm, pwm, false, alert_level, timeout, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_check_duty(
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    check_duty_impl(duty, num_periods, msg, pwm, pwm, false, alert_level, timeout, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_measure(
    variable result       : out t_pwm_measurement;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    measure_impl(result, msg, pwm, terminate, true, timeout, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_check(
    constant period       : in time;
    constant active_time  : in time;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    check_impl(period, active_time, num_periods, msg, pwm, terminate, true, alert_level, timeout, scope, msg_id_panel, config);
  end procedure;

  procedure pwm_check_duty(
    constant duty         : in real;
    constant num_periods  : in integer;
    constant msg          : in string;
    signal   pwm          : in std_logic;
    signal   terminate    : in std_logic;
    constant alert_level  : in t_alert_level    := ERROR;
    constant timeout      : in time             := C_UNDEFINED_TIME;
    constant scope        : in string           := C_BFM_SCOPE;
    constant msg_id_panel : in t_msg_id_panel   := shared_msg_id_panel;
    constant config       : in t_pwm_bfm_config := C_PWM_BFM_CONFIG_DEFAULT
  ) is
  begin
    check_duty_impl(duty, num_periods, msg, pwm, terminate, true, alert_level, timeout, scope, msg_id_panel, config);
  end procedure;

end package body pwm_bfm_pkg;
