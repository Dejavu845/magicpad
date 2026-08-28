#!/usr/bin/env bash
# Lane TEST: say → wav → POST /stt. Does not change product code.
set -euo pipefail
BASE="${BASE_URL:-http://127.0.0.1:7878}"
PHRASE="${STT_PHRASE:-hello magic pad}"
LANG="${STT_LANG:-en-US}"
TMPDIR="${TMPDIR:-/tmp}"
AIFF="$TMPDIR/magicpad-stt-smoke.aiff"
WAV="$TMPDIR/magicpad-stt-smoke.wav"

say -o "$AIFF" "$PHRASE"
afconvert "$AIFF" "$WAV" -d LEI16 -f WAVE -r 16000
BYTES="$(wc -c < "$WAV" | tr -d ' ')"
echo "== stt-smoke phrase=$PHRASE bytes=$BYTES lang=$LANG =="

START_MS="$(python3 -c 'import time; print(int(time.time()*1000))')"
STT_HDR="$TMPDIR/magicpad-stt-smoke.hdrs"
STT_RAW="$(curl -sS --noproxy '*' --max-time "${STT_TIMEOUT:-90}" \
  -D "$STT_HDR" \
  -w '\n%{http_code}' \
  -X POST "$BASE/stt" \
  -H "Content-Type: audio/wav" \
  -H "X-MagicPad-Lang: $LANG" \
  -H "X-MagicPad-Filename: magicpad-stt-smoke.wav" \
  --data-binary @"$WAV")"
END_MS="$(python3 -c 'import time; print(int(time.time()*1000))')"
MS="$((END_MS - START_MS))"
# Additive wave 9: /stt must be HTTP 200 JSON (status captured without dropping the body).
STT_CODE="$(printf '%s\n' "$STT_RAW" | tail -n1)"
STT_JSON="$(printf '%s\n' "$STT_RAW" | sed '$d')"
if [[ "$STT_CODE" != "200" ]]; then
  echo "stt-smoke FAIL: HTTP $STT_CODE body=$(printf '%s' "$STT_JSON" | head -c 200)" >&2
  exit 1
fi
# Additive wave 10: /stt is uncached JSON with MagicPad header (same HTTP stack as /health).
STT_HDRS="$(tr -d '\r' < "$STT_HDR")"
STT_CT="$(printf '%s\n' "$STT_HDRS" | grep -i '^content-type:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
case "$STT_CT" in
  application/json*) ;;
  *) echo "stt-smoke FAIL: Content-Type $STT_CT" >&2; exit 1 ;;
esac
if [[ "$STT_CT" != *charset=utf-8* ]]; then
  echo "stt-smoke FAIL: Content-Type must include charset=utf-8, got $STT_CT" >&2
  exit 1
fi
STT_XM="$(printf '%s\n' "$STT_HDRS" | grep -i '^X-MagicPad:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$STT_XM" != "1" ]]; then
  echo "stt-smoke FAIL: X-MagicPad must be 1, got ${STT_XM:-missing}" >&2
  exit 1
fi
STT_CC="$(printf '%s\n' "$STT_HDRS" | grep -i '^cache-control:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_CC" != *no-store* ]]; then
  echo "stt-smoke FAIL: Cache-Control must include no-store, got $STT_CC" >&2
  exit 1
fi
# Additive wave 11: same cache/CORS stack as /health (phone POST /stt).
if [[ "$STT_CC" != *no-cache* ]]; then
  echo "stt-smoke FAIL: Cache-Control must include no-cache, got $STT_CC" >&2
  exit 1
fi
STT_PRAGMA="$(printf '%s\n' "$STT_HDRS" | grep -i '^Pragma:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_PRAGMA" != *no-cache* ]]; then
  echo "stt-smoke FAIL: Pragma must include no-cache, got ${STT_PRAGMA:-missing}" >&2
  exit 1
fi
STT_EXPIRES="$(printf '%s\n' "$STT_HDRS" | grep -i '^Expires:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$STT_EXPIRES" != "0" ]]; then
  echo "stt-smoke FAIL: Expires must be 0, got ${STT_EXPIRES:-missing}" >&2
  exit 1
fi
STT_ACAO="$(printf '%s\n' "$STT_HDRS" | grep -i '^Access-Control-Allow-Origin:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$STT_ACAO" != "*" ]]; then
  echo "stt-smoke FAIL: CORS origin must be *, got ${STT_ACAO:-missing}" >&2
  exit 1
fi
STT_ACAM="$(printf '%s\n' "$STT_HDRS" | grep -i '^Access-Control-Allow-Methods:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_ACAM" != *post* ]]; then
  echo "stt-smoke FAIL: CORS methods must include POST, got ${STT_ACAM:-missing}" >&2
  exit 1
fi
# Additive wave 12: same extra cache/CORS tokens as /health (phone POST /stt).
if [[ "$STT_CC" != *max-age=0* ]]; then
  echo "stt-smoke FAIL: Cache-Control must include max-age=0, got $STT_CC" >&2
  exit 1
fi
if [[ "$STT_ACAM" != *options* ]]; then
  echo "stt-smoke FAIL: CORS methods must include OPTIONS, got ${STT_ACAM:-missing}" >&2
  exit 1
fi
STT_ACAH="$(printf '%s\n' "$STT_HDRS" | grep -i '^Access-Control-Allow-Headers:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_ACAH" != *x-magicpad-lang* ]]; then
  echo "stt-smoke FAIL: CORS headers must include X-MagicPad-Lang, got ${STT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 13: phone POST /stt CORS Content-Type; OPTIONS preflight.
if [[ "$STT_ACAH" != *content-type* ]]; then
  echo "stt-smoke FAIL: CORS headers must include Content-Type, got ${STT_ACAH:-missing}" >&2
  exit 1
fi
STT_OPT_HDRS="$(curl -sS --noproxy '*' --max-time 3 -D - -o /dev/null -X OPTIONS "$BASE/stt" | tr -d '\r')"
STT_OPT_CODE="$(printf '%s\n' "$STT_OPT_HDRS" | head -n1)"
if [[ "$STT_OPT_CODE" != *" 204"* && "$STT_OPT_CODE" != *" 200"* ]]; then
  echo "stt-smoke FAIL: OPTIONS $STT_OPT_CODE" >&2
  exit 1
fi
STT_OPT_ACAO="$(printf '%s\n' "$STT_OPT_HDRS" | grep -i '^Access-Control-Allow-Origin:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//')"
if [[ "$STT_OPT_ACAO" != "*" ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS origin must be *, got ${STT_OPT_ACAO:-missing}" >&2
  exit 1
fi
# Additive wave 14: OPTIONS 204 + POST + X-MagicPad-Lang (phone preflight).
if [[ "$STT_OPT_CODE" != *" 204"* ]]; then
  echo "stt-smoke FAIL: OPTIONS must be 204, got $STT_OPT_CODE" >&2
  exit 1
fi
STT_OPT_ACAM="$(printf '%s\n' "$STT_OPT_HDRS" | grep -i '^Access-Control-Allow-Methods:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_OPT_ACAM" != *post* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS methods must include POST, got ${STT_OPT_ACAM:-missing}" >&2
  exit 1
fi
STT_OPT_ACAH="$(printf '%s\n' "$STT_OPT_HDRS" | grep -i '^Access-Control-Allow-Headers:' | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
if [[ "$STT_OPT_ACAH" != *x-magicpad-lang* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS headers must include X-MagicPad-Lang, got ${STT_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 15: OPTIONS CORS Content-Type (phone POST /stt preflight).
if [[ "$STT_OPT_ACAH" != *content-type* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS headers must include Content-Type, got ${STT_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 16: OPTIONS CORS drop/stt filename (same Allow-Headers as /health).
if [[ "$STT_OPT_ACAH" != *x-magicpad-filename* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS headers must include X-MagicPad-Filename, got ${STT_OPT_ACAH:-missing}" >&2
  exit 1
fi
# Additive wave 17: POST CORS filename; OPTIONS AutoPaste (same Allow-Headers as /health).
if [[ "$STT_ACAH" != *x-magicpad-filename* ]]; then
  echo "stt-smoke FAIL: CORS headers must include X-MagicPad-Filename, got ${STT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$STT_OPT_ACAH" != *x-magicpad-autopaste* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS headers must include X-MagicPad-AutoPaste, got ${STT_OPT_ACAH:-missing}" >&2
  exit 1
fi
if [[ "$STT_OPT_ACAM" != *options* ]]; then
  echo "stt-smoke FAIL: OPTIONS CORS methods must include OPTIONS, got ${STT_OPT_ACAM:-missing}" >&2
  exit 1
fi
# Additive wave 18: POST CORS AutoPaste (same Allow-Headers as /health).
if [[ "$STT_ACAH" != *x-magicpad-autopaste* ]]; then
  echo "stt-smoke FAIL: CORS headers must include X-MagicPad-AutoPaste, got ${STT_ACAH:-missing}" >&2
  exit 1
fi

printf '%s' "$STT_JSON" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    j = json.loads(raw)
except Exception as e:
    print('stt-smoke FAIL: bad json', e, raw[:240], file=sys.stderr)
    sys.exit(1)
ok = bool(j.get('ok'))
text = str(j.get('text') or '')
engine = str(j.get('engine') or '')
print('stt-smoke ok=%s engine=%s len=%s onDevice=%s bytes=%s ms=%s text=%r reason=%r' % (
    ok, engine, len(text), j.get('onDevice'), j.get('bytes'), $MS, text, j.get('reason')))
if not ok:
    sys.exit(1)
need_stt = ('ok', 'engine', 'text', 'onDevice', 'bytes')
missing = [k for k in need_stt if k not in j]
if missing:
    print('stt-smoke FAIL: missing keys', missing, file=sys.stderr)
    sys.exit(1)
# Additive: on-device Whisper only (no Apple Speech / cloud LLM).
if engine != 'whisper':
    print('stt-smoke FAIL: engine must be whisper, got', engine, file=sys.stderr)
    sys.exit(1)
# Additive wave 6: ok /stt must not look like Apple/cloud, reason empty/none.
eng = engine.lower()
if any(x in eng for x in ('apple', 'openai', 'cloud')):
    print('stt-smoke FAIL: engine looks like cloud/apple, got', engine, file=sys.stderr)
    sys.exit(1)
reason = j.get('reason')
if reason not in (None, '', 'none', 'ok'):
    print('stt-smoke FAIL: ok response reason must be empty/none, got', reason, file=sys.stderr)
    sys.exit(1)
if not text.strip():
    print('stt-smoke FAIL: empty text', file=sys.stderr)
    sys.exit(1)
if j.get('onDevice') is not True:
    print('stt-smoke FAIL: onDevice must be true', file=sys.stderr)
    sys.exit(1)
if int(j.get('bytes') or 0) <= 0:
    print('stt-smoke FAIL: bytes must be > 0', file=sys.stderr)
    sys.exit(1)
if '/Users/' in raw or '/home/' in raw:
    print('stt-smoke FAIL: filesystem path in /stt', file=sys.stderr)
    sys.exit(1)
# Additive wave 5: engine is on-device Whisper (not apple/cloud).
if engine.lower() != 'whisper':
    print('stt-smoke FAIL: engine must be whisper (case-insensitive), got', engine, file=sys.stderr)
    sys.exit(1)
# Additive wave 7: transcription is real text; no cloud endpoint leak in /stt JSON.
if len(text.strip()) < 3:
    print('stt-smoke FAIL: text too short', repr(text), file=sys.stderr)
    sys.exit(1)
_raw_l = raw.lower()
if any(x in _raw_l for x in ('openai.com', 'api.openai', 'huggingface.co', 'anthropic.com', 'generativelanguage', 'api.grok')):
    print('stt-smoke FAIL: cloud endpoint in /stt JSON', file=sys.stderr)
    sys.exit(1)
# Additive wave 8: wav size echoed back; text has letters; no home-path-looking engine.
if int(j.get('bytes') or 0) != $BYTES:
    print('stt-smoke FAIL: bytes must match wav size', j.get('bytes'), $BYTES, file=sys.stderr)
    sys.exit(1)
if not any(c.isalpha() for c in text):
    print('stt-smoke FAIL: text has no letters', repr(text), file=sys.stderr)
    sys.exit(1)
if '/' in engine:
    print('stt-smoke FAIL: engine must not be a path, got', engine, file=sys.stderr)
    sys.exit(1)
# Additive wave 9: typed JSON; no error payload on ok.
if type(j.get('ok')) is not bool:
    print('stt-smoke FAIL: ok must be json bool, got', type(j.get('ok')).__name__, file=sys.stderr)
    sys.exit(1)
if type(j.get('onDevice')) is not bool:
    print('stt-smoke FAIL: onDevice must be json bool, got', type(j.get('onDevice')).__name__, file=sys.stderr)
    sys.exit(1)
if type(j.get('bytes')) is not int:
    print('stt-smoke FAIL: bytes must be int, got', type(j.get('bytes')).__name__, file=sys.stderr)
    sys.exit(1)
if j.get('error') not in (None, '', False):
    print('stt-smoke FAIL: error must be empty on ok /stt, got', j.get('error'), file=sys.stderr)
    sys.exit(1)
# Additive wave 10: typed text/engine; transcription shorter than the wav; no home path in text.
if type(j.get('text')) is not str:
    print('stt-smoke FAIL: text must be json str, got', type(j.get('text')).__name__, file=sys.stderr)
    sys.exit(1)
if type(j.get('engine')) is not str:
    print('stt-smoke FAIL: engine must be json str, got', type(j.get('engine')).__name__, file=sys.stderr)
    sys.exit(1)
if len(text) > int(j.get('bytes') or 0):
    print('stt-smoke FAIL: text longer than wav bytes', len(text), j.get('bytes'), file=sys.stderr)
    sys.exit(1)
if '/Users/' in text or '/home/' in text:
    print('stt-smoke FAIL: filesystem path in transcription', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 11: transcription is short speech not HTML; wav is real audio; no path keys.
if len(text) > 200:
    print('stt-smoke FAIL: text implausibly long for say-wav', len(text), repr(text[:80]), file=sys.stderr)
    sys.exit(1)
if '<' in text or '>' in text:
    print('stt-smoke FAIL: transcription looks like HTML', repr(text), file=sys.stderr)
    sys.exit(1)
if int(j.get('bytes') or 0) < 8000:
    print('stt-smoke FAIL: wav bytes too small', j.get('bytes'), file=sys.stderr)
    sys.exit(1)
for leak in ('modelPath', 'whisperPath', 'userHome', 'home', 'cacheDir', 'bundlePath'):
    if j.get(leak):
        print('stt-smoke FAIL: leak key', leak, file=sys.stderr)
        sys.exit(1)
# Additive wave 12: transcription is one utterance; engine is a short token.
if any(ord(c) < 32 for c in text):
    print('stt-smoke FAIL: transcription has control chars', repr(text), file=sys.stderr)
    sys.exit(1)
if len(engine) > 32 or (not all((c.isalnum() or c == '_') for c in engine)):
    print('stt-smoke FAIL: engine must be a short token, got', engine, file=sys.stderr)
    sys.exit(1)
# Additive wave 13: transcription is speech, not a URL / blank-padded dump.
_tl = text.lower()
if 'http://' in _tl or 'https://' in _tl or 'www.' in _tl:
    print('stt-smoke FAIL: transcription looks like a URL', repr(text), file=sys.stderr)
    sys.exit(1)
if text != text.strip():
    print('stt-smoke FAIL: transcription has surrounding whitespace', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 14: transcription is speech, not a path fragment.
if '/' in text:
    print('stt-smoke FAIL: transcription looks like a path', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 15: transcription is speech, not a Windows path fragment.
if any(c == chr(92) for c in text):
    print('stt-smoke FAIL: transcription looks like a path', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 16: transcription is speech, not a URL/email fragment.
if '://' in text:
    print('stt-smoke FAIL: transcription looks like a URL', repr(text), file=sys.stderr)
    sys.exit(1)
if '@' in text:
    print('stt-smoke FAIL: transcription looks like an email', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 17: transcription is speech, not a query/fragment.
if '?' in text or '#' in text:
    print('stt-smoke FAIL: transcription looks like a URL fragment', repr(text), file=sys.stderr)
    sys.exit(1)
# Additive wave 18: transcription is speech, not a query string.
if '&' in text:
    print('stt-smoke FAIL: transcription looks like a query string', repr(text), file=sys.stderr)
    sys.exit(1)
"

# Additive wave 5: after a successful /stt the advertised model is warm in-process.
HEALTH_AFTER="$(curl -sS --noproxy '*' --max-time 3 "$BASE/health")"
printf '%s' "$HEALTH_AFTER" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    h = json.loads(raw)
except Exception as e:
    print('stt-smoke FAIL: /health after stt bad json', e, file=sys.stderr)
    sys.exit(1)
if h.get('whisperReady') is not True:
    print('stt-smoke FAIL: whisperReady must be true after /stt, got', h.get('whisperReady'), file=sys.stderr)
    sys.exit(1)
if h.get('whisperCached') is not True:
    print('stt-smoke FAIL: whisperCached must be true after /stt, got', h.get('whisperCached'), file=sys.stderr)
    sys.exit(1)
if h.get('whisper') is not True:
    print('stt-smoke FAIL: whisper must be true after /stt', file=sys.stderr)
    sys.exit(1)
_wm = str(h.get('whisperModel') or '').strip()
if _wm not in ('tiny', 'base', 'small', 'medium', 'large', 'large-v2', 'large-v3'):
    print('stt-smoke FAIL: whisperModel after /stt must be a known variant, got', _wm, file=sys.stderr)
    sys.exit(1)
if '/Users/' in raw or '/home/' in raw:
    print('stt-smoke FAIL: filesystem path in /health after /stt', file=sys.stderr)
    sys.exit(1)
# Additive wave 6: post-/stt /health still advertises a usable htmlRev + LAN, no mdns leak.
_hr = str(h.get('htmlRev') or '').strip()
_hr_parts = _hr.split('-')
if not (len(_hr_parts) == 3 and _hr_parts[0].isdigit() and len(_hr_parts[0]) == 8 and _hr_parts[1].isdigit() and len(_hr_parts[1]) == 4 and _hr_parts[2].startswith('h') and _hr_parts[2][1:].isdigit()):
    print('stt-smoke FAIL: htmlRev after /stt must be YYYYMMDD-HHMM-hN, got', _hr, file=sys.stderr)
    sys.exit(1)
if not isinstance(h.get('https'), bool):
    print('stt-smoke FAIL: https must be bool after /stt, got', h.get('https'), file=sys.stderr)
    sys.exit(1)
if str(h.get('mdns') or '') != '':
    print('stt-smoke FAIL: mdns must stay empty after /stt, got', h.get('mdns'), file=sys.stderr)
    sys.exit(1)
# Additive wave 7: STT must not flip LAN/bundle/STT flags.
if h.get('stt') is not True or h.get('sttFile') is not True:
    print('stt-smoke FAIL: stt/sttFile must stay true after /stt, got', h.get('stt'), h.get('sttFile'), file=sys.stderr)
    sys.exit(1)
if h.get('html') is True and h.get('htmlSource') != 'bundle':
    print('stt-smoke FAIL: htmlSource must stay bundle after /stt, got', h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
if str(h.get('binaryPath') or '') != 'MagicPad.app':
    print('stt-smoke FAIL: binaryPath must stay MagicPad.app after /stt, got', h.get('binaryPath'), file=sys.stderr)
    sys.exit(1)
_ip = str(h.get('ip') or '').strip()
_ip_parts = _ip.split('.')
if len(_ip_parts) != 4 or any((not p.isdigit() or int(p) > 255) for p in _ip_parts):
    print('stt-smoke FAIL: ip must be IPv4 host after /stt, got', _ip, file=sys.stderr)
    sys.exit(1)
# Additive wave 8: post-/stt LAN + bundle flags stay usable; advertised model is not a path.
_http = str(h.get('httpUrl') or '').strip()
if not _http.startswith('http://') or '?' in _http or '/' in _http.split('://', 1)[-1].split('/', 1)[0]:
    print('stt-smoke FAIL: httpUrl after /stt must be http:// host, got', h.get('httpUrl'), file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _https = str(h.get('httpsUrl') or '').strip()
    if not _https.startswith('https://') or '?' in _https:
        print('stt-smoke FAIL: httpsUrl after /stt must be https:// without query, got', h.get('httpsUrl'), file=sys.stderr)
        sys.exit(1)
if h.get('htmlPath') != 'bundle' or h.get('htmlSource') != 'bundle':
    print('stt-smoke FAIL: htmlPath/htmlSource must stay bundle after /stt, got', h.get('htmlPath'), h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
if h.get('injectQueue') is not True:
    print('stt-smoke FAIL: injectQueue must stay true after /stt, got', h.get('injectQueue'), file=sys.stderr)
    sys.exit(1)
if '/' in _wm:
    print('stt-smoke FAIL: whisperModel after /stt must not be a path, got', _wm, file=sys.stderr)
    sys.exit(1)
# Additive wave 9: post-/stt identity + RFC1918 LAN stay put.
if h.get('ok') is not True:
    print('stt-smoke FAIL: ok must stay true after /stt, got', h.get('ok'), file=sys.stderr)
    sys.exit(1)
if h.get('service') != 'magicpad':
    print('stt-smoke FAIL: service must stay magicpad after /stt, got', h.get('service'), file=sys.stderr)
    sys.exit(1)
_oa, _ob = int(_ip_parts[0]), int(_ip_parts[1])
if not ((_oa == 10) or (_oa == 192 and _ob == 168) or (_oa == 172 and 16 <= _ob <= 31)):
    print('stt-smoke FAIL: ip must be RFC1918 after /stt, got', _ip, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True and int(h.get('httpsPort') or 0) == int(h.get('httpPort') or 0):
    print('stt-smoke FAIL: httpsPort must differ from httpPort after /stt', file=sys.stderr)
    sys.exit(1)
# Additive wave 10: post-/stt LAN is still not loopback; advertised model stays a variant id.
if _ip.startswith('127.') or _ip in ('0.0.0.0', 'localhost'):
    print('stt-smoke FAIL: ip must not be loopback after /stt, got', _ip, file=sys.stderr)
    sys.exit(1)
if h.get('whisper') is not True or h.get('whisperCached') is not True:
    print('stt-smoke FAIL: whisper/whisperCached must stay true after /stt', file=sys.stderr)
    sys.exit(1)
if h.get('https') is not True:
    print('stt-smoke FAIL: https must stay true after /stt, got', h.get('https'), file=sys.stderr)
    sys.exit(1)
# Additive wave 11: post-/stt LAN host still matches ip; no loopback ifaces.
def _host(url):
    rest = str(url).split('://', 1)[-1]
    hostport = rest.split('/', 1)[0]
    if hostport.startswith('['):
        return hostport[1:].split(']', 1)[0]
    if hostport.count(':') == 1:
        return hostport.split(':')[0]
    return hostport
if _host(_http) != _ip:
    print('stt-smoke FAIL: httpUrl host must equal ip after /stt, got', _http, _ip, file=sys.stderr)
    sys.exit(1)
if '127.' in str(h.get('ifaces') or '') or 'localhost' in str(h.get('ifaces') or '').lower():
    print('stt-smoke FAIL: ifaces must not include loopback after /stt, got', h.get('ifaces'), file=sys.stderr)
    sys.exit(1)
# Additive wave 12: post-/stt httpsUrl host matches ip; ips still lists ip; routeIface stays.
if h.get('https') is True:
    if _host(str(h.get('httpsUrl') or '')) != _ip:
        print('stt-smoke FAIL: httpsUrl host must equal ip after /stt, got', h.get('httpsUrl'), _ip, file=sys.stderr)
        sys.exit(1)
_ips = h.get('ips')
if not isinstance(_ips, list) or _ip not in [str(x) for x in _ips]:
    print('stt-smoke FAIL: ips must contain ip after /stt, got', _ips, _ip, file=sys.stderr)
    sys.exit(1)
_ri = str(h.get('routeIface') or '').strip()
if not _ri or '/' in _ri:
    print('stt-smoke FAIL: routeIface after /stt, got', h.get('routeIface'), file=sys.stderr)
    sys.exit(1)
# Additive wave 13: TLS error stays empty; clients capped; html still from the bundle.
if h.get('https') is True and str(h.get('httpsError') or '') != '':
    print('stt-smoke FAIL: httpsError must stay empty after /stt, got', h.get('httpsError'), file=sys.stderr)
    sys.exit(1)
if type(h.get('clients')) is not int or int(h.get('clients') or 0) < 0 or int(h.get('clients') or 0) > 64:
    print('stt-smoke FAIL: clients after /stt, got', h.get('clients'), file=sys.stderr)
    sys.exit(1)
if str(h.get('htmlPath') or '') != 'bundle':
    print('stt-smoke FAIL: htmlPath must stay bundle after /stt, got', h.get('htmlPath'), file=sys.stderr)
    sys.exit(1)
# Additive wave 14: port identity + html still served; httpUrl slash.
if int(h.get('port') or 0) != int(h.get('httpPort') or 0):
    print('stt-smoke FAIL: port must equal httpPort after /stt, got', h.get('port'), h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
if h.get('html') is not True:
    print('stt-smoke FAIL: html must stay true after /stt, got', h.get('html'), file=sys.stderr)
    sys.exit(1)
if not _http.endswith('/'):
    print('stt-smoke FAIL: httpUrl must end with / after /stt, got', _http, file=sys.stderr)
    sys.exit(1)
# Additive wave 15: post-/stt LAN ifaces + TLS slash + bundle htmlSource + alnum routeIface.
if _ip not in str(h.get('ifaces') or ''):
    print('stt-smoke FAIL: ifaces must contain ip after /stt, got', h.get('ifaces'), _ip, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _https15 = str(h.get('httpsUrl') or '').strip()
    if not _https15.endswith('/'):
        print('stt-smoke FAIL: httpsUrl must end with / after /stt, got', _https15, file=sys.stderr)
        sys.exit(1)
if str(h.get('htmlSource') or '') != 'bundle':
    print('stt-smoke FAIL: htmlSource must stay bundle after /stt, got', h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
if not _ri.isalnum() or not _ri[0].isalpha():
    print('stt-smoke FAIL: routeIface must be alnum after /stt, got', _ri, file=sys.stderr)
    sys.exit(1)
# Additive wave 16: post-/stt URL ports still match; htmlPath stays htmlSource.
def _url_port(url, default):
    rest = str(url).split('://', 1)[-1]
    hostport = rest.split('/', 1)[0]
    if hostport.count(':') == 1:
        return int(hostport.split(':')[1])
    return int(default)
if _url_port(_http, 80) != int(h.get('httpPort')):
    print('stt-smoke FAIL: httpUrl port must equal httpPort after /stt, got', _http, h.get('httpPort'), file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    if _url_port(str(h.get('httpsUrl') or ''), 443) != int(h.get('httpsPort')):
        print('stt-smoke FAIL: httpsUrl port must equal httpsPort after /stt, got', h.get('httpsUrl'), h.get('httpsPort'), file=sys.stderr)
        sys.exit(1)
if str(h.get('htmlPath') or '') != str(h.get('htmlSource') or ''):
    print('stt-smoke FAIL: htmlPath must equal htmlSource after /stt, got', h.get('htmlPath'), h.get('htmlSource'), file=sys.stderr)
    sys.exit(1)
# Additive wave 17: post-/stt ips stay RFC1918 unique LAN; htmlRev year still in window.
if len(_ips) != len(set(str(x) for x in _ips)):
    print('stt-smoke FAIL: ips must be unique after /stt, got', _ips, file=sys.stderr)
    sys.exit(1)
for _one in _ips:
    _p = str(_one).split('.')
    if len(_p) != 4 or any((not x.isdigit() or int(x) > 255) for x in _p):
        print('stt-smoke FAIL: ips items must be IPv4 after /stt, got', _ips, file=sys.stderr)
        sys.exit(1)
    _oa17, _ob17 = int(_p[0]), int(_p[1])
    if not ((_oa17 == 10) or (_oa17 == 192 and _ob17 == 168) or (_oa17 == 172 and 16 <= _ob17 <= 31)):
        print('stt-smoke FAIL: ips items must be RFC1918 after /stt, got', _ips, file=sys.stderr)
        sys.exit(1)
_hr_yyyy17 = int(_hr_parts[0][:4])
if _hr_yyyy17 < 2026 or _hr_yyyy17 > 2030:
    print('stt-smoke FAIL: htmlRev year out of range after /stt, got', _hr, file=sys.stderr)
    sys.exit(1)
# Additive wave 18: post-/stt LAN URL is http://host:port/ ; routeIface short; ips not loopback.
if _http.count('/') != 3 or '@' in _http or '#' in _http:
    print('stt-smoke FAIL: httpUrl after /stt must be http://host:port/, got', _http, file=sys.stderr)
    sys.exit(1)
if h.get('https') is True:
    _hu18 = str(h.get('httpsUrl') or '').strip()
    if _hu18.count('/') != 3 or '@' in _hu18 or '#' in _hu18:
        print('stt-smoke FAIL: httpsUrl after /stt must be https://host:port/, got', _hu18, file=sys.stderr)
        sys.exit(1)
if len(_ri) < 2 or len(_ri) > 16:
    print('stt-smoke FAIL: routeIface length after /stt, got', _ri, file=sys.stderr)
    sys.exit(1)
if any(str(x).startswith('127.') or str(x) in ('0.0.0.0', 'localhost') for x in _ips):
    print('stt-smoke FAIL: ips must not include loopback after /stt, got', _ips, file=sys.stderr)
    sys.exit(1)
print('stt-smoke post-health PASS whisperReady=true whisperCached=true whisperModel=%s htmlRev=%s ip=%s' % (_wm, _hr, _ip))
"
