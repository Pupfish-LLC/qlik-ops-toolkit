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

function Export-QlikUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$false)]
        [string]$Context = $QlikCloudContext
    )

    try {
        Write-QlikLog "Exporting users..." -echo
        $users = qlik user ls --context $Context --limit 10000 --json | ConvertFrom-Json
        $users | Export-Csv -Path (Join-Path -Path $BackupPath -ChildPath "users.csv") -NoTypeInformation
        Write-QlikLog "Successfully exported $($users.Count) users." -echo
    }
    catch {
        Write-QlikLogError "Failed to export users: $($_.Exception.Message)"
    }
}

function Export-QlikSpaces {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$false)]
        [string]$Context = $QlikCloudContext
    )

    try {
        Write-QlikLog "Exporting spaces..." -echo
        $spaces = qlik space ls --context $Context --limit 10000 --json | ConvertFrom-Json
        $spaces | Export-Csv -Path (Join-Path -Path $BackupPath -ChildPath "spaces.csv") -NoTypeInformation
        Write-QlikLog "Successfully exported $($spaces.Count) spaces." -echo
    }
    catch {
        Write-QlikLogError "Failed to export spaces: $($_.Exception.Message)"
    }
}

function Export-QlikSpaceAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$false)]
        [string]$Context = $QlikCloudContext
    )

    try {
        Write-QlikLog "Exporting space assignments..." -echo
        $spaces = qlik space ls --context $Context --limit 10000 --json | ConvertFrom-Json

        $allAssignments = foreach ($space in $spaces) {
            qlik space assignment ls --spaceId $space.id --context $Context --json | ConvertFrom-Json
        }

        $allAssignments | Export-Csv -Path (Join-Path -Path $BackupPath -ChildPath "space_assignments.csv") -NoTypeInformation
        Write-QlikLog "Successfully exported $($allAssignments.Count) space assignments." -echo
    }
    catch {
        Write-QlikLogError "Failed to export space assignments: $($_.Exception.Message)"
    }
}

function Export-QlikApps {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$false)]
        [string]$Context = $QlikCloudContext
    )

    try {
        Write-QlikLog "Exporting apps..." -echo
        $apps = qlik app ls --context $Context --limit 10000 --json | ConvertFrom-Json
        $appsPath = Join-Path -Path $BackupPath -ChildPath "apps"
        New-Item -ItemType Directory -Path $appsPath -Force | Out-Null

        foreach ($app in $apps) {
            $sanitizedAppName = $app.name -replace '[\\/:"*?<>|]', ''
            $fileName = "$($sanitizedAppName)_$($app.id).qvf"
            Write-QlikLog "Exporting app: $($app.name)"
            qlik app export --app $app.id --context $Context --file (Join-Path -Path $appsPath -ChildPath $fileName)
        }

        Write-QlikLog "Successfully exported $($apps.Count) apps." -echo
    }
    catch {
        Write-QlikLogError "Failed to export apps: $($_.Exception.Message)"
    }
}

function Export-QlikRoleAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,

        [Parameter(Mandatory=$false)]
        [string]$Context = $QlikCloudContext
    )

    try {
        Write-QlikLog "Exporting role assignments..." -echo
        $roles = qlik role assignment ls --context $Context --limit 10000 --json | ConvertFrom-Json
        $roles | Export-Csv -Path (Join-Path -Path $BackupPath -ChildPath "role_assignments.csv") -NoTypeInformation
        Write-QlikLog "Successfully exported $($roles.Count) role assignments." -echo
    }
    catch {
        Write-QlikLogError "Failed to export role assignments: $($_.Exception.Message)"
    }
}
