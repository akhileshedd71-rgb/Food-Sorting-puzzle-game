# Original art and audio

All food and restaurant art below was generated specifically for Garden Table with OpenAI image generation. The supplied reference screenshots informed the warm casual puzzle aesthetic; no image pixels or branded assets were extracted from those screenshots. The generated art is supplied as part of this project and has no third-party attribution dependency.

| Asset | Format | Details |
| --- | --- | --- |
| `food/food_atlas.png` | 1536 × 1024 RGBA PNG | Original six-food atlas, three columns by two rows, equal 512 × 512 cells, transparent background. Generous alpha padding prevents neighboring sprites from entering a crop. |
| `food/barbecue_atlas.png` | 1536 × 1024 RGBA PNG | Six original Backyard Barbecue foods. Same three-by-two layout and 512-pixel cells; clean alpha and generous empty margins. |
| `food/breakfast_atlas.png` | 1536 × 1024 RGBA PNG | Six original Breakfast Griddle foods. Same three-by-two layout and 512-pixel cells; distinct silhouettes and interior patterns. |
| `backgrounds/restaurant.png` | 841 × 1870 RGB PNG | Original portrait cafe background. Sunlit garden cafe in upper 30%, horizontal counter rim, quiet honey wood playing surface in lower 70%. |

Atlas indices are zero based, read left to right:

| Index | Column, row | Food ID | Appearance |
| --- | --- | --- | --- |
| 0 | 0, 0 | `tomato` | Plump red tomato with green calyx |
| 1 | 1, 0 | `corn_cob` | Golden corn cob with green husk |
| 2 | 2, 0 | `button_mushroom` | Tan cap and ivory stem |
| 3 | 0, 1 | `bell_pepper_ring` | Orange-red hollow pepper ring |
| 4 | 1, 1 | `zucchini_round` | Pale green interior and dark green rind |
| 5 | 2, 1 | `eggplant_slice` | Long pale interior with purple rind |

Crop with `Rect2(column * 512, row * 512, 512, 512)` using `AtlasTexture`. Retain alpha and use linear filtering when drawing food at small sizes. The six silhouettes and interior patterns distinguish ingredients beyond hue alone. Food names and additional markers are supplied by the high-readability UI.

Version 0.3 adds the following original atlases, generated to match the first six foods. The original atlas was used as an art-style reference. A second image-generation pass corrected size and transparent padding; no sprites were extracted from the user's reference screenshots. The original Garden Grill atlas remains unchanged.

| Atlas | Index | Column, row | Food ID | Readability cue |
| --- | --- | --- | --- | --- |
| Barbecue | 0 | 0, 0 | `chicken_drumstick` | Golden teardrop ending in a pale two-knob bone |
| Barbecue | 1 | 1, 0 | `steak` | Broad irregular cut, pale rim and crossed grill marks |
| Barbecue | 2 | 2, 0 | `prawn` | Orange segmented open crescent with a split tail |
| Barbecue | 3 | 0, 1 | `fish_fillet` | Tapered salmon slab with broad white bands |
| Barbecue | 4 | 1, 1 | `sausage_spiral` | Brown continuous spiral with a protruding end |
| Barbecue | 5 | 2, 1 | `halloumi_slice` | Pale thick rectangle with three dark parallel stripes |
| Breakfast | 0 | 0, 0 | `fried_egg` | Wavy white perimeter and raised round yolk |
| Breakfast | 1 | 1, 0 | `pancake_stack` | Three round stacked layers with a square butter pat |
| Breakfast | 2 | 2, 0 | `waffle_square` | Square silhouette and nine deep grid cavities |
| Breakfast | 3 | 0, 1 | `toast_slice` | Two rounded top lobes, pale center and dark crust |
| Breakfast | 4 | 1, 1 | `hash_brown` | Jagged shredded edge around an oblong capsule |
| Breakfast | 5 | 2, 1 | `croissant` | Ridged crescent with inward-curving pointed ends |

Both expansion atlases were inspected at full resolution: alpha spans 0–254, every cell has a single food contained within its own 512-pixel region, and visible alpha bounds leave at least 90 pixels before the closest cell edge. The surrounding colored pixels visible in some raw-image viewers have zero alpha and do not appear in Godot.

A Godot-rendered contact sheet also reviewed all 18 identities at a 100-pixel slot texture extent and a 36-pixel queue-preview extent, against the actual neutral tray palette. A shader desaturated a second 100-pixel row for silhouette/pattern review. The new foods remained distinct through shape and broad internal markings, including the waffle grid, pancake layers, sausage spiral, prawn crescent and contrasting grill patterns. This is a desktop visual review; bright-screen phone readability still needs device testing.

Audio is synthesized by the project's audio service from original waveforms. No sampled commercial recordings are included.

Version 0.2 adds original vector UI artwork in `scenes/ui/coin_icon.gd` (an embossed leaf Chef Coin) and `scenes/ui/brand_mark.gd` (a plate and garden sprig). They are drawn from code, with no external images or attribution requirements. Enamel finishes recolor the existing tray view; all food identities retain their original art and readability.
