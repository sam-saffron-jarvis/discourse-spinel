# frozen_string_literal: true
# Narrow additional domain, never blanket global publication permission.
class CategoryCacheLease
  def note_asset_version(value)
    check!(@host, @port)
    raise ArgumentError, 'asset-version digest type' unless value.is_a?(String) && value.match?(/\A[0-9a-f]{32}\z/)
    @lock.synchronize do
      raise ArgumentError, 'asset-version digest changed within pinned process' unless @asset_version_digest.nil? || @asset_version_digest == value
      @asset_version_digest = value
    end
    nil
  end
  def asset_version_publications; @lock.synchronize { @asset_version_publications || 0 }; end
  def asset_version_reads; @lock.synchronize { @asset_version_reads || 0 }; end
  def asset_version_channel; '/global/asset-version'; end
  def asset_version_command?(command)
    name = command[0].to_s.upcase
    ((name == 'GET' || name == 'ZRANGEBYSCORE') && ["__mb_backlog_id_n_#{asset_version_channel}", "__mb_backlog_n_#{asset_version_channel}"].include?(command[1].to_s)) || ((name == 'EVAL' || name == 'EVALSHA') && command[12] == asset_version_channel)
  end
  def validate_asset_version_payload(payload)
    raise ArgumentError, 'asset-version publication targets' unless payload['user_ids'].nil? && payload['group_ids'].nil? && payload['client_ids'].nil?
    value = @asset_version_digest
    raise ArgumentError, 'asset-version publication digest' unless value.is_a?(String) && payload['data'] == value
    true
  end
  def authorize_asset_version(command)
    check!(@host, @port)
    raise ArgumentError, 'asset-version source must run synchronously' unless Thread.current == Thread.main
    raise ArgumentError, 'asset-version digest not genuinely acquired' unless @asset_version_digest.is_a?(String)
    name = command[0].to_s.upcase
    if name == 'GET'
      raise ArgumentError, 'asset-version last-id key' unless command == ['GET', "__mb_backlog_id_n_#{asset_version_channel}"]
    elsif name == 'ZRANGEBYSCORE'
      raise ArgumentError, 'asset-version backlog range' unless command.size == 4 && command[1] == "__mb_backlog_n_#{asset_version_channel}" && command[2].to_s.match?(/\A[0-9]+\z/) && command[3] == '+inf'
    else
      raise ArgumentError, 'asset-version script identity' unless command[1] == (name == 'EVAL' ? @script : @script_sha)
      expected = ['__mb_global_id_n', "__mb_backlog_id_n_#{asset_version_channel}", "__mb_backlog_n_#{asset_version_channel}", '__mb_global_backlog_n', '_message_bus_0']
      raise ArgumentError, 'asset-version publication namespace' unless command[2].to_i == 5 && command[3, 5] == expected
      wire = command[8].to_s
      prefix = asset_version_channel + '|'
      raise ArgumentError, 'asset-version wire channel' unless wire.start_with?(prefix)
      validate_asset_version_payload(JSON.parse(wire[prefix.length..-1]))
      event('asset_version_publish_dispatch')
    end
    true
  end
  def observe_asset_version(command, response)
    return nil unless asset_version_command?(command)
    @lock.synchronize do
      if command[0] == 'GET'
        @asset_version_reads = (@asset_version_reads || 0) + 1
      elsif command[0] == 'EVAL' || command[0] == 'EVALSHA'
        raise 'asset-version publication reply' unless response.is_a?(Integer) && response > 0
        @asset_version_publications = (@asset_version_publications || 0) + 1
      end
    end
    nil
  end
end
