# Quick Pick Plus · 快速采集（通用版）

Don't Starve Together 的一个小 mod：让几乎所有东西都能**瞬时采集**，
而且**不需要维护任何 prefab 名单**。

作者：dawei233 ｜ 版本：2.0.0 ｜ 许可：GPL-3.0（见文末）

---

## 它解决什么问题

常见的快速采集 mod 都靠一份**写死的 prefab 白名单**：

```lua
local quick_pick_list = { "sapling", "grass", "berrybush", "reeds", ... }
```

于是本体新加的植物要等作者更新，其它 mod 新增的植物（咖啡丛、各种作物）
更是不在名单里 —— 只好再硬编码一条 `if 装了XX mod then 加上 YY 植物 end`，
永远滞后一步。

本 mod 换了个做法：**不去列"哪些植物要快"，而是改"判定所依赖的那个开关"**。

| 做法 | 覆盖范围 |
|---|---|
| 白名单 | 只有名单里的 |
| 本 mod | 任何带「可采集 / 可翻找」组件的实体 —— 本体新增、其它 mod 新增，全部自动生效 |

---

## 实现（两句话）

1. **零白名单标记**：`AddComponentPostInit("pickable" / "searchable")`
   → 给实体打一个自定义标签。凡是带这两个组件的，无一遗漏。
2. **动作升级**：包装状态图动作处理器的 `deststate`，**先委托原逻辑**，
   再把慢状态（`dolongaction` / `domediumaction`）升级为 `doshortaction`
   （10 帧 ≈ 0.33 秒，原本 1 秒）。

只"升级慢的"，所以本体的一切特例都被完整保留：伍迪的快采、WX 的旋转采集、
`junk_pile_big` 自带的 `noquickpick` 屏蔽、重物必须下牛…… 全都不受影响。

服务端图（`wilson`）和客户端图（`wilson_client`）都补，
否则会出现「客户端预测慢动作、服务端已经做完」的抖动。

---

## 有意为之的两个细节

### 1. 刻意**不**设 `pickable.quickpick = true`

最直觉的写法是给每个植物设 `pickable.quickpick = true`，但那样会让
**Walter 的「毛茸茸采集者」失效**：

```lua
-- prefabs/wobybig.lua:527 / wobysmall.lua:551
if not IsFoodSourcePickable(buffaction.target)
   or buffaction.target.components.pickable.quickpick then
    return
end
```

一旦 `quickpick` 为真，沃比就会**跳过**那株植物 —— 玩家白白少拿一份食物。
本 mod 只打自己的标签，所以 Woby 照常工作。

### 2. 顺手修掉一个老 bug：浆果丛

本体的 PICK 判定是「先看 `jostlepick`，再看 `quickpick`」（`SGwilson.lua:1068-1069`），
而浆果丛走的是 `jostlepick` —— 所以**很多老 mod 给它加的那行 `quickpick` 是死代码**，
浆果丛从来没快过。本 mod 直接升级动作状态，把它一并解决（可用 `clear_jostle` 关掉）。

---

## 配置项（全部默认开）

| 选项 | 说明 |
|---|---|
| `pick_generic` | **★ 通用快速采集** —— 所有可采集物，含本体/其它 mod 新增 |
| `clear_jostle` | 浆果丛等「摇晃型」也变快（会跳过摇晃动画） |
| `search_generic` | 通用快速搜索（沉船残骸、可疑土堆……） |
| `quick_harvest` | 快速收获：烹饪锅 / 晾肉架 / 农场 / 蜂箱 |
| `quick_cook_on_fire` | 快速在篝火上烤 |
| `quick_riding` | 骑牛 / 骑沃比时采集、拾取、收割、取物全部同样快 |
| `quick_plant_interact` | 快速播种，以及和农场植物对话 |
| `quick_eat` | 快速进食（肉等「慢吃」食物也变快） |
| `lureplant_take` | 快速取食人花产出的肉 |

> 农场作物与杂草全部走本体自带的 **`farm_plant` 标签**
> （`farm_plants.lua:808` / `weed_plants.lua:504`），
> 所以**其它 mod 新增的作物也一并覆盖**，与 mod 加载顺序无关。

---

## 更新日志

**2.0.0**

- **重写动作升级的挂点**：改包装 `deststate`
  （1.x 版误用了 `handler.fn` —— 那是 timeline 事件的字段，
  导致整条"动作升级"从来没生效过：浆果丛、骑乘、农场作物全都没救到）。
- **不再设 `pickable.quickpick`**，修掉会破坏 Walter 的 Woby 采集的问题。
- 新增 `farm_plant` 标签覆盖：所有农场作物与杂草（含其它 mod 新增）。
- 新增骑乘完整支持：`PICK` / `PICKUP` 提速，并给本体没标 `mount_valid`
  的 `HARVEST` / `TAKEITEM` 补上开关（否则骑乘时选项根本不出现）。
- 新增 `quick_eat`、`lureplant_take` 两个开关。

**1.0.0** — 初版，「零白名单」思路。

---

## 致谢 / 许可

机制参考自以下两个 **GPL-3.0** 项目，特此致谢：

- **Quick Pick+ (Woby Edition)** by **Jotave** — 工坊 [3739258809](https://steamcommunity.com/sharedfiles/filedetails/?id=3739258809)
  - 借鉴：`deststate` 的包装手法、用 `farm_plant` 标签覆盖全部农场作物、
    骑乘时 `mount_valid` 的处理，以及最重要的一条 ——
    **不要设 `pickable.quickpick` 以免破坏 Woby 采集**（这条是本项目 2.0.0 的关键修正）。
- **Quick Pick** by **辣椒小皇纸** — 工坊 [2921270365](https://steamcommunity.com/sharedfiles/filedetails/?id=2921270365)
  / [github.com/jupitersh/dst-mod-quick-pick](https://github.com/jupitersh/dst-mod-quick-pick)
  - 快速采集的最初实现。


---

## License

[GNU General Public License v3.0](LICENSE) 或更高版本。

```
QuickPickPlus · 快速采集（通用版）
Copyright (C) 2026 dawei233

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.
```

## 测试

仓库自带离线验证桩 —— **不需要装游戏本体**，只需要 Python + [lupa](https://pypi.org/project/lupa/)：

```bash
pip install lupa
python tests/test_quickpickplus.py     # 全绿则打印「全部通过」
```

它把 `modmain.lua` 放进模拟的 modmain 沙箱里真跑，再用**分支顺序逐行照抄本体**的假状态图
逐场景断言返回值；包含「**全部开关关闭时与本体完全一致**」的反测。
详见 [`tests/README.md`](tests/README.md)。
