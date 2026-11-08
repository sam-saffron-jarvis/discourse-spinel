# frozen_string_literal: true

class PrimaryGroupSerializer < ApplicationSerializer


  public
  def id
    object.id
  end

  def name
    object.name
  end

  def include_id?; true; end

  def include_name?; true; end

  def attributes
    result = {}
    result[:id] = id if include?(:id)
    result[:name] = name if include?(:name)
    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  case name
when :id; include_id?
when :name; include_name?
else
 raise ArgumentError, "unknown serializer field"
end
end


  def include_associations!

    nil
  end
end
