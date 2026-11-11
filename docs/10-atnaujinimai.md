

## Atnaujinimas iš privačios saugyklos

Atnaujinimo skriptas traukia iš šeimininko `origin`. Kai saugykla privati (Forgejo kopija), git reikalauja prisijungimo.

**Numatytasis būdas: prisijungiate kiekvieną kartą, niekas neišsaugoma.** Terminale paleiskite `scripts/update.sh`. Prieš pradedant atnaujinimą jis paprašo Forgejo naudotojo vardo ir slaptažodžio; vietoj paskyros slaptažodžio įklijuokite **tik skaitymo prieigos raktą (token)**. Atsakymas laikomas tik atmintyje (git `credential-cache`) kol vyksta paleidimas ir ištrinamas, kai skriptas baigia darbą: jokiame šeimininko faile jo nėra. Be terminalo (cron, paslauga) skriptas niekada neklausia ir sustoja su aiškiu pranešimu.

1. **Nukreipkite `origin` į privačią saugyklą** (vieną kartą, diegimo kataloge): `git remote set-url origin https://gv3mkw.mokomasis.org/gabrielius.ndukve/TAK.git`. Į adresą niekada nerašykite token.
2. **Susikurkite token'ą sau.** Forgejo: Settings, Applications, sukurkite prieigos token'ą, pavadintą pagal paskirtį, tik su `read:repository` sritimi. Nutekėjęs token'as leidžia skaityti, bet ne rašyti; atšaukti jį galima bet kada.
3. **Paleiskite atnaujinimą** ir paprašyti įveskite naudotojo vardą bei token. Neteisinga reikšmė sustabdo paleidimą, kol dar niekas nepasikeitė.

**Atnaujinimas be žmogaus (nebūtina).** Šeimininkui, kuris turi atsinaujinti pats, naudokite atskirą mašininį naudotoją (pavyzdžiui `efdi-deploy`) su tik skaitymo prieiga prie `TAK` ir savo token'u, tada paleiskite `git config --global credential.helper store` ir vieną kartą ranka `git fetch`; token'as liks `~/.git-credentials` (teisės 600). Tai darykite tik ten, kur leistina saugoti kredencialą. Agentas token'o niekada neliečia.

## Versijos: atnaujinimas iki žymos ir grįžimas

`scripts/update.sh` be argumentų, kaip ir anksčiau, pereina į šakos galą, bet dabar parodo, kurioje versijoje esate ir kokius commit'us ketina pritaikyti, ir iš terminalo paleistas pirmiausia paklausia (`--yes` arba `EFDI_UPDATE_YES=1` klausimą praleidžia).

- `scripts/update.sh --to v0.9.0` pereina į išleidimo žymą (žyma `stable` veikia taip pat). Jei yra pasirašytojų failas (`EFDI_ALLOWED_SIGNERS` arba `.allowed_signers` saugyklos kataloge), žymą turi būti pasirašęs vienas iš tų SSH raktų (`git verify-tag`); nepasirašyta žyma atmetama.
- Prieš keisdamas skriptas įrašo ankstesnę versiją (`.previous-version`, nesekamas git). `scripts/update.sh --rollback` grąžina į ją. Grįžti atsisakoma, jei šioje kopijoje yra commit'ų, kurių nėra jokioje nuotolinėje saugykloje.
- Pabaigoje atspausdinama versija (`git describe`).

Grįžimas grąžina kodą, bet neatšaukia duomenų pakeitimų. Kai išleidimas keičia konfigūraciją, pirmiausia pasidarykite atsarginę kopiją.
