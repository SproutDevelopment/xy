-- Shared helpers for Anna / Decryption Angel.
-- Keep outside skills/: loadSkillSkelsByPath expects skills to return skeletons.
local M = {}
M.BASE = "xy__anna"
M.ANGEL = "xy__decrypt_angel"
M.STACK = "@xy__jiemi_stack"
M.PHASE_LIMIT = "@xy__miti_limit"  -- persistent per-play-phase allowance (0..8)
M.PHASE_USED = "xy__miti_used-phase" -- auto-cleared after EVERY phase
M.LIMIT = 8

function M.isAnna(p)
  return p and (p.general == M.BASE or p.general == M.ANGEL or
    p.deputyGeneral == M.BASE or p.deputyGeneral == M.ANGEL)
end

function M.isAngel(p)
  return p and (p.general == M.ANGEL or p.deputyGeneral == M.ANGEL)
end

function M.getStack(p)
  return tonumber(p:getMark(M.STACK)) or 0
end

-- Shared between 【解密】 and 【侦探】 so reverting has one consistent rule.
function M.consumeStack(room, p, amount)
  local old = M.getStack(p)
  local removed = math.min(old, math.max(0, amount or 1))
  if removed == 0 then return 0 end
  room:removePlayerMark(p, M.STACK, removed)
  if M.getStack(p) == 0 and M.isAngel(p) then
    if p.general == M.ANGEL then
      room:changeHero(p, M.BASE, false, false, true, false, false)
    elseif p.deputyGeneral == M.ANGEL then
      room:changeHero(p, M.BASE, false, true, true, false, false)
    end
  end
  return removed
end

function M.typeCounts(card_ids)
  local ret = { [Card.TypeBasic] = 0, [Card.TypeTrick] = 0, [Card.TypeEquip] = 0 }
  for _, id in ipairs(card_ids or {}) do
    local c = Fk:getCardById(id)
    if c and ret[c.type] ~= nil then
      ret[c.type] = ret[c.type] + 1
    end
  end
  return ret
end

function M.askThreeNumbers(room, player, skill_name, prefix)
  local types = {Card.TypeBasic, Card.TypeTrick, Card.TypeEquip}
  local names = {"xy__basic", "xy__trick", "xy__equip"}
  local ret = {}
  for i, t in ipairs(types) do
    -- 0..999 deliberately independent of the hidden hand/deck size.
    local guess = room:askToNumber(player, {
      skill_name = skill_name,
      min = 0,
      max = 999,
      cancelable = false,
      prompt = prefix .. ":::" .. names[i],
    })
    ret[t] = math.max(0, math.min(999, tonumber(guess) or 0))
  end
  return ret
end

function M.allCorrect(guess, actual)
  for _, t in ipairs({Card.TypeBasic, Card.TypeTrick, Card.TypeEquip}) do
    if (guess[t] or -1) ~= (actual[t] or 0) then return false end
  end
  return true
end

-- Each correct role guess permanently raises the number of times 【密题】
-- may be activated in *each* subsequent play phase, capped at eight.
function M.getPhaseLimit(player)
  local value = tonumber(player:getMark(M.PHASE_LIMIT)) or 0
  return math.max(0, math.min(M.LIMIT, value))
end

function M.getPhaseUsed(player)
  return math.max(0, tonumber(player:getMark(M.PHASE_USED)) or 0)
end

function M.getPhaseRemaining(player)
  return math.max(0, M.getPhaseLimit(player) - M.getPhaseUsed(player))
end

function M.grantPhaseLimit(room, player, num)
  local before = M.getPhaseLimit(player)
  local increase = math.max(0, math.floor(tonumber(num) or 0))
  local after = math.min(M.LIMIT, before + increase)
  if after ~= before then room:setPlayerMark(player, M.PHASE_LIMIT, after) end
  return after - before
end

function M.isRoleMode(room)
  -- Unknown/custom identity modes are excluded from role-guess logic.
  for _, p in ipairs(room.players or {}) do
    if p.role ~= "lord" and p.role ~= "loyalist" and
       p.role ~= "rebel" and p.role ~= "renegade" then
      return false
    end
  end
  return true
end

return M
