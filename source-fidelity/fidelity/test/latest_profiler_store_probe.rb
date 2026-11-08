# frozen_string_literal: true
# TEST-only observation of actual candidate cache records, after dispatch.
# Never changes data or supplies it as input to the controller/profiler.
class LatestProfilerStoreProbe
  def self.proof(policy)
    config = Rack::MiniProfiler.config
    store = config.storage_instance
    current_id = policy.saved_profile_id
    raise "no actual profiler save reply" if current_id.empty?
    current = store.load(current_id)
    raise "current profiler record missing" unless current && current[:id] == current_id
    unviewed = store.get_unviewed_ids(current[:user])
    {current_id: current_id, ordered_unviewed_ids: unviewed,
      max_traces_to_show: config.max_traces_to_show,
      stored_pages: [current_id].map do |id|
        page = store.load(id)
        {id: page[:id], request_method: page[:request_method], request_path: page[:request_path],
         user: page[:user], fields: page.attributes.keys.map(&:to_s).sort,
         sql_count: page[:sql_count], root_name: page[:root][:name]}
      end}
  end

  def self.call(policy, headers)
    result = proof(policy)
    ids = headers["x-miniprofiler-ids"].to_s.split(",")
    store = Rack::MiniProfiler.config.storage_instance
    result[:stored_pages] = ([result[:current_id]] + ids).uniq.map do |id|
      page = store.load(id)
      raise "advertised profiler page missing" unless page && page[:id] == id
      {id: page[:id], request_method: page[:request_method], request_path: page[:request_path],
       user: page[:user], fields: page.attributes.keys.map(&:to_s).sort,
       sql_count: page[:sql_count], root_name: page[:root][:name]}
    end
    result
  end
end
