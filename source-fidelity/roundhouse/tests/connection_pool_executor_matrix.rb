def complete_pool
  state = ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.run
  raise "source run hook is not noop" unless state.nil?
  ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.complete(state)
end
def active_pool?
  !!ActiveRecord::Base.connection_pool.active_connection?
end
connection = ActiveRecord::Base.connection
raise "writable session" unless connection.select_value("SHOW default_transaction_read_only") == "on"
complete_pool
raise "closed transaction lease leaked" if active_pool?
complete_pool
puts "closed-and-repeated-completion:released"
[true, false].each do |joinable|
  ActiveRecord::Base.transaction(joinable: joinable) do
    connection = ActiveRecord::Base.connection
    raise "readonly scope lost" unless connection.select_value("SHOW default_transaction_read_only") == "on"
    raise "no real active lease" unless active_pool?
    complete_pool
    raise "completion ownership wrong" unless active_pool? == joinable
    puts "open-joinable-#{joinable}:#{active_pool?}"
  end
  complete_pool
end
# A raw outer readonly fixture is not an AR joinable transaction. Completing
# the AR lease must not commit/rollback/unpin the underlying fixture owner.
begin_fixture
connection = ActiveRecord::Base.connection
raise "fixture readonly scope lost" unless connection.select_value("SHOW default_transaction_read_only") == "on"
complete_pool
raise "fixture facade lease leaked" if active_pool?
raise "completion stole raw fixture" unless fixture_preserved?
puts "outer-readonly-fixture:preserved"
end_fixture
