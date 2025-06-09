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

Function Get-QlikGroupId {
    param (

        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$context = $QlikCloudContext                      
    )

    try {
        # Get the groupId using a full ls listing, to avoid the many possible issues with --filter syntax between PowerShell versions
        $groupsJson = qlik group ls --limit 1000000 --context $context | ConvertFrom-Json | Select-Object id,name
        $group = $groupsJson | Where-Object { $_.name -eq $name }

        if ($group) {
            $groupId = $group.id
        } else {
            throw "Failed to find Id for group $name."
        }

        return $groupId

    } catch {
            return $null
    } 

}


function Create-QlikGroup(){

# The script only creates the groups. The assignment of Roles to groups is not supported in this script at this point. 

   param (

        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$context = $QlikCloudContext                      
    )


   try {
        #create the group, get $groupId
        $groupId = $(qlik group create --name $name --context $context -q)

        if (-not $groupId) {
            throw "Failed to create group $name."
        }

        return [pscustomobject]@{
            Success     = $true
            Name        = $name
            GroupId     = $groupId
        }

    } catch {
            return [pscustomobject]@{
                Success = $false
                Name    = $name
                Error   = $_.Exception.Message
            }
    } 

}

function Remove-QlikGroup(){

   param (

        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$context = $QlikCloudContext                      
    )
    
   try {
        #get the $groupID of the group name, then remove the group
        $groupId = Get-QlikGroupId "$name"

        if (-not $groupId) {
            throw "Failed to remove group $name."
        } else {
			$(qlik group rm $groupId -q)
        }	

        return [pscustomobject]@{
            Success     = $true
            Name        = $name
            GroupId     = $groupId
        }

    } catch {
            return [pscustomobject]@{
                Success = $false
                Name    = $name
                Error   = $_.Exception.Message
            }
    } 

}
