# Rotary Encoder VVC – Verification Requirements

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_vvc_reqs.md` |
| Revision | 0.5 |
| Status | **Approved 2026-10-27** (rev 0.5; changes are marked *rev 0.4 proposed* / *rev 0.5 proposed* for traceability, all approved) |
| Source | `rotary_encoder_spec.md` rev 0.6 (approved 2026-10-27) |
| Role | **Encoder** only (the VVC drives A/B/Z into a DUT). Every requirement applies to this role |

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-21 | Initial draft |
| 0.2 | 2026-10-21 | REQ-001: checked by the testbench, not the VVC. Index enabled by default (REQ-002, REQ-040/041). New angle movement (REQ-090 to 095) and detent switch/snap (REQ-024 to 027). Centre-of-state timing (REQ-012/013, D-1 revised, F-002). The user accepted D-2 to D-10. `t_edge` renamed to `time_per_edge`. `t_edge_min` removed: REQ-016, 061, 063, 070 adapted, REQ-073 withdrawn, D-5 and D-8 obsolete. Start angle replaces the start state (REQ-002, new REQ-005) |
| 0.3 | 2026-10-27 | Change after approval, requested by the user (spec rev 0.5). Continuous rotation: new §11b, REQ-100 to REQ-110. Speed profile over time: REQ-111 to REQ-115. Physical speed in rpm with `time_per_edge` as alternative form (D-19): REQ-012, REQ-013, REQ-016, REQ-025, REQ-085, REQ-092, REQ-095 adapted. Jitter in electrical degrees (REQ-061, REQ-063, D-21), bounce cut-off (REQ-054 adapted, new REQ-056, D-22). REQ-003, REQ-070, REQ-083 extended to rotations. Decisions D-11 to D-24 decided by the user |
| 0.4 | 2026-10-27 | Approved 2026-10-27. Proposed with `rotary_encoder_vvc_arch.md` rev 0.1 (requirements cross-check X-1 to X-5): REQ-082 reworded for the angle model (stop at once, as D-13); REQ-054 and D-9 for bounce pulses; REQ-091 note on angle quantisation; REQ-111/REQ-114 maximum profile length 256; new D-25 (edge at a boundary is emitted first, F-003). Spec rev 0.6 (device faults): REQ-001, REQ-063, REQ-070, REQ-071 (set angle and jump replace the illegal transition), REQ-074, REQ-085, REQ-105 adapted; new REQ-075 to REQ-079 (edge offsets, stuck outputs); D-3 generalized; new D-26 to D-30 |
| 0.5 | 2026-10-27 | Approved 2026-10-27 with Phase 4. Proposed with `rotary_encoder_vvc_tb_arch.md` rev 0.1 (TD-4, F-006): REQ-080 acceptance criteria extended to `rotary_encoder_rotate` (AD-16), which no requirement covered |

## 1. Scope

**Selected (user, 2026-10-21):** encoder role only. All optional spec features are included. Index and detent modelling are **on** by default; bounce, jitter, error generation, direction swap and polarity inversion are **off** by default and enabled by the user.

**Out of scope**

| Item | Reason |
|---|---|
| Receiver role (observing A/B/Z from a DUT, spec §8 decoder semantics) | The user excluded it. The VVC is used to stimulate DUT decoders. Spec §8 still defines what a correct decoder infers, so it serves as the expected-behaviour reference for the testbench checker (Phase 4) |
| Push-button switch | Spec §9, handled by a GPIO VVC |
| Everything else in spec §9 | See the spec |

## 2. Conventions

- **Priority:** *Critical* means the VVC is useless without it. *High* means it's needed for normal use or required by UVVM conventions. *Medium* means an optional feature or diagnostic. *Low* means nice to have.
- **Method:** *Sim* means a self-checking simulation test, using a checker in the testbench that is independent of the BFM (designed in Phase 4). *Review* means a code or documentation review.
- **Status:** REQ-001 to REQ-095 are *Approved* (2026-10-21). The new and changed requirements of rev 0.3 and rev 0.4 are *Approved* (2026-10-27). They become *Implemented* and *Verified* in Phase 5.
- **Timing tolerance:** "exact" means equal within one simulator time-resolution step.
- **Alerts:** severities follow UVVM (`TB_ERROR` for an invalid user call, `TB_WARNING` for questionable but executable use). Severities marked "configurable" are VVC configuration fields.
- Requirements marked **(D-n)** depend on a proposed decision in Section 10.

## 3. Signals, initial state, continuity

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-001 | The VVC drives the outputs `A` and `B` and the optional output `Z` with strong `'0'`/`'1'` levels only; the only exception is an output configured as stuck at `'Z'` (REQ-078). This is a property of the drive logic; the VVC does **not** check its own outputs at runtime. *(rev 0.4 proposed)* | Critical | §3, A-01, A-26 | The testbench checker (not the VVC) verifies that after initialization no output carries a value other than `'0'`/`'1'`, on every event in every test that does not configure a stuck `'Z'`. | Sim (testbench checker) | TC-001 |
| REQ-002 | At initialization and before any movement, the VVC drives the state and the Z level that follow from the configured start angle (default 0°, i.e. `AB = 11`, position 0, Z active with the default index configuration). | Critical | §7, A-16 | At the first delta after VVC initialization, `AB` and Z equal the values the checker's model computes for the start angle. Run with the defaults (`AB = 11`, Z active) and with start angles −10°, 30° and 400°, with detents on and off. | Sim | TC-001 |
| REQ-003 | While no move and no rotation is active, A, B and Z hold their last value indefinitely. | Critical | §4.4 | No event on A/B/Z during an `insert_delay` or an idle period of ≥ 100 × `time_per_edge`, after a move and after a stopped rotation. | Sim | TC-002 |
| REQ-004 | Each movement starts from the state and position at which the previous one ended (continuity). | Critical | §4.2, §7 | Over a sequence of mixed forward/reverse movements, every transition is legal (one channel per edge), including at command boundaries. The checker's position equals the expected sum. | Sim | TC-002 |
| REQ-005 | With detent modelling on, the start angle is placed on the nearest detent (on a tie, the one in the positive direction). No edge is emitted; this is the power-up state. | High | §7, A-16 | Defaults, start angle 30°: detents on gives `AB = 11` at position 8 (36°) with Z inactive; detents off gives position 7 (30°) with Z inactive. No event on A/B before the first movement. | Sim | TC-001 |

## 4. Movements

Speeds are given in rpm (primary) or as `time_per_edge` (alternative, spec §4.4). "Time form" below means the speed was given as `time_per_edge`; "rpm form" means it was given in rpm and `time_per_edge` is derived (A-23).

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-010 | A forward movement of N edges produces exactly N edges following the forward Gray sequence `00→10→11→01→00` (A leads B). | Critical | §4.1, A-02 | The checker counts exactly +N edges and every transition is legal and forward. N ∈ {1, 2, 3, 4, 5, 1000}, from all four states (start angles 0°, 4.5°, 9°, 13.5° with detents off). | Sim | TC-010 |
| REQ-011 | A reverse movement of N edges produces exactly N edges following the reverse sequence `00→01→11→10→00`. | Critical | §4.1 | As REQ-010 with −N. | Sim | TC-010 |
| REQ-012 | Edge timing: without jitter, an edge move of N edges that starts in the centre of a state emits its edges at (k − ½) × `time_per_edge` after the start, k = 1..N. The move ends in the centre of the new state, and the command completes N × `time_per_edge` after it started. Each edge time is computed from the exact model and rounded once (A-24). **(D-1)** | Critical | §4.4, §4.6, A-04, A-13, A-23, A-24 | Time form: first edge exactly `time_per_edge`/2 after the start; every further edge-to-edge interval exactly `time_per_edge`, including across back-to-back commands with the same speed and across direction changes; command duration exactly N × `time_per_edge`. Tested with `time_per_edge` ∈ {1 ns, 1 µs, 1 ms}. Rpm form: 7 rpm and 6000 rpm at 20 cycles/rev, N = 1000: every edge within one resolution step of `t_s` + (k − ½) × 60 s / (rpm × 80), no growing deviation, command duration within one step of N × `time_per_edge`. | Sim | TC-011 |
| REQ-013 | Speed curves from moves: consecutive movements with different speeds are executed back to back without extra delay. | High | A-04 | The interval between the last edge of movement k and the first edge of movement k+1 equals (`time_per_edge`(k) + `time_per_edge`(k+1)) / 2: exactly in the time form, within two resolution steps in the rpm form. | Sim | TC-011 |
| REQ-014 | Direction reversal between consecutive movements goes back along the reverse transition from the current state, including in the middle of a cycle. | Critical | §4.2 | Forward 1 edge, then reverse 1 edge, repeated 10 times from each of the four states: every transition is legal and the final position equals the start position. | Sim | TC-012 |
| REQ-015 | A movement of 0 edges produces no edge and completes without consuming time. **(D-6)** | Low | – (boundary) | No event on A/B/Z and the command completes at the current time. | Sim | TC-013 |
| REQ-016 | Invalid movement speeds are rejected with `TB_ERROR` and no edge is produced: `time_per_edge` ≤ 0 ns, or rpm ≤ 0 or not finite (the direction of a move is a separate argument). Any positive speed is allowed, also one too fast for a DUT decoder. | High | §4.4 | Each invalid call raises exactly one `TB_ERROR` (counted via the expected-alert mechanism) and the outputs do not change. | Sim | TC-014 |

## 5. Detents

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-020 | With detent modelling on, a movement of N detents produces N × `edges_per_detent` edges in the requested direction. | High | §5.1 | The checker counts ±N × `edges_per_detent` edges for `edges_per_detent` ∈ {1, 2, 4}, both directions. | Sim | TC-020 |
| REQ-021 | Started from a rest state, a detent movement ends in a rest state. The rest states are the configured rest state (A-06, default `11`) and every state that is a multiple of `edges_per_detent` edges away from it. | High | §5.1, A-06 | After each detent movement, `AB` is a rest state, for all `edges_per_detent` values and each of the 4 rest-state settings. | Sim | TC-020 |
| REQ-022 | When a detent movement starts while the encoder is not in a rest state (after an edge movement that stopped between detents), the VVC raises an alert (configurable severity, default `TB_WARNING`) and still executes N × `edges_per_detent` edges. **(D-7)** | Medium | §5.1, §7 | Exactly one alert of the configured severity is raised and the edge count is correct. No alert when starting from a rest state. | Sim | TC-021 |
| REQ-023 | `edges_per_detent` ∉ {1, 2, 4}, or a configured rest state that isn't a 2-bit state, is rejected with `TB_ERROR` when a detent movement is executed. | High | §5.1 | One `TB_ERROR` per invalid call. No edges are produced. | Sim | TC-021 |
| REQ-024 | Detent modelling can be switched on (default) and off. When off, a detent movement is rejected with `TB_ERROR`, angle moves do not snap, and REQ-022 does not apply. | High | A-14 | With detents off: one `TB_ERROR` per detent movement and no edges. An angle move ends at exactly the requested angle. | Sim | TC-022 |
| REQ-025 | With detent modelling on, after an angle move the shaft snaps to the nearest detent within the same command. The snap emits the edges between the reached angle and that detent (forward or reverse), at the move's speed. | High | A-14, A-15 | Defaults (4.5°/edge, 18°/detent) from the detent at 0°: a 10° move gives 2 forward edges, then 2 forward snap edges, and ends at 18°. A 7° move gives 2 forward edges, then 2 reverse snap edges, and ends at 0°. A 1° move gives no edge and ends at 0°. Edge times match the constant-speed timing. | Sim | TC-022 |
| REQ-026 | Exactly halfway between two detents, the snap goes in the direction of the move. | Medium | A-14 | A 9° forward move ends at 18°. A 9° reverse move ends at −18°. | Sim | TC-022 |
| REQ-027 | Edge moves never snap, also with detent modelling on. | High | A-14 | With detents on, an edge move of 1 edge produces exactly 1 edge and ends between detents. | Sim | TC-022 |

## 6. Direction convention and polarity

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-030 | With direction swap enabled, a forward movement follows the sequence in which **B leads A** (and reverse becomes A leads B). | High | A-02 | With swap enabled, the checker (using the A-leads-B convention) counts −N for a forward movement of N edges. | Sim | TC-030 |
| REQ-031 | With A/B polarity inversion enabled, A and B are driven inverted. All logical states (rest state, index state) keep their logical meaning. | High | A-03 | Inverted outputs equal `not` of the non-inverted run, edge for edge (same stimulus, compared within one testbench). | Sim | TC-031 |
| REQ-032 | With index polarity inversion enabled, Z is active low. | Medium | A-10 | Z equals `not` of the non-inverted run. | Sim | TC-031 |

## 7. Index pulse

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-040 | With index disabled, Z stays at its inactive level. | High | §6 | No event on Z over a test that runs several revolutions with index disabled. | Sim | TC-040 |
| REQ-041 | With index enabled (default, `cycles_per_rev` = 20), Z is active exactly once per revolution, i.e. once every 4 × `cycles_per_rev` edges, at the configured index position, in both directions. | High | §6 | Over ≥ 3 revolutions forward and ≥ 3 reverse, Z activates once per revolution and only at the index cycle. Tested with `cycles_per_rev` ∈ {1, 3, 24} and two index positions. | Sim | TC-040 |
| REQ-042 | Gated ¼ cycle (default mode): Z is active exactly while `AB` is in the configured index state (default `11`) of the index cycle. | High | §6, A-10 | Z rises and falls at the same simulation time as the A/B edges that enter and leave the index state. | Sim | TC-041 |
| REQ-043 | Gated ½ cycle: Z is active while `AB` is in the index state or in the state that follows it in the forward direction, within the index cycle. **(D-2)** | Medium | §6, A-10 | As REQ-042, over 2 states. | Sim | TC-041 |
| REQ-044 | Ungated 1 cycle: Z is active for the whole index cycle (4 states). | Medium | §6, A-10 | As REQ-042, over 4 states. | Sim | TC-041 |
| REQ-045 | `cycles_per_rev` < 1 with index enabled is rejected with `TB_ERROR`. | Medium | §6 | One `TB_ERROR` per invalid call. | Sim | TC-042 |

## 8. Contact bounce

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-050 | With bounce disabled (default), each edge is a single transition. | High | A-07 | Number of events on A plus B equals the number of edges. | Sim | TC-050 |
| REQ-051 | With bounce enabled, after each nominal edge the changing channel toggles a configured number of extra times (always even) within `t_bounce`, then settles at the new value. The other channel does not change. | Medium | §5.2, A-07 | Per edge: 1 + the configured number of extra toggles on the changing channel, all within [edge, edge + `t_bounce`]. No event on the other channel. Final value correct. | Sim | TC-050 |
| REQ-052 | Bounce never shifts the nominal edges: nominal edge-to-edge timing stays as REQ-012. | Medium | §5.2 | The first toggle of each edge occurs at the REQ-012 time. | Sim | TC-050 |
| REQ-053 | Bounce placement: *random* (default when bounce is enabled) is reproducible for the same seed. *Even* places the toggles at equal spacing within `t_bounce`. | Medium | A-08 | Two runs with the same seed produce identical toggle times. In even mode, the spacing is `t_bounce` / (extra toggles + 1) ± 1 resolution step. | Sim | TC-051 |
| REQ-054 | `t_bounce` ≤ 0 ns with bounce enabled is rejected with `TB_ERROR`. The bounce amount is a number of bounce pulses (`natural`, 2 toggles each), so an odd or negative toggle count cannot be expressed. **(D-9)** *(rev 0.4 proposed)* | Medium | A-07 | One `TB_ERROR` per invalid call. | Sim | TC-052 |
| REQ-055 | Z follows the nominal A/B state and does not bounce. **(D-4)** | Low | §5.2, §6 | With bounce and index enabled, Z has exactly 2 events per index pulse. | Sim | TC-050 |
| REQ-056 | If the next nominal edge comes before the bounce window has ended (high speed, or a speed change during the window), the bounce is cut off: the bouncing channel is at its settled value before the next edge and the remaining toggles are dropped. An alert of configurable severity (default `TB_WARNING`) reports this once per move or rotation command. All transitions stay legal. **(D-22)** | Medium | §5.2, A-07 | `t_bounce` = 2 × `time_per_edge` with 4 extra toggles: each edge is preceded by a settled channel, no transition is illegal, the edge count is correct, and exactly one alert per command is raised. | Sim | TC-052 |

## 9. Edge jitter

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-060 | With jitter disabled (default), timing is as in REQ-012. | High | A-05 | Covered by TC-011. | Sim | TC-011 |
| REQ-061 | With jitter enabled (amplitude *j* in electrical degrees, 0 ≤ *j* < 45°), each edge is displaced from its ideal time by a uniformly distributed offset in [−*j*/90, +*j*/90] × `time_per_edge` at the current speed. The offset only moves that edge; the following edges keep their ideal times. **(D-10, D-21)** | Medium | A-05 | Over 10 000 edges at constant speed: every displacement lies within ±*j*/90 × `time_per_edge` (+ one resolution step), the mean displacement is within ±*j*/900 × `time_per_edge`, and both bounds are reached within 5 % of the amplitude. The edge count over the run is exact (no drift). The same *j* at 60 rpm and 600 rpm gives displacements that scale with `time_per_edge`. | Sim | TC-060 |
| REQ-062 | Jitter is reproducible for the same seed. | Medium | A-05 | Two runs with the same seed produce identical edge times. | Sim | TC-060 |
| REQ-063 | *j* < 0°, or *j* ≥ half the width of the narrowest state (45° electrical without edge offsets, REQ-076), is rejected with `TB_ERROR`. *(rev 0.4 proposed)* | Low | A-05, A-25 | One `TB_ERROR` per invalid call: *j* = 45° without offsets; *j* = 30° with a B offset of +30° (narrowest state 60°). *j* = 29° with that offset is accepted. | Sim | TC-061 |

## 10. Device faults and fault events

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-070 | Without configured device faults, normal movements (edge, detent and angle moves, rotations) never produce an illegal transition or a glitch. Bounce toggles (REQ-051) are intended and are not glitches. *(rev 0.4 proposed)* | Critical | §4.5 | The checker reports no violation over all non-error tests. | Sim | all |
| REQ-071 | On request, the VVC places the shaft in zero time: **set angle** to an absolute angle in degrees, optionally replaced by the nearest detent (`use_detent`, default false; tie: positive direction; `TB_ERROR` if detent modelling is off), or **jump** N edges in a given direction from the angle at execution time (sub-edge fraction kept, no snap). The position follows the new angle, and the outputs change from the old to the new state in one delta cycle. No bounce or jitter is applied, and Z takes the level of the new state. Setting the current angle again is a no-op. On a boundary, the shaft is in the state on the side of the old angle. **(D-3, D-30)** *(rev 0.4 proposed)* | Medium | §4.3, A-12 | Jump, from each of the four states: N = 2 gives events on A and B in the same delta cycle (illegal transition); N = 4 gives no event on A/B and the position changes by ±4; N = 1 and N = 3 give one event on one channel; N = 80 at the default 20 cycles/rev gives no A/B event and no Z pulse. Set angle: from position 5, 0° gives `AB` = reference state, Z active (default index) and status position 0; 30° gives position 7 and angle 30°; 30° with `use_detent` gives position 8 (36°); 27° with `use_detent` (tie) gives 36°; `use_detent` with detents off raises one `TB_ERROR` and changes nothing; 2.25° from 0° keeps the state at 0° (boundary, old side). Afterwards the status equals the expected value, and normal movements continue legally from the new state with the index position consistent. Zero simulation time passes. | Sim | TC-070 |
| REQ-072 | On request, the VVC produces a **glitch**: a pulse of configurable width on A or B, after which the channel returns to its previous value. Position and state are unchanged afterwards. | Medium | §4.3, A-12 | Exactly 2 events on the selected channel, `width` apart. No event on the other channel. Subsequent movements are unaffected. | Sim | TC-071 |
| REQ-073 | *Withdrawn in rev 0.2: closely spaced edges are an ordinary move with a high speed (REQ-016).* | – | – | – | – | – |
| REQ-074 | Invalid fault-event parameters (glitch width ≤ 0, a non-finite set-angle value, `use_detent` with detent modelling off) are rejected with `TB_ERROR`. *(rev 0.4 proposed)* | Low | – | One `TB_ERROR` per invalid call. | Sim | TC-073 |
| REQ-075 | **Edge offsets** (device fault): each of the four edges of a cycle – A rising, A falling, B rising, B falling, named by the level change in the forward direction on the logical channels – is displaced by its configured offset in electrical degrees, in both directions. The edge time follows from the displaced edge angle at the current speed. Default: all 0°. **(D-26)** | Medium | §4.5.1, A-25 | Time form, 1 µs per edge, from the centre of a state: B offset +30° (both B edges): every B edge 1/3 µs later than without offset, A edges unchanged, forward and reverse; the logical sequence stays legal. A rise +20°, A fall −20°: the A high time per cycle changes by −40° (duty error). Rpm form 60 rpm and 600 rpm: the time displacement scales with `time_per_edge`. With `direction_swap` enabled, a B offset appears on output A. | Sim | TC-074 |
| REQ-076 | Edge offsets outside the open interval (−45°, +45°) electrical, or non-finite, are rejected with `TB_ERROR` when a movement starts. Within the interval, positions, detents, rest states and the index are unchanged; the move and rotation completion times (state centres) are unchanged. **(D-28)** | Medium | A-25 | One `TB_ERROR` per invalid call for ±45° and a non-finite value, no edge. With all four offsets at ±44°, a detent move ends in a rest state and the command duration equals the one without offsets. | Sim | TC-074 |
| REQ-077 | With edge offsets, Z changes together with the displaced A/B edge that enters or leaves the index state. | Medium | §6, A-25 | Gated ¼ index with a B offset of +30°: Z rises and falls at the same simulation time as the A/B events entering and leaving the index state. | Sim | TC-074 |
| REQ-078 | **Stuck outputs** (device fault): A, B and Z can each be configured as stuck at `'0'`, `'1'` or `'Z'`, or not stuck (default). A stuck output drives the stuck level (after the direction swap, ignoring the polarity inversion), does not bounce, and the model keeps running underneath. The stuck setting is applied at the start of every command and at every edge. **(D-27, D-29)** | Medium | §4.5.1, A-26 | B stuck at `'0'`: no event on B during a 3-revolution move, A toggles as without fault; Z stuck at `'Z'`: Z is `'Z'` during the move. After releasing B, the next command drives B to the level of the current state at its start, and the status position equals the edges moved, including those during the stuck period. Bounce enabled: no bounce on the stuck output. | Sim | TC-075 |
| REQ-079 | A stuck level other than `'0'`, `'1'`, `'Z'` or `'-'` (not stuck) is rejected with `TB_ERROR` when a command starts. | Low | A-26 | One `TB_ERROR` per invalid call, no edge. | Sim | TC-075 |

## 11. UVVM integration

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-080 | The BFM procedures can be used directly from a test sequencer without the VVC. | High | UVVM convention | A BFM-only testbench exercises REQ-010/012/020/040 through direct BFM calls. *(rev 0.5 proposed)* It also runs `rotary_encoder_rotate` in its three overloads: signed rpm with detents on (edge times as REQ-101, then the stop snap as REQ-104), the time form, and a profile with `PROFILE_STOP` (edge times as REQ-111/112); the procedure returns when the shaft is at rest and the end position equals the expected value. | Sim | TC-080 |
| REQ-081 | The VVC follows the UVVM VVC framework: queued commands executed in order, `await_completion`, `insert_delay`, `flush_command_queue`, `terminate_current_command`, `enable/disable_log_msg`, shared VVC configuration and status. | High | UVVM convention | The standard VVC methods behave as in the reference VIPs. A queue of 10 movements completes in order. | Sim | TC-081 |
| REQ-082 | `terminate_current_command` stops a movement at once, at the current angle, without a detent snap (as REQ-107 for rotations). The outputs remain in a legal state and the position matches the edges actually produced. *(rev 0.4 proposed)* | High | §4.1, D-13 | After termination in the middle of a movement, the checker position equals the BFM position and the next movement continues legally. | Sim | TC-082 |
| REQ-083 | Several VVC instances (different instance indices) run independently and concurrently. | High | UVVM convention | Two instances move at different speeds simultaneously. Also, one instance rotates continuously while the other executes moves. Each checker sees only its own instance's edges. | Sim | TC-083 |
| REQ-084 | Configuration changes made through the shared VVC configuration take effect for the next command, not for a command that is already running. (Rotations: REQ-108.) | Medium | UVVM convention | A change issued during a movement does not alter that movement's edges and does alter the next one. | Sim | TC-084 |
| REQ-085 | Each movement and fault-event command is logged with its message ID, direction, edge count and end position. Rotation start, speed change and stop are logged with the speed (rpm, or `time_per_edge` in the time form), the profile length if any, and (for stop) the end position. | Medium | UVVM convention | The log contains the entry. Disabling the message ID suppresses it. | Sim + Review | TC-081 |

## 11a. Movement by angle

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-090 | An angle move turns the shaft by a given angle in degrees (`real`), in either direction, at constant speed. An edge is emitted at each crossing of an edge boundary (±½, ±1½ … edge angles from the centre of the reference state at 0°). | High | §4.6, A-13 | With detents off and 4.5°/edge: three 1° moves from 0° give one edge, during the third move, exactly when 2.25° is crossed. Edge times are exact within one resolution step. | Sim | TC-090 |
| REQ-091 | The angle is tracked without accumulating rounding drift. Angles with up to 7 decimal places are represented exactly; other values are rounded once per move to the angle quantum (1/(`cycles_per_rev` × 10⁷) degree, architecture §6.1). *(rev 0.4 proposed)* | High | §4.6 | With detents off: 360 forward moves of 1° give exactly 80 edges and end at an angle of exactly one revolution. The same for 3600 moves of 0.1° and for a mixed sequence of edge and angle moves. | Sim | TC-091 |
| REQ-092 | An angle move of φ takes φ / edge angle × `time_per_edge` (= φ / (6 × rpm) s in the rpm form), including moves that cross no edge. With detents on, the snap adds the time of its own angle at the same speed. | High | §4.6, A-14 | Command duration equals the computed time within one resolution step, with and without snap, in both forms. | Sim | TC-090 |
| REQ-093 | Edge, detent and angle moves can be mixed; edge and detent moves change the angle by whole edge angles and keep the sub-edge fraction. | High | §4.6 | With detents off: a 1° move, then a 1-edge move, then a 1° move. The edges occur at the angles predicted by the checker's angle model. | Sim | TC-091 |
| REQ-094 | Invalid angle parameters (negative angle when the direction is a separate argument, or a non-finite value) are rejected with `TB_ERROR`. | Medium | – | One `TB_ERROR` per invalid call. No edge. | Sim | TC-092 |
| REQ-095 | Conversion functions: rpm → `time_per_edge` = 60 s / (\|rpm\| × 4 × `cycles_per_rev`), `time_per_edge` → rpm, and rpm ↔ degrees per second (1 rpm = 6 °/s). | Medium | §4.4, A-23 | At 20 cycles/rev: 1, 60, 6000 rpm give 750 ms, 12.5 ms, 125 µs; the inverse gives the rpm back within the rounding of one resolution step; 60 rpm = 360 °/s. `cycles_per_rev` < 1, 0 rpm (to `time_per_edge`) and `time_per_edge` ≤ 0 raise `TB_ERROR`. | Sim | TC-093 |

## 11b. Continuous rotation

Timing examples use the defaults (4.5°/edge, 18°/detent, 20 cycles/rev). *T* = 1 µs is a speed in the time form, chosen so that every fraction used is exact at ps resolution. In the rpm form, 60 rpm gives `time_per_edge` = 12.5 ms and 120 rpm gives 6.25 ms. `t_s` is the time a rotation command is executed. Rotation speeds are signed (A-17): positive = forward, negative = reverse; in the time form the direction is a separate argument.

| ID | Requirement | Prio | Source | Acceptance criteria | Method | Test |
|---|---|---|---|---|---|---|
| REQ-100 | A rotation start begins a continuous rotation at once, at the current angle, with the requested speed (signed rpm, or `time_per_edge` and direction). The command completes at the first edge of the rotation, or at once if the speed is 0 rpm; the rotation then runs on while the VVC executes later commands. **(D-11, D-24)** | High | §4.7, A-17 | Time form from the centre of a state: edges at `t_s` + (k − ½) × *T*, k = 1, 2, …, in the requested direction; the start command and an `await_completion` that follows it complete at `t_s` + 0.5 × *T*. After an angle move to 1.125° (detents off, ¼ edge angle), a forward start emits its first edge and completes at `t_s` + 0.25 × *T*, a reverse start at `t_s` + 0.75 × *T*. Rpm form: +60 rpm gives the first edge at `t_s` + 6.25 ms, forward; −60 rpm the same, reverse. 0 rpm: no edge, completes at `t_s`. | Sim | TC-100 |
| REQ-101 | A rotation keeps turning, with constant edge spacing and without accumulated rounding, until it is stopped. | High | §4.7, §4.6, A-24 | Time form, forward and reverse, 10 revolutions (800 edges): the k-th edge occurs exactly at `t_s` + (k − ½) × *T*. Rpm form, 7 rpm, 10 revolutions: every edge within one resolution step of its ideal time, no growing deviation. Every transition is legal. | Sim | TC-101 |
| REQ-102 | A speed change takes effect at once, at the current angle. The rest of the current edge angle is covered at the new speed. The command completes at the next edge, i.e. the first edge at the new speed, or at once if the new speed is 0 rpm. **(D-11, D-24)** | High | §4.7, A-18 | Time form: started at `t_s` with *T*, change to 2 × *T* at `t_s` + 1.0 × *T* (halfway between edges 1 and 2): edge 2 at `t_s` + 2.0 × *T*, then every 2 × *T*; the change completes at `t_s` + 2.0 × *T*. Rpm form: change to 0 rpm: no further edge, completes at once; then a change to +60 rpm continues from the reached angle. A series of 5 speed changes keeps all transitions legal and the position equal to the checker's angle model. | Sim | TC-102 |
| REQ-103 | A direction change (sign change of the rpm, or a new direction in the time form) takes effect at once, at the current angle, without hysteresis: if the next boundary has not been reached, the next edge re-crosses the boundary that was crossed last. Speed and direction may be changed in the same command. | High | §4.7, A-18, A-13 | Forward rotation from 0° at `t_s` with *T*, reverse at `t_s` + 0.75 × *T* (0.25 edge angle past the first edge): the next edge is a reverse edge at `t_s` + 1.0 × *T*, then every *T*. The state is the one before the first edge. The change command completes at `t_s` + 1.0 × *T*. | Sim | TC-103 |
| REQ-104 | A stop ends the rotation at once. With detents off, the shaft stays at the reached angle. With detents on, it snaps to the nearest detent (tie: direction of the last non-zero speed) at the last non-zero speed of the rotation, or at the configured default snap speed if the rotation never had one. The stop command completes when the shaft is at rest. **(D-12, D-23)** | High | §4.7, A-19, A-14 | Forward from 0°, *T*, detents on. Stop at `t_s` + 2.25 × *T* (10.125°): snap edges at +0.25 × *T* and +1.25 × *T* after the stop, at rest at 18° at +1.75 × *T*. Stop at `t_s` + 1.75 × *T* (7.875°): reverse snap edges at +0.25 × *T* and +1.25 × *T*, at rest at 0° at +1.75 × *T*. Detents off, stop at `t_s` + 1.75 × *T*: no further edge, the command completes at once, and the next rotation start continues from 7.875°. After a 1-edge move (between detents), a rotation at 0 rpm and a stop: the snap runs at the default snap speed. | Sim | TC-104 |
| REQ-105 | While a rotation is active (also at 0 rpm), a move (edge, detent, angle), a fault event (set angle, jump, glitch) and a second rotation start are rejected with `TB_ERROR`. The rotation continues unchanged. **(D-14)** | High | §4.7, A-20 | One `TB_ERROR` per rejected command. Edge times stay as in REQ-101. | Sim | TC-105 |
| REQ-106 | A speed change while no rotation is active is rejected with `TB_ERROR`. A stop while no rotation is active raises an alert of configurable severity (default `TB_WARNING`) and does nothing else. **(D-15)** | Medium | §4.7 | One alert of the expected severity per call. No event on A/B/Z. | Sim | TC-106 |
| REQ-107 | `terminate_current_command` during a rotation stops it at once at the current angle, **without** a detent snap. `flush_command_queue` does not affect a rotation. The outputs remain in a legal state. **(D-13)** | High | §4.7, UVVM convention | After `terminate_current_command`, no further event on A/B/Z. The checker position equals the BFM position, and a following move continues legally. After `flush_command_queue`, the rotation continues as in REQ-101. | Sim | TC-107 |
| REQ-108 | During a rotation, the signal configuration (bounce, jitter, index mode/polarity/position, A/B polarity, direction swap, stuck outputs, alert severities) is read at **every edge**: each edge uses the configuration that is valid when it is emitted. The geometry (`cycles_per_rev`, `edges_per_detent`, rest state, detent on/off, edge offsets) is read at the rotation start, because it defines the angle model; a geometry change during a rotation takes effect at the next rotation start or move. **(D-16)** *(rev 0.4 proposed: stuck outputs and edge offsets added)* | Medium | §4.7, UVVM convention | Bounce enabled between edges k and k+1 of a rotation: edge k is unbounced, edge k+1 and later bounce. `cycles_per_rev` changed during a rotation: the edge spacing and index placement stay unchanged until the rotation is stopped. | Sim | TC-108 |
| REQ-109 | Index, bounce, jitter, direction swap and polarity inversion behave in a rotation as in moves (REQ-030 to REQ-032, REQ-040 to REQ-044, REQ-050 to REQ-056, REQ-061, REQ-062). | High | §4.7 | The index, bounce and jitter checks of TC-031, TC-040, TC-041, TC-050, TC-052 and TC-060 pass with the stimulus given as a rotation instead of moves. | Sim | TC-109 |
| REQ-110 | Invalid rotation parameters are rejected with `TB_ERROR`: `time_per_edge` ≤ 0 ns, a non-finite rpm, or a default snap speed ≤ 0 rpm in the configuration (checked when a snap needs it). 0 rpm is a valid rotation speed. A rejected start does not start a rotation; a rejected change leaves the rotation unchanged. | High | §4.4, A-17 | One `TB_ERROR` per invalid call. No change of the outputs or of the running rotation. | Sim | TC-110 |
| REQ-111 | A rotation start or speed change can give a speed profile: a list of signed rpm entries and a `time_per_entry` > 0. Time 0 is the moment the profile takes effect; entry *j* is the speed from *j* × `time_per_entry` to (*j* + 1) × `time_per_entry`, and each entry boundary is a speed change as REQ-102/REQ-103. The command completes at the first edge after the profile takes effect, or at the end of the profile's first pass if that pass produces no edge. **(D-20, D-24)** | Medium | §4.7.1, A-21 | Rpm form, from the centre of a state, detents off, `time_per_entry` = 25 ms, end *hold*. Profile (60, 120) rpm: edges at `t_s` + 6.25, 18.75, 28.125, 34.375, 40.625, 46.875 ms, then every 6.25 ms; the command completes at `t_s` + 6.25 ms. Profile (0, 60) rpm: no edge before `t_s` + 25 ms, first edge and completion at `t_s` + 31.25 ms. Profile (60, −60) rpm: forward edges at 6.25 and 18.75 ms, then reverse edges at 31.25, 43.75 ms, … Profile (0): completes at `t_s` + 25 ms. Every edge within one resolution step. With jitter enabled, REQ-061 holds per entry. A profile of the maximum length (256 entries, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH`) is accepted. | Sim | TC-111 |
| REQ-112 | The end behaviour of a profile is chosen per call: *hold* continues at the last entry's speed, *stop* stops at the end of the last entry as REQ-104 (including the detent snap), *repeat* restarts at entry 0. **(D-17)** | Medium | §4.7.1, A-21 | Profile (60, 120) rpm, 25 ms, as REQ-111. *hold*: after 46.875 ms every 6.25 ms (53.125, 59.375 ms, …). *repeat*: 56.25, 68.75 ms, then 78.125 ms, … *stop* with detents off: no edge after 46.875 ms, at rest at 27° at `t_s` + 50 ms; a following stop raises the REQ-106 alert. *stop* with detents on (`edges_per_detent` = 4): at 50 ms the shaft is at 27°, halfway between 18° and 36°, so it snaps forward to 36° with edges at 53.125 and 59.375 ms and is at rest at 62.5 ms. | Sim | TC-112 |
| REQ-113 | A speed change, with or without a profile, replaces a running profile at once (REQ-102). | Medium | §4.7.1, A-18 | A plain speed change during a profile: from then on the spacing is the new constant `time_per_edge`, and no further profile entry is used. | Sim | TC-112 |
| REQ-114 | Invalid profiles are rejected with `TB_ERROR` and do not change the rotation state: an empty profile, a non-finite entry, `time_per_entry` ≤ 0 ns, or more entries than the maximum (256). | Medium | §4.7.1 | One `TB_ERROR` per invalid call. No change of the outputs or of a running rotation. | Sim | TC-113 |
| REQ-115 | A single BFM function returns a linear-ramp profile of N entries from a start to an end rpm: entry *j* = rpm₀ + (rpm₁ − rpm₀) × *j* / (N − 1). N = 1 returns the start value. **(D-18)** | Low | §4.7.1, A-22 | 0 → 3000 rpm, N = 4: 0, 1000, 2000, 3000 rpm. −60 → 60 rpm, N = 3: −60, 0, 60 rpm. N < 1 or a non-finite value raises `TB_ERROR`. | Sim | TC-114 |

Transaction Info, Scoreboard and Unwanted Activity Detection are decided in Phase 3 – VVC architecture. With the encoder role only, the scoreboard and Unwanted Activity Detection are expected to be excluded, and Transaction Info is an option.

## 12. Decisions

D-26 to D-30 accepted by the user on 2026-10-27 ("accept all"). The user accepted D-1 to D-10 as proposed on 2026-10-21. D-1 was then revised for the angle model (F-002); the revision was approved with rev 0.2. D-10 is unchanged (uniform); its amplitude unit changes with D-21.

| ID | Decision | Proposal | Alternative |
|---|---|---|---|
| D-1 (revised in rev 0.2) | When does the first edge of a movement occur? | `time_per_edge`/2 after the start (a move goes from the centre of a state to the centre of a state). The command completes `time_per_edge`/2 after its last edge. Back-to-back moves keep a spacing of `time_per_edge` in both directions | Was: `time_per_edge` after the start, completing at the last edge. This is not compatible with angle moves (F-002) |
| D-2 | Which two states are active in gated-½ index mode? | The index state and the next state in the forward direction | Defined by the level of one channel (e.g. "while A is high in the index cycle") |
| D-3 | What happens to the position after an illegal transition? | ±2 edges in the requested direction (physically: the shaft moved too fast to resolve). *Rev 0.4 proposed:* generalized to set angle and jump (REQ-071); the position changes by the edge distance between the old and the new angle | Position unchanged (the state and the position then disagree, which breaks index placement) |
| D-4 | Does Z bounce together with A/B? | No, Z follows the nominal state (index is an optical/magnetic feature, bounce is a mechanical one) | Z follows the bounced state |
| D-5 | *Obsolete in rev 0.2: `t_edge_min` was removed.* | – | – |
| D-6 | Movement of 0 edges | Allowed, a no-op that is only logged | `TB_WARNING` |
| D-7 | Severity when a detent movement starts off a rest state | Configurable, default `TB_WARNING` | `TB_ERROR` |
| D-8 | *Obsolete in rev 0.2: `t_edge_min` was removed. Any positive speed is allowed.* | – | – |
| D-9 | How is the bounce amount configured? | *Rev 0.4 proposed (architecture AD-11):* number of bounce **pulses** (each pulse = 2 toggles), which can't be invalid | Number of extra toggles, which must be even and is validated (rev 0.3) |
| D-10 | Jitter distribution | Uniform | Gaussian (UVVM `rand_pkg` supports both) |

Decided by the user on 2026-10-27:

| ID | Decision | Decided | Rejected alternative |
|---|---|---|---|
| D-11 | When do rotation start and speed/direction change complete? | The change takes effect at once, at the current angle (A-18). The command completes at the next edge, the first edge that shows the change. After `await_completion` the new speed is visible on A/B | (b) Hold the change until the next edge (a direction change on a boundary would need a zero-length state); complete at once |
| D-12 | When does a stop complete? | When the shaft is at rest, i.e. after the detent snap | At once, with the snap in the background |
| D-13 | What does `terminate_current_command` do to a rotation? | Emergency stop at once, without a snap (zero time). The shaft may stay between detents | Like a stop, including the snap |
| D-14 | A move, error generation or second start while a rotation is active | `TB_ERROR`, command dropped, rotation continues (a waiting move would block the queue, because the stop is queued after it) | A second start acts as a speed change |
| D-15 | Stop while no rotation is active | Configurable alert, default `TB_WARNING`, no effect | `TB_ERROR` |
| D-16 | When does a configuration change reach a running rotation? | At every edge (signal configuration). The geometry that defines the angle model is read at the rotation start (REQ-108) | At start and at each speed change |
| D-17 | End behaviour of a speed profile | Chosen per call: hold, stop or repeat | One fixed behaviour |
| D-18 | Linear-ramp helper | One single BFM function, linear in rpm (follows from D-20) | No helper |
| D-19 | Speed unit (S-1 to S-3) | rpm (`real`) as the primary form, signed for rotations (0 rpm legal); `time_per_edge` (`time`) kept as an overload for exact edge spacing; conversion functions incl. degrees per second | Degrees per second; rpm only; `time_per_edge` only (rev 0.4) |
| D-20 | Profile axis (S-4) | Over time: rpm entries with `time_per_entry` | Over edges (`edges_per_entry`, earlier draft of rev 0.3); over angle |

Consequences of D-19/D-20, proposed in rev 0.3 and accepted by the user as proposed on 2026-10-27:

| ID | Decision | Proposal | Alternative |
|---|---|---|---|
| D-21 | Jitter amplitude unit and model | Electrical degrees (0 ≤ *j* < 45°), as datasheets specify phase error. Each edge is displaced on its own, without carry-over; the amplitude scales with the speed. A fixed time amplitude no longer works once the speed varies within a rotation | Keep a time amplitude (rev 0.2), checked against the edge interval at every edge |
| D-22 | Bounce window longer than the time to the next edge | Cut the bounce off before the next edge and raise a configurable alert (default `TB_WARNING`) once per command (REQ-056). A static check "`t_bounce` < `time_per_edge`" is impossible when the speed varies | `TB_ERROR` at the first affected edge |
| D-23 | Snap speed after a stop | The last non-zero speed of the rotation; if there was none, a configurable default snap speed | Always a configurable snap speed (models the detent spring rather than the hand) |
| D-24 | Completion when no edge follows | A start or change to 0 rpm completes at once. A profile completes at its first edge, or at the end of its first pass if that pass has no edge. Otherwise the command, and with it the queue, would wait forever | `TB_ERROR` for a constant 0 rpm |
| D-25 *(rev 0.4, accepted 2026-10-27)* | Who owns a boundary when a stop, speed change, `terminate_current_command` or move end falls exactly on an edge time (F-003)? | The edge is emitted first: a shaft standing exactly on a boundary is in the state it moved into. A following movement in the opposite direction emits its first edge at its start (architecture AD-7) | The edge is suppressed ("strictly beyond"): not implementable deterministically, because the edge is driven in the first delta of that time |
| D-26 *(rev 0.4, accepted 2026-10-27)* | Do edge offsets refer to the logical channels or to the output pins? | Logical channels, before direction swap and inversion. The offsets define where the edges lie in the angle model and are latched with the geometry at the start of a motion; swap and inversion stay per-edge settings. With the defaults (no swap, no inversion) logical = pin | Output pins: a swap or inversion change during a rotation would then move the edge angles mid-motion |
| D-27 *(rev 0.4, accepted 2026-10-27)* | Which stuck levels? | `'0'`, `'1'` and `'Z'` (broken wire without pull resistor; spec §8 makes `'Z'` an error for the decoder), `'-'` = not stuck | `'0'`/`'1'` only (keeps REQ-001 without exception) |
| D-28 *(rev 0.4, accepted 2026-10-27)* | Range of edge offsets | Open interval (−45°, +45°): every state stays wider than 0° and contains its ideal centre, so detents, positions, index and completion times are unaffected | Allow larger offsets down to zero-width states (a lasting illegal transition); detents and rest states then need a new definition |
| D-29 *(rev 0.4, accepted 2026-10-27)* | When does a stuck setting take effect? | At the start of every command and at every edge. A VVC configuration change while the encoder is idle shows at the next command | At once (impossible: a change of the shared configuration has no event) |
| D-30 *(rev 0.4, accepted 2026-10-27 with use_detent and jump_edges)* | Set angle and jump (user requests 2026-10-27) | Two commands: `set_angle` (absolute degrees, `use_detent` default false snaps to the nearest detent with the power-up tie rule, not a power-up) and `jump_edges` (relative edges from the angle at execution time, no snap). On a boundary the shaft stays on the side of the old angle. The relative form keeps error injection independent of the current position, which a queued VVC command cannot know | One command with an absolute angle only; one name for both forms |

## 13. Traceability summary

| Spec section | Requirements |
|---|---|
| §3 Signals, A-01 | REQ-001 |
| §4.1 State sequence, A-02/03 | REQ-010, REQ-011, REQ-030, REQ-031 |
| §4.2 Direction changes | REQ-004, REQ-014 |
| §4.3 Illegal transitions/glitches | REQ-070, REQ-071, REQ-072 |
| §4.4 Speed and timing, A-04/05, A-23, A-24 | REQ-003, REQ-012, REQ-013, REQ-016, REQ-060 to REQ-063, REQ-095, REQ-101 |
| §4.6 Angle, A-13 | REQ-012, REQ-090 to REQ-094 |
| §4.5 Device faults and fault events, A-12, A-25, A-26 | REQ-001, REQ-063, REQ-070 to REQ-072, REQ-074 to REQ-079 |
| §5.1 Detents, A-06, A-14, A-15 | REQ-020 to REQ-027 |
| §5.2 Bounce, A-07/08 | REQ-050 to REQ-056 |
| §6 Index, A-10 | REQ-032, REQ-040 to REQ-045, REQ-055 |
| §7 Initial state, A-16 | REQ-002, REQ-005 |
| §8 Expected decoder behaviour (informative) | Not a VVC requirement (receiver role excluded). Used as the reference for the testbench checker |
| §4.7 Continuous rotation, A-17 to A-20 | REQ-003, REQ-070, REQ-083, REQ-085, REQ-100 to REQ-110 |
| §4.7.1 Speed profile, A-21, A-22 | REQ-111 to REQ-115 |
| UVVM conventions | REQ-080 to REQ-085 |

**Counts:** 77 active requirements (9 Critical, 33 High, 29 Medium, 6 Low), plus 1 withdrawn (REQ-073).
