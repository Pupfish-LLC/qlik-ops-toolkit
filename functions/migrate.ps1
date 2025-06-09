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

<#
TODO: This is an existing function from the original scripts in the Qlik-Migration-Tools. 
It needs refactoring to improve readability, possibly simpification, possibly be made more general purpose.

1. Finds the space by name
2. If space doesn't exist and -createmissing is $true, it creates the space with the specified name, type, and description
3. When necessary, it assigns roles to the user to enable them to upload and edit content in the space
    - createroles assigns a set of roles if none exist
    - updateroles updates the user's roles
    - function distinguishes between roles of shared vs managed
4. The $res (i.e. result) hashtable object is updated with the space's ID, type, and owner and this is returned as the result

Original Description:
Function that evaluates if the qlik-cli user can upload contents to a designated space. 

If the user cannot all roles will be assigned. This is made so that the same user can go directly to the tenant to verify the uploaded apps using the GUI without restrictions.
Note: As a best practice, once the migration process is concluded, please make sure to remove unecessary roles give for the qlik-cli user to the spaces

Parameters:
$evaluatedpacename -> name of the space to verify
$evaluatedspaceuserid -> tenant userid to which the verification should be made to
$createmissing -> flag to identify if the space must be created in case it is missing in the tenant
$evaluatedspacecreatetype -> type of space to create in case $createmissing flag is true (shared or managed)
$evaluatedspacedescription -> description to include when creating a new space
$evaluatedspacecmdinfotext -> message to output during this evaluation, when required

#>
function cliuserspaceuploadprivileges(){
	Param(
		[string] $evaluatedpacename, 
		[string] $evaluatedspaceuserid, 
		[bool] $createmissing, 
		[string] $evaluatedspacecreatetype, 
		[string] $evaluatedspacedescription, 
		[string] $evaluatedspacecmdinfotext
	)

	$res = @{}
	$res.Add("tmpspacehousekeeping", $true)     # Later set to false if the space already existed (in the context of the Qlik-Migration-Tools script this means that the space will not be removed)
	$res.Add("id",$null)                        
	$res.Add("spacetype",$null)                 
	$res.Add("spaceownerid",$null)

	$friendlyusertext = ""
	if($evaluatedspaceuserid -eq $cliuserid){
		$friendlyusertext = "qlik-cli user"
	}else{
		$friendlyusertext = "expected app owner"
	}

	# Internal function that adds a new user (assignee) to a space
	function createroles(){

		Write-host "Info: The $($friendlyusertext) does not have privileges to upload/edit contents to the space '$($evaluatedpacename)'. `
        Adding the necessary roles. Once you have reviewed the uploaded contents pelase make sure to remove unnecessary roles given for the $($friendlyusertext) to the space." -ForegroundColor Cyan
		
        if($evaluatedspace.type -eq "shared"){

			$migrationtemproles = qlik space assignment create --spaceId $evaluatedspace.id --assigneeId $evaluatedspaceuserid --type user --roles "codeveloper,consumer,dataconsumer,facilitator,producer" | ConvertFrom-Json
		
        }else{

			$migrationtemproles = qlik space assignment create --spaceId $evaluatedspace.id --assigneeId $evaluatedspaceuserid --type user --roles "basicconsumer,consumer,contributor,dataconsumer,facilitator,publisher" | ConvertFrom-Json
		
        }
	}

	# Internal function that updates the user (assignee) roles to a space
	function updateroles(){
		
        Write-host "Info: The $($friendlyusertext) does not have privileges to upload/edit contents to the space '$($evaluatedpacename)'. `
        Adding the necessary roles. Once you have reviewed the uploaded contents pelase make sure to remove unnecessary roles given for the $($friendlyusertext) to the space." -ForegroundColor Cyan
		
        if($evaluatedspace.type -eq "shared"){

			$migrationtemproles = qlik space assignment update $evaluatedspaceuseridfounddetails.id --spaceId $evaluatedspace.id --roles "codeveloper,consumer,dataconsumer,facilitator,producer" | ConvertFrom-Json
		
        }else{

			$migrationtemproles = qlik space assignment update $evaluatedspaceuseridfounddetails.id --spaceId $evaluatedspace.id --roles "basicconsumer,consumer,contributor,dataconsumer,facilitator,publisher" | ConvertFrom-Json
		
        }
	}

	# Updated to avoid inconsistent syntax for --filter command in different versions of PowerShell
	
	# $evaluatedspace = qlik space ls --name $evaluatedpacename | ConvertFrom-Json
	# $evaluatedSpace = qlik space ls --filter ('name eq \"' + $evaluatedpacename + '\"') | ConvertFrom-Json


	$evaluatedSpaceId = Get-QlikSpaceId "$evaluatedpacename"

	if ($evaluatedSpaceId) {

		$evaluatedSpace = qlik space get $evaluatedSpaceId | ConvertFrom-Json
		
	} else {

		$evaluatedSpace = $null
	}

	if($null -eq $evaluatedspace.id){

		if($createmissing){

			Write-QlikLog "Info: The space '$($evaluatedpacename)' does not exist in the tenant. Creating it. $($evaluatedspacecmdinfotext)" -echo
			$evaluatedspace = qlik space create --name $evaluatedpacename --type $evaluatedspacecreatetype --description $evaluatedspacedescription | ConvertFrom-Json

		}else{

			# Write-host $evaluatedspacecmdinfotext -ForegroundColor Magenta
			$res.tmpspacehousekeeping = $false
			return $res

		}
	
    }elseif($evaluatedspace.ownerId -ne $evaluatedspaceuserid){

		# Seems the space already exists and the owner is not the same user as the qlik-cli user. Adding roles to allow app upload
		$migrationtemproles =  qlik space assignment ls --spaceId $evaluatedspace.id | ConvertFrom-Json

		if($migrationtemproles.length -eq 0){

			createroles

		}else{

			$evaluatedspaceuseridfound = $false
			$evaluatedspaceuseridfounddetails = @{}

			foreach($migrationtempuser in $migrationtemproles ){

				if($evaluatedspaceuserid -eq $migrationtempuser.assigneeId){

					$evaluatedspaceuseridfound = $true
					$evaluatedspaceuseridfounddetails = $migrationtempuser

				}
			}

			if($evaluatedspaceuseridfound){

				if($null -eq $evaluatedspaceuseridfounddetails.roles){

					createroles

				}else{

					$migrationtempuploadprivileges = $false
	
					foreach($role in $evaluatedspaceuseridfounddetails.roles){

						if($role -eq "codeveloper" -or 	$role -eq "facilitator" -or $role -eq "producer" -or $role -eq "publisher"){
							$migrationtempuploadprivileges = $true
						}
					}

					if($migrationtempuploadprivileges -ne $true){
						updateroles
					}
				}
			}else{

				createroles

			}
		}
	}

	$res.id = $evaluatedspace.id
	$res.spacetype = $evaluatedspace.type
	$res.spaceownerid = $evaluatedspace.ownerid

	return $res
}

function Migrate-QlikAppUsers {
    param (

		[Parameter(Mandatory=$true, Position=0)]
		[Alias("app")]
		[string[]]$apps,								# Accepts single Id or an array of app Ids (can use Get-QlikAppIdList to obtain an array)

        [Parameter(Mandatory=$false, Position=1)]
        [string]$windowsContext = $QlikWindowsContext,

        [Parameter(Mandatory=$false, Position=2)]
        [string]$cloudContext = $QlikCloudContext                      
    )

    Write-QlikLog "Starting process to verify/create on-prem app object owners as cloud users." -echo

    qlik context use $cloudContext | out-null

    $cliuserid = qlik user me -q


    # Obtain relevant attributes for every cloud user (done once at the outset)

	try {
		# Switch context to cloud for fetching cloud users
        qlik context use $cloudContext | Out-Null

		Write-QlikLog "Obtaining relevant attributes for every cloud user..." -echo
		$cloudUsers = Get-QlikUsers "email,id,subject"
        $cloudUserEmails = $cloudusers | ForEach-Object { $_.email } | Sort-Object -Unique

        $uniqueCloudEmailCount = $cloudUserEmails | Measure-Object | Select-Object -ExpandProperty Count
        Write-QlikLog "Total unique user email addresses in cloud: $uniqueCloudEmailCount" -echo
        
	} catch {
		Write-QlikLogError "Encounterd an error while retrieving cloud users [$($_.Exception.Message)]" -stop
	}


	# Preprocess $cloudUsers into hashtables for more efficient lookup by user subject and by user email
	$cloudUserLookupBySubject = @{}
	$cloudUserLookupByEmail = @{}
	try {
		foreach ($user in $cloudUsers) {

			if ($null -ne $user.subject) {
				$cloudUserLookupBySubject[$user.subject] = $user.id
			} else {
				Write-QlikLogWarning "UserId $($user.id) Email: $($user.email) has a blank subject"
			}

			if ($null -ne $user.email) {
				$cloudUserLookupByEmail[$user.email] = $user.id
			} else {
				Write-QlikLogWarning "UserId $($user.id) Subject: $($user.subject) has a blank email address"
			}
		}
	} catch {
		Write-QlikLogError "Encounterd an error while creating user Id lookup tables [$($_.Exception.Message)]" -stop
	}


    # Initialize a hashtable to keep track of distinct owners of app objects
    $distinctOwners = @{}

    # Switch context to QSEoW for fetching on-prem objects and owners
	Write-QlikLog "context set..." -v
    qlik context use $windowsContext | Out-Null

	try {
		foreach ($appId in $apps) {

			Write-QlikLog "Obtaining list of object owners in on-prem appId: $($appid)" -echo
			$appobjects = qlik qrs app object full --filter ("app.id eq $appid") --context $windowsContext --insecure | ConvertFrom-Json

			foreach($object in $appobjects){

				$ownerid = $object.owner.id

				if (-not $distinctOwners.ContainsKey($ownerid)) {
					$distinctOwners[$ownerid] = @{
						ownerId = $object.owner.id
						ownerName = $object.owner.name
						# IMPORTANT: If subjects are different between onPrem and cloud then this will need adjustment
						ownerSubject = $object.owner.userDirectory + '\\' + $object.owner.userId
					}
				}
			}
		}
	} catch {
		Write-QlikLogError "Encountered an error while obtaining list of object owners in on-prem [$($_.Exception.Message)]" -stop
	}

    # Now that we have the distinct owner subjects, obtain the email and inactive status values for each
    Write-QlikLog "$($distinctOwners.Count) distinct object owners obtained for apps.`nNow retrieving their email addresses and active status..." -echo

	# Variables for progress bar operation
	$distinctOwnerCount = $distinctOwners.Count
	$index = 0

	try {
		foreach ($ownerID in $distinctOwners.Keys) {

			$index++
			Write-Progress -Activity "Retrieving object owner emails" -Status "Processing user $index of $distinctOwnerCount" -PercentComplete (($index / $distinctOwnerCount) * 100)

			$ownerDetails = qlik qrs user get $ownerid --context $windowsContext --insecure | ConvertFrom-Json
			$ownerEmail = ($ownerDetails.attributes | Where-Object { $_.attributeType -eq "email" }).attributeValue
			$ownerInactive = $ownerDetails.inactive

			# Update the existing entry in $distinctOwners with these details
			$distinctOwners[$ownerId].ownerEmail = $ownerEmail
			$distinctOwners[$ownerId].ownerInactive = $ownerInactive

		}
	} catch {
		Write-QlikLogError "Encounterd an error while retrieving email addresses and active status of on-prem object owners  [$($_.Exception.Message)]" -stop
	}
    # All app object owners are compiled.
	Write-Progress -Activity "Retrieving object owner emails" -Completed
    $distinctOwnerCount = $distinctOwners.Count
    Write-QlikLogSeparator -echo
    Write-QlikLog "Found $distinctOwnerCount distinct object owners across the on-prem apps." -echo

	# Write the distinct object owners to log (independent of whether the user chooses to view them)
	Write-QlikLogHeader "List of distinct object owners:" -character '-'
	$distinctOwners.Values | ForEach-Object {
		$status = if ($_.ownerInactive) { "Inactive" } else { "Active" }
		Write-QlikLog "Status: $($status), Email: $($_.ownerEmail), Subject: $($_.ownerSubject)"
	}

    # Prompt the user asking if they would like to list the users (DEBUG)
    $userResponse = Read-Host "Would you like to review the list?`n(Y)es - review object owners`n(N)o - proceed with verification/creation of Cloud users`nY or N"
	# Record the prompt/response to log only
	Write-QlikLog "USER PROMPT: Would you like to review the list?`n(Y)es - review object owners`n(N)o - proceed with verification/creation of Cloud users`nY or N"
	Write-QlikLog "USER RESPONSE: $($userResponse)"

    if ($userResponse -ne "N" -and $userResponse -ne "n" -and $userResponse -ne "no" -and $userResponse -ne "No") {
        Write-QlikLogSeparator -echo
        Write-Host "Listing distinct object owners:" -ForegroundColor DarkGray
        $distinctOwners.Values | ForEach-Object {
			$status = if ($_.ownerInactive) { "Inactive" } else { "Active" }
            Write-Host "Status: $($status), Email: $($_.ownerEmail), Subject: $($_.ownerSubject)"
        }
        Write-Host
        while($true){
            $userDecision = Read-Host "Do you want to continue?`n(Y)es to proceed with verification of these object owners as cloud users`n(N)o to abort`nY or N"
			
			# Record the prompt/response to log only
			Write-QlikLog "USER PROMPT: Do you want to continue?`n(Y)es to proceed with verification of these object owners as cloud users`n(N)o to abort`nY or N"
			Write-QlikLog "USER RESPONSE: $($userDecision)"

            if ($userDecision -eq "N") {
                Write-QlikLogError "Aborting process." -stop
            }
            elseif ($userDecision -eq "Y") {
                Write-QlikLog "Continuing process..." -echo
                break
            }
            else {
                Write-QlikLog "Invalid input. Please enter Y or N." -echo
            }
        }
    } else {
        Write-QlikLog "Continuing process..." -echo
    }

    Write-QlikLogHeader "Verifying the existence of $($distinctOwnerCount) on-prem object owners as Qlik Cloud users..." -character '-' -echo
	
	try {
		$usersToCreate = @()
		foreach ($owner in $distinctOwners.Values) {
			if (!$owner.ownerEmail ) {
				Write-QlikLogWarning "User $($owner.ownerSubject) does not have an email address. Ignored."
			}else{
				if ($cloudUserLookupByEmail[$owner.ownerEmail]) {
					Write-QlikLog "User $($owner.ownerEmail) already exists in the cloud." -v
				} else {
					if ($owner.ownerInactive -eq $true){
						Write-QlikLogWarning "User $($owner.ownerEmail) is inactive in on-prem. Ignored."
					}else{
						Write-QlikLog "User $($owner.ownerEmail) does not exist in the cloud. Flagged for creation." -echo
						$usersToCreate += $owner
					}
				}
			}
		}
	} catch {
		Write-QlikLogError "Encountered an error verifying the existence of on-prem users as cloud users [$($_.Exception.Message)]" -stop
	}
    $countToCreate = $usersToCreate.Count
    if ($countToCreate -gt 0) {

        Write-QlikLogHeader "$($countToCreate) distinct users to create in Qlik Cloud" -character '+' -echo

		 $usersToCreate | ForEach-Object {
            Write-Host "Name: $($_.ownerName), Email: $($_.ownerEmail), Subject: $($_.ownerSubject)"
        }

        $userResponse = Read-Host "Would you like to create these $($countToCreate) users in the cloud? (Y/N)"

		# Record the prompt/response to log only
		Write-QlikLog "USER PROMPT: Would you like to create these $($countToCreate) users in the cloud? (Y/N)"
		Write-QlikLog "USER RESPONSE: $($userResponse)"

        if ($userResponse -eq "Y" -or $userResponse -eq "y") {
            
			try {

				foreach ($user in $usersToCreate) {

					$correctedSubject = $user.ownerSubject -replace '\\\\', '\'
					
					Write-QlikLog "Creating user with Email:$($user.ownerEmail) Subject:$($correctedSubject) Name:$($user.ownerName)" -echo
					$response = qlik user create --email $($user.ownerEmail) --subject "$($correctedSubject)" --name "$($user.ownerName)" --context $cloudContext -q
					

					# Check if the response is JSON and contains an error
					if ($response -like 'Error: { *') {

						throw "Error: $response"

					} else {
						# Assume the response is the user ID if no errors are found
						$SaaSuserId = $response
						Write-QlikLog "User created successfully. User ID: $SaaSuserId" -echo
					}

				}
		
			} catch {
				Write-QlikLogError "Encountered an error creating cloud user with Email:$($user.ownerEmail) Subject:$($owner.ownerSubject) Name:$($owner.ownerName) [$($_.Exception.Message)]" -stop
			}

        } else {
            Write-QlikLogSeparator
            Write-QlikLogError "User creation aborted." -stop
        }
    } else {
        Write-QlikLogSeparator
        Write-QlikLogHeader "No new users to create." -character '+' -echo
    }

    Write-QlikLogHeader "Process to verify/create app object owners as cloud users has finished." -character '='


    # Cleanup

}