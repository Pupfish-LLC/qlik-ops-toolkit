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

$initScriptPath = Resolve-Path "$PSSCRIPTROOT\..\..\init.ps1"

# Initialize
try {
    . $initScriptPath
	. .\Migrate-QlikApps_Config.ps1
} catch {
	Write-Host "ERROR: Failed to initialize the script." -ForegroundColor Red
	Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}


# Initialize the log, validate the contexts, and retrieve key info. Halt upon error.
try{

	# Initialize log
	Initialize-QlikLog "Unpublish-QlikApps"
	Write-QlikLogHeader "Starting the app unpublishing process..." -echo

	# Validate windows context
	If (Confirm-QlikContext $QlikWindowsContext) {Write-QlikLog "The context $QlikWindowsContext has been validated." -echo}

	# Validate cloud context and set url
	If (Confirm-QlikContext $QlikCloudContext) {Write-QlikLog "The context $QlikCloudContext has been validated." -echo}
	# Get the cloud tenant Url
	$tenantUrl = Get-QlikTenantUrl $QlikCloudContext
	# Get the id of the current Qlik-cli user
	$cliUserId = qlik user me -q --context $QlikCloudContext

} catch {
	Write-QlikLogError "Encountered an error during initial validation [$($_.Exception.Message)]" -stop
}

# TODO: Insert app batch load here. Tested on individual apps.
# This operation is functional, but encounters occasional errors, presumably due to inconsistent qMeta data that is retrieved from the cloud app via cli-command (see Unpublish-QlikApp function in functions/app.ps1)
# Abandoned development due to inconsistent results in the scope of a migration from QSEoW

try {
	
	Unpublish-QlikApp -app 7d1918c1-02b9-4f61-8939-a2c83151b382 -sharedSpaceId 6643a030dcf4cf4bf5b02a22

} catch {
	Write-QlikLogError "Encountered an error during the unpublish operation [$($_.Exception.Message)]" -stop
}