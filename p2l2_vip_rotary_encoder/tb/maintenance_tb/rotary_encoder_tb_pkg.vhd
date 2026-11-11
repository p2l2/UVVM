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
--                 independent quadrature decoder, check procedures and exact expected edge times.
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

  -- Physical constants (written here, not taken from the BFM, so that a wrong BFM constant is not repeated here)
  constant C_EDGES_PER_CYCLE : positive := 4;   -- Quadrature: 4 edges per cycle
  constant C_SEC_PER_MIN     : positive := 60;
  constant C_DEG_PER_REV     : positive := 360;
  constant C_DEG_ELECTRICAL_PER_EDGE : real := real(C_DEG_PER_REV) / real(C_EDGES_PER_CYCLE); -- 90 deg per edge

  -- Jitter statistics: both bounds reached within 5 % of the amplitude, mean within 1/10 of the amplitude
  -- (j/900 * time_per_edge for an amplitude of j/90 * time_per_edge)
  constant C_JITTER_BOUND_REACHED : real := 0.95;
  constant C_JITTER_MEAN_FRACTION : real := 0.1;

  -- Log ids: the BFM testbench uses id 1, the test harness ids 1 to 3 (one per VVC instance)
  constant C_NUM_LOGS : positive := 3;

  -- Length of the dbg_step waveform label (the current test step); longer texts are truncated
  constant C_DBG_STEP_LENGTH : positive := 120;

  -- One wake-up of a logger process: every delta cycle in which A, B or Z changed
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
  -- alerts. clear() empties the log and resets the counters, but keeps the checker armed.
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

  -- msg as a waveform label of C_DBG_STEP_LENGTH characters: padded with spaces or truncated
  function dbg_text(
    constant msg : in string) return string;

  -- Position in the A-leads-B Gray sequence 00 -> 10 -> 11 -> 01 (AB): 0 to 3, -1 for a non-'0'/'1' level
  function gray_index(
    constant a : in std_logic;
    constant b : in std_logic) return integer;

  -- t_start + numerator / denominator seconds, floored to the simulator resolution. Exact integer/time arithmetic: decimal
  -- long division of the fraction of a second, so no accumulated error and no overflow.
  function ideal_time(
    constant t_start     : in time;
    constant numerator   : in natural;
    constant denominator : in positive) return time;

  -- Ideal time of edge k (k = 1 is the first edge) of a move started at t_start in a state centre with an integer rpm:
  -- t_start + (k - 1/2) * 60 s / (rpm * 4 * cycles_per_rev), floored to the simulator resolution.
  function ideal_edge_time(
    constant t_start        : in time;
    constant k              : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time;

  -- Ideal end of a move of num_edges edges: t_start + num_edges * 60 s / (rpm * 4 * cycles_per_rev), floored
  function ideal_move_time(
    constant t_start        : in time;
    constant num_edges      : in natural;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time;

  -- Ideal duration of an angle move of degrees at rpm: degrees / (6 * rpm) s, floored
  function ideal_angle_time(
    constant degrees : in natural;
    constant rpm     : in positive) return time;

  -- Edges first_idx .. first_idx + num_edges - 1 of the log are A/B edges at expected(k) +- time_tolerance, k = 1 to num_edges
  procedure check_edge_times_list(
    variable event_log      : inout t_event_log;
    constant id             : in positive;
    constant first_idx      : in natural;
    constant num_edges      : in positive;
    constant expected       : in time_vector; -- (1 to num_edges)
    constant time_tolerance : in time;
    constant msg            : in string;
    constant scope          : in string := C_TB_SCOPE_DEFAULT);

  -- Edges first_idx .. first_idx + num_edges - 1 of the log are A/B edges at exactly t_start + (k - 1/2) * time_per_edge
  procedure check_edge_times(
    variable event_log     : inout t_event_log;
    constant id            : in positive;
    constant first_idx     : in natural;
    constant t_start       : in time;
    constant num_edges     : in positive;
    constant time_per_edge : in time;
    constant msg           : in string;
    constant scope         : in string := C_TB_SCOPE_DEFAULT);

  -- As check_edge_times, rpm form: each edge within one resolution step of ideal_edge_time()
  procedure check_edge_times_rpm(
    variable event_log      : inout t_event_log;
    constant id             : in positive;
    constant first_idx      : in natural;
    constant t_start        : in time;
    constant num_edges      : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive;
    constant msg            : in string;
    constant scope          : in string := C_TB_SCOPE_DEFAULT);

  -- Checker counters since the last clear(): position change, illegal transitions, invalid levels. Counted silently; each test step checks them explicitly
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

  ---------------------------------------------------------------------------------
  -- Index model and checks, written independently of the BFM's index decision
  ---------------------------------------------------------------------------------
  -- State (AB on the pins) at position: the state reached from zero_state after position forward edges
  function tb_state(
    constant zero_state : in std_logic_vector(1 downto 0);
    constant position   : in integer) return std_logic_vector;

  -- Z active at position: the index cycle is index_position .. index_position + 3; q is the position in it whose state
  -- is index_state; Z is active at q .. q + index_width - 1, repeated every 4 * cycles_per_rev positions
  function tb_index_active(
    constant position       : in integer;
    constant zero_state     : in std_logic_vector(1 downto 0);
    constant index_state    : in std_logic_vector(1 downto 0);
    constant index_width    : in positive;
    constant index_position : in integer;
    constant cycles_per_rev : in positive) return boolean;

  -- Walks the log from start_position: decodes every A/B entry and checks that Z in the same entry equals the model
  -- (Z changes in the same delta as the A/B edge). activations counts the entries into the
  -- active range.
  procedure check_z_follows_ab(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant start_position : in    integer;
    constant zero_state     : in    std_logic_vector(1 downto 0);
    constant index_state    : in    std_logic_vector(1 downto 0);
    constant index_width    : in    positive;
    constant index_position : in    integer;
    constant cycles_per_rev : in    positive;
    constant index_inverted : in    boolean;
    variable activations    : out   natural;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT);

  -- Compares two logs entry by entry, times relative to t_ref / t_cmp: same A, B and change flags; Z equal, or inverted
  -- with invert_z (index polarity). match is false on the first difference or a different entry count. Raises no alert.
  procedure compare_logs(
    variable event_log : inout t_event_log;
    constant id_ref    : in    positive;
    constant t_ref     : in    time;
    constant id_cmp    : in    positive;
    constant t_cmp     : in    time;
    constant invert_z  : in    boolean;
    variable match     : out   boolean);

  ---------------------------------------------------------------------------------
  -- Bounce and jitter checks
  ---------------------------------------------------------------------------------
  -- Bounce of a time-form move of num_edges edges started at t_start in a state centre: per edge k the first entry
  -- is at exactly t_start + (k - 1/2) * time_per_edge, followed by num_toggles entries on the same channel only, all
  -- within window after the edge, the last one at the level of the edge. With jitter, jitter_amplitude > 0 ns: the
  -- first entry lies within +-(jitter_amplitude + one resolution step) of that time, the window starts at the actual
  -- (jittered) edge, and edges are displaced in both directions. Requires window < time_per_edge - 2 * jitter_amplitude.
  procedure check_bounce(
    variable event_log        : inout t_event_log;
    constant id               : in    positive;
    constant t_start          : in    time;
    constant num_edges        : in    positive;
    constant time_per_edge    : in    time;
    constant num_toggles      : in    natural;
    constant window           : in    time;
    constant msg              : in    string;
    constant scope            : in    string := C_TB_SCOPE_DEFAULT;
    constant jitter_amplitude : in    time   := 0 ns);

  -- Each nominal edge k of a time-form move started at t_start in the centre of start_position is the last entry at
  -- or before t_start + (k - 1/2) * time_per_edge, with the state of position k; the entry before it has the state of
  -- position k - 1, i.e. a bounce was settled before the edge
  procedure check_settled_before_edges(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant t_start        : in    time;
    constant num_edges      : in    positive;
    constant time_per_edge  : in    time;
    constant zero_state     : in    std_logic_vector(1 downto 0);
    constant start_position : in    integer;
    constant direction_sign : in    integer;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT);

  -- Displacements of the A/B entries first_idx .. from expected: each within +-(amplitude + time_tolerance), the
  -- largest at least C_JITTER_BOUND_REACHED * amplitude in both directions, the mean within C_JITTER_MEAN_FRACTION *
  -- amplitude
  procedure check_jitter_stats(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant first_idx      : in    natural;
    constant expected       : in    time_vector;
    constant amplitude      : in    time;
    constant time_tolerance : in    time;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT);

end package rotary_encoder_tb_pkg;

package body rotary_encoder_tb_pkg is

  function is_01(
    constant value : in std_logic) return boolean is
  begin
    return value = '0' or value = '1';
  end function;

  function dbg_text(
    constant msg : in string) return string is
    constant C_LENGTH : natural := minimum(msg'length, C_DBG_STEP_LENGTH);
    variable v_result : string(1 to C_DBG_STEP_LENGTH) := (others => ' ');
  begin
    v_result(1 to C_LENGTH) := msg(msg'left to msg'left + C_LENGTH - 1);
    return v_result;
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
      -- Quadrature decoder: invalid levels, illegal transitions (both channels at once), position
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

  function ideal_time(
    constant t_start     : in time;
    constant numerator   : in natural;
    constant denominator : in positive) return time is
    variable v_time : time    := t_start + (numerator / denominator) * 1 sec;
    variable v_rem  : natural := numerator mod denominator;
    variable v_unit : time    := 1 sec;
  begin
    while v_unit > C_RESOLUTION loop
      v_unit := v_unit / 10;
      v_rem  := v_rem * 10;
      v_time := v_time + (v_rem / denominator) * v_unit;
      v_rem  := v_rem mod denominator;
    end loop;
    return v_time;
  end function;

  function ideal_edge_time(
    constant t_start        : in time;
    constant k              : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time is
  begin
    return ideal_time(t_start, (2 * k - 1) * C_SEC_PER_MIN, 2 * rpm * C_EDGES_PER_CYCLE * cycles_per_rev); -- (k - 1/2)
  end function;

  function ideal_move_time(
    constant t_start        : in time;
    constant num_edges      : in natural;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive) return time is
  begin
    return ideal_time(t_start, num_edges * C_SEC_PER_MIN, rpm * C_EDGES_PER_CYCLE * cycles_per_rev);
  end function;

  function ideal_angle_time(
    constant degrees : in natural;
    constant rpm     : in positive) return time is
  begin
    return ideal_time(0 ns, degrees * C_SEC_PER_MIN, rpm * C_DEG_PER_REV);
  end function;

  procedure check_edge_times_list(
    variable event_log      : inout t_event_log;
    constant id             : in positive;
    constant first_idx      : in natural;
    constant num_edges      : in positive;
    constant expected       : in time_vector; -- (1 to num_edges)
    constant time_tolerance : in time;
    constant msg            : in string;
    constant scope          : in string := C_TB_SCOPE_DEFAULT) is
    variable v_event   : t_enc_event;
    variable v_dev     : time;
    variable v_max_dev : time    := 0 ns;
    variable v_ok      : boolean := true;
  begin
    if event_log.count(id) < first_idx + num_edges then
      alert(ERROR, "encoder " & to_string(id) & ": " & to_string(event_log.count(id) - first_idx) & " events logged, " &
                   to_string(num_edges) & " edges expected: " & msg, scope);
      return;
    end if;
    for k in 1 to num_edges loop
      v_event := event_log.get(id, first_idx + k - 1);
      v_dev   := v_event.time_stamp - expected(k);
      if abs(v_dev) > v_max_dev then
        v_max_dev := abs(v_dev);
      end if;
      if v_ok and (not (v_event.a_changed or v_event.b_changed) or abs(v_dev) > time_tolerance) then
        alert(ERROR, "encoder " & to_string(id) & ": edge " & to_string(k) & " at " & to_string(v_event.time_stamp, ns) &
                     ", expected " & to_string(expected(k), ns) & " +-" & to_string(time_tolerance, ns) & " (A/B changed: " &
                     to_string(v_event.a_changed or v_event.b_changed) & "): " & msg, scope);
        v_ok := false;
      end if;
    end loop;
    if v_ok then
      log(ID_SEQUENCER_SUB, "encoder " & to_string(id) & ": " & to_string(num_edges) & " edge times OK, largest deviation " &
                            to_string(v_max_dev, ns) & ". '" & msg & "'", scope);
    end if;
  end procedure;

  procedure check_edge_times(
    variable event_log     : inout t_event_log;
    constant id            : in positive;
    constant first_idx     : in natural;
    constant t_start       : in time;
    constant num_edges     : in positive;
    constant time_per_edge : in time;
    constant msg           : in string;
    constant scope         : in string := C_TB_SCOPE_DEFAULT) is
    variable v_expected : time_vector(1 to num_edges);
  begin
    for k in 1 to num_edges loop
      v_expected(k) := t_start + (2 * k - 1) * time_per_edge / 2;
    end loop;
    check_edge_times_list(event_log, id, first_idx, num_edges, v_expected, 0 ns, msg, scope);
  end procedure;

  procedure check_edge_times_rpm(
    variable event_log      : inout t_event_log;
    constant id             : in positive;
    constant first_idx      : in natural;
    constant t_start        : in time;
    constant num_edges      : in positive;
    constant rpm            : in positive;
    constant cycles_per_rev : in positive;
    constant msg            : in string;
    constant scope          : in string := C_TB_SCOPE_DEFAULT) is
    variable v_expected : time_vector(1 to num_edges);
  begin
    for k in 1 to num_edges loop
      v_expected(k) := ideal_edge_time(t_start, k, rpm, cycles_per_rev);
    end loop;
    check_edge_times_list(event_log, id, first_idx, num_edges, v_expected, C_RESOLUTION, msg, scope);
  end procedure;

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

  function tb_state(
    constant zero_state : in std_logic_vector(1 downto 0);
    constant position   : in integer) return std_logic_vector is
    constant C_GRAY   : integer := (gray_index(zero_state(1), zero_state(0)) + position mod C_EDGES_PER_CYCLE) mod C_EDGES_PER_CYCLE;
    variable v_result : std_logic_vector(1 downto 0);
  begin
    case C_GRAY is
      when 0      => v_result := "00";
      when 1      => v_result := "10";
      when 2      => v_result := "11";
      when others => v_result := "01";
    end case;
    return v_result;
  end function;

  function tb_index_active(
    constant position       : in integer;
    constant zero_state     : in std_logic_vector(1 downto 0);
    constant index_state    : in std_logic_vector(1 downto 0);
    constant index_width    : in positive;
    constant index_position : in integer;
    constant cycles_per_rev : in positive) return boolean is
    variable v_q : integer := index_position;
  begin
    for p in index_position to index_position + C_EDGES_PER_CYCLE - 1 loop
      if tb_state(zero_state, p) = index_state then
        v_q := p;
      end if;
    end loop;
    return (position - v_q) mod (C_EDGES_PER_CYCLE * cycles_per_rev) < index_width;
  end function;

  procedure check_z_follows_ab(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant start_position : in    integer;
    constant zero_state     : in    std_logic_vector(1 downto 0);
    constant index_state    : in    std_logic_vector(1 downto 0);
    constant index_width    : in    positive;
    constant index_position : in    integer;
    constant cycles_per_rev : in    positive;
    constant index_inverted : in    boolean;
    variable activations    : out   natural;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT) is
    constant C_START_STATE : std_logic_vector(1 downto 0) := tb_state(zero_state, start_position);
    variable v_position    : integer := start_position;
    variable v_gray        : integer := gray_index(C_START_STATE(1), C_START_STATE(0));
    variable v_new_gray    : integer;
    variable v_active      : boolean := tb_index_active(start_position, zero_state, index_state, index_width, index_position,
                                                        cycles_per_rev);
    variable v_now_active  : boolean;
    variable v_exp_z       : std_logic;
    variable v_count       : natural := 0;
    variable v_ok          : boolean := true;
    variable v_event       : t_enc_event;
  begin
    for i in 0 to event_log.count(id) - 1 loop
      v_event := event_log.get(id, i);
      if v_event.a_changed or v_event.b_changed then
        v_new_gray := gray_index(v_event.a, v_event.b);
        if (v_new_gray - v_gray) mod C_EDGES_PER_CYCLE = 1 then
          v_position := v_position + 1;
        elsif (v_new_gray - v_gray) mod C_EDGES_PER_CYCLE = C_EDGES_PER_CYCLE - 1 then
          v_position := v_position - 1;
        elsif v_ok then
          alert(ERROR, "encoder " & to_string(id) & ": entry " & to_string(i) & " at " & to_string(v_event.time_stamp, ns) &
                       " is not one legal edge: " & msg, scope);
          v_ok := false;
        end if;
        v_gray := v_new_gray;
      end if;
      v_now_active := tb_index_active(v_position, zero_state, index_state, index_width, index_position, cycles_per_rev);
      if v_now_active and not v_active then
        v_count := v_count + 1;
      end if;
      v_active := v_now_active;
      if v_active xor index_inverted then
        v_exp_z := '1';
      else
        v_exp_z := '0';
      end if;
      if v_ok and v_event.z /= v_exp_z then
        alert(ERROR, "encoder " & to_string(id) & ": Z " & to_string(v_event.z) & " at position " & to_string(v_position) &
                     " (entry " & to_string(i) & ", " & to_string(v_event.time_stamp, ns) & "), expected " & to_string(v_exp_z) &
                     ": " & msg, scope);
        v_ok := false;
      end if;
    end loop;
    activations := v_count;
    if v_ok then
      log(ID_SEQUENCER_SUB, "encoder " & to_string(id) & ": Z follows A/B in " & to_string(event_log.count(id)) & " entries, " &
                            to_string(v_count) & " index activations, end position " & to_string(v_position) & ". '" & msg & "'",
          scope);
    end if;
  end procedure;

  procedure compare_logs(
    variable event_log : inout t_event_log;
    constant id_ref    : in    positive;
    constant t_ref     : in    time;
    constant id_cmp    : in    positive;
    constant t_cmp     : in    time;
    constant invert_z  : in    boolean;
    variable match     : out   boolean) is
    variable v_ref : t_enc_event;
    variable v_cmp : t_enc_event;
    variable v_z   : std_logic;
  begin
    match := event_log.count(id_ref) = event_log.count(id_cmp) and event_log.count(id_ref) > 0;
    if event_log.count(id_ref) /= event_log.count(id_cmp) then
      return;
    end if;
    for i in 0 to event_log.count(id_ref) - 1 loop
      v_ref := event_log.get(id_ref, i);
      v_cmp := event_log.get(id_cmp, i);
      if invert_z then
        v_z := not v_ref.z;
      else
        v_z := v_ref.z;
      end if;
      if v_cmp.time_stamp - t_cmp /= v_ref.time_stamp - t_ref or v_cmp.a /= v_ref.a or v_cmp.b /= v_ref.b or v_cmp.z /= v_z or
         v_cmp.a_changed /= v_ref.a_changed or v_cmp.b_changed /= v_ref.b_changed or v_cmp.z_changed /= v_ref.z_changed then
        match := false;
        return;
      end if;
    end loop;
  end procedure;

  procedure check_bounce(
    variable event_log        : inout t_event_log;
    constant id               : in    positive;
    constant t_start          : in    time;
    constant num_edges        : in    positive;
    constant time_per_edge    : in    time;
    constant num_toggles      : in    natural;
    constant window           : in    time;
    constant msg              : in    string;
    constant scope            : in    string := C_TB_SCOPE_DEFAULT;
    constant jitter_amplitude : in    time   := 0 ns) is
    variable v_idx       : natural := 0;
    variable v_edge_t    : time;
    variable v_first     : t_enc_event;
    variable v_event     : t_enc_event;
    variable v_count     : natural;
    variable v_dev       : time;
    variable v_tolerance : time    := 0 ns; -- Edge time time_tolerance: exact without jitter
    variable v_earlier   : boolean := false;
    variable v_later     : boolean := false;
    variable v_ok        : boolean := true;

    procedure fail(
      constant reason : in string) is
    begin
      if v_ok then
        alert(ERROR, "encoder " & to_string(id) & ": " & reason & ": " & msg, scope);
      end if;
      v_ok := false;
    end procedure;
  begin
    if jitter_amplitude > 0 ns then
      v_tolerance := jitter_amplitude + C_RESOLUTION;
    end if;
    for k in 1 to num_edges loop
      v_edge_t := t_start + (2 * k - 1) * time_per_edge / 2;
      if v_idx >= event_log.count(id) then
        fail("edge " & to_string(k) & " missing");
        exit;
      end if;
      v_first := event_log.get(id, v_idx);
      v_dev   := v_first.time_stamp - v_edge_t;
      if abs(v_dev) > v_tolerance or v_first.a_changed = v_first.b_changed then
        fail("edge " & to_string(k) & ": first entry at " & to_string(v_first.time_stamp, ns) & ", expected one channel at " &
             to_string(v_edge_t, ns) & " +-" & to_string(v_tolerance, ns));
      end if;
      v_earlier := v_earlier or v_dev < 0 ns;
      v_later   := v_later or v_dev > 0 ns;
      v_count   := 0;
      v_event   := v_first;
      while v_idx < event_log.count(id) loop
        v_event := event_log.get(id, v_idx);
        exit when v_event.time_stamp >= v_edge_t + time_per_edge - v_tolerance; -- Earliest time of the next edge
        if v_event.a_changed /= v_first.a_changed or v_event.b_changed /= v_first.b_changed then
          fail("edge " & to_string(k) & ": entry at " & to_string(v_event.time_stamp, ns) & " on the other channel");
        elsif v_event.time_stamp > v_first.time_stamp + window then
          fail("edge " & to_string(k) & ": toggle at " & to_string(v_event.time_stamp, ns) & " after the bounce window");
        end if;
        v_count := v_count + 1;
        v_idx   := v_idx + 1;
      end loop;
      if v_count = 0 then
        fail("edge " & to_string(k) & ": no entry before the next edge");
        exit;
      end if;
      v_event := event_log.get(id, v_idx - 1);
      if v_count /= 1 + num_toggles then
        fail("edge " & to_string(k) & ": " & to_string(v_count) & " events, expected " & to_string(1 + num_toggles));
      elsif v_event.a /= v_first.a or v_event.b /= v_first.b then
        fail("edge " & to_string(k) & ": not settled at the level of the edge");
      end if;
    end loop;
    if jitter_amplitude > 0 ns and not (v_earlier and v_later) then
      fail("edges not displaced in both directions, jitter has no effect");
    end if;
    if v_ok then
      log(ID_SEQUENCER_SUB, "encoder " & to_string(id) & ": " & to_string(num_edges) & " edges with " & to_string(num_toggles) &
                            " bounce toggles each within " & to_string(window, ns) & " after the edge, jitter amplitude " &
                            to_string(jitter_amplitude, ns) & ". '" & msg & "'", scope);
    end if;
  end procedure;

  procedure check_settled_before_edges(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant t_start        : in    time;
    constant num_edges      : in    positive;
    constant time_per_edge  : in    time;
    constant zero_state     : in    std_logic_vector(1 downto 0);
    constant start_position : in    integer;
    constant direction_sign : in    integer;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT) is
    variable v_idx    : integer := -1;
    variable v_edge_t : time;
    variable v_event  : t_enc_event;
    variable v_before : std_logic_vector(1 downto 0);
    variable v_ok     : boolean := true;
  begin
    for k in 1 to num_edges loop
      v_edge_t := t_start + (2 * k - 1) * time_per_edge / 2;
      while v_idx + 1 < event_log.count(id) and event_log.get(id, v_idx + 1).time_stamp <= v_edge_t loop
        v_idx := v_idx + 1;
      end loop;
      if v_idx < 0 then
        alert(ERROR, "encoder " & to_string(id) & ": no entry at edge " & to_string(k) & ": " & msg, scope);
        return;
      end if;
      v_event := event_log.get(id, v_idx);
      if v_idx = 0 then
        v_before := tb_state(zero_state, start_position);
      else
        v_before := event_log.get(id, v_idx - 1).a & event_log.get(id, v_idx - 1).b;
      end if;
      if v_event.time_stamp /= v_edge_t or
         std_logic_vector'(v_event.a & v_event.b) /= tb_state(zero_state, start_position + direction_sign * k) or
         v_before /= tb_state(zero_state, start_position + direction_sign * (k - 1)) then
        alert(ERROR, "encoder " & to_string(id) & ": edge " & to_string(k) & " at " & to_string(v_edge_t, ns) & ": last entry " &
                     to_string(v_event.time_stamp, ns) & " AB " & to_string(std_logic_vector'(v_event.a & v_event.b)) & ", before it " &
                     to_string(v_before) & "; expected " & to_string(tb_state(zero_state, start_position + direction_sign * (k - 1))) &
                     " -> " & to_string(tb_state(zero_state, start_position + direction_sign * k)) & ": " & msg, scope);
        v_ok := false;
        exit;
      end if;
    end loop;
    if v_ok then
      log(ID_SEQUENCER_SUB, "encoder " & to_string(id) & ": " & to_string(num_edges) & " edges, each from a settled state. '" &
                            msg & "'", scope);
    end if;
  end procedure;

  -- t in ns as real, without converting large times to integer resolution units (|t| < 2**31 ns)
  function to_ns_real(
    constant t : in time) return real is
    constant C_WHOLE : integer := t / 1 ns;
  begin
    return real(C_WHOLE) + real((t - C_WHOLE * 1 ns) / C_RESOLUTION) / real(1 ns / C_RESOLUTION);
  end function;

  procedure check_jitter_stats(
    variable event_log      : inout t_event_log;
    constant id             : in    positive;
    constant first_idx      : in    natural;
    constant expected       : in    time_vector;
    constant amplitude      : in    time;
    constant time_tolerance : in    time;
    constant msg            : in    string;
    constant scope          : in    string := C_TB_SCOPE_DEFAULT) is
    variable v_event : t_enc_event;
    variable v_dev   : time;
    variable v_max   : time    := -amplitude;
    variable v_min   : time    := amplitude;
    variable v_sum   : real    := 0.0;
    variable v_mean  : real;
    variable v_ok    : boolean := true;
  begin
    if event_log.count(id) < first_idx + expected'length then
      alert(ERROR, "encoder " & to_string(id) & ": " & to_string(event_log.count(id) - first_idx) & " events logged, " &
                   to_string(expected'length) & " edges expected: " & msg, scope);
      return;
    end if;
    for k in expected'range loop
      v_event := event_log.get(id, first_idx + k - expected'low);
      v_dev   := v_event.time_stamp - expected(k);
      if v_ok and (not (v_event.a_changed or v_event.b_changed) or abs(v_dev) > amplitude + time_tolerance) then
        alert(ERROR, "encoder " & to_string(id) & ": edge " & to_string(k) & " at " & to_string(v_event.time_stamp, ns) &
                     ", displaced by " & to_string(v_dev, ns) & ", amplitude " & to_string(amplitude, ns) & ": " & msg, scope);
        v_ok := false;
      end if;
      if v_dev > v_max then
        v_max := v_dev;
      end if;
      if v_dev < v_min then
        v_min := v_dev;
      end if;
      v_sum := v_sum + to_ns_real(v_dev);
    end loop;
    v_mean := v_sum / real(expected'length);
    check_value(v_max >= amplitude * C_JITTER_BOUND_REACHED, ERROR, "largest positive displacement " & to_string(v_max, ns) &
                " reaches " & to_string(C_JITTER_BOUND_REACHED, 2) & " x amplitude " & to_string(amplitude, ns) & ": " & msg,
                scope, ID_SEQUENCER_SUB);
    check_value(v_min <= -amplitude * C_JITTER_BOUND_REACHED, ERROR, "largest negative displacement " & to_string(v_min, ns) &
                " reaches " & to_string(C_JITTER_BOUND_REACHED, 2) & " x amplitude: " & msg, scope, ID_SEQUENCER_SUB);
    check_value(abs(v_mean) <= C_JITTER_MEAN_FRACTION * to_ns_real(amplitude), ERROR, "mean displacement " &
                to_string(v_mean, 3) & " ns within " & to_string(C_JITTER_MEAN_FRACTION, 1) & " x amplitude: " & msg, scope,
                ID_SEQUENCER_SUB);
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
