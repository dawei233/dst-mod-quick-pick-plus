--=====================================================================
--  Quick Pick Plus · 快速采集（通用版）  v2.0.0
--  Copyright (C) 2026 dawei233
--
--  本程序为自由软件：你可以依据 GNU 通用公共许可证（GPL）的条款 ——
--  由自由软件基金会发布的第 3 版，或（由你选择）任何更新版本 ——
--  重新发布和/或修改它。
--  本程序发布时希望它有用，但**不提供任何担保**，甚至不提供适销性
--  或特定用途适用性的默示担保。完整条款见随附的 LICENSE 文件。
-----------------------------------------------------------------------
--  【目标】本体新增的、以及任何 Mod 新增的「可采集物 / 可翻找物」，
--          不需要维护任何名单，自动获得瞬时采集。
--
--  【两条腿】
--   ① 零白名单标记：AddComponentPostInit("pickable"/"searchable")
--      → 给实体打自定义标签 FAST_TAG。
--      • 刻意 **不设 pickable.quickpick**，原因见下「Woby 陷阱」。
--   ② 动作升级：包装状态图 actionhandler 的 **deststate**，先委托原逻辑，
--      再把慢状态 (dolongaction / domediumaction) 升级为 doshortaction。
--      只"升级慢的"，本体的一切特例因此被完整保留。
--
--  【为什么必须包 deststate，别碰 .fn】
--      ActionHandler = Class(function(self, action, state, condition)
--          if type(state) == "string" then
--              self.deststate = function(_) return state end
--          else
--              self.deststate = state
--          end
--          self.condition = condition
--      end)                                   -- stategraph.lua:159-171
--      运行时取值：handler.deststate(inst, bufferedaction)   -- :412 / :436
--    ⚠️ stategraph.lua 里还有一个 handler.fn（:268 / :468），那是 **timeline
--       事件** 的字段，与动作处理器无关。二者搞混会让整条腿静默失效。
--
--  【Woby 陷阱】绝不能设 pickable.quickpick = true
--      prefabs/wobybig.lua:527  /  wobysmall.lua:551
--          if not IsFoodSourcePickable(buffaction.target)
--             or buffaction.target.components.pickable.quickpick then
--              return
--          end
--    ⇒ 一旦把 quickpick 设成 true，Walter 的「毛茸茸采集者」会**跳过**该植物，
--      玩家白白损失 Woby 的 +1 食物。所以本 Mod 只打自定义标签。
--
--  【本体判定链（已逐条对照 scripts.zip 核实）】
--    stategraphs/SGwilson.lua:1043  ActionHandler(ACTIONS.PICK, ...)
--      :1045  target:HasTag("noquickpick")                  -> dolongaction
--      :1047  inst farmplantfastpicker & target farm_plant  -> domediumaction  (沃姆伍德)
--      :1050  rider:IsRiding()                              -> dolongaction    ← 骑乘短路
--      :1052  target.components.pickable ...
--      :1068    pickable.jostlepick                          -> dojostleaction  ← 优先于 quickpick
--      :1069    pickable.quickpick                           -> doshortaction
--      :1073    兜底                                          -> dolongaction
--    客户端 SGwilson_client.lua:390-426 是同一套判定，但走 **标签**
--      (target:HasTag("pickable" / "jostlepick" / "quickpick") 等)。
--      标签会联网同步，所以服务端打的标签客户端同样可见 —— 两图可以用同一套判定。
--    状态时长：doshortaction = 10 帧(≈0.33s)；dolongaction = 1s
--      （SGwilson.lua:7921 / :8244）
--    mount_valid：PICK / PICKUP / COOK 本体为 true；**HARVEST 与 TAKEITEM 没有**
--      （actions.lua:366 / 367 / 375  vs  :392 / :452）
--      ⇒ 骑乘时这两类动作会被整个过滤掉，选项根本不出现；
--        要「骑乘也能收割/取物」必须自己翻这个开关。
--
--  【覆盖范围】wilson（服务端权威）+ wilson_client（客户端预测）两个图都补，
--    否则会出现「客户端预测慢动作、服务端已经做完」的抖动。
--
--  【与上游项目的关系 / 许可】
--    本项目基于工坊 GPL-3.0 项目「Quick Pick+ (Woby Edition)」by **Jotave**
--    （工坊 3739258809）开发。来自该项目的做法：
--      · 包装 handler.deststate（先委托原逻辑、再升级慢状态）的手法；
--      · 用本体自带的 `farm_plant` 标签覆盖全部农场作物与杂草；
--      · 骑乘时给 HARVEST / TAKEITEM 补 `mount_valid`；
--      · 最关键的一条结论 —— 不要设 `pickable.quickpick`，否则会让
--        Walter 的 Woby 跳过该植物。
--    更上游还有「Quick Pick」by 辣椒小皇纸（工坊 2921270365 / github.com/jupitersh/dst-mod-quick-pick），
--    是最初的快速采集实现。
--
--    **本项目在此基础上新增的部分**：「零白名单」的整体设计 ——
--    用 AddComponentPostInit 给「可采集 / 可翻找组件」本身打标记，
--    而不维护任何 prefab 名单。
--
--    依 GPL-3.0（或任何更新版本）发布，完整条款见随附的 LICENSE 文件。
--=====================================================================

GLOBAL.setmetatable(env, { __index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end })

-- ---------------------------------------------------------------
-- 配置
-- ---------------------------------------------------------------
local QuickPick     = GetModConfigData("pick_generic")
local ClearJostle   = GetModConfigData("clear_jostle")
local QuickSearch   = GetModConfigData("search_generic")
local QuickHarvest  = GetModConfigData("quick_harvest")
local QuickCook     = GetModConfigData("quick_cook_on_fire")
local QuickRiding   = GetModConfigData("quick_riding")
local QuickInteract = GetModConfigData("quick_plant_interact")
local QuickEat      = GetModConfigData("quick_eat")
local LureTake      = GetModConfigData("lureplant_take")

-- ---------------------------------------------------------------
-- 常量与工具
-- ---------------------------------------------------------------
local FAST_TAG      = "qpp_fast"        -- 本 mod 自己的标记（可采集 / 可翻找）
local TAKE_FAST_TAG = "qpp_takefast"    -- 食人花（TAKEITEM）
local SHORT         = "doshortaction"             -- 10 帧 ≈ 0.33s
local SLOW          = { dolongaction = true, domediumaction = true }

local function log(fmt, ...)
    print("[QuickPickPlus] " .. string.format(fmt, ...))
end

-- AddComponentPostInit 回调签名是 fn(组件实例, 实体)（entityscript.lua:639-641）
local function TagOwner(comp, inst)
    local e = inst or (comp ~= nil and comp.inst or nil)
    if e ~= nil and not e:HasTag(FAST_TAG) then
        e:AddTag(FAST_TAG)
    end
end

-- ---------------------------------------------------------------
-- ① 零白名单标记（不含任何 prefab 名单）
--    刻意不设 pickable.quickpick —— 见文件头「Woby 陷阱」。
--    这里也不做 "有没有 pickable 组件" 的守卫：农场作物只在可收获阶段
--    才加上 pickable，出生时是 nil，加了守卫反而会静默漏掉它们。
-- ---------------------------------------------------------------
if QuickPick then
    AddComponentPostInit("pickable", TagOwner)
end
if QuickSearch then
    AddComponentPostInit("searchable", TagOwner)
end

-- ---------------------------------------------------------------
-- 判定
-- ---------------------------------------------------------------
-- 是否"值得提速"的目标。四种标签都是 **本体自己会联网同步** 的，
-- 因此服务端图与客户端图用同一套判定即可（服务端多一个 FAST_TAG）。
local function IsFastTarget(target)
    if target == nil then
        return false
    end
    return target:HasTag(FAST_TAG)
        or target:HasTag("pickable")     -- 任何可采集物：本体 / 其它 Mod 新增，全自动覆盖
        or target:HasTag("searchable")   -- 任何可翻找物
        or target:HasTag("quickpick")    -- 本体已 instant 的（花 / 蕨 / 多肉 / 种下的胡萝卜）
        or target:HasTag("farm_plant")   -- 农场作物与杂草（farm_plants.lua:808 / weed_plants.lua:504）
end

-- 本体自带的"别快采我"标记（只有 junk_pile_big 用），必须尊重
local function IsBlocked(act)
    return act ~= nil and act.target ~= nil and act.target:HasTag("noquickpick")
end

local function IsRiding(inst)
    if inst == nil then
        return false
    end
    local rider = inst.components ~= nil and inst.components.rider or nil
    if rider == nil and inst.replica ~= nil then
        rider = inst.replica.rider
    end
    return rider ~= nil and rider:IsRiding()
end

-- ---------------------------------------------------------------
-- ② 动作升级（包装 deststate，委托原逻辑）
-- ---------------------------------------------------------------
local function Patch(sg, action, rule)
    local handlers = sg ~= nil and sg.actionhandlers or nil
    local handler = handlers ~= nil and handlers[action] or nil
    if handler == nil then
        log("跳过 %s：状态图里没有这个动作处理器", tostring(action))
        return false
    end
    -- ActionHandler 保证 deststate 一定是函数（字符串会被包成 function(_) return s end）
    local orig = handler.deststate
    if type(orig) ~= "function" then
        log("跳过 %s：deststate 类型异常（%s）", tostring(action), type(orig))
        return false
    end
    handler.deststate = function(inst, act)
        local state = orig(inst, act)
        local better = rule(state, inst, act)
        return better ~= nil and better or state
    end
    return true
end

-- ---- PICK：采集 ----------------------------------------------------
local function RulePick(state, inst, act)
    if act == nil or act.target == nil or act.target:HasTag("noquickpick") then
        return nil
    end
    if not IsFastTarget(act.target) then
        return nil
    end
    if IsRiding(inst) then
        -- 本体在 quickpick 判定之前就因骑乘返回慢动作（伍迪除外），要单独救
        return (QuickRiding and SLOW[state]) and SHORT or nil
    end
    if state == "dojostleaction" then
        -- jostlepick 优先于 quickpick（本体故意如此，比如浆果丛要"摇一摇"）。
        -- 但"快速采集"的意图就是别等这段动画，所以默认也提速。
        return ClearJostle and SHORT or nil
    end
    if SLOW[state] then
        return SHORT
    end
    return nil
end

-- ---- PICKUP：骑乘时拾取 ---------------------------------------------
local function RuleRidingPickup(state, inst, act)
    if act ~= nil and act.target ~= nil and act.target:HasTag("noquickpick") then
        return nil
    end
    -- 原版骑乘时一律 domediumaction；重物的 dodismountaction 不在 SLOW 里，不受影响
    return (SLOW[state] and IsRiding(inst)) and SHORT or nil
end

-- ---- HARVEST / COOK / PLANTSOIL：慢就升级 ----------------------------
local function RuleSlow(state, inst, act)
    if act ~= nil and act.target ~= nil and act.target:HasTag("noquickpick") then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

-- ---- INTERACT_WITH：只对"可对话的农场植物"提速 -----------------------
-- 其它 INTERACT_WITH 用途（YOTB 舞台等）保持原样
local function RuleTend(state, inst, act)
    if act == nil or act.target == nil or not act.target:HasTag("tendable_farmplant") then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

-- ---- EAT：慢吃升级成快吃 --------------------------------------------
local function RuleEat(state, inst, act)
    if state == "eat" then
        return "quickeat"
    end
    if state == "float_eat" then
        return "float_quickeat"
    end
    return nil
end

-- ---- TAKEITEM / TAKESINGLEITEM：只对食人花 ---------------------------
local function RuleTake(state, inst, act)
    if act == nil or act.target == nil or act.target:HasTag("noquickpick") then
        return nil
    end
    if not act.target:HasTag(TAKE_FAST_TAG) then
        return nil
    end
    if IsRiding(inst) and not QuickRiding then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

local function ApplyToSG(sg)
    if QuickPick then
        Patch(sg, ACTIONS.PICK, RulePick)
    end
    if QuickRiding then
        Patch(sg, ACTIONS.PICKUP, RuleRidingPickup)
    end
    if QuickHarvest then
        Patch(sg, ACTIONS.HARVEST, RuleSlow)
    end
    if QuickCook then
        Patch(sg, ACTIONS.COOK, RuleSlow)
    end
    if QuickInteract then
        Patch(sg, ACTIONS.INTERACT_WITH, RuleTend)
        Patch(sg, ACTIONS.PLANTSOIL, RuleSlow)
    end
    if QuickEat then
        Patch(sg, ACTIONS.EAT, RuleEat)
    end
    if LureTake then
        Patch(sg, ACTIONS.TAKEITEM, RuleTake)
        Patch(sg, ACTIONS.TAKESINGLEITEM, RuleTake)
    end
end

AddStategraphPostInit("wilson", ApplyToSG)          -- 服务端权威
AddStategraphPostInit("wilson_client", ApplyToSG)   -- 客户端预测

-- ---------------------------------------------------------------
-- 骑乘解锁：本体没给这两个动作 mount_valid，骑乘时选项根本不出现
-- ---------------------------------------------------------------
if QuickRiding then
    if ACTIONS.TAKEITEM ~= nil then
        ACTIONS.TAKEITEM.mount_valid = true
    end
    if ACTIONS.TAKESINGLEITEM ~= nil then
        ACTIONS.TAKESINGLEITEM.mount_valid = true
    end
    if ACTIONS.HARVEST ~= nil then
        ACTIONS.HARVEST.mount_valid = true
    end
end

-- ---------------------------------------------------------------
-- 食人花：它没有 pickable 组件（那坨肉走 TAKEITEM），单独打标记
-- ---------------------------------------------------------------
if LureTake then
    AddPrefabPostInit("lureplant", function(inst)
        inst:AddTag(TAKE_FAST_TAG)
    end)
end

-- ---------------------------------------------------------------
-- 加载自检
-- ---------------------------------------------------------------
log("v2.0.0 已加载（采集=%s 摇晃也快=%s 翻找=%s 收割=%s 篝火烤=%s 骑乘=%s 种植/对话=%s 进食=%s 食人花=%s）",
    tostring(QuickPick), tostring(ClearJostle), tostring(QuickSearch), tostring(QuickHarvest),
    tostring(QuickCook), tostring(QuickRiding), tostring(QuickInteract), tostring(QuickEat), tostring(LureTake))
