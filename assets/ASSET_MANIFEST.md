# Original art and audio

All food and restaurant art below was generated specifically for Garden Table with OpenAI image generation. The supplied reference screenshots informed the warm casual puzzle aesthetic; no image pixels or branded assets were extracted from those screenshots. The generated art is supplied as part of this project and has no third-party attribution dependency.

| Asset | Format | Details |
| --- | --- | --- |
| `food/food_atlas.png` | 1536 × 1024 RGBA PNG | Original six-food atlas, three columns by two rows, equal 512 × 512 cells, transparent background. Generous alpha padding prevents neighboring sprites from entering a crop. |
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

Audio is synthesized by the project's audio service from original waveforms. No sampled commercial recordings are included.

Version 0.2 adds original vector UI artwork in `scenes/ui/coin_icon.gd` (an embossed leaf Chef Coin) and `scenes/ui/brand_mark.gd` (a plate and garden sprig). They are drawn from code, with no external images or attribution requirements. Enamel finishes recolor the existing tray view; all food identities retain their original art and readability.
