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

# --- 6) doctor: read-only Selbstdiagnose -------------------------------------
# doctor laeuft VOR der Pflichtwert-Pruefung und darf selbst nicht abbrechen.
# Fuer einen gruenen Lauf werden curl und ssh durch Erfolgs-Stubs ersetzt
# (HTTP 200 bzw. Dummy-Passwort); ein Dummy-Key erfuellt die SSH-Key-Pruefung.
BINOK="$WORK/binok"
mkdir -p "$BINOK"
cat > "$BINOK/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: liefert immer HTTP 200 (kein Netzwerkzugriff).
printf '200'
exit 0
STUB
cat > "$BINOK/ssh" <<'STUB'
#!/usr/bin/env bash
# Stub: liefert ein Dummy-Passwort (kein Netzwerkzugriff).
printf 'dummy'
exit 0
STUB
chmod +x "$BINOK/curl" "$BINOK/ssh"
KEYOK="$WORK/id_dummy"
: > "$KEYOK"

# 6a) Positiv: Exit 0 und KEINE FAIL-Zeile in gruener Umgebung.
dout="$(PATH="$BINOK:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$KEYOK" \
  bash "$TEAMCTL" doctor 2>&1)"
drc=$?
if [ "$drc" -ne 0 ]; then
  fail "doctor 6a (positiv): Exit != 0 (war $drc)"
  printf '%s\n' "$dout" | sed 's/^/      /' >&2
elif printf '%s\n' "$dout" | grep -q $'\tFAIL\t'; then
  fail "doctor 6a (positiv): unerwartete FAIL-Zeile"
  printf '%s\n' "$dout" | sed 's/^/      /' >&2
else
  pass "doctor 6a (positiv): Exit 0, keine FAIL-Zeile"
fi

# 6a-Format: jede Pruefzeile hat genau 3 TAB-getrennte Felder.
if [ -z "$dout" ]; then
  fail "doctor 6a (Format): keine Ausgabe"
elif printf '%s\n' "$dout" | awk -F'\t' 'NF!=3{exit 1}'; then
  pass "doctor 6a (Format): jede Zeile <pruefung>\t<status>\t<detail>"
else
  fail "doctor 6a (Format): Zeile ohne 3 TAB-Felder"
  printf '%s\n' "$dout" | sed 's/^/      /' >&2
fi

# 6b) Negativ: http://-GIT_API -> config FAIL + Exit 1 und KEIN Wert-Leak.
# Der Befehl muss trotz ungueltiger Konfiguration laufen (nicht vorher abbrechen).
BADVAL='http://selftest.invalid/api'
dout2="$(PATH="$BINOK:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_GIT_API="$BADVAL" TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$KEYOK" \
  bash "$TEAMCTL" doctor 2>&1)"
drc2=$?
if [ "$drc2" -ne 1 ]; then
  fail "doctor 6b (negativ): Exit != 1 (war $drc2)"
elif printf '%s\n' "$dout2" | grep -q $'^config\tFAIL\t'; then
  pass "doctor 6b (negativ): config FAIL mit Exit 1"
else
  fail "doctor 6b (negativ): keine 'config FAIL'-Zeile"
  printf '%s\n' "$dout2" | sed 's/^/      /' >&2
fi
case "$dout2" in
  *"$BADVAL"*) fail "doctor 6b (negativ): Ausgabe enthaelt den gesetzten Wert" ;;
  *) pass "doctor 6b (negativ): kein Wert-Leak (http://-Wert nicht ausgegeben)" ;;
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

# --- 7) Retry: retry-after-auth respektieren (Issue #16) ---------------------
# Der Wiki-Host liefert bei HTTP 429 den Header "retry-after-auth: <sek>" statt
# "Retry-After". Frueher wurde nur /^Retry-After:/ geparst, daher wartete teamctl
# nur das kurze Backoff ab und lief erneut in 429. Geprueft wird (a) der Parser
# retry_after_secs direkt (ohne Netzwerk) und (b) ein Ende-zu-Ende-Lauf ueber
# "wiki me" mit curl-/ssh-/sleep-Stubs (kein Netzwerk, keine echte Wartezeit).
RAS="$WORK/retry_after_secs.sh"
awk '/^retry_after_secs\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$TEAMCTL" > "$RAS"
if [ ! -s "$RAS" ]; then
  fail "Retry-Parser (Issue #16): retry_after_secs fehlt in teamctl"
else
  . "$RAS"
  H_CASE="$WORK/hdr-case";  printf 'Retry-After-Auth: 22\r\nContent-Type: application/json\r\n' > "$H_CASE"
  H_STD="$WORK/hdr-std";    printf 'retry-after: 7\n' > "$H_STD"
  H_MULTI="$WORK/hdr-multi"; printf 'Retry-After: 5\nretry-after-auth: 9\n' > "$H_MULTI"
  H_NONE="$WORK/hdr-none";  printf 'Content-Type: application/json\n' > "$H_NONE"
  H_CAP="$WORK/hdr-cap";    printf 'retry-after-auth: 999\n' > "$H_CAP"

  TEAMCTL_RETRY_CAP=30
  ra_out="$(retry_after_secs "$H_CASE")"
  if [ "$ra_out" = "22" ]; then pass "Retry-Parser (Issue #16): 'Retry-After-Auth' case-insensitiv -> 22s"
  else fail "Retry-Parser (Issue #16): 'Retry-After-Auth' -> '$ra_out' (erwartet 22)"; fi

  ra_out="$(retry_after_secs "$H_STD")"
  if [ "$ra_out" = "7" ]; then pass "Retry-Parser (Issue #16): Standard 'retry-after' -> 7s"
  else fail "Retry-Parser (Issue #16): Standard 'retry-after' -> '$ra_out' (erwartet 7)"; fi

  ra_out="$(retry_after_secs "$H_MULTI")"
  if [ "$ra_out" = "9" ]; then pass "Retry-Parser (Issue #16): mehrere retry-after*-Header -> 9s (groesster Wert)"
  else fail "Retry-Parser (Issue #16): mehrere Header -> '$ra_out' (erwartet 9)"; fi

  ra_out="$(retry_after_secs "$H_NONE")"
  if [ -z "$ra_out" ]; then pass "Retry-Parser (Issue #16): ohne retry-after* -> leer (Backoff bleibt)"
  else fail "Retry-Parser (Issue #16): ohne retry-after* -> '$ra_out' (erwartet leer)"; fi

  TEAMCTL_RETRY_CAP=4
  ra_out="$(retry_after_secs "$H_CAP")"
  if [ "$ra_out" = "4" ]; then pass "Retry-Parser (Issue #16): Headerwert 999s auf TEAMCTL_RETRY_CAP=4 begrenzt"
  else fail "Retry-Parser (Issue #16): Begrenzung -> '$ra_out' (erwartet 4)"; fi

  # Issue #17: Headerwert oberhalb der bash-Ganzzahlgrenze. Frueher scheiterte
  # der bash-Vergleich "[ $secs -gt $cap ]" still (Fliesskommaform), der
  # Riesenwert lief ungekappt durch. Die Kappung muss in awk erfolgen und einen
  # reinen Integer liefern.
  H_BIG="$WORK/hdr-big"; printf 'retry-after-auth: 99999999999999999999\n' > "$H_BIG"
  TEAMCTL_RETRY_CAP=30
  ra_out="$(retry_after_secs "$H_BIG")"
  if [ "$ra_out" = "30" ]; then pass "Retry-Parser (Issue #17): intmax-Ueberlauf auf TEAMCTL_RETRY_CAP=30 gekappt"
  else fail "Retry-Parser (Issue #17): intmax-Ueberlauf -> '$ra_out' (erwartet 30)"; fi
  case "$ra_out" in
    ''|*[!0-9]*) fail "Retry-Parser (Issue #17): Ausgabe kein reiner Integer ('$ra_out')" ;;
    *)           pass "Retry-Parser (Issue #17): Ausgabe ist reiner Integer (kein 1e+20)" ;;
  esac
  TEAMCTL_RETRY_CAP=30
fi

# 7b) Ende-zu-Ende: wiki_http wartet die retry-after-auth-Zeit ab (Issue #16).
# curl-Stub: 1. Aufruf HTTP 429 mit "retry-after-auth: 3", danach HTTP 200.
# sleep-Stub: protokolliert die Wartezeit statt zu schlafen.
E2E="$WORK/e2e"
mkdir -p "$E2E"
E2E_CNT="$WORK/e2e.cnt"; E2E_SLEEP="$WORK/e2e.sleep"
: > "$E2E_CNT"; : > "$E2E_SLEEP"
cat > "$E2E/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: 1. Aufruf HTTP 429 mit retry-after-auth, danach HTTP 200 (kein Netz).
n=1
[ -s "$E2E_CNT" ] && n=$(( $(cat "$E2E_CNT") + 1 ))
printf '%s' "$n" > "$E2E_CNT"
out=/dev/null; hdr=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -D) hdr="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
if [ "$n" -eq 1 ]; then
  [ -n "$hdr" ] && printf 'HTTP/1.1 429 Too Many Requests\r\nretry-after-auth: 3\r\n\r\n' > "$hdr"
  printf '{"message":"too many requests"}' > "$out"
  printf '429'
else
  [ -n "$hdr" ] && printf 'HTTP/1.1 200 OK\r\n\r\n' > "$hdr"
  printf '{"data":{"user":{"name":"selftest"}}}' > "$out"
  printf '200'
fi
STUB
cat > "$E2E/sleep" <<'STUB'
#!/usr/bin/env bash
# Stub: protokolliert die Wartezeit statt zu schlafen.
printf '%s\n' "$1" >> "$E2E_SLEEP"
exit 0
STUB
cat > "$E2E/ssh" <<'STUB'
#!/usr/bin/env bash
# Stub: liefert ein Dummy-Passwort (kein Netzwerkzugriff).
printf 'dummy\n'
exit 0
STUB
chmod +x "$E2E/curl" "$E2E/sleep" "$E2E/ssh"
E2E_KEY="$WORK/id_e2e_dummy"; : > "$E2E_KEY"

e2e_out="$(PATH="$E2E:$PATH" E2E_CNT="$E2E_CNT" E2E_SLEEP="$E2E_SLEEP" \
  TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' TEAMCTL_WIKI_AS='selftest@selftest.invalid' \
  TEAMCTL_SSH_KEY="$E2E_KEY" bash "$TEAMCTL" wiki me 2>&1)"
e2e_rc=$?
if [ "$e2e_rc" -ne 0 ]; then
  fail "Retry E2E (Issue #16): 'wiki me' Exit != 0 (war $e2e_rc)"
  printf '%s\n' "$e2e_out" | sed 's/^/      /' >&2
elif ! grep -qx '3' "$E2E_SLEEP"; then
  fail "Retry E2E (Issue #16): Wartezeit aus retry-after-auth nicht genutzt (sleep: $(tr '\n' ' ' < "$E2E_SLEEP"))"
  printf '%s\n' "$e2e_out" | sed 's/^/      /' >&2
elif ! printf '%s' "$e2e_out" | grep -q 'selftest'; then
  fail "Retry E2E (Issue #16): Ausgabe ohne Erfolgsmarker"
  printf '%s\n' "$e2e_out" | sed 's/^/      /' >&2
else
  pass "Retry E2E (Issue #16): wiki_http wartet retry-after-auth (3s) ab und laeuft durch"
fi

# --- 8) git status: read-only Status eines lokalen Klons (kein Netz/Token) ---
GSTAT="$WORK/gstat"
mkdir -p "$GSTAT"
git -C "$GSTAT" init -q -b main 2>/dev/null || git -C "$GSTAT" init -q 2>/dev/null
git -C "$GSTAT" -c user.email=selftest@selftest.invalid -c user.name=selftest \
  commit --allow-empty -qm 'init' 2>/dev/null
printf 'x\n' > "$GSTAT/neu.txt"
gout="$(PATH="$BIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
  bash "$TEAMCTL" git status "$GSTAT" 2>&1)"
grc=$?
if [ "$grc" -ne 0 ]; then
  fail "git status (positiv): Exit != 0 (war $grc)"
  printf '%s\n' "$gout" | sed 's/^/      /' >&2
else
  fields="$(printf '%s\n' "$gout" | awk -F'\t' 'NF{print NF}')"
  if [ "$fields" != "6" ]; then
    fail "git status (Format): 6 TAB-Felder erwartet (waren $fields)"
  else
    pass "git status (Format): 6 TAB-Felder"
  fi
  unt="$(printf '%s\n' "$gout" | awk -F'\t' '{print $6}')"
  chg="$(printf '%s\n' "$gout" | awk -F'\t' '{print $5}')"
  if [ "$unt" = "1" ]; then pass "git status: untracked=1 erkannt"
  else fail "git status: untracked erwartet 1 (war $unt)"; fi
  if [ "$chg" = "1" ]; then pass "git status: changed=1 erkannt"
  else fail "git status: changed erwartet 1 (war $chg)"; fi
fi
NGSTAT="$WORK/not-a-repo"; mkdir -p "$NGSTAT"
gout2="$(PATH="$BIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
  bash "$TEAMCTL" git status "$NGSTAT" 2>&1)"
grc2=$?
if [ "$grc2" -eq 0 ]; then
  fail "git status (negativ): Exit != 0 erwartet, war 0"
else
  pass "git status (negativ): kein Repo -> Abbruch (Exit $grc2)"
fi

# --- 9) wiki search: Volltext (Titel + Body + Tags-Zeile), Issue #20 -------
# Offline-Pruefung: die Volltextsuche liest den lokalen Export und braucht
# kein Netzwerk. Der Fixture-Space 'general' enthaelt eine Seite, die den
# Suchbegriff NUR in der Tags-Zeile traegt (nicht im Titel).
WSBIN="$WORK/wsbin"
mkdir -p "$WSBIN"
cat > "$WSBIN/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: kein Netzwerk. Die Volltextsuche braucht keins; der API-Fallback
# (fehlender Export) muss hier scheitern.
exit 7
STUB
cat > "$WSBIN/ssh" <<'STUB'
#!/usr/bin/env bash
# Stub: Dummy-Passwort, damit der API-Fallback schnell und ohne Netz abbricht.
printf 'dummy\n'
exit 0
STUB
chmod +x "$WSBIN/curl" "$WSBIN/ssh"

WSEARCH="${WORK}/wsearch"
mkdir -p "$WSEARCH"
cat > "$WSEARCH/general__wissensdatenbank.md" <<'WSMD'
---
title: "Wissensdatenbank"
space: "general"
spaceId: "sp-x"
pageId: "pg-x"
---

# Wissensdatenbank

Tags: CWE-502, Deserialisierung
WSMD
cat > "$WSEARCH/team-dev__ohne-treffer.md" <<'WSMD'
---
title: "Ohne Treffer"
space: "team-dev"
spaceId: "sp-y"
pageId: "pg-y"
---

Kein gesuchter Begriff in dieser Seite.
WSMD
printf 'general__wissensdatenbank.md\tpg-x\tgeneral\tWissensdatenbank\nteam-dev__ohne-treffer.md\tpg-y\tteam-dev\tOhne Treffer\n' > "$WSEARCH/.wiki-sync-manifest.tsv"

ws_run() { PATH="$WSBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' bash "$TEAMCTL" wiki search "$@"; }

# 9a) Treffer nur in der Tags-Zeile wird gefunden (Default = Volltext).
wsout="$(ws_run CWE-502 --export-dir "$WSEARCH" 2>/dev/null)"
if [ "$wsout" = "$(printf 'general\tpg-x\tWissensdatenbank')" ]; then
  pass "wiki search Volltext (Issue #20): Treffer nur in der Tags-Zeile gefunden"
else
  fail "wiki search Volltext (Issue #20): erwartet 'general TAB pg-x TAB Wissensdatenbank', war '$wsout'"
fi

# 9b) Kein Treffer -> leere Ausgabe, Exit 1 (wie grep; entspricht dem alten
# Verhalten der titelbasierten Suche unter 'set -o pipefail').
wsout2="$(ws_run XYZ-NOPE --export-dir "$WSEARCH" 2>/dev/null)"; ws_rc=$?
if [ "$ws_rc" -eq 1 ] && [ -z "$wsout2" ]; then
  pass "wiki search Volltext (Issue #20): kein Treffer -> leere Ausgabe, Exit 1"
else
  fail "wiki search Volltext (Issue #20): kein Treffer -> rc=$ws_rc, Ausgabe '$wsout2'"
fi

# 9c) Ohne Manifest: YAML-Kopfzeilen dienen als Index.
rm -f "$WSEARCH/.wiki-sync-manifest.tsv"
wsout3="$(ws_run CWE-502 --export-dir "$WSEARCH" 2>/dev/null)"
if [ "$wsout3" = "$(printf 'general\tpg-x\tWissensdatenbank')" ]; then
  pass "wiki search Volltext (Issue #20): ohne Manifest via YAML-Kopfzeile gefunden"
else
  fail "wiki search Volltext (Issue #20): ohne Manifest -> '$wsout3'"
fi

# 9d) Veralteter Export -> Hinweis auf stderr (Schwelle 0 Stunden erzwingt ihn).
ws_err="$(PATH="$WSBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' TEAMCTL_WIKI_SEARCH_MAX_AGE=0 \
  bash "$TEAMCTL" wiki search CWE-502 --export-dir "$WSEARCH" 2>&1 >/dev/null)"
case "$ws_err" in
  *"alt"*) pass "wiki search Volltext (Issue #20): veralteter Export -> Hinweis auf stderr" ;;
  *) fail "wiki search Volltext (Issue #20): kein Veraltet-Hinweis (stderr: $ws_err)" ;;
esac

# 9e) Fehlender Export -> Hinweis + Fallback auf die titelbasierte API-Suche.
ws_err2="$(ws_run CWE-502 --export-dir "$WSEARCH-nonexistent" 2>&1 >/dev/null)"
case "$ws_err2" in
  *"kein Wiki-Export"*) pass "wiki search (Issue #20): fehlender Export -> Hinweis + API-Fallback" ;;
  *) fail "wiki search (Issue #20): fehlender Export -> kein Hinweis (stderr: $ws_err2)" ;;
esac

# --- 10) git upload: Executable-Bit (mode 100755) bleibt erhalten ----------
# Regression zum Fehlerbild "mode change 100755 => 100644": die Contents-API
# speichert regulaere Dateien immer als 100644. Fuer ausfuehrbare lokale
# Dateien muss git upload daher die Git-Data-API nutzen (blob -> tree mit
# mode 100755 -> commit -> ref). Der curl-Stub emuliert die GitHub-API
# vollstaendig offline; jede Anfrage wird in $UP_LOG protokolliert.
GUPBIN="$WORK/gupbin"
mkdir -p "$GUPBIN"
cat > "$GUPBIN/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: emuliert die GitHub-API (kein Netz). Protokollzeile:
# <METHODE>\t<URL>\t<BODY>
method=GET; out=/dev/null; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    -H|--max-time|-w) shift 2 ;;
    -sS|-s|-S) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\t%s\t%s\n' "$method" "$url" "$data" >> "$UP_LOG"
tpath="$url"; tpath="$(printf '%s' "$tpath" | sed 's#.*/contents/##')"
tmode="$UP_TREE_MODE"; [ -n "$tmode" ] || tmode=100755
body=""; code=200
case "$method $url" in
  "GET "*"/repos/selftest-owner/selftest-repo")
    body='{"default_branch":"main"}' ;;
  "GET "*"/git/ref/heads/main")
    body='{"object":{"sha":"head1"}}' ;;
  "GET "*"/git/commits/head1")
    body='{"tree":{"sha":"basetree1"}}' ;;
  "GET "*"/git/trees/commit1?recursive=1")
    body="$(jq -nc --arg p "$UP_PATH" --arg m "$tmode" '{tree:[{path:$p,mode:$m,sha:"blob1"}]}')" ;;
  "POST "*"/git/blobs")
    body='{"sha":"blob1"}'; code=201 ;;
  "POST "*"/git/trees")
    body='{"sha":"tree1"}'; code=201 ;;
  "POST "*"/git/commits")
    body='{"sha":"commit1"}'; code=201 ;;
  "PATCH "*"/git/refs/heads/main")
    body='{}' ;;
  "PUT "*)
    printf '%s' "$data" | jq -r '.content' | base64 -d | wc -c | tr -d '[:space:]' > "$UP_STATE"
    body='{"content":{"sha":"put1"}}'; code=201 ;;
  "GET "*)
    if [ -s "$UP_STATE" ]; then
      body="$(jq -nc --argjson s "$(cat "$UP_STATE")" '{sha:"put1",size:$s}')"
    else
      body='{"message":"Not Found"}'; code=404
    fi ;;
  *)
    body='{"message":"stub: unhandled request"}'; code=500 ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
STUB
chmod +x "$GUPBIN/curl"

guprun() {
  local state="$1" log="$2" p="$3" tmode="$4" file="$5"; shift 5
  : > "$log"; : > "$state"
  PATH="$GUPBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
    TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
    UP_LOG="$log" UP_STATE="$state" UP_PATH="$p" UP_TREE_MODE="$tmode" \
    bash "$TEAMCTL" git upload selftest-repo "$p" "$file" "$@"
}

# 10a) ausfuehrbare Datei -> Git-Data-API, Tree-Eintrag mode 100755.
GUP_A="$WORK/gup-a"; mkdir -p "$GUP_A"
printf '#!/bin/sh\necho hallo\n' > "$GUP_A/x.sh"; chmod +x "$GUP_A/x.sh"
a_out="$(guprun "$GUP_A/state" "$GUP_A/log" x.sh 100755 "$GUP_A/x.sh" 2>&1)"; a_rc=$?
if [ "$a_rc" -ne 0 ]; then
  fail "git upload mode (10a): Exit != 0 (war $a_rc)"
  printf '%s\n' "$a_out" | sed 's/^/      /' >&2
else
  pass "git upload mode (10a): ausfuehrbare Datei -> Exit 0"
fi
if grep -q '/git/blobs' "$GUP_A/log" && grep -q '"mode":"100755"' "$GUP_A/log" \
   && grep -q 'PATCH' "$GUP_A/log"; then
  pass "git upload mode (10a): blob -> tree(mode 100755) -> ref"
else
  fail "git upload mode (10a): Data-API-Kette/Tree-Mode fehlt"
fi
if grep -q '/contents/' "$GUP_A/log"; then
  fail "git upload mode (10a): Contents-API trotz Executable genutzt"
else
  pass "git upload mode (10a): keine Contents-API fuer ausfuehrbare Datei"
fi

# 10b) nicht ausfuehrbare Datei -> Contents-API (Altverhalten, mode 100644).
GUP_B="$WORK/gup-b"; mkdir -p "$GUP_B"
printf 'plain content\n' > "$GUP_B/y.sh"
b_out="$(guprun "$GUP_B/state" "$GUP_B/log" y.sh 100755 "$GUP_B/y.sh" 2>&1)"; b_rc=$?
if [ "$b_rc" -eq 0 ] && grep -q '/contents/y.sh' "$GUP_B/log" \
   && ! grep -q '/git/blobs' "$GUP_B/log"; then
  pass "git upload mode (10b): nicht ausfuehrbar -> Contents-API"
else
  fail "git upload mode (10b): rc=$b_rc, Log: $(tr '\n' '|' < "$GUP_B/log")"
fi

# 10c) --no-exec erzwingt die Contents-API auch bei lokalem +x.
GUP_C="$WORK/gup-c"; mkdir -p "$GUP_C"
printf 'x\n' > "$GUP_C/z.sh"; chmod +x "$GUP_C/z.sh"
c_out="$(guprun "$GUP_C/state" "$GUP_C/log" z.sh 100755 "$GUP_C/z.sh" --no-exec 2>&1)"; c_rc=$?
if [ "$c_rc" -eq 0 ] && grep -q '/contents/z.sh' "$GUP_C/log" \
   && ! grep -q '/git/blobs' "$GUP_C/log"; then
  pass "git upload mode (10c): --no-exec -> Contents-API"
else
  fail "git upload mode (10c): rc=$c_rc, Log: $(tr '\n' '|' < "$GUP_C/log")"
fi

# 10d) --exec erzwingt die Git-Data-API auch ohne lokales +x.
GUP_D="$WORK/gup-d"; mkdir -p "$GUP_D"
printf 'plain\n' > "$GUP_D/w.sh"
d_out="$(guprun "$GUP_D/state" "$GUP_D/log" w.sh 100755 "$GUP_D/w.sh" --exec 2>&1)"; d_rc=$?
if [ "$d_rc" -eq 0 ] && grep -q '"mode":"100755"' "$GUP_D/log" \
   && ! grep -q '/contents/' "$GUP_D/log"; then
  pass "git upload mode (10d): --exec -> Git-Data-API (mode 100755)"
else
  fail "git upload mode (10d): rc=$d_rc, Log: $(tr '\n' '|' < "$GUP_D/log")"
fi

# 10e) Verifikation: falscher Mode im Read-back -> Abbruch (Exit != 0).
GUP_E="$WORK/gup-e"; mkdir -p "$GUP_E"
printf 'y\n' > "$GUP_E/v.sh"; chmod +x "$GUP_E/v.sh"
e_out="$(guprun "$GUP_E/state" "$GUP_E/log" v.sh 100644 "$GUP_E/v.sh" 2>&1)"; e_rc=$?
if [ "$e_rc" -ne 0 ] && printf '%s' "$e_out" | grep -q 'Verifikation'; then
  pass "git upload mode (10e): Read-back-Mode-Abweichung -> Abbruch"
else
  fail "git upload mode (10e): rc=$e_rc, Ausgabe: $e_out"
fi

# --- Ergebnis ---------------------------------------------------------------
if [ "$FAILS" -gt 0 ]; then
  printf 'FAIL: %d Test(s) fehlgeschlagen\n' "$FAILS" >&2
  exit 1
fi
printf 'PASS: alle Tests erfolgreich\n'
exit 0
