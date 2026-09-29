# teamctl - Usage

Kurzanleitung fuer **teamctl** (Wiki/Docmost, Blog, GitHub).
Vollstaendige Beschreibung und Konfiguration: `README.md`.

## Kommandos im Ueberblick

WIKI (Docmost)

    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki search <begriff> [--title|--full] [--export-dir DIR]
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend] [--parent <pageId>|--parent '']
    teamctl wiki upload <pageId> <bilddatei>
    teamctl wiki export [--out DIR] [--space <spaceId>] [--dry-run] [--prune|--no-prune] [--quiet]
    teamctl wiki me
    teamctl wiki profile --name <name>

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
     (interaktiv Rueckfrage, nicht-interaktiv --yes) und nur unter posts/,
     mit Read-back; unlink haengt den <li>-Eintrag aus index.html aus -
     idempotent, mit Read-back ueber die Link-Anzahl)

GIT (GitHub, Token aus der Konfiguration)

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
    teamctl git issue <repo|owner/repo> --title <T> (--body <B> | --file <md>) [--label <l>]
    teamctl git issue-close <repo|owner/repo> <nummer>
    teamctl git issue-comment <repo|owner/repo> <nummer> (--body <B> | --file <md>)
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]
    teamctl git pulls <repo> [--state open|closed|all] [--label <l>]
    teamctl git pulls-all [--state open|closed|all] [--label <l>]

DOCTOR (Selbstdiagnose, read-only)

    teamctl doctor

## Wiki-Export: `teamctl wiki export`

Exportiert alle Docmost-Seiten (oder mit `--space <spaceId>` nur einen Space)
als Markdown: eine Datei je Seite `<space-slug>__<page-slug>.md` mit
YAML-Kopfzeile (`title`, `space`, `spaceId`, `pageId`).

    teamctl wiki export [--out DIR] [--space <spaceId>] [--dry-run] [--prune|--no-prune] [--quiet]

- Default-Ziel: `WIKI_EXPORT_DIR`, sonst `~/.openclaw/wiki`.
- Idempotent ueber ein Manifest (`.wiki-sync-manifest.tsv`); im Wiki geloeschte
  Export-Dateien entfernt das Pruning. Per Default nur Dateien im Export-Schema
  `<space>__<page>[-<pid8>].md` (fremde `*.md` im Ziel bleiben erhalten);
  aggressiv ALLE nicht im Manifest stehenden `*.md` nur mit `--prune`;
  `--no-prune` deaktiviert das Pruning ganz.
- `--dry-run` zeigt nur die Aenderungen, `--quiet` unterdrueckt den Fortschritt.
- Zugangsdaten kommen aus der teamctl-Konfiguration (`TEAMCTL_WIKI_*`) und
  werden nie ausgegeben oder in die Export-Dateien geschrieben.
- Exit 0 = vollstaendig, 1 = Fehler.

## Wiki-Suche: Volltext: `teamctl wiki search`

`teamctl wiki search "<begriff>"` sucht standardmaessig im **Volltext**:
Titel, Body und Tags-Zeile - also auch Begriffe, die nur im Inhalt stehen.

    teamctl wiki search <begriff> [--title|--full] [--export-dir DIR]

- Suchquelle ist der lokale Markdown-Export (`WIKI_EXPORT_DIR`, sonst
  `~/.openclaw/wiki`), den `teamctl wiki export` pflegt - ohne Netzwerkzugriff.
- Ausgabe je Treffer: `spaceSlug`, `pageId` und `title` (TAB-getrennt, nach
  Titel sortiert). `pageId` ermoeglicht `teamctl wiki get <pageId>`.
- Faellt der Export weg (fehlt/leer), folgt ein Hinweis auf stderr und die
  titelbasierte API-Suche als Fallback.
- Ist der Export aelter als `TEAMCTL_WIKI_SEARCH_MAX_AGE` Stunden (Default 24),
  warnt teamctl auf stderr; die Suche laeuft weiter auf dem Export.
- `--title` sucht nur Titel ueber die API, `--full` erzwingt die Volltextsuche,
  `--export-dir DIR` waehlt ein anderes Exportverzeichnis.

## Wiki umhaengen: `teamctl wiki update --parent`

`--parent <pageId>` haengt eine bestehende Seite unter die Ziel-Seite um,
`--parent ''` loest sie vom Parent (Root-Ebene).

    teamctl wiki update <pageId> --file <md> --parent <pageId>
    teamctl wiki update <pageId> --file <md> --parent ''

- Umhaengen laeuft ueber `POST /api/pages/move` (`{pageId, parentPageId,
  position}`), weil Docmost `parentPageId` in `pages/update` ignoriert (#22).
  `position` ist Pflicht (5-12 Zeichen fractional index); die Seite landet am
  Ende der Ziel-Elternliste (Nachbarposition + `V`, leere Liste `a0VVV`).
- Read-back per `pages/info`: `parentPageId` muss dem Ziel entsprechen, sonst
  Fehler und Exit != 0. Ohne `--parent` bleibt der Parent unveraendert.

## Wiki verifizieren: `wiki create` / `wiki update`

Jeder Schreibvorgang prueft den Read-back (`pages/info`); bei Abweichung:
Meldung + Exit != 0.

- **Titel** (`create`): muss dem `--title` entsprechen.
- **parentPageId** (`create --parent`, `update --parent`): muss dem Ziel
  entsprechen (`--parent ''` = Root/null).
- **Inhalt** (vollstaendig/normalisiert): ALLE Wort-Token der Datei muessen in
  der gespeicherten Markdown-Fassung vorkommen (Multimenge; Reihenfolge egal).
  Die Markdown-Umserialisierung des Wikis (Zeilenenden, Einrueckung,
  Tabellen-Ausrichtung, `*x*` vs. `_x_`) wird toleriert - geprueft wird der
  gesamte Inhalt, nicht ein zufaelliges Einzel-Token. Fehlt ein Token, folgen
  bis zu 4 Versuche (Pausen 1s/2s/3s) wegen Eventual Consistency.
- **Leerer Inhalt = Fehler**: kein pruefbares Wort-Token (leer/nur Satzzeichen)
  -> Abbruch statt stiller Ueberspringung.

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
- Issues: Titel als normaler Kurztitel **ohne Praefix**; die Agent-Kennung steht
  **nur im Body** (`Ersteller: <agent-id>` + `Datum: <YYYY-MM-DD>`). `git issue`
  warnt (Exit 0) bei fehlender Body-Kennung; `--require-author` bricht ab,
  `--author <agent-id>` setzt die Kennung im Body.
- `git read`/`git cat` liefern Dateiinhalte ueber die GitHub-Contents-API.
- `git upload` erhaelt das Executable-Bit: ausfuehrbare lokale Dateien (mode +x)
  gehen ueber die Git-Data-API (mode 100755, blob -> tree -> commit -> ref),
  sonst Contents-API (mode 100644). `--exec`/`--no-exec` erzwingen den Mode.
  Grund: die Contents-API speichert regulaere Dateien immer als 100644.
- `git clone`/`git pull` uebergeben den Token intern als HTTP-Header (nie in URL,
  Kommandozeile oder Ausgabe) und speichern ihn nicht im geklonten Repo.

## Konfiguration

Alle Werte kommen aus `teamctl.env` (chmod 600, nicht in Git); Vorlage ist
`.env.example`. Echte Umgebungsvariablen haben Vorrang, der Pfad ist per
`TEAMCTL_ENV_FILE` aenderbar.

Die Datei wird nur geladen, wenn sie sicher ist (regulaere Datei, kein Symlink,
Eigentuemer = aktueller Nutzer/root, kein Gruppen-/Welt-Schreibrecht) - sonst
bricht `teamctl` ab, ohne sie auszufuehren.

Pflichtwerte: TEAMCTL_INFRA_HOST, TEAMCTL_WIKI_URL, TEAMCTL_WIKI_EMAIL,
TEAMCTL_BLOG_ROOT, TEAMCTL_GIT_OWNER, TEAMCTL_GIT_API.

Optional: TEAMCTL_SSH_KEY, TEAMCTL_WIKI_CREDS, TEAMCTL_WIKI_AS,
TEAMCTL_GITHUB_TOKEN_CMD.

Retry/Backoff fuer Wiki-Aufrufe bei HTTP 429:
TEAMCTL_RETRY_MAX, TEAMCTL_RETRY_BASE, TEAMCTL_RETRY_CAP.

TLS fuer das Wiki: TEAMCTL_WIKI_CA (Pfad zum CA-/Leaf-Zertifikat).
Der Zustand wird beim Start geprueft; fehlt/leer/unlesbar/kein PEM -> sofortiger
Abbruch mit klarer Meldung. Gesetzt: Wiki-Aufrufe verifizieren ueber `--cacert`
(kein `-k`). Ohne den Wert laufen Wiki-Aufrufe mit `-k` (TLS-Verifikation AUS,
nur fuer die selbstsignierte Infrastruktur).

`--as`/`TEAMCTL_WIKI_AS` wird per Whitelist validiert (Buchstaben, Ziffern,
`. _ @ + -`, Leerzeichen); in ssh-Aufrufen wird der Wert remote single-quoted.
