# uninstall-githubdesktop.ps1
# Uninstalls GitHub Desktop (Squirrel per-user + MSI if present) and removes desktop shortcuts.
# Exit 0 on success / not present; Exit 1 on hard failure.

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Host "[GitHubDesktop-Uninstall] $Message"
}

function Remove-ShortcutIfExists {
    param([string]$Path)

    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Write-Log "Removed shortcut: $Path"
            return $true
        }
        catch {
            Write-Log "Failed to remove shortcut: $Path - $($_.Exception.Message)"
        }
    }
    return $false
}

function Remove-GitHubDesktopShortcuts {
    Write-Log "Removing GitHub Desktop desktop shortcuts (if present)..."

    # Common shortcut display names
    $shortcutNames = @(
        "GitHub Desktop.lnk",
        "GitHubDesktop.lnk"
    )

    # Public desktop (all users)
    foreach ($name in $shortcutNames) {
        Remove-ShortcutIfExists -Path (Join-Path $env:PUBLIC "Desktop\$name") | Out-Null
    }

    # Per-user desktops (including OneDrive redirected desktops)
    $usersRoot = "C:\Users"
    if (Test-Path $usersRoot) {
        Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $profilePath = $_.FullName

            $desktopPaths = @(
                Join-Path $profilePath "Desktop",
                Join-Path $profilePath "OneDrive\Desktop"
            )

            foreach ($desktop in $desktopPaths) {
                foreach ($name in $shortcutNames) {
                    Remove-ShortcutIfExists -Path (Join-Path $desktop $name) | Out-Null
                }
            }
        }
    }

    Write-Log "Shortcut cleanup complete."
}

function Uninstall-SquirrelPerUser {
    # GitHub Desktop often uses Squirrel (per-user) and can be removed using:
    # %LocalAppData%\GitHubDesktop\Update.exe --uninstall --silent

    $usersRoot = "C:\Users"
    if (-not (Test-Path $usersRoot)) { return $false }

    $foundAny = $false
    $uninstalledAny = $false

    Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $profilePath = $_.FullName
        $updateExe = Join-Path $profilePath "AppData\Local\GitHubDesktop\Update.exe"

        if (Test-Path $updateExe) {
            $foundAny = $true
            Write-Log "Found per-user Update.exe at: $updateExe"

            try {
                $p = Start-Process -FilePath $updateExe -ArgumentList "--uninstall", "--silent" `
                    -PassThru -Wait -WindowStyle Hidden
                Write-Log "Uninstall ran for profile '$($_.Name)' exit code: $($p.ExitCode)"
                $uninstalledAny = $true
            }
            catch {
                Write-Log "Failed running Update.exe uninstall for profile '$($_.Name)': $($_.Exception.Message)"
                # Continue trying other profiles / MSI method
            }
        }
    }

    if (-not $foundAny) {
        Write-Log "No per-user Squirrel installs found under $usersRoot"
    }

    return $uninstalledAny
}

function Find-MsiUninstallEntries {
    # MSI uninstall info is typically in HKLM uninstall keys
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $matches = foreach ($p in $paths) {
        Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.DisplayName -like "GitHub Desktop*") -or
                ($_.Publisher -like "*GitHub*")
            } |
            Select-Object DisplayName, DisplayVersion, Publisher, UninstallString, PSChildName
    }

    return $matches
}