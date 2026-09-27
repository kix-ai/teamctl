# teamctl

Gemeinsames internes CLI fuer **Wiki (Docmost)**, **Blog (statische Seite)** und
**Git (GitHub)**. Kurze Befehle, damit Agents Token sparen. Es gibt keine Secrets aus.

## Ablage

- Skript:        `teamctl` (ausfuehrbar)
- Hilfe:         `teamctl help` (oder `teamctl wiki|blog|git --help`)
- Konfiguration: `teamctl.env` neben dem Skript (chmod 600, NICHT in Git)
- Vorlage:       `.env.example`

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

## Konfiguration

Infrastruktur-Werte (Host, URL, Owner, API) stehen NICHT im Skript, sondern in
einer vertraulichen Konfigurationsdatei. teamctl laedt sie automatisch
(Standard: `teamctl.env` im Skript-Verzeichnis); der Pfad ist per
`TEAMCTL_ENV_FILE` aenderbar. Echte Umgebungsvariablen haben Vorrang vor der Datei.

Pflichtwerte (siehe `.env.example`):

    TEAMCTL_INFRA_HOST   SSH-Ziel des Infra-Hosts (user@host)
    TEAMCTL_WIKI_URL     Docmost-Basis-URL
    TEAMCTL_WIKI_EMAIL   Standard-Wiki-Konto
    TEAMCTL_BLOG_ROOT    Blog-Verzeichnis auf dem Host
    TEAMCTL_GIT_OWNER    GitHub-Owner
    TEAMCTL_GIT_API      GitHub-API-Basis-URL

Optional (generische Vorgaben im Skript):

    TEAMCTL_SSH_KEY            Pfad zum SSH-Key
    TEAMCTL_WIKI_CREDS         Pfad zur Credential-Datei auf dem Host
    TEAMCTL_WIKI_AS            Standard-Wiki-Konto (Default: TEAMCTL_WIKI_EMAIL)
    TEAMCTL_GITHUB_TOKEN_CMD   Befehl, der das Token liefert

Fehlt Konfiguration, bricht teamctl mit einer klaren Fehlermeldung und Verweis
auf die Konfigurationsdatei ab.

## Ausgabe / Fehler

- Ausgabe ist knapp und maschinenlesbar (TAB-getrennt), z.B.
  wiki spaces:    <id> <TAB> <slug> <TAB> <name>
  wiki pages:     <id> <TAB> <titel>   (verschachtelt eingerueckt)
  wiki create:    <pageId>
  wiki upload:    <url>
  blog publish:   OK <TAB> /posts/<slug>.html <TAB> <bytes>
  git upload:     OK <TAB> <owner/repo> <TAB> <pfad> <TAB> <sha>
- Hinweis-/Statuszeilen gehen auf stderr, Daten auf stdout.
- Bei Fehler: Klartext + HTTP-Code, Exit-Code != 0.
- Alle Schreibbefehle machen einen Read-back (Verifikation) und schlagen
  fehl, wenn das Ergebnis nicht bestaetigt werden kann.

## Sicherheit

- Passwoerter werden nur auf dem Host aus der Credential-Datei gelesen
  und nie ausgegeben oder in Dateien geschrieben.
- Git-/SSH-Token werden nur zur Laufzeit in Variablen gehalten.
- `teamctl.env` ist vertraulich: chmod 600 und nicht im Git-Repository.
- Slugs werden auf [A-Za-z0-9._-] beschraenkt (keine Pfad-Traversal).
