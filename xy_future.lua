-- 【来客】'未来' pile + delayed-use support.
-- Kept outside skills/ to avoid registering this utility as a skill.
local M = {}
M.PILE = "xy__future"
M.NAME = "xy__laike"
M.OWNER = "xy__future_owner"

-- Each Future belongs to its original placer: multiple Annas must not
-- accidentally trigger or use one another's stored cards.
function M.get(target, source)
  local pile = target:getPile(M.PILE) or {}
  if not source then return pile end
  local result = {}
  for _, id in ipairs(pile) do
    local card = Fk:getCardById(id)
    if card and tostring(card:getMark(M.OWNER)) == tostring(source.id) then
      result[#result + 1] = id
    end
  end
  return result
end

function M.count(target, source)
  return #M.get(target, source)
end

function M.place(source, target, ids)
  if source.dead or target.dead or #ids == 0 then return false end
  -- Public special pile: every player sees the real cards (name/suit/number).
  -- addToPile's third argument is moveVisible, so true reveals the cards to
  -- EVERY player rather than restricting visibility through visiblePlayers.
  -- Ownership marks still keep different Annas' Futures separate.
  for _, id in ipairs(ids) do
    source.room:setCardMark(Fk:getCardById(id), M.OWNER, tostring(source.id))
  end
  target:addToPile(M.PILE, ids, true, M.NAME, source)
  return true
end

local function inPile(target, source, cardId)
  for _, id in ipairs(M.get(target, source)) do
    if id == cardId then return true end
  end
  return false
end

-- After paying, the TARGET chooses the actual public card images by ID,
-- not numbered positions. Every player can inspect these Future cards.
local function chooseCancelledFuture(room, source, target, amount)
  local available = M.get(target, source)
  local need = math.min(math.max(0, amount), #available)
  if need == 0 then return {} end
  if need == #available then return available end

  local response = room:askToChooseCardsAndChoice(target, {
    cards = available,
    min_num = need,
    max_num = need,
    choices = {"OK"},
    skill_name = M.NAME,
    -- With no %from/%to, the third colon-separated field is %arg.
    prompt = "#xy__laike-select:::" .. tostring(need),
  }) or {}

  local allowed, selected, seen = {}, {}, {}
  for _, id in ipairs(available) do allowed[id] = true end
  if type(response) == "table" then
    for _, id in ipairs(response) do
      if allowed[id] and not seen[id] then
        selected[#selected + 1] = id
        seen[id] = true
        if #selected == need then break end
      end
    end
  end
  -- Network failure/invalid replies cannot waste a discard already paid for.
  -- Only supplement with THIS Anna's still-available physical cards.
  for _, id in ipairs(available) do
    if #selected >= need then break end
    if not seen[id] then
      selected[#selected + 1] = id
      seen[id] = true
    end
  end
  return selected
end

-- Processing a pile is implemented independently of whether Anna is currently
-- transformed: she must still be able to use "未来" after returning to base form.
function M.resolve(room, source, target)
  if target.dead or M.count(target, source) == 0 then return end
  local before = M.get(target, source)
  local maximum = math.min(#before, #target:getCardIds("he"))
  local discarded = {}
  if maximum > 0 then
    discarded = room:askToDiscard(target, {
      min_num = 0,
      max_num = maximum,
      include_equip = true,
      cancelable = true,
      skill_name = M.NAME,
      prompt = "#xy__laike-offset:::" .. tostring(#before),
    }) or {}
  end
  -- Everyone has been able to see the cards since placement.
  -- Cost is paid first; the target then picks exactly which pictured Future
  -- cards to remove (never automatically oldest-first).
  if target.dead then return end
  local offset = math.min(#discarded, #before)
  for _, id in ipairs(chooseCancelledFuture(room, source, target, offset)) do
    if inPile(target, source, id) then
      room:moveCardTo(id, Card.DiscardPile, nil, fk.ReasonDiscard,
        M.NAME, nil, true, target)
    end
  end
  -- Snapshot remaining pile in placement order.  Another effect may have
  -- modified the pile during card use; validate possession each iteration.
  local remaining = M.get(target, source)
  for _, id in ipairs(remaining) do
    if not inPile(target, source, id) then goto continue end
    if target.dead then break end
    -- The original user must be alive to use a card; otherwise it expires.
    if source.dead then
      room:moveCardTo(id, Card.DiscardPile, nil, fk.ReasonDiscard,
        M.NAME, nil, true, source)
      goto continue
    end
    local card = Fk:getCardById(id)
    -- Use the actual Future card as a subcard of the appropriate card name.
    -- Some cards (e.g. Jink, Nullification, equip) cannot legally be used
    -- against another character. If the engine rejects them, discard them.
    local used = nil
    if card then
      used = room:useVirtualCard(card.name, {id}, source, {target},
        M.NAME, true, {bypass_distances = true, bypass_times = true})
    end
    -- A rejected use (or an engine version that did not consume subcards)
    -- must not leave an unresolvable Future stuck on the general.
    if inPile(target, source, id) then
      room:moveCardTo(id, Card.DiscardPile, nil, fk.ReasonDiscard,
        M.NAME, nil, true, source)
    end
    ::continue::
  end
end

return M
