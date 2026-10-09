# Content expansion QA — version 0.3

This document records validation of the 150-level, 18-food, 12-recipe campaign on 2026-10-09 with Godot **4.7.2**. The previous `EXPANSION_QA.md` remains the historical v0.2 report.

## Integration coverage

The content UI suite loads the real main scene and sends Godot mouse/touch events through the viewport. It covers:

- The authentic v0.2 save fixture: completed levels 1–30 gain access to 31 while the unfinished level-30 replay, purchased seventh tray, current food, undo history, run ID, paid-hint receipts, wallet, tutorial and equipped finish remain intact.
- Campaign progression from level 50 into Backyard Barbecue (51), from 100 into Breakfast Griddle (101), and the terminal level-150 victory.
- Chapter-map navigation, the current level marker, completed/locked cells, and the confirmation before replacing an unfinished board.
- All 18 food collection identities and their first-appearance labels; all 12 recipe cards and their actual ingredient icons. The original Garden Sampler completion has its served badge after migration, and newly served Backyard Combo / Sweet Morning badges appear immediately and survive a cold scene reload.
- Atlas crop bounds, transparent sprite backgrounds, and visible content for every registered food; representative new foods displayed on live boards.
- Layout and scrolling on the new collection, map and recipe screens; long food labels stay inside their own tray slots with high readability enabled. Graphical screenshots cover the title, all chapter menus, new food boards, map highlights, collections and chapter/final celebrations.

The existing input suite keeps its original level-17/30 fixtures because the first 30 authored levels are frozen. Its recipe-album assertion checks the four registered recipe names for the selected chapter. Economy, free practice, purchases and saved-board regressions remain in the v0.2 expansion UI suite.

## Results

The final `tools/run_checks.sh` pass imported the project, ran all ten test scripts, and launched the main scene without script errors: **21,641 checks/assertions, zero failures**.

| Suite | Checks / assertions |
| --- | ---: |
| Catalog resources, chapter routing and recipes | 818 |
| Content UI and migration integration | 2,792 |
| Core rules and Appendix E fixtures | 236 |
| Economy transactions | 98 |
| Earlier expansion UI regressions | 581 |
| All 150 levels, replay/undo certificates and content invariants | 16,626 |
| Motion and pointer state | 45 |
| Save integrity, migration and audio | 125 |
| Cooking School | 152 |
| General UI and input routing | 168 |

The graphical content run on X11/Mesa llvmpipe passed **2,813 checks**, including **21 screenshot captures**, at a 450 × 1000 window with a 720 × 1600 logical canvas. Reviewed images show the new food art, chapter headers and collection cards within their bounds. Review found and corrected long high-readability labels escaping their slots; the final snapshots and regression checks confirm the fix. Recipe badge checks also protect against comparing JSON float requirements with in-memory integer requirements.

No script errors, resource-leak reports or export warnings were reported in the final passes. Xvfb reported only that changing VSync mode is unsupported by its graphics driver. The desktop transition check retained 100 scene nodes and 48 resources across 20 level/home roundtrips; it is a regression measurement, not an Android performance claim.

The full screenshot set was produced in `/workspace/scratch/content-v03-shots-final`; selected previews are kept under `docs/screenshots`. Cloud execution logs are `/workspace/scratch/content-v03-checks-final.log`, `/workspace/scratch/content-v03-graphics-final.log` and `/workspace/scratch/content-v03-export.log`.

## Reproduce

```bash
source /workspace/tools/environment.sh
bash tools/run_checks.sh
```

The runner requires Godot 4.7.2, uses temporary save/config/cache directories, sets `GARDEN_UI_TEST=1`, and discovers every `tests/*_tests.gd` file. Standalone UI runs also require an explicitly isolated `XDG_DATA_HOME`; they overwrite their selected test profile.

For a graphical content run on an available Linux display:

```bash
source /workspace/tools/environment.sh
qa_dir="$(mktemp -d /tmp/garden-content-ui.XXXXXX)"
export GARDEN_UI_TEST=1
export XDG_DATA_HOME="$qa_dir/data"
export XDG_CONFIG_HOME="$qa_dir/config"
export XDG_CACHE_HOME="$qa_dir/cache"
DISPLAY=:99 "$GODOT_BIN" --path . --audio-driver Dummy --disable-vsync \
  --script tests/content_ui_tests.gd -- --ui-screenshots="$qa_dir/screenshots"
```

## Android package evidence

The final debug APK was exported from this source using the checked Godot 4.7.2 templates and Android Build-Tools 36.1.0. It remains an ignored local build artifact at `builds/garden-table-debug.apk`; no release signing or store publication was performed.

| Property | Verified value |
| --- | --- |
| Package | `com.akhilesh.gardentable` |
| Version | `0.3.0`, version code `3` |
| Size | 63,457,336 bytes |
| SHA-256 | `d68eb0bcdae4ae5431e81243b3f516507b904a477d194de26070011ac00a35ee` |
| Signature | APK signature schemes v2 and v3 verified |
| Android | Minimum API 24, target API 36 |
| Architectures | ARM64 and x86_64 |
| Orientation | Portrait |
| Requested permission | `android.permission.VIBRATE` only |

The package audit found all **150 level JSON files byte-for-byte identical** to the authored source, all **12 recipe files**, all **18 food definitions and their remapped native resources**, and all **three imported food atlases**. Tests, tools and documentation are excluded from the APK. Build and local device instructions are in [ANDROID.md](ANDROID.md).

Human pacing, listening, physical Android touch/lifecycle behavior and sustained hardware performance remain device acceptance checks. Stored winning replays certify that every authored board is solvable under the production rules; they do not claim shortest solutions or replace human playtesting.
