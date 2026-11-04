# A block param captured by a proc lifted out of a NESTED block lives in a heap
# cell, while the inlined loop emitters bind it by writing the plain C slot.
# The publish slot -> cell used to sit at the capture fill (where the proc is
# built), so every read earlier in the body read a cell still holding nil.
# Two levels of nesting plus a `next` were enough to arrange it: doom's
# build_composite saw its first patch ref as nil for every texture.
Ref = Struct.new(:x_offset, :y_offset, :patch_index)
Post = Struct.new(:top_delta, :pixels)

class Patch
  attr_reader :columns
  def initialize(cols)
    @columns = cols
  end
end

class Mgr
  def initialize
    @refs = [Ref.new(0, 0, 0), Ref.new(1, 0, 1)]
    @patches = {}
  end

  def get_patch(i)
    @patches[i] ||= Patch.new([[Post.new(0, [1, 2])], [Post.new(1, [3])]])
  end

  def build
    columns = Array.new(4) { [] }
    @refs.each do |pref|
      p pref.nil?
      patch = get_patch(pref.patch_index)
      next unless patch

      patch.columns.each_with_index do |posts, px|
        tx = pref.x_offset + px
        next if tx < 0 || tx >= 4

        posts.each do |post|
          columns[tx] << Post.new(pref.y_offset + post.top_delta, post.pixels)
        end
      end
    end
    columns
  end
end

p Mgr.new.build

# The read that broke needs no `next` in the condition, only a read of the
# param before one: the publish, not the branch, was what came too late.
[Ref.new(1, 0, 0), Ref.new(2, 0, 0)].each do |pref|
  v = pref.x_offset
  next if false
  [[7], [8]].each do |posts|
    posts.each { |post| p v + pref.x_offset + post }
  end
end
