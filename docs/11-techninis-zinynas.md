# 11 — Techninis žinynas

Greitos nuorodos konkrečioms reikšmėms. Aiškinimams žr. atitinkamus numeruotus dokumentus.

## Portai

| Portas | Protokolas | Paskirtis | Dok. |
|---|---|---|---|
| 8089 | TCP/TLS | CoT — pagrindinė kliento jungtis | [06](06-tinklas-ir-prieiga.md) |
| 8443 | HTTPS | Marti API | [06](06-tinklas-ir-prieiga.md) |
| 8087 | TCP | Vidinis CoT (serviso paskyros, tik overlay tinkle) | [06](06-tinklas-ir-prieiga.md) |
| 8889 | HTTPS | Admin panelė (WebUI + autentifikuoti atsisiuntimai) | [06](06-tinklas-ir-prieiga.md) |
| 9000–9002 | TCP/TLS | Federacija | [05](05-sertifikatai-ir-saugumas.md), [06](06-tinklas-ir-prieiga.md) |

## `takserver.env` kintamieji

| Kintamasis | Reikšmė |
|---|---|
| `TAK_SERVER_ADDRESS` | Serverio adresas paketuose (IP/hostname) |
| `TAK_SERVER_NAME` | Rodomas vardas klientų pakete |
| `POSTGRES_PASSWORD` / `POSTGRES_USER` / `POSTGRES_DB` / `POSTGRES_ADDRESS` | DB prieiga |
| `CA_NAME` / `CA_PASS` | Sertifikatų autoritetas |
| `TAKSERVER_CERT_PASS` | Serverio sertifikato slaptažodis |
| `ADMIN_CERT_NAME` / `ADMIN_CERT_PASS` | TAK administratoriaus sertifikatas |
| `COUNTRY` / `STATE` / `CITY` / `ORGANIZATION` / `ORGANIZATIONAL_UNIT` | CA sertifikato metaduomenys |
| `DOCKER_SOCKET_GID` | Docker socket grupės ID (nustato diegėjas) |
| `LOGGING_JSON_ENABLED` / `LOGGING_CONFIG` | JSON logų formatas |
| `ADMIN_SECRET_KEY` | JWT pasirašymo raktas (generuoja diegėjas) |
| `ADMIN_FIRST_USER` / `ADMIN_FIRST_PASS` | Pirmojo superadmin paskyra (slaptažodis ištrinamas po pirmo paleidimo) |
| `TAK_BASEMAP_PROXY_ENABLED` / `TAK_BASEMAP_PROXY_URL` / `TAK_BASEMAP_CACHE_MAX_MB` / `TAK_BASEMAP_OFFLINE_PUSH_MAX_MB` / `TAK_BASEMAP_AOI_MAX_TILES` | Bazlapių (basemap) tinkle |
| `BASEMAP_SERVICE_CERT_NAME` | Serviso sertifikatas bazlapių gatewayui |
| `OIDC_ISSUER` / `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` / `OIDC_PROVIDER_NAME` / `OIDC_SCOPES` / `OIDC_GROUPS_CLAIM` / `OIDC_DEFAULT_ROLE` / `OIDC_ROLE_MAP` / `OIDC_REDIRECT_URL` / `OIDC_POST_LOGIN_URL` | Pasirenkamas SSO — tuščia reikšmė = išjungta |

Pilnas komentuotas šablonas: `takserver.env.example`.

## `make` komandos

| Komanda | Ką daro |
|---|---|
| `make build` / `up` / `down` / `restart` | Konteinerių gyvavimo ciklas |
| `make update` | Paleidžia `update.sh` |
| `make add-user USERNAME=x-iTAK` | Sertifikatas + paketas + autorizacija vienu žingsniu |
| `make gen-device-cert` / `make-package` / `gen-cert` / `enable-user` | Granuliuoti naudotojo kūrimo žingsniai |
| `make list-packages` / `serve-packages` | Paketų sąrašas / serverio info |
| `make add-plugin APK=...` / `list-plugins` | Kliento papildiniai |
| `make install-plugin JAR=...` | Serverio papildinys |
| `make add-service NAME=x` | Sertifikatas mašininei integracijai |
| `make logs` / `logs-db` / `status` | Stebėjimas |
| `make shell` | Bash į `takserver_config` |
| `make generate-lockfile` | `admin/ui/pnpm-lock.yaml` sugeneravimas per Docker |

## Rolės (admin panelė)

| Rolė | Prieiga |
|---|---|
| `superadmin` | Viskas, įskaitant naudotojų valdymą, logus, audito žurnalą, shell |
| `admin` | Naudotojai, paketai, papildiniai, žemėlapiai — be sistemos administravimo |
| `readonly` | Tik peržiūra |
| `field` | Tik savo paketų atsisiuntimas |

## Kliento tipo sufiksai

`USERNAME` visada baigiasi `-ATAK`, `-WinTAK`, `-iTAK` arba `-Service` (pastarasis — automatizuotoms integracijoms, ne TAK klientui).
