<# 

Example to dot include this init file in other scripts:

$initScriptPath = Resolve-Path "$PSSCRIPTROOT\..\..\init.ps1"

    # Other path examples:
    # . "$PSSCRIPTROOT\init.ps1"                        (caller script is in the root directory)
    # . "$PSSCRIPTROOT\..\init.ps1"                     (caller script is in a subdirectory)
    # . "$PSSCRIPTROOT\..\..\init.ps1"                  (caller script is two folders down)
    # . "$PSSCRIPTROOT\..\AnotherDirectory\init.ps1"    (caller script is in a parall directory)

# Initialize
try {
    . $initScriptPath
    # . .\AdditionalIncludeFile.ps1
} catch {
	Write-Host "ERROR: Failed to initialize the script." -ForegroundColor Red
	Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

#>

# Set the root directory of the project
$SCRIPTROOT = Split-Path $script:MyInvocation.MyCommand.Path -Parent

# Configuration file path
$GLOBALCONFIG = Join-Path -Path $SCRIPTROOT -ChildPath "config\Global_Config.ps1"

# Check if the global configuration file exists before dot-sourcing
if (Test-Path -Path $GLOBALCONFIG) {
    # Dot-source the global configuration file
    . $GLOBALCONFIG
} else {
    # Throw an error and stop execution if the file does not exist
    throw "Global configuration file not found at path: $GLOBALCONFIG"
}

# Log directory path
$LOGS = Join-Path -Path $SCRIPTROOT -ChildPath "logs"

# Config directory path
$CONFIG = Join-Path -Path $SCRIPTROOT -ChildPath "config"

# Ensure the log directory exists
if (-not (Test-Path -Path $LOGS)) {
    New-Item -ItemType Directory -Path $LOGS | Out-Null
}

# Data directory path
$DATA = Join-Path -Path $SCRIPTROOT -ChildPath "data"

# Ensure the data directory exists
if (-not (Test-Path -Path $DATA)) {
    New-Item -ItemType Directory -Path $DATA | Out-Null
}

# Functions directory path
$FUNCTIONS = Join-Path -Path $SCRIPTROOT -ChildPath "functions"

# Dynamically import all function scripts from the functions directory
try {
    Get-ChildItem -Path $FUNCTIONS -Filter "*.ps1" |
    ForEach-Object {
        . $_.FullName
    }
} catch {
    throw "Failed to load functions $($_.Exception.Message)"
}
