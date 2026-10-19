# flyouts.ps1 - transient (hover) UI: passive detection, a learned knowledge base,
# and a regression check that classifies what changed instead of guessing.
# ASCII only: Windows PowerShell 5.1 reads .ps1 as ANSI, non-ASCII breaks parsing.

function Get-FlyoutKnowledgePath {
  param([string]$Path)
  if ($Path) { return $Path }
  $dir = Join-Path $env:USERPROFILE '.agents\skills\windows-gui-control\data'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  return (Join-Path $dir 'flyouts.json')
}

function Get-FlyoutKnowledge {
  param([string]$Path)
  $p = Get-FlyoutKnowledgePath -Path $Path
  if (-not (Test-Path $p)) { return [pscustomobject]@{ version = 1; entries = @() } }
  $raw = Get-Content $p -Raw -Encoding UTF8
  if (-not $raw.Trim()) { return [pscustomobject]@{ version = 1; entries = @() } }
  return ($raw | ConvertFrom-Json)
}

function Save-FlyoutKnowledge {
  param($Knowledge, [string]$Path)
  $p = Get-FlyoutKnowledgePath -Path $Path
  $json = $Knowledge | ConvertTo-Json -Depth 10
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p, $json, $enc)
  return $p
}

function Get-FlyoutKey {
  param([string]$Name, [string]$Process, [string]$Title)
  if ($Name) { return $Name }
  $proc = if ($Process) { $Process } else { 'unknown' }
  $t = if ($Title) { $Title } else { 'untitled' }
  return ($proc + '|' + $t)
}

# Passive sweep: DO NOT touch the mouse. A region that appears and then goes away
# on its own inside the burst is a transient overlay (toast/flyout/thumbnail).
function Get-TransientRegion {
  param(
    [int]$Frames = 12, [int]$IntervalMs = 80,
    [int]$Threshold = 30, [double]$ReturnRatio = 0.25,
    [string]$Dir
  )
  if (-not $Dir) { $Dir = Join-Path $env:TEMP ('trans_' + [guid]::NewGuid().ToString('N').Substring(0, 6)) }
  New-Item -ItemType Directory -Path $Dir -Force | Out-Null

  $files = @(); $sw = [Diagnostics.Stopwatch]::StartNew()
  for ($i = 0; $i -lt $Frames; $i++) {
    $f = Join-Path $Dir ('t{0:d2}.png' -f $i)
    $null = Get-Screen -Path $f
    $files += $f
    $wait = $IntervalMs - [int]$sw.ElapsedMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }

  $ratios = @()
  for ($i = 0; $i -lt $files.Count; $i++) {
    $r = Get-ChangedRegion -A $files[0] -B $files[$i] -Threshold $Threshold -Raw
    $ratios += [double]$r.Ratio
  }
  $peak = 0; for ($i = 1; $i -lt $ratios.Count; $i++) { if ($ratios[$i] -gt $ratios[$peak]) { $peak = $i } }

  $detected = $false
  if ($peak -gt 0 -and $ratios[$peak] -gt 0.0002 -and $ratios[$ratios.Count - 1] -lt ($ratios[$peak] * $ReturnRatio)) {
    $detected = $true
  }
  $d = Get-ChangedRegion -A $files[0] -B $files[$peak] -Threshold $Threshold
  return [pscustomobject]@{
    Detected = $detected; PeakIndex = $peak; PeakRatio = [math]::Round($ratios[$peak], 5)
    SettledRatio = [math]::Round($ratios[$ratios.Count - 1], 5)
    Status = $d.Status; Left = $d.Left; Top = $d.Top; Width = $d.Width; Height = $d.Height
    Frames = $files; Dir = $Dir
  }
}

function Get-RegionIoU {
  param($A, $B)
  if (-not $A -or -not $B) { return 0.0 }
  $x1 = [math]::Max($A.Left, $B.Left); $y1 = [math]::Max($A.Top, $B.Top)
  $x2 = [math]::Min($A.Left + $A.Width, $B.Left + $B.Width)
  $y2 = [math]::Min($A.Top + $A.Height, $B.Top + $B.Height)
  if ($x2 -le $x1 -or $y2 -le $y1) { return 0.0 }
  $inter = ($x2 - $x1) * ($y2 - $y1)
  $ua = $A.Width * $A.Height; $ub = $B.Width * $B.Height
  if ($ua + $ub - $inter -le 0) { return 0.0 }
  return [math]::Round($inter / ($ua + $ub - $inter), 3)
}

# Compare one observation with the stored expectation and name the situation.
function Get-FlyoutVerdict {
  param($Stored, $Observed)
  if (-not $Observed) { return 'GONE' }
  if (-not $Stored) { return 'LEARNED' }
  if ($Stored.PSObject.Properties['Class'] -and $Observed.PSObject.Properties['Class'] -and
      $Stored.Class -and $Observed.Class -and $Stored.Class -ne $Observed.Class) {
    return 'DIFFERENT_UI'
  }
  $iou = Get-RegionIoU -A $Stored -B $Observed
  $areaS = [double]$Stored.Width * $Stored.Height
  $areaO = [double]$Observed.Width * $Observed.Height
  if ($areaS -le 0 -or $areaO -le 0) { return 'DIFFERENT_UI' }
  $ratio = $areaO / $areaS
  if ($iou -ge 0.6) { return 'MATCH' }
  if ($iou -ge 0.2 -and $ratio -gt 0.5 -and $ratio -lt 2.0) { return 'MOVED' }
  if ($ratio -ge 0.5 -and $ratio -le 2.0) { return 'MOVED' }
  return 'DIFFERENT_UI'
}

function Add-FlyoutObservation {
  param($Knowledge, [string]$Key, $Trigger, $Region, [string]$Verdict, [int]$Attempt)
  $entry = $Knowledge.entries | Where-Object { $_.key -eq $Key } | Select-Object -First 1
  $now = (Get-Date).ToString('s')
  if (-not $entry) {
    $entry = [pscustomobject]@{
      key = $Key; trigger = $Trigger; region = $Region; confidence = 0; attempts = 0
      firstSeen = $now; lastSeen = $now; lastVerdict = $Verdict
      observations = @(); disagreements = @()
    }
    $Knowledge.entries = @($Knowledge.entries) + $entry
  }
  $entry.attempts = [int]$entry.attempts + 1
  $obs = [pscustomobject]@{ at = $now; verdict = $Verdict; attempt = $Attempt; trigger = $Trigger; region = $Region }
  $entry.observations = @($entry.observations) + $obs
  if ($entry.observations.Count -gt 20) { $entry.observations = $entry.observations[-20..-1] }
  if ($Verdict -eq 'MATCH') { $entry.confidence = [int]$entry.confidence + 1; $entry.region = $Region; $entry.trigger = $Trigger; $entry.lastSeen = $now }
  elseif ($Verdict -eq 'MOVED') { $entry.region = $Region; $entry.trigger = $Trigger; $entry.lastSeen = $now; $entry.confidence = [int]$entry.confidence }
  elseif ($Verdict -eq 'GONE') { $entry.confidence = [Math]::Max(0, [int]$entry.confidence - 1) }
  elseif ($Verdict -eq 'LEARNED') { $entry.confidence = 1; $entry.lastSeen = $now }
  $entry.lastVerdict = $Verdict
  return $entry
}

# Open a known flyout: fast path from the knowledge base, verification every time,
# and an explicit verdict when today does not match yesterday.
function Invoke-Flyout {
  param(
    [string]$Name,
    [int]$TriggerX, [int]$TriggerY,
    [int]$Attempts = 3, [int]$Frames = 10, [int]$IntervalMs = 60,
    [int]$Threshold = 30, [string]$KnowledgePath, [switch]$ForceSweep
  )
  $kb = Get-FlyoutKnowledge -Path $KnowledgePath
  $key = $Name
  $entry = $kb.entries | Where-Object { $_.key -eq $key } | Select-Object -First 1

  $tx = $TriggerX; $ty = $TriggerY
  if ($entry -and $entry.trigger -and $tx -eq 0 -and $ty -eq 0) { $tx = [int]$entry.trigger.x; $ty = [int]$entry.trigger.y }

  $fast = $false
  if ($entry -and [int]$entry.confidence -ge 2 -and -not $ForceSweep) { $fast = $true }

  $verdicts = @(); $lastRegion = $null; $lastPeak = $null; $gonePenalised = $false
  for ($a = 1; $a -le $Attempts; $a++) {
    # Passive look first: if the UI is already on screen, we do not need to hover.
    $pre = Get-TransientRegion -Frames 4 -IntervalMs 60 -Threshold $Threshold
    if ($pre.Detected) { $lastRegion = $pre; $lastPeak = $pre.PeakRatio }

    [Win32UI]::SetCursorPos($tx, $ty)
    $frames = if ($fast) { 6 } else { $Frames }
    $r = Capture-HoverFlyout -X $tx -Y $ty -Frames $frames -IntervalMs $IntervalMs -Threshold $Threshold

    # A new top-level window is the reliable identity of a flyout: pixels also
    # catch blinking carets and animated text, which produced 24x24 false bboxes.
    $observed = $null
    $near = $r.NewWindows | Where-Object {
      ([math]::Abs($_.Left + $_.Width / 2 - $tx) -lt 900) -and
      ([math]::Abs($_.Top + $_.Height / 2 - $ty) -lt 900) -and
      $_.Width -le 900 -and $_.Height -le 700 -and ($_.Width * $_.Height) -ge 64
    } | Sort-Object { $_.Width * $_.Height } | Select-Object -First 1
    if ($near) {
      $observed = [pscustomobject]@{
        Left = $near.Left; Top = $near.Top; Width = $near.Width; Height = $near.Height
        Class = $near.Class; Hwnd = $near.Hwnd; Source = 'window'; Ratio = $r.BestRatio; Frame = $near.Path
      }
    } elseif ($r.Status -eq 'OK' -and $r.BestRatio -ge 0.0002 -and $r.Width * $r.Height -ge 400) {
      $observed = [pscustomobject]@{
        Left = $r.Left; Top = $r.Top; Width = $r.Width; Height = $r.Height
        Class = ''; Hwnd = 0; Source = 'pixels'; Ratio = $r.BestRatio; Frame = $r.BestFrame
      }
    }
    if ($observed) { $lastRegion = $observed; $lastPeak = $r.BestRatio }

    $stored = if ($entry -and $entry.region -and $entry.region.Width -gt 0) { $entry.region } else { $null }
    $v = Get-FlyoutVerdict -Stored $stored -Observed $observed
    $verdicts += $v
    $trigger = [pscustomobject]@{ x = $tx; y = $ty }

    # Write gate: a single contradictory observation must NOT rewrite the entry.
    # LEARNED writes once, MATCH confirms every time, MOVED / DIFFERENT_UI need
    # two consecutive identical verdicts, and GONE costs at most -1 per call
    # (otherwise 3 attempts at a closed app drop confidence by 3).
    $prev = if ($verdicts.Count -ge 2) { $verdicts[$verdicts.Count - 2] } else { $null }
    $shouldWrite = $false
    if (-not $entry) { $shouldWrite = $true }
    elseif ($v -eq 'MATCH') { $shouldWrite = $true }
    elseif ($v -eq 'MOVED' -and $prev -eq 'MOVED') { $shouldWrite = $true }
    elseif ($v -eq 'DIFFERENT_UI' -and $prev -eq 'DIFFERENT_UI') { $shouldWrite = $true }
    elseif ($v -eq 'GONE' -and -not $gonePenalised) { $shouldWrite = $true; $gonePenalised = $true }
    if ($shouldWrite) {
      $entry = Add-FlyoutObservation -Knowledge $kb -Key $key -Trigger $trigger -Region $observed -Verdict $v -Attempt $a
    }

    if ($v -eq 'MATCH') { break }
    if ($v -eq 'GONE' -and $a -ge 1 -and $verdicts.Count -ge 2 -and $verdicts[0] -ne 'GONE') { break }
    Start-Sleep -Milliseconds 250
  }

  # Disagreement: the attempts did not agree with each other -> this entry is unstable.
  # LEARNED then MATCH is the normal first run, not a contradiction. Only a real
  # disagreement (found vs not found, or a different UI) marks the entry unstable.
  $distinct = $verdicts | Select-Object -Unique
  $pos = @($verdicts | Where-Object { $_ -in @('LEARNED', 'MOVED', 'MATCH') }).Count
  $neg = @($verdicts | Where-Object { $_ -in @('GONE', 'DIFFERENT_UI') }).Count
  $unstable = ($pos -gt 0 -and $neg -gt 0)
  if ($entry -and $unstable) {
    $entry.disagreements = @($entry.disagreements) + [pscustomobject]@{ at = (Get-Date).ToString('s'); verdicts = $verdicts }
    if ($entry.disagreements.Count -gt 10) { $entry.disagreements = $entry.disagreements[-10..-1] }
  }
  $null = Save-FlyoutKnowledge -Knowledge $kb -Path $KnowledgePath

  return [pscustomobject]@{
    Key = $key; FastPath = $fast; Verdicts = $verdicts; Agreed = ($distinct.Count -eq 1)
    Final = $verdicts[$verdicts.Count - 1]; Unstable = $unstable
    Region = $(if ($lastRegion) { $lastRegion } else { $null }); PeakRatio = $lastPeak
    Confidence = $(if ($entry) { $entry.confidence } else { 0 })
    KnowledgePath = (Get-FlyoutKnowledgePath -Path $KnowledgePath)
  }
}
