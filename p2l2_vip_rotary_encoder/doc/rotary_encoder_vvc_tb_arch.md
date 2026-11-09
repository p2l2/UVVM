# Rotary Encoder VVC – Testbench Architecture

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_vvc_tb_arch.md` |
| Revision | 0.2 |
| Status | **Approved 2026-10-27** (Phase 4 – Testbench architecture) |
| Sources | `rotary_encoder_spec.md` rev 0.6, `rotary_encoder_vvc_reqs.md` rev 0.5, `rotary_encoder_vvc_arch.md` rev 0.4 |
| References | Scripts and per-VIP files: official `bitvis_vip_gpio` (TD-6). Testbench layout and integration precedent: `p2l2_vip_pwm` (branch `p2l2_vip_pwm`, `742ca88f`; integration commit `bb4b0c91`) |

Decisions are marked **TD-n** and collected in Section 9. All accepted by the user on 2026-10-27 (TD-6 changed to official scripts).

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-27 | Initial proposal |
| 0.2 | 2026-10-27 | User decision TD-6: official scripts first, so `test.py`, the companion scripts and the per-VIP files come from `bitvis_vip_gpio`, not from PWM (§5, §7.1). TD-1 to TD-5, TD-7, TD-8 and S-1 to S-8 accepted as proposed. Approved 2026-10-27 |

---

## 1. What the VVC is tested against (TD-1)

The VVC is encoder-only, so there is no receive side to loop back to, and no DUT exists. **Proposal: an independent decoder checker in the testbench**, built from spec §8 (A-11), plus an event log of every change on A/B/Z.

| Option | Verdict |
|---|---|
| **Independent checker + event log (recommended)** | Spec §8 is written as exactly this reference. Small (one logger process per interface, one protected type), no build dependency, and it sees every delta-level event, which the fault requirements (REQ-071 same-delta illegal transition, REQ-001 levels) need |
| VVC↔VVC loopback | Impossible: no receiver role (excluded in Phase 2) |
| Behavioural DUT decoder (counter RTL) | Adds a DUT to maintain, hides delta-level detail behind its own sampling, and would itself need verification. Better suited to a user's project |

**Independence rule.** The testbench never uses the BFM to compute an expected value. The Gray table, the position decoding and the expected edge times are written in the testbench package. Expected values come from (a) the literal numbers in the requirement acceptance criteria, which were computed by hand, or (b) closed-form functions in the testbench package (Section 3.4). The testbench does **not** reimplement the angle/segment engine; a second implementation of the same algorithm would share its mistakes. BFM functions appear only as the object under test (`rotary_encoder_get_status` in status checks, the conversions in TC-093, `rotary_encoder_linear_ramp` in TC-114).

## 2. Layout

Same layout as `p2l2_vip_pwm/tb/maintenance_tb/`:

| File | Content |
|---|---|
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | Package `rotary_encoder_tb_pkg`: event record, protected event log/checker, Gray decoding, expected-value functions, check procedures. Second package `rotary_encoder_th_pkg` in the same file with the shared log variable (PWM precedent: a shared variable of a protected type cannot be declared before the protected body) |
| `tb/maintenance_tb/rotary_encoder_th.vhd` | Test harness for the VVC testbench: `ti_uvvm_engine`, three VVC instances, one logger process per instance |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | VVC test sequencer, `GC_TESTCASE : string := "UVVM"` |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | BFM-only test sequencer (REQ-080 and all signal-level requirements), own interface signal and logger, `GC_TESTCASE` |

Test case selection: `if GC_TESTCASE = "TC_010" then … elsif …` with an `else` branch that raises `TB_ERROR "Unsupported test case"`, as PWM; HDLRegression discovers the test cases from these branches. Each test sets `<TC>_Log.txt` / `<TC>_Alert.txt` and ends with `report_alert_counters(FINAL)` and `std.env.stop`.

### 2.1 Test harness (`rotary_encoder_th`)

| Instance | Generic `GC_ROTARY_ENCODER_BFM_CONFIG` | Signal | Used by |
|---|---|---|---|
| 1 | default | `enc1_if` | Every VVC test |
| 2 | default | `enc2_if` | REQ-083 (concurrency) |
| 3 | default with `start_angle => 30.0` (detents on) | `enc3_if` | REQ-002/005 through the generic path: power-up at position 8 (36°) |

No clock, no reset (the VVC has none). Three logger processes write to the shared log under ids 1, 2, 3. The VVC testbench reaches the signals with external names only where the log is not enough (PWM precedent: `<< signal i_test_harness.… >>`).

### 2.2 Start-angle matrix (X-6, TD-3)

REQ-002/005 need a power-up per start angle (−10°, 30°, 400°, detents on/off, plus the defaults: 7 configurations). Proposal:
- **BFM testbench TC_001** runs the full matrix with `rotary_encoder_init` and one configuration per step. The VVC's `p_motion` calls the same procedure with its generic, so this covers the logic.
- **VVC testbench TC_001** covers the generic path once: instance 1 (defaults: `AB = 11`, Z active, position 0) and instance 3 (30°, detents on: position 8, `AB = 11`, Z inactive), checked at the first delta and with no A/B event before the first movement.

Alternative: one VVC instance per configuration (7 instances in the harness). Rejected: it duplicates the BFM coverage and makes every other VVC test elaborate seven VVCs.

## 3. Checker and event log (`rotary_encoder_tb_pkg`)

### 3.1 Event logging

One logger process per interface: `wait on enc_if.a, enc_if.b, enc_if.z;` and one log entry per wake-up: `(time, a, b, z, a_changed, b_changed, z_changed)`. A wake-up happens once per delta cycle in which something changed, so:
- A and B changing in the **same delta** appear as one entry with both flags set (illegal transition, REQ-071).
- A zero-length state (AD-7: two events on one channel at the same time, in different deltas) appears as two entries with the same time, each legal.

The log is dynamically sized (grows inside the protected body), so the 10 000-edge jitter test and bounce runs need no capacity constant. `clear(id)` empties a log between steps.

### 3.2 Decoder checker (spec §8)

Runs inside `add()` on every entry, per log id, after the checker is **armed** (the BFM testbench arms it after `rotary_encoder_init`; the harness loggers arm at the first event at time 0, i.e. the VVC's initialization):

| Event | Classification | Counter |
|---|---|---|
| A or B not `'0'`/`'1'` (also Z) | Invalid level (spec §8, REQ-001) | `invalid_level` |
| Exactly one of A/B changed, forward per the A-leads-B Gray table `00→10→11→01→00` | Forward edge | `position + 1`, `edges + 1` |
| Exactly one of A/B changed, reverse | Reverse edge | `position − 1`, `edges + 1` |
| A and B changed in one entry | Illegal transition (spec §4.3) | `illegal`, position unchanged (§8) |
| Only Z changed | Index event | `z_events` |

Bounce toggles and glitch pulses decode as alternating forward/reverse edges, so the net position stays correct and nothing is counted as illegal; the bounce and glitch tests count events explicitly. Inverting both A and B maps the forward sequence onto itself, so the checker is unaffected by `ab_inverted`; `direction_swap` reverses the count (REQ-030).

The checker **counts and does not alert**: error tests provoke illegal transitions and invalid levels on purpose. Instead every test step ends with `check_checker(id, exp_position_change, exp_illegal => 0, exp_invalid => 0, msg)` (TD-5). This gives REQ-001 and REQ-070 in every test without per-test effort and keeps the expected counts visible in the test code.

### 3.3 Check procedures (indicative names; final names in Stage 5.2)

| Procedure / function | Purpose |
|---|---|
| `check_checker` | Position change and violation counters since the last clear |
| `check_event_times(id, first, expected : t_time_array, tolerance)` | Event times relative to a start time; tolerance 0 for "exact", `C_RESOLUTION` for "within one step" |
| `check_edge_sequence(id, expected : t_ab_array)` | Logical AB sequence (direction, Gray order) |
| `check_no_event(id, from, to)` | REQ-003 hold, REQ-040 Z quiet, stuck outputs |
| `check_z_follows_ab(id, index_state, mode)` | REQ-042…044, 077: Z changes in the same entry or delta-time as the A/B event that enters/leaves the index states |
| `save_events` / `compare_inverted` | REQ-031/032: second run equals `not` of the first, time-relative |
| `check_constant_spacing(id, first, n, period, tolerance)` | REQ-101 long runs without a table |
| `check_jitter_stats(id, ideal_first, period, amplitude)` | REQ-061: bound, mean, both bounds reached within 5 % |

### 3.4 Expected edge times without accumulated error

Rpm-form criteria require "within one resolution step" over runs of up to 86 s (10 revolutions at 7 rpm). On GHDL and NVC the resolution is fs; a `real` (53-bit mantissa) holding 8.6·10¹⁶ fs has a granularity of about 16 fs, so a single `real` formula for the expected time would itself be wrong by more than the tolerance. The testbench therefore computes ideal times with exact `time`/`integer` arithmetic for **integer rpm** (every rpm value in the acceptance criteria is an integer: 7, 60, 120, 600, 6000):

  t(k) = t_s + (k − ½) × 60 s / (rpm × 4 × `cycles_per_rev`) = t_s + q × 1 sec + f, with n = (2k − 1) × 30, D = rpm × 4 × `cycles_per_rev`, q = n / D, r = n mod D, f = r / D seconds.

f is computed by decimal long division in `integer`, one digit per power of ten down to `std.env.resolution_limit` (remainder × 10 < 10 × D stays far inside 32 bits), and accumulated as `time`. This is the exact floor of the ideal time, independent of the resolution and free of overflow (a direct `r × 1 sec` would overflow 64 bits for D > 9 200, e.g. 6000 rpm: D = 480 000). The tolerance of one step then covers floor vs. rounding. The function gets a self-test against hand values in Stage 5.2 (Inc 1 expected decision E-1.2). Time-form criteria use `time` arithmetic directly and are exact.

### 3.5 Alerts

Expected `TB_ERROR`/`TB_WARNING` per invalid call (REQ-016, 022, 023, …) are declared with `increment_expected_alerts_and_stop_limit(severity, 1)` immediately before the call, so `report_alert_counters(FINAL)` fails the test on a missing or extra alert. A helper `check_rejected(…)` combines that with `check_no_event` (outputs unchanged).

## 4. Test cases and requirement mapping

TC IDs are the requirement test IDs (`TC-010` → `GC_TESTCASE = "TC_010"`). Only TC-001 exists in both testbenches (signal level in the BFM TB, generic path in the VVC TB). TC-072 is not used by any requirement. Every test also checks REQ-001 and REQ-070 through `check_checker`.

### 4.1 BFM testbench (`rotary_encoder_bfm_tb`, 30 test cases)

| TC | Content | Requirements | Inc |
|---|---|---|---|
| TC_001 | Start-angle matrix (defaults; −10°, 30°, 400° × detents on/off), state and Z at the first delta, no A/B event before the first move | REQ-001, 002, 005 | 1 |
| TC_010 | Forward/reverse N ∈ {1…5, 1000} from all four states (start angles 0°, 4.5°, 9°, 13.5°, detents off); no violation in any non-error test (checker, every TC) | REQ-010, 011, 070 | 1 |
| TC_011 | Edge timing, time form 1 ns/1 µs/1 ms; rpm form 7 and 6000 rpm, N = 1000; speed curves back to back | REQ-012, 013, 060 | 1 |
| TC_012 | Reversal ±1 edge ×10 from each state; mixed sequence continuity | REQ-004, 014 | 1 |
| TC_013 | 0-edge move | REQ-015 | 1 |
| TC_014 | Invalid speeds | REQ-016 | 1 |
| TC_020 | Detent moves, `edges_per_detent` ∈ {1, 2, 4}, 4 rest states | REQ-020, 021 | 1 |
| TC_021 | Detent move off a rest state; invalid `edges_per_detent`/rest state | REQ-022, 023 | 1 |
| TC_022 | Detents off; snap after angle moves (10°, 7°, 1°, 9° ties); edge moves don't snap | REQ-024…027 | 1 |
| TC_030 | Direction swap | REQ-030 | 2 |
| TC_031 | A/B and index polarity inversion vs. non-inverted run | REQ-031, 032 | 2 |
| TC_040 | Index off; once per revolution, `cycles_per_rev` ∈ {1, 3, 24}, two index positions, both directions | REQ-040, 041 | 2 |
| TC_041 | Index modes ¼, ½, 1 cycle | REQ-042…044 | 2 |
| TC_042 | Invalid `cycles_per_rev` | REQ-045 | 2 |
| TC_050 | Bounce off/on, nominal timing kept, Z does not bounce | REQ-050, 051, 052, 055 | 2 |
| TC_051 | Bounce placement random (seed reproducible) / even | REQ-053 | 2 |
| TC_052 | Invalid window; bounce cut-off and its alert | REQ-054, 056 | 2 |
| TC_060 | Jitter statistics over 10 000 edges, seed reproducibility, 60/600 rpm scaling | REQ-061, 062 | 2 |
| TC_061 | Invalid jitter, incl. the offset-dependent limit | REQ-063 | 2 |
| TC_070 | `rotary_encoder_set_angle` / `rotary_encoder_jump_edges` (all criteria of REQ-071) | REQ-071 | 3 |
| TC_071 | Glitch | REQ-072 | 3 |
| TC_073 | Invalid fault-event parameters | REQ-074 | 3 |
| TC_074 | Edge offsets: timing, duty error, swap, ±44° limits, invalid ±45°, Z with offsets | REQ-075, 076, 077 | 3 |
| TC_075 | Stuck outputs incl. `'Z'`, release, bounce; invalid levels | REQ-078, 079 | 3 |
| TC_080 | BFM-only flow: edges/timing/detents/index by direct calls; `rotary_encoder_rotate` in its three overloads (TD-4) | REQ-080 | 3 |
| TC_090 | Angle moves: edge at 2.25°, durations with and without snap, both forms | REQ-090, 092 | 1 |
| TC_091 | No drift: 360 × 1°, 3600 × 0.1°, mixed edge/angle moves | REQ-091, 093 | 1 |
| TC_092 | Invalid angles | REQ-094 | 1 |
| TC_093 | Conversion functions and their errors | REQ-095 | 1 |
| TC_114 | `rotary_encoder_linear_ramp` | REQ-115 | 3 |

### 4.2 VVC testbench (`rotary_encoder_vvc_tb`, 20 test cases)

| TC | Content | Requirements | Inc |
|---|---|---|---|
| TC_001 | Power-up of instances 1 and 3 from the generic (2.2) | REQ-001, 002, 005 | 4 |
| TC_002 | Hold during `insert_delay` and ≥ 100 × `time_per_edge` idle, after a move and after a stopped rotation; continuity across commands | REQ-003, 004 | 4 (move part), 5 (rotation part) |
| TC_081 | Framework methods; queue of 10 moves in order; one move of each kind and form through the VVC with edge times and completion; fault events and `get_status`/`fetch_result` through the VVC; logging with the message ID on and off | REQ-081, 085 | 4 |
| TC_082 | `terminate_current_command` during a move | REQ-082 | 4 |
| TC_083 | Instances 1 and 2 at different speeds; instance 1 rotating while 2 moves; each log sees only its own edges | REQ-083 | 4 (moves), 5 (rotation part) |
| TC_084 | Shared config change during a move affects only the next one | REQ-084 | 4 |
| TC_100 | Rotation start: completion at the first edge, ¼-edge start offsets, ±60 rpm, 0 rpm | REQ-100 | 5 |
| TC_101 | 800 edges exact (time form), 7 rpm × 10 rev within one step | REQ-101 | 5 |
| TC_102 | Speed change mid-edge, change to 0 rpm and back, 5 changes | REQ-102 | 5 |
| TC_103 | Direction change without hysteresis | REQ-103 | 5 |
| TC_104 | Stop with snap forward/reverse, detents off, default snap speed | REQ-104 | 5 |
| TC_105 | Moves, fault events and second start rejected during a rotation | REQ-105 | 5 |
| TC_106 | Speed change / stop without rotation | REQ-106 | 5 |
| TC_107 | `terminate_current_command` during a rotation with the executor idle (F-004) and busy; `flush_command_queue` | REQ-107 | 5 |
| TC_108 | Signal config read per edge, geometry at start | REQ-108 | 5 |
| TC_109 | Index, bounce, jitter, swap, inversion checks with a rotation as stimulus | REQ-109 | 5 |
| TC_110 | Invalid rotation parameters | REQ-110 | 5 |
| TC_111 | Profiles: (60, 120), (0, 60), (60, −60), (0), jitter per entry, 256 entries | REQ-111 | 5 |
| TC_112 | Profile end hold/repeat/stop (detents off/on); plain speed change replaces a profile | REQ-112, 113 | 5 |
| TC_113 | Invalid profiles | REQ-114 | 5 |

**Coverage check:** all 77 active requirements map to at least one test case; REQ-001 and REQ-070 additionally run in every test. REQ-085 is *Sim + Review*: TC_081 produces the log with the ID enabled and disabled, and the log file is kept in `<evidence_dir>` for the review.

## 5. Regression infrastructure (TD-6)

**Rule (user, 2026-10-27): official scripts first.** Scripts are taken from an official UVVM VIP; a p2l2 VIP is used only where no official source exists.

**Script:** `script/maintenance_script/test.py`, copied from **`bitvis_vip_gpio`** (official, clock-less signal-level VIP like this one; unlike `bitvis_vip_clock_generator` its script also verifies `compile_src.do` and `compile_bfm.do` on Questa/Riviera) with only these edits:
1. `print('Verify p2l2_vip_rotary_encoder')` (GPIO: `'Verify Bitvis VIP GPIO'`);
2. library `bitvis_vip_gpio` → `p2l2_vip_rotary_encoder` in the three `add_files` calls, comment `# Add GPIO VIP` → `# Add Rotary Encoder VIP`;
3. dependency VIPs: remove the `bitvis_vip_scoreboard` line and change its comment to `# Add util and fw` (no scoreboard, AD/arch §4);
4. DUT: none.

The script must be **started from `p2l2_vip_rotary_encoder/sim`** (create the folder if missing): its cleanup only runs there and HDLRegression writes into the current directory (pitfall F-016/F-019). It deletes `sim/` contents after a passing run (F-014). Run: `cd p2l2_vip_rotary_encoder/sim && python3 ../script/maintenance_script/test.py`, plus HDLRegression's own options for simulator selection.

**Simulators:** GHDL 6.0.0 (fs), NVC 1.23.0 (fs), Questa Starter 2025.3 (`-t ps` from the script). The test values were chosen so that every "exact" criterion is exact at ps. The official script has no NVC branch; NVC runs with HDLRegression's defaults. If NVC needs an option, that is a script change proposed as a deviation in Stage 5.4.

**Companion scripts** (from `bitvis_vip_gpio`, names adapted): `script/compile_src.do`, `script/compile_bfm.do`, `script/compile_order.txt`, `script/README.txt`. `test.py` runs both `.do` scripts on Questa after the HDLRegression run.

## 6. Implementation increments

| Inc | Content | Requirements | Test cases | Expected decisions |
|---|---|---|---|---|
| 1 – BFM core | Types, config, state, `rotary_encoder_init`, motion engine (start/run/halt), edge/detent/angle moves with snap, `get_status`, conversions | REQ-001, 002, 004, 005, 010…016, 020…027, 070, 090…095 | BFM TC_001, 010…014, 020…022, 090…093 | E-1.1 private fields of `t_rotary_encoder_state`; E-1.2 the TB time function (3.4); E-1.3 the BFM reads `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` directly from `adaptations_pkg` (`transaction_pkg` compiles after the BFM, so the alias cannot be used there) |
| 2 – BFM signal options | Swap, inversion, index modes, bounce (cut-off), jitter | REQ-030…032, 040…045, 050…056, 060…063 | BFM TC_030, 031, 040…042, 050…052, 060, 061 | E-2.1 random bounce placement (sorted uniform draws in the window vs. a jittered even grid); E-2.2 jitter-test run time on Questa Starter (10 000 edges) |
| 3 – BFM faults, timed rotation, ramp | `set_angle`, `jump_edges`, glitch, edge offsets, stuck outputs, `rotary_encoder_rotate` (3 overloads: rotation, profile, stop snap), `rotary_encoder_linear_ramp` | REQ-071, 072, 074…079, 080, 115 | BFM TC_070, 071, 073…075, 080, 114 | E-3.1 glitch on a stuck channel (proposal: drive nothing, log it); E-3.2 log format of fault events |
| 4 – VVC commands | Skeleton adaptation, `p_motion`, executor ↔ `p_motion` handshake, moves, fault events, `get_status`/`fetch_result`, terminate during a move, transaction info, logging | REQ-001, 002, 003, 004, 005, 081…085 | VVC TC_001, 002 (moves), 081…084 (083 moves only) | E-4.1 interpreter change for `halt_req` (F-004) – placed in this increment or in Inc 5; E-4.2 transaction info for zero-time commands |
| 5 – VVC rotation | Start, speed change, stop, profiles, rejects, terminate/flush during a rotation, per-edge configuration | REQ-003, 083, 100…114 | VVC TC_002 (rotation), 083 (rotation), 100…113 | E-5.1 `first_edge_ack` when the change falls exactly on an edge time (D-25); E-5.2 terminate with the executor idle vs. a command arriving in the same delta |
| Stage 5.4 | Shared files (Section 7), all simulators, VSG, implementation report | – | All 50 | – |

Stage 5.2 (before Inc 1) creates `rotary_encoder_tb_pkg`, the harness, both testbenches with a placeholder test (logger and checker plumbing on the skeleton VVC) and `test.py`.

## 7. Integration checklist

Precedent: branch `p2l2_vip_pwm` (all commits since `master`, integration commit `bb4b0c91`). `p2l2_vip_mdio` touched the same eight shared files.

### 7.1 VIP's own files

| File | Source | Stage |
|---|---|---|
| `src/rotary_encoder_bfm_pkg.vhd`, `transaction_pkg.vhd`, `vvc_cmd_pkg.vhd`, `vvc_methods_pkg.vhd`, `rotary_encoder_vvc.vhd`, `vvc_context.vhd` | Generator + architecture | 5.1 / Inc 1–5 |
| `tb/maintenance_tb/` (4 files, Section 2) | New | 5.2 / Inc 1–5 |
| `script/maintenance_script/test.py` | `bitvis_vip_gpio`, edits of Section 5 | 5.2 |
| `script/compile_src.do`, `compile_bfm.do`, `compile_order.txt`, `README.txt` | `bitvis_vip_gpio`, names adapted (`compile_order.txt` is read by `script/compile_all.sh`) | 5.1 |
| `LICENSE.TXT`, `README.TXT`, `CHANGES.TXT`, `VERSION.TXT` (`v1.0.0`), `.gitignore` | `bitvis_vip_gpio`, names adapted | 5.1 |
| `doc/*.md` workflow documents | Exist; `doc/evidence/` stays git-ignored | – |

### 7.2 Shared files (scope to approve once)

| # | File | Change (PWM pattern) | Read by / verified with | Stage |
|---|---|---|---|---|
| S-1 | `uvvm_util/src/adaptations_pkg.vhd` | Block `-- ROTARY ENCODER` after RGMII, before SBI: `C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH`, `C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM`, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH := 256` | Every compile; `test.py` | **5.1** (TD-7) |
| S-2 | `script/component_list.txt` | Append `p2l2_vip_rotary_encoder` | `script/compile_all.sh`, `compile_all.do`, `release/update_versions.py`; verified by running the compile-all script | 5.4 |
| S-3 | `misc/context/uvvm_all_context.vhd` | Append `library p2l2_vip_rotary_encoder; context p2l2_vip_rotary_encoder.vvc_context;` | Compile-all (context compile) | 5.4 |
| S-4 | `versions.txt` | Append `p2l2_vip_rotary_encoder, version v1.0.0` (no trailing newline, as the file) | Review | 5.4 |
| S-5 | `vhdl_ls.toml` | Block `p2l2_vip_rotary_encoder.files` (framework `src_target_dependent` + VIP) | Review (editor config) | 5.4 |
| S-6 | `release/code_conventions/uvvm.yaml` | Add `'ROTARY_ENCODER_VVCT'` to `case_exceptions` | VSG run in Stage 5.4 | 5.4 |
| S-7 | `doc/source/index.rst` | `vip_rotary_encoder.rst` after `vip_rgmii.rst` | Sphinx build (Phase 6) | 6 |
| S-8 | `doc/source/vip_rotary_encoder.rst` | New VIP page | Sphinx build (Phase 6) | 6 |

**Merge conflicts:** the `p2l2_vip_pwm` and `p2l2_vip_mdio` branches append at the same places (S-2, S-3, S-4, S-5, S-6, S-7 next to `vip_rgmii`/after `vip_i2c`). Whichever branch merges later resolves trivial line conflicts; S-1 does not conflict (different block positions).

## 8. Simulation-time and run-time notes

- Longest simulated time: TC_101 at 7 rpm, 10 revolutions ≈ 86 s; TC_011 at 7 rpm, 1000 edges ≈ 107 s. Both are event-sparse (~1 000 events), so wall time is small. `time` is 64-bit on all three simulators; 107 s = 1.07·10¹⁷ fs fits.
- Largest event count: TC_060 (10 000 edges) and the bounce tests (≤ 5 events per edge).

## 9. Decisions

| ID | Decision | Proposal | Alternative |
|---|---|---|---|
| TD-1 | Counterpart | Independent decoder checker + event log in the testbench (spec §8), no DUT | Behavioural RTL decoder as a DUT |
| TD-2 | Testbench split | BFM testbench for every signal-level requirement (30 TCs), VVC testbench for framework, command and rotation semantics (20 TCs); the VVC TB spot-checks each move kind through the VVC (TC_081) | Everything through the VVC (slower to debug, BFM-only use untested beyond REQ-080) |
| TD-3 | Start-angle matrix (X-6) | Matrix in the BFM TB; generic path once through instance 3 (30°) | Seven VVC instances |
| TD-4 | Coverage of `rotary_encoder_rotate` (AD-16): no requirement covers it (F-006) | Extend REQ-080 acceptance criteria: the BFM-only testbench also runs `rotary_encoder_rotate` in its three overloads (constant rpm with stop snap, time form, profile with `PROFILE_STOP`) and checks edge times and the end position. **Requirement change after approval → reqs rev 0.5 (proposed)** | Leave it untested (an unverified public procedure fails the audit's API coverage) |
| TD-5 | Checker behaviour | Counts silently; every step ends with an explicit `check_checker` with expected counts | Alerts on every violation, with expected-alert bookkeeping in every error test |
| TD-6 | `test.py` and per-VIP files | **Decided by the user 2026-10-27: official scripts first.** Copy from `bitvis_vip_gpio` with the four permitted edits; started from `<vip>/sim` | PWM's script (rejected: carries four non-official changes) |
| TD-7 | When S-1 (`adaptations_pkg`) is changed | Stage 5.1: the generated `transaction_pkg` aliases the constants, so nothing compiles without them | Stage 5.4 with local constants until then (they would have to be removed again) |
| TD-8 | Expected rpm-form edge times | Exact `time`/`integer` long division for integer rpm (3.4) | One `real` formula (≈ 16 fs error at 86 s, larger than the fs tolerance) |
