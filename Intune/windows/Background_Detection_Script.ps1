$FilePath = "C:\Windows\Web\Wallpaper\DesktopWallpaper.jpg"

if (Test-Path $FilePath) {
    Write-Output "File detected: $FilePath"
    exit 1
} else {
    Write-Output "File not found."
    exit 0
}