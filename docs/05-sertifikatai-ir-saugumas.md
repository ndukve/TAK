# 05 — Sertifikatai ir saugumas

## Klientų prisijungimas (mTLS)

Kiekvienas klientas gauna savo sertifikatą, pasirašytą serverio CA. Sertifikatai generuojami vieną kartą — `firstrun.sh` paleidimo metu — ir saugomi `takserver_data` tome (volume), **ne** atvaizde (image).

> **Sertifikatų slaptažodžių keitimas reikalauja tomo išvalymo.** Jei pakeičiate `TAKSERVER_CERT_PASS` arba `CA_PASS` faile `takserver.env` po pirmo paleidimo, esami JKS failai tome liks užšifruoti senu slaptažodžiu ir nebesutaps su nauju. Reikia ištrinti tomus (`docker compose down -v`) ir leisti `firstrun.sh` sugeneruoti viską iš naujo — o tai reiškia, kad **visi** anksčiau išduoti kliento sertifikatai nustos veikę ir turės būti perleisti.

Atvaizdo (image) atnaujinimas **neatnaujina** sertifikatų — jie lieka tome. Tik tomo ištrynimas paleidžia regeneravimą.

## Admin panelės autentifikacija

- Lokalus prisijungimas: slaptažodis (bcrypt), JWT access token (15 min), rotuojamas refresh token (7 dienos) su vagystės aptikimu — pakartotinis jau panaudoto refresh token panaudojimas atšaukia visą naudotojo sesiją.
- Rolės: `superadmin` / `admin` / `readonly` / `field`.
- Slaptažodžių rotacija: 90 dienų; per 5 nesėkmingus bandymus — 15 min užrakinimas.
- Pasirenkamas OIDC SSO (Keycloak, Authentik ar bet kuris atitinkantis standartą IdP) — išjungtas pagal nutylėjimą, įjungiamas nustačius `OIDC_ISSUER`/`OIDC_CLIENT_ID`/`OIDC_CLIENT_SECRET`. IdP grupės susiejamos su panelės rolėmis per `OIDC_ROLE_MAP`. Žr. `takserver.env.example` komentarus.

## Docker socket izoliacija

Admin API neturi tiesioginės prieigos prie Docker socket. Visos konteinerių operacijos eina per `docker_socket_proxy`, kuris leidžia tik logs ir exec konkretiems TAK servisams — jokio konteinerių kūrimo/naikinimo, atvaizdų, tomų ar tinklų valdymo API. Žr. [01-architektura.md](01-architektura.md).

## Įkėlimų (uploads) validacija

Paketai, papildiniai ir žemėlapių šaltiniai: leidžiamų plėtinių sąrašas (allowlist), dydžio apribojimas, kelio sanitizacija prieš path traversal ataką.

## Federacija

TAK-serveris-į-TAK-serverį federacija sukonfigūruota `templates/CoreConfig.tpl` (portai 9000–9002, TLS abipusė autentifikacija). Numatytai portai atverti `docker-compose.yml`, bet realiam federavimui reikia abipusio sertifikatų pasikeitimo su kitu TAK serveriu — žr. `templates/CoreConfig.tpl` `<federation>` bloką.

## Pažeidžiamumų pranešimas

Žr. repo šaknies [SECURITY.md](../SECURITY.md) — privatus pranešimas per GitHub Security Advisories, ne viešą issue.
