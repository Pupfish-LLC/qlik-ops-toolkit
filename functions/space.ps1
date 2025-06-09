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

function Create-QlikSpace {
    param (

        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateSet("shared", "managed")]
        [string]$type,

        [Parameter(Mandatory=$false)]
        [string]$description = "",

        [Parameter(Mandatory=$false)]
        [string]$owner = "",                               # Email of target space owner. If not given, cli user will be the owner

        [Parameter(Mandatory=$false)]
        [string]$context = $QlikCloudContext                      
    )

    try {
        #create the space, get $SpaceId
        $spaceId = $(qlik space create --name $name --type $type --description $description --context $context -q)

        if (-not $spaceId) {
            throw "Failed to create space $name."
        }

        #set the owner, if specified. Otherwise the cli user will be the owner.
        if ($owner) {
            $userId =  qlik user ls --email $owner --context $context -q
            if (-not $userId) {
                throw "Owner $owner not found."
            }
            
            qlik space update $spaceId --ownerId $userId --context $context
        }

        return [pscustomobject]@{
            Success     = $true
            Name        = $name
            Type        = $type
            Description = $description
            Owner       = $owner
            SpaceId     = $spaceId
        }

    } catch {
            return [pscustomobject]@{
                Success = $false
                Name    = $name
                Type    = $type
                Error   = $_.Exception.Message
            }
    } 

}


Function Get-QlikSpaceId {
    param (

        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,

        [Parameter(Mandatory=$false, Position=1)]
        [string]$context = $QlikCloudContext                      
    )

    try {
        # Get the spaceId using a full ls listing
        # This method is not efficient for repeated ID lookups, though it avoids the many possible issues with --filter syntax between PowerShell versions
        
        # Capture the output as a single string
        $spacesString = qlik space ls --limit 1000000 --context $context | Out-String 
 
        # Convert the JSON string to an object and select the id and name properties
        $spacesJson = $spacesString | ConvertFrom-Json 
        $spacesJson = $spacesJson | Select-Object id, name 
        
        # Filter for the space with the matching name
        $space = $spacesJson | Where-Object { $_.name -eq $name }
        
        <# Same command in a single pipeline, but known to cause issues in PowerShell 5
            $spacesJson = qlik space ls --limit 1000000 --context $context | ConvertFrom-Json | Select-Object id,name
            $space = $spacesJson | Where-Object { $_.name -eq $name }
        #>

        if ($space) {
            $spaceId = $space.id
        } else {
            throw "Failed to find Id for space $name."
        }

        return $spaceId

    } catch {
            return $null
    } 

}

function Remove-QlikSpaceMember() {

   param (

        [Parameter(Mandatory=$true)]
        [string]$space,

        [Parameter(Mandatory=$false)]
        [string]$group,

        [Parameter(Mandatory=$false)]
        [string]$email,

        [Parameter(Mandatory=$false)]
        [switch]$all,                   # -all flag will remove all member assignments on the space

        [Parameter(Mandatory=$false)]
        [string]$context = $QlikCloudContext                      
    )


    # Check that either group or email is supplied, but not both or neither
    if ((-not $group -and -not $email) -or ($group -and $email)) {
        throw "You must supply either a group or an email, but not both."
    }

    # Check that if -all flag is present then neither group or email are present, since this would be ambiguous
    if (($all) -and ($group -or $email)) {
        throw "Ambiguous input to the Remove-QlikSpaceMember function. The -all flag cannot be applied when a group or user was also provided."
    }

    try {

        $spaceId = Get-QlikSpaceId "$space"

        if (-not $spaceId) {
            throw "The spaceId could not be retrieved for this space name."
        }
            
        if ($group) {
            
            $groupId = Get-QlikGroupId "$group"
            if (-not $groupId) {
                throw "The groupId could not be retrieved for this group name"
            }

        } elseif ($user) {
            throw "User assignment is not yet supported."
        }

        # Get all the existing assigneeIds and the assignmentIds for the space (the assigneeId is the ID of the group)
        $currentassignments = (qlik space assignment ls --spaceId $spaceId | ConvertFrom-Json) | Select-Object id,assigneeId

        # Store just the assigneeIds in a variable, for comparison to the group whose assignment we either want to add or update
        $assigneeIds = $currentassignments | ForEach-Object { $_.assigneeId }

        # Check to see if the assignee already exists in the space
        if ($assigneeIds -contains $groupId) {

            # This group has already been assigned, so remove the assignment
            $assignmentToRemove = $currentassignments | Where-Object { $_.assigneeId -eq $groupId }  # this is the assignment object that needs to be updated (not added)
            $response = qlik space assignment rm $assignmentToRemove.id --spaceId $spaceId -q
            
            if ($response) {

                return [pscustomobject]@{
                    Success         = $true
                    SpaceId         = $spaceId
                    MemberId        = $groupId                    
                    AssignmentId    = $assignmentToRemove.id
                    Type            = "Removed"
                }

            } else {
                throw "Failed to remove assignment for group '$($group)' in space '$($space)'."
            }

        } else {

            # The member doesn't exist in the space, so consider this a success
            return [pscustomobject]@{
                Success         = $true
                SpaceId         = $spaceId
                MemberId        = $groupId                    
                AssignmentId    = $null
                Type            = "Nonexistent"
            }
        
        }

    } catch{

        return [pscustomobject]@{
            Success         = $false
            Error           = $_.Exception.Message
        }

    }

}

<#
function Assign-QlikSpaceMember() {

    # 	If a particular group assignment already exists on a space, the assignment will be updated
    #	If multiple roles are to be assigned, include them on a single record, surrounded by quotes
    #	without any space between the values, i.e. "dataconsumer,producer,codeveloper"

   param (

        [Parameter(Mandatory=$true)]
        [string]$space,

        [Parameter(Mandatory=$false)]
        [string]$group,

        [Parameter(Mandatory=$false)]
        [string]$email,

        [Parameter(Mandatory=$true)]
        [string]$roles,

        [Parameter(Mandatory=$false)]
        [string]$context = $QlikCloudContext                      
    )

    # Check that either group or email is supplied, but not both or neither
    if ((-not $group -and -not $email) -or ($group -and $email)) {
        throw "You must supply either a group or an email, but not both."
    }

    # Load the role aliases from the configuration file
    $configFilePath = "C:\Path\To\Your\roleAliases.json"
    if (-not (Test-Path -Path $configFilePath)) {
        throw "Configuration file not found: $configFilePath"
    }

    try {
        $rolesArray = $roles -split ',' | ForEach-Object { $_.Trim() }
        $mappedRoles = @()

        foreach ($role in $rolesArray) {
            if ($roleAliases.ContainsKey($role)) {
                $aliasRoles = $roleAliases[$role] -split ',' | ForEach-Object { $_.Trim() }
                $mappedRoles += $aliasRoles
            } else {
                throw "Invalid role or alias: $role. Valid roles/aliases are: $($roleAliases.Keys -join ', ')"
            }
        }

        # Ensure unique roles and join them into a single string
        $processedRoles = ($mappedRoles | Sort-Object -Unique) -join ','

    try {

        $spaceId = Get-QlikSpaceId "$space"

        if (-not $spaceId) {
            throw "The spaceId could not be retrieved for this space name."
        }
            
        if ($group) {
            
            $groupId = Get-QlikGroupId "$group"
            if (-not $groupId) {
                throw "The groupId could not be retrieved for this group name"
            }

        } elseif ($user) {
            throw "User assignment is not yet supported."
        }

        # Get all the existing assigneeIds and the assignmentIds for the space (the assigneeId is the ID of the group)
        $currentassignments = (qlik space assignment ls --spaceId $spaceId | ConvertFrom-Json) | Select-Object id,assigneeId

        # Store just the assigneeIds in a variable, for comparison to the group whose assignment we either want to add or update
        $assigneeIds = $currentassignments | ForEach-Object { $_.assigneeId }

        # Check to see if the assignee already exists in the space
        if ($assigneeIds -contains $groupId) {

            # This group has already been assigned, so update the assignment
            $assignmentToUpdate = $currentassignments | Where-Object { $_.assigneeId -eq $groupId }  # this is the assignment object that needs to be updated (not added)
            $response = qlik space assignment update $assignmentToUpdate.id --roles "$roles" --spaceId $spaceId -q
            
            if ($response) {

                return [pscustomobject]@{
                    Success         = $true
                    SpaceId         = $spaceId
                    MemberId        = $groupId                    
                    AssignmentId    = $assignmentToUpdate.id
                    Type            = "Updated"
                }

            } else {
                throw "Failed to update assignment for group '$($group)' in space '$($space)'."
            }

        } else {

            # Create the new assignment
            $assignmentId = qlik space assignment create --spaceId $spaceId --assigneeId $groupId --roles "$roles" --type group -q

            if ($assignmentId) {

                return [pscustomobject]@{
                    Success         = $true
                    SpaceId         = $spaceId
                    MemberId        = $groupId                    
                    AssignmentId    = $assignmentId
                    Type            = "Created"
                }

            } else {
                throw "Failed to create assignment for group '$($group)' in space '$($space)'."
            }
        
        }

    } catch{

        return [pscustomobject]@{
            Success         = $false
            Error           = $_.Exception.Message
        }

    }

}

#>