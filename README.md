# AchaeaHidden

When a venom gives you an affliction without saying which, clear the queue and
diagnose.

The game's whole notice is one line:

```
You are confused as to the effects of the venom.
```

On that line the package sends

```
clearqueue all
queue add bal diagnose
```

and says so on a line of its own. The diagnose runs as soon as you have
balance: at once if you have it, otherwise when it returns. A second bite
inside two seconds sends nothing more. That is all it does. It is not gated on
a class.

## Install

Drag `AchaeaHidden.xml` into Mudlet, or build `AchaeaHidden.mpackage` with
`python3 build.py` and install that. `hidden diag` prints the build stamp
`build.py` printed; if the two differ, Mudlet is running an older install.

## Commands

| command | what it does |
| --- | --- |
| `hidden` | whether it is on, what it sends, how often the line has been seen and acted on |
| `hidden on\|off` | act on the line at all (on by default) |
| `hidden clear on\|off` | send `clearqueue all` first, or leave the queue alone (on by default) |
| `hidden send <a;b>` | the commands it sends after that, separated by semicolons |
| `hidden gap <seconds>` | how long a repeat of the line is ignored for (2) |
| `hidden diag` | build stamp, trigger count, where settings are saved |

A `send` you have set is saved and kept across upgrades, so a new default does
not replace it. `hidden send queue add bal diagnose` is the current default.

`hidden clear` alone decides whether the queue is cleared. Up to 0.2.0
`clearqueue all` was the first command in `send`, and a settings file saved by
that version still holds it there; one found in `send` is dropped, so
`hidden clear off` works on an upgraded install and `on` does not clear twice.
With it off, whatever was queued stays queued and the diagnose joins it. That
has not been run in a live client.

The game has no command called `hidden`: sent past the alias, it answers
"I'm sorry, I don't know what "hidden" does." So the prefix shadows nothing.

Settings are saved to `achaea-hidden.lua` in the profile directory. A file
that cannot be read is renamed to `achaea-hidden.lua.bad` at the next save
and is not written over.

## What it rests on

- **The line** was captured from a vampire spider's bite: the attack, a
  `Health lost` line, then the line above and nothing naming an affliction.
  A huge rat's claw prints the same line, so it is not one creature's.
  The harness carries those lines and fires the live trigger on them. The
  pattern is anchored at the start and not at the end, because other packages
  append their own text to lines they time.
- **`CLEARQUEUE ALL` and `QUEUE ADD <queue> <command>`** are `HELP 4.6.1`.
- **`DIAGNOSE`** is `AB SURVIVAL DIAGNOSE`: `DIAGNOSE/DIAG [ME]`, at a cost
  of 1.00 seconds of equilibrium. It also needs balance, which the scroll
  does not say and the game does: sent off balance it answers "You must
  regain balance first."

## If you run Orion

Orion triggers on the same line and does not diagnose. With `ori hiddenchecks`
on, it tries six symptom checks: hold breath for asthma, touch mindseye for
paralysis, and so on. That finds those six and nothing else. The two packages
do not conflict.

## What a live run shows

Five bites while hunting with Orion and Orifox, which clears and refills the
`eb` queue with `queue addclear eqbal` on nearly every prompt. Each time the
bite landed off balance, and each time (abridged: Mudlet's echo of the two
commands and the prompts between are left out):

```
You are confused as to the effects of the venom.
[AchaeaHidden] hidden affliction: clearqueue all, queue add bal diagnose
[System]: All queued commands cleared.
[System]: Added DIAGNOSE to your balance queue.
...
[System]: Queued eb commands cleared.
[System]: Added HUNTING_ATTACK to your eb queue.
You have recovered balance on all limbs.
[System]: Running queued eb command: DIAGNOSE
You are:
afflicted by a crippled left arm.
Equilibrium used: 1.00s.
```

The diagnose waits in the balance queue, the hunting script's `addclear` does
not remove it, and it runs ahead of the re-queued attack when balance returns.
Server-side curing then cured what it named.

**What it costs: about a second per bite, and once a whole attack.** The
diagnose spends a second of equilibrium, so the attack queued behind it fails
with "You must regain equilibrium first", is queued again by the server piece
by piece, and lands when equilibrium returns. The queue holds ten commands
across all types (`HELP 4.6.1`). In one of the five bites the attack alias
was seven commands long, the last piece got "Your queue is full", and that
piece was the attack itself: that round's hit was lost, not delayed.

### Why the balance queue

Four forms were tried against the same hunting setup.

| sent | result |
| --- | --- |
| `diagnose` | Works, three bites in three, but only because the server queues a refused command itself. With `CONFIG USEQUEUEING OFF` it would simply be refused. |
| `queue add eb diagnose` | Does not work. The game confirms "Added DIAGNOSE to your eb queue.", then the hunting script's `addclear eqbal` clears it with its own attack: three bites, no diagnosis. |
| `queue add bal diagnose` | Works, five bites in five. Nothing is refused first, so it should not depend on that setting; it was not tried with the setting off. This is the default. |
| `queue add full diagnose` | Did not run, one bite in one, during the fight or after it. `full` also waits on not being paralysed, and paralysis turned up straight after that bite. `QUEUE LIST` afterwards still showed it queued, with health, equilibrium and balance all up. |

`ADDCLEAR` removes commands "of the specified queue type" (`HELP 4.6.1`), so
an entry in the balance queue is out of reach of a script that owns `eb`.

`DIAGNOSE` typed by hand runs while seated and while paralysed, and reports
both. By `HELP 4.6.1` the `free`, `freestand` and `full` queues wait on not
being paralysed, and the last two on standing, so they wait on conditions the
command does not need. Only `full` was tried.

### Not seen

- `queue add bal diagnose` arriving while you **have** balance. A queued
  command whose condition is already met has been seen to run at once for
  `eb`, and `bal` should do the same. One hit did land on balance, but the
  hunting script's attack ran first and spent it, so the diagnose waited for
  balance as usual.
- Balance returning while equilibrium is still down. The diagnose would then
  be refused; in every bite on record equilibrium was up.
- A hunting script that clears the balance queue too, or no hunting script.

`hidden send` changes the commands without a rebuild.

## Build and test

```bash
python3 build.py
luajit -e "assert(loadfile('AchaeaHidden.lua'))"
luajit test_harness.lua
```

To send a patch, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE), which is also shipped inside the
built `.mpackage`.
