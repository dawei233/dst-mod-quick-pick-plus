# -*- coding: utf-8 -*-
"""
Quick Pick Plus 离线桩（仓库根目录下运行：python tests/test_quickpickplus.py）
==========================================================
这次的核心约束：**桩必须还原真实的 ActionHandler 语义**。

v1.0.0 的教训：桩里自己造了一个 `handler.fn` 字段，而本体真正的字段是
`handler.deststate`（stategraph.lua:159-171 的构造 / :412 :436 的取值），
于是"缺陷被桩掩盖"。本桩照抄本体构造，并额外断言 modmain **不含** `.fn`。

另外还原：
  · 假状态图里 PICK/PICKUP/... 的**分支顺序逐行照抄 SGwilson.lua / SGwilson_client.lua**
  · Woby 的 Furry Forager 判定（wobybig.lua:527）—— 验证我们没把它弄坏
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import lupa.luajit21 as lupa

SRC_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        os.pardir, "modmain.lua")
SRC = io.open(SRC_PATH, encoding="utf-8").read()

fails = []


def show(label, cond, extra=""):
    print(("  [OK]   " if cond else "  [FAIL] ") + label + (("   " + extra) if extra else ""))
    if not cond:
        fails.append(label)


# =====================================================================
#  0) 源码级回归检查（最快、最直接）
# =====================================================================
print("=" * 78)
print("0) 源码回归检查 —— 不能重蹈 v1.0.0 的覆辙")
print("=" * 78)

# 去掉注释后的"有效代码"，避免把注释里提到的关键字算进去
_eff = "\n".join(l for l in SRC.split("\n") if not l.strip().startswith("--"))

show("不含 handler.fn（那是 timeline 事件的字段，动作处理器用 deststate）",
     "handler.fn" not in _eff and ".fn =" not in _eff)
show("确实包装了 deststate", "handler.deststate" in _eff)
show("不设 pickable.quickpick（会破坏 Walter 的 Woby 采集）",
     not re.search(r"\.quickpick\s*=\s*true", _eff))
show("不设 searchable.quicksearch", not re.search(r"\.quicksearch\s*=\s*true", _eff))
show("无任何 prefab 白名单表", "quick_pick_list" not in _eff and "MOD_COMPAT" not in _eff)
show("覆盖 farm_plant 标签（其它 Mod 新增的作物也自动生效）", '"farm_plant"' in _eff)
show("两个状态图都注册（服务端 + 客户端）",
     _eff.count('AddStategraphPostInit("wilson"') >= 1 and _eff.count('AddStategraphPostInit("wilson_client"') >= 1)
show("处理了 mount_valid（骑乘解锁 HARVEST/TAKEITEM）", "mount_valid" in _eff)
show("致谢里写明参考来源", "Jotave" in SRC and "3739258809" in SRC and "2921270365" in SRC)

# 从 modmain 源码动态解析自定义标签值 —— 以后改标签名不会漏
_m = re.search(r'local\s+FAST_TAG\s*=\s*"([^"]+)"', SRC)
FAST_TAG = _m.group(1) if _m else "??"
_m = re.search(r'local\s+TAKE_FAST_TAG\s*=\s*"([^"]+)"', SRC)
TAKE_TAG = _m.group(1) if _m else "??"
show("能从源码解析出自定义标签值",
     FAST_TAG != "??" and TAKE_TAG != "??",
     "%s / %s" % (FAST_TAG, TAKE_TAG))


# =====================================================================
#  1) 搭一个"像本体"的沙箱
# =====================================================================
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()

g.COMP_POSTINIT = lua.table()
g.SG_POSTINIT = lua.table()
g.PREFAB_POSTINIT = lua.table()

g.BOOT_LUA = r"""
-- ================== 容器（每个 runtime 自建，避免跨 runtime 混用） ==================
COMP_POSTINIT = {}
SG_POSTINIT = {}
PREFAB_POSTINIT = {}

-- ================== 模拟本体 ==================
-- 本体的 ACTIONS.X 是 Action 对象（带 mount_valid 等字段），不是字符串。
-- 照抄 actions.lua:366/367/375(=true) 与 :392/:452(=没有) 的差异。
local function mkAction(name, mount_valid)
    return { name = name, mount_valid = mount_valid }
end

ACTIONS = {
    PICK = mkAction("PICK", true),
    PICKUP = mkAction("PICKUP", true),
    HARVEST = mkAction("HARVEST"),                 -- actions.lua:392  Action()  ← 没有 mount_valid
    COOK = mkAction("COOK", true),                 -- actions.lua:375
    INTERACT_WITH = mkAction("INTERACT_WITH", true),
    PLANTSOIL = mkAction("PLANTSOIL"),
    EAT = mkAction("EAT", true),
    TAKEITEM = mkAction("TAKEITEM"),               -- actions.lua:452  Action()  ← 没有
    TAKESINGLEITEM = mkAction("TAKESINGLEITEM"),
}

-- 照抄 stategraph.lua:159-171 的构造语义
ActionHandler = function(action, state, condition)
    local h = {}
    h.action = action
    if type(state) == "string" then
        h.deststate = function(_) return state end
    else
        h.deststate = state
    end
    h.condition = condition
    return h
end

GLOBAL = {
    ACTIONS = ACTIONS,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    rawget = rawget,
    rawset = rawset,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    ipairs = ipairs,
    pairs = pairs,
    next = next,
    select = select,
    table = table,
    string = string,
    math = math,
    print = function() end,                      -- 静音 modmain 的加载日志
    AddComponentPostInit = function(name, fn)
        if COMP_POSTINIT[name] == nil then COMP_POSTINIT[name] = {} end
        table.insert(COMP_POSTINIT[name], fn)
    end,
    AddStategraphPostInit = function(name, fn)
        if SG_POSTINIT[name] == nil then SG_POSTINIT[name] = {} end
        table.insert(SG_POSTINIT[name], fn)
    end,
    AddPrefabPostInit = function(name, fn)
        if PREFAB_POSTINIT[name] == nil then PREFAB_POSTINIT[name] = {} end
        table.insert(PREFAB_POSTINIT[name], fn)
    end,
}

-- 加载 modmain（用一个像 DST 的 env）
function LOAD_MOD(src, cfg)
    local ENV = {}
    ENV.GLOBAL = GLOBAL
    ENV.env = ENV
    ENV.GetModConfigData = function(k) return cfg[k] end
    local chunk = assert(loadstring(src))
    setfenv(chunk, ENV)
    chunk()
    return ENV
end

-- ================== 实体 ==================
-- tags 同时支持两种写法：{"a","b"}（数组）与 {a=true, b=true}（哈希）
function mkEnt(tags, riding, opts)
    opts = opts or {}
    local e = {}
    e.tags = {}
    if tags ~= nil then
        for k, v in pairs(tags) do
            if type(k) == "number" and type(v) == "string" then
                e.tags[v] = true
            elseif v == true and type(k) == "string" then
                e.tags[k] = true
            end
        end
    end
    e.components = {}
    e.replica = {}
    e.HasTag = function(self, t) return self.tags[t] == true end
    e.AddTag = function(self, t) self.tags[t] = true end
    e.RemoveTag = function(self, t) self.tags[t] = nil end
    e.HasAnyTag = function(self, ...)
        for _, t in ipairs({...}) do if self.tags[t] then return true end end
        return false
    end
    if riding then
        e.components.rider = { IsRiding = function() return true end }
        e.replica.rider = e.components.rider
    end
    return e
end

-- 模拟 EntityScript:AddComponent —— 先打本体标签，再跑 ComponentPostInit
function addComp(e, name, comp, client_side)
    comp = comp or {}
    comp.inst = e
    e.components[name] = comp
    if not client_side then
        if name == "pickable" then e:AddTag("pickable") end       -- pickable.lua:3
        if name == "searchable" then e:AddTag("searchable") end
    end
    local fns = COMP_POSTINIT[name]
    if fns ~= nil then
        for _, fn in ipairs(fns) do fn(comp, e) end
    end
    return comp
end

-- ================== 假状态图（分支顺序逐行照抄本体） ==================
function mkSG(is_client)
    local sg = { name = is_client and "wilson_client" or "wilson", actionhandlers = {} }

    if is_client then
        -- 照抄 SGwilson_client.lua:390-426 —— 全部走 **标签**
        sg.actionhandlers[ACTIONS.PICK] = ActionHandler(ACTIONS.PICK, function(inst, action)
            if action.target:HasTag("noquickpick") then
                return "dolongaction"
            elseif inst:HasTag("farmplantfastpicker") and action.target:HasTag("farm_plant") then
                return "domediumaction"
            end
            local rider = inst.replica.rider
            if rider and rider:IsRiding() then
                return inst:HasTag("woodiequickpicker") and "dowoodiefastpick" or "dolongaction"
            elseif action.target:HasTag("pickable") then
                if inst:HasTag("fastpicker") then return "doshortaction" end
                if inst:HasTag("woodiequickpicker") then return "dowoodiefastpick" end
                if inst:HasTag("quagmire_fasthands") then return "domediumaction" end
                return (action.target:HasAnyTag("jostlepick", "jostlerummage") and "dojostleaction")
                    or (action.target:HasAnyTag("quickpick", "quickrummage") and "doshortaction")
                    or "dolongaction"
            elseif action.target:HasTag("searchable") then
                return (action.target:HasTag("jostlesearch") and "dojostleaction")
                    or (action.target:HasTag("quicksearch") and "doshortaction")
                    or "dolongaction"
            end
        end)
    else
        -- 照抄 SGwilson.lua:1043-1080 —— 服务端走 **组件**
        sg.actionhandlers[ACTIONS.PICK] = ActionHandler(ACTIONS.PICK, function(inst, action)
            if action.target:HasTag("noquickpick") then
                return "dolongaction"
            elseif inst:HasTag("farmplantfastpicker") and action.target:HasTag("farm_plant") then
                return "domediumaction"
            elseif inst.components.rider and inst.components.rider:IsRiding() then
                return inst:HasTag("woodiequickpicker") and "dowoodiefastpick" or "dolongaction"
            elseif action.target.components.pickable then
                return (action.target.components.pickable.jostlepick and "dojostleaction")
                    or (action.target.components.pickable.quickpick and "doshortaction")
                    or (inst:HasTag("fastpicker") and "doshortaction")
                    or (inst:HasTag("woodiequickpicker") and "dowoodiefastpick")
                    or (inst:HasTag("quagmire_fasthands") and "domediumaction")
                    or "dolongaction"
            elseif action.target.components.searchable then
                return (action.target.components.searchable.jostlesearch and "dojostleaction")
                    or (action.target.components.searchable.quicksearch and "doshortaction")
                    or "dolongaction"
            end
        end)
    end

    sg.actionhandlers[ACTIONS.PICKUP] = ActionHandler(ACTIONS.PICKUP, function(inst, action)
        local rr = (inst.components and inst.components.rider) or (inst.replica and inst.replica.rider)
        if rr ~= nil and rr:IsRiding() then
            if action.target ~= nil and action.target:HasTag("heavy") then return "dodismountaction" end
            return "domediumaction"
        end
        return "doshortaction"
    end)

    sg.actionhandlers[ACTIONS.HARVEST] = ActionHandler(ACTIONS.HARVEST, function(inst)
        return inst:HasTag("quagmire_fasthands") and "domediumaction" or "dolongaction"
    end)

    sg.actionhandlers[ACTIONS.COOK] = ActionHandler(ACTIONS.COOK, function(inst)
        return inst:HasTag("expertchef") and "domediumaction" or "dolongaction"
    end)

    sg.actionhandlers[ACTIONS.INTERACT_WITH] = ActionHandler(ACTIONS.INTERACT_WITH, function(inst, action)
        return (action.target:HasTag("yotb_stage") and "doshortaction")
            or (inst:HasTag("plantkin") and "domediumaction")
            or "dolongaction"
    end)

    sg.actionhandlers[ACTIONS.PLANTSOIL] = ActionHandler(ACTIONS.PLANTSOIL, function(inst)
        return (inst:HasTag("quagmire_farmhand") and "doshortaction")
            or (inst:HasTag("quagmire_fasthands") and "domediumaction")
            or "dolongaction"
    end)

    sg.actionhandlers[ACTIONS.EAT] = ActionHandler(ACTIONS.EAT, function(inst, action)
        local obj = action.target or action.invobject
        if obj ~= nil and obj:HasTag("sloweat") then return "eat" end
        return "quickeat"
    end)

    local function takeHandler(inst, action)
        return (action.target ~= nil and action.target:HasTag("inventoryitemholder_take") and "domediumaction")
            or (action.target ~= nil and action.target.takeitem ~= nil and "give")
            or "dolongaction"
    end
    sg.actionhandlers[ACTIONS.TAKEITEM] = ActionHandler(ACTIONS.TAKEITEM, takeHandler)
    sg.actionhandlers[ACTIONS.TAKESINGLEITEM] = ActionHandler(ACTIONS.TAKESINGLEITEM, takeHandler)

    return sg
end

function runPostInit(sg)
    local fns = SG_POSTINIT[sg.name]
    if fns ~= nil then
        for _, fn in ipairs(fns) do fn(sg) end
    end
    return sg
end

-- 取某个动作当前会返回的状态
function dest(sg, action, inst, act)
    local h = sg.actionhandlers[action]
    if h == nil then return "NO_HANDLER" end
    return h.deststate(inst, act)
end
"""

lua.execute(g.BOOT_LUA)


BOOT_LUA_SRC = g.BOOT_LUA          # 取成 Python str，跨 runtime 安全


def run(cfg):
    """在指定配置下建一个新的沙箱（每个配置一个独立 runtime，互不污染）"""
    lua2 = lupa.LuaRuntime(unpack_returned_tuples=True)
    lg = lua2.globals()
    lg.BOOT_LUA = BOOT_LUA_SRC
    lg.SRC = SRC
    lg.CFG = lua2.table()
    for k, v in cfg.items():
        lg.CFG[k] = v
    lua2.execute(BOOT_LUA_SRC)       # 里面会建 COMP_POSTINIT 等容器
    lua2.execute("LOAD_MOD(SRC, CFG)")
    return lua2


ALL_ON = {
    "pick_generic": True, "clear_jostle": True, "search_generic": True,
    "quick_harvest": True, "quick_cook_on_fire": True, "quick_riding": True,
    "quick_plant_interact": True, "quick_eat": True, "lureplant_take": True,
}
ALL_OFF = {k: False for k in ALL_ON}


# =====================================================================
#  2) 功能断言
# =====================================================================
print()
print("=" * 78)
print("1) 功能断言（全开配置）")
print("=" * 78)

L = run(ALL_ON)

# 建各色实体 —— 走 addComp，让 ComponentPostInit 真的跑一遍
L.execute(r"""
SRV = mkSG(false)
CLI = mkSG(true)
runPostInit(SRV)
runPostInit(CLI)

function entTree(tags, comps_)
    local e = mkEnt(tags, false)
    for name, cfg in pairs(comps_ or {}) do addComp(e, name, cfg, false) end
    return e
end

-- 普通可采集植物（例如小树枝）
E_SAPLING = mkEnt({}, false)
addComp(E_SAPLING, "pickable", { quickpick = false, jostlepick = false }, false)

-- 浆果丛（本体给 jostlepick = true）
E_BERRY = mkEnt({}, false)
addComp(E_BERRY, "pickable", { quickpick = false, jostlepick = true }, false)

-- 本体已 instant 的花（本体自己设 quickpick = true + 打 quickpick 标签）
E_FLOWER = mkEnt({ quickpick = true }, false)
addComp(E_FLOWER, "pickable", { quickpick = true }, false)

-- 本体自带 opt-out（junk_pile_big）
E_NOQP = mkEnt({ noquickpick = true }, false)
addComp(E_NOQP, "pickable", { quickpick = false }, false)

-- 农场作物：带 farm_plant 标签
E_FARM = mkEnt({ farm_plant = true }, false)
addComp(E_FARM, "pickable", { quickpick = false }, false)

-- 农夫（沃姆伍德技能：farmplantfastpicker）
P_WORM = mkEnt({ farmplantfastpicker = true }, false)

-- 普通玩家 / 骑牛玩家
P      = mkEnt({}, false)
P_RIDE = mkEnt({}, true)

-- 可搜索物
E_FLOTSAM = mkEnt({}, false)
addComp(E_FLOTSAM, "searchable", { quicksearch = false, jostlesearch = false }, false)

-- 慢吃的肉 / 快吃的浆果
E_MEAT  = mkEnt({ sloweat = true }, false)
E_BERRYFOOD = mkEnt({}, false)

-- 食人花（要模拟它走了 PrefabPostInit，才会拿到 TAKE_FAST_TAG）
E_LURE = mkEnt({ inventoryitemholder_take = true }, false)
do
    local fns = PREFAB_POSTINIT["lureplant"]
    if fns ~= nil then for _, fn in ipairs(fns) do fn(E_LURE) end end
end
-- 普通带 shelf 的 holder（不该被提速）
E_OTHERHOLDER = mkEnt({ inventoryitemholder_take = true }, false)

-- 农场植物（可对话）
E_TENDABLE = mkEnt({ tendable_farmplant = true }, false)
E_YOTBSTAGE = mkEnt({ yotb_stage = true }, false)

-- 重物
E_HEAVY = mkEnt({ heavy = true }, false)
""")


def act(sg, action, inst, target=None, invobject=None):
    L.execute("__sg = %s" % sg)
    L.execute("__inst = %s" % inst)
    L.execute("__act = { target = %s, invobject = %s }" % (target or "nil", invobject or "nil"))
    L.execute("__r = dest(__sg, ACTIONS.%s, __inst, __act)" % action)
    return L.globals().__r


# --- 标签是否真的打上了 ---------------------------------------------
print("\n[A] 标记阶段")
show("普通植物被打上我们的 FAST_TAG",
     L.eval('E_SAPLING:HasTag("%s")' % FAST_TAG) == True)
show("★ 但 pickable.quickpick 仍是 false（Woby 安全）",
     L.eval("E_SAPLING.components.pickable.quickpick") == False)
show("浆果丛也打上了（→ 骑乘/摇晃场景可用）",
     L.eval('E_BERRY:HasTag("%s")' % FAST_TAG) == True)
show("可搜索物被打上 FAST_TAG",
     L.eval('E_FLOTSAM:HasTag("%s")' % FAST_TAG) == True)
show("食人花被 PrefabPostInit 打上 TAKE_FAST_TAG",
     L.eval('(function() local fns = PREFAB_POSTINIT["lureplant"]; '
            'if fns == nil then return false end; '
            'local e = mkEnt({}, false); for _, fn in ipairs(fns) do fn(e) end; '
            'return e:HasTag("%s") end)()' % TAKE_TAG) == True)

# 桩自检：别因为夹具本身没设上标签而误判（上一版就踩过 ipairs 遍历哈希表的坑）
show("桩自检 · E_NOQP 带 noquickpick",
     L.eval('E_NOQP:HasTag("noquickpick")') == True)
show("桩自检 · E_HEAVY 带 heavy", L.eval('E_HEAVY:HasTag("heavy")') == True)
show("桩自检 · E_TENDABLE 带 tendable_farmplant",
     L.eval('E_TENDABLE:HasTag("tendable_farmplant")') == True)
show("桩自检 · E_YOTBSTAGE 带 yotb_stage",
     L.eval('E_YOTBSTAGE:HasTag("yotb_stage")') == True)
show("桩自检 · E_LURE 带 inventoryitemholder_take",
     L.eval('E_LURE:HasTag("inventoryitemholder_take")') == True)
show("桩自检 · E_FLOWER 带 quickpick",
     L.eval('E_FLOWER:HasTag("quickpick")') == True)
show("桩自检 · P_RIDE 处于骑乘状态",
     L.eval('P_RIDE.components.rider:IsRiding()') == True)

# --- PICK -----------------------------------------------------------
print("\n[B] PICK（采集）")
show("普通植物：dolongaction → doshortaction",
     act("SRV", "PICK", "P", "E_SAPLING") == "doshortaction",
     "实际=%s" % act("SRV", "PICK", "P", "E_SAPLING"))
show("★ 浆果丛(jostlepick)：dojostleaction → doshortaction（jostlepick 优先级坑已绕过）",
     act("SRV", "PICK", "P", "E_BERRY") == "doshortaction",
     "实际=%s" % act("SRV", "PICK", "P", "E_BERRY"))
show("本体已 instant 的花：保持 doshortaction",
     act("SRV", "PICK", "P", "E_FLOWER") == "doshortaction")
show("★ noquickpick（junk_pile_big）：必须保持 dolongaction",
     act("SRV", "PICK", "P", "E_NOQP") == "dolongaction",
     "实际=%s" % act("SRV", "PICK", "P", "E_NOQP"))
show("骑牛 + 普通植物：dolongaction → doshortaction",
     act("SRV", "PICK", "P_RIDE", "E_SAPLING") == "doshortaction",
     "实际=%s" % act("SRV", "PICK", "P_RIDE", "E_SAPLING"))
show("★ 沃姆伍德 + 农场作物：domediumaction → doshortaction",
     act("SRV", "PICK", "P_WORM", "E_FARM") == "doshortaction",
     "实际=%s" % act("SRV", "PICK", "P_WORM", "E_FARM"))
show("客户端图同样生效（靠本体同步的 pickable 标签）",
     act("CLI", "PICK", "P", "E_SAPLING") == "doshortaction",
     "实际=%s" % act("CLI", "PICK", "P", "E_SAPLING"))
show("客户端图也绕过 jostlepick",
     act("CLI", "PICK", "P", "E_BERRY") == "doshortaction")
show("客户端图也尊重 noquickpick",
     act("CLI", "PICK", "P", "E_NOQP") == "dolongaction")

# --- PICKUP / HARVEST / COOK ----------------------------------------
print("\n[C] PICKUP / HARVEST / COOK")
show("骑牛拾取轻物：domediumaction → doshortaction",
     act("SRV", "PICKUP", "P_RIDE", "E_SAPLING") == "doshortaction",
     "实际=%s" % act("SRV", "PICKUP", "P_RIDE", "E_SAPLING"))
show("骑牛拾取重物：dodismountaction 必须保持（还得下牛）",
     act("SRV", "PICKUP", "P_RIDE", "E_HEAVY") == "dodismountaction",
     "实际=%s" % act("SRV", "PICKUP", "P_RIDE", "E_HEAVY"))
show("步行拾取：本来就是 doshortaction，不受影响",
     act("SRV", "PICKUP", "P", "E_SAPLING") == "doshortaction")
show("HARVEST（锅/晾肉架）：dolongaction → doshortaction",
     act("SRV", "HARVEST", "P") == "doshortaction")
show("COOK（篝火）：dolongaction → doshortaction",
     act("SRV", "COOK", "P") == "doshortaction")

# --- INTERACT_WITH / PLANTSOIL / EAT ---------------------------------
print("\n[D] INTERACT_WITH / PLANTSOIL / EAT")
show("与农场植物对话：dolongaction → doshortaction",
     act("SRV", "INTERACT_WITH", "P", "E_TENDABLE") == "doshortaction",
     "实际=%s" % act("SRV", "INTERACT_WITH", "P", "E_TENDABLE"))
show("★ 其它 INTERACT_WITH（YOTB 舞台）：不得被改动",
     act("SRV", "INTERACT_WITH", "P", "E_YOTBSTAGE") == "doshortaction")
show("★ 普通 INTERACT_WITH 目标：不该被升级",
     act("SRV", "INTERACT_WITH", "P", "E_SAPLING") == "dolongaction",
     "实际=%s" % act("SRV", "INTERACT_WITH", "P", "E_SAPLING"))
show("播种：dolongaction → doshortaction",
     act("SRV", "PLANTSOIL", "P") == "doshortaction")
show("慢吃肉：eat → quickeat",
     act("SRV", "EAT", "P", "E_MEAT") == "quickeat")
show("快吃浆果：quickeat 不变",
     act("SRV", "EAT", "P", "E_BERRYFOOD") == "quickeat")

# --- TAKEITEM --------------------------------------------------------
print("\n[E] TAKEITEM（食人花）")
show("取食人花的肉：domediumaction → doshortaction",
     act("SRV", "TAKEITEM", "P", "E_LURE") == "doshortaction",
     "实际=%s" % act("SRV", "TAKEITEM", "P", "E_LURE"))
show("★ 其它 inventoryitemholder：保持 domediumaction",
     act("SRV", "TAKEITEM", "P", "E_OTHERHOLDER") == "domediumaction",
     "实际=%s" % act("SRV", "TAKEITEM", "P", "E_OTHERHOLDER"))

# --- mount_valid ------------------------------------------------------
print("\n[F] 骑乘解锁")
show("ACTIONS.HARVEST.mount_valid 被打开（否则骑乘时根本没这个选项）",
     L.eval("ACTIONS.HARVEST.mount_valid") == True)
show("ACTIONS.TAKEITEM.mount_valid 被打开",
     L.eval("ACTIONS.TAKEITEM.mount_valid") == True)


# =====================================================================
#  3) 反测：全关 = 原版行为
# =====================================================================
print()
print("=" * 78)
print("2) 反测：全部关闭时，必须与本体**逐场景完全一致**")
print("=" * 78)

L0 = run(ALL_OFF)
L0.execute(r"""
SRV0 = mkSG(false)
CLI0 = mkSG(true)
runPostInit(SRV0)
runPostInit(CLI0)
BASE_SRV = mkSG(false)   -- 没跑过 postinit 的原始图，作为基准
BASE_CLI = mkSG(true)

function mk0(tags, comps_)
    local e = mkEnt(tags, false)
    for name, cfg in pairs(comps_ or {}) do addComp(e, name, cfg, false) end
    return e
end
E0_SAPLING = mkEnt({}, false); addComp(E0_SAPLING, "pickable", { quickpick = false }, false)
E0_BERRY   = mkEnt({}, false); addComp(E0_BERRY,   "pickable", { jostlepick = true }, false)
E0_FLOWER  = mkEnt({ quickpick = true }, false); addComp(E0_FLOWER, "pickable", { quickpick = true }, false)
E0_NOQP    = mkEnt({ noquickpick = true }, false); addComp(E0_NOQP, "pickable", { quickpick = false }, false)
E0_FARM    = mkEnt({ farm_plant = true }, false); addComp(E0_FARM, "pickable", { quickpick = false }, false)
P0      = mkEnt({}, false)
P0_WORM = mkEnt({ farmplantfastpicker = true }, false)
P0_RIDE = mkEnt({}, true)
E0_MEAT = mkEnt({ sloweat = true }, false)
E0_LURE = mkEnt({ inventoryitemholder_take = true }, false)
E0_YOTB = mkEnt({ yotb_stage = true }, false)
E0_TEND = mkEnt({ tendable_farmplant = true }, false)
""")

CASES = [
    ("PICK", "P0", "E0_SAPLING"),
    ("PICK", "P0", "E0_BERRY"),
    ("PICK", "P0", "E0_FLOWER"),
    ("PICK", "P0", "E0_NOQP"),
    ("PICK", "P0_RIDE", "E0_SAPLING"),
    ("PICK", "P0_WORM", "E0_FARM"),
    ("PICKUP", "P0_RIDE", "E0_SAPLING"),
    ("PICKUP", "P0", "E0_SAPLING"),
    ("HARVEST", "P0", "nil"),
    ("COOK", "P0", "nil"),
    ("INTERACT_WITH", "P0", "E0_TEND"),
    ("INTERACT_WITH", "P0", "E0_YOTB"),
    ("PLANTSOIL", "P0", "nil"),
    ("EAT", "P0", "E0_MEAT"),
    ("TAKEITEM", "P0", "E0_LURE"),
]


def pair(sg, action, inst, target):
    L0.execute("__sg = %s" % sg)
    L0.execute("__i = %s" % inst)
    L0.execute("__a = { target = %s }" % target)
    L0.execute("__r = dest(__sg, ACTIONS.%s, __i, __a)" % action)
    return L0.globals().__r


same = 0
for action, inst, target in CASES:
    a = pair("SRV0", action, inst, target)
    b = pair("BASE_SRV", action, inst, target)
    ok = (a == b)
    if ok:
        same += 1
    else:
        show("反测失败 %s %s %s：补丁后=%s 原版=%s" % (action, inst, target, a, b), False)

show("服务端 %d 组场景与本体完全一致" % len(CASES), same == len(CASES),
     "%d/%d" % (same, len(CASES)))

same_c = 0
for action, inst, target in CASES:
    a = pair("CLI0", action, inst, target)
    b = pair("BASE_CLI", action, inst, target)
    if a == b:
        same_c += 1
    else:
        show("反测失败(客户端) %s %s" % (action, inst), False)
show("客户端 %d 组场景与本体完全一致" % len(CASES), same_c == len(CASES),
     "%d/%d" % (same_c, len(CASES)))

show("全关时 mount_valid 不会被改",
     L0.eval("ACTIONS.HARVEST.mount_valid") in (None, False))


# =====================================================================
#  4) 单项开关互不串台
# =====================================================================
print()
print("=" * 78)
print("3) 单项开关：只关一个，其它照常")
print("=" * 78)

# 只关 clear_jostle
Lj = run({**ALL_ON, "clear_jostle": False})
Lj.execute(r"""
SRVj = mkSG(false); runPostInit(SRVj)
Ej_BERRY = mkEnt({}, false); addComp(Ej_BERRY, "pickable", { jostlepick = true }, false)
Ej_SAP   = mkEnt({}, false); addComp(Ej_SAP,   "pickable", { quickpick = false }, false)
Pj = mkEnt({}, false)
""")
show("关掉「摇晃也快」后：浆果丛保持 dojostleaction",
     Lj.eval('dest(SRVj, ACTIONS.PICK, Pj, { target = Ej_BERRY })') == "dojostleaction")
show("关掉「摇晃也快」不影响普通植物",
     Lj.eval('dest(SRVj, ACTIONS.PICK, Pj, { target = Ej_SAP })') == "doshortaction")

# 只关 quick_riding
Lr = run({**ALL_ON, "quick_riding": False})
Lr.execute(r"""
SRVr = mkSG(false); runPostInit(SRVr)
Er_SAP = mkEnt({}, false); addComp(Er_SAP, "pickable", { quickpick = false }, false)
Pr     = mkEnt({}, false)
Pr_R   = mkEnt({}, true)
""")
show("关掉「骑乘」后：骑牛采集回到 dolongaction",
     Lr.eval('dest(SRVr, ACTIONS.PICK, Pr_R, { target = Er_SAP })') == "dolongaction")
show("关掉「骑乘」不影响步行采集",
     Lr.eval('dest(SRVr, ACTIONS.PICK, Pr, { target = Er_SAP })') == "doshortaction")
show("关掉「骑乘」后 HARVEST 不设 mount_valid",
     Lr.eval("ACTIONS.HARVEST.mount_valid") in (None, False))

# 只关 pick_generic
Lp = run({**ALL_ON, "pick_generic": False})
Lp.execute(r"""
SRVp = mkSG(false); runPostInit(SRVp)
Ep_SAP = mkEnt({}, false); addComp(Ep_SAP, "pickable", { quickpick = false }, false)
Pp = mkEnt({}, false)
""")
show("关掉「通用采集」后不注册 pickable 的 ComponentPostInit",
     Lp.eval('COMP_POSTINIT["pickable"]') is None)
show("关掉「通用采集」后普通植物回到 dolongaction",
     Lp.eval('dest(SRVp, ACTIONS.PICK, Pp, { target = Ep_SAP })') == "dolongaction")

# 只关 lureplant_take
Ll = run({**ALL_ON, "lureplant_take": False})
Ll.execute(r"""
SRVl = mkSG(false); runPostInit(SRVl)
El_LURE = mkEnt({ inventoryitemholder_take = true }, false)
Pl = mkEnt({}, false)
""")
show("关掉「食人花」后 TAKEITEM 保持 domediumaction",
     Ll.eval('dest(SRVl, ACTIONS.TAKEITEM, Pl, { target = El_LURE })') == "domediumaction")
show("关掉「食人花」后不注册 lureplant 的 PrefabPostInit",
     Ll.eval('PREFAB_POSTINIT["lureplant"]') is None)


# =====================================================================
print()
print("=" * 78)
if fails:
    print("失败 %d 项：" % len(fails))
    for f in fails:
        print("   · " + f)
    sys.exit(1)
print("全部通过")
