-- XY / Yagami Light: public-mode, per-viewer portrait concealment.
-- While any living xy__cangshen holder exists, a viewer is shown the
-- engine's ordinary unknown general for every OTHER player. Never alter
-- authoritative server player.general/deputyGeneral or the skill list.
--
-- Unlike the older Detective experiment this is persistent: GameStart,
-- role-holder death/revival, and general changes all resynchronise it.
-- Hidden-general modes are excluded to avoid leaking secret identities
-- when the effect ends and real general names are restored.
local D = dofile('./packages/XY/deathgod_utils.lua')
local M = {}
local safeModes = { aaa_role_mode = true, role_mode = true }
local candidateMasks = {'anjiang', 'hiddenone'}
-- Weak keys prevent retained state after a game room is destroyed.
local maskedRooms = setmetatable({}, {__mode = 'k'})

local function safeRoom(room)
  if not room then return false end
  if type(room.settings) == 'table' and type(room.settings.gameMode) == 'string' then
    return safeModes[room.settings.gameMode] == true
  end
  if type(room.isGameMode) == 'function' then
    local ok, isRole = pcall(room.isGameMode, room, 'role_mode')
    return ok and isRole == true
  end
  return false
end

local function availableMask()
  if not Fk or type(Fk.generals) ~= 'table' then return nil end
  for _, name in ipairs(candidateMasks) do
    if Fk.generals[name] then return name end
  end
  return nil
end

local function livingHolder(room)
  for _, p in ipairs(room.players or {}) do
    if D.hasCangshen(p) then return true end
  end
  return false
end

local function privatelySet(viewer, subject, prop, value)
  if type(viewer.doNotify) ~= 'function'
    or type(json) ~= 'table' or type(json.encode) ~= 'function' then
    return false
  end
  return pcall(viewer.doNotify, viewer, 'PropertyUpdate',
    json.encode{subject.id, prop, value})
end

local function restore(room, viewer, subject, fields)
  if not viewer or not subject or type(room.notifyProperty) ~= 'function' then
    return false
  end
  local okAll = true
  for prop in pairs(fields) do
    local ok = pcall(room.notifyProperty, room, viewer, subject, prop)
    okAll = ok and okAll
  end
  return okAll
end

local function playerById(room, id)
  if type(room.getPlayerById) == 'function' then
    local ok, player = pcall(room.getPlayerById, room, id)
    if ok and player then return player end
  end
  for _, p in ipairs(room.players or {}) do
    if p.id == id then return p end
  end
  return nil
end

local function undoAll(room, state)
  for viewerId, subjects in pairs(state) do
    local viewer = playerById(room, viewerId)
    for subjectId, fields in pairs(subjects) do
      restore(room, viewer, playerById(room, subjectId), fields)
    end
  end
  maskedRooms[room] = nil
end

-- force can be true (refresh all) or a particular player / player ID
-- (a changed general needs masking again after FreeKill broadcasts it).
function M.sync(room, force)
  if not room or type(room.players) ~= 'table' then return false end
  -- A switch into a secret-general mode must NEVER broadcast true generals.
  -- Drop bookkeeping without sending restores; such modes own visibility.
  if not safeRoom(room) then
    maskedRooms[room] = nil
    return false
  end
  local mask = livingHolder(room) and availableMask() or nil
  local state = maskedRooms[room]
  if not mask then
    if state then undoAll(room, state) end
    return false
  end
  if not state then
    state = {}
    maskedRooms[room] = state
  end
  local changedId = type(force) == 'table' and force.id or force
  for _, viewer in ipairs(room.players) do
    if viewer.id ~= nil then
      local peers = state[viewer.id]
      if not peers then
        peers = {}
        state[viewer.id] = peers
      end
      for _, subject in ipairs(room.players) do
        if subject.id ~= nil and subject.id ~= viewer.id then
          local fields = peers[subject.id]
          if not fields then
            fields = {}
            peers[subject.id] = fields
          end
          local resend = force == true or changedId == subject.id
          for _, prop in ipairs({'general', 'deputyGeneral'}) do
            local realName = subject[prop]
            if type(realName) == 'string' and realName ~= '' then
              if not fields[prop] or resend then
                if privatelySet(viewer, subject, prop, mask) then
                  fields[prop] = true
                end
              end
            elseif fields[prop] then
              -- A deputy was removed while being hidden; restore its
              -- actual property before dropping the tracked masking entry.
              if restore(room, viewer, subject, {[prop] = true}) then
                fields[prop] = nil
              end
            end
          end
          if not next(fields) then peers[subject.id] = nil end
        end
      end
      if not next(peers) then state[viewer.id] = nil end
    end
  end
  return true
end

function M.isRunning(room)
  return room ~= nil and maskedRooms[room] ~= nil
end

return M
