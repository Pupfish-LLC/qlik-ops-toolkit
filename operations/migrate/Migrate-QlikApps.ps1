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
	Initialize-QlikLog "Migrate-QlikApps"
	Write-QlikLogHeader "Starting the app migration process..." -echo

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


# Load the list of apps
try {

	$importDataPath = Join-Path -Path $DATA -ChildPath "migrate-qliksense\input\apps.csv"

	#Qlik Sense Headers: AppId,SpaceName,AppOwnerEmail
	$apps = Import-Csv -Path $importDataPath -Header "AppId", "SpaceName", "AppOwnerEmail" | Select-Object -skip 1

} catch {
	Write-QlikLogError "Failed to load the app.csv list [$($_.Exception.Message)]" -stop
}

# Define and initialize the path for the apps_created.csv file
try {
	$appsCreatedFilePath = Join-Path -Path $DATA -ChildPath "migrate-qliksense\output\apps_created.csv"

	# Initialize the apps_created.dsv file if it does not exist
	if (-not (Test-Path -Path $appsCreatedFilePath)) {
		"AppID,CloudAppID,DevCopyID,MigrationType,ExportScope,LogFile" | Out-File -FilePath $appsCreatedFilePath -Encoding utf8
	}

} catch {
	Write-QlikLogError "Failed to initialize the apps_created output file [$($_.Exception.Message)]" -stop
}

# Define the directory to which apps will be exported, and verify it
try {

	$appsdir = Join-Path -Path $DATA -ChildPath "migrate-qliksense\export\apps"

	if (-not (Test-Path -Path $appsdir)) {
		throw "The export directory could not be verified "
	}

} catch {
	Write-QlikLogError "Failed to set the directory location for app export [$($_.Exception.Message)]" -stop
}


try {

	# Ensure that the temporary space is available and ready to use
	# TODO: This cliuserspaceuploadprivileges function is an original script from the Qlik's migration tools, still used used here and in several places. 
	# The function call has been cleaned up and flag names added for readability,
	# but the function itself needs refactoring and improvement. The function itself has been moved to the migrate.ps1 script file and is mostly in its original state, for now

	$migrationspace = cliuserspaceuploadprivileges `
	-evaluatedpacename $migrationtempspacename `
	-evaluatedspaceuserid $cliUserId `
	-createmissing $true `
	-evaluatedspacecreatetype "shared" `
	-evaluatedspacedescription "This is a temporary space created to support the migration process." `
	-evaluatedspacecmdinfotext "This is a temporary space to support the app migration process. It can be removed when the migration process concludes."

	# Store the id of the temporary space
	If ($migrationSpace.Id) {
		$migrationSpaceId = $migrationSpace.id
	} else {
		throw "The space Id of the temporary migration space could not be identified"
	}

	# Store the boolean value that indicates if the space already existed (the logic here is from the original script and is questionable, in that if the space already exists it will not be removed despite the initial setting)
	If ($removemigrationtemp) {$removemigrationtemp = $migrationspace.tmpspacehousekeeping}  	# Now it will only override the config setting if it was set to remove and the space was found to already exist


	# Obtain relevant attributes for every cloud user (this is now done once at the outset to avoid individual api calls per object owner)
	try {
		
		Write-QlikLog "Obtaining relevant attributes for every cloud user..." -echo
		$cloudUsers = Get-QlikUsers "email,id,subject"
		
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


	# Get the id of the fallbackObjectOwner, if a $fallbackObjectOwnerEmail is set in the configuration
	try {
		if ($null -ne $fallbackObjectOwnerEmail -and $fallbackObjectOwnerEmail -ne "" -and $fallbackObjectOwnerEmail -ne " ") {
			$fallbackOwnerId = $cloudUserLookupByEmail[$fallbackObjectOwnerEmail]
		} else {
			Write-QlikLogWarning "A fallback object owner was not provided in the config settings. Any private objects that do not have a corresponding user in the cloud will not be migrated."
			$fallbackOwnerId = $null
		}
	} catch {
		throw "Encountered an error looking up the user Id of the fallback object owner. Please review the value provided in the fallbackObjectOwnerEmail config setting"
	}


	# Begin looping through apps
	try {
		foreach ($app in $apps) {

			# A few app variables, more to be determined
			$appId = $app.AppID
			$spaceName = $app.SpaceName

			# Enrich the app data for this app, and determine target app owner's UserId
			try{
				$thisApp = qlik qrs app get $appid --context $QlikWindowsContext --insecure | ConvertFrom-Json
				If (-not $thisApp.id) {
					Write-QlikLogError "Failed to retrieve information for this app from on-prem repository. Skipping this app."
					continue 			# Move to next app
				}

				# More app variables
				$appName = $thisApp.name
				$appOnPremOwnerSubject = $($thisApp.owner.userDirectory + '\' + $thisApp.owner.userId)
				$appOnPremOwnerName = $thisApp.owner.name

				# Log section header for this app
				Write-QlikLogHeader "Migrating AppId: $($appId)        App Name: $($appName)        Target Space: $($spaceName)" -echo
				
				Write-QlikLog "On-Prem App Owner: $($appOnPremOwnerName)" -echo
				Write-QlikLog "On-Prem Owner Subject: $($appOnPremOwnerSubject)" -echo

				# Determine the appropriate owner of the cloud app
				
				# Logic: If an app owner was specified in the apps.csv then assign app ownership accordingly (essentially overriding existing onPrem ownership of the app)
				# Otherwise, use the current onPrem app owner as the app owner in the cloud
				# If the onPrem app owner cannot be resolved to a cloud user, then assign app ownership to the qlik-cli user)

				# Check if an app owner was supplied
				if ($app.AppOwnerEmail -ne "-" -and $null -ne $app.AppOwnerEmail -and $app.AppOwnerEmail -ne "" -and $app.AppOwnerEmail -ne " ") {
					
					Write-QlikLog "An email was specified as the target owner for this app." -echo

					$appOwneremail = $app.AppOwnerEmail
					Write-QlikLog "Target Owner Email: $($appowneremail)" -echo
					
					# Assign the cloud userid owner based on the email supplied in the apps.csv
					if ($null -ne $appowneremail) {
						$userId = $cloudUserLookupByEmail[$appowneremail]
					} else {
						$userId = $null
					}
					# If the provided user email can't be matched to a cloud user, then fallback to the qlik-cli user for app ownership
					if ($null -eq $userId) {
						Write-QlikLogWarning "Error retrieving user with email ($appowneremail), the owner of $($appName)."
						Write-QlikLogWarning "Ownership of $($appName) has been assigned to the qlik-cli user."
						$userId = $cliUserId
					}
				
				}else{
					
					# No app owner provided, assign ownership to existing onPrem app owner

					Write-QlikLog "App ownership will be assigned to the same user as in on-prem (an owner override was not specified for this app in the input file)." -echo

					# Find the corresponding cloud userid by matching the on-prem subject against the list of all cloud users
					# IMPORTANT: If user subjects in cloud don't match 'directory\userId', use a different approach to find the correct cloud user for object ownership assignment
					$onPremSubject = $appOnPremOwnerSubject
					if ($null -ne $onPremSubject) {
						$userId = $cloudUserLookupBySubject[$onPremSubject]
					} else {
						$userId = $null				# Avoid null array index error
					}

					if ($null -eq $userId) {
						Write-QlikLogWarning "No matching cloud user found for $($onPremSubject), the owner of $($appName)."
						Write-QlikLogWarning "Ownership of $($appName) has been assigned to the qlik-cli user."
						$userId = $cliUserId
					}

				}
			
				Write-QlikLog "Target Owner's UserId in Cloud: $($userId)" -echo

			} catch {

				Write-QlikLogError "Encountered an error retrieving app-level attributes from On-Prem and determining app ownership [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}


			# Identify the target space characteristics
			try {
				$spaceType = ""
				$spaceId = ""
				$spaceOwnerId = ""
				$spacefriendlyname = ""
				$spaceExists = $false

				if($spaceName -eq '-' -or $spaceName -eq 'Work' -or $spaceName -eq 'Personal' -or $null -eq $spaceName)
				{
					$spaceType = "personal"
					$spacefriendlyname = "Personal space"

				}else{

					# Check cli user privileges on the target space and return the details of the target space
					$targetSpace = cliuserspaceuploadprivileges `
					-evaluatedpacename $spaceName `
					-evaluatedspaceuserid $cliUserId `
					-createmissing $false `
					-evaluatedspacecreatetype "" `
					-evaluatedspacedescription "" `
					-evaluatedspacecmdinfotext ""


					if(-not $targetSpace.id){
						throw "The target space for this app does not exist."
					}

					# Set the attributes of the target space as variables
					$spaceType = $targetSpace.spacetype
					$spaceId = $targetSpace.id
					$spaceOwnerId = $targetSpace.spaceownerid
					$spacefriendlyname = "$($spaceName)"

				}

			} catch {

				Write-QlikLogError "Encountered an error retrieving the target space details [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}


			# If this is a publish update operation, verify that the conditions of a publish update are in place. If the target app is currently staged, move it to the target space.
			# TODO: Beyond checking that the app exists in the cloud, also check that it is responsive (not corrupted, not exceeding capacity). See function Confirm-QlikApp.
			Try {
				If ($publishMode -eq 'update') {

					If ($spaceType -eq 'managed') {

						# Get the properties of the target app in the cloud
						$targetCloudApp = qlik app get $appid --context $QlikCloudContext | ConvertFrom-Json

						if ($targetCloudApp.attributes.id) {								# If the target app exists

							if ($targetCloudApp.attributes.spaceId) {						# If the target app is not in staged, i.e. it resides in a space (safely presumed to be in a managed space since the appId is the same as onPrem)

								if ($targetCloudApp.attributes.spaceId -ne $spaceId) {		# If the target app does not currently reside in the target space

									Write-QlikLogWarning "The target cloud app currently exists in a space other than the target space. It will be moved to '$($spaceName)' as part of this migration process."

								}

							} else {											# Else the target app exists in staged

								# Move the app from staged to the target space now, otherwise subsequent app operations will fail if performed on a staged app
								qlik app space update $appid --spaceId $spaceId --context $QlikCloudContext -q | Out-Null
								
							}

						} else {

							Write-QlikLogError "The publish mode is currently set to 'update' and the target cloud app does not exist in the cloud tenant. Skipping this app"
							continue 			# Move to the next app

						}

						# Confirm that the app is responsive in the cloud (this could be a corruption issue, the app could exceed capacity, no permissions to app, etc)
						$appConfirmation = Confirm-QlikApp -app $appId

						If($appConfirmation.Success){

							Write-QlikLog "Target AppId $($appId): Responded successfully" -echo

						}elseif ($appConfirmation.Error = 5) {

							Write-QlikLogWarning "The app exists in Qlik Cloud, but app responsiveness could not be verified due to GENERIC ACCESS DENIED."
 						
						} else {
						
							throw "Target AppId $($appId) responded with an error: $($appConfirmation.ErrorDetails)" 
						
						}
						

					} else {

						Write-QlikLogWarning "The target space for this app is a $($spaceType) space. The publish mode of 'update' is not relevant in this case and will be ignored."

					}

				}
			
			} catch {

				Write-QlikLogError "Encountered an error verifying that the conditions of a publish update are in place [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}
			

			# Export the app from onPrem, then immediately load the app object metadata from onPrem
			$exportAppFile = ""
			$appObjects = @{}

			# Construct the filter string for the object details retrieval based on the exportScope
			if ($exportScope -eq 'all') {
				$objectFilter = "app.id eq $($appid)"
			} elseif ($exportScope -eq 'approved') {
				$objectFilter = "app.id eq $($appid) and approved eq true"
			} elseif ($exportScope -eq 'published') {
				$objectFilter = "app.id eq $($appid) and published eq true"
			}

			try {

				$exportAppFile = Join-Path -Path $appsdir -ChildPath "$appid.qvf"
				qlik context use $QlikWindowsContext | out-null

				Write-QlikLog "Exporting the app to local storage..." -echo		
				qlik qrs app export create $appid --skipdata $SS --exportScope $exportScope --output-file $exportAppFile

				Write-QlikLog "Retrieving details of $($exportScope) app objects from the on-prem repository..." -echo	
				$appObjects = qlik qrs app object full --filter "$objectFilter" --insecure | ConvertFrom-Json
				
				qlik context use $QlikCloudContext | out-null

			} catch {

				Write-QlikLogError "Encountered an error exporting the app from On-Prem [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}

			# Import the app into the temporary migration space
			$cloudAppId = ""
			try {

				$cloudApp = qlik app import -f $exportAppFile --spaceId $migrationSpaceId | ConvertFrom-Json
				
				If ($cloudApp.attributes.id) {
					$cloudAppId = $cloudApp.attributes.id
				} else {
					throw "Cloud App Id not present"
				}

			} catch {

				Write-QlikLogError "Encountered an error importing the app into the temporary migration space [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}
			
			try {

				# Loop through all app objects and define additional attributes in $thisObjectAttributes table, accumulate them all into $objectAttributes
				
				if ($null -eq $appObjects) {
					
					throw "No objects were returned for this app"
				
				} else {

					Write-QlikLogHeader "Processing attributes of all app objects to determine ownership and necessary actions." -echo -character '-'

					#$objectAttributes = @()														# An array that will accumulate a hashtable for all sheet, bookmark, story objects
					$objectAttributes = New-Object System.Collections.Generic.List[Hashtable]		# Initialize $objectAttributes as a List[Hashtable] a more efficient data structure for accumulation

					$thisObjectAttributes = @{}														# Stores attributes for an individual appobject, reset each loop

					# Variables to store individual object attributes
					$objectOwnerSubject = $null
					$objectId = $null
					$objectName = $null
					$objectType = $null
					
					# Variables for progress bar operation
					$appObjectsCount = $appObjects.Count
					$index = 0

					foreach($i in $appObjects) {
						
						$index++
						Write-Progress -Activity "Processing App Objects" -Status "Processing object $index of $appObjectsCount" -PercentComplete (($index / $appObjectsCount) * 100)

						$objectType = $i.objectType
						$objectPublishd = $i.published
						$objectApproved = $i.approved

						# Ignore processing of any private objects if specified to not migrate this object type in config settings
						if ((-not $objectPublished) -and
							(($objectType  -eq 'sheet' -and -not $migratePrivateSheets) -or 
							($objectType  -eq 'bookmark' -and -not $migratePrivateBookmarks) -or 
							($objectType  -eq 'story' -and -not $migratePrivateStories) -or
							($objectType  -eq 'snapshot' -and -not $migratePrivateSnapshots))) {
							continue
						}

						# Ignore processing of any objectTypes that are not specified to process in config settings
                        if ($objectTypesToProcess -notcontains 'all' -and $objectType -notin $objectTypesToProcess) {
                            continue
                        }

						try {
							
							Write-QlikLog "OBJECTID: $($i.engineObjectId) OBJECTNAME: $($i.name)" -echoVerbose

							# IMPORTANT: If user subjects in cloud don't match 'directory\userId', this will need to be adjusted to find the correct cloud user for object ownership assignment
							# Set the user subject
							$objectOwnerSubject = $($i.owner.userDirectory + '\' + $i.owner.userId)
							
							$objectId = $i.engineObjectId
							$objectName = $i.name

							$thisObjectAttributes = @{}	# Attributes for this appobject, reset for each $i

							$thisObjectAttributes.Add("onPremId", $objectId)
							$thisObjectAttributes.Add("objectType", $objectType)
							$thisObjectAttributes.Add("onPremSubject", $objectOwnerSubject)

							$thisObjectAttributes.Add("onPremName", $objectName)
							$thisObjectAttributes.Add("onPremIsPublished", $objectPublishd)
							$thisObjectAttributes.Add("onPremIsApproved", $objectApproved)
							
							# Find the corresponding cloud userid by matching the on-prem subject against the list of all cloud users
							if ($null -ne $objectOwnerSubject) {
								$cloudOwnerId = $cloudUserLookupBySubject[$objectOwnerSubject]
							} else {
								$cloudOwnerId = $null
							}

							# Set the cloud owner Id. If not identified then set ownership to the fallback user. If no fallback user then ignore the object
							if ($cloudOwnerId) {
								$thisObjectAttributes.Add("cloudTargetUserId", $cloudOwnerId)
								$thisObjectAttributes.Add("flagCloudOwnerFound", $true)
							} else {
								Write-QlikLogWarning "No matching cloud user found for $($objectOwnerSubject), the owner of $($objectType) named $($objectName)."
								$thisObjectAttributes.Add("flagCloudOwnerFound", $false)
								
								If ($fallbackOwnerId) {
									$thisObjectAttributes.Add("cloudTargetUserId", $fallbackOwnerId)
									Write-QlikLogWarning "^ Object ownership assigned to $($fallbackObjectOwnerEmail)"
								} else {
									# Make sure that base content objects are not lost, otherwise ignore the object
									if($objectApproved) {
										$thisObjectAttributes.Add("cloudTargetUserId", $cliUserId)
										Write-QlikLogWarning "^ This is a base content (i.e., approved) object with no matching cloud user. Since a fallback object owner was not provided in the configuration, object ownership has been set to the cli user to preserve this approved object."
									} else {
										$thisObjectAttributes.Add("cloudTargetUserId", $null)
										Write-QlikLogWarning "^ This object will not be migrated (the object is not base content)."
										continue	# Skip this object, it will not be added to $objectAttributes
									}
								}

							}

							# Get app object layout to determine publish, approve, ownerId
							$thisObjectLayout = @{}
							
							if($objectType -eq "masterobject" -or $objectType -eq "app_appscript"){
								
								# The values can be inferred for certain objects (this is to avoid uneccessary api calls and to avoid a known issue with duplicated Json keys in Vizlib masterobjects)
								$thisObjectAttributes.Add("cloudLayoutOwnerId", $cliUserId)
								$thisObjectAttributes.Add("cloudLayoutIsPublished", $true)
								$thisObjectAttributes.Add("cloudLayoutIsApproved", $true)

							} else {
								
								try{
									if($objectType -eq "dimension" -or $objectType -eq "measure"){
										
										$thisObjectLayout = qlik app $objectType layout $objectId -a $cloudAppId --no-data | ConvertFrom-Json

									} elseif ($objectType -eq "snapshot" -or $objectType -eq "bookmark") {

										$thisObjectLayout = qlik app bookmark layout $objectId -a $cloudAppId --no-data | ConvertFrom-Json

									} else {

										$thisObjectLayout = qlik app object layout $objectId -a $cloudAppId --no-data | ConvertFrom-Json

									}
								} catch {
									Write-QlikLogError "Encountered an error retrieving app object layout for $($objectType) object, named '$($objectName)' with objectID $($objectId). This is likely due to unprintable characters in the object's name. [DETAILS: $($_.Exception.Message)]"
									Write-QlikLogSeparator -echo
									continue
								}
								$thisObjectAttributes.Add("cloudLayoutOwnerId", $thisObjectLayout.qMeta.ownerId)
								$thisObjectAttributes.Add("cloudLayoutIsPublished", $thisObjectLayout.qMeta.published)
								$thisObjectAttributes.Add("cloudLayoutIsApproved", $thisObjectLayout.qMeta.approved)

							}


							# Object flags
							#$thisObjectAttributes.Add("flagPrivate", $thisObjectAttributes.cloudLayoutIsPublished -ne $true)
							$thisObjectAttributes.Add("flagOwnerUpdateNeeded", $thisObjectAttributes.cloudTargetUserId -ne $thisObjectAttributes.cloudLayoutOwnerId)
							
							Write-QlikLog ">>> TYPE:$($objectType) PUBLISHED:$($i.published) APPROVED:$($i.approved)" -echoVerbose
							Write-QlikLog "___ ON-PREM OWNER:$($objectOwnerSubject) CORRESPONDING CLOUD USER:$($cloudOwnerId)" -echoVerbose
							Write-QlikLogSeparator -v
							#TODO: This shoud be recreated as a .NET System.Collections.Generic.List[T] to be much more efficient. Will also require changing the reference to elements. Alternatively, just add properties to the $appObjects
							#$objectAttributes = $objectAttributes + $thisObjectAttributes
							$objectAttributes.Add($thisObjectAttributes)
							
						} catch {

							Write-QlikLogError "Encountered an error retrieving app object attributes [$($_.Exception.Message)]"
							Write-QlikLogError "Skipping this object."
							continue 		# Move to next object

						}

					}

					Write-Progress -Activity "Processing Completed" -Completed
					
					Write-QlikLogHeader "Found $($objectAttributes.Count) app objects that will require processing." -echo -character '+'

					# Release variables to be safe
					$objectOwnerSubject = $null
					$objectId = $null
					$objectName = $null
					$objectType = $null

				}


				# Take appropriate actions and make ownership adjustments based upon the target space type (and consider the publish mode if the target is managed)
				
				# If migrationg to a PERSONAL SPACE, assign the app objects, move the app to personal, assign app ownership, and done
				if ($spaceType -eq "personal") {

					Write-QlikLog "App is targeted to be imported into the user's 'personal' space. Making any necessary adjustments to object ownership." -echo

					foreach ($appObject in $objectAttributes) {	

						# Ensuring correct assignation of object/bookmark ownership
						if($appObject.flagOwnerUpdateNeeded -eq $true){
							Write-QlikLog " Set Owner >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) NAME:$($appObject.onPremName) OWNER:$($userId)" -v
							Update-QlikAppObjectOwner -appId $cloudAppId -objectId $appObject.onPremId -ownerId $userId | out-null
						} else {
							Write-QlikLog " No Change --- OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) NAME:$($appObject.onPremName) OWNER:$($userId)" -v
						}

					}

					Write-QlikLog "Moving app to the personal space." -echo
					qlik app space rm $cloudAppId -q | Out-Null

					# Assigning the rightful app ownership
					Write-QlikLog "Assigning ownership of the app." -echo
					qlik app owner $cloudAppId --ownerId $userId -q | Out-Null


				} elseif ($spaceType -eq "shared") {

					Write-QlikLog "App is targeted to be imported into a $($spaceType) space named '$($spaceName)'" -echo

					foreach ($appObject in $objectAttributes) {	

						# Ensuring correct assignment of object ownership
						if ($appObject.flagOwnerUpdateNeeded -eq $true) {
							Write-QlikLog "Set Owner >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
							Update-QlikAppObjectOwner -appId $cloudAppId -objectId $appObject.onPremId -ownerId $appObject.cloudTargetUserId  | Out-Null
						} else {
							Write-QlikLog "No Change --- OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
						}

					}

					Write-QlikLog "Moving app to the target shared space." -echo
					qlik app space update $cloudAppId --spaceId $spaceId -q | Out-Null

					Write-QlikLog "Assigning ownership on the target app." -echo
					qlik app owner $cloudAppId --ownerId $userId -q | Out-Null

				} elseif ($spaceType -eq "managed") {

					# If in publish create mode, the cloudappid will become the target app, establishing a new appId. The app copy will become the shared developer source app.
					# If in publish update mode,the original cloudappid will serve as a temporary app to carry over private content to the existing appId, the app copy will be the final source app.

					Write-QlikLog "The publishMode configuration is set to: $($publishMode)" -echo

					# If in create mode, we want to assign ownership to the target app at this point before the publish create operation
					if ($publishMode -eq "create") {

						Write-QlikLog "Updating ownership assignments for objects in the target app." -echo

						foreach ($appObject in $objectAttributes) {	

							# Ensuring correct assignment of object ownership
							if ($appObject.flagOwnerUpdateNeeded -eq $true) {
								Write-QlikLog "Set Owner >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
								Update-QlikAppObjectOwner -appId $cloudAppId -objectId $appObject.onPremId -ownerId $appObject.cloudTargetUserId  | Out-Null
							} else {
								Write-QlikLog "No Change --- OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
							}

						}
					}

					# Duplicating the app, which will end up becoming the source app for the published one in the managed space
					Write-QlikLog "Duplicating the app to serve as the source app for the published app." -echo
					$appCopyId = (qlik app copy $cloudAppId | ConvertFrom-Json).attributes.id

					# Run the function to make sure that the shared space exists and if not create it (making sure that the cli user has adequate permission)
					$managedplaceholderspace = cliuserspaceuploadprivileges `
					-evaluatedpacename $sourceAppsSharedSpace `
					-evaluatedspaceuserid $cliUserId `
					-createmissing $true `
					-evaluatedspacecreatetype "shared" `
					-evaluatedspacedescription "This is a temporary space created to support the migration process. Unless something went wrong, it should be automatically deleted once the script finishes its execution." `
					-evaluatedspacecmdinfotext ""
								

					# Publishing the app to the target managed space
					# Either create a new appID (publishmode = 'create') or publish over the existing distributed app that has the same appId as the onPrem app (publishmode = 'update')

					if ($publishMode -eq "create") {

						# Publishing the app to the target managed space as a new appID
						# Remember we've got a copy of the original app in this case ($appCopyId) vs the original ($cloudAppId), the latter which has already had it's objects assigned
						
						Write-QlikLog "Moving the source app to the shared space named '$($sourceAppsSharedSpace)'." -echo
						Write-QlikLog "Once the migration is completed, you may review the source app and move it to another shared space if needed." -echo
						qlik app space update $cloudAppId --spaceId $managedplaceholderspace.id -q | out-null
						qlik app space update $appCopyId --spaceId $managedplaceholderspace.id | out-null
						
						# Placing the app(s) in the temporary shared space. This space will persist after running the script so you can move the source app to a space of your choosing
						Write-QlikLog "Publishing the target app to the target space named '$($spacefriendlyname)' in publish create mode." -echo
						qlik app publish create $cloudAppId --moveApp --originAppId $appCopyId --spaceId $spaceId -q | Out-Null
					
					} elseif ($publishMode -eq "update") {

						# Publishing the app as an update to the existing app in the managed space
						Write-QlikLog "Moving the source app to the supporting shared space named '$($sourceAppsSharedSpace)'." -echo
						Write-QlikLog "Once the migration is completed, you may review the source app and move it to another shared space if needed." -echo
						qlik app space update $cloudAppId --spaceId $managedplaceholderspace.id -q | out-null

						if ($exportScope -ne 'all') {
							Write-QlikLogWarning "Skipping step to transfer private content to the target app, because the exportScope was not set to 'all'."
							Write-QlikLog "Removing the temporary source app that would have been used to transfer private content to target app." -echo
							qlik app rm $cloudAppId -q
						} else {

							Write-QlikLog "Preparing a temporary source app to publish it as an update to the existing target appId: '$($appid)'" -echo

							# First publish and approve private objects temporarily, so that they carry over in the publish operation
							Write-QlikLogSeparator -echo
							Write-QlikLog "Publishing private objects in the temporary source app, so that they will carry over to the target app." -echo
							Write-QlikLog "Unpublishing community objects in the temporary source app, so that they will not carry over to the target app." -echo
							Write-QlikLogSeparator -echo

							$objectAttributesCount = $objectAttributes.Count
							$index = 0

							foreach ($appObject in $objectAttributes) {	

								$index++
								Write-Progress -Activity "Publishing/Unpublishing Objects in the Temp Source App" -Status "Processing object $index of $objectAttributesCount" -PercentComplete (($index / $objectAttributesCount) * 100)

									# Publish all private content except those with unknowns owners
									if ($appObject.onPremIsPublished -eq $false -and $null -ne $appObject.cloudTargetUserId) {
							
										Write-QlikLog "Temporarily Publishing   >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
										Publish-QlikAppObject -object $appObject.onPremId -app $cloudAppId -type $appObject.objectType | Out-Null

									# Unpublish all base and community content
									} elseif ($appObject.onPremIsApproved -eq $false) {
							
										Write-QlikLog "Temporarily Unpublishing >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
										Unpublish-QlikAppObject -object $appObject.onPremId -app $cloudAppId -type $appObject.objectType | Out-Null

									}
							}

							Write-Progress -Activity "Creation of temp source app completed" -Completed

							# Now publish the app as an update
							Write-QlikLogSeparator -echo
							Write-QlikLog "Publishing the temporary source app as an update to the target app (transferring private content)." -echo
							qlik app publish update $($cloudAppId) --data "target" --targetId $($appid) --checkOriginAppId=false -q | out-null

							
							Write-QlikLog "Removing the temporary source app that was used to transfer private content to target app." -echo
							qlik app rm $cloudAppId -q
							
							# Remove the space assignment of the target app temporarily to make adjustments (essentially making it a personal space app temporarily)
							# Reset the private objects back to private, the published objects back to published
							# (ignore the community objects because they will come from the multi-cloud distribution)

							Write-QlikLogHeader "Unpublishing private objects in the target app and setting the appropriate ownership." -echo -character '-'
							Write-QlikLog "Temporarily moving the app to a personal space to allow these changes." -echo
							Write-QlikLogSeparator -echo
							qlik app space rm $appid -q | Out-Null

							$index = 0

							foreach ($appObject in $objectAttributes) {	

								$index++
								Write-Progress -Activity "Unpublishing Private Objects in the Target App" -Status "Processing object $index of $objectAttributesCount" -PercentComplete (($index / $objectAttributesCount) * 100)

								# Remember that we are undoing what was done previously. e.g., If not published, then it was published, so now we unpublish
								if($appObject.onPremIsPublished -eq $false -and $null -ne $appObject.cloudTargetUserId){

									Write-QlikLog "Unpublishing >>> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName)" -v
									Unpublish-QlikAppObject -object $appObject.onPremId -app $appid -type $appObject.objectType | Out-Null

									# Change private content to original owner	
									Write-QlikLog "Changing owner of objectid:$($appObject.onPremId) Cloud Owner Id:$($appObject.cloudTargetUserId) On-Prem Name:$($appObject.onPremName)" -v
									Update-QlikAppObjectOwner -appId $appid -objectId $appObject.onPremId -ownerId $appObject.cloudTargetUserId  | Out-Null
								
								}

							}

							Write-Progress -Activity "Completed unpublishing private objects in target apps" -Completed

						}

						# Move the app back to the target managed space (if private content was not moved this is still done to ensure that the managed app finishes in the target space)
						Write-QlikLogSeparator -echo
						Write-QlikLog "Moving the target app to the target managed space." -echo
						Write-QlikLogSeparator -echo
						qlik app space update $appid --spaceId $spaceId -q | Out-Null


						} else {

							Write-QlikLog "Error: Unknown publish mode. Please review the migrateapps_config settings to set a valid publish mode." -echo
						
						}

						# Removing personal objects from the source app (in the shared space)
						# Or otherwise delete it if the removesharedapp config variable is set to $true
						if ($removeSharedApp -eq $true) {

							Write-QlikLog "Removing source app in the shared space, as indicated in the configuration." -echo
							qlik app rm $appCopyId -q | Out-Null
							$appCopyId = $null

						} elseif ($exportScope -ne 'approved') {

							Write-QlikLogHeader "Performing a cleanup of the source app by removing all 'non-approved' contents: " -echo -character '-'

							$objectAttributesCount = $objectAttributes.Count
							$index = 0

							foreach($appObject in $objectAttributes) {	

								$index++
								Write-Progress -Activity "Cleanup of Non-Approved Objects in the Source App" -Status "Processing object $index of $objectAttributesCount" -PercentComplete (($index / $objectAttributesCount) * 100)

								Write-QlikLogSeparator -v
								Write-QlikLog "Processing  >> OBJECT ID:$($appObject.onPremId) TYPE:$($appObject.objectType) PUBLISHED:$($appObject.onPremIsPublished) APPROVED:$($appObject.onPremIsApproved) NAME:$($appObject.onPremName) OWNER:$($userId)" -v

								if($appObject.cloudLayoutIsApproved -eq $false){

									if($appObject.cloudLayoutIsPublished -eq $true){

										Write-QlikLog "            >> Unpublishing" -v
										Unpublish-QlikAppObject -object $appObject.onPremId -app $appCopyId -type $appObject.objectType | Out-Null
			
									}
									
									Write-QlikLog "            >> Removing" -v
									
									if ($appObject.objectType -eq "dimension" -or $appObject.objectType -eq "measure") {
										
										qlik app $appObject.objectType rm $appObject.onPremId --app $appCopyId --no-data --no-save | out-null

									} elseif ($appObject.objectType -eq "snapshot" -or $appObject.objectType -eq "bookmark") {

										qlik app bookmark rm $appObject.onPremId --app $appCopyId --no-data --no-save | out-null

									} elseif ($appObject.objectType -ne "app_appscript") {

										qlik app object rm $appObject.onPremId --app $appCopyId --no-data --no-save | out-null
										
									}
								}
							}
							
							#Now save changes
							qlik app build --app $appCopyId --no-reload	--no-data | Out-Null						

							Write-Progress -Activity "Removal of non-approved content in the source app completed" -Completed

						}

						# With an "update" publish mode, we still need to set the space of the source app and the publish it once more to establish the publish relationship
						If ($publishMode -eq "update" -and $removeSharedApp -eq $false) {
							
							# Set the space of the appcopy, which will now become the source app
							Write-QlikLog "Moving the source app to the shared space." -echo
							qlik app space update $appCopyId --spaceId $managedplaceholderspace.id -q | out-null

							# Publish once again to reestablish the publish association between source and target app
							Write-QlikLog "Publishing the source app to the target app, to establish the publish association." -echo
							qlik app publish update $($appCopyId) --data "target" --targetId $($appid) --checkOriginAppId=false -q | out-null

							# Assign ownership of the source app
							qlik app owner $appCopyId --ownerId $userId -q | Out-Null

						}

						# DISABLED: Need to decide if granting user level access to the space is more trouble than it is worth. Possible function to check for access via group.
						#$targetSpace = cliuserspaceuploadprivileges $sourceAppsSharedSpace $userId $false "" "" ""

						# DISABLED: Need to decide if granting user level access to the target space is more trouble than it is worth. Possible function to check for access via group.
						#$targetSpace = cliuserspaceuploadprivileges $spaceName $userId $false "" "" ""

						Write-QlikLog "Assigning ownership on the target app." -echo
						If($publishMode -eq "create"){

							qlik app owner $cloudAppId --ownerId $userId -q | Out-Null

						}elseif($publishMode -eq "update"){

							qlik app owner $appid --ownerId $userId -q | Out-Null

						}

				} else {

					Write-QlikLog "Warning: the app is targeted to be imported in a space that does not exist in the tenant. Please add the '$($spaceName)' space to your tenant and re-import the app." -echo
				
				}

			} catch {

				Write-QlikLogError "Encountered an error while establishing this app in the cloud [$($_.Exception.Message)]"
				Write-QlikLogError "Skipping this app."
				continue 		# Move to next app

			}


			Write-QlikLogHeader "Done: the app '$($appname)' is now migrated to $($spacefriendlyname)" -echo
			Write-QlikLogSeparator -echo

			if ($spaceType -eq "personal") {
				
				Write-QlikLog "Personal App (for the app owner only): $($tenanturl)/sense/app/$($cloudAppId)" -echo
				Write-QlikLog "Personal Space (for the app owner only): $($tenanturl)/catalog?space_filter=personal" -echo
				# Construct appID mapping for output to file (AppID, CloudAppID, DevCopyID, MigrationType, ExportScope, LogFile)
            	$outputLine = "$appId,$cloudAppId,$null,personal,$exportScope,$Global:QlikLogFileName"

			}
			elseif ($spaceType -eq "shared") {
				
				Write-QlikLog "Shared App: $($tenanturl)/sense/app/$($cloudAppId)" -echo
				Write-QlikLog "Shared Space: $($tenanturl)/catalog?space_filter=$($spaceId)" -echo
				# Construct appID mapping for output to file (AppID, CloudAppID, DevCopyID, MigrationType, ExportScope, LogFile)
            	$outputLine = "$appId,$cloudAppId,$null,shared,$exportScope,$Global:QlikLogFileName"

			} elseif ($spaceType -eq "managed") {

				if ($publishMode -eq 'create') {

					Write-QlikLog "Published App: $($tenanturl)/sense/app/$($cloudAppId)" -echo
					# Construct appID mapping for output to file (AppID, CloudAppID, DevCopyID, MigrationType, ExportScope, LogFile)
            		$outputLine = "$appId,$cloudAppId,$appCopyId,managed-create,$exportScope,$Global:QlikLogFileName"
				
				} elseif ($publishMode -eq 'update'){

					Write-QlikLog "Published app: $($tenanturl)/sense/app/$($appid)" -echo
					# Construct appID mapping for output to file (AppID, CloudAppID, DevCopyID, MigrationType, ExportScope, LogFile)
            		$outputLine = "$appId,$appId,$appCopyId,managed-update,$exportScope,$Global:QlikLogFileName"
				}

				Write-QlikLog "Shared App: $($tenanturl)/sense/app/$($appCopyId)" -echo
				Write-QlikLog "Shared Space: $($tenanturl)/catalog?space_filter=$($managedplaceholderspace.id)" -echo


			}
			# Append the IDs to the CSV output file
			Add-Content -Path $appsCreatedFilePath -Value $outputLine
			Write-QlikLogSeparator -echo

		}

	} catch {

		Write-QlikLogError "Encountered an unexpected error while processing this app [$($_.Exception.Message)]"
		Write-QlikLogError "Skipping this app."
		continue 		# Move to next app

	} finally {

		if ($null -ne $exportAppFile -and $exportAppFile -ne "") {
			if (Test-Path $exportAppFile) {
				Remove-Item $exportAppFile
			}
		}
		
	}

} catch {

	Write-QlikLogError "Encountered an unexpected error [$($_.Exception.Message)]"

} finally {

	# Always cleanup temp space if it exists and set to remove
	# I don't trust this until the legacy cliuserspaceuploadprivileges function is fully tested. It deleted a target space while testing in PowerShell 7.
	# Write-QlikLogSeparator -echo
	# if($removeMigrationTemp){

	# 	Write-QlikLog "Info: the space $($migrationtempspacename) is no longer needed. Removing it. " -echo
	# 	qlik space rm $migrationSpaceId

	# }else{

	# 	Write-QlikLog "The space $($migrationtempspacename) will persist on your tenant. You may review any apps in this space and remove the space manually if needed. " -echo

	# }

	Write-QlikLogHeader "App migration process concluded." -echo -character '*'

}