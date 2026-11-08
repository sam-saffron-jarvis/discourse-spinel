//! Diagnostic-only controls of the audited ORIGINAL multisite patch input.
//! No guessed loader order, fabricated provider, inferred-ABI waiver or native
//! acceptance. The actual Rails boundary has a separate guarded oracle.
use roundhouse::dialect::MethodReceiver;
use roundhouse::expr::{Expr, ExprNode};
use roundhouse::project::BuildTarget;

fn visit(expr: &Expr, f: &mut impl FnMut(&Expr)) {
    f(expr);
    // Defined's operand is intentionally not an evaluated child in IR.
    if let ExprNode::Defined { operand } = &*expr.node {
        visit(operand, f);
    }
    expr.node.for_each_child(&mut |child| visit(child, f));
}

#[test]
#[ignore = "requires audited expanded original core input; output is never executed"]
fn actual_patch_retains_yield_rescue_default_lookup_and_unproved_feature_lifetime() {
    let input =
        std::path::PathBuf::from(std::env::var("ROUNDHOUSE_ORIGINAL_SETTINGS_APP").expect("audited input required"));
    let app = roundhouse::ingest::ingest_app_for_target(&input, BuildTarget::Spinel).unwrap();
    let path = input.join("lib/freedom_patches/rails_multisite.rb");
    let original = std::fs::read_to_string(&path).unwrap();
    let (index, source) = app
        .sources
        .iter()
        .enumerate()
        .find(|(_, source)| source.path == path.to_string_lossy())
        .unwrap();
    assert_eq!(source.text, original, "original patch bytes changed");
    let records: Vec<_> = app
        .library_classes
        .iter()
        .filter(|class| class.name.0.as_str() == "RailsMultisite::ConnectionManagement")
        .collect();
    let safe = records
        .iter()
        .flat_map(|class| &class.methods)
        .find(|method| method.name.as_str() == "safe_each_connection")
        .expect("genuine patch method missing");
    assert_eq!(safe.receiver, MethodReceiver::Class);
    assert_eq!(safe.name_span.file.0 as usize, index + 1);
    assert!(safe.params.is_empty(), "original no-positional-parameter ABI changed");
    let mut yields = 0;
    let mut breaks = 0;
    let mut rescues = 0;
    let mut constants = std::collections::BTreeSet::new();
    let mut defined = false;
    visit(&safe.body, &mut |expr| match &*expr.node {
        ExprNode::Yield { .. } => yields += 1,
        ExprNode::Break { .. } => breaks += 1,
        ExprNode::BeginRescue { .. } => rescues += 1,
        ExprNode::Defined { .. } => defined = true,
        ExprNode::Const { path } => {
            constants.insert(path.iter().map(|part| part.as_str()).collect::<Vec<_>>().join("::"));
        }
        _ => {}
    });
    assert_eq!(yields, 2, "primary/retry callback removed");
    assert_eq!(breaks, 2, "original failure controls removed");
    assert!(rescues > 0 && defined, "original exception/late constant world removed");
    for name in [
        "PG::ConnectionBad",
        "PG::UnableToSend",
        "PG::ServerError",
        "RailsFailover::ActiveRecord",
        "RailsMultisite::ConnectionManagement::DEFAULT",
    ] {
        assert!(
            constants.contains(name),
            "genuine runtime dependency omitted: {name}: {constants:?}"
        );
    }
    let active = records
        .iter()
        .flat_map(|class| &class.methods)
        .find(|method| method.name.as_str() == "each_active_connection")
        .unwrap();
    assert_eq!(active.block_param.as_ref().unwrap().name.as_str(), "blk");
    let delegated = records
        .iter()
        .flat_map(|class| &class.methods)
        .find(|method| method.name.as_str() == "current_db" && method.receiver == MethodReceiver::Class)
        .unwrap();
    assert!(delegated.params.iter().any(|param| param.forwarding));
    assert!(delegated.body.declaration_step().is_some());
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_MULTISITE_RUBY") {
        // Render ONLY the complete original patch records. This is not a
        // fabricated main owner or a merged gem/patch file. A diagnostic full-
        // Rails carrier may compare these methods after boot; native rejection
        // below remains mandatory and no load-order claim follows from rendering.
        let mut patch = roundhouse::App::default();
        patch.sources = app.sources.clone();
        patch.library_classes = app
            .library_classes
            .iter()
            .filter(|class| {
                class
                    .methods
                    .iter()
                    .any(|method| method.name_span.file.0 as usize == index + 1)
            })
            .cloned()
            .collect();
        assert_eq!(patch.library_classes.len(), 2, "whole original patch class set changed");
        let rendered = roundhouse::emit::ruby::emit_library(&patch)
            .into_iter()
            .filter(|file| file.path.extension().is_some_and(|extension| extension == "rb"))
            .map(|file| file.content)
            .collect::<Vec<_>>()
            .join("\n");
        std::fs::write(output, rendered).unwrap();
    }
    let (result, diagnostics) =
        roundhouse::emit::diagnostics::scope(|| roundhouse::project::target_files(&app, &input, BuildTarget::Spinel));
    assert!(
        result.is_err(),
        "unproved original app/gem patch feature lifetime became executable"
    );
    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.message.contains("has no single feature identity")),
        "genuine multi-body binding was merged/picked: {diagnostics:#?}"
    );
    assert!(
        diagnostics.iter().any(
            |diagnostic| diagnostic.message.contains("lib/freedom_patches/rails_multisite.rb")
                && diagnostic.message.contains("no ordered file-program identity")
        ),
        "unpositioned original patch source was not identified: {diagnostics:#?}"
    );
    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.message.contains("full argument forwarding")),
        "native carrier guard was bypassed"
    );
    let mut typed = app.clone();
    let diagnostics = roundhouse::session::analyze_and_lower_for(&mut typed, BuildTarget::Spinel);
    let methods: Vec<_> = typed
        .library_classes
        .iter()
        .filter(|class| class.name.0.as_str() == "RailsMultisite::ConnectionManagement")
        .flat_map(|class| &class.methods)
        .filter(|method| ["instance", "current_db", "config_filename="].contains(&method.name.as_str()))
        .collect();
    // The oracle happened to use NullInstance, but the SOURCE also permits
    // the configured main instance. Do not specialize away that live arm.
    let instance = methods
        .iter()
        .find(|method| method.name.as_str() == "instance")
        .unwrap();
    assert!(matches!(&instance.signature, Some(roundhouse::ty::Ty::Fn { ret, .. })
        if matches!(&**ret, roundhouse::ty::Ty::Union { variants }
            if variants.iter().any(|variant| matches!(variant, roundhouse::ty::Ty::SelfInstance))
            && variants.iter().any(|variant| matches!(variant, roundhouse::ty::Ty::Class { id, .. }
                if id.0.as_str() == "RailsMultisite::ConnectionManagement::NullInstance")))));
    let current = methods
        .iter()
        .find(|method| method.name.as_str() == "current_db" && method.receiver == MethodReceiver::Class)
        .unwrap();
    let mut union_receiver = false;
    visit(&current.body, &mut |expr| {
        if let ExprNode::Send {
            recv: Some(recv),
            method,
            ..
        } = &*expr.node
            && method.as_str() == "current_db"
            && let Some(roundhouse::ty::Ty::Union { variants }) = &recv.ty
        {
            union_receiver = variants.iter().any(|variant| {
                matches!(variant, roundhouse::ty::Ty::Class { id, .. }
                if id.0.as_str() == "RailsMultisite::ConnectionManagement")
            }) && variants.iter().any(|variant| {
                matches!(variant, roundhouse::ty::Ty::Class { id, .. }
                    if id.0.as_str() == "RailsMultisite::ConnectionManagement::NullInstance")
            });
        }
    });
    assert!(
        union_receiver,
        "actual two-producer source receiver was frozen to the observed singleton"
    );
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_MULTISITE_TYPED_IR") {
        std::fs::write(output, serde_json::to_vec_pretty(&serde_json::json!({
            "scope": "actual source-derived producer/callee diagnostic ONLY; errors retained; no inferred-ABI admission",
            "methods": methods, "diagnostic_count": diagnostics.len(),
        })).unwrap()).unwrap();
    }
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_MULTISITE_IR") {
        std::fs::write(output, serde_json::to_vec_pretty(&records).unwrap()).unwrap();
    }
}
