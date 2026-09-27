# teamctl - Usage

Kurzanleitung fuer das interne Kommandozeilen-Tool **teamctl**
(Wiki / Docmost, Team-Blog, GitHub).

Vollstaendige Beschreibung: README.md im Repository.

## Kommandos im Ueberblick

WIKI (Docmost)
    teamctl wiki spaces
    teamctl wiki pages <spaceId>
    teamctl wiki get <pageId>
    teamctl wiki create --space <spaceId> --title <T> --file <md> [--parent <pageId>]
    teamctl wiki update <pageId> --file <md> [--mode replace|append|prepend]
    teamctl wiki upload <pageId> <bilddatei>

BLOG (statische Seite auf dem Infra-Host)
    teamctl blog list
    teamctl blog publish --file <html> --slug <slug>
    teamctl blog link --title <T> --slug <slug>

GIT (GitHub; Standard privat)
    teamctl git info <repo>
    teamctl git list <repo> [dir]
    teamctl git create-repo <name> [--public]
    teamctl git upload <repo> <pfad> <lokale-datei> [--message <m>]

## Konventionen

- Datenausgabe: TAB-getrennt, maschinenlesbar. Status-/Hinweiszeilen auf stderr.
- Jeder Schreibbefehl prueft das Ergebnis per Read-back und bricht bei
  Abweichung ab (Exit-Code != 0).
- Keine Secrets in Ausgaben; Token/Passwoerter werden nur zur Laufzeit gelesen.

## Konfiguration

Alle Werte kommen aus `teamctl.env` (chmod 600, nicht in Git); Vorlage ist
`.env.example`. Echte Umgebungsvariablen haben Vorrang vor der Datei.
Der Pfad ist per `TEAMCTL_ENV_FILE` aenderbar.

Pflichtwerte: TEAMCTL_INFRA_HOST, TEAMCTL_WIKI_URL, TEAMCTL_WIKI_EMAIL,
TEAMCTL_BLOG_ROOT, TEAMCTL_GIT_OWNER, TEAMCTL_GIT_API.

Optional: TEAMCTL_SSH_KEY, TEAMCTL_WIKI_CREDS, TEAMCTL_WIKI_AS,
TEAMCTL_GITHUB_TOKEN_CMD.

Fehlt Konfiguration, bricht teamctl mit einer klaren Fehlermeldung und Verweis
auf die Konfigurationsdatei ab.
