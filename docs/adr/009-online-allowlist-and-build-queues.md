# ADR 009 - Online: eight animals in the relay, one lobby queue per build

Date: 2026-11-18. Status: accepted.

## Context

The online relay (Pulse, `apps/pvp`) only allowed crab, octopus and gull; any other animal silently became the crab.
With five new fighters that would hide them online. Separately, every client runs the match itself from the same seed,
so two clients with different sim, bot or data versions drift apart (desync) when they share a room. Until now nothing
kept builds apart.

## Options

1. Reject a client whose build differs from the one that opened the lobby.
2. One lobby queue per build id (open lobby); in friends rooms, where the code is all that selects the room, tell the
   player on the other build instead of seating them.
3. Compare a version inside the room only (too late: the match is already seated).

## Decision

Option 2.
- The relay allowlist for Whitecap is the eight animal ids of `data/animals.json`; an unknown id still becomes the
  first (crab).
- The client sends `v=<build id>` on the lobby address. The relay accepts 1-32 characters of letters, digits, `.`,
  `_`, `-`; the open lobby name gets a `:v:<id>` suffix, so players of different builds never meet and nobody is
  turned away. A client without `v` (older builds, other games) shares the queue without suffix.
- Friends rooms keep the room code as their only key. The first player stores the build id; a later joiner on another
  id gets `{type: "error", code: "version_mismatch"}` and the socket is closed. The stored id is replaced when the
  lobby was empty.
- Whitecap's build id (`Match.build_id()`) is `SIM_VERSION` plus an FNV-1a hash of `animals.json`, `rules.json`,
  `bots.json` and `modes/ball.json`. Data changes therefore change the id by themselves; `SIM_VERSION` is bumped by
  hand for code-only changes to the sim or the bots.

## Consequences

- After a release, players on the old and new build wait in separate queues (bots fill the seats), which is better
  than a desync mid-match.
- A code change that alters match results without touching those data files needs a `SIM_VERSION` bump; the
  developer has to remember it (follow-up: derive it from the golden trace hashes in CI).
- Deployed to the dev environment on 2026-11-18 (develop pushes deploy dev); acc and prod only by hand.
