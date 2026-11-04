//! Compile-valid, executable shapes found in the full Discourse emit.
use roundhouse::emit::ruby;
use roundhouse::ingest::ingest_app_from_tree;

fn emitted(source: &str, marked: bool) -> Vec<roundhouse::emit::EmittedFile> {
    let tree: std::collections::HashMap<std::path::PathBuf, Vec<u8>> = [(
        std::path::PathBuf::from("app/services/shapes.rb"),
        source.as_bytes().to_vec(),
    )]
    .into_iter()
    .collect();
    let app = ingest_app_from_tree(tree).expect("ingest");
    if marked {
        ruby::source_markers::with_source_markers(&app, || ruby::emit_library(&app))
    } else {
        ruby::emit_library(&app)
    }
}

fn run(source: &str, assertion: &str) {
    let source = format!("{source}\n{assertion}");
    let parsed = ruby_prism::parse(source.as_bytes());
    assert!(parsed.errors().next().is_none(), "{source}");
    let output = std::process::Command::new("ruby")
        .args(["-e", &source])
        .output()
        .expect("ruby");
    assert!(
        output.status.success(),
        "{}\n{source}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn first_light_non_def_method_names_keep_aliases_visibility_and_rbs() {
    let files = emitted(
        "class Shapes\n def scan_tag(content)\n content.upcase\n end\n alias_method :'scan_tag_#', :scan_tag\n private :'scan_tag_#'\nend\n",
        false,
    );
    let rb = files
        .iter()
        .find(|f| f.path.ends_with("shapes.rb"))
        .expect("Ruby");
    run(
        &rb.content,
        "raise unless Shapes.new.send(:'scan_tag_#', 'ok') == 'OK'; raise unless Shapes.private_instance_methods.include?(:'scan_tag_#')",
    );
    let rbs = files
        .iter()
        .find(|f| f.path.ends_with("shapes.rbs"))
        .expect("RBS");
    assert!(rbs.content.contains("`scan_tag_#`"), "{}", rbs.content);
    ruby_rbs::node::parse(&rbs.content).expect("valid RBS with quoted method names");
}

#[test]
fn first_light_sequence_defaults_do_not_inline_source_comments() {
    let files = emitted(
        "class Shapes\n def self.value(value = (getter = true; nil))\n getter ? 'default' : value\n end\nend\n",
        true,
    );
    let rb = files
        .iter()
        .find(|f| f.path.ends_with("shapes.rb"))
        .expect("Ruby");
    assert!(
        rb.content.contains("#<SPINEL_SOURCE>"),
        "markers must be enabled"
    );
    run(
        &rb.content,
        "raise unless Shapes.value == 'default'; raise unless Shapes.value('given') == 'given'",
    );
}

#[test]
fn first_light_lifted_data_factory_has_one_block_and_executes_methods() {
    let files = emitted(
        "class Shapes\n Page = Data.define(:records, :has_more) do\n def self.paginate(records)\n new(records: records, has_more: false)\n end\n end\nend\n",
        false,
    );
    let rb = files
        .iter()
        .find(|f| f.path.ends_with("shapes.rb"))
        .expect("Ruby");
    run(
        &rb.content,
        "page = Shapes::Page.paginate([1, 2]); raise unless page.records == [1, 2] && page.has_more == false",
    );
}

#[test]
fn first_light_survey_refusal_pragma_is_explicit_and_idempotent() {
    let mut files = vec![
        ("app/models/shapes.rb".into(), "class Shapes; end\n".into()),
        ("sig/shapes.rbs".into(), "class Shapes\nend\n".into()),
        ("spin.toml".into(), "[package]\n".into()),
    ];
    roundhouse::project::defer_spinel_survey_refusals(&mut files);
    assert!(files[0].1.starts_with("# spinel: defer-refusals\n"));
    assert!(!files[1].1.contains("defer-refusals"));
    assert!(!files[2].1.contains("defer-refusals"));
    let once = files.clone();
    roundhouse::project::defer_spinel_survey_refusals(&mut files);
    assert_eq!(files, once);
}

#[test]
fn explicit_survey_native_subclass_boundary_raises_its_gap() {
    let mut app = roundhouse::App::new();
    app.library_classes = roundhouse::ingest::ingest_library_classes(
        b"class Deferred < OpenStruct\n def self.settings; 123; end\n def value; data; end\nend\n",
        "deferred.rb",
    ).unwrap();
    assert_eq!(app.library_classes[0].parent.as_ref().unwrap().0.as_str(), "OpenStruct");
    let diagnostics = ruby::survey::native_subclass_boundaries(&mut app);
    assert_eq!(diagnostics.len(), 1);
    assert!(app.library_classes[0].parent.is_none());
    let files = ruby::emit_library(&app);
    let rb = files.iter().find(|f| f.path.ends_with("deferred.rb")).unwrap();
    run(&rb.content, r#"
      [:new, :allocate, :settings].each do |method|
        begin
          Deferred.public_send(method)
          raise "survey boundary returned invented behavior"
        rescue RuntimeError => error
          raise unless error.message.include?("class Deferred < OpenStruct: subclassing OpenStruct not supported")
        end
      end
    "#);
}
