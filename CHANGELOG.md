# Changelog

## 0.1.2 — 2026-10-18

外部审核（`REVIEW-NOTES-2026-10-18.md`）逐条修复：

- **P0 `uia.py` 崩溃**：`control_of()` 不再对 `UIAWrapper` 调 `child_window()`
  （此前 `find`/`click` 必抛 `'UIAWrapper' object has no attribute 'child_window'`），
  改为按祖先遍历匹配，`tree` 的缩进按真实深度输出。
- **P1 物理点击会点到别的窗口**：`uia.py click --input` 在目标窗口不是前台时拒绝，
  退出码 3 并给出提示；确认层叠关系后才可 `--force`。
- **P1 文档写错 HAL 行为**：`stm32f4-bringup` 的 3b 节纠正为“HAL 不校验 PLL 频率”，
  `HAL_RCC_OscConfig` 在等 `PLLRDY` 超时后返回 `HAL_TIMEOUT`
  （`stm32f4xx_hal_rcc.c:487`，不是 `HAL_ERROR`），并补上 `.ioc` 里
  `HCLK=168000000` 的跨型号陷阱。
- **P2 定位 API**：`Get-Window -Like` 真按通配符转义（`-Regex` 才当正则）、新增
  `Get-Window -Hwnd`；`Assert-Window` 接受 HWND、IntPtr 和 `Get-WindowList` 的行。
- **P2 截图契约**：`Get-WindowCapture` 对最小化窗口直接抛错（`-NoThrow` 才返回状态），
  默认文件名带 HWND；`Test-Occluded` 用随机文件名并返回真实 `WindowPng/ScreenPng`。
- **P2 硬规则**：补 UAC 提权窗口不可控（UIPI）、截图涉及隐私、脚本内保持 ASCII。
- **描述去重**：`windows-gui-control` 改为“函数参考”，入口判断归
  `windows-screen-automation`，避免四个技能的触发描述互相重叠。

## 0.1.0 — 2026-10-18

首个版本。把四个在真实任务里验证过的技能打包成 DSH 插件。

- `windows-gui-control`：`ui.ps1`（19 KB，25 个函数）+ `uia.py`（pywinauto 桥）
- `windows-screen-automation`：看→点→验闭环、`Get-WindowCapture` 遮挡截图、像素差阈值
- `windows-uia-inspector`：UIA 树 dump、定位优先级、Java/SWT 空树的处置
- `windows-input-bridge`：剪贴板打字、组合键、焦点/时序、控制台窗口的特殊情况

已验证的场景：

- STM32CubeMX（Java/SWT，无控件树）：点 `GENERATE CODE`、点时钟求解器对话框
- Keil uVision：`UV4.exe -b/-f` 之外的图形操作
- 记事本 / 资源管理器 / cmd：真实鼠标点击 + 剪贴板打字 + 窗口截图回执

已知问题：

- 最小化窗口无法截图（矩形退化为 158×26）；
- 启动器进程 PID ≠ 窗口 PID（Win11 打包应用会复用实例），`Get-WindowByPid` 可能返回 `$null`，脚本已加 `Assert-Window` 明确报错。
