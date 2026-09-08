# Voorstel refactor AFAS User target connector

## Aanleiding

De huidige AFAS User target connector wordt vooral gebruikt om bestaande AFAS-gebruikers te correleren en velden zoals e-mailadres en UPN bij te werken. In de implementatie is user-create nog optioneel beschikbaar voor het geval een gecorreleerde medewerker nog geen AFAS-user heeft.

Daarnaast is het belangrijk om correlatie en account reference functioneel te scheiden. Correlatie gebeurt op het Medewerkersnummer (`EmId`). De HelloID account reference is `BcCo`, het medewerkersnummer dat in de AFAS-userrelatie wordt gebruikt. `UsId` blijft de AFAS user identifier en username, maar is niet de HelloID account reference.

Autorisaties in AFAS gaan nu via de account scripts, terwijl het beter zou passen in permissies. Dan is het ook mogelijk om via businessrules verschillende autorisaties uit te delen o.b.v. eigenschappen van de medewerker.

De refactor moet de connector vereenvoudigen, waarbij alle AFAS-autorisaties als permissies worden gemodelleerd en er minder mapping in de scripts plaatsvindt. Het onderscheid wordt: accountdata en lifecycle in de account life cycle scripts, zelfstandige autorisaties als permissions.

## Doel

Voorstel: deze nieuwe connector wordt de beoogde standaard voor nieuwe implementaties en herinrichtingen.

Doelen:

* bestaande users correleren en user-create optioneel ondersteunen;
* een heldere correlatie- en account-reference-strategie;
* duidelijkere fieldmapping;
* betere scheiding tussen account data en autorisaties;
* afhankelijkheden tussen Outsite, EmAd en mutatiecodes explicieter documenteren in fieldmapping;
* configuratie-opties gebruiken voor reconciliation;
* InSite, Profit en overige zelfstandige autorisaties als permissions;
* verwijderen van legacy-functionaliteit zoals `only update on correlate`;
* target GET-connector(s) aanpassen;
* scripts herschrijven volgens laatste conventie

Buiten scope:

* refactor van de AFAS Medewerker connector;
* herontwerp van bestaande AFAS source connectors;
* OAuth als autorisatiemethode;
* mTLS met certificaat;
* migratie van bestaande klantinrichtingen.

## Ontwerpkeuzes

### 1. Correlatie en optionele user-create

Create zoekt op `EmId` en vereist daarbij een niet-lege `BcCo`. Als de gevonden medewerker al een `UsId` heeft, wordt de bestaande AFAS-user gecorreleerd. De actie legt `BcCo` vast als HelloID account reference en neemt de gemapte startwaarden over.

Als de gevonden medewerker geen `UsId` heeft, kan de connector afhankelijk van de configuratieoptie `CreateUser` een nieuwe AFAS-user aanmaken. Staat deze optie uit, dan faalt de actie gecontroleerd. Als er geen medewerker wordt gevonden of meerdere medewerkers worden gevonden, faalt de correlatie.

### 2. Correlatie en account references

In dit voorstel geldt:

* correlatie op `EmId`, het Medewerkersnummer;
* primaire HelloID account reference op `BcCo`;
* `UsId` als AFAS user identifier en username.

Vervolgacties zoeken de account op `BcCo`. Er is momenteel geen fallback op `UsId`, geen validatie van een opgeslagen `EmId` en geen configureerbare hercorrelatie als `BcCo` niet wordt gevonden.

Met de optie `UpdateUserId` kan `UsId` tijdens een update na correlatie eenmalig worden gewijzigd. Dit gebeurt met de AFAS-mutatiecode 4 en alleen wanneer het account in die actie is gecorreleerd. De HelloID account reference blijft daarbij `BcCo`.

### 3. Fieldmapping

Nieuwe fieldmapping:

| Veld | Acties                  | Doel                                                                       |
|------|-------------------------|----------------------------------------------------------------------------|
| EmId | Create                  | Correlatie op Medewerkersnummer                                            |
| EmAd | Create, Update, Delete  | Zakelijk e-mailadres tijdens dienstverband en eindstaat                    |
| Upn  | Create, Update, Delete  | Loginnaam / UPN tijdens dienstverband en eindstaat                         |
| UsId | Create, Update          | AFAS user identifier; update alleen wanneer `UpdateUserId` is ingeschakeld |
| BcCo | Create, Update          | HelloID account reference; scriptmatig gevuld vanuit AFAS                  |
| Site | Enable, Disable, Delete | OutSite lifecyclegedrag                                                    |
| MtCd | Enable, Disable, Delete | Mutatiecode voor blokkeren/deblokkeren en groepsgedrag                     |

`Nm` staat niet in de fieldmapping, maar wordt in update-, enable-, disable-, delete- en permission-calls verplicht scriptmatig meegestuurd omdat AFAS dit veld vereist in de update payload, maar er verder niets mee wordt gedaan. Dus een update van het veld is niet mogelijk.

### 4. Verwijderen `only update on correlate`

De legacy-optie `only update on correlate` wordt in dit voorstel verwijderd.

Deze optie past niet bij de huidige werkwijze.

## Lifecycle per actie

### Create / correlate

Verantwoordelijk voor koppeling en startdata:

* medewerker zoeken op `EmId` en controleren op een niet-lege `BcCo`;
* bestaande AFAS-user zoeken en correleren;
* optioneel een AFAS-user aanmaken als `CreateUser` is ingeschakeld en `UsId` ontbreekt;
* `BcCo` als HelloID account reference teruggeven;
* gemapte startwaarden schrijven bij correlatie of create.

Geen aparte permissionlogica.

### Enable

Verantwoordelijk voor de actieve lifecycle-stand:

* deblokkeren in combinatie met de gemapte `MtCd`;
* `Site` toepassen via fieldmapping;
* optionele `EmAd`/`Upn`-mutaties via fieldmapping.

### Update

Verantwoordelijk voor datamutaties tijdens dienstverband:

* `EmAd`;
* `Upn`;
* optioneel `UsId` bij een update na correlatie wanneer `UpdateUserId` is ingeschakeld.

Geen lifecycle- of permissionlogica.

Vervolgacties zoeken primair op de HelloID account reference `BcCo`. Wanneer het account niet wordt gevonden, faalt de update; er is geen fallback-hercorrelatie.

### Disable

Verantwoordelijk voor de niet-actieve lifecycle-stand en daarmee de tegenhanger van enable:

* `Site` toepassen via fieldmapping;
* blokkeren en groepsgedrag toepassen via fieldmapping (`MtCd`);
* optionele `EmAd`/`Upn`-mutaties via fieldmapping.

Voor reconciliationgedrag, zie verderop.

### Delete / uncorrelate

Verantwoordelijk voor de definitieve post-employment eindstaat:

* `EmAd`/`Upn` volgens de delete-fieldmapping toepassen;
* `Site` toepassen via fieldmapping;
* blokkeren en groepsgedrag toepassen via fieldmapping (`MtCd`);
* de account als verwijderd afhandelen in HelloID.

Voor reconciliationgedrag, zie verderop.

## Reconciliation

In dit voorstel gebruikt de connector-configuratie twee dropdowns ter ondersteuning van reconciliation.

### Reconciliationgedrag bij disable (`DisableMode`)

| Waarde                            | Betekenis                                      |
|-----------------------------------|------------------------------------------------|
| `enableOutSiteNoBlock`            | OutSite aan, niet blokkeren                    |
| `blockKeepGroupsDisableOutSite`   | OutSite uit, blokkeren met groepen behouden    |
| `blockRemoveGroupsDisableOutSite` | OutSite uit, blokkeren met groepen verwijderen |

### Reconciliationgedrag bij delete (`DeleteMode`)

| Waarde                            | Betekenis                                                    |
|-----------------------------------|--------------------------------------------------------------|
| `enableOutSiteNoBlock`            | OutSite aan, `Upn` wissen en `EmAd` behouden, niet blokkeren |
| `blockKeepGroupsDisableOutSite`   | OutSite uit, blokkeren met groepen behouden                  |
| `blockRemoveGroupsDisableOutSite` | OutSite uit, blokkeren met groepen verwijderen               |

Deze instellingen zijn sturing voor reconciliation, waar geen fieldmappingdata beschikbaar is.

## Permissions

In dit voorstel worden zelfstandige autorisaties als permissions gemodelleerd:

* `InSi` - InSite access (beschikbaar voor permission grant/revoke);
* `Awin` - Profit Windows access;
* `OcUs` - Activate collaboration license;
* `PoMa` - AFAS Online Portal administrator;
* `AcUs` - AFAS Accept.

De permission-import levert alle vijf bovenstaande permissions aan.

Omdat AFAS afhankelijkheden kent rond InSite/Profit Windows, wordt de bestaande randvoorwaarde expliciet meegenomen: bij revoke van InSite wordt indien nodig ook `Awin` uitgezet zodat de wijziging technisch afdwingbaar blijft.
OutSite wordt niet als permission beheerd, maar via de fieldmapping.