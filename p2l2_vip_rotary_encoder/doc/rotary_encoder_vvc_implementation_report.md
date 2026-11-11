# Rotary Encoder VVC – Implementation and Verification Report

| Item | Value |
|---|---|
| Revision | 0.11 (Stage 5.3 – Increment 5: VVC rotation) |
| Date | 2026-11-11 |
| Baseline | Branch `p2l2_vip_rotary_encoder`, base `90d56e93`; uvvm_util v2.21.4, uvvm_vvc_framework v2.12.15 |
| Inputs | Specification rev 0.13, design rev 0.6 (Stages 5.1/5.2 and Increments 1–2 were built against the former separate requirements, architecture and testbench architecture documents, now merged into the design) |
| Mode | One-shot (pause at Stage 5.1, Stage 5.2, each increment); development simulator NVC 1.23.0; the user commits |

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-27 | Stage 5.1 – Generate skeleton: generator run, file inventory, markers, skeleton comparison |
| 0.2 | 2026-10-27 | Stage 5.2 – First testbench and regression script: SK-1 to SK-4 and SK-7 applied, testbench files, `test.py`, NVC regression |
| 0.3 | 2026-10-27 | Stage 5.3 – Increment 1: BFM core: BFM engine, 13 BFM test cases, NVC regression 15/15 |
| 0.4 | 2026-11-09 | Section 3 rewritten for the Increment 1 rework (TD-10, architecture rev 0.6): detents removed, `zero_state`, `set_motion`, index width / pin-referred index state, move to state, centre state; 13 BFM test cases, NVC regression 14/14 |
| 0.5 | 2026-11-09 | Section 3 updated for spec rev 0.9 / arch rev 0.7 (Q-14): direction swap removed from the BFM and `move_to_state`; D-1 decided (arch rev 0.7); NVC regression 14/14 |
| 0.6 | 2026-11-09 | Section 3 updated for spec rev 0.10 / arch rev 0.8 (Q-15): A/B polarity inversion (`ab_inverted`) removed from the BFM; states are pin levels; NVC regression 14/14 |
| 0.7 | 2026-11-09 | Increment 1 approved by the user (committed as `8b333d5d`). New Section 4 – Increment 2: BFM signal options (index validation and last valid configuration, bounce with cut-off, jitter; decisions AD-22 to AD-25); 9 BFM test cases; NVC regression 23/23 |
| 0.8 | 2026-11-11 | Increment 2 approved (`a482f55a`, `27e50a52`); Increment 3 approved by the user 2026-11-11 incl. D-89 to D-94. New Section 5 – Increment 3: BFM faults, timed rotation, ramp (edge offsets, stuck outputs, set angle, jump, glitch, rotation engine with profiles, `rotary_encoder_rotate`, `rotary_encoder_linear_ramp`); 7 BFM test cases; NVC regression 31/31. Section 4 statements about edge offsets updated |
| 0.9 | 2026-11-11 | Increment 3: unused `last_rpm` removed; new test case `linear_ramp_rotation` (user request); NVC regression 32/32 |
| 0.10 | 2026-11-11 | Increment 3 committed by the user (`3e4a08cf`). Glitch removed (D-100), Sections 5 and 6 updated; transaction info with the command's effect (D-98). New Section 6 – Increment 4: VVC commands (`p_motion`, executor handshake, moves, centre state, fault events, status read, terminate, transaction info, logging); 6 VVC test cases replace the Stage 5.2 placeholder; NVC regression 36/36 |
| 0.11 | 2026-11-11 | Increment 4 committed by the user (`842f9876`). New Section 7 – Increment 5: VVC rotation (start, speed change, stop, profiles, rejects, terminate/flush, configuration after every edge; D-101 to D-106); 13 VVC test cases (11 new, rotation parts of 2); NVC regression 50/50. Section 6.3 rotation parts and 6.6 updated |

## 1. Stage 5.1 – Generate skeleton

### 1.1 Generator run

- Script: `uvvm_vvc_framework/script/vvc_generator/vvc_generator.py` (prompt order checked in `main()`, `get_generating_level()`, `get_number_of_channels()`; it matches design 4.10).
- Run in an empty scratch directory with piped answers: `printf 'rotary_encoder\ny\nn\ny\nn\n\nn\n' | python3 …/vvc_generator.py`
  (name, extended features y, scoreboard n, transaction info y, UAD n, channels Enter = 1, multiple executors n).
- Result: exit 0, "The vvc_generator script is now finished", 6 files in `output/`. **PASS**

### 1.2 File inventory

| File | Source | Changes applied in Stage 5.1 |
|---|---|---|
| `src/rotary_encoder_bfm_pkg.vhd` | Generator | UVVM header (`Copyright 2026 UVVM`, AD-3) instead of the generator banner |
| `src/rotary_encoder_vvc.vhd` | Generator | Header |
| `src/transaction_pkg.vhd` | Generator (transaction info) | Header |
| `src/vvc_cmd_pkg.vhd` | Generator | Header |
| `src/vvc_methods_pkg.vhd` | Generator | Header |
| `src/vvc_context.vhd` | Generator | Header; `library vip_rotary_encoder` → `p2l2_vip_rotary_encoder` (AD-2) |
| `script/compile_src.do` | `bitvis_vip_gpio` | Year 2026; dependency line "3. Bitvis VIP Scoreboard" removed (no scoreboard; same as PWM) |
| `script/compile_bfm.do` | `bitvis_vip_gpio` | Year 2026; `lib_name p2l2_vip_rotary_encoder`; `rotary_encoder_bfm_pkg.vhd` |
| `script/compile_order.txt` | `bitvis_vip_gpio` | Library and file names; `vvc_sb_pkg.vhd` removed (no scoreboard) |
| `script/README.txt` | `bitvis_vip_gpio` | Unchanged copy |
| `LICENSE.TXT`, `.gitignore` | `bitvis_vip_gpio` | Unchanged copies |
| `README.TXT` | `bitvis_vip_gpio` layout | Names, directory description and one-paragraph VIP description |
| `CHANGES.TXT` | PWM layout | v1.0.0 "not yet released (in development)" |
| `VERSION.TXT` | `bitvis_vip_gpio` layout | `1.0.0` |
| `uvvm_util/src/adaptations_pkg.vhd` (S-1, shared) | – | Block `-- ROTARY ENCODER` after RGMII, before SBI: `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH := 256`, `C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH`, `C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM` (RGMII layout: size constant first) |

Not yet created (per plan): `tb/maintenance_tb/*` and `script/maintenance_script/test.py` (Stage 5.2; the directories exist and are empty).

### 1.3 `USER_INPUT` markers (28)

| File | Lines | What | Resolved in |
|---|---|---|---|
| `rotary_encoder_bfm_pkg.vhd` | 35 | Interface signals (`t_rotary_encoder_if`) | Inc 1 |
| | 48, 50–52, 60, 62–64 | Config record fields, message IDs, defaults | Inc 1 (all fields), Inc 2/3 (options, faults) |
| | 73, 80 | Procedure declarations and bodies | Inc 1–3 |
| `rotary_encoder_vvc.vhd` | 40 | Interface generics (none needed: remove example lines) | 5.1 skeleton decision SK-3 |
| | 54 | Port | SK-3 |
| | 235 | `v_cmd_is_bfm_access` operation check | Inc 4 |
| | 263 | BFM calls in the executor | Inc 4/5 |
| | 316 | `insert_delay` clock cycles | SK-5 |
| `vvc_methods_pkg.vhd` | 105, 164 | VVC method declarations and bodies | Inc 4/5 |
| | 237, 264, 283 | Transaction-info/operation mappings (`to_string`, `set_global_vvc_transaction_info`, …) | Inc 4 |
| `transaction_pkg.vhd` | 44 | `t_operation` literals | Inc 4/5 |
| | 49 | Size constants | SK-4 |
| | 82, 91 | Transaction info fields | Inc 4 |
| `vvc_cmd_pkg.vhd` | 41, 66 | Command record fields and defaults | Inc 4/5 |
| | 146 | Result record fields | Inc 4 (`t_rotary_encoder_status`) |

Markers stay until their content is implemented; the audit checks that none remain.

### 1.4 Skeleton comparison (generator vs. architecture and references)

References: `p2l2_vip_pwm` (primary structure), `bitvis_vip_gpio` (scripts, file layout). `vvc_context.vhd` is identical to GPIO's apart from names. `vvc_cmd_pkg.vhd` and `transaction_pkg.vhd` differ from GPIO only in the `USER_INPUT` areas and in formatting.

| ID | Generator output | Architecture / reference | Proposed resolution | When |
|---|---|---|---|---|
| SK-1 | Port `clk : in std_logic` always present | Arch §5: no clock, no reset (PWM has none) | Remove the port; remove the commented `clk =>` lines in the executor | Stage 5.2 (before the first harness compile) |
| SK-2 | `GC_INSTANCE_IDX : natural` without default | Arch §5 and PWM: `:= 1` | Add `:= 1` (known pitfall F-004 of the PWM run) | Stage 5.2 |
| SK-3 | Port `rotary_encoder_vvc_if` commented out, with `GC_ADDR_WIDTH`/`GC_DATA_WIDTH` example generics | Arch §5: `rotary_encoder_vvc_if : inout t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID)`, no width generics | Follow the architecture; delete the example generics | Stage 5.2 (record type) / Inc 1 |
| SK-4 | `transaction_pkg` defines local constants `C_VVC_CMD_DATA_MAX_LENGTH := 32`, `C_VVC_CMD_STRING_MAX_LENGTH := 300`, `C_VVC_MAX_INSTANCE_NUM` | GPIO/PWM alias `C_<NAME>_VVC_*` from `adaptations_pkg` (design 4.1) | Alias `C_VVC_CMD_STRING_MAX_LENGTH`, `C_VVC_MAX_INSTANCE_NUM`, `C_VVC_CMD_PROFILE_MAX_LENGTH` to the S-1 constants; drop the data/address constants (no data bus) | Stage 5.2 |
| SK-5 | `insert_delay` clock-cycle branch commented out, expects `bfm_config.clock_period` | Arch §4 and PWM: clock cycles → `TB_ERROR` (no clock) | Follow PWM | Inc 4 |
| SK-6 | Only `p_cmd_interpreter` and `p_cmd_executor` | Arch §7.1: hand-written `p_motion` (sole port driver), `halt_req` from the interpreter (F-004) | Add per architecture | Inc 4/5 |
| SK-7 | BFM config has `id_for_bfm` only; `id_for_bfm_wait`/`id_for_bfm_poll` commented | Arch §2.2/§6.7: `id_for_bfm` and `id_for_bfm_wait` | Follow the architecture; delete `id_for_bfm_poll` | Inc 1 |
| SK-8 | `t_vvc_config` with the standard fields only | Arch §2.2: extra field `stop_when_idle_severity` (REQ-106) | Add | Inc 5 |
| SK-9 | Section separators `--====` 90 columns wide; official files use 120 | Official VIPs (GPIO) | Keep for now. VSG in Stage 5.4 settles formatting; separators are adjusted to the official width then if VSG does not | Stage 5.4 |
| SK-10 | Transaction info calls in the executor commented out | Arch §7.5: base transaction only | Implement | Inc 4 |

No generator choice is kept against the architecture. SK-1 to SK-4 change only the entity/package interfaces and are done at the start of Stage 5.2 so that the first harness compiles against the final entity.

### 1.5 Checks

| Check | Result |
|---|---|
| Generator exit code and output files | PASS |
| Library name: no `vip_rotary_encoder` without prefix left (`grep`) | PASS |
| Generator banner replaced in all 6 sources (`grep "generated with"` finds nothing) | PASS |
| Compile of the skeleton | NOT RUN (Stage 5.2 compiles after SK-1 to SK-4) |

Approved by the user 2026-10-27 (committed by the user as `7f22761b`).

## 2. Stage 5.2 – First testbench and regression script

### 2.1 Source changes

| File | Change | Ref |
|---|---|---|
| `src/rotary_encoder_vvc.vhd` | `clk` port removed; port `rotary_encoder_vvc_if : inout t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID)`; example width generics removed; `GC_INSTANCE_IDX := 1` | SK-1, SK-2, SK-3 |
| `src/transaction_pkg.vhd` | Local size constants replaced by aliases of `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH`, `…_CMD_STRING_MAX_LENGTH`, `…_MAX_INSTANCE_NUM` (`adaptations_pkg`) | SK-4 |
| `src/rotary_encoder_bfm_pkg.vhd` | Declarations from design 5.1: `t_rotary_encoder_if`, the five enumeration types, the full `t_rotary_encoder_bfm_config` with `C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT` (incl. `id_for_bfm_wait`), `t_rotary_encoder_status`, `init_rotary_encoder_if_signals` (all `'Z'`); `C_BFM_SCOPE = "ROTARY ENCODER BFM"` (generator: underscore, design 4.1: space) | SK-3, SK-7 (brought forward from Inc 1: harness instance 3 needs `start_angle`) |
| `src/vvc_cmd_pkg.vhd` | `t_vvc_result` is `t_rotary_encoder_status` (generator: `std_logic_vector` of the removed data constant), `to_string(t_vvc_result)`; `use work.rotary_encoder_bfm_pkg.all` (PWM pattern) | Consequence of SK-4, design 4.6.2 |

Remaining `USER_INPUT` markers: 15 (procedures, commands, transaction info, executor), all planned for Inc 1–5.

### 2.2 Testbench and regression script

| File | Content |
|---|---|
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | `t_enc_event`, protected `t_event_log` (dynamic per-id storage, decoder checker: Gray position, edges, illegal transitions, invalid levels, Z events; `arm`, `clear`), `gray_index`, `ideal_edge_time` (design 7.3, long division, E-1.2), `check_checker`, `check_no_event`; package `rotary_encoder_th_pkg` with `shared_th_event_log` |
| `tb/maintenance_tb/rotary_encoder_th.vhd` | `ti_uvvm_engine`, three VVC instances (3: `start_angle => 30.0`), signals `enc1_if` to `enc3_if`, one logger per interface, checker armed at the first event |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | Sequencer, `GC_TESTCASE`, placeholder **`testbench_self_test`, `vvc_instances_execute_commands`**: `insert_delay`/`await_completion` on all three instances; event logs empty (no driver yet) |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Sequencer with own `enc_if` and logger (id 1), **`testbench_self_test`, `vvc_instances_execute_commands`** testbench self-test: Gray index, checker on hand-driven forward/reverse/illegal/invalid/Z sequences, zero-length state (two entries at one time), `check_no_event` positive and negative, `ideal_edge_time` against 7 exact values (ps and fs branch) |
| `script/maintenance_script/test.py` | Copy of `bitvis_vip_gpio`'s, exactly the four edits of design 7.5 (print text, library name ×3 and comment, scoreboard line removed, comment) |

Decided by the user 2026-10-27: `testbench_self_test` stays permanently as the testbench self-test; `vvc_instances_execute_commands` is a placeholder, replaced by `power_up_state`, `vvc_power_up_state` in Inc 4. The declarations brought forward from Inc 1 and the `C_BFM_SCOPE` correction are accepted. `GC_INSTANCE_IDX := 1` (SK-2) follows design 4.4; the official VVCs are split (11 with default, e.g. `clock_generator`, `spi`, `uart`; 12 without, e.g. `gpio`, `axistream`).

Remaining check procedures of design 7.3 (`check_event_times`, `check_edge_sequence`, `check_z_follows_ab`, `save_events`/`compare_inverted`, `check_constant_spacing`, `check_jitter_stats`, `check_rejected`) are added with the increments that first need them.

### 2.3 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression (2 tests: `rotary_encoder_bfm_tb.`testbench_self_test`, `vvc_instances_execute_commands`, `rotary_encoder_vvc_tb.`testbench_self_test`, `vvc_instances_execute_commands`) | NVC 1.23.0 (resolution 1 fs) | `cd p2l2_vip_rotary_encoder/sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (2 passing, exit 0) | `doc/evidence/stage5_2/regression_nvc_verbose.log` |
| `ideal_edge_time` self-test, fs branch | NVC | (in `testbench_self_test`, `vvc_instances_execute_commands`) | PASS, 7 of 7 values exact | same log |
| `ideal_edge_time` self-test, ps branch | Questa | – | NOT RUN (Stage 5.4) | – |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |

First run failed (F-007, testbench error, fixed).

Approved by the user 2026-10-27 (committed by the user as `1418078c`).

## 3. Stage 5.3 – Increment 1: BFM core

Implemented first on 2026-10-27 against architecture rev 0.4 (detents), not approved. Reworked in place on 2026-11-09 for architecture rev 0.6 (TD-10). Updated the same day for spec rev 0.9 / arch rev 0.7 (direction swap removed, Q-14) and spec rev 0.10 / arch rev 0.8 (A/B polarity inversion removed, Q-15). This section describes the current state; the 2026-10-27 evidence is kept in `doc/evidence/inc1/stale_2026-10-27/`.

### 3.1 Source changes

| File | Change |
|---|---|
| `src/rotary_encoder_bfm_pkg.vhd` | Types: `t_rotary_encoder_motion_kind` = (`MOTION_EDGES`, `MOTION_ANGLE`, `MOTION_TO_STATE`, `MOTION_ROTATION`), `_speed_form`, `_motion_event`, `t_rotary_encoder_motion` (with `target_state`), `C_ROTARY_ENCODER_MOTION_DEFAULT`, `t_rotary_encoder_state` (private fields, E-1.1). Config as design 4.5.7: `zero_state`, `index_width`, `index_state` (all states are pin levels); `direction_swap`, `ab_inverted`, detent fields, `default_snap_rpm`, `off_detent_severity` and `t_rotary_encoder_index_mode` removed. Public: conversions (4), `rotary_encoder_get_status`, `rotary_encoder_init`, `rotary_encoder_move_edges`/`_move_angle`/`_move_to_state` (rpm and time overloads), `rotary_encoder_center_state`, engine `rotary_encoder_set_motion`/`_run_motion`/`_halt_motion` ("Used by the VVC."). `rotary_encoder_move_detents` removed. Body-only (DV-1): integer angle model (K = 9·10⁸ quanta/edge), segment timing from the anchor (design 4.5.2), Gray mapping, zero-state check (`is_call_valid`), index decision (design 4.5.4), move-to-state resolution, output mapping, `floor_big`/`round_big`/`units_to_time`/`time_to_units` (pitfall F-042), `real_image` (F-011) |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Detent constants, helpers and TC_020…022 removed; `power_up_state`, `vvc_power_up_state`, , , ,  rewritten; `move_to_state`, `center_state` new; helpers `move_to_state`, `center`, `check_power_up`, `check_forward_cycle`, `check_zero_time_no_event` |
| `tb/maintenance_tb/rotary_encoder_th.vhd` | Instance 3 generic: 30° with zero state `00` (design 7.2; used by `vvc_power_up_state` in Inc 4) |

**Engine.** `rotary_encoder_set_motion` (renamed from `start_motion`) validates in this order: state initialized, `zero_state` equal to the one kept at init (D-32), `cycles_per_rev`, speed, kind-specific parameters (angle; `occurrence` ≥ 1 and a 2-bit `target_state` for `MOTION_TO_STATE`), length ≤ 2⁵³ quanta. Only then does it end a running motion at the current angle, latch the geometry and anchor the segment; a rejected call changes nothing. `MOTION_TO_STATE` is resolved there from the angle at `now` (AD-19): the first matching position k₁ ∈ 1…4 in the move direction (the current state is never counted), then k₁ + 4 × (`occurrence` − 1), since every 4 consecutive positions contain each state once. This is the closed form of the "at most 4 × `occurrence` steps" search in design 4.5.5 and needs no loop over large occurrences. The distance is k × K − dir × offset quanta. A stop is `rotary_encoder_halt_motion` only (AD-18); there is no snap.

**Centre state.** Checks the state and the zero state, sets the sub-edge offset to 0, logs; no output is driven, no time passes. Because a move that ends on a boundary already counts as being in the state it moved into (AD-7), the boundary cases of REQ-097 follow without a special case.

**Index (design 4.5.4).** *q* = the position in `index_position` … +3 whose state is `index_state`; Z active at *q* … *q* + `index_width` − 1, modulo 4 × `cycles_per_rev`. An invalid index configuration (width outside 1–4, non-'0'/'1' index state) currently gives an inactive Z without an alert; its `TB_ERROR` and "keep the last valid configuration" (REQ-045, D-31) are Inc 2.

No magic numbers (user rule): the BFM names its physical constants and arithmetic limits; the testbench derives the geometry from the default configuration (`C_CPR`, `C_EDGES_PER_REV`, `C_DEG_PER_EDGE`) and lists the requirement test vectors as named constants or tables with their REQ (`C_START_CASES`, `C_STATES`/`C_Z_AT_ZERO`, `C_TO_STATE_CASES`, `C_ANGLE_10`, `C_ANGLE_1`, `C_BOUNDARY_ANGLE`, `C_EDGE_OFFSET`). Literals left on purpose: the specified config defaults (design 4.5.7), the hand-computed table values, the REQ-095 values in `speed_conversion` and the reference values of `testbench_self_test`, `vvc_instances_execute_commands`.

Implemented ahead of their increment (needed by `drive_outputs` or the VVC; tested in the planned increment): Z polarity, index decision (`index_polarity`, `index_once_per_revolution`, `index_width_and_state` in Inc 2; REQ-002/006 need Z at power-up now); `rotary_encoder_run_motion` and `rotary_encoder_halt_motion` (Inc 4 with `p_motion`).

Not implemented in Increment 1: `MOTION_ROTATION` (`set_motion` rejects it with `TB_ERROR` "not supported yet" until Inc 3/5); index validation, bounce, jitter (Inc 2, Section 4); edge offsets, stuck outputs, fault events, `rotary_encoder_rotate`, `rotary_encoder_linear_ramp` (Inc 3). Remaining `USER_INPUT` markers in the BFM: none; in the VVC files: 13 (Inc 4/5).

Approved by the user 2026-11-09 (committed by the user as `8b333d5d`).

Expected decisions: E-1.1 – the state fields are declared in the package with the comment "All fields are private" (VHDL needs the full record). E-1.2 – done in Stage 5.2. E-1.3 – the motion record uses `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` from `adaptations_pkg` directly. E-1.4 – `rotary_encoder_center_state` has `config` and checks the zero state; no other Inc 1 procedure lacked it. D-1 (Section 3.5) decided by the user and folded into arch rev 0.7 §6.6.

### 3.2 Tests (`rotary_encoder_bfm_tb`)

| TC | Content |
|---|---|
| `power_up_state`, `vvc_power_up_state` | Power-up at 0°, −10°, 30°, 400° (AB/Z in the first delta, status, no event for 1 µs); the four zero states at 0° (AB = zero state, Z only for `11`), each followed by one forward cycle checked state by state and ending in the zero state; invalid zero state `0X` at init; `0X` and changed `00` at the next edge move and centre state: one `TB_ERROR` each, no time, no event; the kept zero state still moves |
| `move_edges_forward_and_reverse` | N ∈ {1…5, 1000} forward and reverse from all 4 states; checker position, edge count, status |
| `edge_timing` | Time form 10 edges at 1 ns/1 µs/1 ms (exact); 3+2+2 back to back (exact); 1000 edges at 7 and 6000 rpm (each edge within one step of the exact floor); speed curves |
| `direction_reversal` | ±1 ×10 from each state; +5 −3 +7 −10 with continuous timing |
| `zero_edge_move` | 0 edges (time and rpm form) and 0°: no event, no time |
| `invalid_speed` | 6 invalid speeds: one `TB_ERROR` each, no time, no event |
| `move_angle` | Three 1° moves: one edge at 2.25 µs; 10° from 0°: edges at 2.25/6.75 µs, 10 µs, ends at 10° (forward and reverse); 10° and 1° at 60 rpm within one step; 1° without an edge in the time form |
| `move_angle_without_drift` | 360 × 1°, 3600 × 0.1°, 40 × (1 edge + 4.5°): 80 edges, status angle exactly 360.0; 2° + 1 edge + 1° |
| `invalid_angle_and_move_to_state` | Invalid angles (−1.0, `real'high`, rpm form); invalid move to state (occurrence 0, target `0X`, 0 ns, −60 rpm); status position, angle, AB unchanged |
| `speed_conversion` | Conversions and 5 invalid calls |
| `move_to_state` | All 6 BFM cases of REQ-096 at T = 1 µs: duration and every edge time within one step of (distance / edge angle) × T, edge count, checker direction, status position and angle |
| `center_state` | REQ-097: from 10° → 9°, twice (second unchanged); forward move ending on 6.75° → 9°, reverse → 4.5°; offsets ±44° from 1° and 3.5°; from 1°, centre, then 1 edge at exactly 0.5 × `time_per_edge`. Each centre call: zero time, no new event |

`center_state` note: the ±44° offset step runs and passes, but edge offsets are only implemented in Inc 3 (REQ-075). Until then it shows only that centring drives nothing; it covers displaced boundaries from Inc 3 on without a change.

Debug signals `dbg_position`/`dbg_angle` (user request 2026-10-27) are updated by the move helpers and `center`; no check uses them.

Every test also checks the decoder checker (illegal transitions 0, invalid levels 0) after each step: REQ-001 and REQ-070 for all non-error tests. `edge_timing`, `move_angle` and `move_to_state` each declare one expected `TB_WARNING` (UVVM time-stamp truncation, raised once per simulation).

### 3.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-001 | Yes (drive logic: only '0'/'1') | PASS | checker in every TC |
| REQ-002 | Yes (BFM init; VVC power-up Inc 4) | PASS (BFM) | `power_up_state`, `vvc_power_up_state` |
| REQ-004 | Yes | PASS (BFM) | `direction_reversal` |
| REQ-006 | Yes (init, `is_call_valid`; VVC check Inc 4) | PASS (BFM) | `power_up_state`, `vvc_power_up_state` |
| REQ-010, 011 | Yes | PASS | `move_edges_forward_and_reverse` |
| REQ-012, 013 | Yes | PASS | `edge_timing`, `direction_reversal` |
| REQ-014 | Yes | PASS | `direction_reversal` |
| REQ-015 | Yes | PASS | `zero_edge_move` |
| REQ-016 | Yes | PASS | `invalid_speed` |
| REQ-070 | Yes | PASS (Inc 1 scope) | checker in every TC |
| REQ-090, 092 | Yes | PASS | `move_angle` |
| REQ-091, 093 | Yes | PASS | `move_angle_without_drift` |
| REQ-094 | Yes | PASS | `invalid_angle_and_move_to_state` |
| REQ-095 | Yes | PASS | `speed_conversion` |
| REQ-096 | Yes (BFM; VVC case Inc 4) | PASS (BFM) | `move_to_state` |
| REQ-097 | Yes | PASS (offset part only meaningful from Inc 3) | `center_state` |
| REQ-098 | Yes | PASS | `invalid_angle_and_move_to_state` |

REQ-002, 004, 006 and 096 are verified for the BFM; their VVC part is verified in Inc 4.

### 3.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 14 tests (`testbench_self_test`, `power_up_state`, `move_edges_forward_and_reverse`, `edge_timing`, `direction_reversal`, `zero_edge_move`, `invalid_speed`, `move_angle`, `move_angle_without_drift`, `invalid_angle_and_move_to_state`, `speed_conversion`, `move_to_state`, `center_state`; `vvc_instances_execute_commands`) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (14 passing; expected TB_WARNING 1 in `edge_timing`, `move_angle`, `move_to_state`, none else) | `doc/evidence/inc1/regression_nvc_verbose.log` |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |

Rework runs: run 1 – 13 of 14 passed, `center_state` failed; run 2 – the same, one delta later; run 3 – 14/14; run 4 after the swap removal – 14/14; run 5 after the A/B inversion removal – 14/14 (the evidence log). Both `center_state` failures were testbench errors (finding F-015). The first implementation's runs (F-010, F-011, F-013) are in the findings log.

Known limitation: for a non-integer divisor (|rpm| × 4 × `cycles_per_rev` not an integer) `tpe_frac` still comes from the `real` value. The error is about n × 10⁻¹⁶ of `time_per_edge` (0.1 fs per 10⁶ edges at 7 rpm). REQ-012 tests integer rpm only.

### 3.5 Decision taken during the increment

**D-1 – `rotary_encoder_center_state` while a motion is active** (decided by the user 2026-11-09, arch rev 0.7 §6.6). The architecture rev 0.6 did not say. Only the low-level engine can have an active motion between calls (the user-level procedures run to the end), and the VVC rejects centre state during a rotation itself (REQ-105). Implemented: one `TB_ERROR`, nothing changes. Alternative: centre at the current angle and halt the motion. Decision: keep the `TB_ERROR`.

## 4. Stage 5.3 – Increment 2: BFM signal options

Implemented 2026-11-09 against architecture rev 0.9 (proposed with this increment: AD-22 to AD-25).

### 4.1 Source changes

| File | Change |
|---|---|
| `src/rotary_encoder_bfm_pkg.vhd` | State record: seeds (from `config` at init), jitter limit (latched with the geometry), drawn jitter of the next edge, pending bounce (channel, settled level, end time), cut-off reported flag, last valid / last reported invalid signal configuration. Body-only (DV-1): `jitter_limit` (half the narrowest state from the four edge offsets), `signal_config_error` (index width 1–4 and 2-bit index state when the index is enabled, `bounce_window` > 0 with bounce enabled, 0 ≤ `jitter` < limit and finite), `resolve_signal_config` (per `run_motion` call: valid → kept as last valid; invalid → one `TB_ERROR` per value, last valid used; D-31, AD-24), `schedule_bounce` (AD-22), `cut_bounce` (AD-25), jittered `next_motion_event` with the segment clamp (AD-23); `segment_time` takes the jitter as an extra `real` term, so each edge is still rounded once. `rotary_encoder_init` and every motion start validate the signal configuration (one `TB_ERROR`, nothing changes). `execute_move` and `rotary_encoder_run_motion`: before each edge, cut a pending bounce and wait one delta if the channel settles. No public declaration changed apart from the private state fields |
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | `C_DEG_ELECTRICAL_PER_EDGE`, jitter statistics constants; independent index model `tb_state`, `tb_index_active` (spec §6 text); `check_z_follows_ab` (walks the log, Z of every entry against the model), `compare_logs` (run-to-run, optionally with Z inverted), `check_bounce`, `check_settled_before_edges`, `check_jitter_stats` (bound, both bounds reached within 5 %, mean) |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Logger writes to a selectable log (`log_id`, second run into log 2); helpers `select_log`, `index_config`, `bounce_config`, `check_z_model`, `index_stimulus`, `check_accepted`, `go_to_position`, `reject_move`; named constants for every Inc 2 test vector; `index_polarity`, `index_once_per_revolution`, `index_width_and_state`, `invalid_index_configuration`, `bounce`, `bounce_placement`, `bounce_cut_off_and_invalid_window`, `jitter`, `invalid_jitter` |

**Index (REQ-045, D-31).** The index decision of Increment 1 is unchanged; what is new is the validation. A call with the index enabled and `index_width` outside 1–4 or an `index_state` that is not a 2-bit `'0'`/`'1'` value raises one `TB_ERROR` and produces no edge; with the index disabled these fields are not checked. During a motion, `rotary_encoder_run_motion` validates the configuration it is called with and keeps the last valid one otherwise, one `TB_ERROR` per invalid value. In the BFM-only flow every call validates its configuration first, so the per-call path is only reached by the VVC (TD-9: tested in `config_change_during_rotation`, Increment 5).

**Bounce (REQ-050 … 056).** At an edge with bounce enabled, `2 × bounce_pulses` toggles of the changed channel are scheduled as `transport` transactions at sorted uniform positions in the window (AD-22) or evenly spaced; a toggle that rounds onto the edge or onto the previous toggle moves one resolution step later. Z is driven only at the nominal edge, so it never bounces (D-4). Before each edge a bounce that has not ended is cut off: the settled level is driven (which deletes the remaining toggles) and `bounce_cut_severity` is raised once per command; if the channel was at its bounced level, the edge follows one delta later (AD-25, F-016).

**Jitter (REQ-060 … 063).** A uniform fraction *u* ∈ (−1, 1) is drawn once per edge from the state's seeds and kept until the edge is emitted; the edge time is the nominal one plus *u* × *j*/90 × `time_per_edge`, rounded once together with the nominal time, and clamped into the segment (AD-23, F-017). The limit is half the narrowest state from the edge offsets in the configuration (edge offsets: Section 5).

**Code rules (2026-11-10, F-023).** All test cases are named for what they test (the name is the `GC_TESTCASE` value, e.g. `bounce_with_jitter`); the comments in `src/` and `tb/` no longer refer to the workflow documents, the reason is written instead; testbench literals follow the user's rule: a literal with a comment before its first use; named constants only for values shared between test cases or with a meaning of their own (geometry derived from the default configuration, `C_Z_EVENTS_PER_PULSE`, `C_RPM_EDGE_TOL`, shared invalid values, loop vectors and case tables).

### 4.2 Tests (`rotary_encoder_bfm_tb`)

| TC | Content |
|---|---|
| `index_polarity` | Index stimulus (3 revolutions + 4 edges forward and back) without and with `index_inverted`, logged into two logs: Z at power-up per the model; every entry of the inverted run equals the plain run with Z inverted (times, A, B, flags); Z follows the model in both runs |
| `index_once_per_revolution` | Index disabled, not inverted and inverted: Z at its inactive level, no Z event over the stimulus. `cycles_per_rev` ∈ {1, 3, 24} × `index_position` ∈ {0, 5, −3} × both directions first: Z of every log entry equals the model, ≥ 3 index pulses per direction |
| `index_width_and_state` | Widths 1–4 × index state `00`/`10` × direction: Z of every entry equals the model. Literal hand values: width 2 at `00` with zero state `00`: Z at positions 0, 1 (B low), not at 2, −1. Index state `00`, width 1: Z only at position 0 with zero state `00`, only at position 2 with zero state `11` (REQ-046) |
| `invalid_index_configuration` | `cycles_per_rev` 0, width 0 and 5, index state `0X`: one `TB_ERROR` each, no time, no event; init with index state `0X` rejected; status unchanged. Index disabled with width 0 and state `0X`: accepted, 4 edges |
| `bounce` | Bounce off: 20 A/B events for 20 edges. Bounce on (random, 2 pulses, 4 µs window, 10 µs per edge), one revolution from 180° across the index: per edge the first event exactly at the nominal time, then 4 toggles on the same channel only, within the window, settled; Z exactly 2 events |
| `bounce_placement` | Even placement (3 pulses, 7 µs): toggle *i* at *i* × 1 µs ± one step after each edge. Random: the same seed twice gives identical logs, another seed a different one (100 edges each) |
| `bounce_cut_off_and_invalid_window` | `bounce_window` 0 ns and −1 ns rejected; disabled with −1 ns accepted. Cut-off with even placement, window 2 × and 3 × `time_per_edge`, two commands (6 + 4 edges): exactly one `TB_WARNING` per command (checked right after each command), every edge from a settled state (the 3× case needs the one-delta settle), no illegal transition, position +10 |
| `bounce_with_jitter` | Bounce with jitter: random placement, 2 pulses, 4 µs window, 20° jitter at 10 µs per edge, one revolution from 180° across the index: every edge within ±2.22 µs + one step of its ideal time and displaced in both directions, 4 toggles on the same channel within 4 µs after the actual edge, Z 2 events, completion exact. Same seeds twice: identical logs. Same seeds without bounce: 99 of 100 edge times differ (one random stream, AD-26). 40° jitter with a 6 µs window, 2 commands of 100 edges: one `TB_WARNING` per command (cut-off by a jittered edge), final state settled, position change 200, no illegal transition |
| `jitter` | 40° jitter, 10 000 edges at 1 µs: every displacement within ±444.4 ns + one step, largest +444.39 / −444.36 ns, mean −3.3 ns (bound 44.4 ns), 10 000 edges, duration exact. 1000 edges at 60 and 600 rpm against the exact ideal times: amplitude 5.56 ms and 0.556 ms reached within 5 %. Same seed twice: identical logs |
| `invalid_jitter` | Jitter 45°, −1°, `real'high` rejected; with B offsets +30°: 30° rejected, 29° accepted |

Every step also checks the decoder checker (no illegal transition, no invalid level, position change).

Waveform label: both testbenches write their step headers with `log_step`, which logs the header (`ID_LOG_HDR`) and copies it into the string signal `dbg_step` (`C_DBG_STEP_LENGTH` = 120 characters, padded or truncated by `dbg_text` in `rotary_encoder_tb_pkg`). The BFM testbench also shows `dbg_config` (the configuration passed to the last BFM call, set when the call starts) and `dbg_index_active` (Z before `index_inverted`, from `rotary_encoder_get_status`). `check_bounce` takes an optional jitter amplitude: the first entry of an edge may then lie within ±(amplitude + one step) of its ideal time, and the window is measured from the actual edge. `dbg_step` shows which step is running at any point in the waveform (user request 2026-11-10); no check uses it.

### 4.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-032 | Yes | PASS (BFM; rotation REQ-109 in Inc 5) | `index_polarity` |
| REQ-040, 041 | Yes | PASS | `index_once_per_revolution` |
| REQ-042, 046 | Yes | PASS | `index_width_and_state` |
| REQ-045 | Yes (call validation; per-call validation in `run_motion`) | PASS for calls; the rotation part NOT RUN (`config_change_during_rotation`, Inc 5) | `invalid_index_configuration` |
| REQ-050, 051, 052, 055 | Yes | PASS | `bounce` |
| REQ-053 | Yes | PASS | `bounce_placement` |
| REQ-054 | Yes | PASS for calls; the rotation part (rev 0.10) NOT RUN (`config_change_during_rotation`, Inc 5) | `bounce_cut_off_and_invalid_window` |
| REQ-056 | Yes | PASS | `bounce_cut_off_and_invalid_window`, `bounce_with_jitter` |
| REQ-057 | Yes (no BFM change: bounce is scheduled after the jittered edge is driven) | PASS | `bounce_with_jitter` |
| REQ-060 | Yes | PASS (`edge_timing` unchanged, jitter off) | `edge_timing` |
| REQ-061, 062 | Yes | PASS | `jitter` |
| REQ-063 | Yes (limit from the configured offsets) | PASS for calls; the rotation part (rev 0.10) NOT RUN (`config_change_during_rotation`, Inc 5) | `invalid_jitter` |

### 4.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 23 tests (`testbench_self_test`, `power_up_state`, `move_edges_forward_and_reverse`, `edge_timing`, `direction_reversal`, `zero_edge_move`, `invalid_speed`, `index_polarity`, `index_once_per_revolution`, `index_width_and_state`, `invalid_index_configuration`, `bounce`, `bounce_placement`, `bounce_cut_off_and_invalid_window`, `jitter`, `invalid_jitter`, `move_angle`, `move_angle_without_drift`, `invalid_angle_and_move_to_state`, `speed_conversion`, `move_to_state`, `center_state`; `vvc_instances_execute_commands`) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (23 passing; expected `TB_WARNING`: 4 in `bounce_cut_off_and_invalid_window` (cut-off), 1 each in `edge_timing`, `move_angle`, `move_to_state` (time-stamp truncation)) | `doc/evidence/inc2/regression_nvc_verbose.log` |
| Regression after adding `dbg_step`, 23 tests | NVC 1.23.0 (1 fs) | as above | **PASS** (23 passing) | `doc/evidence/inc2/regression_nvc_dbg_step.log` |
| Regression after adding `dbg_config`/`dbg_index_active` and `bounce_with_jitter`, 24 tests | NVC 1.23.0 (1 fs) | as above | **PASS** (24 passing; expected `TB_WARNING`: 2 in `bounce_with_jitter`) | `doc/evidence/inc2/regression_nvc_tc053.log` |
| Regression after renaming the test cases and removing document references, 24 tests | NVC 1.23.0 (1 fs) | as above | **PASS** (24 passing) | `doc/evidence/inc2/regression_nvc_named_tests.log` |
| Regression after the testbench constant review (literals with comments, constants only where shared or meaningful), 24 tests | NVC 1.23.0 (1 fs) | as above | **PASS** (24 passing) | `doc/evidence/inc2/regression_nvc_tb_literals.log` |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |

Runs: run 0 (BFM only, before the tests were added) – 14/14, Increment 1 unchanged; run 1 – 22/23, `bounce_placement` failed (testbench error, F-019); run 2 – 23/23 (the evidence log). E-2.2 (jitter test run time on Questa Starter) is measured in Stage 5.4; on NVC the whole regression takes a few seconds of wall time.

### 4.5 Decisions taken during the increment

Decided by the user 2026-11-09 and folded into architecture rev 0.9 (requirements rev 0.10, testbench architecture rev 0.6): **AD-22** (E-2.1) sorted uniform bounce draws; **AD-23** jittered edge clamped into its segment (F-017); **AD-24** invalid bounce window / jitter during a rotation as D-31, which extends REQ-054 and REQ-063 and `config_change_during_rotation`; **AD-25** cut-off settle one delta before the edge (F-016).

Decided by the user 2026-11-10 during the review of the increment: **AD-26** bounce and jitter share one random stream (documented, no API change); new REQ-057 and `bounce_with_jitter` (bounce combined with jitter).

### 4.6 Notes for later increments

- **Inc 4 (`p_motion`):** `rotary_encoder_run_motion` waits `wait on interrupt for 0 ns` between two edges at one time step and before an edge after a bounce settle (already so in Increment 1). An event on `interrupt` in that delta wakes the wait but is not reported, so `p_motion` must detect a pending request by comparing indices (`motion_req.idx` against the last one handled), not only by an event on `motion_interrupt`.
- **Inc 5:** E-5.3 (F-018) – when an edge reads the shared configuration.

## 5. Stage 5.3 – Increment 3: BFM faults, timed rotation, ramp

Implemented and approved 2026-11-11 against design rev 0.3 (decisions D-86 to D-88 by the user; D-89 to D-94 taken in one-shot mode and approved with the increment, Section 5.5). Committed by the user as `3e4a08cf`.

### 5.1 Source changes

| File | Change |
|---|---|
| `src/rotary_encoder_bfm_pkg.vhd` | **Public:** `rotary_encoder_linear_ramp`, `rotary_encoder_rotate` (signed rpm; direction + `time_per_edge`; profile with `time_per_entry` and `profile_end`), `rotary_encoder_set_angle`, `rotary_encoder_jump_edges` (`rotary_encoder_glitch` was removed in Increment 4, D-100), as in the API preview. **State record (private fields):** latched edge offsets (quanta per boundary), stuck levels last applied, segment kind (moving / bounded) and end time, profile entry and pass start. **Body-only:** `edge_offset_error`, `latch_geometry`, `upper_bound`/`lower_bound`/`settle` (state boundaries with the offsets), `output_level`/`z_level`/`apply_stuck`, `settle_bounce` (shared by `cut_bounce` and the fault events), `segment_time` with whole edges and rest separately (rotations up to 2³¹ edges from one anchor stay exact), `next_motion_event` with three outcomes (edge, segment end, none), `speed_error`/`set_speed`, `start_rotation_segment`, `start_profile_entry`, `advance_profile` (hold / stop / repeat), `halt`, `is_command_valid`, `run_to_end` (moves and timed rotation), `execute_rotation`, `place_shaft`. `rotary_encoder_run_motion` handles rotations: `MOTION_PROFILE_PASS` at the end of a pass, and it waits only for an interrupt during a rotation at 0 rpm without a profile. Removed the private state field `last_rpm`: written but never read, a leftover of the removed detent model |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Wrappers `jump`, `set_angle`, `rotate` (3), helpers `wait_for_logger` (F-025), `num_events`, `num_ab_events`, `b_offset_config`, `is_b_edge`, `check_ramp`, `check_at_rest`; status fields in `move_angle`; test cases of 5.2 |

**Edge offsets (REQ-075 … 077).** The four offsets are latched with the geometry (at init, at every motion start, at set angle and jump) as boundary offsets in quanta, indexed by the Gray index of the state below the boundary (`00→10` A rise, `10→11` B rise, `11→01` A fall, `01→00` B fall). The state at position *p* reaches from −K/2 + offset(*p*−1) to +K/2 + offset(*p*); the boundary distance, the landing point after an edge and the clamp of the current angle use these bounds. State centres are unchanged, so move ends, positions, the index and centre state are unaffected. Each offset must lie in (−45°, +45°) and be finite, else `TB_ERROR` at the call.

**Stuck outputs (REQ-078, 079).** Every edge drives the stuck level of a stuck output (`drive_outputs`), and no bounce is scheduled on it. At the start of each command `apply_stuck` drives only the outputs whose stuck setting changed (newly stuck: the stuck level; released: the level of the current state), so a running bounce on another output is not touched. A stuck Z ignores `index_inverted`. Invalid levels are part of the signal configuration check (one `TB_ERROR`, and per `run_motion` call during a VVC rotation).

**Fault events (REQ-071, 074).** `set_angle` and `jump_edges` compute the new (position, offset), resolve it into a state with the latched boundaries (on a boundary: the side of the old angle), settle a running bounce and drive the new state in one delta.

**Rotation in the engine.** A rotation is an unbounded segment; with a profile, each entry ends at `profile_t0 + (j + 1) × time_per_entry` (exact `time` arithmetic) and the next entry starts there at the current angle (rounded once). An edge due exactly at an entry end comes first. At 0 rpm a segment has no edge. A speed change during a rotation (a rotation that replaces a rotation) keeps the geometry latched at the rotation start. `rotary_encoder_rotate` runs the rotation until `now + duration` and stops there at the reached angle; with `PROFILE_STOP` it returns at the profile end.

### 5.2 Tests (`rotary_encoder_bfm_tb`)

| TC | Content |
|---|---|
| `set_angle_and_jump_edges` | Jumps of 1, 2, 3, 4 and 80 edges from each of the four states in both directions: zero time; A/B entries 1, 1, 1, 0, 0; decoded position change ±1, 0 (illegal transition), ∓1, 0, 0; status position ± N; Z per the model; one revolution gives no event at all. Jump of 2, then one revolution: Z follows the model from position 2, one index pulse. Set angle from position 5 to 0° (AB = zero state, Z active, one A/B entry, zero time) and to 30° (position 7). Set angle onto the boundary at 2.25° from 0° (position 0) and from 4.5° (position 1), no event; the same angle again: nothing. After 30°, one revolution: Z follows the model from position 7 |
| `invalid_fault_event` | Set angle `real'high` and `real'low`: one `TB_ERROR` each, no time, no event |
| `edge_offsets` | B offset +30°, 1 µs per edge, 8 edges forward from 0° and in reverse from 36°: A edges at (k − ½) µs, B edges 1/3 µs later going forward and 1/3 µs earlier in reverse (± one step), duration 8 µs. A rise +20°, A fall −20°: A high time 2 µs − 4/9 µs (± two steps). B offset +30° at 60 and 600 rpm: B edges displaced by `time_per_edge`/3 (± two steps). All four offsets at +44° and −44°: a 4-edge move ends in the zero state after exactly 4 µs. Offsets +45°, −45°, `real'high` rejected. Index stimulus with the B offset: Z changes in the same entry as the displaced A/B edges |
| `stuck_outputs` | B stuck at `'0'` (applied by a 0-edge move), 3 revolutions: no B event, 120 A events, status position 240. B released: B changes at the start of the next command to the level of the current state. Z stuck at `'Z'` from init during one revolution: Z stays `'Z'`, no Z event, every entry counted as invalid level. Z stuck at `'1'` with `index_inverted`: Z `'1'`, no Z event. Bounce with A stuck at `'1'`: no A event, B edges with 4 toggles each. `a_stuck` `'X'`, `b_stuck` `'U'`, `z_stuck` `'H'` rejected |
| `bfm_only_flow_and_rotate` | BFM-only flow: 4 edges with exact times and Z per the model, then a 10° move (position 6). `rotary_encoder_rotate`: +60 rpm for 50 ms (4 edges within one step of the ideal rpm-form times, at rest at 18°, `is_rotating` false, rpm 0.0, no edge in the following 50 ms); −120 rpm for 50 ms (8 edges back); reverse at 1 µs per edge for 2.75 µs (edges at 0.5, 1.5, 2.5 µs, at rest at −12.375°, position −3); profile (60, 120) rpm, 25 ms, `PROFILE_STOP`: edges at 6.25, 18.75, 28.125, 34.375, 40.625, 46.875 ms, returns at 50 ms at 27°; `PROFILE_HOLD` for 60 ms: then 53.125, 59.375 ms, at rest at 7.6 edge angles; `PROFILE_REPEAT` for 80 ms: then 56.25, 68.75, 78.125 ms, at rest at 8.8 edge angles; profile (0, 60): edges at 31.25, 43.75 ms; a 256-entry profile accepted; 0 rpm: no event. Rejected with one `TB_ERROR` each, no time, no event: rpm `real'high`, `time_per_edge` 0 ns, empty profile, 257 entries, `time_per_entry` 0 ns, entry `real'high`, duration 0 ns and −1 ns |
| `linear_ramp` | 0 → 3000 rpm, 4 entries: 0, 1000, 2000, 3000; −60 → 60 rpm, 3 entries: −60, 0, 60; 1 entry: the start value. 0 and −1 entries and a start of `real'high`: one `TB_ERROR` each, empty result |
| `linear_ramp_rotation` | `rotary_encoder_linear_ramp(0.0, 60.0, 61)` as the profile of `rotary_encoder_rotate`, 3 s per entry, `PROFILE_STOP`: no edge in entry 0; entry *j* has 4·*j* edges, each within one step of its exact rpm-form time from the entry start (all 7320 edges; largest deviation below the printed ns resolution); returns after 183 s, at rest at position 7320, `is_rotating` false, rpm 0.0; no illegal transition |

Also in this increment: `move_angle` checks the remaining status fields after the 10° move (`ab` = state of position 2, `index_active` false, `is_rotating` false, rpm 0.0); the ±44° step of `center_state` and the B-offset steps of `invalid_jitter` now run with displaced boundaries.

### 5.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-071 | Yes | PASS | `set_angle_and_jump_edges` |
| REQ-074 | Yes | PASS | `invalid_fault_event` |
| REQ-075, 076, 077 | Yes | PASS | `edge_offsets`, `center_state` |
| REQ-078, 079 | Yes | PASS | `stuck_outputs` |
| REQ-080 | Yes | PASS | `bfm_only_flow_and_rotate` |
| REQ-086 | BFM part: yes | PASS (BFM); VVC part: Section 6; rotation part NOT RUN (Inc 5) | `move_angle`, `bfm_only_flow_and_rotate` |
| REQ-110 | BFM part (`rotary_encoder_rotate`, engine validation): yes | PASS (BFM); VVC commands NOT RUN (Inc 5) | `bfm_only_flow_and_rotate` |
| REQ-111, 112 | Engine: yes | Through `rotary_encoder_rotate` only (PASS); the VVC criteria (completion at the first edge, profile replaced by a speed change) NOT RUN (Inc 5) | `bfm_only_flow_and_rotate`, `linear_ramp_rotation` |
| REQ-115 | Yes | PASS | `linear_ramp`, `linear_ramp_rotation` |

### 5.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 31 tests (30 BFM, 1 VVC) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (31 passing) | `doc/evidence/inc3/regression_nvc.log` |
| Compile and elaborate after removing `last_rpm` (no simulation, as agreed with the user) | NVC 1.23.0 | Scratch compile of uvvm_util, uvvm_vvc_framework, the VIP and both testbenches (`--relaxed`), elaboration of `rotary_encoder_bfm_tb` and `rotary_encoder_vvc_tb` | **PASS** | – |
| Regression after removing `last_rpm` and adding `linear_ramp_rotation`, 32 tests (31 BFM, 1 VVC) | NVC 1.23.0 (1 fs) | as above | **PASS** (32 passing) | `doc/evidence/inc3/regression_nvc_ramp_rotation.log` |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |
| VSG | – | – | BLOCKED (F-022, Stage 5.4) | – |

Runs: run 1 – compile error (`string & std_logic` ambiguous in a message); run 2 – 23/24, `invalid_jitter` (F-025, testbench); run 3 – 30/31, `set_angle_and_jump_edges` read AB in the delta of the call (testbench, same cause as F-025); run 4 – 31/31; run 5 after merging two equal constants – 31/31 (the evidence log).

### 5.5 Decisions taken during the increment

By the user (design rev 0.3): **D-87** REQ-075 reverse criterion corrected (F-024); **D-88** `duration` ≤ 0 ns of `rotary_encoder_rotate` is `TB_ERROR`.

Taken in one-shot mode (internal, approved by the user with the increment):
- **D-89** (E-3.2) log line of fault events;
- **D-90** `rotary_encoder_init` validates the edge offsets and resolves the start angle with them;
- **D-91** fault events settle a running bounce without the cut-off alert;
- **D-92** `rotary_encoder_linear_ramp` returns an empty profile after its `TB_ERROR`;
- **D-93** no correction when an offset change leaves a resting shaft outside its state;
- **D-94** jump target limited to ±(`integer'high` / 2).

### 5.6 Notes for later increments

- **Inc 4/5:** `rotary_encoder_run_motion` now supports rotations and profiles (`MOTION_PROFILE_PASS`, waiting for an interrupt at 0 rpm). Only the BFM path (`run_to_end`) is tested so far; the `run_motion` path is tested with the VVC.

## 6. Stage 5.3 – Increment 4: VVC commands

Implemented and approved 2026-11-11 against design rev 0.5 and spec rev 0.13 (both approved with the increment). Decisions D-95 to D-99 taken in one-shot mode (internal). D-100 by the user: the glitch is removed from the VIP (Section 6.5).

### 6.1 Source changes

| File | Change |
|---|---|
| `src/transaction_pkg.vhd` | `t_operation`: `MOVE_EDGES`, `MOVE_ANGLE`, `MOVE_TO_STATE`, `CENTER_STATE`, `SET_ANGLE`, `JUMP_EDGES`, `GET_STATUS`. Base transaction fields of design 4.6.5 (`direction`, `num_edges`, `target_state`, `occurrence`, `angle`, `rpm`, `time_per_edge`, `profile_length`, `time_per_entry`, `profile_end`) plus the effect fields `edges` and `status` (D-98); uses `rotary_encoder_bfm_pkg` (compiled before it) |
| `src/vvc_cmd_pkg.vhd` | Command field `motion : t_rotary_encoder_motion`; `to_string(t_vvc_result)` with 4 decimals, as the BFM log |
| `src/vvc_methods_pkg.vhd` | `unwanted_activity_severity` removed from `t_vvc_config` (no UAD, as PWM and clock_generator). Methods: `rotary_encoder_move_edges`, `_move_angle`, `_move_to_state` (rpm and `time_per_edge` overloads each), `_center_state`, `_set_angle`, `_jump_edges`, `_get_status`; body-only helpers `send_command`, `move_motion`, `with_rpm`, `with_time_per_edge`, `real_image`. Transaction info set/reset for the seven operations; the `t_vvc_result` overload of `set_global_vvc_transaction_info` takes `edges` and writes `edges` and `status` for all operations |
| `src/rotary_encoder_vvc.vhd` | Request/response types and signals `motion_req`, `motion_rsp`, `motion_interrupt` (D-99). Executor: `request` (sends a request, waits for its response or `terminate_current_cmd`, then sends `REQ_HALT`), `execute_move` (logs the end or "Terminated after N edges"; transaction info `COMPLETED` with edges and end status, `FAILED` when rejected), `execute_operation`, `complete_transaction_info`; `GET_STATUS` stores the status in the result queue; BFM access = moves and fault events; `insert_delay` with clock cycles → `TB_ERROR`. New process `p_motion`: `rotary_encoder_init` from the generic at time 0, request detection by index, `rotary_encoder_set_motion` with the configuration taken at the move start (D-96), `rotary_encoder_run_motion` loop, zero-time operations through the BFM procedures. No `USER_INPUT` marker is left in `src/` |
| `src/rotary_encoder_bfm_pkg.vhd` | `rotary_encoder_run_motion` applies a changed stuck setting at each call (D-97, F-027). `rotary_encoder_glitch` removed (D-100) |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Test case `glitch`, wrapper `glitch` and the glitch-width step of `invalid_fault_event` removed (D-100) |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | Placeholder `vvc_instances_execute_commands` removed (Stage 5.2 decision). Helpers `await`, `wait_for_logger`, `read_status`, `check_status`, `check_event_time`, `edge_direction`, `go_to_zero`, `begin_reject`/`end_reject`; six test cases (6.2) |

### 6.2 Tests (`rotary_encoder_vvc_tb`)

| TC | Content |
|---|---|
| `vvc_power_up_state` | One logged entry per instance at 0 ns: instance 1 `AB = 11`, Z `'1'`; instance 3 (generic: 30°, zero state `00`) `AB = 01`, Z `'0'`; status through the VVC position 0 / 0° and 7 / 30°; no further event of instances 1–3 for 1 µs; checker clean. `zero_state` changed to `00` in the shared configuration: the next move raises one `TB_ERROR`, takes no time, no event; restored, a 1-edge move works |
| `hold_between_commands` | 3 edges, `insert_delay` of 100 edge intervals, an idle wait of 100 intervals: no event after the move; move plus delay last exactly 103 intervals. Moves −5, +2, −1 queued back to back: 8 edges at exactly (k − ½) × 100 ns, checker −4, no illegal transition, status −1 / −4.5° |
| `vvc_commands` | Queue of 10 moves (i edges, alternating direction): 55 edges at exactly (k − ½) × 100 ns, each edge in the direction of its move, duration 5.5 µs, checker −5. `insert_delay` then a move; two moves queued during it and flushed: only the running move happens. Transaction info: while a 4-edge move runs `MOVE_EDGES`, `REVERSE`, 4 edges, `time_per_edge`, `IN_PROGRESS`, `edges` 0; at `COMPLETED` `edges` 4 and the end position; a move with 0 ns per edge ends with `FAILED`, `edges` 0, position unchanged (one `TB_ERROR`); `get_status` puts its result into `status`; `INACTIVE` afterwards. Angle move 10° time form from 0°: edges at 2.25 and 6.75 µs, done at 10 µs, all REQ-086 status fields. Centre state: 9°, position 2, zero time, no event. 9° at 60 rpm: duration 25 ms, edges at their rpm-form times. 4 edges at 6000 rpm. Move to state queued after a 1.125° move: edges at 0.5 and 1.5 µs, done at 2 µs, status 9°; move to state `10` at 60 rpm: one edge, done after 12.5 ms. Set angle 30° from position 3 (no A/B event), jump 2 edges (zero time, one illegal transition, status 39°). A move with `ID_BFM` disabled and one enabled (log reviewed, 6.4) |
| `terminate_move` | A 20-edge move terminated after 10.25 intervals: the command completes at the terminate, no further event, 10 edges, status 46.125°; the next 2-edge move emits its first edge a quarter interval after its start |
| `multiple_instances` | Instances 1 (8 edges forward, 100 ns) and 2 (6 edges reverse, 150 ns) at the same time: each log has exactly its own edges at exact times, instance 3 none; status 8 / −6 |
| `config_change_between_moves` | Bounce enabled in the shared configuration during a 4-edge move: that move has 4 entries, the next 12 (one bounce pulse per edge). B stuck at `'0'` set between moves: B falls at the start of the next move, only the two A edges follow; released: B rises at the start of the next move, the A edge follows at half an interval, status position 13 (the edges of the stuck period count) |

### 6.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-001, 002, 006 (VVC path) | Yes | PASS | `vvc_power_up_state`; REQ-001 also through `check_checker` in every test |
| REQ-003, 004 (moves) | Yes | PASS; rotation part in Section 7.3 | `hold_between_commands` |
| REQ-078 (VVC path) | Yes | PASS | `config_change_between_moves` |
| REQ-081 | Yes | PASS | `vvc_commands` |
| REQ-082 | Yes | PASS | `terminate_move` |
| REQ-083 (moves) | Yes | PASS; rotation part in Section 7.3 | `multiple_instances` |
| REQ-084 | Yes | PASS | `config_change_between_moves` |
| REQ-085 (moves, fault events) | Yes | PASS (Sim); Review: log in the evidence file (6.4); rotation part in Section 7.3 | `vvc_commands` |
| REQ-086 (VVC) | Yes | PASS; rotation part in Section 7.3 | `vvc_commands`, `vvc_power_up_state` |
| REQ-096 (VVC, execution time) | Yes | PASS | `vvc_commands` |

### 6.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 36 tests (30 BFM, 6 VVC) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (36 passing, exit 0) | `doc/evidence/inc4/regression_nvc.log` |
| REQ-085 log review (ID on/off) | NVC | in the regression | `vvc_commands`: the move with `ID_BFM` disabled has no `ID_BFM` line, the one after `enable_log_msg` has; move lines name the VVC call, edges, position and angle | same log |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |
| VSG | – | – | BLOCKED (F-022, Stage 5.4) | – |

Runs: run 1 – compiled, 31/32: the placeholder `vvc_instances_execute_commands` expected "no driver yet" (removed as planned); run 2 – 37/37; run 3 (verbose) – 37/37; run 4 after `to_string` with 4 decimals – 37/37; run 5 with the stuck step – 37/37 PASS, then HDLRegression crashed while saving its project (F-028); run 6 – identical, 37/37, exit 0; run 7 after removing the glitch (D-100) – 36/36, exit 0; run 8 with the transaction-info effect fields (D-98, option A) – 36/36, exit 0.

### 6.5 Decisions taken during the increment

Taken in one-shot mode (internal, approved by the user with the increment):
- **D-95** (E-4.1) the interpreter change for `halt_req` moves to Increment 5, where it is tested;
- **D-96** a VVC move keeps the configuration of its start (REQ-084; F-026);
- **D-97** `rotary_encoder_run_motion` applies a changed stuck setting at each call (F-027);
- **D-99** one request and one response record between executor and `p_motion`; alerts of a rejected move name `rotary_encoder_set_motion(MOTION_…)`, after the executor's "Will be executed" line of the VVC call.

By the user: **D-98** (E-4.2, option A) the transaction info carries the effect of each command (`edges`, end `status`, the `get_status` result) and a rejected move ends with `FAILED`. **D-100** no glitch in the VIP: spec rev 0.13 (A-12), REQ-072 removed, BFM procedure and VVC method removed; bounce, jitter and edge offsets cover the short pulses a decoder must handle. Spec rev 0.13 and design rev 0.5 approved 2026-11-11.

### 6.6 Notes for later increments

- Done in Increment 5 (Section 7): rotations through `REQ_MOTION`, rejects in `p_motion`, configuration after every edge (D-101), responses at the first edge / profile pass, `REQ_STOP`, `rotation_active`, `halt_req` (D-95, D-102), `stop_when_idle_severity` (SK-8).

## 7. Stage 5.3 – Increment 5: VVC rotation

Implemented 2026-11-11 against design rev 0.6. Decisions D-101 to D-103 by the user before coding (Section 7.5); D-104 to D-106 taken in one-shot mode (internal).

### 7.1 Source changes

| File | Change |
|---|---|
| `src/transaction_pkg.vhd` | `t_operation`: `START_ROTATION`, `SET_SPEED`, `STOP_ROTATION`; field comments |
| `src/vvc_cmd_pkg.vhd` | Command field `has_profile` (a rotation command given as a profile; an empty profile has `profile_length` 0 like a constant speed and is rejected by it) |
| `src/vvc_methods_pkg.vhd` | `t_vvc_config.stop_when_idle_severity` (default `TB_WARNING`, SK-8). Methods `rotary_encoder_start_rotation` and `rotary_encoder_set_speed` (rpm, direction + `time_per_edge`, profile + `time_per_entry` + end behaviour each) and `rotary_encoder_stop_rotation`, as API preview 5.2. Body-only helpers `rotation_rpm`, `rotation_time`, `rotation_profile` (a profile longer than the record keeps its length, so it is rejected), `profile_string`; `send_command` takes `has_profile`. Transaction info for the three operations; `rpm`/`time_per_edge` only for a constant speed |
| `src/rotary_encoder_vvc.vhd` | Interpreter: `TERMINATE_CURRENT_COMMAND` increments `halt_req` while `rotation_active`, then calls the framework procedure (D-102). Executor: `execute_rotation` (logs "Took effect" or "Terminated, the rotation is halted", `FAILED` when rejected), `STOP_ROTATION` (logs "Stopped"), `execute_operation` ends `FAILED` when rejected (D-103), `position_string`. `p_motion`: `REQ_STOP`, `halt_req` handling, `rotation_active`, rejections by rotation state with `reject_request` (D-105), a pending response that is given at the first edge, the end of the first profile pass, the end of the motion, or at once for a constant 0 rpm (D-104); a rotation takes the shared configuration after every edge (D-101); log at the end of a `PROFILE_STOP` profile; `motion_interrupt <= motion_req.idx + halt_req` |
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | The edge-list check (formerly private `check_edges_against`) is public as `check_edge_times_list`, for irregular edge times (speed changes, profiles) |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | Constants `C_T`, `C_PROFILE`, `C_TIME_PER_ENTRY`, `C_PROFILE_EDGES`. Helpers `wait_until`, `await_at`, `stop`, `check_rotating`, `check_at_rest`, `begin_reject_running`/`end_reject_running`, `set_config`. 11 new test cases; rotation steps in `hold_between_commands` and `multiple_instances` (7.2) |

The BFM (`rotary_encoder_bfm_pkg.vhd`) is unchanged.

### 7.2 Tests (`rotary_encoder_vvc_tb`)

T = 1 µs per edge (time form) unless stated; 60 rpm = 12.5 ms per edge.

| TC | Content |
|---|---|
| `hold_between_commands` (rotation step) | Rotation at 100 ns stopped 2.25 intervals after its start, `insert_delay` of 100 intervals and an idle wait of 100: no event; the next 1-edge move emits its edge a quarter interval after its start |
| `multiple_instances` (rotation step) | Instance 1 rotates at 100 ns while instance 2 executes +4 and −2 edges at 150 ns: instance 1 12 edges, instance 2 6 edges, each at exact times and only in its own log |
| `rotation_start` | Forward and reverse from a state centre: edges at (k − ½) T, the start completes at 0.5 T, status rotating. From 1.125°: forward completes at 0.25 T, reverse at 0.75 T. ±60 rpm: completes at the rpm-form time of edge 1, status ±60 rpm. 0 rpm: completes at once, rotating at 0 rpm, no edge; after the stop at rest |
| `rotation_long_run_timing` | 800 edges forward and reverse, each exactly at (k − ½) T; 7 rpm, 800 edges, each within one resolution step (85.7 s simulated). One expected TB_WARNING (time stamp truncation) |
| `rotation_speed_change` | T → 2T at 1.0 T: edges at 0.5, 2, 4, 6 T, the change completes at 2 T. Status read at 10 ms during 60 rpm: rotating, 60 rpm; edge times unchanged. 60 rpm → 0 rpm a quarter interval after edge 1: completes at once, status 3.375°, no edge in 20 ms; back to 60 rpm: completes 9.375 ms later. Five changes of speed and direction: no illegal transition, checker position = status position |
| `rotation_direction_change` | Reverse at 0.75 T: edges at 0.5, 1, 2 T, edges 2 and 3 reverse, edge 2 back to the zero state, the change completes at 1 T. +60 → −120 rpm 1.125° past the boundary: the reverse edge 1.5625 ms after the change |
| `rotation_stop` | Stop at 1.75 T: completes at once, no further edge, status position 2, 7.875°, at rest. Forward start from there: first edge after 0.75 T; reverse start: after 0.25 T. Stop at 1.5 T (on the boundary): the edge at 1.5 T is emitted, status 6.75°, position 2; a reverse start emits its edge at its start |
| `commands_rejected_during_rotation` | Edge move, angle move, move to state, centre state, set angle, jump (transaction `FAILED`), second start: one `TB_ERROR` each, zero time; 10 edges at exact times. At 0 rpm a move is rejected as well |
| `speed_change_and_stop_without_rotation` | Speed change (rpm, time form, profile) without rotation: one `TB_ERROR` each, no event. Stop: one `TB_WARNING`, zero time, no event; with `stop_when_idle_severity = ERROR` one `ERROR` |
| `terminate_and_flush_during_rotation` | Terminate with the executor idle at 2.25 T: no further event, status 10.125°, at rest; the next move is not terminated and emits its first edge after T/4. Terminate during `insert_delay`: the delay ends at the terminate, no further event. Terminate while a speed change to 10 T waits for its edge: it ends at the terminate, status 4.95°, at rest. `flush_command_queue` removes a queued move: 10 edges at exact times, no `TB_ERROR` |
| `config_change_during_rotation` | Bounce enabled between edges 1 and 2: edges 1 and 2 without bounce, edges 3 to 5 with one pulse each (`check_bounce`). `cycles_per_rev` 20 → 10 during 6000 rpm: 50 edges at the 20-cycle spacing, no index at position 40. Index width 5, bounce window 0 ns, jitter 45° written between edges: one `TB_ERROR` each at the next edge, none more while the value stays; 14 edges at exact times, no bounce, Z per the default index |
| `index_bounce_and_jitter_in_rotation` | Index width 2 at state `00`, Z inverted, 100 edges: Z follows the model, 2 activations. Bounce 2 pulses in 300 ns on 5 edges. Jitter 18° on 1000 edges: `check_jitter_stats` (bounds reached, mean). One expected TB_WARNING |
| `invalid_rotation` | Start with 0 ns (transaction `FAILED`), −1 ns, non-finite rpm: one `TB_ERROR` each, no event, at rest. During a rotation, changes to 0 ns and to a non-finite rpm: one `TB_ERROR` each, 5 edges at exact times |
| `speed_profile` | (60, 120) hold: completes at 6.25 ms, edges at 6.25, 18.75, 28.125, 34.375, 40.625, 46.875 ms. (0, 60): completes at 31.25 ms, one edge until 40 ms. (60, −60): edges at 6.25, 18.75 ms forward, 31.25, 43.75 ms reverse. (0): completes at 25 ms, rotating, no edge. (60, 120) with jitter 18°: 32 edges, each within the amplitude of its entry's speed, jittered. 256 entries of 6000 rpm, 1 µs each, `PROFILE_STOP`: accepted, completes at 62.5 µs, 2 edges, at rest after 256 µs. One expected TB_WARNING |
| `speed_profile_end` | Hold: 8 edges up to 59.375 ms. Repeat: 9 edges, 56.25, 68.75, 78.125 ms after the first pass. Stop: completes at 6.25 ms, at rest at 27°, position 6 at 50 ms, no further edge; a following stop raises one `TB_WARNING`. A speed change to 1 ms per edge at 30 ms during a repeating profile: first edge at 30.7 ms, then every 1 ms up to 59.7 ms, no repeat at 50 ms |
| `invalid_speed_profile` | Empty, non-finite entry, `time_per_entry` 0 ns, 257 entries: one `TB_ERROR` each as a start (no rotation) and as a speed change during a rotation (5 edges at exact times) |

### 7.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-003, 004 (rotation) | Yes | PASS | `hold_between_commands` |
| REQ-045, 054, 063 (during a rotation) | Yes | PASS | `config_change_during_rotation` |
| REQ-083 (rotation) | Yes | PASS | `multiple_instances` |
| REQ-085 (rotation) | Yes | PASS (Sim); Review: "Took effect", "Stopped", "Terminated …" and profile-end lines in the evidence log | all Inc 5 tests |
| REQ-086 (rotation) | Yes | PASS | `rotation_start`, `rotation_speed_change` |
| REQ-100 | Yes | PASS | `rotation_start` |
| REQ-101 | Yes | PASS | `rotation_long_run_timing` |
| REQ-102 | Yes | PASS | `rotation_speed_change` |
| REQ-103 | Yes | PASS | `rotation_direction_change` |
| REQ-104 | Yes | PASS | `rotation_stop` |
| REQ-105 | Yes | PASS | `commands_rejected_during_rotation` |
| REQ-106 | Yes | PASS | `speed_change_and_stop_without_rotation`, `speed_profile_end` |
| REQ-107 | Yes | PASS | `terminate_and_flush_during_rotation` |
| REQ-108 | Yes | PASS | `config_change_during_rotation` |
| REQ-109 | Yes | PASS | `index_bounce_and_jitter_in_rotation`, `speed_profile` (jitter per entry) |
| REQ-110 (VVC) | Yes | PASS | `invalid_rotation` |
| REQ-111 | Yes | PASS | `speed_profile` |
| REQ-112, 113 | Yes | PASS | `speed_profile_end` |
| REQ-114 | Yes | PASS | `invalid_speed_profile` |

With Increment 5 every feature except REQ-033 (documentation example, Phase 6) has a passing test on NVC.

### 7.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 50 tests (30 BFM, 20 VVC) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (50 passing, no minor alerts, exit 0) | `doc/evidence/inc5/regression_nvc.log` |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |
| VSG | – | – | BLOCKED (F-022, Stage 5.4) | – |

Runs: run 1 – compile error, `reject` is a reserved word (F-029); run 2 – 49/50, a test expectation in `rotation_direction_change` (stop on an edge time, F-030; log `doc/evidence/inc5/regression_nvc_test_bug_direction_change.log`); run 3 – 50/50, 3 with minor alerts (time stamp truncation, F-031); run 4 – 50/50 PASS, exit 0.

Mutation checks: NOT RUN (optional, can be offered for D-101/D-102 at the boundary).

### 7.5 Decisions taken during the increment

By the user (2026-11-11, before coding):
- **D-101** (E-5.3) a rotation takes the shared configuration after every edge; a change between edges k and k+1 takes effect from edge k+2; no engine API change. REQ-108 reworded;
- **D-102** `terminate_current_command` halts a running rotation also while the executor runs another command, which is terminated as well. REQ-107 extended;
- **D-103** every command the VVC rejects with `TB_ERROR` ends with transaction status `FAILED`; a stop without rotation `COMPLETED`.

Taken in one-shot mode (internal, for review):
- **D-104** (E-5.1) a change at an edge time completes at the first edge after it; the edge at the change time belongs to the old motion (D-25);
- **D-105** rejections that depend on the rotation state are decided in `p_motion`, not in the executor;
- **D-106** (E-5.2) the interpreter halts only a running rotation (`rotation_active`); queued rotation commands are not affected by `terminate_current_command`.

Also internal: command field `has_profile` to reject an empty profile (an empty profile would otherwise look like a constant speed); `check_edge_times_list` made public in the testbench package.

### 7.6 Notes for Stage 5.4

- Jitter steps and the 7 rpm run each declare one expected time-stamp-truncation `TB_WARNING`. On GHDL (fs) and Questa (`-t ps`) the jittered times also lie between whole ns, so the count should hold; check it per simulator.
- `rotation_long_run_timing` simulates 85.7 s at 7 rpm and `speed_profile` about 0.2 s; NVC needed seconds. Watch the Questa Starter run time (E-2.2).
