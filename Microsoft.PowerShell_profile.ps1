### PowerShell Profile
### Version 2.00 - Fixed & Refactored

#region --- Helpers ---

function Test-CommandExists {
    param($command)
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

#endregion

#region --- Connectivity Check ---

# Quick GitHub connectivity check (1 second timeout)
$global:canConnectToGitHub = try {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $reached = $tcp.ConnectAsync('github.com', 443).Wait(1000)
    $tcp.Close()
    $reached
} catch { $false }

#endregion

#region --- Module Imports ---

# Terminal-Icons
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Write-Host "Installing Terminal-Icons module..." -ForegroundColor Cyan
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module -Name Terminal-Icons

# Chocolatey profile (if present)
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module "$ChocolateyProfile"
}

#endregion

#region --- oh-my-posh ---

if (-not (Test-CommandExists oh-my-posh)) {
    Write-Host "oh-my-posh not found. Installing..." -ForegroundColor Cyan
    try {
        winget install JanDeDobbeleer.OhMyPosh --source winget --accept-source-agreements --accept-package-agreements --silent
        Refresh-Path
        Write-Host "oh-my-posh installed successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to install oh-my-posh: $_"
    }
}

if (Test-CommandExists oh-my-posh) {
    oh-my-posh init pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/jandedobbeleer.omp.json | Invoke-Expression
} else {
    Write-Warning "oh-my-posh could not be loaded. Please restart PowerShell and try again."
}

#endregion

#region --- zoxide ---

if (-not (Test-CommandExists zoxide)) {
    Write-Host "zoxide not found. Installing..." -ForegroundColor Cyan
    try {
        winget install ajeetdsouza.zoxide --source winget --accept-source-agreements --accept-package-agreements --silent
        Refresh-Path
        Write-Host "zoxide installed successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to install zoxide: $_"
    }
}

if (Test-CommandExists zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
} else {
    Write-Warning "zoxide could not be loaded. Please restart PowerShell and try again."
}

#endregion

#region --- Profile Updates ---

function Update-Profile {
    if (-not $global:canConnectToGitHub) {
        Write-Host "Skipping profile update check (GitHub unreachable)." -ForegroundColor Yellow
        return
    }
    try {
        $url = "https://raw.githubusercontent.com/B8usap/powershell-profile/main/Microsoft.PowerShell_profile.ps1"
        $tmpFile = "$env:TEMP\Microsoft.PowerShell_profile.ps1"
        $oldhash = Get-FileHash $PROFILE
        Invoke-RestMethod $url -OutFile $tmpFile
        $newhash = Get-FileHash $tmpFile
        if ($newhash.Hash -ne $oldhash.Hash) {
            Copy-Item -Path $tmpFile -Destination $PROFILE -Force
            Write-Host "Profile updated. Please restart your shell." -ForegroundColor Magenta
        }
    } catch {
        Write-Warning "Unable to check for profile updates: $_"
    } finally {
        Remove-Item "$env:TEMP\Microsoft.PowerShell_profile.ps1" -ErrorAction SilentlyContinue
    }
}

Update-Profile

#endregion

#region --- PowerShell Updates ---

function Update-PowerShell {
    if (-not $global:canConnectToGitHub) {
        Write-Host "Skipping PowerShell update check (GitHub unreachable)." -ForegroundColor Yellow
        return
    }
    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $currentVersion = [Version]$PSVersionTable.PSVersion.ToString()
        $latestReleaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestVersion = [Version]$latestReleaseInfo.tag_name.TrimStart('v')

        if ($currentVersion -lt $latestVersion) {
            Write-Host "Updating PowerShell to $latestVersion..." -ForegroundColor Yellow
            winget upgrade Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell updated. Please restart your shell." -ForegroundColor Magenta
        } else {
            Write-Host "PowerShell is up to date ($currentVersion)." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to check for PowerShell updates: $_"
    }
}

Update-PowerShell

#endregion

#region --- Admin Check & Window Title ---

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function prompt {
    if ($isAdmin) { "[" + (Get-Location) + "] # " } else { "[" + (Get-Location) + "] $ " }
}

$adminSuffix = if ($isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell {0}$adminSuffix" -f $PSVersionTable.PSVersion.ToString()

#endregion

#region --- Editor Configuration ---

$EDITOR = if     (Test-CommandExists notepad++) { 'notepad++' }
          elseif (Test-CommandExists pvim)       { 'pvim' }
          elseif (Test-CommandExists vim)        { 'vim' }
          elseif (Test-CommandExists vi)         { 'vi' }
          elseif (Test-CommandExists code)       { 'code' }
          elseif (Test-CommandExists sublime_text) { 'sublime_text' }
          else   { 'notepad' }

Set-Alias -Name edit -Value $EDITOR -Force

function Edit-Profile { & $EDITOR $PROFILE }

#endregion

#region --- PSReadLine Colors ---

Set-PSReadLineOption -Colors @{
    Command   = 'Yellow'
    Parameter = 'Green'
    String    = 'DarkCyan'
}

#endregion

#region --- Utility Functions ---

function touch($file) { "" | Out-File $file -Encoding ASCII }

function ff($name) {
    Get-ChildItem -Recurse -Filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        "$($_.Directory)\$($_)"
    }
}

function Get-PubIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

function uptime {
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        Get-WmiObject win32_operatingsystem |
            Select-Object @{Name='LastBootUpTime'; Expression={$_.ConverttoDateTime($_.lastbootuptime)}} |
            Format-Table -HideTableHeaders
    } else {
        net statistics workstation | Select-String "since" | ForEach-Object {
            $_.ToString().Replace('Statistics since ', '')
        }
    }
}

function reload-profile { & $PROFILE }

function unzip($file) {
    Write-Output "Extracting $file to $pwd"
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}

function hb {
    if ($args.Length -eq 0) { Write-Error "No file path specified."; return }
    $FilePath = $args[0]
    if (-not (Test-Path $FilePath)) { Write-Error "File path does not exist."; return }
    $Content = Get-Content $FilePath -Raw
    try {
        $response = Invoke-RestMethod -Uri "http://bin.christitus.com/documents" -Method Post -Body $Content -ErrorAction Stop
        "http://bin.christitus.com/$($response.key)"
    } catch {
        Write-Error "Failed to upload. Error: $_"
    }
}

function grep($regex, $dir) {
    if ($dir) { Get-ChildItem $dir | Select-String $regex; return }
    $input | Select-String $regex
}

function df { Get-Volume }

function sed($file, $find, $replace) {
    (Get-Content $file).Replace("$find", $replace) | Set-Content $file
}

function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }

function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }

function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process }

function pgrep($name) { Get-Process $name }

function head { param($Path, $n = 10) Get-Content $Path -Head $n }

function tail { param($Path, $n = 10) Get-Content $Path -Tail $n }

function nf { param($name) New-Item -ItemType File -Path . -Name $name }

function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

#endregion

#region --- Navigation Shortcuts ---

function docs { Set-Location -Path $HOME\Documents }
function down { Set-Location -Path $HOME\Downloads }   # Fixed: was %HOME
function dtop { Set-Location -Path $HOME\Desktop }

#endregion

#region --- Git Shortcuts ---

function gs    { git status }
function ga    { git add . }
function gc    { param($m) git commit -m "$m" }
function gp    { git push }
function g     { z Github }

function gcom {
    git add .
    git commit -m "$args"
}

function lazyg {
    git add .
    git commit -m "$args"
    git push
}

#endregion

#region --- Process & System ---

function k9      { Stop-Process -Name $args[0] }
function sysinfo { Get-ComputerInfo }
function flushdns { Clear-DnsClientCache }

#endregion

#region --- Listing Aliases ---

function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

#endregion

#region --- Clipboard ---

function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

#endregion