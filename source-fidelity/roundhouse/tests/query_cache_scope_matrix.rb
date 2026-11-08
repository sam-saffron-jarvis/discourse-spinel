# frozen_string_literal: true

def state(label)
  puts label + ":" + cache_enabled?.to_s
end

state("initial")
outer = start_scope
state("outer")
inner = start_scope
inner_body = body_for_scope(inner)
inner_body.close
state("inner-complete")
outer_body = body_for_scope(outer)
puts outer_body.join
state("body-materialized-not-closed")
outer_body.close
state("outer-complete")
outer_body.close
state("double-close")
later = start_scope
outer_body.close
state("old-body-cannot-complete-later-scope")
complete_scope(later)
state("later-complete")
failed = start_scope
begin
  raise "test request exception"
rescue RuntimeError
ensure
  complete_scope(failed)
end
state("exception-cleanup")
