# frozen_string_literal: true
# Explicit UNIT-only digest producer, never application asset graph/input.
module AssetVersionBusUnit
  def self.run
    lease = CategoryCacheBootstrap.lease
    bus = CategoryCacheBootstrap.bus
    digest = Digest::MD5.hexdigest('UNIT-only asset-version bus lifecycle')
    lease.note_asset_version(digest)
    channel = lease.asset_version_channel
    raise 'asset-version cold backlog not empty' unless bus.last_message(channel).nil?
    fault = ENV.fetch('FIDELITY_ASSET_BUS_FAULT', '')
    target = fault == 'wrong-channel' ? channel + '/wrong' : channel
    payload = fault == 'wrong-digest' ? digest + 'wrong' : digest
    bus.publish(target, payload)
    message = bus.last_message(channel)
    raise 'asset-version source last-message differs' unless !message.nil? && message.channel == channel && message.data == digest && message.message_id == 1 && message.user_ids.nil? && message.group_ids.nil? && message.client_ids.nil?
    raise 'asset-version duplicate publication' unless lease.asset_version_publications == 1
    again = bus.last_message(channel)
    raise 'asset-version genuine warm backlog changed' unless !again.nil? && again.data == digest && lease.asset_version_publications == 1
    begin
      bus.publish(channel, digest + 'invalid')
      raise 'asset-version wrong digest accepted'
    rescue ArgumentError => error
      raise unless error.message == 'asset-version publication digest'
    end
    raise 'asset-version refused publication dispatched' unless lease.asset_version_publications == 1
    puts 'FIDELITY_ASSET_VERSION_BUS_UNIT ' + JSON.generate({unit_only: true, cold_absent: true, digest: digest, message_id: message.message_id, publications: lease.asset_version_publications, reads: lease.asset_version_reads, refused_wrong_digest_before_dispatch: true})
  end
end
AssetVersionBusUnit.run
