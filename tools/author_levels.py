#!/usr/bin/env python3
"""Write the 30 deliberately authored Garden boards, then certify with Godot.

This is an authoring tool, never a runtime level generator. It has no randomness.
Run `python3 tools/author_levels.py` followed by the production-resolver
certification command documented in docs/LEVELS.md. This overwrites authored
level data; review the resulting JSON changes before publishing them.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOODS = dict(A="tomato", B="corn_cob", C="button_mushroom",
             D="bell_pepper_ring", E="zucchini_round", F="eggplant_slice")
RECIPES = {
    "garden_sampler": ("Garden Sampler", dict(A=1, B=1, C=1)),
    "ratatouille_grill": ("Ratatouille Grill", dict(A=1, D=1, E=1, F=1)),
    "charred_duo": ("Charred Duo", dict(B=2, C=1)),
    "garden_banquet": ("Garden Banquet", dict(A=1, B=1, C=1, D=1, E=1, F=1)),
}

# Each string is exactly three slots: _ means empty. Queue keys are zero-based
# tray indices and their ordered lists advance only after the whole front clears.
# Board shape, inventory and queue placement are designed individually.
BOARDS = [
    ("A Fresh Start", "Move the tomato into the empty space beside two tomatoes.",
     ["AA_", "A__"], {}, []),
    ("Corn on the Counter", "Only three identical foods clear. Choose an empty space.",
     ["AB_", "AAB", "B__"], {}, []),
    ("Mushroom Morning", "Tap a food, then tap an empty space on another tray.",
     ["AA_", "ABB", "BCC", "C__"], {}, []),
    ("Find Its Place", "Read each tray. The three empty spaces are spread around the board.",
     ["AB_", "AC_", "BC_", "ABC"], {}, []),
    ("A Little Breathing Space", "Use the empty tray to make room before your first match.",
     ["AAB", "BCC", "ABC", "___"], {}, []),
    ("Try, Then Undo", "Undo restores your last complete move, including any cleared food.",
     ["ABC", "AC_", "BB_", "AC_"], {}, []),
    ("Another Helping", "Clear the front row to bring the next row forward.",
     ["AA_", "AAB", "ACC", "B__"], {0: ["ABC"]}, []),
    ("Last Piece Out", "Moving the last piece out also reveals the next row.",
     ["A__", "AA_", "BCC", "BCC"], {0: ["BCC"]}, []),
    ("One Sweet Cascade", "A revealed row of three identical foods clears automatically.",
     ["AA_", "A__", "BB_", "B__"], {0: ["CCC"]}, []),
    ("Sunny Break", "Take your time. There is plenty of room on this counter.",
     ["AA_", "B__", "AC_", "BBC", "C__"], {}, []),
    ("A Ring of Pepper", "Meet the pepper ring. Match its hollow shape with two more.",
     ["AA_", "ABB", "BCC", "CDD", "D__"], {}, []),
    ("Shared Space", "Use temporary spaces to separate the mixed food before collecting a triple.",
     ["AB_", "CD_", "AD_", "ABC", "BCD"], {}, []),
    ("Two More Helpings", "Two trays have waiting rows. Check both before making space.",
     ["AA_", "BB_", "ABD", "ABD", "CD_"], {0: ["ABC"], 1: ["ABC"]}, []),
    ("A Peek Ahead", "The small row previews show what comes next. Tap a row badge to inspect.",
     ["AA_", "AB_", "BB_", "CC_", "D__"], {2: ["CDD"]}, []),
    ("The Garden Sampler", "Match 3 to prepare 1 batch. Serve the order and clear every tray.",
     ["AA_", "ABC", "BC_", "A__", "B__"], {0: ["AAC"]}, ["garden_sampler"]),
    ("Corn, Twice Please", "Charred Duo needs two corn batches: six corn pieces in all.",
     ["BB_", "BC_", "C__", "B__"], {0: ["BBC"]}, ["charred_duo"]),
    ("Two Tickets", "Future orders keep prepared batches. Both tickets are fixed from the start.",
     ["AA_", "ABB", "BC_", "B__", "C__"], {0: ["BBC"], 1: ["BBC"], 2: ["BCC"]},
     ["garden_sampler", "charred_duo"]),
    ("The Last Side Dish", "When the order is served, clear the remaining food to finish.",
     ["AA_", "ABB", "BCC", "CDD", "D__"], {4: ["DDD"]}, ["garden_sampler"]),
    ("Two Things at Once", "A move can reveal its source row and clear its destination together.",
     ["A__", "AA_", "ABC", "BDD", "BCD"], {0: ["ADD"], 3: ["ACD"]}, []),
    ("A Familiar Lunch", "Enjoy a short, familiar board before the next Garden ingredient.",
     ["AB_", "BC_", "CA_", "AB_", "C__"], {}, []),
    ("Zucchini Joins In", "The green rounds are zucchini. Find three to prepare their first batch.",
     ["AA_", "ABB", "BCC", "CDD", "DE_", "EE_"], {}, []),
    ("Three Courses Deep", "One tray has three rows. Read its count and inspect the queue.",
     ["AA_", "AB_", "AC_", "BD_", "CE_", "DE_"], {0: ["ABC", "ADE"]}, []),
    ("Room for Tomorrow", "Look ahead before a reveal. Keep useful space for the waiting food.",
     ["AAB", "ABB", "BCE", "CD_", "DE_", "EA_"], {0: ["ABC"], 1: ["ABD"]}, []),
    ("The Regular Order", "Serve a familiar Garden Sampler, then finish the extra sides.",
     ["AA_", "AB_", "AC_", "BC_", "BD_", "CD_"], {0: ["ADD"], 1: ["ADD"]}, ["garden_sampler"]),
    ("Aubergine Afternoon", "Meet the purple eggplant slice. Its matching pair is in the next row.",
     ["AB_", "ABB", "CCD", "DDE", "EEF", "C__"], {0: ["FFA"]}, []),
    ("Ratatouille Table", "Four different batches make Ratatouille Grill. Match each food separately.",
     ["AA_", "AD_", "DD_", "DE_", "EF_", "FA_"], {0: ["ADE"], 2: ["ADF"]}, ["ratatouille_grill"]),
    ("Set Aside, Come Back", "Use a temporary space, then retrieve that food as deeper rows arrive.",
     ["ABC", "AAB", "BBC", "CD_", "DE_", "EA_"], {0: ["ABC", "BCE"], 2: ["ACD"]}, []),
    ("A Table for Everyone", "Garden Banquet needs exactly one batch of each of the six Garden foods.",
     ["AA_", "ABB", "BCC", "C__", "DE_", "F__"], {0: ["DEF"], 3: ["DEF"]}, ["garden_banquet"]),
    ("Garden Challenge", "Plan your storage through the layers. Undo and Restart are always free.",
     ["ABD", "AAB", "BBC", "CC_", "DD_", "EA_"],
     {0: ["ABD", "CDE"], 2: ["ACD"], 4: ["BCE"]}, []),
    ("The Garden Celebration", "Serve the full Garden Banquet, clear the counter, and celebrate your chapter.",
     ["AA_", "AB_", "BC_", "CD_", "BE_", "FA_"],
     {0: ["ABC", "DEF"], 2: ["ABD"], 4: ["BEF"]}, ["garden_banquet"]),
]

TARGETS = [
    (2,1,1,3), (3,2,1,3), (4,3,1,3), (4,3,1,3), (4,3,1,3),
    (4,3,1,3), (4,3,2,3), (4,3,2,3), (4,3,2,6), (5,3,1,6),
    (5,4,1,3), (5,4,1,3), (5,4,2,3), (5,4,2,6), (5,3,2,6),
    (4,2,2,6), (5,3,2,6), (5,4,2,3), (5,4,2,3), (5,3,1,6),
    (6,5,1,3), (6,5,3,6), (6,5,2,3), (6,4,2,6), (6,6,2,3),
    (6,4,2,6), (6,5,3,3), (6,6,2,6), (6,5,3,3), (6,6,3,6),
]


def row(text):
    assert len(text) == 3
    return [FOODS.get(slot) for slot in text]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def main():
    for recipe_id, (name, ingredients) in RECIPES.items():
        write_json(ROOT / "data/recipes" / f"{recipe_id}.json", {
            "schema_version": 1, "id": recipe_id, "name": name,
            "name_key": f"recipe.{recipe_id}", "chapter": 1,
            "unlock_level": {"garden_sampler":15, "charred_duo":16,
                             "ratatouille_grill":26, "garden_banquet":28}[recipe_id],
            "requirements": {FOODS[key]: value for key, value in ingredients.items()},
        })
    for number, (title, lesson, fronts, queues, recipe_ids) in enumerate(BOARDS, 1):
        target_trays, target_foods, target_depth, target_free = TARGETS[number - 1]
        trays = [dict(id=f"tray_{i+1}", front=row(front),
                      queue=[row(r) for r in queues.get(i, [])])
                 for i, front in enumerate(fronts)]
        tickets = []
        for i, recipe_id in enumerate(recipe_ids):
            name, ingredients = RECIPES[recipe_id]
            tickets.append(dict(id=f"ticket_{i+1}", recipe_id=recipe_id, name=name,
                                requirements={FOODS[k]: v for k, v in ingredients.items()}))
        counts = {}
        for tray in trays:
            for r in [tray["front"], *tray["queue"]]:
                for food in r:
                    if food:
                        counts[food] = counts.get(food, 0) + 1
        assert len(trays) == target_trays, number
        assert len(counts) == target_foods, (number, counts)
        assert max(1 + len(t["queue"]) for t in trays) == target_depth, number
        assert sum(t["front"].count(None) for t in trays) == target_free, number
        assert all(count % 3 == 0 for count in counts.values()), (number, counts)
        assert not any(t["front"][0] and len(set(t["front"])) == 1 for t in trays), number
        level = dict(schema_version=1, content_version=1,
                     level_id=f"garden_{number:03d}", number=number, title=title,
                     title_key=f"level.garden_{number:03d}.title", lesson=lesson,
                     lesson_key=f"level.garden_{number:03d}.lesson", chapter=1,
                     mode="campaign_orders" if tickets else "campaign",
                     active_ticket_limit=1, timer_seconds=0, trays=trays,
                     tickets=tickets, solution=[],
                     authoring=dict(source="Development brief, Appendix D",
                                    expected_trays=target_trays, expected_foods=target_foods,
                                    expected_max_rows=target_depth, expected_free_slots=target_free,
                                    challenge=number == 29, relief=number in (10, 20),
                                    human_playtest_status="pending"))
        write_json(ROOT / "data/levels" / f"garden_{number:03d}.json", level)
    print("Authored 30 finite boards and 4 recipes. Run Godot certification next.")


if __name__ == "__main__":
    main()
