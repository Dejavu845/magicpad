#!/usr/bin/env bash
# MagicPad regression entry: health + inject telemetry contract + ws + type/key burst
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${BASE_URL:-http://127.0.0.1:7878}"

echo "== health =="
# Additive wave 8: capture HTTP status (JSON body must still parse below).
HEALTH_JSON="$(curl -sS --noproxy '*' --max-time 3 -w '\n%{http_code}' "$BASE/health")"
HEALTH_CODE="$(printf '%s\n' "$HEALTH_JSON" | tail -n1)"
HEALTH_JSON="$(printf '%s\n' "$HEALTH_JSON" | sed '$d')"
echo "$HEALTH_JSON" | head -c 500
echo
if [[ "$HEALTH_CODE" != "200" ]]; then
  echo "health HTTP FAIL: status=$HEALTH_CODE" >&2
  exit 1
fi

# Additive wave 9: /health is uncached JSON with the MagicPad header (not an HTML error page).
HEALTH_HDRS="$(curl -sS --noproxy '*' --max-time 3 -D - -o /dev/null "$BASE/health" | tr -d '\r')"
HEALTH_CT="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^content-type:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
HEALTH_CT_LC="$(printf '%s' "$HEALTH_CT" | tr '[:upper:]' '[:lower:]')"
case "$HEALTH_CT_LC" in
  application/json*) ;;
  *) echo "health Content-Type FAIL: $HEALTH_CT" >&2; exit 1 ;;
esac
HEALTH_CC="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^cache-control:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_CC" != *no-store* ]]; then
  echo "health Cache-Control FAIL: must include no-store, got $HEALTH_CC" >&2
  exit 1
fi
if ! printf '%s\n' "$HEALTH_HDRS" | grep -qi '^X-MagicPad:'; then
  echo "health X-MagicPad FAIL: missing header" >&2
  exit 1
fi
# Additive wave 10: token is 1; JSON charset; extra cache; CORS for the phone.
HEALTH_XM="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^X-MagicPad:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_XM" != "1" ]]; then
  echo "health X-MagicPad FAIL: must be 1, got $HEALTH_XM" >&2
  exit 1
fi
if [[ "$HEALTH_CT_LC" != *charset=utf-8* ]]; then
  echo "health Content-Type FAIL: must include charset=utf-8, got $HEALTH_CT" >&2
  exit 1
fi
HEALTH_PRAGMA="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^Pragma:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_PRAGMA" != *no-cache* ]]; then
  echo "health Pragma FAIL: must include no-cache, got $HEALTH_PRAGMA" >&2
  exit 1
fi
HEALTH_EXPIRES="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^Expires:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_EXPIRES" != "0" ]]; then
  echo "health Expires FAIL: must be 0, got $HEALTH_EXPIRES" >&2
  exit 1
fi
HEALTH_ACAO="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^Access-Control-Allow-Origin:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_ACAO" != "*" ]]; then
  echo "health CORS origin FAIL: must be *, got $HEALTH_ACAO" >&2
  exit 1
fi
HEALTH_ACAM="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^Access-Control-Allow-Methods:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_ACAM" != *get* ]]; then
  echo "health CORS methods FAIL: must include GET, got $HEALTH_ACAM" >&2
  exit 1
fi
if [[ "$HEALTH_ACAM" != *post* ]]; then
  echo "health CORS methods FAIL: must include POST, got $HEALTH_ACAM" >&2
  exit 1
fi
HEALTH_ACAH="$(printf '%s\n' "$HEALTH_HDRS" | grep -i '^Access-Control-Allow-Headers:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_ACAH" != *x-magicpad-lang* ]]; then
  echo "health CORS headers FAIL: must include X-MagicPad-Lang, got $HEALTH_ACAH" >&2
  exit 1
fi
# Additive wave 11: extra cache tokens + CORS preflight + drop/stt filename header.
if [[ "$HEALTH_CC" != *no-cache* ]]; then
  echo "health Cache-Control FAIL: must include no-cache, got $HEALTH_CC" >&2
  exit 1
fi
if [[ "$HEALTH_CC" != *max-age=0* ]]; then
  echo "health Cache-Control FAIL: must include max-age=0, got $HEALTH_CC" >&2
  exit 1
fi
if [[ "$HEALTH_ACAM" != *options* ]]; then
  echo "health CORS methods FAIL: must include OPTIONS, got $HEALTH_ACAM" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *x-magicpad-filename* ]]; then
  echo "health CORS headers FAIL: must include X-MagicPad-Filename, got $HEALTH_ACAH" >&2
  exit 1
fi
# Additive wave 12: CORS HEAD + Content-Type + AutoPaste; Cache-Control must-revalidate.
if [[ "$HEALTH_ACAM" != *head* ]]; then
  echo "health CORS methods FAIL: must include HEAD, got $HEALTH_ACAM" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *content-type* ]]; then
  echo "health CORS headers FAIL: must include Content-Type, got $HEALTH_ACAH" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *x-magicpad-autopaste* ]]; then
  echo "health CORS headers FAIL: must include X-MagicPad-AutoPaste, got $HEALTH_ACAH" >&2
  exit 1
fi
if [[ "$HEALTH_CC" != *must-revalidate* ]]; then
  echo "health Cache-Control FAIL: must include must-revalidate, got $HEALTH_CC" >&2
  exit 1
fi
# Additive wave 13: HEAD + OPTIONS + phone WS CORS (Upgrade / Sec-WebSocket-Key).
if [[ "$HEALTH_ACAH" != *upgrade* ]]; then
  echo "health CORS headers FAIL: must include Upgrade, got $HEALTH_ACAH" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *sec-websocket-key* ]]; then
  echo "health CORS headers FAIL: must include Sec-WebSocket-Key, got $HEALTH_ACAH" >&2
  exit 1
fi
HEALTH_HEAD_HDRS="$(curl -sS --noproxy '*' --max-time 3 -I "$BASE/health" | tr -d '\r')"
HEALTH_HEAD_CODE="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | head -n1)"
if [[ "$HEALTH_HEAD_CODE" != *" 200"* ]]; then
  echo "health HEAD FAIL: $HEALTH_HEAD_CODE" >&2
  exit 1
fi
HEALTH_HEAD_CT="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^content-type:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
case "$HEALTH_HEAD_CT" in
  application/json*) ;;
  *) echo "health HEAD Content-Type FAIL: $HEALTH_HEAD_CT" >&2; exit 1 ;;
esac
HEALTH_HEAD_XM="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^X-MagicPad:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_HEAD_XM" != "1" ]]; then
  echo "health HEAD X-MagicPad FAIL: must be 1, got ${HEALTH_HEAD_XM:-missing}" >&2
  exit 1
fi
HEALTH_OPT_HDRS="$(curl -sS --noproxy '*' --max-time 3 -D - -o /dev/null -X OPTIONS "$BASE/health" | tr -d '\r')"
HEALTH_OPT_CODE="$(printf '%s\n' "$HEALTH_OPT_HDRS" | head -n1)"
if [[ "$HEALTH_OPT_CODE" != *" 204"* && "$HEALTH_OPT_CODE" != *" 200"* ]]; then
  echo "health OPTIONS FAIL: $HEALTH_OPT_CODE" >&2
  exit 1
fi
HEALTH_OPT_ACAO="$(printf '%s\n' "$HEALTH_OPT_HDRS" | grep -i '^Access-Control-Allow-Origin:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_OPT_ACAO" != "*" ]]; then
  echo "health OPTIONS CORS origin FAIL: must be *, got ${HEALTH_OPT_ACAO:-missing}" >&2
  exit 1
fi
HEALTH_OPT_ACAM="$(printf '%s\n' "$HEALTH_OPT_HDRS" | grep -i '^Access-Control-Allow-Methods:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_OPT_ACAM" != *get* || "$HEALTH_OPT_ACAM" != *head* || "$HEALTH_OPT_ACAM" != *post* || "$HEALTH_OPT_ACAM" != *options* ]]; then
  echo "health OPTIONS CORS methods FAIL: must include GET HEAD POST OPTIONS, got ${HEALTH_OPT_ACAM:-missing}" >&2
  exit 1
fi
# Additive wave 14: phone WS CORS Connection/Version/Extensions; HEAD cache+CORS; OPTIONS 204.
if [[ "$HEALTH_ACAH" != *connection* ]]; then
  echo "health CORS headers FAIL: must include Connection, got $HEALTH_ACAH" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *sec-websocket-version* ]]; then
  echo "health CORS headers FAIL: must include Sec-WebSocket-Version, got $HEALTH_ACAH" >&2
  exit 1
fi
if [[ "$HEALTH_ACAH" != *sec-websocket-extensions* ]]; then
  echo "health CORS headers FAIL: must include Sec-WebSocket-Extensions, got $HEALTH_ACAH" >&2
  exit 1
fi
HEALTH_HEAD_CC="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^cache-control:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_HEAD_CC" != *no-store* ]]; then
  echo "health HEAD Cache-Control FAIL: must include no-store, got ${HEALTH_HEAD_CC:-missing}" >&2
  exit 1
fi
HEALTH_HEAD_ACAO="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^Access-Control-Allow-Origin:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_HEAD_ACAO" != "*" ]]; then
  echo "health HEAD CORS origin FAIL: must be *, got ${HEALTH_HEAD_ACAO:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_CODE" != *" 204"* ]]; then
  echo "health OPTIONS FAIL: must be 204, got $HEALTH_OPT_CODE" >&2
  exit 1
fi
HEALTH_OPT_ACAH="$(printf '%s\n' "$HEALTH_OPT_HDRS" | grep -i '^Access-Control-Allow-Headers:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_OPT_ACAH" != *content-type* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Content-Type, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 15: HEAD extra cache + charset + CORS GET; OPTIONS phone WS/STT preflight.
if [[ "$HEALTH_HEAD_CC" != *no-cache* ]]; then
  echo "health HEAD Cache-Control FAIL: must include no-cache, got ${HEALTH_HEAD_CC:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_HEAD_CC" != *max-age=0* ]]; then
  echo "health HEAD Cache-Control FAIL: must include max-age=0, got ${HEALTH_HEAD_CC:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_HEAD_CT" != *charset=utf-8* ]]; then
  echo "health HEAD Content-Type FAIL: must include charset=utf-8, got $HEALTH_HEAD_CT" >&2
  exit 1
fi
HEALTH_HEAD_ACAM="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^Access-Control-Allow-Methods:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_HEAD_ACAM" != *get* ]]; then
  echo "health HEAD CORS methods FAIL: must include GET, got ${HEALTH_HEAD_ACAM:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *x-magicpad-lang* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include X-MagicPad-Lang, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *upgrade* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Upgrade, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 16: HEAD Pragma/Expires; OPTIONS phone WS Key + drop filename.
HEALTH_HEAD_PRAGMA="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^Pragma:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_HEAD_PRAGMA" != *no-cache* ]]; then
  echo "health HEAD Pragma FAIL: must include no-cache, got ${HEALTH_HEAD_PRAGMA:-missing}" >&2
  exit 1
fi
HEALTH_HEAD_EXPIRES="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^Expires:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$HEALTH_HEAD_EXPIRES" != "0" ]]; then
  echo "health HEAD Expires FAIL: must be 0, got ${HEALTH_HEAD_EXPIRES:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *sec-websocket-key* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Sec-WebSocket-Key, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *x-magicpad-filename* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include X-MagicPad-Filename, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 17: HEAD CORS methods full set; OPTIONS phone WS Version + Connection + AutoPaste.
if [[ "$HEALTH_HEAD_ACAM" != *head* ]]; then
  echo "health HEAD CORS methods FAIL: must include HEAD, got ${HEALTH_HEAD_ACAM:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_HEAD_ACAM" != *post* ]]; then
  echo "health HEAD CORS methods FAIL: must include POST, got ${HEALTH_HEAD_ACAM:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_HEAD_ACAM" != *options* ]]; then
  echo "health HEAD CORS methods FAIL: must include OPTIONS, got ${HEALTH_HEAD_ACAM:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *connection* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Connection, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *sec-websocket-version* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Sec-WebSocket-Version, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *x-magicpad-autopaste* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include X-MagicPad-AutoPaste, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 18: HEAD CORS Allow-Headers (phone GET/HEAD /health); OPTIONS WS Extensions.
HEALTH_HEAD_ACAH="$(printf '%s\n' "$HEALTH_HEAD_HDRS" | grep -i '^Access-Control-Allow-Headers:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$HEALTH_HEAD_ACAH" != *content-type* ]]; then
  echo "health HEAD CORS headers FAIL: must include Content-Type, got ${HEALTH_HEAD_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_HEAD_ACAH" != *x-magicpad-lang* ]]; then
  echo "health HEAD CORS headers FAIL: must include X-MagicPad-Lang, got ${HEALTH_HEAD_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$HEALTH_OPT_ACAH" != *sec-websocket-extensions* ]]; then
  echo "health OPTIONS CORS headers FAIL: must include Sec-WebSocket-Extensions, got ${HEALTH_OPT_ACAH:-missing}" >&2
  exit 1
fi

echo "== health contract (lastKey + lastKeyReason + injectCount + lastKeyOk + lastKeyAt + lastKeyCount) =="
INJECT_BEFORE="$(printf '%s' "$HEALTH_JSON" | python3 -c "
import json, sys, time, datetime
raw = sys.stdin.read()
try:
    h = json.loads(raw)
except Exception as e:
    print('health JSON parse FAIL:', e, file=sys.stderr)
    sys.exit(1)
need = ('lastKey', 'lastKeyReason', 'injectCount', 'lastKeyOk', 'lastKeyAt', 'lastKeyCount', 'https', 'httpsPort', 'httpPort', 'lastGesture', 'lastGestureReason', 'lastGestureAt', 'lastGesturePhase', 'gestureCount', 'binaryPath', 'htmlRev', 'injectQueue', 'clients', 'lastDropOk', 'lastDropReason', 'dropCount', 'whisper', 'whisperReady', 'whisperCached', 'whisperModel', 'httpUrl', 'ip', 'httpsUrl', 'stt', 'sttFile', 'html', 'ips', 'lastDropKind', 'htmlSource', 'ok', 'service', 'ax', 'ifaces', 'routeIface', 'httpsError', 'lastDropAt', 'htmlPath', 'port', 'ts', 'mdns')
missing = [k for k in need if k not in h]
if missing:
    print('health contract FAIL: missing keys', missing, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('https'), bool):
    print('health contract FAIL: https must be bool', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('httpsPort'), (int, float)):
    print('health contract FAIL: httpsPort must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKeyOk'), bool):
    print('health contract FAIL: lastKeyOk must be bool, got', type(h.get('lastKeyOk')).__name__, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('injectCount'), (int, float)):
    print('health contract FAIL: injectCount must be number, got', type(h.get('injectCount')).__name__, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKeyAt'), (int, float)):
    print('health contract FAIL: lastKeyAt must be number, got', type(h.get('lastKeyAt')).__name__, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKeyCount'), (int, float)):
    print('health contract FAIL: lastKeyCount must be number, got', type(h.get('lastKeyCount')).__name__, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKeyReason'), str):
    print('health contract FAIL: lastKeyReason must be str, got', type(h.get('lastKeyReason')).__name__, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastGesture'), str):
    print('health contract FAIL: lastGesture must be str', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastGestureReason'), str):
    print('health contract FAIL: lastGestureReason must be str', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastGestureAt'), (int, float)):
    print('health contract FAIL: lastGestureAt must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastGesturePhase'), (int, float)):
    print('health contract FAIL: lastGesturePhase must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('gestureCount'), (int, float)):
    print('health contract FAIL: gestureCount must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('binaryPath'), str):
    print('health contract FAIL: binaryPath must be str', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('htmlRev'), str) or not str(h.get('htmlRev') or '').strip():
    print('health contract FAIL: htmlRev must be non-empty str', file=sys.stderr)
    sys.exit(1)
if h.get('injectQueue') is not True:
    print('health contract FAIL: injectQueue must be true', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('clients'), (int, float)):
    print('health contract FAIL: clients must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastDropReason'), str):
    print('health contract FAIL: lastDropReason must be str', file=sys.stderr)
    sys.exit(1)
if int(h.get('dropCount') or 0) == 0 and str(h.get('lastDropReason') or '') != 'never':
    print('health contract FAIL: unused drop must be lastDropReason=never, got', h.get('lastDropReason'), file=sys.stderr)
    sys.exit(1)
if h.get('whisper') is not True:
    print('health contract FAIL: whisper must be true', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('whisperReady'), bool):
    print('health contract FAIL: whisperReady must be bool', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('whisperCached'), bool):
    print('health contract FAIL: whisperCached must be bool', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('whisperModel'), str) or not str(h.get('whisperModel') or '').strip():
    print('health contract FAIL: whisperModel must be non-empty str', file=sys.stderr)
    sys.exit(1)
# Additive: model id is a variant name (tiny/base/…), never a filesystem path.
# (backslash omitted: this python -c lives in a bash double-quoted string)
if '/' in str(h.get('whisperModel') or ''):
    print('health privacy FAIL: whisperModel must not be a path, got', h.get('whisperModel'), file=sys.stderr)
    sys.exit(1)
# Additive wave 2: variant id only (tiny/base/…), matches Resources/whisper/openai_whisper-<id>
_wm = str(h.get('whisperModel') or '').strip()
_wm_ok = ('tiny', 'base', 'small', 'medium', 'large', 'large-v2', 'large-v3')
if _wm not in _wm_ok:
    print('health contract FAIL: whisperModel must be a known variant, got', _wm, file=sys.stderr)
    sys.exit(1)
http_url = str(h.get('httpUrl') or '').strip()
if not isinstance(h.get('httpUrl'), str) or not http_url.startswith('http://'):
    print('health contract FAIL: httpUrl must be http:// URL, got', h.get('httpUrl'), file=sys.stderr)
    sys.exit(1)
ip = str(h.get('ip') or '').strip()
if not isinstance(h.get('ip'), str) or not ip or '/' in ip:
    print('health contract FAIL: ip must be non-empty host, got', h.get('ip'), file=sys.stderr)
    sys.exit(1)
def _host(url):
    rest = str(url).split('://', 1)[-1]
    hostport = rest.split('/', 1)[0]
    if hostport.startswith('['):
        return hostport[1:].split(']', 1)[0]
    if hostport.count(':') == 1:
        return hostport.split(':')[0]
    return hostport
if _host(http_url) != ip:
    print('health contract FAIL: httpUrl host must equal ip, got', http_url, ip, file=sys.stderr)
    sys.exit(1)
def _url_port(url, default):
    rest = str(url).split('://', 1)[-1]
    hostport = rest.split('/', 1)[0]
    if hostport.startswith('['):
        tail = hostport.split(']', 1)[-1]
        if tail.startswith(':'):
            return int(tail[1:])
        return int(default)
    if hostport.count(':') == 1:
        return int(hostport.split(':')[1])
    return int(default)
if not isinstance(h.get('httpPort'), (int, float)) or int(h.get('httpPort') or 0) <= 0:
    print('health contract FAIL: httpPort must be positive number, got', h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
if _url_port(http_url, 80) != int(h.get('httpPort')):
    print('health contract FAIL: httpUrl port must equal httpPort, got', http_url, h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('port'), (int, float)) or int(h.get('port') or 0) != int(h.get('httpPort')):
    print('health contract FAIL: port must equal httpPort, got', h.get('port'), h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
ips = h.get('ips')
if not isinstance(ips, list) or ip not in [str(x) for x in ips]:
    print('health contract FAIL: ips must be a list containing ip, got', ips, ip, file=sys.stderr)
    sys.exit(1)
if h.get('stt') is not True:
    print('health contract FAIL: stt must be true', file=sys.stderr)
    sys.exit(1)
if h.get('sttFile') is not True:
    print('health contract FAIL: sttFile must be true', file=sys.stderr)
    sys.exit(1)
if h.get('html') is not True:
    print('health contract FAIL: html must be true', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastDropKind'), str):
    print('health contract FAIL: lastDropKind must be str', file=sys.stderr)
    sys.exit(1)
# Additive wave 3: typed extras already on /health (no product change).
if h.get('ok') is not True:
    print('health contract FAIL: ok must be true', file=sys.stderr)
    sys.exit(1)
if h.get('service') != 'magicpad':
    print('health contract FAIL: service must be magicpad, got', h.get('service'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('ax'), bool):
    print('health contract FAIL: ax must be bool', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastDropOk'), bool):
    print('health contract FAIL: lastDropOk must be bool', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastDropAt'), (int, float)):
    print('health contract FAIL: lastDropAt must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('httpsError'), str):
    print('health contract FAIL: httpsError must be str', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('ifaces'), str):
    print('health contract FAIL: ifaces must be str', file=sys.stderr)
    sys.exit(1)
_ri = str(h.get('routeIface') or '').strip()
if not isinstance(h.get('routeIface'), str) or not _ri or '/' in _ri:
    print('health contract FAIL: routeIface must be non-empty iface, got', h.get('routeIface'), file=sys.stderr)
    sys.exit(1)
if h.get('htmlSource') not in ('bundle', 'source'):
    print('health contract FAIL: htmlSource must be bundle|source, got', h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
# Additive wave 4: cached weights, htmlPath alias, htmlRev shape, ifaces↔ip, empty TLS error.
if h.get('whisperCached') is not True:
    print('health contract FAIL: whisperCached must be true', file=sys.stderr)
    sys.exit(1)
if h.get('htmlPath') != h.get('htmlSource'):
    print('health contract FAIL: htmlPath must equal htmlSource, got', h.get('htmlPath'), h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('clients'), (int, float)):
    print('health contract FAIL: clients must be number', file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('ts'), (int, float)):
    print('health contract FAIL: ts must be number', file=sys.stderr)
    sys.exit(1)
_hr = str(h.get('htmlRev') or '').strip()
_hr_parts = _hr.split('-')
if not (len(_hr_parts) == 3 and _hr_parts[0].isdigit() and len(_hr_parts[0]) == 8 and _hr_parts[1].isdigit() and len(_hr_parts[1]) == 4 and _hr_parts[2].startswith('h') and _hr_parts[2][1:].isdigit()):
    print('health contract FAIL: htmlRev must be YYYYMMDD-HHMM-hN, got', _hr, file=sys.stderr)
    sys.exit(1)
if ip not in str(h.get('ifaces') or ''):
    print('health contract FAIL: ifaces must contain ip, got', h.get('ifaces'), ip, file=sys.stderr)
    sys.exit(1)
if not any(part.startswith(_ri + '=') for part in str(h.get('ifaces') or '').split(',')):
    print('health contract FAIL: ifaces must include routeIface=, got', h.get('ifaces'), _ri, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True and str(h.get('httpsError') or '') != '':
    print('health contract FAIL: httpsError must be empty when https=true, got', h.get('httpsError'), file=sys.stderr)
    sys.exit(1)
# Additive: when TLS is up, httpsUrl must be a usable https:// URL (no home paths).
if h.get('https') is True:
    https_url = str(h.get('httpsUrl') or '').strip()
    if not isinstance(h.get('httpsUrl'), str) or not https_url.startswith('https://'):
        print('health contract FAIL: httpsUrl must be https:// URL when https=true, got', h.get('httpsUrl'), file=sys.stderr)
        sys.exit(1)
    if '/' in https_url.split('://', 1)[-1].split('/', 1)[0]:
        print('health contract FAIL: httpsUrl host must not contain /, got', h.get('httpsUrl'), file=sys.stderr)
        sys.exit(1)
    if _host(https_url) != ip:
        print('health contract FAIL: httpsUrl host must equal ip, got', https_url, ip, file=sys.stderr)
        sys.exit(1)
    if _url_port(https_url, 443) != int(h.get('httpsPort')):
        print('health contract FAIL: httpsUrl port must equal httpsPort, got', https_url, h.get('httpsPort'), file=sys.stderr)
        sys.exit(1)
    if not https_url.endswith('/'):
        print('health contract FAIL: httpsUrl must end with /, got', https_url, file=sys.stderr)
        sys.exit(1)
# Additive wave 5: exact binary name, positive httpsPort, clients>=0, ips hosts, httpUrl slash.
if str(h.get('binaryPath') or '') != 'MagicPad.app':
    print('health contract FAIL: binaryPath must be MagicPad.app, got', h.get('binaryPath'), file=sys.stderr)
    sys.exit(1)
if int(h.get('httpsPort') or 0) <= 0:
    print('health contract FAIL: httpsPort must be positive number, got', h.get('httpsPort'), file=sys.stderr)
    sys.exit(1)
if int(h.get('clients') or 0) < 0:
    print('health contract FAIL: clients must be >= 0, got', h.get('clients'), file=sys.stderr)
    sys.exit(1)
if any((not str(x).strip() or '/' in str(x)) for x in ips):
    print('health contract FAIL: ips items must be hosts without /, got', ips, file=sys.stderr)
    sys.exit(1)
if not http_url.endswith('/'):
    print('health contract FAIL: httpUrl must end with /, got', http_url, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKey'), str):
    print('health contract FAIL: lastKey must be str, got', type(h.get('lastKey')).__name__, file=sys.stderr)
    sys.exit(1)
# Additive wave 6: unused drop/gesture empty, mdns exact, TLS on a different port, no extra leak keys.
if not isinstance(h.get('mdns'), str) or str(h.get('mdns') or '') != '':
    print('health contract FAIL: mdns must be empty str, got', h.get('mdns'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('dropCount'), (int, float)) or int(h.get('dropCount') or 0) < 0:
    print('health contract FAIL: dropCount must be >= 0, got', h.get('dropCount'), file=sys.stderr)
    sys.exit(1)
if int(h.get('dropCount') or 0) == 0 and str(h.get('lastDropKind') or '') != '':
    print('health contract FAIL: unused drop must be lastDropKind empty, got', h.get('lastDropKind'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('gestureCount'), (int, float)) or int(h.get('gestureCount') or 0) < 0:
    print('health contract FAIL: gestureCount must be >= 0, got', h.get('gestureCount'), file=sys.stderr)
    sys.exit(1)
if int(h.get('gestureCount') or 0) == 0:
    if str(h.get('lastGesture') or '') != '' or str(h.get('lastGestureReason') or '') != '':
        print('health contract FAIL: unused gesture must be empty lastGesture/lastGestureReason, got', h.get('lastGesture'), h.get('lastGestureReason'), file=sys.stderr)
        sys.exit(1)
if h.get('https') is True and int(h.get('httpsPort') or 0) == int(h.get('httpPort') or 0):
    print('health contract FAIL: httpsPort must differ from httpPort when https=true, got', h.get('httpsPort'), h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
if not isinstance(ips, list) or len(ips) < 1:
    print('health contract FAIL: ips must be non-empty list, got', ips, file=sys.stderr)
    sys.exit(1)
if http_url.startswith('https://'):
    print('health contract FAIL: httpUrl must be http not https, got', http_url, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('ts'), (int, float)) or int(h.get('ts') or 0) <= 0:
    print('health contract FAIL: ts must be positive unix seconds, got', h.get('ts'), file=sys.stderr)
    sys.exit(1)
if int(h.get('injectCount') or 0) < 0:
    print('health contract FAIL: injectCount must be >= 0, got', h.get('injectCount'), file=sys.stderr)
    sys.exit(1)
# Additive wave 7: unused drop/gesture/inject zeroed; IPv4 ip; html served from bundle.
if int(h.get('dropCount') or 0) == 0:
    if h.get('lastDropOk') is not False:
        print('health contract FAIL: unused drop must be lastDropOk=false, got', h.get('lastDropOk'), file=sys.stderr)
        sys.exit(1)
    if float(h.get('lastDropAt') or 0) != 0:
        print('health contract FAIL: unused drop must be lastDropAt=0, got', h.get('lastDropAt'), file=sys.stderr)
        sys.exit(1)
if int(h.get('gestureCount') or 0) == 0:
    if float(h.get('lastGestureAt') or 0) != 0 or int(h.get('lastGesturePhase') or 0) != 0:
        print('health contract FAIL: unused gesture must be lastGestureAt=0 lastGesturePhase=0, got', h.get('lastGestureAt'), h.get('lastGesturePhase'), file=sys.stderr)
        sys.exit(1)
if not isinstance(h.get('lastKeyCount'), (int, float)) or int(h.get('lastKeyCount') or 0) < 0:
    print('health contract FAIL: lastKeyCount must be >= 0, got', h.get('lastKeyCount'), file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('lastKeyAt'), (int, float)) or float(h.get('lastKeyAt') or 0) < 0:
    print('health contract FAIL: lastKeyAt must be >= 0, got', h.get('lastKeyAt'), file=sys.stderr)
    sys.exit(1)
if int(h.get('injectCount') or 0) == 0:
    if int(h.get('lastKeyCount') or 0) != 0:
        print('health contract FAIL: unused inject must be lastKeyCount=0, got', h.get('lastKeyCount'), file=sys.stderr)
        sys.exit(1)
    if h.get('lastKeyOk') is not False:
        print('health contract FAIL: unused inject must be lastKeyOk=false, got', h.get('lastKeyOk'), file=sys.stderr)
        sys.exit(1)
    if str(h.get('lastKeyReason') or '') != '':
        print('health contract FAIL: unused inject must be lastKeyReason empty, got', h.get('lastKeyReason'), file=sys.stderr)
        sys.exit(1)
if h.get('html') is True and h.get('htmlSource') != 'bundle':
    print('health contract FAIL: htmlSource must be bundle when html=true, got', h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
_ip_parts = ip.split('.')
if len(_ip_parts) != 4 or any((not p.isdigit() or int(p) > 255) for p in _ip_parts):
    print('health contract FAIL: ip must be IPv4 host, got', ip, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _hu = str(h.get('httpsUrl') or '').strip()
    if _hu.startswith('http://'):
        print('health contract FAIL: httpsUrl must not be http://, got', _hu, file=sys.stderr)
        sys.exit(1)
# Additive wave 8: htmlRev clock; ips/ifaces IPv4 pairs; ports <=65535; used inject lastKey; ts unix seconds; no query on LAN URLs; no cloud hosts.
_hr_yyyy = int(_hr_parts[0][:4])
if _hr_yyyy < 2026 or _hr_yyyy > 2030:
    print('health contract FAIL: htmlRev year out of range, got', _hr, file=sys.stderr)
    sys.exit(1)
_hh = int(_hr_parts[1][:2])
_mm = int(_hr_parts[1][2:])
if _hh > 23 or _mm > 59:
    print('health contract FAIL: htmlRev HHMM not a clock, got', _hr, file=sys.stderr)
    sys.exit(1)
if int(_hr_parts[2][1:]) < 1:
    print('health contract FAIL: htmlRev hN must be >= 1, got', _hr, file=sys.stderr)
    sys.exit(1)
for _one in ips:
    _p = str(_one).split('.')
    if len(_p) != 4 or any((not x.isdigit() or int(x) > 255) for x in _p):
        print('health contract FAIL: ips items must be IPv4, got', ips, file=sys.stderr)
        sys.exit(1)
for _part in str(h.get('ifaces') or '').split(','):
    _part = _part.strip()
    if not _part or '=' not in _part:
        print('health contract FAIL: ifaces pair must be iface=ipv4, got', h.get('ifaces'), file=sys.stderr)
        sys.exit(1)
    _iname, _iip = _part.split('=', 1)
    if not _iname or '/' in _iname or '=' in _iname:
        print('health contract FAIL: iface name invalid, got', _iname, file=sys.stderr)
        sys.exit(1)
    _pp = _iip.split('.')
    if len(_pp) != 4 or any((not x.isdigit() or int(x) > 255) for x in _pp):
        print('health contract FAIL: ifaces IP must be IPv4, got', _part, file=sys.stderr)
        sys.exit(1)
if int(h.get('httpPort') or 0) > 65535 or int(h.get('httpsPort') or 0) > 65535:
    print('health contract FAIL: ports must be <= 65535, got', h.get('httpPort'), h.get('httpsPort'), file=sys.stderr)
    sys.exit(1)
if '?' in http_url:
    print('health contract FAIL: httpUrl must not carry query, got', http_url, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True and '?' in str(h.get('httpsUrl') or ''):
    print('health contract FAIL: httpsUrl must not carry query, got', h.get('httpsUrl'), file=sys.stderr)
    sys.exit(1)
_ts = float(h.get('ts') or 0)
if _ts < 1000000000 or _ts >= 20000000000:
    print('health contract FAIL: ts must be unix seconds, got', h.get('ts'), file=sys.stderr)
    sys.exit(1)
for _atk in ('lastKeyAt', 'lastDropAt', 'lastGestureAt'):
    if float(h.get(_atk) or 0) > _ts + 5:
        print('health contract FAIL: %s is in the future vs ts, got' % _atk, h.get(_atk), _ts, file=sys.stderr)
        sys.exit(1)
if int(h.get('injectCount') or 0) > 0:
    if not str(h.get('lastKey') or '').strip():
        print('health contract FAIL: used inject must have lastKey, got', h.get('lastKey'), file=sys.stderr)
        sys.exit(1)
    if not str(h.get('lastKeyReason') or '').strip():
        print('health contract FAIL: used inject must have lastKeyReason, got', h.get('lastKeyReason'), file=sys.stderr)
        sys.exit(1)
    if float(h.get('lastKeyAt') or 0) <= 0:
        print('health contract FAIL: used inject must have lastKeyAt>0, got', h.get('lastKeyAt'), file=sys.stderr)
        sys.exit(1)
_raw_l = raw.lower()
if any(x in _raw_l for x in ('openai.com', 'api.openai', 'huggingface.co', 'anthropic.com', 'generativelanguage', 'api.grok')):
    print('health contract FAIL: cloud endpoint in /health', file=sys.stderr)
    sys.exit(1)
# Additive wave 9: RFC1918 LAN ip; URL path is /; no userinfo/fragment; unique ips;
# live ts; htmlRev is a real calendar date (not future); unprivileged ports; int counters.
_oa, _ob = int(_ip_parts[0]), int(_ip_parts[1])
if not ((_oa == 10) or (_oa == 192 and _ob == 168) or (_oa == 172 and 16 <= _ob <= 31)):
    print('health contract FAIL: ip must be RFC1918 LAN, got', ip, file=sys.stderr)
    sys.exit(1)
if http_url.count('/') != 3 or '@' in http_url or '#' in http_url:
    print('health contract FAIL: httpUrl must be http://host:port/ with no userinfo/fragment, got', http_url, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _hu9 = str(h.get('httpsUrl') or '').strip()
    if _hu9.count('/') != 3 or '@' in _hu9 or '#' in _hu9:
        print('health contract FAIL: httpsUrl must be https://host:port/ with no userinfo/fragment, got', _hu9, file=sys.stderr)
        sys.exit(1)
if len(ips) != len(set(str(x) for x in ips)):
    print('health contract FAIL: ips must be unique, got', ips, file=sys.stderr)
    sys.exit(1)
try:
    _hr_date = datetime.date(int(_hr_parts[0][:4]), int(_hr_parts[0][4:6]), int(_hr_parts[0][6:8]))
except ValueError:
    print('health contract FAIL: htmlRev YYYYMMDD not a real date, got', _hr, file=sys.stderr)
    sys.exit(1)
if _hr_date > datetime.date.today():
    print('health contract FAIL: htmlRev date is in the future, got', _hr, file=sys.stderr)
    sys.exit(1)
if abs(_ts - time.time()) > 180:
    print('health contract FAIL: ts not live vs wall clock, got', _ts, time.time(), file=sys.stderr)
    sys.exit(1)
if int(h.get('httpPort') or 0) < 1024 or int(h.get('httpsPort') or 0) < 1024:
    print('health contract FAIL: ports must be >= 1024, got', h.get('httpPort'), h.get('httpsPort'), file=sys.stderr)
    sys.exit(1)
if not _ri.isalnum() or not _ri[0].isalpha():
    print('health contract FAIL: routeIface must be alnum iface, got', _ri, file=sys.stderr)
    sys.exit(1)
for _ck in ('clients', 'dropCount', 'gestureCount', 'injectCount', 'lastKeyCount', 'httpPort', 'httpsPort', 'port', 'ts'):
    _cv = h.get(_ck)
    if isinstance(_cv, bool) or type(_cv) is not int:
        print('health contract FAIL: %s must be int, got' % _ck, type(_cv).__name__, _cv, file=sys.stderr)
        sys.exit(1)
# Additive wave 10: advertised LAN is not loopback; lastKey* are not paths;
# AX-off successful inject uses the clipboard reason (not a drop).
if ip.startswith('127.') or ip in ('0.0.0.0', '255.255.255.255', 'localhost'):
    print('health contract FAIL: ip must not be loopback, got', ip, file=sys.stderr)
    sys.exit(1)
if any(str(x).startswith('127.') or str(x) in ('0.0.0.0', 'localhost') for x in ips):
    print('health contract FAIL: ips must not include loopback, got', ips, file=sys.stderr)
    sys.exit(1)
if _host(http_url).startswith('127.') or _host(http_url) in ('localhost', '0.0.0.0'):
    print('health contract FAIL: httpUrl host must not be loopback, got', http_url, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _h10 = _host(str(h.get('httpsUrl') or ''))
    if _h10.startswith('127.') or _h10 in ('localhost', '0.0.0.0'):
        print('health contract FAIL: httpsUrl host must not be loopback, got', h.get('httpsUrl'), file=sys.stderr)
        sys.exit(1)
_lk = str(h.get('lastKey') or '')
_lkr = str(h.get('lastKeyReason') or '')
if '/Users/' in _lk or '/home/' in _lk or '/Users/' in _lkr or '/home/' in _lkr:
    print('health contract FAIL: lastKey/lastKeyReason looks like a home path', _lk, _lkr, file=sys.stderr)
    sys.exit(1)
if '/' in _lk or '/' in _lkr:
    print('health contract FAIL: lastKey/lastKeyReason must not be a path, got', _lk, _lkr, file=sys.stderr)
    sys.exit(1)
if '/' in _hr or _hr.startswith('.'):
    print('health contract FAIL: htmlRev must not look like a path, got', _hr, file=sys.stderr)
    sys.exit(1)
if h.get('ax') is False and int(h.get('injectCount') or 0) > 0 and h.get('lastKeyOk') is True:
    if _lkr not in ('ax_denied_clipboard_ok', 'ax_denied'):
        print('health contract FAIL: AX-off ok inject must be clipboard/ax_denied reason, got', _lkr, file=sys.stderr)
        sys.exit(1)
# Additive wave 11: ifaces not loopback; lastKey short; lastKeyReason snake token; clients cap.
if '127.' in str(h.get('ifaces') or '') or 'localhost' in str(h.get('ifaces') or '').lower():
    print('health contract FAIL: ifaces must not include loopback, got', h.get('ifaces'), file=sys.stderr)
    sys.exit(1)
if len(_lk) > 64:
    print('health contract FAIL: lastKey too long, got', _lk, file=sys.stderr)
    sys.exit(1)
if any(c in _lk for c in '\n\r\t'):
    print('health contract FAIL: lastKey has control whitespace, got', repr(_lk), file=sys.stderr)
    sys.exit(1)
if _lkr and (not all((c.isalnum() or c == '_') for c in _lkr)):
    print('health contract FAIL: lastKeyReason must be snake token, got', _lkr, file=sys.stderr)
    sys.exit(1)
if int(h.get('clients') or 0) > 64:
    print('health contract FAIL: clients implausibly high, got', h.get('clients'), file=sys.stderr)
    sys.exit(1)
if '/' in str(h.get('httpsError') or ''):
    print('health contract FAIL: httpsError must not look like a path, got', h.get('httpsError'), file=sys.stderr)
    sys.exit(1)
# Additive wave 12: RFC1918 on ips/ifaces (not link-local); used drop/gesture are tokens not paths.
for _one in ips:
    _p = str(_one).split('.')
    _oa12, _ob12 = int(_p[0]), int(_p[1])
    if not ((_oa12 == 10) or (_oa12 == 192 and _ob12 == 168) or (_oa12 == 172 and 16 <= _ob12 <= 31)):
        print('health contract FAIL: ips items must be RFC1918, got', ips, file=sys.stderr)
        sys.exit(1)
    if str(_one).startswith('169.254.'):
        print('health contract FAIL: ips must not be link-local, got', ips, file=sys.stderr)
        sys.exit(1)
for _part in str(h.get('ifaces') or '').split(','):
    _part = _part.strip()
    _iname, _iip = _part.split('=', 1)
    _pp = _iip.split('.')
    _oa12, _ob12 = int(_pp[0]), int(_pp[1])
    if not ((_oa12 == 10) or (_oa12 == 192 and _ob12 == 168) or (_oa12 == 172 and 16 <= _ob12 <= 31)):
        print('health contract FAIL: ifaces IP must be RFC1918, got', _part, file=sys.stderr)
        sys.exit(1)
    if _iip.startswith('169.254.') or _iip.startswith('127.'):
        print('health contract FAIL: ifaces IP must not be loopback/link-local, got', _part, file=sys.stderr)
        sys.exit(1)
if ip.startswith('169.254.'):
    print('health contract FAIL: ip must not be link-local, got', ip, file=sys.stderr)
    sys.exit(1)
_ldk = str(h.get('lastDropKind') or '')
_ldr = str(h.get('lastDropReason') or '')
if '/' in _ldk or '/' in _ldr:
    print('health contract FAIL: lastDropKind/lastDropReason must not be a path, got', _ldk, _ldr, file=sys.stderr)
    sys.exit(1)
if _ldr and (not all((c.isalnum() or c == '_') for c in _ldr)):
    print('health contract FAIL: lastDropReason must be snake token, got', _ldr, file=sys.stderr)
    sys.exit(1)
if _ldk and (not all((c.isalnum() or c == '_') for c in _ldk)):
    print('health contract FAIL: lastDropKind must be snake token, got', _ldk, file=sys.stderr)
    sys.exit(1)
if int(h.get('dropCount') or 0) > 0:
    if not _ldk:
        print('health contract FAIL: used drop must have lastDropKind, got', _ldk, file=sys.stderr)
        sys.exit(1)
    if not _ldr:
        print('health contract FAIL: used drop must have lastDropReason, got', _ldr, file=sys.stderr)
        sys.exit(1)
_lg = str(h.get('lastGesture') or '')
_lgr = str(h.get('lastGestureReason') or '')
if '/' in _lg or '/' in _lgr:
    print('health contract FAIL: lastGesture* must not be a path, got', _lg, _lgr, file=sys.stderr)
    sys.exit(1)
if _lgr and (not all((c.isalnum() or c == '_') for c in _lgr)):
    print('health contract FAIL: lastGestureReason must be snake token, got', _lgr, file=sys.stderr)
    sys.exit(1)
if int(h.get('gestureCount') or 0) > 0:
    if not _lg.strip():
        print('health contract FAIL: used gesture must have lastGesture, got', _lg, file=sys.stderr)
        sys.exit(1)
    if not _lgr:
        print('health contract FAIL: used gesture must have lastGestureReason, got', _lgr, file=sys.stderr)
        sys.exit(1)
    if len(_lg) > 64:
        print('health contract FAIL: lastGesture too long, got', _lg, file=sys.stderr)
        sys.exit(1)
# Additive wave 13: lastKeyReason short; ips small LAN; lastKeyAt unix; htmlRev hN sane; ip exact.
if len(_lkr) > 64:
    print('health contract FAIL: lastKeyReason too long, got', _lkr, file=sys.stderr)
    sys.exit(1)
if len(ips) > 8:
    print('health contract FAIL: ips implausibly many, got', ips, file=sys.stderr)
    sys.exit(1)
if int(h.get('injectCount') or 0) > 0:
    _lka = float(h.get('lastKeyAt') or 0)
    if _lka < 1000000000 or _lka >= 20000000000:
        print('health contract FAIL: lastKeyAt must be unix seconds, got', h.get('lastKeyAt'), file=sys.stderr)
        sys.exit(1)
if int(_hr_parts[2][1:]) > 9999:
    print('health contract FAIL: htmlRev hN implausibly high, got', _hr, file=sys.stderr)
    sys.exit(1)
if ip != ip.strip() or ' ' in ip or '\t' in ip:
    print('health contract FAIL: ip must not have whitespace, got', repr(ip), file=sys.stderr)
    sys.exit(1)
# Additive wave 14: lastKeyCount <= injectCount; htmlRev/ips/urls no whitespace; routeIface short; known gesture phase.
if int(h.get('lastKeyCount') or 0) > int(h.get('injectCount') or 0):
    print('health contract FAIL: lastKeyCount exceeds injectCount, got', h.get('lastKeyCount'), h.get('injectCount'), file=sys.stderr)
    sys.exit(1)
if _hr != _hr.strip() or ' ' in _hr or '\t' in _hr:
    print('health contract FAIL: htmlRev must not have whitespace, got', repr(_hr), file=sys.stderr)
    sys.exit(1)
if any((' ' in str(x) or '\t' in str(x) or str(x) != str(x).strip()) for x in ips):
    print('health contract FAIL: ips items must not have whitespace, got', ips, file=sys.stderr)
    sys.exit(1)
if ' ' in http_url or '\t' in http_url:
    print('health contract FAIL: httpUrl must not have whitespace, got', repr(http_url), file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _hu14 = str(h.get('httpsUrl') or '')
    if ' ' in _hu14 or '\t' in _hu14:
        print('health contract FAIL: httpsUrl must not have whitespace, got', repr(_hu14), file=sys.stderr)
        sys.exit(1)
if len(_ri) < 2 or len(_ri) > 16:
    print('health contract FAIL: routeIface length, got', _ri, file=sys.stderr)
    sys.exit(1)
if int(h.get('gestureCount') or 0) > 0:
    _lgp = int(h.get('lastGesturePhase') or 0)
    if _lgp not in (0, 1, 2, 3, 10, 11, 20, 21, 22, 23, 24):
        print('health contract FAIL: lastGesturePhase not a known trackpad phase, got', _lgp, file=sys.stderr)
        sys.exit(1)
# Additive wave 15: unused inject lastKeyAt zeroed + short placeholder; iface names alnum like routeIface.
if int(h.get('injectCount') or 0) == 0:
    if float(h.get('lastKeyAt') or 0) != 0:
        print('health contract FAIL: unused inject must be lastKeyAt=0, got', h.get('lastKeyAt'), file=sys.stderr)
        sys.exit(1)
    if len(_lk) > 8:
        print('health contract FAIL: unused lastKey too long, got', _lk, file=sys.stderr)
        sys.exit(1)
for _part in str(h.get('ifaces') or '').split(','):
    _part = _part.strip()
    if not _part or '=' not in _part:
        continue
    _iname15 = _part.split('=', 1)[0]
    if not _iname15.isalnum() or not _iname15[0].isalpha() or len(_iname15) < 2 or len(_iname15) > 16:
        print('health contract FAIL: iface name length/alnum, got', _iname15, file=sys.stderr)
        sys.exit(1)
# Additive wave 16: lastKey/lastGesture no backslash; ifaces pair cap; lastKeyCount cap; lastDropAt unix-or-zero.
if any(c == chr(92) for c in _lk) or any(c == chr(92) for c in _lg):
    print('health contract FAIL: lastKey/lastGesture must not be a path, got', _lk, _lg, file=sys.stderr)
    sys.exit(1)
_iface_n = len([p for p in str(h.get('ifaces') or '').split(',') if p.strip()])
if _iface_n < 1 or _iface_n > 8:
    print('health contract FAIL: ifaces pair count, got', h.get('ifaces'), file=sys.stderr)
    sys.exit(1)
if int(h.get('lastKeyCount') or 0) > 64:
    print('health contract FAIL: lastKeyCount implausibly high, got', h.get('lastKeyCount'), file=sys.stderr)
    sys.exit(1)
_lda = float(h.get('lastDropAt') or 0)
if _lda != 0 and (_lda < 1000000000 or _lda >= 20000000000):
    print('health contract FAIL: lastDropAt must be unix seconds, got', h.get('lastDropAt'), file=sys.stderr)
    sys.exit(1)
# Additive wave 17: lastGestureAt unix-or-zero; lastKey/httpsError trimmed tokens (spaces inside lastKey are ok).
_lga17 = float(h.get('lastGestureAt') or 0)
if _lga17 != 0 and (_lga17 < 1000000000 or _lga17 >= 20000000000):
    print('health contract FAIL: lastGestureAt must be unix seconds, got', h.get('lastGestureAt'), file=sys.stderr)
    sys.exit(1)
if _lk != _lk.strip() or _lk.startswith('.') or _lk.endswith('.'):
    print('health contract FAIL: lastKey must be trimmed, got', repr(_lk), file=sys.stderr)
    sys.exit(1)
_he17 = str(h.get('httpsError') or '')
if _he17 != _he17.strip() or ' ' in _he17 or '\t' in _he17:
    print('health contract FAIL: httpsError must not have whitespace, got', repr(_he17), file=sys.stderr)
    sys.exit(1)
if _lkr != _lkr.strip():
    print('health contract FAIL: lastKeyReason must be trimmed, got', repr(_lkr), file=sys.stderr)
    sys.exit(1)
# Additive wave 18: lastKey/lastGesture are tokens not URLs; drop/gesture strings trimmed.
if any(x in _lk for x in ('://', '@', '?', '#')) or any(x in _lg for x in ('://', '@', '?', '#')):
    print('health contract FAIL: lastKey/lastGesture must not look like a URL, got', _lk, _lg, file=sys.stderr)
    sys.exit(1)
if _ldk != _ldk.strip() or _ldr != _ldr.strip():
    print('health contract FAIL: lastDropKind/lastDropReason must be trimmed, got', repr(_ldk), repr(_ldr), file=sys.stderr)
    sys.exit(1)
if _lg != _lg.strip() or _lg.startswith('.') or _lg.endswith('.'):
    print('health contract FAIL: lastGesture must be trimmed, got', repr(_lg), file=sys.stderr)
    sys.exit(1)
if _lgr != _lgr.strip():
    print('health contract FAIL: lastGestureReason must be trimmed, got', repr(_lgr), file=sys.stderr)
    sys.exit(1)
_bp18 = str(h.get('binaryPath') or '')
if _bp18 != _bp18.strip() or ' ' in _bp18 or '\t' in _bp18:
    print('health contract FAIL: binaryPath must not have whitespace, got', repr(_bp18), file=sys.stderr)
    sys.exit(1)
_hs18 = str(h.get('htmlSource') or '')
_hp18 = str(h.get('htmlPath') or '')
if _hs18 != _hs18.strip() or _hp18 != _hp18.strip() or ' ' in _hs18 or ' ' in _hp18:
    print('health contract FAIL: htmlSource/htmlPath must be trimmed, got', repr(_hs18), repr(_hp18), file=sys.stderr)
    sys.exit(1)
# H22: LAN /health must not leak home paths, SSID, or computer name
if '/Users/' in raw or '/home/' in raw:
    print('health privacy FAIL: filesystem path in /health', file=sys.stderr)
    sys.exit(1)
if h.get('ssid'):
    print('health privacy FAIL: ssid must be absent or empty', file=sys.stderr)
    sys.exit(1)
if h.get('appPath'):
    print('health privacy FAIL: appPath must be absent or empty', file=sys.stderr)
    sys.exit(1)
if h.get('mdns'):
    print('health privacy FAIL: mdns must be empty', file=sys.stderr)
    sys.exit(1)
for leak in ('modelPath', 'whisperPath', 'computerName', 'userHome', 'home', 'modelDir', 'cacheDir', 'resourcesPath', 'bundlePath', 'logPath', 'whisperDir'):
    if h.get(leak):
        print('health privacy FAIL: leak key', leak, 'must be absent or empty', file=sys.stderr)
        sys.exit(1)
if h.get('htmlPath') not in ('bundle', 'source'):
    print('health privacy FAIL: htmlPath must be bundle|source, got', h.get('htmlPath'), file=sys.stderr)
    sys.exit(1)
if '/' in str(h.get('binaryPath') or ''):
    print('health privacy FAIL: binaryPath must not be a filesystem path', file=sys.stderr)
    sys.exit(1)
print('health contract PASS lastKey=%r lastKeyReason=%r injectCount=%s lastKeyOk=%s lastKeyAt=%s lastKeyCount=%s ax=%s https=%s httpsPort=%s lastGesture=%r binaryPath=%r htmlRev=%r injectQueue=%s whisperModel=%r stt=%s ip=%r' % (
    h.get('lastKey'), h.get('lastKeyReason'), h.get('injectCount'), h.get('lastKeyOk'), h.get('lastKeyAt'), h.get('lastKeyCount'), h.get('ax'), h.get('https'), h.get('httpsPort'), h.get('lastGesture'), h.get('binaryPath'), h.get('htmlRev'), h.get('injectQueue'), h.get('whisperModel'), h.get('stt'), h.get('ip')))
print(int(h.get('injectCount') or 0))
")"
# last line is injectCount before smoke-type
INJECT_COUNT_BEFORE="$(printf '%s\n' "$INJECT_BEFORE" | tail -n1)"
printf '%s\n' "$INJECT_BEFORE" | sed '$d'

ORIGIN="$ROOT/MagicPadClient/index.html"
BUNDLE="$ROOT/build/MagicPad.app/Contents/Resources/index.html"
if [[ ! -f "$ORIGIN" ]]; then
  echo "html md5 FAIL: missing $ORIGIN" >&2
  exit 1
fi
if [[ ! -f "$BUNDLE" ]]; then
  echo "html md5 FAIL: missing $BUNDLE — run nice -n 19 ./scripts/build_app.sh" >&2
  exit 1
fi

# Additive wave 5: the running /health htmlRev must match the bundle copy (origin may still be mid-edit).
echo "== htmlRev bundle ≡ /health =="
BUNDLE_REV="$(sed -n "s/.*MAGICPAD_HTML_REV = '\\([^']*\\)'.*/\\1/p" "$BUNDLE" | head -n1)"
HEALTH_REV="$(printf '%s' "$HEALTH_JSON" | python3 -c 'import json,sys; print((json.loads(sys.stdin.read()).get("htmlRev") or "").strip())')"
if [[ -z "$BUNDLE_REV" || "$BUNDLE_REV" != "$HEALTH_REV" ]]; then
  echo "htmlRev bundle FAIL: bundle=$BUNDLE_REV health=$HEALTH_REV — restart after --html-only" >&2
  exit 1
fi
echo "htmlRev bundle PASS $BUNDLE_REV"

# Additive wave 10: bundle copy is actual HTML (not an empty/plist stub).
if [[ ! -s "$BUNDLE" ]]; then
  echo "html bundle FAIL: empty $BUNDLE" >&2
  exit 1
fi
if ! grep -qi '<html' "$BUNDLE"; then
  echo "html bundle FAIL: no <html in $BUNDLE" >&2
  exit 1
fi
if ! grep -q "MAGICPAD_HTML_REV" "$BUNDLE"; then
  echo "html bundle FAIL: no MAGICPAD_HTML_REV in $BUNDLE" >&2
  exit 1
fi

# Additive wave 9: model dirs exist even if origin html is mid-edit (md5 still fails below).
echo "== whisper model in app bundle (before html md5) =="
ADVERTISED_MODEL="$(printf '%s' "$HEALTH_JSON" | python3 -c 'import json,sys; print((json.loads(sys.stdin.read()).get("whisperModel") or "").strip())')"
for variant in tiny "$ADVERTISED_MODEL"; do
  _wbase="$ROOT/build/MagicPad.app/Contents/Resources/whisper/openai_whisper-${variant}"
  if [[ ! -d "$_wbase/TextDecoder.mlmodelc" ]]; then
    echo "whisper model FAIL: missing $_wbase/TextDecoder.mlmodelc" >&2
    exit 1
  fi
  if [[ ! -s "$_wbase/TextDecoder.mlmodelc/coremldata.bin" ]]; then
    echo "whisper cores FAIL: empty/missing $_wbase/TextDecoder.mlmodelc/coremldata.bin" >&2
    exit 1
  fi
  if [[ ! -s "$_wbase/tokenizer.json" ]]; then
    echo "whisper tokenizer FAIL: empty/missing $_wbase/tokenizer.json" >&2
    exit 1
  fi
  # Additive wave 10: all 3 cores + vocab still checked when origin html is mid-edit.
  for core in TextDecoder.mlmodelc AudioEncoder.mlmodelc MelSpectrogram.mlmodelc; do
    if [[ ! -d "$_wbase/$core" ]]; then
      echo "whisper cores FAIL: missing $_wbase/$core" >&2
      exit 1
    fi
    if [[ ! -s "$_wbase/$core/coremldata.bin" ]]; then
      echo "whisper cores FAIL: empty/missing $_wbase/$core/coremldata.bin" >&2
      exit 1
    fi
  done
  if [[ ! -s "$_wbase/vocab.json" ]]; then
    echo "whisper tokenizer FAIL: empty/missing $_wbase/vocab.json" >&2
    exit 1
  fi
  _tok_sz="$(wc -c < "$_wbase/tokenizer.json" | tr -d ' ')"
  if [[ "$_tok_sz" -lt 1000 ]]; then
    echo "whisper tokenizer FAIL: tokenizer.json too small ($_tok_sz) in $_wbase" >&2
    exit 1
  fi
  # Additive wave 11: tokenizer/vocab are real JSON; decoder weights not a stub.
  if [[ "$_tok_sz" -lt 10000 ]]; then
    echo "whisper tokenizer FAIL: tokenizer.json too small for a real tokenizer ($_tok_sz) in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,(dict,list)) and j" "$_wbase/tokenizer.json"; then
    echo "whisper tokenizer FAIL: tokenizer.json not valid JSON in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,(dict,list)) and j" "$_wbase/vocab.json"; then
    echo "whisper tokenizer FAIL: vocab.json not valid JSON in $_wbase" >&2
    exit 1
  fi
  if [[ ! -s "$_wbase/TextDecoder.mlmodelc/weights/weight.bin" ]]; then
    echo "whisper cores FAIL: empty/missing $_wbase/TextDecoder.mlmodelc/weights/weight.bin" >&2
    exit 1
  fi
  # Additive wave 12: encoder+mel weights not stubs; config.json is a Whisper config.
  if [[ ! -s "$_wbase/AudioEncoder.mlmodelc/weights/weight.bin" ]]; then
    echo "whisper cores FAIL: empty/missing $_wbase/AudioEncoder.mlmodelc/weights/weight.bin" >&2
    exit 1
  fi
  if [[ ! -s "$_wbase/MelSpectrogram.mlmodelc/weights/weight.bin" ]]; then
    echo "whisper cores FAIL: empty/missing $_wbase/MelSpectrogram.mlmodelc/weights/weight.bin" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and j.get('model_type')=='whisper'" "$_wbase/config.json"; then
    echo "whisper config FAIL: config.json not a Whisper JSON in $_wbase" >&2
    exit 1
  fi
  # Additive wave 13: generation/preprocessor/tokenizer configs + model.mil + decoder weights size.
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and 'eos_token_id' in j" "$_wbase/generation_config.json"; then
    echo "whisper config FAIL: generation_config.json not a Whisper JSON in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and j.get('feature_extractor_type')" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json missing feature_extractor_type in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and j" "$_wbase/tokenizer_config.json"; then
    echo "whisper tokenizer FAIL: tokenizer_config.json not valid JSON in $_wbase" >&2
    exit 1
  fi
  for core in TextDecoder.mlmodelc AudioEncoder.mlmodelc MelSpectrogram.mlmodelc; do
    if [[ ! -s "$_wbase/$core/model.mil" ]]; then
      echo "whisper cores FAIL: empty/missing $_wbase/$core/model.mil" >&2
      exit 1
    fi
  done
  _dec_w="$(wc -c < "$_wbase/TextDecoder.mlmodelc/weights/weight.bin" | tr -d ' ')"
  if [[ "$_dec_w" -lt 1000000 ]]; then
    echo "whisper cores FAIL: TextDecoder weight.bin too small ($_dec_w) in $_wbase" >&2
    exit 1
  fi
  # Additive wave 14: tokenizer extras + config vocab + encoder weights size.
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and j.get('eos_token')" "$_wbase/special_tokens_map.json"; then
    echo "whisper tokenizer FAIL: special_tokens_map.json missing eos_token in $_wbase" >&2
    exit 1
  fi
  _merges="$(wc -c < "$_wbase/merges.txt" | tr -d ' ')"
  if [[ "$_merges" -lt 1000 ]]; then
    echo "whisper tokenizer FAIL: merges.txt too small ($_merges) in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j.get('vocab_size'), int) and j['vocab_size'] > 1000" "$_wbase/config.json"; then
    echo "whisper config FAIL: config.json vocab_size missing in $_wbase" >&2
    exit 1
  fi
  _enc_w="$(wc -c < "$_wbase/AudioEncoder.mlmodelc/weights/weight.bin" | tr -d ' ')"
  if [[ "$_enc_w" -lt 1000000 ]]; then
    echo "whisper cores FAIL: AudioEncoder weight.bin too small ($_enc_w) in $_wbase" >&2
    exit 1
  fi
  # Additive wave 15: 16 kHz preprocessor + decoder_start + tokenizer_class + bos + mel weights.
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('sampling_rate')==16000" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json sampling_rate not 16000 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert 'decoder_start_token_id' in j" "$_wbase/generation_config.json"; then
    echo "whisper config FAIL: generation_config.json missing decoder_start_token_id in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('tokenizer_class')" "$_wbase/tokenizer_config.json"; then
    echo "whisper tokenizer FAIL: tokenizer_config.json missing tokenizer_class in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('bos_token')" "$_wbase/special_tokens_map.json"; then
    echo "whisper tokenizer FAIL: special_tokens_map.json missing bos_token in $_wbase" >&2
    exit 1
  fi
  _mel_w="$(wc -c < "$_wbase/MelSpectrogram.mlmodelc/weights/weight.bin" | tr -d ' ')"
  if [[ "$_mel_w" -lt 1000 ]]; then
    echo "whisper cores FAIL: MelSpectrogram weight.bin too small ($_mel_w) in $_wbase" >&2
    exit 1
  fi
  # Additive wave 16: pad tokens + 16 kHz hop + tokenizer model + vocab size + model.mil size.
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('pad_token')" "$_wbase/special_tokens_map.json"; then
    echo "whisper tokenizer FAIL: special_tokens_map.json missing pad_token in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert 'pad_token_id' in j" "$_wbase/generation_config.json"; then
    echo "whisper config FAIL: generation_config.json missing pad_token_id in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('hop_length')==160" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json hop_length not 160 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j,dict) and j.get('model')" "$_wbase/tokenizer.json"; then
    echo "whisper tokenizer FAIL: tokenizer.json missing model in $_wbase" >&2
    exit 1
  fi
  _vocab_sz="$(wc -c < "$_wbase/vocab.json" | tr -d ' ')"
  if [[ "$_vocab_sz" -lt 10000 ]]; then
    echo "whisper tokenizer FAIL: vocab.json too small ($_vocab_sz) in $_wbase" >&2
    exit 1
  fi
  for core in TextDecoder.mlmodelc AudioEncoder.mlmodelc MelSpectrogram.mlmodelc; do
    _mil="$(wc -c < "$_wbase/$core/model.mil" | tr -d ' ')"
    if [[ "$_mil" -lt 1000 ]]; then
      echo "whisper cores FAIL: $core model.mil too small ($_mil) in $_wbase" >&2
      exit 1
    fi
  done
  # Additive wave 17: unk/bos ids + 16 kHz FFT/mel bins (same on tiny+advertised).
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('unk_token')" "$_wbase/special_tokens_map.json"; then
    echo "whisper tokenizer FAIL: special_tokens_map.json missing unk_token in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert 'bos_token_id' in j" "$_wbase/generation_config.json"; then
    echo "whisper config FAIL: generation_config.json missing bos_token_id in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('n_fft')==400" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json n_fft not 400 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('feature_size')==80" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json feature_size not 80 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('unk_token') or j.get('pad_token')" "$_wbase/tokenizer_config.json"; then
    echo "whisper tokenizer FAIL: tokenizer_config.json missing unk/pad token in $_wbase" >&2
    exit 1
  fi
  # Additive wave 18: 30s chunk + 80 mel bins + bos + max_length + decoder metadata.
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('chunk_length')==30" "$_wbase/preprocessor_config.json"; then
    echo "whisper config FAIL: preprocessor_config.json chunk_length not 30 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('num_mel_bins')==80" "$_wbase/config.json"; then
    echo "whisper config FAIL: config.json num_mel_bins not 80 in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j.get('bos_token')" "$_wbase/tokenizer_config.json"; then
    echo "whisper tokenizer FAIL: tokenizer_config.json missing bos_token in $_wbase" >&2
    exit 1
  fi
  if ! python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert isinstance(j.get('max_length'), int) and j['max_length']>0" "$_wbase/generation_config.json"; then
    echo "whisper config FAIL: generation_config.json missing max_length in $_wbase" >&2
    exit 1
  fi
  if [[ ! -s "$_wbase/TextDecoder.mlmodelc/metadata.json" ]]; then
    echo "whisper cores FAIL: empty/missing $_wbase/TextDecoder.mlmodelc/metadata.json" >&2
    exit 1
  fi
done
echo "whisper model early PASS tiny+${ADVERTISED_MODEL}"

echo "== html md5 (origin ≡ Resources) =="
ORIGIN_MD5="$(md5 -q "$ORIGIN" 2>/dev/null || md5sum "$ORIGIN" | awk '{print $1}')"
BUNDLE_MD5="$(md5 -q "$BUNDLE" 2>/dev/null || md5sum "$BUNDLE" | awk '{print $1}')"
if [[ "$ORIGIN_MD5" != "$BUNDLE_MD5" ]]; then
  ORIGIN_BYTES="$(wc -c < "$ORIGIN" | tr -d ' ')"
  BUNDLE_BYTES="$(wc -c < "$BUNDLE" | tr -d ' ')"
  ORIGIN_REV="$(sed -n "s/.*MAGICPAD_HTML_REV = '\\([^']*\\)'.*/\\1/p" "$ORIGIN" | head -n1)"
  echo "html md5 FAIL: origin=$ORIGIN_MD5 resources=$BUNDLE_MD5 originBytes=$ORIGIN_BYTES resourcesBytes=$BUNDLE_BYTES originRev=$ORIGIN_REV resourcesRev=$BUNDLE_REV — sync index.html into the app bundle" >&2
  exit 1
fi
echo "html md5 PASS $ORIGIN_MD5"

echo "== whisper model in app bundle =="
MODEL_DEC=""
for cand in "$ROOT"/build/MagicPad.app/Contents/Resources/whisper/openai_whisper-*/TextDecoder.mlmodelc; do
  if [[ -d "$cand" ]]; then
    MODEL_DEC="$cand"
    break
  fi
done
if [[ -z "$MODEL_DEC" ]]; then
  echo "whisper model FAIL: no TextDecoder.mlmodelc under Resources/whisper/openai_whisper-*" >&2
  exit 1
fi
echo "whisper model PASS $MODEL_DEC"

# Additive wave 2: the variant /health advertises must exist in the bundle.
ADVERTISED_MODEL="$(printf '%s' "$HEALTH_JSON" | python3 -c 'import json,sys; print((json.loads(sys.stdin.read()).get("whisperModel") or "").strip())')"
ADVERTISED_DEC="$ROOT/build/MagicPad.app/Contents/Resources/whisper/openai_whisper-${ADVERTISED_MODEL}/TextDecoder.mlmodelc"
if [[ -z "$ADVERTISED_MODEL" || ! -d "$ADVERTISED_DEC" ]]; then
  echo "whisper advertised FAIL: /health whisperModel=${ADVERTISED_MODEL:-empty} missing $ADVERTISED_DEC" >&2
  exit 1
fi
echo "whisper advertised PASS $ADVERTISED_DEC"

# Additive wave 4: tiny fallback stays, and advertised + tiny each have the 3 Core ML cores.
echo "== whisper complete mlmodelc (tiny fallback + advertised) =="
for variant in tiny "$ADVERTISED_MODEL"; do
  _wbase="$ROOT/build/MagicPad.app/Contents/Resources/whisper/openai_whisper-${variant}"
  for core in TextDecoder.mlmodelc AudioEncoder.mlmodelc MelSpectrogram.mlmodelc; do
    if [[ ! -d "$_wbase/$core" ]]; then
      echo "whisper cores FAIL: missing $_wbase/$core" >&2
      exit 1
    fi
  done
  # Additive wave 5: tokenizer files stay next to the Core ML cores.
  # Additive wave 6: config + tokenizer_config, and TextDecoder has coremldata.bin.
  for extra in tokenizer.json vocab.json config.json tokenizer_config.json generation_config.json preprocessor_config.json merges.txt special_tokens_map.json; do
    if [[ ! -f "$_wbase/$extra" ]]; then
      echo "whisper tokenizer FAIL: missing $_wbase/$extra" >&2
      exit 1
    fi
  done
  # Additive wave 7: every Core ML core ships coremldata.bin (not decoder-only).
  for core in TextDecoder.mlmodelc AudioEncoder.mlmodelc MelSpectrogram.mlmodelc; do
    if [[ ! -f "$_wbase/$core/coremldata.bin" ]]; then
      echo "whisper cores FAIL: missing $_wbase/$core/coremldata.bin" >&2
      exit 1
    fi
  done
done
echo "whisper cores PASS tiny+${ADVERTISED_MODEL}"

echo "== drop mp4 (m4a name + audio/mp4 → kind=video .mp4) =="
# Minimal ISO BMFF ftyp so preferredExt sees mp4; paste=0 so smoke never Cmd+V
DROP_JSON="$(printf '\x00\x00\x00\x18ftypisom\x00\x00\x00\x00mp41' | curl -sS --noproxy '*' --max-time 5 \
  -X POST "$BASE/drop?paste=0&name=web-recording.m4a" \
  -H 'Content-Type: audio/mp4' \
  -H 'X-MagicPad-Filename: web-recording.m4a' \
  --data-binary @-)"
printf '%s' "$DROP_JSON" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    j = json.loads(raw)
except Exception as e:
    print('drop mp4 FAIL: bad json', e, raw[:200], file=sys.stderr)
    sys.exit(1)
if not j.get('ok'):
    print('drop mp4 FAIL: ok=false', j, file=sys.stderr)
    sys.exit(1)
name = str(j.get('name') or '')
kind = str(j.get('kind') or '')
if not name.lower().endswith('.mp4'):
    print('drop mp4 FAIL: name not .mp4', name, file=sys.stderr)
    sys.exit(1)
if kind != 'video':
    print('drop mp4 FAIL: kind=%r want video' % kind, file=sys.stderr)
    sys.exit(1)
print('drop mp4 PASS name=%s kind=%s bytes=%s' % (name, kind, j.get('bytes')))
"

echo "== smoke-ws =="
python3 "$ROOT/scripts/smoke-ws.py"
echo "== smoke-type =="
python3 "$ROOT/scripts/smoke-type.py"

echo "== health after smoke-type (injectCount ≥ before + lastKeyReason + lastKeyCount) =="
HEALTH_AFTER="$(curl -sS --noproxy '*' --max-time 3 "$BASE/health")"
printf '%s' "$HEALTH_AFTER" | python3 -c "
import json, sys
before = int(sys.argv[1])
raw = sys.stdin.read()
h = json.loads(raw)
after = int(h.get('injectCount') or 0)
need = ('lastKey', 'lastKeyReason', 'injectCount', 'lastKeyOk', 'lastKeyAt', 'lastKeyCount')
missing = [k for k in need if k not in h]
if missing:
    print('post-type health FAIL: missing', missing)
    sys.exit(1)
if not isinstance(h.get('lastKeyReason'), str):
    print('post-type health FAIL: lastKeyReason must be str')
    sys.exit(1)
if not isinstance(h.get('lastKeyCount'), (int, float)):
    print('post-type health FAIL: lastKeyCount must be number, got', type(h.get('lastKeyCount')).__name__)
    sys.exit(1)
if after < before:
    print('post-type health FAIL: injectCount %s < before %s' % (after, before))
    sys.exit(1)
print('post-type health PASS injectCount %s → %s lastKey=%r lastKeyReason=%r lastKeyOk=%s lastKeyAt=%s lastKeyCount=%s' % (
    before, after, h.get('lastKey'), h.get('lastKeyReason'), h.get('lastKeyOk'), h.get('lastKeyAt'), h.get('lastKeyCount')))
sys.exit(0)
" "$INJECT_COUNT_BEFORE"

# HTTPS last (OPT-26): isolated WARN — TLS handshake stalls must not block HTTP smoke.
# Default short timeout + 0 retries inside smoke-all; override via HTTPS_TIMEOUT / HTTPS_RETRIES.
echo "== smoke-https (isolated; WARN only if TLS down; after HTTP smoke) =="
set +e
HTTPS_OUT="$(
  HTTPS_TIMEOUT="${HTTPS_TIMEOUT:-4}" \
  HTTPS_RETRIES="${HTTPS_RETRIES:-0}" \
  python3 "$ROOT/scripts/smoke-https.py" 2>&1
)"
HTTPS_RC=$?
set -e
printf '%s\n' "$HTTPS_OUT"
if [[ "$HTTPS_RC" -ne 0 ]]; then
  # OPT-26: surface stage/reason from smoke-https FAIL line (app_down | tls_handshake | …)
  STAGE_STR="$(printf '%s\n' "$HTTPS_OUT" | grep -E 'smoke-https FAIL' | tail -n1 | tr -d '\r' || true)"
  if [[ -z "$STAGE_STR" ]]; then
    STAGE_STR="(no FAIL line; exit=$HTTPS_RC)"
  fi
  echo "WARN: smoke-https exit=$HTTPS_RC — $STAGE_STR — HTTP smoke continues" >&2
else
  echo "smoke-https subsection OK"
fi

echo "smoke-all DONE"
