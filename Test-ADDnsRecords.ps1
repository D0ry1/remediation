<#
.SYNOPSIS
  Check core Active Directory DNS records after DC promotion.

.DESCRIPTION
  Validates that key SRV, A, CNAME and NS records exist for:
    - LDAP, Kerberos, GC
    - Site specific records
    - PDC and DC locator records
    - _msdcs GUID CNAMEs for each DC (NTDS Settings GUID)
    - _msdcs NS records
    - ForestDnsZones / DomainDnsZones presence

.PARAMETER DnsServer
  Optional DNS server to query. If not set, uses system resolver.

.EXAMPLE
  .\Test-ADDnsRecords.ps1

.EXAMPLE
  .\Test-ADDnsRecords.ps1 -DnsServer 192.168.1.10
#>

[CmdletBinding()]
param(
    [string]$DnsServer
)

Import-Module ActiveDirectory -ErrorAction Stop

function Test-DnsRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Type,

        [string]$Server
    )

    $params = @{
        Name        = $Name
        Type        = $Type
        ErrorAction = 'Stop'
    }

    if ($Server) {
        $params.Server = $Server
    }

    try {
        $result = Resolve-DnsName @params

        # Capture all returned records (hostname, IP, SRV fields etc)
        $recordData = $result | ForEach-Object {
            if ($_.QueryType -eq "SRV") {
                "Target=$($_.NameTarget), Port=$($_.Port), Priority=$($_.Priority), Weight=$($_.Weight)"
            }
            elseif ($_.QueryType -eq "A") {
                "Address=$($_.IPAddress)"
            }
            elseif ($_.QueryType -eq "CNAME") {
                "Alias=$($_.NameHost)"
            }
            elseif ($_.QueryType -eq "NS") {
                "NS=$($_.NameHost)"
            }
            elseif ($_.QueryType -eq "SOA") {
                "SOA Primary=$($_.PrimaryServer), Admin=$($_.Administrator)"
            }
            else {
                $_ | Out-String
            }
        }

        [PSCustomObject]@{
            Name        = $Name
            Type        = $Type
            Present     = $true
            Count       = $result.Count
            Records     = $recordData
            Message     = "Found $($result.Count) record(s)"
        }
    }
    catch {
        [PSCustomObject]@{
            Name        = $Name
            Type        = $Type
            Present     = $false
            Count       = 0
            Records     = @()
            Message     = $_.Exception.Message
        }
    }
}

Write-Host "Gathering AD information..." -ForegroundColor Cyan

$domain = Get-ADDomain
$forest = Get-ADForest
$dcs    = Get-ADDomainController -Filter *
$sites  = $forest.Sites

$domainDnsRoot = $domain.DNSRoot        # e.g. contoso.local
$forestDnsRoot = $forest.RootDomain     # usually same as above in single-domain forest

# Build list of records to test
$tests = @()

# 1. Domain wide core SRV records
$tests += [PSCustomObject]@{ Name = "_ldap._tcp.$domainDnsRoot";               Type = 'SRV' }
$tests += [PSCustomObject]@{ Name = "_kerberos._tcp.$domainDnsRoot";            Type = 'SRV' }
$tests += [PSCustomObject]@{ Name = "_kerberos._udp.$domainDnsRoot";            Type = 'SRV' }

# 2. DC locator SRV records
$tests += [PSCustomObject]@{ Name = "_ldap._tcp.dc._msdcs.$domainDnsRoot";      Type = 'SRV' }
$tests += [PSCustomObject]@{ Name = "_ldap._tcp.pdc._msdcs.$domainDnsRoot";     Type = 'SRV' }

# 3. Global Catalog SRV records (forest wide)
$tests += [PSCustomObject]@{ Name = "_gc._tcp.$forestDnsRoot";                  Type = 'SRV' }

# 4. Site specific records for each site
foreach ($site in $sites) {
    $siteNameDns = $site

    $tests += [PSCustomObject]@{ Name = "_ldap._tcp.$siteNameDns._sites.$domainDnsRoot";      Type = 'SRV' }
    $tests += [PSCustomObject]@{ Name = "_kerberos._tcp.$siteNameDns._sites.$domainDnsRoot";  Type = 'SRV' }
    $tests += [PSCustomObject]@{ Name = "_gc._tcp.$siteNameDns._sites.$forestDnsRoot";        Type = 'SRV' }
}

# 5. _msdcs NS records
$tests += [PSCustomObject]@{ Name = "_msdcs.$forestDnsRoot";                    Type = 'NS' }

# 6. ForestDnsZones and DomainDnsZones (check SOA as indicator zone exists)
$tests += [PSCustomObject]@{ Name = "ForestDnsZones.$forestDnsRoot";            Type = 'SOA' }
$tests += [PSCustomObject]@{ Name = "DomainDnsZones.$forestDnsRoot";            Type = 'SOA' }

# 7. Per DC records: host A and GUID CNAME (NTDS Settings GUID)
foreach ($dc in $dcs) {
    # Host A record (FQDN)
    $dcHost = $dc.HostName
    if ($dcHost) {
        $tests += [PSCustomObject]@{ Name = $dcHost; Type = 'A' }
    }

    # GUID based CNAME in _msdcs – use NTDS Settings object GUID, not computer GUID
    try {
        if ($dc.NTDSSettingsObjectDN) {
            $ntds = Get-ADObject -Identity $dc.NTDSSettingsObjectDN -Properties objectGUID -ErrorAction Stop
            if ($ntds.ObjectGUID) {
                $guidNoBraces = $ntds.ObjectGUID.ToString()
                $guidName     = "$guidNoBraces._msdcs.$forestDnsRoot"
                $tests += [PSCustomObject]@{ Name = $guidName; Type = 'CNAME' }
            }
        }
    }
    catch {
        Write-Verbose "Could not resolve NTDS Settings GUID for DC $($dc.HostName): $_"
    }
}

# Choose display name for target server
if ([string]::IsNullOrWhiteSpace($DnsServer)) {
    $targetServer = 'system resolver'
} else {
    $targetServer = $DnsServer
}

Write-Host "Testing DNS records against $targetServer..." -ForegroundColor Cyan

$results = foreach ($t in $tests | Sort-Object Name, Type -Unique) {
    Test-DnsRecord -Name $t.Name -Type $t.Type -Server $DnsServer
}

# Output results (high level)
$results |
    Sort-Object Present, Name, Type |
    Format-Table Name, Type, Present, Message -AutoSize

# Also return results object for programmatic use
$resultsMissing = $results | Where-Object { -not $_.Present }

Write-Host ""
Write-Host "Summary" -ForegroundColor Yellow
Write-Host "  Total records checked : $($results.Count)"
Write-Host "  Records present       : $(( $results | Where-Object { $_.Present } ).Count)"

if ($resultsMissing.Count -gt 0) {
    $missingColour = 'Red'
} else {
    $missingColour = 'Green'
}

Write-Host "  Records missing       : $($resultsMissing.Count)" -ForegroundColor $missingColour

if ($resultsMissing.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing records:" -ForegroundColor Red
    $resultsMissing | Format-Table Name, Type, Message -AutoSize
}

# Extra detail for names with more than one record
$multi = $results | Where-Object { $_.Present -and $_.Count -gt 1 }

if ($multi.Count -gt 0) {
    Write-Host ""
    Write-Host "Detailed multi-record results" -ForegroundColor Cyan
    Write-Host "==============================================="

    foreach ($r in $multi) {
        Write-Host ""
        Write-Host "$($r.Name)  [$($r.Type)] returned $($r.Count) records:" -ForegroundColor Yellow

        foreach ($line in $r.Records) {
            Write-Host "   $line"
        }
    }
}

# Uncomment if you want the object returned when dot sourcing
# $results
