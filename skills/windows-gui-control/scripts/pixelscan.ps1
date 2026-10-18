# pixelscan.ps1 - pixel-level localization for ui.ps1.
# Loaded automatically by ui.ps1 when both files sit in the same folder.
# Everything here is ASCII on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI.

if (-not ("PixelScan" -as [type])) {
  Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class PixelScan {
  static int[] Pixels(string path, out int w, out int h) {
    using (var bmp = new Bitmap(path)) {
      w = bmp.Width; h = bmp.Height;
      var rect = new Rectangle(0, 0, w, h);
      var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      int[] buf = new int[w * h];
      Marshal.Copy(data.Scan0, buf, 0, buf.Length);
      bmp.UnlockBits(data);
      return buf;
    }
  }
  static int R(int v) { return (v >> 16) & 0xFF; }
  static int G(int v) { return (v >> 8) & 0xFF; }
  static int B(int v) { return v & 0xFF; }

  // Raw diff: every differing pixel, bounding box of all of them.
  public static string Region(string pa, string pb, int chThreshold) {
    int wa, ha, wb, hb;
    var a = Pixels(pa, out wa, out ha);
    var b = Pixels(pb, out wb, out hb);
    if (wa != wb || ha != hb) return string.Format("SIZE {0} {1} {2} {3} 0", wa, ha, wb, hb);
    int left = -1, top = -1, right = -1, bottom = -1; long changed = 0;
    for (int y = 0; y < ha; y++) {
      int row = y * wa;
      for (int x = 0; x < wa; x++) {
        int p = a[row + x], q = b[row + x];
        int d = Math.Abs(R(p) - R(q)) + Math.Abs(G(p) - G(q)) + Math.Abs(B(p) - B(q));
        if (d > chThreshold) {
          changed++;
          if (left < 0 || x < left) left = x;
          if (x > right) right = x;
          if (top < 0 || y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    double ratio = (double)changed / ((double)wa * ha);
    if (changed == 0) return "NONE 0 0 0 0 0.000";
    return string.Format("OK {0} {1} {2} {3} {4:F4}", left, top, right, bottom, ratio);
  }

  // Cluster-aware diff: keep cells with at least minPerCell changed pixels,
  // then pick the LARGEST 8-connected cluster of such cells. A menu popup is
  // one contiguous blob; a blinking clock or a spinner tail is not.
  public static string Dense(string pa, string pb, int chThreshold, int cell, int minPerCell) {
    int wa, ha, wb, hb;
    var a = Pixels(pa, out wa, out ha);
    var b = Pixels(pb, out wb, out hb);
    if (wa != wb || ha != hb) return "SIZE 0 0 0 0 0 0 0";
    if (cell < 4) cell = 4;
    int gw = (wa + cell - 1) / cell;
    int gh = (ha + cell - 1) / cell;
    int[] cnt = new int[gw * gh];
    long changed = 0;
    for (int y = 0; y < ha; y++) {
      int row = y * wa, gy = y / cell;
      for (int x = 0; x < wa; x++) {
        int p = a[row + x], q = b[row + x];
        int d = Math.Abs(R(p) - R(q)) + Math.Abs(G(p) - G(q)) + Math.Abs(B(p) - B(q));
        if (d > chThreshold) { cnt[gy * gw + (x / cell)]++; changed++; }
      }
    }
    bool[] hot = new bool[gw * gh];
    for (int i = 0; i < hot.Length; i++) hot[i] = cnt[i] >= minPerCell;

    bool[] seen = new bool[gw * gh];
    int bestCells = 0, bl = -1, bt = -1, br = -1, bb = -1;
    var stack = new System.Collections.Generic.Stack<int>();
    for (int gy = 0; gy < gh; gy++) {
      for (int gx = 0; gx < gw; gx++) {
        int idx = gy * gw + gx;
        if (!hot[idx] || seen[idx]) continue;
        int cells = 0, l = gx, t = gy, r = gx, bo = gy;
        stack.Clear(); stack.Push(idx); seen[idx] = true;
        while (stack.Count > 0) {
          int cur = stack.Pop();
          int cy2 = cur / gw, cx2 = cur % gw;
          cells++;
          if (cx2 < l) l = cx2; if (cx2 > r) r = cx2;
          if (cy2 < t) t = cy2; if (cy2 > bo) bo = cy2;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              int nx = cx2 + dx, ny = cy2 + dy;
              if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
              int ni = ny * gw + nx;
              if (hot[ni] && !seen[ni]) { seen[ni] = true; stack.Push(ni); }
            }
          }
        }
        if (cells > bestCells) {
          bestCells = cells; bl = l; bt = t; br = r; bb = bo;
        }
      }
    }
    double ratio = (double)changed / ((double)wa * ha);
    if (bestCells == 0) return string.Format("NONE 0 0 0 0 {0:F4} 0", ratio);
    int px0 = bl * cell, py0 = bt * cell;
    int px1 = Math.Min(wa - 1, br * cell + cell - 1), py1 = Math.Min(ha - 1, bb * cell + cell - 1);
    return string.Format("OK {0} {1} {2} {3} {4:F4} {5}", px0, py0, px1, py1, ratio, bestCells);
  }

  // Coarse-to-fine template search inside [x0..x1] x [y0..y1].
  // score = mean |dR|+|dG|+|dB| per sampled pixel (0 = identical, <12 = same widget).
  public static string Best(string hay, string needle, int step, int x0, int y0, int x1, int y1) {
    int hw, hh, nw, nh;
    var h = Pixels(hay, out hw, out hh);
    var n = Pixels(needle, out nw, out nh);
    if (nw > hw || nh > hh) return "TOOBIG 0 0 0";
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > hw - nw) x1 = hw - nw;
    if (y1 > hh - nh) y1 = hh - nh;
    if (x1 < x0) x1 = x0;
    if (y1 < y0) y1 = y0;
    // Reject nearly uniform templates: matching a flat patch always scores 0.
    long vsum = 0, vcnt = 0; int prev = -1;
    for (int y = 0; y < nh; y += 2) {
      for (int x = 0; x < nw; x += 2) {
        int v = R(n[y * nw + x]) + G(n[y * nw + x]) + B(n[y * nw + x]);
        if (prev >= 0) { vsum += Math.Abs(v - prev); vcnt++; }
        prev = v;
      }
    }
    double spread = vcnt == 0 ? 0 : (double)vsum / vcnt;
    if (spread < 4.0) return string.Format("FLAT 0 0 {0:F2}", spread);
    int s = step < 1 ? 1 : step;
    int bestX = x0, bestY = y0; double best = double.MaxValue;
    for (int y = y0; y <= y1; y += s) {
      for (int x = x0; x <= x1; x += s) {
        long sum = 0; int cnt = 0;
        for (int j = 0; j < nh; j += 3) {
          int hrow = (y + j) * hw, nrow = j * nw;
          for (int i = 0; i < nw; i += 3) {
            int p = h[hrow + x + i], q = n[nrow + i];
            sum += Math.Abs(R(p) - R(q)) + Math.Abs(G(p) - G(q)) + Math.Abs(B(p) - B(q));
            cnt += 3;
          }
        }
        double score = cnt == 0 ? double.MaxValue : (double)sum / cnt;
        if (score < best) { best = score; bestX = x; bestY = y; }
      }
    }
    return string.Format("{0} {1} {2:F2}", bestX, bestY, best);
  }
}
'@
}

# Take N screenshots as fast as the desktop allows, so short-lived UI
# (hover popups, menus, tooltips) cannot vanish between two model turns.
function Get-ScreenBurst {
  param([int]$Count = 5, [int]$IntervalMs = 120, [string]$Prefix = 'burst')
  $dir = Join-Path $env:TEMP ('burst_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $files = @()
  for ($i = 0; $i -lt $Count; $i++) {
    $p = Join-Path $dir ('{0}_{1:d2}.png' -f $Prefix, $i)
    $null = Get-Screen -Path $p
    $files += $p
    if ($i -lt ($Count - 1)) { Start-Sleep -Milliseconds $IntervalMs }
  }
  return [pscustomobject]@{ Dir = $dir; Files = $files; Count = $Count }
}

# Compare two captures. Default = cluster-aware bbox (robust against a blinking
# clock): cells of 24x24 px need at least 24 changed pixels to count as "hot".
function Get-ChangedRegion {
  param([string]$A, [string]$B, [int]$Threshold = 30, [int]$Cell = 24, [int]$MinPerCell = 24, [switch]$Raw)
  $res = [pscustomobject]@{
    Status = 'NONE'; Left = 0; Top = 0; Right = 0; Bottom = 0; Ratio = 0
    Width = 0; Height = 0; CenterX = 0; CenterY = 0; Cells = 0
  }
  if ($Raw) { $line = [PixelScan]::Region($A, $B, $Threshold); $parts = $line -split ' ' }
  else       { $line = [PixelScan]::Dense($A, $B, $Threshold, $Cell, $MinPerCell); $parts = $line -split ' ' }
  $res.Status = $parts[0]
  if ($parts[0] -eq 'OK') {
    $res.Left = [int]$parts[1]; $res.Top = [int]$parts[2]; $res.Right = [int]$parts[3]; $res.Bottom = [int]$parts[4]
    $res.Ratio = [double]$parts[5]
    if ($parts.Count -gt 6) { $res.Cells = [int]$parts[6] }
    $res.Width = $res.Right - $res.Left + 1
    $res.Height = $res.Bottom - $res.Top + 1
    $res.CenterX = [int](($res.Left + $res.Right) / 2)
    $res.CenterY = [int](($res.Top + $res.Bottom) / 2)
  } elseif ($parts[0] -eq 'SIZE') {
    $res.Ratio = 0
  }
  return $res
}

# Show what changed between two captures: writes a black/white mask image.
function Get-ChangeMask {
  param([string]$A, [string]$B, [int]$Threshold = 30, [string]$Path)
  if (-not $Path) { $Path = Join-Path $env:TEMP ('mask_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png') }
  $r = [PixelMask]::Write($A, $B, $Threshold, $Path)
  return $Path
}


# Fast whole-image mask writer. GetPixel over 4 MP takes ~10 s; Marshal.Copy ~30 ms.
if (-not ('PixelMask' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class PixelMask {
  static byte[] Grab(Bitmap src, out int stride, out int w, out int h) {
    w = src.Width; h = src.Height;
    var ra = new Rectangle(0, 0, w, h);
    using (var b32 = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
      using (var g = Graphics.FromImage(b32)) { g.DrawImage(src, ra); }
      var d = b32.LockBits(ra, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      try {
        stride = d.Stride;
        var buf = new byte[stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        return buf;
      } finally { b32.UnlockBits(d); }
    }
  }

  public static string Write(string pa, string pb, int th, string outp) {
    using (var a = new Bitmap(pa)) using (var b = new Bitmap(pb)) {
      if (a.Width != b.Width || a.Height != b.Height)
        throw new Exception("size mismatch: " + a.Width + "x" + a.Height + " vs " + b.Width + "x" + b.Height);
      int sa, sb, w, h;
      var A = Grab(a, out sa, out w, out h);
      var B = Grab(b, out sb, out w, out h);
      var mask = new byte[w * h];
      for (int y = 0; y < h; y++) {
        int ra2 = y * sa, rb = y * sb;
        for (int x = 0; x < w; x++) {
          int i = ra2 + x * 4, j = rb + x * 4;
          int d = Math.Abs(A[i] - B[j]) + Math.Abs(A[i+1] - B[j+1]) + Math.Abs(A[i+2] - B[j+2]);
          mask[y * w + x] = (byte)(d > th ? 255 : 0);
        }
      }
      using (var m = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
        var ra = new Rectangle(0, 0, w, h);
        var dm = m.LockBits(ra, ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        try {
          int stride = dm.Stride;
          var buf = new byte[stride * h];
          for (int y = 0; y < h; y++) {
            int row = y * stride;
            for (int x = 0; x < w; x++) {
              byte v = mask[y * w + x];
              buf[row + x * 3] = v; buf[row + x * 3 + 1] = v; buf[row + x * 3 + 2] = v;
            }
          }
          Marshal.Copy(buf, 0, dm.Scan0, buf.Length);
        } finally { m.UnlockBits(dm); }
        m.Save(outp, ImageFormat.Png);
      }
      return outp;
    }
  }
}
"@
}

# Crop a template out of a screenshot (used to build locators).
function Save-ImageCrop {
  param([string]$Source, [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Path)
  Add-Type -AssemblyName System.Drawing
  $probe = [System.Drawing.Image]::FromFile($Source)
  $iw = $probe.Width; $ih = $probe.Height; $probe.Dispose()
  if ($Width -le 0 -or $Height -le 0) { throw "Save-ImageCrop: width/height must be > 0 (got ${Width}x${Height})" }
  if ($X -lt 0 -or $Y -lt 0 -or ($X + $Width) -gt $iw -or ($Y + $Height) -gt $ih) {
    throw "Save-ImageCrop: rect ($X,$Y) ${Width}x${Height} is outside the ${iw}x${ih} image"
  }
  $src = [System.Drawing.Image]::FromFile($Source)
  try {
    $rect = New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  } finally { $src.Dispose() }
  return $Path
}

# Find a template anywhere on screen. Coarse pass (step 4) then a +-8 px refine.
# Returns Found / CenterX / CenterY / Score / Rect. Score <= Tolerance means "same widget".
function Find-ImageOnScreen {
  param(
    [string]$Template,
    [double]$Tolerance = 12,
    [string]$Shot,
    [int]$RegionX = 0, [int]$RegionY = 0, [int]$RegionW = 0, [int]$RegionH = 0
  )
  if (-not $Shot) { $Shot = Join-Path $env:TEMP ('find_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png'); $null = Get-Screen -Path $Shot }
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($Shot)
  $sw = $img.Width; $sh = $img.Height; $img.Dispose()
  $t = [System.Drawing.Image]::FromFile($Template)
  $tw = $t.Width; $th = $t.Height; $t.Dispose()

  if ($RegionW -le 0) { $RegionW = $sw - $RegionX }
  if ($RegionH -le 0) { $RegionH = $sh - $RegionY }
  $x1 = [math]::Min($sw - $tw, $RegionX + $RegionW - $tw)
  $y1 = [math]::Min($sh - $th, $RegionY + $RegionH - $th)

  $coarse = ([PixelScan]::Best($Shot, $Template, 4, $RegionX, $RegionY, $x1, $y1)) -split ' '
  if ($coarse[0] -eq 'FLAT' -or $coarse[0] -eq 'TOOBIG') {
    return [pscustomobject]@{
      Found = $false; Reason = $coarse[0]; Score = [double]$coarse[2]
      Left = 0; Top = 0; Width = $tw; Height = $th; CenterX = 0; CenterY = 0
      Tolerance = $Tolerance; Shot = $Shot
    }
  }
  $cx = [int]$coarse[0]; $cy = [int]$coarse[1]
  $fine = ([PixelScan]::Best($Shot, $Template, 1, $cx - 8, $cy - 8, $cx + 8, $cy + 8)) -split ' '
  $fx = [int]$fine[0]; $fy = [int]$fine[1]; $fscore = [double]$fine[2]

  return [pscustomobject]@{
    Found = ($fscore -le $Tolerance)
    Left = $fx; Top = $fy; Width = $tw; Height = $th
    CenterX = [int]($fx + $tw / 2); CenterY = [int]($fy + $th / 2)
    Score = [math]::Round($fscore, 2); Tolerance = $Tolerance; Shot = $Shot
  }
}

# Locate a template, click its centre, then prove the screen changed.
function Invoke-ClickTemplate {
  param([string]$Template, [double]$Tolerance = 12, [int]$WaitMs = 700, [int]$Threshold = 25)
  $before = Join-Path $env:TEMP ('ct_before_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  $after = Join-Path $env:TEMP ('ct_after_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  $null = Get-Screen -Path $before
  $hit = Find-ImageOnScreen -Template $Template -Tolerance $Tolerance -Shot $before
  if (-not $hit.Found) {
    # Keep ONE shape for every outcome: a caller that checks .Changed must not
    # get $null just because the template was missing.
    return [pscustomobject]@{
      Clicked = $false; Found = $false; Reason = $hit.Reason; Score = $hit.Score
      CenterX = 0; CenterY = 0; Changed = $false; Ratio = 0; RawRatio = 0; Diff = $null
    }
  }
  [Win32UI]::Click($hit.CenterX, $hit.CenterY)
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $after
  $d = Get-ChangedRegion -A $before -B $after -Threshold $Threshold
  $raw = Get-ChangedRegion -A $before -B $after -Threshold $Threshold -Raw
  # A checkbox tick changes far fewer than 24 pixels per cell, so the cluster
  # pass can say NONE. Fall back to the raw ratio (>= 20 changed pixels).
  $changed = ($d.Status -eq 'OK') -or ($raw.Status -eq 'OK' -and $raw.Ratio -ge 0.00005)
  return [pscustomobject]@{
    Clicked = $true; Found = $true; Score = $hit.Score; CenterX = $hit.CenterX; CenterY = $hit.CenterY
    Changed = $changed; Ratio = $d.Ratio; RawRatio = $raw.Ratio; Diff = $d
  }
}

# Move onto (X,Y), capture, move away, capture, diff: the bbox is the
# hover-only UI (tooltip, flyout, submenu).
function Test-HoverPopup {
  param([int]$X, [int]$Y, [int]$AwayPx = 600, [int]$WaitMs = 700, [int]$Threshold = 25)
  $a = Join-Path $env:TEMP ('hover_on_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  $b = Join-Path $env:TEMP ('hover_off_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  $orig = [Win32UI]::GetCursorPos()
  [Win32UI]::SetCursorPos($X, $Y)
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $a
  # Park in a corner instead of "X-600,Y-600": a diagonal move can land on
  # another widget and raise ITS tooltip, which would pollute the diff.
  [Win32UI]::SetCursorPos(4, 4)
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $b
  [Win32UI]::SetCursorPos([int]$orig.X, [int]$orig.Y)
  $d = Get-ChangedRegion -A $a -B $b -Threshold $Threshold
  $d | Add-Member -NotePropertyName HoverOnPng -NotePropertyValue $a
  $d | Add-Member -NotePropertyName HoverOffPng -NotePropertyValue $b
  return $d
}

# Hover UI (flyouts, thumbnails, tooltips) lives ~1 s and disappears when the
# pointer leaves. You cannot beat it with a model round trip - you must capture
# INSIDE its lifetime, from one process call:
#   1. park the cursor on the target and DO NOT move it again
#   2. burst-capture at ~70 ms for ~1.2 s
#   3. also snapshot new top-level windows and PrintWindow them (works while fading)
#   4. diff the frames to get the flyout bbox and keep the richest frame
function Capture-HoverFlyout {
  param(
    [int]$X, [int]$Y,
    [int]$Frames = 16, [int]$IntervalMs = 70,
    [int]$Threshold = 30, [string]$Dir
  )
  if (-not $Dir) { $Dir = Join-Path $env:TEMP ('flyout_' + [guid]::NewGuid().ToString('N').Substring(0, 6)) }
  New-Item -ItemType Directory -Path $Dir -Force | Out-Null

  $before = @{}
  foreach ($w in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 })) { $before[[int64]$w.MainWindowHandle] = $w.ProcessName }

  [Win32UI]::SetCursorPos($X, $Y)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $files = @()
  for ($i = 0; $i -lt $Frames; $i++) {
    $f = Join-Path $Dir ('f{0:d2}.png' -f $i)
    $null = Get-Screen -Path $f
    $files += $f
    $wait = $IntervalMs - [int]$sw.ElapsedMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }

  $best = $files[0]; $bestDiff = 0.0
  for ($i = 1; $i -lt $files.Count; $i++) {
    $r = Get-ChangedRegion -A $files[0] -B $files[$i] -Threshold $Threshold -Raw
    if ($r.Ratio -gt $bestDiff) { $bestDiff = $r.Ratio; $best = $files[$i] }
  }
  $diff = Get-ChangedRegion -A $files[0] -B $best -Threshold $Threshold

  $newWins = @()
  $after = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
  foreach ($w in $after) {
    if (-not $before.ContainsKey([int64]$w.MainWindowHandle)) {
      $shot = Join-Path $Dir ('win_' + $w.ProcessName + '_' + $w.MainWindowHandle + '.png')
      $cap = Get-WindowCapture -Window ([pscustomobject]@{ Hwnd = [int64]$w.MainWindowHandle }) -Path $shot -NoThrow
      $newWins += [pscustomobject]@{ Pid = $w.Id; Process = $w.ProcessName; Hwnd = [int64]$w.MainWindowHandle; Capture = $cap.Status; Path = $shot }
    }
  }
  [Win32UI]::SetCursorPos(4, 4)

  return [pscustomobject]@{
    Frames = $files.Count; Dir = $Dir; BestFrame = $best; BestRatio = [math]::Round($bestDiff, 5)
    Status = $diff.Status; Left = $diff.Left; Top = $diff.Top; Width = $diff.Width; Height = $diff.Height
    NewWindows = $newWins
  }
}

