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
} catch {
	Write-Host "ERROR: Failed to initialize the script." -ForegroundColor Red
	Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
  
# Initialize the log, validate the contexts, and retrieve key info. Halt upon error.
try{

	# Initialize log
	Initialize-QlikLog "Create-QlikSpaces"
	Write-QlikLogHeader "Starting the space creation process..." -echo

	# Validate cloud context and set url
	If (Confirm-QlikContext $QlikCloudContext) {Write-QlikLog "The context $QlikCloudContext has been validated." -echo}
	# Get the cloud tenant Url
	$tenantUrl = Get-QlikTenantUrl $QlikCloudContext
	# Get the id of the current Qlik-cli user
	$cliUserId = qlik user me -q --context $QlikCloudContext

} catch {
	Write-QlikLogError "Encountered an error during initial validation [$($_.Exception.Message)]" -stop
}

try {

    qlik context use $QlikCloudContext

    $spaces = Import-Csv -Path $DATA\administer\input\spaces.csv
    Write-QlikLog "$($spaces.count) spaces imported to create." -echo
    Write-QlikLogSeparator -echo

    #set a $timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

    # Initialize the output CSV file
    $outputFilePath = "$DATA\administer\output\spaces_created.csv"
    if (-not (Test-Path -Path $outputFilePath)) {
        "Name,Type,Description,Owner,SpaceId,Timestamp,Error" | Out-File -FilePath $outputFilePath -Encoding utf8
    }

    foreach ($space in $spaces) {
        $name = $space.Name
        $type = $space.Type
        $owner = $space.Owner
        $description = $space.Description
        
        Write-QlikLog "Creating space with name: $name | type: $type" -echo

        try {
            $spaceDetails = Create-QlikSpace -name $name -type $type -description $description -owner $owner

           # Add properties dynamically to the $space object
            Add-Member -InputObject $space -NotePropertyName SpaceId -NotePropertyValue ""
            Add-Member -InputObject $space -NotePropertyName Timestamp -NotePropertyValue $timestamp
            Add-Member -InputObject $space -NotePropertyName Error -NotePropertyValue ""

            # Check if the output is an error message
            if ($spaceDetails.Success) {
                $logMessage = @"
Success: True
Name: $($spaceDetails.Name)
Type: $($spaceDetails.Type)
Description: $($spaceDetails.Description)
Owner: $($spaceDetails.Owner)
SpaceId: $($spaceDetails.SpaceId)
"@
                Write-QlikLog $logMessage -echo
                Write-QlikLogSeparator -echo
                $space.SpaceId = $spaceDetails.SpaceId
                $space.Error = ""
            } else {
                Write-QlikLogError "Space creation encountered an error. $($spaceDetails.Error)"
                $space.SpaceId = ""
                $space.Error = $spaceDetails.Error
            }
        } catch {
            Write-QlikLogError "Encountered an error during the space creation process [$($_.Exception.Message)]"
            $space.SpaceId = ""
            $space.Error = $_.Exception.Message
        } finally {
            $space | Select-Object Name,Type,Description,Owner,SpaceId,Timestamp,Error | Export-Csv -Path $outputFilePath -Append -NoTypeInformation
        }
    }

} catch {
    Write-QlikLogError "Encountered an unexpected error during the space creation process [$($_.Exception.Message)]"
} finally {
    Write-QlikLogHeader "Space creation process concluded." -echo -character '*'
}