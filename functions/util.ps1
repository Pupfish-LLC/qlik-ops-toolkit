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

function Initialize-QlikLog {
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [string]$prefix = "Log",

        [Parameter(Mandatory=$false, Position=1)]
        [string]$path = $LOGS

    )

    try {
        # Ensure the log directory exists
        if (-not (Test-Path -Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }

        # Generate log file name with caller script and current date-time
        $date = Get-Date -Format "yyyyMMdd_HHmm"
        $Global:QlikLogFileName = "${prefix}_${date}.txt"
        $Global:QlikLogFilePath = Join-Path -Path $path -ChildPath $Global:QlikLogFileName

    } catch {

        throw "Failed to initialize the log file [$($_.Exception.Message)]"

    }

}

function Write-QlikLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]       # Can accept piped values, but can also accept as a parameter
        [string]$message,

        [Parameter(Mandatory=$false)]
        [switch]$skipLog,               # -skiplog  (don't write message to log, used when the message is exclusively a verbose, debug, or console message)

        [Alias("echo")]
        [switch]$console,               # -echo, -console (message also written to console)

        [Alias("v")]
        [switch]$echoVerbose,           # -v, -echoVerbose (verbose flag, written to the console when -Verbose parameter is specified at execution)

        [Alias("dbug")]
        [switch]$echoDebug              # -dbug, -echoDebug (debug flag, written to console when -Debug parameter is specified at execution)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Global:QlikLogFilePath)) {
            throw "Log file path not initialized. Please call Initialize-QlikLog first."
        }

        # Prepend each log entry with a timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp : $message"

        # Write to the pre-defined log file
        if (-not $skipLog) {
            Add-Content -Path $Global:QlikLogFilePath -Value $logEntry
        }
        
        # Check if message should be output to the console (-echo or -console) 
        if ($console) {
            Write-Host "$($message)"
        }

        # Check if verbose message (written only if the -Verbose parameter was specified during script execution)
        if ($echoVerbose) {
            Write-Verbose "$($message)"
        }

        # Check if debug message (written only if the -Debug parameter was specified during script execution)
        if ($echoDebug) {
            Write-Debug "$($message)"
        }

    }catch {

        throw "Failed to write to the log [$($_.Exception.Message)]"

    }
}

function Write-QlikLogSeparator {
    param (
        [Parameter(Mandatory=$false)]
        [int]$count = 1,            # Default to one blank line

        [Alias("echo")]
        [switch]$console,            # -echo, -console (header also written to console)
    
        [Alias("v")]
        [switch]$echoVerbose  
    )

    try {
        1..$count | ForEach-Object { Add-Content -Path $Global:QlikLogFilePath -Value "" }

        If ($console) {
            Write-Host ""
        }

        If ($echoVerbose) {
            Write-Verbose ""
        }
    
    } catch {

        throw "Failed to write log separator [$($_.Exception.Message)]"

    }
}

function Write-QlikLogHeader {
    param (
        [Parameter(Mandatory=$true)]
        [string]$header,

        [Parameter(Mandatory=$false)]
        [string]$character = '=', # Default to '=' if not specified

        [Alias("echo")]
        [switch]$console # -echo, -console (header also written to console)
    )

    try {
        
        $visualHeader = $header -replace "\t", "        "
        $separator = $character * $visualHeader.Length
        Add-Content -Path $Global:QlikLogFilePath -Value ""
        Add-Content -Path $Global:QlikLogFilePath -Value $separator
        Add-Content -Path $Global:QlikLogFilePath -Value $header
        Add-Content -Path $Global:QlikLogFilePath -Value $separator
        Add-Content -Path $Global:QlikLogFilePath -Value ""

        If ($console) {
            Write-Host
            Write-Host "$separator"
            Write-Host "$header"
            Write-Host "$separator"
            Write-Host
        }

    } catch {

        throw "Failed to write the header [$($_.Exception.Message)]"
    }
}

function Write-QlikLogError {
    param (
        [Parameter(Mandatory=$true)]
        [string]$errorMessage,

        [Parameter(Mandatory=$false)]
        [switch]$stop
    )

    try {

        $errorEntry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " : ERROR: " + $errorMessage
        Add-Content -Path $Global:QlikLogFilePath -Value $errorEntry

        Write-Host "ERROR: $($errorMessage)" -ForegroundColor Red

        If($stop) {Exit 1}

    } catch {

        throw "Failed to write error to log [$($_.Exception.Message)]"

    }
}

function Write-QlikLogWarning {
    param (
        [Parameter(Mandatory=$true)]
        [string]$warningMessage
    )

    try {

        $warningEntry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " : WARNING: " + $warningMessage
        Add-Content -Path $Global:QlikLogFilePath -Value $warningEntry

        Write-Host "Warning: $($warningMessage)" -ForegroundColor Yellow

    } catch {

        throw "Failed to write warning to the log file [$($_.Exception.Message)]"

    }
}