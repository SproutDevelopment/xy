-- Native processing-zone visibility for 【偵探】.
-- A registered physical ID is moved face-down while the matching UseCard
-- event is active. Ordinary card movements retain their original visibility.
local M = {}
local KEY = '_xy__zhentan_hidden_processing_ids'

function M.register(room, ids)
  if type(room) ~= 'table' or type(ids) ~= 'table' then return end
  local active = rawget(room, KEY)
  if not active then active = {}; rawset(room, KEY, active) end
  for _, id in ipairs(ids) do
    if type(id) == 'number' and id ~= 0 then
      active[id] = (active[id] or 0) + 1
    end
  end
end

function M.unregister(room, ids)
  local active = type(room) == 'table' and rawget(room, KEY)
  if not active or type(ids) ~= 'table' then return end
  for _, id in ipairs(ids) do
    local n = active[id]
    if n then
      if n <= 1 then active[id] = nil else active[id] = n - 1 end
    end
  end
  if not next(active) then rawset(room, KEY, nil) end
end

local function isProcessing(move)
  return type(move) == 'table' and move.toArea == Card.Processing
    and type(move.moveInfo) == 'table' and #move.moveInfo > 0
end

local function hasMarkedId(active, move)
  if not isProcessing(move) then return false end
  for _, info in ipairs(move.moveInfo) do
    if type(info) == 'table' and active[info.cardId] then return true end
  end
  return false
end

function M.hasMarkedMove(room, moves)
  local active = type(room) == 'table' and rawget(room, KEY)
  if not active or type(moves) ~= 'table' then return false end
  for _, move in ipairs(moves) do
    if hasMarkedId(active, move) then return true end
  end
  return false
end

-- MoveCardsData instances wrap their public fields in _data. Construct extra
-- move events with the native class where possible, preserving all fields and
-- the original per-card order. In Lua test fixtures they are plain tables.
local function duplicateMove(move, original, infos)
  local args = {}
  for key, value in pairs(original) do args[key] = value end
  args.moveInfo = infos
  if rawget(move, '_data') then
    if type(MoveCardsData) == 'table'
      and type(MoveCardsData.new) == 'function' then
      return MoveCardsData:new(args)
    end
    return setmetatable({_data = args}, getmetatable(move))
  end
  return setmetatable(args, getmetatable(move))
end

function M.hideMarkedMoves(room, moves)
  local active = type(room) == 'table' and rawget(room, KEY)
  if not active or type(moves) ~= 'table' then return 0 end
  local rewritten, masked = {}, 0
  local changedStructure = false

  for _, move in ipairs(moves) do
    if not hasMarkedId(active, move) then
      rewritten[#rewritten + 1] = move
    else
      -- Partition *contiguous* runs by visibility to preserve moveInfo order.
      -- It is unsafe to mark the whole move hidden if it contains normal IDs.
      local groups = {}
      for _, info in ipairs(move.moveInfo) do
        local hidden = type(info) == 'table' and active[info.cardId] ~= nil
        local last = groups[#groups]
        if not last or last.hidden ~= hidden then
          last = { hidden = hidden, infos = {} }
          groups[#groups + 1] = last
        end
        last.infos[#last.infos + 1] = info
      end

      if #groups == 1 then
        move.moveVisible = false
        move.visiblePlayers = {}
        rewritten[#rewritten + 1] = move
        masked = masked + 1
      else
        changedStructure = true
        local original = rawget(move, '_data') or move
        local snapshot = {}
        for k, v in pairs(original) do snapshot[k] = v end
        -- First group reuses the original object; all later groups retain
        -- the same MoveCardsData metatable and all unrelated metadata.
        for index, group in ipairs(groups) do
          local part = index == 1 and move
            or duplicateMove(move, snapshot, group.infos)
          part.moveInfo = group.infos
          if group.hidden then
            part.moveVisible = false
            part.visiblePlayers = {}
            masked = masked + 1
          end
          rewritten[#rewritten + 1] = part
        end
      end
    end
  end

  -- BeforeCardsMove receives a shared list; do not replace its identity.
  if changedStructure then
    for i = #moves, 1, -1 do moves[i] = nil end
    for i, move in ipairs(rewritten) do moves[i] = move end
  end
  return masked
end

return M
