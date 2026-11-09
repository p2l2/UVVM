# Rotary Encoder VVC – Implementation and Verification Report

| Item | Value |
|---|---|
| Revision | 0.3 (Stage 5.3 – Increment 1: BFM core) |
| Date | 2026-10-27 |
| Baseline | Branch `p2l2_vip_rotary_encoder`, base `90d56e93`; uvvm_util v2.21.4, uvvm_vvc_framework v2.12.15 |
| Inputs | Requirements rev 0.5, VVC architecture rev 0.4, testbench architecture rev 0.2 |
| Mode | One-shot (pause at Stage 5.1, Stage 5.2, each increment); development simulator NVC 1.23.0; the user commits |

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-27 | Stage 5.1 – Generate skeleton: generator run, file inventory, markers, skeleton comparison |
| 0.2 | 2026-10-27 | Stage 5.2 – First testbench and regression script: SK-1 to SK-4 and SK-7 applied, testbench files, `test.py`, NVC regression |
| 0.3 | 2026-10-27 | Stage 5.3 – Increment 1: BFM core: BFM engine, 13 BFM test cases, NVC regression 15/15 |

## 1. Stage 5.1 – Generate skeleton

### 1.1 Generator run

- Script: `uvvm_vvc_framework/script/vvc_generator/vvc_generator.py` (prompt order checked in `main()`, `get_generating_level()`, `get_number_of_channels()`; it matches arch §11).
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
| SK-4 | `transaction_pkg` defines local constants `C_VVC_CMD_DATA_MAX_LENGTH := 32`, `C_VVC_CMD_STRING_MAX_LENGTH := 300`, `C_VVC_MAX_INSTANCE_NUM` | GPIO/PWM alias `C_<NAME>_VVC_*` from `adaptations_pkg` (arch §2.2) | Alias `C_VVC_CMD_STRING_MAX_LENGTH`, `C_VVC_MAX_INSTANCE_NUM`, `C_VVC_CMD_PROFILE_MAX_LENGTH` to the S-1 constants; drop the data/address constants (no data bus) | Stage 5.2 |
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
| `src/rotary_encoder_bfm_pkg.vhd` | Declarations from arch §15.1: `t_rotary_encoder_if`, the five enumeration types, the full `t_rotary_encoder_bfm_config` with `C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT` (incl. `id_for_bfm_wait`), `t_rotary_encoder_status`, `init_rotary_encoder_if_signals` (all `'Z'`); `C_BFM_SCOPE = "ROTARY ENCODER BFM"` (generator: underscore, arch §2.2: space) | SK-3, SK-7 (brought forward from Inc 1: harness instance 3 needs `start_angle`) |
| `src/vvc_cmd_pkg.vhd` | `t_vvc_result` is `t_rotary_encoder_status` (generator: `std_logic_vector` of the removed data constant), `to_string(t_vvc_result)`; `use work.rotary_encoder_bfm_pkg.all` (PWM pattern) | Consequence of SK-4, arch §7.2 |

Remaining `USER_INPUT` markers: 15 (procedures, commands, transaction info, executor), all planned for Inc 1–5.

### 2.2 Testbench and regression script

| File | Content |
|---|---|
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | `t_enc_event`, protected `t_event_log` (dynamic per-id storage, decoder checker: Gray position, edges, illegal transitions, invalid levels, Z events; `arm`, `clear`), `gray_index`, `ideal_edge_time` (tb arch 3.4, long division, E-1.2), `check_checker`, `check_no_event`; package `rotary_encoder_th_pkg` with `shared_th_event_log` |
| `tb/maintenance_tb/rotary_encoder_th.vhd` | `ti_uvvm_engine`, three VVC instances (3: `start_angle => 30.0`), signals `enc1_if` to `enc3_if`, one logger per interface, checker armed at the first event |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | Sequencer, `GC_TESTCASE`, placeholder **TC_000**: `insert_delay`/`await_completion` on all three instances; event logs empty (no driver yet) |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | Sequencer with own `enc_if` and logger (id 1), **TC_000** testbench self-test: Gray index, checker on hand-driven forward/reverse/illegal/invalid/Z sequences, zero-length state (two entries at one time), `check_no_event` positive and negative, `ideal_edge_time` against 7 exact values (ps and fs branch) |
| `script/maintenance_script/test.py` | Copy of `bitvis_vip_gpio`'s, exactly the four edits of tb arch §5 (print text, library name ×3 and comment, scoreboard line removed, comment) |

Decided by the user 2026-10-27: BFM TC_000 stays permanently as the testbench self-test; VVC TC_000 is a placeholder, replaced by TC_001 in Inc 4. The declarations brought forward from Inc 1 and the `C_BFM_SCOPE` correction are accepted. `GC_INSTANCE_IDX := 1` (SK-2) follows arch §5; the official VVCs are split (11 with default, e.g. `clock_generator`, `spi`, `uart`; 12 without, e.g. `gpio`, `axistream`).

Remaining check procedures of tb arch 3.3 (`check_event_times`, `check_edge_sequence`, `check_z_follows_ab`, `save_events`/`compare_inverted`, `check_constant_spacing`, `check_jitter_stats`, `check_rejected`) are added with the increments that first need them.

### 2.3 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression (2 tests: `rotary_encoder_bfm_tb.TC_000`, `rotary_encoder_vvc_tb.TC_000`) | NVC 1.23.0 (resolution 1 fs) | `cd p2l2_vip_rotary_encoder/sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (2 passing, exit 0) | `doc/evidence/stage5_2/regression_nvc_verbose.log` |
| `ideal_edge_time` self-test, fs branch | NVC | (in TC_000) | PASS, 7 of 7 values exact | same log |
| `ideal_edge_time` self-test, ps branch | Questa | – | NOT RUN (Stage 5.4) | – |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |

First run failed (F-007, testbench error, fixed).

Approved by the user 2026-10-27 (committed by the user as `1418078c`).

## 3. Stage 5.3 – Increment 1: BFM core

### 3.1 Source changes

| File | Change |
|---|---|
| `src/rotary_encoder_bfm_pkg.vhd` | Motion types (`t_rotary_encoder_motion_kind`, `_speed_form`, `_motion_event`, `t_rotary_encoder_motion`, `C_ROTARY_ENCODER_MOTION_DEFAULT`), `t_rotary_encoder_state` (private fields, E-1.1); public: conversions (4), `rotary_encoder_get_status`, `rotary_encoder_init`, `rotary_encoder_move_edges`/`_detents`/`_angle` (rpm and time overloads), engine `rotary_encoder_start_motion`/`_run_motion`/`_halt_motion` ("Used by the VVC."). Body-only helpers (DV-1): integer angle model (K = 9·10⁸ quanta/edge), segment timing from the anchor (arch 6.2), detent snap, normalization, output mapping, `floor_big`/`round_big`/`units_to_time`/`time_to_units` (no `floor` above 2³¹, pitfall F-042), `real_image` (F-011) |
| `doc/rotary_encoder_vvc_arch.md` | Rev 0.5 (proposed): §6.2 exact `tpe_int`/`tpe_frac` for an integer rpm divisor (F-010) |

No magic numbers (user request 2026-10-27): the BFM names its physical constants (`C_EDGES_PER_CYCLE`, `C_SEC_PER_MIN`, `C_MINUTE`, `C_DEG_PER_REV`, `C_DEG_PER_SEC_PER_RPM`) and its arithmetic limits (`C_SPLIT`, `C_FLOOR_SPLIT`, `C_MAX_DIVISOR`, `C_MAX_PRINTABLE`, `C_REAL_DIGITS`); `C_QUANTA_PER_DEG` is derived from K. The testbench derives the geometry from the default configuration (`C_CPR`, `C_EDGES_PER_REV`, `C_DEG_PER_EDGE`, `C_DEG_PER_DETENT`), names its speeds (`C_TPE`, `C_TIME_PER_DEG`, `C_TPE_ANGLE`), and lists the requirement test vectors as constants with their REQ. Literals left on purpose: the specified config defaults (arch 6.7), the TC_001 table (REQ-002/005), the REQ-095 values in TC_093, and the hand-computed reference values of TC_000.

Implemented ahead of their increment, because `drive_outputs` and the VVC need them; their tests stay in the planned increment:
- direction swap, A/B and Z inversion, index cycle and modes (AD-9) in `drive_outputs` – tests Inc 2 (TC_030, 031, 040, 041). REQ-002 needs Z already at power-up;
- `rotary_encoder_run_motion` (interrupt, one delta per edge) and `rotary_encoder_halt_motion` – tests Inc 4 with `p_motion`.

Not yet implemented: `MOTION_ROTATION`, `MOTION_STOP` (`rotary_encoder_start_motion` rejects them with `TB_ERROR` "not supported yet" until Inc 3); bounce, jitter, edge offsets, stuck outputs, fault events, `rotary_encoder_rotate`, `rotary_encoder_linear_ramp` (Inc 2/3). Remaining `USER_INPUT` markers in the BFM: none; in the VVC files: 13 (Inc 4/5).

Expected decisions: E-1.1 – the state fields are declared in the package with the comment "All fields are private" (VHDL needs the full record). E-1.2 – done in Stage 5.2. E-1.3 – the motion record uses `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` from `adaptations_pkg` directly. No decision needed the user.

### 3.2 Tests (`rotary_encoder_bfm_tb`)

| TC | Content |
|---|---|
| TC_001 | 8 power-ups (0°, −10°, 30°, 400° × detents on/off): AB and Z in the first delta, status position and angle, no event for 1 µs |
| TC_010 | N ∈ {1…5, 1000} forward and reverse from all 4 states; checker position, edge count, status |
| TC_011 | Time form 10 edges at 1 ns/1 µs/1 ms (exact times and duration); 3+2+2 back to back with direction changes (exact); 1000 edges at 7 and 6000 rpm (each edge within one step of the exact floor, duration within one step); speed curves (time form exact 2 µs, rpm form 9.375 ms ± 2 steps) |
| TC_012 | ±1 ×10 from each state; +5 −3 +7 −10 with continuous timing (25 edges exact) |
| TC_013 | 0 edges and 0 detents: no event, no time |
| TC_014 | 7 invalid speeds: one `TB_ERROR` each, no time, no event |
| TC_020 | Detent moves for 1/2/4 edges per detent × 4 rest states: edge counts, rest state after each move |
| TC_021 | Detent move off a rest state: one `TB_WARNING`, 4 edges; none from a rest state; invalid `edges_per_detent` (0, 3, 8) and `rest_state` (X1, 1Z) rejected |
| TC_022 | Detents off: detent move rejected, angle move without snap. Snap: 10° → 18° (4 edges at exact times, 18 µs), 7° → 0° (edge times at 2.25/6.75/7.25/11.75 µs, 14 µs), 1° → 0° (no edge, 2 µs), 9° ties forward/reverse (±18°), edge move does not snap |
| TC_090 | Three 1° moves: one edge at 2.25 µs; durations 9° / 10°+snap / 7°+snap at 60 rpm and in the time form |
| TC_091 | 360 × 1°, 3600 × 0.1°, 40 × (1 edge + 4.5°): 80 edges and status angle exactly 360.0; 2° + 1 edge + 1°: edges at 225/675 ns, ends at 7.5° |
| TC_092 | Invalid angles (−1.0, `real'high`, rpm form) rejected |
| TC_093 | Conversions 1/60/6000 rpm ↔ 750 ms/12.5 ms/125 µs, −60 rpm, 60 rpm ↔ 360 °/s; 5 invalid calls → 5 `TB_ERROR` |

Debug signals (user request 2026-10-27): `dbg_position` and `dbg_angle` in `rotary_encoder_bfm_tb` show the shaft after every init and move (from `rotary_encoder_get_status()`, updated by the move helpers; all valid moves go through `edges`/`detents`/`angle`, with rpm overloads). `init_encoder` waits `C_IDLE_TIME` (= `C_TPE`) before re-initializing, so each end state stays visible instead of lasting only two deltas. They are not used by any check. To see them and process variables in Questa, load the test with `vsim -voptargs=+acc …` (HDLRegression passes only `-t ps`).

Every test also checks the decoder checker (illegal transitions 0, invalid levels 0) after each step: REQ-001 and REQ-070 for all non-error tests. TC_011 and TC_090 each declare one expected `TB_WARNING` (UVVM time-stamp truncation, raised once per simulation, pitfall F-012/F-022 of the PWM run).

### 3.3 Requirement status

| REQ | Implemented | Verified (NVC) | Test |
|---|---|---|---|
| REQ-001 | Yes (drive logic: only '0'/'1') | PASS | checker in every TC |
| REQ-002 | Yes (BFM init; VVC power-up Inc 4) | PASS (BFM) | TC_001 |
| REQ-004 | Yes | PASS | TC_012 |
| REQ-005 | Yes | PASS | TC_001 |
| REQ-010, 011 | Yes | PASS | TC_010 |
| REQ-012, 013 | Yes | PASS | TC_011, TC_012 |
| REQ-014 | Yes | PASS | TC_012 |
| REQ-015 | Yes | PASS | TC_013 |
| REQ-016 | Yes | PASS | TC_014 |
| REQ-020, 021 | Yes | PASS | TC_020 |
| REQ-022, 023 | Yes | PASS | TC_021 |
| REQ-024 to 027 | Yes | PASS | TC_022 |
| REQ-070 | Yes | PASS (Inc 1 scope) | checker in every TC |
| REQ-090, 092 | Yes | PASS | TC_090, TC_022 |
| REQ-091, 093 | Yes | PASS | TC_091 |
| REQ-094 | Yes | PASS | TC_092 |
| REQ-095 | Yes | PASS | TC_093 |

REQ-002 and REQ-004 are verified for the BFM; their VVC part is verified in Inc 4.

### 3.4 Results

| Check | Simulator | Command | Result | Evidence |
|---|---|---|---|---|
| Regression, 15 tests (BFM TC_000, 001, 010–014, 020–022, 090–093; VVC TC_000) | NVC 1.23.0 (1 fs) | `cd sim && python3 ../script/maintenance_script/test.py -s NVC -fr -v` | **PASS** (15 passing) | `doc/evidence/inc1/regression_nvc_verbose.log` |
| GHDL, Questa | – | – | NOT RUN (Stage 5.4) | – |

First run: 4 of 15 failed. TC_011: BFM defect F-010 (fixed). TC_014/TC_092: NVC crash F-011 (fixed). TC_091: testbench expectation F-013 (fixed).

Known limitation: for a non-integer divisor (|rpm| × 4 × `cycles_per_rev` not an integer) `tpe_frac` still comes from the `real` value. The error is about n × 10⁻¹⁶ of `time_per_edge` (0.1 fs per 10⁶ edges at 7 rpm). REQ-012 tests integer rpm only.
