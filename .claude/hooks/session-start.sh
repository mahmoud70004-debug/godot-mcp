#!/bin/bash
# Installs and starts FreeLLMAPI (https://github.com/tashfeenahmed/freellmapi)
# in remote sessions. OpenAI-compatible endpoint: http://localhost:3001/v1
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

DIR="${FREELLMAPI_DIR:-$HOME/freellmapi}"
PORT="${FREELLMAPI_PORT:-3001}"

if [ ! -d "$DIR/.git" ]; then
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/tashfeenahmed/freellmapi "$DIR"
fi

cd "$DIR"
hashes=node_modules/.session-start.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null || [ ! -f server/dist/index.js ]; then
  rm -f "$hashes"
  npm install
  npm run build -w server
  sha256sum package.json package-lock.json > "$hashes"
fi

# Start the server if it is not already listening
if ! curl -s -m 2 -o /dev/null "http://localhost:$PORT/v1/models"; then
  (cd server && PORT="$PORT" nohup node dist/index.js > /tmp/freellmapi.log 2>&1 &)
  sleep 5
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export OPENAI_BASE_URL=\"http://localhost:$PORT/v1\"" >> "$CLAUDE_ENV_FILE"
fi
