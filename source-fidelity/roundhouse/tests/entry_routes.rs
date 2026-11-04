//! Route-scoped Spinel emit keeps only the request closure of the selected
//! flattened route patterns. These exercise the synthetic analyzed-App API,
//! not hand-edited emitted Ruby.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use roundhouse::build_target::BuildTarget;
use roundhouse::ingest::ingest_app_from_tree;

fn tree(files: &[(&str, &str)]) -> HashMap<PathBuf, Vec<u8>> {
    files
        .iter()
        .map(|(path, source)| (PathBuf::from(path), source.as_bytes().to_vec()))
        .collect()
}

fn analyzed(files: &[(&str, &str)]) -> roundhouse::App {
    let mut app = ingest_app_from_tree(tree(files)).expect("ingest synthetic app");
    roundhouse::session::analyze_and_lower_for(&mut app, BuildTarget::Spinel);
    app
}

fn select(app: &mut roundhouse::App, patterns: &[&str]) {
    roundhouse::entry_routes::select(
        app,
        patterns.iter().map(|path| (*path).to_string()).collect(),
    )
    .expect("select requested entry routes");
}

fn class_names(app: &roundhouse::App) -> Vec<&str> {
    app.entry_slice
        .as_ref()
        .expect("entry slice metadata")
        .classes
        .iter()
        .map(String::as_str)
        .collect()
}

const REQUEST_TREE: &[(&str, &str)] = &[
    (
        "db/schema.rb",
        "ActiveRecord::Schema.define do\n  create_table :topics do |t|\n    t.string :title\n  end\n  create_table :unused_items do |t|\n    t.string :name\n  end\nend\n",
    ),
    (
        "app/controllers/application_controller.rb",
        "class ApplicationController < ActionController::Base\n  before_action :authenticate\n\n  private\n\n  def authenticate\n    AuthSupport.allowed?\n  end\nend\n",
    ),
    (
        "app/controllers/topics_controller.rb",
        "class TopicsController < ApplicationController\n  def show\n    @topic = Topic.find(params[:topic_id])\n    @title = TopicPresenter.title(@topic)\n    head :ok\n  end\n\n  def index\n    head :ok\n  end\n\n  private\n\n  def unused_helper\n    UnusedItem.first\n  end\nend\n",
    ),
    (
        "app/controllers/unrelated_controller.rb",
        "class UnrelatedController < ApplicationController\n  def index\n    UnusedItem.first\n  end\nend\n",
    ),
    (
        "app/models/topic.rb",
        "class Topic < ApplicationRecord\nend\n",
    ),
    (
        "app/models/unused_item.rb",
        "class UnusedItem < ApplicationRecord\nend\n",
    ),
    (
        "app/models/auth_support.rb",
        "module AuthSupport\n  def self.allowed?\n    true\n  end\nend\n",
    ),
    (
        "app/models/topic_presenter.rb",
        "module TopicPresenter\n  def self.title(topic)\n    topic.title\n  end\nend\n",
    ),
    (
        "app/models/unused_support.rb",
        "module UnusedSupport\n  def self.unused\n    true\n  end\nend\n",
    ),
    (
        "test/controllers/topics_controller_test.rb",
        r#"class TopicsControllerTest < ActiveSupport::TestCase
  test "a placeholder" do
    assert true
  end
end
"#,
    ),
    ("test/fixtures/topics.yml", "one: {}\n"),
    ("app/assets/stylesheets/unrelated.css", "body {}\n"),
    ("public/unrelated.js", "window.unused = true;\n"),
    (
        "config/routes.rb",
        "Rails.application.routes.draw do\n  get \"/t/:slug/:topic_id\", to: \"topics#show\"\n  get \"/unrelated\", to: \"unrelated#index\"\nend\n",
    ),
];

#[test]
fn selected_action_keeps_applicable_inherited_filter_and_transitive_helpers() {
    let mut app = analyzed(REQUEST_TREE);
    select(&mut app, &["/t/:slug/:topic_id"]);

    let names = class_names(&app);
    for reached in [
        "ApplicationController",
        "TopicsController",
        "Topic",
        "AuthSupport",
        "TopicPresenter",
    ] {
        assert!(
            names.contains(&reached),
            "reachable class {reached} missing: {names:?}"
        );
    }
    for dropped in ["UnrelatedController", "UnusedItem", "UnusedSupport"] {
        assert!(
            !names.contains(&dropped),
            "unreachable class {dropped} retained: {names:?}"
        );
    }
    assert_eq!(
        app.controllers
            .iter()
            .map(|c| c.name.0.as_str())
            .collect::<Vec<_>>(),
        ["ApplicationController", "TopicsController",]
    );
    assert!(app.models.iter().any(|m| m.name.0.as_str() == "Topic"));
    assert!(!app.models.iter().any(|m| m.name.0.as_str() == "UnusedItem"));

    let topic_controller = app
        .controllers
        .iter()
        .find(|c| c.name.0.as_str() == "TopicsController")
        .unwrap();
    let action_names: Vec<_> = topic_controller
        .actions()
        .map(|a| a.name.as_str())
        .collect();
    assert_eq!(action_names, ["show"]);
    let slice = app.entry_slice.as_ref().unwrap();
    for (owner, class_side, method) in [
        ("ApplicationController", false, "authenticate"),
        ("TopicsController", false, "show"),
        ("TopicsController", false, "process_action"),
        ("AuthSupport", true, "allowed?"),
        ("TopicPresenter", true, "title"),
    ] {
        assert!(
            slice.method(owner, class_side, method),
            "missing {owner}#{method}"
        );
    }
    assert!(!slice.method("TopicsController", false, "index"));
    assert!(!slice.method("TopicsController", false, "unused_helper"));

    // The route-sliced project does not carry unrelated test/assets trees.
    let files = roundhouse::project::target_files(
        &app,
        Path::new("fixtures/tiny-api"),
        BuildTarget::Spinel,
    )
    .expect("emit selected Spinel project");
    let paths: Vec<_> = files.iter().map(|(path, _)| path.as_str()).collect();
    assert!(
        !paths.iter().any(|path| path.starts_with("test/")),
        "test files retained: {paths:?}"
    );
    assert!(
        !paths.iter().any(|path| path.starts_with("public/")),
        "public assets retained: {paths:?}"
    );
    assert!(
        !paths
            .iter()
            .any(|path| path.ends_with("unrelated_controller.rb")),
        "unreachable controller emitted: {paths:?}"
    );
}

#[test]
fn optional_nested_patterns_are_literal_and_keep_all_verbs_for_each_match() {
    let mut app = analyzed(&[
        (
            "app/controllers/topics_controller.rb",
            "class TopicsController < ActionController::Base\n  def show\n    head :ok\n  end\nend\n",
        ),
        (
            "config/routes.rb",
            "Rails.application.routes.draw do\n  get \"/t/:slug/:topic_id(/:revision)\", to: \"topics#show\"\n  post \"/t/:slug/:topic_id(/:revision)\", to: \"topics#show\"\n  resources :topics, only: :show do\n    resources :posts, only: :show\n  end\n  get \"/t/:topic_id\", to: \"topics#show\"\nend\n",
        ),
    ]);

    let before = roundhouse::lower::routes::flatten_routes(&app);
    let optional: Vec<_> = before
        .iter()
        .filter(|route| route.source_path == "/t/:slug/:topic_id(/:revision)")
        .map(|route| route.path.as_str())
        .collect();
    assert!(optional.contains(&"/t/:slug/:topic_id"));
    assert!(optional.contains(&"/t/:slug/:topic_id/:revision"));
    assert!(
        before
            .iter()
            .any(|route| route.path == "/topics/:topic_id/posts/:id"),
        "nested route not flattened: {before:?}"
    );

    select(
        &mut app,
        &["/t/:slug/:topic_id", "/t/:slug/:topic_id/:revision"],
    );
    let selected = roundhouse::lower::routes::flatten_routes(&app);
    assert!(
        selected
            .iter()
            .all(|route| route.path.starts_with("/t/:slug/:topic_id")),
        "nonmatching route retained: {selected:?}"
    );
    assert_eq!(
        selected
            .iter()
            .filter(|route| route.path == "/t/:slug/:topic_id")
            .count(),
        2,
        "both verbs for an exact path must remain: {selected:?}"
    );
    assert!(selected
        .iter()
        .any(|route| route.path == "/t/:slug/:topic_id/:revision"));
    assert!(!selected
        .iter()
        .any(|route| route.path == "/topics/:topic_id/posts/:id"));
    assert!(
        !selected.iter().any(|route| route.path == "/t/:topic_id"),
        "parameter names are literal, not interchangeable: {selected:?}"
    );
}

#[test]
fn constant_only_reference_keeps_its_declaring_class() {
    let mut app = analyzed(&[
        (
            "app/controllers/topics_controller.rb",
            "class TopicsController < ActionController::Base\n  def show\n    @title = TopicSettings::DEFAULT_TITLE\n    head :ok\n  end\nend\n",
        ),
        (
            "app/models/topic_settings.rb",
            "module TopicSettings\n  DEFAULT_TITLE = \"Topics\"\nend\n",
        ),
        (
            "app/models/unused_settings.rb",
            "module UnusedSettings\n  VALUE = \"unused\"\nend\n",
        ),
        (
            "config/routes.rb",
            "Rails.application.routes.draw do\n  get \"/t/:topic_id\", to: \"topics#show\"\nend\n",
        ),
    ]);

    select(&mut app, &["/t/:topic_id"]);
    let names = class_names(&app);
    assert!(
        names.contains(&"TopicSettings"),
        "constant-only dependency was dropped: {names:?}"
    );
    assert!(
        !names.contains(&"UnusedSettings"),
        "unreferenced constant owner retained: {names:?}"
    );
}

#[test]
fn patterns_without_an_ingested_route_are_reported_not_synthesized() {
    let mut app = analyzed(REQUEST_TREE);
    select(&mut app, &["/t/:slug/:topic_id", "/missing/:id"]);
    let slice = app.entry_slice.as_ref().unwrap();
    assert_eq!(slice.unmatched, ["/missing/:id"]);
    assert!(roundhouse::lower::routes::flatten_routes(&app)
        .iter()
        .all(|route| route.path == "/t/:slug/:topic_id"));
}

#[test]
fn selecting_only_unmatched_routes_is_an_error() {
    let mut app = analyzed(REQUEST_TREE);
    let error = roundhouse::entry_routes::select(&mut app, vec!["/missing/:id".into()])
        .expect_err("must not invent a dispatch route");
    assert!(error.contains("matched no ingested route"), "{error}");
}

#[test]
fn tests_fixtures_and_web_assets_are_not_entry_roots() {
    let mut app = analyzed(&[
        (
            "app/controllers/topics_controller.rb",
            "class TopicsController < ActionController::Base\n  def show\n    head :ok\n  end\nend\n",
        ),
        (
            "config/routes.rb",
            "Rails.application.routes.draw do\n  get \"/t/:topic_id\", to: \"topics#show\"\nend\n",
        ),
        (
            "test/controllers/unrelated_test.rb",
            "class UnrelatedTest < ActionController::TestCase\nend\n",
        ),
        ("test/fixtures/topics.yml", "one: {}\n"),
        ("app/assets/stylesheets/unrelated.css", "body {}\n"),
        ("public/unrelated.js", "window.unused = true;\n"),
    ]);
    assert!(
        !app.test_modules.is_empty(),
        "fixture test should ingest before slicing"
    );
    assert!(
        !app.fixtures.is_empty(),
        "YAML fixture should ingest before slicing"
    );
    assert!(
        app.stylesheets.iter().any(|name| name == "unrelated"),
        "stylesheet should ingest before slicing: {:?}",
        app.stylesheets
    );
    select(&mut app, &["/t/:topic_id"]);
    assert!(app.test_modules.is_empty());
    assert!(app.fixtures.is_empty());
    assert!(app.binary_assets.is_empty());
    assert!(app.stylesheets.is_empty());
}
