# ADR 008 - Separate bot damage against humans, per level

Date: 2026-11-18. Status: accepted (owner decision 2026-11-18: challenge for the player has priority).

## Context

After step a2 (ADR 001) bots fight actively. With the damage proposed in 3.3 (60-100 %) all-bot matches ended in
20-25 s, so `damage_pct` was lowered to 22-50 % to meet the bot-vs-bot duration targets of docs/design.md 7.2. The
same number also scales what a bot does to the player, so the scripted test player (100 % damage) now wins far too
easily: average place easy 1.20, normal 1.15, hard 1.72. The difficulty ladder (normal >= easy + 0.4, hard >= normal +
0.3) is missed, and "hard" is not hard. One knob serves two goals that pull in opposite directions.

Constraints: the sim is deterministic (integers, `sim.rng`, all state in `ENT_FIELDS`); bot behaviour must stay
blind to whether a target is human (ADR 001, fairness and believability); online rooms mix humans and bots and every
client must compute the same; Strandbal KOs fell to 0.1 per match with the low damage.

## Options

1. **Two damage percentages per bot, chosen at hit time by the victim** (`damage_pct` against bots,
   `human_damage_pct` against humans, `victim.is_bot == 0`). Projectiles, dives and traps carry the unscaled base
   damage; the sim scales on impact. Bot behaviour unchanged.
2. **One damage number, restore it to 60-100 % and slow the bots down instead** (longer fire gap, worse aim). Loses the
   lively, aggressive bots the owner asked for in the same round, and slower bots are also less dangerous to the
   player, so the ladder still is not met.
3. **Victim-side factor** (humans take more damage, or bots take less damage from humans). "Humans take more" also
   raises human-vs-human damage in online PvP; "bots take less from humans" makes the player's hits feel weak and
   lengthens every match with a human.
4. **Bots behave differently towards humans** (better aim, more focus on the player). Breaks the target-blind rule of
   ADR 001; ganging up on the player feels unfair and is exactly what `human_focus_pct` guards against.
5. **More bot HP.** Affects bot-vs-bot and bot-vs-human alike; does not separate the two goals.

## Decision

Option 1.

- New level fields in `data/bots.json` (version 3): `human_damage_pct` (normal mode), `ball_damage_pct` and
  `ball_human_damage_pct` (Strandbal; default to the normal-mode values when absent). New optional style field
  `human_damage_pct` (default 100); the existing style `damage_pct` keeps acting on bot-vs-bot damage only.
- New integer entity field `human_damage_pct` (default 100, hashed and snapshotted). Humans keep 100 in both fields,
  so damage by humans (and human-vs-human in PvP) is unchanged.
- One sim helper scales every entity-caused damage: `base * (src.human_damage_pct if victim.is_bot == 0 else
  src.damage_pct) / 100`. Water damage is never scaled.
- Online rooms use the same level table (the room's level). A player who leaves becomes a bot and from that tick
  gets bot damage values, set through one helper used by `Match.create`, `create_online`, `to_bot` and the rollback.
- The scripted test player gets two additional, deterministic skill profiles (casual, skilled) so the ladder is measured
  against something closer to a human than a perfect-aim turret; the legacy profile stays for golden data.

Option 2 is rejected because it trades away liveliness and still does not separate the goals. Option 3 is rejected
because it changes PvP or weakens the player's own hits. Option 4 is rejected by ADR 001. Option 5 is rejected because
it does not separate anything.

## Consequences

- Bot-vs-bot balance and the player's challenge can be tuned independently; all-bot metrics stay byte-identical to a2
  as long as bot-vs-bot values are untouched (acceptance check for the implementation).
- The rule "everyone deals the same damage" no longer holds for bots: a bot hits the player harder than it hits another
  bot. This is invisible to players (no damage numbers are shown) and is the usual difficulty handicap of games.
- In an online room every human gets the same bot damage, so fairness between humans holds; human-vs-human damage stays
  100 %.
- Projectile/dive/trap `damage` now holds the unscaled base damage: the state hash changes and golden traces and the
  replay fixture are re-recorded once (ADR 003).
- Two more numbers per level to tune; targets in docs/design.md 7.2 (ladder per test player profile, early-out share,
  Strandbal KOs) make the tuning measurable.
- The test player remains a proxy; the owner playtest (A-B5) stays the final judge of "hard is really hard".
