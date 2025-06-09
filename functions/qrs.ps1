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

function Update-QlikAppWithItself {

    param (
        [Parameter(Mandatory=$true)]
        [string]$app,

        [Parameter(Mandatory=$false)]
        [string]$context=$QlikWindowsContext
    )

    try {

        Write-Host "Copying app..."
        $appCopyId = qlik qrs app copy $app --context $context -q

        if ($LASTEXITCODE -eq 0){
            Write-Host "Success"
        }else{
            Write-Host "Encountered an issue copying the app."
            Return $false
        }
        
        Write-Host "Replacing original app with the copy..."
        $updateCommandOutput = qlik qrs app replace update $appCopyId --app $app --context $context -q

        if ($LASTEXITCODE -eq 0){
            Write-Host "Success"
        }else{
            Write-Host "Encountered an issue while replacing the original app."
            Return $false
        }

        If ($updateCommandOutput -eq $app) {
            Write-Host "Removing copy..."
            qlik qrs app rm $appCopyId --context $context -q | Out-Null
            if ($LASTEXITCODE -eq 0){
                Write-Host "Success"
            }else{
                Write-Host "Encountered issue during removal of copy."
            }
        }else{
            Write-Host "Encountered issue during removal of copy."
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "App distribution for appId $($app) repaired successfully. You will still need to trigger the app for redistribution."
            return $true
        }else {
            return $false
        }
    }
    
    catch {
        throw "Failed to update app with itself: $($_.Exception.Message)"
    }

}