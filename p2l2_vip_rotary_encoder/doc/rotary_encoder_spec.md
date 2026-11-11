# Rotary / Incremental Quadrature Encoder – Baseline Specification

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_spec.md` |
| Revision | 0.12 |
| Status | Rev 0.12 approved 2026-11-11 (authoritative source for the VVC features) |
| Route | A – drafted baseline spec (de-facto protocol, no single formal standard) |
| Target | Generic: mechanical rotary encoders (EC11-style knobs) and optical/magnetic incremental encoders with A/B(/Z) outputs. Detents are not modelled (§9) |

Items marked **[A-nn]** are *assumptions*: conventions chosen for this baseline, not universal facts. Items marked **[Q-nn]** are questions that were open during drafting; the answers are recorded in Section 11.

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-21 | Initial draft |
| 0.2 | 2026-10-21 | Push-button switch removed (Q-01) |
| 0.3 | 2026-10-21 | "Step" renamed to edge; datasheet translation; Q-02 to Q-04 resolved (jitter, fault generation, no open-drain) |
| 0.4 | 2026-10-21 | Movement by angle with sub-edge tracking (§4.6, A-13); configurable start angle (A-16); `time_per_edge` |
| 0.5 | 2026-10-27 | Continuous rotation (§4.7), speed profiles (§4.7.1), speed in rpm (§4.4, A-23, A-24); jitter in electrical degrees |
| 0.6 | 2026-10-27 | Device faults (edge offsets A-25, stuck channels A-26) and fault events (set angle, jump, glitch, A-12); boundary rule in A-13 |
| 0.7 | 2026-10-28 | Detents removed (Q-09); zero state (A-06); index cycle, index state and index width 1–4 (§6, A-10, Q-10 to Q-12); datasheet translation inverted |
| 0.8 | 2026-11-09 | Move to state (A-27) and centre state (A-28) (Q-13) |
| 0.9 | 2026-11-09 | Direction swap removed (Q-14) |
| 0.10 | 2026-11-09 | A/B polarity inversion removed; all states are pin levels (Q-15) |
| 0.11 | 2026-11-10 | Bounce example in A-07 corrected to datasheet practice |
| 0.12 | 2026-11-10 | VVC-specific content moved to the VVC design document (identifier mapping, configuration defaults, alert severity, helper functions); withdrawn and obsolete entries removed. No change to the protocol. Approved 2026-11-11 |

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
| Zero state | The state at angle 0° (position 0); it differs between parts (A-06). Angle 0° lies in the middle of this state (A-13). |
| Cycle | Four consecutive edges in one direction; one full period of A (and of B). 360° electrical. |
| Electrical degree | 1/360 of a cycle. One edge angle = 90° electrical. |
| Speed | Rotational speed of the shaft in revolutions per minute (rpm). It is a property of the shaft and does not depend on `cycles_per_rev` (§4.4). |
| `time_per_edge` | The time the shaft needs to turn one edge angle at the current speed. At constant speed it equals the time between two consecutive edges. It is derived from the speed (§4.4), or given directly where an exact edge spacing is needed. |
| Forward / reverse | Direction labels; mapped to CW/CCW by [A-02]. |
| Index (Z) | Optional pulse marking one reference position per revolution. |
| Index cycle | The four positions `p_idx … p_idx+3` (forward), repeated every 4 × `cycles_per_rev` edges, where `p_idx` is the configured index position (§6). |
| Index state | The state in which the index pulse starts (§6, A-10); independent of the zero state. |
| `cycles_per_rev` | Number of cycles per mechanical revolution. Defines the edge angle and the index spacing. |
| Edge angle | Shaft rotation between two edges = 360° / (4 × `cycles_per_rev`), e.g. 4.5° at 20 cycles per revolution. |
| Angle | Mechanical shaft angle in degrees, tracked with sub-edge precision (§4.6). |
| Move | A movement of fixed length (edges, angle, or to a state) that ends by itself (§4.6). |
| Move to state | A move to the centre of the *n*-th following state with a given A/B state (A-27). |
| Centre state | Placing the shaft at the centre of the state it is in, in zero time (A-28). |
| Rotation | A continuous movement without a fixed length. It turns until it is stopped, and its speed and direction can be changed while it turns (§4.7). |
| Bounce | Short spurious toggles of a mechanical contact around a transition. |
| Edge offset | Fixed angular displacement of one kind of edge from its ideal position, in electrical degrees, caused by the device (e.g. a misaligned sensor) (A-25). |
| Stuck channel | An output that holds a fixed level regardless of the shaft, e.g. a dead sensor or a broken wire (A-26). |
| Set angle | Placing the shaft at an absolute angle in zero time; the state changes directly from the old to the new state (A-12). |
| Jump | Moving the shaft by N edges in zero time; the state changes directly from the old to the new state (A-12). |

### 2.1 Datasheet translation

The table maps each term of this spec to the datasheet terms that may express it. The spec terms are defined exactly (§2); the datasheet terms are not: vendors use the same word for different quantities (e.g. PPR and CPR differ by a factor of 4 between vendors), so one datasheet term can appear in several rows. Use the definition in the second column to decide which spec term a datasheet number is, not the word.

| Spec term | Definition (how to recognise it) | Datasheet terms that may mean it |
|---|---|---|
| `cycles_per_rev` | Number of rising edges of A per revolution | lines, line count, signal periods, pulses per 360°, PPR, CPR ("cycles per revolution"), resolution, ×1 counts |
| Edges per revolution (= 4 × `cycles_per_rev`) | Number of transitions on A and B together per revolution | counts per revolution, CPR ("counts per revolution"), PPR, quadrature counts, ×4 counts, resolution |
| Edge angle (= 360° / edges per revolution) | Shaft rotation between two edges | resolution (in °), angular resolution, step angle |
| Speed (rpm) | Rotational speed of the shaft | speed, rotational speed, max. speed, rpm |
| Edge offset (A-25) | Fixed displacement of one kind of edge from its ideal position, the same at every occurrence (° electrical) | phase error, phase shift tolerance, state width error, symmetry error, duty-cycle error |
| Jitter amplitude (A-05) | Random displacement of an edge, different at every occurrence (° electrical) | edge jitter, cycle-to-cycle jitter, phase error |
| Index width (A-10) | Number of states during which Z is active (1–4) | index pulse width (90°/180°/270°/360° electrical, ¼ / ½ / 1 cycle, LSB), gated / ungated |
| Index state (A-10) | State of A/B in which the index pulse starts | index gating ("gated with A and B", "Z high while A = B = high") |

Example: a datasheet that gives "1024 PPR" and "4096 counts with ×4 decoding" has `cycles_per_rev` = 1024 (1024 rising edges of A) and 4096 edges per revolution. Datasheet quantities without a spec term (e.g. detents per revolution, §9) are not modelled.

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

- **[A-02]** *Forward* is defined as **A leading B** by 90° and is mapped to clockwise rotation (viewed from the shaft end). Manufacturers differ on this mapping. There is no option to swap the convention (Q-14): for a part whose clockwise rotation is "B leads A", A and B are swapped in the testbench wiring (the encoder's A output drives the DUT's B input and vice versa), so that the waveform of the encoder outputs stays the waveform of the model. Reverse moves give "B leads A" without any change.
- **[A-03]** Levels: every state in this specification (zero state, index state, move-to-state target, the sequences above) is the level on the output pins A and B, as seen in a waveform and on datasheets. There is no A/B polarity inversion option (Q-15): inverting both channels keeps the cycle order (`00→10→11→01` inverted is `11→01→00→10`, the same forward sequence), so its only effect would be a different state at angle 0°, which the zero state (A-06) already sets. A part whose contacts pull to ground ("closed" = `'0'`) is described by its zero state as seen on the pins.

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

- **[A-23]** Relation: `time_per_edge` = 60 s / (|rpm| × 4 × `cycles_per_rev`). In degrees per second: 1 rpm = 6 °/s. Example with 20 cycles per revolution: 60 rpm ↔ 12.5 ms per edge; 6000 rpm ↔ 125 µs.
- **[A-24]** Exactness: edge times are computed from the exact (real-valued) motion model. Only the absolute time of each edge is rounded to the simulator resolution; rounding errors do not add up within a move, nor within a rotation between two speed changes. Each edge therefore lies within one resolution step of its ideal time. When the speed is given as `time_per_edge` and `time_per_edge`/2 is representable, the edge times are exact. A move or speed change starts at the (already rounded) simulation time at which it takes effect.
- **[A-04]** Baseline motion model: within one move, within a rotation between two speed changes, and within one profile entry, the speed is constant, so all edges have the same nominal `time_per_edge` (ideal 90° phase). Speed curves (acceleration, deceleration) are built from consecutive moves with different speeds, from speed changes of a rotation, or from a speed profile (§4.7.1).
- **[A-05]** Phase error (non-ideal edge positions within a cycle) is modelled as optional, configurable **edge jitter** with an amplitude *j* in **electrical degrees**, as on datasheets. Each edge is displaced from its ideal time by a random offset of up to ± *j*/90 × `time_per_edge` (*j*/90 edge angles at the current speed). The offset only moves that edge; it does not carry over to the following edges. 0 ≤ *j* < half the width of the narrowest state, so two neighbouring edges can never swap their order. Without edge offsets (A-25) every state is 90° wide, so the limit is 45° electrical. The amplitude is independent of the speed.
- When no move and no rotation is active, the encoder is at standstill: A and B hold their last state indefinitely. There is no idle level other than the current state.

### 4.5 Device faults and fault events (for testing decoders)

To verify how a DUT decoder handles non-ideal or faulty encoders, the encoder side models two kinds of faults. Normal movements of an encoder without configured faults are always legal.

#### 4.5.1 Device faults (configuration)

A device fault is a property of the part. It is configured, stays active until it is configured off, and applies to every move and rotation.

- **[A-25] Edge offsets.** Each of the four edges of a cycle can be displaced from its ideal angle by a fixed offset in electrical degrees: the edge where A rises, where A falls, where B rises and where B falls, each named after its level change in the **forward** direction (in reverse, the same edge is the opposite level change at the same angle; there is no hysteresis). The level changes are those on the output pins (A-03).
  - Equal offsets on both edges of one channel shift that channel: phase error, e.g. a misaligned B sensor. Different offsets on the rising and falling edge of one channel change its duty cycle (symmetry error). Any combination gives the state-width error that datasheets specify.
  - Because the offsets are angles, the resulting edge-time displacement scales with the speed and is the same in both directions.
  - Each offset lies in the open interval (−45°, +45°) electrical. Every state is then still wider than 0° and still contains its ideal centre, so positions and the index (§6) are unchanged; only the edge angles move.
  - Z changes together with the A/B edge that enters or leaves the index state, so it follows the offsets.
- **[A-26] Stuck channels.** Each output (A, B, Z) can be configured as stuck at `'0'`, `'1'` or `'Z'` (high impedance, e.g. a broken wire with no pull resistor). A stuck output drives that level instead of the model's level; it does not bounce and ignores the index polarity (A-10). The model keeps running underneath: when the output is released, it returns to the level of the current state. The stuck level is an electrical level of the output pin.

#### 4.5.2 Fault events (on request)

- **[A-12]** On explicit request, the encoder produces:
  - a **set angle**: the shaft is placed at an absolute angle in degrees (any `real`, also outside one revolution) in zero time. It brings the encoder to a known angle, e.g. between test cases. It is not a power-up (§7): the start angle is not re-read.
  - a **jump** of N edges in a given direction from the angle at the time of the request, in zero time; the sub-edge fraction is kept.

  For both, the outputs change directly from the old to the new state, in one step, and Z takes the level of the new state without a pulse for skipped positions. What a decoder sees depends on the edge distance N between the old and the new position: N mod 4 = 2 is an illegal transition (A and B change at the same time); N mod 4 = 0 changes nothing on A/B but moves the position (lost cycles, as with missed samples at too high a speed); N mod 4 = 1 or 3 is one legal edge, which for N mod 4 = 3 points in the opposite direction. If the new angle lies exactly on a boundary, the shaft is in the state on the side of the old angle (it has not crossed the boundary).
  - a **glitch**: a pulse on A or B of configurable width, after which the output returns to its previous value. The position does not change.

  Edges that are too close for a decoder need no special request: they are an ordinary move with a high speed or a small `time_per_edge`.

### 4.6 Movement by angle

- **[A-13]** The encoder keeps the shaft angle with sub-edge precision. Each state covers one edge angle, and the state is a function of the angle alone (no hysteresis). Angle 0° is the **centre** of the zero state (A-06, default `AB = 11` on the pins, position 0), so the edges lie at ±½, ±1½, ±2½ … edge angles. Angle 0° is defined by the zero state alone, with or without an index: an encoder without Z (e.g. a mechanical knob) needs the same reference. The index is placed relative to 0° (§6). Position *p* is the state centred at *p* edge angles; its state is the one reached from the zero state after *p* forward edges (§4.1). An edge is emitted whenever the angle crosses one of these boundaries, in either direction. The edge is emitted when the angle *reaches* the boundary: a shaft that stands exactly on a boundary is in the state it moved into. A following movement in the opposite direction therefore emits its first edge at its start.
- Angle moves smaller than the edge angle accumulate. With an edge angle of 4.5°, starting at 0°, three moves of 1° produce one edge, during the third move, at the moment the 2.25° boundary is crossed.
- An **edge move** of N edges is an angle move of N edge angles. Starting from the centre of a state, its edges occur ½, 1½, … N−½ × `time_per_edge` after the move starts. The move ends in the centre of the new state, N × `time_per_edge` after it started. Back-to-back edge moves at the same speed therefore keep an edge spacing of `time_per_edge` (A-24), in both directions.
- The angle is not rounded between moves, so a sequence of moves that adds up to one revolution produces exactly 4 × `cycles_per_rev` edges.
- An angle move turns at constant speed, given in rpm or as `time_per_edge`, the same as for edge moves. A move of angle φ takes φ / edge angle × `time_per_edge` (= φ / (6 × rpm) seconds), also when no edge is crossed.
- Edge moves change the angle by whole edge angles and keep the sub-edge fraction. Edge and angle moves can be mixed.
- Every move ends exactly at its target angle; there is no correction movement afterwards.
- **[A-27] Move to state.** A move to state turns the shaft in a given direction to the **centre** of the *n*-th following state (*n* ≥ 1) that equals a given target state (A/B levels on the pins, like every state, A-03). The state the shaft is in when the move starts is **never counted**, whatever its sub-edge position and even if it is the target state; counting starts with the next state in the move direction. The result therefore changes only where the state changes (at a boundary, A-13), never inside a state. The move is an angle move to that centre (constant speed, rpm or `time_per_edge`, timing as above) and ends exactly there. It is resolved from the angle at the moment the move starts.
  - Example (4.5° per edge, zero state `11`; positions 0 to 3 are `11`, `01`, `00`, `10`, so the `00` centres lie at 9° + *k* × 18°): forward to `00`, *n* = 1: from 0° or from 1° to 9° (2 edges, at 2.25° and 6.75°); from 10° (already in `00`) to 27°. Forward to `00`, *n* = 2, from 0°: 27°. Reverse to `00`, *n* = 1, from 0°: −9°.
  - One click of a knob with one detent per cycle at state `00` is a move to state `00` with *n* = 1 (detents are not modelled, §9).
- **[A-28] Centre state.** On request, the shaft is placed at the centre of the state it is in, in zero time. The centre is the ideal one (*p* edge angles, A-13); it always lies inside the state, also with edge offsets (A-25). No boundary is crossed, so no edge, bounce, jitter or Z change occurs; only the angle changes. A shaft already on the centre is unchanged. On a boundary, the state is the one the shaft moved into (A-13). Example: at 10° (state `00`, position 2) the shaft is placed at 9°.

### 4.7 Continuous rotation

A rotation models a shaft that keeps turning, e.g. a motor with an encoder, while the test does other things. It uses the same angle model as moves (A-13): the angle changes at constant speed between speed changes, and an edge is emitted at each crossing of an edge boundary.

- **[A-17] Start.** A rotation starts at the current angle with a given speed: a signed rpm value, or a `time_per_edge` with a direction. It turns until it is stopped; it has no length. 0 rpm is legal: the rotation is active but the shaft stands still. Starting from the centre of a state, the edges occur ½, 1½, 2½ … × `time_per_edge` after the start, as for an edge move. Starting with a sub-edge fraction (e.g. after an angle move), the first edge comes when the next boundary is reached.
- **[A-18] Speed and direction change.** While a rotation turns, its speed (and with it the direction, by the sign) can be changed. The change takes effect **at once**, at the current angle; there is no wait for the next edge or state centre. The rest of the current edge angle is covered at the new speed. A direction change reverses from the current angle, so the next edge is the boundary that was crossed last if the change comes before the next boundary is reached (no hysteresis, A-13). Any time between two edges is legal, so a change shortly after an edge produces a short state; this is physical behaviour, not a glitch.
- **[A-19] Stop.** A stop ends the rotation at once, at the current angle. The shaft stays at the reached angle, including its sub-edge fraction; no edges follow.
- **[A-20] Exclusivity.** While a rotation is active (also at 0 rpm), the shaft has no other motion: moves (§4.6, including move to state A-27), centre state (A-28) and fault events (§4.5.2) are not available until the rotation is stopped. A second start while a rotation is active is not a restart; the speed is changed with A-18.
- The angle is not rounded at speed changes, so the angle model stays free of rounding drift (§4.6, A-24) except for the quantisation of the change time to the simulator resolution.
- Index (§6), bounce (§5), jitter (A-05), index polarity (A-10) and device faults (§4.5.1) apply to rotations exactly as to moves.

#### 4.7.1 Speed profile

A speed profile describes a speed that changes over time, e.g. a motor that starts up under a heavy load. It is available for rotations only, not for moves.

- **[A-21] Profile.** A rotation start or a speed change can give a profile instead of a single speed: an ordered list of signed rpm values (entries) and a duration `time_per_entry` > 0. Time 0 is the moment the profile takes effect (A-17, A-18). Entry *j* (counted from 0) is the speed from *j* × `time_per_entry` to (*j* + 1) × `time_per_entry`; within an entry the speed is constant (A-04), and each entry boundary is a speed change as A-18. Entries may be 0 rpm and may change sign (reversal).
- **End of the profile** (chosen per call):
  - *hold*: the rotation continues at the last entry's speed;
  - *stop*: at the end of the last entry, the rotation stops as with A-19;
  - *repeat*: the profile starts again with entry 0 (e.g. a periodic load).
- A later speed change, with or without a profile, replaces the running profile (A-18).
- Jitter (A-05) and bounce (§5) are applied on top of the profile.
- **[A-22] Linear ramp.** A speed that changes linearly in rpm from a start to an end value is described by a profile of N entries with equal `time_per_entry`; it approximates constant acceleration as a staircase.

## 5. Contact bounce (mechanical encoders)

Mechanical encoders use sliding contacts. When a channel changes, it may toggle several times before settling.

- Bounce affects only the channel that is changing at that edge (the other one stays stable), so bounce looks like a legal back-and-forth movement on one channel (e.g. `10 ↔ 11`). It never produces an illegal transition by itself.
- **[A-07]** Bounce model: after the nominal edge, the changing channel toggles a configurable number of extra times (an even number of toggles, so it ends at the new value) within a bounce window `t_bounce` (a time: it is a property of the contact, not of the speed). Datasheets give bounce as a maximum time at a stated test speed, e.g. 5 ms max at 15 rpm (Bourns PEC11R); they do not give the number of bounce pulses. If the next edge comes before the window has ended (high speed, or a speed change during the window), the bounce is cut off: the channel is at its settled value before the next edge, and the remaining toggles are dropped.
- **[A-08]** The positions of the bounce toggles inside the window may be uniformly random (seeded, reproducible) or evenly spaced.

## 6. Index pulse (optical / magnetic encoders)

- Z produces one pulse per revolution, i.e. once every `cycles_per_rev` cycles, at the same mechanical position in both directions.
- **[A-10]** The index is configured by its position, its state and its width. The **index position** `p_idx` (any integer, in edges relative to position 0, i.e. angle 0°) selects the **index cycle**: the four positions `p_idx`, `p_idx+1`, `p_idx+2`, `p_idx+3` (forward), repeated every 4 × `cycles_per_rev` edges. The **index state** is independent of the zero state. Like every state it is given as the A/B levels on the pins (A-03), which are the levels datasheets show (e.g. "Z gated with A = B = high"), so a datasheet figure can be copied as drawn. The **index width** is 1, 2, 3 or 4 states; Z is active at:

- the one position in the index cycle whose state is the index state, and
- the next width − 1 positions forward, whose states follow the index state in the order `00 → 10 → 11 → 01`. They may lie outside the index cycle.

| Index width | Electrical | Typical datasheet wording |
|---|---|---|
| 1 state | 90° | "gated with A and B", "¼ cycle" |
| 2 states | 180° | "gated with A" or "gated with B", "½ cycle" |
| 3 states | 270° | "3 LSB" (e.g. AS5047P in ABI mode) |
| 4 states | 360° | "ungated", "1 cycle" (Z edges aligned with A/B edges) |

  Z is active high or active low, depending on the part; it only sets the level of Z, not where Z is active. Z follows the position, so it is active at the same shaft angle in both directions.
- With zero state `11`, index state `11` and `p_idx` = 0, the index (width 1) is centred at 0°. If the zero state and the index state differ, the index lies inside the index cycle, away from 0°.
- Example (AMT11-style datasheet figure: Z high while A = B = low, about one state wide; `cycles_per_rev` = 20, so 4.5° per edge; index width 1, index state `00`, `p_idx` = 0):
  - zero state `00`: the index cycle is `00` (0°), `10` (4.5°), `11` (9°), `01` (13.5°); Z is centred at 0°, the natural choice for a part without detents;
  - zero state `11`: the index cycle is `11` (0°), `01` (4.5°), `00` (9°), `10` (13.5°); Z is centred at 9° (position 2). The waveform is the same, only the angle reference differs.
  - On such a part A leads B for counter-clockwise rotation. If the DUT must count clockwise as positive, A and B are swapped in the testbench wiring (A-02). The index state refers to the encoder outputs, before that wiring: `00` and `11` are unaffected, an index state `10` or `01` read from the DUT side has its bits exchanged.
- Example (index width 2, index state `00`, zero state `00`, `p_idx` = 0): Z covers the states `00` and `10` at positions 0 and 1, so it is active while B is low, in both directions of rotation.
- Z is optional (§3): a part without an index has no Z output.

## 7. Initial state and reset

- An encoder has no reset input. When it is powered, the shaft can be at any angle.
- **[A-16]** The start angle is the position of the knob or motor shaft when the simulation starts; it can be any `real` value. The start state, position and Z level follow from it. They are not configured separately: the state is the one whose centre is nearest to the start angle (A-13), and Z is the level that the index configuration gives for that position. This is power-up, not movement, so no edges are emitted.
- Example (4.5°/edge, zero state `11`, index width 1 at `11`, `p_idx` = 0): start angle 0° gives `AB = 11` with Z active. Start angle 30° gives position 7 (the state centred at 31.5°), Z inactive.
- *(Informative)* A decoder that starts observing samples the current state as its reference. It does not count the initial state as an edge.

## 8. Expected decoder behaviour (informative)

*Informative.* These rules describe what a correct decoder infers from the signals. They describe the receiving side and explain what the faults of §4.5 provoke in a decoder.

- **[A-11]** The receiver tracks the position in edges: each legal forward edge increments the position by one, each legal reverse edge decrements it by one. Positions in cycles are derived from it.
- An illegal transition (Section 4.3) is reported as an error. The position is not changed.
- A pulse on A or B shorter than the decoder's minimum resolvable edge spacing is a glitch (§4.3). The limit is a decoder property.
- `'X'`, `'U'`, `'Z'`, `'W'`, `'-'` on any signal is an error.
- An index pulse is checked against its expected state and width (Section 6), when index is enabled.

## 9. Out of scope

| Item | Reason |
|---|---|
| Absolute encoders (SSI, BiSS, EnDat, Hiperface) | Serial protocols, different VIP |
| Analog sin/cos encoders | Analog signals |
| Differential electrical layer (RS-422 A+/A−) | Electrical; the logic level is the same as single-ended A/B |
| Hall-sensor commutation outputs (U/V/W) | Different 3-phase sequence |
| Step/direction and CW/CCW pulse interfaces | Different interface (may be a future extension) |
| Detents (mechanical rest positions, `edges_per_detent`, snapping to a detent) | Q-09: too complex for the benefit. A click of a detented knob is an edge move of the part's edges per detent (§2.1); the test places the shaft with moves and set angle |
| True ungated index with Z edges not aligned to A/B edges (e.g. separate index track, arbitrary phase and width) | Q-12: the index width covers 1 to 4 whole states (§6). If needed later, it can be added as two Z edge offsets in electrical degrees, analogous to A-25 |
| Physical modelling (inertia, load, friction) | Speed curves are given by the user as moves, rotation speed changes or speed profiles (§4.7.1). The model does not compute them from torque or inertia |
| Continuous speed curves within a profile entry (e.g. linear interpolation) | The speed is constant within an entry (A-04); finer curves use shorter `time_per_entry` |
| Speed profiles for moves | Q-06: rotations only |
| Open-drain / pull-up signal resolution (`'0'`/`'Z'` with external `'H'`) | Q-04: not needed |
| A/B polarity inversion option | Q-15: no visible effect when every state is given on the pins; the zero state sets which state is at 0° (A-03, A-06) |
| Direction swap option (A and B exchanged inside the model) | Q-14: no extra stimulus; it makes the output pins differ from the logical channels. A and B are swapped in the testbench wiring instead (A-02) |
| Push-button switch (SW) | Independent of A/B. It is driven by a GPIO VVC in the testbench (Q-01) |

## 10. Assumptions

| ID | Assumption |
|---|---|
| A-01 | Push-pull strong `'0'`/`'1'` logic levels |
| A-02 | Forward = A leads B = CW; other conventions by swapping A and B in the testbench wiring |
| A-03 | All states are A/B levels on the output pins; no A/B polarity inversion |
| A-04 | Constant speed within a move, a rotation segment and a profile entry; speed curves from several of them |
| A-05 | Phase error as optional edge jitter, amplitude *j* in electrical degrees, 0 ≤ *j* < half the narrowest state (45° without offsets), displaces single edges without carry-over |
| A-06 | Zero state: the state at angle 0° (position 0), A/B levels on the pins; manufacturers differ |
| A-07 | Bounce: N extra toggles of the changing channel within `t_bounce`; cut off at the next edge |
| A-08 | Bounce toggle placement random (seeded) or even |
| A-10 | Index width 1–4 states, starting at the index state; index position `p_idx` selects the index cycle (`p_idx … p_idx+3`); index state independent of the zero state; further states follow the index state in the order `00 → 10 → 11 → 01`, may lie outside the index cycle |
| A-11 | *(Informative, §8)* A decoder tracks position in edges; cycles derived |
| A-12 | Fault events on request, in zero time: set angle (absolute) and jump (N edges relative; illegal transition for N mod 4 = 2); glitch |
| A-13 | Movement by angle with sub-edge angle tracking, no rounding drift; angle 0° is the centre of the zero state (A-06), independent of the index; a shaft exactly on a boundary is in the state it moved into |
| A-16 | Start angle (position of the knob/motor at simulation start); start state, position and Z follow from it, without edges |
| A-17 | Continuous rotation: starts at the current angle with a signed rpm (or `time_per_edge` and direction), turns until stopped; 0 rpm legal |
| A-18 | Rotation speed and direction changes take effect at once, at the current angle |
| A-19 | Rotation stop takes effect at once and keeps the reached angle |
| A-20 | No moves, centre state or fault events while a rotation is active; a second start is not a restart |
| A-21 | Rotation speed profile over time: signed rpm entries, `time_per_entry`, end behaviour hold / stop / repeat chosen per call |
| A-22 | Linear ramp: rpm linear over the entries of a profile |
| A-23 | Speed in rpm (primary) or `time_per_edge` (alternative); `time_per_edge` = 60 s / (\|rpm\| × 4 × `cycles_per_rev`) |
| A-24 | Edge times from the exact model, each rounded once; no accumulated rounding within a move or rotation segment |
| A-25 | Device fault: fixed edge offsets per channel and edge in electrical degrees, each in (−45°, +45°), named by the level change on the pins |
| A-26 | Device fault: A, B or Z stuck at `'0'`, `'1'` or `'Z'` on the output pin |
| A-27 | Move to state: centre of the *n*-th state (*n* ≥ 1) with a given state in a given direction; the current state is never counted; resolved when the move starts |
| A-28 | Centre state: to the centre of the current state in zero time, no edge |

## 11. Resolved questions

| ID | Question | Answer |
|---|---|---|
| Q-01 | Push-button switch in scope? | No, it is handled by a GPIO VVC (2026-10-21) |
| Q-02 | Edge-time jitter / phase error needed? | Yes, as an optional feature ([A-05]) (2026-10-21) |
| Q-03 | Generate errors, or only detect them? | Both: generation is [A-12], detection is Section 8 (2026-10-21) |
| Q-04 | Open-drain mode needed? | No, it is out of scope (2026-10-21) |
| Q-05 | Continuous rotation (start at a speed, change it, stop) needed? | Yes, new §4.7 ([A-17] to [A-20]) (2026-10-27) |
| Q-06 | Non-constant speed (e.g. motor start-up under load)? | Yes, as a speed profile for rotations only, with end behaviour per call and a linear ramp (§4.7.1, [A-21], [A-22]) (2026-10-27) |
| Q-07 | `time_per_edge` as the speed unit is abstract: the real speed depends on `cycles_per_rev`. | Speed in rpm, signed for rotations; `time_per_edge` kept as an alternative form for exact edge spacing; profiles over time (§4.4, [A-23], [A-24], §4.7.1) (2026-10-27) |
| Q-08 | One fixed illegal-transition request covers one symptom only; how are device faults such as a misaligned sensor modelled? | Device faults by configuration (edge offsets A-25, stuck channels A-26), fault events by request (set angle and jump replace the illegal transition; glitch kept) (§4.5) (2026-10-27) |
| Q-09 | Detents and snapping make the model and its API too complex (seen in Stage 5.3 Increment 1). Keep them? | No, removed completely in rev 0.7; detents are out of scope (§9). The zero state at 0° stays configurable (A-06, manufacturers differ) and the start angle stays (A-16) (2026-10-28) |
| Q-10 | What counts as 0°: the zero state or the index state? How is the index cycle located when they differ? | 0° is the centre of the zero state, with or without an index (A-13). The index position selects the index cycle `p_idx … p_idx+3`; the index state is independent of the zero state; gated ½ may extend past the index cycle. Checked against an AMT11-style figure (Z at `00`) (§6, A-10) (2026-11-09) |
| Q-12 | Are there index widths other than ¼, ½ and 1 cycle (e.g. ¾)? | Yes (e.g. AS5047P "3 LSB" = 3 states). The index mode is replaced by an index width of 1 to 4 states, starting at the index state and following the pin order `00 → 10 → 11 → 01`. True ungated Z with free edges is out of scope (§9) (§6, A-10) (2026-11-09) |
| Q-13 | Moving to a given state needs the current state, which a queued VVC command cannot know; after a rotation the shaft is usually off-centre. Add commands? | Yes: move to state (A-27), current state never counted, so the result changes only at a boundary and not with tiny differences of a stop angle; centre state (A-28) in zero time. Target state given as pin levels like the index state (2026-11-09) |
| Q-14 | Is a direction swap option needed, given that it can be done in the wiring and makes the waveform differ from the logical channels? | No, removed in rev 0.9. A and B are swapped in the testbench wiring for a "B leads A" part; reverse moves give "B leads A" directly. All states (zero, index, target) are A/B levels on the pins (2026-11-09) |
| Q-15 | With every state given as A/B levels, does an A/B polarity inversion option still have an effect? | No: inverting both channels keeps the forward order and only shifts which state is at 0°, which the zero state already sets. Removed in rev 0.10; all states are levels on the pins. Z polarity stays (2026-11-09) |
