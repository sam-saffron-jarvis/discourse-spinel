# frozen_string_literal: true
require_relative 'theme_ids_read'

require_relative 'theme_ids_source'
require_relative 'theme_ids_cache_source'
require_relative 'theme_ids_stylesheet_source'

module ThemeIdsViewProtocol
  def theme_ids_stage_observation
    record = stylesheet_manager_read_stage_observation
    raise 'Theme IDs actual consumer missing' if ThemeIdsRead.consumed_json.empty?
    record[:theme_ids_read] = {source_getter_entered: true, warm_proof_at_existing_cleanup: true, forced_synchronization: false}
    record
  end
end
class RequestStyleReadManager
  include ThemeIdsStylesheetPrefix
end
class ListBodyContext
  include ThemeIdsViewProtocol
  def observation; theme_ids_stage_observation; end
end
