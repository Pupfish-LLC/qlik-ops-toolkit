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
	Initialize-QlikLog "Create-QlikGroups"
	Write-QlikLogHeader "Starting the group creation process..." -echo

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

    $groups = Import-Csv -Path $DATA\administer\input\groups.csv
    Write-QlikLog "$($groups.count) groups imported to create." -echo
    Write-QlikLogSeparator -echo

    #set a $timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

    # Initialize the output CSV file
    $outputFilePath = "$DATA\administer\output\groups_created.csv"
    if (-not (Test-Path -Path $outputFilePath)) {
        "Name,GroupId,Timestamp,Error" | Out-File -FilePath $outputFilePath -Encoding utf8
    }

    foreach ($group in $groups) {
        $name = $group.Name
        
        Write-QlikLog "Creating group with name: $name" -echo

        try {
            $groupDetails = Create-QlikGroup -name $name

           # Add properties dynamically to the $group object
            Add-Member -InputObject $group -NotePropertyName GroupId -NotePropertyValue ""
            Add-Member -InputObject $group -NotePropertyName Timestamp -NotePropertyValue $timestamp
            Add-Member -InputObject $group -NotePropertyName Error -NotePropertyValue ""

            # Check if the output is an error message
            if ($groupDetails.Success) {
                $logMessage = @"
Success: True
Name: $($groupDetails.Name)
GroupId: $($groupDetails.GroupId)
"@
                Write-QlikLog $logMessage -echo
                Write-QlikLogSeparator -echo
                $group.GroupId = $groupDetails.GroupId
                $group.Error = ""
            } else {
                Write-QlikLogError "Group creation encountered an error. $($groupDetails.Error)"
                $group.GroupId = ""
                $group.Error = $groupDetails.Error
            }
        } catch {
            Write-QlikLogError "Encountered an error during the group creation process [$($_.Exception.Message)]"
            $group.groupId = ""
            $group.Error = $_.Exception.Message
        } finally {
            $group | Select-Object Name,GroupId,Timestamp,Error | Export-Csv -Path $outputFilePath -Append -NoTypeInformation
        }
    }

} catch {
    Write-QlikLogError "Encountered an unexpected error during the group creation process [$($_.Exception.Message)]"
} finally {
    Write-QlikLogHeader "Group creation process concluded." -echo -character '*'
}