#requires -Version 5.1
<#
.SYNOPSIS
    Installs available WinGet application updates and Windows/Microsoft updates.
.DESCRIPTION
    Designed for non-interactive execution by Ansible. It does not display GUI
    prompts or pause for input. It reports reboot status and only reboots when
    -RebootIfRequired is explicitly supplied.
.PARAMETER RebootIfRequired
    Restart the computer after updates if a reboot is pending.
.PARAMETER SkipWinget
    Skip WinGet application updates.
.PARAMETER SkipWindowsUpdate
    Skip Windows and Microsoft Update.
#>

[CmdletBinding()]
param(
    [switch]$RebootIfRequired,
    [switch]$SkipWinget,
    [switch]$SkipWindowsUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failedSteps = [System.Collections.Generic.List[string]]::new()
$rebootRequired = $false

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script in an elevated PowerShell session.'
}

# TLS 1.2 fallback for older Windows PowerShell/.NET environments.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Verbose "Could not set TLS 1.2 explicitly: $($_.Exception.Message)"
}

if (-not $SkipWinget) {
    Write-Host '=== WinGet application updates ===' -ForegroundColor Cyan
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning 'WinGet was not found; skipping application updates.'
    }
    else {
        & $winget.Source upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
        $wingetExitCode = $LASTEXITCODE
        if ($wingetExitCode -ne 0) {
            $failedSteps.Add("WinGet upgrade (exit code $wingetExitCode)")
            Write-Warning "WinGet returned exit code $wingetExitCode."
        }
    }
}

if (-not $SkipWindowsUpdate) {
    Write-Host '=== Windows and Microsoft updates ===' -ForegroundColor Cyan
    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Confirm:$false -Scope AllUsers
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop -Verbose
    }
    catch {
        $failedSteps.Add("Windows Update ($($_.Exception.Message))")
        Write-Warning "Windows Update failed: $($_.Exception.Message)"
    }
}

# Check common pending-reboot indicators.
$rebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
foreach ($key in $rebootKeys) {
    if (Test-Path $key) { $rebootRequired = $true }
}
try {
    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sessionManager.PendingFileRenameOperations) { $rebootRequired = $true }
} catch {}

Write-Host ''
if ($rebootRequired) {
    Write-Output 'REBOOT_REQUIRED=true'
    if ($RebootIfRequired) {
        Write-Host 'A reboot is pending. Restarting as requested...' -ForegroundColor Yellow
        Restart-Computer -Force
        exit 0
    }
    Write-Warning 'A reboot is required. Re-run with -RebootIfRequired to restart automatically.'
}
else {
    Write-Output 'REBOOT_REQUIRED=false'
}

if ($failedSteps.Count -gt 0) {
    Write-Error ("One or more update steps failed: " + ($failedSteps -join '; '))
    exit 1
}

Write-Host 'Update process completed.' -ForegroundColor Green
exit 0
