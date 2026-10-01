-- QuickPickPlus · 快速采集（通用版）
-- Copyright (C) 2026 dawei233
-- 依 GNU GPL v3（或任何更新版本）发布，不作任何担保。完整条款见随附的 LICENSE。

local Lg = locale == "zh" or locale == "zhr"

name = Lg and "快速采集 · 通用版（Quick Pick Plus）" or "Quick Pick Plus"

description = Lg and
[[让几乎所有东西都能快速采集 —— 而且**不需要维护任何名单**。

和常见的快速采集 Mod 不同，本 Mod 不靠一份写死的 prefab 白名单，
而是直接给「可采集 / 可翻找」组件打上快速标记，所以：
  · 游戏本体新加的任何植物，自动生效
  · 其它 Mod 新增的植物 / 物品（咖啡丛、农场作物、杂草……），也自动生效
  · 以后不用等作者更新

【四件事】
1. 通用快速采集：所有可采集物（含其它 Mod 新增的）瞬时采集。
2. 通用快速收获：烹饪锅 / 晾肉架 / 农场 / 蜂箱，以及农场作物与杂草
   —— 农场作物走本体的 farm_plant 标签，所以**任何 Mod 新增的作物也一并覆盖**。
3. 骑乘完整支持：骑着皮弗娄牛 / 沃比时，采集、拾取、收割、取物全部同样快
   （原版骑乘时会强制慢动作，甚至直接把动作藏起来）。
4. 不破坏 Walter 的「毛茸茸采集者」：本 Mod **刻意不设 pickable.quickpick**，
   因为一旦设了，沃比会跳过那株植物、白白少一份食物。

【顺带修掉的一个老问题】
原版判定"先看抖动(jostlepick)、再看快速(quickpick)"，
所以浆果丛这类"摇晃型"植物永远走慢动作 —— 旧写法给它们加 quickpick 也没用。
本 Mod 可选把抖动型一并变快。

【与上游项目的关系 / 许可】
本项目基于工坊 GPL-3.0 项目「Quick Pick+ (Woby Edition)」by Jotave
（工坊 3739258809）开发。来自它的做法：
  · 包装 deststate（先委托原逻辑、再升级慢状态）的挂点手法
  · 用本体自带的 farm_plant 标签覆盖全部农场作物与杂草
  · 骑乘时给 HARVEST / TAKEITEM 补 mount_valid
  · 以及最关键的一条结论 —— 不要设 pickable.quickpick，否则会让
    Walter 的 Woby 跳过该植物
更上游为「Quick Pick」by 辣椒小皇纸（工坊 2921270365），是最初的实现。

本项目新增的是「零白名单」的整体设计 —— 用 AddComponentPostInit 给
「可采集 / 可翻找组件」本身打标记，不维护任何 prefab 名单，
从而自动覆盖本体更新与其它 mod 新增的植物。
因上述渊源，本项目依 GPL-3.0 发布。]]
or
[[Makes almost everything pick quickly -- with NO prefab whitelist.

Instead of a hardcoded list of prefabs, it tags the "pickable"/"searchable" components
themselves, so it automatically covers:
  · any plant added by a future game update
  · any plant/item added by other mods (custom coffee bushes, farm crops, weeds, ...)
  · no need to wait for the author to update

Four things it does:
1. Generic quick pick  -- every pickable plant, instantly.
2. Generic quick harvest -- cookpots/dryers/farms/bee boxes, plus every farm crop and
   weed (via the game's own "farm_plant" tag, so mod-added crops are covered too).
3. Full mounted support -- while riding a Beefalo or Woby, picking, pickup, harvesting
   and taking items are all fast (vanilla forces slow actions, or hides them entirely).
4. Walter-safe -- it deliberately does NOT set pickable.quickpick, because doing so makes
   Woby's "Furry Forager" skip that plant and lose the bonus food.

Credits / License: this project is built upon the GPL-3.0 project
Quick Pick+ (Woby Edition) by Jotave (workshop 3739258809) --
from it come the deststate wrapping approach, the use of the game's own
"farm_plant" tag to cover every farm crop and weed, the mount_valid fix for
HARVEST/TAKEITEM while riding, and the key finding that setting
pickable.quickpick breaks Woby's foraging. The lureplant snippet and the
tag naming also follow it.
Upstream of that: Quick Pick by 辣椒小皇纸 (workshop 2921270365).

New here: the "no whitelist" design -- tagging the pickable/searchable
components themselves via AddComponentPostInit, so nothing has to be listed.
Released under GPL-3.0, same as both upstream projects.]]

author = "dawei233"
version = "2.0.0"
forumthread = ""

api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

-- 客户端也要生效（动作状态由客户端预测），但本地 mod 不便强制别人装
all_clients_require_mod = false
client_only_mod = false

server_filter_tags = { "Quick Pick", "utility", "tweak" }

local boolean_option = {
    { description = Lg and "开" or "On", data = true },
    { description = Lg and "关" or "Off", data = false },
}

configuration_options = {
    {
        name = "pick_generic",
        label = Lg and "★ 通用快速采集（推荐）" or "★ Generic quick pick",
        hover = Lg and "给所有可采集植物打快速标记，包含本体新增与其它 Mod 新增的植物。\n关掉后本 Mod 基本就退化成旧版那种白名单模式了。"
                     or "Mark every pickable plant as quick, including plants added by updates or other mods.\nTurning this off mostly reduces the mod to the old whitelist behaviour.",
        options = boolean_option,
        default = true,
    },
    {
        name = "clear_jostle",
        label = Lg and "浆果丛等「摇晃型」也变快" or "Speed up shake-type bushes too",
        hover = Lg and "原版判定里 jostlepick 优先于 quickpick，所以浆果丛一律慢动作。\n开启后改为快速动作（会失去摇晃动画）。"
                     or "Vanilla checks jostlepick before quickpick, so berry bushes always played the slow animation.\nEnable to use the fast action instead (the shake animation is skipped).",
        options = boolean_option,
        default = true,
    },
    {
        name = "search_generic",
        label = Lg and "通用快速搜索" or "Generic quick search",
        hover = Lg and "沉船残骸、可疑的土堆等「可搜索」目标的搜刮动作变快。" or "Speed up searching searchable targets (flotsam, suspicious dirt piles, ...).",
        options = boolean_option,
        default = true,
    },
    {
        name = "quick_harvest",
        label = Lg and "快速收获" or "Quick harvest",
        hover = Lg and "从烹饪锅、晾肉架、农场、蜂箱等处收获变快。" or "Quick picking from cookpots, dryers, farms and bee boxes.",
        options = boolean_option,
        default = true,
    },
    {
        name = "quick_cook_on_fire",
        label = Lg and "快速在火上烤" or "Quick cook on fire",
        hover = Lg and "把食物放到篝火上烤的动作变快。" or "Quickly cooking food on a firepit.",
        options = boolean_option,
        default = true,
    },
    {
        name = "quick_riding",
        label = Lg and "骑牛时也能快速操作" or "Quick actions while riding",
        hover = Lg and "原版骑着皮弗娄牛 / 沃比时采集、拾取一律慢动作，收割和取物更是直接没有选项。\n开启后全部变得和步行时一样快。"
                     or "Vanilla forces slow actions while riding, and hides harvest/take entirely.\nEnable to make everything as fast as on foot.",
        options = boolean_option,
        default = true,
    },
    {
        name = "quick_plant_interact",
        label = Lg and "快速种植与对话" or "Quick plant & talk to plants",
        hover = Lg and "播种，以及与农场植物对话（让它开心）的动作变快。" or "Quick planting seeds, and quick talking to farm plants.",
        options = boolean_option,
        default = true,
    },
    {
        name = "quick_eat",
        label = Lg and "快速进食" or "Quick eat",
        hover = Lg and "吃肉等「慢吃」食物时也要等一段长动画，开启后和吃浆果一样快。" or "Meats and other slow foods normally play the long eating animation; make them as fast as berries.",
        options = boolean_option,
        default = true,
    },
    {
        name = "lureplant_take",
        label = Lg and "快速取食人花的肉" or "Quick take from lureplant",
        hover = Lg and "食人花产出的肉要用「拿取」动作，原本是慢动作，开启后变快。" or "Taking the meat a lureplant produces normally plays the slow animation; make it quick.",
        options = boolean_option,
        default = true,
    },
}
