# Gawr Gura Mutation Mod

Adds a shark-girl mutation category inspired by Gawr Gura.

To make it more accurate on appearance, make sure to add:
- Eye color: blue
- Hair color: white
- Hair style: Gura
- Pale Skin

## New Content

| File | Count | What |
|---|---|---|
| `mutations.json` | 13 | Shark-themed mutations (FAST_REFLEXES_SAME, TAIL_SHARK, SHARK_BITE, SUMMON_TRIDENT, SHARK_CALL, SALT_WATER_AFFINITY, etc.) |
| `spells.json` | 1 | Awakened Trident Shockwave (cone attack during Shark Call) |
| `professions.json` | 1 | Gawr Gura starting profession |
| `items.json` | 3 | Gura's Trident, Shark Hoodie, Hood down ver. |
| `effects.json` | 1 | Shark Call buff effect (strength + speed scaling) |
| `dreams.json` | 4 | SAME category dreams (4 intensity tiers) |
| `mutagens.json` | 2 | SAME mutagen and SAME serum |
| `recipes.json` | 3 | Mutagen, serum, and shark hoodie crafting recipes |
| `categories.json` | 1 | SAME mutation category |
| `thresh_mutation.json` | 1 | Atlantean threshold mutation (THRESH_SAME) |
| `nested.json` | 1 | Nested mutation category config |
| `mutation_ordering.json` | 1 | Mutation ordering |
| `mod_tileset.json` | 1 | Mutation overlay sprites (8 tiles) |

## Modified Vanilla

| File | Count | What |
|---|---|---|
| `vanilla_mutations.json` | 15 | Vanilla mutations extended to SAME category (AMPHIBIAN, SEESLEEP, WATERSLEEP, FRESHWATEROSMOSIS, DEX_UP_4, etc.) |

## Lua Script

`preload.lua` handles custom mutation behaviors:
- **Trident Summon** — active toggle mutation, summons/fades Gura's Trident on command, (a)ctivate Gura's trident to riptide, windup time scales with distance
- **Shark Call** — one-shot timed buff; burns kcal for strength/speed scaling; auto-deactivates after use
- **Awakened Trident** — 35% chance to cast cone attack on melee hit while Shark Call is active
- **Shark Bite** — 20% chance on kill to heal all body parts by 1 HP if wounded
- **Cosmetic Mood System** — tail and expression overlays swap automatically
- **Salt Water Affinity** — heals all body parts by 1 HP every 5 minutes while wet
