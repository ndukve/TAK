# 07 — Stebėjimas

## Admin panelės Dashboard

Realaus laiko servisų būsena (5s poll): CPU/RAM/diskas/uptime/load/tinklas, kiekvienas servisas su būsenos indikatoriumi ir paskutinio stebėjimo laiku ("as of Xs ago"). Bendras sprendimas (NOMINAL/INCOMPLETE) skaičiuojamas iš realių duomenų — jei visi servisai veikia ir diskas nekritinis, NOMINAL; priešingu atveju įvardijamas konkretus servisas/signalas, kuriam reikia dėmesio.

## `health.sh`

```bash
./health.sh
```

Savarankiškas (self-heal + self-test) patikrinimas veikiančiam diegimui prieš dabartinį `git` commit:

- **Self-heal:** tikrina, ar kiekvieno veikiančio atvaizdo įrašytas git-commit žymeklis sutampa su HEAD. Nesutapimas reiškia, kad Docker sluoksnio talpykla (layer cache) tyliai panaudojo pasenusį sluoksnį — automatiškai priverčia `--no-cache` perstatymą.
- **Self-test:** tikrina, ar paketo generatorius realiai sukuria teisingą zip struktūrą kiekvienam kliento tipui, ne tik ar atvaizdas iš teisingo commit'o.

Saugu paleisti bet kada — nedaro `git pull`/`fetch` (tai `update.sh` darbas). `update.sh` automatiškai iškviečia `health.sh`, jei jo pačio greitas self-test'as nepavyksta po įprasto build'o.

## Auditas

Admin panelė rašo audito įrašus (prisijungimai, naudotojų valdymas, konfigūracijos pakeitimai) — matoma superadmin rolei per Audit Logs.

## Pranešimai

In-app toast pranešimai admin panelėje sėkmingoms/nepavykusioms operacijoms. **Nėra** išorinio pranešimų kanalo (Slack, el. paštas, webhook) — jei reikia, tai reikėtų kurti atskirai, šiuo metu neįdiegta.

## Logai

```bash
make logs       # visi servisai, sekimo režimu
make logs-db    # tik takdb
```

Admin panelėje: Logs (superadmin, konkretaus serviso filtras).
