# frozen_string_literal: true
require "json"

# Child-free counterpart of GitUtils.git_version: the same filesystem override
# has precedence, otherwise resolve the repository HEAD from live Git metadata.
# No captured oracle values, baked SHA, shell, network or write operations.
class PortableGitVersion
  def self.configure_application_root(root)
    @application_root = root
  end

  def self.application_root
    @application_root || Rails.root.to_s
  end

  def self.read(root)
    overrides = File.join(root, "config/git-utils-overrides.json")
    if File.file?(overrides)
      value = JSON.parse(File.read(overrides))["git_version"]
      return value if value
    end
    git = File.join(root, ".git")
    if File.file?(git)
      pointer = File.read(git).strip
      return "unknown" unless pointer.start_with?("gitdir: ")
      git = File.expand_path(pointer.delete_prefix("gitdir: "), root)
    end
    git = root if !File.directory?(git) && File.file?(File.join(root, "HEAD"))
    return "unknown" unless File.directory?(git)
    common = git
    common_file = File.join(git, "commondir")
    common = File.expand_path(File.read(common_file).strip, git) if File.file?(common_file)
    head = File.join(git, "HEAD")
    return "unknown" unless File.file?(head)
    value = File.read(head).strip
    8.times do
      return value if /\A(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})\z/.match?(value)
      return "unknown" unless value.start_with?("ref: refs/")
      ref = value.delete_prefix("ref: ")
      return "unknown" if ref.include?("..") || ref.include?("\\")
      loose = File.join(git, ref)
      loose = File.join(common, ref) unless File.file?(loose)
      if File.file?(loose)
        value = File.read(loose).strip
      else
        packed = File.join(common, "packed-refs")
        return "unknown" unless File.file?(packed)
        value = ""
        File.read(packed).split("\n").each do |line|
          pair = line.split(" ", 2)
          value = pair[0] if pair.length == 2 && pair[1] == ref
        end
      end
    end
    "unknown"
  rescue Errno::ENOENT
    # Git metadata may disappear during a concurrent deployment. GitUtils'
    # failed git command also returns its explicit unknown fallback.
    "unknown"
  end
end
