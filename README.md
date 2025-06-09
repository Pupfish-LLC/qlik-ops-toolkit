# Qlik Ops Toolkit

**Qlik Ops Toolkit** is a collection of PowerShell scripts originally developed and released by DI Squared, LLC and Pupfish, LLC to assist the Qlik community in managing Qlik Sense environments.

## License
This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](./LICENSE) file for details.

## Contributors
This project was developed collaboratively to benefit the Qlik community. 

- **DI Squared, LLC**
  [Website](https://disqr.com)
  Collaboration on initial release (v1.1.1).
  
- **Pupfish, LLC**
  [Website](https://pupfish.io)
  Collaboration on initial release (v1.1.1).

## Overview
The Qlik Ops Toolkit is a comprehensive collection of PowerShell scripts designed to streamline administration and migration of Qlik environments. Utilizing qlik-cli and API calls, the `functions` in the toolkit offer a standardized framework to perform and log various actions. These functions are intended for incorporation into `operations` scripts to provide automation, consistency, and logging of administrative activities.

## Features
- **Administrative Actions:** Automate common Qlik administration tasks such as user management, space creation, and permissions.
- **Migration Utilities:** Tools for simplifying the process of migrating users, apps, load scripts, and private content from on-prem to Qlik Cloud.
- **Logging Mechanism:** Integrated logging for tracking operations, facilitating troubleshooting and compliance.
- **Standardized Framework:** Provides a unified approach to scripting, ensuring consistent execution and simplified maintenance.

## Changelog
- See the [CHANGELOG](./CHANGELOG.md) for a full history of updates and version information.
  
## Getting Started

### Prerequisites
- PowerShell version 5.1 or higher (the only exception is the Update-QlikAppScripts function, which must be run in PowerShell 7.x to process UTF-8 encoding correctly) 
- Qlik-Cli installed and configured. [Install Qlik-Cli](https://qlik.dev/toolkits/qlik-cli/install-qlik-cli/)
- Configuration of a Qlik-Cli context to the target environment(s) with sufficient permissions to perform the intended operations. [Create Contexts](https://qlik.dev/toolkits/qlik-cli/qlik-cli-contexts/)
- If you plan to perform migration operations from QSEoW to Qlik Cloud, this will require configuration of a context to both environments:
     - When configuring a context to the cloud tenant, utilizing an OAuth client for authentication is recommended. [Create an OAuth Client](https://qlik.dev/authenticate/oauth/create-oauth-client/)
     - When configuring a context to the QSEoW environment, this will require a [JWT configuration](https://qlik.dev/toolkits/qlik-cli/qlik-cli-qrs-get-started/)

### Installation
1. Clone the repository to your local machine or server:
    ```powershell
    git clone <Repository URL>
    ```

    Alternatively, simply copy the files to your local machine or server. Ensure that the files are accessible from your PowerShell environment.
    
2. Update the `Global_Config.ps1` file in the `config` directory with the name(s) of your Qlik-Cli context(s)
    ```powershell
    $QlikCloudContext = "Cloud_Tenant_Context"
    $QlikWindowsContext = "QSEoW"
    ```
3. (Optional) You may wish to add toolkit functions and/or operations to your PowerShell profile so that they can be used directly from the command line:
    ```powershell
    $PROFILE
    ```
    If the profile does not exist, create it:
    ```powershell
    if (!(Test-Path -Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force
    }
    notepad $PROFILE
    ```
    Add the following lines to your profile script to dot source individual toolkit functions:
    ```powershell
    $ToolkitPath = "C:\Path\To\Your\QLIK-OPS-TOOLKIT\functions"
    . "$ToolkitPath\space.ps1"
    . "$ToolkitPath\otherfunction.ps1"
    ```
    Alternatively, add the following to your profile to dot source all functions:
    ```powershell
    $ToolkitPath = "C:\Path\To\Your\QLIK-OPS-TOOLKIT\functions"
    Get-ChildItem -Path $ToolkitPath -Filter *.ps1 | ForEach-Object {
        . $_.FullName
    }
    ```
4. (Future Functionality) Add the toolkit path to your $env:PSModulePath for easier access to the functions:
    ```powershell
    $env:PSModulePath += "C:\Path\To\Your\QLIK-OPS-TOOLKIT"
    ```
### Usage
Below are examples demonstrating how to use common functions within the toolkit:

```powershell
# Migrate users from on-prem to Qlik Cloud
TODO

# Migrate an app from on-prem to Qlik Cloud
TODO

# Create spaces in Qlik Cloud
TODO

# Set space permissions in Qlik Cloud
TODO
