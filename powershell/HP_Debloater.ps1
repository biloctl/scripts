$apps = @(
    # HP Bloatware
    "HP Connection Optimizer"
    "HP Documentation"
    "HP Notifications"
    "HP Sure Run Module"
    "HP Sure Recover"
    "MicrosoftTeams"
    "MSTeams"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.OutlookForWindows"
    "Microsoft.GamingApp"
    "Microsoft.Xbox.TCUI"
    "Microsoft.MicrosoftSolitaireCollection"
    "MicrosoftCorporationII.MicrosoftFamily"
    "MicrosoftCorporationII.QuickAssist"
    "Poly Lens"

    "AD2F1837.HPEasyClean"
    "AD2F1837.HPPCHardwareDiagnosticsWindows"
    "AD2F1837.HPPowerManager"
    "AD2F1837.HPPrivacySettings"
    "AD2F1837.HPQuickDrop"
    "AD2F1837.HPSupportAssistant"
    "AD2F1837.myHP"
    "AD2F1837.HPSystemInformation"
)

$ConnOpt = "[InstallShield Silent]
Version=v7.00
File=Response File
[File Transfer]
OverwrittenReadOnly=NoToAll
[{6468C4A5-E47E-405F-B675-A70A70983EA6}-DlgOrder]
Dlg0={6468C4A5-E47E-405F-B675-A70A70983EA6}-SdWelcomeMaint-0
Count=3
Dlg1={6468C4A5-E47E-405F-B675-A70A70983EA6}-MessageBox-0
Dlg2={6468C4A5-E47E-405F-B675-A70A70983EA6}-SdFinishReboot-0
[{6468C4A5-E47E-405F-B675-A70A70983EA6}-SdWelcomeMaint-0]
Result=303
[{6468C4A5-E47E-405F-B675-A70A70983EA6}-MessageBox-0]
Result=6
[Application]
Name=HP Connection Optimizer
Version=2.0.18.0
Company=HP Inc.
Lang=0409
[{6468C4A5-E47E-405F-B675-A70A70983EA6}-SdFinishReboot-0]
Result=1
BootOption=0"

$appxprovisionedpackages = Get-AppxProvisionedPackage -Online

foreach ($app in $apps) {
    Write-Output "Trying to remove $app"

    # remove appx packages
    if ((Get-AppxPackage -AllUsers).Name -eq "$app") {
        Get-AppxPackage $app -AllUsers | Remove-AppxPackage -AllUsers | Out-Null
        if ($?) {
            Write-Host "    Successfully removed AppX-Package $app"
            Continue
        } else {
            Write-Host "    Failed to remove AppX-Package $app"
            Continue
        }

        ($appxprovisionedpackages).Where( {$_.DisplayName -EQ $app}) |
            Remove-AppxProvisionedPackage -Online
        if (!$?) {
            Write-Host "    Failed to remove AppX-ProvisionedPackage $app"
        } else {
            Write-Host "    Removed AppX-ProvisionedPackage $app"
        }
        Continue
    }

    # remove normal packages
    Get-Package -Name $app -ErrorAction SilentlyContinue | Out-Null
    if ($?) {
        Uninstall-Package -Name $app -AllVersions -Force
        if (!$?) {
            Write-Host "Failed to remove $app"
        } else {
            # in some cases uninstall command returns a successfull but doesnt actually uninstall the Package
            # as a last effort i try to remove the Package using the UninstallString
            Get-Package -Name $item -ErrorAction SilentlyContinue | Out-Null
            if ($?) {
                Write-Host "    Trying via Uninstallstring"
                # remove Programms via uninstallString because Remove-Package doesnt work :(
                if ($app -eq "HP Documentation") {
                    try {
                        $uninstallString = "C:\Program Files\HP\Documentation\Doc_uninstall.cmd"
                        Start-Process -FilePath "$uninstallString" -NoNewWindow
                        Write-Host "    Successfully removed HP Documentation via uninstall string"
                    } catch {
                        Write-Host "    Failed to remove HP Documentation via uninstall string"
                    }
                } elseif ($app -eq "HP Connection Optimizer") {
                    try {
                        $ConnOpt | Out-File c:\Windows\Temp\ISS-HP.iss
                        &'C:\Program Files (x86)\InstallShield Installation Information\{6468C4A5-E47E-405F-B675-A70A70983EA6}\setup.exe' @('-s', '-f1C:\Windows\Temp\ISS-HP.iss')
                        
                        Write-Host "    Successfully removed HP Connection Optimizer via uninstallfile"
                    } catch {
                        Write-Host "    Couldnt create uninstallfile for HP Connection Optimizer"
                    }
                }
            }   
        }
    }
}

$apps2 = @(
 # Bloatware
    "HP Wolf Security"
    "HP Wolf Security - Console"
    "HP Security Update Service"
    "HP Wolf Security Application Support for Sure Sense"
)
foreach ($app2 in $apps2) {
 # remove normal packages
    Get-Package -Name $app2 -ErrorAction SilentlyContinue | Out-Null
    if ($?) {
        Uninstall-Package -Name $app2 -AllVersions -Force
        if (!$?) {
            Write-Host "Failed to remove $app2"
        } else {Write-Host "    Removed Uninstall-Package -Name $app2"
        }
    }
}

# Removing HP Wolf Security Application*
Get-Package | Where-Object Name -Like "*HP Wolf Security Application*" | Uninstall-Package -AllVersions -Force
Write-Host "Removing HP Security Applications"

# Removing HP System Information. Comment out if want to include this
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "AD2F1837.HPSystemInformation"} | Remove-AppxProvisionedPackage -Online
Write-Host "Removed HP System Information"

# Uninstall Retail M365
$UninstallString = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\O365HomePremRetail - en-us").UninstallString
$UninstallEXE = ($UninstallString -split '"')[1]
$UninstallArg = ($UninstallString -split '"')[2] + " DisplayLevel=False ForceAppShutdown=True"
 
Start-Process -FilePath $UninstallEXE -ArgumentList $UninstallArg -Wait
Write-Host "Preloaded Microsoft 365 Uninstalled"

# Uninstall Retail OneNote
$UninstallString = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneNoteFreeRetail - en-us").UninstallString
$UninstallEXE = ($UninstallString -split '"')[1]
$UninstallArg = ($UninstallString -split '"')[2] + " DisplayLevel=False ForceAppShutdown=True"
 
Start-Process -FilePath $UninstallEXE -ArgumentList $UninstallArg -Wait
Write-Host "Preloaded OneNote Uninstalled"



Write-Host "Debloating Complete. Continue Autopilot process by logging into ESP with the user's credentials"