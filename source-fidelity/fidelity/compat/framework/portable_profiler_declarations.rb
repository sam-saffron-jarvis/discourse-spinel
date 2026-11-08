# frozen_string_literal: true
# GENERATED actual application profiler path declarations, not observed values.
module PortableProfilerDeclarations
def self.skip_paths(base_path)
%w[
      /assets/
      /cdn_asset/
      /extra-locales/
      /favicon/proxied
      /highlight-js/
      /images/
      /javascripts/
      /letter_avatar_proxy/
      /letter_avatar/
      /logs
      /manifest.webmanifest
      /message-bus/
      /opensearch.xml
      /presence/
      /secure-media-uploads/
      /secure-uploads/
      /srv/status
      /stylesheets/
      /svg-sprite/
      /theme-javascripts
      /topics/timings
      /uploads/
      /user_avatar/
      /theme-qunit/
    ].map { |path| "#{base_path}#{path}" }.concat([%r{/(\d+/)?(theme-qunit|tests)}])
end
end
