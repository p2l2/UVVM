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
-- Description   : Support package of the PWM maintenance testbenches: an edge log filled by an edge-logger process and a
--                 reference model of the expected edges. The model does not use pwm_bfm_pkg (only its enum types), so
--                 that a timing error in the BFM is not repeated in the expected values.
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library p2l2_vip_pwm;
use p2l2_vip_pwm.pwm_bfm_pkg.t_pwm_alignment;
use p2l2_vip_pwm.pwm_bfm_pkg.t_pwm_polarity;
use p2l2_vip_pwm.pwm_bfm_pkg.t_pwm_idle_level;

package pwm_tb_pkg is

  type t_edge is record
    time_stamp : time;
    level      : std_logic; -- the new level
  end record t_edge;
  type t_edge_array is array (natural range <>) of t_edge;

  -- Parameters of one period of the reference waveform
  type t_period_param is record
    period      : time;
    active_time : time;
  end record t_period_param;
  type t_period_param_array is array (natural range <>) of t_period_param;

  constant C_MAX_EDGES : positive := 8192;

  type t_edge_log is protected
    procedure clear;
    procedure add(
      constant time_stamp : in time;
      constant level      : in std_logic);
    impure function count return natural;
    impure function get(
      constant idx : in natural) return t_edge;
  end protected t_edge_log;

  function tb_active_level(
    constant polarity : in t_pwm_polarity) return std_logic;

  function tb_idle_value(
    constant polarity   : in t_pwm_polarity;
    constant idle_level : in t_pwm_idle_level) return std_logic;

  -- num_periods times the same period
  function repeat_period(
    constant period      : in time;
    constant active_time : in time;
    constant num_periods : in positive) return t_period_param_array;

  -- Edges expected when the periods in 'params' are generated back to back from 'start', starting from
  -- 'initial_level' and returning to 'idle' after the last period (spec 3.4, 3.5, A-08).
  function expected_edges(
    constant start         : in time;
    constant initial_level : in std_logic;
    constant params        : in t_period_param_array;
    constant alignment     : in t_pwm_alignment;
    constant active        : in std_logic;
    constant idle          : in std_logic) return t_edge_array;

  -- Compares the logged edges with the expected edges: number, time and level of each edge. Reports the first
  -- mismatch only and then logs all logged edges.
  procedure check_edges(
    variable edge_log : inout t_edge_log;
    constant expected : in t_edge_array;
    constant msg      : in string;
    constant scope    : in string := C_TB_SCOPE_DEFAULT);

end package pwm_tb_pkg;

package body pwm_tb_pkg is

  type t_edge_log is protected body
    variable v_edges : t_edge_array(0 to C_MAX_EDGES - 1);
    variable v_count : natural := 0;

    procedure clear is
    begin
      v_count := 0;
    end procedure;

    procedure add(
      constant time_stamp : in time;
      constant level      : in std_logic) is
    begin
      if v_count < C_MAX_EDGES then
        v_edges(v_count) := (time_stamp, level);
      else
        alert(TB_ERROR, "Edge log full (" & to_string(C_MAX_EDGES) & " edges)");
      end if;
      v_count := v_count + 1;
    end procedure;

    impure function count return natural is
    begin
      return v_count;
    end function;

    impure function get(
      constant idx : in natural) return t_edge is
    begin
      return v_edges(idx);
    end function;
  end protected body t_edge_log;

  function tb_active_level(
    constant polarity : in t_pwm_polarity) return std_logic is
  begin
    if polarity = ACTIVE_HIGH then
      return '1';
    end if;
    return '0';
  end function;

  function tb_idle_value(
    constant polarity   : in t_pwm_polarity;
    constant idle_level : in t_pwm_idle_level) return std_logic is
    constant C_ACTIVE : std_logic := tb_active_level(polarity);
  begin
    case idle_level is
      when IDLE_INACTIVE => return not C_ACTIVE;
      when IDLE_ACTIVE   => return C_ACTIVE;
      when IDLE_HIGH_Z   => return 'Z';
    end case;
  end function;

  function repeat_period(
    constant period      : in time;
    constant active_time : in time;
    constant num_periods : in positive) return t_period_param_array is
    constant C_PARAMS : t_period_param_array(1 to num_periods) := (others => (period, active_time));
  begin
    return C_PARAMS;
  end function;

  function expected_edges(
    constant start         : in time;
    constant initial_level : in std_logic;
    constant params        : in t_period_param_array;
    constant alignment     : in t_pwm_alignment;
    constant active        : in std_logic;
    constant idle          : in std_logic) return t_edge_array is
    constant C_RESOLUTION : time      := std.env.resolution_limit;
    constant C_INACTIVE   : std_logic := not active;
    variable v_edges      : t_edge_array(0 to 3 * params'length);
    variable v_num        : natural   := 0;
    variable v_level      : std_logic := initial_level;
    variable v_time       : time      := start;
    variable v_off_time   : time;
    variable v_first_gap  : time;

    -- The line is at 'level' for 'duration' from v_time on
    procedure segment(
      constant level    : in std_logic;
      constant duration : in time) is
    begin
      if duration > 0 ns then
        if level /= v_level then
          v_edges(v_num) := (v_time, level);
          v_num          := v_num + 1;
          v_level        := level;
        end if;
        v_time := v_time + duration;
      end if;
    end procedure;
  begin
    for i in params'range loop
      v_off_time := params(i).period - params(i).active_time;
      case alignment is
        when LEFT_ALIGNED =>
          segment(active, params(i).active_time);
          segment(C_INACTIVE, v_off_time);
        when RIGHT_ALIGNED =>
          segment(C_INACTIVE, v_off_time);
          segment(active, params(i).active_time);
        when CENTER_ALIGNED =>
          v_first_gap := ((v_off_time / C_RESOLUTION) / 2) * C_RESOLUTION;
          segment(C_INACTIVE, v_first_gap);
          segment(active, params(i).active_time);
          segment(C_INACTIVE, v_off_time - v_first_gap);
      end case;
    end loop;
    if idle /= v_level then
      v_edges(v_num) := (v_time, idle);
      v_num          := v_num + 1;
    end if;
    return v_edges(0 to v_num - 1);
  end function;

  procedure check_edges(
    variable edge_log : inout t_edge_log;
    constant expected : in t_edge_array;
    constant msg      : in string;
    constant scope    : in string := C_TB_SCOPE_DEFAULT) is
    variable v_ok   : boolean;
    variable v_edge : t_edge;
  begin
    v_ok := check_value(edge_log.count, expected'length, ERROR, "number of edges: " & msg, scope, ID_SEQUENCER_SUB);
    for i in 0 to minimum(edge_log.count, expected'length) - 1 loop
      exit when not v_ok;
      v_edge := edge_log.get(i);
      v_ok   := check_value(v_edge.time_stamp, expected(expected'low + i).time_stamp, ERROR,
                            "time of edge " & to_string(i) & ": " & msg, scope, ID_NEVER);
      if v_ok then
        v_ok := check_value(v_edge.level, expected(expected'low + i).level, MATCH_EXACT, ERROR,
                            "level of edge " & to_string(i) & ": " & msg, scope, ID_NEVER);
      end if;
    end loop;
    if not v_ok then
      for i in 0 to minimum(edge_log.count, C_MAX_EDGES) - 1 loop
        v_edge := edge_log.get(i);
        log(ID_SEQUENCER, "logged edge " & to_string(i) & ": " & to_string(v_edge.time_stamp) & " -> " &
                          to_string(v_edge.level), scope);
      end loop;
    end if;
  end procedure;

end package body pwm_tb_pkg;
