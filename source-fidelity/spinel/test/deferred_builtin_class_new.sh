#!/bin/sh
# Calls can defer their Class.new(parent) refusal; class layouts cannot.
set -eu
SPINEL=${SPINEL:-bin/spinel}
scratch=$(mktemp -d "${TMPDIR:-build}/deferred-builtin-class-new.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
cat > "$scratch/call.rb" <<'RUBY'
def unused
  Class.new(Array)
end
def factory(run)
  if run
    Class.new(String)
  else
    "untaken"
  end
end
puts factory(false)
begin
  factory(true)
rescue NotImplementedError => e
  puts e.message.include?("Class.new(parent)")
end
puts "after"
RUBY
if "$SPINEL" "$scratch/call.rb" -c -o "$scratch/strict.c" > "$scratch/strict.log" 2>&1; then
  echo 'deferred-builtin-class-new: FAIL (strict call accepted)' >&2
  exit 1
fi
grep -q 'Class.new.*not supported' "$scratch/strict.log"
printf 'untaken\ntrue\nafter\n' > "$scratch/expected"
for mode in flag pragma; do
  if [ "$mode" = flag ]; then
    "$SPINEL" --defer-refusals "$scratch/call.rb" -o "$scratch/call" > "$scratch/$mode.log" 2>&1
  else
    { echo '# spinel: defer-refusals'; cat "$scratch/call.rb"; } > "$scratch/pragma.rb"
    "$SPINEL" "$scratch/pragma.rb" -o "$scratch/call" > "$scratch/$mode.log" 2>&1
  fi
  "$scratch/call" > "$scratch/out"
  cmp "$scratch/expected" "$scratch/out"
done
printf 'class Layout < OpenStruct; end\n' > "$scratch/layout.rb"
if "$SPINEL" --defer-refusals "$scratch/layout.rb" -c -o "$scratch/layout.c" > "$scratch/layout.log" 2>&1; then
  echo 'deferred-builtin-class-new: FAIL (unsupported layout accepted)' >&2
  exit 1
fi
grep -q 'class Layout < OpenStruct' "$scratch/layout.log"
echo 'deferred-builtin-class-new: pass'
