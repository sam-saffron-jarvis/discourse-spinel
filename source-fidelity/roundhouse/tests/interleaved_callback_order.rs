//! Callback nesting must match actual Rails, not grouped before/around/after lists.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const PARENT: &str = r#"class ApplicationController < ActionController::Base
  EVENTS = ["initial"]
  before_action :first
  around_action :outer
  before_action :second
  after_action :parent_after
  rescue_from ArgumentError do
    mark("rescued")
    head :bad_request
  end
  private
  def mark(name)
    ApplicationController::EVENTS << name
  end
  def first
    mark("first")
    if action_name == "halted"
      mark("halt")
      render plain: "halt"
    end
  end
  def outer
    mark("outer.enter")
    if action_name == "cached"
      mark("cached")
      render plain: "cached"
    else
      yield
    end
  ensure
    mark("outer.ensure")
  end
  def second
    mark("second")
  end
  def parent_after
    mark("parent.after")
  end
end
"#;
const CHILD: &str = r#"class ProbeController < ApplicationController
  before_action :third
  around_action :inner
  before_action :fourth
  after_action :child_after
  def index
    mark("action")
    render plain: "ok"
  end
  def halted
    mark("must-not-run")
    render plain: "bad"
  end
  def cached
    mark("must-not-run")
    render plain: "bad"
  end
  def fails
    mark("failure")
    raise ArgumentError, "actual callback unwind"
  end
  private
  def third
    mark("third")
  end
  def inner
    mark("inner.enter")
    yield
  ensure
    mark("inner.ensure")
  end
  def fourth
    mark("fourth")
  end
  def child_after
    mark("child.after")
  end
end
"#;

#[test]
#[ignore = "requires SPINEL and original Rails bundle; runs no servers or database"]
fn interleaved_inherited_callbacks_and_unwinds_match_real_rails_on_both_runtimes() {
    use std::process::Command;
    let actions = ["index", "halted", "cached", "fails"];
    let (emitted, errors) = emit_and_run::empty_app()
        .write("db/schema.rb", "ActiveRecord::Schema.define(version: 1) do\nend\n")
        .write("app/controllers/application_controller.rb", PARENT)
        .write("app/controllers/probe_controller.rb", CHILD)
        .write("config/routes.rb", "Rails.application.routes.draw do\n get '/probe', to: 'probe#index'\n get '/halted', to: 'probe#halted'\n get '/cached', to: 'probe#cached'\n get '/fails', to: 'probe#fails'\nend\n")
        .emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let mut driver = String::from("require 'json'\nrequire_relative 'runtime/base64'\nrequire_relative 'runtime/json_impl'\nrequire_relative 'runtime/json_builder'\nrequire_relative 'runtime/active_support_ext'\nrequire_relative 'runtime/rails'\nrequire_relative 'runtime/action_dispatch'\nrequire_relative 'runtime/action_dispatch/request'\nrequire_relative 'runtime/action_controller'\nrequire_relative 'runtime/inprocess_controller'\nrequire_relative 'app/controllers/probe_controller'\n");
    for action in actions {
        driver.push_str(&format!("ApplicationController::EVENTS.clear\nr = ActionDispatch::Request.new\nr.request_method = 'GET'\nr.format = 'json'\nm = ActionDispatch::Router::MatchResult.new(:probe, :{action}, {{}})\nActionDispatch::InProcessController.dispatch(ProbeController.new, r, m)\nputs ApplicationController::EVENTS.join('|')\n"));
    }
    let source = emitted.join("callback_order.rb");
    std::fs::write(&source, driver).unwrap();
    let ruby = Command::new("ruby").arg(&source).current_dir(&*emitted).output().unwrap();
    assert!(ruby.status.success(), "{}", String::from_utf8_lossy(&ruby.stderr));
    let compiler = std::fs::canonicalize(std::env::var_os("SPINEL").expect("SPINEL required")).unwrap();
    let binary = emitted.join("callback_order");
    let build = Command::new(compiler).args(["--jobs=4", "--cc=clang"]).arg(&source).arg("-o").arg(&binary).output().unwrap();
    assert!(build.status.success(), "{}", String::from_utf8_lossy(&build.stderr));
    let native = Command::new(binary).current_dir(&*emitted).output().unwrap();
    assert!(native.status.success(), "{}", String::from_utf8_lossy(&native.stderr));
    assert_eq!(native.stdout, ruby.stdout);
    let mut original = format!("require 'action_controller/railtie'\nrequire 'rack/mock'\n{PARENT}\n{CHILD}\n");
    for action in actions {
        original.push_str(&format!("ApplicationController::EVENTS.clear\nProbeController.action(:{action}).call(Rack::MockRequest.env_for('http://localhost/probe'))\nputs ApplicationController::EVENTS.join('|')\n"));
    }
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("discourse");
    let rails = Command::new("bundle").args(["exec", "ruby", "-e", &original]).current_dir(root).output().unwrap();
    assert!(rails.status.success(), "{}", String::from_utf8_lossy(&rails.stderr));
    assert_eq!(rails.stdout, ruby.stdout, "emitted callback order differs from actual Rails");
}
