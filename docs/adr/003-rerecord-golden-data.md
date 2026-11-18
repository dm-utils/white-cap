# ADR 003 - Re-record golden traces and replay fixtures; no sim version field yet

Date: 2026-11-18. Status: accepted.

## Context

New bot behaviour, new entity fields and the larger bot roster change every all-bot match. Consequences:
`tests/golden/traces.json` no longer matches, `tests/golden/replays_windows.json` (scores recorded on Windows with the
old bots) no longer verifies, and any score still pending at the leaderboards service from an older build would be
rejected by the nightly replay check, which always runs the current code.

Sign-in does not work for real players yet (the mail route is pending), so no real scores exist.

## Options

1. **Re-record the fixtures** with the new code (`--update-golden`; regenerate the replay fixture through
   `test_score_check`) and accept that older pending scores fail.
2. **Add a sim/rules version** to scores and replays now, and keep old code paths to verify old versions. Correct for
   a live game, but needs a backend change (leaderboards schema, verify workflow checking out the matching ref) for a
   situation that does not exist yet.
3. **Freeze the old bots** for leaderboard matches and use the new bots only elsewhere. Splits the game in two and
   leaves the leaderboards with the passive bots the owner wants gone.

## Decision

Option 1. The replay fixture is renamed to `tests/golden/replays_recorded.json` because it is no longer recorded on
Windows; the CI Linux run and local Linux runs give the cross-platform check from now on. A sim version field is
follow-up work before real players can post scores.

Option 2 is postponed (cost without users). Option 3 is rejected (contradicts the owner's request).

## Consequences

- Each step that changes behaviour re-records golden traces once, deliberately, and says so in the commit message.
- The Windows cross-check of replays is gone until someone records a fixture on Windows again.
- Before launch: add `sim_version` to the score payload and keep the verifier on the matching code (new card).
