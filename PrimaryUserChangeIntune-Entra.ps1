# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "User.Read.All"

function Get-LastLoggedOnUser {
    param (
        [Parameter(Mandatory)]
        [string]$DeviceId
    )
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')?`$select=id,deviceName,usersLoggedOn,userPrincipalName"
        $device = Invoke-MgGraphRequest -Uri $uri -Method GET

        if ($device.usersLoggedOn -and $device.usersLoggedOn.Count -gt 0) {
            $lastUser = $device.usersLoggedOn |
                Sort-Object -Property lastLogOnDateTime -Descending |
                Select-Object -First 1

            return [PSCustomObject]@{
                LastUserId        = $lastUser.userId
                CurrentPrimaryUPN = $device.userPrincipalName
            }
        }

        return [PSCustomObject]@{
            LastUserId        = $null
            CurrentPrimaryUPN = $device.userPrincipalName
        }
    }
    catch {
        Write-Host "Error getting last logged on user for device $DeviceId : $_" -ForegroundColor Red
        return [PSCustomObject]@{
            LastUserId        = $null
            CurrentPrimaryUPN = $null
        }
    }
}

function Set-PrimaryUser {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory)]
        [string]$DeviceId,

        [Parameter(Mandatory)]
        [string]$UserId
    )
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceId')/users/`$ref"
        $body = @{
            "@odata.id" = "https://graph.microsoft.com/beta/users('$UserId')"
        } | ConvertTo-Json

        if ($PSCmdlet.ShouldProcess("DeviceId=$DeviceId", "Set Primary User to UserId=$UserId")) {
            Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body -ContentType "application/json"
        }

        return $true
    }
    catch {
        Write-Host "Error setting primary user for device $DeviceId : $_" -ForegroundColor Red
        return $false
    }
}

# -----------------------------
# TEST SETTINGS (edit these)
# -----------------------------
$TargetDeviceName = "KC-1015685"   # e.g. "LAPTOP-1234"
# Optional: if you prefer to target by ID instead, set this and leave $TargetDeviceName as $null
$TargetManagedDeviceId = $null              # e.g. "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

# -----------------------------
# Find the one device
# -----------------------------
$device = $null

if ($TargetManagedDeviceId) {
    $device = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $TargetManagedDeviceId -ErrorAction SilentlyContinue
}
elseif ($TargetDeviceName) {
    # Filter by deviceName; escape single quotes for OData
    $safeName = $TargetDeviceName.Replace("'", "''")
    $matches = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$safeName'" -All -ErrorAction SilentlyContinue

    if (-not $matches) {
        Write-Host "No device found in Intune with deviceName '$TargetDeviceName'." -ForegroundColor Red
        Disconnect-MgGraph
        return
    }

    if ($matches.Count -gt 1) {
        Write-Host "Multiple devices found with name '$TargetDeviceName'. Please target by ManagedDeviceId instead:" -ForegroundColor Yellow
        $matches | Select-Object Id, DeviceName, UserPrincipalName, OperatingSystem, SerialNumber | Format-Table -AutoSize
        Disconnect-MgGraph
        return
    }

    $device = $matches | Select-Object -First 1
}
else {
    Write-Host "Set either `$TargetDeviceName or `$TargetManagedDeviceId." -ForegroundColor Red
    Disconnect-MgGraph
    return
}

Write-Host "Testing on device: $($device.DeviceName) (Id: $($device.Id))" -ForegroundColor Cyan
Write-Host "Current primary user (from list call): $($device.UserPrincipalName)" -ForegroundColor Yellow

# -----------------------------
# Get last logged on user + update if needed
# -----------------------------
$info = Get-LastLoggedOnUser -DeviceId $device.Id

if (-not $info.LastUserId) {
    Write-Host "No last logged on user found for this device (usersLoggedOn is empty or unavailable)." -ForegroundColor Yellow
    Disconnect-MgGraph
    return
}

$lastUser = Get-MgUser -UserId $info.LastUserId -ErrorAction Stop
Write-Host "Last logged on user: $($lastUser.UserPrincipalName)" -ForegroundColor Yellow

if ($device.UserPrincipalName -ne $lastUser.UserPrincipalName) {
    Write-Host "Primary user differs, will update." -ForegroundColor Yellow

    # Use -WhatIf when calling Set-PrimaryUser to simulate without changes:
    $result = Set-PrimaryUser -DeviceId $device.Id -UserId $info.LastUserId -WhatIf

    if ($result) {
        Write-Host "Completed (or simulated) primary user update to $($lastUser.UserPrincipalName)" -ForegroundColor Green
    } else {
        Write-Host "Failed to update primary user" -ForegroundColor Red
    }
}
else {
    Write-Host "Primary user is already set to the last logged on user." -ForegroundColor Green
}

# Disconnect
Disconnect-MgGraph
