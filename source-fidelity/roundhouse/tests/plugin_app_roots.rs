//! Discourse plugins are selected by plugin.rb, independently of PATH gems.
//! Boot DSLs and mounting remain explicit gaps, not claims of runtime support.

use std::path::PathBuf;

use roundhouse::ingest::{ingest_app_from_tree, survey};

fn tree(files: &[(&str, &str)]) -> roundhouse::vfs::FileTree {
    files.iter().map(|(path, text)| (PathBuf::from(path), text.as_bytes().to_vec())).collect()
}

fn surveyed(files: &[(&str, &str)]) -> (roundhouse::App, Vec<String>) {
    survey::activate();
    let result = ingest_app_from_tree(tree(files));
    let gaps = survey::drain().into_iter().map(|gap| gap.to_string()).collect();
    (result.expect("plugin survey must recover"), gaps)
}

#[test]
fn plugin_app_layers_and_sibling_library_are_ingested_once() {
    let (app, gaps) = surveyed(&[
        ("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table :foos do |t|\n    t.string :title\n  end\nend\n"),
        ("app/models/application_record.rb", "class ApplicationRecord < ActiveRecord::Base\n  self.abstract_class = true\nend\n"),
        ("app/controllers/application_controller.rb", "class ApplicationController < ActionController::Base\nend\n"),
        ("plugins/foo/plugin.rb", "enabled_site_setting :foo_enabled\nmodule FooPlugin\n  def self.name\n    'foo'\n  end\nend\n"),
        ("plugins/foo/app/models/foo.rb", "class Foo < ApplicationRecord\nend\n"),
        ("plugins/foo/app/controllers/foos_controller.rb", "class FoosController < ApplicationController\n  def index\n    @foos = Foo.all\n  end\nend\n"),
        ("plugins/foo/app/views/foos/index.html.erb", "<h1>Foos</h1>"),
        ("plugins/foo/app/serializers/foo_serializer.rb", "class FooSerializer\n  def title\n    'foo'\n  end\nend\n"),
        ("plugins/foo/lib/foo_tool.rb", "class FooTool\n  def self.call\n    1\n  end\nend\n"),
        ("plugins/not_a_plugin/app/models/ignored.rb", "class Ignored < ApplicationRecord\nend\n"),
    ]);
    assert_eq!(app.app_roots, vec!["app", "plugins/foo/app"]);
    assert_eq!(app.models.iter().filter(|model| model.name.0.as_str() == "Foo").count(), 1);
    assert!(!app.models.iter().any(|model| model.name.0.as_str() == "Ignored"));
    assert_eq!(app.controllers.iter().filter(|controller| controller.name.0.as_str() == "FoosController").count(), 1);
    assert!(app.views.iter().any(|view| view.name.as_str() == "foos/index"));
    for name in ["FooPlugin", "FooSerializer", "FooTool"] {
        assert_eq!(app.library_classes.iter().filter(|class| class.name.0.as_str() == name).count(), 1, "{name}");
    }
    assert!(gaps.iter().any(|gap| gap.contains("plugin.rb DSL not modeled: enabled_site_setting")), "{gaps:?}");
}

#[test]
fn lib_only_plugins_contribute_libraries_and_marker_only_plugins_still_survey() {
    let (app, gaps) = surveyed(&[
        ("plugins/lib_only/plugin.rb", "# metadata only\n"),
        ("plugins/lib_only/lib/tool.rb", "module PluginTool\n  def self.call\n    1\n  end\nend\n"),
        ("plugins/assets_only/plugin.rb", "register_asset 'foo.scss'\n"),
        ("plugins/assets_only/assets/foo.scss", "body {}"),
        ("plugins/missing_marker/lib/ignored.rb", "class Ignored\nend\n"),
    ]);
    assert_eq!(app.app_roots, vec!["app", "plugins/lib_only/app"]);
    assert!(app.library_classes.iter().any(|class| class.name.0.as_str() == "PluginTool"));
    assert!(!app.library_classes.iter().any(|class| class.name.0.as_str() == "Ignored"));
    assert!(gaps.iter().any(|gap| gap.contains("plugins/assets_only/plugin.rb") && gap.contains("plugin.rb DSL not modeled: register_asset")), "{gaps:?}");
}

#[test]
fn plugin_boot_dsl_is_inventoried_per_construct_even_in_nested_blocks() {
    let (_, gaps) = surveyed(&[("plugins/foo/plugin.rb", r#"
# register_fake is just a comment, not a construct.
register_asset "foo.scss"
register_asset "bar.scss"
after_initialize do
  add_to_serializer(:topic, :foo) { object.foo }
  self.on(:event) do
    add_to_class(:topic, :foo) { true }
  end
  Discourse::Application.routes.append { mount Foo::Engine, at: "/foo" }
end
module FooPlugin
  def self.ordinary_method
    not_a_boot_call
  end
end
"#)]);
    for name in ["register_asset", "after_initialize", "add_to_serializer", "on", "add_to_class", "mount"] {
        let needle = format!("plugin.rb DSL not modeled: {name}");
        assert_eq!(gaps.iter().filter(|gap| gap.contains(&needle)).count(), 1, "{gaps:?}");
    }
    assert!(gaps.iter().any(|gap| gap.contains("plugin.rb boot call not modeled: append")), "{gaps:?}");
    assert!(!gaps.iter().any(|gap| gap.contains("DSL not modeled: not_a_boot_call") || gap.contains("register_fake")), "{gaps:?}");
}

#[test]
fn plugin_dsl_is_not_silently_accepted_in_strict_mode() {
    let result = ingest_app_from_tree(tree(&[("plugins/foo/plugin.rb", "register_asset 'foo.scss'\n")]));
    let error = result.expect_err("unmodeled plugin boot DSL must block strict ingest").to_string();
    assert!(error.contains("plugin.rb DSL not modeled: register_asset"), "{error}");
}

#[test]
fn plugin_routes_are_surveyed_but_never_installed_at_host_root() {
    let (app, gaps) = surveyed(&[
        ("config/routes.rb", "Rails.application.routes.draw do\n  get '/host', to: 'host#index'\nend\n"),
        ("plugins/foo/plugin.rb", "# metadata\n"),
        ("plugins/foo/lib/foo/engine.rb", "module Foo\n  class Engine < ::Rails::Engine\n    engine_name 'foo'\n    isolate_namespace Foo\n  end\nend\n"),
        ("plugins/foo/config/routes.rb", "Foo::Engine.routes.draw do\n  get '/only_in_plugin', to: 'foos#index'\n  authenticate :user do\n    get '/private', to: 'foos#private'\n  end\nend\n"),
    ]);
    assert!(gaps.iter().any(|gap| gap.contains("plugins/foo/config/routes.rb") && gap.contains("plugin foo: engine route mounting not modeled")), "{gaps:?}");
    assert!(gaps.iter().any(|gap| gap.contains("authenticate")), "route DSL must actually be ingested: {gaps:?}");
    let routes = format!("{:?}", app.routes);
    assert!(routes.contains("/host"), "{routes}");
    assert!(!routes.contains("only_in_plugin") && !routes.contains("/private"), "engine paths leaked into host: {routes}");
}

#[test]
fn plugin_migrations_remain_a_named_schema_gap() {
    let (app, gaps) = surveyed(&[
        ("plugins/foo/plugin.rb", "# metadata\n"),
        ("plugins/foo/db/migrate/001_create_foos.rb", "class CreateFoos < ActiveRecord::Migration[8.0]\n  def change\n    create_table :foos\n  end\nend\n"),
    ]);
    assert!(gaps.iter().any(|gap| gap.contains("plugins/foo/db/migrate") && gap.contains("plugin foo: migration schema not ingested")), "{gaps:?}");
    assert!(!format!("{:?}", app.schema).contains("foos"));
}

#[test]
fn malformed_plugin_entrypoint_reports_parse_error_and_keeps_other_roots() {
    let ((app, _), diagnostics) = roundhouse::ingest::prism::scope(|| surveyed(&[
        ("plugins/broken/plugin.rb", "register_asset (\n"),
        ("plugins/okay/plugin.rb", "# metadata\n"),
        ("plugins/okay/lib/okay.rb", "class Okay\nend\n"),
    ]));
    assert!(app.library_classes.iter().any(|class| class.name.0.as_str() == "Okay"));
    assert!(!diagnostics.is_empty(), "malformed plugin must retain parse diagnostics");
}
