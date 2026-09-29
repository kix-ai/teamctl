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

Die Konfigurationsdatei wird als Shell-Code eingelesen und daher vor dem Laden
geprueft (N5): sie muss eine regulaere Datei sein (kein Symlink), dem aktuellen
Nutzer (oder root) gehoeren und darf kein Gruppen-/Welt-Schreibrecht tragen
(`chmod 600`). Andernfalls bricht `teamctl` mit einer Meldung ab und fuehrt die
Datei **nicht** aus; die Meldung nennt nur den Pfad, nie Werte.

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
| `TEAMCTL_WIKI_CA` | (kein) | Pfad zum CA-/Leaf-Zertifikat (PEM) des Wiki-Hosts; gesetzt => Wiki-curl-Aufrufe nutzen `--cacert` und verifizieren das Zertifikat. Ohne den Schluessel laufen Wiki-Aufrufe mit `-k` (TLS-Verifikation AUS - nur fuer die selbstsignierte Infrastruktur) |

## Beispiele

WIKI (Docmost)

    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki search <begriff> [--title|--full] [--export-dir DIR]
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend] [--parent <pageId>|--parent '']
    teamctl wiki upload <pageId> <bilddatei>
    teamctl wiki export [--out DIR] [--space <spaceId>] [--dry-run] [--prune|--no-prune] [--quiet]
    (optional ueberall: --as <email|name>)
    (wiki update --parent <pageId> haengt die Seite um; --parent '' loest sie auf Root)
    (wiki create/update verifizieren Titel, --parent-parentPageId und den
     gesamten Inhalt normalisiert; leerer Inhalt = Fehler -- siehe unten)

BLOG (statische Seite auf dem Host)

    teamctl blog list
    teamctl blog publish --file <html> --slug <slug> [--title <T>] [--link|--no-link]
    teamctl blog link --title <T> --slug <slug>
    teamctl blog unpublish --slug <slug> [--yes]
    teamctl blog unlink --slug <slug>
    (publish haengt den Post standardmaessig in index.html ein und verifiziert
     den Eintrag per Read-back; --no-link uebersprungen = Warnhinweis;
     --title setzt den Index-Titel, sonst wird <title> aus der Datei gelesen)
    (unpublish entfernt posts/<slug>.html remote - nur mit Bestaetigung
     (interaktiv Rueckfrage, nicht-interaktiv --yes) und nur unter posts/;
     unlink haengt den <li>-Eintrag aus index.html aus - idempotent, mit
     Read-back ueber die Link-Anzahl)

GIT (GitHub, Konto per Token)

    teamctl git info <repo>
    teamctl git branches <repo>
    teamctl git commits <repo> [--n <anzahl>]
    teamctl git repos
    teamctl git list <repo> [dir]
    teamctl git create-repo <name> [--public]
    teamctl git upload <repo> <pfad> <lokale-datei> [--message <m>] [--exec|--no-exec]
    teamctl git read <repo> <pfad> [--ref <branch>]      (Alias: git cat)
    teamctl git clone <repo> [--dir <ziel>] [--branch <b>]
    teamctl git pull <dir>
    teamctl git status <dir>
    teamctl git issue <repo> --title <T> (--body <B> | --file <md>) [--label <l>]
                      [--author <agent-id>] [--require-author]
    teamctl git issue-close <repo> <nummer>
    teamctl git issue-comment <repo> <nummer> (--body <B> | --file <md>)
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]

DIAGNOSE (read-only)

    teamctl doctor

`teamctl help` zeigt die Kurzuebersicht, `teamctl wiki|blog|git --help`
die jeweiligen Unterbefehle.

### Executable-Bit bei `git upload`

`teamctl git upload` erhaelt das Executable-Bit:

- Ist die lokale Datei ausfuehrbar (mode `+x`), schreibt teamctl sie ueber die
  Git-Data-API (blob -> tree mit mode `100755` -> commit -> ref) - der
  Executable-Bit bleibt erhalten.
- Sonst nutzt teamctl die Contents-API (mode `100644`, unveraendertes
  Altverhalten). `--exec` erzwingt `100755`, `--no-exec` erzwingt `100644`.
- Grund: die Contents-API speichert regulaere Dateien immer als `100644`;
  ein Executable-Bit laesst sich damit nicht setzen. Fehlerbild sonst:
  `mode change 100755 => 100644` beim Checkout.
- Read-back: nach dem Schreiben prueft teamctl Mode und Blob-SHA im Tree des
  neuen Commits; bei Abweichung bricht `git upload` mit Exit ungleich 0 ab.

### Ersteller-Kennung bei `git issue`

Konvention (Quelle: Wiki "Team & Koordination" -> "Richtlinien & Vorgaben"):
der Titel ist ein **normaler Kurztitel ohne Praefix**; die Agent-Kennung steht
**nur im Body** - dort beginnt der Text mit `Ersteller: <agent-id>` sowie
`Datum: <YYYY-MM-DD>`. (N6: frueher verlangte die Pruefung zusaetzlich das
Titel-Praefix `[<agent-id>]`, wodurch jede konventionsgerechte Anlage eine
WARNUNG erzeugte.)

- `teamctl git issue` prueft die Body-Kennung und warnt bei fehlender Kennung
  auf **stderr** - das Issue wird trotzdem angelegt, der Exit-Code bleibt 0.
- `--require-author` macht die Pruefung strikt: fehlt die Kennung, bricht
  `teamctl` mit Klartext auf stderr und Exit-Code ungleich 0 ab - **bevor** ein
  Issue angelegt wird (kein API-Schreibaufruf).
- `--author <agent-id>` setzt die Kennung automatisch: Body-Beginn
  `Ersteller: <agent-id>` + `Datum: <YYYY-MM-DD>` (falls der Body nicht schon
  mit `Ersteller:` beginnt). Der Titel bleibt unveraendert (kein Praefix).

Ohne die neuen Flags bleiben Titel und Body unveraendert; die Pruefung aendert die
stdout-Ausgabe nicht (Hinweise gehen ausschliesslich auf stderr).

### Kommentare auf Issues: `git issue-comment`

`teamctl git issue-comment <repo|owner/repo> <nummer> (--body <B> | --file <md>)`
postet einen Kommentar auf ein Issue (`POST /repos/{owner}/{repo}/issues/{nr}/comments`)
und verifiziert ihn per Read-back: der angelegte Kommentar wird ueber seine ID
erneut gelesen (`GET /repos/{owner}/{repo}/issues/comments/{id}`) und der Inhalt
mit der Eingabe verglichen. Bei Abweichung bricht der Befehl mit Exit ungleich 0 ab.

- `--body` fuer Inline-Text, `--file <md>` fuer eine Markdown-Datei (nicht beide
  gleichzeitig); leere Eingaben werden abgelehnt.
- `<repo>` akzeptiert wie `git issue`/`git issue-close` die Form `<repo>` (Owner =
  `TEAMCTL_GIT_OWNER`) und `<owner>/<repo>` fuer fremde Repos.
- Ausgabe (TAB-getrennt): `OK<TAB>owner/repo<TAB>nummer<TAB>kommentar-id<TAB>url`.

## Wiki-Export fuer die Memory-Suche: `teamctl wiki export`

`teamctl wiki export` exportiert **alle** Docmost-Seiten **aller** Spaces als
Markdown in ein Zielverzeichnis und haelt es idempotent aktuell. Der Export wird
von der Memory-Suche der Agents (`memory_search`) als zusaetzlicher Pfad
indiziert; so ist das Wiki durchsuchbar, ohne jede Seite in den Kontext zu laden.

- Quelle: Docmost-API (`auth/login` + `spaces/` + `pages/sidebar-pages` +
  `pages/info`), **seriell** mit einem Login je Lauf (Cookie wiederverwendet)
  und Wiederholung bei HTTP 429 (Retry-After/Backoff).
- Zugangsdaten: wie `teamctl` aus `teamctl.env` (`TEAMCTL_WIKI_*`); sie werden
  nie ausgegeben und stehen nicht in den Export-Dateien.
- Ziel: eine Markdown-Datei pro Seite, `<space-slug>__<page-slug>.md`, mit
  YAML-Kopfzeile (`title`, `space`, `spaceId`, `pageId`) und dem Seiteninhalt.
- Idempotent: unveraenderte Seiten werden nicht angefasst; im Wiki geloeschte
  Export-Dateien entfernt das Pruning per Manifest
  (`.wiki-sync-manifest.tsv`). Per Default wird dabei nur das Export-Schema
  `<space>__<page>[-<pid8>].md` angefasst - fremde `*.md` im `--out` bleiben
  erhalten; aggressives Loeschen ALLER nicht im Manifest stehenden `*.md`
  erfordert explizites `--prune`, `--no-prune` deaktiviert das Pruning ganz.
- Atomar/idempotent: Manifest und Export-Dateien werden im Zielverzeichnis
  zwischengeschrieben und per `mv` (gleiches Dateisystem) umbenannt; erst
  schreiben, wenn sich der Inhalt geaendert hat (N4).
- Exit 0 = vollstaendiger Export, 1 = Fehler (unvollstaendig).

    teamctl wiki export [--out DIR] [--space <spaceId>] [--dry-run] [--prune|--no-prune] [--quiet]

| Option | Bedeutung |
| --- | --- |
| `--out DIR` | Zielverzeichnis (Default: `WIKI_EXPORT_DIR`, sonst `~/.openclaw/wiki`) |
| `--space <spaceId>` | nur diesen Space exportieren (andere Spaces bleiben unberuehrt) |
| `--dry-run` | nur zeigen, was sich aendern wuerde (keine Schreibzugriffe) |
| `--prune` | aggressives Pruning: ALLE nicht im Manifest stehenden `*.md` entfernen (Opt-in) |
| `--no-prune` | gar kein Pruning: im Wiki geloeschte Dateien im Ziel belassen |
| `--quiet` | Fortschrittsausgabe unterdruecken (Fehler bleiben sichtbar) |

| Variable | Default | Bedeutung |
| --- | --- | --- |
| `WIKI_EXPORT_DIR` | `~/.openclaw/wiki` | Zielverzeichnis, wenn `--out` fehlt |
| `TEAMCTL_WIKI_EXPORT_SLEEP` | `0.2` | Pause zwischen API-Aufrufen (429-Schutz), Sekunden |

Ist das Default-Ziel nicht beschreibbar, `WIKI_EXPORT_DIR` in `teamctl.env` auf
einen beschreibbaren Pfad setzen. Derselbe Pfad muss in der
OpenClaw-Konfiguration unter `memory.search.extraPaths` stehen.


## Wiki-Suche mit Volltext: `teamctl wiki search`

`teamctl wiki search "<begriff>"` sucht seit Issue #20 standardmaessig im
**Volltext** - Titel, Body und Tags-Zeile. Damit findet die Suche auch Seiten,
die den Begriff nur im Inhalt (z. B. in einer Tags-Zeile) tragen; frueher wurde
ausschliesslich der Titel durchsucht.

    teamctl wiki search <begriff> [--title|--full] [--export-dir DIR]

- Suchquelle ist der lokale Markdown-Export (`WIKI_EXPORT_DIR`, sonst
  `~/.openclaw/wiki`), den `teamctl wiki export` pflegt. Die Suche laeuft
  **lokal** und ohne Netzwerkzugriff; der Index ist das Manifest
  (`.wiki-sync-manifest.tsv`, bei fehlendem Manifest die YAML-Kopfzeilen).
- Ausgabe je Treffer TAB-getrennt `spaceSlug<TAB>pageId<TAB>title`, nach Titel
  sortiert; mit der `pageId` laesst sich die Seite per `teamctl wiki get` lesen.
- Fehlt der Export (Verzeichnis fehlt/leer), folgt ein Hinweis auf stderr und
  die **titelbasierte API-Suche** als Fallback.
- Ist der Export aelter als `TEAMCTL_WIKI_SEARCH_MAX_AGE` Stunden (Default 24),
  warnt `teamctl` auf stderr - die Suche laeuft trotzdem auf dem Export weiter.

| Option | Bedeutung |
| --- | --- |
| `--full` | Volltextsuche ueber den Export erzwingen (Default) |
| `--title` | nur den Titel ueber die Docmost-API suchen (ohne Export) |
| `--export-dir DIR` | anderes Exportverzeichnis (sonst `WIKI_EXPORT_DIR`) |

| Variable | Default | Bedeutung |
| --- | --- | --- |
| `TEAMCTL_WIKI_SEARCH_MAX_AGE` | `24` | Stunden, ab denen der Export als veraltet gilt |

## Wiki-Seite umhaengen: `teamctl wiki update --parent`

`--parent <pageId>` haengt eine **bestehende** Seite unter die Ziel-Seite um;
`--parent ''` loest sie vom Parent und setzt sie auf Root-Ebene (Issue #22).

    teamctl wiki update <pageId> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> --parent ''

- `wiki create --parent` setzt den Parent beim Anlegen; `wiki update --parent`
  haengt danach um. Beides laeuft ueber die Docmost-API.
- Docmost ignoriert `parentPageId` in `POST /api/pages/update` (Issue #22). Das
  Umhaengen laeuft deshalb ueber `POST /api/pages/move` mit
  `{pageId, parentPageId, position}`; `position` ist PFLICHT (5-12 Zeichen,
  fractional index).
- Die Seite landet am **Ende** der Ziel-Elternliste. Die Position wird aus der
  groessten Nachbarposition gebildet (`position + 'V'`; leere Liste: `a0VVV`),
  ohne die Seite selbst. Ist die Nachbarposition bereits 12 Zeichen lang, bricht
  `teamctl` mit klarer Meldung ab (keine ungueltige Position).
- **Read-back:** Danach liest `teamctl` die Seite per `pages/info` und prueft
  `parentPageId` gegen das Ziel; bei Abweichung folgt eine Meldung und Exit != 0.
  So faellt ein stilles Ignorieren des Umhaengens sofort auf.
- Der Inhalt wird wie bisher per `pages/update` geschrieben; `--parent` steht
  nur beim Umhaengen. Ohne `--parent` aendert `wiki update` den Parent nicht.

## Read-back-Verifikation: `wiki create` / `wiki update`

Jeder Schreibvorgang wird anschliessend per `pages/info` gegen den Soll-Zustand
geprueft; bei Abweichung folgt eine Meldung und **Exit != 0**.

- **Titel** (nur `create`): der zurueckgelesene Titel muss dem `--title` entsprechen.
- **parentPageId** (`create --parent` und `update --parent`): die zurueckgelesene
  Eltern-Zuordnung muss dem Ziel entsprechen (`--parent ''` = Root/null). Damit
  faellt ein stilles Ignorieren sofort auf (Issue #22 und die gleiche blinde
  Stelle beim Anlegen).
- **Inhalt** (vollstaendig/normalisiert): **alle** Wort-Token der lokalen Datei
  muessen in der gespeicherten Markdown-Fassung vorkommen (Multimenge,
  Reihenfolge egal) - nicht nur ein zufaelliges Einzel-Token. Der Vergleich
  normalisiert bewusst die Markdown-Umserialisierung des Wikis (Zeilenenden,
  Einrueckung, Tabellen-Ausrichtung, `*x*` vs. `_x_`), prueft aber den gesamten
  Inhalt. Fehlt ein Token, wird wegen Eventual Consistency bis zu 4-mal
  wiederholt (Pausen 1s/2s/3s) und dann mit knapper Meldung (Anzahl + Beispiele)
  abgebrochen.
- **Leerer Inhalt = Fehler:** enthaelt die Datei kein pruefbares Wort-Token
  (leer oder nur Satzzeichen), bricht der Read-back mit klarer Meldung ab statt
  die Verifikation still zu ueberspringen.

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
  Wiki-curl-Aufrufe das Serverzertifikat ueber `--cacert`; `-k` wird in
  diesem Fall NICHT gesetzt (H2: frueher entwertete ein globales `-k` das
  `--cacert`). Fehlt die Datei, ist sie leer oder nicht lesbar, bricht
  `teamctl` ab; die Meldung nennt nur den Schluesselnamen, nie den Pfad oder
  Zertifikatsinhalt.
- Ohne `TEAMCTL_WIKI_CA` laufen Wiki-Aufrufe mit `-k` (TLS-Verifikation AUS).
  Das ist nur fuer die selbstsignierte Infrastruktur noetig; fuer ein
  verifiziertes bzw. selbstsigniertes Wiki mit bekannter CA den Schluessel
  setzen. `-k` steht bewusst nur in diesem Fall (WIKI_CURL_OPTS), nie global.
- `--as`/`TEAMCTL_WIKI_AS` wird per Whitelist validiert (nur Buchstaben,
  Ziffern, `. _ @ + -` und Leerzeichen); Shell-Metazeichen werden abgelehnt.
  In ssh-awk-Aufrufen wird der Wert zusaetzlich remote single-quoted
  (`shq`), kann also nie aus dem Quoting ausbrechen (H1: Command-Injection).
- `teamctl wiki export` entfernt per Default nur Dateien, die dem Export-Schema
  `<space>__<page>[-<pid8>].md` entsprechen; fremde `*.md` im `--out` bleiben
  erhalten. Aggressives Loeschen ALLER nicht im Manifest stehenden `*.md` nur
  mit explizitem `--prune` (M1).
- Die Konfigurationsdatei wird nur geladen, wenn sie sicher ist: regulaere Datei
  (kein Symlink), Eigentuemer = aktueller Nutzer/root, kein Gruppen-/Welt-
  Schreibrecht (N5). Sonst Abbruch ohne Ausfuehrung.
- `git`-Pfade werden segmentweise geprueft (N2): abgelehnt werden absolute
  Pfade, End-Slash, leere Segmente (`a//b`) und jedes `.`/`..`-Segment
  (auch `a/../b`), damit keine Traversal-API-Pfade entstehen.
- `blog publish`/`blog link` erzeugen ihre remote Tempdateien mit `mktemp`
  (N1: keine vorhersagbaren `/tmp/teamctl_*_$$`-Namen) und verifizieren
  `blog publish` ueber den `sha256`-Hash der ausgelieferten Datei (N3), nicht
  nur ueber die Byte-Anzahl. `blog link` verifiziert die Link-Anzahl in
  `index.html`. `blog publish` haengt den Post zusaetzlich standardmaessig in
  die Indexseite ein (Auto-Link) und prueft den Eintrag per Read-back;
  `--no-link` ueberspringt das mit deutlichem Warnhinweis, `--link` erzwingt es
  explizit. Ohne Titel (weder `--title` noch `<title>` in der Datei) bricht
  `blog publish` nach dem Upload mit klarer Meldung + `blog link`-Hinweis ab.
- `blog unpublish` loescht `posts/<slug>.html` nur nach Bestaetigung
  (nicht-interaktiv `--yes`) und nur mit gueltigem Slug (Whitelist, kein `.`/`..`);
  der Zielpfad wird zwingend als `<BLOG_DIR>/posts/<slug>.html` gebildet und
  gegen die `posts/`-Whitelist geprueft, danach Read-back (Datei muss weg sein).
  `blog unlink` entfernt den `<li>`-Eintrag idempotent `index.html` und
  verifiziert per Read-back, dass die Link-Anzahl genau sinkt und der Slug weg
  ist.
- `wiki export` legt Manifest- und Datei-Temp im Zielverzeichnis an, damit das
  abschliessende `mv` innerhalb desselben Dateisystems atomar bleibt (N4);
  Manifest-Felder werden von echten Tabs/CR/LF befreit (`wex_tsv`), damit die
  spaltige `.wiki-sync-manifest.tsv` nicht zerstoert wird.

## Selbsttest (Regressions-Guard)

`tests/selftest.sh` prueft Syntax, das dateiweite Fehlen jeglicher
Shell-Auswertung (`eval`) im Kommandokontext, die Ablehnung von Metazeichen in
`TEAMCTL_GITHUB_TOKEN_CMD` sowie die Haertungen N1-N6 (Config-Rechte/-Owner,
Segment-Traversal, remote `mktemp` + `sha256`-Verifikation beim Blog-Publish,
Body-only-Erstellerkennung, atomarer Wiki-Export). Zusaetzlich deckt er die
Blog-Auto-Link-Logik von `blog publish` hermetisch ab (SSH-/SCP-Stubs, kein
Netz): Default laedt hoch und haengt ein, `--no-link` ueberspringt
(Warnhinweis), `--title` schlaegt den Datei-`<title>`; fehlender Titel =
Read-back-Fehler mit `blog link`-Hinweis, `blog link` bleibt idempotent.
Ebenso abgedeckt: `blog unpublish` (ohne `--yes` keine Loeschung,
Slug-Whitelist, fehlende Datei = Fehler, `--yes` entfernt + Read-back) und
`blog unlink` (genau ein Eintrag weg, andere bleiben, idempotent per SKIP):

```bash
bash tests/selftest.sh
```

Exit 0 = alle Tests PASS, Exit != 0 = mindestens ein FAIL. Der Test laeuft ohne
Secrets und ohne Infrastruktur (Dummy-Konfiguration mit `.invalid`-Werten und
curl-Stub). Ein optionaler Live-Positivtest (`teamctl git repos`, Exit 0) ist
mit `TEAMCTL_SELFTEST_LIVE=1` aktivierbar.

## Lizenz

MIT - siehe `LICENSE`.
