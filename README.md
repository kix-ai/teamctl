# teamctl (lokale Installation)

Gemeinsames internes CLI fuer **Wiki (Docmost)**, **Blog (statische Seite)** und
**Git (GitHub)**. Kurze Befehle, damit Agents Token sparen. Es gibt keine Secrets aus.

## Ablage (dieser Host)

- Skript:        `<install-dir>/teamctl` (ausfuehrbar)
- Konfiguration: `<install-dir>/teamctl.env` (chmod 600,
                 NICHT in Git und NICHT in der Wiki-Doku)
- Vorlage:       `<install-dir>/.env.example`
                 (nur Schluessel/Platzhalter, keine Werte)
- SSH-Key (600): `<install-dir>/.ssh/id_ed25519`
- Hilfe:         `teamctl help` (oder `teamctl wiki|blog|git --help`)
- PATH-Aufruf:   `teamctl ...` ohne vollen Pfad via Symlink in einem
                 PATH-Verzeichnis (z. B. `~/.local/bin/teamctl`, s. u.)

## Aufruf ohne vollen Pfad (PATH)

`teamctl` ist zusaetzlich als **Symlink in einem PATH-Verzeichnis** hinterlegt,
damit kurze Aufrufe wie `teamctl wiki spaces` ohne vollen Pfad funktionieren:

- kanonisch:   `~/.local/bin/teamctl`  (hier: `~/.local/bin/teamctl`)
- zusaetzlich: `~/bin/teamctl`         (Fallback fuer Setups mit `~/bin` im PATH)

Der Symlink zeigt auf `<install-dir>/teamctl`. Das Skript
loest seinen eigenen Pfad auch ueber Symlinks hinweg auf und findet seine
`teamctl.env` daher weiterhin im Verzeichnis des echten Skripts.

Hinweis (nicht-interaktive Shells, z. B. `bash -c` oder Cron): dort gilt der PATH
der aufrufenden Umgebung. Ist `~/.local/bin` nicht enthalten, entweder den PATH
ergaenzen (`export PATH="$HOME/.local/bin:$PATH"`) oder als robuste Rueckfall-
loesung den vollen Pfad `<install-dir>/teamctl` nutzen.

## Nutzung

WIKI (Docmost)
    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend]
    teamctl wiki upload <pageId> <bilddatei>
    (optional ueberall: --as <email|name>)

BLOG (statische Seite auf dem Infra-Host)
    teamctl blog list
    teamctl blog publish --file <html> --slug <slug>
    teamctl blog link --title <T> --slug <slug>

GIT (GitHub, Konto per Token)
    teamctl git info <repo>
    teamctl git list <repo> [dir]
    teamctl git create-repo <name> [--public]     # Standard: privat
    teamctl git upload <repo> <pfad> <lokale-datei> [--message <m>]
    teamctl git issue <repo> --title <T> (--body <B> | --file <md>) [--label <l>]
    teamctl git issue-close <repo> <nummer>
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]

`git issue` legt Issues (z. B. Feature-Requests/Wuensche) an; `--label` akzeptiert
Labels, mehrere kommagetrennt. `git issue-close` schliesst ein Issue wieder
(`state=closed`). `git issues` listet Issues (Standard `--state open`) TAB-getrennt.
(`state=closed`). Beide lesen Owner/API/Token aus der Konfiguration (keine Werte hier).
`git issues-all` listet Issues ueber ALLE sichtbaren Repos in einem Aufruf
(Standard `--state open`); Pull Requests werden uebersprungen.

## Konfiguration

Infrastruktur-Werte (Host, URL, Owner, API) stehen NICHT im Skript und NICHT in
dieser Doku, sondern ausschliesslich in der vertraulichen Datei `teamctl.env`
(chmod 600, nicht in Git). teamctl laedt die Datei automatisch; der Pfad ist per
`TEAMCTL_ENV_FILE` aenderbar. Echte Umgebungsvariablen haben Vorrang vor der Datei.

Werte-Vorlage: `.env.example` im selben Verzeichnis (nur Schluessel und
Platzhalter - zum Befuellen von `teamctl.env` kopieren).

Pflichtwerte: TEAMCTL_INFRA_HOST, TEAMCTL_WIKI_URL, TEAMCTL_WIKI_EMAIL,
TEAMCTL_BLOG_ROOT, TEAMCTL_GIT_OWNER, TEAMCTL_GIT_API.
Optional: TEAMCTL_SSH_KEY, TEAMCTL_WIKI_CREDS, TEAMCTL_WIKI_AS,
TEAMCTL_GITHUB_TOKEN_CMD, TEAMCTL_RETRY_MAX, TEAMCTL_RETRY_BASE, TEAMCTL_RETRY_CAP.

Fehlt Konfiguration, bricht teamctl mit einer klaren Fehlermeldung und Verweis
auf die Konfigurationsdatei ab.

## Ausgabe / Fehler

- Ausgabe ist knapp und maschinenlesbar (TAB-getrennt).
- Hinweis-/Statuszeilen gehen auf stderr, Daten auf stdout.
- Bei Fehler: Klartext + HTTP-Code, Exit-Code != 0.
- Bei HTTP 429 (Too Many Requests) wiederholt teamctl Wiki-Aufrufe automatisch:
  begrenzte Anzahl Versuche, exponentielles Backoff mit Zufallsanteil (Jitter),
  `Retry-After`-Header wird beachtet; jede Wiederholung wird auf stderr gemeldet.
  Steuerung: `TEAMCTL_RETRY_MAX` (Default 4), `TEAMCTL_RETRY_BASE` (Default 2),
  `TEAMCTL_RETRY_CAP` (Default 30). Nach erschoepften Versuchen klarer Abbruch.
- Alle Schreibbefehle machen einen Read-back (Verifikation) und schlagen
  fehl, wenn das Ergebnis nicht bestaetigt werden kann.

## Sicherheit

- Passwoerter werden nur auf dem Host aus der Credential-Datei gelesen
  und nie ausgegeben oder in Dateien geschrieben.
- Git-/SSH-Token werden nur zur Laufzeit in Variablen gehalten.
- `teamctl.env` ist vertraulich: chmod 600 und nicht im Git-Repository.
- Slugs werden auf [A-Za-z0-9._-] beschraenkt (keine Pfad-Traversal).
