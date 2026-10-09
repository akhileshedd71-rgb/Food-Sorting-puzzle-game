#!/usr/bin/env python3
"""Prepare the explicit 31-150 curriculum and new recipes, never rewrite 1-30.

This offline authoring plan feeds author_expansion.gd. Published levels are
frozen JSON and witnesses, not layouts generated on a player's device.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GARDEN = ["tomato", "corn_cob", "button_mushroom", "bell_pepper_ring", "zucchini_round", "eggplant_slice"]
BARBECUE = ["chicken_drumstick", "steak", "prawn", "fish_fillet", "sausage_spiral", "halloumi_slice"]
BREAKFAST = ["fried_egg", "pancake_stack", "waffle_square", "toast_slice", "hash_brown", "croissant"]
NEW_RECIPES = [
    ("backyard_combo", "Backyard Combo", 2, 55, {"chicken_drumstick": 1, "corn_cob": 1}),
    ("surf_and_turf", "Surf and Turf", 2, 65, {"steak": 1, "prawn": 1, "bell_pepper_ring": 1}),
    ("seafood_grill", "Seafood Grill", 2, 70, {"fish_fillet": 1, "prawn": 1, "zucchini_round": 1}),
    ("smoky_platter", "Smoky Platter", 2, 80, {"sausage_spiral": 1, "halloumi_slice": 1, "button_mushroom": 1, "bell_pepper_ring": 1}),
    ("sweet_morning", "Sweet Morning", 3, 115, {"pancake_stack": 1, "waffle_square": 1}),
    ("classic_breakfast", "Classic Breakfast", 3, 125, {"fried_egg": 1, "toast_slice": 1, "hash_brown": 1}),
    ("bakery_basket", "Bakery Basket", 3, 130, {"croissant": 2, "toast_slice": 1}),
    ("brunch_board", "Brunch Board", 3, 135, {"fried_egg": 1, "hash_brown": 1, "tomato": 1, "button_mushroom": 1}),
]
RHYTHMS = ["introduction", "normal", "variation", "challenge", "relief"]
TITLE_STARTS = {
    1: ["Garden", "Greenhouse", "Orchard", "Sunlit"],
    2: ["Backyard", "Patio", "Fireside", "Picnic", "Ember", "Summer", "Sunset", "Courtyard", "Grillhouse", "Gathering"],
    3: ["Morning", "Daybreak", "Breakfast", "Golden", "Sunday", "Bakery", "Brunch", "Sunrise", "Honeylight", "Celebration"],
}
TITLE_ENDS = ["Welcome", "Table", "Turnabout", "Challenge", "Breather"]
FOOD_NAMES = {"chicken_drumstick": "Chicken Drumstick", "steak": "Steak", "prawn": "Prawn", "fish_fillet": "Fish Fillet", "sausage_spiral": "Sausage Spiral", "halloumi_slice": "Halloumi Slice", "fried_egg": "Fried Egg", "pancake_stack": "Pancake Stack", "waffle_square": "Waffle Square", "toast_slice": "Toast Slice", "hash_brown": "Hash Brown", "croissant": "Croissant"}


def write(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def main():
    manifest = json.loads((ROOT / "data/levels/legacy_manifest.json").read_text())
    for path, expected in manifest["files"].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, path
    for recipe_id, name, chapter, unlock, requirements in NEW_RECIPES:
        write(ROOT / "data/recipes" / f"{recipe_id}.json", dict(schema_version=1, id=recipe_id, name=name,
              name_key=f"recipe.{recipe_id}", chapter=chapter, unlock_level=unlock, requirements=requirements))
    recipes = [json.loads(path.read_text()) for path in sorted((ROOT / "data/recipes").glob("*.json"))]
    specs = []
    for number in range(31, 151):
        chapter = 1 if number <= 50 else 2 if number <= 100 else 3
        slug = ["garden", "barbecue", "breakfast"][chapter - 1]
        local = number - (30 if chapter == 1 else 50 if chapter == 2 else 100)
        group, phase = divmod(local - 1, 5)
        rhythm = RHYTHMS[phase]
        chapter_foods = GARDEN if chapter == 1 else BARBECUE if chapter == 2 else BREAKFAST
        starts = [1, 2, 3, 11, 21, 25] if chapter == 1 else [51, 56, 61, 66, 71, 76] if chapter == 2 else [101, 106, 111, 116, 121, 126]
        available = [food for food, unlock in zip(chapter_foods, starts) if unlock <= number]
        new_food = next((food for food, unlock in zip(chapter_foods, starts) if unlock == number), "")
        newly_served = next((r for r in recipes if int(r["unlock_level"]) == number), None)
        chapter_recipes = [r for r in recipes if r["chapter"] == chapter and int(r["unlock_level"]) <= number]
        selected_recipes = []
        if newly_served:
            selected_recipes = [newly_served]
        elif chapter_recipes and phase in (1, 4) and (group % 2 == 0 or phase == 4):
            selected_recipes = [chapter_recipes[(group + phase) % len(chapter_recipes)]]
        elif chapter_recipes and phase == 3 and group >= 5:
            selected_recipes = [chapter_recipes[group % len(chapter_recipes)]]
        # Later normal levels occasionally buffer two finite, already-known
        # tickets. Curate their combined palette before authoring inventory.
        if phase == 1 and group >= 6 and len(chapter_recipes) >= 2:
            pair = [chapter_recipes[group % len(chapter_recipes)], chapter_recipes[(group + 1) % len(chapter_recipes)]]
            if len(set().union(*(r["requirements"] for r in pair))) <= 6:
                selected_recipes = pair
        required = {}
        for recipe in selected_recipes:
            for food, batches in recipe["requirements"].items():
                required[food] = required.get(food, 0) + batches
        palette = list(required)
        if new_food and new_food not in palette:
            palette.append(new_food)
        introductory_kinds = 4 if chapter == 3 or (chapter == 2 and group >= 6) else 3
        kinds = max(len(palette), [introductory_kinds, 4 + group % 2, 4 + group % 3, 5 + group % 2, 3][phase])
        kinds = min(kinds, 6)
        # Keep new-chapter portraits prominent and bring Garden ingredients
        # back where a recipe or a small early chapter palette needs them.
        pool = available[group % len(available):] + available[:group % len(available)]
        pool += GARDEN[(group + phase) % 6:] + GARDEN[:(group + phase) % 6]
        for food in pool:
            if len(palette) >= kinds:
                break
            if food not in palette:
                palette.append(food)
        minimum_batches = sum(max(1, required.get(food, 0)) for food in palette)
        if phase == 0:
            trays = 4 if kinds == 3 else 5
            free = 3
            batches = max(minimum_batches, trays - 1)
            depth = 1 if batches == trays - 1 else 2
        elif phase == 1:
            trays = 5 + group % 2
            free = 3 if group % 2 == 0 else 6
            batches = max(minimum_batches, (trays * 3 - free) // 3 + 2)
            depth = 2 + group % 2
        elif phase == 2:
            trays, free = 6, 6
            batches = max(minimum_batches, 7 + group % 2)
            depth = 3 + group % 2
        elif phase == 3:
            trays, free = 6, 3
            batches = max(minimum_batches, 8 + group % 4)
            depth = 3 + group % 2
        else:
            trays = 4 if kinds <= 4 else 6
            free = 6 if trays == 4 else 9
            batches = max(minimum_batches, (trays * 3 - free) // 3)
            depth = 1 if batches == (trays * 3 - free) // 3 else 2
        queued_rows = batches - (trays * 3 - free) // 3
        depth = min(depth, 1 + queued_rows)
        assert queued_rows <= trays * (depth - 1)
        title = f"{TITLE_STARTS[chapter][group]} {TITLE_ENDS[phase]}"
        if new_food:
            title = f"Welcome, {FOOD_NAMES[new_food]}"
        elif newly_served:
            title = f"Today's {newly_served['name']}"
        if number in (50, 100, 150):
            title = ["A Garden Farewell", "The Backyard Celebration", "A Beautiful Breakfast"][chapter - 1]
        lessons = {
            "introduction": f"Meet {FOOD_NAMES.get(new_food, 'a fresh pairing')}. Find its matching shapes and take your time." if new_food else "A fresh combination of familiar food. Settle in and find your first match.",
            "normal": "Look at the waiting rows before making room. Every matching triple prepares one batch.",
            "variation": "A deeper helping is waiting. Use the previews to keep useful space between matches.",
            "challenge": "A little planning goes a long way. Keep room for the next row; Undo and Restart are always free.",
            "relief": "Enjoy a little breathing room. Finish this short serving at your own pace.",
        }
        if newly_served:
            lessons["relief"] = f"Serve {newly_served['name']} with matching food batches, then clear the last pieces from the counter."
        specs.append(dict(number=number, level_id=f"{slug}_{number:03d}", chapter=chapter,
                          title=title, lesson=lessons[rhythm], rhythm=rhythm, palette=palette,
                          recipe_ids=[r["id"] for r in selected_recipes], required_batches=required,
                          trays=trays, free_slots=free, batch_count=batches, max_rows=depth,
                          new_food=new_food, new_recipe=newly_served["id"] if newly_served else "",
                          min_solution_moves=10 if phase == 3 else 1,
                          max_solution_moves=18 if phase == 4 and newly_served else 12 if phase == 4 else 40,
                          seed=930031 + number * 104729, allow_cascade=phase == 2 and group % 3 == 1))
    write(ROOT / "data/levels/expansion_plan.json", dict(schema_version=1, generator_version=1,
          scope="120 offline generated and certified additions; frozen first thirty retained", levels=specs))
    print("Prepared 120 curriculum entries and 8 recipes. Run author_expansion.gd to certify candidates.")


if __name__ == "__main__":
    main()
