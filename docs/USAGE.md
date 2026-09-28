# teamctl - Usage

Kurzanleitung fuer **teamctl** (Wiki/Docmost, Blog, GitHub).
Vollstaendige Beschreibung und Konfiguration: `README.md`.

## Kommandos im Ueberblick

WIKI (Docmost)

    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki search <begriff>
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend]
    teamctl wiki upload <pageId> <bilddatei>
    teamctl wiki me
    teamctl wiki profile --name <name>

BLOG (statische Seite auf dem Host)

    teamctl blog list
    teamctl blog publish --file <html> --slug <slug>
    teamctl blog link --title <T> --slug <slug>

GIT (GitHub, Token aus der Konfiguration)

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
    teamctl git issue <repo|owner/repo> --title <T> (--body <B> | --file <md>) [--label <l>]
    teamctl git issue-close <repo|owner/repo> <nummer>
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]
    teamctl git pulls <repo> [--state open|closed|all] [--label <l>]
    teamctl git pulls-all [--state open|closed|all] [--label <l>]

DOCTOR (Selbstdiagnose, read-only)

    teamctl doctor

## Konventionen

- Datenausgabe TAB-getrennt und maschinenlesbar; Statuszeilen auf stderr.
- `teamctl doctor` prueft nur (read-only) und gibt je Pruefung eine Zeile
  `<pruefung>\t<OK|WARN|FAIL>\t<detail>` aus; Exit 0 ohne FAIL (WARN allein -> 0),
  1 bei mindestens einem FAIL. Details nennen nur Schluesselnamen/Status/HTTP-Codes.
  Der Befehl laeuft vor der Pflichtwert-Pruefung: eine unvollstaendige
  Konfiguration wird als `config FAIL` gemeldet statt abzubrechen.
- Jeder Schreibbefehl prueft das Ergebnis per Read-back und bricht bei
  Abweichung ab (Exit-Code ungleich 0).
- Keine Secrets in Ausgaben; Token und Passwoerter werden nur zur Laufzeit gelesen.
- `git read`/`git cat` liefern Dateiinhalte ueber die GitHub-Contents-API.
- `git clone`/`git pull` uebergeben den Token intern als HTTP-Header (nie in URL,
  Kommandozeile oder Ausgabe) und speichern ihn nicht im geklonten Repo.

## Konfiguration

Alle Werte kommen aus `teamctl.env` (chmod 600, nicht in Git); Vorlage ist
`.env.example`. Echte Umgebungsvariablen haben Vorrang, der Pfad ist per
`TEAMCTL_ENV_FILE` aenderbar.

Pflichtwerte: TEAMCTL_INFRA_HOST, TEAMCTL_WIKI_URL, TEAMCTL_WIKI_EMAIL,
TEAMCTL_BLOG_ROOT, TEAMCTL_GIT_OWNER, TEAMCTL_GIT_API.

Optional: TEAMCTL_SSH_KEY, TEAMCTL_WIKI_CREDS, TEAMCTL_WIKI_AS,
TEAMCTL_GITHUB_TOKEN_CMD.

Retry/Backoff fuer Wiki-Aufrufe bei HTTP 429:
TEAMCTL_RETRY_MAX, TEAMCTL_RETRY_BASE, TEAMCTL_RETRY_CAP.

TLS fuer das Wiki: TEAMCTL_WIKI_CA (Pfad zum CA-/Leaf-Zertifikat).
Der Zustand wird beim Start geprueft; fehlt/leer/unlesbar/kein PEM -> sofortiger
Abbruch mit klarer Meldung. Ohne den Wert gilt die System-CA.
