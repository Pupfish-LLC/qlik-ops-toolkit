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
	. "$CONFIG\Migrate-QlikApps_Config.ps1"
} catch {
	Write-Host "ERROR: Failed to initialize the script." -ForegroundColor Red
	Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize the log, validate the contexts, and retrieve key info. Halt upon error.
try{

	# Initialize log
	Initialize-QlikLog "[Operation-Name]"
	Write-QlikLogHeader "Starting the [Operation-Name] process..." -echo

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

<#

Begin additional scripting for your operational script...

For example:

# Load a list of apps
try {

	$importDataPath = Join-Path -Path $DATA -ChildPath "migrate-qliksense\input\"

	$apps = Get-QlikAppIdList -path $importDataPath -file "apps.csv" -property "AppId"

} catch {
	Write-QlikLogError "Failed to load the app.csv list [$($_.Exception.Message)]" -stop
}

#>