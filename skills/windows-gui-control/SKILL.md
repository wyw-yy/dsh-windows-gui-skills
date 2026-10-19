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

## Read this first (three things that cost a whole session each)

1. **Decision ladder, in one line per rung** — full version at
   [Decision ladder](#decision-ladder--always-start-at-the-top):
   CLI/file → UIA semantic → window capture (PrintWindow) → full-screen image →
   coordinate click with verification. Start at the top; only fall through when
   the rung above genuinely cannot express the action.
2. **Sandbox beats you silently.** A desktop program that writes under
   `%USERPROFILE%` (CubeMX, IDE caches, plugin loaders) cannot start under
   `workspace-write`: it exits in seconds, writes nothing, and reports nothing.
   Symptom: log file mtime does not move, no new process. Fix: get write access
   to the home directory (ask the user), then run once — do not retry.
3. **A GUI started by `pwsh` dies when that call returns.** `Start-Process` alone
   is not enough if the parent shell is torn down with the tool call. Keep it
   alive deliberately: launch it inside a background job, or a detached
   `Start-Process` whose own process tree you then re-discover by PID before
   each action. Re-query windows every time — handles are rebuilt on navigation.

**Use the installed scripts only.** Load
`$env:USERPROFILE\.agents\skills\windows-gui-control\scripts\ui.ps1` (30+
functions). A workspace `tools\ui.ps1` is a stale copy — it may be missing
`Get-WindowCapture`, `Invoke-VerifiedClick`, `Set-DpiAware`, `Test-Occluded`, and
you will not notice until the one thing you need is absent.

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

**Tested negative on STM32CubeMX 6.16.1** (2026-10-18): `jabswitch -enable`
reported success, `javaaccessbridge.dll` + `windowsaccessbridge-64.dll` are
present in the bundled JRE, the app was relaunched — and the UIA tree still
contained exactly six nodes (TitleBar, system menu, 最小化/最大化/关闭), with no
"GENERATE CODE" or any other business control. So:
`jabswitch` is worth one 30-second try, not worth a second attempt. Disable it
again (`-disable`) if it changed nothing, and fall back to window capture +
coordinates. CubeMX draws its canvas itself; there is no accessibility tree to
find.

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

## Locating things when coordinates are not enough

Fixed screen coordinates break the moment a window moves, the DPI changes, or
the user drags the mouse. Use pixels instead of remembered numbers.

### Template match: find a widget by what it looks like

```powershell
# 1) crop the widget once (from any screenshot that shows it)
$tpl = Save-ImageCrop -Source $shot -X $rect[0] -Y $rect[1] -Width $w -Height $h -Path "$env:TEMP\btn.png"
# 2) find it again in a brand-new screenshot
$hit = Find-ImageOnScreen -Template $tpl -Tolerance 10
$hit.Found; $hit.CenterX; $hit.CenterY; $hit.Score
# 3) click it and prove the screen changed
$r = Invoke-ClickTemplate -Template $tpl -Tolerance 10
$r.Changed; $r.Ratio
```

Measured 2026-10-18 (2560x1600 @150%): a 210x35 button crop was located with
`score=0` **after the window had been moved by SetWindowPos**, the click landed,
and the app's own label changed to `pong-211045`. That is the difference between
"click at 450,398 and hope" and "click whatever currently looks like the button".

Rules:

- `Score <= 10` means "same widget"; `> 20` means you found a look-alike.
- A nearly uniform crop returns `FLAT` and is rejected on purpose — a blank patch
  scores 0 against any other blank patch.
- Crop from the same DPI/scale you will search at. Cross-DPI matching works but
  the score degrades; re-crop instead of lowering the tolerance.

### Burst + diff: catch UI that only exists for a moment

Hover flyouts, tooltips, submenus and "appears only while the mouse is near"
panels vanish between two model turns. Capture a burst and diff it in-process:

```powershell
$b = Get-ScreenBurst -Count 6 -IntervalMs 120
$d = Get-ChangedRegion -A $b.Files[0] -B $b.Files[5]   # cluster-aware bbox
$d.Status; $d.Left; $d.Top; $d.Width; $d.Height; $d.Cells
```

The diff is cluster-aware: cells of 24x24 px need >=24 changed pixels, and only
the **largest 8-connected cluster** is reported. Without that, a blinking clock in
the corner stretched the bounding box across the whole screen (observed: bbox
`(24,72)-(1343,1319)` for a 0.1% pixel change). With it, the same desktop produced
`(816,1200)-(1419,1247)` — exactly the status text that was animating.

Related helpers:

| Function | Use |
|---|---|
| `Get-ScreenBurst -Count N -IntervalMs M` | N shots in one call; nothing can vanish in between |
| `Get-ChangedRegion -A -B [-Raw]` | where two frames differ (cluster bbox + ratio) |
| `Get-ChangeMask -A -B` | writes a black/white mask image, so you can *look* at the diff |
| `Test-HoverPopup -X -Y` | hover, capture, move away, capture; bbox = the hover-only UI |
| `Find-ImageOnScreen -Template` | locate a crop anywhere on screen |
| `Invoke-ClickTemplate -Template` | locate + click + verify in one call |

Cost: a burst is 5-6 captures of disk I/O and ~0 model tokens; only the frames you
actually `read_image` cost context. Diff and match run in C# inside the script.

### Hover-only UI that lives ~1 s (flyouts, thumbnails, tooltips)

A model round trip is 5-15 s; the flyout is gone in ~1 s. You cannot "click, look,
then click again". Capture **inside** its lifetime, from one process call:

```powershell
$r = Capture-HoverFlyout -X 570 -Y 474 -Frames 18 -IntervalMs 60
$r.BestRatio; $r.Status; $r.Left; $r.Top; $r.Width; $r.Height; $r.BestFrame
```

What it does, in this order, without returning to the model:

1. parks the cursor on the target and never moves it again (leaving = instant dismiss);
2. burst-captures 16-18 frames at 60-70 ms, i.e. while the flyout still exists;
3. diffs every frame against frame 0, keeps the richest frame, and reports the
   changed bbox (cluster pass, so a blinking clock does not swallow the screen);
4. snapshots top-level windows that appeared during the burst and PrintWindow-captures
   them - a fading tooltip still renders into its own HWND after it leaves the screen;
5. parks the cursor at (4,4) so the pointer is not left hovering a live control.

Measured 2026-10-18: hovering a WinForms button captured the tooltip text
`FORM-MARKER` at bbox `552,480 168x72` - a window that exists only while the pointer
is on the button. Same call, no extra tokens.

Rules that make or break it:

- **Verify the hover target first** (UIA rect or `Find-ImageOnScreen`). If the pointer
  lands 3 px off, you get no flyout and the diff reports whatever else moves on
  screen (measured: a spinner 300 px away became the bbox).
- If you must *act* on the flyout, do the click in the same call, right after the
  burst - not in the next turn.
- Prefer a path that does not need the flyout at all: keyboard (Tab/arrow), the
  window's UIA tree while it is open, or a persistent panel instead of a hover panel.


### Learned flyout knowledge + the correction rule

Bursting every time is wasteful. The skill keeps a per-machine knowledge base at
`%USERPROFILE%\.agents\skills\windows-gui-control\data\flyouts.json`:

```json
{ "version": 1, "entries": [ {
  "key": "hovertest:btn",
  "trigger": { "x": 570, "y": 474 },
  "region": { "Left": 570, "Top": 500, "Width": 147, "Height": 32, "Class": "tooltips_class32", "Source": "window" },
  "confidence": 4, "attempts": 6, "firstSeen": "...", "lastSeen": "...",
  "lastVerdict": "MATCH", "observations": [ ... ], "disagreements": [ ... ] } ] }
```

Use it instead of a bare burst:

```powershell
$r = Invoke-Flyout -Name 'qq:searchPanel' -TriggerX 2218 -TriggerY 183 -Attempts 3
$r.Verdicts; $r.Final; $r.Confidence; $r.Unstable; $r.Region
```

- **confidence >= 2** -> fast path: 6 frames instead of 12-18, and the stored
  trigger is used when you pass no coordinates.
- Every run still verifies, and classifies what happened:

| verdict | meaning | effect |
|---|---|---|
| `MATCH` | IoU >= 0.6 with the stored region | confidence +1, region refreshed |
| `MOVED` | same size band, different place | region/trigger updated, confidence kept |
| `GONE` | nothing appeared for every attempt | confidence -1 |
| `DIFFERENT_UI` | a window appeared but class/size differ | kept, entry flagged unstable |

- **Correction rule (this is the point):** the function runs up to `-Attempts`
  passes and only calls it `Agreed` when the passes agree. Any mix of
  found/not-found or a class change sets `Unstable = $true` and appends the whole
  verdict list to `disagreements[]` in the JSON. A single disagreement never
  rewrites the entry - it takes repeated samples, which is what "check again
  before believing it" means in practice.

- **When the entry is written (the gate).** A lesson can only be rewritten after
  the evidence repeats, otherwise one fluke becomes permanent:

| verdict | writes to the entry? |
|---|---|
| `LEARNED` (no entry yet) | yes, creates it with confidence 1 |
| `MATCH` | always - refresh region and trigger, confidence +1 |
| `MOVED` | only after **two consecutive identical** verdicts |
| `DIFFERENT_UI` | only after **two consecutive identical** verdicts |
| `GONE` | never rewrites the region; costs confidence -1 **once per invocation**, not once per attempt |

  `GONE` deserves the emphasis: with `-Attempts 3` a failing lookup used to lose
  3 confidence points in one call and wipe a good entry. The gate now spends at
  most one point per run, and a `hit`-worthy `MATCH` on the next run earns it back.

Why windows beat pixels here: a full-screen diff is dominated by blinking carets
and animated text. Measured on a real tooltip: the pixel pass produced a 24x24
false bbox while the window pass returned the tooltip itself
(`tooltips_class32`, 147x32). Identity therefore comes from the new top-level
window (class + rect, filtered to < 900x700 and near the trigger); pixels are the
fallback only.

Measured cycle (same machine, 2026-10-18): learn -> `MATCH` conf 2; window moved
200,150 with the old trigger -> `GONE` conf 0; new trigger -> `MATCH` conf 1 with
the region following to `770,650`; app closed -> `GONE` conf 0, stable.

## 经验库（自动维护）

`knowledge\lessons.md` 是本技能的经验条目（<=40 行，加载技能时一并读）。
判据：**换一个任务，这句话还用得上吗？** 工程参数、账号、一次性坐标不要写。

- 命中（按它做并且成功）：`lesson.ps1 hit  -Skill <本技能> -Key <key>`
- 矛盾（按它做失败）：`lesson.ps1 miss -Skill <本技能> -Key <key>`（连续 2 次降一级，降到 1 标 [REFUTED]，保留但不再采用）
- 新增：只在“同一坑踩两次 / 结果推翻假设 / 用户明确指教”时
  `lesson.ps1 add -Skill <本技能> -Key <域>.<主题> -Text "<一句话规则>" -Confidence 3-5`
