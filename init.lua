-- 星月同輝自定义武将：帕拉塞尔苏斯、攬佬、安娜 (FreeKill 0.5.5+)
-- 拓展安装位置：packages/XY。
local extension = Package:new("starmoon")
extension.extensionName = "XY"

extension:loadSkillSkelsByPath("./packages/XY/skills")

local paracelsus = General:new(
  extension, "alch__paracelsus", "qun", 3, 3, General.Male
)
paracelsus:addSkills({"alch__liancheng", "alch__qucai"})

local lanlao = General:new(
  extension, "alch__lanlao", "qun", 3, 3, General.Female
)
lanlao:addSkills({"alch__nengfei", "alch__huangpi"})

-- 新武將：夜神月（沒有指定立繪，使用引擎預設形象）
local deathgod = General:new(
  extension, "xy__deathgod", "qun", 4, 4, General.Male
)
deathgod:addSkills({"xy__cangshen", "xy__sishen"})

-- 解謎天使目前只有暫時性的變身模板，等待您提供正式武將資料與圖片。
local anna = General:new(
  extension, "xy__anna", "qun", 3, 3, General.Female
)
anna:addSkills({"xy__jiemi", "xy__mipu", "xy__miti"})

local angel = General:new(
  extension, "xy__decrypt_angel", "qun", 3, 3, General.Female
)
-- Transformation-only form: not an initial general-choice candidate.
-- Keep the general registered so room:changeHero can still transform Anna.
angel.hidden = true
angel.total_hidden = true
angel:addSkills({"xy__jiemi", "xy__mipu", "xy__miti", "xy__zhentan", "xy__laike"})

-- Secondary forms must be usable by changeHero, but must not be offered
-- as playable generals. General:new added this form to extension.generals;
-- remove it from that selection/package list. The engine registry is kept
-- separately by the install hook below, so transformation still resolves.
for i = #extension.generals, 1, -1 do
  if extension.generals[i] == angel then
    table.remove(extension.generals, i)
  end
end

local installBasePackage = extension.install
function extension:install(engine)
  -- Install the playable characters and all skeleton skills normally.
  installBasePackage(self, engine)
  -- Register the second form only in the runtime lookup used by changeHero.
  -- Do not add it back to the package's initial general list.
  if engine.generals[angel.name] == nil then
    engine:addGeneral(angel)
  end

  -- Some custom/free-select interfaces ask canUseGeneral directly. Reject
  -- this one ID even if a UI ignores the standard hidden flags.
  if not engine._xy_decrypt_angel_choose_guard and type(engine.canUseGeneral) == 'function' then
    local oldCanUseGeneral = engine.canUseGeneral
    engine.canUseGeneral = function(self, general_name, ...)
      if general_name == angel.name then return false end
      return oldCanUseGeneral(self, general_name, ...)
    end
    engine._xy_decrypt_angel_choose_guard = true
  end
end

Fk:loadTranslationTable{
  ["XY"] = "星月同輝",
  ["starmoon"] = "星月同輝",
  ["alch"] = "星月同輝",

  ["alch__paracelsus"] = "帕拉塞爾蘇斯",
  ["#alch__paracelsus"] = "鍊金術士",
  ["alch__liancheng"] = "炼成",
  [":alch__liancheng"] = "准备阶段，你从弃牌堆中获得一张【杀】；结束阶段，你从弃牌堆中获得一张【闪】。",
  ["alch__qucai"] = "取材",
  [":alch__qucai"] = "锁定技，弃牌阶段开始时，你将手牌数调整至3。",

  ["alch__lanlao"] = "攬佬",
  ["#alch__lanlao"] = "中国人",
  ["alch__nengfei"] = "能飞",
  [":alch__nengfei"] = "你成为一张牌的目标时，你可以进行一次判定。若判定结果为中国红，此牌对你无效。",
  ["alch__huangpi"] = "黄皮",
  [":alch__huangpi"] = "一名场上拥有中国红牌的角色回合结束时，若该角色为黄皮肤，你可以摸场上拥有中国红牌的角色数量张牌。",
  ["#alch__nengfei-invoke"] = "能飞：是否进行判定？",
  ["#alch__huangpi-invoke"] = "黄皮：是否摸牌？",

  -- 新武將：夜神月
  ["xy__deathgod"] = "夜神月",
  ["#xy__deathgod"] = "不可直視之名",
  ["xy__cangshen"] = "藏身",
  ["xy__cangshen-hidden-desc"] = "受“藏身”影響，無法查看此技能描述。",
  [":xy__cangshen"] = "持恆技，遊戲開始時即生效。當你存活時，所有角色無法觀看其他角色的武將名字、技能名字、技能描述及武將皮膚。",
  ["xy__sishen"] = "死神",
  [":xy__sishen"] = "當你在聊天框發送的整則文字與一名武將的名字完全相同時，所有同名的存活武將立即死亡。",
  ["#xy__sishen-choose"] = "死神：選擇一個存活武將的名字，令所有同名角色死亡（未安裝聊天室伺服器補丁時的備用方式）",
  ["#xy__sishen-kill"] = "%from 發動“死神”，說出%arg，令%to立即死亡。",

  -- 新增：解謎天使——安娜
  ["xy"] = "星月同輝",
  ["xy__anna"] = "安娜",
  ["#xy__anna"] = "解謎天使",
  ["xy__decrypt_angel"] = "解密天使",
  ["#xy__decrypt_angel"] = "解密中的安娜",

  -- 解密天使限定技能
  ["xy__hidden_card"] = "未知牌",
  ["#xy__zhentan-hidden-use"] = "%from 對 %to 使用了一張【未知牌】。",
  ["#xy__zhentan-no-choices"] = "%from 發動〖偵探〗，但本局沒有可聲明的實體牌名，失去一層變身層數。",
  ["xy__zhentan"] = "偵探",
  [":xy__zhentan"] = "你拥有“解密”，“谜谱”，“密题”。你成为一张牌的唯一目标时，使用该牌的角色需暗置之并需声明该牌的花色和点数，然后你选择是否声明一个牌名。若该牌名与你声明的牌名相同，该牌无效且你摸两张牌。否则，你减少1层变身层数。",
  ["#xy__zhentan-choice"] = "侦探：这张牌的花色点数是%arg，请声明其牌名",
  ["#xy__zhentan-right"] = "%from 發動〖偵探〗猜中了未知牌，令此牌對其無效並摸兩張牌。",
  ["#xy__zhentan-wrong"] = "%from 發動〖偵探〗猜測失敗，失去一層變身層數。",
  ["xy__laike"] = "來客",
  [":xy__laike"] = "出牌阶段，你可以扣置任意张牌于一名其他角色的武将牌上，称之为“未来”。一名角色回合开始时，其可以弃置任意张牌，来弃置自己等量张“未来”，然后你依次对其使用“未来”的牌。 （无距离限制）",
  ["xy__future"] = "未來",
  ["#xy__laike-combined"] = "來客：請選擇一名其他角色及至少一張牌，扣置為“未來”。（你於其回合開始時對其使用）",
  ["#xy__laike-offset"] = "來客：你共有%arg張“未來”（所有角色均可檢視牌面），可先棄置任意張自己的牌，再選擇要移除的相同數量“未來”",
  ["#xy__laike-select"] = "來客：請直接選擇要移除的%arg張“未來”（所有角色均可檢視牌面）",

  ["xy__jiemi"] = "解密",
  [":xy__jiemi"] = "变身技，出牌阶段，你可以弃置一张牌并将武将牌替换成【解密天使】。 （直到你使用一张牌）",
  ["#xy__jiemi-discard"] = "解密：选择弃置一张牌来变身／叠加层数，或点击取消放弃本次发动",
  ["@xy__jiemi_stack"] = "解密",

  ["xy__mipu"] = "谜谱",
  [":xy__mipu"] = "使命技，成功：游戏结束时，你可以声明牌堆里每类型牌的数量，若你正确，你胜利。",
  ["#xy__mipu-ask"] = "谜谱：是否猜测剩余摸牌堆基本牌、锦囊牌、装备牌的数量？",
  ["#xy__mipu-number"] = "谜谱：请声明%arg的数量（剩余摸牌堆）",
  ["xy__mipu_yes"] = "挑战谜谱",
  ["xy__mipu_no"] = "不发动",
  ["#xy__mipu-guess"] = "【谜谱】%from 的猜测（基本牌 / 锦囊牌 / 装备牌）：%arg。",
  ["#xy__mipu-answer"] = "【谜谱】正确答案（基本牌 / 锦囊牌 / 装备牌）：%arg。",
  ["#xy__mipu-success"] = "%from 谜谱成功，获得特殊胜利！",
  ["#xy__mipu-failure"] = "%from 谜谱未能解开，保留正常游戏结果。",
  ["xy__mipu_winner"] = "谜谱胜利",

  ["xy__miti"] = "密题",
  [":xy__miti"] = "成器（8），出牌阶段，你可以选择一名角色并声明其每种类型牌的数量，若你声明的数量正确，你获得其所有牌。否则，其须声明其每种类型的牌大于或小于或等于你声明的数量。回合开始时，声明所有名角色的身分或阵营。进学：你正确声明一名角色的身分或阵营。",
  ["@xy__miti_limit"] = "密题每阶段次数",
  ["#xy__miti-enter"] = "【密题】安娜回合开始，正在依次询问角色身份。",
  ["xy__miti_guess_lord"] = "主公",
  ["xy__miti_guess_loyalist"] = "忠臣",
  ["xy__miti_guess_rebel"] = "反贼",
  ["xy__miti_guess_renegade"] = "内奸",
  ["xy__miti_skip"] = "跳过此角色",
  ["#xy__miti-wrong"] = "【密题】%from未猜对%to的身份。",
  ["#xy__miti-target"] = "密题：选择一名要猜测牌型数量的角色",
  ["#xy__miti-number"] = "密题：请声明目标%arg的数量（手牌和装备区）",
  ["xy__basic"] = "基本牌",
  ["xy__trick"] = "锦囊牌",
  ["xy__equip"] = "装备牌",
  ["xy__more"] = "多于",
  ["xy__equal"] = "等于",
  ["xy__less"] = "少于",
  ["#xy__miti-study"] = "【密题】本次配对猜对%arg人身分，之后每个出牌阶段的使用次数上限增加%arg2次。",
  ["#xy__miti-reveal"] = "【密题】%from猜对了%to的身分：%arg；现在公开该角色的身分。",
  ["#xy__miti-perfect"] = "%from猜对了%to的所有牌型数量！",
  ["#xy__miti-clue"] = "【密题】%from对%to说：%arg的数量%arg2你声明的数量。",
}

-- Client-side privacy adapter. Masks other players' general names, skill
-- names and descriptions while 【藏身】 is active.
-- Internal general IDs and game rules remain untouched.
dofile("./packages/XY/cangshen_client.lua")

-- Client-side convenience: one click on 【解密】 submits its target-free
-- active use; normal one-card discard prompt still follows.
dofile("./packages/XY/one_click_jiemi.lua")

return { extension }
