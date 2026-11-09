# Rotary Encoder VVC – Architecture

| Item | Value |
|---|---|
| Document | `p2l2_vip_rotary_encoder/doc/rotary_encoder_vvc_arch.md` |
| Revision | 0.5 |
| Status | **Approved 2026-10-27** (Phase 3 – VVC architecture) |
| Sources | `rotary_encoder_spec.md` rev 0.6, `rotary_encoder_vvc_reqs.md` rev 0.4 (both approved 2026-10-27) |
| Role | Encoder only (drives A/B/Z into a DUT) |

Decisions are marked **AD-n** and collected in Section 14. The user accepted all recommendations on 2026-10-27 ("accept all").

## Revision history

| Rev | Date | Change |
|---|---|---|
| 0.1 | 2026-10-27 | Initial proposal |
| 0.2 | 2026-10-27 | User decisions: low-level motion engine stays public, documented "used by the VVC" (AD-15, DV-3); timed BFM rotation kept (AD-16). Fault model reworked (AD-17, spec rev 0.6): device faults by configuration (edge offsets §6.2, stuck outputs §6.3), `rotary_encoder_jump` replaces `rotary_encoder_illegal_transition`, glitch kept. Boundary rule AD-7 added to spec A-13 (Q-3) |
| 0.3 | 2026-10-27 | User request: `rotary_encoder_jump` renamed and generalized to `rotary_encoder_set_angle` (absolute in degrees, or relative in edges), also for bringing the encoder to a known angle (AD-14, AD-17, D-30) |
| 0.4 | 2026-10-27 | User decisions: `rotary_encoder_set_angle` gets `use_detent` (default false); the relative form is `rotary_encoder_jump_edges`. Q-1 (copyright UVVM), Q-2 (bounce defaults) and Q-4 (D-26 to D-30) answered. All AD accepted; approved 2026-10-27 |
| 0.5 | 2026-10-27 | §6.2: exact `tpe_int`/`tpe_frac` for an integer rpm divisor (F-010, Stage 5.3 Inc 1). Proposed |

---

## 1. Use cases (answered 2026-10-27)

| ID | Use case | Consequence |
|---|---|---|
| U-1 | Stimulate a DUT decoder with discrete moves (edges, detents, angle) **and** with continuous rotation, optionally with time-based speed profiles | Moves are blocking commands. A rotation runs in the background while the executor stays free for speed changes, stop and other commands |
| U-2 | Read back the encoder state, if it adds little complexity | Included: one queued command plus `fetch_result()`, reusing the framework's result queue (AD-12) |
| U-3 | One encoder per DUT; several instances must still run independently (REQ-083) | One channel, one instance per encoder, standard `GC_INSTANCE_IDX` |
| U-4 | Structural references `bitvis_vip_clock_generator` and `p2l2_vip_pwm`; all official VVCs as convention reference | Section 2 |

## 2. References

### 2.1 Structural references

| VIP | Where | Used for |
|---|---|---|
| `p2l2_vip_pwm` (branch `p2l2_vip_pwm`, commit `bb4b0c91`) | Primary | File layout (BFM, `transaction_pkg`, `vvc_cmd_pkg`, `vvc_methods_pkg`, `vvc_context`, VVC entity), the separate waveform process that keeps the executor free during continuous operation (`start_req`/`update_req`/`stop_req`/`abort_req` with index acknowledges), `GC_<NAME>_BFM_CONFIG` driven from time 0, transaction info, `insert_delay` without clock, BFM overloads with an abort signal, scripts and `test.py`, integration commit as precedent |
| `bitvis_vip_clock_generator` | Secondary | Official precedent for a free-running background process next to the executor (`p_clock_generator`), start/stop/set-parameter command naming, a clock-less signal-level VVC |
| `bitvis_vip_gpio` | Optional | Precedent for a queued "get" command with `fetch_result()` (`gpio_get`) – the pattern for U-2 |
| `bitvis_vip_spi` | Convention only | Interface record type with `init_<name>_if_signals()` for a multi-signal port |

### 2.2 Convention profile (survey over all 23 VVC entities and 13 BFM packages in the checkout)

| Topic | Majority convention | Applied here |
|---|---|---|
| File header | UVVM Apache-2.0 banner, `Copyright 2024 UVVM` (13 BFMs); PWM `Copyright 2026 UVVM` | UVVM banner, `Copyright 2026 UVVM` (AD-3) |
| BFM config record | `t_<name>_bfm_config`, constant `C_<NAME>_BFM_CONFIG_DEFAULT`, fields `id_for_bfm` (26×), `id_for_bfm_wait` (16×) | `t_rotary_encoder_bfm_config`, both message-ID fields |
| BFM scope | `C_BFM_SCOPE : string := "<NAME> BFM"` (spaces 9×, underscores 4×) | `"ROTARY ENCODER BFM"` |
| BFM parameter order | operation parameters, (output variables), `msg`, signal(s), `scope`, `msg_id_panel`, `config` | Same; the inout `state` variable comes before `msg` (as PWM's seeds and SBI's `data_value`) |
| VVC method parameter order | `VVCT`, `vvc_instance_idx`, parameters, `msg`, `scope`, `parent_msg_id_panel` | Same |
| Multi-signal port | Record type `t_<name>_if` + `init_<name>_if_signals()`, `inout` port `<name>_vvc_if` (10 BFMs) | `t_rotary_encoder_if`, port `rotary_encoder_vvc_if` |
| VVC generics | `GC_INSTANCE_IDX`, the six queue generics (23×), BFM config as `GC_<NAME>_BFM_CONFIG` (RGMII, GMII, Wishbone, PWM) or `GC_<NAME>_CONFIG` (UART, SPI, SBI) | `GC_ROTARY_ENCODER_BFM_CONFIG` (PWM precedent) |
| Per-VIP size constants | `C_<NAME>_VVC_CMD_STRING_MAX_LENGTH`, `C_<NAME>_VVC_MAX_INSTANCE_NUM` in `adaptations_pkg`, aliased in `transaction_pkg` | Same, plus `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` (AD-10, like `C_RGMII_VVC_CMD_DATA_MAX_BYTES`) |
| `t_vvc_config` | Standard fields; VVC-level extras are common (`unwanted_activity_severity` 14×, `clock_period` in clock_generator) | One extra field `stop_when_idle_severity` (REQ-106) |
| `t_vvc_status` | Never extended (0 of 23) | Not extended; U-2 uses `fetch_result()` |
| Type names | Prefixed with the VIP name; the framework already declares `t_direction` | Every public type is `t_rotary_encoder_*` |
| Helper visibility | Some official BFMs declare helpers publicly (e.g. `odd_parity` in UART) | **Deviation DV-1**: helpers are body-only (Section 12) |

## 3. Naming and identity

| Item | Proposal | Reason |
|---|---|---|
| VVC name given to the generator (AD-1) | `rotary_encoder` → `rotary_encoder_vvc`, `rotary_encoder_bfm_pkg`, `ROTARY_ENCODER_VVCT`, `C_VVC_NAME = "ROTARY_ENCODER_VVC"` | The spec's own name; unambiguous. Alternatives: `quadrature_encoder` (more precise, longer), `encoder` (ambiguous: 8b/10b, line encoders) |
| Library and directory (AD-2) | `p2l2_vip_rotary_encoder` (directory already exists) | Same prefix as `p2l2_vip_pwm` and `p2l2_vip_mdio`. Not `bitvis_` (reads as official UVVM) and not `external_vip_` (used for contributed VIPs merged upstream). The generator writes `library vip_rotary_encoder;` into `vvc_context.vhd`; it is replaced in Stage 5.1 |
| File header (AD-3) | UVVM Apache-2.0 banner as in `p2l2_vip_pwm`, `Copyright 2026 UVVM`, plus `LICENSE.TXT` copied from PWM | Same as the PWM precedent. Please confirm the copyright holder; if it should be someone else, it changes every file header |
| Procedure prefix | `rotary_encoder_` for every BFM procedure and VVC method | UVVM convention: BFM procedure and VVC method share the name |

### 3.1 Protocol term mapping

| Spec term (§) | Meaning | VHDL identifier | Where |
|---|---|---|---|
| A, B, Z (§3) | Quadrature channels and index | record fields `a`, `b`, `z` of `t_rotary_encoder_if` | Port, BFM signal |
| State `AB` (§2) | 2-bit value of the channels | `std_logic_vector(1 downto 0)`, bit 1 = A, bit 0 = B; fields `rest_state`, `index_state`, result field `ab` | Config, result |
| Edge (§2) | One transition on A or B | `edge`: `num_edges`, `rotary_encoder_move_edges` | BFM, VVC |
| Detent (§2, §5.1) | Mechanical rest position | `detent`: `num_detents`, `edges_per_detent`, `detents_enabled` | BFM, VVC, config |
| `cycles_per_rev` (§2) | Cycles per revolution | `cycles_per_rev` | Config, conversions |
| Angle (§4.6) | Shaft angle in degrees | `angle : real` | BFM, VVC, result |
| Speed (§4.4) | rpm, signed for rotations | `rpm : real` | BFM, VVC, result |
| `time_per_edge` (§4.4) | Edge interval | `time_per_edge : time` | BFM, VVC |
| Forward / reverse (§4.1) | Direction | `t_rotary_encoder_direction` = (`FORWARD`, `REVERSE`) | BFM, VVC |
| Direction swap (A-02) | A/B exchanged | `direction_swap : boolean` | Config |
| Polarity inversion (A-03, A-10) | Inverted electrical level | `ab_inverted`, `index_inverted : boolean` | Config |
| Index mode (A-10) | ¼, ½, 1 cycle | `t_rotary_encoder_index_mode` = (`INDEX_GATED_QUARTER`, `INDEX_GATED_HALF`, `INDEX_UNGATED`) | Config |
| Index position (§6) | Index cycle, in edges from position 0 | `index_position : integer` | Config |
| Bounce, `t_bounce` (§5.2) | Contact bounce, window | `bounce_enabled`, `bounce_pulses`, `bounce_window`, `bounce_placement` | Config |
| Jitter *j* (A-05) | Phase error in electrical degrees | `jitter : real` (0.0 = off) | Config |
| Set angle, jump, glitch (A-12) | Fault events; set angle also for a known angle | `rotary_encoder_set_angle` (`use_detent`), `rotary_encoder_jump_edges`, `rotary_encoder_glitch`; channel type `t_rotary_encoder_channel` = (`CHANNEL_A`, `CHANNEL_B`) | BFM, VVC |
| Edge offset (A-25) | Device fault: displaced edge, electrical degrees | `a_rise_offset`, `a_fall_offset`, `b_rise_offset`, `b_fall_offset : real` | Config |
| Stuck channel (A-26) | Device fault: output held at a level | `a_stuck`, `b_stuck`, `z_stuck : std_logic` (`'-'` = not stuck) | Config |
| Rotation (§4.7) | Continuous movement | `rotary_encoder_start_rotation`, `rotary_encoder_set_speed`, `rotary_encoder_stop_rotation` | VVC |
| Profile, `time_per_entry`, end behaviour (A-21) | Speed over time | `profile : real_vector`, `time_per_entry : time`, `t_rotary_encoder_profile_end` = (`PROFILE_HOLD`, `PROFILE_STOP`, `PROFILE_REPEAT`) | BFM, VVC |
| Snap speed (A-19) | Speed of the detent snap after a stop | `default_snap_rpm : real` | Config |
| Start angle (A-16) | Power-up angle | `start_angle : real` | Config |

Reserved-word check: none of the identifiers is a VHDL or VHDL-AMS reserved word. `STOP` is avoided as an enumeration literal (it would hide `std.env.stop`), hence `PROFILE_STOP` and `ROTATION_STOP`.

## 4. Feature configuration

| Feature | Proposal | Reason |
|---|---|---|
| Channels | One channel (`NA`) | One encoder per instance (U-3); A/B/Z are one interface |
| Executors | One command executor (generator: no multiple executors) **plus** a hand-written process `p_motion` | `p_motion` is the only driver of the port. The executor stays free while a rotation runs (PWM `p_waveform` precedent, clock_generator `p_clock_generator`) |
| BFM | Full BFM usable without the VVC (REQ-080): init, moves, timed rotation, fault events, status, conversions, ramp; device faults through the configuration | Section 6 |
| Commands | Queued: moves, rotation start/speed change/stop, fault events (set angle, jump, glitch), status read; standard UVVM commands | Section 7 |
| Results | `rotary_encoder_get_status` stores a `t_rotary_encoder_status` in the result queue for `fetch_result()` | U-2 (AD-12) |
| Transaction Info | **Included** | Cheap, conventional, used by PWM. Base transaction only (no sub/compound transactions) |
| Scoreboard | **Excluded** | Encoder only; the VVC receives no data to compare |
| Unwanted Activity Detection | **Excluded** | No DUT outputs are observed |
| Monitor / checker | **Excluded** from the VIP | The checker that verifies the encoder is part of the maintenance testbench (Phase 4) |
| `insert_delay` with clock cycles | `TB_ERROR` (no clock) | PWM precedent |
| Inter-BFM delay | Applies to moves and fault events; rotation commands are not delayed | They act on a running rotation (PWM precedent) |

## 5. Physical interface and entity

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

- No clock and no reset port: the encoder is asynchronous and has no reset input (spec §3, §7). The generator's `clk` port is removed in Stage 5.1.
- `inout` with `'Z'` initial values follows the official record-port VIPs. From the first delta, `p_motion` drives strong `'0'`/`'1'` on all three fields (A-01). With index disabled, Z is driven at its inactive level, not `'Z'` (REQ-040).
- `GC_INSTANCE_IDX` gets the default 1 (generator pitfall: it has none).
- **Start state (AD-14).** At time 0, `p_motion` initializes the encoder from `GC_ROTARY_ENCODER_BFM_CONFIG` (`start_angle`, `rest_state`, detents, index), because `shared_rotary_encoder_vvc_config` is not set up yet at time 0 (PWM precedent). Changing `start_angle` in the shared configuration later has no effect; it is a power-up property. Tests with several start angles use several instances or the BFM directly (Phase 4).

## 6. BFM (`rotary_encoder_bfm_pkg`)

### 6.1 Angle model and state (AD-5)

The BFM keeps the shaft in a public state record that the caller owns (`variable state : inout t_rotary_encoder_state`). The angle cannot be reconstructed from the signals (sub-edge fraction, last speed), so a state variable is unavoidable; the VVC's copy lives in `p_motion`. Its fields are documented as private: users only declare it, pass it, and read it through `rotary_encoder_get_status()`.

- **Position:** `position : integer` – the edge index of the current state; state centre *p* lies at *p* edge angles. Range ±2³¹ edges (≥ 26 million revolutions at 20 cycles/rev).
- **Sub-edge offset:** `offset : integer` in quanta, −K/2 ≤ offset ≤ +K/2, with **K = 900 000 000 quanta per edge**.
- **Why K = 9·10⁸:** one degree is 4 × `cycles_per_rev` × K / 360 = `cycles_per_rev` × 10⁷ quanta, an integer for every `cycles_per_rev`. Every angle with up to 7 decimals (0.1°, 1°, 2.25°, 1.125°…) converts exactly, so sums of moves are exact integer arithmetic: 3600 × 0.1° = exactly one revolution (REQ-091). An angle with more decimals (e.g. 1/3°) is rounded once per move to the nearest quantum (≤ 5.6·10⁻¹⁰ edge angles per move; 10⁹ such moves would be needed to shift one edge by 1 % of an edge angle). The quantisation is noted in REQ-091 (Section 13).
- Long moves: the distance of one move is held as an integer-valued `real` (exact up to 2⁵³ quanta, i.e. 125 000 revolutions per move at 20 cycles/rev, 250 at 10 000 cycles/rev). Beyond that, `TB_ERROR`.
- **State mapping (AD-8):** the logical state at position *p* is the forward Gray sequence (`00→10→11→01`) started at the **reference state** `state(0)`. The reference state is `config.rest_state` at initialization (A-13: angle 0° is the centre of the rest state) and is kept in the state record. Later changes of `rest_state` move the detents (below) but never remap A/B, so they cannot cause a jump.
- **Boundaries with edge offsets (A-25):** the boundary between positions *p* and *p*+1 lies at (*p* + ½) edge angles plus the offset of that edge (A rise, A fall, B rise or B fall, identified by the logical level change in the forward direction from `state(p)` to `state(p+1)`), converted from electrical degrees to quanta (90° electrical = K). Each offset is in (−45°, +45°), so a boundary never passes a state centre: positions, detents, the index cycle and the end of every move (state centres) are unchanged; only the edge angles move (REQ-075, REQ-076). The offsets are latched with the geometry at the motion start (D-26).
- **Detents:** the detent positions are the positions whose logical state is a rest state of the *current* configuration: for `edges_per_detent` = 4 the states equal to `rest_state`, for 2 also the state two edges away, for 1 every state (spec §5.1 table). With the defaults this is *p* ≡ 0 (mod 4).
- **Boundary rule (AD-7, closes F-003, spec A-13 rev 0.6):** an edge is emitted when the angle *reaches* a boundary. A shaft that stands exactly on a boundary is in the state it moved into. This is the only rule that can be implemented deterministically: an edge due at time *t* is driven in the first delta cycle of *t*, before a stop, speed change or `terminate_current_command` issued at *t* can reach `p_motion`. Consequences: a move that ends exactly on a boundary emits that edge at its end; a following move in the same direction reaches the next boundary after a full edge angle (continuous, as one longer move); a following move in the opposite direction emits its first edge at its start, so two back-to-back commands give a state of zero length at that time step (two events on one channel at the same simulation time). This is the A-18 "short state" in its limit, not an illegal transition; the testbench checker accepts it.

### 6.2 Edge-time computation (AD-6, A-24)

- A **segment** is a stretch of constant speed: a move, a rotation between two speed changes, a profile entry, a snap. It is anchored at its start time `t0` (an exact `time`) and its start angle.
- The speed of a segment is held as `time_per_edge` split into a whole number of resolution units (`tpe_int : time`) and the fraction of a unit (`tpe_frac : real`, 0 ≤ `tpe_frac` < 1). In the time form `tpe_frac` = 0. In the rpm form both come from 60 s / (|rpm| × 4 × `cycles_per_rev`), split without converting large values to `integer` (pitfalls F-040, F-042). When |rpm| × 4 × `cycles_per_rev` is an integer (every integer rpm), `tpe_int` = 60 s / that integer and the remainder are computed exactly in `time` arithmetic and `tpe_frac` = remainder / divisor; otherwise both come from the `real` value. A `tpe_frac` taken from a `real` `time_per_edge` carries its rounding error, which `n × tpe_frac` multiplies (finding F-010).
- The time to reach a distance *d* quanta from the anchor is computed from scratch for every edge, with *d* = *n*·K + *r* (whole edges *n*, rest *r* < K):
  `t = t0 + n × tpe_int + round(n × tpe_frac + (r / K) × tpe_res)`, where `tpe_res` is `time_per_edge` in resolution units as `real`.
  The `time` part is exact; the `real` part stays small (< *n* + one edge interval), so every edge is within one resolution step of its ideal time and nothing accumulates (REQ-012, REQ-101). In the time form with an even number of resolution units per edge, the edges from a state centre are exact: (*k* − ½) × `time_per_edge`.
- When a segment ends between edges (speed change, stop, profile entry boundary, status request), the angle at that time is computed from the anchor and rounded once to a quantum. The next segment is anchored at the current simulation time. This is the only rounding at a speed change (spec §4.7: quantisation of the change time).
- Jitter (A-05): each emitted edge is moved by an offset drawn uniformly from ±`jitter`/90 × `time_per_edge` of the current segment (D-10, D-21), using the seeds in the state. The nominal time is not changed, so there is no carry-over. The jitter limit is half the narrowest state, i.e. 45° minus half the largest difference of adjacent offsets (REQ-063); then an edge can never be moved past the next one. The distance *d* to the next boundary includes its offset, so the timing formula above is unchanged.

### 6.3 Driving an edge

Each nominal edge (in a move, a rotation or a snap) does, at its (jittered) time:

1. Settle the channel that bounced at the previous edge if its bounce has not ended yet (cut-off, REQ-056): drive its settled value, cancel its remaining toggles (a `transport` assignment deletes later transactions), raise `config.bounce_cut_severity` once per command.
2. Drive the new logical state, mapped through `direction_swap` (A ↔ B) and `ab_inverted`; an output whose `*_stuck` is not `'-'` drives its stuck level instead (after the swap, without inversion; REQ-078). The stuck setting is also applied at the start of every command, so a release shows at the next command (D-29).
3. Drive Z from the nominal state (never bounces, D-4; follows the displaced edges, REQ-077), mapped through `index_inverted`, or `z_stuck`.
4. With bounce enabled and the changing output not stuck, schedule `2 × bounce_pulses` toggles of the changing channel within `bounce_window` as `transport` assignments (random placement from the state's seeds, or even spacing `bounce_window` / (2 × `bounce_pulses` + 1)), ending at the new value.

Swap and inversion are applied per edge from the configuration given to that edge (REQ-108). If a user changes `direction_swap` or `ab_inverted` while the shaft is not on a symmetric state, the next edge changes both lines at once. This is the requested reconfiguration, not a model error; it is documented and not alerted.

### 6.4 Index (AD-9)

- Index cycle: the 4 positions *q* … *q*+3, where *q* is the largest position ≤ `index_position` whose logical state is `index_state`, repeated every 4 × `cycles_per_rev` edges.
- Z active: gated ¼ at *q*; gated ½ at *q* and *q*+1 (D-2: the next state in the forward direction); ungated at *q* … *q*+3.
- Defaults (`index_position` 0, `index_state` 11 = reference state): *q* = 0, so Z is active in the reference state at 0° (spec §7 example). The definition makes every combination of `index_position` and `index_state` valid, and gated ½ always stays inside the cycle.

### 6.5 Motion engine (low-level public API)

All movement – moves, rotations, profiles, snaps – runs through one engine in the package body. It is exposed through three low-level procedures, because the VVC needs to interrupt and resume a motion (speed change, stop, status, terminate) and to re-read the configuration at every edge (REQ-108). The user-level procedures (6.6) are thin wrappers around the same engine, so BFM and VVC behave identically.

- `rotary_encoder_start_motion(motion, state, …)` – zero time. Validates the motion, latches the geometry (`cycles_per_rev`, `edges_per_detent`, `rest_state`, `detents_enabled`) into the state, and anchors the first segment at `now`. Replaces an active motion.
- `rotary_encoder_run_motion(state, event, …, interrupt, …)` – runs the active motion until the next nominal edge (`MOTION_EDGE`), the end of a profile pass (`MOTION_PROFILE_PASS`), the end of the motion (`MOTION_DONE`, the shaft is at rest), or an event on the `interrupt` signal (`MOTION_INTERRUPTED`). Returning never changes the motion: the next call continues the same segment from the same anchor, so returning at every edge costs no accuracy.
- `rotary_encoder_halt_motion(state)` – zero time. Ends the active motion at the current angle, without a snap (`terminate_current_command`, REQ-082/107).

**Documentation (AD-15, decided by the user):** the engine stays public. Every engine declaration carries the comment `-- Used by the VVC.` in the package, and the RST documentation lists the engine in its own section "Low-level motion engine (used by the VVC)" after the user-level procedures, with a note that testbenches normally use the user-level procedures or the VVC. The API-coverage check of Phase 6 treats them as public API.

`t_rotary_encoder_motion` is a public record that describes one motion (kind, direction, count, angle, speed form, rpm, `time_per_edge`, profile, `time_per_entry`, end behaviour). The profile is a fixed array of `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` entries plus a length (AD-10). The same record is a field of the VVC command record.

Motion kinds: `MOTION_EDGES`, `MOTION_DETENTS`, `MOTION_ANGLE` (with snap if detents are on), `MOTION_ROTATION` (constant speed or profile), `MOTION_STOP` (stop: snap to the nearest detent at the last non-zero speed, else `default_snap_rpm`; tie in the direction of the last non-zero speed; with detents off no motion at all).

The stop snap is the same computation as the snap after an angle move (0° angle move in the direction of the last speed), so A-14 and A-19 share one implementation.

### 6.6 User-level BFM procedures

| Procedure | Behaviour | Completes |
|---|---|---|
| `rotary_encoder_init` | Initializes the state from `config` (start angle placed on the nearest detent with detents on, A-16) and drives A/B/Z. No edges | At once |
| `rotary_encoder_move_edges` (rpm, time) | N edges, no snap (REQ-010…013, 027) | N × `time_per_edge` after the start |
| `rotary_encoder_move_detents` (rpm, time) | N × `edges_per_detent` edges; alert `off_detent_severity` if not started on a detent (REQ-020…024) | As an edge move |
| `rotary_encoder_move_angle` (rpm, time) | Angle move, then snap with detents on (REQ-025, 026, 090…093) | When at rest, after the snap |
| `rotary_encoder_rotate` (rpm; direction + time; profile) | Rotates for `duration`, then stops as A-19 (snap with detents on). With a profile and `PROFILE_STOP`, it may end earlier | When at rest |
| `rotary_encoder_set_angle` | Places the shaft at an absolute angle in zero time; with `use_detent` (default false) at the nearest detent instead (tie: positive direction; `TB_ERROR` with detents off). Not a power-up (REQ-071, D-30) | At once |
| `rotary_encoder_jump_edges` | Moves the shaft by N edges in zero time from the current angle, sub-edge fraction kept, no snap (REQ-071, D-3) | At once |

For both: the outputs change from the old to the new state in one delta (edge distance mod 4 = 2: illegal transition; 0: lost cycles; 1/3: one edge), no bounce or jitter, Z without pulses for skipped positions; on a boundary the shaft stays on the side of the old angle.

| Procedure | Behaviour | Completes |
|---|---|---|
| `rotary_encoder_glitch` | Pulse of `width` on A or B, back to the previous value (REQ-072) | After `width` |
| `rotary_encoder_get_status` (function) | Position, angle, logical state, Z, rotation flag, signed rpm at `now` | – |
| Conversions (functions) | rpm ↔ `time_per_edge`, rpm ↔ degrees per second (REQ-095) | – |
| `rotary_encoder_linear_ramp` (function) | Linear profile of N entries (REQ-115, D-18) | – |

Every procedure that takes a state raises `TB_ERROR` and returns at once if the state was not initialized with `rotary_encoder_init`. Invalid parameters and configuration (REQ-016, 023, 024, 045, 054, 063, 074, 076, 079, 094, 110, 114) raise one `TB_ERROR` and produce no edge. Each completed move and fault event is logged with `config.id_for_bfm`: direction, edge count, end position and angle (REQ-085).

### 6.7 Configuration record

| Field | Type | Default | Read | Source |
|---|---|---|---|---|
| `cycles_per_rev` | `integer` | 20 | motion start | A-10, §2 |
| `edges_per_detent` | `integer` | 4 | motion start | A-06 |
| `detents_enabled` | `boolean` | `true` | motion start | A-14 |
| `rest_state` | `std_logic_vector(1 downto 0)` | `"11"` | init (reference state), motion start (detents) | A-06 |
| `start_angle` | `real` | 0.0 | init | A-16 |
| `direction_swap` | `boolean` | `false` | every edge | A-02 |
| `ab_inverted` | `boolean` | `false` | every edge | A-03 |
| `index_enabled` | `boolean` | `true` | every edge | §6 |
| `index_mode` | `t_rotary_encoder_index_mode` | `INDEX_GATED_QUARTER` | every edge | A-10 |
| `index_state` | `std_logic_vector(1 downto 0)` | `"11"` | every edge | A-10 |
| `index_position` | `integer` | 0 | every edge | §6 |
| `index_inverted` | `boolean` | `false` | every edge | A-10 |
| `bounce_enabled` | `boolean` | `false` | every edge | A-07 |
| `bounce_pulses` | `natural` | 2 | every edge | A-07, D-9 (AD-11) |
| `bounce_window` | `time` | 1 ms | every edge | A-07 |
| `bounce_placement` | `t_rotary_encoder_bounce_placement` = (`BOUNCE_RANDOM`, `BOUNCE_EVEN`) | `BOUNCE_RANDOM` | every edge | A-08 |
| `jitter` | `real` (electrical degrees) | 0.0 (off) | every edge | A-05 |
| `a_rise_offset`, `a_fall_offset`, `b_rise_offset`, `b_fall_offset` | `real` (electrical degrees, logical channels) | 0.0 | motion start | A-25, D-26, D-28 |
| `a_stuck`, `b_stuck`, `z_stuck` | `std_logic` (`'0'`, `'1'`, `'Z'`; `'-'` = not stuck) | `'-'` | command start and every edge | A-26, D-27, D-29 |
| `rand_seed1`, `rand_seed2` | `positive` | `C_RAND_INIT_SEED_1/2` | init | REQ-053, 062 |
| `default_snap_rpm` | `real` | 60.0 | when a snap needs it | A-19, D-23 (AD-13) |
| `off_detent_severity` | `t_alert_level` | `TB_WARNING` | motion start | REQ-022, D-7 |
| `bounce_cut_severity` | `t_alert_level` | `TB_WARNING` | every edge | REQ-056, D-22 |
| `id_for_bfm` | `t_msg_id` | `ID_BFM` | – | convention |
| `id_for_bfm_wait` | `t_msg_id` | `ID_BFM_WAIT` | – | convention |

"Read" shows where the value is taken: *motion start* is the geometry latched by `rotary_encoder_start_motion` (REQ-084, REQ-108); *every edge* is the signal configuration, which during a VVC rotation is re-read from the shared VVC configuration at each edge (REQ-108). Integer fields that have a valid range (`cycles_per_rev`, `edges_per_detent`) are `integer`, not `positive`, so an invalid value raises the required `TB_ERROR` instead of a range failure.

## 7. VVC

### 7.1 Processes

| Process | Role |
|---|---|
| `p_cmd_interpreter` | Generated; one change: `TERMINATE_CURRENT_COMMAND` while the executor is idle and a rotation runs halts the rotation directly (7.2) |
| `p_cmd_executor` | Fetches commands, validates them that need VVC state (rotation active?), logs, sets transaction info, sends a **motion request** to `p_motion` and waits for its acknowledge. Never drives the port |
| `p_motion` | The only driver of `rotary_encoder_vvc_if`. At time 0 runs `rotary_encoder_init` with the generic. Then: idle → wait for a request; motion active → `rotary_encoder_run_motion` with `interrupt` = the request signal and the *current* `vvc_config.bfm_config`, so the signal configuration is re-read at every edge |
| `cmd_terminator` | Generated flag handler |

Executor → `p_motion` (PWM pattern of indexed requests):

| Signal | Content |
|---|---|
| `motion_req` | `(idx, kind, motion)`: `kind` ∈ {`REQ_MOTION`, `REQ_STOP`, `REQ_HALT`, `REQ_STATUS`, `REQ_SET_ANGLE`, `REQ_JUMP_EDGES`, `REQ_GLITCH`} |
| `motion_ack` | idx of the last request that has taken effect |
| `motion_done` | idx of the last request whose motion is at rest (moves, stop) |
| `first_edge_ack` | idx of the last rotation start/change whose first edge (or, with no edge, completion point per D-24) has occurred |
| `rotation_active` | `true` from a rotation start until its stop, halt or profile end |
| `motion_status` | `t_rotary_encoder_status` snapshot for `REQ_STATUS` |
| `halt_req` | Interpreter → `p_motion`: halt the rotation while the executor is idle (7.2) |
| `motion_interrupt` | `motion_req.idx + halt_req`, the `interrupt` actual of `rotary_encoder_run_motion` |

### 7.2 Command semantics

| Command | Rejected when | Completes |
|---|---|---|
| `rotary_encoder_move_edges/_detents/_angle` | rotation active → `TB_ERROR`, dropped (REQ-105, D-14) | when the shaft is at rest (after the snap) |
| `rotary_encoder_start_rotation` | rotation active → `TB_ERROR`; invalid speed/profile → `TB_ERROR`, nothing started | at the first edge; at once for 0 rpm; for a profile at its first edge or the end of its first pass if that has none (D-11, D-24) |
| `rotary_encoder_set_speed` | no rotation → `TB_ERROR` (REQ-106); invalid → `TB_ERROR`, rotation unchanged | as the start; replaces a running profile (REQ-113) |
| `rotary_encoder_stop_rotation` | no rotation → `stop_when_idle_severity` (default `TB_WARNING`), no effect | when at rest after the snap (D-12, D-23) |
| `rotary_encoder_set_angle`, `rotary_encoder_jump_edges`, `rotary_encoder_glitch` | rotation active → `TB_ERROR`; `use_detent` with detents off → `TB_ERROR` | at once / after `width` |
| `rotary_encoder_get_status` | – | at once; the result is the state at the execution time, mid-rotation included |
| `terminate_current_command` | – | Move: halt at once at the current angle, no snap. Rotation (also while no command is running, i.e. the rotation itself): halt at once, no snap (D-13, REQ-082 as reworded in Section 13, REQ-107) |
| `flush_command_queue` | – | Does not touch a running rotation (REQ-107) |
| `insert_delay` (time) | – | as usual; with clock cycles: `TB_ERROR` |

`terminate_current_command` and a running rotation: the framework's `interpreter_terminate_current_command` sets the terminate flag only while the executor is busy (`td_vvc_entity_support_pkg.vhd:760`). While a rotation runs and the executor is idle, the flag would stay unseen, or worse, terminate the next command. Therefore the VVC's interpreter handles this case itself: if the executor is idle and `rotation_active` is true, it increments its own signal `halt_req` (logged with `ID_IMMEDIATE_CMD`) instead of calling the framework procedure. If the executor is busy, the framework procedure is called as usual and the executor sends `REQ_HALT`. `p_motion` is interrupted by either signal (`motion_interrupt <= motion_req.idx + halt_req`, a concurrent assignment, so each signal keeps a single driver).

### 7.3 Configuration and status records

- `t_vvc_config`: the standard fields, `bfm_config : t_rotary_encoder_bfm_config`, plus `stop_when_idle_severity : t_alert_level := TB_WARNING` (REQ-106, a VVC-only behaviour).
- `t_vvc_status`: standard, not extended.
- `t_vvc_result` = `t_rotary_encoder_status` (subtype in `vvc_cmd_pkg`, as PWM).

### 7.4 Logging (REQ-085)

- Moves and fault events: the BFM log line (`config.id_for_bfm`) with direction, edges, end position and angle.
- Rotation start / speed change: executor log with the speed (`+60.0 rpm`, or `time_per_edge` and direction), the profile length and `time_per_entry` if any, and "took effect" at completion.
- Stop: executor log with the end position and angle after the snap.
- No per-edge log during a rotation.

### 7.5 Transaction info

Base transaction only: `operation`, `direction`, `num_edges`, `num_detents`, `angle`, `rpm`, `time_per_edge`, `profile_length`, `time_per_entry`, `profile_end`, `channel`, `width`, `vvc_meta`, `transaction_status`. `IN_PROGRESS` when the command starts, `COMPLETED` when it completes as in 7.2.

## 8. Concurrency and integration

- One VVC instance per encoder; instances share nothing except the framework (REQ-083).
- Dependencies: `uvvm_util`, `uvvm_vvc_framework` (the same as PWM). `ieee.math_real` in the BFM body.
- Shared-file changes (scope approved in Phase 4 – Testbench architecture, from the PWM integration precedent): `adaptations_pkg` (three constants), `component_list.txt`, `uvvm_all_context.vhd`, `versions.txt`, `vhdl_ls.toml`, `release/code_conventions/uvvm.yaml`, `doc/source/index.rst` + the VIP's RST page.
- `adaptations_pkg` constants: `C_ROTARY_ENCODER_VVC_CMD_STRING_MAX_LENGTH`, `C_ROTARY_ENCODER_VVC_MAX_INSTANCE_NUM`, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH := 256` (AD-10).

## 9. Alerts and failure behaviour

| Situation | Alert | Effect |
|---|---|---|
| Invalid parameter or configuration | `TB_ERROR` (one per call) | Command dropped, outputs unchanged |
| Move, fault event or second start during a rotation | `TB_ERROR` | Dropped, rotation continues |
| Edge offset outside (−45°, +45°), invalid stuck level, jitter ≥ half the narrowest state | `TB_ERROR` | Command dropped |
| Speed change without rotation | `TB_ERROR` | Dropped |
| Stop without rotation | `stop_when_idle_severity` (`TB_WARNING`) | No effect |
| Detent move off a detent | `off_detent_severity` (`TB_WARNING`) | Executed |
| Bounce cut off | `bounce_cut_severity` (`TB_WARNING`), once per command | Bounce shortened |
| BFM state not initialized | `TB_ERROR` | Returns at once |
| Move distance > 2⁵³ quanta | `TB_ERROR` | Dropped |
| Profile longer than the maximum | `TB_ERROR` | Dropped |

There is no timeout: every command completes by construction (D-24).

## 10. Supported modes and exclusions

- Supported: everything in spec rev 0.5 for the encoder role.
- Excluded: receiver/decoder role, Scoreboard, Unwanted Activity Detection, monitor, push-button (GPIO VVC), and everything in spec §9.
- Not offered: a power-up after time 0 (AD-14). `rotary_encoder_set_angle` places the shaft at a known angle instead.

## 11. Planned generator answers

| Prompt | Answer |
|---|---|
| VVC name | `rotary_encoder` |
| Extended UVVM features | `y` |
| Scoreboard | `n` |
| Transaction info | `y` |
| Unwanted activity detection | `n` |
| Number of channels | Enter (1) |
| Multiple executors | `n` |

Expected post-generation changes (listed again in the Stage 5.1 skeleton comparison): remove `clk`, add the `GC_INSTANCE_IDX` default, library name, file headers, `adaptations_pkg` aliases, add `p_motion`.

## 12. Convention deviations

| ID | Convention | Proposal | Reason | Impact |
|---|---|---|---|---|
| DV-1 | Some official BFMs declare helpers publicly | Only the public API is declared; helpers are body-only | Project rule (skill), keeps the namespace small | None for users; audit must not flag it |
| DV-2 | BFMs are normally stateless | Public state record passed `inout` | The angle and last speed cannot be read back from the signals | Users declare one variable per encoder (as PWM's seeds) |
| DV-3 | BFMs normally expose only user operations | Three low-level motion procedures and the motion record are public, marked "used by the VVC" | The VVC needs interruptible, resumable motion with the same engine (PWM precedent: `pwm_drive_period` with abort) | Documented as "used by the VVC" (AD-15). **Approved by the user 2026-10-27** |

## 13. Requirements cross-check

Every acceptance criterion was checked against this design. Changes are proposed in `rotary_encoder_vvc_reqs.md` rev 0.4 (status *Proposed*).

| ID | Requirement | Finding | Proposal |
|---|---|---|---|
| X-1 | REQ-082 | "stops after the current edge (at an edge boundary)" dates from before the angle model (rev 0.1). With the centre model, a move can only stop at once at the current angle; D-13 already says so for rotations | Reword: stops at once at the current angle, without a snap, as REQ-107 |
| X-2 | REQ-054, D-9 | With `bounce_pulses : natural` (AD-11), an odd or negative toggle count cannot be expressed | Only `bounce_window` ≤ 0 ns is checked; D-9 decided as pulses |
| X-3 | REQ-091 | Exact for angles with ≤ 7 decimals; others are rounded once per move to the quantum (6.2) | Add the note; the test values (1°, 0.1°) are exact |
| X-4 | REQ-111, REQ-114 | "maximum length (constant, Phase 3)" | 256 entries, `C_ROTARY_ENCODER_VVC_CMD_PROFILE_MAX_LENGTH` |
| X-5 | REQ-104, REQ-107 (F-003) | Stop or terminate exactly at an edge time needs a defined owner | New D-25: the edge is emitted first (AD-7) |
| X-6 | REQ-002, REQ-005 | Start angles −10°, 30°, 400° need a power-up per value | Feasible through several VVC instances or the BFM; planned in Phase 4 |
| X-7 | REQ-108 | Swap/inversion changed mid-rotation make the next edge change both lines | Documented consequence (6.3); no requirement change |
| X-8 | REQ-012, 101 (timing) | Achievable with 6.2 at ps and fs. GHDL runs at fs; 10 revolutions at 7 rpm last 86 s ≈ 8.6·10¹⁶ fs, which still fits `time` (64 bit). The split computation keeps the `real` part small | None |
| X-9 | REQ-061 (statistics) | Uniform ±A: the mean of 10 000 samples has σ ≈ A/173, the bound A/10 is 17σ; the chance of missing the outer 5 % at either end is 0.975¹⁰⁰⁰⁰ ≈ 10⁻¹¹⁰ | None |
| X-10 | REQ-100, 102, 111 (completion) | Achievable: `p_motion` acknowledges the first edge through `first_edge_ack` | None |
| X-11 | REQ-075, 076 (offsets) | With offsets in (−45°, +45°) every boundary stays between its two state centres, so REQ-012/092 completion times and REQ-021 rest states keep holding; only edge times change | Range fixed as D-28 |
| X-12 | REQ-001 vs. REQ-078 | A stuck `'Z'` contradicts "strong levels only" | REQ-001 exception (rev 0.4) |
| X-13 | REQ-108 | Offsets move edge angles, so they belong to the geometry (motion start); stuck outputs are signal configuration (every edge) | REQ-108 lists updated |

Spec rev 0.6 adds AD-7 to A-13 (Q-3) and the fault model (AD-17).

## 14. Decisions and open questions

| ID | Decision | Recommendation | Alternative |
|---|---|---|---|
| AD-1 | VVC name | `rotary_encoder` | `quadrature_encoder`; `encoder` |
| AD-2 | Library / directory | `p2l2_vip_rotary_encoder` | – |
| AD-3 | Header and copyright holder | **Confirmed by the user 2026-10-27 (Q-1):** UVVM Apache banner, `Copyright 2026 UVVM` (as PWM) | Another holder |
| AD-4 | Process structure | Executor + `p_motion` (single driver), engine in the BFM | Rotation logic in the VVC entity (BFM and VVC would differ) |
| AD-5 | Angle representation | Integer position + integer offset, K = 9·10⁸ quanta per edge | `real` degrees (fails REQ-091 for 0.1° steps) |
| AD-6 | Edge-time computation | Split `time` + small `real`, recomputed from the segment anchor | Incremental addition (accumulates rounding) |
| AD-7 | Boundary owner (F-003) | Edge first: reaching a boundary emits the edge | "Strictly beyond": not implementable deterministically for stops at an edge time |
| AD-8 | State mapping and rest-state changes | Mapping fixed at init; `rest_state` changes move only the detents | Remap A/B on change (jumps) |
| AD-9 | Index cycle | *q* = largest position ≤ `index_position` with `index_state` | `index_position` = first active position, no `index_state` field (deviates from A-10) |
| AD-10 | Profile maximum | 256 entries, constant in `adaptations_pkg` | 64 / 1024 |
| AD-11 | Bounce amount (D-9) | `bounce_pulses : natural` (2 toggles each); defaults 2 pulses and 1 ms window **confirmed by the user 2026-10-27 (Q-2)** | Even toggle count, validated |
| AD-12 | Status read-back (U-2) | Included: `rotary_encoder_get_status` + `fetch_result()` | Excluded |
| AD-13 | Default snap speed | 60 rpm | Another value |
| AD-14 | Start state | From the generic at time 0 only. A known angle later in the simulation is set with `rotary_encoder_set_angle` (not a power-up, rev 0.3) | A re-initialization command that re-reads the configuration |
| AD-15 | Visibility of the motion engine | **Decided by the user 2026-10-27:** stays public in the BFM package, documented "used by the VVC" (6.5) | Internal package (rejected) |
| AD-16 | Timed BFM rotation | **Decided 2026-10-27:** kept ("keep as is") | Rotation VVC-only |
| AD-17 | Fault model | **Decided by the user 2026-10-27:** device faults by configuration (four edge offsets, stuck A/B/Z), fault events by request (`rotary_encoder_set_angle` with `use_detent` and `rotary_encoder_jump_edges` replace `rotary_encoder_illegal_transition` (rev 0.3/0.4, user requests); `rotary_encoder_glitch` kept) | One fixed illegal-transition request (rev 0.1) |

Answered questions: Q-1 copyright holder `UVVM` (yes), Q-2 bounce defaults (yes), Q-3 boundary rule in spec A-13 (done), Q-4 D-26 to D-30 (accept all), all 2026-10-27. AD-1 to AD-17 accepted 2026-10-27; no open questions.

## 15. API preview

All declarations below are public. Everything else (Gray mapping, edge-time split, jitter and bounce scheduling, index decision, validation, formatting) is body-only.

### 15.1 BFM package declarations

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
  type t_rotary_encoder_index_mode        is (INDEX_GATED_QUARTER, INDEX_GATED_HALF, INDEX_UNGATED);
  type t_rotary_encoder_bounce_placement  is (BOUNCE_RANDOM, BOUNCE_EVEN);
  type t_rotary_encoder_profile_end       is (PROFILE_HOLD, PROFILE_STOP, PROFILE_REPEAT);

  type t_rotary_encoder_bfm_config is record
    cycles_per_rev      : integer;
    edges_per_detent    : integer;
    detents_enabled     : boolean;
    rest_state          : std_logic_vector(1 downto 0);
    start_angle         : real;
    direction_swap      : boolean;
    ab_inverted         : boolean;
    index_enabled       : boolean;
    index_mode          : t_rotary_encoder_index_mode;
    index_state         : std_logic_vector(1 downto 0);
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
    default_snap_rpm    : real;
    off_detent_severity : t_alert_level;
    bounce_cut_severity : t_alert_level;
    id_for_bfm          : t_msg_id;
    id_for_bfm_wait     : t_msg_id;
  end record t_rotary_encoder_bfm_config;

  constant C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT : t_rotary_encoder_bfm_config := (
    cycles_per_rev      => 20,
    edges_per_detent    => 4,
    detents_enabled     => true,
    rest_state          => "11",
    start_angle         => 0.0,
    direction_swap      => false,
    ab_inverted         => false,
    index_enabled       => true,
    index_mode          => INDEX_GATED_QUARTER,
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
    default_snap_rpm    => 60.0,
    off_detent_severity => TB_WARNING,
    bounce_cut_severity => TB_WARNING,
    id_for_bfm          => ID_BFM,
    id_for_bfm_wait     => ID_BFM_WAIT
  );

  -- Result of rotary_encoder_get_status() and of the VVC's rotary_encoder_get_status() via fetch_result()
  type t_rotary_encoder_status is record
    position     : integer;                      -- Edges from position 0
    angle        : real;                         -- Degrees, sub-edge precision
    ab           : std_logic_vector(1 downto 0); -- Logical state (before swap and inversion)
    index_active : boolean;                      -- Logical Z (before inversion)
    is_rotating  : boolean;
    rpm          : real;                         -- Signed current speed, 0.0 when not rotating
  end record t_rotary_encoder_status;

  -- BFM state: one variable per encoder, initialized with rotary_encoder_init(). Fields are private.
  type t_rotary_encoder_state is record
    -- (private fields: initialized flag, reference state, position, offset, latched geometry,
    --  active motion and segment anchor, last non-zero speed, bounce bookkeeping, seeds)
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

  -- rotary_encoder_move_detents: as rotary_encoder_move_edges, with num_detents : natural (2 overloads)
  -- rotary_encoder_move_angle:   as rotary_encoder_move_edges, with angle : real (degrees, >= 0.0) (2 overloads)

  ---------------------------------------------------------------------------------
  -- Timed rotation: rotates for duration, then stops as a VVC stop (snap with detents on)
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
  -- Places the shaft at angle (degrees) in zero time; use_detent: at the nearest detent instead
  procedure rotary_encoder_set_angle(
    constant angle        : in    real;
    variable state        : inout t_rotary_encoder_state;
    constant msg          : in    string;
    signal   encoder_if   : inout t_rotary_encoder_if;
    constant use_detent   : in    boolean                     := false;
    constant scope        : in    string                      := C_BFM_SCOPE;
    constant msg_id_panel : in    t_msg_id_panel              := shared_msg_id_panel;
    constant config       : in    t_rotary_encoder_bfm_config := C_ROTARY_ENCODER_BFM_CONFIG_DEFAULT
  );

  -- Moves the shaft by num_edges in zero time, no snap (2 edges: illegal transition)
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

  procedure rotary_encoder_glitch(
    constant channel      : in    t_rotary_encoder_channel;
    constant width        : in    time;
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
  type t_rotary_encoder_motion_kind  is (MOTION_EDGES, MOTION_DETENTS, MOTION_ANGLE, MOTION_ROTATION, MOTION_STOP);
  type t_rotary_encoder_speed_form   is (SPEED_RPM, SPEED_TIME_PER_EDGE);
  type t_rotary_encoder_motion_event is (MOTION_EDGE, MOTION_PROFILE_PASS, MOTION_DONE, MOTION_INTERRUPTED);

  type t_rotary_encoder_motion is record
    kind           : t_rotary_encoder_motion_kind;
    direction      : t_rotary_encoder_direction; -- moves; rotation in SPEED_TIME_PER_EDGE
    num            : natural;                    -- edges or detents
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

  procedure rotary_encoder_start_motion(
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

  procedure rotary_encoder_halt_motion(
    variable state : inout t_rotary_encoder_state
  );

end package rotary_encoder_bfm_pkg;
```

`t_rotary_encoder_state` is shown without its fields here; the real declaration has them (a record cannot be empty), commented as private.

### 15.2 VVC methods (`vvc_methods_pkg`)

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
-- rotary_encoder_move_detents (num_detents : natural) and rotary_encoder_move_angle (angle : real): same two overloads each

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

-- Zero time. set_angle: absolute degrees, use_detent snaps to the nearest detent.
-- jump_edges: relative to the angle at execution time, no snap.
procedure rotary_encoder_set_angle(
  signal   VVCT                : inout t_vvc_target_record;
  constant vvc_instance_idx    : in    integer;
  constant angle               : in    real;
  constant msg                 : in    string;
  constant use_detent          : in    boolean        := false;
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

### 15.3 Usage example (VVC)

```vhdl
-- Defaults: 20 cycles/rev (4.5 deg per edge, 18 deg per detent), detents on, index on
rotary_encoder_move_detents(ROTARY_ENCODER_VVCT, 1, FORWARD, 3, 60.0, "Three clicks forward");     -- 12 edges, 150 ms
rotary_encoder_move_angle(ROTARY_ENCODER_VVCT, 1, REVERSE, 10.0, 1 ms, "Turn back 10 deg, snaps"); -- ends on a detent
rotary_encoder_start_rotation(ROTARY_ENCODER_VVCT, 1, 600.0, "Motor at 600 rpm");
await_completion(ROTARY_ENCODER_VVCT, 1, 10 ms, "First edge seen");                               -- 1.25 ms per edge
wait for 100 ms;                                                                                    -- the test does other things
rotary_encoder_set_speed(ROTARY_ENCODER_VVCT, 1, rotary_encoder_linear_ramp(600.0, -600.0, 11), 10 ms, PROFILE_HOLD,
                         "Reverse through a ramp");
rotary_encoder_get_status(ROTARY_ENCODER_VVCT, 1, "Where is the shaft?");
v_cmd_idx := get_last_received_cmd_idx(ROTARY_ENCODER_VVCT, 1);
await_completion(ROTARY_ENCODER_VVCT, 1, 1 sec, "");
fetch_result(ROTARY_ENCODER_VVCT, 1, v_cmd_idx, v_status, "Read status");
rotary_encoder_stop_rotation(ROTARY_ENCODER_VVCT, 1, "Stop, snaps to a detent");
```

### 15.4 Usage example (BFM only)

```vhdl
variable v_enc : t_rotary_encoder_state;
...
rotary_encoder_init(v_enc, "Power-up", encoder_if, config => C_ENC_CONFIG);
rotary_encoder_move_edges(FORWARD, 5, 1 us, v_enc, "5 edges", encoder_if, config => C_ENC_CONFIG);
rotary_encoder_rotate(-120.0, 50 ms, v_enc, "Reverse 50 ms at 120 rpm", encoder_if, config => C_ENC_CONFIG);
-- 5 edges forward, then 8 edges back (50 ms / 6.25 ms) to position -3, then the stop snaps to the detent at -4
check_value(rotary_encoder_get_status(v_enc).position, -4, ERROR, "On the detent at -18 deg");
```

## 16. Traceability (architecture → requirements)

| Section | Requirements |
|---|---|
| 5 Interface, start state | REQ-001, 002, 005 |
| 6.1 Angle model, boundary rule, edge offsets, detents | REQ-004, 014, 020…027, 075…077, 090…094 |
| 6.2 Edge times, jitter | REQ-012, 013, 060…063, 101 |
| 6.3 Driving an edge, bounce, stuck outputs | REQ-001, 030…032, 050…056, 070, 078, 079 |
| 6.4 Index | REQ-040…045, 055 |
| 6.5 Motion engine | REQ-003, 100…115 |
| 6.6 BFM procedures | REQ-010, 011, 015, 016, 071, 072, 074, 080, 095, 115 |
| 7 VVC processes and commands | REQ-081…085, 100…114 |
| 7.4 Logging | REQ-085 |
| 9 Alerts | all `TB_ERROR`/severity requirements |
