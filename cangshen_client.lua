-- 【藏身】client-side, viewer-aware masking of general names, skill names and descriptions.
-- FreeKill main/core 0.5.5+: GetPlayerSkills(id) invokes
-- Fk:getDescription(skill_name, language, inspected_player).
--
-- The package is loaded into separate client/server Lua VMs. Install once on
-- this VM's Fk object, but only mask when ClientInstance and Self are present.
-- Keep game logic, internal skill IDs and the general-gallery description
-- path (without an inspected player) unchanged.
local M = {}
M.BANNER = "xy__cangshen_active"
M.SKILL = "xy__cangshen"
M.GENERAL = "xy__deathgod"
M.HIDDEN_TEXT = "受“藏身”影響，無法查看此技能描述。"
M.HIDDEN_GENERAL = "？？？"
M.HIDDEN_SKILL = "？？？"
M.HIDDEN_PORTRAIT = "？？？"

-- 持恆技必須無視一般封技；角色資料可能比房間 banner 更早到達。
-- 夜神月開局本有此技能，所以可在其技能列表同步之前依武將 ID 辨認。
local function hasCangshen(p)
  if not p then return false end
  if type(p.hasSkill) == "function" then
    local ok, value = pcall(p.hasSkill, p, M.SKILL, true)
    if ok and value then return true end
  end
  if type(p.player_skills) == "table" then
    for _, s in pairs(p.player_skills) do
      if s == M.SKILL or (type(s) == "table" and s.name == M.SKILL) then
        return true
      end
    end
  end
  return p.general == M.GENERAL or p.deputyGeneral == M.GENERAL
end

function M.active(c)
  if not c or type(c.players) ~= "table" then return false end
  local banner
  if type(c.getBanner) == "function" then
    local ok, value = pcall(c.getBanner, c, M.BANNER)
    if ok then banner = value end
  end

  -- Persistent from the beginning of the game, even before the server's
  -- GameStart banner is synchronised. A stale false banner cannot switch
  -- off a Permanent skill held by a living player.
  local knownOwners = 0
  for _, p in ipairs(c.players) do
    if hasCangshen(p) then
      knownOwners = knownOwners + 1
      if not p.dead then return true end
    end
  end
  -- If all known holders died, do not trust a stale true banner.
  if knownOwners > 0 then return false end
  -- If the bearer has not yet been sent to this client (or skill lists are
  -- still empty), honour GameStart's server flag as a temporary fallback.
  return banner == true or banner == 1
end

function M.shouldMask(owner)
  local c, viewer = ClientInstance, Self
  if not c or not viewer or not owner then return false end
  if type(owner) ~= "table" or owner.id == nil or viewer.id == nil then return false end
  if owner.id == viewer.id then return false end
  -- Only a current room participant. General galleries and bare skill tooltips
  -- have no inspected-player argument and are intentionally not intercepted.
  if type(c.getPlayerById) ~= "function" then return false end
  local ok, currentOwner = pcall(c.getPlayerById, c, owner.id)
  if not ok or not currentOwner then return false end
  if currentOwner ~= owner and currentOwner.id ~= owner.id then return false end
  if not M.active(c) then return false end
  return true
end

-- The server now sends native anjiang to every player's OTHER peers.
-- Disable the legacy PhotoBase overlay, which otherwise covers anjiang.
function M.shouldMaskPortrait(playerId)
  return false
end

function XYShouldHidePortrait(playerId)
  return false
end

-- PhotoBase.qml renders a player's translated general ID using Lua.tr(name).
-- Unlike getDescription(skill, language, inspectedPlayer), this translation
-- has NO player ID. We therefore mask only general IDs currently worn by a
-- different player, never the viewer's own general/deputy ID.
-- Limitation: two players using the same general ID are indistinguishable
-- here; preserve the viewer's own name rather than hiding both.
local function wearsGeneral(p, generalName)
  return p and (p.general == generalName or p.deputyGeneral == generalName)
end

function M.shouldMaskGeneral(generalName)
  local c, viewer = ClientInstance, Self
  if not c or not viewer or type(generalName) ~= "string"
     or generalName == "" or type(c.players) ~= "table" then return false end
  if not M.active(c) then return false end
  if viewer.id == nil or type(c.getPlayerById) ~= "function" then return false end
  local ok, currentSelf = pcall(c.getPlayerById, c, viewer.id)
  if not ok or not currentSelf then return false end
  if wearsGeneral(currentSelf, generalName) or wearsGeneral(viewer, generalName) then
    return false
  end
  for _, p in ipairs(c.players) do
    if p.id ~= viewer.id and wearsGeneral(p, generalName) then
      return true
    end
  end
  return false
end

function M.shouldMaskTranslation(engine, key)
  if type(key) ~= "string" or not engine or type(engine.generals) ~= "table" then
    return false
  end
  -- General titles can also identify generals in some player panels.
  local generalName = key:sub(1, 1) == "#" and key:sub(2) or key
  if engine.generals[generalName] == nil then return false end
  return M.shouldMaskGeneral(generalName)
end

-- The FreeKill UI translates skill names through Fk:translate(skill ID),
-- which carries NO inspected-player ID. Scope hiding to skills possessed by
-- opponents but not the viewer. If both players have the same skill ID, keep
-- its name visible so the viewer can still read their own skill. This is a
-- display-only best effort, not a general-purpose security boundary.
local function skillId(entry)
  if type(entry) == "string" then return entry end
  if type(entry) == "table" then
    if type(entry.name) == "string" then return entry.name end
    if type(entry.getSkeleton) == "function" then
      local ok, skeleton = pcall(entry.getSkeleton, entry)
      if ok and skeleton and type(skeleton.name) == "string" then
        return skeleton.name
      end
    end
  end
  return nil
end

local function playerHasSkillName(p, name)
  if not p then return false end
  if type(p.player_skills) == "table" then
    for _, skill in pairs(p.player_skills) do
      if skillId(skill) == name then return true end
    end
  end
  if type(p.getSkillNameList) == "function" then
    local ok, names = pcall(p.getSkillNameList, p)
    if ok and type(names) == "table" then
      for _, s in pairs(names) do
        if skillId(s) == name then return true end
      end
    end
  end
  if type(p.hasSkill) == "function" then
    local ok, has = pcall(p.hasSkill, p, name, true)
    if ok and has then return true end
  end
  return false
end

function M.shouldMaskSkillTranslation(engine, skillName)
  if type(skillName) ~= "string" or not engine
      or type(engine.skills) ~= "table"
      or engine.skills[skillName] == nil then return false end
  local c, viewer = ClientInstance, Self
  if not c or not viewer or viewer.id == nil
      or type(c.players) ~= "table"
      or type(c.getPlayerById) ~= "function" then return false end
  if not M.active(c) then return false end
  local ok, ownPlayer = pcall(c.getPlayerById, c, viewer.id)
  if not ok or not ownPlayer then return false end
  if playerHasSkillName(ownPlayer, skillName)
      or playerHasSkillName(viewer, skillName) then return false end
  for _, p in ipairs(c.players) do
    if p.id ~= viewer.id and playerHasSkillName(p, skillName) then
      return true
    end
  end
  return false
end

function M.install(engine)
  engine = engine or Fk
  if not engine then return false end
  local descReady = false
  if type(engine.getDescription) == "function" then
    if not engine._xyCangshenDescriptionInstalled then
      local previous = engine.getDescription
      engine.getDescription = function(self, skillName, language, owner, ...)
        if type(skillName) == "string"
           and type(self.skills) == "table"
           and self.skills[skillName] ~= nil
           and M.shouldMask(owner) then
          if type(self.translate) == "function" then
            local ok, translated = pcall(self.translate, self,
              "xy__cangshen-hidden-desc", language)
            if ok and type(translated) == "string"
               and translated ~= "xy__cangshen-hidden-desc" then
              return translated
            end
          end
          return M.HIDDEN_TEXT
        end
        return previous(self, skillName, language, owner, ...)
      end
      engine._xyCangshenDescriptionInstalled = true
      engine._xyCangshenPreviousDescription = previous
    end
    descReady = true
  end
  local nameReady = false
  if type(engine.translate) == "function" then
    if not engine._xyCangshenGeneralTranslationInstalled then
      local previous = engine.translate
      engine.translate = function(self, key, ...)
        if M.shouldMaskTranslation(self, key) then
          return M.HIDDEN_GENERAL
        end
        if M.shouldMaskSkillTranslation(self, key) then
          return M.HIDDEN_SKILL
        end
        return previous(self, key, ...)
      end
      engine._xyCangshenGeneralTranslationInstalled = true
      engine._xyCangshenPreviousTranslation = previous
    end
    nameReady = true
  end
  return descReady and nameReady
end

M.install()
return M
