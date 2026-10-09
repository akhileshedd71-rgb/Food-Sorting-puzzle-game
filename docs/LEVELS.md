# Campaign content and certification

Garden Table contains **150 frozen levels, 18 food identities and 12 recipe bundles** across three chapters. Levels 1–30 are the original individually authored teaching boards. Levels 31–150 are offline generated additions, selected against an explicit curriculum, structural-diversity checks and production-model solution replays. They are not represented as 120 hand-designed or human-playtested puzzles.

Every published board has a stored legal solution without hints, extra trays or other tools. Across the catalogue, the frozen witnesses contain **1,609 accepted moves and clear 2,583 food tokens**. These witnesses prove solvability, not shortest paths or human difficulty.

## Chapters and food introductions

| Chapter | Levels | Six foods and first appearances |
| --- | --- | --- |
| Garden Grill | 1–50 | Tomato 1; corn 2; mushroom 3; pepper 11; zucchini 21; eggplant 25 |
| Backyard Barbecue | 51–100 | Chicken drumstick 51; steak 56; prawn 61; fish fillet 66; sausage spiral 71; halloumi slice 76 |
| Breakfast Griddle | 101–150 | Fried egg 101; pancake stack 106; waffle square 111; toast slice 116; hash brown 121; croissant 126 |

Each new board uses four to six trays and a curated palette of at most six simultaneous foods, including familiar Garden ingredients where a recipe calls for them. The expansion retains empty-destination moves, identical triples, whole-row reveals and integer recipe batches. Sealed trays, chilled food and other later restrictions are not part of these levels.

Levels 31–150 follow a repeating **introduction → normal → variation → challenge → relief** rhythm. Introductions either welcome one food or offer a fresh shallow combination. Variations use deeper queues; challenges provide fuller layered boards; relief levels reduce the board and witness length. Recipe introductions happen on relief positions. This is a content pacing plan, not a claim that individual difficulty has been measured with players.

| Rhythm | Boards | Recorded moves | Median moves | Initial tokens |
| --- | --- | --- | --- | --- |
| Introduction | 24 | 3–8 | 5.5 | 9–12 |
| Normal | 24 | 9–17 | 12 | 18–21 |
| Variation | 24 | 10–22 | 14.5 | 21–24 |
| Challenge | 24 | 13–22 | 17 | 24–33 |
| Relief | 24 | 3–13 | 7.5 | 9–18 |

Queue depth ranges from one to four rows including the active row. Ordinary relief witnesses are capped at 12 moves; a relief introducing a recipe can use up to 18. All published witnesses remain below the normal 40-transaction Undo capacity.

## Twelve finite recipe bundles

Requirements count completed triples, never pieces or mixed-food trays. Future tickets retain Prepared credit. Every level preauthors its complete ticket list, and combined demand is checked against complete visible and queued inventory.

| Bundle | Required batches | First level |
| --- | --- | --- |
| Garden Sampler | Tomato ×1, corn ×1, mushroom ×1 | 15 |
| Charred Duo | Corn ×2, mushroom ×1 | 16 |
| Ratatouille Grill | Tomato ×1, pepper ×1, zucchini ×1, eggplant ×1 | 26 |
| Garden Banquet | One batch of each Garden food | 28 |
| Backyard Combo | Chicken drumstick ×1, corn ×1 | 55 |
| Surf and Turf | Steak ×1, prawn ×1, pepper ×1 | 65 |
| Seafood Grill | Fish fillet ×1, prawn ×1, zucchini ×1 | 70 |
| Smoky Platter | Sausage spiral ×1, halloumi ×1, mushroom ×1, pepper ×1 | 80 |
| Sweet Morning | Pancake stack ×1, waffle ×1 | 115 |
| Classic Breakfast | Fried egg ×1, toast ×1, hash brown ×1 | 125 |
| Bakery Basket | Croissant ×2, toast ×1 | 130 |
| Brunch Board | Fried egg ×1, hash brown ×1, tomato ×1, mushroom ×1 | 135 |

## Original progress stays valid

The bytes of `garden_001.json` through `garden_030.json`, including their content hashes, metadata and solution commands, are preserved. `data/levels/legacy_manifest.json` records their raw SHA-256 values and their original certificate hashes. `legacy_replay_report.json` is a byte-for-byte copy of the original thirty-level report. The combined `replay_report.json` retains those thirty certificate entries unchanged and appends the 120 new entries.

The unchanged original data keeps its Appendix D tray, food, depth and free-slot targets. Existing special witnesses still cover the first single-move match, temporary storage, automatic cascade, order completion before board clear, simultaneous reveal/match, and storage followed by retrieval. Save migration and access to level 31 are validated by the save/economy suites.

## Offline authoring pipeline

`tools/author_expansion.py` writes an explicit 120-entry plan and the eight additional recipes. The plan fixes each level's chapter, title, teaching text, palette, recipe demand, rhythm, exact tray/free-space/depth targets, batch inventory, seed and acceptable solution length. It verifies the old thirty files before doing any work.

`tools/author_expansion.gd` makes bounded candidates using the plan. Candidates have divisible inventories, stable starting rows and valid whole-row queues. Most queued prematches are rejected; a few variation positions permit automatic cascades. New candidates are compared against every accepted board, including the original thirty, under all food renamings, tray permutations and within-row slot permutations. Changing a palette or a ticket cannot disguise an existing layout.

The authoring tool solves candidates with the actual `PuzzleSolver` and `BoardModel`, then replays the entire witness on a fresh model before accepting anything. Search has a finite time budget; UNKNOWN candidates are rejected, not treated as solved. Every accepted board records its seed, selected candidate index, plan hash, structural signature and solution. The runtime only loads these frozen JSON files; it never generates campaign boards.

Fresh generation can select a different candidate near a search-time limit on another machine. Published files and proofs are authoritative. A rerun safely reuses existing valid candidates with matching plan hashes, so ordinary verification does not depend on machine speed. Human-readable JSON changes and replay reports should be reviewed together before publication.

## Verification and deliberate regeneration

Use Godot **4.7.2** from the project root:

```sh
godot --headless --path . --script res://tools/build_levels.gd
godot --headless --path . --script res://tests/level_tests.gd
```

`build_levels.gd` is now a **read-only verifier**: it checks all 150 frozen solutions and their intermediate state hashes without rewriting any content. The expanded content suite passes **16,626 checks**, covering all 150 production replays, rejected-command purity, every Undo checkpoint, independent Resource/model copies, exact authoring targets, global structural uniqueness, first appearances for all 18 foods and 12 recipes, recipe demand, chapter mapping, pacing bounds, and original file/certificate preservation.

To deliberately reauthor the additions:

```sh
python3 tools/author_expansion.py
godot --headless --path . --script res://tools/author_expansion.gd
godot --headless --path . --script res://tests/level_tests.gd
```

The first command prepares the expansion plan and recipe data. The second reuses matching accepted files or finds and certifies replacements. It leaves levels 1–30 untouched. If a planned level cannot be certified within the attempt budget, the report records failure and the command exits nonzero; do not publish that intermediate result. `tools/author_levels.py` remains the historical source for the first thirty boards and should not be rerun as part of expansion work.

Content hashes cover the entire authored dictionary, including the solution, except `content_hash` itself. Hash serialization uses `BoardModel.canonical_json()` to normalize integer-valued JSON numbers and sort keys. Runtime state hashes are computed after the normal typed Resource conversion.

## Human review still required

**Human pacing, enjoyment, first-time teaching and target-phone readability are pending.** Every new board records `human_playtest_status: pending`. Automated uniqueness and solvability do not prove that a strategy is forced, that a lesson is understood or that all boards feel different to a player.

Before treating the catalogue as launch-ready content, play through each chapter on the target phone and record completion time, Undo/Restart use, misdrops, food recognition and queue-preview comprehension. Review the full five-level rhythm, chapter transitions, recipe introductions and challenge/relief contrast. Revise plan entries when observation disagrees with the intended pacing, then recertify the changed boards.
