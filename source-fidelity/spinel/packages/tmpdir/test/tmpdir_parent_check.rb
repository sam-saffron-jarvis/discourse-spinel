# Dir.mktmpdir's block form refuses to clean up through a parent that is
# world-writable and not sticky, and only checks a parent it chose itself.
#
# Before this change the check could never fire: it asked for the sticky
# bit to be set and clear at once, so a directory under a world-writable,
# non-sticky Dir.tmpdir was removed without complaint. Now the check reads
# the two bits the way CRuby does, and as in CRuby it is skipped when the
# caller named the parent: that parent is the caller's to vouch for. When
# the check fires the ArgumentError is the answer and the directory is
# left where it is.
#
# Every mode change is on a directory this test made, and the ensure at the
# end puts it back to 0700 and removes it with whatever an arm left inside,
# so a failing arm does not leave a world-writable directory behind.
require "tmpdir"

outer = Dir.mktmpdir("spinel-parent-")
saved = ENV["TMPDIR"]
ENV["TMPDIR"] = outer

begin
  # A parent the caller named is not checked, even world-writable and not sticky
  File.chmod(0o777, outer)
  path = nil
  Dir.mktmpdir("named-", outer) do |d|
    path = d
    File.write("#{d}/f", "x")
  end
  p Dir.exist?(path)
  File.chmod(0o700, outer)

  # Dir.tmpdir turned world-writable and not sticky during the block: the
  # ArgumentError names the parent, and the directory is left alone
  path = nil
  begin
    Dir.mktmpdir("default-") do |d|
      path = d
      File.write("#{d}/f", "x")
      File.chmod(0o777, outer)
    end
  rescue ArgumentError => e
    p e.message == "parent directory is world writable but not sticky: #{outer}"
  end
  p Dir.exist?(path)
  File.chmod(0o700, outer)
  if Dir.exist?(path)
    File.delete("#{path}/f")
    Dir.rmdir(path)
  end

  # World-writable with the sticky bit is fine
  path = nil
  Dir.mktmpdir("sticky-") do |d|
    path = d
    File.chmod(0o1777, outer)
  end
  p Dir.exist?(path)
  File.chmod(0o700, outer)

  # Group-writable without the world bit is fine
  path = nil
  Dir.mktmpdir("group-") do |d|
    path = d
    File.chmod(0o775, outer)
  end
  p Dir.exist?(path)
  File.chmod(0o700, outer)

ensure
  ENV["TMPDIR"] = saved if saved
  File.chmod(0o700, outer)
  Dir.children(outer).each do |c|
    left = "#{outer}/#{c}"
    File.delete("#{left}/f") if File.exist?("#{left}/f")
    Dir.rmdir(left)
  end
  Dir.rmdir(outer)
end
p Dir.exist?(outer)
