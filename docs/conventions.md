# Conventions

These are the conventions already used in the codebase, written down; follow them for new work.

## Language and identity

- Code, identifiers, comments, data files, commit messages and project documentation in English.
- Player-facing text only through `tr("KEY")`; every key in `i18n/strings.csv` with an `en` and `nl` column.
- No emoji in code, commits or documentation.

## Simulation and bots (`sim/`, `bots/`)

- Integers only: positions in milli-tiles (1 tile = 1000), speeds per tick (30 ticks/s), HP and damage x100,
  angles 0..4095 (`Fx`), percentages as integer percent, friction per mille.
- No floats, no `randf`/`randi`, no clock, no `delta`, no nodes. Randomness only from `sim.rng` (or a seeded `SimRng`
  stream that does not touch the sim's).
- Everything that can affect the future is an integer field listed in `ENT_FIELDS`, `PROJ_FIELDS`, `CLOUD_FIELDS`,
  `DIVE_FIELDS`, `TRAP_FIELDS` (or the ball lists) so it is hashed, snapshotted and restored.
- Bots are static functions `think(sim, e, cfg) -> cmd`; memory lives on the entity; bots run in entity-id order.
- Tunables live in `data/*.json`, never as magic numbers in code (small geometric constants such as a dodge length
  may be named constants in the bot file).
- An intended behaviour change re-records golden traces (`-- --update-golden`) in the same commit and says so in the
  commit message.

## Data (`data/`)

- One JSON file per concern with a `version` field; bump it when the schema changes.
- Ids are lower-case `snake_case` (`crab`, `otter_sailor`). Text keys are upper-case (`ANIMAL_OTTER`,
  `LOOK_OTTER_SAILOR`, `ATTACK_DESC_<KIND>`, `SPECIAL_DESC_<KIND>`).
- Looks are named `<animal>_<theme>`; mastery looks `<animal>_golden`.
- Generated files (`data/rigs/*.json`, `data/looks.json`, `assets/animals/`, `assets/looks/`, `data/sin_table.json`)
  are never edited by hand; change the generator and rerun it.

## Art (`tools/art/`, `assets/`)

- Cutout part names are stable: `body`, `head`, `eye_l`, `eye_r`, `mouth`, `claw_l`, `claw_r`, `limb_fl`, `limb_fr`,
  `limb_bl`, `limb_br`, `limb_top`, `tail`, `shell`, `accessory`. `accessory` only exists in looks.
- Animal space 200 x 200, origin (100, 172) at the feet, outline 7, at most 12 parts per animal including the
  accessory. SVG parts are imported at `svg/scale=2.0`.
- Every asset has a row (or a covering folder row) in `assets/credits.csv`.
- Animals and accessories are never fully cyan `#3FE0FF` or coral `#FF5A4E` (reserved for player/foe rings).

## Tests (`tests/`)

- `tests/run_tests.tscn` is the CI suite (headless, must stay under the 300 s timeout); heavy runs (balance, bot
  metrics) are separate scenes with a light version inside the suite.
- Every new mechanic gets a unit test via a small duel (`_duel`) and a snapshot/restore hash check.

## Git

- Branches `feature/<name>`, `fix/<name>`, `chore/<name>` off `develop`.
- Commits in English, imperative or conventional style as in the existing history.
