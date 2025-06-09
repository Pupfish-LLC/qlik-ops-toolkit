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

function Confirm-QlikContext {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$context
    )

    try {

        $commandOutput = & qlik context use $context 2>&1 | Out-String

        # Check for error in response
        if ($commandOutput -match "Error:") {
            throw "The context $context is invalid or could not be set"
        } else {
            return $true
        }
    } catch {

        throw "Failed to confirm the context [$($_.Exception.Message)]"

    }

}



function Get-QlikTenantUrl {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$context
    )

    try {

        $tenantUrl = qlik context get $context | Select-String -Pattern "server:" | ForEach-Object { $_.ToString().Replace('server: ','').Trim() }

        # Check for error in response
        if ($tenantUrl -match "Error:") {
            throw "Unable to retrieve the tenant Url for $($context)"
        } else {
            return $tenantUrl
        }
    } catch {

        throw "Failed to retrieve the tenant Url [$($_.Exception.Message)]"

    }

}