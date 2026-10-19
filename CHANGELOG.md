# Changelog

All notable changes to this skill package. Newest first.

## 0.2.6 - 2026-10-19

Three small things that bite anyone who follows the docs literally.

- `lesson.ps1` now ships **inside every skill** (`skills\<name>\scripts\lesson.ps1`)
  instead of only under `windows-gui-control`. The five other skills told you to
  run `lesson.ps1 hit -Skill <this skill>` with no path, and the file was not
  there — a literal reader gets "not found". Each 经验库 block now also spells out
  the full path under `$env:USERPROFILE\.agents\skills\<skill>\scripts\`.
- The 经验库 block said lessons are read "together with the skill". They are not:
  the `skill` tool returns SKILL.md only. Reworded to "`skill` does not carry it —
  open `knowledge\lessons.md` with `read` before acting".
- `Get-Window` and `Get-WindowList` do **not** return the same shape:
  `Get-WindowList` rows have `.Handle/.Pid/.Name`; `Get-Window` returns an
  `AutomationElement` whose `.Handle` is empty — the HWND lives at
  `.Current.NativeWindowHandle`. Added a shape table plus the rule
  `$h = Get-Handle (Get-Window -Like '...')`. Measured: `.Handle` empty vs
  `.Current.NativeWindowHandle` = 2097762.

## 0.2.5 - 2026-10-19

The skills were right but never loaded, because `AGENTS.md` is injected every
turn and a skill catalog only shows a truncated description. So the three rules
that turn a session into a wasted one moved to the always-read file, and the two
remaining traps became one-line conclusions instead of table rows.

- Workspace `AGENTS.md` §四 now opens with the three "otherwise the day is gone"
  rules: sandbox silently kills CubeMX; a `pwsh`-launched GUI dies with the call;
  `ui.ps1` is only valid from the installed path (a workspace `tools\ui.ps1` is a
  10-function stale copy missing the verification functions).
- `stm32f4-bringup` §5 opens with the conclusion: under the desktop sandbox,
  CubeMX 6.16.1 executed nothing (no log lines, no `Bye bye`, `javaw` gone,
  launcher exit 0), one attempt ≈ 170 s, check home-directory write access before
  the first retry, never burn a third run. Also added the field note that
  aligning `MxCube.Version` with 6.16.1 can unstick a silent no-op, while bumping
  `MxDb.Version` by hand turns it into the `Mcu.getDie()` NPE.
- `windows-screen-automation` failure table: `Changed=False` + **title changed** +
  SWT window = the click worked; do not click a second time.

## 0.2.4 - 2026-10-19

Fixes from using the skills on a real CubeMX session that failed three times
(`F401_BUZZER`). The skills were correct but did not fire, and two gaps made a
recoverable mistake look like a hang.

- `stm32f4-bringup` description now carries the setup-side triggers that were
  missing — 用 CubeMX 新建工程 / 生成 Keil 工程 / 用 CubeMX + Keil 做个 xxx /
  .ioc 需要能生成代码 / 批处理卡住. Previously it only matched "the LED is
  dark", so a request to *create* a project never loaded it.
- `stm32f4-bringup` §5: the sandbox trap (no write access to
  `%USERPROFILE%\.stm32cubemx\` means `javaw` exits silently, the log mtime
  freezes, and the launcher's exit code is already 0) and the fact that CubeMX
  migration prompts are self-drawn Swing panels, not HWNDs.
- `windows-gui-control`: new "Read this first" block at the top — decision ladder
  in one line per rung (it used to sit 57 lines down), sandbox behaviour, GUI
  process lifetime, and the rule to load only the installed `ui.ps1`.
- `windows-screen-automation`: the same three environment traps, before the loop.
- `windows-uia-inspector`: SWT modals are often drawn inside the main window, so
  `EnumWindows`-based "wait for the dialog" always times out.
- `windows-input-bridge` + `ui.ps1`: `Get-UserIdleSeconds` (GetLastInputInfo).
  "Don't steal the input" now has a number — idle must exceed 2 s — instead of
  relying on good intentions.
- `clarify-before-act`: mid-task template for taking the screen, because asking
  only at task start does not cover the second and third focus steal.
- Four new lessons seeded: `gui.sandbox.silent`, `gui.process.lifecycle`,
  `gui.local.copy.drift`, `embed.cubemx.byebye`.

## 0.2.3 - 2026-10-19

Round-5 review fixes (`REVIEW-NOTES-5.md`).

- `skills/clarify-before-act/data/clarify-log.json` no longer ships. It held
  this machine's real records ("send button at 1340,916", outcome `wrong`), so
  a fresh install copied them into someone else's profile. The file is now
  untracked, deleted from the repo tree and gitignored; `clarify.ps1` recreates
  it as `[]` on first use.
- `skills/clarify-before-act/references/clarify-knowledge.md` replaces
  `data/clarify-knowledge.md`: curated advice ships, `data\` is per-machine
  state only, so `install.ps1` carrying `data\` over can no longer freeze an
  old knowledge file in place.
- `.npmignore`: `files` in package.json whitelists the whole `skills/`
  directory and npm applies neither `.gitignore` nor file-level `.npmignore`
  rules on top of it, so per-machine `data/` folders are excluded as whole
  directories. Without this, `npm pack` still shipped the log.
- `install.ps1`: only genuinely per-machine paths survive an upgrade -
  `data\` + `knowledge\` for `windows-gui-control`, `knowledge\` for the rest,
  `data\clarify-log.json` for `clarify-before-act`. The whole `data\` folder
  used to be copied over every time.
- `install.ps1`: the staging `.new-*` folder and the `.bak-*` backup are now
  removed in a per-skill `finally`, not only on the happy path; a backup that
  cannot be deleted is reported instead of silently leaking.
- `install.ps1`: `-Source` and the downloaded archive are checked against the
  package's own `MANIFEST.txt` before anything is installed.
- `tools/manifest.ps1`: repo-only patterns are `NOTE*.md`, `REVIEW-NOTES*.md`,
  `REVIEW-RESPONSE*.md`, `REVIEW-REQUEST*.md`, so a bare `REVIEW-REQUEST.md` is
  excluded the same way `REVIEW-REQUEST-3.md` already was; `.npmignore` is
  excluded too. MANIFEST is 26 files.
- `lib/index.js`: `SKILL_NAMES` and the module comment list six skills -
  `clarify-before-act` was missing.
- `README.md`: six skills (heading, install note, table row for
  `clarify-before-act`), and the npm-pack example uses the current version.
- `BOOT.md`: the workspace copy that `@BOOT.md` actually reads still carried
  the "actual 15 skills" sentence; it now matches the package copy
  (`B17C95C7...`, byte-identical).

## 0.2.2 - 2026-10-19

Round-4 review fixes (`REVIEW-NOTES-4.md`).

- `tools/manifest.ps1`: `-AllowExtra` no longer downgrades a missing file. A file
  listed in MANIFEST.txt but absent on disk is always `FILE GONE` + exit 1; the
  switch only excuses files that are present but not listed (NOTE.md, review
  notes). Regression test: delete `skills\windows-input-bridge\SKILL.md` ->
  `FILE GONE`, exit 1, even with `-AllowExtra`.
- `tools/manifest.ps1`: repo-only files (`.gitignore`, `REVIEW-*.md`, `NOTE.md`)
  are no longer written into MANIFEST.txt, so a delivery folder can contain every
  listed file instead of silently missing repo-only ones. MANIFEST now 25 files.
- `install.ps1`: copy into a staging folder, carry `data\` / `knowledge\` over,
  then swap by rename, with restore on failure. The old order deleted the
  installed skill first and had no rollback.
- `ui.ps1`: dot-sourcing no longer writes objects to the output stream
  (`$null = Set-DpiAware`) - it used to print a `Width Height` table.
- `pixelscan.ps1`: the two `Add-Type` blocks use single-quoted here-strings
  (`@' ... '@`), matching the "no interpolation" rule in BOOT.md.
- `BOOT.md`: dropped the drifting "actual 15 skills" number.
- `CHANGELOG.md`: the 0.2.1 entry pointed at a `tools/verify_manifest.ps1` that
  does not exist; it is `tools/manifest.ps1`.
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
  hashing, and `tools/manifest.ps1 -Mode verify` does the same when it checks, so a
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
