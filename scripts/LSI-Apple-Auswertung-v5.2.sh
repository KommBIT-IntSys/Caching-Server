#!/bin/zsh
# SPDX-License-Identifier: EUPL-1.2
# lsi_apple_auswertung.sh
# Wertet WID-Sicherheitsmeldungen (BSI/LSI-Bayern) mit Apple-Bezug aus.
# macOS-Äquivalent zu LSI-Apple-Auswertung-v5.2.ps1
#
# Abhängigkeiten: curl, jq, python3  (curl + python3 auf jedem Mac vorhanden;
#                                      jq: brew install jq)
#
# API-Key:
#   Variante A: SCRIPT_WID_API_KEY unten im Skript direkt eintragen.
#   Variante B: export WID_API_KEY="lsiwid_..."
#
# Nutzung:
#   ./lsi_apple_auswertung.sh [Optionen]
#
# Optionen:
#   -d TAGE    Zeitfenster rückwärts (DaysBack).       Default: 365
#   -m MAX     Max. Advisories pro Lauf.               Default: 50
#   -s BOOL    Nur abonnierte Advisories (true|false). Default: true
#   -r REGEX   Titel-Filter (ERE).                     Default: Apple iOS/iPadOS/Safari
#   -p GROESSE Seitengrösse WID-API.                   Default: 100
#   -j         Roh-JSON je LSI speichern
#   -c         Einzel-CSV je LSI speichern
#   -f         Vollanlage erzwingen (ForceFullRun)
#   -h         Hilfe
#
# Ausgabe (im Skript-Verzeichnis):
#   LSI-Apple-Gesamtauswertung_<Datum>.csv
#   LSI-Apple-Managementreport_<Datum>.csv

# =============================================================================
# LOKALE KONFIGURATION — hier API-Key eintragen für Rechtsklick-Betrieb
# =============================================================================
SCRIPT_WID_API_KEY="Dein-LSI-API-Key"

# iOS-/iPadOS-Zweige im Feld (manuell pflegen)
RELEVANT_VERSIONS=("18" "26")

# =============================================================================
# DEFAULTS
# =============================================================================
DAYS_BACK=365
MAX_ADVISORIES=50
ONLY_SUBSCRIBED=true
TITLE_REGEX="Apple.*(iOS|iPadOS)|iOS.*iPadOS|Apple Safari"
PAGE_SIZE=100
KEEP_RAW_JSON=false
KEEP_PER_ADVISORY_CSV=false
FORCE_FULL_RUN=false

# =============================================================================
# PARAMETER
# =============================================================================
usage() {
    sed -n '/^# Nutzung:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
    exit 0
}

while getopts "d:m:s:r:p:jcfh" opt; do
    case $opt in
        d) DAYS_BACK=$OPTARG ;;
        m) MAX_ADVISORIES=$OPTARG ;;
        s) ONLY_SUBSCRIBED=$OPTARG ;;
        r) TITLE_REGEX=$OPTARG ;;
        p) PAGE_SIZE=$OPTARG ;;
        j) KEEP_RAW_JSON=true ;;
        c) KEEP_PER_ADVISORY_CSV=true ;;
        f) FORCE_FULL_RUN=true ;;
        h) usage ;;
        *) print "Unbekannte Option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# =============================================================================
# SETUP
# =============================================================================
SCRIPT_DIR="${0:A:h}"
OUT_DIR="$SCRIPT_DIR"
TIMESTAMP=$(date '+%Y-%m-%d')
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

# API-Key aus Skript übernehmen falls kein Platzhalter
if [[ -n "${SCRIPT_WID_API_KEY}" && \
      "${SCRIPT_WID_API_KEY}" != "Dein-LSI-API-Key" && \
      "${SCRIPT_WID_API_KEY}" != "dein-api-key" ]]; then
    WID_API_KEY="${SCRIPT_WID_API_KEY}"
fi

if [[ -z "${WID_API_KEY:-}" ]]; then
    print "FEHLER: WID_API_KEY nicht gesetzt." >&2
    print "  Variante A: SCRIPT_WID_API_KEY im Skript eintragen." >&2
    print "  Variante B: export WID_API_KEY='lsiwid_...'" >&2
    exit 1
fi

# CSV-Spaltennamen
CSV_COLUMNS=(
    LsiId LsiTitel LsiRisiko Exploit NoPatch
    LsiInitialdatum LsiStand BetroffeneVersionen BehobenDurch
    MinFixVersions MinFixIosLinie18 MinFixIosLinie26
    MinFixIpadOsLinie18 MinFixIpadOsLinie26
    QuelleDeutsch AppleUrl Komponente
    ImpactOriginal DescriptionOriginal CVEs
    Qualitaet KurzbeschreibungDE
)

# =============================================================================
# HELPER: CSV
# =============================================================================
csv_header() {
    python3 -c "
import csv, sys
from io import StringIO
fields = sys.argv[1:]
buf = StringIO()
w = csv.writer(buf, delimiter=';', quoting=csv.QUOTE_ALL, lineterminator='')
w.writerow(fields)
print(buf.getvalue())
" "${CSV_COLUMNS[@]}"
}

# =============================================================================
# HELPER: VERSIONSNORMALISIERUNG
# =============================================================================

# normalize_version "18.7.7" → "18.07.07"
normalize_version() {
    python3 -c "
v = '${1}'
if not v: exit()
parts = v.split('.')
print('.'.join(f'{int(p):02d}' if p.isdigit() else p for p in parts), end='')
"
}

# normalize_apple_versions "Apple iOS < 18.7.5" → "Apple iOS < 18.07.05"
normalize_apple_versions() {
    python3 - "${1}" <<'PYEOF'
import sys, re

def norm(v):
    return '.'.join(f'{int(p):02d}' if p.isdigit() else p for p in v.split('.'))

pat = (r'((?:Apple\s+)?(?:iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)'
       r'(?:\s+[A-Za-z][A-Za-z0-9._-]*){0,4}\s+(?:[<>=]+\s*)?)(\d+(?:\.\d+)*)')

print(re.sub(pat, lambda m: m.group(1) + norm(m.group(2)), sys.argv[1]), end='')
PYEOF
}

# =============================================================================
# HELPER: RELEVANT_VERSIONS-FILTER
# Gibt 0 zurück wenn relevant, 1 wenn nicht.
# =============================================================================
test_is_relevant_entry() {
    local betroffene="$1" behoben="$2"
    if (( ${#RELEVANT_VERSIONS[@]} == 0 )); then return 0; fi

    python3 - "${betroffene} ${behoben}" "${RELEVANT_VERSIONS[@]}" <<'PYEOF'
import sys, re

combined  = sys.argv[1]
relevant  = sys.argv[2:]

def norm(v):
    return '.'.join(f'{int(p):02d}' if p.isdigit() else p for p in v.split('.'))

rel_norm = [norm(r) for r in relevant]
found = re.findall(
    r'(?:iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)\s+(?:[<>=]+\s*)?(\d+(?:\.\d+)*)',
    combined)

for f in found:
    fn = norm(f)
    for rn in rel_norm:
        if fn == rn or fn.startswith(rn + '.'):
            sys.exit(0)
sys.exit(1)
PYEOF
}

# =============================================================================
# HELPER: MIN-FIX-BREAKDOWN
# Setzt globale Vars: _COMPACT _IOS18 _IOS26 _IPADOS18 _IPADOS26
# =============================================================================
get_min_fix_breakdown() {
    local fixed_pipe="$1"   # |-getrennter String der "Apple iOS/iPadOS X.Y"-Namen

    _COMPACT="" _IOS18="" _IOS26="" _IPADOS18="" _IPADOS26=""
    [[ -z "$fixed_pipe" ]] && return

    local result
    result=$(python3 - "$fixed_pipe" <<'PYEOF'
import sys, re

def norm(v):
    return '.'.join(f'{int(p):02d}' if p.isdigit() else p for p in v.split('.'))

names = [n.strip() for n in sys.argv[1].split('|') if n.strip()]
pat = re.compile(r'^Apple\s+(iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)\s+(\d+(?:\.\d+)*)$')

parts = []
ios18 = ios26 = ipados18 = ipados26 = ''

for name in names:
    m = pat.match(name)
    if not m: continue
    product, version = m.group(1), m.group(2)
    major = version.split('.')[0]
    nv = norm(version)
    parts.append(f'{product} {nv}')
    key = f'{product}/{major}'
    if key == 'iOS/18'    and not ios18:    ios18    = nv
    if key == 'iOS/26'    and not ios26:    ios26    = nv
    if key == 'iPadOS/18' and not ipados18: ipados18 = nv
    if key == 'iPadOS/26' and not ipados26: ipados26 = nv

compact = ', '.join(sorted(set(parts)))
print(f'{compact}\t{ios18}\t{ios26}\t{ipados18}\t{ipados26}')
PYEOF
)
    _COMPACT="${result%%	*}"
    local rest="${result#*	}"
    _IOS18="${rest%%	*}";    rest="${rest#*	}"
    _IOS26="${rest%%	*}";    rest="${rest#*	}"
    _IPADOS18="${rest%%	*}"; _IPADOS26="${rest#*	}"
}

# =============================================================================
# HELPER: GERMAN SUMMARY + RISK QUALITY
# =============================================================================
new_german_summary() {
    local s="${(L)1} ${(L)2}"   # lowercase concat

    [[ "$s" =~ 'crash[[:space:]]a[[:space:]]system[[:space:]]process|system[[:space:]]process.*crash' ]] \
        && print "Eine App kann unter Umständen einen Systemprozess zum Absturz bringen." && return
    [[ "$s" =~ 'access[[:space:]]notes[[:space:]]attachments|notes[[:space:]]attachments' ]] \
        && print "Eine App kann unter Umständen auf Notes-Anhänge zugreifen." && return
    [[ "$s" =~ 'out[[:space:]]of[[:space:]]bounds[[:space:]]write' ]] \
        && print "Ein Angreifer kann unter Umständen einen begrenzten Speicher-Schreibfehler auslösen." && return
    [[ "$s" =~ 'privileged[[:space:]]network[[:space:]]position|intercept[[:space:]]network[[:space:]]traffic' ]] \
        && print "Ein Angreifer in privilegierter Netzwerkposition kann unter Umständen Netzwerkverkehr abfangen." && return
    [[ "$s" =~ 'hide[[:space:]]ip[[:space:]]address|block[[:space:]]all[[:space:]]remote[[:space:]]content|load[[:space:]]remote[[:space:]]images|remote[[:space:]]content.*mail|mail[[:space:]]previews|lockdown[[:space:]]mode' ]] \
        && print "E-Mail-Inhalte können unter Umständen trotz aktivierter Schutzoptionen geladen werden." && return
    [[ "$s" =~ 'keychain' ]] \
        && print "Ein lokaler Angreifer kann unter Umständen auf Schlüsselbund-Inhalte zugreifen." && return
    [[ "$s" =~ 'same[[:space:]]origin[[:space:]]policy|cross-origin' ]] \
        && print "Manipulierter Webinhalt kann unter Umständen die Same-Origin-Sicherheitsgrenze umgehen." && return
    [[ "$s" =~ 'cross-site[[:space:]]scripting' ]] \
        && print "Der Besuch einer manipulierten Webseite kann unter Umständen Cross-Site-Scripting ermöglichen." && return
    [[ "$s" =~ 'script[[:space:]]message[[:space:]]handlers|other[[:space:]]origins' ]] \
        && print "Eine bösartige Webseite kann unter Umständen auf Schnittstellen anderer Web-Ursprünge zugreifen." && return
    [[ "$s" =~ 'outside[[:space:]]the[[:space:]]sandbox|web[[:space:]]content[[:space:]]sandbox' ]] \
        && print "Eine bösartige Webseite kann unter Umständen Sandbox-Grenzen für Webinhalte umgehen." && return
    [[ "$s" =~ 'leaked[[:space:]]dns[[:space:]]queries|private[[:space:]]relay' ]] \
        && print "Ein entfernter Angreifer kann unter Umständen DNS-Anfragen trotz Private Relay einsehen." && return
    [[ "$s" =~ 'access[[:space:]]protected[[:space:]]user[[:space:]]data|protected[[:space:]]user[[:space:]]data|access[[:space:]]user-sensitive|sensitive[[:space:]]data[[:space:]]logged|sensitive[[:space:]]contact|safari[[:space:]]history|deleted[[:space:]]notes|passkeys[[:space:]]without[[:space:]]authentication|private[[:space:]]browsing[[:space:]]tabs' ]] \
        && print "Eine App oder ein Angreifer kann unter Umständen auf geschützte oder sensible Nutzerdaten zugreifen." && return
    [[ "$s" =~ 'identifying[[:space:]]information[[:space:]]leaked|identify[[:space:]]what[[:space:]]other[[:space:]]app|installed[[:space:]]apps' ]] \
        && print "Eine App kann unter Umständen Informationen zu installierten Apps des Nutzers auslesen." && return
    [[ "$s" =~ 'observe[[:space:]]system-wide[[:space:]]network[[:space:]]connections' ]] \
        && print "Eine App kann unter Umständen systemweite Netzwerkverbindungen beobachten." && return
    [[ "$s" =~ 'monitor[[:space:]]keystrokes' ]] \
        && print "Eine App kann unter Umständen Tastatureingaben ohne Zustimmung überwachen." && return
    [[ "$s" =~ 'passcode.*read[[:space:]]aloud|voiceover' ]] \
        && print "Der Gerätecode kann unter Umständen über VoiceOver vorgelesen werden." && return
    [[ "$s" =~ 's/mime|encrypted[[:space:]]e-mail|encrypted[[:space:]]email' ]] \
        && print "Bei S/MIME-verschlüsselten E-Mails können unter Umständen Klartextinhalte offengelegt werden." && return
    [[ "$s" =~ 'bypass[[:space:]]privacy[[:space:]]preferences|bypass[[:space:]]certain[[:space:]]privacy' ]] \
        && print "Eine App kann unter Umständen Datenschutzeinstellungen umgehen." && return
    [[ "$s" =~ 'bypass[[:space:]]gatekeeper|gatekeeper[[:space:]]checks|file[[:space:]]quarantine[[:space:]]bypass' ]] \
        && print "Ein manipuliertes Disk-Image kann unter Umständen Gatekeeper-Prüfungen umgehen." && return
    [[ "$s" =~ 'bypass[[:space:]]signature[[:space:]]validation|signature[[:space:]]validation' ]] \
        && print "Eine bösartige App kann unter Umständen Signaturprüfungen umgehen." && return
    [[ "$s" =~ 'bypass[[:space:]]sandbox[[:space:]]restrictions|circumvent[[:space:]]sandbox|break[[:space:]]out[[:space:]]of[[:space:]]web[[:space:]]content[[:space:]]sandbox' ]] \
        && print "Eine App oder Webseite kann unter Umständen Sandbox-Beschränkungen umgehen." && return
    [[ "$s" =~ 'write[[:space:]]arbitrary[[:space:]]files|overwrite[[:space:]]arbitrary[[:space:]]files|read[[:space:]]arbitrary[[:space:]]files|delete[[:space:]]files|protected[[:space:]]system[[:space:]]files|protected[[:space:]]parts[[:space:]]of[[:space:]]the[[:space:]]file[[:space:]]system|access[[:space:]]arbitrary[[:space:]]files' ]] \
        && print "Eine App oder ein Angreifer kann unter Umständen Dateien lesen, verändern oder löschen, für die keine Berechtigung besteht." && return
    [[ "$s" =~ 'address[[:space:]]bar[[:space:]]spoofing|user[[:space:]]interface[[:space:]]spoofing|ui[[:space:]]spoofing' ]] \
        && print "Der Besuch einer manipulierten Webseite kann unter Umständen eine gefälschte Adresszeile anzeigen." && return
    [[ "$s" =~ 'fail[[:space:]]to[[:space:]]lock|persistently[[:space:]]fail[[:space:]]to[[:space:]]lock' ]] \
        && print "Ein Gerät kann unter Umständen dauerhaft nicht korrekt gesperrt werden." && return
    [[ "$s" =~ 'face[[:space:]]id' ]] \
        && print "Ein speziell präpariertes 3D-Modell kann unter Umständen eine Face-ID-Authentifizierung auslösen." && return
    [[ "$s" =~ 'app[[:space:]]transport[[:space:]]security' ]] \
        && print "Eine App kann unter Umständen App-Transport-Security-Vorgaben nicht korrekt durchsetzen." && return
    [[ "$s" =~ 'live[[:space:]]caller[[:space:]]id' ]] \
        && print "Informationen können unter Umständen trotz deaktivierter Live-Caller-ID-Erweiterung an diese gelangen." && return
    [[ "$s" =~ 'maliciously[[:space:]]crafted[[:space:]]usd[[:space:]]file|usd[[:space:]]file' ]] \
        && print "Eine manipulierte USD-Datei kann unter Umständen Speicherinhalte offenlegen." && return
    [[ "$s" =~ 'maliciously[[:space:]]crafted[[:space:]]audio[[:space:]]file' ]] \
        && print "Eine manipulierte Audiodatei kann unter Umständen Nutzerdaten offenlegen." && return
    [[ "$s" =~ 'unexpected[[:space:]]safari[[:space:]]crash' ]] \
        && print "Manipulierter Webinhalt kann unter Umständen Safari zum Absturz bringen." && return
    if [[ "$s" =~ 'terminate[[:space:]]the[[:space:]]process' ]]; then
        if [[ "$s" =~ 'audio|media' ]]; then
            print "Eine manipulierte Mediendatei kann unter Umständen einen Prozessabsturz verursachen." && return
        fi
        print "Manipulierte Inhalte können unter Umständen einen Prozessabsturz verursachen." && return
    fi
    [[ "$s" =~ 'content[[:space:]]security[[:space:]]policy|csp' ]] \
        && print "Manipulierter Webinhalt kann unter Umständen eine wichtige Web-Sicherheitsregel umgehen." && return
    if [[ "$s" =~ 'unexpected[[:space:]]process[[:space:]]crash|process[[:space:]]crash' ]]; then
        if [[ "$s" =~ 'web[[:space:]]content|website|webkit|webrtc|safari' ]]; then
            print "Manipulierter Webinhalt kann unter Umständen einen Prozess- oder Browserabsturz verursachen." && return
        fi
        print "Manipulierte Inhalte können unter Umständen einen Prozessabsturz verursachen." && return
    fi
    [[ "$s" =~ 'malicious[[:space:]]iframe.*download[[:space:]]settings|iframe.*download[[:space:]]settings' ]] \
        && print "Ein manipuliertes eingebettetes Webelement kann unter Umständen Download-Einstellungen einer anderen Webseite missbrauchen." && return
    [[ "$s" =~ 'leak[[:space:]]sensitive[[:space:]]kernel[[:space:]]state' ]] \
        && print "Eine App kann unter Umständen sensible Kernel-Zustandsinformationen offenlegen." && return
    [[ "$s" =~ 'maliciously[[:space:]]crafted[[:space:]]website.*leak[[:space:]]sensitive[[:space:]]data|website[[:space:]]may[[:space:]]leak[[:space:]]sensitive[[:space:]]data' ]] \
        && print "Der Besuch einer manipulierten Webseite kann unter Umständen sensible Daten offenlegen." && return
    [[ "$s" =~ 'corrupt[[:space:]]process[[:space:]]memory' ]] \
        && print "Speicherfehler können unter Umständen sicherheitsrelevante Auswirkungen haben." && return

    # Schadcodeausführung
    if [[ "$s" =~ 'arbitrary[[:space:]]code[[:space:]]execution|execute[[:space:]]arbitrary[[:space:]]code|code[[:space:]]execution' ]]; then
        if   [[ "$s" =~ 'web[[:space:]]content|html|safari|webkit' ]]; then
            print "Manipulierter Webinhalt kann Schadcodeausführung ermöglichen." && return
        elif [[ "$s" =~ 'image|photo|picture' ]]; then
            print "Ein manipuliertes Bild kann Schadcodeausführung ermöglichen." && return
        elif [[ "$s" =~ 'file|media|document' ]]; then
            print "Eine manipulierte Datei kann Schadcodeausführung ermöglichen." && return
        fi
        print "Manipulierte Inhalte können Schadcodeausführung ermöglichen." && return
    fi

    [[ "$s" =~ 'gain[[:space:]]root[[:space:]]privileges|root[[:space:]]privileges' ]] \
        && print "Eine App kann unter Umständen höchste Systemrechte erlangen." && return
    [[ "$s" =~ 'local[[:space:]]attacker.*elevate.*privileges|elevate[[:space:]]their[[:space:]]privileges' ]] \
        && print "Ein lokaler Angreifer kann unter Umständen seine Rechte auf dem Gerät erweitern." && return
    [[ "$s" =~ 'gain[[:space:]]elevated[[:space:]]privileges|elevate[[:space:]]privileges|privilege[[:space:]]escalation|increase[[:space:]]privileges' ]] \
        && print "Eine App kann unter Umständen erweiterte Rechte auf dem Gerät erlangen." && return
    [[ "$s" =~ 'kernel[[:space:]]privileges' ]] \
        && print "Eine App kann unter Umständen Rechte im Betriebssystem-Kernel erlangen." && return
    [[ "$s" =~ 'write[[:space:]]kernel[[:space:]]memory|modify[[:space:]]kernel[[:space:]]memory' ]] \
        && print "Eine App kann unter Umständen Speicherbereiche des Betriebssystem-Kernels verändern." && return
    [[ "$s" =~ 'read[[:space:]]kernel[[:space:]]memory|disclose[[:space:]]kernel[[:space:]]memory|determine[[:space:]]kernel[[:space:]]memory' ]] \
        && print "Eine App kann unter Umständen Speicherinhalte des Betriebssystem-Kernels auslesen." && return
    [[ "$s" =~ 'break[[:space:]]out[[:space:]]of[[:space:]]its[[:space:]]sandbox|escape[[:space:]]its[[:space:]]sandbox|sandbox[[:space:]]escape' ]] \
        && print "Eine bösartige App kann unter Umständen aus ihrer Sandbox ausbrechen." && return
    [[ "$s" =~ 'bypass[[:space:]]pointer[[:space:]]authentication|bypass.*pac' ]] \
        && print "Eine App kann unter Umständen einen Schutzmechanismus gegen Speicherangriffe umgehen." && return
    [[ "$s" =~ 'sensitive[[:space:]]user[[:space:]]data|sensitive[[:space:]]user[[:space:]]information|access[[:space:]]sensitive|sensitive[[:space:]]information|disclose[[:space:]]sensitive' ]] \
        && print "Eine App oder ein Angreifer kann unter Umständen auf sensible Nutzerdaten zugreifen." && return
    [[ "$s" =~ 'private[[:space:]]information|personal[[:space:]]information' ]] \
        && print "Eine App oder ein Angreifer kann unter Umständen private Informationen offenlegen." && return
    [[ "$s" =~ 'location[[:space:]]information|precise[[:space:]]location|user[[:space:]]location' ]] \
        && print "Eine App kann unter Umständen Standortinformationen offenlegen." && return
    [[ "$s" =~ 'contacts|photos|calendar|microphone|camera' ]] \
        && print "Eine App kann unter Umständen auf Kontakte, Fotos, Kalender oder Kamera zugreifen." && return
    [[ "$s" =~ 'fingerprint|tracking|track[[:space:]]user' ]] \
        && print "Eine App oder ein Webinhalt kann unter Umständen Nutzer wiedererkennen oder verfolgen." && return
    [[ "$s" =~ 'spoofing|spoofed' ]] \
        && print "Eine bösartige Komponente kann unter Umständen eine Identität oder Quelle vortäuschen." && return
    [[ "$s" =~ 'denial[[:space:]]of[[:space:]]service|denial-of-service' ]] \
        && print "Manipulierte Inhalte können unter Umständen einen Denial-of-Service auslösen." && return
    [[ "$s" =~ 'unexpected[[:space:]]app[[:space:]]termination|unexpected[[:space:]]system[[:space:]]termination|app[[:space:]]termination|app[[:space:]]crash|system[[:space:]]crash|device[[:space:]]may[[:space:]]restart' ]] \
        && print "Manipulierte Inhalte können unter Umständen einen unerwarteten App- oder Systemabbruch verursachen." && return
    [[ "$s" =~ 'memory[[:space:]]corruption|out-of-bounds[[:space:]]read|out-of-bounds[[:space:]]write|use[[:space:]]after[[:space:]]free|integer[[:space:]]overflow|integer[[:space:]]underflow' ]] \
        && print "Speicherfehler können unter Umständen sicherheitsrelevante Auswirkungen haben." && return
    [[ "$s" =~ 'local[[:space:]]network' ]] \
        && print "Ein Angreifer im lokalen Netzwerk kann unter Umständen sicherheitsrelevante Auswirkungen erzielen." && return
    [[ "$s" =~ 'physical[[:space:]]access' ]] \
        && print "Ein Angreifer mit physischem Zugriff kann unter Umständen sicherheitsrelevante Auswirkungen erzielen." && return
    print ""
}

new_risk_quality() {
    local s="${(L)1} ${(L)2}"

    # Spezialfälle
    [[ "$s" =~ 'access[[:space:]]notes[[:space:]]attachments|notes[[:space:]]attachments' ]] && print "relevant" && return
    [[ "$s" =~ 'maliciously[[:space:]]crafted[[:space:]]website.*leak[[:space:]]sensitive[[:space:]]data|website[[:space:]]may[[:space:]]leak[[:space:]]sensitive[[:space:]]data' ]] && print "relevant" && return
    [[ "$s" =~ 'crash[[:space:]]a[[:space:]]system[[:space:]]process|system[[:space:]]process.*crash|out[[:space:]]of[[:space:]]bounds[[:space:]]write' ]] && print "mittel" && return

    # Sehr relevant
    if [[ "$s" =~ 'arbitrary[[:space:]]code[[:space:]]execution|execute[[:space:]]arbitrary[[:space:]]code|code[[:space:]]execution|kernel[[:space:]]privileges|root[[:space:]]privileges|gain[[:space:]]root|kernel[[:space:]]memory|sandbox[[:space:]]escape|escape[[:space:]]its[[:space:]]sandbox|break[[:space:]]out[[:space:]]of[[:space:]]its[[:space:]]sandbox|break[[:space:]]out[[:space:]]of[[:space:]]web[[:space:]]content[[:space:]]sandbox|bypass[[:space:]]pointer[[:space:]]authentication|bypass[[:space:]]gatekeeper|gatekeeper[[:space:]]checks|file[[:space:]]quarantine[[:space:]]bypass|bypass[[:space:]]signature[[:space:]]validation|actively[[:space:]]exploited|passkeys[[:space:]]without[[:space:]]authentication|face[[:space:]]id|arbitrary[[:space:]]files|protected[[:space:]]system[[:space:]]files|protected[[:space:]]parts[[:space:]]of[[:space:]]the[[:space:]]file[[:space:]]system|delete[[:space:]]files|overwrite[[:space:]]arbitrary[[:space:]]files|read[[:space:]]arbitrary[[:space:]]files|bypass[[:space:]]sandbox[[:space:]]restrictions|circumvent[[:space:]]sandbox|elevate.*privileges|local[[:space:]]attacker.*privileges' ]]; then
        print "sehr relevant" && return
    fi

    # Relevant
    if [[ "$s" =~ 'privileged[[:space:]]network[[:space:]]position|intercept[[:space:]]network[[:space:]]traffic|hide[[:space:]]ip[[:space:]]address|load[[:space:]]remote[[:space:]]images|remote[[:space:]]content|mail[[:space:]]previews|lockdown[[:space:]]mode|keychain|same[[:space:]]origin[[:space:]]policy|cross-origin|cross-site[[:space:]]scripting|other[[:space:]]origins|outside[[:space:]]the[[:space:]]sandbox|leaked[[:space:]]dns[[:space:]]queries|private[[:space:]]relay|protected[[:space:]]user[[:space:]]data|access[[:space:]]user-sensitive|sensitive[[:space:]]data[[:space:]]logged|sensitive[[:space:]]contact|safari[[:space:]]history|deleted[[:space:]]notes|private[[:space:]]browsing[[:space:]]tabs|identifying[[:space:]]information|identify[[:space:]]what[[:space:]]other[[:space:]]app|installed[[:space:]]apps|observe[[:space:]]system-wide|monitor[[:space:]]keystrokes|passcode|voiceover|s/mime|encrypted[[:space:]]e-mail|encrypted[[:space:]]email|address[[:space:]]bar[[:space:]]spoofing|user[[:space:]]interface[[:space:]]spoofing|fail[[:space:]]to[[:space:]]lock|app[[:space:]]transport[[:space:]]security|live[[:space:]]caller[[:space:]]id|sensitive[[:space:]]user[[:space:]]data|sensitive[[:space:]]information|disclose[[:space:]]sensitive|user-sensitive[[:space:]]data|leak[[:space:]]sensitive[[:space:]]kernel|lock[[:space:]]screen|content[[:space:]]security[[:space:]]policy|private[[:space:]]information|personal[[:space:]]information|location[[:space:]]information|precise[[:space:]]location|contacts|photos|calendar|microphone|camera|fingerprinting|tracking|spoofing|spoofed' ]]; then
        print "relevant" && return
    fi

    [[ "$s" =~ 'denial[[:space:]]of[[:space:]]service|denial-of-service' ]] && print "mittel" && return
    [[ "$s" =~ 'unexpected.*crash|process[[:space:]]crash|terminate[[:space:]]the[[:space:]]process|unexpected.*termination|app[[:space:]]termination|app[[:space:]]crash|system[[:space:]]crash|device[[:space:]]may[[:space:]]restart' ]] && print "mittel" && return
    [[ "$s" =~ 'memory[[:space:]]corruption|corrupt[[:space:]]process[[:space:]]memory|out-of-bounds|use[[:space:]]after[[:space:]]free|integer[[:space:]]overflow|integer[[:space:]]underflow' ]] && print "mittel" && return
    [[ "$s" =~ 'local[[:space:]]network|physical[[:space:]]access' ]] && print "mittel" && return

    print "prüfen"
}

# =============================================================================
# WID-API
# =============================================================================
invoke_wid_api() {
    curl --silent --fail --show-error --max-time 30 \
        -H "Accept: */*" \
        -H "X-Api-Key: ${WID_API_KEY}" \
        "$1"
}

# Schreibt Kandidaten als JSONL nach stdout
get_wid_candidates() {
    local days_back=$1 max_advisories=$2 only_subscribed=$3
    local title_regex="$4" page_size=$5

    local from_date
    from_date=$(python3 -c "
from datetime import datetime, timedelta, timezone
dt = datetime.now(timezone.utc) - timedelta(days=$days_back)
print(dt.strftime('%Y-%m-%dT00:00:00.000+00:00'))
")
    local encoded_from
    encoded_from=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$from_date")

    print "Suche WID Security Advisories..." >&2
    print "Zeitraum ab:     $from_date" >&2
    print "OnlySubscribed:  $only_subscribed" >&2
    print "MaxAdvisories:   $max_advisories" >&2
    print "" >&2

    local page=0 total=0 limit_reached=false

    while true; do
        local uri="https://wid.lsi.bayern.de/content/public/securityAdvisory?sort=published%2Cdesc&size=${page_size}&page=${page}&aboFilter=${only_subscribed}&publishedFromFilter=${encoded_from}"

        local resp
        resp=$(invoke_wid_api "$uri") || { print "FEHLER: WID-API nicht erreichbar." >&2; return 1; }

        local total_pages
        total_pages=$(print -r -- "$resp" | jq -r '.totalPages // 1')

        local resp_tmp="$WORK_DIR/wid_resp_${page}.json"
        print -r -- "$resp" > "$resp_tmp"

        local matched
        matched=$(python3 - "$title_regex" "$max_advisories" "$total" "$resp_tmp" <<'PYEOF'
import sys, json, re

data    = json.load(open(sys.argv[4]))
tregex  = sys.argv[1]
cap     = int(sys.argv[2])
already = int(sys.argv[3])
count   = already

for item in data.get('content', []):
    if count >= cap: break
    clf   = item.get('classification', '')
    title = item.get('title', '')
    if clf in ('hoch', 'kritisch') and re.search(tregex, title, re.IGNORECASE):
        print(json.dumps({
            'LsiId':          item.get('name', ''),
            'Uuid':           item.get('uuid', ''),
            'Published':      item.get('published', ''),
            'Classification': clf,
            'Title':          title,
            'NoPatch':        str(item.get('noPatch', '')).lower(),
            'Exploit':        str(item.get('exploit', '')).lower(),
        }, ensure_ascii=False))
        count += 1
PYEOF
)

        local added=0
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            print -r -- "$line"
            (( added++ ))
            (( total++ ))
            (( total >= max_advisories )) && limit_reached=true && break
        done <<< "$matched"

        print "Seite $page / $(( total_pages - 1 )): Kandidaten bisher $total" >&2

        [[ "$limit_reached" == true ]] && break
        (( page + 1 >= total_pages )) && break
        (( page++ ))
    done
}

# =============================================================================
# APPLE-SEITE PARSEN
# Gibt JSONL nach stdout: {component, impact, description, cves, url}
# =============================================================================
parse_apple_page() {
    local url="$1"
    local html_tmp
    html_tmp=$(mktemp /tmp/lsi_apple_XXXXXX.html)
    curl --silent --fail --max-time 30 -L "$url" > "$html_tmp" || { rm -f "$html_tmp"; return 1; }
    python3 - "$url" "$html_tmp" <<'PYEOF'
import sys, re, json
from html import unescape

url = sys.argv[1]
with open(sys.argv[2]) as _f: raw = _f.read()

for tag, repl in [
    (r'<br\s*/?>', '\n'), (r'</(?:p|h[23]|li)>', '\n'),
]:
    raw = re.sub(tag, repl, raw, flags=re.IGNORECASE)
raw = re.sub(r'<[^>]+>', '', raw)
text = unescape(raw)

lines = [l.strip() for l in text.split('\n') if l.strip()]

SKIP    = re.compile(r'^(Impact|Description|Available for|CVE-|Released|About|'
                     r'This document|Entry added|Entry updated|Published Date|Helpful)',
                     re.IGNORECASE)
IS_COMP = re.compile(r'^[A-Za-z0-9 /()\._-]{2,60}$')

comp = impact = desc = None
cves = []
entries = []

def emit():
    if comp and impact:
        entries.append({'component': comp, 'impact': impact,
                        'description': desc or '', 'cves': cves[:], 'url': url})

for line in lines:
    if IS_COMP.match(line) and not SKIP.search(line):
        emit(); comp, impact, desc, cves = line, None, None, []; continue
    m = re.match(r'^Impact:\s*(.+)$',      line); impact = m.group(1) if m else impact; (m and None) or None
    if m: impact = m.group(1); continue
    m = re.match(r'^Description:\s*(.+)$', line)
    if m: desc = m.group(1); continue
    cves += re.findall(r'CVE-\d{4}-\d{4,7}', line)

emit()

for e in entries:
    e['cves'] = ', '.join(sorted(set(e['cves'])))
    print(json.dumps(e, ensure_ascii=False))
PYEOF
    local rc=$?
    rm -f "$html_tmp"
    return $rc
}

# =============================================================================
# LSI-DETAILS — schreibt CSV-Datenzeilen nach stdout (kein Header)
# Fehler → return 1
# =============================================================================
get_lsi_apple_entries() {
    local lsi_id="$1" uuid="$2" exploit="$3" no_patch="$4"

    # UUID per Name-Lookup wenn nötig
    if [[ -z "$uuid" || "$uuid" == "null" ]]; then
        local enc
        enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$lsi_id")
        uuid=$(invoke_wid_api \
            "https://wid.lsi.bayern.de/content/public/securityAdvisory/uuid-by-name/${enc}" \
            | tr -d '"') || { print "UUID-Lookup fehlgeschlagen: $lsi_id" >&2; return 1; }
    fi

    local detail
    detail=$(invoke_wid_api "https://wid.lsi.bayern.de/content/public/content/${uuid}") \
        || { print "Detail-Abruf fehlgeschlagen: $lsi_id" >&2; return 1; }

    [[ "$KEEP_RAW_JSON" == true ]] && print -r -- "$detail" > "${OUT_DIR}/${lsi_id}.json"

    local lsi_titel lsi_risiko lsi_initialdatum lsi_stand
    lsi_titel=$(print -r -- "$detail" | jq -r '.properties.title // ""')
    lsi_risiko=$(print -r -- "$detail" | jq -r '.properties.risiko // ""')
    lsi_initialdatum=$(print -r -- "$detail" | jq -r '.properties.initialreleasedate // ""')
    lsi_stand=$(print -r -- "$detail" | jq -r '.properties.currentreleasedate // ""')

    local betroffene_raw behoben_raw
    betroffene_raw=$(print -r -- "$detail" | jq -r '
        [.children[] | select(.name=="productReferenceListe") | .children[]
         | select(.properties.name | contains("<")) | .properties.name]
        | sort | unique | join(" | ")')
    behoben_raw=$(print -r -- "$detail" | jq -r '
        [.children[] | select(.name=="productReferenceListe") | .children[]
         | select(.properties.id | endswith("-fixed")) | .properties.name]
        | sort | unique | join("|")')

    local apple_urls
    apple_urls=$(print -r -- "$detail" | jq -r '
        [.children[] | select(.name=="documentReferenceListe") | .children[]
         | select(.properties.url | contains("support.apple.com")) | .properties.url]
        | sort | unique | .[]')

    if [[ -z "$apple_urls" ]]; then
        print "Keine Apple-Support-URLs in $lsi_id." >&2; return 1
    fi

    local betroffene_norm behoben_norm
    betroffene_norm=$(normalize_apple_versions "$betroffene_raw")
    # Für normalize: | durch Leerzeichen ersetzen, dann wieder zusammensetzen
    behoben_norm=$(normalize_apple_versions "$(print -r -- "$behoben_raw" | tr '|' '\n' | \
        while IFS= read -r n; do normalize_apple_versions "$n"; print ""; done | \
        paste -sd '|' -)")

    get_min_fix_breakdown "$behoben_raw"

    print "" >&2
    print "LSI-ID:  $lsi_id" >&2
    print "Titel:   $lsi_titel" >&2
    print "Risiko:  $lsi_risiko" >&2
    print "Apple-URLs:" >&2
    print -r -- "$apple_urls" | while IFS= read -r u; do print "  $u" >&2; done
    print "" >&2

    # Alle Apple-Seiten parsen → JSONL sammeln
    local parsed_jsonl="$WORK_DIR/parsed_${lsi_id}.jsonl"
    : > "$parsed_jsonl"

    print -r -- "$apple_urls" | while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        print "Lese Apple-Seite: $url" >&2
        local page_entries
        page_entries=$(parse_apple_page "$url") || { print "Fehler: $url" >&2; continue; }
        local cnt
        cnt=$(print -r -- "$page_entries" | grep -c . 2>/dev/null)
        print "Einträge: $cnt" >&2
        print "" >&2
        print -r -- "$page_entries" >> "$parsed_jsonl"
    done

    # Deduplizierung + CSV-Zeilen erzeugen (python3 erledigt beides)
    python3 - \
        "$lsi_id" "$lsi_titel" "$lsi_risiko" \
        "$exploit" "$no_patch" \
        "$lsi_initialdatum" "$lsi_stand" \
        "$betroffene_norm" "$behoben_norm" \
        "$_COMPACT" "$_IOS18" "$_IOS26" "$_IPADOS18" "$_IPADOS26" \
        "$parsed_jsonl" <<'PYEOF'
import sys, json, csv
from io import StringIO

(lsi_id, lsi_titel, lsi_risiko, exploit, no_patch,
 lsi_init, lsi_stand, betroffene, behoben,
 mf_compact, mf_ios18, mf_ios26, mf_ipados18, mf_ipados26) = sys.argv[1:15]

entries = [json.loads(l) for l in open(sys.argv[15]) if l.strip()]
if not entries: sys.exit(0)

# Deduplizierung: key=(component, cves) → merge AppleUrls
groups = {}
for e in entries:
    key = (e['component'], e['cves'])
    if key not in groups:
        groups[key] = dict(e); groups[key]['urls'] = [e['url']]
    elif e['url'] not in groups[key]['urls']:
        groups[key]['urls'].append(e['url'])

for e in groups.values():
    apple_url = ' | '.join(sorted(set(e['urls'])))
    row = [
        lsi_id, lsi_titel, lsi_risiko, exploit, no_patch,
        lsi_init, lsi_stand, betroffene, behoben,
        mf_compact, mf_ios18, mf_ios26, mf_ipados18, mf_ipados26,
        'Apple Security Advisory', apple_url,
        e['component'], e['impact'], e['description'], e['cves'],
        '',  # Qualitaet — wird unten gesetzt
        '',  # KurzbeschreibungDE — wird unten gesetzt
    ]
    buf = StringIO()
    w = csv.writer(buf, delimiter=';', quoting=csv.QUOTE_ALL, lineterminator='')
    w.writerow(row)
    print(buf.getvalue())
PYEOF
}

# =============================================================================
# QUALITÄT + KURZBESCHREIBUNG in bestehende CSV-Zeile schreiben
# Liest CSV-Zeilen von stdin, schreibt ergänzte Zeilen nach stdout
# =============================================================================
enrich_quality() {
    while IFS= read -r csv_row; do
        [[ -z "$csv_row" ]] && continue

        # Impact (Feld 17) und Description (Feld 18) extrahieren
        local impact desc
        impact=$(print -r -- "$csv_row" | python3 -c "
import sys,csv
r=next(csv.reader(sys.stdin,delimiter=';'))
print(r[17] if len(r)>17 else '',end='')")
        desc=$(print -r -- "$csv_row" | python3 -c "
import sys,csv
r=next(csv.reader(sys.stdin,delimiter=';'))
print(r[18] if len(r)>18 else '',end='')")

        local qual kurz
        qual=$(new_risk_quality "$impact" "$desc")
        kurz=$(new_german_summary "$impact" "$desc")

        # Letzten zwei Felder ersetzen
        local row_tmp
        row_tmp=$(mktemp /tmp/lsi_row_XXXXXX.txt)
        print -r -- "$csv_row" > "$row_tmp"
        python3 - "$qual" "$kurz" "$row_tmp" <<'PYEOF'
import sys, csv
from io import StringIO
qual, kurz = sys.argv[1], sys.argv[2]
row = next(csv.reader(open(sys.argv[3]), delimiter=';'))
if len(row) >= 22:
    row[-2] = qual; row[-1] = kurz
buf = StringIO()
csv.writer(buf, delimiter=';', quoting=csv.QUOTE_ALL, lineterminator='').writerow(row)
print(buf.getvalue())
PYEOF
        rm -f "$row_tmp"
    done
}

# =============================================================================
# MERGE BESTEHENDE + NEUE EINTRÄGE
# Schlüssel: LsiId|Komponente|CVEs — neue überschreiben bestehende
# Liest neue von stdin; bestehende aus $1
# =============================================================================
merge_with_existing() {
    local existing_csv="$1" new_csv="$2"
    python3 - "$existing_csv" "$new_csv" <<'PYEOF'
import sys, csv
from io import StringIO

existing_path = sys.argv[1]

with open(existing_path, encoding='utf-8', newline='') as f:
    reader = csv.DictReader(f, delimiter=';')
    fieldnames = reader.fieldnames
    existing = list(reader)

new_rows = list(csv.DictReader(open(sys.argv[2], encoding='utf-8', newline=''), delimiter=';'))

merged = {}
for r in existing:
    k = f"{r.get('LsiId','')}|{r.get('Komponente','')}|{r.get('CVEs','')}"
    merged[k] = r
for r in new_rows:
    k = f"{r.get('LsiId','')}|{r.get('Komponente','')}|{r.get('CVEs','')}"
    merged[k] = r

w = csv.DictWriter(sys.stdout, fieldnames=fieldnames, delimiter=';',
                   quoting=csv.QUOTE_ALL, lineterminator='\n')
w.writeheader()
w.writerows(merged.values())
PYEOF
}

# =============================================================================
# BEREINIGUNG: Einträge ohne Treffer in RELEVANT_VERSIONS entfernen
# =============================================================================
prune_by_relevant_versions() {
    local input_csv="$1"
    python3 - "$input_csv" "${RELEVANT_VERSIONS[@]}" <<'PYEOF'
import sys, csv, re

path     = sys.argv[1]
relevant = sys.argv[2:]

def norm(v):
    return '.'.join(f'{int(p):02d}' if p.isdigit() else p for p in v.split('.'))

rel_norm = [norm(r) for r in relevant]

def ok(betroffene, behoben):
    if not rel_norm: return True
    found = re.findall(
        r'(?:iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)\s+(?:[<>=]+\s*)?(\d+(?:\.\d+)*)',
        f'{betroffene} {behoben}')
    for f in found:
        fn = norm(f)
        for rn in rel_norm:
            if fn == rn or fn.startswith(rn + '.'): return True
    return False

with open(path, encoding='utf-8', newline='') as f:
    reader = csv.DictReader(f, delimiter=';')
    rows = [r for r in reader if ok(r.get('BetroffeneVersionen',''), r.get('BehobenDurch',''))]
    fn = reader.fieldnames

before = sum(1 for _ in open(path, encoding='utf-8').readlines()) - 1
print(f'Bereinigung: {before} → {len(rows)} Einträge', file=sys.stderr)

w = csv.DictWriter(sys.stdout, fieldnames=fn, delimiter=';',
                   quoting=csv.QUOTE_ALL, lineterminator='\n')
w.writeheader()
w.writerows(rows)
PYEOF
}

# =============================================================================
# MANAGEMENT REPORT
# =============================================================================
export_management_report() {
    local gesamt_csv="$1" report_csv="$2"
    python3 - "$gesamt_csv" "$report_csv" <<'PYEOF'
import sys, csv, re
from collections import defaultdict

gesamt_csv, report_csv = sys.argv[1], sys.argv[2]

with open(gesamt_csv, encoding='utf-8', newline='') as f:
    rows = list(csv.DictReader(f, delimiter=';'))

if not rows: sys.exit(0)

groups = defaultdict(list)
for r in rows: groups[r['LsiId']].append(r)

REPORT_FIELDS = [
    'LsiId','LsiTitel','LsiRisiko','LsiInitialdatum','LsiStand',
    'BetroffeneVersionen','BehobenDurch',
    'AppleUrlAnzahl','AppleUrls','CveAnzahl','EintraegeGesamt',
    'SehrRelevant','Relevant','Mittel','Pruefen',
    'Schwerpunkte','SehrRelevanteBeispiele','Kurzfazit',
]

def themes(rows):
    t = ' '.join(
        r.get('KurzbeschreibungDE','') + ' ' +
        r.get('ImpactOriginal','')     + ' ' +
        r.get('DescriptionOriginal','') for r in rows).lower()
    out = []
    if re.search(r'schadcode|codeausf|arbitrary code|execute arbitrary', t): out.append('Schadcodeausführung')
    if re.search(r'systemrechte|root|rechte|privileg|privilege|kernel priv', t): out.append('Rechteausweitung')
    if re.search(r'sandbox|gatekeeper|quarant|schutzmechanismus|same-origin|csp|pointer auth', t): out.append('Umgehung von Schutzmechanismen')
    if re.search(r'nutzerdaten|private info|sensitive|keychain|standort|location|dns|network traffic|mail', t): out.append('Informationsabfluss / Datenschutz')
    if re.search(r'denial|absturz|crash|termination|speicherfehler|memory corruption', t): out.append('Absturz / Denial of Service')
    if re.search(r'webkit|webinhalt|website|safari|cross-site', t): out.append('Web/Safari/WebKit')
    if re.search(r'lokalen netzwerk|local network|network', t): out.append('Netzwerk')
    return sorted(set(out))

def get_cves(rows):
    cves = set()
    for r in rows:
        cves.update(re.findall(r'CVE-\d{4}-\d{4,7}', r.get('CVEs','')))
    return sorted(cves)

report_rows = []
for lsi_id in sorted(groups):
    r = groups[lsi_id]; first = r[0]
    urls = sorted(set(u.strip() for row in r for u in row.get('AppleUrl','').split('|') if u.strip()))
    cves = get_cves(r)
    sehr = sum(1 for x in r if x.get('Qualitaet') == 'sehr relevant')
    rel  = sum(1 for x in r if x.get('Qualitaet') == 'relevant')
    mit  = sum(1 for x in r if x.get('Qualitaet') == 'mittel')
    pru  = sum(1 for x in r if x.get('Qualitaet') == 'prüfen')
    th   = themes(r)
    bsp  = list(dict.fromkeys(
        x.get('KurzbeschreibungDE','') for x in r
        if x.get('Qualitaet')=='sehr relevant' and x.get('KurzbeschreibungDE','').strip()
    ))[:5]
    pru_txt = f' {pru} Einträge müssen fachlich nachgeprüft werden.' if pru else ''
    th_txt  = ', '.join(th) if th else 'mehrere unterschiedliche Schwachstellenarten'
    fazit = (f"Die Meldung ist vom LSI als '{first.get('LsiRisiko','')}' eingestuft und betrifft "
             f"{first.get('BetroffeneVersionen','')}. Behoben durch: {first.get('BehobenDurch','')}. "
             f"Enthalten sind {sehr} sehr relevante, {rel} relevante und {mit} mittlere "
             f"Schwachstelleneinträge. Schwerpunkte: {th_txt}.{pru_txt}")
    report_rows.append({
        'LsiId': lsi_id, 'LsiTitel': first.get('LsiTitel',''),
        'LsiRisiko': first.get('LsiRisiko',''),
        'LsiInitialdatum': first.get('LsiInitialdatum',''),
        'LsiStand': first.get('LsiStand',''),
        'BetroffeneVersionen': first.get('BetroffeneVersionen',''),
        'BehobenDurch': first.get('BehobenDurch',''),
        'AppleUrlAnzahl': len(urls), 'AppleUrls': ' | '.join(urls),
        'CveAnzahl': len(cves), 'EintraegeGesamt': len(r),
        'SehrRelevant': sehr, 'Relevant': rel, 'Mittel': mit, 'Pruefen': pru,
        'Schwerpunkte': ' | '.join(th),
        'SehrRelevanteBeispiele': ' | '.join(bsp),
        'Kurzfazit': fazit,
    })

with open(report_csv, 'w', encoding='utf-8', newline='') as f:
    w = csv.DictWriter(f, fieldnames=REPORT_FIELDS, delimiter=';', quoting=csv.QUOTE_ALL)
    w.writeheader(); w.writerows(report_rows)

print(f'{len(report_rows)} LSIs im Report')
PYEOF
}

# =============================================================================
# HAUPTLAUF
# =============================================================================
print "LSI-Apple-Auswertung v5.2 (macOS)"
print "----------------------------------"
print ""

# 1) Vorhandene Gesamtauswertung suchen
EXISTING_FILE=""
IS_FIRST_RUN=true

if [[ "$FORCE_FULL_RUN" == false ]]; then
    EXISTING_FILE=$(find "$OUT_DIR" -maxdepth 1 -name "LSI-Apple-Gesamtauswertung_*.csv" \
        ! -name "*Fehler*" 2>/dev/null | sort | tail -1)
    if [[ -n "$EXISTING_FILE" ]]; then
        local_row_count=$(tail -n +2 "$EXISTING_FILE" | grep -c . 2>/dev/null || print 0)
        (( local_row_count > 0 )) && IS_FIRST_RUN=false
    fi
fi

# 2) Effektive Parameter bestimmen
EFFECTIVE_DAYS=$DAYS_BACK
EFFECTIVE_MAX=$MAX_ADVISORIES

if [[ "$IS_FIRST_RUN" == true ]]; then
    (( EFFECTIVE_MAX < 100 )) && EFFECTIVE_MAX=100
    print "Modus: ERSTLAUF"
    print "Deckel: $EFFECTIVE_MAX"
else
    print "Modus: FOLGELAUF"
    print "Vorhandene Datei:  $EXISTING_FILE"
    print "Einträge Bestand:  $local_row_count"

    newest_stand=""
    newest_stand=$(tail -n +2 "$EXISTING_FILE" | python3 -c "
import sys, csv
from datetime import datetime
rows = list(csv.DictReader(sys.stdin, delimiter=';'))
dates = []
for r in rows:
    try: dates.append(datetime.fromisoformat(r.get('LsiStand','')))
    except: pass
if dates: print(max(dates).strftime('%Y-%m-%d'))
" 2>/dev/null)

    if [[ -n "$newest_stand" ]]; then
        print "Neuester LsiStand: $newest_stand"
        days_since=""
        auto_days=""
        days_since=$(python3 -c "
from datetime import datetime
import math
print(math.ceil((datetime.now() - datetime.fromisoformat('$newest_stand')).total_seconds()/86400))")
        auto_days=$(( days_since + 7 ))
        if (( auto_days < EFFECTIVE_DAYS )); then
            print "DaysBack reduziert auf: $auto_days (war $EFFECTIVE_DAYS)"
            EFFECTIVE_DAYS=$auto_days
        fi
    fi
fi

print ""
print "RELEVANT_VERSIONS: ${RELEVANT_VERSIONS[*]}"
print ""

# 3) WID-Abfrage
CANDIDATES_JSONL="$WORK_DIR/candidates.jsonl"
get_wid_candidates \
    "$EFFECTIVE_DAYS" "$EFFECTIVE_MAX" \
    "$ONLY_SUBSCRIBED" "$TITLE_REGEX" "$PAGE_SIZE" \
    > "$CANDIDATES_JSONL"

candidate_count=$(grep -c . "$CANDIDATES_JSONL" 2>/dev/null || print 0)
print ""

if (( candidate_count == 0 )); then
    print "Keine passenden WID-Advisories gefunden."
    if [[ "$IS_FIRST_RUN" == true ]]; then
        print "Erstlauf ohne Treffer — Abbruch." >&2; exit 1
    fi
else
    print "Gefundene LSI-Meldungen ($candidate_count):"
    jq -r '"  \(.LsiId)  \(.Published[0:10])  \(.Classification)  \(.Title)"' "$CANDIDATES_JSONL"
    print ""
fi

# 4) Neue Einträge verarbeiten
NEW_CSV="$WORK_DIR/new_entries.csv"
FAILED_JSONL="$WORK_DIR/failed.jsonl"
csv_header > "$NEW_CSV"
: > "$FAILED_JSONL"

while IFS= read -r cand; do
    [[ -z "$cand" ]] && continue

    lsi_id="" uuid="" exploit="" no_patch="" title=""
    lsi_id=$(print -r -- "$cand" | jq -r '.LsiId')
    uuid=$(print -r -- "$cand" | jq -r '.Uuid // ""')
    exploit=$(print -r -- "$cand" | jq -r '.Exploit // ""')
    no_patch=$(print -r -- "$cand" | jq -r '.NoPatch // ""')
    title=$(print -r -- "$cand" | jq -r '.Title')

    print "============================================================"
    print "Verarbeite: $lsi_id – $title"
    print "============================================================"

    raw_entries=""
    if ! raw_entries=$(get_lsi_apple_entries "$lsi_id" "$uuid" "$exploit" "$no_patch" 2>&1); then
        print "FEHLER bei $lsi_id" >&2
        print -r -- "{\"LsiId\":\"$lsi_id\",\"Title\":\"${title//\"/\\\"}\",\"Error\":\"Abruf fehlgeschlagen\"}" >> "$FAILED_JSONL"
        continue
    fi

    # Qualität + Kurzbeschreibung ergänzen, dann mit Relevanz-Filter in neue CSV
    print -r -- "$raw_entries" | enrich_quality | while IFS= read -r enriched_row; do
        [[ -z "$enriched_row" ]] && continue
        betr="" beh=""
        betr=$(print -r -- "$enriched_row" | python3 -c "import sys,csv; r=next(csv.reader(sys.stdin,delimiter=';')); print(r[7] if len(r)>7 else '',end='')")
        beh=$(print -r -- "$enriched_row"  | python3 -c "import sys,csv; r=next(csv.reader(sys.stdin,delimiter=';')); print(r[8] if len(r)>8 else '',end='')")
        if test_is_relevant_entry "$betr" "$beh"; then
            print -r -- "$enriched_row" >> "$NEW_CSV"
        fi
    done

    [[ "$KEEP_PER_ADVISORY_CSV" == true ]] && {
        sc="${OUT_DIR}/${lsi_id}_Apple-Auswertung_${TIMESTAMP}.csv"
        { csv_header; grep "\"${lsi_id}\"" "$NEW_CSV"; } > "$sc"
        print "Einzel-CSV: $sc"
    }

done < "$CANDIDATES_JSONL"

# 5) Mit Bestand mergen
ALL_CSV="$WORK_DIR/all_entries.csv"

if [[ "$IS_FIRST_RUN" == true || -z "$EXISTING_FILE" ]]; then
    cp "$NEW_CSV" "$ALL_CSV"
else
    new_count=$(tail -n +2 "$NEW_CSV" | grep -c . 2>/dev/null || print 0)
    print "Merge: $local_row_count bestehende + $new_count neue Einträge"
    merge_with_existing "$EXISTING_FILE" "$NEW_CSV" > "$ALL_CSV"
    merged_total=$(tail -n +2 "$ALL_CSV" | grep -c . 2>/dev/null || print 0)
    print "Nach Merge: $merged_total Einträge"
    print ""
fi

# 6) Bereinigung nach RELEVANT_VERSIONS
PRUNED_CSV="$WORK_DIR/pruned.csv"
prune_by_relevant_versions "$ALL_CSV" > "$PRUNED_CSV"
cp "$PRUNED_CSV" "$ALL_CSV"

# 7) Ausgabe schreiben
final_count=$(tail -n +2 "$ALL_CSV" | grep -c . 2>/dev/null || print 0)

if (( final_count > 0 )); then
    if [[ "$IS_FIRST_RUN" == true || -z "$EXISTING_FILE" ]]; then
        GESAMT_CSV="${OUT_DIR}/LSI-Apple-Gesamtauswertung_${TIMESTAMP}.csv"
    else
        GESAMT_CSV="$EXISTING_FILE"
    fi

    cp "$ALL_CSV" "$GESAMT_CSV"
    print ""
    print "Gesamt-CSV:       $GESAMT_CSV"
    print "Einträge gesamt:  $final_count"
    print ""

    print "Qualitätsverteilung:"
    python3 -c "
import csv
from collections import Counter
c = Counter(r.get('Qualitaet','') for r in csv.DictReader(open('$GESAMT_CSV'), delimiter=';'))
for k,v in sorted(c.items()): print(f'  {k}: {v}')
"
    print ""

    print "LSI-Verteilung:"
    python3 -c "
import csv
from collections import Counter
c = Counter(r.get('LsiId','') for r in csv.DictReader(open('$GESAMT_CSV'), delimiter=';'))
for k,v in sorted(c.items()): print(f'  {k}: {v}')
"
    print ""

    print "Prüffälle:"
    python3 -c "
import csv
rows = [r for r in csv.DictReader(open('$GESAMT_CSV'), delimiter=';') if r.get('Qualitaet')=='prüfen']
if not rows: print('  Keine')
for r in rows: print(f\"  {r.get('LsiId','')}  {r.get('Komponente','')}  {r.get('CVEs','')}\")
"
    print ""

    # Management Report
    if [[ "$IS_FIRST_RUN" == true || -z "$EXISTING_FILE" ]]; then
        REPORT_CSV="${OUT_DIR}/LSI-Apple-Managementreport_${TIMESTAMP}.csv"
    else
        REPORT_CSV=$(find "$OUT_DIR" -maxdepth 1 -name "LSI-Apple-Managementreport_*.csv" \
            2>/dev/null | sort | tail -1)
        REPORT_CSV="${REPORT_CSV:-${OUT_DIR}/LSI-Apple-Managementreport_${TIMESTAMP}.csv}"
    fi

    export_management_report "$GESAMT_CSV" "$REPORT_CSV"
    print "Managementreport: $REPORT_CSV"
    print ""
else
    print "Keine Einträge nach Verarbeitung und Bereinigung."
fi

# 8) Fehler-Report
failed_count=$(grep -c . "$FAILED_JSONL" 2>/dev/null || print 0)
if (( failed_count > 0 )); then
    FAILED_OUT="${OUT_DIR}/LSI-Apple-Gesamtauswertung_Fehler_${TIMESTAMP}.csv"
    python3 -c "
import json, csv, sys
rows = [json.loads(l) for l in open('$FAILED_JSONL') if l.strip()]
with open('$FAILED_OUT','w',encoding='utf-8',newline='') as f:
    w = csv.DictWriter(f, fieldnames=['LsiId','Title','Error'],
                       delimiter=';', quoting=csv.QUOTE_ALL)
    w.writeheader(); w.writerows(rows)
"
    print "Fehlgeschlagene LSIs ($failed_count):"
    jq -r '"  \(.LsiId): \(.Error)"' "$FAILED_JSONL"
    print "Fehler-CSV: $FAILED_OUT"
fi

print ""
print "Fertig."
