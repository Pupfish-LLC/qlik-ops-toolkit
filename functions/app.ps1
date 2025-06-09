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

function Get-QlikAppIdList {

    param (
        [Parameter(Mandatory=$true)]
        [string]$path,

        [Parameter(Mandatory=$true)]
        [string]$file,

        [Parameter(Mandatory=$true)]
        [string]$property
    )
    
    $fullPath = Join-Path -Path $path -ChildPath $file

    try {
        $appIDs = Import-Csv -Path $fullPath | Select-Object -ExpandProperty "$property"
        return $appIDs
    }
    catch {
        throw "Failed to get app list: $($_.Exception.Message)"
    }

}


function Confirm-QlikApp {

    param (
        [Parameter(Mandatory=$true)]
        [string]$app,

        [Parameter(Mandatory=$false)]
        [string]$context=$QlikCloudContext
    )
    
    try {
        # Run the command and capture both stdout and stderr
        $evalOutput = qlik app eval 1 -a $app --context $context 2>&1 | Out-String

        # Check the last exit code immediately after running the command
        if ($LASTEXITCODE -ne 0) {

            $errorType = ""
            $errorDetails = ""

             # Check for specific error patterns and set a custom error message accordingly
            if ($evalOutput -match "9003 PERSISTENCE NOT FOUND") {
                $errorType = 9003
                $errorDetails = "9003 PERSISTENCE NOT FOUND"
            } elseif ($evalOutput -match "5 GENERIC ACCESS DENIED") {
                $errorType = 5
                $errorDetails = "GENERIC ACCESS DENIED"
            } elseif ($evalOutput -match "1015 APP SIZE EXCEEDED") {
                $errorType = 1015
                $errorDetails = "APP SIZE EXCEEDED"
            } elseif ($evalOutput -match "9001 PERSISTENCE READ FAILED") {
                $errorType = 9001
                $errorDetails = "PERSISTENCE READ FAILED"
            } elseif ($evalOutput -match "Error: the data model is empty") {
                $errorType = "empty"
                $errorDetails = "Data model is empty"
            } elseif ($evalOutput -match "Error: could not connect to engine: session closed before reciving OnConnected message") {
                $errorType = "session closed"
                $errorDetails = "Could not connect to engine: session closed before reciving OnConnected message"
            } else {
                #Fallback error message if no specific patterns are matched
                $errorType = "unspecified"
                $errorDetails = $evalOutput
            }
            
            return @{
                Success = $false
                Error = $errorType
                ErrorDetails = $errorDetails
            }
        }

    } catch {
        # Catch any unexpected errors
        throw "An error occurred while executing the Qlik CLI command: $_"
    }

    # If no error, return success
    return @{
        Success = $true
    }

}


function Unpublish-QlikApp {

    param (
        [Parameter(Mandatory=$true)]
        [string]$app,

        [Parameter(Mandatory=$true)]
        [string]$sharedSpaceId,

        [switch]$preservePrivateContent,

        [Parameter(Mandatory=$false)]
        [string]$ownerId="no change",

        [Parameter(Mandatory=$false)]
        [string]$context=$QlikCloudContext
    )

    try {

        # TODO: Validate that the app is in a managed space and published
        # TODO: Validate that the sharedSpaceId is a shared space

        # Obtain original app attributes
        $appAttributes = (qlik app get $app | ConvertFrom-Json).attributes
        $originalOwnerId = $appAttributes.ownerId
        $originalSpaceId = $appAttributes.spaceId

        # Obtain object list
        Write-QlikLog "Retrieving app objects..." -echo
        $appObjects = qlik app object ls -a $app --json | ConvertFrom-Json
        Write-QlikLog "Retrieved $(($appObjects).Count) app objects." -echo

        # Obtain bookmarks
        Write-QlikLog "Retrieving app bookmarks..." -echo
        $appBookmarks = qlik app bookmark ls -a $app --json | ConvertFrom-Json
        Write-QlikLog "Retrieved $(($appBookmarks).Count) bookmarks." -echo

        # Add qType to each bookmark
        $appBookmarks | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name "qType" -Value "bookmark"
        }
        
        # Combine app objects and bookmarks
        $contentObjects = $appObjects + $appBookmarks
        $contentObjectsCount = $contentObjects.Count
        Write-QlikLog "Combined to $($contentObjectsCount) content objects." -echo

        # Filter the objects to only those that could be private content
        $contentObjects = $contentObjects | Where-Object { $_.qType -in @('sheet', 'bookmark', 'story', 'snapshot') }
        $contentObjectsCount = $contentObjects.Count
        Write-QlikLog "Filtered to $($contentObjectsCount) private content objects." -echo

        Write-QlikLog "Changing owner of app to qlik-cli user." -echo
        qlik app owner $app -q | out-null

        Write-QlikLog "Removing the app from managed space (i.e. moving to a personal space)." -echo
        qlik app space update $app -q | out-null

        Write-QlikLog "Duplicating the app to serve as a shared developer copy." -echo
        $appCopyId = (qlik app copy $app | ConvertFrom-Json).attributes.id

        # Initialize an array to store the IDs and published values of unapproved objects
        #$unapprovedObjects = @()

        if (-not $preservePrivateContent) {

			$index = 0

            foreach ($object in $contentObjects) {

                $index++
                Write-Progress -Activity "Removing Private Content From Shared App" -Status "Removing private object $index of $contentObjectsCount" -PercentComplete (($index / $contentObjectsCount) * 100)

                # Obtain the layout of each object 
                if ($object.qType -eq "snapshot" -or $object.qType -eq "bookmark") {

                    $objectLayout = qlik app bookmark layout $object.qId -a $app --no-data | ConvertFrom-Json

                } else {

                    $objectLayout = qlik app object layout $object.qId -a $app --no-data | ConvertFrom-Json
                    
                }
                
                # Check if object is NOT approved content (i.e. not base content). If it is not, store the id and whether it is published
                if ($objectLayout.qMeta.approved -eq $false) {
                    
                    # Store the qId and published value of the unapproved object
                    #$unapprovedObjects += [PSCustomObject]@{
                    #    id = $objectLayout.qInfo.qId
                    #    published = $objectLayout.qMeta.published
                    #}
                    # Output the unapproved objects
                    #$unapprovedObjects | ForEach-Object {
                    #    Write-Output "id: $($_.id), published: $($_.published)"
                    #}

                    if ($objectLayout.qMeta.published -eq $true) {

                        Unpublish-QlikAppObject -object $objectLayout.qInfo.qId -app $appCopyId -type $objectLayout.qInfo.qType -context $context

                    }

                    if ($objectLayout.qInfo.qType -eq "snapshot" -or $objectLayout.qInfo.qType -eq "bookmark") {

                        qlik app bookmark rm $objectLayout.qInfo.qId --app $appCopyId --no-data --no-save

                    } else {

                        qlik app object rm $objectLayout.qInfo.qId --app $appCopyId --no-data --no-save | out-null
                        
                    }

                }
            }

            #Now save changes
		    qlik app build --app $appCopyId --no-reload	--no-data | Out-Null						
		    Write-Progress -Activity "Removal of non-approved content in the source app completed" -Completed

        }

        Write-QlikLog "Moving the copy to the shared space." -echo
        qlik app space update $appCopyId --spaceId $sharedSpaceId -q | Out-Null

        Write-QlikLog "Establishing ownership of the shared app." -echo
        If ($ownerId -eq "no change") {
            Write-QlikLog "Assigning ownership to same user as the managed app (an alternative owner was not specified)." -echo
            qlik app owner $appCopyId --ownerId $originalOwnerId -q | out-null
        } else {
            Write-QlikLog "A specific owner for the shared app was specified, assigning ownership to UserId: $($newOwnerId)." -echo
            qlik app owner $appCopyId --ownerId $newOwnerId -q | out-null
        }

        #TODO: Add some more detailed error handling
        if ($LASTEXITCODE -eq 0){
            #Write-Host "Success"
            Return $true
        }else{
            throw "Encountered an issue ($_.Exception.Message)"
            Return $false
        }
    
    } catch {

        Write-QlikLogError "Failed to unpublish app: $($_.Exception.Message)"
        return $false

    } finally {

        # Always return ownership and the space of the original app, even if a critical error was encountered during the process 
        Write-QlikLog "Moving the original app back to the managed space." -echo
        qlik app space update $app --spaceId $originalSpaceId -q | Out-Null

        Write-QlikLog "Establish original ownership of original app." -echo
        qlik app owner $app --ownerId $originalOwnerId -q | out-null

    }

}