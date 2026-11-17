# Migration

## From version 4.x to 5.0.0

> [!WARNING]
> Version 5.0.0 is **not backward compatible** with version 4.x. Do not replace the scripts of an existing 4.x target system that already has granted accounts.

Pull request: [#34](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-AFAS-Profit-Users/pull/34). Report migration issues in this pull request.

### What has changed

| Item                      | Version 4.x                                  | Version 5.0.0                                                                                    |
| ------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Account reference         | Object with the user ID (`Gebruiker`/`UsId`) | Person number `BcCo` (string)                                                                    |
| Account correlation field | `Medewerker`                                 | `EmId`                                                                                           |
| GetConnector              | `T4E_HelloID_Users_v2`                       | `T4E_HelloID_Target_Users`                                                                       |
| AFAS authorizations       | Set in the account lifecycle scripts         | Permissions (`permissions/authorizations`)                                                       |
| Configuration             | `onlyUpdateOnCorrelate`, `isDebug`           | Removed; added `DisableMode` and `DeleteMode`; `CreateUser` and `UpdateUserId` changed behavior |

The scripts look up the user by `BcCo`. With an account reference of version 4.x no user is found: update and enable fail, while disable, delete and revoke treat the account as already deleted and do nothing.

### Migration steps

Because this is primarily a correlate-only connector, the upgrade is a **clean go-live** of the connector:

1. Import the GetConnector [Tools4ever - HelloID - T4E_HelloID_Target_Users.gcn](./Tools4ever%20-%20HelloID%20-%20T4E_HelloID_Target_Users.gcn) in AFAS Profit and give the App Connector access to it.
2. Configure the target system with the scripts, configuration, correlation and field mapping of this version. Choose the field mapping that matches the intake, see [Field mapping options](./README.md#field-mapping-options).
3. Keep `CreateUser` disabled during the go-live, so existing AFAS users are only correlated.
4. Run a dry run (preview) and check the correlation results before enforcing.
5. Grant the permissions with business rules; use the permission entitlement import to compare them with the current situation in AFAS.
