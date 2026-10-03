-- Drives AchaeaHidden.lua under plain luajit against a stubbed Mudlet.
--
--   luajit test_harness.lua
--
-- The package sends commands unasked, so what is under test is the line it
-- fires on, what goes out, and everything it must stay quiet on. The captured
-- lines are put through the live trigger's own pattern, translated rather
-- than retyped: a retyped copy would pass while the package shipped something
-- else.

local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."

local ECHOED, SENT, TRIGGERS, SAVED = {}, {}, {}, nil
local STORED = nil          -- what the settings file holds, or nil for no file
local RAISE_ON_LOAD = false
local RENAMED = {}
local ORDER = {}             -- echoes and sends together, in the order made
function cecho(text) ECHOED[#ECHOED + 1] = text; ORDER[#ORDER + 1] = "echo" end
function echo(text) ECHOED[#ECHOED + 1] = text; ORDER[#ORDER + 1] = "echo" end
function send(cmd) SENT[#SENT + 1] = cmd; ORDER[#ORDER + 1] = "send" end
function getMudletHomeDir() return "/profile" end
io.exists = function() return STORED ~= nil or RAISE_ON_LOAD end
table.load = function(_, into)
  if RAISE_ON_LOAD then error("unexpected symbol") end
  for key, value in pairs(STORED) do into[key] = value end
end
-- Mudlet's table.save returns nothing when it worked and nil plus a message
-- when the file could not be opened; it does not raise. The stub does the same.
local SAVE_FAILS = false
table.save = function(_, t)
  if SAVE_FAILS then return nil, "Permission denied" end
  SAVED = {}
  for key, value in pairs(t) do SAVED[key] = value end
end
local realRename = os.rename
local RENAME_FAILS = false
os.rename = function(from, to)
  if RENAME_FAILS then return nil, "permission denied" end
  RENAMED[#RENAMED + 1] = from .. " -> " .. to
  return true
end
local seq = 0
function tempRegexTrigger(re, fn)
  seq = seq + 1
  TRIGGERS[seq] = { re = re, fn = fn }
  return seq
end
-- Prompt triggers are kept apart: they come and go with each bite, and the
-- counts below are of the two that live as long as the package does.
local PROMPTS = {}
function tempPromptTrigger(fn, expiry)
  seq = seq + 1
  PROMPTS[seq] = { fn = fn, expiry = expiry }
  return seq
end
function killTrigger(id) TRIGGERS[id] = nil; PROMPTS[id] = nil end
local function pendingPrompts()
  local n = 0
  for _ in pairs(PROMPTS) do n = n + 1 end
  return n
end
local HANDLERS = {}
function registerAnonymousEventHandler(event, fn)
  seq = seq + 1
  HANDLERS[seq] = { event = event, fn = fn }
  return seq
end
function killAnonymousEventHandler(id) HANDLERS[id] = nil end
local function raise(event, ...)
  local n = 0
  for _, h in pairs(HANDLERS) do
    if h.event == event then n = n + 1; h.fn(event, ...) end
  end
  return n
end
local function liveTriggers()
  local n = 0
  for _ in pairs(TRIGGERS) do n = n + 1 end
  return n
end

-- The constructs these patterns use and nothing else; anything more errors
-- here instead of passing. `(\d+)` is the bleed line's one capture.
local function pcreToLua(re)
  local lua, i = {}, 1
  while i <= #re do
    local c = re:sub(i, i)
    if re:sub(i, i + 4) == "(\\d+)" then
      lua[#lua + 1], i = "(%d+)", i + 5
    elseif c == "\\" then
      local n = re:sub(i + 1, i + 1)
      assert(n:match("%p"), "pcreToLua: no translation for \\" .. n)
      lua[#lua + 1], i = "%" .. n, i + 2
    elseif c:match("[%(%)%[%]{}|?*+%-%%]") then
      error("pcreToLua: no translation for " .. c .. " in " .. re)
    else
      lua[#lua + 1], i = c, i + 1
    end
  end
  return table.concat(lua)
end

local function load() assert(loadfile(HERE .. "/AchaeaHidden.lua"))() end

-- ---- it installs switched on ----------------------------------------------
load()
assert(AchaeaHidden.CONFIG_DEFAULTS.enabled == true and AchaeaHidden.config.enabled == true,
       "a fresh install acts on the line without being told to")
AchaeaHidden.stop()
AchaeaHidden = nil

-- ---- the file 0.2.0 saved: the clear inside `send`, and no `clear` key ----
STORED = { enabled = true, send = "clearqueue all;queue add bal diagnose", gap = 2 }
load()
assert(AchaeaHidden.config.clear == true, "a file with no `clear` key clears, as it always did")
local upgraded = AchaeaHidden.commands()
assert(#upgraded == 2 and upgraded[1] == "clearqueue all" and upgraded[2] == "queue add bal diagnose",
       "and sends what 0.2.0 sent, each command once")
AchaeaHidden.stop()
AchaeaHidden = nil
STORED = { enabled = true, send = "queue add bal diagnose", gap = 2, clear = false }
load()
assert(AchaeaHidden.config.clear == false, "a saved off comes back off")
AchaeaHidden.stop()
AchaeaHidden = nil

-- ---- a saved file comes back, filtered by name and type -------------------
STORED = { enabled = false, send = "diagnose", gap = "soon", retired = true }
load()
local M = AchaeaHidden
assert(M.config.enabled == false and M.config.send == "diagnose", "saved settings load")
assert(M.config.gap == 2, "a setting of the wrong type keeps its default")
assert(M.config.retired == nil, "a key no version knows does not come back")
assert(M.state.loaded == "ok")
M.setEnabled(true)
M.setSend(M.CONFIG_DEFAULTS.send)
assert(SAVED.enabled == true and SAVED.send == "queue add bal diagnose" and SAVED.gap == 2
       and SAVED.clear == true,
       "every key that is loaded is saved")
assert(M.CONFIG_DEFAULTS.clear == true, "the queue is cleared unless that is turned off")
assert(M.BUILD == "source", "an unbuilt load says so")

-- ---- the line, through the live trigger -----------------------------------
-- What the game printed, pasted from a fight: the attack, the damage, and
-- then the only notice there is. `SOMEONE says` lines and the like are below.
local VENOM_LINE = "You are confused as to the effects of the venom."
local captured = {
  "A vampire spider launches at you, sinking his fangs into your flesh.",
  "Health lost: 444 (poison).",
  VENOM_LINE,
  "You have recovered balance on all limbs.",
}
assert(M.LINE == VENOM_LINE, "the package watches for the captured line")
assert(#M.state.triggers == 2 and liveTriggers() == 2, "two triggers: the venom line, and bleeding")
local trigger = TRIGGERS[M.state.triggers[1]]
assert(trigger.re == M.PATTERN, "the venom line's trigger is the first")
local pattern = pcreToLua(trigger.re)

local clock = 100
M.now = function() return clock end
SENT, ORDER = {}, {}
local hits = 0
for _, text in ipairs(captured) do
  if text:find(pattern) then
    hits = hits + 1
    assert(text == VENOM_LINE, "the trigger fired on: " .. text)
    line = text
    trigger.fn()
  else
    assert(M.onLine(text) == false, "the reader is quiet on: " .. text)
  end
end
assert(hits == 1, "the captured venom line fires the trigger exactly once")
assert(#SENT == 2 and SENT[1] == "clearqueue all" and SENT[2] == "queue add bal diagnose",
       "it clears the queue, then queues a diagnose on balance")
-- Not under `eb`: that is the queue a hunting script clears every prompt, and
-- a diagnose put there was watched being cleared three bites in three.
assert(not M.CONFIG_DEFAULTS.send:find("queue add eb", 1, true)
       and not M.CONFIG_DEFAULTS.send:find("eqbal", 1, true),
       "the default never queues under eb")
-- Mudlet's echo of a sent command starts its own line when the last one is
-- not empty, so a newline of ours next to the sends is a blank line. The
-- alert opens with one, closes without one, and goes out first.
local alert = ECHOED[#ECHOED]
assert(alert:sub(1, 1) == "\n", "a trigger's echo starts a line of its own")
assert(alert:sub(-1) ~= "\n", "and leaves the newline after it to the command echo")
assert(table.concat(ORDER, " ") == "echo send send",
       "the alert is printed before anything is sent")
assert(M.state.sent == 1 and M.state.seen == 1, "and it is counted once")

-- Orion glues stopwatches onto line ends; a tail must not stop it.
assert((M.LINE .. "[Venom] (1.00)"):find(pattern), "no end anchor")
-- Somebody saying the line is not the line.
assert(not ('Someone says, "' .. M.LINE .. '"'):find(pattern), "anchored at the start")
assert(M.onLine('(Party): Someone says, "' .. M.LINE .. '"') == false and #SENT == 2)
assert(M.onLine(nil) == false and M.onLine("") == false, "safe on anything")

-- ---- the gap --------------------------------------------------------------
assert(M.onLine(M.LINE) == false and #SENT == 2, "a repeat inside the gap sends nothing")
clock = clock + 5
assert(M.onLine(M.LINE) == true and #SENT == 4, "past the gap it sends again")
M.setGap("0")
assert(M.onLine(M.LINE) == true and #SENT == 6, "a gap of 0 never holds back")
M.setGap("-1"); M.setGap("soon")
assert(M.config.gap == 0, "a gap that is not a number of seconds is refused")
M.setGap("2")
clock = clock + 5

-- ---- off, and the commands as a setting -----------------------------------
M.setEnabled(false)
assert(M.onLine(M.LINE) == false and #SENT == 6, "off sends nothing")
assert(M.state.seen == 5, "but the line is still counted")
M.setEnabled(true)
M.setSend(" queue addclearfull eqbal diagnose ; ")
assert(M.onLine(M.LINE) == true and #SENT == 8 and SENT[7] == "clearqueue all"
       and SENT[8] == "queue addclearfull eqbal diagnose", "trimmed, blanks dropped")
clock = clock + 5
M.setSend(";")
assert(M.onLine(M.LINE) == false and #SENT == 8, "nothing to send is nothing sent")
assert(M.statusLine():find("sends nothing", 1, true))
M.setSend(M.CONFIG_DEFAULTS.send)

-- ---- clearing the queue is a switch of its own ----------------------------
clock = clock + 5
SENT, ORDER = {}, {}
M.setClear(false)
assert(SAVED.clear == false, "the switch is saved")
assert(M.onLine(M.LINE) == true and #SENT == 1 and SENT[1] == "queue add bal diagnose",
       "off, the diagnose is queued and nothing is cleared")
assert(not M.statusLine():find("clearqueue", 1, true), "and the status line says what goes out")
-- What 0.2.0 wrote to the settings file: the clear as the first word of
-- `send`. The switch has to win over it both ways.
clock = clock + 5
SENT = {}
M.setSend("clearqueue all;queue add bal diagnose")
assert(M.onLine(M.LINE) == true and #SENT == 1 and SENT[1] == "queue add bal diagnose",
       "off beats a clear left in `send` by an older version")
clock = clock + 5
SENT = {}
M.setClear(true)
assert(M.onLine(M.LINE) == true and #SENT == 2
       and SENT[1] == "clearqueue all" and SENT[2] == "queue add bal diagnose",
       "on, the same file clears once and not twice")
clock = clock + 5
SENT = {}
ECHOED = {}
M.setSend(" ClearQueue  ALL ; diagnose")
assert(ECHOED[#ECHOED]:find("in send is ignored", 1, true), "typing one into send says it is dropped")
assert(M.onLine(M.LINE) == true and #SENT == 2 and SENT[2] == "diagnose",
       "however it was typed")
clock = clock + 5
SENT = {}
M.setSend(";")
assert(M.onLine(M.LINE) == false and #SENT == 0,
       "with nothing to send, the queue is not cleared for nothing")
ECHOED = {}
M.setSend(M.CONFIG_DEFAULTS.send)
assert(not ECHOED[#ECHOED]:find("ignored", 1, true), "and a send without one says nothing of it")
M.COMMANDS = { { usage = "hidden", help = "this list" } }
M.report(); M.diag()

-- ---- recklessness, read at the prompt after the bite ---------------------
-- Vitals as Achaea sends them, strings, with the numbers from the captures in
-- the evidence corpus: 4060 health and 4994 mana at full. In the giant vampire
-- spider capture the prompt read 4060|100% through two bites and a relapse,
-- until "Prudence rules your psyche once again." and then 1920|47%.
--
-- The order the harness drives is the game's: the line, then the prompt's
-- GMCP frame (raised as Mudlet reads it), then the prompt line, which fires
-- the prompt triggers. A line can reach the triggers before or after its
-- frame, depending on where a network read ended; the prompt cannot.
local function vitals(hp, mp)
  return { hp = tostring(hp), maxhp = "4060", mp = tostring(mp), maxmp = "4994" }
end
local function frame(v)
  gmcp = gmcp or {}
  gmcp.Char = gmcp.Char or {}
  gmcp.Char.Vitals = v
  raise("gmcp.Char.Vitals")
end
local function prompt(v)
  if v then frame(v) end
  local fired = 0
  for id, p in pairs(PROMPTS) do
    fired = fired + 1
    if p.expiry == 1 then PROMPTS[id] = nil end
    p.fn()
  end
  return fired
end
local function bite()
  line = M.LINE
  trigger.fn()
end
local function affs(kind, value)
  gmcp = gmcp or {}
  gmcp.Char = gmcp.Char or {}
  gmcp.Char.Afflictions = { [kind] = value }
  raise("gmcp.Char.Afflictions." .. kind)
end
assert(M.CONFIG_DEFAULTS.reckless == true and M.config.reckless == true,
       "recklessness is predicted unless that is turned off")
clock = clock + 5
SENT, ORDER, ECHOED = {}, {}, {}
local predicted = M.state.predicted

-- Three bites on file followed a full prompt (4060 and 4994) and left 3538,
-- 3791 and 3420. A read that ends just after the line leaves that full
-- prompt's frame in hand when the trigger fires; the prompt has the real one.
for _, hp in ipairs({ 3538, 3791, 3420 }) do
  clock = clock + 5
  frame(vitals(4060, 4994))
  bite()
  assert(pendingPrompts() == 1, "the line asks for one look at the next prompt")
  assert(prompt(vitals(hp, 4994)) == 1 and pendingPrompts() == 0, "which is spent on it")
end
assert(#SENT == 6 and M.state.predicted == predicted,
       "full before the bite and short after it only diagnoses")

-- The unknown venom capture: 444 poison off a 4039|99% prompt, and the prompt
-- after it read 4060|100% 4994|100%.
clock = clock + 5
SENT, ORDER, ECHOED = {}, {}, {}
frame(vitals(4039, 4994))
bite()
assert(#SENT == 2, "the diagnose goes on the line")
prompt(vitals(4060, 4994))
assert(#SENT == 3 and SENT[3] == M.RECKLESS and M.RECKLESS == "curing predict recklessness",
       "a bite that leaves the prompt full predicts recklessness")
assert(table.concat(ORDER, " ") == "echo send send echo send",
       "on an alert of its own, ahead of the send")
assert(ECHOED[#ECHOED]:sub(1, 1) == "\n" and ECHOED[#ECHOED]:sub(-1) ~= "\n"
       and ECHOED[#ECHOED]:find("after the bite: curing predict recklessness", 1, true),
       "starting its own line, as anything a trigger prints must")
assert(M.state.predicted == predicted + 1, "and it is counted")
assert(M.statusLine():find("(" .. (predicted + 1) .. " so far)", 1, true))
assert(M.state.known == true)

-- Pinned: the giant spider's second bite and every prompt after it read full.
-- Predicted once, not once a prompt.
for _ = 1, 3 do
  clock = clock + 5
  bite()
  prompt(vitals(4060, 4994))
end
assert(#SENT == 3 + 6, "while it is known, bites diagnose and predict nothing more")
-- What Orion printed "Cured Aff: recklessness" from, before "Prudence rules
-- your psyche once again.": a Remove frame, a list of names.
affs("Remove", { "scytherus", "recklessness" })
assert(M.state.known == false, "a cure reported over GMCP forgets it")
clock = clock + 5
SENT = {}
bite()
prompt(vitals(4060, 4994))
assert(#SENT == 3 and SENT[3] == M.RECKLESS, "so the next full bite predicts again")
affs("Remove", { "scytherus" })
assert(M.state.known == true, "another affliction's cure does not")
frame(vitals(1920, 4994))
assert(M.state.known == false, "and a prompt below full, which pinned vitals cannot show, does")
affs("Add", { name = "recklessness" })
assert(M.state.known == true, "an affliction the game names needs no prediction")
clock = clock + 5
SENT = {}
bite()
prompt(vitals(4060, 4994))
assert(#SENT == 2, "so none is sent")
affs("Remove", { { name = "recklessness" } })
assert(M.state.known == false, "and either frame shape is read")

-- A second bite inside the gap: no second diagnose, still looked at.
clock = clock + 5
bite()
clock = clock + 0.5
SENT, ORDER = {}, {}
local acted = M.state.sent
bite()
assert(M.state.sent == acted and pendingPrompts() == 1, "two lines, one look")
prompt(vitals(4060, 4994))
assert(#SENT == 1 and SENT[1] == M.RECKLESS, "inside the gap only the prediction goes")
affs("Remove", { "recklessness" })

-- Health full and mana short is not the signature; nor is the reverse.
for _, v in ipairs({ vitals(4060, 4934), vitals(3925, 4994) }) do
  clock = clock + 5
  SENT = {}
  bite()
  prompt(v)
  assert(#SENT == 2, "both have to read full")
end
-- Numbers rather than strings read the same; missing or empty ones read as not full.
assert(M.fullVitals({ hp = 10, maxhp = 10, mp = 5, maxmp = 5 }) == true)
assert(M.fullVitals({ hp = "10", maxhp = "10" }) == false)
assert(M.fullVitals({ hp = "0", maxhp = "0", mp = "0", maxmp = "0" }) == false)
assert(M.fullVitals(nil) == false and M.fullVitals("H:4060") == false)
clock = clock + 5
SENT = {}
bite()
gmcp = nil
prompt()
assert(#SENT == 2, "no gmcp table is no prediction and no error")
SENT = {}
prompt(vitals(4060, 4994))
assert(#SENT == 0, "a prompt nobody asked about is just a prompt")

-- The switch, and the master switch over it.
M.setReckless(false)
assert(SAVED.reckless == false, "the switch is saved")
assert(M.statusLine():find("not predicted", 1, true))
clock = clock + 5
SENT = {}
bite()
assert(pendingPrompts() == 0, "off, nothing is watched")
prompt(vitals(4060, 4994))
assert(#SENT == 2, "the bite diagnoses and nothing is predicted")
M.setReckless(true)
clock = clock + 5
bite()
M.setReckless(false)
SENT = {}
prompt(vitals(4060, 4994))
assert(#SENT == 0, "turned off between the line and the prompt, nothing goes")
M.setReckless(true)
M.setEnabled(false)
clock = clock + 5
SENT = {}
bite()
prompt(vitals(4060, 4994))
assert(#SENT == 0, "and `hidden off` stops this as well")
M.setEnabled(true)

-- ---- bleeding is checked the same way -------------------------------------
-- From the huge rat claw capture: the raw line, the bleed, and the prompt it
-- took exactly 60 off.
local bleedTrigger = TRIGGERS[M.state.triggers[2]]
assert(bleedTrigger.re == M.BLEED_PATTERN)
local bleedPattern = pcreToLua(bleedTrigger.re)
local function bleed(text)
  local amount = text:match(bleedPattern)
  if not amount then return false end
  line, matches = text, { text, amount }
  bleedTrigger.fn()
  return true
end
assert(not ("Health lost: 60 (raw)."):find(bleedPattern), "the raw line is not the bleed")
assert(not ('Someone says, "You bleed 60 health."'):find(bleedPattern), "anchored at the start")
assert(("You bleed 60 health.[x] (0.10)"):find(bleedPattern), "no end anchor")
assert(not (M.LINE):find(bleedPattern) and not ("You bleed 60 health."):find(pattern),
       "each trigger fires on its own line only")
SENT, ORDER, ECHOED = {}, {}, {}
assert(bleed("You bleed 60 health."))
prompt(vitals(3599, 4994))
assert(#SENT == 0, "a bleed the prompt shows predicts nothing")
frame(vitals(4060, 4994))
assert(bleed("You bleed 60 health."))
prompt(vitals(4060, 4994))
assert(#SENT == 1 and SENT[1] == M.RECKLESS, "a bleed over 50 that leaves the prompt full predicts")
assert(ECHOED[#ECHOED]:find("after bleeding", 1, true), "and says it was the bleeding")
assert(table.concat(ORDER, " ") == "echo send")
affs("Remove", { "recklessness" })
SENT = {}
-- The captured ticks under the threshold: 7, 11, 22, 23, 28, 32, 42, 47.
for _, n in ipairs({ 7, 11, 22, 23, 28, 32, 42, 47, 50 }) do
  assert(bleed("You bleed " .. n .. " health."))
  assert(pendingPrompts() == 0, "a bleed of " .. n .. " is not looked at")
end
-- A bite and a bleed in one prompt: one look, one prediction, named the bite.
clock = clock + 5
SENT, ECHOED = {}, {}
bleed("You bleed 60 health.")
bite()
bleed("You bleed 55 health.")
assert(pendingPrompts() == 1, "one look for the whole prompt")
prompt(vitals(4060, 4994))
assert(#SENT == 3 and SENT[3] == M.RECKLESS, "one prediction")
assert(ECHOED[#ECHOED]:find("after the bite", 1, true), "named after the bite")
affs("Remove", { "recklessness" })
M.setReckless(false)
SENT = {}
bleed("You bleed 60 health.")
prompt(vitals(4060, 4994))
assert(#SENT == 0, "off, bleeding predicts nothing either")
M.setReckless(true)
M.setEnabled(false)
bleed("You bleed 60 health.")
prompt(vitals(4060, 4994))
assert(#SENT == 0, "nor with the package off")
M.setEnabled(true)
assert(M.onBleed(nil) == false and M.onBleed("lots") == false, "safe on anything")
assert(M.onLine("You bleed 60 health.") == false, "and the venom reader is quiet on it")

-- A state table from 0.3.1 has none of the new keys.
M.state.predicted, M.state.known, M.state.prompt, M.state.watching = nil, nil, nil, nil
SENT = {}
bleed("You bleed 60 health.")
prompt(vitals(4060, 4994))
assert(#SENT == 1 and M.state.predicted == 1, "a recompile over 0.3.1's state counts from one")
affs("Remove", { "recklessness" })

-- Stopping with a look pending takes the prompt trigger with it.
bleed("You bleed 60 health.")
assert(pendingPrompts() == 1)
M.stop()
assert(pendingPrompts() == 0 and M.state.prompt == nil, "stop kills a pending prompt trigger")
M.start()
gmcp, matches = nil, nil

-- ---- a recompile leaves one trigger ---------------------------------------
load()
assert(liveTriggers() == 2, "recompiling must not leave a second copy sending twice")
assert(raise("sysUninstall", "SomethingElse") == 1,
       "and one uninstall handler, not one per load")

-- ---- removing the package stops it ----------------------------------------
-- Mudlet removes the aliases and the script and leaves a temp trigger alone,
-- so without this the package goes on clearing the queue with no `hidden off`.
assert(liveTriggers() == 2, "somebody else's package being removed changes nothing")
do
  local src = assert(io.open(HERE .. "/build.py")):read("*a")
  assert(src:match('PACKAGE_NAME = "([^"]+)"') == M.PACKAGE,
         "the name the event is checked against is the one the package is built under")
end
raise("sysUninstall", M.PACKAGE)
assert(liveTriggers() == 0, "removing this package kills both triggers")
assert(raise("sysUninstall", M.PACKAGE) == 0, "and the handler that did it")
-- A state table made by 0.3.0 has no handlers key; stop must not mind.
M.state.handlers = nil
M.stop()
M.start()
assert(liveTriggers() == 2, "start brings them back, as an upgrade does")
M.stop()
assert(liveTriggers() == 0, "stop removes it")

-- ---- a save that fails says so --------------------------------------------
SAVE_FAILS, SAVED, ECHOED = true, nil, {}
assert(M.save() == false and SAVED == nil, "a file that cannot be written is reported")
M.setEnabled(false)
local said = false
for _, text in ipairs(ECHOED) do
  if text:find("could not write", 1, true) then said = true end
end
assert(said, "and the command that changed the setting says it was not kept")
SAVE_FAILS = false
M.setEnabled(true)
assert(SAVED.enabled == true, "a save that works still returns true and writes")

-- ---- an unreadable file is moved aside, never written over ----------------
RAISE_ON_LOAD = true
load()
assert(M.state.loaded == "unreadable")
assert(#RENAMED == 0, "nothing is touched until there is something to save")
M.setEnabled(true)
assert(RENAMED[1] == "/profile/achaea-hidden.lua -> /profile/achaea-hidden.lua.bad",
       "the unreadable file is renamed before the save")
M.setEnabled(true)
assert(#RENAMED == 1, "and only once")
-- A rename that fails must not be followed by a write over the same file.
load()
RENAME_FAILS, SAVED = true, nil
assert(M.save() == false and SAVED == nil, "a file that cannot be moved aside is not written over")
assert(M.state.loaded == "unreadable", "and it is tried again at the next save")
RENAME_FAILS = false
M.stop()
os.rename = realRename

print("all harness checks passed")
