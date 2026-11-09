# Rotary / Incremental Quadrature Encoder – Baseline Specification

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_spec.md` |
| Revision | 0.7 |
| Status | **Proposed** (rev 0.7, change after approval; rev 0.6 approved 2026-10-27) |
| Route | A – drafted baseline spec (de-facto protocol, no single formal standard) |
| Target | Generic: mechanical rotary encoders (EC11-style knobs) and optical/magnetic incremental encoders with A/B(/Z) outputs. Detents are not modelled (§9) |

Items marked **[A-nn]** are *assumptions*: conventions chosen for this baseline, not universal facts. Items marked **[Q-nn]** are questions that were open during drafting; the answers are recorded in Section 11.

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-21 | Initial draft |
| 0.2 | 2026-10-21 | Push-button switch removed (Q-01: handled by a GPIO VVC), A-09 withdrawn |
| 0.3 | 2026-10-21 | Terminology: "step" renamed to **edge**. PPR/CPR/count are no longer used as spec terms and a datasheet translation table was added. Q-02 (optional jitter), Q-03 (generate and detect errors, new A-12) and Q-04 (open-drain out of scope) resolved. Detent explained, `edges_per_detent = 1` covers non-detented parts |
| 0.4 | 2026-10-21 | Change after approval, requested by the user: movement by angle with sub-edge angle tracking (new §4.6, A-13). Detent modelling can be switched off, and angle moves snap to the nearest detent (§5.1, A-14). Angle 0° is the centre of a state, so edges and detents are symmetric in both directions (A-13, A-15). Index enabled by default with `cycles_per_rev` = 20 (A-10). `cycles_per_rev` is now a general parameter, not index-only. `t_edge` renamed to `time_per_edge`. `t_edge_min` removed (a decoder property, not needed for generation) and the edge-spacing violation command dropped. Configurable start angle replaces the start state and position (A-16). §8 and A-11 relabelled as informative (encoder-only VVC) |
| 0.5 | 2026-10-27 | Change after approval, requested by the user. **Continuous rotation** (new §4.7, A-17 to A-20): start, change speed and direction while turning, stop. **Speed profiles** for rotations over time (§4.7.1, A-21, A-22). **Physical speed** (Q-07): speed in rpm, independent of `cycles_per_rev`; `time_per_edge` stays as an alternative form and as the derived edge interval (§4.4, A-23); edge times without accumulated rounding (A-24). As a consequence: jitter in electrical degrees (A-05), bounce window cut at the next edge (A-07), snap speed (A-19). New terms *speed*, *move*, *rotation* (§2) |
| 0.6 | 2026-10-27 | Change after approval, requested by the user in Phase 3. Error generation (§4.5) split into **device faults** set by configuration and **fault events** on request. New device faults: **edge offsets** per channel and edge (A-25: sensor misalignment, phase, duty and state-width error) and **stuck channels** (A-26). The illegal-transition request is replaced by two general requests in zero time (A-12): **set angle** (absolute, optionally on the nearest detent, also to bring the encoder to a known angle) and **jump** (relative, N edges). Jitter limit generalized for offsets (A-05). Boundary rule added to A-13 (a shaft exactly on a boundary is in the state it moved into, F-003). New terms *edge offset*, *set angle*, *jump*, *stuck channel* (§2) |
| 0.7 | 2026-10-28 | Change after approval, requested by the user after Stage 5.3 Increment 1 (complexity, Q-09). **Detents removed completely**: no detent term, no `edges_per_detent`, no detent moves, no snap after angle moves (A-14), rotation stop (A-19) or profile stop, no detent option for set angle (A-12), no detent placement of the start angle (A-16). The rest state is renamed **zero state** (`zero_state`) and stays configurable (A-06, reworded: the state at angle 0°, default `AB = 11`; it differs between manufacturers); the start angle stays (A-16). A-14 and A-15 withdrawn. §5 is contact bounce only. Detents added to the out-of-scope list (§9) |

---

## 1. Scope

An incremental (quadrature) encoder reports relative motion of a shaft on two digital channels **A** and **B** whose square waves are 90° out of phase. The sign of the phase difference gives the direction, the number of edges gives the distance. An optional **index** pulse **Z** (once per revolution) marks a reference position. The push-button switch found on many hand-operated rotary encoders is not part of this specification (Section 9).

This specification describes the signal-level behaviour at the logic level, as seen by the decoder that receives the signals. It is deliberately device-independent; every device-specific property is a parameter.

## 2. Terminology

Only terms that are directly visible in a waveform are used. The vendor terms PPR, CPR and "count" are ambiguous (vendors disagree by a factor of 4), so they are only used in the translation table in 2.1.

| Term | Definition |
|---|---|
| State | The 2-bit value `AB` of the two quadrature channels. |
| Edge | One transition on A **or** B, i.e. a change between two adjacent states. It is the smallest movement the encoder can report. |
| Zero state | The state at angle 0° (position 0); configurable, default `AB = 11` (A-06). Angle 0° lies in the middle of this state (A-13). |
| Cycle | Four consecutive edges in one direction; one full period of A (and of B). 360° electrical. |
| Electrical degree | 1/360 of a cycle. One edge angle = 90° electrical. |
| Speed | Rotational speed of the shaft in revolutions per minute (rpm). It is a property of the shaft and does not depend on `cycles_per_rev` (§4.4). |
| `time_per_edge` | The time the shaft needs to turn one edge angle at the current speed. At constant speed it equals the time between two consecutive edges. It is derived from the speed (§4.4), or given directly where an exact edge spacing is needed. |
| Forward / reverse | Direction labels; mapped to CW/CCW by [A-02]. |
| Index (Z) | Optional pulse marking one reference position per revolution. |
| `cycles_per_rev` | Number of cycles per mechanical revolution (default 20). Defines the edge angle and the index spacing. |
| Edge angle | Shaft rotation between two edges = 360° / (4 × `cycles_per_rev`). Default: 4.5°. |
| Angle | Mechanical shaft angle in degrees, tracked with sub-edge precision (§4.6). |
| Move | A movement of fixed length (edges or angle) that ends by itself (§4.6). |
| Rotation | A continuous movement without a fixed length. It turns until it is stopped, and its speed and direction can be changed while it turns (§4.7). |
| Bounce | Short spurious toggles of a mechanical contact around a transition. |
| Edge offset | Fixed angular displacement of one kind of edge from its ideal position, in electrical degrees, caused by the device (e.g. a misaligned sensor) (A-25). |
| Stuck channel | An output that holds a fixed level regardless of the shaft, e.g. a dead sensor or a broken wire (A-26). |
| Set angle | Placing the shaft at an absolute angle in zero time; the state changes directly from the old to the new state (A-12). |
| Jump | Moving the shaft by N edges in zero time; the state changes directly from the old to the new state (A-12). |

### 2.1 Datasheet translation

| Datasheet term | Usually means | In this spec |
|---|---|---|
| PPR (pulses per revolution), lines, line count, signal periods | Full A periods per revolution | `cycles_per_rev` |
| CPR | **Ambiguous**: "cycles per revolution" (e.g. US Digital, Broadcom/Avago HEDS) = `cycles_per_rev`, or "counts per revolution" = 4 × `cycles_per_rev` edges. Check the part's datasheet. | `cycles_per_rev` or edges per revolution |
| ×4 counts, quadrature counts | Edges | edges |
| ×2 counts | Edges on A only | – (derived) |
| ×1 counts | Cycles | cycles |
| Detents per revolution | Mechanical clicks per revolution | Not modelled (§9). One click is an edge move of 4 × `cycles_per_rev` / detents per revolution edges |
| Max. speed / rpm | Rotational speed | speed (rpm) |
| Phase error, state width error (° electrical) | Deviation of an edge from its ideal position | jitter amplitude (A-05) |

### 2.2 Identifier mapping (provisional, finalized in Phase 3)

| Spec term | Proposed VHDL identifier |
|---|---|
| A, B | `enc_a`, `enc_b` |
| Z / index | `enc_z` (`index` in configuration names) |
| edge | `edge` (e.g. `num_edges`) |
| cycles per revolution | `cycles_per_rev` |
| zero state | `zero_state` (replaces `rest_state`) |
| angle | `angle` (degrees, `real`) |
| speed | `rpm` (`real`) |

## 3. Signals

| Signal | Direction (encoder → decoder) | Required | Description |
|---|---|---|---|
| A | out | yes | Quadrature channel A |
| B | out | yes | Quadrature channel B |
| Z | out | optional | Index pulse, once per revolution |

- **[A-01]** All signals are single-ended single-bit logic signals (`std_logic`). The logic model drives strong `'0'`/`'1'` (push-pull). The only exception is an output configured as stuck at `'Z'` (A-26). Open-drain/pull-up behaviour is out of scope (Section 9).
- The encoder has no clock; all timing is asynchronous to any system clock.

## 4. Quadrature behaviour

### 4.1 State sequence

The states follow the 2-bit Gray-code sequence. Exactly one channel changes per edge.

```
forward:  AB = 00 → 10 → 11 → 01 → 00 → ...   (A leads B)
reverse:  AB = 00 → 01 → 11 → 10 → 00 → ...   (B leads A)
```

- **[A-02]** *Forward* is defined as **A leading B** by 90° and is mapped to clockwise rotation (viewed from the shaft end). Manufacturers differ on this mapping; a configuration option swaps the direction convention (equivalent to swapping A and B).
- **[A-03]** Polarity: the sequence above is in *logic* levels. A configuration option inverts the electrical level of A and B (for encoders whose contacts pull to ground, where "closed" = `'0'`). Default: non-inverted.

### 4.2 Direction changes

- The direction may reverse after any edge, including in the middle of a cycle; the reversal is the reverse transition from the current state (e.g. `10 → 11 → 10`). This is legal and occurs in real systems (operator reversal, vibration dithering around an edge).

### 4.3 Illegal transitions and glitches

- A transition in which **A and B change at the same time** (e.g. `00 → 11`) is an *illegal transition*: the direction cannot be determined. In real systems it is caused by excessive speed, noise or missed samples. A decoder must flag it as an error.
- A decoder has a minimum edge spacing that it can resolve (a property of its input filter and sampling clock, specified on encoder datasheets as a phase-error tolerance such as 90° ± 45° electrical). A pulse on A or B that is shorter than this is a *glitch*. The decoder may filter or flag it ([A-11]). This is a property of the receiving side. The encoder model has no such limit; any speed may be generated.

### 4.4 Speed and timing

The speed is a property of the shaft. The same speed produces different edge spacings on parts with different `cycles_per_rev`.

| Parameter | Meaning | Constraint |
|---|---|---|
| Speed (rpm, `real`) | Primary form of every speed: moves, rotations and profiles. | Moves: > 0, the direction is given separately. Rotations and profiles: signed; positive = forward, negative = reverse, 0 = standstill while the rotation stays active (§4.7). Finite. |
| `time_per_edge` (`time`) | Alternative form, for tests that need an exact edge spacing (e.g. a decoder input filter or minimum-spacing test). Also the name of the edge interval derived from a speed. | > 0 when given directly; the direction is given separately. |

- **[A-23]** Relation: `time_per_edge` = 60 s / (|rpm| × 4 × `cycles_per_rev`). Conversion functions are provided in both directions, and between rpm and degrees per second (1 rpm = 6 °/s). Example with the default part (20 cycles): 60 rpm ↔ 12.5 ms per edge; 6000 rpm ↔ 125 µs.
- **[A-24]** Exactness: edge times are computed from the exact (real-valued) motion model. Only the absolute time of each edge is rounded to the simulator resolution; rounding errors do not add up within a move, nor within a rotation between two speed changes. Each edge therefore lies within one resolution step of its ideal time. When the speed is given as `time_per_edge` and `time_per_edge`/2 is representable, the edge times are exact. A move or speed change starts at the (already rounded) simulation time at which it takes effect.
- **[A-04]** Baseline motion model: within one move, within a rotation between two speed changes, and within one profile entry, the speed is constant, so all edges have the same nominal `time_per_edge` (ideal 90° phase). Speed curves (acceleration, deceleration) are built from consecutive moves with different speeds, from speed changes of a rotation, or from a speed profile (§4.7.1).
- **[A-05]** Phase error (non-ideal edge positions within a cycle) is modelled as optional, configurable **edge jitter** with an amplitude *j* in **electrical degrees**, as on datasheets. Each edge is displaced from its ideal time by a random offset of up to ± *j*/90 × `time_per_edge` (*j*/90 edge angles at the current speed). The offset only moves that edge; it does not carry over to the following edges. 0 ≤ *j* < half the width of the narrowest state, so two neighbouring edges can never swap their order. Without edge offsets (A-25) every state is 90° wide, so the limit is 45° electrical. The amplitude is independent of the speed. Default: off.
- When no move and no rotation is active, the encoder is at standstill: A and B hold their last state indefinitely. There is no idle level other than the current state.

### 4.5 Device faults and fault events (for testing decoders)

To verify how a DUT decoder handles non-ideal or faulty encoders, the encoder side models two kinds of faults. Normal movements of an encoder without configured faults are always legal.

#### 4.5.1 Device faults (configuration)

A device fault is a property of the part. It is configured, stays active until it is configured off, and applies to every move and rotation.

- **[A-25] Edge offsets.** Each of the four edges of a cycle can be displaced from its ideal angle by a fixed offset in electrical degrees: the edge where A rises, where A falls, where B rises and where B falls, each named after its level change in the **forward** direction (in reverse, the same edge is the opposite level change at the same angle; there is no hysteresis). The offsets refer to the logical channels A and B, before the direction swap (A-02) and the polarity inversion (A-03).
  - Equal offsets on both edges of one channel shift that channel: phase error, e.g. a misaligned B sensor. Different offsets on the rising and falling edge of one channel change its duty cycle (symmetry error). Any combination gives the state-width error that datasheets specify.
  - Because the offsets are angles, the resulting edge-time displacement scales with the speed and is the same in both directions.
  - Each offset lies in the open interval (−45°, +45°) electrical. Every state is then still wider than 0° and still contains its ideal centre, so positions and the index (§6) are unchanged; only the edge angles move. Default: all 0°.
  - Z changes together with the A/B edge that enters or leaves the index state, so it follows the offsets.
- **[A-26] Stuck channels.** Each output (A, B, Z) can be configured as stuck at `'0'`, `'1'` or `'Z'` (high impedance, e.g. a broken wire with no pull resistor). A stuck output drives that level instead of the model's level; it does not bounce and ignores the polarity inversion. The model keeps running underneath: when the output is released, it returns to the level of the current state. The stuck level is an electrical level of the output pin, after the direction swap. Default: no output stuck.

#### 4.5.2 Fault events (on request)

- **[A-12]** On explicit request, the encoder produces:
  - a **set angle**: the shaft is placed at an absolute angle in degrees (any `real`, also outside one revolution) in zero time. It brings the encoder to a known angle, e.g. between test cases. It is not a power-up (§7): the start angle is not re-read.
  - a **jump** of N edges in a given direction from the angle at the time of the request, in zero time; the sub-edge fraction is kept.

  For both, the outputs change directly from the old to the new state, in one step, and Z takes the level of the new state without a pulse for skipped positions. What a decoder sees depends on the edge distance N between the old and the new position: N mod 4 = 2 is an illegal transition (A and B change at the same time); N mod 4 = 0 changes nothing on A/B but moves the position (lost cycles, as with missed samples at too high a speed); N mod 4 = 1 or 3 is one legal edge, which for N mod 4 = 3 points in the opposite direction. If the new angle lies exactly on a boundary, the shaft is in the state on the side of the old angle (it has not crossed the boundary).
  - a **glitch**: a pulse on A or B of configurable width, after which the output returns to its previous value. The position does not change.

  Edges that are too close for a decoder need no special request: they are an ordinary move with a high speed or a small `time_per_edge`.

### 4.6 Movement by angle

- **[A-13]** The encoder keeps the shaft angle with sub-edge precision. Each state covers one edge angle, and the state is a function of the angle alone (no hysteresis). Angle 0° is the **centre** of the zero state (A-06, default `AB = 11` in logical levels, position 0), so the edges lie at ±½, ±1½, ±2½ … edge angles. An edge is emitted whenever the angle crosses one of these boundaries, in either direction. The edge is emitted when the angle *reaches* the boundary: a shaft that stands exactly on a boundary is in the state it moved into. A following movement in the opposite direction therefore emits its first edge at its start.
- Angle moves smaller than the edge angle accumulate. With an edge angle of 4.5°, starting at 0°, three moves of 1° produce one edge, during the third move, at the moment the 2.25° boundary is crossed.
- An **edge move** of N edges is an angle move of N edge angles. Starting from the centre of a state, its edges occur ½, 1½, … N−½ × `time_per_edge` after the move starts. The move ends in the centre of the new state, N × `time_per_edge` after it started. Back-to-back edge moves at the same speed therefore keep an edge spacing of `time_per_edge` (A-24), in both directions.
- The angle is not rounded between moves, so a sequence of moves that adds up to one revolution produces exactly 4 × `cycles_per_rev` edges.
- An angle move turns at constant speed, given in rpm or as `time_per_edge`, the same as for edge moves. A move of angle φ takes φ / edge angle × `time_per_edge` (= φ / (6 × rpm) seconds), also when no edge is crossed.
- Edge moves change the angle by whole edge angles and keep the sub-edge fraction. Edge and angle moves can be mixed.
- Every move ends exactly at its target angle; there is no correction movement afterwards.

### 4.7 Continuous rotation

A rotation models a shaft that keeps turning, e.g. a motor with an encoder, while the test does other things. It uses the same angle model as moves (A-13): the angle changes at constant speed between speed changes, and an edge is emitted at each crossing of an edge boundary.

- **[A-17] Start.** A rotation starts at the current angle with a given speed: a signed rpm value, or a `time_per_edge` with a direction. It turns until it is stopped; it has no length. 0 rpm is legal: the rotation is active but the shaft stands still. Starting from the centre of a state, the edges occur ½, 1½, 2½ … × `time_per_edge` after the start, as for an edge move. Starting with a sub-edge fraction (e.g. after an angle move), the first edge comes when the next boundary is reached.
- **[A-18] Speed and direction change.** While a rotation turns, its speed (and with it the direction, by the sign) can be changed. The change takes effect **at once**, at the current angle; there is no wait for the next edge or state centre. The rest of the current edge angle is covered at the new speed. A direction change reverses from the current angle, so the next edge is the boundary that was crossed last if the change comes before the next boundary is reached (no hysteresis, A-13). Any time between two edges is legal, so a change shortly after an edge produces a short state; this is physical behaviour, not a glitch.
- **[A-19] Stop.** A stop ends the rotation at once, at the current angle. The shaft stays at the reached angle, including its sub-edge fraction; no edges follow.
- **[A-20] Exclusivity.** While a rotation is active (also at 0 rpm), the shaft has no other motion: moves (§4.6) and fault events (§4.5.2) are not available until the rotation is stopped. A second start while a rotation is active is not a restart; the speed is changed with A-18.
- The angle is not rounded at speed changes, so the angle model stays free of rounding drift (§4.6, A-24) except for the quantisation of the change time to the simulator resolution.
- Index (§6), bounce (§5), jitter (A-05), direction swap (A-02), polarity inversion (A-03) and device faults (§4.5.1) apply to rotations exactly as to moves.

#### 4.7.1 Speed profile

A speed profile describes a speed that changes over time, e.g. a motor that starts up under a heavy load. It is available for rotations only, not for moves.

- **[A-21] Profile.** A rotation start or a speed change can give a profile instead of a single speed: an ordered list of signed rpm values (entries) and a duration `time_per_entry` > 0. Time 0 is the moment the profile takes effect (A-17, A-18). Entry *j* (counted from 0) is the speed from *j* × `time_per_entry` to (*j* + 1) × `time_per_entry`; within an entry the speed is constant (A-04), and each entry boundary is a speed change as A-18. Entries may be 0 rpm and may change sign (reversal).
- **End of the profile** (chosen per call):
  - *hold*: the rotation continues at the last entry's speed;
  - *stop*: at the end of the last entry, the rotation stops as with A-19;
  - *repeat*: the profile starts again with entry 0 (e.g. a periodic load).
- A later speed change, with or without a profile, replaces the running profile (A-18).
- Jitter (A-05) and bounce (§5) are applied on top of the profile.
- **[A-22] Linear ramp.** A helper builds a profile of N entries whose speed changes linearly in rpm from a start to an end value. With equal `time_per_entry` this approximates constant acceleration as a staircase.

## 5. Contact bounce (mechanical encoders)

Mechanical encoders use sliding contacts. When a channel changes, it may toggle several times before settling.

- Bounce affects only the channel that is changing at that edge (the other one stays stable), so bounce looks like a legal back-and-forth movement on one channel (e.g. `10 ↔ 11`). It never produces an illegal transition by itself.
- **[A-07]** Bounce model: after the nominal edge, the changing channel toggles a configurable number of extra times (an even number of toggles, so it ends at the new value) within a configurable bounce window `t_bounce` (a time: it is a property of the contact, not of the speed). Default: bounce disabled. Typical datasheet values: bounce ≤ 2–5 ms at 60 rpm. If the next edge comes before the window has ended (high speed, or a speed change during the window), the bounce is cut off: the channel is at its settled value before the next edge, and the remaining toggles are dropped. An alert of configurable severity (default `TB_WARNING`) reports this once per move or rotation command.
- **[A-08]** The positions of the bounce toggles inside the window may be uniformly random (seeded, reproducible) or evenly spaced. Default when enabled: random.

## 6. Index pulse (optical / magnetic encoders)

- Z produces one pulse per revolution, i.e. once every `cycles_per_rev` cycles, at the same mechanical position in both directions.
- **[A-10]** Index width and gating are configurable:

| Index mode | Z is active while |
|---|---|
| gated ¼ cycle (default) | in the configured index state (default `AB = 11`) of the index cycle |
| gated ½ cycle | in two adjacent states of the index cycle |
| ungated 1 cycle | for the whole index cycle |

  Default: gated ¼ cycle at `AB = 11`, active high, polarity invertible.
- The index position (which of the `cycles_per_rev` cycles is the index cycle) is given in edges relative to position 0 (angle 0°). Default: 0, so the index cycle contains the zero state at 0°.
- Index is **enabled by default**, with `cycles_per_rev` = 20. Users whose part has no Z leave the signal unconnected. Index can be disabled (Z then stays inactive), e.g. to test a DUT with Z idle.

## 7. Initial state and reset

- An encoder has no reset input. When it is powered, the shaft can be at any angle.
- **[A-16]** The start angle is the position of the knob or motor shaft when the simulation starts; it is set by the user. It is configurable (default 0°, any `real` value). The start state, position and Z level follow from it. They are not configured separately: the state is the one whose centre is nearest to the start angle (A-13), and Z is the level that the index configuration gives for that position. This is power-up, not movement, so no edges are emitted.
- Example (defaults: 4.5°/edge, zero state `11`, index at position 0): start angle 0° gives `AB = 11` with Z active. Start angle 30° gives position 7 (the state centred at 31.5°), Z inactive.
- *(Informative)* A decoder that starts observing samples the current state as its reference. It does not count the initial state as an edge.

## 8. Expected decoder behaviour (informative)

*Informative.* These rules describe what a correct decoder infers from the signals. The VVC does not implement them (it is encoder-only). They are the reference for the testbench checker that verifies the encoder, and they explain what the fault features (§4.5) provoke in a DUT.

- **[A-11]** The receiver tracks the position in edges: each legal forward edge increments the position by one, each legal reverse edge decrements it by one. Positions in cycles are derived from it.
- An illegal transition (Section 4.3) is reported as an error. The position is not changed.
- A pulse on A or B shorter than the decoder's minimum resolvable edge spacing is a glitch (§4.3). The limit is a decoder property.
- `'X'`, `'U'`, `'Z'`, `'W'`, `'-'` on any signal is an error.
- An index pulse is checked against its expected state and gating (Section 6), when index is enabled.

## 9. Out of scope

| Item | Reason |
|---|---|
| Absolute encoders (SSI, BiSS, EnDat, Hiperface) | Serial protocols, different VIP |
| Analog sin/cos encoders | Analog signals |
| Differential electrical layer (RS-422 A+/A−) | Electrical; the logic level is the same as single-ended A/B |
| Hall-sensor commutation outputs (U/V/W) | Different 3-phase sequence |
| Step/direction and CW/CCW pulse interfaces | Different interface (may be a future extension) |
| Detents (mechanical rest positions, `edges_per_detent`, snapping to a detent) | Q-09: too complex for the benefit. A click of a detented knob is an edge move of the part's edges per detent (§2.1); the test places the shaft with moves and set angle |
| Physical modelling (inertia, load, friction) | Speed curves are given by the user as moves, rotation speed changes or speed profiles (§4.7.1). The model does not compute them from torque or inertia |
| Continuous speed curves within a profile entry (e.g. linear interpolation) | The speed is constant within an entry (A-04); finer curves use shorter `time_per_entry` |
| Speed profiles for moves | Q-06: rotations only |
| Open-drain / pull-up signal resolution (`'0'`/`'Z'` with external `'H'`) | Q-04: not needed |
| Push-button switch (SW) | Independent of A/B. It is driven by a GPIO VVC in the testbench (Q-01) |

## 10. Assumptions

| ID | Assumption | Default |
|---|---|---|
| A-01 | Push-pull strong `'0'`/`'1'` logic levels | yes |
| A-02 | Forward = A leads B = CW; convention swappable | A leads B |
| A-03 | A/B polarity invertible | non-inverted |
| A-04 | Constant speed within a move, a rotation segment and a profile entry; speed curves from several of them | yes |
| A-05 | Phase error as optional edge jitter, amplitude *j* in electrical degrees, 0 ≤ *j* < half the narrowest state (45° without offsets), displaces single edges without carry-over | off |
| A-06 | Configurable zero state: the logical state at angle 0° (position 0); manufacturers differ | `11` |
| A-07 | Bounce: N extra toggles of the changing channel within `t_bounce`; cut off at the next edge with an alert | off |
| A-08 | Bounce toggle placement random (seeded) or even | random |
| A-09 | *(withdrawn in rev 0.2: the push-button is out of scope)* | – |
| A-10 | Index ¼ / ½ / 1 cycle, configurable state and position | ¼ cycle at `11`, **enabled**, `cycles_per_rev` = 20 |
| A-11 | *(Informative, §8)* A decoder tracks position in edges; cycles derived | edges |
| A-12 | Fault events on request, in zero time: set angle (absolute) and jump (N edges relative; illegal transition for N mod 4 = 2); glitch | only on request |
| A-13 | Movement by angle with sub-edge angle tracking, no rounding drift; angle 0° is the centre of the zero state (A-06); a shaft exactly on a boundary is in the state it moved into | – |
| A-14 | *(withdrawn in rev 0.7: detents are out of scope)* | – |
| A-15 | *(withdrawn in rev 0.7: the zero state is A-06, angle 0° is A-13)* | – |
| A-16 | Configurable start angle (user-set position of the knob/motor at simulation start); start state, position and Z follow from it, without edges | 0° |
| A-17 | Continuous rotation: starts at the current angle with a signed rpm (or `time_per_edge` and direction), turns until stopped; 0 rpm legal | – |
| A-18 | Rotation speed and direction changes take effect at once, at the current angle | – |
| A-19 | Rotation stop takes effect at once and keeps the reached angle | – |
| A-20 | No moves or fault events while a rotation is active; a second start is not a restart | – |
| A-21 | Rotation speed profile over time: signed rpm entries, `time_per_entry`, end behaviour hold / stop / repeat chosen per call | – |
| A-22 | Linear-ramp helper: rpm linear over the entries | – |
| A-23 | Speed in rpm (primary) or `time_per_edge` (alternative); `time_per_edge` = 60 s / (\|rpm\| × 4 × `cycles_per_rev`) | rpm |
| A-24 | Edge times from the exact model, each rounded once; no accumulated rounding within a move or rotation segment | – |
| A-25 | Device fault: fixed edge offsets per channel and edge in electrical degrees, each in (−45°, +45°), on the logical channels | all 0° |
| A-26 | Device fault: A, B or Z stuck at `'0'`, `'1'` or `'Z'` on the output pin | none |

## 11. Resolved questions

| ID | Question | Answer |
|---|---|---|
| Q-01 | Push-button switch in scope? | No, it is handled by a GPIO VVC (2026-10-21) |
| Q-02 | Edge-time jitter / phase error needed? | Yes, as an optional feature, off by default ([A-05]) (2026-10-21) |
| Q-03 | Generate errors, or only detect them? | Both: generation is [A-12], detection is Section 8 (2026-10-21) |
| Q-04 | Open-drain mode needed? | No, it is out of scope (2026-10-21) |
| Q-05 | Continuous rotation (start at a speed, change it, stop) needed? | Yes, new §4.7 ([A-17] to [A-20]) (2026-10-27) |
| Q-06 | Non-constant speed (e.g. motor start-up under load)? | Yes, as a speed profile for rotations only, with end behaviour per call and one linear-ramp helper (§4.7.1, [A-21], [A-22]) (2026-10-27) |
| Q-07 | `time_per_edge` as the speed unit is abstract: the real speed depends on `cycles_per_rev`. | Speed in rpm, signed for rotations; `time_per_edge` kept as an alternative form for exact edge spacing; profiles over time (§4.4, [A-23], [A-24], §4.7.1) (2026-10-27) |
| Q-08 | One fixed illegal-transition request covers one symptom only; how are device faults such as a misaligned sensor modelled? | Device faults by configuration (edge offsets A-25, stuck channels A-26), fault events by request (set angle and jump replace the illegal transition; glitch kept) (§4.5) (2026-10-27) |
| Q-09 | Detents and snapping make the model and its API too complex (seen in Stage 5.3 Increment 1). Keep them? | No, removed completely in rev 0.7; detents are out of scope (§9). The zero state at 0° stays configurable (A-06, manufacturers differ) and the start angle stays (A-16) (2026-10-28) |
