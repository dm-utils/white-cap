# Whitecap - design

Status: change round 2026-11-18 (bots, five new fighters, skins, tagline); bot damage against humans split from
bot-vs-bot damage (ADR 008, step a3).
The original design documents (Dutch, outside this repo) remain the background: functional design, technical design,
styleguide and phase plans. This file summarises the parts of the existing architecture that matter for this round
and specifies the changes. Decisions are recorded in `docs/adr/`. Terms are in `docs/glossary.md`, conventions in
`docs/conventions.md`.

Contents

1. Existing architecture (summary)
2. Change 1 - tagline "Survival of the driest!"
3. Change 2 - bots that fight (3.9: damage against humans)
4. Change 3 - five new fighters
5. Change 4 - two skins per fighter
6. Work breakdown for the developer (steps a-c)
7. Test plan and acceptance (for the tester)
8. Owner input, costs, resources
9. Risks and follow-up work

---

## 1. Existing architecture (summary)

Godot 4.7.2, GDScript, Compatibility renderer. Targets: web (main), Windows, Android test build.

```
 input (keys/mouse/touch)        bots (BotBrain / BallBrain)
          | commands                    | commands
          v                             v
 +-----------------------------------------------------------+
 | MatchSim (sim/match_sim.gd): pure, deterministic, ints    |
 | 30 Hz tick, SimRng (xorshift32), milli-tiles, 0..4095     |
 | state: ents, projs, snacks, clouds, dives (+ ball)        |
 | out: events, state_hash(), snapshot()/restore(), result() |
 +-----------------------------------------------------------+
          | read only
          v
 view (view/match_view.gd, view/cutout.gd, view/fx_draw.gd), HUD, sound
 Platform autoload (profile, rewards, leaderboards, online relay)
```

Key facts the developer must keep intact:

- **Determinism.** No floats, no `randf`, no clock in `sim/` and `bots/`. All randomness from `sim.rng`. Bots run
  inside `Match.step()` in entity-id order and keep all memory as integer fields on `MatchSim.Ent`. Everything that
  can affect the future is in `ENT_FIELDS`/`PROJ_FIELDS`/... so `state_hash()`, `snapshot()` and `restore()` cover it.
  This is what makes replays (`sim/replay.gd`), the leaderboard replay check (`tools/verify/`), online rollback
  (`sim/rollback.gd`) and golden traces work.
- **Commands.** `{m: move angle, a: attack angle, s: special angle, sd: special distance}`, -1 = none.
- **Content is data.** `data/animals.json` (stats, attack, special), `data/rules.json` (tide, ground speed, charges,
  regen, snacks), `data/bots.json` (difficulty levels), `data/path.json` (Treasure Path), `data/seasons.json`,
  `data/mastery.json`, `data/palette.json` (colours of animals and looks), `data/modes/ball.json` (Strandbal overrides).
- **Attack.** Every attack fires `count` projectiles with `spread`, `speed`, `life`, `damage`, `radius`. Range =
  `speed * life`. 3 charges, recharge 29 ticks per charge, cooldown 8 ticks. Each projectile hit adds 1 to
  `special`; the special is ready at 4.
- **Specials today.** `dash` (crab: move fast, damage + push whoever is touched), `ink` (octopus: slowing cloud),
  `dive` (gull: delayed area blast at a point).
- **Art.** `tools/art/animals.py` draws every animal as cutout parts (SVG per part) from code and writes
  `assets/animals/<id>/<part>.svg` and `data/rigs/<id>.json`. A look = the same parts recoloured from
  `palette.json` into `assets/looks/<look>/`. `view/cutout.gd` builds a node per part from the rig and animates in
  code. CI regenerates art and fails on a diff. Budgets: `tools/check_budgets.py`.
- **Progress.** `ui/result_screen.gd::apply_result` adds pearls and walks `path.json` with `Rewards.walk`/`grant`;
  season pearls in parallel (`platform/season.gd`); mastery counters per animal (`platform/mastery.gd`). Looks:
  `profile.looks.owned` and `profile.looks.equipped[animal]`. Only the player wears a look in a match; bots never.
- **Bots pick animals** from `Match.SLICE_ANIMALS` (`crab`, `octopus`, `gull`); the same constant gates the daily
  animal, the replay check and the match fallback.
- **Tests.** `tests/run_tests.tscn` (headless, CI, 300 s timeout), `tests/balance.tscn` (all-bot balance),
  `tests/ball_balance.tscn`, golden traces in `tests/golden/traces.json`, recorded replays in
  `tests/golden/replays_recorded.json` (was `replays_windows.json` before a2).

---

## 2. Change 1 - tagline "Survival of the driest!"

Decision: ADR 007. The game stays **Whitecap**; the line under the title on the boot screen, which today reads
"working title", becomes the tagline **"Survival of the driest!"**, identical in English and Dutch.

| File | Change |
|---|---|
| `i18n/strings.csv` | Remove key `BOOT_WORKING_TITLE`; add `BOOT_TAGLINE,Survival of the driest!,Survival of the driest!` |
| `ui/boot_screen.gd` | `sub.text = tr("BOOT_TAGLINE")` (rename the variable to `tagline`) |
| `tools/i18n_add_nl.py` | Replace the `BOOT_WORKING_TITLE` entry by `"BOOT_TAGLINE": "Survival of the driest!"` |
| `web/shell.html` | Under `<h1>WHITECAP</h1>` in the loader add `<p class="tag">Survival of the driest!</p>` (styled like `.msg`, white) |
| unchanged | `TITLE`, `project.godot` name, export names, package id |

Acceptance (A-T):
- A-T1 The boot screen shows "WHITECAP" with "Survival of the driest!" below it, in English and in Dutch (`lang=nl`).
- A-T2 No file in the repo contains `BOOT_WORKING_TITLE`, "working title" or "werktitel" (grep, excluding `.git`).
- A-T3 `test_every_text_key_exists` and `test_every_language_complete` pass.
- A-T4 The web loader shows the tagline under WHITECAP.

---

## 3. Change 2 - bots that fight

### 3.1 Why the bots are sitting ducks (analysis of `bots/bot_brain.gd`)

1. **Attacks only on think ticks.** `cmd.a` is only set inside the `next_think` block (every 12-15 ticks on easy).
   Every other tick the bot cannot attack at all.
2. **Very low attack chance.** `aggression = aggression_pct * (span + 3*urgency) / (4*span)`. With span 7 this is a
   quarter of `aggression_pct` at the start: easy 10 %, normal 15 %, hard 20 %, rising by only a few percent per
   tide phase (25 s). The attack roll uses `max(aggression, 15 if nd < 3500 else 0)`, so outside 3.5 tiles an easy bot
   fires on about 1 in 10 think ticks: roughly 0.2 attacks per second, and only while a target is in range.
3. **Bots walk away from each other.** `_pick_goal` subtracts up to 150 points for every animal within 6 tiles of a
   candidate spot, weighted by `(span - urgency)/span`, i.e. at full strength at the start. There is no term that pulls
   a bot towards an opponent. Bots spread out over the high ground and only meet when the tide squeezes them together.
4. **Standing still wins the goal pick.** Sample 0 is the bot's own position with `r = 0`; all other samples pay
   `r/100`. With the repulsion above the current spot usually scores best, so `goal == position`, `gd <= 300`, and
   the bot does not move.
5. **"Engaging" never closes the gap.** `strafe` is non-zero only with probability `aggression` per think, and the
   strafe vector is perpendicular to the enemy (a circle), never towards it.
6. **No lead, no dodge.** Aim is at the target's current position (plus error); a moving player is almost never hit.
   Nothing reacts to incoming projectiles, dive markers or dashes.
7. **Specials wasted or unused.** The special charges only from hits (rare, see 1-6) and is fired at any enemy within
   7 tiles regardless of kind: the crab dashes from 7 tiles with a 4.9-tile dash, the octopus drops ink at a fixed
   offset.
8. **Hurt means passive.** Below 40 % HP a bot stops engaging; below 50 % its goal pick always keeps maximum distance.
9. **Calm start** (`calm_start_ticks` 150 = 5 s) blocks attacks; harmless on its own.

Net effect: matches are decided by the tide (phase 3 balance: average 2:56, close to the tide's full length).

### 3.2 Design overview

Decision: ADR 001 (layered utility AI with committed targets), ADR 002 (state and determinism), ADR 008 (bot damage
against humans).

`BotBrain.think(sim, e, cfg)` keeps its signature and stays a static, pure function of sim state + `sim.rng`. It is
split into four layers that run in this order every tick:

| Layer | When | What |
|---|---|---|
| 1. Reflex | every tick, re-evaluated every `reaction_ticks` | Detect threats (projectiles, dive markers, traps, dashes heading at me); with chance `dodge_pct` start a sidestep for 8 ticks. |
| 2. Plan | on think ticks (`think_ticks + rng(4)`) | Tide check, pick/keep a target, choose a goal spot (fight position at preferred range, or safety/snack), choose strafe side, decide the special. |
| 3. Move | every tick | Goal vector + strafe + backpedal; dodge overrides; never step from safe ground into deep water. |
| 4. Fire | every tick | Lead aim at the target (or an opportunistic closer foe), respect charges reserve and fire gap. |

### 3.3 Configuration (`data/bots.json`, version 3)

```json
{
  "version": 3,
  "levels": {
    "easy":   { "think_ticks": 12, "reaction_ticks": 12, "aim_error": 450, "lead_pct": 20,  "dodge_pct": 25,
                "aggression_pct": 55, "keep_charges": 1, "fire_gap_ticks": 55, "special_pct": 50,
                "tide_lookahead_ticks": 0,   "samples": 10, "look_tiles": 7, "damage_pct": 50,
                "human_damage_pct": 55, "ball_damage_pct": 55, "max_on_target": 2 },
    "normal": { "think_ticks": 8,  "reaction_ticks": 7,  "aim_error": 150, "lead_pct": 75,  "dodge_pct": 55,
                "aggression_pct": 75, "keep_charges": 0, "fire_gap_ticks": 40, "special_pct": 50,
                "tide_lookahead_ticks": 75,  "samples": 12, "look_tiles": 8, "damage_pct": 22,
                "human_damage_pct": 85, "ball_damage_pct": 75, "max_on_target": 2 },
    "hard":   { "think_ticks": 5,  "reaction_ticks": 3,  "aim_error": 40,  "lead_pct": 100, "dodge_pct": 85,
                "aggression_pct": 90, "keep_charges": 0, "fire_gap_ticks": 28, "special_pct": 100,
                "tide_lookahead_ticks": 150, "samples": 14, "look_tiles": 9, "damage_pct": 22,
                "human_damage_pct": 125, "ball_damage_pct": 90, "max_on_target": 3 }
  },
  "styles": {
    "crab":    { "range_pct": 55, "min_pct": 0,  "flee_hp_pct": 25, "damage_pct": 115 },
    "octopus": { "range_pct": 65, "min_pct": 30, "flee_hp_pct": 30, "damage_pct": 170 },
    "gull":    { "range_pct": 65, "min_pct": 40, "flee_hp_pct": 35 },
    "puffer":  { "range_pct": 50, "min_pct": 0,  "flee_hp_pct": 20 },
    "otter":   { "range_pct": 70, "min_pct": 40, "flee_hp_pct": 40 },
    "seal":    { "range_pct": 60, "min_pct": 0,  "flee_hp_pct": 25 },
    "hermit":  { "range_pct": 55, "min_pct": 0,  "flee_hp_pct": 20 },
    "star":    { "range_pct": 70, "min_pct": 25, "flee_hp_pct": 30 }
  },
  "default_style": { "range_pct": 60, "min_pct": 0, "flee_hp_pct": 30 },
  "default_level": "easy",
  "names": { "...": "unchanged" }
}
```

Values of everything except `human_damage_pct`, `ball_damage_pct` and `ball_human_damage_pct` as tuned in step a2
(measured, see 6.1); the first proposal differed in `aim_error`, `lead_pct`, `fire_gap_ticks`, `special_pct`,
`damage_pct` and the gull style. The three damage fields added in step a3 are **starting values** for the tuning of
section 7.2. Styles of the five new animals are untuned placeholders for b1.

Meaning of the level fields:

| Field | Meaning |
|---|---|
| `think_ticks` | Plan cadence (plus `rng(4)`). |
| `reaction_ticks` | The reflex layer re-checks threats at most every N ticks (average reaction = N/2). |
| `aim_error` | Max random angle error (of 4096) added to every shot. |
| `lead_pct` | How much of the target's velocity is used for lead (0 = aim at position, 100 = full lead). |
| `dodge_pct` | Chance to sidestep a detected threat. |
| `aggression_pct` | Chance per plan to engage the target (else reposition for safety/snacks). Plus a tide bonus: `+10 * urgency / span`, capped at 100. |
| `keep_charges` | Keep this many charges in reserve, unless the target is below 30 % HP or within 40 % of attack range. |
| `fire_gap_ticks` | Minimum extra ticks between two shots (plus `rng(fire_gap_ticks + 1)`), on top of the sim cooldown. |
| `special_pct` | Chance to use the special when its condition (3.6) is met on a plan tick. |
| `tide_lookahead_ticks` | When `phase_left <= warn_ticks + this`, safety is judged on the next tide level. |
| `samples`, `look_tiles` | Goal sampling, as today. |
| `damage_pct` | Damage multiplier of a bot **against other bots** in the normal match (and against former humans that became bots). Tuned for bot-vs-bot match length; does not affect the player. |
| `human_damage_pct` | Damage multiplier of a bot **against humans** in the normal match (3.9). The difficulty knob for the player; must rise strictly from easy to normal to hard. Allowed range 30-200. |
| `ball_damage_pct` | Optional. As `damage_pct`, in Strandbal (`mode == "ball"`). Default: `damage_pct`. |
| `ball_human_damage_pct` | Optional. As `human_damage_pct`, in Strandbal. Default: `human_damage_pct`. |
| `max_on_target` | At most this many bots may hold the same target (spreads fights, prevents ganging up on the player). |

Style field `damage_pct` (optional, default 100): multiplies the level's `damage_pct` (or `ball_damage_pct`) for bots
of that animal. Added in a2 as the balance knob for bot-vs-bot fights; it does **not** act on damage against humans.
Style field `human_damage_pct` (optional, default 100, added in a3): multiplies the level's `human_damage_pct` (or
`ball_human_damage_pct`) for bots of that animal; leave it absent unless one animal is measurably too strong or weak
against the test player (7.2). Players are never affected by style fields.

Styles (per animal): `range_pct` preferred distance to the target as % of attack range; `min_pct` back off when the
target is closer than this %; `flee_hp_pct` disengage below this HP % unless cornered (target within 40 % of range).
An animal without a style entry uses `{range_pct 60, min_pct 0, flee_hp_pct 30}`.

### 3.4 New entity fields

All `int`, added to `MatchSim.Ent` and to `ENT_FIELDS` (so hashed, snapshotted, restored). Defaults in brackets.

| Field | Owner | Meaning |
|---|---|---|
| `vx`, `vy` [0] | sim | Movement of this entity in the last tick (`x - x_before`, `y - y_before`), set at the end of `_update_ent`. Used for lead aim and threat prediction. |
| `guard` [0] | sim | Ticks left of a guard special (section 4.2); added now so the hash layout changes once. |
| `target` [-1] | bot | Entity id of the committed target. |
| `target_until` [0] | bot | Tick until which the target is kept (re-picked earlier if it dies). |
| `next_shot` [0] | bot | Earliest tick for the next shot (fire gap). |
| `reflex_at` [0] | bot | Next tick on which the reflex layer looks for threats. |
| `dodge_until` [0] | bot | Sidestep active while `tick < dodge_until`. |
| `dodge_dir` [0] | bot | Sidestep angle (0..4095). |
| `strafe_until` [0] | bot | Tick at which a new strafe side is drawn. `strafe` (existing) is now always -1 or +1. |
| `engaged` [0] | bot | 1 = this plan the bot fights its target, 0 = it repositions. |
| `human_damage_pct` [100] | match (a3) | Damage multiplier of this entity against victims with `is_bot == 0` (3.9). Set by `Match.make_bot`; 100 for humans. Add it to `ENT_FIELDS` directly after `damage_pct`. |

`Match.create`/`create_online` leave the bot fields at defaults. Ball mode uses `target`, `next_shot`, `reflex_at`,
`dodge_until`, `dodge_dir` too.

`MatchSim.attack_range(e)` changes: if the attack has `back > 0` (boomerang, section 4) the range is
`speed * back`, else `speed * life` as today.

### 3.5 Algorithm (normal match)

Integer maths only (`Fx`), `sim.rng` only. Helper functions are `static` in `BotBrain` and reused by `BallBrain`
(`reflex`, `incoming_threat`, `lead_point`, `danger`).

**Layer 1 - reflex (every tick).**
```
if tick >= e.reflex_at:
    e.reflex_at = tick + cfg.reaction_ticks
    th = incoming_threat(sim, e)          # see below; returns {angle_from, kind} or {}
    if th and tick >= e.dodge_until and rng(100) < cfg.dodge_pct:
        side = perpendicular to the threat direction, on the side away from the threat line
        if depth at (e + 2 tiles * side) >= 2: use the other side
        e.dodge_dir = side; e.dodge_until = tick + 8
```
`incoming_threat` checks, in this order, and returns the first hit:
- projectiles of a foe whose path passes within `e.radius + p.radius + 150` of `e` within the next 12 ticks
  (closest-approach test on the straight line `p + t * (dx, dy)`, `t` in 0..min(12, p.life)); for a boomerang also
  the return leg if `p.back <= 12`;
- dives of a foe with `delay <= 10` whose blast circle contains `e`;
- traps of a foe that are armed and whose trigger circle is within 1 tile of `e`, or whose fuse is `<= 10` and blast
  circle contains `e`;
- foes with `dash > 0` whose dash line passes within `e.radius + o.radius` of `e` within `o.dash` ticks.
Cap: at most 24 projectiles examined per call (iterate in list order and stop at 24) to bound cost.

**Layer 2 - plan (think ticks).**
```
e.next_think = tick + think_ticks + rng(4)
safe_level = level + 1 if phase_left <= warn_ticks + tide_lookahead_ticks and level < max_level else level
danger(p) = safe_level - height_at(p)     # <= 0 dry, 1 shallow, >= 2 deep
1. TIDE: if danger(e) >= 2, or (land animal and danger(e) == 1 and a dry sample exists within look_tiles):
       goal = best safety sample, e.engaged = 0, go to step 5 (special); the target is kept.
2. TARGET: if e.target invalid/dead or tick >= e.target_until: pick_target(); e.target_until = tick + 60 + rng(60)
3. HURT: if hp% < style.flee_hp_pct and target distance > 40 % of range:
       goal = best safety sample with snack bonus; e.engaged = 0
4. ENGAGE: else e.engaged = rng(100) < min(100, aggression_pct + 10 * urgency / span)
       if engaged: goal = fight_spot(); else goal = best safety sample
   strafe: if tick >= e.strafe_until: e.strafe = +1 or -1 (rng); e.strafe_until = tick + 30 + rng(45)
5. SPECIAL: if e.special >= special_hits and tick >= calm_start_ticks and rng(100) < special_pct:
       use_special(kind) -> may set cmd.s / cmd.sd (section 3.6)
```
`pick_target`: for each alive foe `o` compute
`score = -dist/10 + (100 - hp%) * 2 + (200 if e.last_hit_by == o.id and tick - e.last_hit_tick < 90)
+ (100 if dist <= attack_range(e)) - (300 if count of other bots with target == o.id >= max_on_target) + rng(60)`.
Highest score wins. **No term depends on whether `o` is human or bot** (this stays true after ADR 008: only the damage
number differs, never the behaviour).

`fight_spot`: ideal point = target position + unit(e - target) * (attack_range * range_pct / 100), rotated around the
target by `strafe * 300` (of 4096). Score `samples` candidates around it (radius up to 2 tiles, candidate 0 = the
ideal point): `score = -danger*120 - (400 if danger >= 2) - dist_to_ideal/50 + (80 if water animal and danger == 1)`.

Safety sample (replaces `_pick_goal`): as today (`-depth*120`, deep -400, water bonus, snack bonus when hurt,
centre pull with urgency) but with `danger()` instead of current depth, **without the repulsion from other animals**
except a small crowd term: `-(4000 - od)/40` for each foe within 4 tiles **only when hurt**. Candidate 0 (own position)
gets a penalty of 40 so bots keep moving.

**Layer 3 - move (every tick).**
```
if tick < e.dodge_until: cmd.m = e.dodge_dir; skip the rest of the move layer
v = unit(goal - e) if |goal - e| > 300 else 0
if engaged and target alive:
    d = dist(target); ideal = range * range_pct / 100
    v += tangent(target, e.strafe) * 6/10                    # circle
    if d < range * min_pct / 100: v += unit(e - target) * 8/10 # back off (kite)
    elif d > ideal * 13/10:        v += unit(target - e) * 6/10 # close in
if v == 0 and not engaged: v = tangent(goal, e.strafe) * 4/10  # idle wander, never stand still
look-ahead: p = e + unit(v) * speed * 6; if danger(e) < 2 and depth_now(p) >= 2: rotate v by +-1024 (the side with lower depth)
cmd.m = atan2(v)
```

**Layer 4 - fire (every tick).**
```
if tick < calm_start_ticks or e.cooldown > 0 or e.charges == 0 or tick < e.next_shot: no shot
if a guard with no_attack is active (section 4.2): no shot
reserve = keep_charges unless target hp < 30 % or dist < 40 % of range
if e.charges <= reserve: no shot
t = target (or, if target out of range, the nearest foe within 60 % of range)
flight = dist(t) / attack.speed
px = t.x + t.vx * flight * lead_pct / 100;  py likewise
if dist(e, p) <= attack_range(e) * 95 / 100:
    cmd.a = atan2(p - e) + rng.between(-aim_error, aim_error)
    e.next_shot = tick + fire_gap_ticks + rng(fire_gap_ticks + 1)
Ring attacks (count * spread >= 4096, the puffer): no aiming, fire when any foe is within range.
```

### 3.6 Special use per kind (bots)

`use_special` dispatches on `special.kind` (not `mech`, so two animals with the same mechanic can use it differently).
In step a2 only `dash`, `ink`, `dive` exist; the other rows come in step b1.

| Kind (animal) | Fire when | Aim |
|---|---|---|
| `dash` (crab) | target within `ticks*speed*85/100` and > 1 tile; or escape: in deep water and a dry sample lies within dash reach | predicted target position (lead with `ticks/2`); escape: towards the dry sample |
| `ink` (octopus) | target within `offset + radius`; or hurt and a foe within 4 tiles | at the target / chasing foe |
| `dive` (gull) | the best candidate point covers >= 1 foe and lies within `range` | among foes: predicted position after `delay` ticks; pick the one whose blast circle covers the most foes; `sd` = distance |
| `belly` (seal) | target within reach and the point `target + unit(dir) * push` has depth >= 2 (push into the sea); otherwise target within reach with 50 % chance | predicted target position |
| `slide` (otter) | hurt (< flee) and a foe within 5 tiles: slide to the safest sample away from the foe; or `charges == 0` and target in range: slide perpendicular to the target (refill); or tide escape like the crab | as described |
| `puff` (puffer) | a foe within `radius*grow/100 + 800`, or 2+ foes within 3 tiles, or a threat is incoming and hp < 50 % | any angle (aim at the nearest foe) |
| `shell` (hermit) | a threat is incoming and hp < 60 %, or a foe with `dash > 0` heads at me within 3 tiles, or hp < 35 % and a foe within 3 tiles | any angle |
| `arm` (star) | a foe within 3 tiles that moves towards me (`dot(o.v, e - o) > 0`), or I stand within 1.5 tiles of a snack and a foe is within 6 tiles | away from the foe (the trap drops at my position, section 4) |

### 3.7 Ball mode bot (`bots/ball_brain.gd`)

Assessment: the role logic (attack/defend/support, behind-the-ball positioning, keep-dry) works and meets its balance
goals (3.0 goals per match, sides 50/50). Weak points: no dodge, no lead when shooting at foes, `_fight` only near the
ball with `aggression_pct / 2`, and `_special` only knows `dash`, `dive`, `ink` (new animals would never use theirs).

Changes:
- Call the shared reflex layer (`BotBrain.reflex`) first; while dodging, move = dodge.
- `_fight` uses `BotBrain.lead_point` and the fire gap; aggression no longer halved.
- `_special` gains (step b1): `belly` like `dash` (aligned and `ball_d < 4500`); `slide` = reposition to `_behind`
  when it is more than 5 tiles away; `puff` when the ball and a foe are within 2.5 tiles; `shell` for the defender
  when the ball moves towards the own goal and is within 4 tiles (the hermit becomes a wall); `arm` for the defender:
  drop at the own goal mouth when a foe is within 6 tiles of the ball near the own goal.
- `data/modes/ball.json` `ball.shot` gets entries for the new attack kinds and the dash/guard/trap specials
  (section 4.2); the sim uses `shot[special.kind]` with fallback `shot.dash` (dash family) or `shot.dive` (blasts).
- Ball acceptance stays as in `tests/ball_balance.gd`, extended to all 8 animals (section 7).
- Step a3: ball bots use `ball_damage_pct` / `ball_human_damage_pct` (3.3, 3.9) instead of the normal-mode values, so
  Strandbal KOs come back (a2: 0.1 per match, baseline 3.6) without changing normal-match length. The sim-wide
  `rules.ball.damage_pct` (65) in `data/modes/ball.json` stays and still applies on top, to everyone.

### 3.8 Measuring (new tool `tests/bot_metrics.gd` + `.tscn`)

```
godot --headless --path . res://tests/bot_metrics.tscn -- --matches=200 --level=normal --seed=1 [--human=1] [--profile=legacy|casual|skilled] [--ladder=1] [--check=1] [--out=user://bot_metrics.json]
```
- Runs all-bot matches (or with `--human=1` the scripted test player in slot 0; move `_player_cmd` from
  `tests/run_tests.gd` into `tests/test_player.gd` (`class_name TestPlayer`, `static func cmd(sim, me)`), used by both).
- Collects from `sim.events` and entity state per tick, per bot:
  - `alive_min`: alive ticks / 1800.
  - `attacks_per_min`: `attack` events / alive_min.
  - `hits_per_attack`: `hit` events by the bot / its `attack` events (reported for all; thresholds only on
    single-projectile animals: crab, gull, otter, seal, hermit, star).
  - `specials_per_min`: `special` events / alive_min.
  - `special_lag_s`: average seconds between `special` reaching `special_hits` and the next `special` event.
  - `idle_pct`: alive ticks after tick 30 with `vx == 0 and vy == 0 and dash == 0`, as % of those ticks.
  - per match: `fight_ko_pct` = KOs with `by >= 0` / all KOs; `avoidable_drown_pct` = bot KOs with `by < 0` while
    `level < max_level` / bot KOs; `duration_s`.
  - with `--human=1`: `human_focus_pct` = bot hits on entity 0 / all bot hits; test player's average place.
  - per animal: entries, wins, win % per entry, KOs per entry.
  - `ms_per_1000_ticks`.
- KOs are "credited" when `by >= 0` and the victim was last hit within `knockout_credit_ticks`; a KO without credit
  counts as drowning (the sim keeps `last_hit_by` forever, so `by >= 0` alone would hide late drownings).
- Positions are compared before/after each step by the tool itself (no dependence on `vx/vy`), so it works on the old brain.
- `--ms_max=<n>` with `--check=1` also fails when `ms_per_1000_ticks` exceeds n. The JSON holds no timing, so equal
  commands give byte-identical files.
- Prints a table; `--out` writes JSON; `--check=1` exits 1 when any target in section 7.2 is missed.
- Works on the old brain too (it only reads state and events), so step a1 can record a baseline.

Additions in step a3:
- `--profile=<p>` (with `--human=1`, default `legacy`): which test player plays slot 0 (3.9.4). The JSON records
  `"profile"`.
- `--ladder=1`: run easy, normal and hard in one call with the same seeds (`--level` is ignored), print one block per
  level plus a ladder line, write `{"levels": {"easy": {...}, "normal": {...}, "hard": {...}}, "ladder": {...}}`, and
  with `--check=1` also check the cross-level targets of 7.2.
- New per-run keys with `--human=1`: `human_win_pct` (% of matches with place 1), `human_early_out_pct` (% of matches in
  which the test player is out with `died_tick < 1350`, i.e. before 45 s, and place > 1), `human_survived_s_median`
  (median of `(died_tick if died_tick >= 0 else final tick) / 30`).
- New all-bot key: `duration_s_p10` (nearest rank: sort the durations ascending, take index `ceil(n / 10) - 1`).
- `tests/ball_balance.gd` gains `kos_per_match` (all `ko` events / matches) in its output and check.

### 3.9 Damage against humans (ADR 008, step a3)

**Why.** With active bots, bot-vs-bot match length forces a low bot `damage_pct` (22-50 %), while the player needs
bots that hurt. One number cannot serve both (6.1). The owner decided (2026-11-18) that the challenge for the player has
priority, without making bot-vs-bot matches shorter.

**3.9.1 Damage matrix.** "Human" means `victim.is_bot == 0` at the moment of the hit.

| Attacker \ victim | bot | human |
|---|---|---|
| human (offline or online) | 100 % | 100 % (online PvP unchanged) |
| bot | `attacker.damage_pct` | `attacker.human_damage_pct` |
| water (`by = -1`) | unscaled | unscaled |

Entity values, computed once when an entity becomes a bot:
- normal match: `damage_pct = level.damage_pct * style.damage_pct / 100`,
  `human_damage_pct = level.human_damage_pct * style.human_damage_pct / 100` (style values default 100);
- Strandbal: the same with `level.ball_damage_pct` (default `level.damage_pct`) and `level.ball_human_damage_pct`
  (default `level.human_damage_pct`).
Humans keep `damage_pct = 100` and `human_damage_pct = 100`.

**3.9.2 Code.**

`bots/bot_brain.gd`: replace `damage_pct(cfg, animal)` by
```
## Bot damage multipliers: x = against bots, y = against humans (docs/design.md 3.9).
static func damage_pcts(cfg: Dictionary, animal: String, mode: String) -> Vector2i
```
Ball keys are used when `mode == "ball"`, with the fallbacks of 3.9.1. Integer maths, same rounding as today
(`level * style / 100`).

`sim/match.gd`:
- New public `func make_bot(slot: int) -> void`: `e.is_bot = 1`, `var d := BotBrain.damage_pcts(_bot_cfg, animal, sim.mode)`,
  `e.damage_pct = d.x`, `e.human_damage_pct = d.y`. Idempotent.
- `create` and `create_online` call `make_bot(e.id)` for every bot entity instead of setting `is_bot`/`damage_pct`
  inline.
- `to_bot(slot)`: `humans.erase(slot); make_bot(slot)` (a player who leaves gets bot values; today the slot kept 100 %).
- `sim/rollback.gd::_play`: replace `m.sim.ents[s].is_bot = 1` by `m.make_bot(s)`.
Since `make_bot` only reads data and the entity's animal, every client sets the same values at the same tick.

`sim/match_sim.gd`:
```
## Damage an entity deals to `victim`: bots scale differently against humans (docs/design.md 3.9).
func _hit_amount(src: Ent, victim: Ent, base: int) -> int:
	return base * (src.human_damage_pct if victim.is_bot == 0 else src.damage_pct) / 100
```
Every entity-caused damage goes through it, at the moment of impact (the victim is unknown when a shot is fired):

| Place | Today | a3 |
|---|---|---|
| projectile creation | `p.damage = cfg.damage * e.damage_pct / 100` | `p.damage = int(cfg.damage)` (base) |
| `_update_projs` hit | `_damage(e, p.damage, p.owner)` | `_damage(e, _hit_amount(ents[p.owner], e, p.damage), p.owner)` |
| dash hit | `_damage(o, sp.damage * e.damage_pct / 100, e.id)` | `_damage(o, _hit_amount(e, o, int(sp.damage)), e.id)` |
| dive creation | `v.damage = sp.damage * e.damage_pct / 100` | `v.damage = int(sp.damage)` (base) |
| dive blast | `_damage(e, v.damage, v.owner)` | `_damage(e, _hit_amount(ents[v.owner], e, v.damage), v.owner)` |
| guard bounce (b1) | | `_hit_amount(e, o, bounce_damage)` |
| trap creation / blast (b1) | | `damage = int(sp.damage)` (base); blast `_hit_amount(ents[t.owner], victim, t.damage)` |
| water | `_damage(e, dmg, -1)` | unchanged |

`ents[owner]` is always valid (dead entities stay in the list). The Strandbal factor `rules.ball.damage_pct` stays
inside `_damage` and applies after `_hit_amount`. For bot victims the result is bit-for-bit the old value
(`base * pct / 100` either way), so all-bot matches play out exactly as in a2; only the stored projectile/dive damage
and the new field change the state hash.

**3.9.3 Determinism and online.**
- No new RNG draws, no floats; values come from data at match creation and live in `ENT_FIELDS`, so snapshot, restore,
  rollback and the replay check cover them. Bot behaviour (`BotBrain`) does not change at all.
- `Replay.check` and `tools/verify/` rebuild the match with `Match.create` and get the same values from the same build.
  Scores from builds before a3 no longer verify (accepted, ADR 003; the sim version field stays follow-up work).
- Online rooms (`create_online`, default level `normal`) use the same table: every human in the room takes
  `human_damage_pct` from bots, humans hit each other at 100 %. Two clients with different `bots.json` would compute
  different damage; because the field is hashed this shows up as a hash mismatch, not as a silent drift (covered by the
  existing follow-up "build/sim version in the lobby URL").
- Leaver: from its leave tick the slot is a bot with bot values and is damaged at bot-vs-bot rates.

**3.9.4 Test player profiles (`tests/test_player.gd`).**

The existing scripted player (`legacy`) aims exactly at the current position of the nearest animal (no error, no lead),
fires whenever the sim allows (also out of range), never dodges, walks to the island centre and fires the special every
240 ticks. It is a perfect-aim turret: stronger than a casual 10+ player at close range, weaker in movement. One proxy
is not enough to judge a difficulty ladder, so a3 adds two profiles that bracket a human player. `legacy` stays
unchanged (golden traces, replay fixture and `test_score_check` keep using `TestPlayer.cmd`).

API: `TestPlayer.new(profile: String)` and `func next(sim: MatchSim, me: MatchSim.Ent) -> Dictionary`; memory
(`next_shot`, `dodge_until`, `dodge_dir`, `react_at`, `circle`) in instance variables (the metrics tool never rolls back).
`profile == "legacy"` returns `TestPlayer.cmd(sim, me)`. The profiles **never** call `sim.rng`; their noise is
```
static func noise(sim, me, salt: int, n: int) -> int:
    var h := (sim.seed_value * 73856093) ^ (sim.tick * 19349663) ^ (me.id * 83492791) ^ (salt * 2654435761)
    h ^= (h << 13) & 0xFFFFFFFF; h ^= h >> 17; h ^= (h << 5) & 0xFFFFFFFF
    return (h & 0x7FFFFFFF) % n
```

| Behaviour | `casual` | `skilled` |
|---|---|---|
| target | nearest alive foe | nearest alive foe |
| aim | target position + `noise(..., 1, 901) - 450` | `BotBrain.lead_point(sim, me, t, speed, 60)` + `noise(..., 1, 301) - 150` |
| fire | only when the target is within `attack_range`; at most once per 20 ticks | only within 95 % of `attack_range`; whenever the sim allows |
| special | when ready and a foe is within 6 tiles: at the nearest foe, `sd` = its distance | when ready and the target is within 70 % of `attack_range`: at `lead_point(..., 100)`, `sd` = its distance |
| dodge | never | every 6 ticks `BotBrain.incoming_threat(sim, me)`; if a threat and `noise(..., 2, 100) < 60`: sidestep 8 ticks, side as in `BotBrain.reflex` (cross product; other side if `depth_at` 2 tiles out is >= 2) |
| move | as `legacy` (to the centre, wander there) | if standing in water that is deep (or shallow for a land animal): step towards the best of 8 directions at 3 tiles by `height_at`; else keep the target between 50 % and 90 % of `attack_range` (back off / close in) and otherwise circle it, side flipped every 60 ticks by `noise(..., 3, 2)` |

Calibration: the owner playtest (A-B5) records the owner's places; the tester compares them with the `casual` and
`skilled` numbers. When the owner is clearly outside the bracket (better than `skilled` on hard or worse than `casual`
on easy), that is reported as a follow-up for the profiles, not a reason to change the targets.

---

## 4. Change 3 - five new fighters

Decisions: ADR 004 (mechanics), ADR 005 (roster, free animals, path). Names and text keys already exist in
`i18n/strings.csv` (`ANIMAL_PUFFER` ... `ANIMAL_STAR`).

### 4.1 Roster and stats (`data/animals.json`, version 3)

Changes to the schema:
- `in_slice` is replaced by `free` (bool): free animals are always available.
- `attack` may have `push` (milli-tiles of knockback on hit, default 0) and `back` (ticks after which the projectile
  reverses, default 0 = never).
- `special` gets `mech` (the sim mechanic: `dash`, `cloud`, `dive`, `guard`, `trap`); `kind` stays the identity used
  for text keys (`SPECIAL_DESC_<KIND>`), sounds and bot logic. Existing: crab `kind dash, mech dash`, octopus
  `kind ink, mech cloud`, gull `kind dive, mech dive`. The sim does `match str(sp.get("mech", sp.kind))`.

| id | type | free | hp | radius | speed | attack | special |
|---|---|---|---|---|---|---|---|
| crab | land | yes | 12000 | 420 | 120 | `snip` unchanged | `dash` unchanged |
| octopus | water | yes | 9500 | 420 | 120 | `fan` unchanged | `ink` (`mech: cloud`) unchanged |
| gull | flyer | yes | 8800 | 400 | 120 | `long` unchanged | `dive` unchanged |
| **puffer** | water | no (path 150) | 14000 | 460 | 108 | `spines`: count 8, spread 512, speed 380, life 7, damage 1100, radius 240 | `puff` (`mech: guard`): ticks 90, taken_pct 50, self_speed_pct 80, no_attack 0, grow_pct 150, steady 0, bounce_damage 1500, bounce_push 2600 |
| **otter** | water | **yes** | 9000 | 400 | 132 | `shell`: count 1, speed 520, life 14, damage 1700, radius 280 | `slide` (`mech: dash`): ticks 14, speed 560, damage 0, push 0, intangible 1, refill 1 |
| **seal** | water | no (path 350) | 12500 | 460 | 112 | `jet`: count 1, speed 460, life 11, damage 1300, radius 320, push 1200 | `belly` (`mech: dash`): ticks 12, speed 560, damage 1400, push 4200 |
| **hermit** | land | **yes** | 13000 | 440 | 112 | `poke`: count 1, speed 600, life 6, damage 2000, radius 420 | `shell` (`mech: guard`): ticks 75, taken_pct 10, self_speed_pct 30, no_attack 1, grow_pct 100, steady 1, bounce_damage 0, bounce_push 0 |
| **star** | land | no (path 550) | 10000 | 420 | 118 | `star`: count 1, speed 420, life 20, back 10, damage 1400, radius 300 | `arm` (`mech: trap`): offset 0, arm_ticks 15, fuse_ticks 150, trigger 600, radius 1800, damage 3200, max 2 |

Order in `animals.json`: crab, octopus, gull, puffer, otter, seal, hermit, star (this is the roster order).

Character of each new fighter (for collection texts and art):
- **Puff the Pufferfish** (water, tank): slow and sturdy; spines fly out in all directions (good in a crowd, weak at
  range). Special: blows himself up for 3 s - bigger, takes half damage, and bounces off everyone he touches.
- **Slick the Otter** (water, hit-and-run): fastest animal, light. Throws shells. Special: a long belly slide through
  water and sand during which nothing hits him; he comes out with full charges.
- **Bumper the Seal** (water, pusher): water jet that pushes the target back. Special: belly slide that sends
  everything it hits far away - into the deep if you aim well.
- **Shelly the Hermit Crab** (land, defender): short strong poke. Special: hides in his shell for 2.5 s - takes only
  10 % damage and cannot be pushed, but cannot attack and barely moves.
- **Twinkle the Starfish** (land, sly): throws a spinning star that flies out and comes back. Special: leaves an arm
  behind that explodes after 5 s or as soon as a foe steps on it (at most 2 at once).

Balance rationale (to be tuned, section 7): each new animal trades one strength against one weakness, like the
originals: puffer = most HP, shortest reach; otter = fastest, least HP, escape instead of damage special; seal = most
displacement, mid damage; hermit = best defence, cannot attack during it, slow; star = burst from traps, moderate HP.
Tuning rule: change only numbers in `animals.json`, at most +-25 % per value from this table, until the targets in
7.2 are met; record final values in the test report.

### 4.2 Sim changes (`sim/match_sim.gd`)

All new state is integers, hashed and snapshotted (ADR 002).

1. **Constants.** `ENT_FIELDS` gets the fields of 3.4 (in step a2; `human_damage_pct` in a3). `PROJ_FIELDS += ["push",
   "back"]`. New `TRAP_FIELDS := ["owner", "x", "y", "arm", "fuse", "trigger", "radius", "damage"]`, class `Trap`,
   `var traps: Array = []`, hashed after `dives` (also add `traps.size()` to the header list), snapshot key
   `"traps"`, restored with `_restore_list`, cleared in `_kickoff()`.
2. **Projectile creation:** `p.push = int(cfg.get("push", 0))`, `p.back = int(cfg.get("back", 0))`. `p.damage` holds the
   base damage (3.9.2).
3. **`_update_projs`:** after moving: `if p.back > 0: p.back -= 1; if p.back == 0: p.dx = -p.dx; p.dy = -p.dy`.
   On hit: if `p.push > 0` and the target is not steady: `d = max(1, Fx.dist(p.dx, p.dy))`,
   `o.x += p.dx * p.push / d`, `o.y += p.dy * p.push / d`, `_clamp(o)`. Skip targets that are intangible.
4. **Intangible / steady helpers:**
   `func _intangible(e) -> bool: return e.dash > 0 and int(animals[e.id].special.get("intangible", 0)) == 1`
   `func _steady(e) -> bool: return e.guard > 0 and int(animals[e.id].special.get("steady", 0)) == 1`
   Intangible entities are skipped by projectiles, cloud slow, dive blasts, trap blasts, guard bounce and dash hits.
   Steady entities are not moved by dash push, projectile push or guard bounce (they still take the damage).
5. **Dash family (`mech: dash`):** unchanged movement. Damage is skipped when `special.damage == 0`; push skipped when
   `special.push == 0` or the target is steady. When `e.dash` goes from 1 to 0 in this tick and `special.refill == 1`:
   `e.charges = rules.attack.charges; e.reload = 0`. Ball: kick with `rules.ball.shot.get(kind, shot.dash)`.
6. **Guard (`mech: guard`):** activation: `e.guard = ticks; e.dash_hit = []; e.radius = base_radius * grow_pct / 100`.
   Start of `_update_ent`: `if e.guard > 0: e.guard -= 1; if e.guard == 0: e.radius = int(animals[e.id].radius)`.
   Movement speed `* self_speed_pct / 100` while guard > 0. Attack ignored while guard > 0 and `no_attack == 1`.
   `_damage`: when `e.guard > 0` and `by >= 0`, `amount = amount * taken_pct / 100` (water damage is not reduced: the
   tide stays the main threat). Bounce: while `guard > 0` and `bounce_push > 0`, every foe overlapping `e` that is
   not in `e.dash_hit` is added to it, takes `_hit_amount(e, o, bounce_damage)` (3.9.2) and is pushed along
   `unit(o - e) * bounce_push` (direction (1, 0) when the positions are equal); `_clamp`. Ball: overlapping the ball
   once per guard kicks it outward with `shot.puff` (mark with `BALL_MARK` in `dash_hit`).
   `_clamp` uses the current (grown) radius.
7. **Trap (`mech: trap`):** activation: new `Trap` at `e + unit(aim) * offset`, `arm = arm_ticks`,
   `fuse = fuse_ticks`, `trigger`, `radius`, `damage = int(sp.damage)` (base; scaled per victim with `_hit_amount`
   when it fires, 3.9.2). If the owner already has `max` traps, remove its oldest first. `_update_traps()` runs after
   `_update_dives()`: `arm = max(0, arm - 1)`, `fuse -= 1`; it fires when `fuse <= 0` or (`arm == 0` and any alive,
   non-intangible foe of the owner touches the trigger circle). Firing damages every alive, non-intangible foe within
   `radius` (like a dive), kicks the ball with `shot.arm` if touched, and emits `{"type": "trap", "id": owner, "x",
   "y"}`. A trap of a washed-away owner stays until it fires.
8. **`vx`, `vy`** (step a2): remember `x, y` at the start of `_update_ent`; at the end `e.vx = e.x - x0; e.vy = e.y - y0`.
9. **`attack_range`:** `speed * back` when `back > 0`, else `speed * life`.
10. **Events:** `special` events keep `kind`; new `trap` event. The view reads `e.guard` from state for the guard pose.

`data/rules.json` stays unchanged. Strandbal: `data/modes/ball.json`
`"shot": { "snip": 700, "fan": 300, "long": 460, "spines": 280, "shell": 520, "jet": 640, "poke": 620, "star": 420,
"dash": 860, "belly": 900, "slide": 500, "dive": 760, "puff": 700, "arm": 760 }`.
`_update_projs` already uses `shot[attack.kind]`; make it `shot.get(kind, shot.long)` so a missing key never crashes.

### 4.3 Roster in code

Replace `Match.SLICE_ANIMALS` by `static func roster() -> Array` in `sim/match.gd` returning the ids of
`Content.animals()` in file order (cached). Every user:

| File | Use |
|---|---|
| `sim/match.gd` | bots pick from `roster()` (all 8) in `create` and `create_online` |
| `platform/daily.gd` | `animal_for(seed) = roster()[seed % roster().size()]` - the daily may hand out an animal the player has not unlocked yet (try-out, ADR 005) |
| `sim/replay.gd` | `Replay.check` accepts any id in `roster()` |
| `view/match_view.gd` | fallback when the animal is unknown: `"octopus"` (unchanged) |
| `tests/run_tests.gd` | all uses of `SLICE_ANIMALS` |
| `tests/bot_metrics.gd` | the test player's animal rotates over the free animals of `roster()` |
| `platform/local_backend.gd` | `default_profile().unlocked_animals` = ids with `free == true` (step b3) |

### 4.4 Unlocks and the Treasure Path (`data/path.json`)

Free from the start: crab, octopus, gull, **otter**, **hermit** (ADR 005). New path (rows marked "c" are added in
step c, together with the looks they point to):

| at | kind | id | name_key | note |
|---|---|---|---|---|
| 100 | avatar | shell | REWARD_SHELL_AVATAR | unchanged |
| 150 | animal | puffer | ANIMAL_PUFFER | was 250 |
| 250 | look | otter_sailor | LOOK_OTTER_SAILOR | new (c) |
| 350 | animal | seal | ANIMAL_SEAL | was 1400 |
| 400 | badge | beachcomber | REWARD_BEACHCOMBER | unchanged |
| 550 | animal | star | ANIMAL_STAR | was 3000 |
| 600 | look | crab_sunset | REWARD_SUNSET_PINCH | unchanged |
| 750 | look | hermit_blossom | LOOK_HERMIT_BLOSSOM | new (c) |
| 900 | look | puffer_lagoon | LOOK_PUFFER_LAGOON | new (c) |
| 1100 | avatar | wave | REWARD_WAVE_AVATAR | unchanged |
| 1300 | look | gull_captain | LOOK_GULL_CAPTAIN | new (c) |
| 1500 | look | seal_dapper | LOOK_SEAL_DAPPER | new (c) |
| 1750 | look | octopus_midnight | REWARD_MIDNIGHT_INKA | unchanged |
| 2100 | look | star_sunny | LOOK_STAR_SUNNY | new (c) |
| 2500 | badge | tide_master | REWARD_TIDE_MASTER | unchanged, end of path |

With about 30-45 pearls per match this is roughly puffer after 4 matches, seal after 9, star after 14 (was 6, 35, 75).
`hermit` and `otter` leave the path (they are free).

**Reconcile (retroactive grants).** New `static func Rewards.reconcile(profile) -> Dictionary` (pure, idempotent,
returns the corrected profile):
1. add every `free` animal to `unlocked_animals`;
2. grant every `path.json` reward with `at <= pearls_total` (players who passed 150/350/550 under the old path get the
   animals now; players past 250 get the otter look once it exists);
3. grant the mastery look of every animal whose mastery tier is `>= mastery.look_tier` (step c; skip when
   `mastery.json` has no `looks`).
`Platform.load_profile()` returns `Rewards.reconcile(backend.load_profile())`. Not saved by itself; the next save
persists it. `apply_result` keeps using `Rewards.walk` for the "new on your path" message.

### 4.5 Art, view, sound, text

**Rigs and parts** (in `tools/art/animals.py`, new builders `puffer`, `otter`, `seal`, `hermit`, `star`; 200 x 200
animal space, origin (100, 172), outline 7, colours from `palette.json`):

| Animal | Parts (z) | Silhouette |
|---|---|---|
| puffer | `tail` (-1), `limb_fl`, `limb_fr` (fins, -2), `body` (0, round with spikes drawn on the outline), `eye_l`, `eye_r`, `mouth` (1) | ball with spikes |
| otter | `tail` (-2), `limb_bl`, `limb_br` (-2), `body` (0), `limb_fl`, `limb_fr` (1, front paws), `head` (2), `eye_l`, `eye_r`, `mouth` (3, parent head) | long body, round head, thick tail |
| seal | `tail` (-1, rear flippers), `body` (0, lying teardrop), `limb_fl`, `limb_fr` (1, flippers), `head` (2), `eye_l`, `eye_r`, `mouth` (3, parent head; whiskers in mouth) | teardrop with flippers |
| hermit | `limb_bl`, `limb_br` (-2), `shell` (-1, spiral shell, larger than the body), `body` (0), `claw_l`, `claw_r` (2), `eye_l`, `eye_r` (1, stalks), `mouth` (1) | spiral shell with a crab peeking out |
| star | `limb_top`, `limb_fl`, `limb_fr`, `limb_bl`, `limb_br` (-1, five arms), `body` (0, centre), `eye_l`, `eye_r`, `mouth` (1) | five-pointed star |

New part names `shell` and `limb_top` join the stable list (docs/conventions.md). Each animal has at most 12 parts
including the accessory a look adds (section 5).

**Default palettes** (`palette.json` `animals`; never fully cyan `#3FE0FF` or coral `#FF5A4E`):

| Animal | base | shade | accent | extra |
|---|---|---|---|---|
| puffer | `#F2D35B` | `#D9B53C` | `#FFF1A8` | `spines: #C9873A` |
| otter | `#9C6B45` | `#7E5334` | `#E8C9A0` | |
| seal | `#8E9AA6` | `#6F7B87` | `#C9D2DA` | |
| hermit | `#E9A23B` | `#C98426` | `#FFD08A` | `shell: #F4E1C1`, `shell_shade: #D8BE94`, `shell_line: #B98A5E` |
| star | `#D97BC0` | `#B95FA0` | `#F7C3E0` | |

**Cutout (`view/cutout.gd`):**
- `var guard_kind := ""`, set by the match view each frame from `e.guard > 0` and the special kind (`puff`/`shell`).
- `puff`: `_body.scale *= 1.5` (matching `grow_pct`), spikes wobble; `shell`: every joint except `shell`, `eye_l`,
  `eye_r` scaled to 0.15 and moved to the shell centre (the hermit hides), eyes peek.
- Attack pose: `star` spins its five limbs (`rotation += k * 1.2`); `otter`/`seal` use the existing head nudge;
  `puffer` scales `body` +10 % on attack.
- The zoo (`view/zoo.gd`) builds its rows from data: every animal in `roster()` with "" and every look in
  `palette.json`, 5 rows per page, page from `Boot.args.page` (default 0); add a `special` column that sets
  `guard_kind` for guard animals. `tools/web_smoke.py` photographs every zoo page.

**Match view:**
- `FxDraw.trap_marker(ci, pos, radius_px, armed, fuse_left_ratio, col, t)`: a small star arm on the ground in the
  owner colour (cyan for the player, coral for others), blinking faster as the fuse runs out, a thin dashed blast
  ring when armed. Drawn on `board` after dives.
- `trap` event: same feedback as `dive` (boom fx, splash, sound `boom`).
- Projectiles: keep the circle; for `star` draw a small 5-point star rotating with `_t`; for `jet` an elongated drop.
- Guarded entities get a thin white ring around their health bar.

**Sounds** (`data/sfx.json`, synthesised by `tools/audio/sfx.py`, loudness-checked in CI): attack `prick` (puffer),
`toss` (otter), `squirt` (seal), `poke` (hermit), `whirl` (star); special `inflate` (puff), `whoosh` (slide), `slap`
(belly), `clack` (shell), `pop` (arm). Mapping in `match_view.gd` `ATTACK_SOUNDS` and the special map.

**Text** (`i18n/strings.csv`, en + nl draft):

| Key | en | nl |
|---|---|---|
| ATTACK_DESC_SPINES | spines that fly out in every direction | stekels die alle kanten op vliegen |
| ATTACK_DESC_SHELL | a thrown shell | een gegooide schelp |
| ATTACK_DESC_JET | a water jet that pushes back | een waterstraal die terugduwt |
| ATTACK_DESC_POKE | a short, hard poke with the claw | een korte, harde por met de schaar |
| ATTACK_DESC_STAR | a spinning star that comes back | een draaiende ster die terugkomt |
| SPECIAL_DESC_PUFF | puffs up: bigger, tougher, bounces others away | blaast zich op: groter, taaier, kaatst anderen weg |
| SPECIAL_DESC_SLIDE | a fast slide nothing can hit; comes out reloaded | een snelle glijpartij waar niets op raakt; daarna weer geladen |
| SPECIAL_DESC_BELLY | a belly slide that shoves everything far away | een buikschuiver die alles ver wegduwt |
| SPECIAL_DESC_SHELL | hides in the shell: almost no damage, can't be pushed, can't attack | kruipt in de schelp: bijna geen schade, niet te duwen, kan niet aanvallen |
| SPECIAL_DESC_ARM | leaves an arm behind that explodes when someone steps on it | laat een arm achter die ontploft als iemand erop stapt |

Update `tools/i18n_add_nl.py` with the same nl texts. The promo-site text (other repository) is follow-up work.

---

## 5. Change 4 - two skins per fighter

Decision: ADR 006.

### 5.1 What a skin is

A skin is a **look** (existing concept, same profile fields, same `Rewards`) that now consists of a palette **plus
one accessory part**. Accessories are small: they never change the ring, outline thickness, the overall silhouette
or the size; they sit inside the animal's 200 x 200 space and their part box covers at most 25 % of the `body` part's
box area (checked by the art script, which fails otherwise). Accessory colours are never fully cyan `#3FE0FF` or
coral `#FF5A4E`.

### 5.2 The skin list

Every fighter gets exactly two permanent skins: one from the Treasure Path and one from mastery (silver). Seasonal
looks are extra and time-limited, so they do not count towards the two.

| Look id | Animal | Source | Palette (base / shade / accent) | Accessory (slot) | Status |
|---|---|---|---|---|---|
| crab_sunset | crab | path 600 | existing | sunglasses (face) | existing look, gains accessory |
| crab_golden | crab | mastery silver | golden | crown (top) | new |
| octopus_midnight | octopus | path 1750 | existing | nightcap (top) | existing look, gains accessory |
| octopus_golden | octopus | mastery silver | golden | crown (top) | new |
| gull_captain | gull | path 1300 | `#F4F1E8` / `#D6D2C4` / `#2F4B7C` | captain_cap (top) | new |
| gull_golden | gull | mastery silver | golden (beak `#F2A93B`) | crown (top) | new |
| puffer_lagoon | puffer | path 900 | `#9BD35A` / `#7AB23F` / `#E8F5C8` | goggles (face) | new |
| puffer_golden | puffer | mastery silver | golden | crown (top) | new |
| otter_sailor | otter | path 250 | `#B58457` / `#946640` / `#F0DDBF` | scarf (neck) | new |
| otter_golden | otter | mastery silver | golden | crown (top) | new |
| seal_dapper | seal | path 1500 | `#6E7C8A` / `#56636F` / `#B3BEC9` | bow_tie (neck) | new |
| seal_golden | seal | mastery silver | golden | crown (top) | new |
| hermit_blossom | hermit | path 750 | body default, `shell: #F7B2C4`, `shell_shade: #E08FA6` | flower (top, on the shell) | new |
| hermit_golden | hermit | mastery silver | golden (shell golden too) | crown (top) | new |
| star_sunny | star | path 2100 | `#F2C46B` / `#D9A64A` / `#FFE6B0` | sun_hat (top) | new |
| star_golden | star | mastery silver | golden | crown (top) | new |
| crab_storm | crab | Storm Season 350 | existing | souwester (top) | existing seasonal extra, gains accessory |
| octopus_storm | octopus | Storm Season 500 | existing | souwester (top) | existing seasonal extra, gains accessory |
| gull_storm | gull | Storm Season 200 | existing | souwester (top) | existing seasonal extra, gains accessory |

"golden" = `#E8B23A` / `#C48F22` / `#FFE7A3`. Players who already own a look keep it; it simply gains its accessory.

### 5.3 Data and pipeline

**Gull beak rename.** The gull's beak currently uses the part name `accessory`. Rename it to `mouth` (it is the gull's
mouth) in `tools/art/animals.py` (`gull()` and `PARENTS`), so `accessory` is free for skins. The regenerated output
moves `assets/animals/gull/accessory.svg` to `mouth.svg` (and the same in `assets/looks/gull_storm/`); move the
`.svg.import` files along.

**Slots per animal** in `tools/art/animals.py` (`SLOTS[animal][slot] = (x, y, parent, z, scale)`), written into the
rig as `"slots": {"top": {"at": [x, y], "parent": "head", "z": 4}, ...}`. Slots: `top` (crown of the head / top of
the shell / top arm), `face` (over the eyes), `neck` (between head and body). At minimum every animal has the slots
its skins use.

**Accessory library** in a new module `tools/art/accessories.py` (stdlib only, imported by `animals.py`): one function
per kind, `draw(kind, at, scale, colours) -> svg_body`, drawn in animal space with the same outline. Kinds:
`crown`, `sunglasses`, `nightcap`, `captain_cap`, `goggles`, `scarf`, `bow_tie`, `flower`, `sun_hat`, `souwester`.
Each kind has default colours (overridable per look with `acc_base`, `acc_shade`, `acc_detail`).

**Look definition** in `palette.json` `looks` (source of truth for art):
```json
"otter_sailor": { "animal": "otter", "base": "#B58457", "shade": "#946640", "accent": "#F0DDBF",
                  "accessory": { "kind": "scarf", "slot": "neck" }, "acc_base": "#2F4B7C", "acc_shade": "#F7FBF8" }
```

**Generated manifest** `data/looks.json` (written by `animals.py`, checked by CI like the rigs):
```json
{ "version": 1, "looks": { "otter_sailor": { "animal": "otter",
    "accessory": { "name": "accessory", "parent": "head", "pivot": [100, 96], "z": 4, "box": [70, 82, 60, 30] } } } }
```
`animals.py` writes `assets/looks/<look>/accessory.svg` next to the recoloured parts, and writes a `<part>.svg.import`
with `svg/scale=2.0` for every new SVG that has none yet (copy an existing one as template and let Godot assign the
uid on `--import`; `test_every_asset_has_credits` checks the scale). The CI step "Generated art is up to date" adds
`data/looks.json` to its `git diff --exit-code` list.

**Cutout.** `Cutout.build(id, look)`: after building the rig parts, if `data/looks.json` has an accessory for `look`,
add one more joint exactly like a rig part (texture `res://assets/looks/<look>/accessory.svg`, its pivot, box, z,
parent). No other code changes; animations treat it like any child of its parent.

### 5.4 Getting skins (no power, ever)

| Source | How | Data |
|---|---|---|
| Treasure Path | 6 new looks placed on the path (section 4.4); crab_sunset and octopus_midnight stay | `data/path.json` |
| Mastery silver | reaching silver (25 matches, 5 wins with that animal) grants its `<animal>_golden` look | `data/mastery.json`: add `"look_tier": 2` and `"looks": {"crab": "crab_golden", ...}` for all 8 |
| Season | Storm Season keeps its three looks (extras) | `data/seasons.json` unchanged |
| Shop (later) | may sell further looks; never these 16, never power | - |

`apply_result`: after updating mastery, if `tier_before < look_tier <= tier_after`, grant the mastery look and add it
to the outcome (`"mastery_look": id`) so the result screen can say "New look: ...". `Rewards.reconcile` covers players
who were already silver.

**Collection (`ui/collection_screen.gd`):** `looks_for(animal)` also finds mastery looks and sets `source` to
`COLLECTION_FROM_MASTERY` ("Silver mastery: {matches} matches, {wins} wins" / "Zilver meesterschap: {matches} potjes,
{wins} gewonnen"). Look names: `LOOK_<ID>` keys for the new looks, e.g. `LOOK_CRAB_GOLDEN` "Golden Pinch" / "Gouden
Kees", `LOOK_OTTER_SAILOR` "Sailor Slick" / "Matroos Glij", `LOOK_GULL_CAPTAIN` "Captain Skye" / "Kapitein Skye",
`LOOK_PUFFER_LAGOON` "Lagoon Puff" / "Lagune-Puf", `LOOK_SEAL_DAPPER` "Dapper Bumper" / "Chique Bonk",
`LOOK_HERMIT_BLOSSOM` "Blossom Shelly" / "Bloesem-Schelpje", `LOOK_STAR_SUNNY` "Sunny Twinkle" / "Zonnige Twinkel",
and `LOOK_<ANIMAL>_GOLDEN` for the other golden looks ("Golden Inka", "Golden Skye", "Golden Puff", "Golden Slick",
"Golden Bumper", "Golden Shelly", "Golden Twinkle" / "Gouden ..."). `RESULT_MASTERY_LOOK`: "New look: {look}!" /
"Nieuwe look: {look}!".

---

## 6. Work breakdown for the developer

Three feature branches, merged to `develop` in this order. Within a branch the steps are sequential (they touch the
same files). A branch is merged only when all its steps are done and every test is green: new animals must never be
picked by bots before their art exists.

| Branch | Steps |
|---|---|
| `feature/livelier-bots` | a1, a2, a3 |
| `feature/new-fighters` | b1, b2, b3 |
| `feature/fighter-skins` | c |

### Step a1 - tagline and measuring tool
1. Tagline (section 2).
2. `tests/test_player.gd` (move `_player_cmd` out of `run_tests.gd`), `tests/bot_metrics.gd/.tscn` (section 3.8).
3. Run it on the **old** bots and hand the output to the tester as the baseline (easy, normal, hard, 100 matches each,
   with and without `--human=1`).
Acceptance: A-T1..A-T4; the metrics tool runs headless and prints every metric of 3.8; same seed gives identical output
twice.

### Step a2 - bot rework (existing three animals)
1. `Ent` fields of 3.4 (all of them, including `guard`), `vx/vy` in the sim, `attack_range` with `back`.
2. `data/bots.json` v2, `BotBrain` layers (3.5) and special use for `dash`, `ink`, `dive` (3.6).
3. `BallBrain` changes of 3.7 for the existing kinds.
4. Re-record golden traces (`--update-golden`) and the replay fixture (ADR 003): rename
   `tests/golden/replays_windows.json` to `tests/golden/replays_recorded.json` with fresh content produced the same way
   as `test_score_check` builds its sample (one honest score, three rejected), and point the test at the new file.
5. Light bot check in `run_tests.gd`: `test_bots_fight()` - 4 all-bot matches on normal, 1800 ticks each, asserting
   attacks per alive minute >= 10, idle % <= 15, and determinism (same seed twice = same hash).
Acceptance: section 7.2 targets for crab/octopus/gull on all three levels; ball balance goals unchanged;
`ms_per_1000_ticks` at most 2x the a1 baseline.

### 6.1 Result of steps a1 and a2 (measured with `tests/bot_metrics.tscn`, seed 1)

All-bot runs, 200 matches per level (`--human=1` columns: 100 matches). Baseline = old brain, a1 measurement
(commit 13e1d64); new = a2. Wall-clock figures come from a shared machine and vary by 20-30 %.

| Metric | easy old / new | normal old / new | hard old / new |
|---|---|---|---|
| attacks per alive minute (median) | 14.6 / 20.4 | 15.8 / 27.6 | 7.9 / 38.9 |
| hits per attack (single-projectile) | 0.56 / 0.33 | 0.69 / 0.53 | 0.90 / 0.40 |
| specials per alive minute (median) | 2.30 / 1.91 | 2.20 / 4.89 | 1.73 / 5.61 |
| special lag (s) | 0.4 / 0.9 | 0.4 / 0.7 | 0.2 / 0.3 |
| idle % avg (worst bot) | 75.7 (93.9) / 0.0 (0.0) | 74.7 (95.7) / 0.0 (0.1) | 69.3 (94.0) / 0.0 (0.0) |
| fight KOs % | 100 / 100 | 100 / 100 | 100 / 100 |
| avoidable drowning % | 0 / 0 | 0 / 0 | 0 / 0 |
| match duration avg (min) s | 171 (57) / 164 (33) | 63 (26) / 175 (39) | 32 (11) / 152 (30) |
| human focus % (`--human=1`) | 38.7 / 31.5 | 29.5 / 32.1 | 24.5 / 27.2 |
| test player average place | 1.00 / 1.20 | 1.80 / 1.15 | 3.14 / 1.72 |
| `ms_per_1000_ticks` | 152 / 138 | 184 / 170 | 254 / 201 |

Win % per entry (all-bot, 3 animals): easy crab 12.9, gull 22.6, octopus 14.4; normal (400 matches) crab 13.6, gull 23.7,
octopus 12.9; hard crab 15.7, gull 11.2, octopus 23.1. Ball balance (120 matches, normal): 2.93 goals, 0-0 1 %, blue 55 %,
animals 48-53 %, within goals (baseline: 3.13 goals, blue 54 %).

Targets of 7.2 met: attack rate, hits per attack, specials, lag, idle, fight KOs, drowning, average duration, cost
(at most 2x; about 1x). Missed or not comparable:
- **Shortest match**: 33 s (easy, target 45), 39 s (normal, 40), 30 s (hard, 35). The short matches are brawls in which
  several same-animal bots (with the octopus/crab damage multiplier) take each other out within one tide phase.
  Resolution (a3): the single-match minimum is replaced by a 10th-percentile target plus a 25 s floor (7.2).
- **Test player ladder** (normal >= easy + 0.4, hard >= normal + 0.3) is not met: the scripted player deals 100 % damage
  and wins against bots that deal 22-50 %. Bot-vs-bot duration (7.2) and a strong bot against a 100 % player pull in
  opposite directions through `damage_pct`; the duration targets were given priority. Resolution (a3): separate
  `human_damage_pct` (ADR 008, 3.9) and a ladder measured with the `casual` and `skilled` test players (7.2).
- Duration in `--human=1` runs is about 30-65 s (the scripted player wins quickly); the 7.2 duration targets are judged on
  all-bot runs, as the baseline already did.
- Old balance rule (share of wins 22-45 %, `tests/balance.tscn`): gull is at about 45-47 % on easy/normal, crab and octopus
  26-30 %. Per-entry win % of the 8-animal rule (10-24 %) holds for all three animals on easy and normal.

Deviations from the design text of 3.3-3.8:
- `damage_pct` is much lower than proposed (22-50 instead of 60-100): with the proposed attack rates matches lasted
  20-25 s. Tuned together with `fire_gap_ticks` (the cadence limit; `keep_charges` has no effect once the gap is long
  enough that charges are always full), `aim_error`, `lead_pct`, `special_pct`.
- New optional style field `damage_pct` (crab 115, octopus 170): without it the octopus won 2-6 % of the matches (slow on
  dry ground at 80 % speed, lowest hp) and the crab 5 %.
- Gull style `range_pct` 65 / `min_pct` 40 (proposed 75 / 45): at 75 % hard bots dodged nearly every long shot (gull 7 % wins).
- Fire layer fires independent of `engaged` (engaged only steers movement), so `aggression_pct` hardly changes the
  attack rate.
- KO credit in the metrics tool uses the credit window (see 3.8).
- `ball_brain`: dodge overrides the whole move; `_fight` keeps its think-tick cadence but uses lead, fire gap and the
  full `aggression_pct`. Ball bots deal almost no KOs now (0.1 per match, baseline 3.6) because bot `damage_pct` is low
  and the ball mode scales damage down again (65 %); goals and sides are unchanged. Resolution (a3): `ball_damage_pct`.
- Replay fixture: `tests/golden/replays_recorded.json` is rewritten by `run_tests -- --update-golden` (same sample as
  `test_score_check`), so one command re-records both fixtures.

### Step a3 - bot damage against humans (ADR 008)

Same branch (`feature/livelier-bots`), after a2. Order matters: first prove that the split changes nothing, then tune.

1. **Split without effect.** `human_damage_pct` entity field (3.4), `BotBrain.damage_pcts`, `Match.make_bot` (also in
   `to_bot` and `rollback.gd`), `MatchSim._hit_amount` and all call sites of 3.9.2. Temporarily set in `bots.json`
   `human_damage_pct = damage_pct` per level and style `human_damage_pct = damage_pct` for crab (115) and octopus (170),
   no ball keys. Run `bot_metrics` (all-bot, all three levels, 200 matches) and `--human=1 --profile=legacy` (100
   matches): every metric value must equal the a2 numbers in 6.1 (A-B7). Do not commit these temporary values.
2. **Test player profiles** (3.9.4) and the metrics tool additions (3.8: `--profile`, `--ladder`, the new keys,
   `duration_s_p10`; `kos_per_match` in `ball_balance`).
3. **Tune.** Set the starting values of 3.3 (remove the temporary style `human_damage_pct` entries) and tune only
   `human_damage_pct` per level (range 30-200, strictly rising easy < normal < hard) until the human targets of 7.2 hold.
   Tuning order when not everything can be met at once: (1) `skilled` hard win % and the `skilled` ladder, (2) `casual`
   easy win %, (3) early-out shares, (4) the rest; report every miss with its value. Use the style `human_damage_pct`
   only when one animal's bots are measurably out of line (more than 1.5x the average human hits taken from that
   animal per entry); record it in 6.1.
4. **Strandbal.** Tune `ball_damage_pct` per level (start values in 3.3; the pre-a2 `damage_pct` values in
   `git show 13e1d64:data/bots.json` gave 3.6 KOs per match with the old brain and are the reference if they differ)
   until A-B4 including `kos_per_match` holds. Leave `ball_human_damage_pct` absent unless A-B4 fails because of the
   player-free runs (it cannot: `ball_balance` has no human), i.e. it stays absent in a3.
5. **Bot-vs-bot duration.** Do not touch `damage_pct` unless `duration_s_p10` or the 25 s floor (7.2) is missed; then
   tune the level/style `damage_pct` (at most +-25 %) and re-check all all-bot targets.
6. **Tests in `run_tests.gd`:** `test_bot_damage_split` (A-B6) and `test_bots_config`: every level has
   `human_damage_pct` in 30..200 and `easy < normal < hard`.
7. Re-record golden traces and the replay fixture once (`--update-golden`, ADR 003); say so in the commit message.
8. Add the a3 measurement to 6.1 (new table: per level and profile place, win %, early out %, focus %; all-bot p10 and
   minimum; ball KOs per match) and list deviations.

Acceptance: A-B1 (7.2 incl. the new human table), A-B2, A-B4, A-B6, A-B7; A-B3 and A-B5 by the owner.

### Step b1 - fighters: sim, data, bots
1. Sim mechanics 4.2 (mech, intangible/steady, guard, trap, projectile push/back, ball shot table).
2. `animals.json` v3 with the five animals (4.1), `Match.roster()` and its users (4.3, except `default_profile`).
3. Bot special logic for `belly`, `slide`, `puff`, `shell`, `arm` (3.6) and the ball specials (3.7).
4. Unit tests per mechanic in `test_sim_rules` (duels via `_duel`): spines ring fires 8 projectiles in 8 directions;
   boomerang reverses after `back` ticks and can hit on the way back; jet push moves the target by `push` along the
   shot; slide is intangible (a projectile passes through) and refills charges at the end; belly pushes 4200; puff
   grows the radius to 150 % and back after 90 ticks, halves foe damage but not water damage, and bounces a touching
   foe once; shell takes 10 %, blocks attacks and is not moved by a dash; trap does not fire before `arm_ticks`, fires
   on a foe entering the trigger circle, fires by itself at the fuse, max 2 per owner; all new state survives
   `snapshot()`/`restore()` with an identical hash. Guard bounce and trap damage against a human use
   `human_damage_pct` (3.9.2).
5. Re-record golden traces and the replay fixture.

### Step b2 - fighters: art, view, sound, text
Art builders and rigs (4.5), palettes, cutout guard poses, zoo pages, trap marker, projectile shapes, sounds, text
keys, collection descriptions.

### Step b3 - fighters: progression
`free` flag in `default_profile`, path rows for animals (4.4, rows without "c"), `Rewards.reconcile` (points 1 and 2)
in `Platform.load_profile`, tests updated (`test_result_bookkeeping` thresholds, collection tests).
Acceptance for b1-b3: section 7.2 incl. per-animal win % for 8 animals and the human table with the test player on
every free animal, A-B4 for 8 animals, A-F1..A-F9.

### Step c - skins
Gull beak rename, slots, accessory library, palette looks, `data/looks.json`, `.import` files, CI diff list, Cutout
accessory joint, mastery looks (data, `apply_result`, reconcile point 3), path look rows (4.4 rows "c"), collection
sources, text keys. Acceptance: A-S1..A-S9.

Rough size: a1 small, a2 medium-large, a3 medium, b1 large, b2 large (art), b3 small, c medium.

---

## 7. Test plan and acceptance (for the tester)

All runs headless: `godot --headless --path . <scene> -- <args>`. Run `--import` first on a fresh checkout.

### 7.1 Always
- `res://tests/run_tests.tscn` exits 0 (CI too), within the 300 s CI timeout.
- Golden traces green after the intended re-record; a second run gives the same hashes.
- `python3 -I tools/art/animals.py` followed by
  `git diff --exit-code -- assets/animals assets/looks data/rigs data/looks.json` is clean.
- `python3 -I tools/check_budgets.py build/web` passes (every animal and look <= 1024 x 1024 area, web <= 30 MB).
- `scan-ai-traces` 0 failures (pre-push hook).

### 7.2 Bot metrics (`tests/bot_metrics.tscn`, seed 1)

**All-bot runs** (200 matches per level; win % per animal with 400 matches on normal). These do not depend on
`human_damage_pct`.

| Metric | easy | normal | hard |
|---|---|---|---|
| attacks per alive minute (median over bots) | 10-40 | 18-50 | 25-60 |
| hits per attack (single-projectile animals, aggregate) | 0.15-0.45 | 0.25-0.55 | 0.35-0.70 |
| specials per alive minute (median) | >= 0.4 | >= 0.8 | >= 1.2 |
| special lag (average) | <= 8 s | <= 4 s | <= 2 s |
| idle % (average over bots) / worst single bot | <= 12 / <= 25 | <= 8 / <= 20 | <= 6 / <= 15 |
| fight KOs (credited) % of all KOs | >= 35 | >= 50 | >= 60 |
| avoidable drowning % of bot KOs | <= 45 | <= 30 | <= 15 |
| average match duration | 100-190 s | 90-180 s | 80-170 s |
| match duration, 10th percentile (`duration_s_p10`) | >= 80 s | >= 75 s | >= 70 s |
| shortest match (`duration_s_min`) | >= 25 s | >= 25 s | >= 25 s |
| `ms_per_1000_ticks` | <= 2x a1 baseline | <= 2x | <= 2x |

Why the shortest-match target changed: the minimum of 200 matches is a single extreme brawl and jumps with the seed;
the player never sees an all-bot match. The 10th percentile says "short matches are rare", the 25 s floor says "no
match is over before the second tide phase starts". What the player feels is measured below (early out).

**Human runs** (`--human=1 --profile=<p> --ladder=1`, 200 matches per level, seed 1; the test player's animal
rotates over the free animals). "Place" is 1 (won) to 6; "early out" = out before 45 s.

| Metric | easy | normal | hard |
|---|---|---|---|
| `skilled`: average place | <= 2.0 | 2.3-3.3 and >= easy + 0.6 | >= 3.3 and >= normal + 0.5 |
| `skilled`: win % | >= 45 | 15-40 | 3-15 |
| `skilled`: early out % | <= 10 | <= 20 | <= 35 |
| `casual`: average place | <= 2.8 | >= easy + 0.4 | >= normal + 0.3 |
| `casual`: win % | >= 25 | reported | reported |
| `casual`: early out % | <= 15 | <= 30 | reported |
| human focus % (each profile) | <= 35 | <= 35 | <= 40 |
| `legacy`: average place | reported (comparison with 6.1) | reported | reported |

Rationale: the ladder is judged on profiles that miss, move and (skilled) dodge, not on a perfect-aim turret. Easy must
let a casual player win at least 1 in 4 (A-B5); hard must beat a skilled player most of the time but stay winnable
(win 3-15 %). The early-out caps keep hard from feeling unfair: being knocked out in the first 45 s stays the exception.

Per-animal win % per entry (8 animals, normal, 400 matches, all-bot): every animal within **10-24 %** (fair = 16.7 %).
After step a2 (3 animals) the old rule applies: share of wins 22-45 % per animal (`tests/balance.tscn`).
Determinism: the same command twice gives byte-identical JSON output (all-bot, human and ladder runs).

### 7.3 Acceptance per change

Bots (A-B)
- A-B1 All 7.2 targets met (report both tables with the a1 baseline and the a2 values next to them).
- A-B2 `test_determinism`, `test_golden_traces`, `test_rollback`, `test_replay`, `test_score_check` pass.
- A-B3 In an online two-window test (as in phase 12c) bots act identically on both screens (equal hashes), also after
  one player leaves (the leaver's slot becomes a bot with bot damage values on both screens).
- A-B4 Ball balance (`tests/ball_balance.tscn`, 120 matches normal): 2-8 goals per match, 0-0 < 15 %, blue 45-55 %,
  every animal 40-60 %; ball bots' idle % <= 10; KOs per match (`kos_per_match`) 1.0-5.0.
- A-B5 Playtest note (owner): on easy a casual player wins at least 1 in 4 matches; on hard the owner loses most
  matches but wins now and then; bots visibly chase, dodge and fight each other, and bot-vs-bot fights do not look
  strangely harmless next to the damage the player takes. The tester puts the owner's places next to the `casual` and
  `skilled` numbers (3.9.4).
- A-B6 `test_bot_damage_split` in `run_tests.gd` passes, covering:
  1. `Match.create(seed, "crab", 6, "hard")`: entity 0 has `damage_pct == 100` and `human_damage_pct == 100`; every bot
     has the values of `BotBrain.damage_pcts(level_config("hard"), animal, "")`.
  2. A bot projectile hitting the human removes `base * human_damage_pct / 100` HP; hitting a bot removes
     `base * damage_pct / 100`; a human projectile removes `base` from a bot (set up via `_duel` or by placing entities).
  3. The same for a crab dash and a gull dive hitting the human.
  4. Deep-water damage per tick on the human is the same on easy and hard.
  5. `create_online` with two humans: both have 100/100; after `to_bot(1)` slot 1 has bot values and a bot projectile
     hitting it removes `base * damage_pct / 100`.
  6. `mode == "ball"`: bots get `ball_damage_pct`; with the key removed from a test config they fall back to
     `damage_pct` (call `BotBrain.damage_pcts` with a hand-made cfg).
  7. `snapshot()`/`restore()` keeps `human_damage_pct` (equal `state_hash()`).
- A-B7 Regression (step a3.1, with the temporary equal values): all-bot and `legacy` human metrics are identical to the
  a2 values in 6.1. The developer reports the two outputs; the tester re-runs one level to confirm.

Fighters (A-F)
- A-F1 New profile: crab, octopus, gull, otter, hermit unlocked; puffer, seal, star locked with "Treasure Path: 150 /
  350 / 550 pearls".
- A-F2 An existing profile with 600 pearls and only the old three animals loads with puffer, seal, star, otter,
  hermit unlocked and crab_sunset owned (reconcile), without saving first.
- A-F3 Crossing 150 in `apply_result` reports the puffer as newly unlocked.
- A-F4 `Daily.animal_for` returns all 8 ids over seeds 0..7; `Replay.check` accepts all 8 and rejects `shark`.
- A-F5 Every animal builds in the cutout test (`test_cutouts_build` over `roster()`), each part has a texture, the
  rig has <= 12 parts.
- A-F6 The mechanic unit tests listed in step b1 pass.
- A-F7 Every new attack/special kind has its `ATTACK_DESC_*`/`SPECIAL_DESC_*` key in en and nl; the collection
  detail shows them.
- A-F8 Every new sound exists, is imported and passes the loudness check in CI.
- A-F9 Zoo screenshots (all pages) in the CI contact sheet show all 8 animals in all states; owner art review.

Skins (A-S)
- A-S1 `palette.json` has 19 looks; every animal has exactly one path look and one mastery look.
- A-S2 Every look folder contains `accessory.svg`; `data/looks.json` lists it with a box inside 0..200 and an area
  <= 25 % of the body box.
- A-S3 `Cutout.build(animal, look)` adds an `accessory` joint for every look; `build(animal)` (no look) has none.
- A-S4 No part file named `accessory.svg` exists under `assets/animals/` (the gull beak is `mouth.svg`).
- A-S5 A profile reaching silver with the otter gets `otter_golden`; a profile already at silver gets it via
  reconcile; bronze does not.
- A-S6 Owning crab_sunset before the change: it still shows as owned and now has sunglasses.
- A-S7 Collection detail lists both permanent looks per animal with their source text, plus season looks.
- A-S8 No accessory colour is `#3FE0FF` or `#FF5A4E` (checked by the art script).
- A-S9 A profile with 300 pearls loads with `otter_sailor` owned (reconcile of a path look).

Title: A-T1..A-T4 (section 2).

---

## 8. Owner input, costs, resources

| Part | Reused | New | Owner input | Costs / accounts | Extra resources |
|---|---|---|---|---|---|
| Tagline | i18n, boot screen, web shell | one text key | none (spelling "driest" confirmed 2026-11-18) | none | none |
| Bots | sim, RNG, Ent state, balance runner, ball brain roles | layered brain, metrics tool, 12 int fields, damage split, two test player profiles | playtest about 15 min per level after a2 and again after a3 (with places noted) | none | CI about +30 s (light bot check); CPU per tick up to 2x |
| Fighters | projectile model, dash/dive code, cutout pipeline, sfx synth, path/rewards, collection | 2 mechanics (guard, trap) + 3 flags, 5 builders, 10 sounds, about 10 text keys | approve free picks (otter, hermit); art review (zoo contact sheet); approve the relay allowlist change + dev deploy in st33f-engine | none (all art and audio made by code) | web download about +0.3 MB (SVG + Ogg) |
| Skins | looks, palette, rewards, season, mastery counters | accessory library, slots, manifest, mastery looks | approve the skin list and the "golden + crown" mastery theme; art review | none | +16 look folders, each far below the 1024 x 1024 budget |

No paid services, no new accounts.

## 9. Risks and follow-up work

| Risk | Effect | Measure |
|---|---|---|
| Bots too strong for 10+ casual players | Frustration on easy | `casual` easy targets and early-out caps in 7.2; `human_damage_pct` per level; owner playtest A-B5; easy stays the default level |
| Test player profiles are a poor proxy for a human | Ladder tuned to the wrong strength | Two profiles bracket a player; owner places compared with them (A-B5); profiles adjustable without changing targets |
| Bots hurt the player much more than each other | Players may notice bot-vs-bot fights looking harmless | No damage numbers shown; owner playtest note (A-B5); if it shows, raise `damage_pct` and accept longer tuning of bot-vs-bot duration |
| Hard too punishing in online rooms (normal level by default) | Online feels harsher than before | Online uses `normal`; human focus cap; humans in a room all get the same bot damage |
| Different `bots.json` between clients | Online desync | Field is hashed (visible mismatch); follow-up: build/sim version in the lobby URL |
| Bot CPU cost on web/phone | Frame drops | Threat scan capped at 24 projectiles; budget 2x baseline; perf overlay check on the web build |
| Balance of 8 animals and new mechanics | Some animal dominates | Data-only tuning (+-25 %), 400-match runs; tester reports per-animal win % |
| Recorded replays and pending leaderboard scores of older builds no longer verify | Old scores rejected | No real players yet (sign-in waits on the mail route); a sim version field before launch (follow-up, ADR 003) |
| Online: relay still allows only crab/octopus/gull | New animals silently become crab online | Follow-up in st33f-engine `apps/pvp/src/env.ts`; dev deploy needs owner approval |
| Online: two different builds in one room | Desync | Follow-up: build/sim version in the lobby URL, separate queues per version |
| Accessories vs the "never change silhouette" rule | Readability | Size cap (25 % of body box), inside the animal space, never cyan/coral; only the player wears a look |
| Type mix 3 land / 4 water / 1 flyer | Tide favours water animals more often | Watch per-type win % in the metrics; future flyer candidate |
| `crab_sunset` base `#FF6F61` is close to coral | Existing readability issue | Not in scope; noted for the art review |

Follow-up work (for new cards): relay allowlist + lobby version check; sim/rules version in scores before launch;
promo-site text (eight animals, tagline); a mastery gold reward; updating the Dutch design documents outside the repo;
re-run the human table of 7.2 after b1 with all free animals.
