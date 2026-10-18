---
name: windows-gui-control
description: >
  Function reference for the bundled ui.ps1 / uia.py: which function to call for
  screenshot, single-window capture (PrintWindow, works while covered), UIA tree
  and semantic click, real mouse, clipboard typing, click verification — plus the
  hard rules and coordinate math they all depend on. Load this when you already
  know a GUI must be automated and need the exact signature, the decision ladder,
  or the pitfalls (window not foreground, DPI scale, minimized window, elevated
  window). For the general "look then act" strategy see windows-screen-automation;
  for typing see windows-input-bridge; for the control tree see
  windows-uia-inspector.
---

# Windows GUI control

Nothing to install for the core: it is `user32` + UI Automation called from
PowerShell. Optional extra: `pywinauto` (pip) for a friendlier control walker.

```
scripts/ui.ps1    screenshot, occluded-window capture, real mouse, UIA tree,
                  semantic find/click, click verification
scripts/uia.py    pywinauto bridge: windows / tree / find / click / text / value
```

## Load it (once per shell process)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\ui.ps1"
```

Both lines are mandatory in **every** fresh `pwsh` call: execution policy blocks
`.ps1`, and each tool call is a new process.

Then, before the first screenshot, pin the coordinate space:

```powershell
Set-DpiAware          # 150%-scaled displays otherwise report 1707x1067 while capturing 2560x1600
Get-ScreenInfo        # ImageW/ScreenW/ImageScale — the exact factor to apply to preview pixels
```

## Coordinate math that keeps failing

Three different sizes are in play and they get confused constantly:

| Thing | Typical value | Meaning |
|---|---|---|
| physical screen | 2560x1600 | what `Click(x,y)` and `SetCursorPos` take |
| what a DPI-unaware process reports | 1707x1067 | `Screen.PrimaryScreen.Bounds` before `Set-DpiAware` |
| the image the model sees | 1610x1006 | a *preview*: it was downscaled on the way in |

Rule: measure on the image you are looking at, then
`physical = preview_px * (ImageW / preview_px_wide)`. After `Set-DpiAware` the
capture is 1:1, so `ImageScale` is 1 and only the preview downscale remains.

## Decision ladder — always start at the top

Cheapest and most reliable first. Do not skip a rung because the next one is
more fun.

| # | Rung | Cost | Use when |
|---|---|---|---|
| 1 | **CLI / file / API** — `UV4.exe -b`, edit `.ioc` text, `git`, `curl` | ~0 | there is any non-GUI path at all |
| 2 | **UIA semantics** — `Get-UiNodes`, `Find-UiElement`, `uia.py` | small text | app exposes controls (Win32, MFC, WPF, Qt, Chromium) |
| 3 | **Window capture** — `Get-WindowCapture` (PrintWindow) | 0 tokens if you only diff it | window is covered; or you need to see one window, not the desktop |
| 4 | **Screen capture + look** — `Get-Screen` + `read_image` | ~1k tokens **per image** | UIA is empty or the state is visual |
| 5 | **Coordinate click + verify** — `Invoke-VerifiedClick` | 0 tokens | no clickable element, only pixels |

**A human at the keyboard changes the math.** Rung 5 stops being cheap: synthetic
clicks land on whatever window has focus this second, typed keys go nowhere, and
each retry costs 10–20 s. When somebody is actively using the machine, prefer
rung 1 even if it looks harder. On 2026-10-18 a repository that would not get
created through ~25 minutes of browser automation was created by one
`POST /user/repos` call — because the token was already sitting in the git
credential store. For any login or authorization screen, hunt for an existing
credential (`git credential fill`, `gh auth status`, env vars) before touching
the browser.

Two different things get confused here:

- **Screenshot for verification** is cheap: the image never enters the model.
  `Get-WindowCapture` + `Diff()` compares pixels inside the PowerShell process
  and returns a number (`Changed=True, Diff=37.4`).
- **Screenshot for looking** is expensive: every image you `read_image` costs
  context. Use it when the answer is genuinely visual (which tab is active,
  what a chart shows, is the label drawn correctly).

## Can you act without a screen? Yes — for some apps

UI Automation gives you, per control: `ControlType`, `Name`, `AutomationId`,
`IsEnabled`, `BoundingRectangle`, and for inputs also `ValuePattern` /
`TextPattern`. That is enough to *find and press a button with no pixels at all*
(covered window, off-screen monitor, headless-ish automation). `uia.py find`
prints exactly that as JSON.

What UIA does **not** give you, which is why rung 4 still exists:

- **Existence vs state.** UIA says a control exists; it does not say the app is
  mid-computation, which radio is visually highlighted, or that a custom-drawn
  progress ring is at 80%.
- **Virtualised lists.** A scrolled list only exposes the visible rows; rects of
  off-screen rows are wrong or missing.
- **Duplicate names.** Three `OK` buttons in one window are common; clicking the
  wrong one by name is silent damage.
- **Self-drawn UI.** Java/SWT (STM32CubeMX), Chromium `<canvas>`, games,
  DirectUI shell parts expose almost nothing. Measured here: CubeMX's UIA tree
  contained only 最小化 / 最大化 / 关闭.
- **Text inside custom controls** (data grids, terminal panels) is often not in
  the tree at all.

So: UIA for *locating and acting*, pixels for *proving and for blind apps*.

### Java apps: try Java Access Bridge before giving up

SWT/AWT apps can be exposed to UIA if Java Access Bridge is on:

```powershell
& "C:\path\to\jre\bin\jabswitch.exe" -enable   # then restart the app
```

If the app is a Java app and UIA shows nothing, this is the first thing to try;
it can turn a coordinate-clicking nightmare into normal semantic control.

## Functions

### Look

| Function | What it does |
|---|---|
| `Get-Screen -Path p.png` | Full virtual screen (multi-monitor) |
| `Get-ScreenRegion -X -Y -Width -Height -Path p.png` | One rectangle of the screen |
| `Get-WindowShot -Window $w -Path p.png` | Crop of the screen at the window rect — **shows whatever covers it** |
| `Get-WindowCapture -Window $w -Path p.png` | The window's own content via `PrintWindow(PW_RENDERFULLCONTENT)` — **works while covered** |
| `Test-Occluded -Window $w` | Compares the two: `{Occluded=$true; Diff=195.4}` proves it was covered |

`Get-WindowCapture` returns `{Status, Path, Minimized, Foreground, Left, Top,
Width, Height}`. A minimized window yields a 158x26 rectangle and no pixels, so
since 0.1.2 it **throws** (`cannot capture: TOOSMALL ... iconic=True`) instead of
handing back a `Path` that does not exist; `Focus-Window` first, or pass
`-NoThrow` to get the status object. The default `Path` includes the HWND
(`win_<hwnd>_capture.png`) so two windows never overwrite each other's file.

`Test-Occluded` writes `$env:TEMP\<Tag>_<random>_win.png` / `_screen.png` and
returns those exact paths — do not assume a fixed filename, read `.WindowPng`.

### Find and act

| Function | What it does |
|---|---|
| `Get-WindowList` / `Get-Window -Like` / `Get-Window -Hwnd n` / `Get-WindowByPid` | enumerate / match (rows from `Get-WindowList` are accepted anywhere a window is) |
| `Get-UiNodes -Window $w -Max 400` | every control with `Type/Name/AutomationId/Enabled/X/Y/Element` |
| `Get-UiTree -Window $w` | the same as printable indented text (paste into a report) |
| `Find-UiElement -Window $w -Name/-AutomationId/-Type` | first matching live element |
| `Invoke-ClickElement $el` | Invoke → SelectionItem → Toggle → coordinate fallback |
| `Invoke-ClickByNameVerified -Window $w -Name "OK"` | find + click + verify |
| `Invoke-VerifiedClick -Window $w -X -Y` | click, then poll pixels; returns `{Changed, Diff}` |
| `Invoke-ClickWindow $w -FX .5 -FY .5` | click a fraction of the window |
| `[Win32UI]::DblClick($x,$y)` / `::RightClick($x,$y)` | other buttons |
| `Send-Text "text"` | clipboard + Ctrl+V (survives a Chinese IME) |
| `Send-Key "^s"` | raw SendKeys |
| `Close-Dialogs -Names 'OK','Yes'` | press the first matching button in any window |
| `Focus-Window $w` | restore + foreground |

### pywinauto bridge

```powershell
python $env:USERPROFILE\.agents\skills\windows-gui-control\scripts\uia.py windows
python ...\uia.py tree  --title "STM32CubeMX" --depth 4          # observation only
python ...\uia.py tree  --title "..." --focus                    # opt in to focus
python ...\uia.py find  --title "Notepad" --name "保存"
python ...\uia.py click --title "Notepad" --auto-id 1234
python ...\uia.py value --title "..." --auto-id 5678
```

Exit codes: `0` ok, `2` window/control not found, `3` refused because the target
is not foreground (physical click), `4` refused because the target is minimized
or its rectangle is degenerate, `1` unexpected error. It prints JSON for `find`
(including the `patterns` the control actually supports and its `center`), so a
caller can act without pixels.

`tree` does **not** call `set_focus` by default — dumping a control tree is an
observation and used to yank the foreground away from whatever the user was
doing. Pass `--focus` when you actually want it raised.

`find` exits `4` instead of handing back nonsense coordinates:

```json
{"...": "...", "found": true,
 "unusable": "window is minimized (IsIconic); its coordinates do not exist - call focus/SW_RESTORE first"}
```

A minimized window reports a rectangle around `(-47940,-47940)`; clicking that
center sends the cursor into the void. The guard checks `IsIconic` first, then
whether the rectangle is collapsed (≤4 px) or entirely outside the virtual
screen, and `click` applies the same check before touching anything.

`click` is **semantic first**: it tries Invoke → Select → Toggle and only falls
back to a physical click when the element supports none of them. A physical
click is refused with exit code 3 unless the target window is foreground —
otherwise the click lands on whatever is on top of it:

```json
{"clicked": false, "refused": "target window is not foreground; ...", "hint": "call `python uia.py focus` ...", "foreground_before": false}
```

On success the JSON reports both `foreground_before` and `foreground_after`, so
you can tell "clicked while already on top" from "raised it first".

Reproducing the refusal without touching the user's screen: launch the same
throw-away window **twice**; the second one is foreground, so target the first
one by `--handle` (take it from `uia.py windows`, pick the handle that is not
`GetForegroundWindow()`). That yields exit 3 deterministically.

Pass `--force` only when you have checked the stacking yourself.
`value --auto-id LBL` reads a Label's text; `value --name "OK"` matches the
visible text, which is not the same thing (`--name` looks at window text).

## Hard rules (each one cost something to learn)

- **Match the window by PID of the process you started**, never by title alone
  when *acting*. A loose `Get-Window 'Notepad'` once grabbed the user's open
  document, pasted into it, and a `Stop-Process -Force` by name closed it.
  Title matching is for *reading*; PID is for *acting*.
- **Never `Stop-Process -Name <app>`** — only `Stop-Process -Id $app.Pid`.
- **Chinese IME eats raw keystrokes** (`SendKeys "hello"` → `hello- typed不用按…`).
  Always `Send-Text`.
- **Screenshot before and after every click**, and verify by effect. `Changed=False`
  means the click missed — do not click again blindly, re-shoot and re-decide.
- **Re-shoot before every coordinate click.** Window moved, DPI 125 %, second
  monitor, or the app re-laid out after a dialog closed: all shift pixels.
- **Preview coordinates are not screen coordinates.** A 2560×1600 screen shown
  as a 1610×1006 preview needs ×1.59. Compute the scale from
  `image width / window width` and write it down, or you will click ~60 % off.
- **Ask before anything destructive**: 删除 / 覆盖 / 提交 / 付款 / 格式化 / 发送 /
  uninstall / erase. Screenshot it, name what will happen, wait for a yes.
- **Never leave the user's other windows disturbed.** Restore minimised windows
  you opened, do not resize their layout, do not leave the cursor parked on a
  button.
- **A launched PID often owns no window.** Measured: `Start-Process notepad`
  returned PID 38276 while the visible Notepad window belonged to an older
  process (Windows 11 packaged apps reuse the instance), and a `cmd.exe` window
  belongs to `WindowsTerminal.exe`. `Get-WindowByPid` is then legitimately empty
  — don't "fix" it by clicking a title you guessed; give the app a unique title
  (`cmd /k title MYRUN`), then `Get-Window -Like 'MYRUN'`, or launch an app you
  control and read back an artifact.
- **Window titles carry trailing spaces.** `title SMOKEWIN` yields `"SMOKEWIN "`
  (length 9), so `-Like '^SMOKEWIN$'` finds nothing while `-Like 'SMOKEWIN'`
  works. Never anchor a title regex with `$`.
- **`Get-Window -Like` takes wildcards, not raw regex.** It already bit once:
  `-Like '*Device Activation*'` was passed straight into `-match`, threw
  `The following error occurred: quantifier {x,y} following nothing`, and a retry
  loop turned that into 17.6k tokens of the same exception. Wildcards are now
  translated; use `-Regex` only when you really mean regex.
- **A DPI-unaware process misreports the screen.** Same machine reported
  1707x1067 and captured 2560x1600 in alternating calls, so a coordinate that
  worked one minute earlier missed the next. `Set-DpiAware` first, always.
- **Chromium/Electron page content is not in the UIA tree.** A full browser page
  exposes ~38 elements: window frame, tab strip, address bar, buttons — no DOM.
  Everything inside the viewport needs pixels or DevTools, not UIA.
- **Java/SWT apps expose only the window frame** too (CubeMX: 最小化 / 最大化 /
  关闭 and nothing else). Do not spend calls hunting for controls; go to pixels.
- **`PrintWindow` can return black or stale** frames for GPU-composited windows.
  Check the result (mean brightness, diff against screen); when it fails, fall
  back to `BitBlt` from the window DC, then to a plain screen grab.
- **After clicking in a browser, wait 1–4 s before judging.** DOM updates are
  async; a screenshot taken too early shows the old page and looks like a miss.
- **Elevated (UAC) windows are invisible to you.** A non-elevated process cannot
  send input to, or read the UIA tree of, a window running as administrator
  (UIPI). Symptom: the window is in `Get-WindowList`, `Invoke-ClickElement`
  silently does nothing, `uia.py` prints `CONTROL NOT FOUND`. Do not retry —
  ask the user to close it, or that one action needs their hand.
- **Screenshots are other people's private data.** Capture a single window
  (`Get-WindowCapture`) rather than the whole desktop, and do not read windows
  that are not part of the task (chat, mail, password managers). If a private
  window happens to be in a full-screen shot, do not quote or describe it.
- **Keep `ui.ps1` and any code you paste into a `pwsh` call ASCII-only.** Windows
  PowerShell 5.1 decodes `.ps1` as ANSI and command text as ANSI too: a Chinese
  character inside a here-string or a `Replace` argument once produced
  `字符串缺少终止符` / `UnexpectedToken` and a corrupted file. CJK belongs in
  arguments, JSON payloads and skill docs — never hard-coded into the script.

## Recipes

### Read a Java app's dialog text (no OCR)

```powershell
$w = Get-Window -Like 'STM32CubeMX'
Get-UiText $w            # usually empty for SWT - that is data, not a bug
Get-WindowCapture -Window $w -Path 'C:\tmp\cmx.png' | Format-List
```

### Click a button and prove it worked

```powershell
$w = Get-Window -Like 'STM32CubeMX'
$el = Find-UiElement -Window $w -Name 'GENERATE CODE'
if ($el) { (Invoke-ClickByNameVerified -Window $w -Name 'GENERATE CODE') | Format-List }
else { $r = Invoke-VerifiedClick -Window $w -X 1858 -Y 304; $r }
```

### Work on an app that is completely covered

```powershell
$w = Get-Window -Like '图片查看器'
(Test-Occluded -Window $w) | Format-List     # Occluded=True, Diff=195 -> covered
Get-WindowCapture -Window $w -Path 'C:\tmp\behind.png'   # real content anyway
```

### Clear a blocking popup

```powershell
Get-WindowList | Where-Object { $_.Name -match 'CubeMX|Warning|Info' }
Close-Dialogs -Names 'OK','Yes','Continue','确定','是'
```

## Boundaries

- Needs an interactive desktop session (the one the user is looking at); it moves
  the real cursor, so warn them if they are typing.
- Minimized windows cannot be captured or clicked — restore first.
- A covered window can be captured, but a window on **another virtual desktop**
  cannot; switch desktops first.
- Some `PrintWindow` targets render black for GPU-composited surfaces (some
  Electron games, hardware-overlay video). Detect it with `Test-Occluded`
  reporting `Diff≈0` while the window is obviously covered, then fall back to
  rung 4 after bringing the window forward.
- PowerShell 5.1 reads `.ps1` files as ANSI: keep `ui.ps1` **ASCII-only**.
  Passing CJK button names as arguments is fine; hard-coding them is not.
