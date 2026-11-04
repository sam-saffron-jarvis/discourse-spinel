#!/bin/sh
# gen.sh K: a Ruby program of K units of one shape, for `make scale-test`.
# Each unit is a model / service / presenter trio with ivars, blocks, hashes,
# strings, a class-method constructor, a yielding method and a call into the
# previous unit, so the whole-program passes meet every kind of node they
# index, and the program grows linearly in K. Every unit repeats the same
# method and local names, which is the shape that makes a name-keyed lookup
# filtered by class or scope cost O(K) per ask (rubys/roundhouse#72).
K=${1:-10}
awk -v K="$K" 'BEGIN {
  print "class Base"
  print "  def initialize(id) = @id = id"
  print "  def id = @id"
  print "  def describe = \"#{self.class.name}(#{@id})\""
  print "end"
  print "module Scoring"
  print "  def score(xs) = xs.sum { |x| x * weight }"
  print "end"
  for (i = 0; i < K; i++) {
    p = i > 0 ? i - 1 : 0
    printf "class Model%d < Base\n", i
    print  "  include Scoring"
    print  "  attr_reader :tags, :counts"
    printf "  def initialize(id)\n    super(id)\n    @tags = []\n    @counts = {}\n    @label = \"m%d\"\n    @extra = nil\n  end\n", i
    print  "  def weight = 2"
    print  "  def add(tag)"
    print  "    @tags << tag"
    print  "    @counts[tag] = (@counts[tag] || 0) + 1"
    print  "    self"
    print  "  end"
    print  "  def top(n) = @counts.sort_by { |k, v| -v }.first(n).map { |k, v| k }"
    print  "  def extra=(v)"
    print  "    @extra = v"
    print  "  end"
    print  "  def extra_s = @extra.nil? ? \"-\" : @extra.to_s"
    printf "  def label = \"#{@label}-#{@tags.size}\"\n"
    print  "end"
    printf "class Service%d\n", i
    printf "  def initialize\n    @models = []\n    @index = {}\n    @prev = Service%d\n  end\n", p
    printf "  def build(n)\n    n.times do |j|\n      m = Model%d.new(j)\n      m.add(\"t#{j %% 3}\").add(\"u\")\n      m.extra = j.even? ? j : \"odd\"\n      @models << m\n      @index[m.id] = m\n    end\n    self\n  end\n", i
    print  "  def find(id) = @index[id]"
    print  "  def total = @models.map { |m| m.score([1, 2, 3]) }.sum"
    print  "  def labels = @models.select { |m| m.id > 0 }.map(&:label)"
    print  "  def each_model"
    print  "    @models.each { |m| yield m }"
    print  "  end"
    print  "  def summary"
    print  "    h = Hash.new(0)"
    print  "    each_model { |m| m.tags.each { |t| h[t] += 1 } }"
    print  "    h.keys.sort.map { |k| \"#{k}=#{h[k]}\" }.join(\",\")"
    print  "  end"
    printf "  def self.make(n) = new.build(n)\n"
    print  "end"
    printf "class Presenter%d\n", i
    printf "  def initialize(svc) = @svc = svc\n"
    print  "  def render"
    print  "    out = +\"\""
    print  "    out << @svc.summary << \";\" << @svc.total.to_s"
    print  "    @svc.labels.each_with_index { |l, k| out << \" #{k}:#{l}\" }"
    print  "    m = @svc.find(1)"
    print  "    out << \" \" << (m ? m.describe + m.extra_s : \"none\")"
    print  "    out"
    print  "  end"
    print  "end"
  }
  print "acc = 0"
  for (i = 0; i < K; i++) {
    printf "r%d = Presenter%d.new(Service%d.make(3)).render\n", i, i, i
    printf "acc += r%d.size\n", i
  }
  print "p acc"
}'
