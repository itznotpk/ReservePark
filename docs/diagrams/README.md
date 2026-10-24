# Slide diagrams

| File | Slide | Content |
| --- | --- | --- |
| `block_diagram_4_1.png` / `.svg` | 4.1 Block diagram | SoC blocks, bus links, external I/O, direct sensor and interlock wires |
| `exit_fsm_4_5.png` / `.svg` | 4.5 Exit FSM | Corrected exit FSM from PRD section 8.1, with new and renamed states marked |

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
