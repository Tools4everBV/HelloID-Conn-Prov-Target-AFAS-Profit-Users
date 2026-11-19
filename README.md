# HelloID-Conn-Prov-Target-AFAS-Profit-Users

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/blob/main/Logo.png?raw=true" alt="AFAS Logo">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-AFAS-Profit-Users](#helloid-conn-prov-target-afas-profit-users)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
      - [Scope](#scope)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
      - [Field mapping options](#field-mapping-options)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Breaking change in version 5.0.0](#breaking-change-in-version-500)
    - [Private data](#private-data)
    - [Users are never deleted](#users-are-never-deleted)
    - [Concurrent actions](#concurrent-actions)
    - [One AFAS user per person number](#one-afas-user-per-person-number)
    - [Comma or semicolon in values](#comma-or-semicolon-in-values)
    - [Create / correlate](#create--correlate)
    - [Update](#update)
    - [Reconciliation](#reconciliation)
    - [Import](#import)
    - [Permissions](#permissions)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-AFAS-Profit-Users_ is a _target_ connector. _AFAS-Profit-Users_ provides an interface to communicate with Profit through a set of GetConnectors, which is a component that allows the creation of custom views on the Profit data. GetConnectors are based on a pre-defined `'data collection'`, which is an existing view based on the data inside the Profit database.

The connector is primarily used to correlate existing AFAS users and to keep account data such as the e-mail address and UPN up to date. Creating an AFAS user is optional. Account data and the account lifecycle are handled by the account lifecycle scripts; AFAS authorizations (InSite, Profit Windows, etc.) are handled as permissions, so they can be assigned with business rules.

> [!WARNING]
> Version 5.0.0 contains breaking changes and is not backward compatible with version 4.x. See [MIGRATION.md](./MIGRATION.md).

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks                                                       |
| ----------------------------------------- | --------- | --------------------------------------- | ------------------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete | Create correlates; creating a user is optional (`CreateUser`) |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 | Static, see [Permissions](#permissions)                       |
| **Resources**                             | ❌         | -                                       |                                                               |
| **Entitlement Import: Accounts**          | ✅         | -                                       |                                                               |
| **Entitlement Import: Permissions**       | ✅         | -                                       |                                                               |
| **Governance Reconciliation Resolutions** | ✅         | Disable                                 | Disable only, see [Reconciliation](#reconciliation)           |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/refs/heads/main/Icon.png
```

### Requirements

- HelloID Provisioning agent (cloud or on-prem).
- **AFAS GetConnector** `T4E_HelloID_Target_Users`:<br>
  Import [Tools4ever - HelloID - T4E_HelloID_Target_Users.gcn](./Tools4ever%20-%20HelloID%20-%20T4E_HelloID_Target_Users.gcn) into the AFAS Profit environment. The scripts use the fields `EmId`, `BcCo`, `UsId`, `Nm`, `EmAd`, `Upn`, `Site`, `Bl` and the permission fields `InSi`, `Awin`, `OcUs`, `PoMa` and `AcUs`. When the GetConnector is changed, these fields must remain available.
- **AFAS update connector** `KnUser`:<br>
  The built-in Profit update connector that is used to create and update users.
- **AFAS App Connector**:<br>
  An App Connector with OAuth client credentials (client id and client secret) and access to the GetConnector and the `KnUser` update connector. See the AFAS Knowledge Base: [Create the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm), [Manage the APP connector](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Maint.htm) and [Configure OAuth on the APP connector](https://help.afas.nl/help/NL/SE/120718.htm#o136210).

### Connection settings

The following settings are required to connect to the API.

| Setting                                                | Description                                                                                                                                                                                                   | Mandatory |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Base Uri                                               | The URL to the AFAS environment REST services                                                                                                                                                                 | Yes       |
| Client ID                                              | The OAuth client id of the AppConnector                                                                                                                                                                       | Yes       |
| Client Secret                                          | The OAuth client secret of the AppConnector                                                                                                                                                                   | Yes       |
| GetConnector                                           | The GetConnector in AFAS to query the user with. Default: `T4E_HelloID_Target_Users`                                                                                                                          | Yes       |
| UpdateConnector                                        | The UpdateConnector in AFAS to update the user with. Default: `KnUser`                                                                                                                                        | Yes       |
| Update User ID after correlation                       | When toggled, the User ID (`UsId`) is changed to the mapped value when it differs, only in the update that directly follows the correlation. **This is not advised, as it can break links in AFAS. Consult AFAS first.** | No        |
| Create user when Medewerker has no User ID             | When toggled, the create action creates a new AFAS user when the correlated employee has no User ID. When not toggled, the create action fails for such an employee (correlate only).                         | No        |
| Behavior on disable during a reconciliation action     | A disable triggered by reconciliation always blocks the user and disables OutSite. Choose whether groups are kept (default) or removed. See [Reconciliation](#reconciliation).                                   | Yes       |

#### Scope

The data collection retrieved by the set of GetConnectors is sufficient for HelloID to provision persons. The data collection can be changed by the customer itself to meet their requirements.

| Connector                                          | Field               | Default filter            |
| -------------------------------------------------- | ------------------- | ------------------------- |
| __Tools4ever - HelloID - T4E_HelloID_Target_Users__ | contract start date | <[Vandaag + 3 maanden]    |
|                                                    | contract end date   | >[Vandaag - 3 maanden];[] |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _AFAS Profit_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `EmId`                            |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!NOTE]
> Fill in the correct customer code in the field mapping for `UsId`.

| Field  | Actions                 | Purpose                                                                                       |
| ------ | ----------------------- | --------------------------------------------------------------------------------------------- |
| `EmId` | Create                  | Correlation on the employee number                                                            |
| `EmAd` | Create, Update, Delete  | Business e-mail address during employment and the value after employment                      |
| `Upn`  | Create, Update, Delete  | Login name / UPN during employment and the value after employment                             |
| `UsId` | Create, Update          | AFAS user ID; only changed by update when `Update User ID after correlation` is toggled       |
| `BcCo` | Create, Update          | Person number and account reference; filled by the scripts from AFAS, not by the mapping      |
| `Site` | Enable, Disable, Delete | OutSite. `EmAd` is required to enable OutSite                                                 |
| `MtCd` | Enable, Disable, Delete | AFAS mutation code that sets the block status and group behavior                              |

The mutation codes (`MtCd`) of the `KnUser` update connector are: `0` block user and remove groups, `1` update user, `2` block user and keep groups, `3` update user, `4` change user ID (handled by the update script, do not map), `5` change password (do not map), `6` unblock user. When `MtCd` is not mapped, the scripts use `1`.

`Nm` (user description) is not in the field mapping. AFAS requires it in every update, so the scripts send the current value from AFAS (or `UsId` when it is empty). It cannot be changed with this connector.

#### Field mapping options

Two field mappings are available. They differ only in the end state after employment:

| File                                                     | Disable                                  | Delete                                                                             |
| -------------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------- |
| [_fieldMapping.json_](./fieldMapping.json)               | OutSite disabled, user blocked and groups kept (`2`) | OutSite disabled, user blocked and groups kept (`2`), UPN and e-mail cleared |
| [_fieldMapping.option2.json_](./fieldMapping.option2.json) | OutSite disabled, user not blocked (`1`) | OutSite disabled, user not blocked (`1`), UPN cleared, e-mail set to the private e-mail address |

Use the default mapping when former employees must be blocked in AFAS. Use option 2 when former employees must not be blocked and keep their private e-mail address in AFAS. For the use of these AFAS settings, see the [AFAS documentation](https://help.afas.nl/help/en/SE/App_Conect_UpdDsc_KnUser.htm). Both mappings set OutSite to disabled on enable; change the `Site` mapping for enable to `true` when OutSite must be enabled for active employees.

### Account Reference

The account reference is populated with the `BcCo` property (person number) from _AFAS Profit_. The `UsId` property is used to identify the user in AFAS update requests.

## Remarks

### Breaking change in version 5.0.0

> [!WARNING]
> Version 5.0.0 is **not backward compatible** with version 4.x. The account reference, the correlation field and the GetConnector have changed. Upgrade with a clean go-live of the connector, see [MIGRATION.md](./MIGRATION.md).

### Private data

- **GDPR**: The private data of persons, such as the private e-mail address and birth date, is not in the data collection by default. When it is needed for the implementation (for example the private e-mail address on delete in _fieldMapping.option2.json_), these properties have to be added.

### Users are never deleted

- **No delete in AFAS**: The delete action only updates the user to its end state (see [Field mapping options](#field-mapping-options)).

### Concurrent actions

- **Set concurrent actions to 1**: When using the permissions of this connector, set the concurrent actions of the target system to `1`. The AFAS `KnUser` update connector updates the user as a whole, so two simultaneous mutations on the same user will clash and can overwrite each other's changes.

### One AFAS user per person number

- **Unique person number**: A person number (`BcCo`) must resolve to a single AFAS user in the GetConnector. When multiple users are found, the action fails and the audit log lists the user IDs (`UsId`) that were found.

### Comma or semicolon in values

- **Filter values**: Account reference values and correlation values that contain a comma or semicolon are rejected, because AFAS uses these characters to separate filter values.

### Create / correlate

The create action searches the employee by `EmId` with a non-empty `BcCo`. When the employee has a `UsId`, the AFAS user is correlated. When the employee has no `UsId`, a new AFAS user is created only when `Create user when Medewerker has no User ID` is toggled; all authorizations are then set to `false` and are granted with permissions.

### Update

The update action only sends the changed fields. An empty (`""`) or `null` mapped value clears the field in AFAS. `UsId` cannot be cleared.

### Reconciliation

- **Disable only**: This is a correlate-only connector, so AFAS users are never deleted, and a user that is not managed by HelloID cannot be reliably distinguished from a user outside the scope of HelloID. Only disable is supported as a reconciliation resolution, because blocking the user is the opposite of enable and the next account import returns the user as disabled. A delete triggered by reconciliation fails with an error.
- **Disable behavior**: During reconciliation no field mapping data is available, so disable uses the setting `DisableMode`:

| Value                                     | Disable                                   |
| ----------------------------------------- | ----------------------------------------- |
| `blockKeepGroupsDisableOutSite` (default) | OutSite disabled, block and keep groups   |
| `blockRemoveGroupsDisableOutSite`         | OutSite disabled, block and remove groups |

### Import

The account entitlement import is used for reconciliation, entitlement import and rule mining. It returns every user in the GetConnector with a person number (`BcCo`) and a UPN (`Upn`). A user without a UPN is not an account, because both field mappings clear `Upn` on delete. When the delete mapping is changed, the import filter must match the end state of the delete action. `Enabled` is the opposite of the block status (`Bl`).

### Permissions

The permission reference is the AFAS field name: `InSi` (InSite), `Awin` (Profit Windows), `OcUs` (collaboration license), `PoMa` (AFAS Online Portal administrator) and `AcUs` (AFAS Accept).

> [!IMPORTANT]
> AFAS only allows `Awin` while `InSi` is active. Granting `Awin` fails while `InSi` is not active, and revoking `InSi` fails while `Awin` is active. Make sure that the business rules grant `InSi` whenever they grant `Awin`.

## Development resources

### API endpoints

The following endpoints are used by the connector.

| Endpoint                      | HTTP Method | Description                        |
| ----------------------------- | ----------- | ---------------------------------- |
| profitrestservices/oauth/token | POST       | Retrieve an OAuth access token     |
| profitrestservices/connectors | GET         | Retrieve user information          |
| profitrestservices/connectors | POST        | Create a user                      |
| profitrestservices/connectors | PUT         | Update user information            |

### API documentation

[AFAS App Connector documentation](https://help.afas.nl/help/NL/SE/App_Apps_Custom_Add.htm)

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
