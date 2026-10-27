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
-- Description   : Support package of the rotary encoder maintenance testbenches: an event log of A/B/Z with an
--                 independent quadrature decoder (spec 8), check procedures and exact expected edge times (tb arch 3).
--                 Nothing here uses the BFM procedures (only its interface type), so that a BFM error is not repeated
--                 in the expected values.
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library p2l2_vip_rotary_encoder;
use p2l2_vip_rotary_encoder.rotary_encoder_bfm_pkg.t_rotary_encoder_if;

package rotary_encoder_tb_pkg is

  constant C_RESOLUTION : time := std.env.resolution_limit;

  -- Log ids: the BFM testbench uses id 1, the test harness ids 1 to 3 (one per VVC instance)
  constant C_NUM_LOGS : positive := 3;

  -- One wake-up of a logger process: every delta cycle in which A, B or Z changed (tb arch 3.1)
  type t_enc_event is record
    time_stamp : time;
    a          : std_logic;
    b          : std_logic;
    z          : std_logic;
    a_changed  : boolean;
    b_changed  : boolean;
    z_changed  : boolean;
  end record t_enc_event;
  type t_enc_event_array is array (natural range <>) of t_enc_event;

  -- Event log with decoder checker per id. The checker classifies entries only after arm(); it counts and never
  -- alerts (tb arch 3.2). clear() empties the log and resets the counters, but keeps the checker armed.
  type t_event_log is protected
    procedure clear(
      constant id : in positive);
    procedure arm(
      constant id     : in positive;
      constant enc_if : in t_rotary_encoder_if);
    procedure add(
      constant id        : in positive;
      constant enc_if    : in t_rotary_encoder_if;
      constant a_changed : in boolean;
      constant b_changed : in boolean;
      constant z_changed : in boolean);
    impure function count(
      constant id : in positive) return natural;
    impure function get(
      constant id  : in positive;
      constant idx : in natural) return t_enc_event;
    impure function position_change(
      constant id : in positive) return integer;
    impure function num_edges(
      constant id : in positive) return natural;
    impure function num_illegal(
      constant id : in positive) return natural;
    impure function num_invalid_level(
      constant id : in positive) return natural;
    impure function num_z_events(
      constant id : in positive) return natural;
  end protected t_event_log;

  -- Position in the A-leads-B Gray sequence 00 -> 10 -> 11 -> 01 (AB, spec 8): 0 to 3, -1 for a non-'0'/'1' level
  function gray_index(
    constant a : in std_logic;
    constant b : in std_logic) return integer;

  -- Ideal time of edge k (k = 1 is the first edge) of a move started at t_start with an integer rpm:
  -- t_start + (k - 1/2) * 60 s / (rpm * 4 * cycles_per_rev), floored to the simulator resolution. Exact integer/time
  -- arithmetic, no accumulated error (tb arch 3.4).
  function ideal_edge_time(
    constant t_start        : in time;
    constant k              : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time;

  -- Checker counters since the last clear(): position change, illegal transitions, invalid levels (tb arch 3.2, TD-5)
  procedure check_checker(
    variable event_log           : inout t_event_log;
    constant id                  : in positive;
    constant exp_position_change : in integer;
    constant msg                 : in string;
    constant exp_illegal         : in natural := 0;
    constant exp_invalid         : in natural := 0;
    constant scope               : in string  := C_TB_SCOPE_DEFAULT);

  -- No logged event with from_time <= time_stamp <= to_time
  procedure check_no_event(
    variable event_log : inout t_event_log;
    constant id        : in positive;
    constant from_time : in time;
    constant to_time   : in time;
    constant msg       : in string;
    constant scope     : in string := C_TB_SCOPE_DEFAULT);

end package rotary_encoder_tb_pkg;

package body rotary_encoder_tb_pkg is

  function is_01(
    constant value : in std_logic) return boolean is
  begin
    return value = '0' or value = '1';
  end function;

  function gray_index(
    constant a : in std_logic;
    constant b : in std_logic) return integer is
  begin
    if not is_01(a) or not is_01(b) then
      return -1;
    elsif a = '0' and b = '0' then
      return 0;
    elsif a = '1' and b = '0' then
      return 1;
    elsif a = '1' and b = '1' then
      return 2;
    else
      return 3;
    end if;
  end function;

  type t_event_log is protected body
    type t_enc_event_array_ptr is access t_enc_event_array;
    type t_ptr_array is array (1 to C_NUM_LOGS) of t_enc_event_array_ptr;

    variable v_events    : t_ptr_array                        := (others => null);
    variable v_count     : integer_vector(1 to C_NUM_LOGS)    := (others => 0);
    variable v_armed     : boolean_vector(1 to C_NUM_LOGS)    := (others => false);
    variable v_last_gray : integer_vector(1 to C_NUM_LOGS)    := (others => -1);
    variable v_position  : integer_vector(1 to C_NUM_LOGS)    := (others => 0);
    variable v_edges     : integer_vector(1 to C_NUM_LOGS)    := (others => 0);
    variable v_illegal   : integer_vector(1 to C_NUM_LOGS)    := (others => 0);
    variable v_invalid   : integer_vector(1 to C_NUM_LOGS)    := (others => 0);
    variable v_z_events  : integer_vector(1 to C_NUM_LOGS)    := (others => 0);

    procedure clear(
      constant id : in positive) is
    begin
      v_count(id)    := 0;
      v_position(id) := 0;
      v_edges(id)    := 0;
      v_illegal(id)  := 0;
      v_invalid(id)  := 0;
      v_z_events(id) := 0;
    end procedure;

    procedure arm(
      constant id     : in positive;
      constant enc_if : in t_rotary_encoder_if) is
    begin
      v_armed(id)     := true;
      v_last_gray(id) := gray_index(enc_if.a, enc_if.b);
    end procedure;

    procedure add(
      constant id        : in positive;
      constant enc_if    : in t_rotary_encoder_if;
      constant a_changed : in boolean;
      constant b_changed : in boolean;
      constant z_changed : in boolean) is
      variable v_old  : t_enc_event_array_ptr;
      variable v_gray : integer;
      variable v_step : integer;
    begin
      -- Store, growing the array by doubling
      if v_events(id) = null then
        v_events(id) := new t_enc_event_array(0 to 1023);
      elsif v_count(id) > v_events(id)'high then
        v_old        := v_events(id);
        v_events(id) := new t_enc_event_array(0 to 2 * v_old'length - 1);
        v_events(id)(v_old'range) := v_old.all;
        deallocate(v_old);
      end if;
      v_events(id)(v_count(id)) := (now, enc_if.a, enc_if.b, enc_if.z, a_changed, b_changed, z_changed);
      v_count(id) := v_count(id) + 1;

      if not v_armed(id) then
        return;
      end if;
      -- Decoder (spec 8)
      if not is_01(enc_if.a) or not is_01(enc_if.b) or not is_01(enc_if.z) then
        v_invalid(id) := v_invalid(id) + 1;
      end if;
      if z_changed then
        v_z_events(id) := v_z_events(id) + 1;
      end if;
      if a_changed or b_changed then
        v_gray := gray_index(enc_if.a, enc_if.b);
        if a_changed and b_changed then
          v_illegal(id) := v_illegal(id) + 1; -- position unchanged
        elsif v_gray >= 0 and v_last_gray(id) >= 0 then
          v_step := (v_gray - v_last_gray(id)) mod 4;
          if v_step = 1 then
            v_position(id) := v_position(id) + 1;
            v_edges(id)    := v_edges(id) + 1;
          elsif v_step = 3 then
            v_position(id) := v_position(id) - 1;
            v_edges(id)    := v_edges(id) + 1;
          elsif v_step = 2 then
            v_illegal(id) := v_illegal(id) + 1; -- both channels changed across an invalid level
          end if;
        end if;
        if v_gray >= 0 then
          v_last_gray(id) := v_gray;
        end if;
      end if;
    end procedure;

    impure function count(
      constant id : in positive) return natural is
    begin
      return v_count(id);
    end function;

    impure function get(
      constant id  : in positive;
      constant idx : in natural) return t_enc_event is
    begin
      if idx >= v_count(id) then
        alert(TB_ERROR, "Event log " & to_string(id) & ": index " & to_string(idx) & " beyond " & to_string(v_count(id)) &
                        " events");
        return (0 ns, 'U', 'U', 'U', false, false, false);
      end if;
      return v_events(id)(idx);
    end function;

    impure function position_change(
      constant id : in positive) return integer is
    begin
      return v_position(id);
    end function;

    impure function num_edges(
      constant id : in positive) return natural is
    begin
      return v_edges(id);
    end function;

    impure function num_illegal(
      constant id : in positive) return natural is
    begin
      return v_illegal(id);
    end function;

    impure function num_invalid_level(
      constant id : in positive) return natural is
    begin
      return v_invalid(id);
    end function;

    impure function num_z_events(
      constant id : in positive) return natural is
    begin
      return v_z_events(id);
    end function;
  end protected body t_event_log;

  function ideal_edge_time(
    constant t_start        : in time;
    constant k              : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time is
    constant C_NUM   : natural := (2 * k - 1) * 30;          -- (k - 1/2) * 60
    constant C_DEN   : natural := rpm * 4 * cycles_per_rev;
    variable v_time  : time    := t_start + (C_NUM / C_DEN) * 1 sec;
    variable v_rem   : natural := C_NUM mod C_DEN;
    variable v_unit  : time    := 1 sec;
  begin
    -- Decimal long division of the fraction of a second, one digit per power of ten down to the resolution
    while v_unit > C_RESOLUTION loop
      v_unit := v_unit / 10;
      v_rem  := v_rem * 10;
      v_time := v_time + (v_rem / C_DEN) * v_unit;
      v_rem  := v_rem mod C_DEN;
    end loop;
    return v_time;
  end function;

  procedure check_checker(
    variable event_log           : inout t_event_log;
    constant id                  : in positive;
    constant exp_position_change : in integer;
    constant msg                 : in string;
    constant exp_illegal         : in natural := 0;
    constant exp_invalid         : in natural := 0;
    constant scope               : in string  := C_TB_SCOPE_DEFAULT) is
  begin
    check_value(event_log.position_change(id), exp_position_change, ERROR,
                "encoder " & to_string(id) & " position change: " & msg, scope, ID_SEQUENCER_SUB);
    check_value(event_log.num_illegal(id), exp_illegal, ERROR,
                "encoder " & to_string(id) & " illegal transitions: " & msg, scope, ID_SEQUENCER_SUB);
    check_value(event_log.num_invalid_level(id), exp_invalid, ERROR,
                "encoder " & to_string(id) & " invalid levels: " & msg, scope, ID_SEQUENCER_SUB);
  end procedure;

  procedure check_no_event(
    variable event_log : inout t_event_log;
    constant id        : in positive;
    constant from_time : in time;
    constant to_time   : in time;
    constant msg       : in string;
    constant scope     : in string := C_TB_SCOPE_DEFAULT) is
    variable v_event : t_enc_event;
    variable v_found : natural := 0;
  begin
    for i in 0 to event_log.count(id) - 1 loop
      v_event := event_log.get(id, i);
      if v_event.time_stamp >= from_time and v_event.time_stamp <= to_time then
        if v_found = 0 then
          alert(ERROR, "encoder " & to_string(id) & ": unexpected event at " & to_string(v_event.time_stamp, ns) &
                       " (A " & to_string(v_event.a) & ", B " & to_string(v_event.b) & ", Z " & to_string(v_event.z) &
                       "): " & msg, scope);
        end if;
        v_found := v_found + 1;
      end if;
    end loop;
    if v_found = 0 then
      log(ID_SEQUENCER_SUB, "encoder " & to_string(id) & ": no event from " & to_string(from_time, ns) & " to " &
                            to_string(to_time, ns) & ". '" & msg & "'", scope);
    end if;
  end procedure;

end package body rotary_encoder_tb_pkg;

--==========================================================================================
-- Event log of the testbenches. Separate package: a shared variable of a protected type cannot be declared before the
-- protected type body.
--==========================================================================================
use work.rotary_encoder_tb_pkg.all;

package rotary_encoder_th_pkg is
  -- Filled by the logger processes (rotary_encoder_th: ids 1 to 3, rotary_encoder_bfm_tb: id 1)
  shared variable shared_th_event_log : t_event_log;
end package rotary_encoder_th_pkg;
