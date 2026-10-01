# 测试

## 跑法

```bash
python tests/test_quickpickplus.py
```

从**仓库根目录**或 `tests/` 里跑都行（路径是按脚本自身位置算的）。
末尾打印 `全部通过` 即成功；有失败会逐条列出并返回非 0。

## 依赖

- Python 3.8+
- [`lupa`](https://pypi.org/project/lupa/)（需带 **LuaJIT 2.1**，本部用 `import lupa.luajit21`）

```bash
pip install lupa
```

## 这个桩在测什么

它把 `modmain.lua` 放进一个**模拟的 DST modmain 沙箱**里真跑，捕获
`AddComponentPostInit` / `AddStategraphPostInit` / `AddPrefabPostInit` 的注册，
再造出**分支顺序逐行照抄本体**的假状态图（`wilson` 走组件判定、`wilson_client` 走标签判定），
最后逐场景调用被包装后的 `handler.deststate`，断言返回值。

分四组：

| 组 | 内容 |
|---|---|
| 0 · 源码回归 | 纯正则检查 `modmain.lua`：不含 `handler.fn`、确实包装 `deststate`、不设 `pickable.quickpick`、无 prefab 白名单表 …… |
| 1 · 夹具自检 | 确保测试实体真的带上了 `noquickpick` / `heavy` / `farm_plant` 等标签（**防止夹具自己有 bug 导致误判**） |
| 2 · 功能断言 | 采集、浆果丛、骑乘、沃姆伍德、收获、播种、进食、食人花、`noquickpick` 屏蔽 …… |
| 3 · 反测 | **全部开关关闭时，服务端 15 组 + 客户端 15 组场景必须与本体逐一完全相同** |
| 4 · 单项开关 | 只关一个开关时行为正确、且互不串台 |

## 两条硬规矩（踩过坑才加的）

1. **假宿主对象必须照抄真实构造。**
   本项目的 1.0.0 版本在桩里**自己造了一个 `handler.fn`**，
   而本体真正的字段是 `deststate` —— 桩把这个 bug 一起复刻了进去，24 项断言照样全绿。
   现在的桩直接照抄本体 `ActionHandler` 的 `Class(function(self, action, state, condition) …)`
   构造语义（含"字符串会被包成函数"）。

2. **加源码级断言。**
   纯正则、不需要模拟环境，但能把"字段名写错"这类错误钉死 ——
   见上面「组 0」。
