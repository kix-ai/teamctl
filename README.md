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
| `TEAMCTL_GITHUB_TOKEN_CMD` | `gh auth token` | Befehl, der den GitHub-Token auf stdout liefert |
| `TEAMCTL_RETRY_MAX` | `4` | Wiederholungen bei HTTP 429 |
| `TEAMCTL_RETRY_BASE` | `2` | Basis-Sekunden fuer das Backoff |
| `TEAMCTL_RETRY_CAP` | `30` | Obergrenze der Wartezeit je Versuch (Sekunden) |

## Beispiele

WIKI (Docmost)

    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki search <begriff>
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend]
    teamctl wiki upload <pageId> <bilddatei>
    (optional ueberall: --as <email|name>)

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
    teamctl git issue-close <repo> <nummer>
    teamctl git issues <repo> [--state open|closed|all] [--label <l>]
    teamctl git issues-all [--state open|closed|all] [--label <l>]

`teamctl help` zeigt die Kurzuebersicht, `teamctl wiki|blog|git --help`
die jeweiligen Unterbefehle.

## Ausgabe und Fehler

- Daten auf stdout, Hinweis-/Statuszeilen auf stderr, TAB-getrennt.
- Bei Fehlern Klartext, HTTP-Code und Exit-Code ungleich 0.
- Bei HTTP 429 wiederholt `teamctl` Wiki-Aufrufe automatisch (begrenztes
  Backoff mit Jitter, `Retry-After` wird beachtet).
- Alle Schreibbefehle machen einen Read-back und schlagen fehl, wenn das Ergebnis
  nicht bestaetigt werden kann.

## Sicherheit

- Zugangsdaten und Tokens werden nur zur Laufzeit gelesen und nie ausgegeben.
- `teamctl.env` bleibt lokal (chmod 600, per `.gitignore` ausgeschlossen).
- Git- und SSH-Token werden nur intern als HTTP-Header uebergeben - nie in URL,
  Kommandozeile oder Ausgabe - und nicht im geklonten Repo gespeichert.
- Slugs werden auf `[A-Za-z0-9._-]` beschraenkt (kein Pfad-Traversal).
- Endpoint-Werte (`TEAMCTL_WIKI_URL`, `TEAMCTL_GIT_API`) werden auf das Schema
  `https://` beschraenkt; Klartext-HTTP und fehlendes Schema werden abgelehnt.

## Lizenz

MIT - siehe `LICENSE`.
