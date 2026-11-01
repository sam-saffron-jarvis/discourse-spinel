#!/usr/bin/env bash
# Owned, temporary native listener. Oracle is a synchronous Rails runner, never
# a Rails data-serving process. All PG operations are SELECT/read-only.
set -euo pipefail
cd "$(dirname "$0")/.."
source ../harness/env.sh
export DATABASE_URL="$DSPINEL_PG_URL/discourse_development"
export REDIS_URL="redis://127.0.0.1:6399/0"
export MINIMAL_TEST_PORT="${MINIMAL_TEST_PORT:-3529}"
[[ "$MINIMAL_TEST_PORT" == 3528 || "$MINIMAL_TEST_PORT" == 3529 ]]
export PORT="$MINIMAL_TEST_PORT"
export MINIMAL_PROFILER=0
WORKTREE="$PWD"
export MINIMAL_BASE_URI=""
export MINIMAL_ORIGIN="http://127.0.0.1:$PORT"
mkdir -p build/tmp
export TMPDIR="$PWD/build/tmp"
export PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000'
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 - <<'PY'
import socket, os
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', int(os.environ['PORT'])))  # fail rather than test a shared listener
PY
python3 test/source_contract.py
spin test test/query_contract.rb test/serializers.rb test/settings_users.rb test/surface.rb test/avatars.rb test/message_bus.rb test/site.rb test/document.rb test/preloads.rb test/topic.rb
ruby reference/native_site_test.rb
ruby frontend/test_native_document.rb
PYTHONDONTWRITEBYTECODE=1 python3 frontend/test_stage_assets.py
(
  cd ../discourse
  timeout --kill-after=5s 120s bin/rails runner "$WORKTREE/reference/capture-latest-rails.rb"
) >build/latest-rails.new.json 2>build/rails-capture.stderr
(
  cd ../discourse
  timeout --kill-after=5s 120s bin/rails runner "$WORKTREE/reference/site-oracle.rb"
) >build/site-contract.json 2>build/site-contract.stderr
cat build/site-contract.json
(
  cd ../discourse
  timeout --kill-after=5s 120s bin/rails runner "$WORKTREE/test/message_bus_oracle.rb"
) >build/message-bus-contract.json 2>build/message-bus-contract.stderr
cat build/message-bus-contract.json
python3 - <<'PY'
import json
with open('build/latest-rails.new.json') as source:
    capture = json.load(source)
assert capture['responses']['latest']['body']['topic_list']['topics'], 'seeded reference must contain real topics'
PY
mv build/latest-rails.new.json build/latest-rails.json
export TOPIC_ORACLE_IDS
TOPIC_ORACLE_IDS=$(python3 -c 'import json; print(",".join(str(t["id"]) for t in json.load(open("build/latest-rails.json"))["responses"]["latest"]["body"]["topic_list"]["topics"]))')
(
  cd ../discourse
  timeout --kill-after=5s 120s bin/rails runner ../minimal/reference/capture-topic-rails.rb
) >build/topic-rails.json 2>build/topic-rails.stderr
(
  cd ../discourse
  TOPIC_ORACLE_POST_NUMBER=2147483647 timeout --kill-after=5s 120s bin/rails runner ../minimal/reference/capture-topic-rails.rb
) >build/topic-near-rails.json 2>build/topic-near-rails.stderr

build/bin/discourse >build/server.log 2>&1 &
pid=$!
for _ in {1..100}; do
  kill -0 "$pid" 2>/dev/null || { cat build/server.log >&2; exit 1; }
  if curl --max-time 2 -fsS http://127.0.0.1:$PORT/srv/status >build/status.json 2>/dev/null; then
    break
  fi
  sleep .1
done
kill -0 "$pid"
python3 reference/compare-latest.py --compare-recorded build/latest-rails.json --candidate http://127.0.0.1:$PORT
python3 test/http_contract.py
python3 test/topic_http_contract.py
printf 'smoke: native ELF, live read-only PG, strict Rails JSON parity, site/settings contract, native HTML/assets and semantic/security fixtures passed; browser DOM verified separately by browser-smoke\n'
