#!/usr/bin/env bash
# tests/selftest.sh - Regressions-Guard fuer teamctl.
#
# Prueft die injektionssichere Aufloesung des GitHub-Tokens (git_token) sowie
# die Syntax des Skripts. Laeuft OHNE Secrets und OHNE Infrastruktur:
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

# --- 2) Guard: kein eval im Zusammenhang mit GITHUB_TOKEN_CMD ---------------
# Jede Zeile, die das Token-Kommando erwaehnt, darf kein eval enthalten.
if grep -n 'GITHUB_TOKEN_CMD' "$TEAMCTL" | grep -Eq '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)'; then
  fail "Guard: kein eval im Zusammenhang mit GITHUB_TOKEN_CMD"
else
  pass "Guard: kein eval im Zusammenhang mit GITHUB_TOKEN_CMD"
fi

# Zusaetzlich: der Funktionskoerper von git_token() enthaelt kein eval.
GTOK="$(awk '/^git_token\(\)/{f=1} f{print} f && /^}/{exit}' "$TEAMCTL")"
if printf '%s' "$GTOK" | grep -v '^[[:space:]]*#' | grep -Eq '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)'; then
  fail "Guard: git_token() ohne eval"
else
  pass "Guard: git_token() ohne eval"
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

run_teamctl() {
  PATH="$BIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_GITHUB_TOKEN_CMD="$1" \
    bash "$TEAMCTL" git repos 2>&1
}

# --- 3) Negativtests: Metazeichen muessen abgelehnt werden ------------------
# Jede Nutzlast versucht bei einer Shell-Interpretation (eval) eine Marker-
# Datei anzulegen. Der Marker darf NICHT entstehen, der Aufruf muss mit
# Exit != 0 abbrechen, die Meldung darf nur den Schluesselnamen nennen und
# niemals den Wert selbst.
payloads=(
  'true; touch __MARK__/semi'
  'printf %s "$(touch __MARK__/subst)"'
  'printf %s "`touch __MARK__/bt`"'
  'printf x | tee __MARK__/pipe'
  'printf x > __MARK__/redir'
)
n=0
for p in "${payloads[@]}"; do
  n=$((n + 1))
  marker="${p##*/}"
  payload="${p//__MARK__/$WORK}"
  out="$(run_teamctl "$payload")"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "Negativ #$n: Exit != 0 erwartet, war 0"
    continue
  fi
  if [ -e "$WORK/$marker" ]; then
    fail "Negativ #$n: Nebenwirkung erzeugt ($marker)"
    continue
  fi
  case "$out" in
    *TEAMCTL_GITHUB_TOKEN_CMD*) ;;
    *) fail "Negativ #$n: Meldung nennt Schluesselnamen nicht"; continue ;;
  esac
  case "$out" in
    *"$payload"*) fail "Negativ #$n: Ausgabe enthaelt den Wert"; continue ;;
  esac
  pass "Negativ #$n: Metazeichen abgelehnt (Exit $rc, keine Nebenwirkung)"
done

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
