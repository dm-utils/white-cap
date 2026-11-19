# Glossary

| Term | Meaning |
|---|---|
| Accessory | The one extra cutout part a skin adds (hat, scarf, glasses, ...), attached to a rig slot. Never on base animals. |
| Animal / fighter | A playable character (crab, octopus, gull, puffer, otter, seal, hermit, star). Defined in `data/animals.json`. |
| Attack | The normal attack: `count` projectiles with `spread`, `speed`, `life`, `damage`, `radius`; 3 charges. |
| Attack range | `speed * life` of the attack, or `speed * back` for a boomerang. |
| Boomerang (`back`) | Projectile that reverses its direction after `back` ticks (starfish attack). |
| Bot damage | A bot's damage multiplier against other bots (`damage_pct`, level x style). Tuned for bot-vs-bot match length. |
| Bot level | Difficulty preset in `data/bots.json` `levels`: easy, normal, hard. |
| Bot style | Per-animal bot parameters in `data/bots.json` `styles`: preferred range, back-off distance, flee threshold, optional damage factors. |
| Build id | `Match.build_id()`: `SIM_VERSION` plus a hash of the sim data files. Sent to the online lobby; players with different ids are never matched together (ADR 009). |
| Calm start | The first `calm_start_ticks` of a match in which nobody attacks. |
| Charges | Attack ammunition (3), recharging one per `reload_ticks`. |
| Committed target | The foe a bot keeps fighting until `target_until`, unless it dies. |
| Cutout | The animal drawn as separate parts on joints (`view/cutout.gd`), from a rig. |
| Daily challenge | One seed, island, bots and animal per day for everyone. |
| Danger | A bot's view of depth at a point, using the next tide level when the tide is about to rise. |
| Difficulty ladder | The required rise of the test player's average place from easy to normal to hard (docs/design.md 7.2). |
| Dodge | A bot's short sidestep (8 ticks) away from a detected threat. |
| Early out | A match in which the test player is knocked out before 45 s (and did not win). |
| Fight KO | A knockout credited to an animal (last hit within `knockout_credit_ticks`), as opposed to drowning. |
| Free animal | An animal with `free: true`, available from the start (crab, octopus, gull, otter, hermit). |
| Golden trace | Fixed seed + fixed ticks -> recorded state hash; catches unintended rule changes. |
| Guard | Special mechanic: a timed state that reduces damage taken and may grow, slow, block attacks, make steady or bounce foes (puffer, hermit). |
| Human | In the sim: an entity with `is_bot == 0` (the local player, or an online player who has not left). |
| Human damage | A bot's damage multiplier against humans (`human_damage_pct`, level x style). The difficulty knob for the player (ADR 008). |
| Idle % | Share of alive ticks in which a bot did not move at all. |
| Intangible | During an otter slide: projectiles, clouds, blasts and dashes pass through. |
| Kind | The identity of an attack or special (text, sound, bot logic), e.g. `belly`. |
| Look | A cosmetic variant of an animal (palette, and from this round an accessory). Synonym used by players: skin. |
| Mastery | Bronze, silver, gold per animal from matches and wins with it; silver grants the animal's golden look. |
| Mech | The sim mechanic behind a special: `dash`, `cloud`, `dive`, `guard`, `trap`. |
| Pearls | Earned per match; fill the Treasure Path and the season path. Not a currency. |
| Reconcile | `Rewards.reconcile`: on profile load, grant free animals, all path rewards up to the pearl total and reached mastery looks. |
| Reflex layer | The per-tick part of the bot brain that detects threats and starts dodges. |
| Rig | `data/rigs/<id>.json`: parts with pivot, parent, z, box, and accessory slots. |
| Roster | All animals in `data/animals.json`, in file order (`Match.roster()`). |
| Season path | A second free path per season with time-limited looks (Storm Season). |
| Skin | Player-facing word for a look; in this round: palette plus accessory. |
| Slot | A named anchor on a rig (`top`, `face`, `neck`) where an accessory attaches. |
| Special | The second ability; ready after 4 projectile hits. |
| Steady | During the hermit's shell: cannot be pushed. |
| Strandbal | The 3-against-3 beach ball mode (`mode = "ball"`). |
| Tagline | "Survival of the driest!", shown under the name White Cap. |
| Test player | Scripted stand-in for a human in tests (`tests/test_player.gd`). Profiles: `legacy` (perfect-aim turret, golden data), `casual`, `skilled` (difficulty measurement). |
| Threat | Something about to hit a bot: a projectile on course, a dive or trap blast about to land, a dash heading at it. |
| Tide | The water level that rises in phases and shrinks the island; deep water hurts. |
| Trap | Special mechanic: an object that arms, then explodes when a foe touches its trigger circle or when its fuse runs out (starfish arm). |
| Treasure Path | The free reward path filled by pearls (`data/path.json`). |
