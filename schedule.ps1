#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Register/unregister the cleanup script as a Windows scheduled task.
.PARAMETER Register
    Create the scheduled task (runs weekly on Sunday at 3 AM).
.PARAMETER Unregister
    Remove the scheduled task.
.PARAMETER Interval
    Schedule interval: Daily, Weekly (default), Monthly.
#>

param(
    [switch]$Register,
    [switch]$Unregister,
    [ValidateSet('Daily', 'Weekly', 'Monthly')]
    [string]$Interval = 'Weekly'
)

$TaskName = "WinCleanup"
$ScriptPath = Join-Path $PSScriptRoot "cleanup.ps1"

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Task '$TaskName' removed." -ForegroundColor Green
    exit 0
}

if ($Register) {
    if (-not (Test-Path $ScriptPath)) {
        Write-Host "Error: cleanup.ps1 not found at $ScriptPath" -ForegroundColor Red
        exit 1
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Force"

    switch ($Interval) {
        'Daily'   { $trigger = New-ScheduledTaskTrigger -Daily   -At '03:00' }
        'Weekly'  { $trigger = New-ScheduledTaskTrigger -Weekly  -DaysOfWeek Sunday -At '03:00' }
        'Monthly' { $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At '03:00' }
    }

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force

    Write-Host "Task '$TaskName' registered ($Interval at 3:00 AM)." -ForegroundColor Green
    Write-Host "To run now: schtasks /Run /TN $TaskName"
}

if (-not $Register -and -not $Unregister) {
    Write-Host "Usage:"
    Write-Host "  .\schedule.ps1 -Register                 # Weekly (default)"
    Write-Host "  .\schedule.ps1 -Register -Interval Daily # Daily"
    Write-Host "  .\schedule.ps1 -Unregister               # Remove task"
}
