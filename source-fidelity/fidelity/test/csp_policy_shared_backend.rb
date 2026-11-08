# frozen_string_literal: true
# The same candidate construction entry for standalone and composed unit probes.
def unit_build_csp(context, base_url, report_only)
  PortableCspUnitProfile.validate_build!(base_url, report_only)
  (context.extensions.themes + context.extensions.plugins).each { |extension| PortableCspUnitProfile.validate_extension!(extension) }
  ContentSecurityPolicy.new(context).build("unit-theme", base_url: base_url, report_only: report_only)
end

def unit_default_directives(context, report_only)
  ContentSecurityPolicy::Default.new(context: context, report_only: report_only).directives
end
