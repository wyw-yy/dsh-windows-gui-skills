# Generate or verify MANIFEST.txt (SHA-256 of every shipped file).
#
#   powershell -ExecutionPolicy Bypass -File tools\manifest.ps1 -Mode gen
#   powershell -ExecutionPolicy Bypass -File tools\manifest.ps1 -Mode verify
#   ... -Root <path>   check another copy (installed skills, a zipped delivery, ...)
#
# Line endings are normalised to LF before hashing. Two files in this package
# (SKILL.md files with CRLF) used to hash differently depending on how git checked
# them out, so a clean package could report "mismatch" on Linux/CI. Normalising
# both when writing and when verifying makes the manifest checkout-independent.
#
# Excluded: .git, MANIFEST.txt itself, knowledge/ and data/ (per-machine user state).

[CmdletBinding()]
param(
    [ValidateSet('gen', 'verify')][string]$Mode = 'verify',
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path
$manifest = Join-Path $Root 'MANIFEST.txt'

$excludeDir = @('.git', 'node_modules', '__pycache__', 'knowledge', 'data')

function Get-Files {
    Get-ChildItem -Path $Root -Recurse -File -Force |
        Where-Object {
            $rel = $_.FullName.Substring($Root.Length + 1)
            $parts = $rel -split '[\\/]'
            $bad = $false
            foreach ($p in $parts[0..([math]::Max(0, $parts.Count - 2))]) {
                if ($excludeDir -contains $p) { $bad = $true }
            }
            (-not $bad) -and ($rel -ne 'MANIFEST.txt')
        } |
        Sort-Object FullName
}

function Get-NormHash([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $norm = $text -replace "`r`n", "`n"
    $nb = [System.Text.Encoding]::UTF8.GetBytes($norm)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($nb) } finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-Rel([string]$path) {
    return ($path.Substring($Root.Length + 1) -replace '\\', '/')
}

if ($Mode -eq 'gen') {
    $lines = foreach ($f in Get-Files) { (Get-NormHash $f.FullName) + '  ' + (Get-Rel $f.FullName) }
    [System.IO.File]::WriteAllText($manifest, (($lines -join "`n") + "`n"), $utf8)
    Write-Output ("wrote " + $manifest + "  files=" + @($lines).Count)
    return
}

if (-not (Test-Path $manifest)) { throw "no MANIFEST.txt in $Root (run -Mode gen first)" }

$want = @{}
foreach ($line in [System.IO.File]::ReadAllLines($manifest)) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -eq 2) { $want[$parts[1].Trim()] = $parts[0].Trim() }
}

$bad = 0; $checked = 0
foreach ($f in Get-Files) {
    $rel = Get-Rel $f.FullName
    $checked++
    if (-not $want.ContainsKey($rel)) { Write-Output ("  MISSING IN MANIFEST  " + $rel); $bad++; continue }
    $got = Get-NormHash $f.FullName
    if ($got -ne $want[$rel]) { Write-Output ("  MISMATCH  " + $rel); $bad++ }
}
foreach ($k in $want.Keys) {
    if (-not (Test-Path (Join-Path $Root ($k -replace '/', '\')))) { Write-Output ("  FILE GONE  " + $k); $bad++ }
}
Write-Output ("checked " + $checked + " files, " + $bad + " problem(s)")
if ($bad -gt 0) { exit 1 }
