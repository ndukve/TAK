# 06 — Tinklas ir prieiga

## Kaip įrenginiai pasiekia serverį

Diegimo metu (`install.sh` [1/7]) pasirenkamas vienas iš trijų variantų:

| Variantas | Kada naudoti |
|---|---|
| **Vietinis tinklas (LAN/Wi-Fi)** — rankinis IP | Visi įrenginiai tame pačiame tinkle kaip serveris. Reikia statinio IP arba DHCP rezervacijos. |
| **NetBird** | Nuotolinis prisijungimas, WireGuard tuneliu. Setup raktas iš [app.netbird.io](https://app.netbird.io) → Keys. |
| **Tailscale** | Nuotolinis prisijungimas, alternatyva NetBird. Auth raktas iš [login.tailscale.com](https://login.tailscale.com) → Settings → Keys. |

Jei serveryje jau veikia ir NetBird, ir Tailscale, `install.sh` paklaus, kurį naudoti kaip `TAK_SERVER_ADDRESS`.

## Portai

| Portas | Protokolas | Paskirtis |
|---|---|---|
| 8089 | TCP/TLS | CoT — pagrindinė TAK kliento jungtis (mTLS) |
| 8443 | HTTPS | Marti API |
| 8087 | TCP (plaintext) | Anoniminis CoT įėjimas (be TLS ir be kliento sertifikato; žr. `TAK_USER_GROUP` faile `templates/CoreConfig.tpl`), paskelbtas tik serverio loopback sąsajoje — **niekada neskelbti tinklo sąsajoje; klientai naudoja 8089** |
| 9444 | HTTPS | Admin panelė — WebUI, autentifikuotas paketų/papildinių/žemėlapių atsisiuntimas |
| 9000–9002 | TCP/TLS | Federacija (žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md)) |

> **`Makefile` ir šaknies `README.md` mini portą 8888** kaip anoniminį paketų serverį — šis kelias pasenęs. Faktinis kelias per naujausią kodą: `GET /api/packages/{vardas}/download` per admin panelės portą **9444**, autentifikuotas (`admin`/`superadmin`/`field` rolė). Jei atsisiuntimas per `:8888` neveikia, naudoti admin panelę arba `./scripts/admin_fallback.sh`.

## Klientų paketų atsisiuntimas

Per admin panelę (Packages → Download) arba `./scripts/admin_fallback.sh`, jei WebUI nepasiekiama. Reikalauja prisijungimo — anoniminės viešos prieigos prie paketų nėra.

## Federacija su kitu TAK serveriu

Žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md) ir `templates/CoreConfig.tpl` `<federation>` bloką. Reikalauja abipusio sertifikatų pasikeitimo su kitos šalies TAK serveriu.
