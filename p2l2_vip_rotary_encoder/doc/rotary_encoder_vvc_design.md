# Rotary Encoder VVC – Design

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_vvc_design.md` |
| Revision | 0.7 |
| Status | Use cases, scope, features: approved 2026-11-10. Architecture, API preview: approved 2026-11-10. Test plan, increments, integration checklist: approved 2026-11-10. Merge into this document: approved 2026-11-11. REQ-086 (rev 0.2): approved 2026-11-11. REQ-072, REQ-075, REQ-110 (rev 0.3): approved 2026-11-11. Test case `linear_ramp_rotation` (rev 0.4): approved 2026-11-11. Rev 0.5 (glitch removed, D-100; transaction info with the command's effect, D-98; Increment 4 decisions D-95 to D-97, D-99): approved 2026-11-11. Rev 0.6 (Increment 5: REQ-107, REQ-108, transaction info; D-101 to D-106): approved 2026-11-11. Rev 0.7 (Stage 5.4 status in Increments): review pending |
| Specification | `rotary_encoder_spec.md` rev 0.13 (approved 2026-11-11) |
| Role | Encoder only: the VVC drives A/B/Z into a DUT |

---

## 1. Use cases

| ID | Use case | Consequence for the design |
|---|---|---|
| U-1 | Stimulate a DUT decoder with discrete moves (edges, angle, to a state) **and** with continuous rotation, optionally with time-based speed profiles, with optional bounce, jitter and faults | Moves are blocking commands. A rotation runs in the background while the executor stays free for speed changes, stop and other commands. Served by REQ-001 to REQ-080, REQ-086 and REQ-090 to REQ-115 |
| U-2 | Read back the encoder state (position, angle, state, rotation) in the test sequencer, if it adds little complexity | One queued command plus `fetch_result()`, reusing the framework's result queue (D-44); REQ-086 |
| U-3 | One encoder per DUT; several encoder instances in one testbench run independently | One channel, one VVC instance per encoder, standard `GC_INSTANCE_IDX` (REQ-083) |

REQ-081, REQ-082, REQ-084 and REQ-085 are UVVM conventions that every use case relies on.

## 2. Scope

**Selected:** encoder role only. All optional features of the spec are included. Index is **on** by default; bounce, jitter, device faults and Z polarity inversion are **off** by default.

**Out of scope**

| Item | Reason |
|---|---|
| Receiver role (observing A/B/Z from a DUT, spec §8 decoder semantics) | Excluded by the user: the VVC stimulates DUT decoders. Spec §8 still defines what a correct decoder infers and is the reference for the testbench checker (Test plan 7.3) |
| Push-button switch | Spec §9, handled by a GPIO VVC |
| Detents and snapping | Spec §9 (Q-09). A click of a detented knob is an edge move or a move to state |
| Direction swap and A/B polarity inversion options | Spec §9 (Q-14, Q-15). A "B leads A" part is handled by crossed wiring (REQ-033, D-52) |
| Scoreboard, Unwanted Activity Detection, monitor | Nothing is received from the DUT (Architecture 4.3) |
| Everything else in spec §9 | See the spec |

## 3. Features

- **Priority:** *Critical* means the VVC is useless without it. *High* means it is needed for normal use or required by UVVM conventions. *Medium* means an optional feature or diagnostic. *Low* means nice to have.
- **Method:** *Sim* means a self-checking simulation test with a checker in the testbench that is independent of the BFM (Test plan 7.1). *Review* means a code or documentation review. The test cases per feature are in Test plan 7.4.
- **Status:** all features are *Approved*. Implementation and verification status per feature: implementation report.
- **Timing tolerance:** "exact" means equal within one simulator time-resolution step.
- **Alerts:** severities follow UVVM (`TB_ERROR` for an invalid user call, `TB_WARNING` for questionable but executable use). Severities marked "configurable" are configuration fields.
- A **(D-n)** marker names the decision behind a feature (Decision log).

### 3.1 Signals, initial state, continuity

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-001 | The VVC drives the outputs `A` and `B` and the optional output `Z` with strong `'0'`/`'1'` levels only; the only exception is an output configured as stuck at `'Z'` (REQ-078). This is a property of the drive logic; the VVC does **not** check its own outputs at runtime. | Critical | §3, A-01, A-26 | The testbench checker (not the VVC) verifies that after initialization no output carries a value other than `'0'`/`'1'`, on every event in every test that does not configure a stuck `'Z'`. | Sim (testbench checker) |
| REQ-002 | At initialization and before any movement, the VVC drives the state and the Z level that follow from the configured start angle (default 0°, i.e. the zero state `AB = 11`, position 0, Z active with the default index configuration). No edge is emitted; this is the power-up state. | Critical | §7, A-16 | At the first delta after VVC initialization, `AB` and Z equal the values the checker's model computes for the start angle, and there is no event on A/B before the first movement. Run with the defaults (`AB = 11`, Z active) and with start angles −10°, 30° (position 7, Z inactive) and 400°. | Sim |
| REQ-003 | While no move and no rotation is active, A, B and Z hold their last value indefinitely. | Critical | §4.4 | No event on A/B/Z during an `insert_delay` or an idle period of ≥ 100 × `time_per_edge`, after a move and after a stopped rotation. | Sim |
| REQ-004 | Each movement starts from the state and position at which the previous one ended (continuity). | Critical | §4.2, §7 | Over a sequence of mixed forward/reverse movements, every transition is legal (one channel per edge), including at command boundaries. The checker's position equals the expected sum. | Sim |
| REQ-006 | The zero state (A-06) is configurable to any of the four states (A/B levels on the output pins, spec A-03; default `11`). Angle 0° (position 0) is the centre of the zero state, and position *p* is the state reached from the zero state after *p* forward edges. The zero state is a power-up property: it is taken at initialization and must not change afterwards. A zero state that is not a 2-bit `'0'`/`'1'` value, or that differs from the one taken at initialization, is rejected with `TB_ERROR` when a command starts; the command is not executed and the zero state stays unchanged. **(D-32)** | High | §2, §4.6, A-06, A-13 | For each of the 4 zero states (one power-up each, through the BFM or separate instances): start angle 0° gives `AB` = zero state, and a forward move of 4 edges passes the forward sequence from it and ends in it. An invalid zero state, and a zero state changed after initialization, each raise one `TB_ERROR` at the next command start, and no edge is produced. | Sim |

### 3.2 Movements

Speeds are given in rpm (primary) or as `time_per_edge` (alternative, spec §4.4). "Time form" below means the speed was given as `time_per_edge`; "rpm form" means it was given in rpm and `time_per_edge` is derived (A-23).

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-010 | A forward movement of N edges produces exactly N edges following the forward Gray sequence `00→10→11→01→00` (A leads B). | Critical | §4.1, A-02 | The checker counts exactly +N edges and every transition is legal and forward. N ∈ {1, 2, 3, 4, 5, 1000}, from all four states (start angles 0°, 4.5°, 9°, 13.5°). | Sim |
| REQ-011 | A reverse movement of N edges produces exactly N edges following the reverse sequence `00→01→11→10→00`. | Critical | §4.1 | As REQ-010 with −N. | Sim |
| REQ-012 | Edge timing: without jitter, an edge move of N edges that starts in the centre of a state emits its edges at (k − ½) × `time_per_edge` after the start, k = 1..N. The move ends in the centre of the new state, and the command completes N × `time_per_edge` after it started. Each edge time is computed from the exact model and rounded once (A-24). **(D-1)** | Critical | §4.4, §4.6, A-04, A-13, A-23, A-24 | Time form: first edge exactly `time_per_edge`/2 after the start; every further edge-to-edge interval exactly `time_per_edge`, including across back-to-back commands with the same speed and across direction changes; command duration exactly N × `time_per_edge`. Tested with `time_per_edge` ∈ {1 ns, 1 µs, 1 ms}. Rpm form: 7 rpm and 6000 rpm at 20 cycles/rev, N = 1000: every edge within one resolution step of `t_s` + (k − ½) × 60 s / (rpm × 80), no growing deviation, command duration within one step of N × `time_per_edge`. | Sim |
| REQ-013 | Speed curves from moves: consecutive movements with different speeds are executed back to back without extra delay. | High | A-04 | The interval between the last edge of movement k and the first edge of movement k+1 equals (`time_per_edge`(k) + `time_per_edge`(k+1)) / 2: exactly in the time form, within two resolution steps in the rpm form. | Sim |
| REQ-014 | Direction reversal between consecutive movements goes back along the reverse transition from the current state, including in the middle of a cycle. | Critical | §4.2 | Forward 1 edge, then reverse 1 edge, repeated 10 times from each of the four states: every transition is legal and the final position equals the start position. | Sim |
| REQ-015 | A movement of 0 edges produces no edge and completes without consuming time. **(D-6)** | Low | – (boundary) | No event on A/B/Z and the command completes at the current time. | Sim |
| REQ-016 | Invalid movement speeds are rejected with `TB_ERROR` and no edge is produced: `time_per_edge` ≤ 0 ns, or rpm ≤ 0 or not finite (the direction of a move is a separate argument). Any positive speed is allowed, also one too fast for a DUT decoder. | High | §4.4 | Each invalid call raises exactly one `TB_ERROR` (counted via the expected-alert mechanism) and the outputs do not change. | Sim |

### 3.3 Polarity and wiring

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-032 | With index polarity inversion enabled, Z is active low; A and B and the positions where Z is active are unchanged. | Medium | A-10 | Z equals `not` of the non-inverted run, edge for edge (same stimulus, compared within one testbench); A and B are identical in both runs. | Sim |
| REQ-033 | The VIP documentation explains how to connect the encoder to a DUT that counts "B leads A" as forward: A and B are crossed in the port map of the VVC (record elements associated individually); the VVC has no swap option. It notes that an index state `10`/`01` taken from the DUT side then has its bits exchanged. **(D-52)** | Low | A-02, §6, Q-14 | The documentation contains the port-map example and the note. The example compiles and runs in the documentation-example testbench on all working simulators, and the DUT side sees "B leads A" for a forward move. | Review + Sim (documentation example) |

### 3.4 Index pulse

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-040 | With index disabled, Z stays at its inactive level. | High | §6 | No event on Z over a test that runs several revolutions with index disabled. | Sim |
| REQ-041 | With index enabled (default, `cycles_per_rev` = 20), Z is active exactly once per revolution, i.e. once every 4 × `cycles_per_rev` edges, at the configured index position, in both directions. The index position `p_idx` (any integer, in edges from position 0) selects the index cycle: positions `p_idx` … `p_idx+3`, repeated every 4 × `cycles_per_rev` edges. | High | §6, A-10 | Over ≥ 3 revolutions forward and ≥ 3 reverse, Z activates once per revolution and only at the expected positions. Tested with `cycles_per_rev` ∈ {1, 3, 24} and `p_idx` ∈ {0, 5, −3}. | Sim |
| REQ-042 | Index width (default 1): Z is active at the position in the index cycle whose state (on the pins) is the configured index state (default `11`), and at the next width − 1 positions forward, whose states follow the index state in the order `00 → 10 → 11 → 01`. These positions may lie outside the index cycle. Z changes in the same delta cycle as the A/B edge that enters or leaves this range. | High | §6, A-10 | Widths 1, 2, 3, 4, each with index state `00` and `10`, forward and reverse: Z is active over exactly the expected positions and rises and falls at the same simulation time as the A/B edges that enter and leave them. Width 2 at `00` (zero state `00`, `p_idx` = 0): Z is active while B is low, at positions 0 and 1. | Sim |
| REQ-045 | With index enabled, `cycles_per_rev` < 1, an index width outside 1 to 4, or an index state that is not a 2-bit `'0'`/`'1'` value is rejected with `TB_ERROR` when a command starts; the command is not executed. During a rotation the check runs at every edge and Z keeps its last valid configuration. **(D-31)** | Medium | §6, A-10 | One `TB_ERROR` per invalid call for each of: `cycles_per_rev` = 0, width 0, width 5, index state `"0X"`. No edge is produced. | Sim |
| REQ-046 | The index is placed relative to the zero state: the zero state and the index state are independent settings, and angle 0° stays the centre of the zero state whatever the index configuration (spec Q-10). | High | §6, A-10, A-13 | `cycles_per_rev` = 20, width 1, index state `00`, `p_idx` = 0: with zero state `00`, Z is active at position 0 (centred at 0°); with zero state `11`, Z is active at position 2 (centred at 9°). | Sim |

### 3.5 Contact bounce

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-050 | With bounce disabled (default), each edge is a single transition. | High | A-07 | Number of events on A plus B equals the number of edges. | Sim |
| REQ-051 | With bounce enabled, after each nominal edge the changing channel toggles a configured number of extra times (always even) within `t_bounce`, then settles at the new value. The other channel does not change. | Medium | §5, A-07 | Per edge: 1 + the configured number of extra toggles on the changing channel, all within [edge, edge + `t_bounce`]. No event on the other channel. Final value correct. | Sim |
| REQ-052 | Bounce never shifts the nominal edges: nominal edge-to-edge timing stays as REQ-012. | Medium | §5 | The first toggle of each edge occurs at the REQ-012 time. | Sim |
| REQ-053 | Bounce placement: *random* (default when bounce is enabled) is reproducible for the same seed. *Even* places the toggles at equal spacing within `t_bounce`. | Medium | A-08 | Two runs with the same seed produce identical toggle times. In even mode, the spacing is `t_bounce` / (extra toggles + 1) ± 1 resolution step. | Sim |
| REQ-054 | `t_bounce` ≤ 0 ns with bounce enabled is rejected with `TB_ERROR`. The bounce amount is a number of bounce pulses (`natural`, 2 toggles each), so an odd or negative toggle count cannot be expressed. During a rotation the check runs at every edge, as REQ-045: one `TB_ERROR` per invalid value, and the last valid configuration is kept. **(D-9, D-56)** | Medium | A-07 | One `TB_ERROR` per invalid call. During a rotation: one `TB_ERROR` per invalid value, the rotation continues with the last valid bounce configuration. | Sim |
| REQ-055 | Z follows the nominal A/B state and does not bounce. **(D-4)** | Low | §5, §6 | With bounce and index enabled, Z has exactly 2 events per index pulse. | Sim |
| REQ-056 | If the next nominal edge comes before the bounce window has ended (high speed, or a speed change during the window), the bounce is cut off: the bouncing channel is at its settled value before the next edge and the remaining toggles are dropped. An alert of configurable severity (default `TB_WARNING`) reports this once per move or rotation command. All transitions stay legal. **(D-22, D-57)** | Medium | §5, A-07 | `t_bounce` = 2 × `time_per_edge` with 4 extra toggles: each edge is preceded by a settled channel, no transition is illegal, the edge count is correct, and exactly one alert per command is raised. | Sim |
| REQ-057 | With bounce and jitter both enabled, the bounce window of an edge starts at the actual (jittered) edge time. A jittered edge that comes before the bounce window of the previous edge has ended cuts that bounce off as REQ-056. Bounce placement and jitter draw from one random stream (`rand_seed1`/`rand_seed2`): the same seeds and configuration give the same events, but enabling bounce or changing `bounce_pulses` changes the jitter sequence. **(D-58)** | Medium | §5, A-05, A-07, A-08 | Random bounce, jitter 20° at 10 µs per edge, window 4 µs, one revolution across the index: every edge within ±*j*/90 × `time_per_edge` (+ one resolution step) of its ideal time, displaced in both directions; all bounce toggles on the changing channel within [actual edge, actual edge + `t_bounce`], settled at the new level; Z has 2 events; the edge count and completion time are exact. The same seeds twice give identical logs; the same seeds without bounce give different edge times. Jitter 40° with a 6 µs window (fits at ideal timing): exactly one cut-off alert per command, no illegal transition, the position change is exact. | Sim |

### 3.6 Edge jitter

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-060 | With jitter disabled (default), timing is as in REQ-012. | High | A-05 | Covered by the REQ-012 test. | Sim |
| REQ-061 | With jitter enabled (amplitude *j* in electrical degrees, 0 ≤ *j* < 45°), each edge is displaced from its ideal time by a uniformly distributed offset in [−*j*/90, +*j*/90] × `time_per_edge` at the current speed. The offset only moves that edge; the following edges keep their ideal times. **(D-10, D-21, D-55)** | Medium | A-05 | Over 10 000 edges at constant speed: every displacement lies within ±*j*/90 × `time_per_edge` (+ one resolution step), the mean displacement is within ±*j*/900 × `time_per_edge`, and both bounds are reached within 5 % of the amplitude. The edge count over the run is exact (no drift). The same *j* at 60 rpm and 600 rpm gives displacements that scale with `time_per_edge`. | Sim |
| REQ-062 | Jitter is reproducible for the same seed. | Medium | A-05 | Two runs with the same seed produce identical edge times. | Sim |
| REQ-063 | *j* < 0°, or *j* ≥ half the width of the narrowest state (45° electrical without edge offsets, REQ-076), is rejected with `TB_ERROR`. During a rotation the check runs at every edge, as REQ-045: one `TB_ERROR` per invalid value, and the last valid configuration is kept. **(D-56)** | Low | A-05, A-25 | One `TB_ERROR` per invalid call: *j* = 45° without offsets; *j* = 30° with a B offset of +30° (narrowest state 60°). *j* = 29° with that offset is accepted. During a rotation: one `TB_ERROR` per invalid value, the rotation continues with the last valid jitter. | Sim |

### 3.7 Device faults and fault events

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-070 | Without configured device faults, normal movements (edge, angle and move-to-state moves, centre state, rotations) never produce an illegal transition or a glitch. Bounce toggles (REQ-051) are intended and are not glitches. | Critical | §4.5 | The checker reports no violation over all non-error tests. | Sim |
| REQ-071 | On request, the VVC places the shaft in zero time: **set angle** to an absolute angle in degrees, or **jump** N edges in a given direction from the angle at execution time (sub-edge fraction kept). The position follows the new angle, and the outputs change from the old to the new state in one delta cycle. No bounce or jitter is applied, and Z takes the level of the new state. Setting the current angle again is a no-op. On a boundary, the shaft is in the state on the side of the old angle. **(D-3, D-30)** | Medium | §4.3, A-12 | Jump, from each of the four states: N = 2 gives events on A and B in the same delta cycle (illegal transition); N = 4 gives no event on A/B and the position changes by ±4; N = 1 and N = 3 give one event on one channel; N = 80 at the default 20 cycles/rev gives no A/B event and no Z pulse. Set angle: from position 5, 0° gives `AB` = zero state, Z active (default index) and status position 0; 30° gives position 7 and angle 30°; 2.25° from 0° keeps the state at 0° (boundary, old side). Afterwards the status equals the expected value, and normal movements continue legally from the new state with the index position consistent. Zero simulation time passes. | Sim |
| REQ-074 | An invalid fault-event parameter (a non-finite set-angle value) is rejected with `TB_ERROR`. | Low | – | One `TB_ERROR` per invalid call. | Sim |
| REQ-075 | **Edge offsets** (device fault): each of the four edges of a cycle – A rising, A falling, B rising, B falling, named by the level change on the output pin in the forward direction – is displaced by its configured offset in electrical degrees, in both directions. The edge time follows from the displaced edge angle at the current speed. Default: all 0°. **(D-26, D-87)** | Medium | §4.5.1, A-25 | Time form, 1 µs per edge, from the centre of a state: B offset +30° (both B edges): going forward every B edge 1/3 µs later than without offset, going in reverse every B edge 1/3 µs earlier (the edge sits at the same angle in both directions), A edges unchanged; the logical sequence stays legal. A rise +20°, A fall −20°: the A high time per cycle changes by −40° (duty error). Rpm form 60 rpm and 600 rpm: the time displacement scales with `time_per_edge`. | Sim |
| REQ-076 | Edge offsets outside the open interval (−45°, +45°) electrical, or non-finite, are rejected with `TB_ERROR` when a movement starts. Within the interval, positions, the zero state and the index positions are unchanged; the move and rotation completion times (state centres) are unchanged. **(D-28)** | Medium | A-25 | One `TB_ERROR` per invalid call for ±45° and a non-finite value, no edge. With all four offsets at ±44°, a 4-edge move from 0° ends in the zero state and the command duration equals the one without offsets. | Sim |
| REQ-077 | With edge offsets, Z changes together with the displaced A/B edge that enters or leaves the index state. | Medium | §6, A-25 | Index width 1 with a B offset of +30°: Z rises and falls at the same simulation time as the A/B events entering and leaving the index state. | Sim |
| REQ-078 | **Stuck outputs** (device fault): A, B and Z can each be configured as stuck at `'0'`, `'1'` or `'Z'`, or not stuck (default). A stuck output drives the stuck level (a stuck Z ignores the index polarity), does not bounce, and the model keeps running underneath. The stuck setting is applied at the start of every command and at every edge. **(D-27, D-29)** | Medium | §4.5.1, A-26 | B stuck at `'0'`: no event on B during a 3-revolution move, A toggles as without fault; Z stuck at `'Z'`: Z is `'Z'` during the move. After releasing B, the next command drives B to the level of the current state at its start, and the status position equals the edges moved, including those during the stuck period. Bounce enabled: no bounce on the stuck output. | Sim |
| REQ-079 | A stuck level other than `'0'`, `'1'`, `'Z'` or `'-'` (not stuck) is rejected with `TB_ERROR` when a command starts. | Low | A-26 | One `TB_ERROR` per invalid call, no edge. | Sim |

### 3.8 UVVM integration

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-080 | The BFM procedures can be used directly from a test sequencer without the VVC. **(D-48, D-63)** | High | UVVM convention | A BFM-only testbench exercises REQ-010/012/040/090 through direct BFM calls. It also runs `rotary_encoder_rotate` in its three overloads: signed rpm (edge times as REQ-101, then the stop as REQ-104), the time form, and a profile with `PROFILE_STOP` (edge times as REQ-111/112); the procedure returns when the shaft is at rest and the end position equals the expected value. | Sim |
| REQ-081 | The VVC follows the UVVM VVC framework: queued commands executed in order, `await_completion`, `insert_delay`, `flush_command_queue`, `terminate_current_command`, `enable/disable_log_msg`, shared VVC configuration and status. | High | UVVM convention | The standard VVC methods behave as in the reference VIPs. A queue of 10 movements completes in order. | Sim |
| REQ-082 | `terminate_current_command` stops a movement at once, at the current angle (as REQ-107 for rotations). The outputs remain in a legal state and the position matches the edges actually produced. **(D-13)** | High | §4.1 | After termination in the middle of a movement, the checker position equals the BFM position and the next movement continues legally. | Sim |
| REQ-083 | Several VVC instances (different instance indices) run independently and concurrently. | High | UVVM convention | Two instances move at different speeds simultaneously. Also, one instance rotates continuously while the other executes moves. Each checker sees only its own instance's edges. | Sim |
| REQ-084 | Configuration changes made through the shared VVC configuration take effect for the next command, not for a command that is already running. (Rotations: REQ-108.) | Medium | UVVM convention | A change issued during a movement does not alter that movement's edges and does alter the next one. | Sim |
| REQ-085 | Each movement (including move to state), centre-state and fault-event command is logged with its message ID, direction, edge count and end position. Rotation start, speed change and stop are logged with the speed (rpm, or `time_per_edge` in the time form), the profile length if any, and (for stop) the end position. | Medium | UVVM convention | The log contains the entry. Disabling the message ID suppresses it. | Sim + Review |
| REQ-086 | **Status read-back:** the BFM function `rotary_encoder_get_status` and the VVC command `rotary_encoder_get_status` (result read with `fetch_result()`) return position, angle, state, Z (before inversion), rotation flag and signed rpm at the call time (BFM) or the execution time (VVC), also in the middle of a rotation, without changing the motion. **(D-44, D-85)** | High | §4.6, §4.7 | After a 10° move from 0°: position 2, angle 10.0, `ab` = state of position 2, `index_active` false, `is_rotating` false, rpm 0.0. During a +60 rpm rotation (VVC): `is_rotating` true, rpm 60.0, and the edge times after the read are unchanged. | Sim |

### 3.9 Movement by angle

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-090 | An angle move turns the shaft by a given angle in degrees (`real`), in either direction, at constant speed, and ends exactly at its target angle, without a correction movement. An edge is emitted at each crossing of an edge boundary (±½, ±1½ … edge angles from the centre of the zero state at 0°). | High | §4.6, A-13 | With 4.5°/edge: three 1° moves from 0° give one edge, during the third move, exactly when 2.25° is crossed. A 10° move from 0° gives exactly 2 edges and ends at 10°. Edge times are exact within one resolution step. | Sim |
| REQ-091 | The angle is tracked without accumulating rounding drift. Angles with up to 7 decimal places are represented exactly; other values are rounded once per move to the angle quantum (1/(`cycles_per_rev` × 10⁷) degree, Architecture 4.5.1). **(D-37, D-71)** | High | §4.6 | 360 forward moves of 1° give exactly 80 edges and end at an angle of exactly one revolution. The same for 3600 moves of 0.1° and for a mixed sequence of edge and angle moves. | Sim |
| REQ-092 | An angle move of φ takes φ / edge angle × `time_per_edge` (= φ / (6 × rpm) s in the rpm form), including moves that cross no edge. | High | §4.6 | Command duration equals the computed time within one resolution step, in both forms. | Sim |
| REQ-093 | Edge and angle moves can be mixed; edge moves change the angle by whole edge angles and keep the sub-edge fraction. | High | §4.6 | A 1° move, then a 1-edge move, then a 1° move. The edges occur at the angles predicted by the checker's angle model. | Sim |
| REQ-094 | Invalid angle parameters (negative angle when the direction is a separate argument, or a non-finite value) are rejected with `TB_ERROR`. | Medium | – | One `TB_ERROR` per invalid call. No edge. | Sim |
| REQ-095 | Conversion functions: rpm → `time_per_edge` = 60 s / (\|rpm\| × 4 × `cycles_per_rev`), `time_per_edge` → rpm, and rpm ↔ degrees per second (1 rpm = 6 °/s). | Medium | §4.4, A-23 | At 20 cycles/rev: 1, 60, 6000 rpm give 750 ms, 12.5 ms, 125 µs; the inverse gives the rpm back within the rounding of one resolution step; 60 rpm = 360 °/s. `cycles_per_rev` < 1, 0 rpm (to `time_per_edge`) and `time_per_edge` ≤ 0 raise `TB_ERROR`. | Sim |
| REQ-096 | **Move to state:** the shaft turns in the given direction to the centre of the *n*-th state (*n* ≥ 1) that equals the target state (levels on the pins, spec A-03). The state the shaft is in when the move starts is never counted, whatever its sub-edge position. The move is an angle move to that centre at constant speed (rpm or `time_per_edge`), ends exactly there, and is resolved from the angle at its start (also in the VVC, at execution time). **(D-51)** | High | §4.6, A-27 | 4.5°/edge, zero state `11` (positions 0 to 3: `11`, `01`, `00`, `10`), time form *T* = 1 µs. Forward to `00`, *n* = 1: from 0° to 9° (edges at 0.5 *T* and 1.5 *T*, completes at 2 *T*); from 1.125° to 9° (edges at 0.25 *T* and 1.25 *T*, completes at 1.75 *T*); from 10° (in `00`) to 27°. *n* = 2 from 0°: 27°. Reverse to `00`, *n* = 1, from 0°: −9°. Target `10` forward from 0°: 13.5° (position 3). Status angle and position equal the target after each move; every transition is legal. Queued in the VVC after a 1.125° angle move, the move starts from 1.125°. | Sim |
| REQ-097 | **Centre state:** on request, the shaft is placed at the centre of the state it is in (*p* edge angles), in zero time. No event occurs on A, B or Z, also with edge offsets; only the angle changes. A shaft already on the centre is unchanged. On a boundary, the state is the one the shaft moved into (A-13). **(D-51)** | Medium | §4.6, A-28 | From 10°: angle 9°, position 2, no event, zero simulation time. A forward move ending exactly at 6.75° then centre state: 9°; a reverse move ending exactly at 6.75° then centre state: 4.5°. With all four edge offsets at +44° and at −44°, from 1° and from 3.5°: no event on A/B/Z. Without offsets, from 1°: centre state, then a 1-edge move emits its edge 0.5 × `time_per_edge` after its start. | Sim |
| REQ-098 | Invalid move-to-state parameters are rejected with `TB_ERROR` and produce no edge: *n* = 0, a target state that is not a 2-bit `'0'`/`'1'` value, or an invalid speed (as REQ-016). | Medium | A-27 | One `TB_ERROR` per invalid call; the outputs and the status do not change. | Sim |

### 3.10 Continuous rotation

Timing examples use the defaults (4.5°/edge, 20 cycles/rev). *T* = 1 µs is a speed in the time form, chosen so that every fraction used is exact at ps resolution. In the rpm form, 60 rpm gives `time_per_edge` = 12.5 ms and 120 rpm gives 6.25 ms. `t_s` is the time a rotation command is executed. Rotation speeds are signed (A-17): positive = forward, negative = reverse; in the time form the direction is a separate argument.

| ID | Feature | Prio | Source | Acceptance criteria | Method |
|---|---|---|---|---|---|
| REQ-100 | A rotation start begins a continuous rotation at once, at the current angle, with the requested speed (signed rpm, or `time_per_edge` and direction). The command completes at the first edge of the rotation, or at once if the speed is 0 rpm; the rotation then runs on while the VVC executes later commands. **(D-11, D-24)** | High | §4.7, A-17 | Time form from the centre of a state: edges at `t_s` + (k − ½) × *T*, k = 1, 2, …, in the requested direction; the start command and an `await_completion` that follows it complete at `t_s` + 0.5 × *T*. After an angle move to 1.125° (¼ edge angle), a forward start emits its first edge and completes at `t_s` + 0.25 × *T*, a reverse start at `t_s` + 0.75 × *T*. Rpm form: +60 rpm gives the first edge at `t_s` + 6.25 ms, forward; −60 rpm the same, reverse. 0 rpm: no edge, completes at `t_s`. | Sim |
| REQ-101 | A rotation keeps turning, with constant edge spacing and without accumulated rounding, until it is stopped. | High | §4.7, §4.6, A-24 | Time form, forward and reverse, 10 revolutions (800 edges): the k-th edge occurs exactly at `t_s` + (k − ½) × *T*. Rpm form, 7 rpm, 10 revolutions: every edge within one resolution step of its ideal time, no growing deviation. Every transition is legal. | Sim |
| REQ-102 | A speed change takes effect at once, at the current angle. The rest of the current edge angle is covered at the new speed. The command completes at the next edge, i.e. the first edge at the new speed, or at once if the new speed is 0 rpm. **(D-11, D-24)** | High | §4.7, A-18 | Time form: started at `t_s` with *T*, change to 2 × *T* at `t_s` + 1.0 × *T* (halfway between edges 1 and 2): edge 2 at `t_s` + 2.0 × *T*, then every 2 × *T*; the change completes at `t_s` + 2.0 × *T*. Rpm form: change to 0 rpm: no further edge, completes at once; then a change to +60 rpm continues from the reached angle. A series of 5 speed changes keeps all transitions legal and the position equal to the checker's angle model. | Sim |
| REQ-103 | A direction change (sign change of the rpm, or a new direction in the time form) takes effect at once, at the current angle, without hysteresis: if the next boundary has not been reached, the next edge re-crosses the boundary that was crossed last. Speed and direction may be changed in the same command. | High | §4.7, A-18, A-13 | Forward rotation from 0° at `t_s` with *T*, reverse at `t_s` + 0.75 × *T* (0.25 edge angle past the first edge): the next edge is a reverse edge at `t_s` + 1.0 × *T*, then every *T*. The state is the one before the first edge. The change command completes at `t_s` + 1.0 × *T*. | Sim |
| REQ-104 | A stop ends the rotation at once. The shaft stays at the reached angle, including its sub-edge fraction, and no further edge follows. The stop command completes at once. **(D-12, D-25, D-50)** | High | §4.7, A-19 | Forward from 0°, *T*: stop at `t_s` + 1.75 × *T* (7.875°): no further edge, the command completes at the stop time, and the status angle is 7.875°. A following forward start at *T* emits its first edge 0.75 × *T* after it starts (boundary 11.25°), a reverse start 0.25 × *T* after it starts (boundary 6.75°). Stop exactly on a boundary at `t_s` + 1.5 × *T* (6.75°): the edge at that time is emitted first, and a following reverse start emits its first edge at its start. | Sim |
| REQ-105 | While a rotation is active (also at 0 rpm), a move (edge, angle, move to state), centre state, a fault event (set angle, jump) and a second rotation start are rejected with `TB_ERROR`. The rotation continues unchanged. **(D-14)** | High | §4.7, A-20 | One `TB_ERROR` per rejected command. Edge times stay as in REQ-101. | Sim |
| REQ-106 | A speed change while no rotation is active is rejected with `TB_ERROR`. A stop while no rotation is active raises an alert of configurable severity (default `TB_WARNING`) and does nothing else. **(D-15)** | Medium | §4.7 | One alert of the expected severity per call. No event on A/B/Z. | Sim |
| REQ-107 | `terminate_current_command` during a rotation stops it at once at the current angle, as a stop (REQ-104), whether the executor is idle, waits for the first edge of a rotation command, or runs another command (which is terminated as usual). `flush_command_queue` does not affect a rotation. The outputs remain in a legal state. **(D-13, D-102)** | High | §4.7, UVVM convention | After `terminate_current_command` with the executor idle, during `insert_delay` and during a speed change: no further event on A/B/Z, the delay and the speed change complete at the terminate. The checker position equals the BFM position, and a following move continues legally (it is not terminated). After `flush_command_queue`, the rotation continues as in REQ-101. | Sim |
| REQ-108 | During a rotation, the signal configuration (bounce, jitter, index width/state/polarity/position, stuck outputs, alert severities) is read **after every edge**: each edge uses the configuration that was valid when the edge before it was emitted (the first edge after a rotation start or speed change: the configuration at that command). A change between edges k and k+1 therefore takes effect from edge k+2. The geometry (`cycles_per_rev`, zero state, edge offsets) is read at the rotation start, because it defines the angle model; a geometry change during a rotation takes effect at the next rotation start or move. **(D-16, D-101)** | Medium | §4.7, UVVM convention | Bounce enabled between edges k and k+1 of a rotation: edges k and k+1 are unbounced, edge k+2 and later bounce. `cycles_per_rev` changed during a rotation: the edge spacing and index placement stay unchanged until the rotation is stopped. | Sim |
| REQ-109 | Index (incl. Z polarity), bounce and jitter behave in a rotation as in moves (REQ-032, REQ-040 to REQ-042, REQ-046, REQ-050 to REQ-056, REQ-061, REQ-062). | High | §4.7 | The index, bounce and jitter checks of the tests of those features pass with the stimulus given as a rotation instead of moves. | Sim |
| REQ-110 | Invalid rotation parameters are rejected with `TB_ERROR`: `time_per_edge` ≤ 0 ns, a non-finite rpm, or a `duration` ≤ 0 ns of the BFM procedure `rotary_encoder_rotate`. 0 rpm is a valid rotation speed. A rejected start does not start a rotation; a rejected change leaves the rotation unchanged. **(D-88)** | High | §4.4, A-17 | One `TB_ERROR` per invalid call. No change of the outputs or of the running rotation. `rotary_encoder_rotate` with a duration of 0 ns and −1 ns: one `TB_ERROR` each, no event, no time consumed. | Sim |
| REQ-111 | A rotation start or speed change can give a speed profile: a list of signed rpm entries and a `time_per_entry` > 0. Time 0 is the moment the profile takes effect; entry *j* is the speed from *j* × `time_per_entry` to (*j* + 1) × `time_per_entry`, and each entry boundary is a speed change as REQ-102/REQ-103. The command completes at the first edge after the profile takes effect, or at the end of the profile's first pass if that pass produces no edge. **(D-20, D-24, D-42)** | Medium | §4.7.1, A-21 | Rpm form, from the centre of a state, `time_per_entry` = 25 ms, end *hold*. Profile (60, 120) rpm: edges at `t_s` + 6.25, 18.75, 28.125, 34.375, 40.625, 46.875 ms, then every 6.25 ms; the command completes at `t_s` + 6.25 ms. Profile (0, 60) rpm: no edge before `t_s` + 25 ms, first edge and completion at `t_s` + 31.25 ms. Profile (60, −60) rpm: forward edges at 6.25 and 18.75 ms, then reverse edges at 31.25, 43.75 ms, … Profile (0): completes at `t_s` + 25 ms. Every edge within one resolution step. With jitter enabled, REQ-061 holds per entry. A profile of the maximum length (256 entries, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH`) is accepted. | Sim |
| REQ-112 | The end behaviour of a profile is chosen per call: *hold* continues at the last entry's speed, *stop* stops at the end of the last entry as REQ-104, *repeat* restarts at entry 0. **(D-17)** | Medium | §4.7.1, A-21 | Profile (60, 120) rpm, 25 ms, as REQ-111. *hold*: after 46.875 ms every 6.25 ms (53.125, 59.375 ms, …). *repeat*: 56.25, 68.75 ms, then 78.125 ms, … *stop*: no edge after 46.875 ms, at rest at 27° at `t_s` + 50 ms; a following stop raises the REQ-106 alert. | Sim |
| REQ-113 | A speed change, with or without a profile, replaces a running profile at once (REQ-102). | Medium | §4.7.1, A-18 | A plain speed change during a profile: from then on the spacing is the new constant `time_per_edge`, and no further profile entry is used. | Sim |
| REQ-114 | Invalid profiles are rejected with `TB_ERROR` and do not change the rotation state: an empty profile, a non-finite entry, `time_per_entry` ≤ 0 ns, or more entries than the maximum (256). | Medium | §4.7.1 | One `TB_ERROR` per invalid call. No change of the outputs or of a running rotation. | Sim |
| REQ-115 | A single BFM function returns a linear-ramp profile of N entries from a start to an end rpm: entry *j* = rpm₀ + (rpm₁ − rpm₀) × *j* / (N − 1). N = 1 returns the start value. **(D-18)** | Low | §4.7.1, A-22 | 0 → 3000 rpm, N = 4: 0, 1000, 2000, 3000 rpm. −60 → 60 rpm, N = 3: −60, 0, 60 rpm. N < 1 or a non-finite value raises `TB_ERROR`. | Sim |

**Counts:** 71 features (9 Critical, 28 High, 27 Medium, 7 Low). IDs that are not listed were removed and are not reused (REQ-005, REQ-020 to REQ-027, REQ-030, REQ-031, REQ-043, REQ-044, REQ-072, REQ-073).

---

## 4. Architecture

### 4.1 References

| VIP | Role | Used for |
|---|---|---|
| `p2l2_vip_pwm` (branch `p2l2_vip_pwm`, commit `bb4b0c91`) | Primary structural reference | File layout (BFM, `transaction_pkg`, `vvc_cmd_pkg`, `vvc_methods_pkg`, `vvc_context`, VVC entity), the separate waveform process that keeps the executor free during continuous operation (`start_req`/`update_req`/`stop_req`/`abort_req` with index acknowledges), `GC_<NAME>_BFM_CONFIG` driven from time 0, transaction info, `insert_delay` without clock, BFM overloads with an abort signal, testbench layout, integration commit as precedent |
| `bitvis_vip_clock_generator` | Secondary structural reference | Official precedent for a free-running background process next to the executor (`p_clock_generator`), start/stop/set-parameter command naming, a clock-less signal-level VVC |
| `bitvis_vip_gpio` | Scripts and per-VIP files; status read-back | Official source of `test.py` and the per-VIP files (D-65); a queued "get" command with `fetch_result()` (`gpio_get`) – the pattern for U-2 |
| `bitvis_vip_spi` | Convention only | Interface record type with `init_<name>_if_signals()` for a multi-signal port |

**Convention profile** (survey over all 23 VVC entities and 13 BFM packages in the checkout):

| Topic | Majority convention | Applied here |
|---|---|---|
| File header | UVVM Apache-2.0 banner, `Copyright 2024 UVVM` (13 BFMs); PWM `Copyright 2026 UVVM` | UVVM banner, `Copyright 2026 UVVM` (D-35) |
| BFM config record | `t_<name>_bfm_config`, constant `C_<NAME>_BFM_CONFIG_DEFAULT`, fields `id_for_bfm` (26×), `id_for_bfm_wait` (16×) | `t_rotary_encoder_bfm_config`, both message-ID fields |
| BFM scope | `C_BFM_SCOPE : string := "<NAME> BFM"` (spaces 9×, underscores 4×) | `"ROTARY ENCODER BFM"` |
| BFM parameter order | operation parameters, (output variables), `msg`, signal(s), `scope`, `msg_id_panel`, `config` | Same; the inout `state` variable comes before `msg` (as PWM's seeds and SBI's `data_value`) |
| VVC method parameter order | `VVCT`, `vvc_instance_idx`, parameters, `msg`, `scope`, `parent_msg_id_panel` | Same |
| Multi-signal port | Record type `t_<name>_if` + `init_<name>_if_signals()`, `inout` port `<name>_vvc_if` (10 BFMs) | `t_rotary_encoder_if`, port `rotary_encoder_vvc_if` |
| VVC generics | `GC_INSTANCE_IDX`, the six queue generics (23×), BFM config as `GC_<NAME>_BFM_CONFIG` (RGMII, GMII, Wishbone, PWM) or `GC_<NAME>_CONFIG` (UART, SPI, SBI) | `GC_ROTARY_ENCODER_BFM_CONFIG` (PWM precedent) |
| Per-VIP size constants | `C_<NAME>_VVC_CMD_STRING_MAX_LENGTH`, `C_<NAME>_VVC_MAX_INSTANCE_NUM` in `adaptations_pkg`, aliased in `transaction_pkg` | Same, plus `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` (D-42, like `C_RGMII_VVC_CMD_DATA_MAX_BYTES`) |
| `t_vvc_config` | Standard fields; VVC-level extras are common (`unwanted_activity_severity` 14×, `clock_period` in clock_generator) | One extra field `stop_when_idle_severity` (REQ-106) |
| `t_vvc_status` | Never extended (0 of 23) | Not extended; U-2 uses `fetch_result()` |
| Type names | Prefixed with the VIP name; the framework already declares `t_direction` | Every public type is `t_rotary_encoder_*` |
| Helper visibility | Some official BFMs declare helpers publicly (e.g. `odd_parity` in UART) | Helpers are body-only (deviation DV-1, 4.11) |

### 4.2 Naming and identity

| Item | Value | Reason |
|---|---|---|
| VVC name given to the generator (D-33) | `rotary_encoder` → `rotary_encoder_vvc`, `rotary_encoder_bfm_pkg`, `ROTARY_ENCODER_VVCT`, `C_VVC_NAME = "ROTARY_ENCODER_VVC"` | The spec's own name; unambiguous |
| Library and directory (D-34) | `p2l2_vip_rotary_encoder` | Same prefix as `p2l2_vip_pwm` and `p2l2_vip_mdio`. Not `bitvis_` (reads as official UVVM) and not `external_vip_` (used for contributed VIPs merged upstream). The generator writes `library vip_rotary_encoder;` into `vvc_context.vhd`; replaced after generation |
| File header (D-35) | UVVM Apache-2.0 banner as in `p2l2_vip_pwm`, `Copyright 2026 UVVM`, plus `LICENSE.TXT` copied from the official reference | Same as the PWM precedent |
| Procedure prefix | `rotary_encoder_` for every BFM procedure and VVC method | UVVM convention: BFM procedure and VVC method share the name |

**Protocol term mapping**

| Spec term (§) | Meaning | VHDL identifier | Where |
|---|---|---|---|
| A, B, Z (§3) | Quadrature channels and index | record fields `a`, `b`, `z` of `t_rotary_encoder_if` | Port, BFM signal |
| State `AB` (§2) | 2-bit value of the channels | `std_logic_vector(1 downto 0)`, bit 1 = A, bit 0 = B; fields `zero_state`, `index_state`, `target_state` and result field `ab`, all A/B levels on the output pins (spec A-03) | Config, result |
| Edge (§2) | One transition on A or B | `edge`: `num_edges`, `rotary_encoder_move_edges` | BFM, VVC |
| Zero state (§2, A-06) | State at angle 0° (position 0) | `zero_state : std_logic_vector(1 downto 0)` | Config (init only) |
| `cycles_per_rev` (§2) | Cycles per revolution | `cycles_per_rev` | Config, conversions |
| Angle (§4.6) | Shaft angle in degrees | `angle : real` | BFM, VVC, result |
| Speed (§4.4) | rpm, signed for rotations | `rpm : real` | BFM, VVC, result |
| `time_per_edge` (§4.4) | Edge interval | `time_per_edge : time` | BFM, VVC |
| Forward / reverse (§4.1) | Direction | `t_rotary_encoder_direction` = (`FORWARD`, `REVERSE`) | BFM, VVC |
| Index polarity (A-10) | Z active low | `index_inverted : boolean` | Config |
| Index width (A-10) | 1–4 states (90° to 360° electrical) | `index_width : integer` | Config |
| Index position `p_idx` (§6) | First position of the index cycle, in edges from position 0 | `index_position : integer` | Config |
| Bounce, `t_bounce` (§5) | Contact bounce, window | `bounce_enabled`, `bounce_pulses`, `bounce_window`, `bounce_placement` | Config |
| Jitter *j* (A-05) | Phase error in electrical degrees | `jitter : real` (0.0 = off) | Config |
| Set angle, jump (A-12) | Fault events; set angle also for a known angle | `rotary_encoder_set_angle`, `rotary_encoder_jump_edges` | BFM, VVC |
| Edge offset (A-25) | Device fault: displaced edge, electrical degrees | `a_rise_offset`, `a_fall_offset`, `b_rise_offset`, `b_fall_offset : real` | Config |
| Stuck channel (A-26) | Device fault: output held at a level | `a_stuck`, `b_stuck`, `z_stuck : std_logic` (`'-'` = not stuck) | Config |
| Move to state (A-27) | To the centre of the *n*-th following state equal to a target state | `rotary_encoder_move_to_state` (`target_state`, `occurrence : natural`) | BFM, VVC |
| Centre state (A-28) | To the centre of the current state, zero time | `rotary_encoder_center_state` | BFM, VVC |
| Rotation (§4.7) | Continuous movement | `rotary_encoder_start_rotation`, `rotary_encoder_set_speed`, `rotary_encoder_stop_rotation` | VVC |
| Profile, `time_per_entry`, end behaviour (A-21) | Speed over time | `profile : real_vector`, `time_per_entry : time`, `t_rotary_encoder_profile_end` = (`PROFILE_HOLD`, `PROFILE_STOP`, `PROFILE_REPEAT`) | BFM, VVC |
| Start angle (A-16) | Power-up angle | `start_angle : real` | Config |

Reserved-word check: none of the identifiers is a VHDL or VHDL-AMS reserved word. `STOP` is avoided as an enumeration literal (it would hide `std.env.stop`), hence `PROFILE_STOP`.

### 4.3 Feature configuration

| Feature | Configuration | Reason |
|---|---|---|
| Channels | One channel (`NA`) | One encoder per instance (U-3); A/B/Z are one interface |
| Executors | One command executor (generator: no multiple executors) **plus** a hand-written process `p_motion` (D-36) | `p_motion` is the only driver of the port. The executor stays free while a rotation runs (PWM `p_waveform` precedent, clock_generator `p_clock_generator`) |
| BFM | Full BFM usable without the VVC (REQ-080): init, moves, timed rotation, fault events, status, conversions, ramp; device faults through the configuration | 4.5 |
| Commands | Queued: moves, rotation start/speed change/stop, fault events (set angle, jump), centre state, status read; standard UVVM commands | 4.6 |
| Results | `rotary_encoder_get_status` stores a `t_rotary_encoder_status` in the result queue for `fetch_result()` | U-2 (D-44) |
| Transaction Info | **Included**, base transaction only (no sub/compound transactions) | Cheap, conventional, used by PWM |
| Scoreboard | **Excluded** | Encoder only; the VVC receives no data to compare |
| Unwanted Activity Detection | **Excluded** | No DUT outputs are observed |
| Monitor / checker | **Excluded** from the VIP | The checker that verifies the encoder is part of the maintenance testbench (Test plan 7.3) |
| `insert_delay` with clock cycles | `TB_ERROR` (no clock) | PWM precedent |
| Inter-BFM delay | Applies to moves and fault events; rotation commands are not delayed | They act on a running rotation (PWM precedent) |

### 4.4 Physical interface and entity

```vhdl
-- in rotary_encoder_bfm_pkg
type t_rotary_encoder_if is record
  a : std_logic;  -- Quadrature channel A
  b : std_logic;  -- Quadrature channel B
  z : std_logic;  -- Index pulse, leave unconnected if the encoder has none
end record t_rotary_encoder_if;

function init_rotary_encoder_if_signals(constant dummy : t_void) return t_rotary_encoder_if; -- all 'Z'

entity rotary_encoder_vvc is
  generic (
    GC_INSTANCE_IDX                          : natural                     := 1;
    GC_ROTARY_ENCODER_BFM_CONFIG             : t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT;
    GC_CMD_QUEUE_COUNT_MAX                   : natural                     := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural                     := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level               := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural                     := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural                     := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level               := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port (
    rotary_encoder_vvc_if : inout t_rotary_encoder_if := init_rotary_encoder_if_signals(VOID)
  );
end entity rotary_encoder_vvc;
```

- No clock and no reset port: the encoder is asynchronous and has no reset input (spec §3, §7). The generator's `clk` port is removed.
- `inout` with `'Z'` initial values follows the official record-port VIPs. From the first delta, `p_motion` drives strong `'0'`/`'1'` on all three fields (A-01). With index disabled, Z is driven at its inactive level, not `'Z'` (REQ-040).
- `GC_INSTANCE_IDX` has the default 1 (the generator gives none).
- **Start state (D-46).** At time 0, `p_motion` initializes the encoder from `GC_ROTARY_ENCODER_BFM_CONFIG` (`start_angle`, `zero_state`, index), because `shared_rotary_encoder_vvc_config` is not set up yet at time 0 (PWM precedent). `vvc_constructor` copies the generic into `shared_rotary_encoder_vvc_config`, so both start equal. Changing `start_angle` in the shared configuration later has no effect; it is a power-up property. Changing `zero_state` later is `TB_ERROR` at the next command (D-40, D-32). Tests with several start angles use several instances or the BFM directly (D-62).

### 4.5 BFM (`rotary_encoder_bfm_pkg`)

#### 4.5.1 Angle model and state (D-37)

The BFM keeps the shaft in a public state record that the caller owns (`variable state : inout t_rotary_encoder_state`). The angle cannot be reconstructed from the signals (sub-edge fraction, last speed), so a state variable is unavoidable (DV-2); the VVC's copy lives in `p_motion`. Its fields are declared in the package (VHDL needs the full record) and commented as private (D-80): users only declare it, pass it, and read it through `rotary_encoder_get_status()`.

- **Position:** `position : integer` – the edge index of the current state; state centre *p* lies at *p* edge angles. Range ±2³¹ edges (≥ 26 million revolutions at 20 cycles/rev).
- **Sub-edge offset:** `offset : integer` in quanta, −K/2 ≤ offset ≤ +K/2, with **K = 900 000 000 quanta per edge**.
- **Why K = 9·10⁸:** one degree is 4 × `cycles_per_rev` × K / 360 = `cycles_per_rev` × 10⁷ quanta, an integer for every `cycles_per_rev`. Every angle with up to 7 decimals (0.1°, 1°, 2.25°, 1.125°…) converts exactly, so sums of moves are exact integer arithmetic: 3600 × 0.1° = exactly one revolution (REQ-091). An angle with more decimals (e.g. 1/3°) is rounded once per move to the nearest quantum (≤ 5.6·10⁻¹⁰ edge angles per move; 10⁹ such moves would be needed to shift one edge by 1 % of an edge angle).
- **Long moves:** the distance of one move is held as an integer-valued `real` (exact up to 2⁵³ quanta, i.e. 125 000 revolutions per move at 20 cycles/rev, 250 at 10 000 cycles/rev). Beyond that, `TB_ERROR`.
- **State mapping (D-40):** the state at position *p* is the forward Gray sequence (`00→10→11→01`) started at the **zero state** `state(0)` (A-13: angle 0° is the centre of the zero state). The zero state is taken from `config.zero_state` at initialization and kept in the state record. Every later procedure call (BFM) or command (VVC) compares `config.zero_state` with the kept value; a different or invalid value raises `TB_ERROR` and the call is not executed (REQ-006, D-32). So A/B are never remapped.
- **Boundaries with edge offsets (A-25):** the boundary between positions *p* and *p*+1 lies at (*p* + ½) edge angles plus the offset of that edge (A rise, A fall, B rise or B fall, identified by the level change in the forward direction from `state(p)` to `state(p+1)`), converted from electrical degrees to quanta (90° electrical = K). Each offset is in (−45°, +45°), so a boundary never passes a state centre: positions, the zero state, the index positions and the end of every move (state centres) are unchanged; only the edge angles move (REQ-075, REQ-076). The offsets are latched with the geometry at the motion start (D-26).
- **Boundary rule (D-39, spec A-13):** an edge is emitted when the angle *reaches* a boundary. A shaft that stands exactly on a boundary is in the state it moved into. This is the only rule that can be implemented deterministically: an edge due at time *t* is driven in the first delta cycle of *t*, before a stop, speed change or `terminate_current_command` issued at *t* can reach `p_motion`. Consequences: a move that ends exactly on a boundary emits that edge at its end; a following move in the same direction reaches the next boundary after a full edge angle (continuous, as one longer move); a following move in the opposite direction emits its first edge at its start, so two back-to-back commands give a state of zero length at that time step (two events on one channel at the same simulation time). This is the A-18 "short state" in its limit, not an illegal transition; the testbench checker accepts it.

#### 4.5.2 Edge-time computation (D-38, A-24)

- A **segment** is a stretch of constant speed: a move, a rotation between two speed changes, a profile entry. It is anchored at its start time `t0` (an exact `time`) and its start angle.
- The speed of a segment is held as `time_per_edge` split into a whole number of resolution units (`tpe_int : time`) and the fraction of a unit (`tpe_frac : real`, 0 ≤ `tpe_frac` < 1). In the time form `tpe_frac` = 0. In the rpm form both come from 60 s / (|rpm| × 4 × `cycles_per_rev`), split without converting large values to `integer` (pitfalls F-040, F-042). When |rpm| × 4 × `cycles_per_rev` is an integer (every integer rpm), `tpe_int` = 60 s / that integer and the remainder are computed exactly in `time` arithmetic and `tpe_frac` = remainder / divisor; otherwise both come from the `real` value. A `tpe_frac` taken from a `real` `time_per_edge` carries its rounding error, which `n × tpe_frac` multiplies (finding F-010).
- The time to reach a distance *d* quanta from the anchor is computed from scratch for every edge, with *d* = *n*·K + *r* (whole edges *n*, rest *r* < K):
  `t = t0 + n × tpe_int + round(n × tpe_frac + (r / K) × tpe_res)`, where `tpe_res` is `time_per_edge` in resolution units as `real`.
  The `time` part is exact; the `real` part stays small (< *n* + one edge interval), so every edge is within one resolution step of its ideal time and nothing accumulates (REQ-012, REQ-101). In the time form with an even number of resolution units per edge, the edges from a state centre are exact: (*k* − ½) × `time_per_edge`.
- When a segment ends between edges (speed change, stop, profile entry boundary, status request), the angle at that time is computed from the anchor and rounded once to a quantum. The next segment is anchored at the current simulation time. This is the only rounding at a speed change (spec §4.7: quantisation of the change time).
- **Jitter (A-05):** each emitted edge is moved by an offset drawn uniformly from ±`jitter`/90 × `time_per_edge` of the current segment (D-10, D-21), using the seeds in the state. The fraction *u* ∈ (−1, 1) is drawn once per edge and kept until the edge is emitted, so a repeated computation (a `run_motion` call after an interrupt) gives the same time; the displacement enters the formula above as an extra term of the `real` part, so the edge is still rounded once. The nominal time is not changed, so there is no carry-over. The jitter limit is half the narrowest state (REQ-063): in the forward direction the boundaries of a cycle are A rise, B rise, A fall, B fall, and the state after boundary *i* is 90° wide plus the offset of boundary *i* + 1 minus that of boundary *i*; then an edge can never be moved past the next one. The limit is latched with the geometry at the motion start. The distance *d* to the next boundary includes its offset, so the timing formula above is unchanged.
- **Jitter at a segment boundary (D-55):** a jittered edge stays inside its segment: it is not placed before the segment start, and for a move not after the move end. With a valid amplitude this only affects angle and move-to-state moves that start or end within *j*/90 edge angles of a boundary; move durations stay exact (REQ-092) and every edge belongs to its own command.

#### 4.5.3 Driving an edge

Each nominal edge (in a move or a rotation) does, at its (jittered) time:

1. Settle the channel that bounced at the previous edge if its bounce has not ended yet (cut-off, REQ-056): drive its settled value, cancel its remaining toggles (a `transport` assignment deletes later transactions), raise `config.bounce_cut_severity` once per command. If the channel is at its bounced level at that moment, the settle is an event, and the edge follows **one delta later** at the same simulation time (D-57); otherwise the settled channel and the other channel would change in the same delta (an illegal transition for the decoder). The two log entries at one time are legal transitions (a zero-length state, as D-39). If the channel is already at its settled level, the edge follows in the same delta.
2. Drive the new state on A and B as it is (states are pin levels, spec A-03); an output whose `*_stuck` is not `'-'` drives its stuck level instead (REQ-078). The stuck setting is also applied at the start of every command, so a release shows at the next command (D-29).
3. Drive Z from the nominal position with the index decision of 4.5.4 (never bounces, D-4; follows the displaced edges, REQ-077), mapped through `index_inverted`, or `z_stuck`. The **signal configuration** – index (`index_enabled`, `index_width`, `index_state`, `index_position`, `index_inverted`), bounce (`bounce_window` with bounce enabled) and `jitter` (against the latched limit, 4.5.2) – is validated at every `rotary_encoder_run_motion` call; an invalid value raises `TB_ERROR` once (again only after the value has changed), and the edges use the last valid signal configuration, which the state record holds (REQ-045, D-31; bounce and jitter D-56). A motion only starts with a valid signal configuration, so this can only happen when the configuration changes during a VVC rotation.
4. With bounce enabled and the changing output not stuck, schedule `2 × bounce_pulses` toggles of the changing channel within `bounce_window` as `transport` assignments, ending at the new value. Random placement takes `2 × bounce_pulses` uniform draws in (0, `bounce_window`) from the state's seeds and sorts them (D-54, A-08 "uniformly random"); even placement spaces them `bounce_window` / (2 × `bounce_pulses` + 1). A toggle that rounds to the edge time or to the previous toggle is moved one resolution step later, so the number of toggles is always exact (REQ-051). The bounce is scheduled after the edge has been driven, so its window starts at the actual (jittered) edge. Bounce placement and jitter draw from the same seeds in the state, in edge order (jitter of edge *k*, then the bounce of edge *k*), so enabling bounce changes the jitter sequence of a seed (D-58, REQ-057).

No signal option changes A or B outside an edge: there is no A/B polarity inversion (spec Q-15) and no direction swap (spec Q-14); for a "B leads A" DUT, A and B are crossed in the port map (4.9).

#### 4.5.4 Index (D-41)

Spec §6, A-10. Positions are taken modulo 4 × `cycles_per_rev` (the latched geometry).

- **Index cycle:** the positions `index_position` … `index_position + 3`. It contains each of the four states once, so exactly one position *q* in it has `state(q) = index_state` (A/B levels on the pins).
- **Z active** at *q* … *q* + `index_width` − 1 (forward; their states follow the index state in the order `00 → 10 → 11 → 01`). These may lie outside the index cycle.
- Defaults (`index_position` 0, `index_state` 11 = zero state, width 1): *q* = 0, Z active at 0° (spec §7 example). Spec §6 examples: zero state `00`, index state `00`, width 2 → Z at 0 and 1; zero state `11`, index state `00`, width 1 → Z at position 2.
- The decision is a pure function in the package body; the testbench checker implements it independently (Test plan 7.3).

#### 4.5.5 Motion engine (low-level public API)

All movement – moves, rotations, profiles – runs through one engine in the package body. It is exposed through three low-level procedures, because the VVC needs to interrupt and resume a motion (speed change, stop, status, terminate) and to re-read the configuration at every edge (REQ-108). The user-level procedures (4.5.6) use the same engine routines, so BFM and VVC behave identically.

- `rotary_encoder_set_motion(motion, state, …)` – zero time, but **time-relevant** (name: D-84): makes `motion` the active motion at `now`. It ends a running motion at the current angle (that is where a speed change takes effect, A-18), validates the motion, checks `zero_state` against the kept value (D-32), latches the geometry (`cycles_per_rev`, edge offsets) into the state, resolves `MOTION_TO_STATE` from the angle at `now`, and anchors the first segment at `now`: from this moment the shaft moves in the model. It drives no output; `rotary_encoder_run_motion` must follow in the same time step, otherwise the edges are late.
- `rotary_encoder_run_motion(state, event, …, interrupt, …)` – runs the active motion until the next nominal edge (`MOTION_EDGE`), the end of a profile pass (`MOTION_PROFILE_PASS`), the end of the motion (`MOTION_DONE`, the shaft is at rest), or an event on the `interrupt` signal (`MOTION_INTERRUPTED`). Returning never changes the motion: the next call continues the same segment from the same anchor, so returning at every edge costs no accuracy. Each call first applies a changed stuck setting of its `config` (only the changed outputs are driven), so a VVC move releases or sets a stuck output at its start like the user-level procedures (D-97).
- `rotary_encoder_halt_motion(state)` – zero time. Ends the active motion at the current angle. Used for a stop and for `terminate_current_command` (REQ-082, REQ-104, REQ-107; D-50).

**Calling sequence.** One process owns the state and the port and calls the three procedures:

| Situation | Calls |
|---|---|
| Start a move or rotation (VVC: `REQ_MOTION`) | `set_motion(motion)`, then `run_motion` in a loop |
| Speed change or new profile during a rotation | `set_motion(new rotation)` (replaces the running one at `now`, keeps the angle), then continue the `run_motion` loop |
| Stop, `terminate_current_command` | `halt_motion` (zero time; the shaft stays at the reached angle) |
| Status during a motion | `run_motion` returned `MOTION_INTERRUPTED`; `rotary_encoder_get_status(state)`, then continue the `run_motion` loop (the segment anchor is unchanged, so no accuracy is lost) |

`run_motion` returns at every nominal edge (`MOTION_EDGE`: re-read the configuration, acknowledge a first edge), at the end of a profile pass (`MOTION_PROFILE_PASS`), when the shaft is at rest (`MOTION_DONE`), or when `interrupt` has an event (`MOTION_INTERRUPTED`: a new request; the motion itself is unchanged). The loop in `p_motion` (4.6.1):

```vhdl
loop
  if motion_req.idx = v_handled_idx and not v_motion_active then
    wait on motion_interrupt;                -- idle: wait for the next request
  end if;
  if motion_req.idx /= v_handled_idx then    -- pending request, detected by index (a delta wait in run_motion can
    handle_request;                          -- absorb the event): set_motion / halt_motion / status / fault event;
  end if;                                    -- sets v_motion_active, responds on motion_rsp
  if v_motion_active then
    -- config: a move uses the configuration taken at its start (REQ-084); a rotation the one taken after its last edge (REQ-108)
    rotary_encoder_run_motion(v_state, v_event, msg, rotary_encoder_vvc_if, motion_interrupt, config => v_run_config);
    case v_event is
      when MOTION_EDGE         => null;      -- respond to a rotation start/change at its first edge; rotation: take the
                                             -- shared configuration for the next edge
      when MOTION_PROFILE_PASS => null;      -- respond to a profile without edges (D-24)
      when MOTION_DONE         => v_motion_active := false;  -- respond to the move; a profile with PROFILE_STOP ended
      when MOTION_INTERRUPTED  => null;      -- a new request: handled in the next pass, the motion is unchanged
    end case;
  end if;
end loop;
```

The user-level BFM procedures (4.5.6) do not use the three procedures: they have no interrupt signal and run a motion to its end with the same private engine routines (validation, segment, next event, edge step), so BFM and VVC timing are identical.

**Documentation (D-47):** the engine stays public. Every engine declaration carries the comment `-- Used by the VVC.` in the package, and the RST documentation lists the engine in its own section "Low-level motion engine (used by the VVC)" after the user-level procedures, with a note that testbenches normally use the user-level procedures or the VVC. The API-coverage check of the documentation treats them as public API.

`t_rotary_encoder_motion` is a public record that describes one motion (kind, direction, count, angle, speed form, rpm, `time_per_edge`, profile, `time_per_entry`, end behaviour). The profile is a fixed array of `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` entries plus a length (D-42); the BFM reads the constant directly from `adaptations_pkg` (D-82). The same record is a field of the VVC command record.

Motion kinds: `MOTION_EDGES`, `MOTION_ANGLE`, `MOTION_TO_STATE`, `MOTION_ROTATION` (constant speed or profile). `MOTION_TO_STATE` is resolved in `rotary_encoder_set_motion` into an angle move (D-51): from the current position *p* (the state the shaft is in, A-13 boundary rule), step through *p*±1, *p*±2, … in the move direction and take the `occurrence`-th position whose state equals `target_state`; the distance is from the current angle (incl. sub-edge offset) to that centre, in exact quanta. Every 4 consecutive positions hold each state once, so the first match lies at *k*₁ ∈ 1…4 steps and the `occurrence`-th at *k*₁ + 4 × (`occurrence` − 1): a closed form, no loop over large occurrences. A stop is not a motion: it is `rotary_encoder_halt_motion` (D-50). A profile with `PROFILE_STOP` halts itself at the end of its last entry.

#### 4.5.6 User-level BFM procedures

| Procedure | Behaviour | Completes |
|---|---|---|
| `rotary_encoder_init` | Initializes the state from `config` (`zero_state` kept, start angle used as given, A-16; seeds) and drives A/B/Z. No edges. Validates `cycles_per_rev`, `zero_state`, the edge offsets and the signal configuration (4.5.3 step 3) like a command: `TB_ERROR`, the state stays as it was. The start angle is placed in the state that contains it with the edge offsets (D-90) | At once |
| `rotary_encoder_move_edges` (rpm, time) | N edges (REQ-010…013) | N × `time_per_edge` after the start |
| `rotary_encoder_move_angle` (rpm, time) | Angle move, ends exactly at the target angle (REQ-090…093) | φ / edge angle × `time_per_edge` after the start |
| `rotary_encoder_rotate` (rpm; direction + time; profile) | Rotates for `duration`, then stops at once at the reached angle (A-19, D-48). With a profile and `PROFILE_STOP`, it may end earlier. `duration` ≤ 0 ns is `TB_ERROR` (D-88) | After `duration` (or at the profile end) |
| `rotary_encoder_move_to_state` (rpm, time) | Angle move to the centre of the `occurrence`-th following state equal to `target_state`; the current state is never counted (REQ-096, A-27) | When at the target centre |
| `rotary_encoder_center_state` | Places the shaft at the centre of its current state in zero time; only the offset in the state record changes, no output event (REQ-097, A-28). While a motion is active (only possible through the low-level engine) it raises `TB_ERROR` and changes nothing (D-59); the VVC rejects it during a rotation itself (REQ-105) | At once |
| `rotary_encoder_set_angle` | Places the shaft at an absolute angle in zero time. Not a power-up (REQ-071, D-30) | At once |
| `rotary_encoder_jump_edges` | Moves the shaft by N edges in zero time from the current angle, sub-edge fraction kept (REQ-071, D-3). A target position beyond ±(`integer'high` / 2) is `TB_ERROR` (D-94) | At once |
| `rotary_encoder_get_status` (function) | Position, angle, state, Z, rotation flag, signed rpm at `now` | – |
| Conversions (functions) | rpm ↔ `time_per_edge`, rpm ↔ degrees per second (REQ-095) | – |
| `rotary_encoder_linear_ramp` (function) | Linear profile of N entries (REQ-115, D-18); after a `TB_ERROR` it returns an empty profile (D-92) | – |

For `set_angle` and `jump_edges`: the outputs change from the old to the new state in one delta (edge distance mod 4 = 2: illegal transition; 0: lost cycles; 1/3: one edge), no bounce or jitter, Z without pulses for skipped positions; on a boundary the shaft stays on the side of the old angle. A bounce still running from the last edge is settled first, without the cut-off alert (D-91).

Every procedure that takes a state raises `TB_ERROR` and returns at once if the state was not initialized with `rotary_encoder_init`. Invalid parameters and configuration (REQ-006, 016, 045, 054, 063, 074, 076, 079, 094, 098, 110, 114) raise one `TB_ERROR` and produce no edge. Every procedure that checks the kept zero state takes `config` (D-83). Each completed move and fault event is logged with `config.id_for_bfm`: direction, edge count, end position and angle (REQ-085).

#### 4.5.7 Configuration record

| Field | Type | Default | Read | Source |
|---|---|---|---|---|
| `cycles_per_rev` | `integer` | 20 | motion start | A-10, §2 |
| `zero_state` | `std_logic_vector(1 downto 0)` (pin levels) | `"11"` | init; checked unchanged at every call/command (D-32) | A-06, REQ-006 |
| `start_angle` | `real` | 0.0 | init | A-16 |
| `index_enabled` | `boolean` | `true` | every edge | §6 |
| `index_width` | `integer` (1 to 4 states) | 1 | every edge | A-10, REQ-042 |
| `index_state` | `std_logic_vector(1 downto 0)` (pin levels) | `"11"` | every edge | A-10 |
| `index_position` | `integer` | 0 | every edge | §6 |
| `index_inverted` | `boolean` | `false` | every edge | A-10 |
| `bounce_enabled` | `boolean` | `false` | every edge | A-07 |
| `bounce_pulses` | `natural` | 2 | every edge | A-07, D-9, D-43 |
| `bounce_window` | `time` | 1 ms | every edge | A-07, D-43 |
| `bounce_placement` | `t_rotary_encoder_bounce_placement` = (`BOUNCE_RANDOM`, `BOUNCE_EVEN`) | `BOUNCE_RANDOM` | every edge | A-08 |
| `jitter` | `real` (electrical degrees) | 0.0 (off) | every edge | A-05 |
| `a_rise_offset`, `a_fall_offset`, `b_rise_offset`, `b_fall_offset` | `real` (electrical degrees, named by the pin level change) | 0.0 | motion start | A-25, D-26, D-28 |
| `a_stuck`, `b_stuck`, `z_stuck` | `std_logic` (`'0'`, `'1'`, `'Z'`; `'-'` = not stuck) | `'-'` | command start and every edge | A-26, D-27, D-29 |
| `rand_seed1`, `rand_seed2` | `positive` | `C_RAND_INIT_SEED_1/2` | init | REQ-053, 057, 062 |
| `bounce_cut_severity` | `t_alert_level` | `TB_WARNING` | every edge | REQ-056, D-22 |
| `id_for_bfm` | `t_msg_id` | `ID_BFM` | – | convention |
| `id_for_bfm_wait` | `t_msg_id` | `ID_BFM_WAIT` | – | convention |

"Read" shows where the value is taken: *motion start* is the geometry latched by `rotary_encoder_set_motion` (REQ-084, REQ-108); *every edge* is the signal configuration, which during a VVC rotation is taken from the shared VVC configuration after each edge, for the edge after it (REQ-108, D-101). Integer fields that have a valid range (`cycles_per_rev`, `index_width`) are `integer`, not `positive`, so an invalid value raises the required `TB_ERROR` instead of a range failure.

### 4.6 VVC

#### 4.6.1 Processes

| Process | Role |
|---|---|
| `p_cmd_interpreter` | Generated; one change: `TERMINATE_CURRENT_COMMAND` while a rotation runs also halts the rotation through `halt_req`, whatever the executor does (4.6.2, D-102) |
| `p_cmd_executor` | Fetches commands, logs, sets transaction info, sends a **motion request** to `p_motion` and waits for its response (on `terminate_current_command` it sends `REQ_HALT`). Never drives the port |
| `p_motion` | The only driver of `rotary_encoder_vvc_if` and the owner of the encoder state, so it also decides the rejections that depend on the rotation state (REQ-105, REQ-106; D-105). At time 0 runs `rotary_encoder_init` with the generic. Then: idle → wait for a request; motion active → `rotary_encoder_run_motion` with `interrupt` = `motion_interrupt`. A move runs with the `vvc_config.bfm_config` taken at its start (REQ-084); a rotation with the one taken at its start or speed change and again after every edge (REQ-108, D-96, D-101) |
| `cmd_terminator` | Generated flag handler |

Executor ↔ `p_motion` (PWM pattern of indexed requests; one response per request, D-99):

| Signal | Content |
|---|---|
| `motion_req` | `(idx, kind, cmd, msg_id_panel)`: `kind` ∈ {`REQ_MOTION` (move, rotation start or speed change, by `cmd.operation`), `REQ_STOP`, `REQ_HALT`, `REQ_STATUS`, `REQ_SET_ANGLE`, `REQ_JUMP_EDGES`, `REQ_CENTER_STATE`}; `cmd` is the whole command record (parameters, `proc_call`, `msg`, `cmd_idx`, and `has_profile` for a rotation command given as a profile, so that an empty profile can be rejected) |
| `motion_rsp` | `(idx, accepted, edges, status)`: request `idx` is complete – a move at rest, a zero-time operation or a status read done, a stop or halt done, a rotation start/change at its first edge after the change (an edge at the change time itself belongs to the old motion, D-25, D-104; with no edge, at its completion point per D-24), a request rejected with `TB_ERROR` at once (`accepted` false; also a stop without rotation). `edges` and `status` (a `t_rotary_encoder_status` snapshot) at that time |
| `rotation_active` | `true` from an accepted rotation start until its stop, halt or profile end |
| `halt_req` | Interpreter → `p_motion`: halt a running rotation on `terminate_current_command` (4.6.2) |
| `motion_interrupt` | `motion_req.idx + halt_req`, the `interrupt` actual of `rotary_encoder_run_motion` |

#### 4.6.2 Command semantics

| Command | Rejected when | Completes |
|---|---|---|
| `rotary_encoder_move_edges/_angle/_to_state` | rotation active → `TB_ERROR`, dropped (REQ-105, D-14); invalid → `TB_ERROR` (REQ-098) | when the shaft is at rest (end of the move). `_to_state` is resolved when `p_motion` starts it, i.e. at execution time (REQ-096) |
| `rotary_encoder_start_rotation` | rotation active → `TB_ERROR`; invalid speed/profile → `TB_ERROR`, nothing started | at the first edge; at once for 0 rpm; for a profile at its first edge or the end of its first pass if that has none (D-11, D-24) |
| `rotary_encoder_set_speed` | no rotation → `TB_ERROR` (REQ-106); invalid → `TB_ERROR`, rotation unchanged | as the start; replaces a running profile (REQ-113) |
| `rotary_encoder_stop_rotation` | no rotation → `stop_when_idle_severity` (default `TB_WARNING`), no effect | at once, at the reached angle (REQ-104, D-12, D-50) |
| `rotary_encoder_set_angle`, `rotary_encoder_jump_edges`, `rotary_encoder_center_state` | rotation active → `TB_ERROR` | at once |
| `rotary_encoder_get_status` | – | at once; the result is the state at the execution time, mid-rotation included |
| `terminate_current_command` | – | Move: halt at once at the current angle. Rotation: halt at once, as a stop, whatever the executor does; a command in the executor (e.g. `insert_delay`, a speed change waiting for its first edge) is terminated as well (D-13, D-102, REQ-082, REQ-107) |
| `flush_command_queue` | – | Does not touch a running rotation (REQ-107) |
| `insert_delay` (time) | – | as usual; with clock cycles: `TB_ERROR` |

Every command that starts a motion or a fault event checks `zero_state` and the index configuration first (D-31, D-32): `TB_ERROR`, the command is dropped.

`terminate_current_command` and a running rotation: the framework's `interpreter_terminate_current_command` sets the terminate flag only while the executor is busy (`td_vvc_entity_support_pkg.vhd:760`), and the flag only reaches the command in the executor. A rotation runs on after its start command has completed, so the flag cannot halt it (F-004). Therefore the VVC's interpreter first increments its own signal `halt_req` (logged with `ID_IMMEDIATE_CMD`) whenever `rotation_active` is true, and then calls the framework procedure as usual, which terminates a command in the executor (that command's `REQ_HALT` then finds the rotation already halted). `p_motion` is interrupted by either signal (`motion_interrupt <= motion_req.idx + halt_req`, a concurrent assignment, so each signal keeps a single driver). The interpreter decides by `rotation_active` alone: a rotation command that is queued but not yet executed is not affected, as with the framework's terminate (D-106).

#### 4.6.3 Configuration, status and result records

- `t_vvc_config`: the standard fields, `bfm_config : t_rotary_encoder_bfm_config`, plus `stop_when_idle_severity : t_alert_level := TB_WARNING` (REQ-106, a VVC-only behaviour).
- `t_vvc_status`: standard, not extended.
- `t_vvc_result` = `t_rotary_encoder_status` (subtype in `vvc_cmd_pkg`, as PWM).

#### 4.6.4 Logging (REQ-085)

- Moves and fault events: the BFM log line (`config.id_for_bfm`): the call with its arguments (direction, count or angle, speed), then for moves and timed rotations `N edges, position P, angle A deg`, for set angle and jump `N edges forward|reverse in zero time, position P, angle A deg, AB xx` (D-89). In the VVC the move line is written by the executor with the VVC call (`rotary_encoder_move_edges(ROTARY_ENCODER_VVC,1, …)=> N edges, …`); a terminated move logs `Terminated after N edges, position P, angle A deg`. Centre state, set angle and jump log the BFM line from `p_motion`.
- Status read: executor log (`config.id_for_bfm`) with the status (`position P, angle A deg, AB xx, index …, rotating …, rpm …`).
- Rotation start / speed change: executor log at completion, the VVC call with the speed (`60.0000 rpm`, or direction and `time_per_edge`, or the profile length, `time_per_entry` and end behaviour), then `=> Took effect, position P, angle A deg`; a terminated one `=> Terminated, the rotation is halted, position P, angle A deg`.
- Stop: executor log `=> Stopped, position P, angle A deg`. A profile that ends with `PROFILE_STOP` is logged by `p_motion` (`config.id_for_bfm`): `Rotation stopped at the end of its profile, position P`.
- Rejections (`TB_ERROR`) and the stop without rotation (`stop_when_idle_severity`) name the VVC call.
- No per-edge log during a rotation.

#### 4.6.5 Transaction info

Base transaction only (as GPIO, UART, SBI). Its purpose is the framework's: a model elsewhere in the testbench sees what each command did on the interface, without reimplementing the angle model (D-98).

- **Parameters** (set at `IN_PROGRESS`): `operation`, `direction`, `num_edges`, `target_state`, `occurrence`, `angle`, `rpm`, `time_per_edge`, `profile_length`, `time_per_entry`, `profile_end`, `vvc_meta`. `rpm` and `time_per_edge` hold a constant speed in the form it was given; the other one is 0. For a profile both are 0 and `profile_length`, `time_per_entry`, `profile_end` describe it.
- **Effect** (set at the end, default while `IN_PROGRESS`): `edges` – the edges a move emitted (also a terminated move; 0 for the other operations); `status` – a `t_rotary_encoder_status` with the encoder state at the end of the command; for `rotary_encoder_get_status` it is the result, as GPIO's `GET` puts its read value into the transaction info.
- **`transaction_status`:** `IN_PROGRESS` when the command starts, then `COMPLETED` when it completes as in 4.6.2, or `FAILED` for every command the VVC rejects with `TB_ERROR`: an invalid move, rotation start or speed change, and a move, centre state, fault event or second start during a rotation, or a speed change without one (nothing changed; D-98, D-103). A stop without rotation (only `stop_when_idle_severity`) ends `COMPLETED`. A zero-time command sets both in the same time step. Set angle, jump and centre state end with `COMPLETED` also when the BFM itself rejected them (invalid parameters; the BFM procedures return no acceptance); their `status` then shows the unchanged state. After the command the record returns to its defaults (`INACTIVE`).
- A rotation start completes at its first edge (4.6.2) and the shaft keeps turning; the transaction info does not track the shaft during a rotation.

### 4.7 Concurrency and integration

- One VVC instance per encoder; instances share nothing except the framework (REQ-083).
- Dependencies: `uvvm_util`, `uvvm_vvc_framework` (the same as PWM). `ieee.math_real` in the BFM body.
- `adaptations_pkg` constants: `C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH`, `C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM`, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH := 256` (D-42). The other shared files are listed in Integration checklist 9.2.

### 4.8 Alerts and failure behaviour

| Situation | Alert | Effect |
|---|---|---|
| Invalid parameter or configuration | `TB_ERROR` (one per call) | Command dropped, outputs unchanged |
| Move, fault event or second start during a rotation | `TB_ERROR` | Dropped, rotation continues |
| Edge offset outside (−45°, +45°), invalid stuck level, jitter ≥ half the narrowest state | `TB_ERROR` | Command dropped |
| Speed change without rotation | `TB_ERROR` | Dropped |
| Stop without rotation | `stop_when_idle_severity` (`TB_WARNING`) | No effect |
| `zero_state` invalid or changed after init | `TB_ERROR` | Command dropped (D-32) |
| Signal configuration (index, bounce window, jitter) invalid during a rotation | `TB_ERROR`, once per invalid value | The edges use the last valid signal configuration; the rotation continues (D-31, D-56) |
| Bounce cut off | `bounce_cut_severity` (`TB_WARNING`), once per command | Bounce shortened |
| BFM state not initialized | `TB_ERROR` | Returns at once |
| Move distance > 2⁵³ quanta | `TB_ERROR` | Dropped |
| Profile longer than the maximum | `TB_ERROR` | Dropped |

There is no timeout: every command completes by construction (D-24).

### 4.9 Supported modes and exclusions

- Supported: everything in the spec for the encoder role.
- Excluded: see Scope (Section 2).
- **Direction convention (D-52, REQ-033):** no swap option. The VIP documentation shows how to connect a DUT that counts "B leads A" as forward, by associating the record elements individually in the port map, and notes that an index state `10`/`01` read from the DUT side then has its bits exchanged:
  ```vhdl
  i_rotary_encoder_vvc : entity p2l2_vip_rotary_encoder.rotary_encoder_vvc
    port map(
      rotary_encoder_vvc_if.a => dut_enc_b,  -- the part counts clockwise as "B leads A"
      rotary_encoder_vvc_if.b => dut_enc_a,
      rotary_encoder_vvc_if.z => dut_enc_z
    );
  ```
- Not offered: a power-up after time 0 (D-46). `rotary_encoder_set_angle` places the shaft at a known angle instead.

### 4.10 Generator answers

| Prompt | Answer |
|---|---|
| VVC name | `rotary_encoder` |
| Extended UVVM features | `y` |
| Scoreboard | `n` |
| Transaction info | `y` |
| Unwanted activity detection | `n` |
| Number of channels | Enter (1) |
| Multiple executors | `n` |

Post-generation changes (implementation report, skeleton comparison): remove `clk`, add the `GC_INSTANCE_IDX` default, library name, file headers, `adaptations_pkg` aliases, add `p_motion`.

### 4.11 Convention deviations

| ID | Convention | Applied | Reason | Impact |
|---|---|---|---|---|
| DV-1 | Some official BFMs declare helpers publicly | Only the public API is declared; helpers are body-only | Project rule, keeps the namespace small | None for users; the audit must not flag it |
| DV-2 | BFMs are normally stateless | Public state record passed `inout` | The angle and last speed cannot be read back from the signals | Users declare one variable per encoder (as PWM's seeds) |
| DV-3 | BFMs normally expose only user operations | Three low-level motion procedures and the motion record are public, marked "used by the VVC" (D-47) | The VVC needs interruptible, resumable motion with the same engine (PWM precedent: `pwm_drive_period` with abort) | Documented as "used by the VVC" |

### 4.12 Traceability (architecture → features)

| Section | Features |
|---|---|
| 4.4 Interface, start state | REQ-001, 002, 006 |
| 4.5.1 Angle model, zero state, boundary rule, edge offsets | REQ-004, 006, 014, 075…077, 090…094, 097 |
| 4.5.2 Edge times, jitter | REQ-012, 013, 057, 060…063, 101 |
| 4.5.3 Driving an edge, bounce, stuck outputs | REQ-001, 032, 050…057, 070, 078, 079 |
| 4.5.4 Index | REQ-032, 040…042, 045, 046, 055 |
| 4.5.5 Motion engine | REQ-003, 096, 098, 100…115 |
| 4.5.6 BFM procedures | REQ-010, 011, 015, 016, 071, 074, 080, 086, 095, 115 |
| 4.6 VVC processes and commands | REQ-081…086, 100…114 |
| 4.6.4 Logging | REQ-085 |
| 4.8 Alerts | every `TB_ERROR`/severity feature |
| 4.9 Direction convention | REQ-033 |

---

## 5. API preview

All declarations below are public. Everything else (Gray mapping, edge-time split, jitter and bounce scheduling, index decision, validation, formatting) is body-only (DV-1).

### 5.1 BFM package declarations

```vhdl
package rotary_encoder_bfm_pkg is

  constant C_BFM_SCOPE : string := "ROTARY ENCODER BFM";

  type t_rotary_encoder_if is record
    a : std_logic;
    b : std_logic;
    z : std_logic;
  end record t_rotary_encoder_if;

  type t_rotary_encoder_direction         is (FORWARD, REVERSE);
  type t_rotary_encoder_channel           is (CHANNEL_A, CHANNEL_B);
  type t_rotary_encoder_bounce_placement  is (BOUNCE_RANDOM, BOUNCE_EVEN);
  type t_rotary_encoder_profile_end       is (PROFILE_HOLD, PROFILE_STOP, PROFILE_REPEAT);

  type t_rotary_encoder_bfm_config is record
    cycles_per_rev      : integer;
    zero_state          : std_logic_vector(1 downto 0); -- pin levels; init only
    start_angle         : real;
    index_enabled       : boolean;
    index_width         : integer;                      -- 1 to 4 states
    index_state         : std_logic_vector(1 downto 0); -- pin levels
    index_position      : integer;
    index_inverted      : boolean;
    bounce_enabled      : boolean;
    bounce_pulses       : natural;
    bounce_window       : time;
    bounce_placement    : t_rotary_encoder_bounce_placement;
    jitter              : real;
    a_rise_offset       : real;
    a_fall_offset       : real;
    b_rise_offset       : real;
    b_fall_offset       : real;
    a_stuck             : std_logic;
    b_stuck             : std_logic;
    z_stuck             : std_logic;
    rand_seed1          : positive;
    rand_seed2          : positive;
    bounce_cut_severity : t_alert_level;
    id_for_bfm          : t_msg_id;
    id_for_bfm_wait     : t_msg_id;
  end record t_rotary_encoder_bfm_config;

  constant C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT : t_rotary_encoder_bfm_config := (
    cycles_per_rev      => 20,
    zero_state          => "11",
    start_angle         => 0.0,
    index_enabled       => true,
    index_width         => 1,
    index_state         => "11",
    index_position      => 0,
    index_inverted      => false,
    bounce_enabled      => false,
    bounce_pulses       => 2,
    bounce_window       => 1 ms,
    bounce_placement    => BOUNCE_RANDOM,
    jitter              => 0.0,
    a_rise_offset       => 0.0,
    a_fall_offset       => 0.0,
    b_rise_offset       => 0.0,
    b_fall_offset       => 0.0,
    a_stuck             => '-',
    b_stuck             => '-',
    z_stuck             => '-',
    rand_seed1          => C_RAND_INIT_SEED_1,
    rand_seed2          => C_RAND_INIT_SEED_2,
    bounce_cut_severity => TB_WARNING,
    id_for_bfm          => ID_BFM,
    id_for_bfm_wait     => ID_BFM_WAIT
  );

  -- Result of rotary_encoder_get_status() and of the VVC's rotary_encoder_get_status() via fetch_result()
  type t_rotary_encoder_status is record
    position     : integer;                      -- Edges from position 0
    angle        : real;                         -- Degrees, sub-edge precision
    ab           : std_logic_vector(1 downto 0); -- State (pin levels)
    index_active : boolean;                      -- Logical Z (before inversion)
    is_rotating  : boolean;
    rpm          : real;                         -- Signed current speed, 0.0 when not rotating
  end record t_rotary_encoder_status;

  -- BFM state: one variable per encoder, initialized with rotary_encoder_init(). Fields are private.
  type t_rotary_encoder_state is record
    -- (private fields: initialized flag, zero state, position, offset, latched geometry,
    --  active motion and segment anchor, last valid index configuration, bounce bookkeeping, seeds)
  end record t_rotary_encoder_state;

  function init_rotary_encoder_if_signals(
    constant dummy : t_void
  ) return t_rotary_encoder_if;

  ---------------------------------------------------------------------------------
  -- Conversions and profile helper
  ---------------------------------------------------------------------------------
  impure function rotary_encoder_rpm_to_time_per_edge(
    constant rpm            : in real;
    constant cycles_per_rev : in integer
  ) return time;

  impure function rotary_encoder_time_per_edge_to_rpm(
    constant time_per_edge  : in time;
    constant cycles_per_rev : in integer
  ) return real;

  function rotary_encoder_rpm_to_deg_per_sec(
    constant rpm : in real
  ) return real;

  function rotary_encoder_deg_per_sec_to_rpm(
    constant deg_per_sec : in real
  ) return real;

  impure function rotary_encoder_linear_ramp(
    constant rpm_start   : in real;
    constant rpm_end     : in real;
    constant num_entries : in integer
  ) return real_vector;

  impure function rotary_encoder_get_status(
    constant state : in t_rotary_encoder_state
  ) return t_rotary_encoder_status;

  ---------------------------------------------------------------------------------
  -- Init
  ---------------------------------------------------------------------------------
  procedure rotary_encoder_init(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Moves. Each exists with rpm : real (> 0) and with time_per_edge : time (> 0 ns).
  ---------------------------------------------------------------------------------
  procedure rotary_encoder_move_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_move_edges(
    constant direction     : in    t_rotary_encoder_direction;
    constant num_edges     : in    natural;
    constant time_per_edge : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- rotary_encoder_move_angle: as rotary_encoder_move_edges, with angle : real (degrees, >= 0.0) (2 overloads)

  -- To the centre of the occurrence-th following state equal to target_state;
  -- the current state is never counted. Second overload with time_per_edge : time.
  procedure rotary_encoder_move_to_state(
    constant direction    : in    t_rotary_encoder_direction;
    constant target_state : in    std_logic_vector(1 downto 0);
    constant occurrence   : in    natural;
    constant rpm          : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- To the centre of the current state in zero time; no output event
  procedure rotary_encoder_center_state(
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Timed rotation: rotates for duration, then stops at once at the reached angle
  ---------------------------------------------------------------------------------
  procedure rotary_encoder_rotate(
    constant rpm          : in    real;                       -- signed, 0.0 legal
    constant duration     : in    time;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_rotate(
    constant direction     : in    t_rotary_encoder_direction;
    constant time_per_edge : in    time;
    constant duration      : in    time;
    variable state         : inout t_rotary_encoder_state;
    constant msg           : in    string;
    signal   encoder_if    : inout t_rotary_encoder_if;
    constant scope         : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config        : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_rotate(
    constant profile        : in    real_vector;               -- signed rpm entries
    constant time_per_entry : in    time;
    constant profile_end    : in    t_rotary_encoder_profile_end;
    constant duration       : in    time;
    variable state          : inout t_rotary_encoder_state;
    constant msg            : in    string;
    signal   encoder_if     : inout t_rotary_encoder_if;
    constant scope          : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel   : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config         : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  ---------------------------------------------------------------------------------
  -- Fault events (device faults are set in the config: edge offsets, stuck outputs)
  ---------------------------------------------------------------------------------
  -- Places the shaft at angle (degrees) in zero time
  procedure rotary_encoder_set_angle(
    constant angle        : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Moves the shaft by num_edges in zero time (2 edges: illegal transition)
  procedure rotary_encoder_jump_edges(
    constant direction    : in    t_rotary_encoder_direction;
    constant num_edges    : in    natural;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );


  ---------------------------------------------------------------------------------
  -- Low-level motion engine. Used by the VVC; testbenches normally use the
  -- procedures above or the VVC. Every declaration below is commented "Used by the VVC."
  ---------------------------------------------------------------------------------
  type t_rotary_encoder_motion_kind  is (MOTION_EDGES, MOTION_ANGLE, MOTION_TO_STATE, MOTION_ROTATION);
  type t_rotary_encoder_speed_form   is (SPEED_RPM, SPEED_TIME_PER_EDGE);
  type t_rotary_encoder_motion_event is (MOTION_EDGE, MOTION_PROFILE_PASS, MOTION_DONE, MOTION_INTERRUPTED);

  type t_rotary_encoder_motion is record
    kind           : t_rotary_encoder_motion_kind;
    direction      : t_rotary_encoder_direction; -- moves; rotation in SPEED_TIME_PER_EDGE
    num            : natural;                    -- edges (MOTION_EDGES), occurrence (MOTION_TO_STATE)
    target_state   : std_logic_vector(1 downto 0); -- MOTION_TO_STATE, pin levels
    angle          : real;                       -- MOTION_ANGLE
    speed_form     : t_rotary_encoder_speed_form;
    rpm            : real;                       -- > 0 for moves, signed for rotations
    time_per_edge  : time;
    profile        : real_vector(0 to C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH - 1);
    profile_length : natural;                    -- 0: constant speed
    time_per_entry : time;
    profile_end    : t_rotary_encoder_profile_end;
  end record t_rotary_encoder_motion;

  constant C_ROTARY_ENCODER_MOTION_DEFAULT : t_rotary_encoder_motion;  -- full value in the package

  procedure rotary_encoder_set_motion(
    constant motion       : in    t_rotary_encoder_motion;
    variable state        : inout t_rotary_encoder_state;
    variable accepted     : out   boolean;    -- false after a TB_ERROR; the previous motion is unchanged
    constant msg          : in    string;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_run_motion(
    variable state        : inout t_rotary_encoder_state;
    variable event        : out   t_rotary_encoder_motion_event;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    signal   interrupt    : in    natural;    -- any event returns MOTION_INTERRUPTED
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  procedure rotary_encoder_halt_motion(     -- stop and terminate_current_command
    variable state : inout t_rotary_encoder_state
  );

end package rotary_encoder_bfm_pkg;
```

`t_rotary_encoder_state` is shown without its fields here; the real declaration has them (a record cannot be empty), commented as private.

### 5.2 VVC methods (`vvc_methods_pkg`)

```vhdl
-- Moves: rpm : real or time_per_edge : time. Complete when the shaft is at rest.
procedure rotary_encoder_move_edges(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant direction           : in    t_rotary_encoder_direction;
  constant num_edges           : in    natural;
  constant rpm                 : in    real;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
);
procedure rotary_encoder_move_edges(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant direction           : in    t_rotary_encoder_direction;
  constant num_edges           : in    natural;
  constant time_per_edge       : in    time;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
-- rotary_encoder_move_angle (angle : real): same two overloads
-- rotary_encoder_move_to_state (target_state : std_logic_vector(1 downto 0), occurrence : natural): same two overloads
procedure rotary_encoder_move_to_state(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant direction           : in    t_rotary_encoder_direction;
  constant target_state        : in    std_logic_vector(1 downto 0);
  constant occurrence          : in    natural;
  constant rpm                 : in    real;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
-- Zero time, resolved at execution time
procedure rotary_encoder_center_state(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);

-- Rotation start and speed change: three overloads each
procedure rotary_encoder_start_rotation(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant rpm                 : in    real;            -- signed, 0.0 legal
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
procedure rotary_encoder_start_rotation(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant direction           : in    t_rotary_encoder_direction;
  constant time_per_edge       : in    time;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
procedure rotary_encoder_start_rotation(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant profile             : in    real_vector;     -- signed rpm entries, 1 to C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH
  constant time_per_entry      : in    time;
  constant profile_end         : in    t_rotary_encoder_profile_end;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
-- rotary_encoder_set_speed: the same three overloads

procedure rotary_encoder_stop_rotation(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);

-- Zero time. set_angle: absolute degrees. jump_edges: relative to the angle at execution time.
procedure rotary_encoder_set_angle(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant angle               : in    real;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
procedure rotary_encoder_jump_edges(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant direction           : in    t_rotary_encoder_direction;
  constant num_edges           : in    natural;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);


-- Stores a t_rotary_encoder_status in the result queue; read it with fetch_result()
procedure rotary_encoder_get_status(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant msg                 : in    string;
  constant scope               : in    string         := C_VVC_CMD_SCOPE_DEFAULT;
  constant parent_msg_id_panel : in    t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
);
```

Overload check: every pair of overloads of one name differs in the type of a positional parameter before `msg` (`real` / `time` / `real_vector`, or the number of parameters), so calls with literals resolve. Named association for `scope` in examples (pitfall F-046).

---

## 6. Use-case walkthrough

Defaults in all snippets: 20 cycles/rev (4.5° per edge), zero state `11`, index on (width 1 at `11`, position 0).

**U-1 – moves and rotation (VVC)** – *convenient*

```vhdl
rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, 1, FORWARD, 12, 60.0, "Three clicks of a 4-edge knob"); -- 150 ms
rotary_encoder_move_angle(ROTARY_ENCODER_VVCT, 1, REVERSE, 10.0, 1 ms, "Turn back 10 deg");           -- ends at 44 deg
rotary_encoder_start_rotation(ROTARY_ENCODER_VVCT, 1, 600.0, "Motor at 600 rpm");
await_completion(ROTARY_ENCODER_VVCT, 1, 10 ms, "First edge seen");                                  -- 1.25 ms per edge
wait for 100 ms;                                                                                       -- the test does other things
rotary_encoder_set_speed(ROTARY_ENCODER_VVCT, 1, rotary_encoder_linear_ramp(600.0, -600.0, 11), 10 ms, PROFILE_HOLD,
                         "Reverse through a ramp");
rotary_encoder_stop_rotation(ROTARY_ENCODER_VVCT, 1, "Stop at the reached angle");
rotary_encoder_center_state(ROTARY_ENCODER_VVCT, 1, "Back to the centre of the current state");
rotary_encoder_move_to_state(ROTARY_ENCODER_VVCT, 1, FORWARD, "00", 1, 60.0, "One click of a knob with its detent at 00");
```

**U-1 – BFM only (REQ-080)** – *convenient*

```vhdl
variable v_enc : t_rotary_encoder_state;
...
rotary_encoder_init(v_enc, "Power-up", encoder_if, config => C_ENC_CONFIG);
rotary_encoder_move_edges(FORWARD, 5, 1 us, v_enc, "5 edges", encoder_if, config => C_ENC_CONFIG);
rotary_encoder_rotate(-120.0, 50 ms, v_enc, "Reverse 50 ms at 120 rpm", encoder_if, config => C_ENC_CONFIG);
-- 5 edges forward (22.5 deg), then 50 ms / 6.25 ms = 8 edge angles back to -13.5 deg (position -3), stop at once
check_value(rotary_encoder_get_status(v_enc).position, -3, ERROR, "Position after the rotation");
```

**U-2 – status read-back** – *convenient*

```vhdl
rotary_encoder_get_status(ROTARY_ENCODER_VVCT, 1, "Where is the shaft?");
v_cmd_idx := get_last_received_cmd_idx(ROTARY_ENCODER_VVCT, 1);
await_completion(ROTARY_ENCODER_VVCT, 1, 1 sec, "");
fetch_result(ROTARY_ENCODER_VVCT, 1, v_cmd_idx, v_status, "Read status");
check_value(v_status.position, 3, ERROR, "Position");
```

**U-3 – several encoders** – *convenient*

```vhdl
rotary_encoder_start_rotation(ROTARY_ENCODER_VVCT, 1, 300.0, "Encoder 1: motor");
rotary_encoder_move_edges(ROTARY_ENCODER_VVCT, 2, REVERSE, 8, 30.0, "Encoder 2: knob, two clicks back");
await_completion(ROTARY_ENCODER_VVCT, 2, 1 sec, "Knob at rest; encoder 1 keeps turning");
rotary_encoder_stop_rotation(ROTARY_ENCODER_VVCT, 1, "Encoder 1: stop");
```

---

## 7. Test plan

### 7.1 Counterpart (D-60)

The VVC is encoder-only, so there is no receive side to loop back to, and no DUT exists. The VVC is tested against **an independent decoder checker in the testbench**, built from spec §8 (A-11), plus an event log of every change on A/B/Z. Spec §8 is written as exactly this reference; the checker is small (one logger process per interface, one protected type), has no build dependency, and sees every delta-level event, which the fault features (REQ-071 same-delta illegal transition, REQ-001 levels) need.

**Independence rule.** The testbench never uses the BFM to compute an expected value. The Gray table, the position decoding and the expected edge times are written in the testbench package. Expected values come from (a) the literal numbers in the acceptance criteria, which were computed by hand, or (b) closed-form functions in the testbench package (7.3). The testbench does **not** reimplement the angle/segment engine; a second implementation of the same algorithm would share its mistakes. BFM functions appear only as the object under test (`rotary_encoder_get_status` in status checks, the conversions in `speed_conversion`, `rotary_encoder_linear_ramp` in `linear_ramp`). The index decision (spec §6) is the one exception where the testbench has its own small function (7.3), written from the spec text, not from the BFM code; the literal values of REQ-042/046 check that function too.

### 7.2 Layout

Same layout as `p2l2_vip_pwm/tb/maintenance_tb/`:

| File | Content |
|---|---|
| `tb/maintenance_tb/rotary_encoder_tb_pkg.vhd` | Package `rotary_encoder_tb_pkg`: event record, protected event log/checker, Gray decoding, expected-value functions, check procedures. Second package `rotary_encoder_th_pkg` in the same file with the shared log variable (PWM precedent: a shared variable of a protected type cannot be declared before the protected body) |
| `tb/maintenance_tb/rotary_encoder_th.vhd` | Test harness for the VVC testbench: `ti_uvvm_engine`, three VVC instances, one logger process per instance |
| `tb/maintenance_tb/rotary_encoder_vvc_tb.vhd` | VVC test sequencer, `GC_TESTCASE : string := "UVVM"` |
| `tb/maintenance_tb/rotary_encoder_bfm_tb.vhd` | BFM-only test sequencer (REQ-080 and all signal-level features), own interface signal and logger, `GC_TESTCASE` |

Test case selection: `if GC_TESTCASE = "move_edges_forward_and_reverse" then … elsif …` with an `else` branch that raises `TB_ERROR "Unsupported test case"`, as PWM; HDLRegression discovers the test cases from these branches. Each test sets `<TC>_Log.txt` / `<TC>_Alert.txt` and ends with `report_alert_counters(FINAL)` and `std.env.stop`.

**Test harness (`rotary_encoder_th`)**

| Instance | Generic `GC_ROTARY_ENCODER_BFM_CONFIG` | Signal | Used by |
|---|---|---|---|
| 1 | default | `enc1_if` | Every VVC test |
| 2 | default | `enc2_if` | REQ-083 (concurrency) |
| 3 | default with `start_angle => 30.0`, `zero_state => "00"` | `enc3_if` | REQ-002/006 through the generic path: power-up at position 7 (30°), `AB = 01`, Z inactive |

No clock, no reset (the VVC has none). Three logger processes write to the shared log under ids 1, 2, 3. The VVC testbench reaches the signals with external names only where the log is not enough (PWM precedent: `<< signal i_test_harness.… >>`).

**Start-angle and zero-state matrix (D-62).** REQ-002 and REQ-006 need a power-up per configuration: the defaults, start angles −10°, 30°, 400°, and the four zero states (8 configurations), plus an invalid and a changed zero state.
- BFM testbench `power_up_state` runs the full matrix with `rotary_encoder_init`, one configuration per step, and checks the invalid zero state and a zero state changed after init (`TB_ERROR` at the next call, no edge). The VVC's `p_motion` calls the same procedure with its generic, so this covers the logic.
- VVC testbench `vvc_power_up_state` covers the generic path once: instance 1 (defaults: `AB = 11`, Z active, position 0) and instance 3 (30°, zero state `00`: position 7, `AB = 01`, Z inactive), checked at the first delta and with no A/B event before the first movement. It also changes `zero_state` in the shared configuration of instance 1 and checks the `TB_ERROR` at the next command (D-32), then restores it.

### 7.3 Checker and event log (`rotary_encoder_tb_pkg`)

**Event logging.** One logger process per interface: `wait on enc_if.a, enc_if.b, enc_if.z;` and one log entry per wake-up: `(time, a, b, z, a_changed, b_changed, z_changed)`. A wake-up happens once per delta cycle in which something changed, so:
- A and B changing in the **same delta** appear as one entry with both flags set (illegal transition, REQ-071).
- A zero-length state (D-39: two events on one channel at the same time, in different deltas) appears as two entries with the same time, each legal.

The log is dynamically sized (grows inside the protected body), so the 10 000-edge jitter test and bounce runs need no capacity constant. `clear(id)` empties a log between steps.

**Decoder checker (spec §8).** Runs inside `add()` on every entry, per log id, after the checker is **armed** (the BFM testbench arms it after `rotary_encoder_init`; the harness loggers arm at the first event at time 0, i.e. the VVC's initialization):

| Event | Classification | Counter |
|---|---|---|
| A or B not `'0'`/`'1'` (also Z) | Invalid level (spec §8, REQ-001) | `invalid_level` |
| Exactly one of A/B changed, forward per the A-leads-B Gray table `00→10→11→01→00` | Forward edge | `position + 1`, `edges + 1` |
| Exactly one of A/B changed, reverse | Reverse edge | `position − 1`, `edges + 1` |
| A and B changed in one entry | Illegal transition (spec §4.3) | `illegal`, position unchanged (§8) |
| Only Z changed | Index event | `z_events` |

Bounce toggles decode as alternating forward/reverse edges, so the net position stays correct and nothing is counted as illegal; the bounce tests count events explicitly. There is no A/B polarity inversion and no direction swap, so a forward move always counts +N.

The checker **counts and does not alert** (D-64): error tests provoke illegal transitions and invalid levels on purpose. Instead every test step ends with `check_checker(id, exp_position_change, exp_illegal => 0, exp_invalid => 0, msg)`. This gives REQ-001 and REQ-070 in every test without per-test effort and keeps the expected counts visible in the test code.

**Check procedures**

| Procedure / function | Purpose |
|---|---|
| `check_checker` | Position change and violation counters since the last clear |
| `check_event_times(id, first, expected : t_time_array, tolerance)` | Event times relative to a start time; tolerance 0 for "exact", `C_RESOLUTION` for "within one step" |
| `check_edge_sequence(id, expected : t_ab_array)` | AB sequence (direction, Gray order) |
| `check_no_event(id, from, to)` | REQ-003 hold, REQ-040 Z quiet, stuck outputs |
| `tb_index_positions(zero_state, index_state, width, index_position)` | Independent index decision from spec §6 (state of a position, index cycle, width forward); used to sweep REQ-042 (widths 1–4 × index states) |
| `check_z_follows_ab(id, positions)` | REQ-042, 046, 077: Z is active exactly at the expected positions and changes in the same entry or delta-time as the A/B event that enters/leaves them |
| `save_events` / `compare_inverted` | REQ-032: in the second run Z equals `not` of the first and A/B are identical, time-relative |
| `check_constant_spacing(id, first, n, period, tolerance)` | REQ-101 long runs without a table |
| `check_jitter_stats(id, ideal_first, period, amplitude)` | REQ-061: bound, mean, both bounds reached within 5 % |

**Expected edge times without accumulated error (D-67).** Rpm-form criteria require "within one resolution step" over runs of up to 86 s (10 revolutions at 7 rpm). On GHDL and NVC the resolution is fs; a `real` (53-bit mantissa) holding 8.6·10¹⁶ fs has a granularity of about 16 fs, so a single `real` formula for the expected time would itself be wrong by more than the tolerance. The testbench therefore computes ideal times with exact `time`/`integer` arithmetic for **integer rpm** (every rpm value in the acceptance criteria is an integer: 7, 60, 120, 600, 6000):

  t(k) = t_s + (k − ½) × 60 s / (rpm × 4 × `cycles_per_rev`) = t_s + q × 1 sec + f, with n = (2k − 1) × 30, D = rpm × 4 × `cycles_per_rev`, q = n / D, r = n mod D, f = r / D seconds.

f is computed by decimal long division in `integer`, one digit per power of ten down to `std.env.resolution_limit` (remainder × 10 < 10 × D stays far inside 32 bits), and accumulated as `time`. This is the exact floor of the ideal time, independent of the resolution and free of overflow (a direct `r × 1 sec` would overflow 64 bits for D > 9 200, e.g. 6000 rpm: D = 480 000). The tolerance of one step then covers floor vs. rounding. The function has a self-test against hand values (`testbench_self_test`). Time-form criteria use `time` arithmetic directly and are exact.

**Alerts.** Expected `TB_ERROR`/`TB_WARNING` per invalid call (REQ-006, 016, 045, 098, …) are declared with `increment_expected_alerts_and_stop_limit(severity, 1)` immediately before the call, so `report_alert_counters(FINAL)` fails the test on a missing or extra alert. A helper `check_rejected(…)` combines that with `check_no_event` (outputs unchanged).

### 7.4 Test cases

Each test case is named for what it tests; the name is its `GC_TESTCASE` value and appears in the regression output. The feature mapping lives only in these tables, never in testbench comments. Test cases that cover the same features at different levels have separate names (`power_up_state` at signal level in the BFM testbench, `vvc_power_up_state` through the generic in the VVC testbench). Every test also checks REQ-001 and REQ-070 through `check_checker`. The split between the two testbenches is D-61.

**BFM testbench (`rotary_encoder_bfm_tb`, 30 test cases)**

| Test case | Content | Features | Inc |
|---|---|---|---|
| `testbench_self_test` | Testbench self-test without the BFM: decoder checker on hand-driven forward, reverse, illegal and invalid-level sequences, zero-length states, `check_no_event`, expected edge times against hand values | – | 1 |
| `power_up_state` | Start-angle and zero-state matrix (7.2): defaults; −10°, 30°, 400°; 4 zero states; state and Z at the first delta, no A/B event before the first move; invalid zero state and zero state changed after init (`TB_ERROR`, no edge) | REQ-001, 002, 006 | 1 |
| `move_edges_forward_and_reverse` | Forward/reverse N ∈ {1…5, 1000} from all four states (start angles 0°, 4.5°, 9°, 13.5°) | REQ-010, 011, 070 | 1 |
| `edge_timing` | Edge timing, time form 1 ns/1 µs/1 ms; rpm form 7 and 6000 rpm, N = 1000; speed curves back to back | REQ-012, 013, 060 | 1 |
| `direction_reversal` | Reversal ±1 edge ×10 from each state; mixed sequence continuity | REQ-004, 014 | 1 |
| `zero_edge_move` | 0-edge move | REQ-015 | 1 |
| `invalid_speed` | Invalid speeds | REQ-016 | 1 |
| `move_angle` | Angle moves: edge at 2.25°, a 10° move ends at 10° with 2 edges, durations in both forms; all status fields after the 10° move | REQ-086, 090, 092 | 1 (status fields in 3) |
| `move_angle_without_drift` | No drift: 360 × 1°, 3600 × 0.1°, mixed edge/angle moves | REQ-091, 093 | 1 |
| `invalid_angle_and_move_to_state` | Invalid angles; invalid move-to-state parameters (occurrence 0, target `"0X"`, invalid speed) | REQ-094, 098 | 1 |
| `speed_conversion` | Conversion functions and their errors | REQ-095 | 1 |
| `move_to_state` | Move to state: all criteria of REQ-096 except the VVC case (from 0°, 1.125°, 10°; occurrence 2; reverse; target `10`) | REQ-096 | 1 |
| `center_state` | Centre state: from 10°; after forward/reverse moves ending exactly on 6.75°; ±44° offsets without event; edge timing of a following 1-edge move | REQ-097 | 1 (offset step in 3) |
| `index_polarity` | Index polarity inversion vs. non-inverted run: Z inverted, A/B identical in both runs | REQ-032 | 2 |
| `index_once_per_revolution` | Index off; once per revolution, `cycles_per_rev` ∈ {1, 3, 24}, `index_position` ∈ {0, 5, −3}, both directions | REQ-040, 041 | 2 |
| `index_width_and_state` | Index width 1–4 × index state `00`/`10` × forward/reverse (sweep with `tb_index_positions`); literal cases of REQ-042 (width 2 at `00`, zero state `00`: positions 0, 1, Z active while B is low) and REQ-046 (zero state `00` → Z at 0; zero state `11` → Z at position 2) | REQ-042, 046 | 2 |
| `invalid_index_configuration` | Invalid `cycles_per_rev` = 0, index width 0 and 5, index state `"0X"`: one `TB_ERROR` each at the call, no edge (the rotation part is `config_change_during_rotation`, D-68) | REQ-045 | 2 |
| `bounce` | Bounce off/on, nominal timing kept, Z does not bounce | REQ-050, 051, 052, 055 | 2 |
| `bounce_placement` | Bounce placement random (seed reproducible) / even | REQ-053 | 2 |
| `bounce_cut_off_and_invalid_window` | Invalid window; bounce cut-off and its alert | REQ-054, 056 | 2 |
| `bounce_with_jitter` | Bounce combined with jitter: bounce window from the jittered edge, Z does not bounce, reproducible, one random stream (jitter differs with bounce enabled), cut-off caused by jitter | REQ-056, 057 | 2 |
| `jitter` | Jitter statistics over 10 000 edges, seed reproducibility, 60/600 rpm scaling | REQ-061, 062 | 2 |
| `invalid_jitter` | Invalid jitter, incl. the offset-dependent limit | REQ-063 | 2 (offset case in 3) |
| `set_angle_and_jump_edges` | `rotary_encoder_set_angle` / `rotary_encoder_jump_edges` (all criteria of REQ-071) | REQ-071 | 3 |
| `invalid_fault_event` | Set angle with a non-finite angle | REQ-074 | 3 |
| `edge_offsets` | Edge offsets: timing, duty error, ±44° limits (4-edge move from 0° ends in the zero state, same duration), invalid ±45°, Z with offsets | REQ-075, 076, 077 | 3 |
| `stuck_outputs` | Stuck outputs incl. `'Z'`, release, bounce; invalid levels | REQ-078, 079 | 3 |
| `bfm_only_flow_and_rotate` | BFM-only flow: edges/timing/index/angle by direct calls; `rotary_encoder_rotate` in its three overloads, each ending with a stop at the reached angle (D-63); invalid parameters of `rotary_encoder_rotate` (speed, profile, duration) | REQ-080, 110 (BFM) | 3 |
| `linear_ramp` | `rotary_encoder_linear_ramp` | REQ-115 | 3 |
| `linear_ramp_rotation` | Slow start-up from standstill: `rotary_encoder_linear_ramp(0.0, 60.0, 61)` as the profile of `rotary_encoder_rotate`, 3 s per entry, `PROFILE_STOP` (183 s, 7320 edges). Entry *j* covers 4·*j* edge angles, so every entry starts in a state centre and each edge is checked against its exact rpm-form time (one resolution step); returns at the end of the ramp, at rest at the expected position | REQ-111, 115 | 3 |

**VVC testbench (`rotary_encoder_vvc_tb`, 20 test cases)**

| Test case | Content | Features | Inc |
|---|---|---|---|
| `vvc_power_up_state` | Power-up of instances 1 and 3 from the generic; `zero_state` changed in the shared configuration → `TB_ERROR` at the next command (7.2) | REQ-001, 002, 006 | 4 |
| `hold_between_commands` | Hold during `insert_delay` and ≥ 100 × `time_per_edge` idle, after a move and after a stopped rotation; continuity across commands | REQ-003, 004 | 4 (move part), 5 (rotation part) |
| `vvc_commands` | Framework methods (`insert_delay`, `flush_command_queue`, `await_completion`, `enable/disable_log_msg`); transaction info: parameters while a move runs, `edges` and end `status` at `COMPLETED`, `FAILED` for a rejected move, the `get_status` result, `INACTIVE` afterwards; queue of 10 moves in order; one move of each kind and form through the VVC with edge times and completion, incl. move to state queued after a 1.125° angle move (resolved at execution time, REQ-096) and centre state; fault events and `get_status`/`fetch_result` through the VVC (all REQ-086 status fields after a 10° move); logging with the message ID on and off | REQ-081, 085, 086, 096 | 4 |
| `terminate_move` | `terminate_current_command` during a move | REQ-082 | 4 |
| `multiple_instances` | Instances 1 and 2 at different speeds; instance 1 rotating while 2 moves; each log sees only its own edges | REQ-083 | 4 (moves), 5 (rotation part) |
| `config_change_between_moves` | Shared config change during a move affects only the next one (bounce enabled mid-move); stuck B set and released between moves shows at the start of the next move, and the status position counts the edges of the stuck period | REQ-078 (VVC), 084 | 4 |
| `rotation_start` | Rotation start: completion at the first edge, ¼-edge start offsets, ±60 rpm, 0 rpm | REQ-100 | 5 |
| `rotation_long_run_timing` | 800 edges exact (time form), 7 rpm × 10 rev within one step | REQ-101 | 5 |
| `rotation_speed_change` | Speed change mid-edge, change to 0 rpm and back, 5 changes; status read during the rotation (rpm, rotation flag, edge times unchanged) | REQ-086, 102 | 5 |
| `rotation_direction_change` | Direction change without hysteresis | REQ-103 | 5 |
| `rotation_stop` | Stop at 1.75 *T*: no further edge, completes at once, status 7.875°; following forward/reverse start: first edge after 0.75 *T* / 0.25 *T*; stop exactly on a boundary (D-25) | REQ-104 | 5 |
| `commands_rejected_during_rotation` | Moves (incl. move to state), centre state, fault events and second start rejected during a rotation (`FAILED` transaction), also at 0 rpm | REQ-105 | 5 |
| `speed_change_and_stop_without_rotation` | Speed change / stop without rotation | REQ-106 | 5 |
| `terminate_and_flush_during_rotation` | `terminate_current_command` during a rotation with the executor idle (F-004; the next command is not terminated), during `insert_delay` and during a speed change waiting for its first edge; `flush_command_queue` | REQ-107 | 5 |
| `config_change_during_rotation` | Bounce enabled between edges 1 and 2: edge 2 unbounced, edges 3 to 5 bounce (D-101); `cycles_per_rev` changed during a 6000 rpm rotation: spacing and index of the start geometry; invalid index width, bounce window and jitter written during a rotation: one `TB_ERROR` per invalid value at the next edge, the edges keep the last valid configuration (D-31, D-56, D-79) | REQ-045, 054, 063, 108 | 5 |
| `index_bounce_and_jitter_in_rotation` | Index (incl. Z polarity), bounce, jitter checks with a rotation as stimulus | REQ-109 | 5 |
| `invalid_rotation` | Invalid rotation parameters | REQ-110 | 5 |
| `speed_profile` | Profiles: (60, 120), (0, 60), (60, −60), (0), jitter per entry, 256 entries | REQ-111 | 5 |
| `speed_profile_end` | Profile end hold/repeat/stop; plain speed change replaces a profile | REQ-112, 113 | 5 |
| `invalid_speed_profile` | Invalid profiles | REQ-114 | 5 |

**Documentation example (`TC-DOC`, Phase 6 – Documentation).** REQ-033 (documented crossed wiring, 4.9) is not a BFM or VVC behaviour, so it has no test case in the maintenance testbenches. It is verified by the documentation-example testbench in `<evidence_dir>`: the port-map example of 4.9 is instantiated as documented, with the DUT-side signals logged by the checker of `rotary_encoder_tb_pkg`. A forward move of N edges must count −N on the DUT side ("B leads A"). Plus a review that the RST page contains the example and the index-state note.

**Coverage check:** all 72 features map to at least one test case (REQ-033 to TC-DOC); REQ-001 and REQ-070 additionally run in every test. REQ-085 is *Sim + Review*: `vvc_commands` produces the log with the ID enabled and disabled, and the log file is kept in `<evidence_dir>` for the review.

### 7.5 Regression infrastructure (D-65)

**Script:** `script/maintenance_script/test.py`, copied from **`bitvis_vip_gpio`** (official, clock-less signal-level VIP like this one; unlike `bitvis_vip_clock_generator` its script also verifies `compile_src.do` and `compile_bfm.do` on Questa/Riviera) with only these edits:
1. `print('Verify p2l2_vip_rotary_encoder')` (GPIO: `'Verify Bitvis VIP GPIO'`);
2. library `bitvis_vip_gpio` → `p2l2_vip_rotary_encoder` in the three `add_files` calls, comment `# Add GPIO VIP` → `# Add Rotary Encoder VIP`;
3. dependency VIPs: remove the `bitvis_vip_scoreboard` line and change its comment to `# Add util and fw` (no scoreboard, 4.3);
4. DUT: none.

The script must be **started from `p2l2_vip_rotary_encoder/sim`** (create the folder if missing): its cleanup only runs there and HDLRegression writes into the current directory (F-016/F-019). It deletes `sim/` contents after a passing run (F-014). Run: `cd p2l2_vip_rotary_encoder/sim && python3 ../script/maintenance_script/test.py`, plus HDLRegression's own options for simulator selection (`-s NVC -fr -v`).

**Simulators:** GHDL 6.0.0 (fs), NVC 1.23.0 (fs), Questa Starter 2025.3 (`-t ps` from the script). The test values were chosen so that every "exact" criterion is exact at ps. The official script has no NVC branch; NVC runs with HDLRegression's defaults. If NVC needs an option, that is a script change proposed as a deviation in Stage 5.4.

**Companion scripts** (from `bitvis_vip_gpio`, names adapted): `script/compile_src.do`, `script/compile_bfm.do`, `script/compile_order.txt`, `script/README.txt`. `test.py` runs both `.do` scripts on Questa after the HDLRegression run.

**Simulation time and run time.** Longest simulated time: `rotation_long_run_timing` at 7 rpm, 10 revolutions ≈ 86 s; `edge_timing` at 7 rpm, 1000 edges ≈ 107 s. Both are event-sparse (~1 000 events), so wall time is small. `time` is 64-bit on all three simulators; 107 s = 1.07·10¹⁷ fs fits (D-72). Largest event count: `jitter` (10 000 edges) and the bounce tests (≤ 5 events per edge).

---

## 8. Increments

| Inc | Goal and content | Features | Test cases | Status / expected decisions |
|---|---|---|---|---|
| 1 – BFM core | Types, config, state, `rotary_encoder_init`, motion engine (`set_motion`/`run_motion`/`halt_motion`), edge and angle moves, move to state, centre state, `get_status`, conversions | REQ-001, 002, 004, 006, 010…016, 070, 090…098 | BFM tests of Inc 1 (7.4) | Done (decisions D-59, D-80 to D-83) |
| 2 – BFM signal options | Index (width, index state, Z polarity, validation and last valid configuration), bounce (cut-off), jitter, bounce with jitter | REQ-032, 040…042, 045, 046, 050…057, 060…063 | BFM tests of Inc 2 (7.4) | Done (decisions D-54 to D-58) |
| 3 – BFM faults, timed rotation, ramp | `set_angle`, `jump_edges`, edge offsets, stuck outputs, `rotary_encoder_rotate` (3 overloads, stop at the reached angle), `rotary_encoder_linear_ramp`; offset steps of `center_state` and `invalid_jitter`; status fields in `move_angle` | REQ-071, 074…079, 080, 086 (BFM), 115 | `set_angle_and_jump_edges`, `invalid_fault_event`, `edge_offsets`, `stuck_outputs`, `bfm_only_flow_and_rotate`, `linear_ramp`, `linear_ramp_rotation` | Done (decisions D-87 to D-94; its glitch removed in Inc 4, D-100) |
| 4 – VVC commands | Skeleton adaptation, `p_motion`, executor ↔ `p_motion` handshake, moves (incl. move to state), centre state, fault events, `get_status`/`fetch_result`, terminate during a move, zero-state check, transaction info, logging | REQ-001, 002, 003, 004, 006, 081…086, 096 | VVC tests of Inc 4 (7.4) | Done (decisions D-95 to D-100) |
| 5 – VVC rotation | Start, speed change, stop (= halt), profiles, rejects, terminate/flush during a rotation, per-edge configuration incl. invalid index, bounce-window and jitter values | REQ-003, 045, 054, 063, 083, 086 (rotation), 100…114 | VVC tests of Inc 5 (7.4) | Done (decisions D-101 to D-106) |
| Stage 5.4 | Shared files (9.2), all simulators, VSG, implementation report | – | All 50 (TC-DOC in Phase 6) | Done: S-2 to S-6 applied; 50/50 on GHDL, NVC, Questa; VSG 3.36.0 clean (3.29.0 cannot read `uvvm.yaml`). F-021 Questa waveform debugging needs `-voptargs=+acc` |

---

## 9. Integration checklist

Precedent: branch `p2l2_vip_pwm` (all commits since `master`, integration commit `bb4b0c91`). `p2l2_vip_mdio` touched the same eight shared files.

### 9.1 VIP's own files

| File | Source | Stage |
|---|---|---|
| `src/rotary_encoder_bfm_pkg.vhd`, `transaction_pkg.vhd`, `vvc_cmd_pkg.vhd`, `vvc_methods_pkg.vhd`, `rotary_encoder_vvc.vhd`, `vvc_context.vhd` | Generator + architecture | 5.1 / Inc 1–5 |
| `tb/maintenance_tb/` (4 files, 7.2) | New | 5.2 / Inc 1–5 |
| `script/maintenance_script/test.py` | `bitvis_vip_gpio`, edits of 7.5 | 5.2 |
| `script/compile_src.do`, `compile_bfm.do`, `compile_order.txt`, `README.txt` | `bitvis_vip_gpio`, names adapted (`compile_order.txt` is read by `script/compile_all.sh`) | 5.1 |
| `LICENSE.TXT`, `README.TXT`, `CHANGES.TXT`, `VERSION.TXT` (`v1.0.0`), `.gitignore` | `bitvis_vip_gpio`, names adapted | 5.1 |
| `doc/*.md` workflow documents | `doc/evidence/` stays git-ignored | – |

### 9.2 Shared files (scope approved)

| # | File | Change (PWM pattern) | Read by / verified with | Stage |
|---|---|---|---|---|
| S-1 | `uvvm_util/src/adaptations_pkg.vhd` | Block `-- ROTARY ENCODER` after RGMII, before SBI: `C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH`, `C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM`, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH := 256` | Every compile; `test.py` | 5.1 (D-66) |
| S-2 | `script/component_list.txt` | Append `p2l2_vip_rotary_encoder` | `script/compile_all.sh`, `compile_all.do`, `release/update_versions.py`; verified by running the compile-all script | 5.4 |
| S-3 | `misc/context/uvvm_all_context.vhd` | Append `library p2l2_vip_rotary_encoder; context p2l2_vip_rotary_encoder.vvc_context;` | Compile-all (context compile) | 5.4 |
| S-4 | `versions.txt` | Append `p2l2_vip_rotary_encoder, version v1.0.0` (no trailing newline, as the file) | Review | 5.4 |
| S-5 | `vhdl_ls.toml` | Block `p2l2_vip_rotary_encoder.files` (framework `src_target_dependent` + VIP) | Review (editor config) | 5.4 |
| S-6 | `release/code_conventions/uvvm.yaml` | Add `'ROTARY_ENCODER_VVCT'` to `case_exceptions` | VSG run in Stage 5.4 | 5.4 |
| S-7 | `doc/source/index.rst` | `vip_rotary_encoder.rst` after `vip_rgmii.rst` | Sphinx build (Phase 6) | 6 |
| S-8 | `doc/source/vip_rotary_encoder.rst` | New VIP page | Sphinx build (Phase 6) | 6 |

**Merge conflicts:** the `p2l2_vip_pwm` and `p2l2_vip_mdio` branches append at the same places (S-2, S-3, S-4, S-5, S-6, S-7 next to `vip_rgmii`/after `vip_i2c`). Whichever branch merges later resolves trivial line conflicts; S-1 does not conflict (different block positions).

---

## 10. Open questions

None.

---

## 11. Decision log

One log for all decisions. "Old ID" is the ID in the former separate documents (requirements `D-`, architecture `AD-`/`D-`/`Q-`, testbench architecture `TD-`, cross-check `X-`, expected decisions `E-`), so references in the findings log and implementation report still resolve. IDs that are not listed were removed and are not reused (D-2, D-5, D-7, D-8, D-23, D-45).

| ID | Old ID | Question | Decision | Reason / rejected alternative | Date |
|---|---|---|---|---|---|
| D-1 | D-1 | When does the first edge of a movement occur? | `time_per_edge`/2 after the start (a move goes from the centre of a state to the centre of a state); the command completes `time_per_edge`/2 after its last edge; back-to-back moves keep a spacing of `time_per_edge` in both directions | `time_per_edge` after the start, completing at the last edge: not compatible with angle moves (F-002) | 2026-10-21, revised 2026-10-27 |
| D-3 | D-3 | What happens to the position after an illegal transition, set angle or jump? | The position changes by the edge distance between the old and the new angle | Position unchanged: the state and the position then disagree, which breaks index placement | 2026-10-21 |
| D-4 | D-4 | Does Z bounce together with A/B? | No, Z follows the nominal state | Index is an optical/magnetic feature, bounce a mechanical one | 2026-10-21 |
| D-6 | D-6 | Movement of 0 edges | Allowed, a no-op that is only logged | `TB_WARNING` | 2026-10-21 |
| D-9 | D-9 | How is the bounce amount configured? | Number of bounce **pulses** (`natural`, 2 toggles each), which cannot be invalid (D-43) | Number of extra toggles, which must be even and is validated | 2026-10-27 |
| D-10 | D-10 | Jitter distribution | Uniform | Gaussian (UVVM `rand_pkg` supports both) | 2026-10-21 |
| D-11 | D-11 | When do rotation start and speed/direction change complete? | The change takes effect at once, at the current angle (A-18). The command completes at the next edge, the first edge that shows the change; after `await_completion` the new speed is visible on A/B | Hold the change until the next edge (a direction change on a boundary would need a zero-length state); complete at once | 2026-10-27 |
| D-12 | D-12 | When does a stop complete? | At once; without detents the shaft is at rest at the stop | At once, with a snap in the background (detents removed) | 2026-10-27, revised 2026-11-09 |
| D-13 | D-13 | What does `terminate_current_command` do to a rotation? | Stop at once (zero time), at the current angle, as a stop (REQ-104) | – | 2026-10-27 |
| D-14 | D-14 | A move, fault event or second start while a rotation is active | `TB_ERROR`, command dropped, rotation continues | A second start acts as a speed change; a waiting move would block the queue, because the stop is queued after it | 2026-10-27 |
| D-15 | D-15 | Stop while no rotation is active | Configurable alert, default `TB_WARNING`, no effect | `TB_ERROR` | 2026-10-27 |
| D-16 | D-16 | When does a configuration change reach a running rotation? | Signal configuration at every edge; the geometry that defines the angle model at the rotation start (REQ-108) | At start and at each speed change | 2026-10-27 |
| D-17 | D-17 | End behaviour of a speed profile | Chosen per call: hold, stop or repeat | One fixed behaviour | 2026-10-27 |
| D-18 | D-18 | Linear-ramp helper | One BFM function, linear in rpm (follows from D-20) | No helper | 2026-10-27 |
| D-19 | D-19 | Speed unit | rpm (`real`) as the primary form, signed for rotations (0 rpm legal); `time_per_edge` (`time`) as an overload for exact edge spacing; conversion functions incl. degrees per second | Degrees per second; rpm only; `time_per_edge` only | 2026-10-27 |
| D-20 | D-20 | Profile axis | Over time: rpm entries with `time_per_entry` | Over edges; over angle | 2026-10-27 |
| D-21 | D-21 | Jitter amplitude unit and model | Electrical degrees (0 ≤ *j* < 45°), as datasheets specify phase error; each edge displaced on its own, without carry-over; the amplitude scales with the speed | A time amplitude, checked against the edge interval at every edge: no longer works once the speed varies within a rotation | 2026-10-27 |
| D-22 | D-22 | Bounce window longer than the time to the next edge | Cut the bounce off before the next edge and raise a configurable alert (default `TB_WARNING`) once per command (REQ-056) | `TB_ERROR` at the first affected edge; a static check "`t_bounce` < `time_per_edge`" is impossible when the speed varies | 2026-10-27 |
| D-24 | D-24 | Completion when no edge follows | A start or change to 0 rpm completes at once; a profile completes at its first edge, or at the end of its first pass if that pass has no edge | `TB_ERROR` for a constant 0 rpm; otherwise the command, and with it the queue, would wait forever | 2026-10-27 |
| D-25 | D-25, X-5 | Who owns a boundary when a stop, speed change, `terminate_current_command` or move end falls exactly on an edge time (F-003)? | The edge is emitted first (D-39) | "Strictly beyond": not implementable deterministically, because the edge is driven in the first delta of that time | 2026-10-27 |
| D-26 | D-26 | Do edge offsets refer to the logical channels or to the output pins? | Named by the level change on the pins (no swap or inversion exists); the offsets define the edge angles and are latched with the geometry at the motion start | Per-edge settings: a change during a rotation would move the edge angles mid-motion | 2026-10-27, adapted 2026-11-09 |
| D-27 | D-27 | Which stuck levels? | `'0'`, `'1'` and `'Z'` (broken wire without pull resistor; spec §8 makes `'Z'` an error for the decoder), `'-'` = not stuck | `'0'`/`'1'` only (would keep REQ-001 without exception) | 2026-10-27 |
| D-28 | D-28 | Range of edge offsets | Open interval (−45°, +45°): every state stays wider than 0° and contains its ideal centre, so positions, the zero state, the index and completion times are unaffected | Larger offsets down to zero-width states: positions and the index would need a new definition | 2026-10-27 |
| D-29 | D-29 | When does a stuck setting take effect? | At the start of every command and at every edge; a change while idle shows at the next command | At once: impossible, a change of the shared configuration has no event | 2026-10-27 |
| D-30 | D-30 | Set angle and jump | Two commands: `set_angle` (absolute degrees, not a power-up) and `jump_edges` (relative edges from the angle at execution time). On a boundary the shaft stays on the side of the old angle. The relative form keeps error injection independent of the current position, which a queued VVC command cannot know | One command with an absolute angle only; one name for both forms | 2026-10-27 |
| D-31 | D-31 | How and when is an invalid index configuration reported? | `TB_ERROR` when a command starts; the command is not executed. During a rotation: `TB_ERROR` at the next edge, Z keeps its last valid configuration. All invalid parameters of this VVC use `TB_ERROR`; the tests count it with the expected-alert mechanism; UVVM reserves `TB_FAILURE` for a broken testbench | `TB_FAILURE` (used by some official BFMs for configuration sanity checks); clamp silently | 2026-11-09 |
| D-32 | D-32 | Invalid zero state, and may it change after initialization? | `TB_ERROR` if invalid; a value changed after initialization raises `TB_ERROR` at the next command start, and the command is not executed | Apply a change with a `TB_WARNING` (redefines position 0, outputs jump); zero state as a generic only | 2026-11-09 |
| D-33 | AD-1 | VVC name | `rotary_encoder` | `quadrature_encoder` (longer); `encoder` (ambiguous: 8b/10b, line encoders) | 2026-10-27 |
| D-34 | AD-2 | Library and directory | `p2l2_vip_rotary_encoder` | `bitvis_`, `external_vip_` prefixes (4.2) | 2026-10-27 |
| D-35 | AD-3, Q-1 | File header and copyright holder | UVVM Apache banner, `Copyright 2026 UVVM` (as PWM) | Another holder | 2026-10-27 |
| D-36 | AD-4 | Process structure | Executor + `p_motion` (single driver), engine in the BFM | Rotation logic in the VVC entity: BFM and VVC would differ | 2026-10-27 |
| D-37 | AD-5 | Angle representation | Integer position + integer offset, K = 9·10⁸ quanta per edge | `real` degrees: fails REQ-091 for 0.1° steps | 2026-10-27 |
| D-38 | AD-6 | Edge-time computation | Split `time` + small `real`, recomputed from the segment anchor | Incremental addition: accumulates rounding | 2026-10-27 |
| D-39 | AD-7, Q-3 | Boundary owner (F-003) | Edge first: reaching a boundary emits the edge; added to spec A-13 | "Strictly beyond": not implementable deterministically for stops at an edge time | 2026-10-27 |
| D-40 | AD-8 | State mapping and zero-state changes | Mapping fixed at init from `zero_state`; a later change is `TB_ERROR` (D-32) | Remap A/B on change (output jumps) | 2026-10-27, revised 2026-11-09 |
| D-41 | AD-9 | Index placement | Index cycle `index_position` … +3; *q* = the position in it whose state is `index_state`; `index_width` 1–4 positions forward (4.5.4) | *q* = largest position ≤ `index_position` with `index_state`, enum of three index modes | 2026-11-09 |
| D-42 | AD-10, X-4 | Profile maximum | 256 entries, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` in `adaptations_pkg` | 64 / 1024 | 2026-10-27 |
| D-43 | AD-11, Q-2, X-2 | Bounce amount and defaults | `bounce_pulses : natural` (2 toggles each), so only `bounce_window` ≤ 0 ns needs a check; defaults 2 pulses and 1 ms window | Even toggle count, validated | 2026-10-27 |
| D-44 | AD-12 | Status read-back (U-2) | Included: `rotary_encoder_get_status` + `fetch_result()` | Excluded | 2026-10-27 |
| D-46 | AD-14 | Start state | From the generic at time 0 only; a known angle later is set with `rotary_encoder_set_angle` | A re-initialization command that re-reads the configuration | 2026-10-27 |
| D-47 | AD-15, DV-3 | Visibility of the motion engine | Public in the BFM package, documented "used by the VVC" (4.5.5) | Internal package | 2026-10-27 |
| D-48 | AD-16 | Timed BFM rotation | Kept (`rotary_encoder_rotate`, three overloads) | Rotation VVC-only | 2026-10-27 |
| D-49 | AD-17 | Fault model | Device faults by configuration (four edge offsets, stuck A/B/Z); fault events by request (`set_angle`, `jump_edges`) | One fixed illegal-transition request | 2026-10-27 |
| D-50 | AD-18, X-17 | Stop without detents | A stop is `rotary_encoder_halt_motion` (no motion kind for it); `REQ_STOP` and `REQ_HALT` differ only in logging and the `stop_when_idle_severity` check; completes at once, the response on `motion_rsp` in the same delta | A zero-length stop motion (no benefit) | 2026-11-09 |
| D-51 | AD-19, X-18, X-19 | Move to state / centre state | `MOTION_TO_STATE` resolved to an angle move at motion start, i.e. at execution time (one engine, same timing as angle moves); centre state is a zero-time state operation (only the offset changes, no output event); `occurrence : natural` (0 → `TB_ERROR`) | `positive` (0 would be a range failure instead of `TB_ERROR`); compute the target in the VVC executor (it does not own the state) | 2026-11-09 |
| D-52 | AD-20 | Direction convention | No swap option; crossed record elements in the port map, documented with an example (4.9, REQ-033) | Internal crossover fixed at init: VVC port `a` would carry model B in the waveform; the index-state bit exchange stays manual anyway | 2026-11-09 |
| D-53 | AD-21 | A/B levels | All states and edge names are pin levels; no `ab_inverted` (it would only move the zero state); `index_inverted` stays | States before inversion plus `ab_inverted` | 2026-11-09 |
| D-54 | AD-22, E-2.1 | Random bounce placement | Sorted uniform draws in the window; a toggle on the same resolution step as the previous one moves one step later (4.5.3 step 4) | Jittered even grid (one toggle per slot of 2p + 1) | 2026-11-09 |
| D-55 | AD-23 | Jittered edge near the start or end of a move (F-017) | Clamped into its segment: not before the start, for a move not after the end (4.5.2) | Clamp at the start only; the move waits for a late last edge (completion later than REQ-092) | 2026-11-09 |
| D-56 | AD-24 | Invalid `bounce_window` or `jitter` written during a rotation | As D-31: `TB_ERROR` once per invalid value, the last valid signal configuration is kept | Treat the invalid value as off | 2026-11-09 |
| D-57 | AD-25 | Bounce cut-off with the channel at its bounced level (F-016) | Settle one delta before the edge, same simulation time (4.5.3 step 1) | Settle one resolution step before the next nominal edge, scheduled with the bounce: fails for speed changes and jittered edges | 2026-11-09 |
| D-58 | AD-26 | Random streams of bounce and jitter | One stream from `rand_seed1`/`rand_seed2` for both; enabling bounce or changing `bounce_pulses` changes the jitter sequence; a run stays reproducible for the same seeds and configuration | Separate seeds per feature: jitter independent of bounce, but four more configuration fields and a public API change | 2026-11-10 |
| D-59 | arch D-1 | `rotary_encoder_center_state` while a motion is active | `TB_ERROR`, nothing changes | Centre at the current angle and halt the motion | 2026-11-09 |
| D-60 | TD-1 | Test counterpart | Independent decoder checker + event log in the testbench (spec §8), no DUT | VVC↔VVC loopback: impossible without a receiver role; behavioural RTL decoder as DUT: hides delta-level detail and needs its own verification | 2026-10-27 |
| D-61 | TD-2 | Testbench split | BFM testbench for every signal-level feature (30 test cases), VVC testbench for framework, command and rotation semantics (21); the VVC testbench spot-checks each move kind (`vvc_commands`) | Everything through the VVC: slower to debug, BFM-only use untested beyond REQ-080 | 2026-10-27 |
| D-62 | TD-3, X-6, X-14 | Start-angle and zero-state matrix | Matrix in the BFM testbench; the generic path once through VVC instance 3 (30°, zero state `00`); a changed zero state is detected at command start against the value kept in the state | One VVC instance per configuration (eight VVCs in every test) | 2026-10-27 |
| D-63 | TD-4 | Coverage of `rotary_encoder_rotate` (F-006) | REQ-080 acceptance criteria include the three overloads of `rotary_encoder_rotate` | Leave it untested: an unverified public procedure fails the audit's API coverage | 2026-10-27 |
| D-64 | TD-5 | Checker behaviour | Counts silently; every step ends with an explicit `check_checker` with expected counts | Alert on every violation, with expected-alert bookkeeping in every error test | 2026-10-27 |
| D-65 | TD-6 | `test.py` and per-VIP files | Official scripts first: copied from `bitvis_vip_gpio` with the four permitted edits; started from `<vip>/sim` | PWM's script: carries four non-official changes | 2026-10-27 |
| D-66 | TD-7 | When S-1 (`adaptations_pkg`) is changed | Stage 5.1: the generated `transaction_pkg` aliases the constants, so nothing compiles without them | Stage 5.4 with local constants until then | 2026-10-27 |
| D-67 | TD-8 | Expected rpm-form edge times | Exact `time`/`integer` long division for integer rpm (7.3) | One `real` formula: ≈ 16 fs error at 86 s, larger than the fs tolerance | 2026-10-27 |
| D-68 | TD-9 | Where the rotation part of REQ-045 is tested | `config_change_during_rotation`: only the VVC re-reads the configuration during a rotation; a BFM call gets its `config` once | Also in the BFM: impossible, the BFM `config` is a constant per call | 2026-11-09 |
| D-69 | TD-10 | Increment 1 after the detent removal | Rework the existing Inc 1 code in place and rerun its regression | Discard and rewrite Inc 1 | 2026-11-09 |
| D-70 | X-1 | REQ-082 after the angle model | A move stops at once at the current angle, without a snap, as REQ-107 | "Stops after the current edge", from before the angle model | 2026-10-27 |
| D-71 | X-3 | REQ-091 for angles with more than 7 decimals | Rounded once per move to the quantum; noted in REQ-091; the test values (1°, 0.1°) are exact | – | 2026-10-27 |
| D-72 | X-8 | Are REQ-012/101 timing criteria achievable at fs? | Yes with 4.5.2: 10 revolutions at 7 rpm last 86 s ≈ 8.6·10¹⁶ fs, which fits 64-bit `time`; the split computation keeps the `real` part small | – | 2026-10-27 |
| D-73 | X-9 | Are the REQ-061 statistics criteria safe? | Yes: the mean of 10 000 uniform samples has σ ≈ A/173, the bound A/10 is 17σ; the chance of missing the outer 5 % at either end is 0.975¹⁰⁰⁰⁰ ≈ 10⁻¹¹⁰ | – | 2026-10-27 |
| D-74 | X-10 | Completion at the first edge (REQ-100, 102, 111) | `p_motion` responds to the start or change on `motion_rsp` at the first edge (D-99) | – | 2026-10-27 |
| D-75 | X-11 | Offsets and completion times (REQ-075, 076) | With offsets in (−45°, +45°) every boundary stays between its two state centres, so completion times and positions hold; only edge times change (D-28) | – | 2026-10-27 |
| D-76 | X-12 | REQ-001 vs. a stuck `'Z'` (REQ-078) | REQ-001 has the stuck-`'Z'` exception | – | 2026-10-27 |
| D-77 | X-13 | Which configuration is geometry? (REQ-108) | Offsets move edge angles, so they are geometry (motion start); stuck outputs are signal configuration (every edge) | – | 2026-10-27 |
| D-78 | X-15 | Index acceptance values (REQ-042, 046) | Follow from the index decision 4.5.4; the window always runs forward | – | 2026-11-09 |
| D-79 | X-16 | An invalid index value that stays in the configuration during a rotation | Raised once per invalid value (not at every edge); Z keeps the last valid configuration; the test expects exactly one `TB_ERROR` | – | 2026-11-09 |
| D-80 | E-1.1 | Private fields of `t_rotary_encoder_state` | Declared in the package (VHDL needs the full record), commented "All fields are private" | – | 2026-11-09 (Inc 1) |
| D-81 | E-1.2 | Testbench expected-time function | Long division as 7.3, with a self-test in Stage 5.2 | – | 2026-10-27 (Stage 5.2) |
| D-82 | E-1.3 | Profile length constant in the BFM | The motion record uses `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` from `adaptations_pkg` directly | – | 2026-11-09 (Inc 1) |
| D-83 | E-1.4 | BFM procedures that check the kept zero state | They take `config`; `rotary_encoder_center_state` has it, no other Inc 1 procedure lacked it | – | 2026-11-09 (Inc 1) |
| D-84 | arch rev 0.6 | Name of the engine procedure that activates a motion | `rotary_encoder_set_motion`: it drives no output, but it is not time-neutral either | `start_motion`, `prepare_motion` | 2026-11-09 |
| D-85 | OQ-1 | Status read-back (U-2) had no feature ID | New REQ-086 (High) with its own acceptance criteria; BFM part tested in Inc 3 (`move_angle`), VVC part in Inc 4 (`vvc_commands`), rotation part in Inc 5 (`rotation_speed_change`) | Leave it without a feature: the audit's API coverage would flag a public function without criteria | 2026-11-11 |
| D-87 | – | REQ-075 criterion said B edges are 1/3 µs later "forward and reverse", which contradicts spec A-25 (an offset is an angle, the same in both directions) (finding F-024) | Criterion corrected: later going forward, earlier going in reverse; the spec is unchanged | Offsets relative to the direction of motion: hysteresis, contradicts A-25 | 2026-11-11 (Inc 3) |
| D-88 | – | `duration` of `rotary_encoder_rotate` ≤ 0 ns | `TB_ERROR`, nothing happens (added to REQ-110) | 0 ns legal (start and stop at once) | 2026-11-11 (Inc 3) |
| D-89 | E-3.2 | Log line of fault events | The call with its arguments, then the edge distance and direction ("in zero time"), end position, angle and AB (4.6.4) | – | 2026-11-11 (Inc 3, taken in one-shot) |
| D-90 | – | `rotary_encoder_init` and edge offsets | Init validates the offsets like a command and places the start angle in the state that contains it with the offsets | Validate only at the first motion: init would latch invalid geometry | 2026-11-11 (Inc 3, taken in one-shot) |
| D-91 | – | A bounce still running when a fault event starts | Settled at once without the cut-off alert (that alert reports a bounce cut by the next edge); one delta before the new state if the channel was at its bounced level | Raise `bounce_cut_severity` as at an edge | 2026-11-11 (Inc 3, taken in one-shot) |
| D-92 | – | Return value of `rotary_encoder_linear_ramp` after a `TB_ERROR` | An empty profile, so that a rotation started with it is rejected again | A one-entry profile of 0 rpm (would start a rotation silently) | 2026-11-11 (Inc 3, taken in one-shot) |
| D-93 | – | A resting shaft lies outside its state after the edge offsets were changed (possible only for an offset change between commands, with the shaft within a quarter edge of a boundary) | No correction at the latch: a motion towards the moved boundary emits that edge at its start; in the other direction the state stays until its other boundary | Re-resolve the state at the latch: the outputs would change without a motion | 2026-11-11 (Inc 3, taken in one-shot) |
| D-94 | – | Range of `rotary_encoder_jump_edges` | Target position within ±(`integer'high` / 2), else `TB_ERROR`; keeps edge counts in `integer` | No check: an integer overflow stops the simulation | 2026-11-11 (Inc 3, taken in one-shot) |
| D-95 | E-4.1 | When is the interpreter change for `halt_req` (F-004) made? | In Increment 5, together with its test `terminate_and_flush_during_rotation`; Increment 4 has no rotation, so a terminate always finds the executor busy | In Increment 4 without a test that exercises it | 2026-11-11 (Inc 4, taken in one-shot) |
| D-96 | – | Which configuration does a running VVC move use (finding F-026)? | The `vvc_config.bfm_config` taken at the move start (REQ-084); only a rotation re-reads it at every edge (REQ-108) | Re-read at every edge for moves too, as the former loop sketch did: contradicts REQ-084 | 2026-11-11 (Inc 4, taken in one-shot) |
| D-97 | – | How does a VVC move apply a changed stuck setting at its start (REQ-078, finding F-027)? | `rotary_encoder_run_motion` applies a changed stuck setting at each call; only the changed outputs are driven, so a running bounce continues | A new public engine procedure for it (public API change); apply it only at the next edge (a release would show late) | 2026-11-11 (Inc 4, taken in one-shot) |
| D-98 | E-4.2 | What does the transaction info carry, and how do zero-time and rejected commands end? | Parameters at `IN_PROGRESS`; the effect at the end: `edges` of a move and the end `status` (for `get_status` its result, as GPIO's `GET`). A rejected move ends with `FAILED`, every other command with `COMPLETED`; zero-time commands set both in one time step (4.6.5) | Parameters only (a model would have to reimplement the angle model to know the effect of an angle, to-state, set-angle or jump command); `COMPLETED` also for a rejected move (a model could not tell it from a real one); no transaction info (as `bitvis_vip_clock_generator`) | 2026-11-11 (user, option A) |
| D-99 | – | Executor ↔ `p_motion` handshake | One request record with the whole command and one response record per request (`motion_rsp`: idx, accepted, edges, status) instead of separate `motion_ack`, `motion_done`, `first_edge_ack`, `motion_status`; the executor waits for the response or `terminate_current_cmd`, then sends `REQ_HALT`. A move's alert names `rotary_encoder_set_motion(MOTION_…)`, preceded by the executor's "Will be executed" line of the VVC call | Four acknowledge signals: more signals for the same information | 2026-11-11 (Inc 4, taken in one-shot) |
| D-100 | – | Does the VIP produce glitches (former REQ-072; the VVC command had no declaration in the API preview)? | No: the glitch is removed from spec A-12, the features (REQ-072), the BFM (`rotary_encoder_glitch`) and the VVC. Bounce, jitter and edge offsets in the BFM configuration cover the short pulses and states a decoder must handle | A VVC method `rotary_encoder_glitch`; a glitch as a configured device fault after every N-th edge | 2026-11-11 (user, Inc 4) |
| D-101 | E-5.3 | When does a change of the shared configuration reach a running VVC rotation (F-018)? | After every edge `p_motion` takes the shared configuration for the next edge; a change between edges k and k+1 takes effect from edge k+2. Requests in between (status read) do not refresh it, so the rule does not depend on other commands. REQ-108 reworded | A new public engine event `MOTION_EDGE_DUE` (run_motion returns before each edge and is called again with the current configuration; jitter of edge k+1 from the amplitude at edge k): public API change for a one-edge difference | 2026-11-11 (user) |
| D-102 | – | `terminate_current_command` during a rotation while the executor runs another command (e.g. `insert_delay`) | The rotation is halted as well, and the command in the executor is terminated as usual (REQ-107) | Only the current command (strict framework semantics): the rotation would keep running although the user terminated "during the rotation" | 2026-11-11 (user) |
| D-103 | – | Transaction status of commands the VVC rejects because of the rotation state or invalid rotation parameters | `FAILED` for every command the VVC rejects with `TB_ERROR`; a stop without rotation (only a warning) `COMPLETED` (extends D-98) | Only rejected moves and rotation commands `FAILED`, centre state and fault events `COMPLETED` | 2026-11-11 (user) |
| D-104 | E-5.1 | Response of a rotation start or speed change that arrives exactly at an edge time | The edge at that time belongs to the old motion (D-25: the edge is driven in the first delta of its time, the request arrives later); the command completes at the first edge after it. A reverse start on a boundary therefore emits its first edge at once | Count the edge at the change time as the first edge of the change: it does not show the new speed | 2026-11-11 (Inc 5, taken in one-shot) |
| D-105 | – | Where are the rejections that depend on the rotation state decided? | In `p_motion`, which owns the state: it answers `accepted` false and the executor ends the transaction with `FAILED` | In the executor from the signal `rotation_active`: one delta behind a rotation that ends by itself (`PROFILE_STOP`) | 2026-11-11 (Inc 5, taken in one-shot) |
| D-106 | E-5.2 | `terminate_current_command` and a rotation command that is queued but not yet executed | The interpreter decides by `rotation_active` only: a queued start is not affected (the framework's terminate does not reach queued commands either; `flush_command_queue` removes them) | Also cancel queued rotation commands: differs from the framework's semantics | 2026-11-11 (Inc 5, taken in one-shot) |

---

## 12. Change history

| Rev | Date | Change | Approval |
|---|---|---|---|
| 0.1 | 2026-11-10 | Merged from `rotary_encoder_vvc_reqs.md` rev 0.10, `rotary_encoder_vvc_arch.md` rev 0.9 and `rotary_encoder_vvc_tb_arch.md` rev 0.6 (their history is in Git). Removed features, obsolete decisions and revision markers dropped; decision families merged into one log with old IDs; test-case mapping kept only in the test plan; usage examples moved to the use-case walkthrough (new U-2 check line and U-3 snippet); former U-4 moved to Architecture 4.1; OQ-1 opened | Approved by the user 2026-11-11 |
| 0.2 | 2026-11-11 | New REQ-086 status read-back (OQ-1, D-85); test plan and increments updated | Approved by the user 2026-11-11 |
| 0.3 | 2026-11-11 | Increment 3 decisions: REQ-072 glitch on a stuck channel (D-86), REQ-075 reverse criterion corrected (D-87), REQ-110 `duration` ≤ 0 ns of `rotary_encoder_rotate` (D-88); 4.5.6, test plan and increments updated. Internal decisions D-89 to D-94 (taken in one-shot) in 4.5.6, 4.6.4 and the decision log | Approved by the user 2026-11-11 (D-89 to D-94 with Increment 3) |
| 0.4 | 2026-11-11 | New BFM test case `linear_ramp_rotation` (a long, slow linear ramp as a rotation profile) in the test plan and Increment 3 | Requested and approved by the user 2026-11-11 |
| 0.5 | 2026-11-11 | Increment 4: glitch removed (spec rev 0.13, REQ-072, BFM and VVC API, test `glitch`; D-100; 71 features); `p_motion` loop, signals and configuration per motion kind (4.5.5, 4.6.1; D-96, D-97, D-99); logging; transaction info with the effect of each command (`edges`, end `status`) and `FAILED` for a rejected move (4.6.4, 4.6.5; D-98); `halt_req` moved to Increment 5 (D-95); placeholder test `vvc_instances_execute_commands` removed as decided in Stage 5.2 (30 BFM and 20 VVC test cases, 50 in total); `vvc_commands` content made explicit | Approved by the user 2026-11-11 (with Increment 4) |
| 0.6 | 2026-11-11 | Increment 5: REQ-107 terminate also halts a rotation while the executor runs another command (D-102); REQ-108 configuration read after every edge, a change takes effect from the edge after the next (D-101); transaction info `FAILED` for every command the VVC rejects (D-103); 4.5.5, 4.5.7, 4.6.1, 4.6.2, 4.6.4, 4.6.5, test plan and increments updated. Internal decisions D-104 to D-106 (taken in one-shot) | Approved by the user 2026-11-11 (with Increment 5, incl. D-104 to D-106) |
| 0.7 | 2026-11-11 | Increments: Stage 5.4 row shows the result (shared files, three simulators, VSG version) | Review pending (Stage 5.4 boundary) |
