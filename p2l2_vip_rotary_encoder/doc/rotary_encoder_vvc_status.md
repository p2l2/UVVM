# Rotary Encoder VVC – Status

## 1. Current state
- **Phase:** **Phase 5 – Implementation and verification**, Stage 5.3 – Increments. Increments 1 and 2 approved (code committed by the user: `8b333d5d`, `a482f55a`, `27e50a52`).
- **Document migration done 2026-11-11:** `rotary_encoder_vvc_design.md` rev 0.2 (incl. new REQ-086) and spec rev 0.12 approved; old reqs/arch/tb arch files and the revision copies in `doc/evidence/` deleted. The user commits the `doc/` changes as a separate commit.
- **Next step:** Stage 5.3 – Increment 3: BFM faults, timed rotation, ramp — `set_angle`, `jump_edges`, glitch, edge offsets, stuck outputs, `rotary_encoder_rotate` (3 overloads), `rotary_encoder_linear_ramp`, status fields of REQ-086 (BFM part); test cases `set_angle_and_jump_edges`, `glitch`, `invalid_fault_event`, `edge_offsets`, `stuck_outputs`, `bfm_only_flow_and_rotate`, `linear_ramp`, plus the offset steps of `center_state` and `invalid_jitter` and the status fields in `move_angle`; expected decisions E-3.1, E-3.2; NVC regression.
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
| Design document | `doc/rotary_encoder_vvc_design.md` | 0.2 | Approved 2026-11-11. 72 features, decision log D-1…D-85, no open questions |
| Implementation report | `doc/rotary_encoder_vvc_implementation_report.md` | 0.7 | Stages 5.1, 5.2, Inc 1 (§3), Inc 2 (§4); section references point to the design document |
| Findings log | `doc/rotary_encoder_vvc_findings.md` | – | 23 entries |
| Documentation | – | – | not started |
| Audit | – | – | not started |

## 6. Approvals
| Phase / stage | Date | Approval |
|---|---|---|
| Startup gate – workspace and UVVM baseline | 2026-10-21 | Confirmed |
| Phase 1 – Protocol specification | 2026-11-11 | rev 0.12 approved |
| Phase 2 – VVC features | 2026-11-11 | approved (design rev 0.2, REQ-086 added) |
| Phase 3 – VVC architecture | 2026-11-10 | approved (now design §4–§6) |
| Phase 4 – Testbench architecture | 2026-11-10 | approved (now design §7–§9) |
| Document migration to `_vvc_design.md` | 2026-11-11 | approved |
| Stage 5.1 – Generate skeleton | 2026-10-27 | approved, `7f22761b` |
| Stage 5.2 – First testbench and regression script | 2026-10-27 | approved, `1418078c` |
| Stage 5.3 – Increment 1: BFM core | 2026-11-09 | approved, `8b333d5d` |
| Stage 5.3 – Increment 2: BFM signal options | 2026-11-10 | approved, `a482f55a`, `27e50a52` |

## 7. Latest checks
- Inc 2 (2026-11-10): NVC PASS 24 tests (23 BFM, 1 VVC), `doc/evidence/inc2/regression_nvc_tb_literals.log`. GHDL/Questa NOT RUN (Stage 5.4). VSG BLOCKED (F-022)
- Document migration: checked by script – 72 features after REQ-086 (9 Critical, 28 High, 28 Medium, 7 Low); every decision referenced in the design body exists in the log; no revision markers in the body

## 8. Open items
- REQ-086 status read-back: BFM part in Inc 3, VVC part in Inc 4, rotation part in Inc 5
- Inc 3–5 and Stage 5.4 expected decisions and notes: design §8 (E-3.1 … E-5.3, E-2.2, F-021, F-022, `p_motion` request detection by index)
- REQ-033 crossed-wiring example: verified by the documentation example in Phase 6 – Documentation
