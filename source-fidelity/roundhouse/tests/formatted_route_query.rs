//! Formatted route variants retain the base segment shape when the caller
//! passes a runtime options hash. Pin actual emitted execution, not just IR.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

#[test]
fn formatted_route_keeps_a_dynamic_query_hash_out_of_positional_segments() {
    emit_and_run::empty_app()
        .write("db/schema.rb", "ActiveRecord::Schema.define(version: 1) do\nend\n")
        .write("config/routes.rb", "Rails.application.routes.draw do\n get '/probe', to: 'probe#index', as: :probe\nend\n")
        .write("app/controllers/application_controller.rb", "class ApplicationController < ActionController::Base\nend\n")
        .write("app/controllers/probe_controller.rb", r#"class ProbeController < ApplicationController
  def index
    opts = {page: 2, order: "created"}
    render plain: probe_path(params: opts, format: "json")
  end
end
"#)
        .run_ruby(r#"
require_relative "app/controllers/probe_controller"
controller = ProbeController.new
controller.process_action(:index)
raise controller.body.inspect unless controller.body == "/probe.json?order=created&page=2"
"#)
        .assert_passes();
}
