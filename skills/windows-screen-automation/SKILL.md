---
name: windows-screen-automation
description: >
  Start here for "automate this window": the look-then-act loop for Windows GUIs —
  take a screenshot, decide, click, and prove the click changed something. Covers
  full-screen and single-window capture (including windows covered by other
  windows), coords vs preview scaling, pixel-diff verification, retry policy, and
  the failure modes that silently make an automation click the wrong thing. Use
  when asked to 帮我点一下 / 截图看看 / 自动化这个界面 / click through an app, when
  the target exposes no controls, when a click seems to do nothing, when you need
  to know whether a window is occluded, or when deciding if a screenshot is worth
  sending to the model.
---

# Screen automation: look → act → verify

Companion to `windows-gui-control` (function reference) — this skill is the
*loop and the judgement*, not the API list.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\ui.ps1"
```

## Before the loop: keep the process alive, and know the sandbox

- **A GUI launched from `pwsh` dies when that tool call returns.** Start it in a
  background job, or launch it detached and re-discover its windows by PID before
  every action. Same for any helper you spawn.
- **A write-restricted sandbox blocks desktop apps that write under
  `%USERPROFILE%`** — they exit in seconds with no message and no log growth. If
  a window never appears and the log mtime is frozen, suspect the sandbox before
  suspecting the command.
- **Self-drawn dialogs are not windows.** A Java/SWT modal (CubeMX migration
  prompt) lives inside the main window's pixels; `EnumWindows` will never show
  it. Verify by capturing the owner window and diffing, not by looking for a new
  HWND.

## The loop

1. **Baseline.** Capture before acting: `$before = Get-WindowShot -Window $w -Path $b`.
2. **Decide.** From pixels (image) or from controls (`windows-uia-inspector`).
3. **Act once.** `[Win32UI]::Click($x,$y)` or `Invoke-ClickElement`.
4. **Verify cheaply.** Title changed? File appeared? `Invoke-VerifiedClick`
   returned `Changed=True`? Window list gained a dialog?
5. **Only if cheap verification is inconclusive**, look at an image.
6. **On failure, re-shoot before retrying.** Never repeat a click at the same
   coords — the reason it missed (moved window, new dialog, still loading) does
   not fix itself.

## Shooting the right rectangle

| Need | Call | Notes |
|---|---|---|
| whole desktop | `Get-Screen` | multi-monitor aware; huge on 4K |
| one region | `Get-ScreenRegion -X -Y -Width -Height` | crops after capture; cheap |
| what the user sees at the window | `Get-WindowShot -Window $w` | includes covering windows |
| the window's own pixels | `Get-WindowCapture -Window $w` | `PrintWindow(PW_RENDERFULLCONTENT)`; works while covered |

`Get-WindowCapture` is the one you want for Java/SWT apps, dialogs behind other
windows, and for reading text without dragging the whole desktop into context.
For a minimized window it throws (`cannot capture: TOOSMALL ... iconic=True`); pass `-NoThrow` if you want the status object, then restore
first (`Focus-Window $w`), capture again.

## Coordinate scale (the #1 silent bug)

The model sees a **downscaled preview**; `[Win32UI]::Click` needs **physical
screen** pixels.

```
scale = preview_image_width / physical_screen_width
```

On a 2560×1600 screen previewed at 1610×1006 that is ×1.59. Read the scale off
the numbers every time instead of assuming 1.0 — a 60 % error lands the click in
a neighbouring control, which often *does* something, so you get silent damage
rather than an obvious failure.

## Verification that costs nothing

```powershell
$r = Invoke-VerifiedClick -Window $w -X 1858 -Y 304 -TimeoutMs 2500
$r.Changed   # True/False
$r.Diff      # 0..255 mean abs channel diff over the window rect
```

Thresholds used by the code (`Test-Occluded` flags occlusion above `Diff > 20`; `Invoke-VerifiedClick` sets `Changed` above `Diff > 2`):

- `< 1.0` → nothing changed (same frame, or a blinking caret only).
- `1 – 8` → a caret/cursor blink or hover highlight; **not** proof of an action.
- `> 15` → real change: dialog opened, page switched, panel redrew.
- `> 100` → completely different content.

`Changed` is just `Diff > 2`. After clicking "build", don't trust `Changed` — the
strongest cheap signal is an artifact: a new `.hex`, a new log line, a new window
title. Prefer file/window/title evidence over pixel evidence whenever it exists.

A measured false negative: clicking into a console window (then typing a command)
returned `Changed=False, Diff=0` because PrintWindow keeps the last painted
frame and the caret/echo is not in it — yet the command provably ran (its output
was read back from the clipboard). Pixel diff proves *the window repainted*, not
*the input landed*. When the target is a console, terminal, or custom canvas,
verify with the artifact.

## Is it actually occluded?

```powershell
(Test-Occluded -Window $w) | Format-List   # Occluded, Diff, WindowPng, ScreenPng
```

`Occluded=True, Diff>50` proves the window was covered and `Get-WindowCapture`
still returned its real content (measured: an image viewer 195/255 different from
the screen area above it). `Diff≈0` while the window is visibly covered means
the app renders through a GPU surface PrintWindow cannot read → bring it forward
and screenshot the screen instead.

## Failure signatures

| Symptom | Meaning | Fix |
|---|---|---|
| `Changed=False`, window title unchanged | click missed (scale/offset) | re-shoot, recompute scale |
| `Changed=False` **but the action worked** | only a caret / console text changed; PrintWindow sees the last painted frame | verify with an artifact (clipboard, file, log, title), never with pixels alone |
| `Changed=False` **but the window title changed** | **the click worked.** SWT/Java repaints into a surface PrintWindow does not see, and the title is the only evidence that leaks out | stop — do **not** click a second time; confirm via title/content and move on |
| click visibly hits but nothing happens | app busy / wrong element / needs double-click | wait for idle title, try `DblClick` |
| `Get-WindowCapture` all black | GPU-composited surface | `Focus-Window` then `Get-Screen` |
| image is the *desktop*, not the app | window moved between shot and click | re-shoot, click immediately |
| click lands on the taskbar / another app | window lost foreground | `Focus-Window`, verify `GetForegroundWindow` |
| UI frozen mid-animation | capture too early | poll title / wait for a stable diff of two shots |

## Don't burn context on pixels you don't need

- Diff inside the script; only `read_image` when the *decision* is visual
  (which tab is selected, is the label rendered, what does the error say).
- Crop before looking: `Get-ScreenRegion` around the dialog beats a 4K screenshot.
- One image that answers three questions is fine; three images that each answer
  one are waste.

## Recipe: click "Generate Code" on a Java app and prove it

```powershell
$w = Get-Window -Like 'STM32CubeMX'
Focus-Window $w
$before = Get-WindowCapture -Window $w -Path 'C:\tmp\before.png'
Invoke-VerifiedClick -Window $w -X 1858 -Y 304 -TimeoutMs 3000 | Format-List
Test-Path 'C:\work\proj\MDK-ARM'      # artifact beats pixels
Get-ChildItem 'C:\work\proj' | Select-Object Name, LastWriteTime
```

## 经验库（自动维护）

`knowledge\lessons.md` 是本技能的经验条目（<=40 行，加载技能时一并读）。
判据：**换一个任务，这句话还用得上吗？** 工程参数、账号、一次性坐标不要写。

- 命中（按它做并且成功）：`lesson.ps1 hit  -Skill <本技能> -Key <key>`
- 矛盾（按它做失败）：`lesson.ps1 miss -Skill <本技能> -Key <key>`（连续 2 次降一级，降到 1 标 [REFUTED]，保留但不再采用）
- 新增：只在“同一坑踩两次 / 结果推翻假设 / 用户明确指教”时
  `lesson.ps1 add -Skill <本技能> -Key <域>.<主题> -Text "<一句话规则>" -Confidence 3-5`
