# ADR 002 - Bot memory and new mechanics as integer entity state

Date: 2026-11-18. Status: accepted.

## Context

The new bot layers need memory between ticks (target, fire gap, dodge, strafe timing) and the targets' recent
velocity. The new fighters need state too (guard timer, traps, projectile knockback and boomerang). Replays,
the replay check, golden traces and online rollback all depend on `snapshot()`/`restore()`/`state_hash()` covering
everything that influences the future.

## Options

1. **Integer fields on `MatchSim.Ent` / `Proj` and a new `Trap` list**, all added to the field lists that are hashed,
   snapshotted and restored. Bots keep drawing from `sim.rng`.
2. **A separate bot-state dictionary and a separate bot RNG stream** in `Match`. Keeps the sim lean, but snapshot,
   restore, hash and rollback would need a second mechanism, and online clients would have to sync it as well.
3. **Derive everything from the current state each tick** (no memory). No new state, but no reaction delay, no target
   commitment and no fire gap: bots would flicker between targets and act inhumanly fast.

## Decision

Option 1. New `Ent` fields: `guard`, `vx`, `vy`, `target`, `target_until`, `next_shot`, `reflex_at`, `dodge_until`,
`dodge_dir`, `strafe_until`, `engaged`; new `Proj` fields `push`, `back`; new `Trap` class with `TRAP_FIELDS`. `vx/vy`
are maintained by the sim (movement in the last tick), the rest by the bots. All integers.

Option 2 is rejected because it duplicates the determinism machinery. Option 3 is rejected because it makes bots feel
robotic and cannot express reaction time.

## Consequences

- Rollback and replays keep working without extra code; snapshots grow by a few integers per entity.
- The state hash layout changes; golden traces are re-recorded (ADR 003).
- The fields are part of the C++ port specification later.
