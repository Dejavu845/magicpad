#!/bin/bash
# Pack openai_whisper-base (preferred) and keep tiny as fallback.
# Runtime also downloads via WhisperKit into Application Support if this is missing.
# No OpenAI cloud API. Weights are Core ML (ANE).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/whisper"
echo "Fetching Whisper Core ML → $DEST"
mkdir -p "$DEST"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

fetch_variant() {
  local variant="$1"
  echo "→ $variant via HF_ENDPOINT=$HF_ENDPOINT"
  if command -v hf >/dev/null 2>&1; then
    hf download argmaxinc/whisperkit-coreml --include "openai_whisper-${variant}/**" --local-dir "$DEST"
  elif command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli download argmaxinc/whisperkit-coreml --include "openai_whisper-${variant}/*" --local-dir "$DEST"
  else
    echo "Install hf CLI or let MagicPad download on first 听写 (HF_ENDPOINT=$HF_ENDPOINT)."
    return 1
  fi
}

# Tokenizer so first load does not hit huggingface.co
fetch_tokenizer() {
  local variant="$1"
  local tok="$DEST/openai_whisper-${variant}"
  [ -d "$tok" ] || return 0
  if [ -f "$tok/tokenizer.json" ]; then
    echo "tokenizer already in $tok"
    return 0
  fi
  echo "→ tokenizer openai/whisper-${variant}"
  local tmp="$DEST/openai_whisper-${variant}-tokenizer"
  if command -v hf >/dev/null 2>&1; then
    hf download "openai/whisper-${variant}" \
      --include "tokenizer.json" --include "tokenizer_config.json" \
      --include "vocab.json" --include "merges.txt" \
      --include "special_tokens_map.json" --include "added_tokens.json" \
      --include "normalizer.json" \
      --local-dir "$tmp" || true
  fi
  if [ -d "$tmp" ]; then
    cp -n "$tmp/"* "$tok/" 2>/dev/null || true
  fi
}

# Prefer base; keep tiny so the app is never without a bundled model.
fetch_variant base || true
fetch_tokenizer base || true
if [ ! -d "$DEST/openai_whisper-tiny/TextDecoder.mlmodelc" ]; then
  fetch_variant tiny || true
  fetch_tokenizer tiny || true
fi

if [ -d "$DEST/openai_whisper-base/TextDecoder.mlmodelc" ]; then
  echo "OK base. Next full build will copy into MagicPad.app/Contents/Resources/whisper/"
elif [ -d "$DEST/openai_whisper-tiny/TextDecoder.mlmodelc" ]; then
  echo "OK tiny fallback. Next full build will copy into MagicPad.app/Contents/Resources/whisper/"
else
  echo "No complete model in vendor/. App will download on first 听写."
  exit 1
fi
