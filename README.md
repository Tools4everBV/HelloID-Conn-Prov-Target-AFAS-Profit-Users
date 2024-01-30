# HelloID-Conn-Prov-Target-AFAS-Profit-Users
Repository for HelloID Provisioning Target Connector to AFAS Users

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users?color=2b9348"></a>

| :information_source: Information  |
| --------------------------------  |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.  |

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/afas-logo.png">
</p>

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [HelloID-Conn-Prov-Target-AFAS-Profit-Users](#helloid-conn-prov-target-afas-profit-users)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [GetConnector](#getconnector)
      - [Remarks](#remarks)
      - [Scope](#scope)
    - [UpdateConnector](#updateconnector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)


## Introduction
The interface to communicate with Profit is through a set of GetConnectors, which is component that allows the creation of custom views on the Profit data. GetConnectors are based on a pre-defined 'data collection', which is an existing view based on the data inside the Profit database. 

For this connector we have created a default set, which can be imported directly into the AFAS Profit environment.
The HelloID connector consists of the template scripts shown in the following table.

| Action                             | Action(s) Performed                                | Comment |
| ---------------------------------- | -------------------------------------------------- | ------- |
| create.ps1                         | Create or Update AFAS user                         | Optionally you can update the UserID to match the mapped convention. **Note that this is not advised as this can break certain links in AFAS. Use with care!**. Users are only created or updated when this is configured, **make sure to check your configuration options to prevent unwanted actions**.                                                                           |
| enable.ps1                         | Unblock and optionally update AFAS user             | Optionally, you can provide additional properties to update, e.g. **"EmAd", "Upn"**. The **default example sets these with the AD values**. This action is perfomed with **entry code "6"**. For more information on the entry codes, see the [AFAS documenation](https://help.afas.nl/help/en/SE/App_Conect_UpdDsc_KnUser.htm).                                                    |
| update.ps1                         | Update AFAS user                                   | Update with the specified properties, e.g. **"EmAd", "Upn"**, etc. The **default example sets these with the AD values**. This action is perfomed with **entry code "1"**. For more information on the entry codes, see the [AFAS documenation](https://help.afas.nl/help/en/SE/App_Conect_UpdDsc_KnUser.htm)                                                                       |
| disable.ps1                        | Block and optionally update AFAS user               | Optionally, you can provide additional properties to update, e.g. **"EmAd", "Upn"**.  The **default example clears these values**, as the values have to be unique over all AFAS environments. This action is perfomed with **entry code "2"**. For more information on the entry codes, see the [AFAS documenation](https://help.afas.nl/help/en/SE/App_Conect_UpdDsc_KnUser.htm). |
| delete.ps1                         | Block, remove from all groups and update AFAS user | Optionally, you can provide additional properties to update, e.g. **"EmAd", "Upn"**.  The **default example clears these values**, as the values have to be unique over all AFAS environments. This action is perfomed with **entry code "0"**. For more information on the entry codes, see the [AFAS documenation](https://help.afas.nl/help/en/SE/App_Conect_UpdDsc_KnUser.htm). |

<!-- GETTING STARTED -->
## Getting Started

By using this connector you will have the ability to update users in the AFAS Profit system.

Connecting to Profit is done using the app connector system. 
Please see the following pages from the AFAS Knowledge Base for more information.

[Create the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm)

[Manage the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Maint.htm)

[Manual add a token to the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Tokens_Manual.htm)

### Connection settings

The following settings are required to connect to the API.

| Setting                     | Description  | Mandatory |
| --------------------------- | -----------  | --------- |
| Base Uri                    | The URL to the AFAS environment REST services  | Yes       |
| Token in XML format         | The AppConnector token to connect to AFAS  | Yes       |
| Get Connector               | The GetConnector in AFAS to query the user with  | Yes       |
| Update Connector            | The UpdateConnector in AFAS to update the user with  | Yes       |
| Create account when not found  | When toggled, if the user account is not found, a new the AFAS user account will be created in the create action (only in the create action). | No        |
| Update on correlate         | When toggled, if the mapped data differs from data in AFAS, the AFAS user will be updated in the create action (not just correlated). | No        |
| Update User ID              | When toggled, the User ID will be updated if it doesn't match mapped naming convention. **Note that this is not advised as this can break certain links in AFAS. Use with care!** | No        |
| Toggle debug logging        | When toggled, extra logging is shown. Note that this is only meant for debugging, please switch this off when in production.                                  | No        |

### Prerequisites

- [ ] HelloID Provisioning agent (cloud or on-prem).
- [ ] Loaded and available AFAS GetConnectors.
- [ ] AFAS App Connector with access to the GetConnectors and associated views.
  - [ ] Token for this AppConnector

### GetConnector
When the connector is defined as target system, only the following GetConnector is used by HelloID:

*	Tools4ever - HelloID - T4E_HelloID_Users_v2

#### Remarks
 - In view of GDPR, the persons private data, such as private email address and birthdate are not in the data collection by default. When needed for the implementation (e.g. set emailaddress with private email address on delete), these properties will have to be added.
 - We never delete users in AFAS, we only clear the unique fields and block the users.

#### Scope
The data collection retrieved by the set of GetConnector's is sufficient for HelloID to provision persons.
The data collection can be changed by the customer itself to meet their requirements.

| Connector                                       | Field               | Default filter            |
| ----------------------------------------------- | ------------------- | ------------------------- |
| __Tools4ever - HelloID - T4E_HelloID_Users_v2__ | contract start date | <[Vandaag + 3 maanden]    |
|                                                 | contract end date   | >[Vandaag - 3 maanden];[] |

### UpdateConnector
In addition to use to the above get-connector, the connector also uses the following build-in Profit update-connectors:

*	KnUser

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/