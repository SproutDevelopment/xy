-- 【偵探】Scoped, room-local masking of a single use's public presentation.
-- The underlying UseCardData/card is never modified. All hooks are removed
-- when the corresponding CardUseFinished event fires (including an unmatched
-- or missing use-card battle log). A single dispatcher also supports nesting.
--
-- This extension-only approach is best-effort: it cannot guarantee that every
-- possible UI card animation uses native MoveCards visibility.
local M = {}
local KEY = '_xy__zhentan_intercept_v57'

local USE_LOG_TYPES = {
  ['#UseCardToTargets'] = true, ['#UseVCardToTargets'] = true,
  ['#UseV0CardToTargets'] = true, ['#UseCard'] = true,
  ['#UseVCard'] = true, ['#UseV0Card'] = true,
}

local function idOf(x)
  return type(x) == 'table' and x.id or x
end

local function cardIds(card)
  if not card or not Card or type(Card.getIdList) ~= 'function' then
    return {}
  end
  return Card:getIdList(card) or {}
end

local function sameIds(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' or #a ~= #b then
    return false
  end
  for i = 1, #a do
    if idOf(a[i]) ~= idOf(b[i]) then return false end
  end
  return true
end

local function matchesLog(entry, log)
  if entry.log_done or type(log) ~= 'table'
    or not USE_LOG_TYPES[log.type] or idOf(log.from) ~= entry.fromId then
    return false
  end
  local targets = log.to
  if type(targets) == 'table' then
    if #targets ~= 1 or idOf(targets[1]) ~= entry.toId then return false end
  end
  if #entry.ids == 0 then
    -- Zero-subcard virtual use: there is no physical card ID to match.
    -- Only consume a V0 log; do not swallow a later physical use's log.
    return log.type == '#UseV0CardToTargets' or log.type == '#UseV0Card'
  end
  return sameIds(log.card, entry.ids)
end

local function matchesSound(entry, from, card)
  if entry.sound_done or idOf(from) ~= entry.fromId or not card then
    return false
  end
  -- filterCard may replace a physical card's displayed name. Card IDs are
  -- a stronger identity for that physical use; name is needed for ID-less V0.
  if #entry.ids > 0 then return sameIds(cardIds(card), entry.ids) end
  return card.name == entry.cardName and #cardIds(card) == 0
end

local function restoreMethods(room, state)
  -- If a different extension wrapped a function later, leave that wrapper
  -- in place. Our dormant dispatcher will only delegate to its predecessor.
  for field, hook in pairs(state.hooks) do
    if rawget(room, field) == hook.wrapper then
      rawset(room, field, hook.previousOwn)
    end
  end
  if rawget(room, KEY) == state then rawset(room, KEY, nil) end
end

local function install(room)
  local state = { entries = {}, hooks = {} }
  rawset(room, KEY, state)

  local function hook(field, factory)
    local original = room[field]
    if type(original) ~= 'function' then return end
    local oldOwn = rawget(room, field)
    local wrapper = factory(original)
    state.hooks[field] = { wrapper = wrapper, previousOwn = oldOwn }
    rawset(room, field, wrapper)
  end

  hook('sendLog', function(original)
    return function(self, log, ...)
      for i = #state.entries, 1, -1 do
        local entry = state.entries[i]
        if matchesLog(entry, log) then
          entry.log_done = true
          -- Stop intercepting battle logs immediately after the last pending
          -- one is matched. Other sound/virt-name hooks remain until finish.
          local outstanding = false
          for _, pending in ipairs(state.entries) do
            if not pending.log_done then outstanding = true; break end
          end
          if not outstanding and state.hooks.sendLog
            and rawget(self, 'sendLog') == state.hooks.sendLog.wrapper then
            rawset(self, 'sendLog', state.hooks.sendLog.previousOwn)
          end
          return original(self, {
            type = '#xy__zhentan-hidden-use', from = entry.fromId,
            to = { entry.toId },
          }, ...)
        end
      end
      return original(self, log, ...)
    end
  end)

  -- The stock core plays card-specific sounds *before* use-card logs/moves.
  -- Suppress that one sound/emotion in order not to announce the card name.
  hook('playCardEmotionAndSound', function(original)
    return function(self, from, card, ...)
      for i = #state.entries, 1, -1 do
        local entry = state.entries[i]
        if matchesSound(entry, from, card) then
          entry.sound_done = true
          return
        end
      end
      return original(self, from, card, ...)
    end
  end)

  -- Stock FreeKill calls sendCardVirtName(card.name) *after* moving a
  -- transformed/virtual card into Processing. Do not let it overwrite our
  -- unknown-card label during the detective's guessing window.
  hook('sendCardVirtName', function(original)
    return function(self, ids, name, ...)
      for i = #state.entries, 1, -1 do
        local entry = state.entries[i]
        if #entry.ids > 0 and name == entry.cardName
          and sameIds(ids, entry.ids) then
          return original(self, ids, 'xy__hidden_card', ...)
        end
      end
      return original(self, ids, name, ...)
    end
  end)

  return state
end

function M.begin(room, use, defender)
  if type(room) ~= 'table' or type(use) ~= 'table' or not use.card
    or not defender then return end
  local state = rawget(room, KEY) or install(room)
  for _, entry in ipairs(state.entries) do
    if entry.use == use then return end
  end
  -- A preceding use may already have emitted its log while its card remains
  -- in Processing. Reactivate the one-shot log dispatcher for this new use.
  local logHook = state.hooks.sendLog
  if logHook and rawget(room, 'sendLog') == logHook.previousOwn then
    rawset(room, 'sendLog', logHook.wrapper)
  end
  state.entries[#state.entries + 1] = {
    use = use, fromId = idOf(use.from), toId = idOf(defender),
    cardName = use.card.name, ids = cardIds(use.card),
    log_done = false, sound_done = false,
  }
end

function M.finish(room, use)
  if type(room) ~= 'table' then return end
  local state = rawget(room, KEY)
  if not state then return end
  for i = #state.entries, 1, -1 do
    if state.entries[i].use == use then
      table.remove(state.entries, i)
    end
  end
  if #state.entries == 0 then restoreMethods(room, state) end
end

return M
