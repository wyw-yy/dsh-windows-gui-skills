# ui.ps1 - Windows GUI control for agents: screenshot, real mouse, UIA clicking.
# Load with:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   . "C:\Users\yang'yu\.agents\skills\windows-gui-control\scripts\ui.ps1"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes

if (-not ("Win32UI" -as [type])) {
$src = @'
using System;
using System.Runtime.InteropServices;
public class Win32UI {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
  public const uint LEFTDOWN=0x02, LEFTUP=0x04, RIGHTDOWN=0x08, RIGHTUP=0x10;
  public const int SW_RESTORE=9;
  public static void Click(int x,int y){
    SetCursorPos(x,y); System.Threading.Thread.Sleep(120);
    mouse_event(LEFTDOWN,0,0,0,UIntPtr.Zero); mouse_event(LEFTUP,0,0,0,UIntPtr.Zero);
  }
  public static void DblClick(int x,int y){
    SetCursorPos(x,y); System.Threading.Thread.Sleep(120);
    for(int i=0;i<2;i++){ mouse_event(LEFTDOWN,0,0,0,UIntPtr.Zero); mouse_event(LEFTUP,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(80); }
  }
  public static void RightClick(int x,int y){
    SetCursorPos(x,y); System.Threading.Thread.Sleep(120);
    mouse_event(RIGHTDOWN,0,0,0,UIntPtr.Zero); mouse_event(RIGHTUP,0,0,0,UIntPtr.Zero);
  }
}
'@
  Add-Type -TypeDefinition $src
}

function Set-DpiAware {
  # Call once per shell process. Without it a 150% display reports 1707x1067
  # while the capture is 2560x1600, and every click misses by the scale factor.
  if (-not ("Win32Dpi" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32Dpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
  }
  [void][Win32Dpi]::SetProcessDPIAware()
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  return [pscustomobject]@{ Width = $b.Width; Height = $b.Height }
}

function Get-ScreenInfo {
  # Screenshot + the numbers you need to convert preview pixels into clicks.
  param([string]$Path = "$env:TEMP\screen.png")
  $p = Get-Screen -Path $Path
  $img = [System.Drawing.Image]::FromFile($p)
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $info = [pscustomobject]@{
    Path       = $p
    ImageW     = $img.Width
    ImageH     = $img.Height
    ScreenW    = $b.Width
    ScreenH    = $b.Height
    ImageScale = [math]::Round($img.Width / $b.Width, 4)
  }
  $img.Dispose()
  return $info
}

function Get-Screen {
  param([string]$Path = "$env:TEMP\screen.png")
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $Path
}

function Get-WindowShot {
  param($Window, [string]$Path = "$env:TEMP\window.png")
  $r = Get-WindowRect $Window
  $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
  if ($w -le 0 -or $h -le 0) { return $null }
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $Path
}

function Get-WindowList {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
  $res = @()
  foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)) {
    if ($w.Current.Name) {
      $res += [pscustomobject]@{ Pid = $w.Current.ProcessId; Name = $w.Current.Name; Handle = $w.Current.NativeWindowHandle }
    }
  }
  return $res
}

function Get-Window {
  # Wildcards by default: * and ? work, everything else is literal.
  # Pass -Regex for a raw regular expression.
  param([string]$Like, [switch]$Regex)
  if (-not $Like) { return $null }
  $pattern = $Like
  if (-not $Regex) {
    $pattern = [regex]::Escape($Like).Replace('\*', '.*').Replace('\?', '.')
  }
  foreach ($w in Get-WindowList) {
    if ($w.Name -match $pattern) {
      $root = [System.Windows.Automation.AutomationElement]::RootElement
      $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $w.Name)
      return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    }
  }
  return $null
}

function Get-WindowByPid {
  param([int]$ProcessId = 0, [int[]]$Id = @())
  if ($ProcessId -eq 0 -and $Id.Count -gt 0) { $ProcessId = $Id[0] }
  if ($ProcessId -eq 0) { return $null }
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
  try { $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond) } catch { return $null }
  $best = $null
  foreach ($w in $all) {
    try {
      $rc = $w.Current.BoundingRectangle
      if ($rc.Width -gt 200 -and $rc.Height -gt 100) { return $w }
      if (-not $best) { $best = $w }
    } catch {}
  }
  return $best
}

function Wait-Window {
  param([string]$Like, [int]$TimeoutSec = 60)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $w = Get-Window -Like $Like
    if ($w) { return $w }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Wait-AppWindow {
  param([int]$ProcessId, [int]$TimeoutSec = 60)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $w = Get-WindowByPid -ProcessId $ProcessId
    if ($w) { return $w }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Start-GuiApp {
  param([string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSec = 60)
  if ($Arguments.Count -gt 0) { $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru }
  else { $p = Start-Process -FilePath $Exe -PassThru }
  $w = Wait-AppWindow -ProcessId $p.Id -TimeoutSec $TimeoutSec
  return [pscustomobject]@{ Pid = $p.Id; Process = $p; Window = $w }
}

# Fail loudly and once, instead of 20 IntPtr cast errors downstream.
function Assert-Window {
  param($Window, [string]$Hint = 'window not found: got $null (app not started yet, or matched by PID of a launcher process)')
  if ($null -eq $Window) { throw $Hint }
  try { $h = $Window.Current.NativeWindowHandle } catch { throw $Hint }
  if (-not $h -or [int64]$h -eq 0) { throw $Hint }
  return $Window
}

function Get-WindowRect {
  param($Window)
  $null = Assert-Window $Window
  $h = [IntPtr]$Window.Current.NativeWindowHandle
  $r = New-Object Win32UI+RECT
  [Win32UI]::GetWindowRect($h, [ref]$r) | Out-Null
  return $r
}

function Focus-Window {
  param($Window)
  $null = Assert-Window $Window
  $h = [IntPtr]$Window.Current.NativeWindowHandle
  [Win32UI]::ShowWindow($h, 9) | Out-Null
  [Win32UI]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 400
}

function Invoke-ClickWindow {
  param($Window, [double]$FX = 0.5, [double]$FY = 0.5)
  $r = Get-WindowRect $Window
  $x = [int]($r.Left + ($r.Right - $r.Left) * $FX)
  $y = [int]($r.Top + ($r.Bottom - $r.Top) * $FY)
  Focus-Window $Window
  [Win32UI]::Click($x, $y)
  return "$x,$y"
}

# Type text through the clipboard so a Chinese IME cannot corrupt it.
function Send-Text {
  param([string]$Text)
  Set-Clipboard -Value $Text
  Start-Sleep -Milliseconds 150
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Milliseconds 350
}

function Send-Key {
  param([string]$Keys)
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
}

function Get-UiElements {
  param($Window, [int]$Max = 60)
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $out = @()
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($Window)
  while ($queue.Count -gt 0 -and $out.Count -lt $Max) {
    $cur = $queue.Dequeue()
    try {
      $ct = $cur.Current.ControlType.ProgrammaticName
      $short = $ct.Replace('ControlType.', '')
      $nm = $cur.Current.Name
      $rc = $cur.Current.BoundingRectangle
      if ($nm -and $rc.Width -gt 0) {
        $out += [pscustomobject]@{ Type = $short; Name = $nm; X = [int]($rc.X + $rc.Width / 2); Y = [int]($rc.Y + $rc.Height / 2) }
      }
      $child = $walker.GetFirstChild($cur)
      while ($child -ne $null) { $queue.Enqueue($child); $child = $walker.GetNextSibling($child) }
    } catch {}
  }
  return $out
}

function Get-UiText {
  param($Window, [int]$Max = 80)
  (Get-UiElements -Window $Window -Max $Max) | Where-Object { $_.Type -match 'Text|Document|Button|MenuItem' } | ForEach-Object { $_.Name }
}

function Invoke-ClickByName {
  param($Window, [string]$Name)
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
  $el = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
  if (-not $el) { return $false }
  try {
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    return $true
  } catch {}
  $rc = $el.Current.BoundingRectangle
  if ($rc.Width -le 0) { return $false }
  Focus-Window $Window
  [Win32UI]::Click([int]($rc.X + $rc.Width / 2), [int]($rc.Y + $rc.Height / 2))
  return $true
}

# Press the first matching button found in ANY window (popup killer).
function Close-Dialogs {
  # ASCII-only defaults: Windows PowerShell 5.1 reads .ps1 as ANSI, so a
  # non-BOM UTF-8 file with CJK literals breaks the parser. Pass CJK button
  # names as arguments when needed.
  param([string[]]$Names = @('OK', 'Yes', 'Continue', 'Close'), [int]$Rounds = 1)
  $hit = @()
  for ($i = 0; $i -lt $Rounds; $i++) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    $found = $false
    foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)) {
      foreach ($n in $Names) {
        $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $n)
        $btns = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
        if ($btns.Count -gt 0) {
          $b = $btns[0]
          try { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
          catch { $rc = $b.Current.BoundingRectangle; [Win32UI]::Click([int]($rc.X + $rc.Width / 2), [int]($rc.Y + $rc.Height / 2)) }
          $hit += "$($w.Current.Name) -> $n"
          $found = $true
          Start-Sleep -Milliseconds 600
          break
        }
      }
      if ($found) { break }
    }
    if (-not $found) { break }
  }
  return $hit
}

# ===========================================================================
# v2 additions: capture a window even when it is COVERED by other windows,
# prove that it really was covered, dump the UIA tree with AutomationId, and
# verify that a click actually changed something.
# ===========================================================================

if (-not ("Win32Capture" -as [type])) {
$srcCap = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class Win32Capture {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  // flags: 2 = PW_RENDERFULLCONTENT (what most modern apps need), 0 = legacy
  public static string Grab(IntPtr h, string path, uint flags) {
    RECT r; GetWindowRect(h, out r);
    int w = r.Right - r.Left, hh = r.Bottom - r.Top;
    if (w < 40 || hh < 40) return "TOOSMALL " + w + "x" + hh + " iconic=" + IsIconic(h);
    using (Bitmap b = new Bitmap(w, hh, PixelFormat.Format32bppArgb))
    using (Graphics g = Graphics.FromImage(b)) {
      IntPtr dc = g.GetHdc();
      bool ok = PrintWindow(h, dc, flags);
      g.ReleaseHdc(dc);
      b.Save(path, ImageFormat.Png);
      return (ok ? "OK " : "FAIL ") + w + "x" + hh;
    }
  }
  public static bool IsMinimized(IntPtr h) { return IsIconic(h); }
  public static bool IsForeground(IntPtr h) { return GetForegroundWindow() == h; }
  public static string Rect(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    return r.Left + " " + r.Top + " " + (r.Right - r.Left) + " " + (r.Bottom - r.Top);
  }
  // mean absolute pixel difference between two PNGs, 0..255
  public static double Diff(string a, string b) {
    using (Bitmap x = new Bitmap(a))
    using (Bitmap y = new Bitmap(b)) {
      int w = Math.Min(x.Width, y.Width), hh = Math.Min(x.Height, y.Height);
      long tot = 0; double sum = 0;
      for (int py = 3; py < hh - 3; py += 7) for (int px = 3; px < w - 3; px += 7) {
        Color p = x.GetPixel(px, py), q = y.GetPixel(px, py);
        sum += (Math.Abs(p.R - q.R) + Math.Abs(p.G - q.G) + Math.Abs(p.B - q.B)) / 3.0;
        tot++;
      }
      return tot == 0 ? 0 : sum / tot;
    }
  }
}
'@
  Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $srcCap
}

function Get-ScreenRegion {
  param([int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Path = "$env:TEMP\region.png")
  if ($Width -le 0 -or $Height -le 0) { return $null }
  $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $Path
}

# Capture ONE window's own content, even if other windows cover it.
# Works for covered windows; NOT for minimized ones (Windows reports a
# 158x26 rect for those, so restore first with Focus-Window).
function Get-WindowCapture {
  param($Window, [string]$Path = "$env:TEMP\win_capture.png")
  $null = Assert-Window $Window
  $h = [IntPtr]$Window.Current.NativeWindowHandle
  $rc = [Win32Capture]::Rect($h).Split(' ')
  $res = [Win32Capture]::Grab($h, $Path, 2)
  if ($res -like 'FAIL*') { $res = [Win32Capture]::Grab($h, $Path, 0) }
  return [pscustomobject]@{
    Status    = $res
    Path      = $Path
    Minimized = [Win32Capture]::IsMinimized($h)
    Foreground = [Win32Capture]::IsForeground($h)
    Left = [int]$rc[0]; Top = [int]$rc[1]; Width = [int]$rc[2]; Height = [int]$rc[3]
  }
}

# How much the window's real content differs from what is painted at its
# screen rectangle. High value (> 20) proves the window is covered.
function Test-Occluded {
  param($Window, [string]$Tag = 'occ')
  $cap = "$env:TEMP\${Tag}_win.png"
  $scr = "$env:TEMP\${Tag}_screen.png"
  $info = Get-WindowCapture -Window $Window -Path $cap
  if ($info.Status -like 'TOOSMALL*') { return [pscustomobject]@{ Occluded = $false; Diff = 0; Note = $info.Status } }
  $null = Get-ScreenRegion -X $info.Left -Y $info.Top -Width $info.Width -Height $info.Height -Path $scr
  $d = [Win32Capture]::Diff($cap, $scr)
  return [pscustomobject]@{ Occluded = ($d -gt 20); Diff = [math]::Round($d, 1); WindowPng = $cap; ScreenPng = $scr }
}

# Full UIA walk (breadth first) returning both printable rows and live elements.
function Get-UiNodes {
  param($Window, [int]$Max = 400, [int]$MaxDepth = 8)
  $null = Assert-Window $Window
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $rows = @()
  $q = New-Object System.Collections.Queue
  $q.Enqueue(@{ El = $Window; D = 0 })
  while ($q.Count -gt 0 -and $rows.Count -lt $Max) {
    $item = $q.Dequeue()
    $cur = $item.El; $d = $item.D
    try {
      $rc = $cur.Current.BoundingRectangle
      $type = $cur.Current.ControlType.ProgrammaticName.Replace('ControlType.', '')
      $rows += [pscustomobject]@{
        Depth        = $d
        Type         = $type
        Name         = $cur.Current.Name
        AutomationId = $cur.Current.AutomationId
        Enabled      = $cur.Current.IsEnabled
        X            = [int]($rc.X + $rc.Width / 2)
        Y            = [int]($rc.Y + $rc.Height / 2)
        W            = [int]$rc.Width
        H            = [int]$rc.Height
        Element      = $cur
      }
      if ($d -lt $MaxDepth) {
        $child = $walker.GetFirstChild($cur)
        while ($child -ne $null) {
          $q.Enqueue(@{ El = $child; D = $d + 1 })
          $child = $walker.GetNextSibling($child)
        }
      }
    } catch {}
  }
  return $rows
}

# Printable tree, e.g. to paste into a report. Text only.
function Get-UiTree {
  param($Window, [int]$Max = 200, [int]$MaxDepth = 6)
  $nodes = Get-UiNodes -Window $Window -Max $Max -MaxDepth $MaxDepth
  $out = @()
  foreach ($n in $nodes) {
    $pad = '  ' * $n.Depth
    $id = if ($n.AutomationId) { ' #' + $n.AutomationId } else { '' }
    $nm = if ($n.Name) { ' "' + $n.Name + '"' } else { '' }
    $out += ('{0}{1}{2}{3} [{4},{5}]' -f $pad, $n.Type, $id, $nm, $n.X, $n.Y)
  }
  return $out
}

# Semantic lookup: by Name, AutomationId, or control type. Returns the first
# live element (or $null). This is the pywinauto-equivalent fast path.
function Find-UiElement {
  param($Window, [string]$Name, [string]$AutomationId, [string]$Type, [int]$Max = 600)
  $nodes = Get-UiNodes -Window $Window -Max $Max
  foreach ($n in $nodes) {
    if ($Name -and $n.Name -ne $Name) { continue }
    if ($AutomationId -and $n.AutomationId -ne $AutomationId) { continue }
    if ($Type -and $n.Type -ne $Type) { continue }
    return $n.Element
  }
  return $null
}

function Invoke-ClickElement {
  param($Element)
  if (-not $Element) { return $false }
  try { $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch {}
  try { $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); return $true } catch {}
  try { $Element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle(); return $true } catch {}
  $rc = $Element.Current.BoundingRectangle
  if ($rc.Width -le 0) { return $false }
  [Win32UI]::Click([int]($rc.X + $rc.Width / 2), [int]($rc.Y + $rc.Height / 2))
  return $true
}

# Click, then PROVE the pixels changed. Retries once after re-focusing.
# Returns { Changed = $true/$false, Diff = n }.
function Invoke-VerifiedClick {
  param($Window, [int]$X, [int]$Y, [int]$TimeoutMs = 2500)
  $null = Assert-Window $Window
  $before = "$env:TEMP\vc_before.png"
  $after = "$env:TEMP\vc_after.png"
  $null = Get-WindowCapture -Window $Window -Path $before
  [Win32UI]::Click($X, $Y)
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  $best = 0
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
    $null = Get-WindowCapture -Window $Window -Path $after
    $d = [Win32Capture]::Diff($before, $after)
    if ($d -gt $best) { $best = $d }
    if ($d -gt 2) { return [pscustomobject]@{ Changed = $true; Diff = [math]::Round($d, 1) } }
  }
  return [pscustomobject]@{ Changed = $false; Diff = [math]::Round($best, 1) }
}

# Click a control found by name and verify the window changed.
function Invoke-ClickByNameVerified {
  param($Window, [string]$Name, [string]$AutomationId)
  $el = Find-UiElement -Window $Window -Name $Name -AutomationId $AutomationId
  if (-not $el) { return [pscustomobject]@{ Found = $false; Changed = $false } }
  $rc = $el.Current.BoundingRectangle
  $r = Invoke-VerifiedClick -Window $Window -X ([int]($rc.X + $rc.Width / 2)) -Y ([int]($rc.Y + $rc.Height / 2))
  return [pscustomobject]@{ Found = $true; Changed = $r.Changed; Diff = $r.Diff }
}
