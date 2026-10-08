# Implementation contract — Garden Table

First delivery: thirty offline campaign levels, six Garden Grill foods, four recipe bundles. Godot 4.7.2, Compatibility renderer. Later chapters, Rush and paid tools are roadmap scope.

## Shared APIs (frozen for parallel implementation)

`core/board_model.gd`, class_name `BoardModel`, extends RefCounted:
- `setup(level: Dictionary) -> void` initializes a fresh, stable authored level.
- `state: Dictionary`, `history: Array`, `last_events: Array` are instance-owned.
- `apply_move(source_tray: int, source_slot: int, target_tray: int, target_slot: int) -> bool` applies a legal atomic transaction, pushes undo, resolves all triples/reveals/orders. Invalid commands change nothing.
- `undo() -> bool`, `legal_moves() -> Array` of four-integer Arrays.
- `snapshot() -> Dictionary`, `restore(saved: Dictionary) -> void` for deep copies.
- `state_hash() -> String` full replay checksum; `search_key() -> String` excludes moves/batches/sequence/history.
- `is_won() -> bool`, `remaining_tokens() -> int`.

State keys: `level_id`, `trays`, `tickets`, `moves`, `batches`, `initial_total`, `outcome` (ready/won/recovery), `active_ticket_limit`. Tray: `id`, `front` (3 null/String food IDs), `queue` (Array of 3-entry rows). Ticket: `id`, `name`, `requirements` (food -> integer batches), `credits` (food -> integer), `served` bool. Ordered events dictionaries use `type`: moved/cleared/revealed/allocated/served/won; include `tray` integer and `food` for cleared/revealed as appropriate. `cleared` event includes `food`, `tray`, `event_id`.

Level JSON: `schema_version:1`, `content_version:1`, `level_id: garden_001`, `number`, `title`, `lesson`, `mode:campaign/campaign_orders`, `active_ticket_limit:1`, `trays`, `tickets`, `solution` (four-int move arrays). Food IDs: tomato, corn_cob, button_mushroom, bell_pepper_ring, zucchini_round, eggplant_slice.

`core/level_catalog.gd`, class_name `LevelCatalog`: static `load_level(number: int) -> Dictionary`, static `load_all() -> Array`. Convert validated authoring dictionaries into explicit typed Resource definitions internally, then provide independent runtime dictionaries to model. `core/level_validator.gd`, class_name `LevelValidator`: static `validate(level: Dictionary) -> Array` of error strings.

`core/solver.gd`, class_name `PuzzleSolver`: static `solve(model: BoardModel, budget_ms: int = 100) -> Dictionary` returns `status` SOLVED/UNKNOWN/UNSOLVABLE and `moves`. Same production resolver; no claim of shortest path.

`services/save_service.gd`, class_name `SaveService`, extends RefCounted: `data: Dictionary`, `load_save() -> bool`, `save_game() -> bool`, `commit_session(model: BoardModel, level: Dictionary) -> void`, `clear_session() -> void`, `reset_progress() -> void`. Envelope data keys: `schema_version`, `profile` {`unlocked`:int, `completed`:Dictionary, `coins`:int, `settings`:{`sound`:bool,`music`:bool,`haptics`:bool,`reduced_motion`:bool,`high_readability`:bool}}, `session` {`level_number`, `content_hash`, `state`, `history`} or {}. Completion recorded once per level; repeated replay cannot farm currency. Deep snapshots and profile in same verified temp/backup envelope.

`services/audio_service.gd`, class_name `GameAudio`, extends Node: `configure(settings: Dictionary)`, `play_cue(name: String)`, `set_music_active(active: bool)`. Cues select, move, invalid, match, reveal, serve, win, click. Original synthesized assets, no third-party audio.

UI owns flow, animation, pointer state and controls; it never counts a match independently. Content files `data/levels/garden_001.json` … `garden_030.json`; content includes proven no-tool solution commands. Assets `assets/food/food_atlas.png` (3 columns x 2 rows, equal cells; tomato, corn, mushroom / pepper, zucchini, eggplant) and `assets/backgrounds/restaurant.png`. Food renders use transparent backgrounds, UI crops via AtlasTexture.
