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

# Build provider keys from environment variables (names only are logged, never values)
export FREEAPI_CONFIG_JSON="$(node -e '
const e = process.env, keys = [];
if (e.GEMINI_API_KEY) keys.push({ platform: "google", key: e.GEMINI_API_KEY, label: "gemini", enabled: true });
for (let i = 1; i <= 4; i++) if (e[`GROQ_API_KEY_${i}`]) keys.push({ platform: "groq", key: e[`GROQ_API_KEY_${i}`], label: `groq-${i}` });
for (let i = 1; i <= 3; i++) if (e[`NVIDIA_API_KEY_${i}`]) keys.push({ platform: "nvidia", key: e[`NVIDIA_API_KEY_${i}`], label: `nvidia-${i}` });
process.stdout.write(JSON.stringify({ keys, routing: { strategy: "balanced" } }));')"

# Restart the server so it applies the current keys on every session start
for p in $(ps -eo pid,args | awk '$2=="node" && $3=="dist/index.js"{print $1}'); do kill "$p" 2>/dev/null || true; done
sleep 1
(cd "$DIR/server" && PORT="$PORT" nohup node dist/index.js > /tmp/freellmapi.log 2>&1 < /dev/null &) >/dev/null 2>&1 </dev/null
for _ in $(seq 1 30); do
  curl -s -m 2 -o /dev/null "http://localhost:$PORT/v1/models" && break
  sleep 1
done

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export OPENAI_BASE_URL=\"http://localhost:$PORT/v1\"" >> "$CLAUDE_ENV_FILE"
fi
