# 技能索引（读这一页 = 知道有哪些技能可用）

> 用法：新对话第一句只写 `@BOOT.md`，不用再跟任务。
> 读完请回答一句「已知悉：4 个 Windows 技能 + 1 个 STM32 技能 + 2 个元规则技能」，然后等我派活。

## 技能清单

| 技能名 | 什么时候加载 | 体积 |
|---|---|---|
| `windows-screen-automation` | 要操作任何 GUI：截图、找位置、点击、验证（**默认先加载这个**） | ~6 KB |
| `windows-gui-control` | 需要函数签名/坑位时（`ui.ps1`、`pixelscan.ps1`、`uia.py` 的完整参考） | ~11 KB |
| `windows-uia-inspector` | 目标是 Win32/MFC/Qt，有控件树可按名字点 | ~6 KB |
| `windows-input-bridge` | 往输入框打字、按快捷键、鼠标三键 | ~6 KB |
| `stm32f4-bringup` | Keil 编译/烧录、板子不亮、时钟配错 | ~7 KB |
| `clarify-before-act` | 任务有歧义、不可逆、要花钱 | ~17 KB |
| `mcp-on-demand` | 考虑装/开 MCP 服务器时 | ~4 KB |

规则：**一次只加载 1–2 个**（每个 1.5–3k token），别全加载。加载方式是调用 `skill` 工具，参数为技能名全称。

## 经验库（每个技能自带）

- 位置：`%USERPROFILE%\.agents\skills\<技能>\knowledge\lessons.md`（≤40 行，加载技能后读一遍）
- 内容：**可复用的规则**，不是工程参数（判据：换一个任务这句话还用得上吗）
- 维护脚本：`%USERPROFILE%\.agents\skills\windows-gui-control\scripts\lesson.ps1`
  - `add -Skill <技能> -Key <域>.<主题> -Text "<一句话>" -Confidence 3-5`
  - `hit` / `miss`：命中与矛盾；连续 2 次矛盾降一级，降到 1 标 `[REFUTED]`（保留但不采用）
  - `prune`：超过 40 条按置信/时效/命中淘汰
- 写入触发只有三种：**同一坑踩两次 / 结果推翻假设 / 用户明确指教**

## 机器环境（不含工程状态）

- Keil：`C:\Keil_v5\UV4\UV4.exe`（`-b` 编译、`-f` 烧录，判据看日志末尾）
- CubeMX：`C:\Users\<用户>\AppData\Local\Programs\STM32CubeMX\STM32CubeMX.exe`（`-q gen.txt`）
- 串口：ST-Link VCP 通常 COM4 / 115200
- 依赖：Windows + PowerShell 5.1；`uia.py` 需 `pywinauto`（可选）；脚本一律纯 ASCII
- 技能安装目录：`%USERPROFILE%\.agents\skills\`（工作区内的 `.agents\skills` **不生效**）

## 三条硬规矩

1. 能 CLI 就别点鼠标；能指令就别抢用户鼠标。
2. 破坏性动作（删除/覆盖/发送/付款/烧录）先说清后果。
3. 每次点击/输入后要校验，别假设它生效了。
