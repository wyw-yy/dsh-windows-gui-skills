# clarify.ps1 - advisory memory for the clarify-before-act skill.
# ASCII only (Windows PowerShell 5.1 reads .ps1 as ANSI).
# Nothing here blocks anything: it only records what happened and reports patterns.

$script:ClarifyRoot = Split-Path -Parent $PSScriptRoot
$script:ClarifyDataDir = Join-Path $script:ClarifyRoot 'data'
$script:ClarifyLog = Join-Path $script:ClarifyDataDir 'clarify-log.json'

function Initialize-ClarifyStore {
  if (-not (Test-Path $script:ClarifyDataDir)) {
    New-Item -ItemType Directory -Path $script:ClarifyDataDir -Force | Out-Null
  }
  if (-not (Test-Path $script:ClarifyLog)) {
    [System.IO.File]::WriteAllText($script:ClarifyLog, '[]', (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Read-ClarifyLog {
  Initialize-ClarifyStore
  try {
    $raw = [System.IO.File]::ReadAllText($script:ClarifyLog, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) { return @() }
    return @($data)
  } catch {
    Write-Warning ("clarify log unreadable, starting fresh: " + $_.Exception.Message)
    return @()
  }
}

function Save-ClarifyLog {
  param([object[]]$Records)
  Initialize-ClarifyStore
  $trimmed = @($Records | Select-Object -Last 500)
  $json = ConvertTo-Json -InputObject $trimmed -Depth 6
  if ($trimmed.Count -eq 0) { $json = '[]' }
  if ($trimmed.Count -eq 1) { $json = '[' + (ConvertTo-Json -InputObject $trimmed[0] -Depth 6) + ']' }
  [System.IO.File]::WriteAllText($script:ClarifyLog, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-ClarifyRecord {
  <#
    Records one decision point. Outcome values:
      helped  - the answers changed the plan for the better
      wasted  - the questions were unnecessary or annoyed the user
      blocked - the answer was "I don't know yet", work paused
      none    - asked nothing, assumptions were right
      wrong   - asked nothing, assumptions were wrong and had to be fixed
  #>
  param(
    [Parameter(Mandatory = $true)][string]$Task,
    [string]$Domain = 'general',
    [int]$AskedCount = 0,
    [int]$AnsweredCount = 0,
    [string[]]$Assumptions = @(),
    [ValidateSet('helped', 'wasted', 'blocked', 'none', 'wrong', 'unknown')]
    [string]$Outcome = 'unknown',
    [string]$Notes = ''
  )
  $records = Read-ClarifyLog
  $rec = [pscustomobject]@{
    ts            = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    task          = $Task
    domain        = $Domain
    asked         = $AskedCount
    answered      = $AnsweredCount
    assumptions   = @($Assumptions)
    outcome       = $Outcome
    notes         = $Notes
  }
  $records = @($records) + @($rec)
  Save-ClarifyLog -Records $records
  Write-Output ("recorded: {0} [{1}] asked={2} outcome={3}" -f $Task, $Domain, $AskedCount, $Outcome)
}

function Get-ClarifyRecords {
  param([int]$SinceDays = 0, [string]$Domain = '')
  $records = Read-ClarifyLog
  if ($SinceDays -gt 0) {
    $cut = (Get-Date).AddDays(-$SinceDays)
    $records = @($records | Where-Object { [datetime]$_.ts -ge $cut })
  }
  if ($Domain) {
    $records = @($records | Where-Object { $_.domain -eq $Domain })
  }
  return @($records)
}

function Get-ClarifyStats {
  param([int]$SinceDays = 90)
  $records = Get-ClarifyRecords -SinceDays $SinceDays
  if ($records.Count -eq 0) {
    Write-Output "no records yet (advisory only: this changes nothing about how you work)"
    return
  }
  $rows = @()
  foreach ($g in ($records | Group-Object domain)) {
    $helped = @($g.Group | Where-Object { $_.outcome -eq 'helped' }).Count
    $wasted = @($g.Group | Where-Object { $_.outcome -eq 'wasted' }).Count
    $wrong = @($g.Group | Where-Object { $_.outcome -eq 'wrong' }).Count
    $none = @($g.Group | Where-Object { $_.outcome -eq 'none' }).Count
    $asked = @($g.Group | Measure-Object -Property asked -Average).Average
    $rows += [pscustomobject]@{
      Domain   = $g.Name
      N        = $g.Count
      Helped   = $helped
      Wasted   = $wasted
      WrongGuess = $wrong
      Silent   = $none
      AvgAsked = [math]::Round($asked, 1)
    }
  }
  $rows | Sort-Object N -Descending | Format-Table -AutoSize
  Write-Output ""
  Write-Output "How to read this (advisory only, never a rule):"
  Write-Output "  Helped high / Wasted 0  -> asking in this domain usually pays off"
  Write-Output "  Wasted high             -> this domain dislikes questions, act and state assumptions"
  Write-Output "  WrongGuess high         -> your silent assumptions in this domain keep being wrong"
  Write-Output "  older than 90 days      -> treat as stale, re-learn"
}

function Get-ClarifyAdvice {
  param([Parameter(Mandatory = $true)][string]$Task, [int]$Top = 3, [int]$SinceDays = 180)
  $records = Get-ClarifyRecords -SinceDays $SinceDays
  if ($records.Count -eq 0) {
    Write-Output "no history for this kind of task (advisory only)"
    return
  }
  $terms = @(($Task.ToLower() -split '[^0-9a-z\u4e00-\u9fff]+') | Where-Object { $_.Length -ge 2 })
  $scored = foreach ($r in $records) {
    $text = ("" + $r.task + " " + $r.domain + " " + $r.notes).ToLower()
    $hits = 0
    foreach ($t in $terms) { if ($text.Contains($t)) { $hits++ } }
    if ($hits -gt 0) {
      [pscustomobject]@{ Score = $hits; Record = $r }
    }
  }
  if (-not $scored) {
    Write-Output "no similar task in the log (advisory only)"
    return
  }
  $top2 = @($scored | Sort-Object -Property Score -Descending | Select-Object -First $Top)
  foreach ($s in $top2) {
    $r = $s.Record
    Write-Output ("[{0}] {1} | domain={2} asked={3} outcome={4}" -f $r.ts, $r.task, $r.domain, $r.asked, $r.outcome)
    if ($r.assumptions -and @($r.assumptions).Count -gt 0) {
      Write-Output ("    assumptions: " + ((@($r.assumptions)) -join '; '))
    }
    if ($r.notes) { Write-Output ("    notes: " + $r.notes) }
  }
  Write-Output ""
  Write-Output "Advisory only - past records do not decide this turn. If the user already answered, do not ask again."
}
