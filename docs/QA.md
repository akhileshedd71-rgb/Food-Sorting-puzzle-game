# Verification and remaining acceptance work

Tested using Godot `4.7.2.stable.official.ed1daf0bf` on Linux x86_64. The graphical run uses the Compatibility renderer with Mesa llvmpipe under Xvfb; that is a software-rendered desktop environment, not an Android performance sample.

## Automated checks

Run `bash tools/run_checks.sh` after sourcing the environment helper (or setting `GODOT_BIN`). It uses a temporary profile and fails on script/import errors even when Godot reports exit status zero.

| Suite | Evidence |
| --- | --- |
| `tests/core_tests.gd` | Deterministic rules, exact Appendix E fixtures/hashes, two-ticket buffering, cascades, invalid commands, conservation, undo and bounded search |
| `tests/level_tests.gd` | 30 successful campaign replays, 225 accepted commands, stable hash certificates, undo for every step, inventory/recipe supply and exact authoring dimensions |
| `tests/save_tests.gd` | Stable state/history round trip, reward integrity, corrupt save recovery, temporary/backup interruption cases, content mismatch and audio controls |
| `tests/ui_tests.gd` | Actual touch/mouse event routing, second-pointer exclusion, invalid/canceled drops, pause/resume, scaled coordinates, tutorial, saved session and layout checks |

The development brief's Appendix D describes authoring goals. The stored witnesses prove solvability and demonstrate the taught actions. They do not prove every intended strategy is mandatory or that a level has the shortest solution. See `docs/LEVELS.md` for the authoring results and `data/levels/replay_report.json` for exact machine evidence.

The snapshot and recipe tests cover every accepted solution command. A separate integration run also saved and cold-loaded all 225 campaign commands with zero mismatches; the resulting profile had 30 completion records and 900 coins, with the unlock capped at level 30.

The final headless suite reports **2,320 assertions with zero failures**: 236 core, 1,880 level, 48 save/audio and 156 UI checks. The graphical UI variant adds screenshot assertions (165 checks, zero failures). Its 20 level/home transitions showed node count 101 → 99 and resource count 45 → 45. Godot-tracked static memory stayed approximately 50.5 MB in that graphical run. These counts establish no observed scene/resource accumulation in this short desktop test; they are not total-process memory or a phone benchmark.

## Render and export checks

The real Godot client has been rendered at portrait desktop size; six-food palettes, recipe strips, queue previews, two-column trays, toolbar and menu bounds are inspected. Original generated art is used throughout. Headless UI tests exercise pointer coordinate transforms at 360×800 and the normal desktop size.

Android tooling was provisioned from official sources, including matching 4.7.2 templates, Java 21, Android SDK Platform 36 and Build-Tools 36.1.0. The debug APK exports and passes `apksigner verify`. Its manifest declares portrait orientation, API 24 minimum / API 36 target, and vibration permission. No INTERNET permission or online service is required. ARM64 and x86_64 libraries are included.

## Not established by cloud checks

- Physical-device multi-touch, notch/navigation inset behavior, comfort of real tap targets and Android task lifecycle.
- Human tutorial comprehension, difficulty pacing, repeated-level enjoyment or the 2–5 minute session goal.
- Audible speaker/headphone mix quality; files and bus/preferences are tested, but the cloud has no audio output device.
- Phone GPU/CPU budgets, p95 frame time, battery use, memory under an extended 20–30 minute session, and thermal behavior.
- Play Store readiness, release signing, Android release AAB or 150/600-level expansion content.

These are explicit local playtest/release gates. They are not represented as successful tests in the project.
