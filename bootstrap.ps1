#requires -Version 5.1
<#
.SYNOPSIS
    Prepares a Windows host for Ansible management over WinRM.
.DESCRIPTION
    Creates or updates a local automation account, adds it to the local
    Administrators group, configures WinRM for Ansible over HTTP with NTLM,
    and installs an Ansible-compatible Windows upgrader script.
.NOTES
    Run from an elevated PowerShell session. HTTP WinRM with NTLM protects
    credentials and message contents, but should only be exposed to trusted
    management networks. For untrusted networks, configure WinRM over HTTPS.
#>

[CmdletBinding()]
param(
    [string]$UpgraderUrl = 'https://raw.githubusercontent.com/Michdo93/ansible-windows-bootstrap/main/upgrader.ps1',
    [string]$InstallDirectory = "$env:ProgramData\Ansible"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'This script must be run from an elevated PowerShell session (Run as administrator).'
}

Write-Host '=== Ansible Windows Bootstrap ===' -ForegroundColor Cyan

$accountName = (Read-Host 'Local Ansible username').Trim()
if ([string]::IsNullOrWhiteSpace($accountName) -or $accountName -match '[\\/@"]') {
    throw 'Enter a valid local username (do not include a domain or computer name).'
}
if ($accountName.Length -gt 20) {
    Write-Warning 'For maximum compatibility, use a local account name of 20 characters or fewer.'
}

$securePassword = Read-Host "Password for local account '$accountName'" -AsSecureString
if ($securePassword.Length -eq 0) {
    throw 'The password must not be empty.'
}
$confirmPassword = Read-Host 'Confirm password' -AsSecureString
$ptr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$ptr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)
try {
    $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr1)
    $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr2)
    if ($plain1 -cne $plain2) {
        throw 'The passwords do not match.'
    }
}
finally {
    if ($ptr1 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr1) }
    if ($ptr2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2) }
    Remove-Variable plain1, plain2 -ErrorAction SilentlyContinue
}

# Create or update the local account.
$user = Get-LocalUser -Name $accountName -ErrorAction SilentlyContinue
if ($null -eq $user) {
    New-LocalUser -Name $accountName -Password $securePassword `
        -Description 'Local account for Ansible automation' `
        -PasswordNeverExpires:$false | Out-Null
    Write-Host "Created local user '$accountName'." -ForegroundColor Green
}
else {
    Set-LocalUser -Name $accountName -Password $securePassword
    Enable-LocalUser -Name $accountName
    Write-Host "Updated password and enabled existing local user '$accountName'." -ForegroundColor Yellow
}

# Administrators membership is required for general system maintenance and Windows Update.
$administratorsGroup = (Get-LocalGroup -SID 'S-1-5-32-544').Name
$member = Get-LocalGroupMember -Group $administratorsGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "$env:COMPUTERNAME\$accountName" -or $_.Name -eq $accountName }
if (-not $member) {
    Add-LocalGroupMember -Group $administratorsGroup -Member $accountName
}
Write-Host "Ensured '$accountName' is a member of '$administratorsGroup'." -ForegroundColor Green

# Configure WinRM. NTLM provides message encryption over HTTP; do not enable Basic
# authentication or AllowUnencrypted traffic.
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

# Ensure the standard HTTP listener exists. Enable-PSRemoting normally creates it.
$listeners = Get-ChildItem WSMan:\localhost\Listener
$httpListener = $listeners | Where-Object {
    (Get-Item -Path "$($_.PSPath)\Port" -ErrorAction SilentlyContinue).Value -eq 5985
}
if (-not $httpListener) {
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address '*' -Force | Out-Null
}

# Allow remote administrative tokens for local accounts over WinRM.
# This is needed on some Windows configurations for local administrator accounts
# to perform elevated operations remotely. Restrict WinRM to trusted management hosts.
$uacPath = 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System'
New-Item -Path $uacPath -Force | Out-Null
New-ItemProperty -Path $uacPath -Name 'LocalAccountTokenFilterPolicy' -PropertyType DWord -Value 1 -Force | Out-Null

# Ensure the firewall rule is enabled for the current network profile.
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue

# Download the Ansible-oriented upgrader script.
New-Item -Path $InstallDirectory -ItemType Directory -Force | Out-Null
$destination = Join-Path $InstallDirectory 'upgrader.ps1'
Write-Host "Downloading upgrader script from $UpgraderUrl" -ForegroundColor Cyan
Invoke-WebRequest -Uri $UpgraderUrl -OutFile $destination -UseBasicParsing
if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "Failed to install upgrader script at $destination"
}
Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Bootstrap completed.' -ForegroundColor Green
Write-Host "Ansible user: $env:COMPUTERNAME\$accountName"
Write-Host 'WinRM endpoint: HTTP / TCP 5985 (NTLM recommended for local accounts)'
Write-Host "Upgrader script: $destination"
Write-Host ''
Write-Warning 'Restrict TCP 5985 to trusted management hosts/subnets in your firewall. Use WinRM HTTPS on untrusted networks.'
Write-Host 'Test from the Ansible controller before deploying to additional hosts.'
