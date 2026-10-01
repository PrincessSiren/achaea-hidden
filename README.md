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
diagnose
```

and says so on a line of its own. A second bite inside two seconds sends
nothing more. That is all it does. It is not gated on a class.

## Install

Drag `AchaeaHidden.xml` into Mudlet, or build `AchaeaHidden.mpackage` with
`python3 build.py` and install that. `hidden diag` prints the build stamp
`build.py` printed; if the two differ, Mudlet is running an older install.

## Commands

| command | what it does |
| --- | --- |
| `hidden` | whether it is on, what it sends, how often the line has been seen and acted on |
| `hidden on\|off` | act on the line at all (on by default) |
| `hidden send <a;b>` | the commands it sends, separated by semicolons |
| `hidden gap <seconds>` | how long a repeat of the line is ignored for (2) |
| `hidden diag` | build stamp, trigger count, where settings are saved |

The game has no command called `hidden`: sent past the alias, it answers
"I'm sorry, I don't know what "hidden" does." So the prefix shadows nothing.

Settings are saved to `achaea-hidden.lua` in the profile directory. A file
that cannot be read is renamed to `achaea-hidden.lua.bad` at the next save
and is not written over.

## What it rests on

- **The line** was captured from a vampire spider's bite: the attack, a
  `Health lost` line, then the line above and nothing naming an affliction.
  The harness carries those lines and fires the live trigger on them. The
  pattern is anchored at the start and not at the end, because other packages
  append their own text to lines they time.
- **`CLEARQUEUE ALL`** is `HELP 4.6.1`.
- **`DIAGNOSE`** is `AB SURVIVAL DIAGNOSE`: `DIAGNOSE/DIAG [ME]`, at a cost
  of 1.00 seconds of equilibrium. It also needs balance, which the scroll
  does not say and the game does: sent off balance it answers "You must
  regain balance first."

## If you run Orion

Orion triggers on the same line and does not diagnose. With `ori hiddenchecks`
on, it tries six symptom checks: hold breath for asthma, touch mindseye for
paralysis, and so on. That finds those six and nothing else. The two packages
do not conflict.

## What a live run showed, and what it did not

The trigger fires and both commands go out. With the bite landing off
balance, the game answered:

```
[System]: All queued commands cleared.
You must regain balance first.
diagnose was added to your balance queue.
```

So the server queues the diagnose by itself, in the **balance** queue.

**Not yet seen: the diagnose then running.** A hunting script that owns the
queue re-queues its attack at once; Orifox, for one, sends
`queue addclear eqbal HUNTING_ATTACK`. `HELP 4.6.1` says `ADDCLEAR` removes
commands "of the specified queue type", and the attack sits in the `eb` queue,
so the diagnose should survive. Nobody has watched it do so. If the
`[AchaeaHidden]` line prints and no diagnose listing follows, `hidden send`
changes the commands without a rebuild.

**Diagnosing costs a second of equilibrium.** That is a second in which
nothing else that needs equilibrium can run, every time the line fires and
the gap has passed.

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
