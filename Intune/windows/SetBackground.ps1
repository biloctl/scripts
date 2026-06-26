$WallpaperPath = "C:\Windows\Web\Wallpaper\DesktopWallpaper.jpg"
$RegistryPath = "HKCU:\Control Panel\Desktop"

Set-ItemProperty -Path $RegistryPath -Name Wallpaper -Value $WallpaperPath
Set-ItemProperty -Path $RegistryPath -Name WallpaperStyle -Value 2  # 2 = Stretch, 0 = Tile, 1 = Center

RUNDLL32.EXE USER32.DLL,UpdatePerUserSystemParameters

New-Item -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BackgroundAppInstalled.txt" -ItemType File -Force > $null 2>&1
