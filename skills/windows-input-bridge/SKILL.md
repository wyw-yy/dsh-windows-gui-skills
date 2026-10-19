---
name: windows-input-bridge
description: >
  Get text and keystrokes into a Windows app reliably: clipboard paste instead of
  raw SendKeys (so a Chinese IME cannot mangle it), hotkey chords, the three mouse
  buttons, double-click, focus and restore rules, and the timing that separates a
  working automation from one that types into the wrong window. Use when typing
  into a field, sending Ctrl+S / Enter / Tab sequences, when typed text comes out
  garbled or with IME artifacts, when a click works only the first time, or when
  an app ignores input because it never got focus.
---

# Input bridge: text, keys, mouse, focus

The input layer looks trivial and is where most automation silently corrupts
things. Rules here are ordered by how much damage ignoring them has caused.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\ui.ps1"
```

## Text: always through the clipboard

```powershell
Send-Text "C:\work\proj\MX_PA11_LED"     # Set-Clipboard + Ctrl+V
```

Why not `SendKeys "text"`:

- A Chinese IME swallows or reorders ASCII keystrokes — measured output of
  `SendKeys "hello"` was `hello- typed不用按AI阿根廷through啊realmouseclick。`
- `+ ^ % ~ ( ) { }` are SendKeys metacharacters; paths and code break on them.
- Long strings drop characters when the target is slow.

`Send-Text` is atomic, survives any IME state, and handles arbitrary Unicode. It
does clobber the user's clipboard — restore it if the run matters, or tell them.

For fields that replace-on-type vs append, select first:

```powershell
[Win32UI]::Click($x, $y)
[System.Windows.Forms.SendKeys]::SendWait("^a")
Send-Text "336"
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
```

## Keys: only for navigation and chords

```powershell
Send-Key "^s"          # Ctrl+S
Send-Key "{ENTER}"
Send-Key "{TAB}{TAB}{SPACE}"
Send-Key "{ESC}"
```

Keep them ASCII control names; for anything with text in it, use `Send-Text`.
`Send-Key` goes to whatever has focus *now* — verify focus first (below).

## Mouse

```powershell
[Win32UI]::Click($x, $y)          # left, physical screen pixels
[Win32UI]::DblClick($x, $y)       # two clicks 60 ms apart
[Win32UI]::RightClick($x, $y)
Invoke-ClickWindow $w -FX 0.5 -FY 0.5      # centre, fraction of window
```

- Coordinates are **physical pixels**, origin at the virtual screen's top-left.
  Preview images are downscaled — compute the scale, never assume 1.0.
- The real cursor moves. If the user is typing, warn them first; you are taking
  their mouse.
- Some controls need `MouseDown`+`MouseUp` with a delay (custom drag targets) —
  plain `Click` is too fast for those; add a 80 ms gap between the two events.
- After a click that opens a menu, screenshot before the next click: menus close
  on any stray click and you will act on the wrong window.

## Focus: the thing that decides where input lands

```powershell
Focus-Window $w                       # ShowWindow(SW_RESTORE) + SetForegroundWindow
[Win32UI]::GetForegroundWindow()      # verify, don't assume
```

- `Focus-Window` restores a minimized window; you cannot capture or click a
  minimized one (`Status=TOOSMALL … iconic=True`).
- Windows blocks `SetForegroundWindow` from background processes in some cases.
  If focus did not take, retry once after a 200 ms sleep, or click the title bar
  once with `[Win32UI]::Click`, then proceed.
- **Never** act on a window identified only by title when several instances could
  match — hold the `Process` object you started and use `Get-WindowByPid`. A loose
  title match once grabbed the user's open document and a `Stop-Process -Name`
  closed it.
- Wait for the window to be *ready*, not just present: poll the title (an app
  showing "Untitled" for 6 s before loading a file will eat your first clicks).

## Timing

| Situation | Wait |
|---|---|
| after `Start-Process` | poll for window, then poll title until stable |
| after `Focus-Window` | 200–400 ms |
| after a click that opens a dialog | poll window list / `Wait-Window`, 2–8 s |
| after typing into a validated field | 150–300 ms before Tab/Enter |
| before re-clicking a failed target | re-screenshot first; no blind retry |

Polling beats sleeping: a fixed 5 s sleep is wrong on both a fast and a slow run,
and it still fails when the app takes 6 s.

## Consoles and terminals

The window you see for `cmd.exe` / `powershell.exe` belongs to
`WindowsTerminal.exe`, not to the shell process — so a PID handshake fails and a
pixel diff stays at 0 while text is being typed (the terminal renders text
outside PrintWindow's captured frame). Both facts make consoles the worst case
for "did my input land". Give the console a unique title
(`cmd /k title MYRUN`) so you can address it, and verify input by its effect:
`echo some-marker|clip` then read `Get-Clipboard`, or write a file and check it.

## UAC, elevation, and admin windows

A non-elevated automation cannot send input to an elevated window (UIPI). If
clicks on an admin prompt do nothing, the harness is not elevated — say so
instead of clicking harder. Device installers, driver tools, and some flashers
(CubeProgrammer) hit this.

## Text out

Don't scrape by OCR when a cheaper channel exists:

1. `Get-UiText` / `ValuePattern` — real text, exact.
2. Clipboard: `Send-Key "^a^c"` then `Get-Clipboard` — exact, works in most
   editors and terminals.
3. `Get-WindowCapture` + look — last resort, and it costs an image.

## Checklist before typing anything

- [ ] Window matched by PID, not by title.
- [ ] `Focus-Window` called and foreground verified.
- [ ] Target field selected (`^a`) or cursor placed by a verified click.
- [ ] `Send-Text`, not `SendKeys`, if the string contains non-ASCII or symbols.
- [ ] After the action: verify the field's value (UIA `Value` or a `^a^c` read),
      not just "the click seemed to work".

## 经验库（自动维护）

`knowledge\lessons.md` 是本技能的经验条目（<=40 行，加载技能时一并读）。
判据：**换一个任务，这句话还用得上吗？** 工程参数、账号、一次性坐标不要写。

- 命中（按它做并且成功）：`lesson.ps1 hit  -Skill <本技能> -Key <key>`
- 矛盾（按它做失败）：`lesson.ps1 miss -Skill <本技能> -Key <key>`（连续 2 次降一级，降到 1 标 [REFUTED]，保留但不再采用）
- 新增：只在“同一坑踩两次 / 结果推翻假设 / 用户明确指教”时
  `lesson.ps1 add -Skill <本技能> -Key <域>.<主题> -Text "<一句话规则>" -Confidence 3-5`
