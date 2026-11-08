# Stage0 remains independently compared against its original source expression.
require_relative "portable_security_reference_consumer"
load ENV.fetch("FIDELITY_VISIBLE_PAGE_COMPONENT")
load ENV.fetch("FIDELITY_VISIBLE_PAGE_CONSUMER")
class VisiblePageProbe
  def self.relation(options)
    TopicQueryVisiblePage.validate_options!(options)
    query = TopicQuery.new(nil)
    query.instance_exec(options) do |options|
      eval(File.binread(ENV.fetch("FIDELITY_VISIBLE_PAGE_EXPRESSION")), binding,
           File.expand_path("lib/topic_query.rb"), 1)
    end
  end
end
