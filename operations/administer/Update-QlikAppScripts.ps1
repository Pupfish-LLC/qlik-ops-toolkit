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
.SYNOPSIS
    Updates Qlik app scripts by performing find and replace operations as defined in the configuration file, Update-QlikAppScripts_Config.json

.DESCRIPTION
    This script updates Qlik app scripts by performing find and replace operations as defined in a configuration file. It can operate in dry run mode or commit changes to the app.

.PARAMETER commit
    If specified, commits the script updates to the apps as a new script version. 
	If this flag is not present, the script will write the changes to file only (as a dry run)

.PARAMETER appIDs
    Also aliased as -a or -app, this parmeter specifies one or more appIDs from which to extract the load scripts (can not be used in conjunction with the -scripts parameter). One or more appIDs may be provided
	in the format -a "AppID1" "AppID2" or alternatively -a "AppID1,AppID2"

.PARAMETER scripts
    Specifies the folder from which to extract app IDs and script files. The files in the folder should be named with the app IDs followed by _script_initial.txt.
	If this parameter is not present, the App IDs for which to retrieve scripts will be loaded from the apps_created.csv file and the scripts will be retrieved via api calls

.EXAMPLE
    .\Update-QlikAppScripts.ps1 -commit
    Runs the script using the apps_created.csv as the source for app IDs, applies the pattern matching operations as supplied in the config file, and commits the changes to the app.

.EXAMPLE
    .\Update-QlikAppScripts.ps1 -Scripts "Update-QlikAppScripts_20240606_2315"
    Runs the script using the scripts in the specified folder as the source for app IDs and script files, writing the script changes to file without committing the changes to the app(s)

.NOTES
    This script requires PowerShell 7 or later due to the need for UTF-8 encoding.
#>

param (
    [switch]$commit,				# commit the script updates to the app(s) as new script version, if omitted the script will process as a dry run
	[string]$scripts,          		# specify the folder from which to extract app IDs and script files rather than performing an api extract (xx_script_initial.csv scripts will be used, not the xx_script_updated.txt)
	[Alias("a", "app")]
	[string[]]$appIDs               # specify one or more app IDs to update (mutually exclusive with -scripts)
)

$initScriptPath = Resolve-Path "$PSSCRIPTROOT\..\..\init.ps1"

# Ensure -scripts and -appIDs are not both provided
if ($scripts -and $appIDs) {
    Write-Host "ERROR: The -scripts and -appIDs parameters cannot be used together. Please provide only one." -ForegroundColor Red
    exit 1
}

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
	Initialize-QlikLog "Update-QlikAppScripts"
	Write-QlikLogHeader "Starting the load script update process..." -echo

	# Validate cloud context and set url
	If (Confirm-QlikContext $QlikCloudContext) {Write-QlikLog "The context $QlikCloudContext has been validated." -echo}
	# Get the cloud tenant Url
	$tenantUrl = Get-QlikTenantUrl $QlikCloudContext
	# Get the id of the current Qlik-cli user
	$cliUserId = qlik user me -q --context $QlikCloudContext

} catch {
	Write-QlikLogError "Encountered an error during initial validation [$($_.Exception.Message)]" -stop
}

# Remove the .txt extension from the global log file name, then create the export subdirectory for this operation
$exportSubfolder = $Global:QlikLogFileName -replace '\.txt$', ''
$exportSubfolderPath = Join-Path -Path "$($DATA)\administer\export\scripts" -ChildPath "$($exportSubfolder)"

# Ensure the directory exists
if (-not (Test-Path -Path $exportSubfolderPath)) {
    New-Item -Path $exportSubfolderPath -ItemType Directory -Force | Out-Null
}

# Define the summary output file
$summaryFilePath = Join-Path -Path $exportSubfolderPath -ChildPath "_change_summary_$($exportSubfolder).csv"

# Ensure we're using the cloud context
qlik context use $QlikCloudContext | out-null

# Load the list of apps from either the CSV file or the given folder
if ($scripts) {
    try {
		Write-QlikLog "Retrieving script files from folder name: $($scripts)" -echo
		$scriptsPath = Join-Path -Path $DATA -ChildPath "administer\export\scripts\$($scripts)"						# Passed as optional parameter
        $scriptFiles = Get-ChildItem -Path $scriptsPath -Filter "*_script_initial.txt"
        $apps = $scriptFiles | Select-Object -ExpandProperty Name | ForEach-Object { $_ -replace '_script_initial\.txt$', '' }
    } catch {
        Write-QlikLogError "Failed to load the list of apps from folder [$($_.Exception.Message)]" -stop
    }
} elseif ($appIDs) {
    try {
        Write-QlikLog "Using provided app IDs: $($appIDs)" -echo
        # If the appIDs is a single string with commas, split it into an array
        if ($appIDs.Count -eq 1 -and $appIDs -match ",") {
            $apps = $appIDs -split ","
        } else {
            $apps = $appIDs
        }
    } catch {
        Write-QlikLogError "Failed to load the list of apps from the provided app IDs [$($_.Exception.Message)]" -stop
    }
} else {
    try {
		Write-QlikLog "Retrieving script files from Qlik Cloud based upon the supplied app IDs." -echo
        $importDataPath = Join-Path -Path $DATA -ChildPath "migrate-qliksense\output\apps_created.csv"				# Adjust this path as needed, by default this loads from the migration output file: "migrate-qliksense\output\apps_created.csv"
        $apps = Import-Csv -Path $importDataPath | Select-Object -Property DevCopyID								# and by default this loads the appIDs from the DevCopyID field (adjust as needed)
    } catch {
        Write-QlikLogError "Failed to load the list of apps [$($_.Exception.Message)]" -stop
    }
}

# Load the configuration file, which defines the patterns to be flagged or updated
try {
	$configPath = Join-Path -Path $CONFIG -ChildPath "Update-QlikAppScripts_config.json"
	$versionmessage = "$($exportSubfolder)"	# The updated script version, if comitted, will be named with a reference to the timestamped script run instance

	$config = Get-Content $configPath -Raw | ConvertFrom-Json

} catch {
	Write-QlikLogError "Failed to load the script update configuration [$($_.Exception.Message)]" -stop
}

# Initialize the summary output file
"AppId,Pattern,Description,OriginalText,ReplacementText,Context,Flag,Change,Committed" | Out-File -FilePath $summaryFilePath -Encoding UTF8 -Force

# Per app, retrive the current script, perform each of the pattern searches (with an update or flag operation),then post the updated script as a new version 
foreach ($app in $apps){

	try {

		if ($scripts) {
            $appid = $app  # When using the folder, $app is the app ID extracted from the filename
            # Load the script from the file
            $scriptFilePath = Join-Path -Path $scriptsPath -ChildPath "$appid`_script_initial.txt"
            $appscript = Get-Content -Path $scriptFilePath -Raw
		} else {
			if ($appIDs) {
				$appid = $app  # When -appIDs are provided directly, $app is already a string
			} else {
				$appid = $app.PSObject.Properties.Value  # Generic reference to the property values, assumes that only a single property was loaded
			}
            
            Write-QlikLog "Retrieving the load script for appID $($app)" -echo
            $scriptId = (qlik app script version ls --appId $appid --limit 1 | ConvertFrom-Json).scripts[0].scriptId
            $appscript = (qlik app script version get $scriptId --appId $appid | ConvertFrom-Json).script
			
        }

		$totalScriptReplacements = 0
		$totalScriptFlags = 0

		Write-QlikLogSeparator -echo
		Write-QlikLogHeader "Performing Find and Replace on the load script of appId '$($appid)'" -echo -character '-'

        # Define the output file path
        $outputFilePath = Join-Path -Path "$($exportSubfolderPath)" -ChildPath "$($appid)_script_initial.txt"
		# Output current verion of script to file
		$appscript | Out-File $outputFilePath -Encoding UTF8

		Write-QlikLog "Performing find & replace operations as defined in the config file." -echo
		foreach($pair in $config){
		
			try{
				if ($pair.isDisabled) {
					continue
				}

				Write-QlikLogSeparator -echo
				Write-QlikLog "Processing pattern: `"$($pair.findPattern)`" to `"$($pair.replacePattern)`" " -echo
				Write-QlikLog "Description: $($pair.description)" -echo
				Write-QlikLog "CaseSensitive: $($pair.isCaseSensitive) | Regex: $($pair.isRegex) | FlagOnly: $($pair.isFlagOnly)" -echo
				Write-QlikLogSeparator -echo
				
				if (-not $pair.isCaseSensitive) {
					$regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
				} else {
					$regexOptions = [System.Text.RegularExpressions.RegexOptions]::Multiline
				}

				$pattern = $pair.findPattern
				$description = $pair.description

				# If the pattern is not a RegEx, then interpret as a literal string
				if (-not $pair.isRegex) {
					$pattern = [regex]::Escape($pattern)
				}

				

				# Create a PSObject to hold the count (otherwise a variable's scope would not update the outer scope outside the function)
				$count = New-Object PSObject -Property @{ 
					replacements = 0 
					flags = 0
				}

				# Perform regex replacement and count each replacement
				$appscript = [regex]::Replace($appscript, $pattern, {
					param($match)
					
					$originalText = $match.Value
					$replacementText = $pair.replacePattern
					for ($i = 1; $i -le $match.Groups.Count - 1; $i++) {
						$placeholder = '$' + $i
						$replacementText = $replacementText.Replace($placeholder, $match.Groups[$i].Value)
					}

					$replacementText = $replacementText.Replace('$$', '$')  # Replace $$ with $
					$replacementText = $replacementText.Replace('$&', $match.Value)  # Replace $& with the whole match

					# Apply substringFind and substringReplace within the matched text if specified and not empty
            		if (-not [string]::IsNullOrWhiteSpace($pair.substringFind)) {
                		$replacementText = $replacementText -replace [regex]::Escape($pair.substringFind), ($pair.substringReplace -ne $null ? $pair.substringReplace : '')
            		}

					# Maximum number of characters to extract for the context of the pattern match
					$maxContextSize = 300

					# Find start of the line
					$lineStart = $appscript.LastIndexOf("`n", $match.Index)
					if ($lineStart -eq -1) { $lineStart = 0 } else { $lineStart += 1 }  # Adjust to start after the newline character

					# Find end of the line
					$lineEnd = $appscript.IndexOf("`n", $match.Index + $match.Length)
					if ($lineEnd -eq -1) { $lineEnd = $appscript.Length }

					# Extract the whole line
					$context = $appscript.Substring($lineStart, $lineEnd - $lineStart)

					# Limit the context to a maximum number of characters
					if ($context.Length -gt $maxContextSize) {
						$context = $context.Substring(0, $maxContextSize) + "..."
					}

					# Sanitize the context by replacing newline characters with a space
					$context = $context -replace "`n", " " -replace "`r", " "

					# Conditional replacement based on isFlagOnly
					if ($pair.isFlagOnly) {
						$count.flags++
						# Log occurrence and return original text if flagged only
						Write-QlikLogWarning "Flagged occurrence $($count.flags): $context"
						Add-Content -Path $summaryFilePath -Value ('"{0}","{1}","{2}","{3}","{4}","{5}","True","False","{6}"' -f $appid, $pattern, $pair.description, $originalText, $replacementText, $context, $commit)
						#return the same value, no replacement
						return $originalText
					} else {
						$count.replacements++
						Write-QlikLog "Replaced occurrence $($count.replacements): $context" -echo
						Add-Content -Path $summaryFilePath -Value ('"{0}","{1}","{2}","{3}","{4}","{5}","False","True","{6}"' -f $appid, $pattern, $pair.description, $originalText, $replacementText, $context, $commit)
						# Return new text for replacement
						return $replacementText
					}

				}, $regexOptions)

				# Log the number of replacements for this pattern
				#Write-QlikLog "$($count.replacements) replaced occurrences of `"$($pair.findPattern)`" in appId '$appid'" -echo
				$totalScriptReplacements += $count.replacements
				$totalScriptFlags += $count.flags

			} catch {
				Write-QlikLogError "Encountered an error while procesing pattern $($pattern) for $($appId). Moving to next pattern. [$($_.Exception.Message)]"
				continue
			}
		}
		
		if ($totalScriptFlags -gt 0) {
			Write-QlikLogSeparator -echo
			Write-QlikLogWarning "$($totalScriptFlags) flags were identified for appId '$($appId)'"
		}

		# Output the updated load script to a text file
		$changesFilePath = Join-Path -Path "$($exportSubfolderPath)" -ChildPath "$($appid)_script_updated.txt"
		$appscript | Out-File $changesFilePath -Encoding UTF8

		# Now make preparations to output the updated script as a json file, beginning by creating the structure in a PSObject
		$scriptObject = @{
    		script = $appscript
			versionMessage = $versionMessage
		}

		# Convert to JSON format
		$jsonScript = $scriptObject | ConvertTo-Json -Depth 1

		# Save the JSON output to a file with UTF-8 encoding
		$jsonFilePath = Join-Path -Path $exportSubfolderPath -ChildPath "$($appid)_script_updated.json"
		$jsonScript | Out-File -FilePath $jsonFilePath -Encoding UTF8

		# If no replacements were made, output a warning and log it
		if ($totalScriptReplacements -eq 0) {

			Write-QlikLogSeparator -echo
			Write-QlikLogWarning "No replacements were made for appId '$($appId)'"
			Add-Content -Path $summaryFilePath -Value ('"{0}","{1}","{2}","{3}","{4}","{5}","False","False","{6}"' -f $appid, "N/A", "No replacements found for this app ($($totalScriptFlags) flagged items)", "N/A", "N/A", "N/A", $commit)
		
		# Otherwise report the number of replacements and save the update as a new script version
		} else {

			Write-QlikLogHeader "Total number of replacements made for appId' $($appId)': $($totalScriptReplacements)" -echo -character "+"
			
			
			if ($commit) {

				Write-QlikLog "Saving the modified script as a new script version in the app." -echo
				#qlik app script version create --appId $appid --script "$($appscript)" --versionMessage $versionmessage
				qlik app script version create --appId $appid --file "$jsonFilePath"
			} else {
				Write-QlikLog "Updated script saved to file, but not comitted to app. Include the -commit parameter to post these changes as new script versions" -echo
			}

		}

		Write-QlikLogHeader "Script update for appId '$($appid)' is complete." -echo -character "-"

	} catch {
		Write-QlikLogError "Encountered an error while procesing script update for $($appId). Moving to next app. [$($_.Exception.Message)]"
		continue
	}
}

if ($commit) {

	Write-QlikLogHeader "The load script update process has completed (the -commit flag was applied to this process)." -echo -character '+'

} else {
	Write-QlikLogHeader "The load script update process has completed. (the -commit parameter was not applied to this process)." -echo -character '+'
	Write-QlikLog "The changes have been written to the $($exportSubfolderPath) directory but have not been committed.`nInclude the -commit parameter to post updated scripts as new script versions."
}

# Cleanup
#Remove-Item "script.json"