# frozen_string_literal: true
# Common observation program: candidate and full original share NO cache code.
require 'digest'
def observe_asset_lifecycle(root)
  assets = new_request_ember_assets(root)
  before = Thread.list.size
  initial = assets.request_cache.nil?
  begin
    imports = assets.import_map
    chunks = assets.script_chunks
    retained = assets.cache
    manifest = assets.read_manifest!(exception: true)
    replacement = ENV.fetch('FIDELITY_UNIT_ASSET_REPLACEMENT', '')
    unless replacement.empty?
      raise 'unowned unit lifetime mutation' unless root.end_with?('/unit-only-cache-lifetime') && root.start_with?(File.dirname(__FILE__) + '/')
      File.write(File.join(root, 'frontend/discourse/dist/manifest/manifest.json'), File.read(replacement))
    end
    warm_imports = assets.import_map
    warm_chunks = assets.script_chunks
    raise 'warm manifest identity changed' unless manifest.equal?(assets.read_manifest!(exception: true))
    raise 'warm cache identity changed' unless retained.equal?(assets.cache)
    raise 'warm import identity changed' unless imports.equal?(warm_imports)
    raise 'warm chunk identity changed' unless chunks.equal?(warm_chunks)
    assets.reset
    raise 'request cache reset failed' unless assets.request_cache.nil?
    next_imports = assets.import_map
    next_chunks = assets.script_chunks
    raise 'wrong request cache lifetime' if retained.equal?(assets.cache) || imports.equal?(next_imports) || chunks.equal?(next_chunks)
    if replacement.empty?
      raise 'reset changed genuine graph' unless imports == next_imports && chunks == next_chunks
    else
      raise 'stale manifest survived request reset' if imports == next_imports
      raise 'unrelated chunk graph changed' unless chunks == next_chunks
      raise 'wrong live mutation result' unless imports.size == next_imports.size + 1
    end
    puts JSON.generate({root: root, initial_nil: initial, imports: imports, chunks: chunks, warm_identity: true, reset_identity: true, after_reset_imports: next_imports})
  rescue StandardError => error
    raise if error.is_a?(RuntimeError)
    # Original nested and candidate BuildError names differ intentionally.
    kind = error.class.name.to_s.split('::').last
    puts JSON.generate({root: root, initial_nil: initial, error: kind, message: error.message})
  ensure
    assets.reset
    if !assets.request_cache.nil?
      assets.clear_cache!
      raise 'asset unit cleanup failed' unless assets.request_cache.nil?
      puts 'FIDELITY_ASSET_UNIT_MUTANT_CLEANUP reset_failed_but_state_cleared'
      raise 'asset request state leaked'
    end
    raise 'asset threads leaked' unless Thread.list.size == before
  end
end
ARGV.each { |root| observe_asset_lifecycle(root) }
