<#
.SYNOPSIS
  Local machine account password reset and health check
  Run this logged on to the server you are fixing.
#>

param(
    [string]$DomainName  = "yourdomain.local",      # FQDN of the AD domain
    [string]$DCName      = "YourHealthyDC",         # A known good DC
    [string]$DomainAdmin = "YOURDOMAIN\AdminUser"   # Account with rights to reset machine passwords
)

Write-Host "===================================================" 
Write-Host " Machine password reset and health check"
Write-Host " Server : $env:COMPUTERNAME"
Write-Host " Domain : $DomainName"
Write-Host " DC     : $DCName"
Write-Host "===================================================" 
Write-Host ""

# Prompt once for the domain admin password
$SecurePassword = Read-Host "Enter password for $DomainAdmin" -AsSecureString

# Convert secure string to plain text (needed for netdom) in a way that works on older .NET versions
$PlainPassword = (New-Object System.Net.NetworkCredential("", $SecurePassword)).Password

# 1. Reset the machine account password
Write-Host "[*] Resetting machine account password with netdom..." -ForegroundColor Cyan

$cmd = "netdom resetpwd /server:$DCName /userd:$DomainAdmin /passwordd:$PlainPassword"

cmd.exe /c $cmd
$resetExitCode = $LASTEXITCODE

if ($resetExitCode -ne 0) {
    Write-Host "[!] netdom resetpwd failed with exit code $resetExitCode" -ForegroundColor Red
    Write-Host "    Check connectivity to $DCName and credentials for $DomainAdmin."
    return
}

Write-Host "[+] Machine password reset command completed." -ForegroundColor Green

Start-Sleep -Seconds 5

# 2. Verify secure channel
Write-Host ""
Write-Host "[*] Verifying secure channel with nltest..." -ForegroundColor Cyan

$scOutput = nltest /sc_verify:$DomainName
$scSuccess = $scOutput -match "NERR_Success"

if ($scSuccess) {
    Write-Host "[+] Secure channel looks healthy (NERR_Success)." -ForegroundColor Green
} else {
    Write-Host "[!] Secure channel check did not return NERR_Success." -ForegroundColor Yellow
    Write-Host $scOutput
}

# 3. Kerberos ticket sanity check
Write-Host ""
Write-Host "[*] Purging Kerberos tickets and showing current cache..." -ForegroundColor Cyan

klist purge
Start-Sleep -Seconds 2
klist

# 4. SYSVOL access test
Write-Host ""
Write-Host "[*] Testing access to SYSVOL on $DCName..." -ForegroundColor Cyan

$sysvolPath  = "\\$DCName\SYSVOL"
$sysvolOk    = Test-Path $sysvolPath

if ($sysvolOk) {
    Write-Host "[+] Able to access $sysvolPath" -ForegroundColor Green
} else {
    Write-Host "[!] Cannot access $sysvolPath" -ForegroundColor Yellow
}

# 5. Summary
Write-Host ""
Write-Host "================= SUMMARY =================" -ForegroundColor White

$overallOk = $scSuccess -and $sysvolOk

Write-Host "Server          : $env:COMPUTERNAME"
Write-Host "Secure channel  : " -NoNewline
if ($scSuccess) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }

Write-Host "SYSVOL access   : " -NoNewline
if ($sysvolOk)   { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }

if ($overallOk) {
    Write-Host "`nRESULT         : PASS" -ForegroundColor Green
    Write-Host "This server should now be aligned with the current KRBTGT state."
} else {
    Write-Host "`nRESULT         : FAIL" -ForegroundColor Red
    Write-Host "Investigate secure channel and SYSVOL before trusting this host fully."
}

Write-Host "==========================================="
