# ADR 007 - "Survival of the dryest!" as tagline, Whitecap stays the name

Date: 2026-11-18. Status: accepted (spelling to be confirmed by the owner).

## Context

The boot screen shows "WHITECAP" with the line "working title" (`BOOT_WORKING_TITLE`, Dutch "werktitel") under it.
The owner wants the working title replaced by "Survival of the dryest!". The game, repository, package id and promo
site are already called Whitecap.

## Options

1. **Tagline under the name**, identical in English and Dutch: the pun on "survival of the fittest" only works in
   English, and Dutch players of 10+ know the phrase style; one line for both languages.
2. **Translate the tagline** for Dutch (for example "Wie droog blijft, wint!"). Clear, but loses the pun and the
   recognisable line.
3. **Rename the game** to "Survival of the dryest!". Touches export names, package id, store listings and the promo
   site; long for an app icon label.

## Decision

Option 1: key `BOOT_TAGLINE` with the same text in both columns; also in the web loader. The name stays Whitecap.
"Dryest" is kept as the owner wrote it (a recognised variant of "driest" that mirrors "fittest").

Option 2 is rejected because the pun is the point. Option 3 is rejected for its cost and because the owner asked to
replace the working-title line, not the name.

## Consequences

- One text change in code and data; the i18n service gets a new key and drops the old one.
- The promo site can use the tagline later (other repository, follow-up).
