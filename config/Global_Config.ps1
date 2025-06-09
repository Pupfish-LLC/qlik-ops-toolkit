# Configure Qlik-Cli contexts to the target environments and enter the context names in this config file. 
# The authenticated Qlik-Cli user should have sufficient permissions to perform the intended operations. See: (https://qlik.dev/toolkits/qlik-cli/qlik-cli-contexts/)

# Set the name of the the context that will be used to connect to the Qlik Cloud environment. 
# Utilizing an OAuth client for authentication is recommended: (https://qlik.dev/authenticate/oauth/create-oauth-client/)
$QlikCloudContext = "mytenant.us_oauth"

# Set the name of the Qlik-Cli context that will be used to connect to the QSEoW environment. 
# This requires a JWT configuration: (https://qlik.dev/toolkits/qlik-cli/qlik-cli-qrs-get-started/)
$QlikWindowsContext = "QSEoW"

# If using self signed cert, leave as is, else set $SS = ""
$SS = "--insecure"