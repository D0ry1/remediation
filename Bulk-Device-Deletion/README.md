
Bulk delete Intune managed devices (from file)
This PowerShell script bulk deletes Intune managed devices using a list of Intune managedDeviceId GUIDs (IntuneDeviceIds).
It is designed for safe clean-up operations with guardrails and reporting.
What it does
For each device ID in an input file, the script:
Validates the ID is a GUID
Looks up the device in Intune (Microsoft Graph)
Applies guardrails:
Device name must match an allowed prefix
Device must be stale based on LastSyncDateTime being older than a cutoff date
Runs in WhatIf mode by default (no deletions)
Writes a CSV report of everything it evaluated, including skip reasons and delete outcomes
Prerequisites
PowerShell 5.1+ or PowerShell 7+
Microsoft Graph PowerShell SDK
Permissions:
DeviceManagementManagedDevices.ReadWrite.All
Install Graph module (if needed)
Install-Module Microsoft.Graph -Scope CurrentUser
Authentication and permissions
The script connects to Microsoft Graph with:
DeviceManagementManagedDevices.ReadWrite.All
You will be prompted to sign in and consent if required.
Input file format
Provide a text file containing one managedDeviceId GUID per line.
Supported:
Blank lines are ignored
Lines starting with # are treated as comments
Example:
# Intune managedDeviceIds to remove
0f3b9d2b-1111-2222-3333-8e5f1f0c1234
1a2b3c4d-aaaa-bbbb-cccc-1234567890ab

# end
Safety model (guardrails)
The script is built to reduce risk of accidental deletion:
1) WhatIf by default
Nothing is deleted unless you supply -Execute.
2) Device name prefix allow list
Only devices whose DeviceName begins with one of the allowed prefixes will be eligible.
Default in script:
[string[]]$AllowedNamePrefixes = @("Y","Y")
Change that to match your estate naming convention, for example:
[string[]]$AllowedNamePrefixes = @("W10","LAP","W11-")
3) Stale device threshold (LastSyncDateTime)
Only devices with LastSyncDateTime older than Now - StaleDays will be eligible.
Default:
StaleDays = 90
Devices with LastSyncDateTime = null are skipped (stale guardrail cannot be evaluated).
Usage
Dry-run (recommended)
Produces a report and prints what it would delete:
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90
Execute deletions
Actually deletes devices that pass guardrails:
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -StaleDays 90 -Execute
Restrict to specific device name prefixes
.\Remove-IntuneDevicesFromFile.ps1 -Path "C:\temp\remove_ids.txt" -AllowedNamePrefixes @("W10","W11-") -StaleDays 120
Output and reporting
The script writes a CSV report next to the input file:
Intune_Delete_Report_YYYYMMDD-HHMMSS.csv
Report columns include:
InputId
DeviceName
SerialNumber
LastSyncDateTime
AzureAdDeviceId
PrimaryUserUPN
Action (Invalid GUID, Skipped, WouldDelete, Deleted, Failed)
Reason
It also prints:
A summary grouped by action
The top 10 oldest devices that are WouldDelete or Deleted
Common skip reasons
Invalid GUID format
Not found in Intune (or no access)
DeviceName not allowed (prefix guardrail)
LastSyncDateTime is null
Device is not stale (LastSync newer than cutoff)
Notes and cautions
This deletes the Intune managed device object (managedDeviceId). It does not automatically remove:
Entra ID device objects
Autopilot registrations
On-prem AD computer accounts
Those are separate clean-up steps depending on your process.
Always run the dry-run first and review the CSV before using -Execute.
