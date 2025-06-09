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

function Get-QlikUsers {
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [string]$fields = "email,id,subject",

        [Parameter(Mandatory=$false, Position=1)]
        [string]$context = $null                       # Use current context unless otherwise specified
    )

    try {

        $userCount = (qlik user count | ConvertFrom-Json).total

        if ($null -eq $userCount -or $userCount -eq 0) {
            throw "Encountered an error retrieving cloud user count or no users found."
        } else {

            if ($context) {
                $contextFlag = "--context $context"
            }

            $cloudUsers = qlik user ls --fields $Fields --limit $userCount $contextFlag | ConvertFrom-Json | Where-Object { $null -ne $_.email -and $_.email -ne '' }

            return $cloudUsers

        }

    } catch {
        Write-QlikLogError "Encountered an error while retrieving cloud users [$($_.Exception.Message)]" -stop
        return $null
    }
}

function Add-QlikUser {

    ## TODO: To be incorporated into standard architecture and central logging. User creation in operation is standalone and does not utilize this function.

    param (
    [Parameter(Mandatory=$true)]
    [string[]]$userEmail,

    [Parameter(Mandatory=$true)]
    [string[]]$userSubject,	

    [Parameter(Mandatory=$true)]
    [string[]]$userName,	

    [Parameter(Mandatory=$false)]
    [string]$cloudContext = $QlikCloudContext                      
)
    qlik context use $cloudContext

    $users = Import-Csv -Path $DATA\users.csv
    Write-Host "$($users.count) users imported to create"

    #set a $timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

    foreach ($user in $users)
    {
            $email = $user.Email
            #$subject = $($user.userId + '\' + $user.userDirectory)
            $subject = $user.Subject
            $name = $user.Name
            
            try {
                
                $SaaSuserId = qlik user create --email $email --subject $subject --name $name -q
                
                # Check if the output is an error
                if ($SaaSuserId -eq $null) {
                    
                    # Set the error message and throw an error to trigger the catch block
                    $SaaSuserId="Error"
                    $errorMsg = "$email not created"
                    throw
                
                } else {

                    Write-Host "created userId: $SaaSuserId from email: $email subject: $subject" 

                }
            }

            catch {

                Write-Error $errorMsg
                $user | Add-Member -NotePropertyName Error -NotePropertyValue $errorMsg
                continue
            }

            finally {

                $user | Add-Member -NotePropertyName SaaSuserId -NotePropertyValue $SaaSuserId
                $user | Add-Member -NotePropertyName Timestamp -NotePropertyValue $timestamp

            }

    }

    # Export the users log to CSV
    $users | Export-Csv -Path $LOGS\users_log.csv -Append -NoTypeInformation

}

