# ADR 001 - Layered utility bot brain with committed targets

Date: 2026-11-18. Status: accepted.

## Context

The owner reports that bots are "sitting ducks". Analysis of `bots/bot_brain.gd` (docs/design.md 3.1) shows the
causes are structural, not only numeric: attacks can only happen on think ticks, the attack chance starts at a quarter
of `aggression_pct`, the goal picker actively pushes bots away from each other and usually prefers the current spot,
"engaging" only circles, aim has no lead and nothing dodges. Bots must become lively and believable while staying
deterministic (sim RNG, state on the entity) for replays, the leaderboard replay check and online rollback.

## Options

1. **Tune the numbers only** (higher `aggression_pct`, shorter `think_ticks`, smaller repulsion). Cheap, but the
   structure stays: no approach, no lead, no dodge, attack chance still tied to think ticks.
2. **Behaviour tree / state machine per animal.** Expressive, but much more code per animal, harder to keep
   deterministic and portable to the planned C++ port, and eight animals would multiply it.
3. **Layered utility AI**: a per-tick reflex layer (dodge), a plan layer on think ticks (tide, committed target,
   goal spot, special), and per-tick move and fire layers. Animal differences come from a small style table in data
   plus one special-use function per special kind.

## Decision

Option 3. `BotBrain.think` keeps its signature; layers as specified in docs/design.md 3.5. Targets are committed for
2-4 seconds, picked by distance, weakness, revenge and in-range, with a cap on bots per target; no term depends on
whether the target is human. Difficulty is expressed in `data/bots.json` (reaction, dodge chance, lead, aim error,
fire gap, charge reserve, special use, tide look-ahead, damage).

Option 1 is rejected because it cannot produce approach, dodging or leading. Option 2 is rejected for its code size per
animal and the portability cost.

## Consequences

- Bots attack, chase, kite, dodge and fight each other; the tide stays a factor through safety scoring and look-ahead.
- More work per tick: the threat scan is capped (24 projectiles) and the cost is budgeted (at most 2x the old
  `ms_per_1000_ticks`).
- Golden traces and recorded replays change (ADR 003).
- Measurable acceptance via a new metrics tool (`tests/bot_metrics.tscn`), docs/design.md 7.2.
- `BallBrain` reuses the reflex, lead and special helpers.
