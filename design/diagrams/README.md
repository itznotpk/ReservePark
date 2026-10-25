# Slide diagrams

| File | Slide | Content |
| --- | --- | --- |
| `block_diagram_4_1.png` / `.svg` | 4.1 Block diagram | SoC blocks, bus links, external I/O, direct sensor and interlock wires |
| `exit_fsm_4_5.png` / `.svg` | 4.5 Exit FSM | Corrected exit FSM from PRD section 8.1, with new and renamed states marked |
| `entry_fsm.png` / `.svg` | Extra slide (entry) | Entry FSM extending the challenge template; same grid as the exit FSM (PRD section 8.2) |
| `overall_fsm.png` / `.svg` | Extra slide before 4.5 | Booking FSM from request to close; arrows labelled with the lane state that causes each move (PRD section 8) |

The three FSMs are aligned: lane states use ENTRY_ / EXIT_ prefixes, both lane FSMs share one column grid, and the overall FSM uses only booking states. FSM canvases are 2400×1350, rendered at `--force-device-scale-factor=1.6 --window-size=2400,1350`.

PNGs are 3840×2160 (16:9), sized for a full-width slide. SVGs stay sharp at any size and can be converted to editable shapes in PowerPoint (Insert > Pictures, then right-click > Convert to Shape).

These are design diagrams, not simulation results.

## Regenerate after edits

Edit coordinates and labels in `make_diagrams.py`, then from this folder:

```sh
python make_diagrams.py .
```

Render PNGs with headless Chrome. Chrome may be blocked from writing into OneDrive folders, so write to a temp folder and copy:

```sh
chrome --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1920,1080 --screenshot=<temp>/exit_fsm_4_5.png file:///<path>/exit_fsm_4_5.svg
```
