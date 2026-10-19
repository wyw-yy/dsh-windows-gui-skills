# BOOT.md — 这台机器 + 不许犯的错

> 新对话里 `@BOOT.md` 读一次即可。技能清单**不写在这里**：DSH 每轮自动注入技能目录
> （名字 + 描述），手工维护的副本必然漂移。历史备注：前一版列过 7 个、其中一个当时还加载不了，
> 那两条都已作废（实测 8 个全部可加载）——别把数量写回来，写回来就会过期。

**加载规则**：任务命中触发词就**先 `skill` 再动手**，别靠"记得"。完整路由表在
`AGENTS.md` §三（每轮都注入，以它为准）：

| 触发 | 技能 |
|---|---|
| 截图 / 点击 / 弹窗 / 窗口坐标 | `windows-gui-control` |
| 点了没反应 / 怎么验证 / 遮挡 | `windows-screen-automation` |
| 控件找不到 / UIA / Java·Electron | `windows-uia-inspector` |
| 打字 / 快捷键 / 焦点 / 中文乱码 | `windows-input-bridge` |
| 建工程 / 烧录 / 灯不亮 / CubeMX / Keil | `stm32f4-bringup` |
| 需求含糊 / 不可逆 / 花钱 | `clarify-before-act` |

## 机器环境

- Keil：`C:\Keil_v5\UV4\UV4.exe`（`-b` 编译、`-f` 烧录；判据看日志末尾 `0 Error(s)` / `Verify OK`）
- CubeMX：`C:\Users\<用户>\AppData\Local\Programs\STM32CubeMX\STM32CubeMX.exe`（`-q gen.txt` 无界面）
- 串口：**不要写死**。现查 `Get-CimInstance Win32_SerialPort` 或 `[IO.Ports.SerialPort]::GetPortNames()`
  —— ST-Link VCP 只在探针插着时出现，拔掉后编号会让给蓝牙串口（本机现在只有 COM8/COM9）
- 运行环境：Windows + PowerShell 5.1；Python 3.12.8 + **pywinauto 0.6.9 已装**（`uia.py` 开箱可用）
- 脚本：全部纯 ASCII、无 BOM（`ui.ps1` 的 BOM 已去掉）；dot-source 前先 `Set-ExecutionPolicy -Scope Process Bypass`。`Add-Type` 的 here-string 里不要写 PowerShell 变量，否则会被当 C# 编译报错。

## 技能装在哪（决定优先级）

- 用户级 `%USERPROFILE%\.agents\skills\` —— 全局，rank 500
- 工程级 `<项目根>\.agents\skills\` —— **优先于用户级**（rank 200）
  - 项目根 = 最近含 `.git` 的祖先目录；没有 `.git` 就用当前工作目录
  - 想让某个技能只对一个工程生效，放工程级即可，会压过用户级同名技能
- SKILL.md 的 frontmatter 必须是合法 YAML：`description` 里出现 `: `（冒号+空格）要用引号包住，
  否则该技能会被**静默丢弃**（不报错、不出现在目录里，`skill xxx` 报 unknown）

## 经验库（每个技能自带）

- 位置：`%USERPROFILE%\.agents\skills\<技能>\knowledge\lessons.md`（≤40 行，加载技能后读一遍）
- 内容：**可复用的规则**，不是工程参数（判据：换一个任务这句话还用得上吗）
- 维护脚本：`%USERPROFILE%\.agents\skills\windows-gui-control\scripts\lesson.ps1`
  - `add -Skill <技能> -Key <域>.<主题> -Text "<一句话>" -Confidence 3-5`
  - `hit` / `miss`：命中与矛盾；连续 2 次矛盾降一级，降到 1 标 `[REFUTED]`（保留但不采用）
  - `prune`：超过 40 条按置信/时效/命中淘汰
- 写入触发只有三种：**同一坑踩两次 / 结果推翻假设 / 用户明确指教**

## 三条硬规矩

1. 能 CLI 就别点鼠标；能指令就别抢用户鼠标。
2. 破坏性动作（删除/覆盖/发送/付款/烧录）先说清后果。
3. 每次点击/输入后要校验，别假设它生效了。
