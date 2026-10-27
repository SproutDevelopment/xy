-- 安娜【密题】：逐人猜身分。无QML、无一对一配对限制。
-- 选项来自本局所有玩家的实际身份种类（包含死亡角色的身份）。
-- 正确名单储存在安娜的隐藏玩家标记；已公开身份≠猜对。
local M = {}

M.CORRECT_MARK = "xy__miti_correct_ids"

local KNOWN_ORDER = {"lord", "loyalist", "rebel", "renegade"}
local KNOWN = {}
for _, name in ipairs(KNOWN_ORDER) do KNOWN[name] = true end
local INVALID = {unknown = true, hidden = true, unassigned = true, spectator = true}
local ROLE_CHOICE_PREFIX = "xy__miti_guess_"
local SKIP_CHOICE = "xy__miti_skip"

local function validRole(value)
  return type(value) == "string" and value ~= "" and not INVALID[value]
end

local function correctIds(anna)
  local mark = anna:getMark(M.CORRECT_MARK)
  return type(mark) == "table" and mark or {}
end

function M.wasCorrect(anna, other)
  for _, id in ipairs(correctIds(anna)) do
    if tostring(id) == tostring(other.id) then return true end
  end
  return false
end

function M.markCorrect(room, anna, other)
  if M.wasCorrect(anna, other) then return false end
  -- Copy and reassign rather than mutate mark data in-place.
  local result = {}
  for _, id in ipairs(correctIds(anna)) do result[#result + 1] = id end
  result[#result + 1] = other.id
  room:setPlayerMark(anna, M.CORRECT_MARK, result)
  return true
end

function M.targets(room, anna)
  local targets = {}
  for _, other in ipairs(room.alive_players or {}) do
    if not other.dead and validRole(other.role)
       and not M.wasCorrect(anna, other) then
      targets[#targets + 1] = other
    end
  end
  return targets
end

-- Derive all available ROLE TYPES from the actual game, not the current pool
-- of still-unanswered targets. A choice remains available for every target,
-- even if multiple targets have the same role.
function M.availableRoles(room)
  local pool = room.players or (room.getAllPlayers and room:getAllPlayers()) or {}
  local present = {}
  for _, p in ipairs(pool) do
    if validRole(p.role) then present[p.role] = true end
  end
  local roles = {}
  for _, role in ipairs(KNOWN_ORDER) do
    if present[role] then roles[#roles + 1] = role; present[role] = nil end
  end
  local custom = {}
  for role in pairs(present) do custom[#custom + 1] = role end
  table.sort(custom)
  for _, role in ipairs(custom) do roles[#roles + 1] = role end
  return roles
end

local function choiceKey(role)
  -- Built-in four identities receive explicit localizations. Other roles use
  -- their game-provided identifiers, which FreeKill may translate itself.
  if KNOWN[role] then return ROLE_CHOICE_PREFIX .. role end
  return role
end

local function displayName(other)
  local translated = Fk:translate(other.general or "")
  if type(translated) ~= "string" or translated == "" then
    translated = "角色" .. tostring(other.id)
  end
  -- Seat disambiguates multiple generals with identical display names.
  return translated .. "（座位" .. tostring(other.seat or other.id) .. "）"
end

local function reveal(room, other)
  if not other.role_shown then
    room:setPlayerProperty(other, "role_shown", true)
    room:broadcastProperty(other, "role")
  end
end

-- The player gets one built-in dialog per eligible target, including herself, on Anna's turn start.
-- Calling this is optional for each target: the extra 'skip' choice is not a
-- role guess. Every other choice is reoffered independently for each target.
function M.askAll(room, anna, skillName)
  local targets = M.targets(room, anna)
  local roles = M.availableRoles(room)
  if #targets == 0 or #roles == 0 then return 0, 0 end

  local choices, decode = {}, {}
  for _, role in ipairs(roles) do
    local option = choiceKey(role)
    choices[#choices + 1] = option
    decode[option] = role
  end
  choices[#choices + 1] = SKIP_CHOICE

  local correctlyGuessed = 0
  for i, other in ipairs(targets) do
    -- State can change during a trigger (including death / transformations).
    if not other.dead and not M.wasCorrect(anna, other) then
      local prompt = string.format(
        "【密题】%d. 你猜测武将%s的身份／阵营为？", i, displayName(other)
      )
      local result = room:askToChoice(anna, {
        choices = choices,
        skill_name = skillName,
        prompt = prompt,
        cancelable = false,
      })
      local guessed = decode[result]
      if guessed ~= nil then
        if guessed == other.role and M.markCorrect(room, anna, other) then
          correctlyGuessed = correctlyGuessed + 1
          reveal(room, other)
          room:sendLog({
            type = "#xy__miti-reveal", from = anna.id, to = {other.id},
            arg = Fk:translate(choiceKey(other.role)),
          })
        else
          -- Only says whether the guess is correct, never exposes the answer.
          room:sendLog({type = "#xy__miti-wrong", from = anna.id, to = {other.id}})
        end
      end
    end
  end
  return correctlyGuessed, #targets
end

return M
