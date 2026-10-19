# Install the bundled Agent Skills into a skill folder.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Dest D:\tmp\skills -Source .\skills
#
# Default target is %USERPROFILE%\.agents\skills\. `-Dest` installs somewhere
# else (a scratch folder, a project-level `<root>\.agents\skills`, ...) and
# `-Source` installs from a local `skills\` tree instead of downloading main.zip,
# so a package can be tried before it is pushed.
#
# Re-running upgrades the skills and KEEPS the local knowledge bases: the
# per-skill `data\` and `knowledge\` folders are copied aside before the old
# folder is replaced and put back afterwards. The skill catalog refreshes during
# the same session; only npm plugins need a new session.

[CmdletBinding()]
param(
    [string]$Dest = '',
    [string]$Source = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Dest) { $Dest = Join-Path $env:USERPROFILE '.agents\skills' }
$dest = $Dest

$repo = 'wyw-yy/dsh-windows-gui-skills'
$tmp  = Join-Path $env:TEMP ('dsh-wgsk-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    if ($Source) {
        $src = Join-Path $Source 'skills'
        if (-not (Test-Path $src)) { $src = $Source }   # allow pointing straight at skills\
        if (-not (Test-Path $src)) { throw "no skills folder under -Source: $Source" }
        Write-Host "installing from $src"
    } else {
        $zip = Join-Path $tmp 'repo.zip'
        $url = "https://github.com/$repo/archive/refs/heads/main.zip"
        Write-Host "downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Join-Path $tmp 'dsh-windows-gui-skills-main\skills'
        if (-not (Test-Path $src)) { throw "skills folder missing in archive: $src" }
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -Path $src -Directory | ForEach-Object {
        $target = Join-Path $dest $_.Name
        # `data\` and `knowledge\` are gitignored user state: back them up before
        # replacing the folder, then restore them on top of the new version.
        $keep = @()
        if (Test-Path $target) {
            foreach ($sub in @('data', 'knowledge')) {
                $p = Join-Path $target $sub
                if (Test-Path $p) {
                    $bak = Join-Path $tmp ("keep_" + $_.Name + "_" + $sub)
                    Copy-Item -Path $p -Destination $bak -Recurse -Force
                    $keep += [pscustomobject]@{ Rel = $sub; Bak = $bak }
                }
            }
            Remove-Item $target -Recurse -Force
        }
        Copy-Item -Path $_.FullName -Destination $target -Recurse -Force
        foreach ($k in $keep) {
            $p = Join-Path $target $k.Rel
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
            Copy-Item -Path $k.Bak -Destination $p -Recurse -Force
            Write-Host ("  kept user state: " + $_.Name + "\" + $k.Rel)
        }
        Write-Host ("  installed " + $_.Name)
    }
    Write-Host ""
    Write-Host "done -> $dest"
    Write-Host "the skill catalog refreshes in the same session; npm plugins are the ones that need a restart"
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
