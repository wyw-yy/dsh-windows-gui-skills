# Changelog

All notable changes to this skill package. Newest first.

## 0.2.1 - 2026-10-19

Round-3 review fixes (`REVIEW-NOTES-3.md`, deepPCB workspace).

- `install.ps1`: added `param([string]$Dest, [string]$Source)`.
  - `-Dest` installs into a scratch folder instead of `%USERPROFILE%\.agents\skills`
    (the reviewer could not try an install without overwriting the real one).
  - `-Source <dir>` installs from a local `skills\` tree instead of downloading
    main.zip, so the package can be tested before it is pushed.
- `lesson.ps1`: the downgrade rule now matches the documentation. It was
  `misses - hits >= 2` (cumulative difference); it is now **two consecutive
  misses** (`consecutive_misses` on the entry, reset by `hit` and by `add`).
  The old rule could demote an entry that had been right ten times; the docs
  and the 0.2.0 changelog both promised "连续 2 次".
- `windows-gui-control/SKILL.md`: documented the `flyouts.ps1` write gate
  (LEARNED once / MATCH every run / MOVED and DIFFERENT_UI need two consecutive
  identical verdicts / GONE costs at most -1 per invocation) - it was only in
  the source before.
- `tools/check_fm.py`: `--root <dir>` so it can validate the shipped package,
  not just the installed copy. Prints a per-file verdict and exits 1 on failure.
- `MANIFEST.txt` is now generated with line endings normalised to LF before
  hashing, and `tools/verify_manifest.ps1` does the same when it checks, so a
  CRLF checkout no longer reports a false mismatch.
- `CHANGELOG.md`: the 0.1.0-0.1.3 sections were double-encoded mojibake with
  replacement characters (information was already lost). They are rewritten
  from the git log and the corresponding review notes; the sections now carry
  a `[reconstructed]` marker. The file also had `# Changelog` in the middle and
  reverse ordering - fixed.
- `references/app-ui-notes.md` was listed as `eferences/...` in 0.1.8 - fixed.

## 0.2.0 - 2026-10-19

- Every skill gained a `knowledge/` experience base: `lessons.md` (generated,
  <= 40 lines) and `ledger.json` (counters plus evidence).
- New `scripts/lesson.ps1`: `add` / `hit` / `miss` / `list` / `prune`.
  A hit raises confidence every 3 uses, two consecutive misses lower it by 1,
  confidence 1 marks the entry `[REFUTED]`, and above 40 entries the lowest
  confidence / oldest / least-hit are pruned.
- First 20 lessons seeded (`gui.*` / `screen.*` / `uia.*` / `input.*` / `embed.*`).

## 0.1.8 - 2026-10-18

- `references/app-ui-notes.md`: added the measured QQ NT section - main panel toggle is
  Ctrl+Alt+Z (not a click), the panel layout in window-relative coordinates, and the
  toolbar-row trap that opened a payment dialog when the input area was clicked.
- Same file: corrected the uVision numbers after the failed click sweep (menu row y=50,
  toolbars y=88 / y=122) and added the "hover first, never blind-click" rule.

## 0.1.7 - 2026-10-18

- NEW `scripts/flyouts.ps1` (auto-loaded by ui.ps1): learned knowledge base for
  transient UI, plus a correction rule.
  - `Get-TransientRegion`: passive burst (no cursor move) - UI that appears and
    leaves on its own inside the burst.
  - `Invoke-Flyout`: fast path once confidence >= 2 (6 frames, stored trigger),
    verification on every run, verdicts MATCH / MOVED / GONE / DIFFERENT_UI.
  - Disagreement between attempts sets Unstable and is recorded in
    `disagreements[]` instead of silently overwriting the entry.
  - KB at `%USERPROFILE%\.agents\skills\windows-gui-control\data\flyouts.json`.
- `Capture-HoverFlyout` rewritten: baseline is taken BEFORE hovering (frame 0 used
  to already contain the flyout, so the diff said "nothing changed"); pixels are
  compared only inside `-Radius` of the cursor; new top-level windows are captured
  with PrintWindow and carry class + rect.
- `Get-WindowCapture` no longer rejects small windows (a 147x32 tooltip is legit);
  only iconic windows and < 8 px are refused.

## 0.1.6 - 2026-10-18

- NEW `Capture-HoverFlyout`: capture UI that only exists while the pointer hovers it
  (flyout, taskbar thumbnail, tooltip). Parks the cursor, bursts 16-18 frames at
  60-70 ms inside the ~1 s lifetime, keeps the richest frame, reports the cluster
  bbox, and PrintWindow-captures any top-level window that appeared during the burst.
  Verified by capturing a WinForms tooltip (`FORM-MARKER`, bbox 552,480 168x72) that
  exists only during hover.

## 0.1.5 - 2026-10-18

Self-review of 0.1.4, found and fixed six issues:

- `Get-ChangeMask` used per-pixel GetPixel (2560x1600 took ~10 s). Rewritten as
  `PixelMask.Write` with LockBits + Marshal.Copy: **136 ms** (73x).
  (`unsafe` cannot be used: Add-Type compiles without `/unsafe`.)
- `Invoke-ClickTemplate` returned two different shapes; on "not found" it had no
  `.Changed`, so callers silently read `$null`. Now one shape, always with
  `Clicked` / `Found` / `Reason` / `Changed` / `Ratio` / `RawRatio`.
- `Test-HoverPopup` parked the pointer at (X-600, Y-600), which can land on
  another widget and raise ITS tooltip -> wrong bbox. Now parks at (4,4) and
  restores the original cursor position afterwards.
- `Save-ImageCrop` had no bounds check (GDI threw a cryptic error); now throws
  with the rect and the image size.
- A checkbox tick changes too few pixels for the 24-px-cell cluster pass, so a
  real click could report `Changed=false`. Added a raw-ratio fallback
  (`RawRatio >= 0.00005`).
- `Win32UI` had no `GetCursorPos`, which `Test-HoverPopup` needs. Added.

Verified: mask 136 ms; template click on a live WinForms button ->
found/clicked/changed true and the app's own label went `idle` -> `pong-211549`;
self-match on an identical screenshot scores 0 at the exact position.

## 0.1.4 - 2026-10-18

- NEW `scripts/pixelscan.ps1` (auto-loaded by ui.ps1): pixel localization that
  survives window moves and mouse interference.
  - `Get-ScreenBurst` / `Get-ChangedRegion` / `Get-ChangeMask`: burst capture plus
    cluster-aware diff (largest 8-connected cluster of changed 24px cells).
  - `Find-ImageOnScreen` / `Invoke-ClickTemplate` / `Save-ImageCrop`: template match
    (coarse step 4, then +-8 px refine) with a flat-template guard, plus verified click.
  - `Test-HoverPopup`: diff "pointer on target" vs "pointer away" to find flyouts.
- `ui.ps1` now calls `Set-DpiAware` when dot-sourced, so `Click(x,y)` is physical
  pixels on every display scale (previously only `Get-ScreenInfo` was aware).

## 0.1.3 - 2026-10-18 [reconstructed]

Original text was lost to double-encoding; rebuilt from the git log and
`REVIEW-NOTES-2.md`.

- `uia.py click --input`: the ambiguous `foreground` field became
  `foreground_before` + `foreground_after`, so a refusal also states that the
  window was already in the background.
- `tree` no longer steals focus by default; `--focus` is opt-in.
  Verified with two windows: `GetForegroundWindow()` is unchanged before/after.
- Minimized / degenerate-coordinate guard: new `is_minimized()`, `rect_bogus()`,
  `bogus_reason()`. `find` stops returning coordinates like `(-47940,-47940)` and
  exits **4** with an `unusable` reason; `click` runs the same check first
  (`--force` overrides).
- DPI consistency: `main()` calls `SetProcessDpiAwareness(2)` at startup so
  pywinauto's physical rects and `GetSystemMetrics` stop disagreeing at 150%.
- Docs: exit codes 0/2/3/4, `--focus`, and a reproducible recipe for the refusal
  path (open the same test window twice, point `--handle` at the background one).
- `jabswitch` result: no effect on STM32CubeMX 6.16.1 - `-enable` succeeds and the
  JRE ships `javaaccessbridge.dll` / `windowsaccessbridge-64.dll`, but after an
  app restart the UIA tree still has only 6 window-decoration nodes and no
  `GENERATE CODE`. Both skills now say "try once, not twice".

## 0.1.2 - 2026-10-18 [reconstructed]

Original text was lost to double-encoding; rebuilt from the git log and
`REVIEW-NOTES-2026-10-18.md`.

- **P0 `uia.py` crash**: `control_of()` no longer calls `child_window()` on a
  `UIAWrapper` (every `find` / `click` died with
  `'UIAWrapper' object has no attribute 'child_window'`); it walks ancestors and
  matches, and `tree` indents by real depth.
- **P1 physical click could hit another window**: `uia.py click --input` refuses
  when the target is not foreground, exits 3, and explains; `--force` only after
  the layering is confirmed.
- **P1 HAL behaviour documented wrong**: `stm32f4-bringup` section 3b now says
  HAL does not validate PLL frequencies; `HAL_RCC_OscConfig` returns
  `HAL_TIMEOUT` after waiting for `PLLRDY`
  (`stm32f4xx_hal_rcc.c:487`, not `HAL_ERROR`), plus the
  `HCLK=168000000` cross-model trap in `.ioc`.
- **P2 locator API**: `Get-Window -Like` really is wildcard-based (`-Regex`
  switches to regex), added `Get-Window -Hwnd` and the `-Pattern` / `-Title`
  aliases; `Assert-Window` accepts HWND, IntPtr and `Get-WindowList` rows, and
  says what it expected.
- **P2 capture contract**: `Get-WindowCapture` throws for a minimized window
  (`-NoThrow` returns the status instead), default filenames carry the HWND, and
  `Test-Occluded` uses random names and returns the real `WindowPng` / `ScreenPng`.
- **P2 hard rules**: elevated (UAC) windows are unreachable through UIPI, screenshots
  are privacy-sensitive, keep the scripts ASCII.
- **Description de-duplication**: `windows-gui-control` became "function reference"
  and `windows-screen-automation` owns the entry trigger, so the four skills no
  longer overlap.

## 0.1.0 - 2026-10-18 [reconstructed]

Original text was lost to double-encoding; rebuilt from the git log.

- First release: four skills packaged from tasks that were verified end to end.
  - `windows-gui-control`: `ui.ps1` (~19 KB, 25 functions) + `uia.py` (pywinauto bridge).
  - `windows-screen-automation`: look -> click -> verify loop,
    `Get-WindowCapture` occlusion capture, pixel-diff thresholds.
  - `windows-uia-inspector`: UIA tree dump, locator priority, Java/SWT empty trees.
  - `windows-input-bridge`: clipboard typing, chords, focus/timing, console quirks.
- Scenarios verified: STM32CubeMX (Java/SWT, no control tree) - `GENERATE CODE`
  and the clock-solver dialog; Keil uVision beyond `UV4.exe -b/-f`;
  Notepad / Explorer / cmd - real mouse click + clipboard typing + capture replay.
- Known issues at the time: minimized windows cannot be captured (the rect
  degenerates to 158x26); a launcher PID is not the window PID (Win11 packaged
  apps reuse instances), so `Get-WindowByPid` can return `$null` - `Assert-Window`
  now fails loudly.
