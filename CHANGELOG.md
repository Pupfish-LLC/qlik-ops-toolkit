# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2] - 2025-02-18
Contributor: [Kin Mello @ DI Squared](https://disqr.com)

Fix to `Get-QlikSpaceId` in `space.ps1` to address reported issue in PowerShell 5.x when combining these commands into single pipeline.

### Updated

- `Get-QlikSpaceId`
    - The spaceId extraction is accomplished in separate steps rather than a command pipeline to avoid an issue in PowerShell 5.x 

## [1.1.1] - 2024-08-07

Improvements to `Update-QlikAppScripts.ps1` to add an entry to the change_summary file when no replacements were found for an app. Also added a new parameter to pass a single appID to update.

### Updated

- `Update-QlikAppScripts.ps1`
    - The script will now identify when zero replacements were made to an app, and write this condistion to the chang_summary.csv file in the /administer/scripts/TIMESTAMP directory
    - A new optional paramter, -appIDs (alias -a or -app), is made available allowing specific appID(s) to be specified for script update (this parameter cannot be used with the -scripts parameter).

## [1.1.0] - 2024-07-03

All fuctions are usable across all PowerShell versions, with the exception of Update-QlikAppScripts which requires PowerShell 7.x in order to handle UTF-8 encoding properly.
Added several administrative functions. Refactored space and group ID lookups into standard function calls to avoid differences in --filter syntax between PowerShell versions.

### Updated

- `space.ps1`
    - Added `Create-QlikSpace`, a function to create a space 
    - Added `Get-QlikSpaceId`, a function to return the spaceId for a given space name, which avoids common syntax differences between PowerShell versions when using the --filter paramter
- `group.ps1`
    - Added `Create-QlikGroup`, a function to create a group
    - Added `Remove-QlikGroup`, a function to remove a group
    - Added `Get-QlikGroupId`, a function to return the groupId for a given group name, which avoids common syntax differences between PowerShell versions when using the --filter paramter
    - TODO ver 1.1.1: Added `Assign-QlikGroup`, a function to assign a group permissions to a space
- `migrate.ps1`
    - Updated spaceId lookups to use `Get-QlikSpaceId` function, allowing for use in all Powershell versions

### Added

- `Create-QlikSpaces`
    - New operation to create spaces in bulk (supplied in the administer/input/spaces.csv)
    - Writes output summary to `administer/output/spaces_created.csv` in addition to normal operation logging in `logs/`
- `Create-QlikGroup`
    - New operation to create groups in bulk (supplied in the administer/input/groups.csv)
    - Writes output summary to `administer/output/groups_created.csv` in addition to normal operation logging in `logs/`
- `Remove-QlikGroup`
    - New operation to create groups in bulk (supplied in the administer/input/spaces.csv)
    - Writes output summary to `administer/output/groups_removed.csv` in addition to normal operation logging in `logs/`
- TODO ver 1.1.1: `Update-QlikSpaceMembers`
    - New operation to apply space permissions to a list of spaces (supplied in the administer/input/spaces_members.csv)
    - Any group membership records that already exist will be over-written if an update is supplied, but any group membership not overwritten will remain unchanged
    - Writes output summary to `administer/output/space_members_updated.csv` in addition to normal operation logging in `logs/`
    - TODO: For now this operation is capable of assigning group permissions, intention is to support either group or user assignment
    - TODO: An enhancement to supply a flag to remove all existing space membership and replace with those provided

## [1.0.2] - 2024-06-25

Minor bug fixes

### Updated

- `Migrate-QlikApps`
    - Added fine-grain error catching/reporting of known issue occuring when an object's name contains unprintable characters. Issue occurs specifically when retrieving the layout of the object in the cloud apps, usually for snapshot objects. 

## [1.0.1] - 2024-06-14

Minor refactoring and inline script documentation added.

### Updated

- `Update-QlikAppScript`
    - Added max character limit for the extraction of pattern contexts
    - Added `Context` field to the `_change_summary_Update-QlikAppScripts_<TIMESTAMP>.csv` output file
    - In the output to `_change_summary_Update-QlikAppScripts_<TIMESTAMP>.csv`, added quotes around each field value to avoid misinterpreted delimiters
    - Inline comments added to script

- `Update-QlikAppScript_Config.json`
    - Updated to include new pattern to flag binary loads

- `Update-QlikAppScripts_Config.json.template`
    - Updated the template configuration with pattern match examples including flagging binary loads

- `Migrate-QlikApps_Config`
    - Added config section to specify objectTypes for which to process ownership reassignment, publish/unpublish, approve/unapprove

- `Migrate-QlikApps`
    - Added script to ignore processing of objectTypes that are not specified for processing in the `Migrate-QlikApps_Config`
    - FIX: Changed the logic of the `flagOwnerUpdateNeeded` property in the `$thisObjectAttributes` array, so that any object whose owner does not match between environment will be flagged, regardless of whether it is published

## [1.0.0] - 2024-06-10

First major release and the first changelog tracked release.

### Added

- `changelog.md`

### Updated

- `Update-QlikAppScript`
    - Updated with optional parameters `-commit` and `-script`. 
    - Added scripting to perform a literal find/replace of text on pattern matches (`substringFind` and `substringReplace` configuration items)
    - The script version, when committed to the app, is now given a version description that matches the log file, allowing it to be traced back to an operation
- `Update-QlikAppScript_Config.json`
    - Updated to include two new pattern configuration items, `substringFind` and `substringReplace`
    - Renaming of `findPattern` and `replacePattern` configuration items from old nomenclature of textFrom and textTo
- `Update-QlikAppScripts_Config.json.template`
    - Updated the template configuration with a standard set of pattern match examples