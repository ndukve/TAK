# 10 — Atnaujinimai

```bash
make update
# arba tiesiogiai:
./update.sh
```

## Kas vyksta

1. **Pull** — `git fetch` + `git merge --ff-only` dabartinei šakai. Jei `update.sh` pats pasikeitė, skriptas persileidžia iš naujo (nesitęsia su pasenusiu buferiu).
2. **Env backfill** — patikrina, ar `takserver.env` turi visus reikiamus kintamuosius; trūkstamus prideda su numatytosiomis reikšmėmis.
3. **Rebuild** — atvaizdai perstatomi su nauju `GIT_COMMIT` žymekliu.
4. **`admin_proxy` restart** — priverstinis, kad nginx visada turėtų naują `admin` konteinerio IP (kitaip liktų 502 klaidos iki kito restart'o).
5. **Self-test → self-heal** — greitas funkcinis testas po build'o. Jei nepavyksta, automatiškai iškviečiamas `health.sh` (priverstinis `--no-cache` perstatymas). Tik jei ir tai nepadeda — skriptas sustoja su klaida.

## Prieš atnaujinant

- Padaryti atsarginę kopiją (žr. [08-atsargines-kopijos.md](08-atsargines-kopijos.md)), ypač produkciniame diegime.
- Įsitikinti, kad repo nėra `detached HEAD` būsenoje (`update.sh` tai patikrina ir sustoja su nurodymu `git checkout main`).
- Fast-forward-only: jei vietoje yra nesuderinamų lokalių pakeitimų, `update.sh` sustos ir nepadarys merge — reikia rankiniu būdu išspręsti prieš bandant vėl.

## Po atnaujinimo

```bash
docker compose --env-file takserver.env logs -f
```

Patikrinti, kad visi servisai veikia (`make status`) ir admin panelė pasiekiama.
