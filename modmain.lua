--=====================================================================
--  Quick Pick Plus · 快速采集（通用版）  v2.1.0
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
--  【双端配置同步（v2.1.0 新增）】
--    DST 的 mod 配置**没有服务端→客户端网络同步**：客户端读的是
--    client_save/mod_config_data，与服务端 modoverrides.lua 是两份独立存储，
--    引擎不会自动对齐。本 Mod 的 deststate 升级由「客户端预测、服务端权威」
--    双端各自计算，一旦两端配置不同（例如用户在服务端关了某开关、客户端仍是
--    默认开），就会出现动画时长/动作对不上的错乱（quick_eat 即此）。
--    解法：客户端进入世界时向服务端请求配置，服务端把**权威值**打包推回，
--    客户端用收到的值覆盖本端 CFG —— 从此两端一致（详见文件尾 RPC 段）。
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
-- 配置（运行时表，而非加载时常量）
-- ---------------------------------------------------------------
-- 配置键与 modinfo.lua 的 configuration_options 一一对应。
-- 顺序即「服务端→客户端」配置同步 RPC 的参数顺序（位打包，见文件尾 RPC 段）。
local CFG_KEYS = {
    "pick_generic", "clear_jostle", "search_generic", "quick_harvest",
    "quick_cook_on_fire", "quick_riding", "quick_plant_interact",
    "quick_eat", "lureplant_take",
}

-- 运行时配置表：双端各自在加载时读本端 GetModConfigData 初始化；
-- 客户端随后会被服务端通过 ModRPC 推送的「服务端权威值」覆盖（见文件尾 RPC 段）。
-- 之所以用表而不用加载时常量：Rule* / ApplyToSG 必须读「当前生效值」，
-- 否则客户端即使收到 RPC 也无法改变行为。
local CFG = {}
for _, k in ipairs(CFG_KEYS) do
    CFG[k] = GetModConfigData(k)
end

-- 运行时读取（避免在 Rule* / ApplyToSG 里捕获加载时常量）
local function cfg(name)
    return CFG[name]
end

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
-- 仅当对应开关开启时才打标记；运行期读 cfg，保证客户端收到服务端同步后也一致。
local function MakeTagger(opt_key)
    return function(comp, inst)
        if not cfg(opt_key) then
            return
        end
        local e = inst or (comp ~= nil and comp.inst or nil)
        if e ~= nil and not e:HasTag(FAST_TAG) then
            e:AddTag(FAST_TAG)
        end
    end
end

-- ---------------------------------------------------------------
-- ① 零白名单标记（不含任何 prefab 名单）
--    刻意不设 pickable.quickpick —— 见文件头「Woby 陷阱」。
--    无条件注册 hook（开关在 hook 内部按 cfg 判断），使双端结构完全一致。
-- ---------------------------------------------------------------
AddComponentPostInit("pickable", MakeTagger("pick_generic"))
AddComponentPostInit("searchable", MakeTagger("search_generic"))

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
-- pick_generic 是「通用快速采集」总开关：关掉则 PICK 完全不升级。
-- 子开关 clear_jostle（摇晃也快）/ quick_riding（骑乘）在其下独立生效。
local function RulePick(state, inst, act)
    if act == nil or act.target == nil or act.target:HasTag("noquickpick") then
        return nil
    end
    if not cfg("pick_generic") then
        return nil
    end
    if IsRiding(inst) then
        -- 本体在 quickpick 判定之前就因骑乘返回慢动作（伍迪除外），要单独救
        return (cfg("quick_riding") and SLOW[state]) and SHORT or nil
    end
    if state == "dojostleaction" then
        -- jostlepick 优先于 quickpick（本体故意如此，比如浆果丛要"摇一摇"）。
        -- 但"快速采集"的意图就是别等这段动画，所以默认也提速。
        return cfg("clear_jostle") and SHORT or nil
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
    return (SLOW[state] and IsRiding(inst) and cfg("quick_riding")) and SHORT or nil
end

-- ---- HARVEST / COOK / PLANTSOIL：慢就升级 ----------------------------
-- 三者由不同开关控制，所以用 act.action 区分（HARVEST/COOK→quick_harvest，
-- PLANTSOIL→quick_plant_interact）。这些动作的目标不会带 noquickpick，无需检查。
local function RuleSlow(state, inst, act)
    if act == nil then
        return nil
    end
    local a = act.action
    local on = ((a == ACTIONS.HARVEST or a == ACTIONS.COOK) and cfg("quick_harvest"))
            or (a == ACTIONS.PLANTSOIL and cfg("quick_plant_interact"))
    if not on then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

-- ---- INTERACT_WITH：只对"可对话的农场植物"提速 -----------------------
-- 其它 INTERACT_WITH 用途（YOTB 舞台等）保持原样
local function RuleTend(state, inst, act)
    if not cfg("quick_plant_interact") then
        return nil
    end
    if act == nil or act.target == nil or not act.target:HasTag("tendable_farmplant") then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

-- ---- EAT：慢吃升级成快吃 --------------------------------------------
local function RuleEat(state, inst, act)
    if not cfg("quick_eat") then
        return nil
    end
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
    if not cfg("lureplant_take") then
        return nil
    end
    if not act.target:HasTag(TAKE_FAST_TAG) then
        return nil
    end
    if IsRiding(inst) and not cfg("quick_riding") then
        return nil
    end
    return SLOW[state] and SHORT or nil
end

-- 所有动作无条件打补丁：是否"生效"改由 Rule* 读 cfg 决定。
-- 这样双端装的补丁集合完全一致，行为只取决于同一份 CFG（客户端会被 RPC 覆盖为服务端值）。
local function ApplyToSG(sg)
    Patch(sg, ACTIONS.PICK, RulePick)
    Patch(sg, ACTIONS.PICKUP, RuleRidingPickup)
    Patch(sg, ACTIONS.HARVEST, RuleSlow)
    Patch(sg, ACTIONS.COOK, RuleSlow)
    Patch(sg, ACTIONS.INTERACT_WITH, RuleTend)
    Patch(sg, ACTIONS.PLANTSOIL, RuleSlow)
    Patch(sg, ACTIONS.EAT, RuleEat)
    Patch(sg, ACTIONS.TAKEITEM, RuleTake)
    Patch(sg, ACTIONS.TAKESINGLEITEM, RuleTake)
end

AddStategraphPostInit("wilson", ApplyToSG)          -- 服务端权威
AddStategraphPostInit("wilson_client", ApplyToSG)   -- 客户端预测

-- ---------------------------------------------------------------
-- 骑乘解锁：本体没给这两个动作 mount_valid，骑乘时选项根本不出现
-- 运行期按 cfg 设置（收到 RPC 后也会再同步一次）
-- ---------------------------------------------------------------
local function ApplyMountValid()
    if not cfg("quick_riding") then
        return
    end
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
ApplyMountValid()   -- 加载时按本端配置设一次

-- ---------------------------------------------------------------
-- 食人花：它没有 pickable 组件（那坨肉走 TAKEITEM），单独打标记
-- 同样运行期读 cfg，保证双端一致
-- ---------------------------------------------------------------
AddPrefabPostInit("lureplant", function(inst)
    if cfg("lureplant_take") then
        inst:AddTag(TAKE_FAST_TAG)
    end
end)

-- ---------------------------------------------------------------
-- 加载自检
-- ---------------------------------------------------------------
log("v2.1.0 已加载（采集=%s 摇晃也快=%s 翻找=%s 收割=%s 篝火烤=%s 骑乘=%s 种植/对话=%s 进食=%s 食人花=%s）",
    tostring(cfg("pick_generic")), tostring(cfg("clear_jostle")), tostring(cfg("search_generic")),
    tostring(cfg("quick_harvest")), tostring(cfg("quick_cook_on_fire")), tostring(cfg("quick_riding")),
    tostring(cfg("quick_plant_interact")), tostring(cfg("quick_eat")), tostring(cfg("lureplant_take")))

-- ===============================================================
-- 双端配置同步（服务端 → 客户端）
-- ---------------------------------------------------------------
-- 问题：DST 的 mod 配置没有服务端→客户端网络同步。客户端读的是
--      client_save/mod_config_data，与服务端 modoverrides.lua 是两份独立存储。
--      本 Mod 的 deststate 升级由「客户端预测、服务端权威」双端各自计算，
--      若双端配置不一致就会出现动画错乱（用户实测 quick_eat 即此）。
-- 解法：客户端进入世界时向服务端请求配置，服务端把**权威值**打包后推回，
--      客户端用收到的值覆盖本端 CFG，从此双端一致。
-- 注意：RPC 的实际网络派发是引擎（C++）层；这里只负责 Lua 侧的注册与打包，
--      所有 DST API 调用都加了 nil 守卫，老版本 / 离线桩缺失时不会崩。
-- ===============================================================
local RPC_NS   = "QuickPickPlus"
local RPC_REQ  = "ReqCfg"    -- 客户端 → 服务端：请求配置
local RPC_PUSH = "SyncCfg"   -- 服务端 → 客户端：推送配置（1 个整数，位打包 9 个开关）

-- 把 CFG 表按 CFG_KEYS 顺序打包成一个整数（bit0 = pick_generic, bit1 = clear_jostle, ...）
local function PackCfg()
    local bits = 0
    for i, k in ipairs(CFG_KEYS) do
        if CFG[k] then
            bits = bits + math.floor(2 ^ (i - 1))
        end
    end
    return bits
end

-- 收到服务端推送：解包写回本端 CFG，并同步 mount_valid
local function OnSyncCfg(bits)
    bits = math.floor(bits or 0)
    for i, k in ipairs(CFG_KEYS) do
        CFG[k] = (math.floor(bits % 2) == 1)
        bits = math.floor(bits / 2)
    end
    ApplyMountValid()
end

-- 服务端响应：把权威配置推给请求者（player 由引擎在 SendModRPCToServer 时填入）
local function OnReqCfg(player)
    if SendModRPCToClient ~= nil then
        SendModRPCToClient(GetClientModRPC(RPC_NS, RPC_PUSH), player, PackCfg())
    end
end

if AddModRPCHandler ~= nil then
    AddModRPCHandler(RPC_NS, RPC_REQ, OnReqCfg)
end
if AddClientModRPCHandler ~= nil then
    AddClientModRPCHandler(RPC_NS, RPC_PUSH, OnSyncCfg)
end

-- 客户端进世界后向服务端请求一次配置（重连 / 中途加入也会再触发）
local function RequestFromServer()
    if SendModRPCToServer == nil or GetModRPC == nil then return end
    local rpcid = GetModRPC(RPC_NS, RPC_REQ)
    if rpcid == nil then return end
    SendModRPCToServer(rpcid)
end

local function TryRequestAsClient(inst)
    -- 仅客户端（非 master 分片）发起；服务端 world 是 master，跳过。
    -- 注意：AddSimPostInit 回调的 world 参数是 nil，不能用它判断，要查 GLOBAL.TheWorld。
    local TW = (GLOBAL ~= nil and GLOBAL.TheWorld) or nil
    if TW ~= nil and TW.ismastersim == true then return end
    if inst ~= nil and inst.DoTaskInTime ~= nil then
        inst:DoTaskInTime(1, RequestFromServer)   -- 延迟 1s，确保 ModRPC 网络握手完成
    else
        RequestFromServer()
    end
end

if AddPlayerPostInit ~= nil then
    AddPlayerPostInit(function(inst) TryRequestAsClient(inst) end)
elseif AddSimPostInit ~= nil then
    AddSimPostInit(function() TryRequestAsClient(nil) end)
end
