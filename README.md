# teamctl

Schlankes Kommandozeilen-Werkzeug (Bash), mit dem ein Team seine Infrastruktur
mit kurzen Befehlen verwaltet:

- **Wiki (Docmost)** - Spaces und Seiten lesen, suchen, anlegen, aktualisieren
- **Blog (statische Seite)** - Posts veroeffentlichen und in die Indexseite einhaengen
- **Git (GitHub)** - Repos, Branches, Commits, Issues, Dateien lesen und schreiben

Die Ausgabe ist knapp und maschinenlesbar (TAB-getrennt); Statuszeilen gehen auf
stderr. Zugangsdaten stehen ausschliesslich in der lokalen Konfigurationsdatei
`teamctl.env` (chmod 600) und werden nie ausgegeben.

## Voraussetzungen

- Bash, `curl`, `jq`, `git`, `ssh`/`scp`
- GitHub-Zugriff ueber einen Token (siehe Konfiguration)
- fuer den Wiki-Teil: erreichbare Docmost-Instanz
- fuer den Blog-Teil: SSH-Zugang zu dem Host, auf dem die statische Seite liegt

## Installation

1. Repo klonen (oder Dateien ablegen) und ausfuehrbar machen:

       git clone https://github.com/kix-ai/teamctl.git
       cd teamctl
       chmod +x teamctl

2. Konfiguration anlegen (Vorlage kopieren und Werte eintragen):

       cp .env.example teamctl.env
       chmod 600 teamctl.env

   `teamctl.env` ist vertraulich und wird nie committet (siehe `.gitignore`).

3. Optional ohne vollen Pfad aufrufbar machen (Symlink in einem PATH-Verzeichnis):

       mkdir -p ~/.local/bin
       ln -sf "$PWD/teamctl" ~/.local/bin/teamctl

   Das Skript loest seinen eigenen Pfad auch ueber Symlinks auf und findet seine
   `teamctl.env` daher weiterhin im Verzeichnis des echten Skripts.

## Konfiguration

Alle Infrastruktur-Werte kommen aus `teamctl.env` (oder aus echten
Umgebungsvariablen, die Vorrang haben). Der Pfad ist per `TEAMCTL_ENV_FILE`
aenderbar. Fehlt ein Pflichtwert, bricht `teamctl` mit einer klaren Fehlermeldung
und Verweis auf die Konfigurationsdatei ab.

### Pflichtwerte

| Variable | Bedeutung |
| --- | --- |
| `TEAMCTL_INFRA_HOST` | SSH-Ziel fuer Blog/SSH-Funktionen, Form `user@host` |
| `TEAMCTL_WIKI_URL` | Basis-URL der Docmost-Instanz |
| `TEAMCTL_WIKI_EMAIL` | Login-E-Mail des Wiki-Kontos |
| `TEAMCTL_BLOG_ROOT` | Verzeichnis der statischen Seite auf dem Host |
| `TEAMCTL_GIT_OWNER` | GitHub-Account/Organisation der Repos |
| `TEAMCTL_GIT_API` | GitHub-API-Basis, ueblich: https://api.github.com |

Die Endpoint-Werte `TEAMCTL_WIKI_URL` und `TEAMCTL_GIT_API` muessen mit dem
Schema `https://` beginnen. Andere Werte (`http://`, fehlendes Schema oder
leer) lassen `teamctl` mit einer Fehlermeldung abbrechen, die nur den
betroffenen Schluessel nennt - nie den Wert, Host oder die URL.

### Optionale Werte

| Variable | Default | Bedeutung |
| --- | --- | --- |
| `TEAMCTL_SSH_KEY` | `~/.ssh/id_ed25519` | Pfad zum privaten SSH-Key |
| `TEAMCTL_WIKI_CREDS` | `<skriptverzeichnis>/wiki-credentials.txt` | Kontendatei auf dem Host (pipe-getrennt; `#` am Zeilenanfang = Kommentar) |
| `TEAMCTL_WIKI_AS` | `TEAMCTL_WIKI_EMAIL` | Wiki-Konto fuer Logins |
| `TEAMCTL_GITHUB_TOKEN_CMD` | `gh auth token` | Befehl, der den GitHub-Token auf stdout liefert (nur einfache Wortliste ohne Shell-Metazeichen, siehe Sicherheit) |
| `TEAMCTL_RETRY_MAX` | `4` | Wiederholungen bei HTTP 429 |
| `TEAMCTL_RETRY_BASE` | `2` | Basis-Sekunden fuer das Backoff |
| `TEAMCTL_RETRY_CAP` | `30` | Obergrenze der Wartezeit je Versuch (Sekunden) |
| `TEAMCTL_WIKI_CA` | (kein) | Pfad zum CA-/Leaf-Zertifikat (PEM) des Wiki-Hosts; gesetzt => Wiki-curl-Aufrufe nutzen `--cacert` und verifizieren das Zertifikat |

## Beispiele

WIKI (Docmost)

    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki search <begriff>
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend] [--parent <pageId>]
    teamctl wiki upload <pageId> <bilddatei>
    (optional ueberall: --as <email|name>)
    (wiki update: --parent '' loest die Seite vom Parent)

BLOG (statische Seite auf dem Host)

    teamctl blog list
    teamctl blog publish --file <html> --slug <slug>
    teamctl blog link --title <T> --slug <slug>

GIT (GitHub, Konto per Token)

    teamctl git info <repo>
    teamctl git branches <repo>
    teamctl git commits <repo> [--n <anzahl>]
    teamctl git repos
    teamctl git list <repo> [dir]
    teamctl git create-repo <name> [--public]
    teamctl git upload <repo> <pfad> <lokale-datei> [--message <m>]
    teamctl git read <repo> <pfad> [--ref <branch>]      (Alias: git cat)
    teamctl git clone <repo> [--dir <ziel>] [--branch <b>]
    teamctl git pull <dir>
    teamctl git issue <repo> --title <T> (--body <B> | --file <md>) [--label <l>]
                      [--author <agent-id>] [--require-author]
    teamctl git issue-close <repo> <nummer>
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]

DIAGNOSE (read-only)

    teamctl doctor

`teamctl help` zeigt die Kurzuebersicht, `teamctl wiki|blog|git --help`
die jeweiligen Unterbefehle.

### Ersteller-Kennung bei `git issue`

Konvention (Quelle: Wiki "Team & Koordination" -> "Richtlinien & Vorgaben"):
ein Issue traegt im Titel das Praefix `[<agent-id>]` und beginnt im Body mit
`Ersteller: <agent-id>` sowie `Datum: <YYYY-MM-DD>`.

- `teamctl git issue` prueft die Kennung und warnt bei fehlender/unvollstaendiger
  Kennung auf **stderr** - das Issue wird trotzdem angelegt, der Exit-Code bleibt 0.
- `--require-author` macht die Pruefung strikt: fehlt die Kennung, bricht
  `teamctl` mit Klartext auf stderr und Exit-Code ungleich 0 ab - **bevor** ein
  Issue angelegt wird (kein API-Schreibaufruf).
- `--author <agent-id>` setzt die Kennung automatisch: Titel-Praefix
  `[<agent-id>] ` (falls der Titel noch nicht mit `[` beginnt) und Body-Beginn
  `Ersteller: <agent-id>` + `Datum: <YYYY-MM-DD>` (falls der Body nicht schon
  mit `Ersteller:` beginnt).

Ohne die neuen Flags bleiben Titel und Body unveraendert; die Pruefung aendert die
stdout-Ausgabe nicht (Hinweise gehen ausschliesslich auf stderr).

## Ausgabe und Fehler

- Daten auf stdout, Hinweis-/Statuszeilen auf stderr, TAB-getrennt.
- Bei Fehlern Klartext, HTTP-Code und Exit-Code ungleich 0.
- Listen-Befehle (`git repos`, `git branches`, `git commits`, `git list`,
  `git issues`, `git issues-all`, `git pulls`, `git pulls-all`) erwarten ein
  JSON-Array. Bei leerer oder unerwarteter API-Antwort bricht `teamctl` ab
  (Meldung auf stderr, Exit-Code ungleich 0) - kein stiller Erfolg mit
  Fehlertext auf stdout.
- Bei HTTP 429 wiederholt `teamctl` Wiki-Aufrufe automatisch (begrenztes
  Backoff mit Jitter, `Retry-After` wird beachtet).
- Alle Schreibbefehle machen einen Read-back und schlagen fehl, wenn das Ergebnis
  nicht bestaetigt werden kann.

## Selbstdiagnose: `teamctl doctor`

`teamctl doctor` ist ein **read-only** Selbsttest: er prueft lokale Werkzeuge,
Konfiguration und Erreichbarkeit von Wiki- und GitHub-API, ohne Daten zu
aendern. Der Befehl laeuft **vor** der Pflichtwert-Pruefung - eine
unvollstaendige oder fehlerhafte Konfiguration wird also als `FAIL`-Zeile
gemeldet statt mit einem Abbruch beendet.

Ausgabe: je Pruefung eine TAB-getrennte Zeile
`<pruefung>\t<OK|WARN|FAIL>\t<detail>`. Das Detail nennt ausschliesslich
Schluesselnamen, Status und HTTP-Codes - niemals Werte (keine URL, kein Host,
kein Token, kein Pfad-Inhalt, keine E-Mail).

| Pruefung | Inhalt |
| --- | --- |
| `deps` | `jq` und `curl` vorhanden; `openssl` nur bei gesetztem `TEAMCTL_WIKI_CA` |
| `config` | Pflichtwerte gesetzt und `https://` fuer `TEAMCTL_GIT_API`/`TEAMCTL_WIKI_URL` |
| `wiki-ca` | Datei zu `TEAMCTL_WIKI_CA` (nur wenn gesetzt): vorhanden, regulaer, lesbar, nicht leer, PEM, per `openssl` lesbar |
| `wiki-api` | Wiki-Login und `POST /api/spaces/` (OK bei HTTP 200) |
| `git-token` | Token ueber `TEAMCTL_GITHUB_TOKEN_CMD` lesbar und nicht leer |
| `git-api` | `GET /user` (OK bei HTTP 200) |
| `ssh-key` | Datei `TEAMCTL_SSH_KEY` vorhanden (sonst `WARN`, kein Abbruch) |

Exit-Code: `0`, wenn keine Pruefung `FAIL` ist (ein `WARN` allein ergibt `0`);
`1`, wenn mindestens eine Pruefung `FAIL` ist.

```bash
teamctl doctor
```

## Sicherheit

- Zugangsdaten und Tokens werden nur zur Laufzeit gelesen und nie ausgegeben.
- `teamctl.env` bleibt lokal (chmod 600, per `.gitignore` ausgeschlossen).
- Git- und SSH-Token werden nur intern als HTTP-Header uebergeben - nie in URL,
  Kommandozeile oder Ausgabe - und nicht im geklonten Repo gespeichert.
- Slugs werden auf `[A-Za-z0-9._-]` beschraenkt (kein Pfad-Traversal).
- Endpoint-Werte (`TEAMCTL_WIKI_URL`, `TEAMCTL_GIT_API`) werden auf das Schema
  `https://` beschraenkt; Klartext-HTTP und fehlendes Schema werden abgelehnt.
- `TEAMCTL_GITHUB_TOKEN_CMD` wird ohne Shell-Auswertung (kein `eval`) als
  einfache Wortliste gestartet; erlaubt sind nur `A-Z a-z 0-9 _ . / -` und
  Leerzeichen. Alle anderen Zeichen (u. a. `; & | > < $ ( )`, Backticks und
  Zeilenumbrueche) werden abgelehnt. Die Fehlermeldung nennt nur den
  Schluesselnamen, nie den Befehl oder den Token.
- `TEAMCTL_WIKI_CA` nennt nur den Pfad zu einer CA-/Leaf-Zertifikatsdatei
  (PEM) ausserhalb von Git. Ist der Schluessel gesetzt, verifizieren alle
  Wiki-curl-Aufrufe das Serverzertifikat ueber `--cacert` (kein `-k`/Bypass).
  Fehlt die Datei, ist sie leer oder nicht lesbar, bricht `teamctl` ab; die
  Meldung nennt nur den Schluesselnamen, nie den Pfad oder Zertifikatsinhalt.
- Ohne `TEAMCTL_WIKI_CA` nutzen Wiki-Aufrufe die System-CA. Fuer ein
  selbstsigniertes Wiki muss der Schluessel gesetzt sein.

## Selbsttest (Regressions-Guard)

`tests/selftest.sh` prueft Syntax, das dateiweite Fehlen jeglicher
Shell-Auswertung (`eval`) im Kommandokontext und die Ablehnung von
Metazeichen in `TEAMCTL_GITHUB_TOKEN_CMD`:

```bash
bash tests/selftest.sh
```

Exit 0 = alle Tests PASS, Exit != 0 = mindestens ein FAIL. Der Test laeuft ohne
Secrets und ohne Infrastruktur (Dummy-Konfiguration mit `.invalid`-Werten und
curl-Stub). Ein optionaler Live-Positivtest (`teamctl git repos`, Exit 0) ist
mit `TEAMCTL_SELFTEST_LIVE=1` aktivierbar.

## Lizenz

MIT - siehe `LICENSE`.
