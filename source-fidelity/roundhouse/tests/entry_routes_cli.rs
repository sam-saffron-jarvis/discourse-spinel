use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{SystemTime, UNIX_EPOCH};

const MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");
const ROUTES: &str = "Rails.application.routes.draw do\n\
  get \"/posts\", to: \"posts#index\"\n\
  post \"/posts\", to: \"posts#create\"\n\
  get \"/posts/:id\", to: \"posts#show\"\n\
  delete \"/posts/:id\", to: \"posts#destroy\"\n\
  get \"/posts/archive\", to: \"posts#archive\"\n\
end\n";
const POSTS_CONTROLLER: &str = "class PostsController < ApplicationController\n\
  def index; end\n\
  def create; end\n\
  def show; end\n\
  def destroy; end\n\
  def archive; end\n\
end\n";

struct Scratch(PathBuf);

impl Scratch {
    fn new(label: &str) -> Self {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = Path::new(MANIFEST_DIR).join("target").join(format!(
            "entry-routes-cli-{label}-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("create test scratch under target/");
        Self(path)
    }

    fn app(&self) -> PathBuf {
        self.0.join("source")
    }

    fn output(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn copy_tree(from: &Path, to: &Path) {
    fs::create_dir_all(to).expect("create fixture directory");
    for entry in fs::read_dir(from).expect("read fixture directory") {
        let entry = entry.expect("fixture entry");
        let dest = to.join(entry.file_name());
        if entry.file_type().expect("fixture file type").is_dir() {
            copy_tree(&entry.path(), &dest);
        } else {
            fs::copy(entry.path(), dest).expect("copy fixture file");
        }
    }
}

fn app(label: &str) -> Scratch {
    let scratch = Scratch::new(label);
    let root = scratch.app();
    copy_tree(&Path::new(MANIFEST_DIR).join("fixtures/tiny-blog"), &root);
    fs::write(root.join("config/routes.rb"), ROUTES).expect("write route fixture");
    fs::write(
        root.join("app/controllers/posts_controller.rb"),
        POSTS_CONTROLLER,
    )
    .expect("write controller fixture");
    scratch
}

fn run(args: &[&str], root: &Path, output: &Path) -> Output {
    Command::new(env!("CARGO_BIN_EXE_roundhouse"))
        .args(args)
        .arg(root)
        .arg("-o")
        .arg(output)
        .output()
        .expect("spawn roundhouse")
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn route_rows(output: &str) -> Vec<&str> {
    output
        .split("ActionDispatch::Router::Route.new(")
        .skip(1)
        .map(|args| args.split(')').next().expect("route constructor arguments"))
        .collect()
}

fn emit_with_routes(args: &[&str], root: &Path, output: &Path) -> Vec<String> {
    let result = run(args, root, output);
    assert!(result.status.success(), "{}", stderr(&result));
    let routes = fs::read_to_string(output.join("config/routes.rb")).expect("emitted RouteTable");
    route_rows(&routes).into_iter().map(str::to_owned).collect()
}

#[test]
fn separated_and_equals_entry_route_lists_are_accepted_and_filter_routes_and_actions() {
    let scratch = app("syntax");
    let separated = emit_with_routes(
        &[
            "--target",
            "spinel",
            "--allow-unsupported",
            "--entry-routes",
            "/posts,/posts/:id",
        ],
        &scratch.app(),
        &scratch.output("separated"),
    );
    assert_eq!(separated.len(), 4, "{separated:#?}");
    assert!(separated
        .iter()
        .any(|row| row.contains("\"/posts\"") && row.contains(":index")));
    assert!(separated
        .iter()
        .any(|row| row.contains("\"/posts\"") && row.contains(":create")));
    assert!(separated
        .iter()
        .any(|row| row.contains("\"/posts/:id\"") && row.contains(":show")));
    assert!(separated
        .iter()
        .any(|row| row.contains("\"/posts/:id\"") && row.contains(":destroy")));
    assert!(separated.iter().all(|row| !row.contains("archive")));
    let controllers = fs::read_to_string(
        scratch
            .output("separated")
            .join("app/controllers/posts_controller.rb"),
    )
    .expect("emitted selected controller");
    assert!(controllers.contains("def index"), "{controllers}");
    assert!(controllers.contains("def show"), "{controllers}");
    assert!(!controllers.contains("def archive"), "{controllers}");

    let equals = emit_with_routes(
        &[
            "--target=spinel",
            "--allow-unsupported",
            "--entry-routes=/posts,/posts/:id",
        ],
        &scratch.app(),
        &scratch.output("equals"),
    );
    assert_eq!(equals, separated);
}

#[test]
fn no_entry_route_flag_keeps_all_route_rows_and_actions() {
    let scratch = app("default");
    let rows = emit_with_routes(
        &["--target", "spinel", "--allow-unsupported"],
        &scratch.app(),
        &scratch.output("all"),
    );
    assert_eq!(rows.len(), 5, "{rows:#?}");
    assert!(rows
        .iter()
        .any(|row| row.contains("\"/posts/archive\"") && row.contains(":archive")));
    let controllers = fs::read_to_string(
        scratch
            .output("all")
            .join("app/controllers/posts_controller.rb"),
    )
    .expect("emitted controller");
    assert!(controllers.contains("def archive"), "{controllers}");
}

#[test]
fn empty_and_malformed_entry_route_lists_are_rejected() {
    for value in [
        "",
        "posts",
        "/posts,,/posts/:id",
        "/posts?sort=recent",
        "/posts(.:format)",
    ] {
        let result = Command::new(env!("CARGO_BIN_EXE_roundhouse"))
            .args(["--target", "spinel", "--entry-routes", value])
            .output()
            .expect("spawn roundhouse");
        assert!(!result.status.success(), "accepted {value:?}");
        assert!(
            stderr(&result).contains("--entry-routes"),
            "{}",
            stderr(&result)
        );
    }

    let missing = Command::new(env!("CARGO_BIN_EXE_roundhouse"))
        .args(["--target", "spinel", "--entry-routes"])
        .output()
        .expect("spawn roundhouse");
    assert!(!missing.status.success());
    assert!(
        stderr(&missing).contains("--entry-routes requires"),
        "{}",
        stderr(&missing)
    );
}

#[test]
fn entry_routes_are_restricted_to_spinel_transpiles() {
    for args in [
        vec!["--target", "go", "--entry-routes=/posts"],
        vec!["--site", "--entry-routes=/posts"],
        vec!["--target", "fractal", "--entry-routes=/posts"],
    ] {
        let result = Command::new(env!("CARGO_BIN_EXE_roundhouse"))
            .args(&args)
            .output()
            .expect("spawn roundhouse");
        assert!(!result.status.success(), "accepted {args:?}");
        assert!(
            stderr(&result).contains("--entry-routes"),
            "{}",
            stderr(&result)
        );
    }
}

#[test]
fn only_explicit_survey_slices_select_conservative_class_flow() {
    let scratch = app("class-flow");
    for (name, args, unified) in [
        ("slice", vec!["--target", "spinel", "--allow-unsupported", "--entry-routes=/posts"], false),
        ("survey-slice", vec!["--target", "spinel", "--survey", "--allow-unsupported", "--entry-routes=/posts"], true),
        ("survey-whole", vec!["--target", "spinel", "--survey", "--allow-unsupported"], false),
    ] {
        let result = run(&args, &scratch.app(), &scratch.output(name));
        assert!(result.status.success(), "{}", stderr(&result));
        let manifest = fs::read_to_string(scratch.output(name).join("spin.toml")).expect("manifest");
        assert_eq!(manifest.contains("class_flow = \"unified\""), unified, "{name}: {manifest}");
    }
}
