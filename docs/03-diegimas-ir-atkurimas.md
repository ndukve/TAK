# 03 — Diegimas ir atkūrimas

Šis dokumentas — aukšto lygio apžvalga, kada ir kaip diegiama/atkuriama. Žingsnis po žingsnio instrukcijos yra atskiruose vadovuose.

## Naujas diegimas

Pilnas vadovas: [docs/INSTALL.md](INSTALL.md) (EN) / [docs/DIEGIMAS.md](DIEGIMAS.md) (LT).

`install.sh` yra interaktyvus 7 žingsnių vediklis:

| Žingsnis | Ką nustato |
|---|---|
| 1/7 — Networking | Kaip įrenginiai pasiekia serverį: NetBird, Tailscale ar rankinis IP (žr. [06-tinklas-ir-prieiga.md](06-tinklas-ir-prieiga.md)) |
| 2/7 — Certificate metadata | CA duomenys (šalis, organizacija ir kt.) — žr. [05-sertifikatai-ir-saugumas.md](05-sertifikatai-ir-saugumas.md) |
| 3/7 — Admin panel | Pirmojo superadmin naudotojo vardas/slaptažodis |
| 4/7 — Review | Suvestinės patvirtinimas prieš vykdant |
| 5/7 — System setup | Docker Engine diegimas, jei jo dar nėra |
| 6/7 — Write config | `takserver.env` sugeneravimas iš pateiktų atsakymų |
| 7/7 — Build & start | Atvaizdų surinkimas ir konteinerių paleidimas |

Baigus, skriptas parodo CoT/API/admin panelės adresus ir pirmojo admin naudotojo prisijungimo duomenis.

**Pakartotinis paleidimas**, kai `takserver.env` jau egzistuoja: skriptas aptinka esamą diegimą ir siūlo arba palikti kaip yra, arba pereiti per konfigūraciją iš naujo (`reconfigure`), perrašant `takserver.env`.

## Diegimas be interneto

`install-offline.sh` — tas pats vediklis, bet naudoja iš anksto atsisiųstus Docker atvaizdus vietoje `docker pull`. Naudinga izoliuotuose (air-gapped) tinkluose.

## Atkūrimas iš atsarginės kopijos

Pilna procedūra: [08-atsargines-kopijos.md](08-atsargines-kopijos.md).

Trumpai: `./restore.sh <backup-dir>` — **destruktyvu**, perrašo esamą admin DB, TAK CoT DB, sertifikatus/paketus, papildinius ir žemėlapius atsarginės kopijos duomenimis. Reikalauja patvirtinimo įvedant `restore`.

## Atnaujinimas (ne naujas diegimas)

Jau veikiančio diegimo atnaujinimas naujausia kodo versija — tai **ne** šis dokumentas, žr. [10-atnaujinimai.md](10-atnaujinimai.md).
