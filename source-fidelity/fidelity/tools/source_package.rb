# frozen_string_literal: true
# Verify a source member against its locked cached gem, without extraction.
require "rubygems/package"
require "digest"
require "stringio"
require "zlib"
module FidelitySourcePackage
  def self.member(root, gem, member)
    name, version = gem.match(/\A(.+)-(\d[^-]*)\z/).captures
    archive = File.join(root, "run/bundle/ruby/4.0.0/cache/#{gem}.gem")
    hash = Digest::SHA256.file(archive).hexdigest
    lock = File.read(File.join(root, "discourse/Gemfile.lock"))
    raise "unlocked source package #{gem}" unless lock.include?("#{name} (#{version}) sha256=#{hash}")
    Gem::Package.new(archive).verify
    bytes = nil
    File.open(archive, "rb") do |io|
      Gem::Package::TarReader.new(io) do |tar|
        tar.each do |entry|
          next unless entry.full_name == "data.tar.gz"
          Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(entry.read))) do |data|
            data.each { |item| bytes = item.read if item.full_name == member }
          end
        end
      end
    end
    raise "missing package source #{member}" unless bytes
    installed = File.join(root, "run/bundle/ruby/4.0.0/gems/#{gem}", member)
    raise "installed source differs from package #{gem}/#{member}" unless File.binread(installed) == bytes
    [bytes, {gem: gem, package_sha256: hash, member: member, member_sha256: Digest::SHA256.hexdigest(bytes)}]
  end
end
