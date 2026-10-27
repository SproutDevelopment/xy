-- Shared, engine-side helper for the Death God's name resolution.
-- Only exact, current displayed general names count, not player nicknames.
local M = {}
M.GENERAL = "xy__deathgod"
M.SKILL = "xy__sishen"
M.HIDE_SKILL = "xy__cangshen"

local function visibleName(general)
  if type(general) ~= "string" or general == "" then return nil end
  if not Fk or type(Fk.translate) ~= "function" then return nil end
  local ok, display = pcall(Fk.translate, Fk, general)
  if ok and type(display) == "string" and display ~= "" and display ~= general then
    return display
  end
  return nil
end
M.visibleName = visibleName

local function targetNameMatches(p, message)
  local main = visibleName(p.general)
  local deputy = visibleName(p.deputyGeneral)
  -- Compare the entire UTF-8 message with the complete displayed name.
  -- No trimming, punctuation removal, or substring matching is allowed.
  return (main ~= nil and message == main)
      or (deputy ~= nil and message == deputy)
end
M.targetNameMatches = targetNameMatches

local function isOwner(p)
  return p and not p.dead and type(p.hasSkill) == "function" and p:hasSkill(M.SKILL)
end
M.isOwner = isOwner

function M.availableNames(room)
  local set, names = {}, {}
  for _, p in ipairs(room.players or {}) do
    if not p.dead then
      for _, general in ipairs({p.general, p.deputyGeneral}) do
        local label = visibleName(general)
        if label and not set[label] then
          set[label] = true
          names[#names+1] = label
        end
      end
    end
  end
  table.sort(names)
  return names
end

function M.resolve(room, speaker, raw)
  local message = raw
  if not room or not room.game_started or room.game_finished or not isOwner(speaker) then
    return 0
  end
  -- The C++ chat protocol accepts up to 300 characters (UTF-8 may exceed
  -- 300 bytes). This limit guards callback abuse, not a user word count.
  if type(message) ~= "string" or #message == 0 or #message > 4096 then return 0 end
  -- Only the living holder's exact, unmodified chat message can trigger.
  -- A message containing a name plus any other character does not count.
  -- Multiple living generals with that exact name (including deputies) die.
  local victims = {}
  for _, p in ipairs(room.players or {}) do
    if not p.dead and targetNameMatches(p, message) then
      victims[#victims+1] = p
    end
  end
  -- Resolve from a snapshot. Duplicate-named generals all die.
  local count = 0
  for _, p in ipairs(victims) do
    if not p.dead and not room.game_finished then
      if type(room.sendLog) == "function" then
        room:sendLog({type = "#xy__sishen-kill", from = speaker.id, to = {p.id}, arg = message})
      end
      room:killPlayer({who = p})
      count = count + 1
    end
  end
  return count
end

-- FreeKill's native room chat is handled by C++ RoomBase::chat, *not* Lua.
-- Standard clients never invoke room.callbacks.chat on ordinary chat.
-- A compatible server can forward accepted chat lines to the scheduler with
-- the command xy__sishen_chat and the UTF-8 bytes encoded as hex.
-- See OPTIONAL_ENGINE_PATCHES/apply_patches.py (requires a custom core).
local function decodeHex(s)
  if type(s) ~= "string" or #s % 2 ~= 0 or #s > 8192 then return nil end
  if s:find("[^0-9a-fA-F]") then return nil end
  local result = s:gsub("..", function(b) return string.char(tonumber(b, 16)) end)
  return result
end
M.decodeHex = decodeHex

function M.onChat(room, senderId, data)
  if not room or not room.game_started or room.game_finished then return 0 end
  local id = type(senderId) == "table" and senderId.id or tonumber(senderId)
  if not id or type(room.getPlayerById) ~= "function" then return 0 end
  local speaker = room:getPlayerById(id)
  if not speaker or not isOwner(speaker) then return 0 end
  local hex = type(data) == "table" and data[3] or data
  local message = decodeHex(hex)
  if not message then return 0 end
  return M.resolve(room, speaker, message)
end

function M.installChatListener(room)
  if not room or type(room.addCallback) ~= "function" then return false end
  if room.getTag and room:getTag("xy__deathgod_chat_hook") then return true end
  local previous = room.callbacks and room.callbacks.xy__sishen_chat
  room:addCallback("xy__sishen_chat", function(self, senderId, data)
    if type(previous) == "function" then previous(self, senderId, data) end
    return M.onChat(self, senderId, data)
  end)
  if type(room.setTag) == "function" then
    room:setTag("xy__deathgod_chat_hook", true)
  end
  return true
end

-- 持恆技使用“忽略技能無效”的查詢；不能靠普通 hasSkill()，
-- 否則其他武將的封技可能令 Lua 客戶端誤以為藏身已停止。
function M.hasCangshen(p)
  if not p or p.dead then return false end
  if type(p.hasSkill) == "function" then
    local ok, has = pcall(p.hasSkill, p, M.HIDE_SKILL, true)
    if ok and has then return true end
  end
  for _, s in pairs(p.player_skills or {}) do
    if s == M.HIDE_SKILL or (type(s) == "table" and s.name == M.HIDE_SKILL) then
      return true
    end
  end
  -- General information can be available at GameStart before the skills
  -- roster is replicated; this character's own permanent skill is innate.
  return p.general == M.GENERAL or p.deputyGeneral == M.GENERAL
end

-- Notify compatible clients immediately at GameStart and periodically
-- resynchronise.  Display masking is continuous, not a per-turn activation.
function M.refreshHiddenDescriptions(room)
  if not room or type(room.setBanner) ~= "function" then return false end
  local active = false
  for _, p in ipairs(room.players or {}) do
    if M.hasCangshen(p) then
      active = true
      break
    end
  end
  room:setBanner("xy__cangshen_active", active)
  return active
end
return M
