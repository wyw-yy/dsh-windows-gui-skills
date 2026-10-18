# Install the bundled Agent Skills into the user-level skill folder.
# No npm, no DSH plugin: just files in %USERPROFILE%\.agents\skills\.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Re-running upgrades in place. Start a NEW agent session afterwards so the
# skill catalog is reloaded.

$ErrorActionPreference = 'Stop'

$repo = 'wyw-yy/dsh-windows-gui-skills'
$dest = Join-Path $env:USERPROFILE '.agents\skills'
$tmp  = Join-Path $env:TEMP ('dsh-wgsk-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp 'repo.zip'
    $url = "https://github.com/$repo/archive/refs/heads/main.zip"
    Write-Host "downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    $src = Join-Path $tmp 'dsh-windows-gui-skills-main\skills'
    if (-not (Test-Path $src)) { throw "skills folder missing in archive: $src" }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -Path $src -Directory | ForEach-Object {
        $target = Join-Path $dest $_.Name
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Copy-Item -Path $_.FullName -Destination $target -Recurse -Force
        Write-Host ("  installed " + $_.Name)
    }
    Write-Host ""
    Write-Host "done -> $dest"
    Write-Host "start a new session to reload the catalog"
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
