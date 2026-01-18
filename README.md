# Qlik Ops Toolkit

**Qlik Ops Toolkit** is a collection of PowerShell scripts developed by DI Squared, LLC and Pupfish, LLC to assist the Qlik community in managing Qlik Sense environments. It provides automation for administrative tasks and migration operations between Qlik on-premises (QSEoW) and Qlik Cloud environments.

## Table of Contents

- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Backup Operations](#backup-operations)
  - [Administrative Operations](#administrative-operations)
  - [Migration Operations](#migration-operations)
- [Input/Output File Formats](#inputoutput-file-formats)
- [Logging](#logging)
- [Changelog](#changelog)
- [Contributing](#contributing)
- [License](#license)
- [Contributors](#contributors)

## Features

- **Backup & Export:** Automated backup of Qlik Cloud configurations including users, spaces, assignments, and apps
- **Administrative Actions:** Bulk creation and management of spaces, groups, and permissions
- **Migration Utilities:** Tools for migrating users, apps, load scripts, and private content from on-prem to Qlik Cloud
- **Script Updates:** Pattern-based find/replace operations on app load scripts with 15+ built-in patterns
- **Logging Mechanism:** Integrated timestamped logging for tracking operations and troubleshooting
- **Standardized Framework:** Unified approach to scripting with consistent execution and error handling

## Project Structure

```
qlik-ops-toolkit/
├── config/                              # Configuration files
│   ├── Global_Config.ps1                # Primary configuration (contexts, paths, retention)
│   ├── Migrate-QlikApps_Config.ps1      # Migration-specific settings
│   ├── Update-QlikAppScripts_Config.json # Script update patterns
│   ├── Space_Role_Aliases.json          # Role alias mappings
│   └── templates/                       # Template configuration files
├── functions/                           # Reusable PowerShell functions
│   ├── app.ps1                          # App management & validation
│   ├── backup.ps1                       # Backup/export functions
│   ├── context.ps1                      # Context utilities
│   ├── extension.ps1                    # Extension operations
│   ├── group.ps1                        # Group management
│   ├── links.ps1                        # Link operations
│   ├── migrate.ps1                      # Migration utilities
│   ├── object.ps1                       # Object management (sheets, bookmarks)
│   ├── qrs.ps1                          # QRS API utilities
│   ├── space.ps1                        # Space management
│   ├── user.ps1                         # User operations
│   └── util.ps1                         # Logging & utility functions
├── operations/                          # Executable operation scripts
│   ├── Backup-QlikCloud.ps1             # Cloud environment backup
│   ├── administer/                      # Administrative operations
│   │   ├── Create-QlikGroups.ps1        # Bulk group creation
│   │   ├── Create-QlikSpaces.ps1        # Bulk space creation
│   │   ├── Remove-QlikGroups.ps1        # Bulk group removal
│   │   ├── Update-QlikAppScripts.ps1    # Script find/replace
│   │   └── Unpublish-QlikApps.ps1       # App unpublishing
│   └── migrate/                         # Migration operations
│       ├── Migrate-QlikApps.ps1         # Full app migration
│       ├── Migrate-QlikUsers.ps1        # User migration
│       └── Repair-QlikAppDistributions.ps1
├── data/                                # Input/output data
│   ├── administer/
│   │   ├── input/                       # CSV input files
│   │   │   ├── spaces.csv
│   │   │   ├── groups.csv
│   │   │   └── templates/               # CSV templates
│   │   └── output/                      # Operation results
│   └── migrate-qliksense/
│       ├── input/
│       └── output/
├── logs/                                # Timestamped log files
├── docs/                                # Additional documentation
├── init.ps1                             # Initialization script
├── CHANGELOG.md                         # Version history
├── CONTRIBUTING.md                      # Contribution guidelines
└── LICENSE                              # GPLv3 license
```

## Prerequisites

### System Requirements

- **PowerShell 5.1 or higher** for most operations
- **PowerShell 7.x** required specifically for `Update-QlikAppScripts` (UTF-8 encoding support)

### Dependencies

- **Qlik-Cli** must be installed and configured
  - Installation: [Install Qlik-Cli](https://qlik.dev/toolkits/qlik-cli/install-qlik-cli/)
  - Context setup: [Create Contexts](https://qlik.dev/toolkits/qlik-cli/qlik-cli-contexts/)

### Authentication

- **Qlik Cloud:** OAuth client recommended ([Create an OAuth Client](https://qlik.dev/authenticate/oauth/create-oauth-client/))
- **QSEoW (on-prem):** JWT configuration required ([JWT Setup Guide](https://qlik.dev/toolkits/qlik-cli/qlik-cli-qrs-get-started/))

## Installation

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/Pupfish-LLC/qlik-ops-toolkit.git
   ```

   Or download and extract to your preferred location.

2. **Verify the installation:**
   ```powershell
   cd qlik-ops-toolkit
   Get-ChildItem
   ```

3. **(Optional) Add functions to your PowerShell profile:**

   Open your profile:
   ```powershell
   if (!(Test-Path -Path $PROFILE)) {
       New-Item -ItemType File -Path $PROFILE -Force
   }
   notepad $PROFILE
   ```

   Add these lines to dot-source all functions:
   ```powershell
   $ToolkitPath = "C:\Path\To\qlik-ops-toolkit\functions"
   Get-ChildItem -Path $ToolkitPath -Filter *.ps1 | ForEach-Object {
       . $_.FullName
   }
   ```

## Configuration

### Global Configuration

Edit `config/Global_Config.ps1` with your environment settings:

```powershell
# Qlik Cloud context name (configured in Qlik-Cli)
$QlikCloudContext = "mytenant.us_oauth"

# QSEoW context name (for migration operations)
$QlikWindowsContext = "QSEoW"

# SSL setting: use "--insecure" for self-signed certs, or "" for valid certs
$SS = "--insecure"

# Backup storage location
$BackupPath = "C:\QlikBackups"

# Number of days to retain backups
$BackupRetentionDays = 30
```

### Migration Configuration

For app migration operations, edit `config/Migrate-QlikApps_Config.ps1`:

```powershell
# Object export scope: 'all', 'approved', or 'published'
$exportScope = 'all'

# Toggle private content migration
$migratePrivateSheets = $true
$migratePrivateBookmarks = $true
$migratePrivateStories = $true
$migratePrivateSnapshots = $true

# Publish mode: 'create' or 'update'
$publishMode = 'create'

# Fallback owner for objects with inactive users
$fallbackObjectOwnerEmail = "admin@example.com"
```

## Usage

### Backup Operations

**Backup Qlik Cloud environment:**

```powershell
.\operations\Backup-QlikCloud.ps1
```

This exports:
- Users and their details
- Space definitions
- Space assignments (membership)
- Role assignments
- Application metadata

Backups are saved to timestamped folders in your configured `$BackupPath` and automatically cleaned up based on `$BackupRetentionDays`.

### Administrative Operations

#### Create Spaces

1. **Prepare the input file** `data/administer/input/spaces.csv`:
   ```csv
   Name,Type,Owner,Description
   Analytics,managed,,Production analytics space
   Analytics (DEV),shared,,Development workspace
   Finance,managed,finance-admin@company.com,Finance team space
   ```

2. **Run the operation:**
   ```powershell
   .\operations\administer\Create-QlikSpaces.ps1
   ```

3. **Check results** in `data/administer/output/spaces_created.csv`

#### Create Groups

1. **Prepare the input file** `data/administer/input/groups.csv`:
   ```csv
   Name
   Analytics-Users
   Finance-Team
   Power-Users
   ```

2. **Run the operation:**
   ```powershell
   .\operations\administer\Create-QlikGroups.ps1
   ```

3. **Check results** in `data/administer/output/groups_created.csv`

#### Remove Groups

```powershell
.\operations\administer\Remove-QlikGroups.ps1
```

#### Update App Load Scripts

Find and replace patterns in app load scripts (requires PowerShell 7):

```powershell
# Dry run (preview changes without committing)
pwsh .\operations\administer\Update-QlikAppScripts.ps1

# Commit changes to specific apps
pwsh .\operations\administer\Update-QlikAppScripts.ps1 -commit -appIDs "app-id-1" "app-id-2"

# Use previously exported scripts
pwsh .\operations\administer\Update-QlikAppScripts.ps1 -scripts "Update-QlikAppScripts_20240606_2315"
```

Configure patterns in `config/Update-QlikAppScripts_Config.json`.

### Migration Operations

#### Migrate Apps from QSEoW to Qlik Cloud

1. **Prepare the input file** `data/migrate-qliksense/input/apps.csv`:
   ```csv
   AppID,SpaceName,AppOwnerEmail
   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx,Analytics,owner@company.com
   yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy,Finance,admin@company.com
   ```

2. **Configure migration settings** in `config/Migrate-QlikApps_Config.ps1`

3. **Run the migration:**
   ```powershell
   .\operations\migrate\Migrate-QlikApps.ps1
   ```

The migration handles:
- App export from on-prem and import to cloud
- Private content (sheets, bookmarks, stories, snapshots)
- User/group membership and permissions
- Ownership reassignment for inactive users
- Automatic temp space management

#### Migrate Users

```powershell
.\operations\migrate\Migrate-QlikUsers.ps1
```

#### Repair App Distributions

```powershell
.\operations\migrate\Repair-QlikAppDistributions.ps1
```

## Input/Output File Formats

### spaces.csv

| Column | Description | Required |
|--------|-------------|----------|
| Name | Space name | Yes |
| Type | `managed` or `shared` | Yes |
| Owner | Owner email (optional for managed spaces) | No |
| Description | Space description | No |

### groups.csv

| Column | Description | Required |
|--------|-------------|----------|
| Name | Group name | Yes |

### apps.csv (Migration)

| Column | Description | Required |
|--------|-------------|----------|
| AppID | Source app GUID | Yes |
| SpaceName | Target cloud space name | Yes |
| AppOwnerEmail | App owner in cloud | Yes |

## Logging

All operations generate timestamped log files in the `logs/` directory:

```
logs/
├── Create-QlikSpaces_20240115_1430.txt
├── Backup-QlikCloud_20240115_0800.txt
└── Migrate-QlikApps_20240114_1600.txt
```

Log entries include:
- Timestamps for each operation
- Success/error status
- Detailed error messages
- Operation summaries

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history and updates.

**Recent versions:**
- **1.1.2** (2025-02-18) - PowerShell 5.x compatibility fix for `Get-QlikSpaceId`
- **1.1.1** (2024-08-07) - App-specific update support, zero-replacement tracking
- **1.1.0** (2024-07-03) - Administrative functions, standardized ID lookups
- **1.0.0** (2024-06-10) - Initial release

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](./LICENSE) file for details.

## Contributors

- **DI Squared, LLC** - [Website](https://disqr.com)
- **Pupfish, LLC** - [Website](https://pupfish.io)
