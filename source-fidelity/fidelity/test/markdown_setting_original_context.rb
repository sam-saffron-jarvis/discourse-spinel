# frozen_string_literal: true
module OriginalMarkdownEndpointLayoutRead
  def enable_markdown_endpoints(scoped_to = nil)
    raise ArgumentError, 'unsupported scoped markdown getter' unless scoped_to.nil?
    # Same explicit profile admission, but return is independently evaluated
    # by raw original UpcomingChanges.enabled?, NOT the candidate's Boolean.
    portable_store.get_markdown_endpoints_for_layout(portable_site, HtmlUpcomingStatuses::VALUES)
    provider = OriginalHtmlStageSource::LiveProviderView.new(portable_store, portable_site)
    OriginalHtmlStageSource::UpcomingChanges.live_provider = provider
    OriginalHtmlStageSource::UpcomingChanges.enabled?(:enable_markdown_endpoints)
  end
  def enable_markdown_endpoints?(scoped_to = nil); enable_markdown_endpoints(scoped_to); end
end
SiteSetting.extend(OriginalMarkdownEndpointLayoutRead)
