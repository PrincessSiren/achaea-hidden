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
  of 1.00 seconds of equilibrium. The scroll does not say whether it needs
  balance, so that is still unknown.

## If you run Orion

Orion triggers on the same line and does not diagnose. With `ori hiddenchecks`
on, it tries six symptom checks: hold breath for asthma, touch mindseye for
paralysis, and so on. That finds those six and nothing else. The two packages
do not conflict.

## Not yet seen working

Nothing here has run in a live profile.

**A hunting script that owns the queue may clear the diagnose.** Orifox, for
one, sends `queue addclear eqbal HUNTING_ATTACK` whenever the queue has no
attack in it. In the capture the bite landed off balance, so `diagnose` would be queued by
the server and not run at once, and that `addclear` may take it out again. If
the `[AchaeaHidden]` line prints and no diagnose follows, that is why.
`hidden send` changes the commands without a rebuild.

**Diagnosing costs a second of equilibrium.** That is a second in which
nothing else that needs equilibrium can run, every time the line fires and
the gap has passed.

**`hidden` has not been typed in game** to check the game has no command of
that name. An alias on a word the game uses would shadow it.

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
