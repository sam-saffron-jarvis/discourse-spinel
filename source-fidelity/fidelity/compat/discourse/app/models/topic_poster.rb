# frozen_string_literal: true

require "ostruct"

class TopicPoster
  include ActiveModel::Serialization

  attr_accessor :user, :description, :extras, :id, :primary_group

  def initialize(hash = nil)
    @data = OpenStruct.new(hash)
  end
  
  def flair_group
    @data[:flair_group]
  end
  
  def flair_group=(x)
    @data[:flair_group] = x
  end
  
  def [](name)
    @data[name]
  end
  
  def []=(name, value)
    @data[name] = value
  end
  
  def to_h(&block)
    @data.to_h.to_h(&block)
  end
  
  def each_pair
    return enum_for(:each_pair) unless block_given?
    @data.each_pair { |pair| yield pair }
    self
  end
  
  def dig(name, *names)
    @data.dig(name, *names)
  end
  
  def delete_field(name, &block)
    @data.delete_field(name, &block)
  end
  
  def freeze
    @data.freeze
    super
  end
  
  private def initialize_dup(orig)
    super
    @data = @data.dup
  end
  
  private def initialize_clone(orig)
    super
    @data = @data.clone
  end
  
  def respond_to?(name, include_private = false)
    if name.to_sym == :flair_group || name.to_sym == :flair_group=
      @data.respond_to?(name, include_private)
    else
      super
    end
  end
  
  private def respond_to_missing?(name, include_private = false)
    @data.respond_to?(name, include_private) || super
  end
  
  private def method_missing(name, *args)
    text = name.to_s
    if text.end_with?("=")
      if args.length != 1
        raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 1)"
      end
      self[text[0...-1]] = args[0]
    elsif args.empty?
      self[name]
    else
      super
    end
  end

  def attributes
    {
      "user" => user,
      "description" => description,
      "extras" => extras,
      "id" => id,
      "primary_group" => primary_group,
    }
  end

  def name_and_description
    I18n.t("js.user.avatar.name_and_description", name: user.display_name, description: description)
  end
end
