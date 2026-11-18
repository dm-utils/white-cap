# ADR 005 - Data-driven roster, two free newcomers, earlier unlocks with retroactive grants

Date: 2026-11-18. Status: accepted (free picks to be confirmed by the owner).

## Context

The owner decided that two of the five new fighters are free from the start and the other three come as path
rewards, much earlier than now (puffer 250, otter 850, seal 1400, hermit 2100, star 3000 pearls). The free-to-play
rule stays: never sell power. The code hard-codes the three slice animals (`Match.SLICE_ANIMALS`) for bots, the daily
animal, the replay check and the match fallback. Existing profiles may already be past some thresholds.

## Options for the free pair

1. **Otter + hermit crab.** One water, one land animal, so the free roster is balanced 2 land / 2 water / 1 flyer.
   Both have the simplest kits (throw + escape; poke + hide), friendly for new and young players. The flashier kits
   (puffer inflate, seal push-into-the-sea, starfish traps) stay as goals on the path.
2. **Puffer + hermit crab.** Two tanks: forgiving, but the puffer is the iconic first reward and its spines ring is
   less intuitive.
3. **Seal + starfish.** Most spectacular, but the hardest to play well and the strongest motivation to keep playing
   would be given away.

## Options for unlocking

A. Keep `Rewards.walk` only (grants when a match crosses a threshold). Players already past a moved threshold would
   never receive the reward.
B. **Add `Rewards.reconcile(profile)`**: grant free animals, every path reward at or below the pearl total, and
   mastery looks reached; idempotent, applied in `Platform.load_profile()`.

## Decision

Free pair: option 1 (otter + hermit). Unlocking: option B. New path: puffer 150, seal 350, star 550 (about 4, 9 and
14 matches). The roster is read from `data/animals.json` (`Match.roster()`, field `free`). Bots pick from all eight.
The daily challenge picks from all eight, including animals the player has not unlocked yet: a free try-out, not
power, and everyone plays the same animal that day.

Option 2 and 3 are rejected for the reasons above; option A is rejected because it silently skips rewards.

## Consequences

- Profiles are corrected on load without a migration step; the cloud merge (union of unlocked items) is unaffected.
- `in_slice` disappears from `animals.json`; tests and code use `roster()`.
- The online relay in st33f-engine still lists only three animals; until it is updated new animals fall back to
  crab online (follow-up, needs a deploy approved by the owner).
