# App UI notes: what opens on hover, what on click, and what is disabled until the right state

Written after a failed blind-click sweep on uVision (2026-10-18). A single click on an
unknown toolbar button opened a new source file and a `Save changes to 'Text1'?` modal
dialog, after which every further click went to the dialog and the sweep measured
nothing. Two rules follow from that, and they apply to every app in this file:

1. **Hover before you click.** Hovering is non-destructive and reveals whether a control
   has a tooltip at all. Only click things whose meaning you already know.
2. **A modal dialog stops everything.** `#32770` windows (and their Electron/Java
   equivalents) swallow input for the whole process. Detect, answer, close, verify.

## Enablement (why a button does nothing)

Buttons in these IDEs are usually *present but disabled*, which looks identical to a
broken coordinate. The disabled state is not a hit-testing problem, so retrying the click
never helps. The state conditions below are the ones that matter in practice; the
authoritative source is the vendor manual, and for the CLI cases the state does not
matter at all.

| App | Control group | Enabled only when | What to do instead |
|---|---|---|---|
| uVision (Keil MDK) | Build / Rebuild / Batch Build | a target project is loaded (`Project -> Open Project` succeeded) | `UV4.exe -b <proj>.uvprojx -j0 -o build.log` |
| uVision | Download / Flash | a debug adapter is configured **and** a target project is open | `UV4.exe -f <proj>.uvprojx -j0 -o flash.log` |
| uVision | Start/Stop Debug Session, step/run | a build output (`.axf`) exists | `UV4.exe -d <proj>.uvprojx` (debug), or just flash |
| uVision | Debug -> Peripherals / Watch / Memory windows | only inside a debug session | not scriptable, skip |
| uVision | Undo / Redo / Cut / Copy / Paste | an editor window is focused and the clipboard/stack is non-empty | edit files directly |
| CubeMX | GENERATE CODE | a project is open **and** the clock tree is valid (no unresolved clock issue) | `STM32CubeMX.exe -q gen.txt` (`config load`, `project generate`, `exit`) |
| CubeMX | Clock Configuration fields | the `.ioc` loaded without migration prompts | edit `RCC.*` keys in the `.ioc`, then regenerate |
| CubeMX | Pin right-click menu entries | the pin is not locked by an enabled peripheral | change the peripheral activation first |
| LCEDA Pro | almost every canvas command | an editor tab is open (start page has no canvas) | official CLI: `easyeda-client-cli` (EasyEDA Pro client CLI) |

## Which popups are real windows

Measured with EnumWindows before/after the action, same machine:

| App | Hover result | Click result |
|---|---|---|
| uVision | `tooltips_class32` (~250-340 x 63-83 px, appears ~14 px below the cursor) | menu popup class `Afx:001E0000:...` (MFC menus); modal `#32770` for dialogs |
| CubeMX (Java/SWT) | nothing enumerable - tooltips are drawn inside the window | nothing enumerable - popups are in-window |
| LCEDA Pro (Electron) | nothing enumerable | nothing enumerable; new windows only for separate dialogs |

Consequence for automation:

- uVision: window-based detection is exact and cheap. `learn-ui.ps1 -App keil -Modes hover`
  records the tooltip window position and size per toolbar point into
  `data/ui-probes.json`.
- CubeMX / LCEDA: there is no window to detect. Use the pixel path
  (`Invoke-Flyout`, `Get-TransientRegion`) or - better - the CLI, because the GUI exposes
  no machine-readable structure at all (see the UIA measurements in SKILL.md).

## Recorded layout (uVision 5.39, 150% scaling, maximised)

Window-relative coordinates, measured once and stored in `data/ui-probes.json`:

- menu bar row: y = 50, first item x = 55, pitch ~55 (`File`, `Edit`, `View`, `Project`,
  `Flash`, `Debug`, `Peripherals`, `Tools`, `SVCS`, `Window`, `Help`)
- toolbar row 1: y = 88 (new / open / save / cut / copy / paste / undo / redo)
- toolbar row 2: y = 122 (build / rebuild / batch / download / options ...)

These are *not* stable across versions and DPI. Re-run the hover sweep after an upgrade
instead of trusting the numbers.

## QQ NT (9.x, Chromium shell) - measured 2026-10-18

QQ renders nothing when its window is shown with `ShowWindow` by another process: the
window appears but the client area stays black/white (average brightness 245/255 on a
"white" one, 0 on a "black" one). Only the app itself can paint it, so **do not force
it**, use one of these:

| Need | How | Verified |
|---|---|---|
| show/hide the main panel | `Ctrl+Alt+Z` sent to any QQ window | yes - the chat window 1707762 became the 1458x966 main panel |
| open a chat with a known name | click the search box, paste the name, click the first "联系人" row | yes |
| send text | click the empty input area, paste via clipboard, click "发送" | yes - 10 lines delivered at 21:55 |

Layout of the main panel (window-relative, 1458x966 at 150% scaling):

- search box: (165, 97)
- first contact row: y = 240 (followed by 群聊 rows, then 聊天记录)
- input area: y = 760-880, click around (700, 800)
- "发送": (1340, 916)

**Trap that cost a red packet dialog:** the format toolbar row sits at y = 684
(emoji / scissors / folder / image / screenshot / sticker / **红包** / voice). A click at
(700, 700) lands on that row and opened the 红包 dialog. Click the input area *below*
y = 760, and after every click take a capture before the next one - a wrong click here
opens a modal that blocks the rest of the sequence.
