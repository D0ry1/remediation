<# 
DC Connectivity Check (Windows 11, user-safe)

Tests per Domain Controller:
- ICMP Ping
- DNS 53 TCP/UDP
- Kerberos 88 TCP/UDP
- NTP 123 UDP
- RPC Endpoint Mapper 135 TCP
- LDAP 389 TCP/UDP
- SMB 445 TCP
- SYSVOL and NETLOGON real access checks (lists \\DC\SYSVOL and \\DC\NETLOGON)
- LDAPS 636 TCP
- Global Catalog 3268 TCP and 3269 TCP
- RPC Dynamic ports 49152-65535 TCP (sample checks)

Output:
- Grouped by port (53 then 88 etc)
- Colour-coded (green OK, red blocked, yellow other)
#>

$ErrorActionPreference = "SilentlyContinue"

function Get-AllDCs {
    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $dcs = @()
        foreach ($dc in $domain.DomainControllers) {
            if ($dc -and $dc.Name) { $dcs += $dc.Name }
        }
        return $dcs | Sort-Object -Unique
    } catch {
        if ($env:LOGONSERVER) { return @($env:LOGONSERVER -replace "^\\\\","") }
        return @()
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs = 2000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar) | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-UdpPort {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port
    )
    try {
        return [bool](Test-NetConnection -ComputerName $ComputerName -Port $Port -Udp -WarningAction SilentlyContinue).UdpTestSucceeded
    } catch {
        return $false
    }
}

function Test-SmbShareAccess {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][ValidateSet("SYSVOL","NETLOGON")][string]$ShareName
    )

    $path = "\\$ComputerName\$ShareName"

    # Quick reachability check
    if (-not (Test-Path -Path $path)) {
        return [pscustomobject]@{
            Accessible = $false
            Detail     = "Path not reachable"
        }
    }

    # Real access check: list at least one entry (or confirm share is empty but reachable)
    try {
        $item = Get-ChildItem -Path $path -ErrorAction Stop | Select-Object -First 1

        if ($ShareName -eq "SYSVOL") {
            # Extra SYSVOL sanity: domain folder usually exists beneath SYSVOL
            try {
                $domainName = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                $domainFolder = Join-Path $path $domainName
                if (Test-Path -Path $domainFolder) {
                    return [pscustomobject]@{ Accessible = $true; Detail = "Accessible (domain folder present)" }
                } else {
                    return [pscustomobject]@{ Accessible = $true; Detail = "Accessible (domain folder not found under SYSVOL)" }
                }
            } catch {
                return [pscustomobject]@{ Accessible = $true; Detail = "Accessible (could not validate domain folder)" }
            }
        }

        if (-not $item) {
            return [pscustomobject]@{ Accessible = $true; Detail = "Accessible (empty listing)" }
        }

        return [pscustomobject]@{ Accessible = $true; Detail = "Accessible" }
    } catch {
        return [pscustomobject]@{
            Accessible = $false
            Detail     = $_.Exception.Message
        }
    }
}

$dcs = Get-AllDCs
if (-not $dcs -or $dcs.Count -eq 0) {
    Write-Host "No Domain Controllers detected. Are you on the corporate network / VPN and domain-joined?" -ForegroundColor Yellow
    return
}

Write-Host "Testing DC connectivity for: $($dcs -join ', ')" -ForegroundColor Cyan
Write-Host ""

# RPC dynamic port range samples (spot broad blocks)
$rpcDynamicSamples = @(49152, 49500, 52000, 60000)

# Port-grouped checks
$checks = @(
    @{ Order=0;    Name="ICMP Ping";           Proto="ICMP"; Port="";    Test={ param($dc) Test-Connection $dc -Count 2 -Quiet } }

    @{ Order=53;   Name="DNS";                 Proto="UDP";  Port=53;    Test={ param($dc) Test-UdpPort $dc 53 } }
    @{ Order=53;   Name="DNS";                 Proto="TCP";  Port=53;    Test={ param($dc) Test-TcpPort $dc 53 } }

    @{ Order=88;   Name="Kerberos";            Proto="UDP";  Port=88;    Test={ param($dc) Test-UdpPort $dc 88 } }
    @{ Order=88;   Name="Kerberos";            Proto="TCP";  Port=88;    Test={ param($dc) Test-TcpPort $dc 88 } }

    @{ Order=123;  Name="NTP";                 Proto="UDP";  Port=123;   Test={ param($dc) Test-UdpPort $dc 123 } }

    @{ Order=135;  Name="RPC Endpoint Mapper"; Proto="TCP";  Port=135;   Test={ param($dc) Test-TcpPort $dc 135 } }

    @{ Order=389;  Name="LDAP";                Proto="UDP";  Port=389;   Test={ param($dc) Test-UdpPort $dc 389 } }
    @{ Order=389;  Name="LDAP";                Proto="TCP";  Port=389;   Test={ param($dc) Test-TcpPort $dc 389 } }

    @{ Order=445;  Name="SMB";                 Proto="TCP";  Port=445;   Test={ param($dc) Test-TcpPort $dc 445 } }

    @{ Order=636;  Name="LDAPS";               Proto="TCP";  Port=636;   Test={ param($dc) Test-TcpPort $dc 636 } }

    @{ Order=3268; Name="Global Catalog";      Proto="TCP";  Port=3268;  Test={ param($dc) Test-TcpPort $dc 3268 } }
    @{ Order=3269; Name="Global Catalog SSL";  Proto="TCP";  Port=3269;  Test={ param($dc) Test-TcpPort $dc 3269 } }
)

$results = @()

foreach ($dc in $dcs) {

    foreach ($c in $checks) {
        $ok = & $c.Test $dc
        $results += [pscustomobject]@{
            PortOrder = $c.Order
            Port      = $c.Port
            Check     = $c.Name
            Protocol  = $c.Proto
            DC        = $dc
            Status    = if ($ok) { "OK" } else { "BLOCKED" }
            Detail    = ""
        }
    }

    foreach ($p in $rpcDynamicSamples) {
        $ok = Test-TcpPort -ComputerName $dc -Port $p
        $results += [pscustomobject]@{
            PortOrder = 49152
            Port      = $p
            Check     = "RPC Dynamic (sample)"
            Protocol  = "TCP"
            DC        = $dc
            Status    = if ($ok) { "OK" } else { "BLOCKED" }
            Detail    = ""
        }
    }

    # Real SMB share access checks per DC
    $sys = Test-SmbShareAccess -ComputerName $dc -ShareName "SYSVOL"
    $net = Test-SmbShareAccess -ComputerName $dc -ShareName "NETLOGON"

    $results += [pscustomobject]@{
        PortOrder = 445
        Port      = 445
        Check     = "SYSVOL Share (real access)"
        Protocol  = "SMB"
        DC        = $dc
        Status    = if ($sys.Accessible) { "ACCESSIBLE" } else { "NOT ACCESSIBLE" }
        Detail    = $sys.Detail
    }

    $results += [pscustomobject]@{
        PortOrder = 445
        Port      = 445
        Check     = "NETLOGON Share (real access)"
        Protocol  = "SMB"
        DC        = $dc
        Status    = if ($net.Accessible) { "ACCESSIBLE" } else { "NOT ACCESSIBLE" }
        Detail    = $net.Detail
    }
}

# Colour-coded output grouped by port
$sorted = $results | Sort-Object PortOrder, Port, Check, DC

Write-Host ""
Write-Host "DC Connectivity Results (Grouped by Port)" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

$lastPort = $null

foreach ($r in $sorted) {

    if ($r.PortOrder -ne $lastPort) {
        Write-Host ""
        if ($r.PortOrder -eq 0) {
            Write-Host "Port ICMP" -ForegroundColor Cyan
        } else {
            Write-Host ("Port {0}" -f $r.PortOrder) -ForegroundColor Cyan
        }
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        $lastPort = $r.PortOrder
    }

    $statusText = "{0,-30} {1,-6} {2,-28} {3}" -f `
        $r.DC, $r.Protocol, $r.Check, $r.Status

    switch ($r.Status) {
        "OK" {
            Write-Host $statusText -ForegroundColor Green
        }
        "ACCESSIBLE" {
            Write-Host ($statusText + "  ✔ " + $r.Detail) -ForegroundColor Green
        }
        "BLOCKED" {
            Write-Host $statusText -ForegroundColor Red
        }
        "NOT ACCESSIBLE" {
            Write-Host ($statusText + "  ✖ " + $r.Detail) -ForegroundColor Red
        }
        default {
            $extra = ""
            if ($r.Detail) { $extra = "  " + $r.Detail }
            Write-Host ($statusText + $extra) -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Legend:" -ForegroundColor Cyan
Write-Host "  Green  = Working / Accessible" -ForegroundColor Green
Write-Host "  Red    = Blocked / Group Policy likely fails" -ForegroundColor Red
Write-Host "  Yellow = Unexpected / informational" -ForegroundColor Yellow

Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "If SYSVOL Share (real access) is NOT ACCESSIBLE for a DC, Group Policy cannot be read from that DC over the VPN." -ForegroundColor Yellow
Write-Host "If SMB 445 is OK but SYSVOL real access fails, suspect DFS, name resolution, or SMB auth behaviour over the VPN." -ForegroundColor Yellow
