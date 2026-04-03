#!/usr/bin/env bash
# copy_gguf.sh — copy a .gguf file to GemmaDemo's Documents on connected iPhone
# Usage: ./copy_gguf.sh /path/to/model.gguf

set -euo pipefail

DEVICE_UDID="00008130-001E789C34A2001C"
BUNDLE_ID="com.slipcheck.GemmaDemo"
GGUF_FILE="${1:-}"

if [[ -z "$GGUF_FILE" ]]; then
  echo "Usage: $0 /path/to/model.gguf"
  exit 1
fi

if [[ ! -f "$GGUF_FILE" ]]; then
  echo "Error: file not found: $GGUF_FILE"
  exit 1
fi

FILENAME=$(basename "$GGUF_FILE")
echo "Copying $FILENAME to GemmaDemo Documents on device..."

xcrun devicectl device copy to \
  --device "$DEVICE_UDID" \
  --source "$GGUF_FILE" \
  --destination "Documents/$FILENAME" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID"

echo "Done. Open GemmaDemo → Setup → Refresh to see the file."
