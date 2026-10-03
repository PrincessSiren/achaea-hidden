# AchaeaHidden

[![mpkg](https://img.shields.io/badge/mpkg-AchaeaHidden-blue)](https://packages.mudlet.org/packages/achaeahidden)
[![release](https://img.shields.io/github/v/release/PrincessSiren/achaea-hidden)](../../releases/latest)

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
inside two seconds sends nothing more. It is not gated on a class.

It also looks at the prompt that follows. If that reads full health **and**
full mana, the bite has almost certainly given you recklessness, and it sends
the line below. A bleeding tick of more than 50 health is checked the same way.

```
curing predict recklessness
```

so server-side curing treats it without waiting for the diagnose. See
[Recklessness](#recklessness) below.

## Install

In Mudlet, type `mpkg install AchaeaHidden`. Or install `AchaeaHidden.mpackage`
from the [latest release](../../releases/latest), or build it yourself with
`python3 build.py`.

A release is one pinned version: it is tagged `v<version>`, and the `.mpackage`
attached to it is built from that tag. `hidden diag` prints the build stamp
`build.py` printed; if the two differ, Mudlet is running an older install.

## Commands

| command | what it does |
| --- | --- |
| `hidden` | whether it is on, what it sends, how often the line has been seen and acted on |
| `hidden on\|off` | act on the line at all (on by default) |
| `hidden clear on\|off` | send `clearqueue all` first, or leave the queue alone (on by default) |
| `hidden send <a;b>` | the commands it sends after that, separated by semicolons |
| `hidden gap <seconds>` | how long a repeat of the line is ignored for (2) |
| `hidden reckless on\|off` | predict recklessness when the prompt after a bite or a bleed reads full (on by default) |
| `hidden diag` | build stamp, trigger count, where settings are saved |

A `send` you have set is saved and kept across upgrades, so a new default does
not replace it. `hidden send queue add bal diagnose` is the current default.

`hidden clear` alone decides whether the queue is cleared. Up to 0.2.0
`clearqueue all` was the first command in `send`, and a settings file saved by
that version still holds it there; one found in `send` is dropped, so
`hidden clear off` works on an upgraded install and `on` does not clear twice.
`hidden send` says so when you type one into it.
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

## Recklessness

Recklessness makes your prompt show full health and mana, whatever you
really have. That makes it the one hidden affliction you can spot without a
diagnose, because a bite always costs health. Every bite on record took 230
to 640 health off its prompt, except for the ones that left it reading
exactly full.

The clearest capture is two giant vampire spider bites in a row. The prompt
read `H:4060|100% M:4994|100%` through both bites and through a toxic relapse.
Then curing touched the tree, the game printed "Prudence rules your psyche
once again.", and the very next prompt read `H:1920|47%`. Another capture
shows the signature from a prompt that was not full: a bite took 444 health
off `H:4039|99%`, and the prompt after it read `H:4060|100% M:4994|100%`.

So after the venom line the package reads GMCP `Char.Vitals` at the next
prompt and checks `hp == maxhp` and `mp == maxmp`. If both are true it sends
`CURING PREDICT <affliction>` ("Tell the system that you think you have an
affliction", `HELP 13.7.8`) on an alert line of its own.

**Why at the prompt and not on the line.** Mudlet handles a GMCP frame the
moment it arrives. Text usually waits for the game's end-of-prompt marker,
so the frame is normally in hand by the time a trigger sees the line. But
when a network read ends partway through a prompt, Mudlet passes the text it
has to the triggers straight away (`cTelnet::gotRest`, at both 4.22.0 and
5.0.1). A trigger on the bite line would then read the vitals of the prompt
*above* the bite, which are usually full, and predict recklessness that is
not there. Three bites on record came right after a full prompt and left
3420 to 3791 below the line. So the package sets up a one-shot prompt
trigger on the line and reads the vitals there. Mudlet marks a line as the
prompt only when it reads the GA, so by then every GMCP frame sent ahead of
the GA has been handled. That Achaea sends the vitals frame ahead of the GA
is its usual ordering rather than something captured; Orion's GMCP echoes
printing above the lines they came with agree with it.

**It needs Mudlet to see prompts.** Mudlet marks prompts from the game's GA
signal, unless the profile has GA forced off. Then no prompt trigger fires,
and the package drops a look that no prompt answers within five seconds
without predicting anything. `hidden diag` counts the dropped looks, so a
number above zero there means the check is not working in that profile.

**Once, not every prompt.** While you are reckless every prompt reads full,
so the package predicts once and then waits. It forgets the prediction when
GMCP reports recklessness cured (`Char.Afflictions.Remove`, which Orion
printed as "Cured Aff: recklessness" in the capture above, while the
affliction was hidden), or when a prompt reads below full, which pinned
vitals cannot, or when you log in again. If GMCP names recklessness outright
(`Char.Afflictions.Add`, or a `Char.Afflictions.List` that includes it)
there is nothing to predict.

A second bite inside the gap sends no second diagnose but is still checked,
since it may be the one that brought recklessness. A bite and a bleed in the
same prompt are checked once. `hidden off` stops all of this along with
everything else.

**Bleeding is checked the same way.** `You bleed <n> health.` costs health
just as a bite does, so when `n` is over 50 the next prompt is checked too.
Eleven bleeding ticks are on record, from 7 to 60. Ten have a prompt after
them, and each of those took exactly its amount off it; the eleventh is the
last line of its capture. The threshold is the one Orion uses for its own
check on this line. A small tick could be cancelled out by a regeneration
tick in the same prompt, leaving the prompt full for an honest reason. That
has not been seen, and no bleed while reckless has been captured either.

Not yet verified:

- **That GMCP is fooled the same way the prompt is.** The captures show the
  prompt. Orion's own recklessness check reads GMCP vitals and compares them
  the same way, which suggests GMCP is pinned too, but that is a script
  author's belief, not a capture.
- **What a prediction costs when it is wrong.** Curing would presumably eat
  lobelia for an affliction you do not have. A miss needs a bite that does no
  damage, or one that lands exactly as health regenerates back to full, and
  neither has been seen.
- **That a lobelia cure also sends `Char.Afflictions.Remove`.** The tree cure
  is captured; the herb is not. If it does not, the next prompt below full
  still clears the prediction. If recklessness ended with neither, and you
  stayed at full health until you were made reckless again, that second time
  would go unpredicted until a prompt dropped below full or you logged in.
- **Where the alert lands.** It is printed from the prompt trigger, on the
  prompt line, starting a line of its own the way the diagnose alert does.
  The diagnose alert's layout was watched live; this one has not been.

## If you run Orion

Orion triggers on the same line and does not diagnose. With `ori hiddenchecks`
on, it tries six symptom checks: hold breath for asthma, touch mindseye for
paralysis, and so on. That finds those six and nothing else. The two packages
do not conflict.

Orion also has a recklessness check of its own (`ori.ssc.recklessCheck`). On
the venom line it runs only when the vitals *before* the bite were short on
both health and mana. Mana is nearly always full while hunting, so in practice
it never fires there. On the bleeding line it runs in the trigger, on the
vitals in hand at that moment, and skips an affliction it has already
predicted or been told about. So on a reckless bleed both packages can send
the prediction, once each. What the game does with a second prediction of the
same affliction has not been seen.

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
