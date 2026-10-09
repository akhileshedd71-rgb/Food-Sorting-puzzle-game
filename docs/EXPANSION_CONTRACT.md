# Front-end and economy expansion contract

APIs used by the version 0.2 front end, local economy, and guided lessons.

## Currency and permanent profile

The single currency is **Chef Coins**. Keep current earned coins and completed levels. First campaign clears earn 30 as before; undo/restart and replay are free. The one-time welcome gift is 100 and Cooking School graduation earns 30. Hints cost 10, an extra tray costs 40 per run, Sage enamel costs 120, and Berry enamel costs 180. No random rewards or paid randomness. Coin packs (250/700/1600) appear in the shop with purchasing unavailable; no fake payment callbacks, ads, billing SDK or client-side 'paid' grants in this build.

`services/economy_service.gd` class_name `EconomyService`, RefCounted:
- `_init(store: SaveService)`; `initialize() -> Dictionary` idempotently creates/migrates economy/profile fields and welcome gift, persists.
- `balance() -> int`; constants HINT_COST=10, EXTRA_TRAY_COST=40, WELCOME_COINS=100, TUTORIAL_COINS=30.
- `buy_hint(model: BoardModel, level: Dictionary, budget_ms: int = 100) -> Dictionary`: result status `ok`, `insufficient`, `unknown`, `unavailable`, `save_failed`; successful `move` four-int Array and `charged` int. Finds full certified solution (stored replay then same bounded solver); remaps slot-equivalent states. Charges only if a legal verified hint is found. Re-request same exact puzzle state in same run returns same hint without another charge. Save debit+hint receipt in one transaction. Preserve cached move on restart/resume semantics by run ID. Zero cost during tutorial handled UI, not service.
- `buy_extra_tray(model: BoardModel, level: Dictionary) -> Dictionary` same statuses, once per run, eight trays; appends an empty tray. Save debit+grant+board atomically; rollback model/profile on save failure. Persist grant through undo. No grant when completed or already granted.
- `buy_theme(id: String) -> Dictionary`; `equip_theme(id: String) -> Dictionary`; `themes() -> Array` id/name/cost/rim/accent/owned/equipped metadata; IDs `classic`, `sage`, `berry`. User confirmation is UI.
- `complete_tutorial() -> Dictionary` once-only reward, marks profile tutorial.completed and step3. `set_tutorial_step(step:int)->bool` preserves max progress; `tutorial_step()->int`, `tutorial_complete()->bool`.

Profile extension defaults: tutorial {step:0,completed:false}; economy schema and version and ledger/idempotency sufficient for local durability; owned_themes:[classic]; active_theme:classic. Expose these fields through documented APIs. Paid entitlements must stay separate from reversible model history. Existing version 1 checksum files must migrate without reset; unknown future schema must be preserved/rejected. No new session reward from tutorial boards.

BoardModel session extension (economy/core owner): stable per-run ID; `extra_tray_granted:bool`; `grant_extra_tray()->bool` appends stable grant tray; `undo()` re-applies empty granted tray when restored snapshot predates grant, never copies current contents. Save validation permits exactly this additional tray and unchanged inventory/authored queues. Existing boards/search proofs remain unchanged unless grant used; avoid adding nonce fields to solver search keys.

## Tutorial module

`services/tutorial_service.gd` class_name `CookingSchool`, RefCounted, static `lessons()->Array` and `lesson(index:int)->Dictionary`. Three frozen solvable mini levels: identical triple, moving final item reveals row and automatic cascade, recipe batch + future Prepared credit. Each level has normal schema fields/title/lesson/trays/tickets/solution and `tutorial_step`; uses registered six food IDs. No new campaign level/reward. `instruction(index:int, model:BoardModel)->Dictionary` returns `title`, `body`, `source` Vector2i, `target` Vector2i and `progress` String based on current exact/puzzle-equivalent proof state. Hints guide; legal exploration is allowed. Unknown off-path offers honest undo/restart, not fake solution. Tests replay and assert taught semantics.

The application integrates tutorial mini boards without replacing/saving the current campaign session. Only tutorial-step completion is persisted. Exiting a lesson keeps campaign saves intact; resumed school starts its last incomplete mini lesson. Replay school available from title/home/settings. Completed tutorials never duplicate graduation coins. Tutorial hint/undo/restart free.

## Animation and reusable visuals

`scenes/ui/motion.gd` class_name `GardenMotion`, RefCounted, static helpers taking a Node owner (create_tween): `enter(control:Control,reduced:bool=false)->Tween`, `press(control:Control,reduced:bool=false)->Tween`, `pulse(control:Control,reduced:bool=false)->Tween`, `coin_burst(owner:Node, position:Vector2, amount:int,reduced:bool=false)->void`, `match_burst(owner:Node,position:Vector2,reduced:bool=false)->void`. Return null allowed reduced motion. No gameplay authority; kill stale tweens and mouse_filter IGNORE for particles. Original simple vector UI icons via custom Control are allowed; no need new generated art.

Screen assembly and input live in `scenes/main.gd` and `scenes/ui/front_end.gd`. Services retain rule and persistence ownership; animation callbacks never award coins or advance gameplay. The expansion UI suite verifies navigation, transactions, lesson progress, and responsive layout through these production APIs.
