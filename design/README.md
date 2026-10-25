# Design documents

The target ReservePark design, as presented in our slides for challenge sections 4.1 to 4.7.

| Document | Contents |
| --- | --- |
| [PRD.md](PRD.md) | The main design reference: policy, requirements F01–F18, architecture, register and memory contracts, booking / entry / exit FSMs (sections 8 to 8.2), test catalogue D00–D29, random families, DFx and evidence plan |
| [register_map.md](register_map.md) | Full register map for 4.4.2: address regions, R0–R17 field by field with type and reset values, prototype extensions, and what the simulation implements |
| [diagrams/](diagrams/) | Block diagram (4.1) and the three FSM diagrams (4.5) as PNG and editable SVG, plus `make_diagrams.py` that generates them |
| [slide_content.md](slide_content.md) | Team working notes: slide text for 4.1–4.7, state description tables, and how the simulation results map onto the slides |
| [requirements_and_simulation_review.md](requirements_and_simulation_review.md) | Team working notes: cross-check of the challenge requirements against our design |
| [RESERVEPARK_RISCV_Coding_Agent_Brief.md](RESERVEPARK_RISCV_Coding_Agent_Brief.md) | Build brief for the next phase: the full RISC-V proof of concept with firmware, persistence and random tests |

The simplified simulation that validates this design is in [../simulation/](../simulation/).
