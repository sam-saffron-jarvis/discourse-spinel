# frozen_string_literal: true
# Materialize source/cache inputs, NEVER a computed version or PG/oracle payload.
require "prism"
require "pathname"
require "digest"
require "json"
require "fileutils"
root, target = ARGV
raise "owned VM fixture target already exists" if File.exist?(target)
FileUtils.mkdir_p(target)
module Rails
  class << self; attr_accessor :root; end
end
Rails.root = Pathname.new(root)
require File.join(root, "lib/precompiled_bundle")
source = File.read(File.join(root, "lib/asset_processor.rb"))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
node = owner.body.body.grep(Prism::ConstantWriteNode).find { |n| n.name == :BUNDLE }
args = {}
factory = Object.new
factory.define_singleton_method(:new) { |**kwargs, &block| args.replace(kwargs); nil }
scope = Module.new
scope.const_set(:PrecompiledBundle, factory)
scope.module_eval(node.slice)
original = PrecompiledBundle.new(**args) { raise "external build refused" }
raise "current processor bundle requires external build" unless original.precompiled?
files = {}
args.fetch(:dependency_globs).each do |glob|
  members = Dir.glob(glob, base: root).sort
  raise "empty processor dependency glob" if members.empty?
  members.each do |relative|
    bytes = File.binread(File.join(root, relative))
    FileUtils.mkdir_p(File.dirname(File.join(target, relative)))
    File.binwrite(File.join(target, relative), bytes)
    files[relative] = Digest::SHA256.hexdigest(bytes)
  end
end
path = original.path
relative = path.relative_path_from(Pathname.new(root)).to_s
FileUtils.mkdir_p(File.dirname(File.join(target, relative)))
FileUtils.copy_file(path, File.join(target, relative))
files[relative] = Digest::SHA256.file(path).hexdigest
File.write(File.join(target, "vm-source-lease.json"), JSON.pretty_generate({owner_pid: Process.ppid, files: files,
  bundle: relative, digest: original.send(:digest), generated_version_supplied: false}) + "\n")
