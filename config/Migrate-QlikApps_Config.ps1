# Define the exportScope for app object exports from the on premise apps:
# The exportScope defines the filter for the app objects when exported from the on premise app
# all (all app objects will be exported, including base, private, and community content)
# approved (only approved app objects will be exported, i.e., base content only)
# published - (only published app objects will be exported, i.e., base and community content)
# Important: If private content has already been migrated to the target app in a multi-cloud scenario and the only remaining task is to establish the shared dev copy, 
# then the exportScope should be set to 'approved', and the publishMode set to 'update', which will only migrate base content to the shared dev copy and previously migrated private content will remain in the target managed app.
$exportScope = 'approved'

# Set the scope of the PRIVATE content migration
# $true (all objects of this type will be included in the migration)
# $false (all objects of this type will be excluded in the migration)
# Note: The exportScope setting (above) will take precedence over these setting, possibly making them not applicable
$migratePrivateSheets = $true
$migratePrivateBookmarks = $true
$migratePrivateStories = $true
$migratePrivateSnapshots = $true

# Set the scope of objectTypes to process (i.e., ownership reassignment, publishing/unpublishing, and approval/unapproval
# Note that this setting applies to ALL objects, not only private objects
# Default objects are @('sheet', 'bookmark', 'story', 'snapshot')
# To process ownership, publishing, and approval of all object types, set to @('all)
$objectTypesToProcess = @('sheet', 'bookmark', 'story', 'snapshot')

# Provide a valid cloud user email to assign a fallback object owner, to which every object whose owner can not be identified in the cloud (for example, objects owned by inactive users)
# Set to an empty string to remove any objects with inactive owners
$fallbackObjectOwnerEmail = 'name@example.com'

# Define the name of the temporary space (this space will be created if it does not exist)
# A temporary holding place space to support the migration process.
$migrationTempSpaceName = 'MigrationTemp'
$removeMigrationTemp = $false


#  **********************************************************
#  *   Config settings for migrations to managed spaces     *
#  **********************************************************

# Define a single Shared Space that will host the source apps that are published to Managed Spaces
# If needed the apps can be moved from this folder and will still maintain their association with their published counterpart
$sourceAppsSharedSpace = 'SpaceName (DEV)'

# Set the publishMode:
# create (a new appID will be established in the managed space, with a developer copy in the shared space)
# update (the source app wil be "published over" the app in a managed space with the same appID, presumably an app that is already being distributed from On-Prem via multi-cloud)
$publishMode = 'create'

# Remove the source app after publishing?
# $true  (the source app in the shared space will be removed after it is published to the managed space)
# $false (the source app in the shared space will persist, with a publish association to the published app in the managed space)
$removeSharedApp = $false


#  ************************
#  *    Other settings    *
#  ************************

# Set the Verbosity
# 'Ignore'           : Ignores the verbose messages entirely, normal setting when running the script
# 'Continue'         : Verbose messages are displayed
# 'SilentlyContinue' : Default setting in PS, where verbose messages are not displayed (slightly impacts performance)
# 'Stop'             : Treat non-terminating errors as terminating
$VerbosePreference = 'Ignore'

# Automatically assign space roles to app owner (at user level)? (POTENTIAL ENHANCEMENT)
#$removeappownerroles = $false