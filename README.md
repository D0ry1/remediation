# Intune and Entra Operations Toolkit

This repository contains operational PowerShell tools for managing Microsoft Intune and Entra ID at scale.

These scripts are designed for:
- Tenant cleanup
- Post-breach remediation
- Device and identity hygiene
- Bulk operational fixes

They are **not** generic admin scripts. Many of them can delete or modify large numbers of objects.

## Safety first

Most scripts in this repo:
- Default to WhatIf or dry-run mode
- Require explicit execution flags to make changes
- Produce CSV audit logs

**Never run scripts from this repo without reading the README in the script’s folder first.**

## Tool index

| Tool | Purpose |
|------|--------|
| Bulk-Device-Deletion | Deletes Intune managed devices from a list of managedDeviceIds with guardrails |
| Duplicate-Device-Audit | Finds duplicate serial numbers in Intune |
| Primary-User-Fix | Fixes incorrect primary user assignments |
| Entra-Cleanup | Removes stale or orphaned Entra devices |

Each tool has its own README explaining:
- What it does
- What it deletes
- What guardrails exist
- How to run safely
