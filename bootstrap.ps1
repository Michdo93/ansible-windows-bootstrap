#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Username,
    [string]$Password,
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
if (-not (Test-IsAdministrator)) { throw 'Run this script from elevated PowerShell (Run as administrator).' }
if ([string]::IsNullOrWhiteSpace($Username)) { $Username = (Read-Host 'Local Ansible username').Trim() }
if ([string]::IsNullOrWhiteSpace($Username) -or $Username -match '[\\/@"]') { throw 'Enter a valid local username.' }

if ([string]::IsNullOrEmpty($Password)) {
    $securePassword = Read-Host "Password for local account '$Username'" -AsSecureString
    $confirmPassword = Read-Host 'Confirm password' -AsSecureString
    $p1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $p2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)
    try {
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p1)
        $confirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p2)
        if ($Password -cne $confirmation) { throw 'The passwords do not match.' }
    } finally {
        if ($p1 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p1) }
        if ($p2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p2) }
        Remove-Variable confirmation -ErrorAction SilentlyContinue
    }
}
if ([string]::IsNullOrEmpty($Password)) { throw 'The password must not be empty.' }
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Password = $null

$user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if ($null -eq $user) {
    New-LocalUser -Name $Username -Password $securePassword -Description 'Local account for Ansible automation' -PasswordNeverExpires:$true | Out-Null
} else {
    Set-LocalUser -Name $Username -Password $securePassword -PasswordNeverExpires $true
    Enable-LocalUser -Name $Username
}
$administratorsGroup = (Get-LocalGroup -SID 'S-1-5-32-544').Name
$member = Get-LocalGroupMember -Group $administratorsGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$env:COMPUTERNAME\$Username" -or $_.Name -eq $Username }
if (-not $member) { Add-LocalGroupMember -Group $administratorsGroup -Member $Username }

# Install OpenSSH Server and configure automatic startup.
$sshCapability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($sshCapability.State -ne 'Installed') { Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null }
Get-Service -Name sshd -ErrorAction Stop | Out-Null
Set-Service -Name sshd -StartupType Automatic
$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
if (Test-Path -LiteralPath $sshdConfig) {
    $configLines = Get-Content -LiteralPath $sshdConfig
    $passwordAuthConfigured = $false
    $configLines = @($configLines | ForEach-Object {
        if ($_ -match '^\s*#?\s*PasswordAuthentication\s+') {
            $passwordAuthConfigured = $true
            'PasswordAuthentication yes'
        } else { $_ }
    })
    if (-not $passwordAuthConfigured) { $configLines += 'PasswordAuthentication yes' }
    Set-Content -LiteralPath $sshdConfig -Value $configLines -Encoding ascii
}
# Use Windows PowerShell as the default shell for interactive and remote SSH commands.
$openSshRegistryPath = 'HKLM:\SOFTWARE\OpenSSH'
New-Item -Path $openSshRegistryPath -Force | Out-Null
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) { throw "Windows PowerShell was not found at $powerShellPath" }
New-ItemProperty -Path $openSshRegistryPath -Name DefaultShell -Value $powerShellPath -PropertyType String -Force | Out-Null

$sshService = Get-Service -Name sshd
if ($sshService.Status -eq 'Running') {
    Restart-Service -Name sshd -Force
} else {
    Start-Service -Name sshd
}
$sshFirewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($sshFirewallRule) {
    Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
} else {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

# Keep WinRM available for Ansible Windows modules.
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
$uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-Item -Path $uacPath -Force | Out-Null
New-ItemProperty -Path $uacPath -Name 'LocalAccountTokenFilterPolicy' -PropertyType DWord -Value 1 -Force | Out-Null
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue

New-Item -Path $InstallDirectory -ItemType Directory -Force | Out-Null
$destination = Join-Path $InstallDirectory 'upgrader.ps1'
Invoke-WebRequest -Uri $UpgraderUrl -OutFile $destination -UseBasicParsing
if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Failed to install updater at $destination" }
Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue

Write-Host "Created/updated local administrator: $env:COMPUTERNAME\$Username"
Write-Host 'OpenSSH Server is installed and running with automatic startup (TCP 22).'
Write-Host 'WinRM is enabled for Ansible Windows modules (TCP 5985).'
Write-Host "Updater installed at: $destination"
Write-Warning 'Restrict SSH and WinRM firewall access to trusted management hosts.'
