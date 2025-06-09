## Features
- [x] Establish a separate config file to drive the migration actions
  - [x] Setting to name migration temp space
  - [x] Setting to remove migration temp space upon completion
  - [x] New setting to set the Publish Mode (create or update)
  - [x] New setting to remove shared app at the conclusion of a Phase 1 multi-cloud migration
  - [ ] New setting to toggle granting space access to app owner upon completion (always granted at user level in Qlik's original script but commented out currently)
  - [ ] New setting allowing the option to remove space access granted to qlik-cli user that was necessary during migration (always granted at user level in current version but commented out currently)
  - [x] New setting to toggle private sheet, bookmark, story, and snapshot migration
  - [x] New setting to define a fallbackObjectOwnerEmail (see fixes)
  - [x] New verbosity setting to toggle detailed output to terminal
- [x] New "Update" publish mode feature, allowing for migration of private content to multi-cloud distributions while establishing a developer copy in the shared space
- [x] New feature to remove shared developer copy at the conclusion of a migration to managed space, to support use cases where app development will continue to take place on-prem
- [x] Write detailed log to file with successful actions, possible issues, and errors
- [x] The script now migrates private snapshots
- [ ] Integrate cloud user verification/creation as optional first step in migration
- [ ] Integrate load script find/replace for data connection name changes as optional last step of app migration (script to perform this operation has been completed, consider integrating into the migration)
- [ ] Incremental migration of private content from on-prem to managed space app (convey only private content that was created after the last migration).
- [x] Gracefully handle apps exceeding standard capacity (partially implemented, process now checks for a valid response when performing an update operation)
- [x] Overall improvement of error handling (publish, unpublish, change-owner commands), additional handling of potential errors from other qlik commands is still needed
- [ ] Define shared space at app level rather than a single global setting per script execution (may not be advised, could be easier to run in logical batches per migration type. The apps can still be moved from the single dev space without issue)
- [x] If the target app for a publish update operation is in staged, it will be moved to the target space
- [x] If the target app resides in a different space, it will be moved to the target space (applicable use case is moving from UAT space to production space upon migration)
- [x] The only required values for migration are appId and spaceName. The target app owner can be overriden (optional) by providing the email of the app owner, but otherwise app ownership will be assigned to the same owner as in on-prem. If the on-prem user cannot be resolved the owner will be the Qlik-cli user.
- [x] Added a progress bar that is displayed during each phase of a publish update migration rather than detailed output. Detailed output can be toggled by changing the verbosity setting.
- [x] Implement configuration setting to control the filter of app objects (all, approved, published)
- [x] Output summary of mapped appIDs to output file 
- [ ] Administrative script to backup published apps in cloud environment (since last backup). Config options to enable export to qvf, unbuild app to github, export platform config to .txt (spaces, users, groups, assignments, appIDs in each space)


## Moonshots ## 

*Brainstorm ideas. Must be cautious not to make things overly complex, or overfitting for specific scenarios.*
- [ ] Deploy as a PowerShell module with reusable functions and cmdlets
- [ ] Creation of shared and managed spaces that don't exist (would likely require user confirmation in some form). Currently a single shared space can be created if it doesn't exist.
- [x] Reestablish a shared dev copy directly from a managed app (multiple use-cases: 1) The managed app is being deployed from multi-cloud, or 2) the original dev copy was lost). This is implemented in apps.ps1/Unpublish-QlikApp.ps1
- [ ] Fix 9003 errors when returned from a distributed app. Repair-QlikAppDistribution will perform the repair already. Potentially, integrate into process.
- [ ] Tag apps in on-prem with migration status, integrate the migration process with these status tags
- [ ] In the case of a multi-cloud deployment, verify/create the deployment tag, trigger deployment, wait for app to deploy, continue private content migration
- [ ] Automatically create external program tasks in QMC to reload the cloud app consistent with on-prem app schedule
- [ ] Validating reloadability in cloud
- [ ] Automatic flagging/reporting of extensions that are known to require remediation
- [ ] Simple dashboard to summarize migration logs/status
- [ ] Automated communication to users (probably just app owner, maybe object owners)
- [ ] Option to backup exported on-prem apps to path that will persist after the migration
  
## Fixes ##
- [x] Make the script compatible with Powershell 7 (all scripts now compatible across PS 5.x + with the exception of the Update-QlikAppScripts fuctions, which requires PS 7.x)
- [x] Objects owned by inactive on-prem users are migrated but are not accessible by anyone
  > Fix: Option to define a default object owner, to which objects whose owner can not be identified in the cloud will be assigned. If no default owner is defined, objects with inactive owners will not be migrated.
- [x] Use --no-data tag with all publish and unpublish commands
  > Fix: This change appears to improve performance and should also ensure that section access will not cause issues (not tested at time of fix)
- [x] Error migrating some stories
  > Fix: Incorrect PS object was referenced in several places, possibly an introduced error. No known issues with stories now.
- [x] The reporting of space and app links to the user upon app migration completion should be accurate in all migration scenarios
- [x] A validation is performed before a publish update to ensure that the requirements are met (target space exists, target app exists, target app resides in a managed space, etc)
- [x] If the shared space is configured for deletion, don't waste time preparing it
- [x] Handle scenario where the ownner of an app is not an active cloud user (assign ownership to cli user)
- [x] Handle scenario where the owner of a base content object is not an active cloud user and a fallback object owner has not been defined (assigne ownership to cli user)
- [x] Gracefully handle scenario where the qlik app object layout response contains unreadable characters

## Documentation ##

- [x] Setup and configuration
  - Qlik-cli
  - JWT authentication
  - cli contexts

- [ ] Define cloud migration scenarios
  - Establish app as new appId in *managed* space with supporting dev copy in shared space
  - Standalone app migration to a *shared* space
  - Standalone app migration to a *personal* space
  - Phased Multi-Cloud Migration
    - Establish private content in an existing distributed app (Phase 1 of a multi-cloud migration)
    - Establish Shared Dev copy and associate it with an existing distributed app (Phase 2 of a multi-cloud migration)

## Style ##
- [x] Script needs white-space and inline comments
  
## Refactoring ##

- [x] Improve terminal output to better convey current status and possible issues
- [x] Many complex portions of script moved to external functions, further organization and simplification is still necessary
  
## Performance ##
- [x] Use --no-data tag with all publish and unpublish commands
  > Fix: This change appears to improve performance and should also ensure that section access will not cause issues (not tested at time of fix)
- [x] Looking up every object owner's cloud user email with a --filter is a major performance drain. Change to retrieve all users in one batch, then reference list. Consider that this change would add overhead in cases where few objects are being migrated, so possibley define a threshhold based on object count, or simply write a static cloud user list to a reusable file and update as needed.
- [x] Use --no-save on rm operations when removing objects and bookmarks
- [x] The reassignment of the thisappobjects array on each object loop should be rewritten as a Generic.List[] to be much more efficient, especially when an app has many objects.
- [x] On the final two steps of a publish update operation, only a subset of the objects need to be included in the for each loop
- [x] If object owner can't be determined and no default user is supplied, these objects should be completely ignored in the for each loop of all steps

## Tests ##
- [ ] Test app migration to private space (standalone app)
- [ ] Test app migration to shared space (standalone app)
- [ ] Test app migration to managed space (independent of multi-cloud)
- [ ] Test private content migration to existing managed app (multi-cloud deployment Phase 1)
- [ ] Test to establish shared dev copy against a managed app (multi-cloud deployment Phase 2)
- [ ] Test on app with section access
- [ ] Test on app exceeding standard capacity




