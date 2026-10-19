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
        $name = $_.Name
        $target = Join-Path $dest $name
        $tag = [guid]::NewGuid().ToString('N').Substring(0, 6)
        $stage = Join-Path $dest ('.new-' + $name + '-' + $tag)
        $backup = Join-Path $dest ('.bak-' + $name + '-' + $tag)

        # Build the new copy in a staging folder first. The previous version
        # deleted the installed skill before copying, so a failed copy (disk
        # full, locked file, Ctrl+C) left nothing behind and there was no way
        # back. Now the old folder is only renamed after the copy succeeded.
        Copy-Item -Path $_.FullName -Destination $stage -Recurse -Force

        # `data\` and `knowledge\` are gitignored user state: carry them over
        # from the installed skill on top of the fresh copy.
        if (Test-Path $target) {
            foreach ($sub in @('data', 'knowledge')) {
                $p = Join-Path $target $sub
                if (Test-Path $p) {
                    $s = Join-Path $stage $sub
                    if (Test-Path $s) { Remove-Item $s -Recurse -Force }
                    Copy-Item -Path $p -Destination $s -Recurse -Force
                    Write-Host ("  kept user state: " + $name + "\" + $sub)
                }
            }
            Rename-Item -Path $target -NewName (Split-Path $backup -Leaf)
        }
        try {
            Rename-Item -Path $stage -NewName $name
        } catch {
            # Put the previous version back before surfacing the error.
            if (Test-Path $backup) { Rename-Item -Path $backup -NewName $name }
            throw
        }
        if (Test-Path $backup) { Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host ("  installed " + $name)
    }
    Write-Host ""
    Write-Host "done -> $dest"
    Write-Host "the skill catalog refreshes in the same session; npm plugins are the ones that need a restart"
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
