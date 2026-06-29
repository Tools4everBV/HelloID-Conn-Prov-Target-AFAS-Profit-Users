# Voorstel refactor AFAS User target connector

## Aanleiding

De huidige AFAS User target connector ondersteunt meer dan in de praktijk nodig is. De connector wordt vooral gebruikt om bestaande AFAS-gebruikers te correleren en kernvelden zoals e-mailadres en UPN bij te werken. Echte user-create komt nauwelijks voor, omdat gebruikers meestal al bestaan via OutSite of medewerkerregistratie.

Daarnaast is UserId als account reference minder geschikt, omdat deze kan wijzigen. Persoonsnummer is stabieler en sluit beter aan op de relatie tussen medewerker en gebruiker.

De refactor moet de connector vereenvoudigen, maar zonder alle AFAS-autorisaties automatisch als permissions te modelleren. Het onderscheid wordt: accountdata en lifecycle in de account life cycle scripts, zelfstandige autorisaties als permissions.

## Doel

De nieuwe connector wordt de standaard voor nieuwe implementaties en herinrichtingen.

Doelen:

* geen echte AFAS user-create meer;
* Persoonsnummer als account reference;
* kleinere fieldmapping;
* duidelijke scheiding tussen data, lifecycle en autorisaties;
* InSite als vaste lifecycle-logica;
* OutSite als configureerbaar lifecyclegedrag;
* blokkeren/deblokkeren als aparte lifecycle-keuze;
* Profit en overige zelfstandige autorisaties als permissions;
* verwijderen van legacy-functionaliteit zoals `only update on correlate`;
* bestaande connector beschikbaar houden voor legacy-scenario’s.

## Scope

Binnen scope:

* create vervangen door correlate only;
* account reference wijzigen naar Persoonsnummer;
* fieldmapping beperken tot relevante accountvelden;
* lifecyclegedrag vastleggen per actie;
* OutSite en blokkeren configureerbaar maken;
* permission imports toevoegen voor zelfstandige autorisaties;
* target GET-connector(s) aanpassen;
* `only update on correlate` verwijderen.
* scripts herschrijven volgens laatste conventie

Buiten scope:

* refactor van de AFAS Medewerker connector;
* herontwerp van bestaande AFAS source connectors;
* automatische migratie van bestaande klantinrichtingen.

## Ontwerpkeuzes

### 1. Geen echte user-create

Create maakt geen AFAS-gebruiker meer aan. De actie correleert een bestaande gebruiker, legt de account reference vast en schrijft de relevante startwaarden.

Klanten die echte user-create gebruiken blijven op de bestaande connector of worden apart beoordeeld.

### 2. Persoonsnummer als account reference

De account reference wordt Persoonsnummer in plaats van UserId.

Motivatie:

* stabieler dan UserId;
* logischer bij koppeling met medewerker;
* minder gevoelig voor wijzigende gebruikersnamen of technische IDs.

Bij migratie moeten bestaande correlaties gecontroleerd worden.

### 3. Fieldmapping

Fieldmapping wordt gebruikt voor accountdata in update en delete, met een kleine set velden.

Actuele fieldmapping:

| Veld           | Acties         | Doel                                                    |
| -------------- | -------------- | ------------------------------------------------------- |
| Persoonsnummer | Update         | Account reference                                       |
| Medewerker     | Create         | Correlatie                                              |
| EmAd           | Update, Delete | Zakelijk e-mailadres tijdens dienstverband en opschonen |
| Upn            | Update, Delete | Loginnaam / UPN tijdens dienstverband en opschonen      |
| UsId           | Update         | Alleen technisch indien Update User ID is ingeschakeld  |

`Nm` staat niet in de fieldmapping, maar wordt in update-, enable-, disable-, delete- en permission-calls verplicht scriptmatig meegestuurd omdat AFAS dit veld vereist in de update payload.

### 4. Verwijderen `only update on correlate`

De legacy-optie `only update on correlate` wordt niet meegenomen.

Deze optie past niet bij het nieuwe model. Create/correlate zet de initiële waarden, update houdt kernvelden actueel en delete zet waarden terug of schoont ze op.

Als bijvoorbeeld de UPN in AD wijzigt, moet deze wijziging ook naar AFAS worden doorgeschreven. De update-actie mag dit niet overslaan omdat het account al eerder is gecorreleerd.

## Lifecycle per actie

HelloID kent een vaste volgorde. Bij indienst loopt create vóór enable. Bij uitdienst loopt disable vóór delete. Permissions worden beheerd via grant/revoke scripts en zitten na create en vóór delete in de lifecycle.

### Create / correlate

Verantwoordelijk voor koppeling en startdata:

* bestaande AFAS-user zoeken en correleren;
* ARef zetten op Persoonsnummer.

Geen lifecycle- of permissionlogica.

### Enable

Verantwoordelijk voor de actieve lifecycle-stand:

* deblokkeren indien geconfigureerd;
* InSite aanzetten;
* OutSite toepassen volgens indienstconfiguratie.

Geen EmAd/UPN/Nm-mutaties.

### Update

Verantwoordelijk voor datamutaties tijdens dienstverband:

* EmAd;
* Upn;
* optioneel UsId (alleen bij ingeschakelde configuratieoptie `UpdateUserId`).

Geen lifecycle- of permissionlogica.

### Disable

Verantwoordelijk voor de niet-actieve lifecycle-stand en daarmee de tegenhanger van enable:

* InSite uitzetten;
* Profit Windows uitzetten als deze nog actief is;
* OutSite toepassen volgens uitdienstconfiguratie;
* blokkeren indien geconfigureerd.

Disable ondersteunt reconciliation voor alle `DisableDeleteMode`-waarden zonder extra uitzonderingslogica. In disable worden alleen lifecyclevelden aangepast (zoals InSi, Awin, Site en MtCd), geen Upn/EmAd.

### Delete / uncorrelate

Verantwoordelijk voor de definitieve post-employment eindstaat:

* EmAd/UPN volgens delete-fieldmapping;
* InSite idempotent uitzetten;
* OutSite idempotent toepassen volgens uitdienstconfiguratie;
* blokkering idempotent toepassen volgens configuratie;
* uncorrelate.

Delete herhaalt bewust lifecycle-mutaties om de eindstaat te borgen. Reconciliationgedrag voor delete blijft apart beoordeeld ten opzichte van disable.

## Configuratiemodel

De connector gebruikt twee dropdowns in plaats van gecombineerde toggles.

### Gedrag bij enable (`EnableOutSiteMode`)

| Waarde           | Betekenis                    |
| ---------------- | ---------------------------- |
| `disableOutSite` | OutSite expliciet uitzetten  |
| `ignoreOutSite`  | OutSite niet aanpassen       |
| `enableOutSite`  | OutSite expliciet aanzetten  |

Enable zet daarnaast altijd InSite aan en deblokkeert de gebruiker.

### Gedrag bij disable en delete (`DisableDeleteMode`)

| Waarde                            | Betekenis                                                            |
| --------------------------------- | -------------------------------------------------------------------- |
| `enableOutSiteNoBlock`            | OutSite aan, niet blokkeren                                          |
| `blockKeepGroupsDisableOutSite`   | OutSite uit, blokkeren met groepen behouden                          |
| `blockRemoveGroupsDisableOutSite` | OutSite uit, blokkeren met groepen verwijderen (AFAS entrycode `0`) |

## InSite

InSite wordt vaste lifecycle-logica. Er is geen bekend scenario waarin een gebruiker tijdens dienstverband géén InSite moet hebben. Zonder InSite heeft de AFAS User connector functioneel weinig waarde.

| Actie   | InSite          |
| ------- | --------------- |
| Enable  | Aan             |
| Disable | Uit             |
| Delete  | Uit, idempotent |

InSite wordt geen permission en geen klantconfigureerbare fieldmapping.

## OutSite

OutSite is lifecycle-afhankelijk en wordt niet als permission gemodelleerd.

| Actie   | Sturing                                                     |
| ------- | ----------------------------------------------------------- |
| Enable  | via `EnableOutSiteMode` (`disableOutSite`, `ignoreOutSite`, `enableOutSite`) |
| Disable | via `DisableDeleteMode` (`enableOutSiteNoBlock` of blokvarianten met OutSite uit) |
| Delete  | via `DisableDeleteMode` (zelfde keuzes als disable)         |

Timing van enable/disable/delete blijft in HelloID gestuurd via lifecycle en eventuele offsets, niet in deze connectorlogica.

## Blokkeren/deblokkeren

Blokkeren/deblokkeren is onderdeel van lifecycle:

| Actie   | Gedrag                                                                 |
| ------- | ---------------------------------------------------------------------- |
| Enable  | Altijd deblokkeren (AFAS entrycode `6`)                                |
| Disable | `enableOutSiteNoBlock`: niet blokkeren; block-varianten: wel blokkeren |
| Delete  | `enableOutSiteNoBlock`: niet blokkeren; block-varianten: wel blokkeren |

Voor block-varianten worden in de implementatie twee codes gebruikt:

* groepen behouden: `MtCd = 2`;
* groepen verwijderen: `MtCd = 0`.

Combinaties met OutSite aan en blokkeren worden niet gebruikt in het huidige model.

## Permissions

Alleen zelfstandige autorisaties worden permissions:

* `Awin` - Profit;
* `OcUs` - Activate collaboration license;
* `PoMa` - AFAS Online Portal administrator;
* `AcUs` - AFAS Accept.

InSite en OutSite worden niet als permissions geïmporteerd.

## Advies

Introduceer een nieuwe AFAS User target connector voor nieuwe implementaties en herinrichtingen. Gebruik Persoonsnummer als account reference, verwijder echte user-create en houd enable/disable smal.

Beheer accountdata via update/delete, lifecycle via enable/disable/delete en zelfstandige autorisaties via permissions. Enable en disable vormen elkaars tegenhangers; delete borgt de post-employment eindstaat idempotent en verwerkt delete-opschoning van Upn en EmAd.

Verwijder `only update on correlate`, zodat wijzigingen in kernvelden zoals UPN en e-mailadres ook na initiële correlatie naar AFAS worden doorgevoerd.