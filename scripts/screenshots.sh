#!/bin/zsh
# Regenerates the README screenshots (docs/screenshots/*.png) from a demo workspace with
# made-up projects, so no real work shows up. Starts a few real Claude Code sessions and
# makes one of them ask for a permission (a couple of small model calls).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# A path without the user name. The screenshot mode answers Claude's trust prompt for it.
DEMO=/tmp/acme
HOME_DIR=$(mktemp -d /tmp/ws-shots.XXXXXX)
OUT="$ROOT/docs/screenshots"
mkdir -p "$OUT"

./scripts/build-app.sh >/dev/null
APP="$ROOT/build/Workspaces.app/Contents/MacOS"

# Demo repositories.
rm -rf "$DEMO"
for repo in acme-api acme-web acme-ios; do
  mkdir -p "$DEMO/$repo" && cd "$DEMO/$repo"
  git init -q -b main
  echo "# $repo" > README.md
  git add README.md && git -c user.name=demo -c user.email=demo@example.com commit -qm init
  cd "$ROOT"
done
git -C "$DEMO/acme-api" checkout -qb feat/billing

id() { printf 'AAAAAAAA-0000-4000-8000-%012d' "$1"; }
cat > "$HOME_DIR/workspaces.json" <<JSON
{"workspaces":[
 {"name":"Acme","projects":[
  {"name":"acme-api","path":"$DEMO/acme-api","sessionsOnOpen":0,"claudeArguments":"--permission-mode default","savedSessions":[
    {"id":"$(id 1)","label":"main","cwd":"$DEMO/acme-api"},
    {"id":"$(id 2)","label":"fix/timeout","cwd":"$DEMO/acme-api"}]},
  {"name":"acme-web","path":"$DEMO/acme-web","sessionsOnOpen":0,"savedSessions":[
    {"id":"$(id 3)","label":"feat/checkout","cwd":"$DEMO/acme-web"},
    {"id":"$(id 4)","label":"main","cwd":"$DEMO/acme-web"}]},
  {"name":"acme-ios","path":"$DEMO/acme-ios","sessionsOnOpen":0,"savedSessions":[
    {"id":"$(id 5)","label":"feat/widget","cwd":"$DEMO/acme-ios"}]}]},
 {"name":"Pessoal","projects":[{"name":"blog","path":"$DEMO/acme-web","sessionsOnOpen":1}]}],
 "freezeAfterMinutes":1,"hibernateAfterMinutes":0}
JSON

export WORKSPACES_HOME="$HOME_DIR"
WORKSPACES_SCREENSHOTS_TRUST="$DEMO" WORKSPACES_SCREENSHOTS="$OUT" WORKSPACES_SCREENSHOTS_DELAY=120 "$APP/Workspaces" --open Acme >/dev/null 2>&1 &
PID=$!

# Wait for the MCP config of the first session, then script a few states.
until [ -f "$HOME_DIR/sessions/$(id 1).json" ]; do sleep 1; done
sleep 20
hook() { echo "{\"hook_event_name\":\"$2\",\"session_id\":\"demo-$1\",\"cwd\":\"$3\"}" | WORKSPACES_SESSION="$(id $1)" "$APP/workspaces-hook"; }
mcp() {
  local file="$HOME_DIR/sessions/$(id $1).json"
  local url=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['mcpServers']['workspaces']['url'])" "$file")
  local auth=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['mcpServers']['workspaces']['headers']['Authorization'])" "$file")
  curl -s -X POST "$url" -H "Authorization: $auth" -H "X-Workspaces-Session: $(id $1)" -H "Content-Type: application/json" -d "$2" >/dev/null
}
hook 1 UserPromptSubmit "$DEMO/acme-api"
mcp 1 '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"set_status","arguments":{"text":"rodando os testes"}}}'
hook 2 Stop "$DEMO/acme-api"
hook 3 Stop "$DEMO/acme-web"
# A real permission prompt: a new session asked to create a file.
mcp 2 '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_session","arguments":{"project":"acme-api","prompt":"Crie um arquivo CHANGELOG.md com a linha: ## 0.1.0"}}}'

wait $PID || true
rm -rf "$HOME_DIR" "$DEMO"
echo "Prints em $OUT"
ls "$OUT"
