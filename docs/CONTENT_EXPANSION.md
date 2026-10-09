# Version 0.3 content expansion

Scope: 150 campaign levels, 18 food identities, and 12 recipe bundles across Garden Grill, Backyard Barbecue, and Breakfast Griddle. This update expands the existing untimed, unrestricted sorting rules. Sealed/chilled trays remain future mechanics. Levels 1–30 and their existing replay certificates must remain unchanged, including metadata and content hashes, so older sessions keep working.

## Shared content API

`LevelCatalog.LEVEL_COUNT = 150`; `level_id(number)` and `level_path(number)` map 1–50 to `garden_%03d`, 51–100 to `barbecue_%03d`, and 101–150 to `breakfast_%03d`. Invalid numbers return empty strings. `chapters()` returns independent dictionaries with `id`, `slug`, `name`, `start`, `end`, `subtitle`, and `foods`. `chapter_for_level(number)` returns the matching dictionary; `chapter(id)` returns one by its one-based ID. Chapter metadata is separate from loaded level dictionaries. `load_level`, `load_all`, and `load_recipes` retain their existing contracts.

`FoodCatalog.unlock_level(id)` returns the first authored appearance. The original six IDs unlock at 1, 2, 3, 11, 21, and 25. Additional catalog fields must not alter existing level dictionaries. `FoodCatalog.slot_label(id)` uses an optional short `slot_label` for tray labels, falling back to the full display name; collection and selection text retain full names.

| Chapter | Food IDs in atlas row order | First appearance |
| --- | --- | --- |
| Backyard Barbecue | chicken_drumstick, steak, prawn, fish_fillet, sausage_spiral, halloumi_slice | 51, 56, 61, 66, 71, 76 |
| Breakfast Griddle | fried_egg, pancake_stack, waffle_square, toast_slice, hash_brown, croissant | 101, 106, 111, 116, 121, 126 |

New transparent atlases are `assets/food/barbecue_atlas.png` and `assets/food/breakfast_atlas.png`: 3 columns × 2 rows, expected 512-pixel cells; confirm actual dimensions before wiring AtlasTexture regions. Existing art stays unchanged.

New recipes follow Appendix C: Backyard Combo (55), Surf and Turf (65), Seafood Grill (70), Smoky Platter (80), Sweet Morning (115), Classic Breakfast (125), Bakery Basket (130), and Brunch Board (135). Demand must be covered by the complete inventory, including repeated batches and multiple tickets.

## Content and compatibility requirements

New boards use curated palettes of at most six foods, four to six trays, explicit queues and a five-level introduction/normal/variation/challenge/relief rhythm. All 150 must have unique structures under food renaming, tray permutation, and within-row slot permutation. Every published board needs a replay verified through the production resolver. A timeout rejects a candidate rather than claiming it is solvable. Freeze accepted boards; no generation runs on a player's device. Human pacing and device readability still require playtesting.

Save schema 2 remains compatible. A profile that completed level 30 must gain access to 31 without another reward or any loss of wallet, tutorial, cosmetics, active board, run ID, extra tray, undo history, or hint receipts. Campaign identity checks use the catalog mapping.
