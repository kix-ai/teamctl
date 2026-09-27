#!/usr/bin/env bash
# tests/selftest.sh - Regressions-Guard fuer teamctl.
#
# Prueft die injektionssichere Aufloesung des GitHub-Tokens (git_token), das
# Fehlen jeglicher Shell-Auswertung (eval) und die Ablehnung von Metazeichen in
# TEAMCTL_GITHUB_TOKEN_CMD. Laeuft OHNE Secrets und OHNE Infrastruktur:
# alle Netzwerkaufrufe werden durch einen curl-Stub unterbunden, die
# Konfiguration besteht ausschliesslich aus Dummy-Werten (<irgendwas>.invalid).
#
# Aufruf:  bash tests/selftest.sh
# Exit:    0 = alle Tests PASS, != 0 = mindestens ein FAIL.
#
# Optionaler Live-Positivtest (braucht echte Konfiguration/Token):
#   TEAMCTL_SELFTEST_LIVE=1 bash tests/selftest.sh

set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -P "$HERE/.." && pwd)"
TEAMCTL="$ROOT/teamctl"

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

if [ ! -f "$TEAMCTL" ]; then
  printf 'FAIL: teamctl nicht gefunden: %s\n' "$TEAMCTL" >&2
  exit 1
fi

# --- 1) Syntax ---------------------------------------------------------------
if bash -n "$TEAMCTL" 2>/dev/null; then
  pass "Syntax: bash -n teamctl"
else
  fail "Syntax: bash -n teamctl"
fi

# --- 2) Guard: kein eval im Kommandokontext (dateiweit) ----------------------
# Jede Nicht-Kommentarzeile darf die Zeichenfolge 'eval' nicht enthalten -
# unabhaengig von Wortgrenzen. So werden auch ausgelagerte Helfer wie 'qeval',
# 'do_eval' oder 'myEval' erkannt, die ein Muster mit Wortgrenzen
# ([^A-Za-z0-9_]eval[^A-Za-z0-9_]) uebersieht. Kommentarzeilen (Zeilen, die mit
# optionalem Leerraum und '#' beginnen) sind erlaubt, weil sie dokumentieren,
# WARUM kein eval genutzt wird.
EVALHITS="$(awk '{ l=$0; sub(/^[[:space:]]*#.*/,"",l); if (l ~ /eval/) print NR": "$0 }' "$TEAMCTL")"
if [ -n "$EVALHITS" ]; then
  fail "Guard: kein eval im Kommandokontext (dateiweit)"
  printf '%s\n' "$EVALHITS" | sed 's/^/      /' >&2
else
  pass "Guard: kein eval im Kommandokontext (dateiweit)"
fi

# --- Hermetische Testumgebung: Dummy-Config + curl-Stub ---------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ENVF="$WORK/test.env"
cat > "$ENVF" <<'ENV'
TEAMCTL_INFRA_HOST=selftest.invalid
TEAMCTL_WIKI_URL=https://selftest.invalid
TEAMCTL_WIKI_EMAIL=selftest@selftest.invalid
TEAMCTL_BLOG_ROOT=/tmp/teamctl-selftest-blog
TEAMCTL_GIT_OWNER=selftest-owner
TEAMCTL_GIT_API=https://selftest.invalid/api
ENV

BIN="$WORK/bin"
mkdir -p "$BIN"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: verhindert jeden Netzwerkzugriff im Selbsttest.
exit 7
STUB
chmod +x "$BIN/curl"

# Eigener, zunaechst LEERER Marker-Ordner. Jede Negativnutzlast zeigt mit
# __MARK__ hierher; entsteht eine Datei, wurde der Wert von einer Shell
# ausgewertet (eval) bzw. der Wert wurde nicht abgelehnt.
MK="$WORK/mark"
mkdir -p "$MK"

run_teamctl() {
  PATH="$BIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_GITHUB_TOKEN_CMD="$1" \
    bash "$TEAMCTL" git repos 2>&1
}

# --- 3) Negativtests: Metazeichen/missbraeuchliche Werte werden abgelehnt ----
# Jeder Fall hat einen EIGENEN, explizit benannten Marker-Dateinamen (markers[]),
# der ueber __MARK__ in den Wert eingesetzt wird. Bei einer Shell-Auswertung
# (eval) legt die Nutzlast genau diese Datei an, und der Test MUSS das als
# Nebenwirkung melden. Der Marker-Pfad wird bewusst NICHT per Muster-Trimmen
# (z. B. ${p##*/}) gebildet: Trimmen liefert bei Nutzlasten mit ')' oder
# Backtick einen falschen Namen (z. B. 'subst)"') und macht die Pruefung blind.
names=(
  'Semikolon'        # ';'
  'Substitution'     # '$(...)'
  'Backtick'         # '`...`'
  'Pipe'             # '|'
  'Redirect'         # '>'
  'Tab'
  'Newline'
  'CarriageReturn'
  'Glob-Stern'       # '*'
  'Glob-Frage'       # '?'
  'Tilde'            # '~'
  'Brace-Expansion'  # '{a,b}'
  'IFS'              # '$IFS'
  'nur-Leerzeichen'
  'leer'
)
markers=(
  'semi' 'subst' 'bt' 'pipe' 'redir'
  'tab' 'newline' 'cr' 'star' 'quest' 'tilde' 'brace' 'ifs'
  '' ''
)
tpls=(
  'true; touch __MARK__/semi'
  'printf %s "$(touch __MARK__/subst)"'
  'printf %s "`touch __MARK__/bt`"'
  'printf x | tee __MARK__/pipe'
  'printf x > __MARK__/redir'
  $'touch\t__MARK__/tab'
  $'touch __MARK__/newline\ntrue'
  $'true\r; touch __MARK__/cr'
  'touch __MARK__/star *'
  'touch __MARK__/quest ?'
  'touch __MARK__/tilde ~'
  'touch __MARK__/brace {a,b}'
  'touch __MARK__/ifs $IFS'
  '   '
  ''
)

i=0
while [ "$i" -lt "${#tpls[@]}" ]; do
  n=$((i + 1))
  name="${names[$i]}"
  marker="${markers[$i]}"
  payload="${tpls[$i]//__MARK__/$MK}"
  out="$(run_teamctl "$payload")"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "Negativ #$n ($name): Exit != 0 erwartet, war 0"
    i=$((i + 1)); continue
  fi
  if [ -n "$marker" ] && [ -e "$MK/$marker" ]; then
    fail "Negativ #$n ($name): Nebenwirkung erzeugt ($marker)"
    i=$((i + 1)); continue
  fi
  case "$out" in
    *TEAMCTL_GITHUB_TOKEN_CMD*) ;;
    *) fail "Negativ #$n ($name): Meldung nennt Schluesselnamen nicht"; i=$((i + 1)); continue ;;
  esac
  # Wert-Leak: die Ausgabe darf den Wert nicht enthalten. Bei reinen
  # Leerzeichen-/Leerwerten ist diese Pruefung nicht sinnvoll (uebersprungen).
  if [ -n "$payload" ]; then
    case "$payload" in
      *[![:space:]]*)
        case "$out" in
          *"$payload"*) fail "Negativ #$n ($name): Ausgabe enthaelt den Wert"; i=$((i + 1)); continue ;;
        esac ;;
    esac
  fi
  pass "Negativ #$n ($name): abgelehnt (Exit $rc, keine Nebenwirkung)"
  i=$((i + 1))
done

# Sammel-Kontrolle: im Marker-Ordner darf NICHTS entstanden sein - auch keine
# Datei mit einem Namen, den ein einzelner Fall nicht erwartet.
if [ -n "$(ls -A "$MK")" ]; then
  fail "Negativ-Sammel: Marker-Ordner nicht leer ($(ls -A "$MK" | tr '\n' ' '))"
else
  pass "Negativ-Sammel: keine Nebenwirkung im Marker-Ordner"
fi

# --- 4) Positivtest (hermetisch): erlaubter Befehl wird ausgefuehrt ---------
# "printf selftest-token" ist erlaubt; git_token ruft es auf. Der anschliessende
# API-Aufruf scheitert am curl-Stub - entscheidend ist, dass der Abbruch NICHT
# von der Zeichen-Whitelist kommt (der erlaubte Befehl wurde also ausgefuehrt).
out="$(run_teamctl 'printf selftest-token')"
case "$out" in
  *"unerlaubte Zeichen"*) fail "Positiv: erlaubter Befehl wurde von der Whitelist abgelehnt" ;;
  *"Token nicht lesbar"*) fail "Positiv: erlaubter Befehl konnte nicht ausgefuehrt werden" ;;
  *) pass "Positiv: erlaubter Befehl akzeptiert und ausgefuehrt" ;;
esac

# --- 4b) Fail-Fast: fehlschlagender Token-Befehl bricht ab (Issue #15) -------
# In git_cmd wurde 'TOK="$(git_token)"' ohne '|| exit 1' ausgewertet. Ohne
# 'set -e' brach der Lesefehler die Funktion nicht ab: TOK blieb leer und der
# Befehl lief mit leerem Token weiter. Erwartung: Exit 1, GENAU EINE
# Fehlerzeile (die vorhandene aus git_token) und kein HTTP-Aufruf - der
# curl-Stub wuerde sonst eine zusaetzliche Meldung/Exit 7 erzeugen.
out="$(PATH="$BIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_GITHUB_TOKEN_CMD=/nonexistent/nope \
  bash "$TEAMCTL" git repos 2>&1)"
rc=$?
lines="$(printf '%s\n' "$out" | grep -c .)"
if [ "$rc" -ne 1 ]; then
  fail "Fail-Fast (Issue #15): Exit != 1 (war $rc)"
elif [ "$lines" -ne 1 ]; then
  fail "Fail-Fast (Issue #15): genau 1 Meldung erwartet (waren $lines)"
elif ! printf '%s' "$out" | grep -q 'TEAMCTL_GITHUB_TOKEN_CMD'; then
  fail "Fail-Fast (Issue #15): Meldung nennt den Schluesselnamen nicht"
else
  pass "Fail-Fast (Issue #15): Token-Lesefehler bricht mit genau 1 Meldung ab (Exit 1)"
fi

# --- 5) Optional: Live-Positivtest (echte Konfiguration/Token) --------------
if [ "${TEAMCTL_SELFTEST_LIVE:-0}" = "1" ]; then
  if bash "$TEAMCTL" git repos >/dev/null 2>&1; then
    pass "Live: 'teamctl git repos' exit 0"
  else
    fail "Live: 'teamctl git repos' exit != 0"
  fi
else
  printf 'SKIP: Live-Positivtest (TEAMCTL_SELFTEST_LIVE=1 zum Aktivieren)\n'
fi

# --- Ergebnis ---------------------------------------------------------------
if [ "$FAILS" -gt 0 ]; then
  printf 'FAIL: %d Test(s) fehlgeschlagen\n' "$FAILS" >&2
  exit 1
fi
printf 'PASS: alle Tests erfolgreich\n'
exit 0
