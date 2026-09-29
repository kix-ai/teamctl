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

# --- 11) wiki update --parent: Umhaengen ueber pages/move (Issue #22) --------
# --parent war wirkungslos, weil Docmost parentPageId in pages/update ignoriert.
# Der Fix haengt per POST /api/pages/move um (position 5-12 Zeichen Pflicht)
# und prueft das Ergebnis per pages/info (parentPageId). Der curl-Stub unten
# emuliert die Seiten-API offline und protokolliert jede Anfrage in $WP_LOG.
WP="$WORK/wpbin"
mkdir -p "$WP"
cat > "$WP/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: emuliert die Docmost-Seiten-API (kein Netz). Protokoll je Anfrage:
# <METHODE>\t<URL>\t<BODY> in $WP_LOG. Zustand: aktueller Parent in $WP_PARENT.
method=POST; out=/dev/null; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    -D|-H|--max-time|-w|-b|-c|-F) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\t%s\t%s\n' "$method" "$url" "$data" >> "$WP_LOG"
ep="${url##*/api/}"
code=200
case "$ep" in
  auth/login)
    body='{"data":{"user":{"name":"selftest"}}}' ;;
  pages/update)
    printf '%s\n' "$data" >> "$WP_UPD"
    body='{"success":true}' ;;
  pages/sidebar-pages)
    # Enthaelt die umzuhaengende Seite selbst (Selbstausschluss) und einen
    # Nachbarn mit bekannter position.
    body="$(jq -nc --arg p "$WP_PAGE" '{data:{items:[{id:"nb-1",title:"Nachbar",position:"a05FT",hasChildren:false},{id:$p,title:"selbst",position:"a163j",hasChildren:false}]}}')" ;;
  pages/info)
    parent="$(cat "$WP_PARENT" 2>/dev/null || true)"
    body="$(jq -nc --arg p "$parent" --arg c "$WP_CONTENT" '{data:{id:"pg-1",spaceId:"sp-1",parentPageId:(if $p == "" then null else $p end),content:$c,title:"t"}}')" ;;
  pages/move)
    pos="$(printf '%s' "$data" | jq -r '.position // empty')"
    if [ -n "$WP_MOVE_FAIL" ] || [ "${#pos}" -lt 5 ] || [ "${#pos}" -gt 12 ]; then
      code=400
      body='{"message":["position must be longer than or equal to 5 characters"]}'
    else
      if [ -z "$WP_MOVE_NOOP" ]; then
        printf '%s' "$(printf '%s' "$data" | jq -r 'if .parentPageId == null then "" else .parentPageId end')" > "$WP_PARENT"
      fi
      body='{"success":true}'
    fi ;;
  *)
    code=500
    body='{"message":"stub: unhandled request"}' ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
STUB
chmod +x "$WP/curl"
cat > "$WP/ssh" <<'STUB'
#!/usr/bin/env bash
# Stub: liefert ein Dummy-Passwort (kein Netzwerkzugriff).
printf 'dummy\n'
exit 0
STUB
chmod +x "$WP/ssh"

WP_PAGE='pg-selftest'
WP_FILE="$WORK/wp-content.md"
printf 'PARENTMARKER1\n' > "$WP_FILE"
WP_LOG="$WORK/wp.log"; WP_UPD="$WORK/wp.upd"; WP_PARENT="$WORK/wp.parent"
WP_CONTENT='PARENTMARKER1'
WP_KEY="$WORK/id_wp_dummy"; : > "$WP_KEY"

wp_run() {  # $1 = Ziel-Parent ("" = Root); weitere Argumente werden angehaengt
  local parent="$1"; shift
  : > "$WP_LOG"; : > "$WP_UPD"
  printf '%s' 'parent-old' > "$WP_PARENT"
  PATH="$WP:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
    TEAMCTL_WIKI_AS='selftest@selftest.invalid' \
    TEAMCTL_SSH_KEY="$WP_KEY" \
    WP_LOG="$WP_LOG" WP_UPD="$WP_UPD" WP_PARENT="$WP_PARENT" WP_PAGE="$WP_PAGE" \
    WP_CONTENT="$WP_CONTENT" WP_MOVE_FAIL="${WP_MOVE_FAIL:-}" WP_MOVE_NOOP="${WP_MOVE_NOOP:-}" \
    bash "$TEAMCTL" wiki update "$WP_PAGE" --file "$WP_FILE" --parent "$parent" "$@"
}

# 11a) --parent <pageId>: move mit position, Read-back OK, Exit 0.
mout="$(wp_run 'parent-new' 2>&1)"; mrc=$?
mline="$(grep -F 'pages/move' "$WP_LOG" || true)"
if [ "$mrc" -ne 0 ]; then
  fail "wiki update --parent (Issue #22): Exit != 0 (war $mrc)"
  printf '%s\n' "$mout" | sed 's/^/      /' >&2
elif ! printf '%s' "$mline" | grep -q '"parentPageId":"parent-new"'; then
  fail "wiki update --parent (Issue #22): pages/move nicht mit Ziel-Parent aufgerufen"
elif ! printf '%s' "$mline" | grep -q '"position":"a05FTV"'; then
  fail "wiki update --parent (Issue #22): position am Ende der Ziel-Liste fehlt/anders (erwartet a05FTV)"
elif grep -q 'parentPageId' "$WP_UPD"; then
  fail "wiki update --parent (Issue #22): pages/update sendet weiter parentPageId (wirkungslos)"
else
  pass "wiki update --parent (Issue #22): pages/move mit position a05FTV, Read-back OK, Exit 0"
fi

# 11b) --parent '' loest die Seite vom Parent (parentPageId:null, Read-back null).
dout="$(wp_run '' 2>&1)"; drc=$?
dline="$(grep -F 'pages/move' "$WP_LOG" || true)"
if [ "$drc" -ne 0 ]; then
  fail "wiki update --parent \'\' (Issue #22): Exit != 0 (war $drc)"
  printf '%s\n' "$dout" | sed 's/^/      /' >&2
elif ! printf '%s' "$dline" | grep -q '"parentPageId":null'; then
  fail "wiki update --parent \'\' (Issue #22): move ohne parentPageId:null"
elif ! printf '%s' "$dline" | grep -qE '"position":"[A-Za-z0-9]{5,12}"'; then
  fail "wiki update --parent \'\' (Issue #22): position fehlt/ungueltig"
elif [ -n "$(cat "$WP_PARENT" 2>/dev/null)" ]; then
  fail "wiki update --parent \'\' (Issue #22): Read-back nicht auf Root geloest"
else
  pass "wiki update --parent \'\' (Issue #22): vom Parent geloest, Read-back null, Exit 0"
fi

# 11c) Read-back-Schutz: ignorierter move (Parent bleibt alt) -> Abbruch.
WP_MOVE_NOOP=1
vout="$(wp_run 'parent-new' 2>&1)"; vrc=$?
WP_MOVE_NOOP=
if [ "$vrc" -eq 0 ]; then
  fail "wiki update --parent (Read-back, Issue #22): Exit 0 trotz unveraendertem Parent"
elif ! printf '%s' "$vout" | grep -q 'Verifikation'; then
  fail "wiki update --parent (Read-back, Issue #22): keine Verifikationsmeldung"
  printf '%s\n' "$vout" | sed 's/^/      /' >&2
else
  pass "wiki update --parent (Read-back, Issue #22): parentPageId-Mismatch -> Abbruch (Exit $vrc)"
fi

# 11d) move abgelehnt (HTTP 400 zur position) -> klare Meldung, Exit != 0.
WP_MOVE_FAIL=1
fout="$(wp_run 'parent-new' 2>&1)"; frc=$?
WP_MOVE_FAIL=
if [ "$frc" -eq 0 ]; then
  fail "wiki update --parent (Abweisung, Issue #22): Exit 0 trotz HTTP 400"
elif ! printf '%s' "$fout" | grep -q 'Umhaengen fehlgeschlagen'; then
  fail "wiki update --parent (Abweisung, Issue #22): keine klare Meldung"
  printf '%s\n' "$fout" | sed 's/^/      /' >&2
else
  pass "wiki update --parent (Abweisung, Issue #22): HTTP 400 -> klare Meldung, Exit $frc"
fi

# 11e) Ohne --parent wird KEIN move gesendet (kein Nebeneffekt).
: > "$WP_LOG"; : > "$WP_UPD"; printf '%s' 'parent-old' > "$WP_PARENT"
nout="$(PATH="$WP:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' \
  TEAMCTL_SSH_KEY="$WP_KEY" \
  WP_LOG="$WP_LOG" WP_UPD="$WP_UPD" WP_PARENT="$WP_PARENT" WP_PAGE="$WP_PAGE" \
  WP_CONTENT="$WP_CONTENT" \
  bash "$TEAMCTL" wiki update "$WP_PAGE" --file "$WP_FILE" 2>&1)"; nrc=$?
if [ "$nrc" -ne 0 ]; then
  fail "wiki update ohne --parent (Issue #22): Exit != 0 (war $nrc)"
  printf '%s\n' "$nout" | sed 's/^/      /' >&2
elif grep -q 'pages/move' "$WP_LOG"; then
  fail "wiki update ohne --parent (Issue #22): unerwarteter move-Aufruf"
elif grep -q 'parentPageId' "$WP_UPD"; then
  fail "wiki update ohne --parent (Issue #22): pages/update sendet parentPageId"
else
  pass "wiki update ohne --parent (Issue #22): kein move, pages/update ohne parentPageId"
fi

# --- 12) Verifikations-Haertung: wiki create --parent + Inhalts-Read-back ---
# Hintergrund (team-qa-Review): 'wiki create --parent' verifizierte im Read-back
# nur den TITEL, nicht parentPageId (gleiche blinde Stelle wie Issue #22); der
# Inhalts-Read-back in 'wiki update' nutzte nur das erste 6+-alnum-Token als
# Probe und entfiel ganz bei leerer Probe. Neu: parentPageId-Pruefung beim
# Anlegen, vollstaendiger/normalisierter Inhaltsvergleich (ALLE Wort-Token) und
# Fehler bei leerem Inhalt. Der Stub unten emuliert die Seiten-API offline.
WC="$WORK/wcbin"
mkdir -p "$WC"
cat > "$WC/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: emuliert die Docmost-Seiten-API fuer 'wiki create' (kein Netz).
# pages/info gibt Titel, Parent und Inhalt aus dem create-Body zurueck
# (optional per WC_PARENT_OVERRIDE / WC_CONTENT_OMIT manipuliert).
method=POST; out=/dev/null; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    -D|-H|--max-time|-w|-b|-c|-F) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
ep="$(printf '%s' "$url" | sed 's#.*/api/##')"
code=200
case "$ep" in
  auth/login)
    body='{"data":{"user":{"name":"selftest"}}}' ;;
  pages/create)
    printf '%s' "$data" > "$WC_CREATE_OUT"
    if [ -n "$WC_CREATE_FAIL" ]; then code=500; body='{"message":"stub: create abgelehnt"}'
    else body='{"data":{"id":"pg-new"}}'; fi ;;
  pages/info)
    par="$(jq -r '.parentPageId // ""' "$WC_CREATE_OUT" 2>/dev/null)"
    ttl="$(jq -r '.title // ""' "$WC_CREATE_OUT" 2>/dev/null)"
    cnt="$(jq -r '.content // ""' "$WC_CREATE_OUT" 2>/dev/null)"
    if [ -n "$WC_PARENT_OVERRIDE_SET" ]; then par="$WC_PARENT_OVERRIDE"; fi
    if [ -n "$WC_CONTENT_OMIT" ]; then cnt="$(printf '%s' "$cnt" | sed "s/$WC_CONTENT_OMIT//g")"; fi
    body="$(jq -nc --arg t "$ttl" --arg p "$par" --arg c "$cnt" '{data:{id:"pg-new",spaceId:"sp-1",title:$t,parentPageId:(if $p == "" then null else $p end),content:$c}}')" ;;
  *)
    code=500; body='{"message":"stub: unhandled request"}' ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
STUB
chmod +x "$WC/curl"
cat > "$WC/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'dummy\n'
exit 0
STUB
chmod +x "$WC/ssh"

WC_KEY="$WORK/id_wc_dummy"; : > "$WC_KEY"
WC_CREATE_OUT="$WORK/wc.create"
WC_FILE="$WORK/wc-content.md"
printf 'Erster Absatz WortEins.\n\nZweiter Absatz WortZwei.\n' > "$WC_FILE"
WC_CREATE_FAIL=""; WC_PARENT_OVERRIDE=""; WC_PARENT_OVERRIDE_SET=""; WC_CONTENT_OMIT=""

wc_run() {  # $@ = zusaetzliche Optionen (z. B. --parent X)
  : > "$WC_CREATE_OUT"
  PATH="$WC:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
    TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$WC_KEY" \
    WC_CREATE_OUT="$WC_CREATE_OUT" WC_CREATE_FAIL="$WC_CREATE_FAIL" \
    WC_PARENT_OVERRIDE="$WC_PARENT_OVERRIDE" WC_PARENT_OVERRIDE_SET="$WC_PARENT_OVERRIDE_SET" \
    WC_CONTENT_OMIT="$WC_CONTENT_OMIT" \
    bash "$TEAMCTL" wiki create --space sp-1 --title 'Neue Seite' --file "$WC_FILE" "$@"
}

# 12a) create --parent: Exit 0, Seiten-ID auf stdout, parentPageId im Body.
cout="$(wc_run --parent 'parent-x' 2>&1)"; crc=$?
cbody="$(cat "$WC_CREATE_OUT" 2>/dev/null)"
if [ "$crc" -ne 0 ]; then
  fail "wiki create --parent (Verifikations-Haertung): Exit != 0 (war $crc)"
  printf '%s\n' "$cout" | sed 's/^/      /' >&2
elif [ "$cout" != "pg-new" ]; then
  fail "wiki create --parent (Verifikations-Haertung): Seiten-ID fehlt (Ausgabe '$cout')"
elif ! printf '%s' "$cbody" | grep -q '"parentPageId":"parent-x"'; then
  fail "wiki create --parent (Verifikations-Haertung): create ohne Ziel-Parent"
else
  pass "wiki create --parent (Verifikations-Haertung): Exit 0, ID + parentPageId gesetzt"
fi

# 12b) Read-back-Schutz: parentPageId weicht ab -> Abbruch.
WC_PARENT_OVERRIDE_SET=1; WC_PARENT_OVERRIDE='parent-anders'
bout="$(wc_run --parent 'parent-x' 2>&1)"; brc=$?
WC_PARENT_OVERRIDE_SET=""; WC_PARENT_OVERRIDE=""
if [ "$brc" -eq 0 ]; then
  fail "wiki create --parent (Read-back, Verifikations-Haertung): Exit 0 trotz falschem Parent"
elif ! printf '%s' "$bout" | grep -q 'Verifikation'; then
  fail "wiki create --parent (Read-back, Verifikations-Haertung): keine Verifikationsmeldung"
  printf '%s\n' "$bout" | sed 's/^/      /' >&2
else
  pass "wiki create --parent (Read-back, Verifikations-Haertung): parentPageId-Mismatch -> Abbruch (Exit $brc)"
fi

# 12c) create ohne --parent: keine Parent-Pruefung, Exit 0.
nout2="$(wc_run 2>&1)"; nrc2=$?
if [ "$nrc2" -ne 0 ]; then
  fail "wiki create ohne --parent (Verifikations-Haertung): Exit != 0 (war $nrc2)"
  printf '%s\n' "$nout2" | sed 's/^/      /' >&2
elif [ "$nout2" != "pg-new" ]; then
  fail "wiki create ohne --parent (Verifikations-Haertung): Ausgabe '$nout2'"
else
  pass "wiki create ohne --parent (Verifikations-Haertung): Exit 0, keine Parent-Pruefung"
fi

# 12d) Inhalts-Read-back: ein Wort-Token fehlt -> Abbruch.
WC_CONTENT_OMIT='WortZwei'
dout2="$(wc_run 2>&1)"; drc2=$?
WC_CONTENT_OMIT=""
if [ "$drc2" -eq 0 ]; then
  fail "wiki create (Inhalts-Read-back, Verifikations-Haertung): Exit 0 trotz fehlendem Inhalt"
elif ! printf '%s' "$dout2" | grep -q 'Verifikation'; then
  fail "wiki create (Inhalts-Read-back, Verifikations-Haertung): keine Verifikationsmeldung"
  printf '%s\n' "$dout2" | sed 's/^/      /' >&2
else
  pass "wiki create (Inhalts-Read-back, Verifikations-Haertung): fehlendes Wort-Token -> Abbruch (Exit $drc2)"
fi

# 12e) create mit leerem Inhalt (nur Satzzeichen) -> Fehler (nichts pruefbar).
EMPTYF="$WORK/empty-content.md"
printf -- '---\n***\n\n' > "$EMPTYF"
eout2="$(PATH="$WC:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$WC_KEY" \
  WC_CREATE_OUT="$WORK/wc.create2" WC_CREATE_FAIL='' WC_PARENT_OVERRIDE='' \
  WC_PARENT_OVERRIDE_SET='' WC_CONTENT_OMIT='' \
  bash "$TEAMCTL" wiki create --space sp-1 --title 'Leer' --file "$EMPTYF" 2>&1)"; erc2=$?
if [ "$erc2" -eq 0 ]; then
  fail "wiki create (leerer Inhalt, Verifikations-Haertung): Exit 0 trotz leerer Probe"
elif ! printf '%s' "$eout2" | grep -q 'nicht moeglich'; then
  fail "wiki create (leerer Inhalt, Verifikations-Haertung): keine klare Meldung"
  printf '%s\n' "$eout2" | sed 's/^/      /' >&2
else
  pass "wiki create (leerer Inhalt, Verifikations-Haertung): leerer Inhalt -> Abbruch (Exit $erc2)"
fi

# 12f) update: Markdown-Umserialisierung (Tabellen-Padding, _x_ statt *x*,
# eingerueckte Zeilen) darf den vollstaendigen Inhaltsvergleich nicht scheitern lassen.
MDF="$WORK/md-rewrite.md"
printf '%s\n' '## Titel Zwei' '' '**fett** und *kursiv*' '' '| a | b |' '| - | - |' '| 1 | 2 |' '' '  eingerueckt' > "$MDF"
MD_REMOTE='## Titel Zwei

**fett** und _kursiv_

|     |     |
| --- | --- |
| a   | b   |
| 1   | 2   |

eingerueckt'
fout2="$(PATH="$WP:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$WP_KEY" \
  WP_LOG="$WP_LOG" WP_UPD="$WP_UPD" WP_PARENT="$WP_PARENT" WP_PAGE="$WP_PAGE" \
  WP_CONTENT="$MD_REMOTE" WP_MOVE_FAIL='' WP_MOVE_NOOP='' \
  bash "$TEAMCTL" wiki update "$WP_PAGE" --file "$MDF" 2>&1)"; frc2=$?
if [ "$frc2" -ne 0 ]; then
  fail "wiki update (Norm-Vergleich, Verifikations-Haertung): Exit != 0 (war $frc2)"
  printf '%s\n' "$fout2" | sed 's/^/      /' >&2
else
  pass "wiki update (Norm-Vergleich, Verifikations-Haertung): Markdown-Umserialisierung -> Exit 0"
fi

# 12g) update: ein Wort-Token fehlt im Read-back -> Abbruch (statt Zufallstoken).
MF="$WORK/missing-token.md"
printf '%s\n' 'Zeile EINS mit WortAlpha' 'Zeile ZWEI mit WortBeta' > "$MF"
gout="$(PATH="$WP:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$WP_KEY" \
  WP_LOG="$WP_LOG" WP_UPD="$WP_UPD" WP_PARENT="$WP_PARENT" WP_PAGE="$WP_PAGE" \
  WP_CONTENT='Zeile EINS mit WortAlpha' WP_MOVE_FAIL='' WP_MOVE_NOOP='' \
  bash "$TEAMCTL" wiki update "$WP_PAGE" --file "$MF" 2>&1)"; grc=$?
if [ "$grc" -eq 0 ]; then
  fail "wiki update (Inhalts-Read-back, Verifikations-Haertung): Exit 0 trotz fehlendem Token"
elif ! printf '%s' "$gout" | grep -q 'Verifikation'; then
  fail "wiki update (Inhalts-Read-back, Verifikations-Haertung): keine Verifikationsmeldung"
  printf '%s\n' "$gout" | sed 's/^/      /' >&2
else
  pass "wiki update (Inhalts-Read-back, Verifikations-Haertung): fehlendes Token -> Abbruch (Exit $grc)"
fi

# 12h) update: leerer Inhalt -> Fehler (frueher: Verifikation still uebersprungen).
hout="$(PATH="$WP:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$WP_KEY" \
  WP_LOG="$WP_LOG" WP_UPD="$WP_UPD" WP_PARENT="$WP_PARENT" WP_PAGE="$WP_PAGE" \
  WP_CONTENT='x' WP_MOVE_FAIL='' WP_MOVE_NOOP='' \
  bash "$TEAMCTL" wiki update "$WP_PAGE" --file "$EMPTYF" 2>&1)"; hrc=$?
if [ "$hrc" -eq 0 ]; then
  fail "wiki update (leerer Inhalt, Verifikations-Haertung): Exit 0 trotz leerer Probe"
elif ! printf '%s' "$hout" | grep -q 'nicht moeglich'; then
  fail "wiki update (leerer Inhalt, Verifikations-Haertung): keine klare Meldung"
  printf '%s\n' "$hout" | sed 's/^/      /' >&2
else
  pass "wiki update (leerer Inhalt, Verifikations-Haertung): leerer Inhalt -> Abbruch (Exit $hrc)"
fi

# --- 13) H1: Command-Injection ueber --as (Issue #23) -----------------------
# --as/WIKI_AS wird per Whitelist validiert; in ssh-awk-Aufrufen wird der Wert
# ueber shq() remote sicher single-quoted. Beide Schutzschichten werden geprueft.
ASBIN="$WORK/asbin"; mkdir -p "$ASBIN"
cat > "$ASBIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AS_LOG"
exit 0
STUB
chmod +x "$ASBIN/ssh"
cat > "$ASBIN/curl" <<'STUB'
#!/usr/bin/env bash
out=/dev/null
while [ $# -gt 0 ]; do case "$1" in
  -o) out="$2"; shift 2 ;;
  -D|-b|-c|-H|-X|--max-time|-w|--data-binary|--cacert) shift 2 ;;
  -*) shift ;;
  *) shift ;;
esac; done
printf '{}' > "$out"
printf '200'
STUB
chmod +x "$ASBIN/curl"
AS_LOG="$WORK/as.log"; : > "$AS_LOG"
AK="$WORK/id_as_dummy"; : > "$AK"
as_run() { env PATH="$ASBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' TEAMCTL_WIKI_AS='selftest@selftest.invalid' TEAMCTL_SSH_KEY="$AK" AS_LOG="$AS_LOG" bash "$TEAMCTL" "$@"; }

# 13a) Metazeichen-Nutzenlast -> --as abgelehnt (kein ssh, kein Marker).
inj="x'; touch $MK/h1pwn; '"
h1out="$(as_run wiki me --as "$inj" 2>&1)"; h1rc=$?
if [ "$h1rc" -eq 0 ]; then
  fail "H1 (Issue #23): --as-Injection nicht abgelehnt (Exit 0)"
elif ! printf '%s' "$h1out" | grep -q -- '--as'; then
  fail "H1 (Issue #23): keine klare --as-Meldung"
  printf '%s\n' "$h1out" | sed 's/^/      /' >&2
elif [ -e "$MK/h1pwn" ]; then
  fail "H1 (Issue #23): Marker angelegt - Wert wurde ausgewertet"
elif [ -s "$AS_LOG" ]; then
  fail "H1 (Issue #23): ssh trotz ungueltigem --as aufgerufen"
else
  pass "H1 (Issue #23): --as-Injection abgelehnt, kein ssh, kein Marker (Exit $h1rc)"
fi

# 13b) gueltiger Name erreicht ssh und wird single-quoted als Daten uebergeben.
: > "$AS_LOG"
n1out="$(as_run wiki me --as "alice" 2>&1)"; n1rc=$?
if ! grep -qF -- "-v q='alice'" "$AS_LOG"; then
  fail "H1 (Issue #23): gueltiger --as nicht als Daten (q='alice') an ssh uebergeben"
  sed 's/^/      /' "$AS_LOG" >&2
else
  pass "H1 (Issue #23): gueltiger --as als single-quoted Daten an ssh uebergeben"
fi

# 13c) Guard: anfaellige Rohform entfernt, shq + wiki_as_validate vorhanden.
if grep -qF -- "-v q='\$who'" "$TEAMCTL"; then
  fail "H1 (Issue #23): anfaelliges Muster -v q='\$who' weiterhin vorhanden"
elif ! grep -q '^shq()' "$TEAMCTL"; then
  fail "H1 (Issue #23): shq-Helfer fehlt"
elif ! grep -q 'wiki_as_validate' "$TEAMCTL"; then
  fail "H1 (Issue #23): wiki_as_validate fehlt"
else
  pass "H1 (Issue #23): Rohform entfernt, shq + wiki_as_validate vorhanden"
fi

# --- 14) H2: TLS-Verifikation (Issue #24) -----------------------------------
# '-k' darf NUR ohne TEAMCTL_WIKI_CA gelten; mit CA muss --cacert die
# Verifikation aktiv halten (frueher entwertete -k das --cacert). Geprueft
# ueber die curl-Argumente (curl-Stub protokolliert sie).
CSBIN="$WORK/csbin"; mkdir -p "$CSBIN"
cat > "$CSBIN/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CS_LOG"
out=/dev/null
while [ $# -gt 0 ]; do case "$1" in
  -o) out="$2"; shift 2 ;;
  -X|-D|-H|-b|-c|--max-time|--data-binary|-w|--cacert) shift 2 ;;
  -*) shift ;;
  *) shift ;;
esac; done
printf '%s' '{"data":{"user":{"name":"selftest"}}}' > "$out"
printf '200'
STUB
chmod +x "$CSBIN/curl"
cat > "$CSBIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'dummy\n'
exit 0
STUB
chmod +x "$CSBIN/ssh"
CS_LOG="$WORK/cs.log"; : > "$CS_LOG"
CK="$WORK/id_cs_dummy"; : > "$CK"
cs_run() { local _ca="$1"; shift; env PATH="$CSBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_SSH_KEY="$CK" CS_LOG="$CS_LOG" TEAMCTL_WIKI_CA="$_ca" bash "$TEAMCTL" "$@"; }

# 14a) ohne CA -> -k (Insecure-Fallback), kein --cacert.
: > "$CS_LOG"
cs_run '' wiki me --as 'selftest@selftest.invalid' >/dev/null 2>&1 || true
if grep -qE '(^| )-k( |$)' "$CS_LOG" && ! grep -qF -- '--cacert' "$CS_LOG"; then
  pass "H2 (Issue #24): ohne CA -> '-k', kein --cacert"
else
  fail "H2 (Issue #24): ohne CA fehlt '-k' oder --cacert gesetzt"
  sed 's/^/      /' "$CS_LOG" >&2
fi

# 14b) mit CA -> --cacert (Verifikation aktiv), kein -k.
CAF="$WORK/selftest-ca.pem"
if command -v openssl >/dev/null 2>&1; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/selftest-ca.key" -out "$CAF" -days 2 -subj '/CN=selftest.invalid' >/dev/null 2>&1
fi
if [ -s "$CAF" ]; then
  : > "$CS_LOG"
  cs_run "$CAF" wiki me --as 'selftest@selftest.invalid' >/dev/null 2>&1 || true
  if grep -qF -- '--cacert' "$CS_LOG" && ! grep -qE '(^| )-k( |$)' "$CS_LOG"; then
    pass "H2 (Issue #24): mit CA -> '--cacert', kein '-k'"
  else
    fail "H2 (Issue #24): mit CA fehlt --cacert oder '-k' aktiv"
    sed 's/^/      /' "$CS_LOG" >&2
  fi
else
  pass "H2 (Issue #24): mit-CA-Test uebersprungen (openssl fehlt)"
fi

# 14c) Guard: CURL_OPTS enthaelt kein -k mehr.
if grep -q 'CURL_OPTS=(-sk' "$TEAMCTL"; then
  fail "H2 (Issue #24): CURL_OPTS enthaelt weiter '-k'"
else
  pass "H2 (Issue #24): CURL_OPTS ohne '-k'"
fi

# --- 15) M1: wiki export Pruning (Issue #25) --------------------------------
# Pruning darf per Default nur Dateien im Export-Schema entfernen; fremde *.md
# im --out bleiben erhalten. Aggressiv (alle *.md) nur mit --prune.
EXBIN="$WORK/exbin"; mkdir -p "$EXBIN"
cat > "$EXBIN/curl" <<'STUB'
#!/usr/bin/env bash
out=/dev/null; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    -D|-H|--max-time|-w|-b|-c|--cacert) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
ep="${url##*/api/}"
case "$ep" in
  auth/login) body='{"data":{"user":{"name":"selftest"}}}' ;;
  spaces/) body='{"data":{"items":[{"id":"sp-1","slug":"general","name":"General"}]}}' ;;
  pages/sidebar-pages) body='{"data":{"items":[{"id":"deadbeef-cafe-4e5d-9a1b-000000000001","title":"Page One","hasChildren":false}]}}' ;;
  pages/info) body='{"data":{"content":"# Hallo Welt","title":"Page One"}}' ;;
  *) body='{"message":"stub: unhandled"}' ;;
esac
printf '%s' "$body" > "$out"
printf '200'
STUB
chmod +x "$EXBIN/curl"
cat > "$EXBIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'dummy\n'
exit 0
STUB
chmod +x "$EXBIN/ssh"
EK="$WORK/id_ex_dummy"; : > "$EK"
EXOUT="$WORK/exp"
ex_build() {
  rm -rf "$EXOUT"; mkdir -p "$EXOUT"
  printf 'fremd\n' > "$EXOUT/notes.md"
  printf 'fremd\n' > "$EXOUT/README.md"
  printf 'veraltet\n' > "$EXOUT/general__old-page.md"
  printf 'veraltet\n' > "$EXOUT/general__gone-1234abcd.md"
}
ex_run() { env PATH="$EXBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' TEAMCTL_SSH_KEY="$EK" TEAMCTL_WIKI_EXPORT_SLEEP=0 TEAMCTL_WIKI_AS='selftest@selftest.invalid' bash "$TEAMCTL" wiki export --out "$EXOUT" "$@"; }

# 15a) Default: Schema-Dateien ohne Manifest entfernt, fremde *.md bleiben.
ex_build
xout="$(ex_run 2>&1)"; xrc=$?
if [ "$xrc" -ne 0 ]; then
  fail "M1 (Issue #25): Export Exit != 0 (war $xrc)"
  printf '%s\n' "$xout" | sed 's/^/      /' >&2
elif [ -e "$EXOUT/general__old-page.md" ] || [ -e "$EXOUT/general__gone-1234abcd.md" ]; then
  fail "M1 (Issue #25): veraltete Schema-Dateien nicht entfernt"
elif [ ! -f "$EXOUT/notes.md" ] || [ ! -f "$EXOUT/README.md" ]; then
  fail "M1 (Issue #25): fremde *.md im --out geloescht (Default-Pruning zu aggressiv)"
elif [ ! -f "$EXOUT/general__page-one.md" ]; then
  fail "M1 (Issue #25): Export-Datei der Seite fehlt"
else
  pass "M1 (Issue #25): Default entfernt nur Schema-Dateien, fremde *.md bleiben"
fi

# 15b) --no-prune: gar kein Loeschen.
ex_build
ex_run --no-prune >/dev/null 2>&1 || true
if [ -f "$EXOUT/general__old-page.md" ] && [ -f "$EXOUT/notes.md" ]; then
  pass "M1 (Issue #25): --no-prune laesst alles unveraendert"
else
  fail "M1 (Issue #25): --no-prune hat Dateien entfernt"
fi

# 15c) --prune: aggressiv, entfernt auch fremde *.md.
ex_build
ex_run --prune >/dev/null 2>&1 || true
if [ -f "$EXOUT/notes.md" ] || [ -f "$EXOUT/README.md" ]; then
  fail "M1 (Issue #25): --prune entfernte fremde *.md nicht (Opt-in aggressiv)"
else
  pass "M1 (Issue #25): --prune entfernt alle nicht im Manifest stehenden *.md"
fi

# --- 16) git issue-comment: Kommentar + Read-back-Verifikation (Issue #26) ---
# Der Befehl postet einen Kommentar (POST .../issues/{nr}/comments) und liest
# ihn ueber seine ID erneut (GET .../issues/comments/{id}) zurueck; bei
# abweichendem Inhalt bricht er ab. Der curl-Stub emuliert die Kommentar-API
# offline; jede Anfrage wird in $IC_LOG protokolliert, der zuletzt gepostete
# Body in $IC_POSTED abgelegt.
ICBIN="$WORK/icbin"; mkdir -p "$ICBIN"
cat > "$ICBIN/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: emuliert die GitHub-Kommentar-API (kein Netz). Protokollzeile:
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
printf '%s\t%s\t%s\n' "$method" "$url" "$data" >> "$IC_LOG"
body=""; code=200
case "$method $url" in
  "POST "*"/issues/"*"/comments")
    printf '%s' "$data" | jq -r '.body' > "$IC_POSTED"
    if [ -n "$IC_POST_FAIL" ]; then
      code=500; body='{"message":"stub: comment abgelehnt"}'
    else
      body='{"id":9001,"html_url":"https://example.invalid/c/9001"}'; code=201
    fi ;;
  "GET "*"/issues/comments/9001")
    if [ -n "$IC_READBACK_OVERRIDE" ]; then rb="$IC_READBACK_OVERRIDE"
    else rb="$(cat "$IC_POSTED" 2>/dev/null)"; fi
    body="$(jq -nc --arg b "$rb" '{id:9001,body:$b}')" ;;
  *)
    code=500; body='{"message":"stub: unhandled request"}' ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
STUB
chmod +x "$ICBIN/curl"

IC_LOG="$WORK/ic.log"; IC_POSTED="$WORK/ic.posted"
IC_POST_FAIL=""; IC_READBACK_OVERRIDE=""
ic_run() {  # $@ = Argumente fuer git issue-comment (repo/nummer fest: teamctl 26)
  : > "$IC_LOG"; : > "$IC_POSTED"
  PATH="$ICBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
    TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' \
    IC_LOG="$IC_LOG" IC_POSTED="$IC_POSTED" IC_POST_FAIL="$IC_POST_FAIL" \
    IC_READBACK_OVERRIDE="$IC_READBACK_OVERRIDE" \
    bash "$TEAMCTL" git issue-comment teamctl 26 "$@"
}

# 16a) Positiv --body: Exit 0, korrekte Ausgabe, POST + Read-back im Log.
icout="$(ic_run --body 'Hallo Kommentar' 2>&1)"; icrc=$?
okline="$(printf '%s\n' "$icout" | grep -m1 '^OK')"
if [ "$icrc" -ne 0 ]; then
  fail "git issue-comment (16a): Exit != 0 (war $icrc)"
  printf '%s\n' "$icout" | sed 's/^/      /' >&2
elif [ "$okline" != "$(printf 'OK\tselftest-owner/teamctl\t26\t9001\thttps://example.invalid/c/9001')" ]; then
  fail "git issue-comment (16a): Ausgabe unerwartet ('$okline')"
elif ! grep -q 'POST.*/repos/selftest-owner/teamctl/issues/26/comments' "$IC_LOG"; then
  fail "git issue-comment (16a): kein POST auf die Kommentar-URL"
elif ! grep -q 'GET.*/repos/selftest-owner/teamctl/issues/comments/9001' "$IC_LOG"; then
  fail "git issue-comment (16a): kein Read-back per Kommentar-ID"
elif [ "$(cat "$IC_POSTED")" != "Hallo Kommentar" ]; then
  fail "git issue-comment (16a): geposteter Body weicht ab ('$(cat "$IC_POSTED")')"
else
  pass "git issue-comment (Issue #26, 16a): Kommentar gepostet + Read-back verifiziert"
fi

# 16b) Positiv --file: Markdown-Datei wird als Body gepostet.
ICF="$WORK/ic-comment.md"
printf 'Erste Zeile\n\nZweite Zeile mit Wort.\n' > "$ICF"
icout2="$(ic_run --file "$ICF" 2>&1)"; icrc2=$?
if [ "$icrc2" -ne 0 ] || ! grep -q '^OK' <<<"$icout2"; then
  fail "git issue-comment (16b): --file Exit != 0 (war $icrc2)"
  printf '%s\n' "$icout2" | sed 's/^/      /' >&2
elif [ "$(cat "$IC_POSTED")" != "$(cat "$ICF")" ]; then
  fail "git issue-comment (16b): --file-Body weicht ab"
else
  pass "git issue-comment (Issue #26, 16b): --file gepostet und zurueckgelesen"
fi

# 16c) Read-back-Mismatch -> Abbruch (Exit != 0) mit Verifikationsmeldung.
IC_READBACK_OVERRIDE='etwas anderes'
icout3="$(ic_run --body 'Original' 2>&1)"; icrc3=$?
IC_READBACK_OVERRIDE=""
if [ "$icrc3" -eq 0 ]; then
  fail "git issue-comment (16c): Exit 0 trotz abweichendem Read-back"
elif ! printf '%s' "$icout3" | grep -q 'Verifikation'; then
  fail "git issue-comment (16c): keine Verifikationsmeldung"
  printf '%s\n' "$icout3" | sed 's/^/      /' >&2
else
  pass "git issue-comment (Issue #26, 16c): Read-back-Mismatch -> Abbruch (Exit $icrc3)"
fi

# 16d) --body und --file gleichzeitig -> Abbruch ohne API-Aufruf.
icout4="$(ic_run --body x --file "$ICF" 2>&1)"; icrc4=$?
if [ "$icrc4" -eq 0 ] || [ -s "$IC_LOG" ]; then
  fail "git issue-comment (16d): --body+--file nicht abgelehnt (rc=$icrc4)"
else
  pass "git issue-comment (Issue #26, 16d): --body+--file -> Abbruch ohne API-Aufruf"
fi

# 16e) Kein Text -> Abbruch.
icout5="$(ic_run 2>&1)"; icrc5=$?
if [ "$icrc5" -eq 0 ]; then
  fail "git issue-comment (16e): fehlender Text nicht abgelehnt"
else
  pass "git issue-comment (Issue #26, 16e): fehlender Text -> Abbruch (Exit $icrc5)"
fi

# 16f) Ungueltige Issue-Nummer -> Abbruch ohne API-Aufruf.
icout6="$(PATH="$ICBIN:$PATH" TEAMCTL_ENV_FILE="$ENVF" TEAMCTL_WIKI_CA='' \
  TEAMCTL_GITHUB_TOKEN_CMD='printf selftest-token' IC_LOG="$IC_LOG" IC_POSTED="$IC_POSTED" \
  IC_POST_FAIL='' IC_READBACK_OVERRIDE='' \
  bash "$TEAMCTL" git issue-comment teamctl abc --body x 2>&1)"; icrc6=$?
if [ "$icrc6" -eq 0 ] || [ -s "$IC_LOG" ]; then
  fail "git issue-comment (16f): ungueltige Nummer nicht abgelehnt (rc=$icrc6)"
else
  pass "git issue-comment (Issue #26, 16f): ungueltige Nummer -> Abbruch ohne API-Aufruf"
fi

# 16g) POST-Fehler (HTTP 500) -> Abbruch mit HTTP-Meldung.
IC_POST_FAIL=1
icout7="$(ic_run --body 'x' 2>&1)"; icrc7=$?
IC_POST_FAIL=""
if [ "$icrc7" -eq 0 ]; then
  fail "git issue-comment (16g): Exit 0 trotz POST-Fehler"
elif ! printf '%s' "$icout7" | grep -q 'HTTP 500'; then
  fail "git issue-comment (16g): HTTP-500-Meldung fehlt"
  printf '%s\n' "$icout7" | sed 's/^/      /' >&2
else
  pass "git issue-comment (Issue #26, 16g): POST-Fehler -> Abbruch mit HTTP 500"
fi

# --- Ergebnis ---------------------------------------------------------------
if [ "$FAILS" -gt 0 ]; then
  printf 'FAIL: %d Test(s) fehlgeschlagen\n' "$FAILS" >&2
  exit 1
fi
printf 'PASS: alle Tests erfolgreich\n'
exit 0
