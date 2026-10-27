-- 【解密】单击发动：只处理出牌阶段普通主动技的客户端按钮。
-- FreeKill's ReqPlayCard normally selects a skill and waits for the OK button.
-- The active skill has no selected cards/targets (discard cost is asked by the
-- server afterwards), so we can submit the already-feasible action on click.
-- This patch intentionally does NOT modify any other skill or game rule.
-- Request handlers also exist for AI simulation: only auto-submit in clients.
local ok, ReqPlayCard = pcall(require, "ltk.core.request_type.play_card")
if not ok or type(ReqPlayCard) ~= "table" then
  return false -- older/incompatible core: leave normal confirmation behaviour
end
if ReqPlayCard._xyJiemiOneClickInstalled then return true end
local oldUpdate = ReqPlayCard.update
if type(oldUpdate) ~= "function" then return false end

ReqPlayCard.update = function(self, elemType, id, action, data)
  -- Let FreeKill perform its normal skill-button selection, availability checks,
  -- screen updates, and target/card reset before deciding to submit.
  local result = oldUpdate(self, elemType, id, action, data)
  if ClientInstance
    and elemType == "SkillButton"
    and id == "xy__jiemi"
    and type(data) == "table" and data.selected == true
    and self.skill_name == "xy__jiemi"
    and not self._xyJiemiOneClickSubmitted
    and self:feasible() then
    -- One reply only, even if the button is clicked twice before the new UI
    -- arrives. The server then asks which card to discard, with Cancel enabled.
    self._xyJiemiOneClickSubmitted = true
    self:doOKButton()
    -- The request controller must finish this interaction, just like a real
    -- click on the OK button; otherwise the old play-card UI remains active.
    return true
  end
  return result
end
ReqPlayCard._xyJiemiOneClickInstalled = true
return true
