//! Resolve a closed file-program graph before native emission. This is resource
//! and binding IR, not an application-source passthrough. Each declaration stays
//! in the feature Ruby originally loads, so the ordinary loader owns circular
//! loads, failure rollback and retry; no dynamic-owner reflection helper is
//! needed. Unknown worlds remain a refusal, never an eager declaration fallback.

use std::collections::{BTreeMap, BTreeSet};

use crate::app::{FileProgram, ProgramItem};
use crate::expr::{Expr, ExprNode, LValue};
use crate::{App, ClassId};

#[derive(Clone, Debug)]
pub(crate) struct Plan {
    pub programs: Vec<Program>,
    pub declarations: BTreeMap<ClassId, usize>,
    pub autoloaded: BTreeSet<ClassId>,
    /// Explicit namespace bindings already established before a target loads.
    /// Its declaration can use a compact header without creating a second
    /// competing namespace definition in a deferred resource.
    pub compact_headers: BTreeSet<ClassId>,
    pub boot: Vec<usize>,
    /// Only these source load-time constant queries have a proved finite
    /// autoload binding and graph-loader implementation. Other queries keep
    /// their existing refusal; this is not a general defined? waiver.
    pub defined_sites: BTreeSet<(u32, u32, u32)>,
    pub namespace_wrappers: BTreeSet<ClassId>,
    namespace_projection: super::namespace_features::Projection,
}

#[derive(Clone, Debug)]
pub(crate) struct Program {
    pub source: String,
    pub literal_policy: super::source_literal_policy::Policy,
    pub anchor: String,
    pub steps: Vec<Step>,
}

#[derive(Clone, Debug)]
pub(crate) enum Step {
    Declared(Vec<ClassId>),
    Statement(Expr),
    Opened(Vec<Vec<(String, bool)>>),
    Require(usize),
    Autoload {
        owner: String,
        name: String,
        resource: usize,
    },
}

fn refuse(message: impl AsRef<str>) -> String {
    format!("finite native file-program profile: {}", message.as_ref())
}

pub(crate) fn normalize(path: &str) -> String {
    let mut out = Vec::new();
    for part in path.split('/') {
        match part {
            "." => {}
            ".." if out.last().is_some_and(|s| *s != "" && *s != "..") => {
                out.pop();
            }
            _ => out.push(part),
        }
    }
    out.join("/")
}

/// Only graphs containing an autoload select this bounded profile. Ordinary
/// non-autoload emission is unchanged. The legacy Ruby-family helper is also
/// unchanged; a native refusal must not turn into that reflective fallback.
pub(crate) fn lower(app: &App) -> Result<Option<Plan>, String> {
    fn has_autoload(items: &[ProgramItem]) -> bool {
        items.iter().any(|item| match item {
            ProgramItem::Autoload { .. } => true,
            ProgramItem::Branch {
                then_items, else_items, ..
            } => has_autoload(then_items) || has_autoload(else_items),
            _ => false,
        })
    }
    if !app.file_programs.iter().any(|p| has_autoload(&p.items)) && !app.source_gem_ruby_family_inventory {
        return Ok(None);
    }
    let mut selected_require_sites = BTreeSet::new();
    fn select(items: &[ProgramItem], sites: &mut BTreeSet<(u32, u32, u32)>, in_branch: bool) -> Result<Vec<ProgramItem>, String> {
        let mut selected = Vec::new();
        for item in items {
            if let ProgramItem::Branch { condition, negated, then_items, else_items } = item {
                let value = crate::ingest::source_gems::ruby_family_truth(condition)
                    .ok_or_else(|| refuse("file-program branch does not agree on the validated Ruby/Spinel engines"))?;
                selected.extend(select(if value != *negated { then_items } else { else_items }, sites, true)?);
            } else {
                if in_branch && let ProgramItem::Require { span, .. } = item { sites.insert((span.file.0, span.start, span.end)); }
                selected.push(item.clone());
            }
        }
        Ok(selected)
    }
    let mut source_programs = app.file_programs.clone();
    if app.source_gem_ruby_family_inventory {
        for program in &mut source_programs { program.items = select(&program.items, &mut selected_require_sites, false)?; }
    }
    let namespace_projection = super::namespace_features::project(app, &mut source_programs);
    super::namespace_features::validate(app, &namespace_projection).map_err(refuse)?;
    let root = app.root.trim_end_matches('/');
    let relative = |path: &str| {
        path.strip_prefix(root)
            .unwrap_or(path)
            .trim_start_matches('/')
            .to_string()
    };
    let mut programs: Vec<Program> = source_programs
        .iter()
        .map(|p| {
            let source = normalize(&p.source);
            let rel = relative(&source);
            Program {
                source,
                literal_policy: super::source_literal_policy::Policy::Unspecified,
                anchor: format!("models/roundhouse_files/{}", rel.strip_suffix(".rb").unwrap_or(&rel)),
                steps: Vec::new(),
            }
        })
        .collect();
    let indices: BTreeMap<_, _> = programs
        .iter()
        .enumerate()
        .map(|(i, p)| (p.source.clone(), i))
        .collect();
    if indices.len() != programs.len() {
        return Err(refuse("duplicate canonical resource identities"));
    }
    let mut declarations = BTreeMap::new();
    for (i, program) in source_programs.iter().enumerate() {
        for item in &program.items {
            if let ProgramItem::Declared(names) = item {
                for name in names {
                    if declarations.insert(name.clone(), i).is_some() {
                        return Err(refuse(format!(
                            "reopened/merged declaration {} has no single feature identity",
                            name.0
                        )));
                    }
                }
            }
        }
    }
    let mut literal_constants = BTreeMap::new();
    let mut constant_sites = BTreeSet::new();
    for (i, program) in source_programs.iter().enumerate() {
        for item in &program.items {
            if let ProgramItem::Statement(expr) = item
                && let Some(name) = crate::lower::literal_constant_features::binding(app, &program.source, expr)
            {
                if declarations.contains_key(&name) || literal_constants.insert(name, i).is_some() {
                    return Err(refuse("duplicate literal constant feature binding"));
                }
                constant_sites.insert((expr.span.file.0, expr.span.start, expr.span.end));
            }
        }
    }
    let resolve = |from: &str, feature: &str, relative: bool| -> Result<usize, String> {
        let file = if feature.ends_with(".rb") {
            feature.to_string()
        } else {
            format!("{feature}.rb")
        };
        if relative {
            let dir = from.rsplit_once('/').map(|(dir, _)| dir).unwrap_or("");
            let path = normalize(&format!("{dir}/{file}"));
            return indices
                .get(&path)
                .copied()
                .ok_or_else(|| refuse(format!("missing/unknown resource {feature:?} from {from}")));
        }
        let own = from
            .rfind("/lib/")
            .map(|at| normalize(&format!("{}{file}", &from[..at + 5])));
        let suffix = format!("/lib/{file}");
        let found: Vec<_> = indices
            .iter()
            .filter(|(path, _)| path.ends_with(&suffix))
            .map(|(_, i)| *i)
            .collect();
        // Own-lib preference is not proof against a feature shadowed on
        // another load path. A finite native profile refuses ambiguity.
        if found.len() <= 1 {
            if let Some(i) = own.as_ref().and_then(|p| indices.get(p)) {
                return Ok(*i);
            }
        }
        match found.as_slice() {
            [i] => Ok(*i),
            [] => Err(refuse(format!("missing/unknown resource {feature:?} from {from}"))),
            _ => Err(refuse(format!("ambiguous resource {feature:?} from {from}"))),
        }
    };
    let mut autoloaded = BTreeSet::new();
    let mut bindings = BTreeMap::new();
    let mut owners = BTreeSet::new();
    let mut registration_sites = BTreeSet::new();
    for (i, original) in source_programs.iter().enumerate() {
        let mut opened_at = BTreeMap::new();
        let mut last_declaration = None;
        let from = &programs[i].source;
        let mut steps = Vec::new();
        for (position, item) in original.items.iter().enumerate() {
            steps.push(match item {
                ProgramItem::Declared(names) => {
                    last_declaration = Some(position);
                    Step::Declared(names.clone())
                }
                ProgramItem::Opened(chains) => {
                    for chain in chains {
                        opened_at.insert(
                            chain
                                .iter()
                                .map(|(name, _)| name.as_str())
                                .collect::<Vec<_>>()
                                .join("::"),
                            position,
                        );
                    }
                    Step::Opened(chains.clone())
                }
                ProgramItem::Statement(expr) => Step::Statement(expr.clone()),
                ProgramItem::Require {
                    feature,
                    relative,
                    span,
                } => {
                    if !root_require(app, original, *span) && !selected_require_sites.contains(&(span.file.0, span.start, span.end)) {
                        return Err(refuse("a body require has no proved source-ordered declaration split"));
                    }
                    Step::Require(resolve(from, feature, *relative)?)
                }
                ProgramItem::Autoload {
                    owner,
                    name,
                    feature,
                    span,
                } => {
                    registration_sites.insert((span.file.0, span.start, span.end));
                    if owner != "Object" {
                        let Some(opened) = opened_at.get(owner) else {
                            return Err(refuse("autoload has no proved leading module opening"));
                        };
                        if last_declaration.is_some_and(|declared| declared > *opened) {
                            return Err(refuse(
                                "non-leading body autoload requires a source-ordered declaration split",
                            ));
                        }
                        let id = ClassId(crate::Symbol::from(owner.as_str()));
                        let classes: Vec<_> = app.library_classes.iter().filter(|c| c.name == id).collect();
                        if classes.is_empty() || classes.iter().any(|c| c.parent.is_some() || !c.includes.is_empty()) {
                            return Err(refuse(format!("unknown/inherited autoload owner {owner}")));
                        }
                    }
                    let resource = resolve(from, feature, false)?;
                    let id = ClassId(crate::Symbol::from(if owner == "Object" {
                        name.clone()
                    } else {
                        format!("{owner}::{name}")
                    }));
                    if declarations.get(&id).or_else(|| literal_constants.get(&id)) != Some(&resource) {
                        return Err(refuse(format!("resource does not independently declare {id:?}")));
                    }
                    if bindings.insert(id.clone(), resource).is_some_and(|old| old != resource) {
                        return Err(refuse(format!("autoload binding {} changes resource", id.0)));
                    }
                    owners.insert(owner.clone());
                    autoloaded.insert(id);
                    Step::Autoload {
                        owner: owner.clone(),
                        name: name.clone(),
                        resource,
                    }
                }
                ProgramItem::Branch { .. } => {
                    return Err(refuse(
                        "conditional file-program declarations/resources are not yet proved",
                    ));
                }
                ProgramItem::NotCarried { message, .. } => return Err(refuse(message)),
            });
        }
        let mut literal_policy = super::source_literal_policy::Policy::Unspecified;
        for step in &steps {
            let policy = match step {
                Step::Declared(names) => super::source_literal_policy::declarations(app,
                    app.library_classes.iter().filter(|class| names.contains(&class.name))),
                Step::Statement(expr) => super::source_literal_policy::expression(app, expr),
                _ => super::source_literal_policy::Policy::Unspecified,
            };
            literal_policy = literal_policy.join(policy);
        }
        if literal_policy == super::source_literal_policy::Policy::Mixed {
            return Err(refuse("mixed source literal allocation in one feature has no proved common directive"));
        }
        programs[i].literal_policy = literal_policy;
        programs[i].steps = steps;
    }
    // No mutation/override of the finite owner/resource world may hide in an
    // ordinary method or initializer. This deliberately errs on refusal.
    let namespace_owners = owners.clone();
    owners.extend(namespace_projection.protected.iter().cloned());
    if autoloaded.iter().any(|name| namespace_projection.protected.contains(name.0.as_str())) {
        return Err(refuse("an autoload namespace has no proved multi-feature lifetime"));
    }
    owners.extend(autoloaded.iter().map(|name| name.0.as_str().to_string()));
    if app.source_gem_ruby_family_inventory { owners.insert("RUBY_ENGINE".to_string()); }
    let positioned_macros = app
        .library_classes
        .iter()
        .flat_map(|class| &class.class_ivar_initializers)
        .filter(|expr| {
            matches!(&*expr.node, ExprNode::If { cond, else_branch, .. }
            if matches!(&*cond.node, ExprNode::Send { method, .. } if method.as_str() == "class_variable_defined?")
            && matches!(&*else_branch.node, ExprNode::Send { method, .. } if method.as_str() == "class_variable_set"))
        })
        .filter_map(|expr| {
            expr.declaration_step()
                .map(|step| (step.call.file.0, step.call.start, step.call.end))
        })
        .collect();
    reject_binding_writes(app, &owners, &positioned_macros, &constant_sites)?;
    let mut defined_sites = BTreeSet::new();
    for class in &app.library_classes {
        if matches!(
            class.name.0.as_str(),
            "Module" | "Class" | "Kernel" | "Object" | "BasicObject" | "String" | "TrueClass" | "FalseClass" | "NilClass" | "File" | "Dir"
        ) {
            return Err(refuse("a core owner is reopened by application source"));
        }
        for method in &class.methods {
            if forbidden_method(method.name.as_str())
                || matches!(
                    method.name.as_str(),
                    "method_added" | "singleton_method_added" | "const_added" | "inherited" | "extended" | "included"
                )
            {
                return Err(refuse(format!(
                    "overridden owner/resource/observer protocol {}.{}",
                    class.name.0, method.name
                )));
            }
            check_expr(&method.body, &owners)?;
            for param in &method.params {
                if let Some(default) = &param.default {
                    check_expr(default, &owners)?;
                }
            }
        }
        for (name, value) in &class.constants {
            if app.source_gem_ruby_family_inventory && name.as_str() == "RUBY_ENGINE" {
                return Err(refuse("validated engine binding changed after source inventory selection"));
            }
            let full = format!("{}::{name}", class.name.0);
            if owners
                .iter()
                .any(|owner| owner == &full || owner.starts_with(&format!("{full}::")))
            {
                return Err(refuse(format!("autoload owner {full} is reassigned")));
            }
            check_expr(value, &owners)?;
            collect_defined(value, class.name.0.as_str(), &autoloaded, &mut defined_sites);
        }
        for expr in class.class_ivar_initializers.iter().chain(&class.unknown_calls) {
            // Literal registrations are carried by ProgramItem, not replayed
            // as a dynamic Module protocol call in the declaration body.
            if registration_sites.contains(&(expr.span.file.0, expr.span.start, expr.span.end))
                && matches!(&*expr.node, ExprNode::Send { method, recv: None, .. } if method.as_str() == "autoload")
            {
                continue;
            }
            check_expr(expr, &owners)?;
            if class.unknown_calls.iter().any(|call| std::ptr::eq(call, expr))
                && expr.decisions & (crate::expr::BODY_STATEMENT | crate::expr::REPLAYED_CLASS_BODY) == 0
            {
                return Err(refuse("an unmodelled declaration-body effect would be dropped"));
            }
            collect_defined(expr, class.name.0.as_str(), &autoloaded, &mut defined_sites);
        }
    }
    let mut world_failure = None;
    crate::lower::for_each_emit_body_ref(app, &mut |expr| {
        if world_failure.is_none()
            && !registration_sites.contains(&(expr.span.file.0, expr.span.start, expr.span.end))
            && !constant_sites.contains(&(expr.span.file.0, expr.span.start, expr.span.end))
        {
            world_failure = check_expr(expr, &owners).err();

        }
    });
    if let Some(error) = world_failure {
        return Err(error);
    }
    for program in &programs {
        for step in &program.steps {
            if let Step::Statement(expr) = step {
                if constant_sites.contains(&(expr.span.file.0, expr.span.start, expr.span.end)) {
                    if let ExprNode::Assign { value, .. } = &*expr.node {
                        check_expr(value, &owners)?;
                    }
                } else {
                    check_expr(expr, &owners)?;
                }
            }
        }
    }
    let boot = app
        .boot_gem_entries
        .iter()
        .map(|entry| {
            indices
                .get(&normalize(entry))
                .copied()
                .ok_or_else(|| refuse(format!("unknown boot resource {entry}")))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if boot.is_empty() {
        return Err(refuse("no explicit boot feature roots"));
    }
    let compact_headers: BTreeSet<_> = autoloaded
        .iter()
        .filter(|name| name.0.as_str().contains("::") && declarations.contains_key(*name))
        .cloned()
        .collect();
    for name in &compact_headers {
        let resource = declarations[name];
        if declarations
            .iter()
            .any(|(other, source)| *source == resource && other != name)
        {
            return Err(refuse("an autoload resource has nested/multiple declaration contexts"));
        }
        if app
            .library_classes
            .iter()
            .filter(|class| &class.name == name)
            .any(|class| class.parent.is_some() || !class.includes.is_empty())
        {
            return Err(refuse(
                "a compact autoload declaration has unproved inherited/mixin lexical lookup",
            ));
        }
    }
    prove_namespace_dominance(&programs, &declarations, &namespace_owners, &compact_headers, &boot)?;
    let class_bindings = autoloaded
        .iter()
        .filter(|name| declarations.contains_key(*name))
        .cloned()
        .collect();
    prove_retry_class_state(app, &programs, &declarations, &class_bindings)?;
    Ok(Some(Plan {
        programs,
        declarations,
        autoloaded,
        compact_headers,
        boot,
        defined_sites,
        namespace_wrappers: namespace_projection.wrappers.clone(),
        namespace_projection,
    }))
}

fn collect_defined(expr: &Expr, owner: &str, bindings: &BTreeSet<ClassId>, sites: &mut BTreeSet<(u32, u32, u32)>) {
    if let ExprNode::Defined { operand } = &*expr.node {
        if let ExprNode::Const { path } = &*operand.node {
            let name = path.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("::");
            let name = name.trim_start_matches("::");
            if bindings
                .iter()
                .any(|binding| binding.0.as_str() == name || binding.0.as_str() == format!("{owner}::{name}"))
            {
                sites.insert((expr.span.file.0, expr.span.start, expr.span.end));
            }
        }
    }
    expr.node
        .for_each_child(&mut |child| collect_defined(child, owner, bindings, sites));
}

fn forbidden_method(name: &str) -> bool {
    matches!(
        name,
        "autoload"
            | "autoload?"
            | "require"
            | "require_relative"
            | "load"
            | "constants"
            | "const_defined?"
            | "const_get"
            | "const_set"
            | "remove_const"
            | "eval"
            | "binding"
            | "class_eval"
            | "module_eval"
            | "class_exec"
            | "module_exec"
            | "instance_eval"
            | "instance_exec"
            | "define_method"
            | "define_singleton_method"
            | "remove_method"
            | "undef_method"
            | "const_missing"
            | "nesting"
            | "private_constant"
            | "public_constant"
            | "send"
            | "public_send"
            | "__send__"
            | "method_missing"
            | "respond_to_missing?"
            | "alias_method"
            | "singleton_class"
            | "instance_method"
            | "public_instance_method"
            | "instance_methods"
            | "public_instance_methods"
            | "private_instance_methods"
            | "protected_instance_methods"
            | "method_defined?"
            | "public_method_defined?"
            | "private_method_defined?"
            | "protected_method_defined?"
            | "ancestors"
            | "included_modules"
            | "prepend"
            | "set_trace_func"
            | "system"
            | "exec"
            | "spawn"
            | "fork"
    )
}

fn check_expr(expr: &Expr, owners: &BTreeSet<String>) -> Result<(), String> {
    if matches!(&*expr.node, ExprNode::Const { path } if path.iter().any(|part| matches!(part.as_str(), "TracePoint" | "ObjectSpace" | "Binding" | "RubyVM" | "Thread" | "Fiber")))
    {
        return Err(refuse("an external/concurrent reflective world is not proved"));
    }
    if matches!(&*expr.node, ExprNode::Var { name, .. } if matches!(name.as_str(), "$LOAD_PATH" | "$LOADED_FEATURES" | "$:" | "$\""))
    {
        return Err(refuse("dynamic resource search/cache access"));
    }
    if let ExprNode::Send { method, .. } = &*expr.node {
        if forbidden_method(method.as_str()) {
            return Err(refuse(format!("unknown/dynamic owner/resource operation `{method}`")));
        }
        if matches!(
            method.as_str(),
            "write"
                | "binwrite"
                | "delete"
                | "unlink"
                | "rename"
                | "symlink"
                | "open"
                | "popen"
                | "truncate"
                | "copy_stream"
                | "chdir"
                | "each_object"
        ) {
            return Err(refuse(format!("resource mutation `{method}`")));
        }
    }
    if let ExprNode::Assign {
        target: LValue::Const { path },
        ..
    }
    | ExprNode::OpAssign {
        target: LValue::Const { path },
        ..
    } = &*expr.node
    {
        let full = path.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("::");
        if owners.contains("RUBY_ENGINE") && path.last().is_some_and(|name| name.as_str() == "RUBY_ENGINE") {
            return Err(refuse("validated engine binding changed after source inventory selection"));
        }
        if owners
            .iter()
            .any(|owner| owner == &full || owner.starts_with(&format!("{full}::")))
        {
            return Err(refuse(format!("autoload owner {full} is reassigned")));
        }
    }
    let mut failure = None;
    expr.node.for_each_child(&mut |child| {
        if failure.is_none() {
            failure = check_expr(child, owners).err();
        }
    });
    failure.map_or(Ok(()), Err)
}

/// A source require is carried only at the file's own top level. In particular
/// do not bless body_requires' legacy after-declaration approximation.
fn root_require(app: &App, program: &FileProgram, span: crate::span::Span) -> bool {
    use crate::ingest::prism_api::PrismLocation;
    let Some(source) = app
        .sources
        .iter()
        .find(|s| normalize(&s.path) == normalize(&program.source))
    else {
        return false;
    };
    let parsed = ruby_prism::parse(source.text.as_bytes());
    let root = parsed.node();
    root.as_program_node().is_some_and(|p| {
        p.statements()
            .body()
            .iter()
            .any(|stmt| stmt.location().start_offset() == span.start as usize && stmt.as_call_node().is_some())
    })
}

fn prove_namespace_dominance(
    programs: &[Program],
    declarations: &BTreeMap<ClassId, usize>,
    owners: &BTreeSet<String>,
    compact: &BTreeSet<ClassId>,
    boot: &[usize],
) -> Result<(), String> {
    fn run(
        resource: usize,
        programs: &[Program],
        declarations: &BTreeMap<ClassId, usize>,
        owners: &BTreeSet<String>,
        compact: &BTreeSet<ClassId>,
        available: &mut BTreeSet<String>,
        loaded: &mut BTreeSet<usize>,
        loading: &mut BTreeSet<usize>,
    ) -> Result<(), String> {
        if loaded.contains(&resource) || loading.contains(&resource) {
            return Ok(());
        }
        for name in compact.iter().filter(|name| declarations[*name] == resource) {
            let parent = name.0.as_str().rsplit_once("::").unwrap().0;
            if !available.contains(parent) {
                return Err(refuse(format!(
                    "unknown/missing owner {parent} before resource {}",
                    programs[resource].source
                )));
            }
        }
        loading.insert(resource);
        for step in &programs[resource].steps {
            match step {
                Step::Opened(chains) => {
                    for chain in chains {
                        let mut prefix = Vec::new();
                        for (name, _) in chain {
                            prefix.push(name.as_str());
                            available.insert(prefix.join("::"));
                        }
                    }
                }
                Step::Declared(names) => {
                    for name in names {
                        if owners.contains(name.0.as_str()) {
                            available.insert(name.0.as_str().to_string());
                        }
                    }
                }
                Step::Require(target) => run(
                    *target,
                    programs,
                    declarations,
                    owners,
                    compact,
                    available,
                    loaded,
                    loading,
                )?,
                Step::Autoload {
                    owner,
                    resource: target,
                    ..
                } => {
                    if owner != "Object" && !available.contains(owner) {
                        return Err(refuse(format!("unknown/missing owner {owner} before registration")));
                    }
                    // Validate every possible lazy entry using only identities
                    // already established at registration, without executing it
                    // or importing its effects into the caller's state.
                    run(
                        *target,
                        programs,
                        declarations,
                        owners,
                        compact,
                        &mut available.clone(),
                        &mut loaded.clone(),
                        &mut loading.clone(),
                    )?;
                }
                Step::Statement(_) => {}
            }
        }
        loading.remove(&resource);
        loaded.insert(resource);
        Ok(())
    }
    let mut available = BTreeSet::from(["Object".to_string()]);
    let mut loaded = BTreeSet::new();
    let mut loading = BTreeSet::new();
    for resource in boot {
        run(
            *resource,
            programs,
            declarations,
            owners,
            compact,
            &mut available,
            &mut loaded,
            &mut loading,
        )?;
    }
    Ok(())
}

impl Plan {
    /// Compact headers name the SAME already-bound namespace object. Preserve
    /// the original nested lexical constant lookup in shared expression IR,
    /// rather than relying on the changed syntactic Module.nesting. Reflection,
    /// eval, private constants and inherited/mixin lookup remain refused.
    pub fn prepare(&self, original: &App) -> App {
        let mut app = original.clone();
        self.namespace_projection.prepare(&mut app);
        let known: BTreeSet<String> = app
            .library_classes
            .iter()
            .map(|class| class.name.0.as_str().to_string())
            .chain(self.autoloaded.iter().map(|name| name.0.as_str().to_string()))
            .chain(app.file_programs.iter().flat_map(|program| {
                program.items.iter().filter_map(|item| {
                    if let ProgramItem::Statement(expr) = item {
                        crate::lower::literal_constant_features::binding(&app, &program.source, expr)
                            .map(|name| name.0.as_str().to_string())
                    } else {
                        None
                    }
                })
            }))
            .chain(app.library_classes.iter().flat_map(|class| {
                class
                    .constants
                    .iter()
                    .map(move |(name, _)| format!("{}::{name}", class.name.0))
            }))
            .collect();
        fn qualify(expr: &mut Expr, owner: &str, known: &BTreeSet<String>) {
            if let ExprNode::Const { path } = &mut *expr.node {
                if !path.first().is_some_and(|part| part.as_str().is_empty()) {
                    let name = path.iter().map(|part| part.as_str()).collect::<Vec<_>>().join("::");
                    let mut scope = Some(owner);
                    let mut resolved = None;
                    while let Some(prefix) = scope {
                        let candidate = format!("{prefix}::{name}");
                        if known.contains(&candidate) {
                            resolved = Some(candidate);
                            break;
                        }
                        scope = prefix.rsplit_once("::").map(|(parent, _)| parent);
                    }
                    if resolved.is_none() && known.contains(&name) {
                        resolved = Some(name);
                    }
                    if let Some(name) = resolved {
                        *path = std::iter::once(crate::Symbol::from(""))
                            .chain(name.split("::").map(crate::Symbol::from))
                            .collect();
                    }
                }
            }
            expr.node.for_each_child_mut(&mut |child| qualify(child, owner, known));
        }
        for class in &mut app.library_classes {
            if !self.compact_headers.contains(&class.name) {
                continue;
            }
            let owner = class.name.0.as_str();
            for method in &mut class.methods {
                qualify(&mut method.body, owner, &known);
                for param in &mut method.params {
                    if let Some(default) = &mut param.default {
                        qualify(default, owner, &known);
                    }
                }
            }
            for (_, value) in &mut class.constants {
                qualify(value, owner, &known);
            }
            for expr in class.class_ivar_initializers.iter_mut().chain(&mut class.unknown_calls) {
                qualify(expr, owner, &known);
            }
        }
        app
    }
}

/// Constant writes can be omitted from FileProgram because they ride with
/// declarations. Inspect their source nodes too, including conditional/multi
/// targets, so that representation cannot hide a changed owner identity.
fn reject_binding_writes(
    app: &App,
    protected: &BTreeSet<String>,
    positioned: &BTreeSet<(u32, u32, u32)>,
    constant_sites: &BTreeSet<(u32, u32, u32)>,
) -> Result<(), String> {
    use crate::ingest::prism_api::PrismLocation;
    struct Writes<'a> {
        protected: &'a BTreeSet<String>,
        positioned: &'a BTreeSet<(u32, u32, u32)>,
        constant_sites: &'a BTreeSet<(u32, u32, u32)>,
        file: u32,
        changed: Option<String>,
    }
    impl Writes<'_> {
        fn check(&mut self, name: Option<ruby_prism::ConstantId<'_>>) {
            let Some(name) = name else { return };
            let name = String::from_utf8_lossy(name.as_slice());
            if self
                .protected
                .iter()
                .any(|full| full.rsplit("::").next() == Some(name.as_ref()))
            {
                self.changed = Some(name.into_owned());
            }
        }
    }
    impl<'pr> ruby_prism::Visit<'pr> for Writes<'_> {
        fn visit_call_node(&mut self, n: &ruby_prism::CallNode<'pr>) {
            if matches!(
                n.name().as_slice(),
                b"mattr_reader"
                    | b"mattr_writer"
                    | b"mattr_accessor"
                    | b"cattr_reader"
                    | b"cattr_writer"
                    | b"cattr_accessor"
            ) && !self.positioned.contains(&(
                self.file,
                n.location().start_offset() as u32,
                n.location().end_offset() as u32,
            )) {
                self.changed = Some("unpositioned mattr/cattr protocol and definition events".into());
            }
            ruby_prism::visit_call_node(self, n);
        }
        fn visit_constant_write_node(&mut self, n: &ruby_prism::ConstantWriteNode<'pr>) {
            if !self.constant_sites.contains(&(
                self.file,
                n.location().start_offset() as u32,
                n.location().end_offset() as u32,
            )) {
                self.check(Some(n.name()));
            }
            ruby_prism::visit_constant_write_node(self, n);
        }
        fn visit_constant_and_write_node(&mut self, n: &ruby_prism::ConstantAndWriteNode<'pr>) {
            self.check(Some(n.name()));
            ruby_prism::visit_constant_and_write_node(self, n);
        }
        fn visit_constant_or_write_node(&mut self, n: &ruby_prism::ConstantOrWriteNode<'pr>) {
            self.check(Some(n.name()));
            ruby_prism::visit_constant_or_write_node(self, n);
        }
        fn visit_constant_operator_write_node(&mut self, n: &ruby_prism::ConstantOperatorWriteNode<'pr>) {
            self.check(Some(n.name()));
            ruby_prism::visit_constant_operator_write_node(self, n);
        }
        fn visit_constant_path_write_node(&mut self, n: &ruby_prism::ConstantPathWriteNode<'pr>) {
            self.check(n.target().name());
            ruby_prism::visit_constant_path_write_node(self, n);
        }
        fn visit_constant_path_and_write_node(&mut self, n: &ruby_prism::ConstantPathAndWriteNode<'pr>) {
            self.check(n.target().name());
            ruby_prism::visit_constant_path_and_write_node(self, n);
        }
        fn visit_constant_path_or_write_node(&mut self, n: &ruby_prism::ConstantPathOrWriteNode<'pr>) {
            self.check(n.target().name());
            ruby_prism::visit_constant_path_or_write_node(self, n);
        }
        fn visit_constant_path_operator_write_node(&mut self, n: &ruby_prism::ConstantPathOperatorWriteNode<'pr>) {
            self.check(n.target().name());
            ruby_prism::visit_constant_path_operator_write_node(self, n);
        }
        fn visit_constant_target_node(&mut self, n: &ruby_prism::ConstantTargetNode<'pr>) {
            self.check(Some(n.name()));
            ruby_prism::visit_constant_target_node(self, n);
        }
    }
    for (index, source) in app.sources.iter().enumerate().filter(|(_, s)| s.path.ends_with(".rb")) {
        let parsed = ruby_prism::parse(source.text.as_bytes());
        let mut writes = Writes {
            protected,
            positioned,
            constant_sites,
            file: index as u32 + 1,
            changed: None,
        };
        ruby_prism::Visit::visit(&mut writes, &parsed.node());
        if let Some(name) = writes.changed {
            return Err(refuse(format!(
                "owner/binding {name} is reassigned by source {}",
                source.path
            )));
        }
    }
    Ok(())
}

/// Class identity/state from an unsuccessful autoload must not escape. Native
/// static class metadata is not a general repeated-Class-allocation model.
/// Keep this first finite profile to stateless target declarations and refuse
/// possible escapes when a feature can still fail after publishing its header.
fn prove_retry_class_state(
    app: &App,
    programs: &[Program],
    declarations: &BTreeMap<ClassId, usize>,
    compact: &BTreeSet<ClassId>,
) -> Result<(), String> {
    fn literal(expr: &Expr) -> bool {
        match &*expr.node {
            ExprNode::Lit { .. } => true,
            ExprNode::Array { elements, .. } => elements.iter().all(literal),
            ExprNode::Hash { entries, .. } => entries.iter().all(|(key, value)| literal(key) && literal(value)),
            _ => false,
        }
    }
    let mut fallible = BTreeSet::new();
    for name in compact {
        let program = &programs[declarations[name]];
        let mut declared = false;
        for step in &program.steps {
            if let Step::Declared(names) = step {
                declared |= names.contains(name);
            } else if declared {
                fallible.insert(name.0.as_str().rsplit("::").next().unwrap().to_string());
            }
        }
        for class in app.library_classes.iter().filter(|class| &class.name == name) {
            if class.parent.is_some()
                || !class.includes.is_empty()
                || !class.class_ivar_initializers.is_empty()
                || !class.unknown_calls.is_empty()
                || !class.constants.iter().all(|(_, value)| literal(value))
            {
                return Err(refuse(
                    "autoload target class state/effects require a fresh-allocation and retry proof",
                ));
            }
            fn cvar(expr: &Expr) -> bool {
                let mut found = matches!(&*expr.node, ExprNode::Var { name, .. }
                    | ExprNode::Assign { target: LValue::Var { name, .. }, .. }
                    | ExprNode::OpAssign { target: LValue::Var { name, .. }, .. } if name.as_str().starts_with("@@"));
                expr.node.for_each_child(&mut |child| found |= cvar(child));
                found
            }
            if class.methods.iter().any(|method| cvar(&method.body)) {
                return Err(refuse("compact target class-variable lexical lookup is not yet proved"));
            }
        }
    }
    fn escape(expr: &Expr, leaves: &BTreeSet<String>, class_self: bool) -> bool {
        // defined? does not expose the value it queries.
        if matches!(&*expr.node, ExprNode::Defined { operand } if matches!(&*operand.node, ExprNode::Const { .. })) {
            return false;
        }
        let mut found = match &*expr.node {
            ExprNode::Const { path } => path.last().is_some_and(|name| leaves.contains(name.as_str())),
            ExprNode::SelfRef => class_self,
            ExprNode::Send { recv: None, .. } => class_self,
            _ => false,
        };
        expr.node
            .for_each_child(&mut |child| found |= escape(child, leaves, class_self));
        found
    }
    if !fallible.is_empty() {
        for class in &app.library_classes {
            let is_target =
                compact.contains(&class.name) && fallible.contains(class.name.0.as_str().rsplit("::").next().unwrap());
            for method in &class.methods {
                let class_self = is_target && method.receiver == crate::dialect::MethodReceiver::Class;
                if escape(&method.body, &fallible, class_self)
                    || method.params.iter().any(|param| {
                        param
                            .default
                            .as_ref()
                            .is_some_and(|value| escape(value, &fallible, class_self))
                    })
                {
                    return Err(refuse("a failed autoload Class/Module value may escape before retry"));
                }
            }
            for (_, value) in &class.constants {
                if escape(value, &fallible, is_target) {
                    return Err(refuse("a failed autoload Class/Module value may escape before retry"));
                }
            }
            for expr in class.class_ivar_initializers.iter().chain(&class.unknown_calls) {
                if escape(expr, &fallible, is_target) {
                    return Err(refuse("a failed autoload Class/Module value may escape before retry"));
                }
            }
        }
        for program in programs {
            for step in &program.steps {
                if let Step::Statement(expr) = step {
                    if escape(expr, &fallible, false) {
                        return Err(refuse("a failed autoload Class/Module value may escape before retry"));
                    }
                }
            }
        }
    }
    Ok(())
}
