Import-Module ActiveDirectory

$Results = @()

$DCs = Get-ADDomainController -Filter *

foreach ($DC in $DCs) {

    Write-Host ""
    Write-Host "Pinging $($DC.HostName) ($($DC.IPv4Address))" -ForegroundColor Cyan

    try {
        $Replies = Test-Connection -ComputerName $DC.HostName -Count 2 -ErrorAction Stop

        foreach ($Reply in $Replies) {
            Write-Host ("Reply from {0}: bytes={1} time={2}ms TTL={3}" -f `
                $Reply.Address,
                $Reply.BufferSize,
                $Reply.ResponseTime,
                $Reply.TimeToLive)
        }

        $Reachable = $true
    }
    catch {
        Write-Host "Request timed out." -ForegroundColor Red
        $Reachable = $false
    }

    $Results += [PSCustomObject]@{
        Domain      = $DC.Domain
        Name        = $DC.Name
        Hostname    = $DC.HostName
        IPv4Address = $DC.IPv4Address
        Site        = $DC.Site
        Reachable   = $Reachable
    }
}

Write-Host ""
$Results | Sort-Object Domain, Name | Format-Table -AutoSize
