# Cooking School

Cooking School is a short, interactive introduction with three frozen practice boards. It uses the normal `BoardModel` move, matching, reveal and recipe rules. It does not replace the campaign with a slideshow or restrict otherwise legal moves.

| Lesson | Guided moves | What the player does |
| --- | --- | --- |
| Your first little match | 2 | Bring three tomatoes together, then repeat with corn. |
| Another helping is waiting | 2 | Move a tomato while a remaining mushroom keeps the hidden row back; move the last mushroom out to reveal and automatically match the waiting corn. |
| A table for two orders | 3 | Make one corn batch, prepare peppers for the inactive next ticket, then make mushrooms to serve the first ticket and its already-prepared successor. |

All three JSON files are in `data/tutorials/`. They contain normal schema fields, three-slot trays, integer recipe requirements, a frozen legal solution and one useful instruction for each teaching move. `content_hash` is SHA-256 over `BoardModel.canonical_json()` of the authored dictionary excluding that hash field. The loader validates the schema and hash before converting the data through `LevelDefinition` Resources.

The guided route never asks the player to make an invalid move or a deliberate mistake. Cooking School also accepts alternative winning routes. Human first-time comprehension and target-device playtesting are still pending.

## Integration API

`services/tutorial_service.gd` defines `CookingSchool`, a `RefCounted` with static methods:

- `lessons() -> Array` returns three independent level dictionaries.
- `lesson(index: int) -> Dictionary` accepts **zero-based indices 0–2**. An unavailable index returns an empty dictionary. The data's `number` and `tutorial_step` are **one-based 1–3**.
- `instruction(index: int, model: BoardModel) -> Dictionary` inspects the current model without changing its state or undo history.

An instruction contains `title`, `body`, `source`, `target`, `progress`, `status` and `step`. `source` and `target` are `Vector2i(tray_index, slot_index)`. `status` is one of:

| Status | Coordinates | Meaning |
| --- | --- | --- |
| `guided` | A verified legal source and empty destination | The current puzzle state matches a step in the frozen teaching route. |
| `complete` | `Vector2i(-1, -1)` | The actual model has won, including on an alternative route. |
| `off_path` | `Vector2i(-1, -1)` | The player explored a different arrangement; offer normal play, Undo and Restart honestly. |
| `unavailable` | `Vector2i(-1, -1)` | The lesson or matching practice model is absent. |

`step` is the zero-based teaching move, the solution length for a completed lesson, or `-1` when no known teaching step applies. `progress` is player-facing text such as “Lesson 2 of 3 · Move 1 of 2.”

The service compares production `search_key()` values and remaps the source food and target vacancy when active slots have been permuted. It rechecks that the proposed move is legal on a copied production model. Unknown states never receive invented directions or a claim that a heuristic has found a solution. The player can undo to a known step, restart the small lesson, or complete it by exploring.

## Campaign and graduation

The tutorial service has no save, currency or entitlement dependencies. It neither writes a campaign session nor awards campaign-clear coins. The front end must keep practice models separate from the existing campaign model and session, and persist only school progress through the economy service:

- After lesson completion, call `EconomyService.set_tutorial_step(completed_step)`.
- Resume at the last incomplete zero-based lesson, capped to 0–2.
- On graduation, call the idempotent `EconomyService.complete_tutorial()`; the service owns the once-only reward.
- Leaving or restarting a practice board keeps campaign data intact. Practice hints, Undo and Restart are free.

The custom lesson tickets “First plate” and “Next plate” are small teaching orders, not additional campaign recipe-album unlocks.

## Verification

From the project root with Godot 4.7.2:

```sh
godot --headless --path . --script res://tests/tutorial_tests.gd
```

The suite currently passes **152 checks**. It validates and replays all frozen routes using the production resolver; verifies each returned highlighted move; permutes active slots and follows remapped guidance; checks that inspection does not mutate state/history; undoes every lesson transaction; exercises an off-path legal route through a win; checks full-row reveal timing and the automatic cascade; verifies a single batch from three pieces and actual Prepared credit before a future ticket activates; and confirms that running all practice boards leaves an in-progress campaign model untouched.

Save-file preservation, once-only graduation rewards and front-end navigation belong in the owning service/UI test suites. This module's passing model tests do not imply those integration checks or human phone playtesting have occurred.
