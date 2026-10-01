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
function cecho(text) ECHOED[#ECHOED + 1] = text end
function echo(text) ECHOED[#ECHOED + 1] = text end
function send(cmd) SENT[#SENT + 1] = cmd end
function getMudletHomeDir() return "/profile" end
io.exists = function() return STORED ~= nil or RAISE_ON_LOAD end
table.load = function(_, into)
  if RAISE_ON_LOAD then error("unexpected symbol") end
  for key, value in pairs(STORED) do into[key] = value end
end
table.save = function(_, t)
  SAVED = {}
  for key, value in pairs(t) do SAVED[key] = value end
end
local realRename = os.rename
os.rename = function(from, to) RENAMED[#RENAMED + 1] = from .. " -> " .. to; return true end
local seq = 0
function tempRegexTrigger(re, fn)
  seq = seq + 1
  TRIGGERS[seq] = { re = re, fn = fn }
  return seq
end
function killTrigger(id) TRIGGERS[id] = nil end
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
assert(SAVED.enabled == true and SAVED.send == "clearqueue all;diagnose" and SAVED.gap == 2,
       "every key that is loaded is saved")
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
SENT = {}
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
assert(#SENT == 2 and SENT[1] == "clearqueue all" and SENT[2] == "diagnose",
       "it clears the queue, then diagnoses")
assert(ECHOED[#ECHOED - 1] == "\n", "a trigger's echo starts a line of its own")

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
assert(M.onLine(M.LINE) == true and #SENT == 7
       and SENT[7] == "queue addclearfull eqbal diagnose", "trimmed, blanks dropped")
clock = clock + 5
M.setSend(";")
assert(M.onLine(M.LINE) == false and #SENT == 7, "nothing to send is nothing sent")
assert(M.statusLine():find("sends nothing", 1, true))
M.setSend(M.CONFIG_DEFAULTS.send)
M.COMMANDS = { { usage = "hidden", help = "this list" } }
M.report(); M.diag()

-- ---- a recompile leaves one trigger ---------------------------------------
load()
assert(liveTriggers() == 1, "recompiling must not leave a second trigger sending twice")
M.stop()
assert(liveTriggers() == 0, "stop removes it")

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
M.stop()
os.rename = realRename

print("all harness checks passed")
