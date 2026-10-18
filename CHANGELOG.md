# Changelog

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
