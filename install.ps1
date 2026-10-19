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

    # Check the package against its own MANIFEST.txt before touching the
    # installed skills. A truncated download or a hand-edited copy should fail
    # here, loudly, instead of surfacing days later as an unexplained crash.
    # Skipped when someone installs a bare skills\ folder with no tools next to it.
    $pkgRoot = Split-Path -Parent $src
    $verify = Join-Path $pkgRoot 'tools\manifest.ps1'
    if ((Test-Path (Join-Path $pkgRoot 'MANIFEST.txt')) -and (Test-Path $verify)) {
        Write-Host ("verifying " + (Join-Path $pkgRoot 'MANIFEST.txt'))
        # manifest.ps1 ends with `exit 1` on a problem; run it in its own
        # process so that `exit` cannot take this script down with it.
        $vout = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Mode verify -Root $pkgRoot 2>&1
        $vout | ForEach-Object { Write-Host ("  " + $_) }
        if ($LASTEXITCODE -ne 0) { throw ("package failed MANIFEST verification: " + $pkgRoot) }
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    # Per-skill user state that survives an upgrade. Anything not listed here
    # comes from the package, so a *shipped* file can never be shadowed for
    # ever by the previous copy (the whole data\ folder used to be carried
    # over, which froze the old clarify-knowledge.md in place). Curated docs
    # now live in references\; data\ is state.
    $keepState = @{
        'windows-gui-control' = @('data', 'knowledge')
        'clarify-before-act'  = @('knowledge', 'data\clarify-log.json')
    }

    Get-ChildItem -Path $src -Directory | ForEach-Object {
        $name = $_.Name
        $target = Join-Path $dest $name
        $tag = [guid]::NewGuid().ToString('N').Substring(0, 6)
        $stage = Join-Path $dest ('.new-' + $name + '-' + $tag)
        $backup = Join-Path $dest ('.bak-' + $name + '-' + $tag)

        # Build the new copy in a staging folder first. The previous version
        # deleted the installed skill before copying, so a failed copy (disk
        # full, locked file, Ctrl+C) left nothing behind and there was no way
        # back. Now the old folder is only renamed after the copy succeeded.
        $keep = @('knowledge')
        if ($keepState.ContainsKey($name)) { $keep = $keepState[$name] }

        try {
            Copy-Item -Path $_.FullName -Destination $stage -Recurse -Force

            # Carry over the few paths that are genuinely per-machine state.
            if (Test-Path $target) {
                foreach ($rel in $keep) {
                    $p = Join-Path $target $rel
                    if (-not (Test-Path $p)) { continue }
                    $s = Join-Path $stage $rel
                    $parent = Split-Path -Parent $s
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    if (Test-Path $s) { Remove-Item $s -Recurse -Force }
                    Copy-Item -Path $p -Destination $s -Recurse -Force
                    Write-Host ("  kept user state: " + $name + "\" + $rel)
                }
                Rename-Item -Path $target -NewName (Split-Path $backup -Leaf)
            }
            Rename-Item -Path $stage -NewName $name
        } catch {
            # Put the previous version back before surfacing the error.
            if (Test-Path $backup) { Rename-Item -Path $backup -NewName $name }
            throw
        } finally {
            # Neither scratch folder may outlive this skill: a leftover
            # .new-*/  .bak-* is what the round-5 review found, and the
            # `finally` around the whole script only cleaned %TEMP%.
            if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $backup) {
                Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $backup) { Write-Warning ("backup left behind (locked file?): " + $backup) }
            }
        }
        Write-Host ("  installed " + $name)
    }
    Write-Host ""
    Write-Host "done -> $dest"
    Write-Host "the skill catalog refreshes in the same session; npm plugins are the ones that need a restart"
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
