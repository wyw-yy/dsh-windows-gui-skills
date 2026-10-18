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

# Show what changed between two captures: returns the cluster bbox plus the
# diff mask image so you can look at it instead of guessing.
function Get-ChangeMask {
  param([string]$A, [string]$B, [int]$Threshold = 30, [string]$Path)
  if (-not $Path) { $Path = Join-Path $env:TEMP ('mask_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png') }
  Add-Type -AssemblyName System.Drawing
  $ia = [System.Drawing.Image]::FromFile($A); $ib = [System.Drawing.Image]::FromFile($B)
  $w = $ia.Width; $h = $ia.Height
  $bm = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bm)
  $g.Clear([System.Drawing.Color]::Black)
  for ($y = 0; $y -lt $h; $y += 2) {
    for ($x = 0; $x -lt $w; $x += 2) {
      $pa = $ia.GetPixel($x, $y); $pb = $ib.GetPixel($x, $y)
      $d = [math]::Abs($pa.R - $pb.R) + [math]::Abs($pa.G - $pb.G) + [math]::Abs($pa.B - $pb.B)
      if ($d -gt $Threshold) { $bm.SetPixel($x, $y, [System.Drawing.Color]::White) }
    }
  }
  $g.Dispose(); $ia.Dispose(); $ib.Dispose()
  $bm.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bm.Dispose()
  return $Path
}

# Crop a template out of a screenshot (used to build locators).
function Save-ImageCrop {
  param([string]$Source, [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Path)
  Add-Type -AssemblyName System.Drawing
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
  if (-not $hit.Found) { return [pscustomobject]@{ Clicked = $false; Found = $false; Score = $hit.Score } }
  [Win32UI]::Click($hit.CenterX, $hit.CenterY)
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $after
  $d = Get-ChangedRegion -A $before -B $after -Threshold $Threshold
  return [pscustomobject]@{
    Clicked = $true; Found = $true; Score = $hit.Score; CenterX = $hit.CenterX; CenterY = $hit.CenterY
    Changed = ($d.Status -eq 'OK'); Ratio = $d.Ratio; Diff = $d
  }
}

# Move onto (X,Y), capture, move away, capture, diff: the bbox is the
# hover-only UI (tooltip, flyout, submenu).
function Test-HoverPopup {
  param([int]$X, [int]$Y, [int]$AwayPx = 600, [int]$WaitMs = 700, [int]$Threshold = 25)
  $a = Join-Path $env:TEMP ('hover_on_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  $b = Join-Path $env:TEMP ('hover_off_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  [Win32UI]::SetCursorPos($X, $Y)
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $a
  [Win32UI]::SetCursorPos([math]::Max(0, $X - $AwayPx), [math]::Max(0, $Y - $AwayPx))
  Start-Sleep -Milliseconds $WaitMs
  $null = Get-Screen -Path $b
  $d = Get-ChangedRegion -A $a -B $b -Threshold $Threshold
  $d | Add-Member -NotePropertyName HoverOnPng -NotePropertyValue $a
  $d | Add-Member -NotePropertyName HoverOffPng -NotePropertyValue $b
  return $d
}
