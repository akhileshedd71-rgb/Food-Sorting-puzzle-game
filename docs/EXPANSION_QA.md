# Front-end and Chef Coins QA

The v0.2 expansion is covered by the production service tests and live-scene input tests. The live UI tests load `scenes/main.tscn`, send actual Godot mouse/touch events through the viewport, and inspect the resulting board, saved profile, UI controls and tray rendering properties. Currency used by the expansion scenarios comes from the real welcome gift, Cooking School graduation and first campaign clears; the UI tests do not simulate paid grants.

## Reproduce the checks

Use Godot **4.7.2**. The standard runner selects the pinned engine, rejects a different version, sets `GARDEN_UI_TEST=1`, and isolates every run's save/config/cache directories before discovering all `tests/*_tests.gd` suites:

```bash
source /workspace/tools/environment.sh # cloud machine; use your helper's environment.sh elsewhere
bash tools/run_checks.sh
```

To run only the new integration suite with screenshots on a Linux graphical display:

```bash
source /workspace/tools/environment.sh
qa_dir="$(mktemp -d /tmp/garden-expansion-qa.XXXXXX)"
mkdir -p "$qa_dir/data" "$qa_dir/config" "$qa_dir/cache" "$qa_dir/screenshots"
GARDEN_UI_TEST=1 \
  XDG_DATA_HOME="$qa_dir/data" \
  XDG_CONFIG_HOME="$qa_dir/config" \
  XDG_CACHE_HOME="$qa_dir/cache" \
  "$GODOT_BIN" --audio-driver Dummy --path . \
  --script tests/expansion_ui_tests.gd -- \
  --expansion-screenshots="$qa_dir/screenshots"
```

Add `--headless` for the equivalent logic/input checks without screenshots. On this cloud machine, `DISPLAY=:99` is an Xvfb display. Dummy audio is appropriate for cloud rendering because the machine has no audio output device. It does not replace listening tests on a device. The screenshot tests use a 450×1000 window with a 720×1600 logical layout.

**The standalone UI suites reset their selected local profile. Always use an isolated `XDG_DATA_HOME`.** The standard runner handles isolation automatically. `tests/ui_tests.gd` retains campaign input regressions and explicitly enters campaign level 1 after checking the new splash/title/menu flow.

## Behaviors covered

| Area | Integration evidence |
| --- | --- |
| Boot and menus | Splash skip, automatic reduced-motion advance, title → home, home → title, returning-player progress, one-time welcome coins, stale splash timer invalidation, and muted music while the splash advances in the background. |
| Cooking School | Three separately authored lessons played with touch drags; free guide/undo/restart; optional exit; next-lesson resume after a full scene reload; full replay without another graduation reward; failed checkpoint/graduation save, durable rollback and successful retry. |
| Campaign isolation | An unfinished campaign and its undo/run metadata survive school entry, individual lesson completion, replay, reload and graduation exactly; an incompatible campaign handoff keeps the school context when the player returns. Practice never records a campaign completion. |
| Confirmed hints | Confirmation and cancellation reveal no free hint or debit; successful certified guidance costs 10; repeat confirmation and reload reuse the identical paid hint; solver exhaustion charges nothing. |
| Extra tray | Cancel and confirmed 40-coin purchase; seventh tray bounds/hit targets; moving food onto that tray; reload with food and both undo checkpoints; undo across the grant; single-charge ownership; Continue and free restart semantics. |
| Finishes | Cancel and confirm permanent Sage purchase; owned/equipped persistence; free switching; actual `TrayView.rim_color` and `accent_color` change on every live tray; puzzle state unchanged. |
| Low balance | Earned currency is spent down to zero; hint and tray requests show the recovery explanation without granting effects, moving food or making the balance negative. |
| Future coin packs | All three pack buttons are disabled, have no purchase/grant signal callback, and cannot change the balance when clicked. Home-origin shop tools are disabled. |
| Visual cleanup | Switching lessons or opening the shop removes old board match captions. The shop scrolls independently and every seven-tray slot and toolbar control remains within the viewport at 450×1000, 360×780 and 800×1280 window sizes. |

The school save-failure checks temporarily set the service's write-blocked guard, verify the previous on-disk profile/session, then clear the guard and press the real retry button. No real player save is used.

The solver-exhaustion check deliberately supplies a zero-budget/no-witness fixture. It verifies the failure path deterministically; it is not a difficulty or solver-speed measurement. Full hint certification, ledger integrity, file recovery, version migration and failed-write rollback are covered by the corresponding core/economy/save service suites.

## Validation results

Godot 4.7.2 completed the full headless runner with **3,215 checks and zero failures**, plus a clean project import and startup check:

| Suite | Checks |
| --- | ---: |
| Core resolver | 236 |
| Economy | 98 |
| Expansion live UI | 581 |
| Authored levels | 1,880 |
| Motion | 45 |
| Saves/audio | 59 |
| Cooking School content | 152 |
| Existing live UI input | 164 |

The Xvfb/OpenGL graphical expansion run passed **592 checks**, including ten screenshot saves and the graphical music-pause assertion. Reviewed screenshots show title/menu controls, all three school lessons, a seven-tray board, the scrolling shop and the applied Sage finish. The cleanup regressions verify that match captions from an earlier board do not appear over the next screen. A subsequent verbose graphical run exited without ObjectDB leak warnings after the test allowed the audio mixer to finish retiring stopped playbacks; Xvfb still reports its unsupported V-Sync control.

The Android **0.2.0 / version code 2** debug APK exported successfully and passed APK v2/v3 signature verification. Package inspection confirmed 30 campaign levels, three school lessons, the food catalog, all eight compiled Resource targets, ARM64/x86_64 libraries, portrait orientation and only the vibration permission. Tests, tools and documentation were excluded from the APK.

## Captured views

The graphical suite writes `expansion_splash.png`, `expansion_title.png`, `expansion_home.png`, `expansion_school_01.png` through `03`, `expansion_extra_tray_7.png`, `expansion_shop.png`, `expansion_shop_coin_packs.png`, and `expansion_sage_enamel.png`. Selected reviewed views are kept under `docs/screenshots` for the README; the full screenshot set remains a local QA artifact. Neither is packaged in the game.

Before an Android release, test physical touch input, pause/resume, safe areas, audible sound/music, vibration settings and performance on representative phones. Desktop/Xvfb evidence does not establish mobile hardware performance. Coin packs remain explicitly unavailable; this delivery contains no billing SDK, purchase fulfillment or fake payment-success action.
