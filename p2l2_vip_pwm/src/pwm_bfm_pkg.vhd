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
    min_pulse_width       => 0 ns,
    timeout               => C_UNDEFINED_TIME,
    timeout_severity      => ERROR,
    id_for_bfm            => ID_BFM,
    id_for_bfm_wait       => ID_BFM_WAIT
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
      alert(TB_ERROR, proc_call & "=> Failed. period must be > 0 ns, was " & to_string(period) & "." & add_msg_delimiter(msg), scope);
    elsif active_time < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. active_time must be >= 0 ns, was " & to_string(active_time) & "." & add_msg_delimiter(msg), scope);
    elsif active_time > period then
      alert(TB_ERROR, proc_call & "=> Failed. active_time (" & to_string(active_time) & ") must not exceed period (" &
            to_string(period) & ")." & add_msg_delimiter(msg), scope);
    elsif num_periods < 1 then
      alert(TB_ERROR, proc_call & "=> Failed. num_periods must be >= 1, was " & to_string(num_periods) & "." & add_msg_delimiter(msg), scope);
    elsif config.jitter < 0 ns then
      alert(TB_ERROR, proc_call & "=> Failed. config.jitter must be >= 0 ns, was " & to_string(config.jitter) & "." & add_msg_delimiter(msg), scope);
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
    log(config.id_for_bfm, proc_call & " completed (active_time " & to_string(active_time) & ")." & add_msg_delimiter(msg), scope, msg_id_panel);
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

  procedure pwm_drive_period(
    constant period      : in time;
    constant active_time : in time;
    signal   pwm         : inout std_logic;
    constant config      : in t_pwm_bfm_config;
    variable seed1       : inout positive;
    variable seed2       : inout positive
  ) is
    constant C_RESOLUTION : time      := std.env.resolution_limit;
    constant C_ACTIVE     : std_logic := pwm_active_level(config);
    constant C_INACTIVE   : std_logic := pwm_inactive_level(config);
    constant C_OFF_TIME   : time      := period - active_time;
    type t_time_array is array (natural range <>) of time;
    -- The assignments of one period: ideal time relative to the period start and level. The first one is at the period
    -- boundary (an edge only if the previous period ended at the other level).
    variable v_ideal      : t_time_array(0 to 2);
    variable v_level      : std_logic_vector(0 to 2);
    variable v_last       : natural;
    variable v_first_gap  : time;
    variable v_offset     : time;
    variable v_time       : time;
    variable v_now        : time := 0 ns;
  begin
    -- 0 % and 100 %: a constant level, no edges and therefore no jitter
    if active_time = 0 ns then
      pwm <= C_INACTIVE;
      wait for period;
      return;
    elsif active_time = period then
      pwm <= C_ACTIVE;
      wait for period;
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
          v_time := maximum(v_time, v_now + C_RESOLUTION);
        end if;
        v_time := minimum(v_time, period - (v_last + 1 - i) * C_RESOLUTION);
      end if;
      if v_time > v_now then
        wait for v_time - v_now;
      end if;
      pwm   <= v_level(i);
      v_now := v_time;
    end loop;
    wait for period - v_now;
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
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period) & ", " & to_string(active_time) & ", " &
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
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period) & ", duty " & to_string(duty, 6) & ", " &
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
    constant C_PROC_NAME : string := "pwm_generate(" & to_string(period) & ", count " & to_string(count) & "/" &
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

end package body pwm_bfm_pkg;
