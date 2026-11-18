# ADR 010 - Online: the lobby closes its socket after the match message

Date: 2026-11-18. Status: accepted.

## Context

The lobby (Pulse, `apps/pvp/src/lobby.ts`) sent `{type: "match", ...}` and closed the socket in the same tick. The web
build handles that, but native Godot (Windows, Android) never saw the message: `WebSocketPeer` drops packets that
arrive together with the close frame, in every ready state. The probe reads in all states and still gets nothing; a
local test server that sends and closes in one tick shows the same. The player saw "service not reachable" instead of
a match.

## Options

1. Client only: read packets in CLOSING/CLOSED too. Does not help, the data is already gone inside `WebSocketPeer`.
2. Relay waits before closing (a fixed short delay).
3. Client closes the lobby socket itself after `match`; the relay never closes.

## Decision

Option 2, plus the cheap client side of option 1. The relay sends `match`, waits 1 s (`MATCH_CLOSE_DELAY_MS`) and then
closes the seats' sockets with 1000. The wait is not awaited by the request that triggered the match, so the newest
player's handshake is not held up. `OnlineClient` now also drains packets in CLOSING/CLOSED, so a message that is
still queued when the close arrives is not lost on our side.

Option 3 was rejected: it relies on every client (older builds, other games) behaving, and a client that never closes
would keep its lobby socket forever. A fixed delay needs no client change and works for builds already out. One second
is long enough for a poll at 60 fps on a slow connection and short enough that nobody notices.

## Consequences

- Deployed to dev (develop push of Pulse). Acc and prod follow with the normal release.
- Between `match` and the close, a socket that drops makes the lobby send `waiting` to the others; the client ignores
  it once it left for the match scene.
- Test: `apps/pvp/test/run.mjs` checks the lobby socket is still open 500 ms after `match`;
  `tests/online_client_close.tscn` (local server, no network) checks that `OnlineClient` delivers `match` when the
  server closes shortly after.
