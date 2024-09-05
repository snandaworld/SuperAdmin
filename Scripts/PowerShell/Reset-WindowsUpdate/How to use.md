# Reset-Windows-update
A shell script to install Reset Windows update 
This will fix corrupted Windows update.
# To use this script:

Open Terminal and run the following command:
```
$scriptUrl = "https://raw.githubusercontent.com/snandaworld/SuperAdmin/master/Scripts/PowerShell/Reset-WindowsUpdate/Reset-WindowsUpdate.ps1"
$response = Invoke-WebRequest -Uri $scriptUrl
$script = New-Item -Path $env:Temp -ItemType File -Name "ResetWindowsUpdate.ps1" -Value $response.Content -Force
$scriptpath = $env:Temp+"\"+$script.Name
Invoke-Expression -Command $scriptpath
if (Test-Path -Path $scriptpath) {
    Remove-Item -Path $scriptpath -Force
    Write-Host "Reset successfully."
} else {
    Write-Host "Error"
}

```

The script will take care of the installation process for you

