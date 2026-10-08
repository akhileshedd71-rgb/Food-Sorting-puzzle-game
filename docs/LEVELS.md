# Garden campaign content

The project includes **30 frozen, individually authored boards**, six food identities and four Garden recipe bundles. Every level matches the tray count, food variety, maximum row depth and initial free-space target in Appendix D of the supplied development brief. The running game loads this finite catalogue; it does not generate levels or inflate its count with reskinned boards.

All 30 boards have a stored legal no-tool solution, replayed using `core/board_model.gd`, the same resolver used by the game. `data/levels/replay_report.json` records content SHA-256 hashes, every intermediate runtime-state hash, move counts, revealed-row counts, batch totals and teaching-event witnesses. These are solvability witnesses, not shortest-path proofs. Automated content tests also canonicalize every layout under all food renamings, tray permutations and slot permutations, then reject duplicate puzzles.

Human difficulty, pacing and touch-device review are **pending**. Machine validation does not establish that every intended strategy is forced or that a first-time player understands the lesson. In particular, levels 12, 13, 23 and 27 expose the intended storage/queue decisions, but their human teaching quality still needs observation. The recorded level 27 solution includes temporary storage followed by later retrieval; alternate routes are permitted.

## Campaign

“Rows” is maximum depth including the active row. “Free” counts empty active positions at the start. Move counts below describe the recorded witness, not a difficulty rating.

| Level | Title | Trays | Foods | Rows | Free | Replay moves |
| --- | --- | --- | --- | --- | --- | --- |
| 1.0 | A Fresh Start | 2.0 | 1.0 | 1.0 | 3.0 | 1 |
| 2.0 | Corn on the Counter | 3.0 | 2.0 | 1.0 | 3.0 | 3 |
| 3.0 | Mushroom Morning | 4.0 | 3.0 | 1.0 | 3.0 | 3 |
| 4.0 | Find Its Place | 4.0 | 3.0 | 1.0 | 3.0 | 6 |
| 5.0 | A Little Breathing Space | 4.0 | 3.0 | 1.0 | 3.0 | 5 |
| 6.0 | Try, Then Undo | 4.0 | 3.0 | 1.0 | 3.0 | 5 |
| 7.0 | Another Helping | 4.0 | 3.0 | 2.0 | 3.0 | 5 |
| 8.0 | Last Piece Out | 4.0 | 3.0 | 2.0 | 3.0 | 6 |
| 9.0 | One Sweet Cascade | 4.0 | 3.0 | 2.0 | 6.0 | 2 |
| 10.0 | Sunny Break | 5.0 | 3.0 | 1.0 | 6.0 | 4 |
| 11.0 | A Ring of Pepper | 5.0 | 4.0 | 1.0 | 3.0 | 4 |
| 12.0 | Shared Space | 5.0 | 4.0 | 1.0 | 3.0 | 8 |
| 13.0 | Two More Helpings | 5.0 | 4.0 | 2.0 | 3.0 | 10 |
| 14.0 | A Peek Ahead | 5.0 | 4.0 | 2.0 | 6.0 | 4 |
| 15.0 | The Garden Sampler | 5.0 | 3.0 | 2.0 | 6.0 | 6 |
| 16.0 | Corn, Twice Please | 4.0 | 2.0 | 2.0 | 6.0 | 4 |
| 17.0 | Two Tickets | 5.0 | 3.0 | 2.0 | 6.0 | 7 |
| 18.0 | The Last Side Dish | 5.0 | 4.0 | 2.0 | 3.0 | 4 |
| 19.0 | Two Things at Once | 5.0 | 4.0 | 2.0 | 3.0 | 12 |
| 20.0 | A Familiar Lunch | 5.0 | 3.0 | 1.0 | 6.0 | 6 |
| 21.0 | Zucchini Joins In | 6.0 | 5.0 | 1.0 | 3.0 | 5 |
| 22.0 | Three Courses Deep | 6.0 | 5.0 | 3.0 | 6.0 | 13 |
| 23.0 | Room for Tomorrow | 6.0 | 5.0 | 2.0 | 3.0 | 12 |
| 24.0 | The Regular Order | 6.0 | 4.0 | 2.0 | 6.0 | 9 |
| 25.0 | Aubergine Afternoon | 6.0 | 6.0 | 2.0 | 3.0 | 13 |
| 26.0 | Ratatouille Table | 6.0 | 4.0 | 2.0 | 6.0 | 10 |
| 27.0 | Set Aside, Come Back | 6.0 | 5.0 | 3.0 | 3.0 | 17 |
| 28.0 | A Table for Everyone | 6.0 | 6.0 | 2.0 | 6.0 | 9 |
| 29.0 | Garden Challenge | 6.0 | 5.0 | 3.0 | 3.0 | 14 |
| 30.0 | The Garden Celebration | 6.0 | 6.0 | 3.0 | 6.0 | 18 |

## Four finite recipe bundles

Requirements count completed triples, never individual pieces or mixed rows.

| Bundle | Batches | Introduced |
| --- | --- | --- |
| Garden Sampler | Tomato ×1, corn ×1, mushroom ×1 | 15 |
| Charred Duo | Corn ×2, mushroom ×1 | 16 |
| Ratatouille Grill | Tomato ×1, pepper ×1, zucchini ×1, eggplant ×1 | 26 |
| Garden Banquet | One batch of each of the six Garden foods | 28 |

Level 17 preauthors two tickets. Future-ticket batches are credited by the production allocator even before that ticket becomes active. Level 18's stored replay serves the order while food remains, demonstrating the separate board-clear goal. Levels 28 and 30 use Garden Banquet; the former contains exactly one batch of each food, while the capstone contains additional food to clear.

## Reproduce verification

Use Godot **4.7.2** from the project root:

```sh
godot --headless --path . --script res://tests/level_tests.gd
```

The content suite currently performs 1,880 assertions: schema and inventory validity; exact authoring targets; structural uniqueness; content hashes; independent Resource/runtime copies; legal stored moves; stable checksums after each move; rejected-command purity; every undo checkpoint; board/ticket completion; and the key tutorial events. Core rule fixtures are tested separately by `tests/core_tests.gd`.

To deliberately reauthor and recertify content:

```sh
python3 tools/author_levels.py
godot --headless --path . --script res://tools/build_levels.gd
godot --headless --path . --script res://tests/level_tests.gd
```

The first command rewrites all authored JSON from the explicit board definitions in the Python file and clears their certificates. The second uses the production solver and resolver to produce solutions and machine replay reports; it exits nonzero if any board cannot be certified. The final command independently replays the resulting saved catalogue. Review all content/report diffs together. Do not publish the intermediate uncertified output.

`tools/build_levels.gd` searches for solutions within a finite budget, using deliberate short tutorial openings for levels 1, 7, 8, 9, 19 and 27. A search limit yields UNKNOWN rather than claiming a board is impossible. Solving is an offline authoring step; frozen witnesses are shipped in each JSON file. No search budget affects the truth of the replay checks.

Content hashes cover the entire authored dictionary, including its solution, except the `content_hash` field itself. Hash serialization uses `BoardModel.canonical_json()` to normalize integer-valued JSON numbers and sort keys. The typed `LevelDefinition` conversion then creates independent runtime data; replay state hashes cover that runtime representation.

## Human review still required

Play every level on the target phone before treating this as launch-ready content. Record first-time comprehension, completion time, resets, undo use, misdrops and food recognition. Pay particular attention to queue previews, the first recipe and prepared future credits, the tighter temporary-storage boards, and the jump into the level 29 challenge. Review moves on 360–430 CSS-pixel-equivalent portrait widths and long/tall phones. Revise layouts when observations disagree with the lesson, then recertify with the commands above. No human review is claimed by the JSON's `human_playtest_status: pending` field.
