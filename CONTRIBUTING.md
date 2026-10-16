# Contributing

Bug reports and ideas are welcome. So are patches, with the caveats below.

## Running it outside Mudlet

Everything here is stdlib Python and Lua 5.1. There is nothing to install.

```bash
luajit test_harness.lua                        # the harness
luajit -e "assert(loadfile('AchaeaHidden.lua'))"   # syntax
python3 build.py                               # rebuild the package
```

Mudlet embeds **Lua 5.1**, and `luajit` is that exact dialect. A 5.4 parser will
accept things Mudlet rejects, so check with `luajit` rather than `lua`.

## The `.xml` is generated, and it is what gets installed

`AchaeaHidden.xml` is built from `AchaeaHidden.lua` by `build.py`. Never edit it
by hand, and **always rebuild after touching the `.lua`** — a `.lua` edited
without a rebuild ships a package that does not match its source, invisibly,
because the diff of the change itself looks fine. CI fails on this.

`build.py` stamps a short content hash into the package, which `hidden diag`
prints back. That is a hash rather than a timestamp on purpose: the `.xml` is
committed, so building twice with no source change has to produce a
byte-identical file.

`ALIASES` in `build.py` is the single source of truth for the commands. It
generates the XML aliases *and* the `AchaeaHidden.COMMANDS` table the in-game help
prints, so the help cannot drift from what is installed. Adding a command is one
row there plus a function in the Lua.

## Where rules come from

This package is small because it is careful about one thing: **what it claims
about Achaea comes from what Achaea printed**, not from what anyone remembers.

- Cite the scroll or the command: `HELP 4.6.1`, `AB SURVIVAL DIAGNOSE`. Naming
  the command matters more than quoting it, because the command still works
  after the quote goes stale.
- **The trigger line is a capture.** `You are confused as to the effects of
  the venom.` was pasted out of a fight, and the harness carries the lines
  around it. If the game words it differently for another source, bring those
  lines; do not add a pattern from memory. A pattern nobody has seen match is
  a reflex that never fires and never says so.
- If you cannot cite it, say so in the PR. An open question recorded honestly is
  worth more than a rule that reads well.

## Testing

`test_harness.lua` stubs Mudlet, reads the pattern off the live trigger and
fires that trigger on the captured lines, so a typo in the pattern or a
dropped registration fails the run.

A green run means the logic and the packaging hold. It does **not** mean the
diagnose runs in a fight. That has been watched in one setup, which the README
describes; any change to what is sent or when wants watching again.

## Mudlet details the code depends on

Checked in Mudlet's source at `Mudlet-4.22.0` and `Mudlet-5.0.1`; the code
comments carry the detail.

- **The alert goes out before the commands and ends without a newline.** In a
  trigger, `TConsole::printCommand` adds a newline after a command's echo, and
  one before it only when the last line is not empty. So a `send` already ends
  the game's line, and a newline of ours on either side of it prints a blank
  line. The other order was seen to print one.
- **The vitals are read at a prompt trigger, never on the venom line.**
  `cTelnet::processSocketData` handles a GMCP frame as it reads it, but text
  reaches the triggers at the GA. The exception comes once a GA has been seen:
  if a network read then ends partway through a prompt, `gotRest` hands over
  what it has straight away, with the previous prompt's frame still in hand. A line is marked as the prompt only when the GA is read
  (unless the profile sets `mFORCE_GA_OFF`). The `'\n'` pushed before
  `gotPrompt` at `Mudlet-4.22.0:src/ctelnet.cpp:4864` is in
  `slot_processReplayChunk`, the replay path, so it says nothing about a live
  connection.

## Versions

`0.x`. Minor for a change in behaviour, patch for a fix to something already
released, and it moves **once per merged PR** rather than once per push —
bumping mid-review mints numbers for states nobody installed.

`M.VERSION` in the Lua is the only place it lives; `build.py` reads it.

## Releasing

Pushing a tag `v<version>` is what ships. `release.yml` runs the harness, refuses
a tag whose number `M.VERSION` does not claim, builds the `.mpackage` from that
tag, and attaches it to the release.

Publishing to the Mudlet package repository is a further step, gated on a
repository variable `PUBLISH_TO_MUDLET`. It has been on since `v0.3.0`.
`trusted-publishers.json` in that repository pins the owner, the repo and the
workflow file by path, so **renaming `release.yml` revokes publishing** until
that entry is amended.

Each publish opens a pull request there, on a branch of its own, and it merges
itself only if the automated review leaves **no feedback on its head commit**.
Replying to the feedback does not clear it; only a new release does. `v0.4.0`
never reached the registry for that reason: the review flagged that the
package description still described `0.3.x`, and `v0.4.1` shipped with the
description fixed. So:

- **When a release changes behaviour, change `DESCRIPTION` in `build.py` with
  it.** That text becomes the package's description in the registry, and the
  review has flagged it once for not matching the release.
- **A stuck pull request stays open after the fix ships.** Each publish opens a
  new one, so the old one has to be closed by a maintainer there. Merging it
  would roll the package back to its version.

Then it announces the release in Discord, if — and only if — a `DISCORD_WEBHOOK`
secret is set on the repository. The message carries the two things a player can
act on: the `.mpackage` and the build stamp `hidden diag` prints back. Not
the version — that says what you expect whether or not anything was rebuilt —
and not the registry pull request, which is this repository's business rather
than the channel's and is in the run log. That is a channel webhook URL from Discord's
*Server Settings → Integrations → Webhooks*, and it is a secret rather than a
setting because it is a bearer credential: anyone holding it can post to that
channel as this package.

The announcement is the last step and the only one allowed to fail. By the time
it runs the release exists and the package is published, so a webhook that is
down is a message nobody got rather than a release that went wrong — it leaves a
warning and the run stays green. Re-running the job to get the message out would
ask the registry to publish the same version twice; post it by hand instead. A
fork has no secret, so the step skips there rather than notifying this
repository's channel about someone else's tag.
