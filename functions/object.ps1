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

function Publish-QlikAppObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$object,

        [Parameter(Mandatory=$true)]
        [string]$app,
        
        [Parameter(Mandatory=$false)]
        [string]$type,

        [Parameter(Mandatory=$false)]
        [string]$context = $null                       # Use current context unless otherwise specified
    )

    try {

        if ($context) {
            $contextFlag = "--context $context"
        }

        # TODO: Someday find a way to reliably catch errors, until then the stderr is piped to stdout and check for success text, as stderr contains non-error strings

        if($appObject.objectType -eq "dimension" -or $appObject.objectType -eq "measure"){

            $response = qlik app $type publish $object --app $app --no-data $contextFlag 2>&1 | Out-String
            
        }elseif($appObject.objectType -eq "snapshot" -or $appObject.objectType -eq "bookmark"){

            $response = qlik app bookmark publish $object --app $app --no-data $contextFlag 2>&1 | Out-String

        }elseif($appObject.objectType -ne "app_appscript"){

            $response = qlik app object publish $object --app $app --no-data $contextFlag 2>&1 | Out-String

        }

        if ($response -match "Publishing") {
            return $true 
        } else {
            Write-QlikLogError "Issue publishing object type $($type), Id: $($object)"
            return $false
        }

    } catch {
        Write-QlikLogError "Error while publishing object [$($_.Exception.Message)]"
        return $false
    }
}


function Unpublish-QlikAppObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$object,

        [Parameter(Mandatory=$true)]
        [string]$app,
        
        [Parameter(Mandatory=$false)]
        [string]$type,

        [Parameter(Mandatory=$false)]
        [string]$context = $null                       # Use current context unless otherwise specified
    )
    try {

        if ($context) {
            $contextFlag = "--context $context"
        }

        # TODO: Someday find a way to reliably catch errors, until then the stderr is piped to stdout and check for success text, as stderr contains non-error strings

        if($appObject.objectType -eq "dimension" -or $appObject.objectType -eq "measure"){

            $response = qlik app $type unpublish $object --app $app --no-data $contextFlag 2>&1 | Out-String

        }elseif($appObject.objectType -eq "snapshot" -or $appObject.objectType -eq "bookmark"){

            $response = qlik app bookmark unpublish $object --app $app --no-data $contextFlag 2>&1 | Out-String

        }elseif($appObject.objectType -ne "app_appscript"){

            $response = qlik app object unpublish $object --app $app --no-data $contextFlag 2>&1 | Out-String

        }
  
        if ($response -match "Publishing") {
            return $true 
        } else {
            Write-QlikLogError "Issue unpublishing object type $($type), Id: $($object) [$($_.Exception.Message)]"
            return $false
        }

    } catch {
        Write-QlikLogError "Error while unpublishing object [$($_.Exception.Message)]"
        return $false
    }
}


function Update-QlikAppObjectOwner {
    param (
        [Parameter(Mandatory=$true)]
        [string]$objectId,

        [Parameter(Mandatory=$true)]
        [string]$appId,
        
        [Parameter(Mandatory=$true)]
        [string]$ownerId,

        [Parameter(Mandatory=$false)]
        [string]$context = $null                       # Use current context unless otherwise specified
    )

    try {

        if ($context) {
            $contextFlag = "--context $context"
        }
        
        $response = qlik app object change-owner --appId $appId --objectId $objectId --ownerId $ownerId $contextFlag 2>&1 | Out-String

        # Use Select-String with a regex pattern to match lines starting with "Error:"
        $errorLines = $response | Select-String -Pattern 'Error:.*' -AllMatches
        if ($errorLines) {
            $errorLines.Matches.Value | ForEach-Object { Write-QlikLogError "Issue publishing object type $($type), Id: $($object) $_" }
            return $false
        } else {
            return $true
        }

    } catch {
        Write-QlikLogError "Error while changing owner of object [$($_.Exception.Message)]"
        return $false
    }
}