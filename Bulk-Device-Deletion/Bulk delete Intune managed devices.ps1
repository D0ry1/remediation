<# 
Bulk delete Intune managed devices from a list of IntuneDeviceIds (managedDeviceId GUIDs)

Input file format:
- One GUID per line
- Blank lines allowed
- Lines starting with # are treated as comments

Safety:
- Runs in WhatIf mode by default
- Guardrails: name prefix and stale days threshold
- Produces a CSV report


.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90 -Execute

#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$StaleDays = 90,

    [string[]]$AllowedNamePrefixes = @("Y","Y"),

    [switch]$Execute  # Only when set will it actually delete
)

# Connect with correct scope for deletion
$scopes = @(
    "DeviceManagementManagedDevices.ReadWrite.All"
)

Connect-MgGraph -Scopes $scopes

# Build regex for allowed prefixes
$prefixRegex = '^(' + ($AllowedNamePrefixes -join '|') + ')'

# Read and clean input IDs
if (-not (Test-Path -Path $Path)) {
    throw "Input file not found: $Path"
}

$rawLines = Get-Content -Path $Path -ErrorAction Stop

$ids = $rawLines |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Select-Object -Unique

if (-not $ids -or $ids.Count -eq 0) {
    throw "No device IDs found in file after cleaning comments/blank lines."
}

$cutoff = (Get-Date).AddDays(-$StaleDays)

Write-Host "Loaded $($ids.Count) IDs from: $Path"
Write-Host "Guardrails:"
Write-Host " - Allowed name prefixes: $($AllowedNamePrefixes -join ', ')"
Write-Host " - LastSync must be older than: $cutoff (StaleDays=$StaleDays)"
Write-Host ""
Write-Host "Mode: " -NoNewline
if ($Execute) { Write-Host "EXECUTE (will delete)" -ForegroundColor Yellow }
else { Write-Host "WHATIF (no deletions)" -ForegroundColor Green }
Write-Host ""

$report = New-Object System.Collections.Generic.List[object]

foreach ($id in $ids) {

    # Validate GUID
    $guid = [Guid]::Empty
    if (-not [Guid]::TryParse($id, [ref]$guid)) {
        $report.Add([PSCustomObject]@{
            InputId          = $id
            DeviceName       = $null
            SerialNumber     = $null
            LastSyncDateTime = $null
            AzureAdDeviceId  = $null
            Action           = "Skipped"
            Reason           = "Invalid GUID format"
        })
        continue
    }

    # Fetch device details
    try {
        $d = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $id -ErrorAction Stop |
            Select-Object Id, DeviceName, SerialNumber, LastSyncDateTime, AzureAdDeviceId, UserPrincipalName
    }
    catch {
        $report.Add([PSCustomObject]@{
            InputId          = $id
            DeviceName       = $null
            SerialNumber     = $null
            LastSyncDateTime = $null
            AzureAdDeviceId  = $null
            Action           = "Skipped"
            Reason           = "Not found in Intune (or no access)"
        })
        continue
    }

    # Guardrail 1: Name prefix
    if (-not ($d.DeviceName -match $prefixRegex)) {
        $report.Add([PSCustomObject]@{
            InputId          = $d.Id
            DeviceName       = $d.DeviceName
            SerialNumber     = $d.SerialNumber
            LastSyncDateTime = $d.LastSyncDateTime
            AzureAdDeviceId  = $d.AzureAdDeviceId
            PrimaryUserUPN   = $d.UserPrincipalName
            Action           = "Skipped"
            Reason           = "DeviceName not allowed (prefix guardrail)"
        })
        continue
    }

    # Guardrail 2: Stale by LastSyncDateTime
    if ($null -eq $d.LastSyncDateTime) {
        $report.Add([PSCustomObject]@{
            InputId          = $d.Id
            DeviceName       = $d.DeviceName
            SerialNumber     = $d.SerialNumber
            LastSyncDateTime = $null
            AzureAdDeviceId  = $d.AzureAdDeviceId
            PrimaryUserUPN   = $d.UserPrincipalName
            Action           = "Skipped"
            Reason           = "LastSyncDateTime is null (stale guardrail cannot evaluate)"
        })
        continue
    }

    if ($d.LastSyncDateTime -gt $cutoff) {
        $report.Add([PSCustomObject]@{
            InputId          = $d.Id
            DeviceName       = $d.DeviceName
            SerialNumber     = $d.SerialNumber
            LastSyncDateTime = $d.LastSyncDateTime
            AzureAdDeviceId  = $d.AzureAdDeviceId
            PrimaryUserUPN   = $d.UserPrincipalName
            Action           = "Skipped"
            Reason           = "Device is not stale (LastSync newer than cutoff)"
        })
        continue
    }

    # Passed guardrails
    if ($Execute) {
        try {
            Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $d.Id -ErrorAction Stop
            $report.Add([PSCustomObject]@{
                InputId          = $d.Id
                DeviceName       = $d.DeviceName
                SerialNumber     = $d.SerialNumber
                LastSyncDateTime = $d.LastSyncDateTime
                AzureAdDeviceId  = $d.AzureAdDeviceId
                PrimaryUserUPN   = $d.UserPrincipalName
                Action           = "Deleted"
                Reason           = "Passed guardrails"
            })
        }
        catch {
            $report.Add([PSCustomObject]@{
                InputId          = $d.Id
                DeviceName       = $d.DeviceName
                SerialNumber     = $d.SerialNumber
                LastSyncDateTime = $d.LastSyncDateTime
                AzureAdDeviceId  = $d.AzureAdDeviceId
                PrimaryUserUPN   = $d.UserPrincipalName
                Action           = "Failed"
                Reason           = "Delete error: $($_.Exception.Message)"
            })
        }
    }
    else {
        $report.Add([PSCustomObject]@{
            InputId          = $d.Id
            DeviceName       = $d.DeviceName
            SerialNumber     = $d.SerialNumber
            LastSyncDateTime = $d.LastSyncDateTime
            AzureAdDeviceId  = $d.AzureAdDeviceId
            PrimaryUserUPN   = $d.UserPrincipalName
            Action           = "WouldDelete"
            Reason           = "Passed guardrails (WhatIf mode)"
        })
    }
}

# Output summary and export report
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$outCsv = Join-Path -Path (Split-Path $Path -Parent) -ChildPath "Intune_Delete_Report_$ts.csv"

$report | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Report written to: $outCsv" -ForegroundColor Cyan
Write-Host ""

$report |
Group-Object Action |
Sort-Object Name |
ForEach-Object {
    "{0,-12} {1,6}" -f $_.Name, $_.Count
} | Write-Host

Write-Host ""
Write-Host "Top 10 WouldDelete/Deleted items:" -ForegroundColor Cyan
$report |
Where-Object { $_.Action -in @("WouldDelete","Deleted") } |
Sort-Object LastSyncDateTime |
Select-Object -First 10 |
Format-Table DeviceName, SerialNumber, PrimaryUserUPN, LastSyncDateTime, InputId -AutoSize -Wrap
