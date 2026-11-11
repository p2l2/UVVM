# Rotary Encoder VVC – Status

## 1. Current state
- **Phase:** **Phase 5 – Implementation and verification**, Stage 5.3 – Increments. Increments 1, 2 and 3 approved. Committed by the user: Inc 1 `8b333d5d`, Inc 2 `a482f55a`, `27e50a52`, design migration `b0a3d588`; Inc 3 not committed yet (the user commits).
- **Increment 3 – BFM faults, timed rotation, ramp:** approved 2026-11-11 incl. D-89 to D-94. Afterwards: unused `last_rpm` removed, new test case `linear_ramp_rotation` (design rev 0.4, approved 2026-11-11) — NVC 32/32.
- **Next step:** Stage 5.3 – Increment 4: VVC commands — skeleton adaptation, `p_motion`, executor ↔ `p_motion` handshake, moves (incl. move to state), centre state, fault events, `get_status`/`fetch_result`, terminate during a move, zero-state check, transaction info, logging; VVC test cases of Inc 4 (design §7.4); expected decisions E-4.1, E-4.2; NVC regression.
- **Last updated:** 2026-11-11

## 2. Workspace
- Mode: in-tree
- UVVM checkout / Git root: `/home/rhintersteininger/Repositories/p2l2/UVVM` (origin `git@github.com:p2l2/UVVM.git`)
- Branch: `p2l2_vip_rotary_encoder`. Base commit `90d56e93` (= `master`, UVVM PR #300)
- Version evidence: no tags. `versions.txt`: uvvm_util v2.21.4, uvvm_vvc_framework v2.12.15. Baseline confirmed by the user 2026-10-21
- Output dir: `p2l2_vip_rotary_encoder/` (library `p2l2_vip_rotary_encoder`, D-34)
- `<doc_dir>`: `p2l2_vip_rotary_encoder/doc/`
- `<evidence_dir>`: `p2l2_vip_rotary_encoder/doc/evidence/` (git-ignored via `doc/evidence/.gitignore`)
- `<protocol_id>`: `rotary_encoder`
- Related work: `p2l2_vip_pwm` on branch `p2l2_vip_pwm` (not merged); structural reference and integration precedent (commit `bb4b0c91`)
- Untracked leftovers `p2l2_vip_pwm/sim`, `p2l2_vip_mdio/sim` in the working tree: from other branches, not touched
- Generator: `uvvm_vvc_framework/script/vvc_generator/vvc_generator.py`

## 3. Toolchain (probed 2026-10-21)
| Tool | Version | Status |
|---|---|---|
| GHDL | 6.0.0 | works |
| NVC | 1.23.0 (LLVM 23.1.1) | works (after the user's fix, F-001) |
| Questa Altera Starter FSE | 2025.3 | works (license OK) |
| Riviera-PRO | – | not installed |
| Python / HDLRegression | 3.14.7 / 1.6.0 | works |
| sphinx-build | 9.1.0 | works |
| VSG | 3.29.0 | works; rejects `uvvm.yaml` (F-022, Stage 5.4) |

## 4. Settings
- Role: encoder only; scope and defaults in design §2
- Implementation mode: **one-shot** with a pause at each increment boundary (chosen 2026-10-27)
- Development simulator: **NVC 1.23.0** (Stages 5.2–5.3); Stage 5.4 runs GHDL, NVC, Questa
- Commit policy: **user commits** (I stop at boundaries, never commit or push), chosen 2026-10-27
- Shared-file scope: S-1 to S-8 approved (design §9.2; S-1 done in Stage 5.1, S-2 to S-6 in Stage 5.4, S-7/S-8 in Phase 6)
- Scripts: official first (user rule 2026-10-27), from `bitvis_vip_gpio`. Regression from `p2l2_vip_rotary_encoder/sim`: `python3 ../script/maintenance_script/test.py -s NVC -fr -v`

## 5. Artifacts
| Artifact | Path | Rev | Status |
|---|---|---|---|
| Specification | `doc/rotary_encoder_spec.md` | 0.12 | Approved 2026-11-11 |
| Design document | `doc/rotary_encoder_vvc_design.md` | 0.4 | D-86 to D-94 approved 2026-11-11 (REQ-072, 075, 110 changed); rev 0.4: test case `linear_ramp_rotation`. 72 features, decision log D-1…D-94 |
| Implementation report | `doc/rotary_encoder_vvc_implementation_report.md` | 0.9 | Stages 5.1, 5.2, Inc 1 (§3), Inc 2 (§4), Inc 3 (§5) |
| Findings log | `doc/rotary_encoder_vvc_findings.md` | – | 25 entries |
| Documentation | – | – | not started |
| Audit | – | – | not started |

## 6. Approvals
| Phase / stage | Date | Approval |
|---|---|---|
| Startup gate – workspace and UVVM baseline | 2026-10-21 | Confirmed |
| Phase 1 – Protocol specification | 2026-11-11 | rev 0.12 approved |
| Phase 2 – VVC features | 2026-11-11 | approved (design rev 0.2, REQ-086 added); change after approval rev 0.3 (REQ-072, 075, 110) approved 2026-11-11 |
| Phase 3 – VVC architecture | 2026-11-10 | approved (now design §4–§6) |
| Phase 4 – Testbench architecture | 2026-11-10 | approved (now design §7–§9) |
| Document migration to `_vvc_design.md` | 2026-11-11 | approved |
| Stage 5.1 – Generate skeleton | 2026-10-27 | approved, `7f22761b` |
| Stage 5.2 – First testbench and regression script | 2026-10-27 | approved, `1418078c` |
| Stage 5.3 – Increment 1: BFM core | 2026-11-09 | approved, `8b333d5d` |
| Stage 5.3 – Increment 2: BFM signal options | 2026-11-10 | approved, `a482f55a`, `27e50a52` |
| Stage 5.3 – Increment 3: BFM faults, timed rotation, ramp | 2026-11-11 | approved (incl. D-89 to D-94); commit by the user pending |

## 7. Latest checks
- Inc 3 (2026-11-11): NVC PASS 32 tests (31 BFM, 1 VVC), `doc/evidence/inc3/regression_nvc_ramp_rotation.log`. GHDL/Questa NOT RUN (Stage 5.4). VSG BLOCKED (F-022)

## 8. Open items
- REQ-086 status read-back: BFM part done (Inc 3), VVC part in Inc 4, rotation part in Inc 5
- `rotary_encoder_run_motion` rotation/profile path (`MOTION_PROFILE_PASS`, 0 rpm wait) is implemented but only tested through the VVC (Inc 5)
- Inc 3–5 and Stage 5.4 expected decisions and notes: design §8 (E-3.1 … E-5.3, E-2.2, F-021, F-022, `p_motion` request detection by index)
- REQ-033 crossed-wiring example: verified by the documentation example in Phase 6 – Documentation
