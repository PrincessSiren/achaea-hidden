--[[

AchaeaHidden - diagnose when the game says an affliction landed unnamed.

One line of game output, one reflex:

  You are confused as to the effects of the venom.

is all the game says when a venom gives you an affliction without telling you
which. Nothing can be cured by name until it is known, so this clears the
queue and diagnoses, as soon as balance allows:

  clearqueue all
  queue add bal diagnose

`CLEARQUEUE ALL` and `QUEUE ADD` are HELP 4.6.1, and DIAGNOSE is AB SURVIVAL
DIAGNOSE. The line was captured from a vampire spider's bite; the harness
carries the lines around it.

It sends commands to the game unasked, which is the whole of what it does:
what it sends is a setting rather than a constant, and `hidden off` exists.
Clearing the queue first is a switch of its own, `hidden clear`, on unless
turned off. It is not gated on a class, since a venom does not care what you play.

Orion triggers on the same line and never diagnoses: it arms six symptom
checks (`ori hiddenchecks`) and counts in a counter its own comment calls not
working. The two do not conflict.

One hidden affliction can be told without a diagnose. Recklessness shows you
full health and mana whatever you really have, and every bite on record costs
health, so a bite that leaves GMCP Char.Vitals reading hp == maxhp and
mp == maxmp is almost surely it. Then it also sends `curing predict
recklessness` (HELP 13.7.8), so server-side curing eats the lobelia without
waiting to be told. The vitals are read on the line itself: Mudlet handles a
GMCP frame the moment it arrives but holds the text until the prompt's GA, so
by the time a trigger sees the line, the frame in hand is the prompt after the
bite. Bleeding costs health too, so `You bleed <n> health.` with n over 50 is
checked the same way; that is where Orion runs its own check.

Seen working against a hunting script that clears and refills the `eb` queue
on nearly every prompt: the diagnose waits in the balance queue, which that
script leaves alone, and runs when balance returns, ahead of the attack.
`hidden send` is there if another setup needs different commands.

  hidden                  what it sends, and how often it has
  hidden on|off           act on the line at all
  hidden clear on|off     send `clearqueue all` first, or leave the queue be
  hidden send <a;b>       the commands after that, separated by semicolons
  hidden gap <seconds>    how long a repeat of the line is ignored for
  hidden reckless on|off  predict recklessness when a bite leaves vitals full
  hidden diag             build stamp, trigger count, where settings are saved

]]

AchaeaHidden = AchaeaHidden or {}
local M = AchaeaHidden

M.VERSION = "0.4.0"
M.BUILD = M.BUILD or "source"   -- build.py replaces this

-- Settings, and the only keys a saved file is allowed to bring back. Filtered
-- by name and by type on the way in, so a setting dropped in a later version
-- cannot return out of an old file.
local CONFIG_DEFAULTS = {
  enabled = true,                       -- act on the line
  -- Queued on balance by name, not sent bare: DIAGNOSE needs balance, a bare
  -- one sent off balance is only kept if CONFIG USEQUEUEING is on, and one
  -- queued under `eb` shares a queue that hunting scripts clear every prompt.
  send    = "queue add bal diagnose",   -- `;` between commands
  -- Whether CLEARQUEUE ALL goes out first. A switch of its own rather than a
  -- word in `send`, so it can be turned off without retyping the rest.
  clear   = true,
  gap     = 2,                          -- seconds in which a repeat is ignored
  -- Predict recklessness when the prompt after the line shows full vitals.
  reckless = true,
}
M.CONFIG_DEFAULTS = CONFIG_DEFAULTS

M.config = M.config or {}
for key, value in pairs(CONFIG_DEFAULTS) do
  if M.config[key] == nil then M.config[key] = value end
end

-- On the module table rather than in a file-local: Mudlet keeps temp triggers
-- across a script recompile, and a fresh local would lose the id of the old
-- one and install a second, sending everything twice.
M.state = M.state or {
  triggers = {},
  seen     = 0,     -- times the line arrived
  sent     = 0,     -- times it was acted on
  last     = nil,   -- when it was last acted on, M.now()
  predicted = 0,    -- times recklessness was predicted
  loaded   = "none",
}
local S = M.state

-- The game's line. A prefix rather than the whole line: Orion glues
-- stopwatches onto the ends of lines it times, and an end anchor against a
-- line somebody else has appended to never fires.
M.LINE = "You are confused as to the effects of the venom."
M.PATTERN = [[^You are confused as to the effects of the venom\.]]
-- Printed once per bleeding tick, after a `Health lost: <n> (raw).` line. No
-- end anchor, for the same reason as the venom line.
M.BLEED_PATTERN = [[^You bleed (\d+) health\.]]
local function log(message, colour)
  cecho("<" .. (colour or "orange") .. ">[AchaeaHidden]<reset> " .. message .. "\n")
end

-- ------------------------------------------------------------------- settings

function M.path()
  return getMudletHomeDir() .. "/achaea-hidden.lua"
end

function M.load()
  local path = M.path()
  if not (io.exists and io.exists(path)) then
    S.loaded = "none"
    return false
  end
  local stored = {}
  if not pcall(table.load, path, stored) then
    -- table.load runs the file as Lua, so a half-written one raises. Say so,
    -- and let M.save move it aside rather than write over it.
    S.loaded = "unreadable"
    log("could not read " .. path .. "; using the defaults", "red")
    return false
  end
  for key, default in pairs(CONFIG_DEFAULTS) do
    if type(stored[key]) == type(default) then M.config[key] = stored[key] end
  end
  S.loaded = "ok"
  return true
end

function M.save()
  local path = M.path()
  if S.loaded == "unreadable" then
    -- os.rename reports failure by returning nil, not by raising. If the file
    -- could not be moved aside, writing now would destroy the only copy.
    local ok, moved = pcall(os.rename, path, path .. ".bad")
    if not (ok and moved) then
      log("could not move " .. path .. " aside; settings not saved", "red")
      return false
    end
    S.loaded = "ok"
  end
  local out = {}
  for key in pairs(CONFIG_DEFAULTS) do out[key] = M.config[key] end
  -- table.save reports a file it could not open by returning nil and a
  -- message, not by raising, and returns nothing at all when it worked. So the
  -- message is the only sign of a failure, and pcall's own result is not one.
  local ok, _, failed = pcall(table.save, path, out)
  if not ok or failed ~= nil then
    log("could not write " .. path .. "; this setting lasts until Mudlet closes",
        "red")
    return false
  end
  return true
end

-- --------------------------------------------------------------------- reflex

--- Seconds, as fine as the client gives them.
function M.now()
  if type(getEpoch) == "function" then
    local ok, t = pcall(getEpoch)
    if ok and tonumber(t) then return tonumber(t) end
  end
  return os.time()
end

M.CLEAR = "clearqueue all"

--- The commands that go out, in order: the clear when `clear` is on, then
--- what the `send` setting holds. A clear written into `send` is dropped, so
--- the switch is the only thing that decides it: up to 0.2.0 the default
--- `send` began with one, every save wrote it to the settings file, and left
--- in it would be sent with the switch off, or twice with it on.
function M.commands()
  local out = {}
  S.dropped = false
  for cmd in (tostring(M.config.send or "") .. ";"):gmatch("(.-);") do
    cmd = cmd:match("^%s*(.-)%s*$")
    if (cmd:lower():gsub("%s+", " ")) == M.CLEAR then
      S.dropped = true
    elseif cmd ~= "" then
      out[#out + 1] = cmd
    end
  end
  -- Nothing to send is nothing sent; a clear alone would only cost the queue.
  if M.config.clear and #out > 0 then table.insert(out, 1, M.CLEAR) end
  return out
end

-- ----------------------------------------------------------------- recklessness

M.RECKLESS = "curing predict recklessness"
-- A bleed has to be worth more than this to be checked. Orion's threshold,
-- kept: a small tick and a regeneration tick in the same prompt could cancel
-- and leave a prompt full for an honest reason. Eleven ticks are on record,
-- 7 to 60, and every one took exactly its amount off its prompt.
M.BLEED_MIN = 50

--- Whether a Char.Vitals table reads full health and full mana. Achaea sends
--- the numbers as strings, so they are read through tonumber.
function M.fullVitals(v)
  if type(v) ~= "table" then return false end
  local hp, maxhp = tonumber(v.hp), tonumber(v.maxhp)
  local mp, maxmp = tonumber(v.mp), tonumber(v.maxmp)
  if not (hp and maxhp and mp and maxmp) or maxhp <= 0 or maxmp <= 0 then
    return false
  end
  return hp == maxhp and mp == maxmp
end

--- Whether the vitals in hand say recklessness, with the switches on. Called
--- from a trigger, where the frame in hand is already this prompt's: cTelnet
--- raises a GMCP event as soon as it reads the subnegotiation, and passes the
--- text to the trigger engine only at the GA that ends the prompt (both at
--- Mudlet-4.22.0 and 5.0.1). Orion's own echoes from GMCP handlers print
--- above the lines they arrived with, which is the same ordering seen live.
function M.reckless()
  if not (M.config.enabled and M.config.reckless) then return false end
  return M.fullVitals(gmcp and gmcp.Char and gmcp.Char.Vitals)
end

--- Safe on any line: anything but the venom line does nothing.
function M.onLine(text)
  if type(text) ~= "string" or text:sub(1, #M.LINE) ~= M.LINE then return false end
  S.seen = S.seen + 1
  if not M.config.enabled then return false end
  local now = M.now()
  local out = {}
  -- Two bites in one breath want one diagnose, not two fighting over the
  -- queue. The recklessness check is not held back by that: the second bite
  -- may be the one that brought it.
  if not (S.last and now - S.last < (tonumber(M.config.gap) or 0)) then
    out = M.commands()
    if #out > 0 then
      S.last = now
      S.sent = S.sent + 1
    end
  end
  local diagnosing = #out > 0
  local predict = M.reckless()
  if predict then
    S.predicted = (S.predicted or 0) + 1
    out[#out + 1] = M.RECKLESS
  end
  if #out == 0 then return false end
  -- A trigger's echo lands on the line that fired it, so the alert starts
  -- with a newline of its own. It ends without one, and goes out before the
  -- commands: Mudlet's echo of a sent command starts a new line by itself when
  -- the last line is not empty (TConsole::printCommand), so a newline of ours
  -- on either side of the sends is a blank line. Sending first and echoing
  -- "\n" after was seen to print one; this order was watched live and prints
  -- none.
  local what = diagnosing and "hidden affliction: " or "full health and mana after the bite: "
  local said = table.concat(out, ", ")
  if diagnosing and predict then
    said = said .. " (full health and mana after the bite)"
  end
  cecho("\n<orange>[AchaeaHidden]<reset> " .. what .. said)
  for _, cmd in ipairs(out) do send(cmd) end
  return diagnosing
end

--- The bleeding line, with the amount the trigger captured.
function M.onBleed(amount)
  local n = tonumber(amount)
  if not (n and n > M.BLEED_MIN) then return false end
  if not M.reckless() then return false end
  S.predicted = (S.predicted or 0) + 1
  cecho("\n<orange>[AchaeaHidden]<reset> full health and mana after bleeding: " .. M.RECKLESS)
  send(M.RECKLESS)
  return true
end

-- ------------------------------------------------------------------- commands

--- The one renderer for "is this on, and what does it do".
function M.statusLine()
  local commands = M.commands()
  return "status: " .. (M.config.enabled and "ON" or "OFF") .. ", sends " ..
         (#commands > 0 and table.concat(commands, ", ") or "nothing") ..
         " - line seen " .. S.seen .. ", acted on " .. S.sent ..
         "; recklessness " .. (M.config.reckless and "predicted on full vitals" or "not predicted") ..
         " (" .. (S.predicted or 0) .. " so far)"
end

function M.report()
  log(M.statusLine())
  for _, row in ipairs(M.COMMANDS or {}) do
    echo(string.format("  %-22s %s\n", row.usage, row.help))
  end
end

function M.setEnabled(on)
  M.config.enabled = on and true or false
  M.save()
  log(M.statusLine())
  return M.config.enabled
end

function M.setClear(on)
  M.config.clear = on and true or false
  M.save()
  log(M.statusLine())
  return M.config.clear
end

function M.setReckless(on)
  M.config.reckless = on and true or false
  M.save()
  log(M.statusLine())
  return M.config.reckless
end

function M.setSend(text)
  M.config.send = tostring(text or "")
  M.save()
  log(M.statusLine())
  local commands = M.commands()
  -- Typed here it is dropped, which the status line shows only by omission.
  if S.dropped then
    log("a " .. M.CLEAR .. " in send is ignored; `hidden clear on|off` decides it")
  end
  return commands
end

function M.setGap(seconds)
  local n = tonumber(seconds)
  if not n or n < 0 then
    log("gap wants a number of seconds, 0 or more", "red")
    return M.config.gap
  end
  M.config.gap = n
  M.save()
  log("a repeat inside " .. n .. "s is ignored")
  return n
end

function M.diag()
  log("AchaeaHidden " .. M.VERSION .. " build " .. M.BUILD)
  echo("  " .. M.statusLine() .. "\n")
  echo("  pattern:   " .. M.PATTERN .. "\n")
  echo("  bleeding:  " .. M.BLEED_PATTERN .. " (over " .. M.BLEED_MIN .. ")\n")
  echo("  gap:       " .. tostring(M.config.gap) .. "s\n")
  echo("  triggers:  " .. #S.triggers .. " (2 is right; more means a second copy)\n")
  echo("  settings:  " .. M.path() .. " (" .. S.loaded .. ")\n")
end

-- --------------------------------------------------------------- start / stop

-- The name Mudlet knows the package by, which is what its uninstall event
-- carries. build.py has the same string; the harness holds the two together.
M.PACKAGE = "AchaeaHidden"

function M.stop()
  for _, id in ipairs(S.triggers) do pcall(killTrigger, id) end
  S.triggers = {}
  -- `or {}`: the state table outlives a recompile, so one made by a version
  -- that kept no handlers has no such key.
  for _, id in ipairs(S.handlers or {}) do pcall(killAnonymousEventHandler, id) end
  S.handlers = {}
  return true
end

--- Removing the package takes its aliases and its script and leaves a temp
--- trigger behind, still sending commands with no `hidden off` left to stop
--- it. `sysUninstall` rather than `sysUninstallPackage`: it is the one event
--- raised however the package was installed, and one installed through the
--- Module Manager never raises the other. Mudlet raises it before it removes
--- anything, for every package, so the name is checked. An upgrade or a
--- module sync is an uninstall and an install: the new copy's script starts
--- it again.
function M.onUninstall(_, name)
  if name ~= M.PACKAGE then return false end
  M.stop()
  return true
end

function M.start()
  M.stop()
  S.triggers = {
    tempRegexTrigger(M.PATTERN, function() M.onLine(line) end),
    tempRegexTrigger(M.BLEED_PATTERN, function() M.onBleed(matches[2]) end),
  }
  S.handlers = {
    registerAnonymousEventHandler("sysUninstall", M.onUninstall),
  }
  return true
end

M.load()
M.start()
