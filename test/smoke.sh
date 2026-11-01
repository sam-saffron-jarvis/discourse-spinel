#!/usr/bin/env bash
# Owned, temporary native listener. Oracle is a synchronous Rails runner, never
# a Rails data-serving process. All PG operations are SELECT/read-only.
set -euo pipefail
cd "$(dirname "$0")/.."
source ../harness/env.sh
export DATABASE_URL="$DSPINEL_PG_URL/discourse_development"
export REDIS_URL="redis://127.0.0.1:6399/0"
export PORT=3498
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
import socket
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 3498))  # fail rather than test a shared listener
PY
python3 test/source_contract.py
spin test test/query_contract.rb test/serializers.rb test/settings_users.rb
(
  cd ../discourse
  timeout --kill-after=5s 120s bin/rails runner ../minimal/reference/capture-latest-rails.rb
) >build/latest-rails.new.json 2>build/rails-capture.stderr
python3 - <<'PY'
import json
with open('build/latest-rails.new.json') as source:
    capture = json.load(source)
assert capture['responses']['latest']['body']['topic_list']['topics'], 'seeded reference must contain real topics'
PY
mv build/latest-rails.new.json build/latest-rails.json

build/bin/discourse >build/server.log 2>&1 &
pid=$!
for _ in {1..100}; do
  kill -0 "$pid" 2>/dev/null || { cat build/server.log >&2; exit 1; }
  if curl --max-time 2 -fsS http://127.0.0.1:3498/srv/status >build/status.json 2>/dev/null; then
    break
  fi
  sleep .1
done
kill -0 "$pid"
python3 reference/compare-latest.py --compare-recorded build/latest-rails.json --candidate http://127.0.0.1:3498
python3 test/http_contract.py
printf 'smoke: native ELF, live read-only PG, strict Rails JSON parity and semantic fixtures passed; frontend remains 501\n'
