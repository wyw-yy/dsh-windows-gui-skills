---
name: windows-uia-inspector
description: >
  Read and use the real Windows UI Automation control tree: dump every control
  with Name / AutomationId / type / rectangle, pick a stable locator, click it
  semantically (Invoke / SelectionItem / Toggle), and read text or values without
  pixels. Includes the pywinauto CLI bridge, the locator-priority rules that stop
  you clicking the wrong "OK", and what to do when an app exposes nothing
  (Java/SWT, Electron canvas, virtualised lists). Use when you want to act on a
  control by name instead of coordinates, when a window is covered, when you need
  a control's exact rectangle, or when UIA returns an empty tree.
---

# UIA inspection: find a control, act on it, trust it

Semantic control is cheaper and far more robust than coordinate clicking — when
the app exposes a tree. This skill is about reading that tree honestly and
choosing locators that still work on the next run.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\ui.ps1"
```

## See what is there

```powershell
$w = Get-Window -Like 'Notepad'
Get-UiTree   -Window $w -Max 60          # indented, printable, paste-into-report
Get-UiNodes  -Window $w -Max 400         # objects: Type/Name/AutomationId/Enabled/X/Y/Element
```

`Get-UiTree` output looks like:

```
Window "out - 文件资源管理器" [-31882,-31980]
  TitleBar #TitleBar "out - 文件资源管理器"
    Button #Restore "还原"
    Button #Close "关闭"
```

`#xxx` is the AutomationId — that is the part worth remembering.

## Locator priority

1. **AutomationId** — stable across languages and renames. Best.
2. **Name + ControlType** — needs the UI language; breaks on localisation.
3. **Name + parent scope** — scope to the dialog/panel first, then search inside.
4. **Index among same-named siblings** — last resort; order changes with sorting.
5. **Rectangle centre + coordinate click** — only when none of the above exist.

Always scope: `Find-UiElement -Window $dialog -Name 'OK'` beats searching the
whole desktop, and it is the difference between "pressed the app's OK" and
"pressed some other window's OK".

## Find, click, read

```powershell
$el = Find-UiElement -Window $w -Name 'GENERATE CODE'          # or -AutomationId
if ($el) { Invoke-ClickElement $el }                            # Invoke→Select→Toggle→coord
Invoke-ClickByNameVerified -Window $w -Name 'GENERATE CODE'     # + pixel verify

$val = (Find-UiElement -Window $w -Type 'Edit').GetCurrentPattern(
         [System.Windows.Automation.ValuePattern]::Pattern).Current.Value
```

Notes that save time:

- `Invoke-ClickElement` falls back to clicking the element's bounding-rect centre
  when the app has no Invoke pattern — so it works on custom-drawn toolbars too,
  as long as the control exists in the tree.
- `BoundingRectangle` is in **physical screen pixels**, same space as
  `[Win32UI]::Click`. No preview scaling needed (that rule is only for images).
- Reading `Value`/`Text` patterns is how you get a status line or an error message
  without spending an image.

## pywinauto bridge (scripts\uia.py)

For quick exploration from the shell, or when you want JSON instead of objects:

```powershell
$py = "$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\uia.py"
python $py windows                                  # hwnd, pid, class, title
python $py tree  --title "STM32CubeMX" --depth 4
python $py find  --title "out - 文件资源管理器" --name "新建"
python $py click --title "..." --auto-id shareButton
python $py value --title "..." --auto-id 1234
```

`find` prints
`{"class":"Button","text":"新建","auto_id":"","rect":[20,134,148,201],"center":[84,167],"enabled":true}`
— enough to act without an image. Exit codes: `0` ok, `2` not found, `1` error.
The script forces UTF-8 on stdout; without that, CJK titles crash on a GBK console.

## Empty tree: triage before giving up

| App kind | What UIA shows | Move |
|---|---|---|
| Win32 dialog, MFC, WPF, WinForms | full tree | semantic clicks, done |
| Qt (many apps) | partial tree, custom widgets missing | mix: tree for buttons, pixels for canvas |
| Java/SWT (CubeMX) | only 最小化/最大化/关闭 | `jabswitch.exe -enable` **tested, does not help CubeMX 6.16.1** (6 nodes before and after, DLLs present, app restarted) → coordinates + window capture |
| Electron / Chromium | window + a few panes, no DOM | pixels, or drive via CDP/`--remote-debugging-port` |
| Game / DirectUI shell | nothing | pixels |

Measured here: STM32CubeMX 6.16 (SWT) exposes exactly 4 controls — the window
buttons. CodeMirror-style grids and custom dialogs likewise.

## Virtualisation and duplicates

- Scrolled lists expose only realised rows; a match "not found" may just be off
  screen. Scroll first (`Send-Key "{PGDN}"` in the list), then re-query.
- Three controls named `OK` is normal. Print `Type`, `AutomationId`, and the
  containing pane for each hit before clicking.
- `IsEnabled=False` clicks do nothing — check `Enabled` first, and if it is
  disabled, find out *why* (a required field empty) instead of forcing a click.

## Verify with state, not with pixels

After a semantic click, prefer reading state back:

```powershell
# did the tab actually switch? read the selected tab's name, not a screenshot
(Find-UiElement -Window $w -Type 'TabItem').GetCurrentPattern(
  [System.Windows.Automation.SelectionItemPattern]::Pattern)
```

Falling order: state (pattern) → window title → artifact (file/new window) →
pixel diff (`Invoke-VerifiedClick`) → image.

## 经验库（自动维护）

`knowledge\lessons.md` 是本技能的经验条目（<=40 行，加载技能时一并读）。
判据：**换一个任务，这句话还用得上吗？** 工程参数、账号、一次性坐标不要写。

- 命中（按它做并且成功）：`lesson.ps1 hit  -Skill <本技能> -Key <key>`
- 矛盾（按它做失败）：`lesson.ps1 miss -Skill <本技能> -Key <key>`（连续 2 次降一级，降到 1 标 [REFUTED]，保留但不再采用）
- 新增：只在“同一坑踩两次 / 结果推翻假设 / 用户明确指教”时
  `lesson.ps1 add -Skill <本技能> -Key <域>.<主题> -Text "<一句话规则>" -Confidence 3-5`
