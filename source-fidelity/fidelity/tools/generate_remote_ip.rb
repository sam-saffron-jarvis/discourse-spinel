# frozen_string_literal: true
require "prism"
require "digest"

def generate_remote_ip(root, read, parts)
  path = "actionpack-8.1.4/lib/action_dispatch/middleware/remote_ip.rb"
  original = read.call(path)
  owner = Prism.parse(original).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ClassNode).first
  raise "RemoteIp source owner changed" unless owner.constant_path.slice == "RemoteIp"
  # Keep the complete original algorithm, defaults and error class. Only the
  # framework Request protocol and unsupported object-Range expression differ.
  parts << {source: path, start_byte: 0, end_byte: original.bytesize, text_sha256: Digest::SHA256.hexdigest(original)}
  source = original.sub("custom_proxies.blank?", "custom_proxies.nil?")
  source = source.sub("@app = app", 'raise ArgumentError, "unsupported custom remote-IP proxies profile" unless custom_proxies.nil?' + "\n      @app = app")
  source = source.sub("req = ActionDispatch::Request.new env", "req = Rack::CoreRequest.new(env)")
  old = "range = IPAddr.new(ip).to_range"
  raise "RemoteIp singleton-range check changed" unless source.include?(old) && source.include?("range.begin == range.end")
  source = source.sub(old, "address = IPAddr.new(ip)").sub("range.begin == range.end", "address.prefix == (address.ipv4? ? 32 : 128)")
  target = "compat/framework/portable_remote_ip.rb"
  raise "invalid shared RemoteIp" unless Prism.parse(source).success?
  File.binwrite(File.join(root, "fidelity", target), source)
  {candidate: target, candidate_sha256: Digest::SHA256.hexdigest(source), source: path,
   transformations: [
     "Request env adapter writes the identical lazy action_dispatch.remote_ip GetIp slot; controller hydration reads that real object's to_s",
     "Default-proxy constructor only: nonnil custom proxies explicitly refuse, never silently replaced",
     "IPAddr singleton to_range begin==end is equivalent to prefix==address-family bit width, avoiding Spinel's unsupported Range of objects",
     "Proxy and server ingress excluded before effects by portable_json_ingress.rb, not by forcing original live settings"],
   source_replacement: {before: old + "; range.begin == range.end", after: "address = IPAddr.new(ip); address.prefix == (address.ipv4? ? 32 : 128)"},
   equivalence_test: "test_remote_ip_ingress.py original/shared/native and singleton-mask controls",
   full_stack_accepted: false, forwarded_profile_accepted: false, observed_ip_values_as_inputs: false}
end
