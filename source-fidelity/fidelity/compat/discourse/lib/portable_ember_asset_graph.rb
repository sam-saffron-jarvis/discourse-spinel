# frozen_string_literal: true
# GENERATED from pinned EmberAssets graph methods. This is an explicit pure
# dependency: callers supply a live parsed manifest. NOT the full EmberAssets
# class, request/production cache, build-status/error lifecycle or HTML renderer.
require "set"
class PortableEmberAssetGraph
  def self.script_chunks(manifest)
    entrypoints = {}

    {
      **manifest["entrypoints"],
      **manifest["dynamicEntrypoints"],
    }.each do |entry_name, entry_filename|
      entrypoints[entry_name.delete_suffix(".js")] = deep_imports_for(
        chunk_filename: entry_filename,
        chunks: manifest["chunks"],
      ).map { logical_name(it) }
    end

    entrypoints
  end

def self.import_map(manifest)
    (manifest.dig("importMap") || {}).to_h { |stable, real| [logical_name(stable), logical_name(real)] }
  end

def self.logical_name(filename)
    filename.delete_prefix("assets/").delete_suffix(".js")
  end

def self.deep_imports_for(chunk_filename:, chunks:, seen: Set.new)
    return [] unless seen.add?(chunk_filename)
    [
      chunk_filename,
      *chunks
        .dig(chunk_filename, "imports")
        &.flat_map { |import| deep_imports_for(chunk_filename: import, chunks:, seen:) },
    ]
  end
end
