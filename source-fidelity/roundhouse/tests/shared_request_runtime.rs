//! Shared in-process request code must load/run unchanged on CRuby and Spinel.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const DRIVER: &str = r#"require_relative "runtime/base64"
require_relative "runtime/json_impl"
require_relative "runtime/json_builder"
require_relative "runtime/active_support_ext"
require_relative "runtime/rails"
require_relative "runtime/action_dispatch"
require_relative "runtime/action_dispatch/request"
require_relative "runtime/action_controller"
require_relative "runtime/inprocess_controller"
class InProcessUnitController < ActionController::Base
  def process_action(action)
    raise "wrong action" unless action == :show
    cache_control[:no_cache] = true
    cache_control[:extras] = ["no-store"]
    render("actual framework response", content_type: "text/plain")
  end
end
params = {"page" => "2", "format" => "json"}
request = ActionDispatch::Request.new({"REQUEST_METHOD" => "GET", "QUERY_STRING" => "page=2", "action_dispatch.request.parameters" => params})
raise "lost cached params" unless request.params["page"] == "2"
request.format = "json"
matched = ActionDispatch::Router::MatchResult.new(:unit, :show, {})
response = ActionDispatch::InProcessController.dispatch(InProcessUnitController.new, request, matched, etag_middleware: false)
raise "wrong response" unless response.status == 200 && response.body == "actual framework response"
raise "wrong length" unless response.headers["Content-Length"] == "25"
raise "lost default charset" unless response.headers["Content-Type"] == "text/plain; charset=utf-8"
raise "lost source cache directives" unless response.headers["Cache-Control"] == "no-cache, no-store"
raise "deleted Rack::ETag still synthesized a validator" unless response.headers["ETag"].nil?
raise "missing real UUID" unless response.headers["X-Request-Id"].to_s.split("-").map(&:length) == [8, 4, 4, 4, 12]
request.env["HTTP_X_REQUEST_ID"] = "client/id@1"
second = ActionDispatch::InProcessController.dispatch(InProcessUnitController.new, request, matched)
raise "wrong client request ID sanitization" unless second.headers["X-Request-Id"] == "clientid@1"
raise "default Rack::ETag lost no-store body validator" if second.headers["ETag"].nil?
explicit = InProcessUnitController.new
explicit.render("ascii", content_type: "text/plain; charset=iso-8859-1")
raise "overwrote explicit charset" unless explicit.content_type == "text/plain; charset=iso-8859-1"
cacheable = InProcessUnitController.new
cacheable.render("cacheable", content_type: "application/json")
cacheable.commit_conditional_get!("GET", "")
raise "cacheable body lost validator" if cacheable.headers["ETag"].nil?
raise "context leak" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
begin
  ActionDispatch::Request.new({"QUERY_STRING" => "api_key=secret"})
  raise "unparsed credential query accepted"
rescue ArgumentError
end
request.env["HTTP_COOKIE"] = "_t=secret"
begin
  ActionDispatch::InProcessController.dispatch(InProcessUnitController.new, request, matched)
  raise "unsupported cookie profile accepted"
rescue ArgumentError
end
request.env.delete("HTTP_COOKIE")
request.request_method = "POST"
begin
  ActionDispatch::InProcessController.dispatch(InProcessUnitController.new, request, matched)
  raise "unsupported verb accepted"
rescue ArgumentError
end
puts "PASS real shared request/response, parsed context and fail-closed profiles"
"#;

#[test]
#[ignore = "requires SPINEL pointing to the native compiler and libcrypto development libraries"]
fn request_runtime_runs_identically_without_a_transport_or_runtime_swap() {
    let (emitted, errors) = emit_and_run::empty_app()
        .write("db/schema.rb", "ActiveRecord::Schema.define(version: 1) do\nend\n")
        .write("app/controllers/application_controller.rb", "class ApplicationController < ActionController::Base\nend\n")
        .emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let driver = emitted.join("request_unit.rb");
    std::fs::write(&driver, DRIVER).unwrap();
    let ruby = std::process::Command::new("ruby").arg(&driver).current_dir(&*emitted).output().unwrap();
    assert!(ruby.status.success(), "{}", String::from_utf8_lossy(&ruby.stderr));
    let compiler = std::env::var_os("SPINEL").expect("SPINEL must name the existing compiler for this native runtime regression");
    let compiler = std::fs::canonicalize(compiler).unwrap();
    let binary = emitted.join("request_unit");
    let build = std::process::Command::new(compiler).args(["--cc=clang", "--jobs=4"]).arg(&driver).arg("-o").arg(&binary).output().unwrap();
    assert!(build.status.success(), "{}", String::from_utf8_lossy(&build.stderr));
    let native = std::process::Command::new(binary).current_dir(&*emitted).output().unwrap();
    assert!(native.status.success(), "{}", String::from_utf8_lossy(&native.stderr));
    assert_eq!(native.stdout, ruby.stdout);
}
