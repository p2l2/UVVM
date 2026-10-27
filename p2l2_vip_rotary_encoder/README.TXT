-----------------------------------------------------------
-- Directory structure                                   --
-----------------------------------------------------------

- p2l2_vip_rotary_encoder : A VIP that uses UVVM
  - doc                   : Specification, requirements and architecture
  - script                : Compile scripts
  - src                   : Rotary encoder VIP BFM and VVC source code
  - tb                    : Rotary encoder VIP testbenches

This VIP emulates an incremental rotary (quadrature) encoder: channels A and B,
optional index Z, detents, contact bounce, jitter and device faults.
