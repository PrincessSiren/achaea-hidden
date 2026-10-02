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
function killTrigger(id) TRIGGERS[id] = nil end
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

-- The constructs this pattern uses and nothing else; anything more errors
-- here instead of passing.
local function pcreToLua(re)
  local lua, i = {}, 1
  while i <= #re do
    local c = re:sub(i, i)
    if c == "\\" then
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
assert(#M.state.triggers == 1 and liveTriggers() == 1, "one trigger")
local trigger = TRIGGERS[M.state.triggers[1]]
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

-- ---- a recompile leaves one trigger ---------------------------------------
load()
assert(liveTriggers() == 1, "recompiling must not leave a second trigger sending twice")
assert(raise("sysUninstallPackage", "SomethingElse") == 1,
       "and one uninstall handler, not one per load")

-- ---- removing the package stops it ----------------------------------------
-- Mudlet removes the aliases and the script and leaves a temp trigger alone,
-- so without this the package goes on clearing the queue with no `hidden off`.
assert(liveTriggers() == 1, "somebody else's package being removed changes nothing")
do
  local src = assert(io.open(HERE .. "/build.py")):read("*a")
  assert(src:match('PACKAGE_NAME = "([^"]+)"') == M.PACKAGE,
         "the name the event is checked against is the one the package is built under")
end
raise("sysUninstallPackage", M.PACKAGE)
assert(liveTriggers() == 0, "removing this package kills the trigger")
assert(raise("sysUninstallPackage", M.PACKAGE) == 0, "and the handler that did it")
-- A state table made by 0.3.0 has no handlers key; stop must not mind.
M.state.handlers = nil
M.stop()
M.start()
assert(liveTriggers() == 1, "start brings it back, as an upgrade does")
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
