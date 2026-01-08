Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"

# Get Intune devices, only names starting X or Y
$devices = Get-MgDeviceManagementManagedDevice -All |
    Where-Object { $_.DeviceName -match '^(X|Y)' } |
    Select-Object DeviceName, Id, AzureAdDeviceId, SerialNumber, LastSyncDateTime, UserPrincipalName, UserId

$removeList = @()

$devices |
Where-Object { $_.SerialNumber } |
Group-Object SerialNumber |
Where-Object { $_.Count -gt 1 } |
ForEach-Object {

    $sorted = $_.Group | Sort-Object LastSyncDateTime -Descending

    $keep = $sorted[0]
    $remove = $sorted | Select-Object -Skip 1

    Write-Host "`nSerialNumber: $($_.Name)" -ForegroundColor Cyan
    Write-Host "KEEP   : $($keep.DeviceName) | PrimaryUser: $($keep.UserPrincipalName) | LastSync: $($keep.LastSyncDateTime) | IntuneId: $($keep.Id)" -ForegroundColor Green

    foreach ($r in $remove) {
        Write-Host "REMOVE : $($r.DeviceName) | PrimaryUser: $($r.UserPrincipalName) | LastSync: $($r.LastSyncDateTime) | IntuneId: $($r.Id)" -ForegroundColor Yellow

        $removeList += [PSCustomObject]@{
            SerialNumber     = $_.Name
            DeviceName       = $r.DeviceName
            PrimaryUserUPN   = $r.UserPrincipalName
            PrimaryUserId    = $r.UserId
            IntuneDeviceId   = $r.Id
            AzureAdDeviceId  = $r.AzureAdDeviceId
            LastSyncDateTime = $r.LastSyncDateTime
        }
    }

    # Full context view (newest first)
    $sorted | Format-Table DeviceName, UserPrincipalName, Id, AzureAdDeviceId, LastSyncDateTime -AutoSize -Wrap
}

# FINAL REMOVE SUMMARY
Write-Host "`n===== REMOVE CANDIDATES SUMMARY =====" -ForegroundColor Red

$removeList |
Sort-Object LastSyncDateTime |
Format-Table SerialNumber, DeviceName, PrimaryUserUPN, IntuneDeviceId, AzureAdDeviceId, LastSyncDateTime -AutoSize -Wrap
