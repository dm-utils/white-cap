# ADR 004 - Specials as a few reusable mechanics, identity as kind

Date: 2026-11-18. Status: accepted.

## Context

Five new fighters (pufferfish, otter, seal, hermit crab, starfish) need attacks and specials that are unique and fit
the animal, as described in the functional design: spines all around, a thrown shell, a pushing water jet, a short
poke, a returning star; inflating, a fast slide, a belly slide, hiding in the shell, a trap arm. The sim has one
projectile model and three special mechanics (dash, ink cloud, dive). The technical design asks for "a small number
of reusable types"; a new animal should mostly be data plus art.

## Options

1. **Squeeze everything into the existing three mechanics.** Least code, but hiding in a shell, inflating and a
   delayed trap cannot be expressed; the animals would feel like recoloured copies.
2. **One bespoke code path per animal.** Maximum freedom; eight special cases in the sim, the bots and the future
   C++ port.
3. **Separate mechanic (`mech`) from identity (`kind`)** and add only what is missing: two new mechanics (`guard`,
   `trap`), three flags on the dash (`intangible`, `refill`, damage/push 0) and two optional projectile fields
   (`push`, `back`). `kind` stays the key for text, sound and bot logic.

## Decision

Option 3. Mapping:

| Animal | Attack (projectile model) | Special kind -> mech |
|---|---|---|
| puffer | `spines`: 8 projectiles, spread 512 (full ring) | `puff` -> guard (grow, half damage, bounce) |
| otter | `shell`: single projectile | `slide` -> dash (no damage, intangible, refill) |
| seal | `jet`: single projectile with `push` | `belly` -> dash (long, huge push) |
| hermit | `poke`: short single projectile | `shell` -> guard (10 % damage, steady, no attack, slow) |
| star | `star`: projectile with `back` (boomerang) | `arm` -> trap (arm delay, trigger, fuse) |

Option 1 is rejected because it fails the "unique and fitting" requirement. Option 2 is rejected for its cost and
because it breaks the data-driven model.

## Consequences

- Sim changes are bounded (docs/design.md 4.2); every new piece of state is an integer in the hashed state.
- Future animals can reuse `guard` and `trap` with other numbers.
- Guard does not reduce water damage: the tide stays the main threat.
- The view needs two cutout poses (inflate, hide), a trap marker and two projectile shapes.
