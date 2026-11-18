# ADR 006 - Skins = palette + one accessory part on a rig slot

Date: 2026-11-18. Status: accepted (skin list to be reviewed by the owner).

## Context

The owner wants two skins for each of the eight fighters, made of a palette plus an accessory (hat, scarf, glasses,
...) as an extra rig part. Existing looks are palette-only copies of all parts (`crab_sunset`, `octopus_midnight` on
the path; `crab_storm`, `octopus_storm`, `gull_storm` in the Storm Season). The styleguide says looks never change the
ring, outline, silhouette or size. The gull already uses the part name `accessory` for its beak. Skins must never give
power and must be obtainable without paying.

## Options

1. **Accessory as an extra joint on a named slot of the rig**, defined per look in `palette.json`, drawn by a shared
   accessory library in `tools/art`, with a generated manifest `data/looks.json` (pivot, parent, z, box). The base
   animal has no accessory part.
2. **An `accessory` part in every base rig**, hidden when no look is worn. Simpler cutout code, but every base animal
   carries an empty part and every look must supply one.
3. **Hand-drawn accessory SVGs** per look. More freedom, but art outside the script-only pipeline that CI checks.

## Decision

Option 1. Slots `top`, `face`, `neck` per animal; ten accessory kinds (crown, sunglasses, nightcap, captain_cap,
goggles, scarf, bow_tie, flower, sun_hat, souwester). Size cap: the accessory box covers at most 25 % of the body
box and stays inside the 200 x 200 animal space; never fully cyan or coral. The gull's beak is renamed to `mouth`.

Two permanent skins per fighter: one on the Treasure Path, one for silver mastery (`<animal>_golden`, golden palette
with a crown: a consistent "mastered" sign). Existing `crab_sunset` and `octopus_midnight` count as the path skins of
crab and octopus and gain an accessory. Seasonal looks are time-limited and therefore extras, not part of the two; the
three storm looks gain a matching sou'wester. Total: 16 permanent skins + 3 seasonal.

Option 2 is rejected because it adds an empty part to every animal and couples base rigs to skins. Option 3 is
rejected because it bypasses the generated-art check and the budgets.

## Consequences

- The styleguide rule "looks never change the silhouette" is relaxed to "small accessories within the cap"; the base
  silhouette stays recognisable and bots never wear looks.
- `Cutout.build` adds one joint when the manifest lists an accessory; otherwise unchanged.
- Mastery gets its first look reward (`mastery.json` `look_tier` and `looks`), granted in `apply_result` and by
  `Rewards.reconcile`.
- Players who own an existing look keep it and see it gain its accessory.
