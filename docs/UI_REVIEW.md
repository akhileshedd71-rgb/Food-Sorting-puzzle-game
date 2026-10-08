# UI integration and visual review

Tested with Godot 4.7.2 Compatibility on Linux. `tests/ui_tests.gd` instantiates the actual main scene and sends `InputEventScreenTouch`, `InputEventScreenDrag`, mouse and key events through the viewport's normal input pipeline. It does not call pointer handlers to simulate a successful move.

## Reproduce

The integration suite creates and rewrites a profile. Always use an isolated user-data directory:

```bash
GARDEN_UI_TEST_DATA=$(mktemp -d)
GARDEN_UI_TEST=1 XDG_DATA_HOME="$GARDEN_UI_TEST_DATA" godot --headless --path . --script tests/ui_tests.gd
```

To include rendered screenshots, run with a graphical display and omit `--headless`:

```bash
GARDEN_UI_TEST_DATA=$(mktemp -d)
GARDEN_UI_TEST=1 XDG_DATA_HOME="$GARDEN_UI_TEST_DATA" godot --path . --audio-driver Dummy --script tests/ui_tests.gd -- --ui-screenshots=/tmp/garden-table-ui-shots
```

Use the executable name appropriate to your local Godot installation. The required test opt-in prevents accidentally running the script as an ordinary game. `XDG_DATA_HOME` isolation applies to Linux; on other platforms run the suite in a disposable profile or adapt the test save path before running it.

## Coverage

- Fresh launch, guided first tap, one-move tutorial victory, immediate persistence, next-level unlock, and no duplicate replay rewards.
- Dragging and tap-to-move through real touch and mouse events, including physical mouse coordinates at a 360 × 800 window with a 720 × 1600 logical canvas.
- A second finger cannot steal a gesture, commit a move, release the first pointer, or activate the pause button.
- Occupied drops, drops outside trays, OS-canceled touches, and releases over toolbar buttons leave the board unchanged and clear pointer/ghost state.
- Pause from Escape and focus loss during a drag, late pointer releases behind the modal, and normal resume.
- Accepted animated victory followed by focus loss: stable state is already saved, presentation finishes, pause remains visible, and victory appears after resume.
- Mouse undo, exact disk save reload, undo-history restore, incompatible content recovery, and preservation of completed profile data.
- Hint source and destination remain executable after an equivalent within-tray slot permutation.
- Layout and hit-test bounds for levels 1, 17 and 30; home, pause, queues, settings and all four recipe cards.
- Twenty level/home roundtrips followed by node/resource-count comparison on the same level.

## Results and limits

The graphical run passed **165 checks with zero failures**. The software-rendered Linux session used Mesa llvmpipe. Twenty level/home roundtrips took 2621.9 ms in that run; scene-node count changed from 101 to 99, resource count stayed at 45, and Godot static memory changed from 50,529,562 to 50,505,142 bytes. The two transient nodes had expired by the final sample. There was no accumulated scene-node or resource growth.

These measurements describe this desktop regression run, not phone frame rate, peak process memory, battery consumption, or mobile thermal behavior. Touch events are engine-level synthetic inputs; a real Android device still needs installation, touch feel, safe-area and suspend/resume verification.

The screenshot helper captures the game viewport directly. Level 1 is captured at 450 × 1000; later review screens use 720 × 1600. Inspection confirmed clean sprite alpha, distinct food silhouettes, visible queue previews, all six level-30 trays, complete tool controls, and unclipped modal/recipe content. The tall-menu code is checked for fit and for scrolling when its content exceeds the viewport.
