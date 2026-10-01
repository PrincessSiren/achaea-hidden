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
diagnose runs in a fight: whether `DIAGNOSE` needs balance, and what another
package managing the queue does to it, are both open. See the
README.

## Versions

`0.x`. Minor for a change in behaviour, patch for a fix to something already
released, and it moves **once per merged PR** rather than once per push —
bumping mid-review mints numbers for states nobody installed.

`M.VERSION` in the Lua is the only place it lives; `build.py` reads it.

## Releasing

Pushing a tag `v<version>` is what ships. `release.yml` runs the harness, refuses
a tag whose number `M.VERSION` does not claim, builds the `.mpackage` from that
tag, and attaches it to the release.

Publishing to the Mudlet package repository is a further step, and it is **off
until the registry knows this repo**: `trusted-publishers.json` there pins the
owner, the repo and the workflow file by path, so the step can only fail until
that entry is merged. Set a repository variable `PUBLISH_TO_MUDLET` to `true`
once it is, and note that renaming `release.yml` afterwards revokes publishing.

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
