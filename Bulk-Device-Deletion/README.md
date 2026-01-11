# Intune Bulk Device Deletion Tool

This repository contains a PowerShell tool for safely bulk deleting **Microsoft Intune managed devices** using a list of **managedDeviceId GUIDs**.

It is designed for **post-incident clean-up**, **duplicate device remediation**, and **large-scale Intune hygiene** where deletion must be controlled, auditable, and intentional.

## What this tool does

For each device ID in the input file, the script:

1. Validates the ID is a GUID
2. Looks up the device in Intune using Microsoft Graph
3. Applies guardrails:
   - Device name must match an allowed prefix
   - Device must be stale based on `LastSyncDateTime`
4. Runs in **WhatIf mode by default**
5. Writes a **CSV audit report**

No device is deleted unless it passes all guardrails and the `-Execute` switch is supplied.

## Requirements

- PowerShell 5.1+ or PowerShell 7
- Microsoft Graph PowerShell SDK
- Microsoft Graph permission: `DeviceManagementManagedDevices.ReadWrite.All`

### Install the Graph module

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Authentication

The script connects to Microsoft Graph and will prompt for interactive sign-in.  
The signed-in account must have permission to delete Intune managed devices.

## Input file format

The script reads a text file containing **one Intune managedDeviceId per line**.

Rules:
- Blank lines are ignored
- Lines starting with `#` are comments

Example:

```text
# Intune devices to remove
0f3b9d2b-1111-2222-3333-8e5f1f0c1234
1a2b3c4d-aaaa-bbbb-cccc-1234567890ab
```

## Safety model

This script is intentionally hard to misuse.

### WhatIf mode
No deletions happen unless the `-Execute` switch is supplied.

### Device name prefix allow list
Only devices whose `DeviceName` starts with one of the allowed prefixes will be eligible.

Default:
```powershell
[string[]]$AllowedNamePrefixes = @("Y","Y")
```

### Stale device requirement
Only devices with `LastSyncDateTime` older than current date minus `StaleDays` (default 90).

## Usage

### Dry run
```powershell
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90
```

### Execute
```powershell
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90 -Execute
```

## Output

A CSV report is written: `Intune_Delete_Report_YYYYMMDD-HHMMSS.csv`
