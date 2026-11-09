# Rotary Encoder VVC – Status

## 1. Current state
- **Phase:** **Phase 1 – Protocol specification reopened** (change after approval, 2026-10-28): the user removes detents and snapping completely (Q-09). Spec rev 0.7 proposed, awaiting approval. Phase 5 is paused at Stage 5.3 – Increment 1: BFM core (done, not approved, uncommitted; contains detent code that must be removed). Arch rev 0.5 (§6.2, F-010) still unapproved.
- **Next step:** approval of spec rev 0.7, then cascade: Phase 2 – Verification requirements (remove/rewrite detent REQs), Phase 3 – VVC architecture (remove detent API/config, fold in rev 0.5), Phase 4 – Testbench architecture (detent TCs), then rework Stage 5.3 – Increment 1 (BFM, tb) and rerun NVC regression. After that: Stage 5.3 – Increment 2: BFM signal options.
- **Last updated:** 2026-10-28

## 2. Workspace
- Mode: in-tree
- UVVM checkout / Git root: `/home/rhintersteininger/Repositories/p2l2/UVVM` (origin `git@github.com:p2l2/UVVM.git`)
- Branch: `p2l2_vip_rotary_encoder` (the user approved switching to it). Base commit `90d56e93` (= `master`, UVVM PR #300). Re-verified 2026-10-27
- Version evidence: no tags. From `versions.txt`: uvvm_util v2.21.4, uvvm_vvc_framework v2.12.15. The user confirmed the baseline on 2026-10-21
- Output dir: `p2l2_vip_rotary_encoder/` (library `p2l2_vip_rotary_encoder`, AD-2 approved)
- `<doc_dir>`: `p2l2_vip_rotary_encoder/doc/`
- `<evidence_dir>`: `p2l2_vip_rotary_encoder/doc/evidence/` (git-ignored via `doc/evidence/.gitignore`)
- `<protocol_id>`: `rotary_encoder`
- Related work: `p2l2_vip_pwm` lives on branch `p2l2_vip_pwm` (not merged to master). It is a structural-reference candidate and integration precedent (commit `bb4b0c91`). Its `pwm_start`/`pwm_update`/`pwm_stop` (separate waveform process, executor stays free) is the precedent for continuous rotation
- Untracked leftovers `p2l2_vip_pwm/sim`, `p2l2_vip_mdio/sim` in the working tree: simulation output from other branches, not touched
- Generator: `uvvm_vvc_framework/script/vvc_generator/vvc_generator.py`

## 3. Toolchain (probed 2026-10-21)
| Tool | Version | Status |
|---|---|---|
| GHDL | 6.0.0 | works (smoke test) |
| NVC | 1.23.0 (LLVM 23.1.1) | works (smoke test after the user's fix, F-001) |
| Questa Altera Starter FSE | 2025.3 | works (smoke test, license OK) |
| Riviera-PRO | – | not installed |
| Python / HDLRegression | 3.14.7 / 1.6.0 | works |
| sphinx-build | 9.1.0 | works |
| VSG | 3.29.0 | works |

## 4. Settings
- Role: encoder only. All features are included and optional for the user: index on by default (detents removed in spec rev 0.7); bounce, jitter, error generation, direction swap and polarity inversion off by default
- Use cases (Phase 3): U-1 discrete moves **and** continuous rotation with optional time-based speed profiles (rotation only). U-2 state read-back only if it adds little complexity (decide in Phase 3). U-3 one encoder per DUT (REQ-083 multi-instance stays). U-4 structural references `bitvis_vip_clock_generator` + `p2l2_vip_pwm` (continuous mode), `bitvis_vip_gpio` optional; all official VVCs as coding-convention reference. All answered 2026-10-27
- Step-by-step / one-shot: **one-shot** (pause at Stage 5.1, 5.2 and each increment boundary), chosen 2026-10-27
- Development simulator: **NVC 1.23.0** (Stages 5.2–5.3); Stage 5.4 runs GHDL, NVC, Questa
- Commit policy: **user commits** (I stop at boundaries, never commit or push), chosen 2026-10-27
- Shared-file scope: S-1 to S-8 approved with Phase 4 and reconfirmed 2026-10-27 (tb arch §7.2; S-1 `adaptations_pkg` in Stage 5.1 per TD-7, S-2 to S-6 in Stage 5.4, S-7/S-8 in Phase 6)
- Scripts: official first (user rule 2026-10-27): `test.py`, `.do` scripts, `compile_order.txt`, per-VIP TXT files from `bitvis_vip_gpio`; `test.py` is started from `p2l2_vip_rotary_encoder/sim`
- Generator answers (approved, arch §11): name `rotary_encoder`, extended y, scoreboard n, transaction info y, UAD n, channels 1, multiple executors n

## 5. Artifacts
| Artifact | Path | Rev | Status |
|---|---|---|---|
| Specification | `doc/rotary_encoder_spec.md` | 0.7 | 0.6 approved 2026-10-27; 0.7 proposed 2026-10-28 (detents removed, zero state (renamed from rest state, A-06) and start angle A-16 kept configurable, Q-09). Copy of 0.6: `doc/evidence/rotary_encoder_spec_rev0.6.md` |
| Requirements | `doc/rotary_encoder_vvc_reqs.md` | 0.5 | Approved 2026-10-27 (77 active + 1 withdrawn, D-1 to D-30; rev 0.5: REQ-080 covers `rotary_encoder_rotate`) |
| VVC architecture | `doc/rotary_encoder_vvc_arch.md` | 0.5 | 0.4 approved 2026-10-27 (AD-1 to AD-17); 0.5 proposed (§6.2 exact tpe for integer rpm divisor, F-010) |
| Testbench architecture | `doc/rotary_encoder_vvc_tb_arch.md` | 0.2 | Approved 2026-10-27 (TD-1 to TD-8; 30 BFM + 20 VVC test cases; 5 increments; S-1 to S-8) |
| Implementation report | `doc/rotary_encoder_vvc_implementation_report.md` | 0.3 | Stages 5.1, 5.2, Inc 1 written |
| Findings log | `doc/rotary_encoder_vvc_findings.md` | – | 14 entries |
| Documentation | – | – | not started |
| Audit | – | – | not started |

## 6. Approvals
| Phase | Date | Approval |
|---|---|---|
| Startup gate – workspace and UVVM baseline | 2026-10-21 | The user confirmed the checkout, branch (a), folders and NVC fix |
| Phase 1 – Protocol specification | 2026-10-27 | rev 0.6 approved ("approved") |
| Phase 2 – Verification requirements | 2026-10-27 | rev 0.4 approved, D-25 to D-30 accepted |
| Phase 3 – VVC architecture | 2026-10-27 | rev 0.4 approved ("accept all, approved, start Phase 4") |
| Phase 4 – Testbench architecture | 2026-10-27 | rev 0.2 approved ("TD-6: always use the official scripts first. Then I approve Phase 4"), incl. reqs rev 0.5 |

## 7. Latest checks
- Stage 5.1 (2026-10-27): generator run PASS, skeleton approved and committed (`7f22761b`)
- Stage 5.2 (2026-10-27, approved, committed `1418078c`): NVC regression PASS, 2 tests (`rotary_encoder_bfm_tb.TC_000`, `rotary_encoder_vvc_tb.TC_000`), evidence `doc/evidence/stage5_2/regression_nvc_verbose.log`. GHDL/Questa NOT RUN (Stage 5.4). Run from `p2l2_vip_rotary_encoder/sim`: `python3 ../script/maintenance_script/test.py -s NVC -fr`
- Inc 1 (2026-10-27): NVC regression PASS, 15 tests, evidence `doc/evidence/inc1/regression_nvc_verbose.log`

## 8. Open items
- F-004: the VVC interpreter halts a background rotation itself on `terminate_current_command` (arch §7.2) – implement in Stage 5.3
- Inc 1–5 expected decisions E-1.1 … E-5.2 listed in tb arch §6
