<#
Qlik Ops Toolkit
Copyright (C) 2024 DI Squared, LLC (https://disqr.com)
Copyright (C) 2024 Pupfish, LLC (http://pupfish.io)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License v3 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details: https://www.gnu.org/licenses/gpl-3.0.html
#>

# Dot source the required functions
. "$PSScriptRoot\..\functions\util.ps1"
. "$PSScriptRoot\..\functions\backup.ps1"
. "$PSScriptRoot\..\config\Global_Config.ps1"

# Initialize the log
Initialize-QlikLog -prefix "QlikCloudBackup"

try {
    # Create a timestamped backup directory
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupDirectory = Join-Path -Path $BackupPath -ChildPath $timestamp
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null

    Write-QlikLogHeader -header "Starting Qlik Cloud Backup" -echo

    # Export all items
    Export-QlikUsers -BackupPath $backupDirectory
    Export-QlikSpaces -BackupPath $backupDirectory
    Export-QlikSpaceAssignments -BackupPath $backupDirectory
    Export-QlikRoleAssignments -BackupPath $backupDirectory
    Export-QlikApps -BackupPath $backupDirectory

    Write-QlikLogHeader -header "Qlik Cloud Backup Complete" -echo

    # Clean up old backups
    Write-QlikLog "Cleaning up old backups..." -echo
    $backupRoot = $BackupPath
    $retentionDays = $BackupRetentionDays
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)

    Get-ChildItem -Path $backupRoot -Directory | Where-Object { $_.CreationTime -lt $cutoffDate } | ForEach-Object {
        Write-QlikLog "Deleting old backup: $($_.FullName)"
        Remove-Item -Recurse -Force -Path $_.FullName
    }
}
catch {
    Write-QlikLogError "An unexpected error occurred during the backup process: $($_.Exception.Message)"
}
