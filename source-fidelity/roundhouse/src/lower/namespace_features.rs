//! A source feature may open an otherwise empty class only to declare its
//! children, before another feature supplies that class's body. This is a
//! namespace binding, not a second callable owner and not a reopen merge.
//! Retain the opening in ordered resource IR; keep every child in its feature.

use std::collections::{BTreeMap, BTreeSet};

use crate::app::{FileProgram, ProgramItem};
use crate::dialect::LibraryClass;
use crate::{App, ClassId, Symbol};

#[derive(Clone, Debug, Default)]
pub(super) struct Projection {
    pub wrappers: BTreeSet<ClassId>,
    pub protected: BTreeSet<String>,
    removed: BTreeMap<String, BTreeSet<ClassId>>,
    unpositioned: BTreeMap<ClassId, Vec<String>>,
}

pub(super) fn empty(class: &LibraryClass) -> bool {
    class.origin.is_none()
        && class.parent.is_none()
        && class.parent_span.is_synthetic()
        && class.includes.is_empty()
        && class.include_spans.is_empty()
        && class.methods.is_empty()
        && class.class_ivar_initializers.is_empty()
        && class.nullable_columns.is_empty()
        && class.constants.is_empty()
        && class.conditional_definitions.is_empty()
        && class.unknown_calls.is_empty()
}

// Only simple, directly nested headers with no intervening executable body.
// A superclass, compact header, statement, callback, conditional or reopening
// with real members is not interchangeable with a namespace opening.
fn wrappers(source: &str) -> BTreeMap<ClassId, Vec<Vec<(String, bool)>>> {
    fn walk(
        node: &ruby_prism::Node<'_>,
        outer: &[(String, bool)],
        out: &mut BTreeMap<ClassId, Vec<Vec<(String, bool)>>>,
    ) {
        let (path, class, body) = if let Some(n) = node.as_class_node() {
            if n.superclass().is_some() {
                return;
            }
            (n.constant_path(), true, n.body())
        } else if let Some(n) = node.as_module_node() {
            (n.constant_path(), false, n.body())
        } else {
            return;
        };
        let Some(path) = path.as_constant_read_node() else {
            return;
        };
        let Some(body) = body.and_then(|body| body.as_statements_node()) else {
            return;
        };
        let statements: Vec<_> = body.body().iter().collect();
        if statements.is_empty()
            || statements
                .iter()
                .any(|n| n.as_class_node().is_none() && n.as_module_node().is_none())
        {
            return;
        }
        let mut chain = outer.to_vec();
        chain.push((String::from_utf8_lossy(path.name().as_slice()).into_owned(), class));
        let name = ClassId(Symbol::from(
            chain
                .iter()
                .map(|(name, _)| name.as_str())
                .collect::<Vec<_>>()
                .join("::"),
        ));
        out.entry(name).or_default().push(chain.clone());
        for child in &statements {
            walk(child, &chain, out);
        }
    }
    let parsed = ruby_prism::parse(source.as_bytes());
    let mut out = BTreeMap::new();
    if parsed.errors().next().is_none()
        && let Some(program) = parsed.node().as_program_node()
    {
        for statement in program.statements().body().iter() {
            walk(&statement, &[], &mut out);
        }
    }
    out
}

pub(super) fn project(app: &App, programs: &mut [FileProgram]) -> Projection {
    let proofs: Vec<_> = programs
        .iter()
        .map(|program| {
            app.sources
                .iter()
                .find(|source| source.path == program.source)
                .map(|source| wrappers(&source.text))
                .unwrap_or_default()
        })
        .collect();
    let mut occurrences: BTreeMap<ClassId, Vec<usize>> = BTreeMap::new();
    for (index, program) in programs.iter().enumerate() {
        for item in &program.items {
            if let ProgramItem::Declared(names) = item {
                for name in names {
                    occurrences.entry(name.clone()).or_default().push(index);
                }
            }
        }
    }
    let mut projection = Projection::default();
    for (name, sites) in occurrences {
        if sites.len() < 2 {
            continue;
        }
        let candidates: Vec<_> = sites
            .iter()
            .filter(|&&site| proofs[site].get(&name).is_some_and(|chains| chains.len() == 1))
            .copied()
            .collect();
        if candidates.len() + 1 != sites.len() {
            continue;
        }
        let records: Vec<_> = app.library_classes.iter().filter(|class| class.name == name).collect();
        if records.len() != sites.len() {
            // A member supplied outside this ordered source-feature world is
            // not another empty wrapper. Retain the refusal and identify the
            // actual missing declaration source; never select the first body
            // or fold an app/lib patch into the gem's earlier declaration.
            let missing: Vec<_> = app
                .library_class_files
                .iter()
                .filter(|(source, names)| {
                    names.contains(&name) && !programs.iter().any(|program| program.source == **source)
                })
                .map(|(source, _)| source.clone())
                .collect();
            if !missing.is_empty() {
                projection.unpositioned.insert(name, missing);
            }
            continue;
        }
        if records.iter().filter(|class| empty(class)).count() != candidates.len() {
            continue;
        }
        let Some(owner) = records.iter().find(|class| !empty(class)) else {
            continue;
        };
        if owner.parent.is_some()
            || !owner.includes.is_empty()
            || candidates
                .iter()
                .any(|&site| proofs[site][&name][0].last().unwrap().1 == owner.is_module)
        {
            continue;
        }
        projection.wrappers.insert(name.clone());
        for site in candidates {
            projection
                .removed
                .entry(programs[site].source.clone())
                .or_default()
                .insert(name.clone());
            let chain = &proofs[site][&name][0];
            let mut prefix = Vec::new();
            for (segment, _) in chain {
                prefix.push(segment.as_str());
                projection.protected.insert(prefix.join("::"));
            }
        }
    }
    for (index, program) in programs.iter_mut().enumerate() {
        let Some(removed) = projection.removed.get(&program.source) else {
            continue;
        };
        let mut items = Vec::new();
        for item in &program.items {
            if let ProgramItem::Declared(names) = item {
                // A wrapper precedes its descendants in Declared's source
                // order. Do not move a later sibling's opening ahead of them.
                let mut pending = Vec::new();
                for name in names {
                    if removed.contains(name) {
                        if !pending.is_empty() {
                            items.push(ProgramItem::Declared(std::mem::take(&mut pending)));
                        }
                        items.push(ProgramItem::Opened(vec![proofs[index][name][0].clone()]));
                    } else {
                        pending.push(name.clone());
                    }
                }
                if !pending.is_empty() {
                    items.push(ProgramItem::Declared(pending));
                }
            } else {
                items.push(item.clone());
            }
        }
        program.items = items;
    }
    projection
}

impl Projection {
    pub fn prepare(&self, app: &mut App) {
        app.library_classes
            .retain(|class| !(self.wrappers.contains(&class.name) && empty(class)));
        for (source, names) in &mut app.library_class_files {
            if let Some(removed) = self.removed.get(source) {
                names.retain(|name| !removed.contains(name));
            }
        }
    }
}

/// Class objects whose initialization lifetime spans features are not arbitrary
/// first-class values in this profile. In particular, native constructors still
/// use the final initialize surface: do not admit an early constructor, alias,
/// superclass escape or a body upcall that could expose that mismatch. Callable
/// parent methods retain their source-point availability; methods/constant reads
/// of the child remain ordinary source IR.
pub(super) fn validate(app: &App, projection: &Projection) -> Result<(), String> {
    use crate::expr::{Expr, ExprNode, Literal};
    if let Some((name, sources)) = projection.unpositioned.first_key_value() {
        return Err(format!(
            "namespace {name} has no single feature identity: declaration source(s) {} have no ordered file-program identity; separate member-feature lifetimes are unproved",
            sources.join(", ")
        ));
    }
    if projection.wrappers.is_empty() {
        return Ok(());
    }
    let methods: BTreeMap<_, BTreeSet<_>> = projection
        .wrappers
        .iter()
        .map(|name| {
            let names = app
                .library_classes
                .iter()
                .filter(|class| &class.name == name)
                .flat_map(|class| &class.methods)
                .filter(|method| method.receiver == crate::dialect::MethodReceiver::Class)
                .map(|method| method.name.as_str().to_string())
                .collect();
            (name.0.as_str().to_string(), names)
        })
        .collect();
    fn check(
        expr: &Expr,
        methods: &BTreeMap<String, BTreeSet<String>>,
        body: Option<&BTreeSet<String>>,
    ) -> Result<(), String> {
        if let ExprNode::Const { path } = &*expr.node {
            let name = path
                .iter()
                .map(|part| part.as_str())
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join("::");
            if methods.contains_key(&name) {
                return Err("a first-class namespace value has no proved initialization lifetime".into());
            }
        }
        if body.is_some() && matches!(&*expr.node, ExprNode::SelfRef) {
            return Err("a namespace body exposes its incomplete class object".into());
        }
        if let ExprNode::Send { recv, method, args, .. } = &*expr.node {
            if method.as_str() == "superclass" {
                return Err("a superclass value has no proved namespace initialization lifetime".into());
            }
            if body
                .is_some_and(|names| names.contains(method.as_str()) || matches!(method.as_str(), "new" | "allocate"))
                && (recv.is_none()
                    || recv
                        .as_ref()
                        .is_some_and(|recv| matches!(&*recv.node, ExprNode::SelfRef)))
            {
                return Err("a namespace body upcall has no proved constructor activation".into());
            }
            if let Some(recv) = recv
                && let ExprNode::Const { path } = &*recv.node
            {
                let name = path
                    .iter()
                    .map(|part| part.as_str())
                    .filter(|part| !part.is_empty())
                    .collect::<Vec<_>>()
                    .join("::");
                if let Some(names) = methods.get(&name) {
                    let query = method.as_str() == "respond_to?"
                        && args.first().is_some_and(|arg| {
                            matches!(
                                &*arg.node,
                                ExprNode::Lit {
                                    value: Literal::Sym { .. } | Literal::Str { .. }
                                }
                            )
                        });
                    if matches!(method.as_str(), "new" | "allocate")
                        || (!names.contains(method.as_str()) && !query)
                        || body.is_some()
                    {
                        return Err(format!(
                            "namespace operation {name}.{method} at {:?} has no proved initialization lifetime",
                            expr.span
                        ));
                    }
                    // Check all arguments/blocks, without treating this proved
                    // literal receiver as an escaped first-class Class value.
                    let mut failure = None;
                    expr.node.for_each_child(&mut |child| {
                        if !std::ptr::eq(child, recv) && failure.is_none() {
                            failure = check(child, methods, body).err();
                        }
                    });
                    return failure.map_or(Ok(()), Err);
                }
            }
        }
        let mut failure = None;
        expr.node.for_each_child(&mut |child| {
            if failure.is_none() {
                failure = check(child, methods, body).err();
            }
        });
        failure.map_or(Ok(()), Err)
    }
    for class in &app.library_classes {
        if class
            .parent
            .as_ref()
            .is_some_and(|parent| projection.wrappers.contains(parent))
        {
            return Err("subclass construction crosses an unproved namespace initialization lifetime".into());
        }
        if let Some(names) = methods.get(class.name.0.as_str()) {
            for expr in class
                .constants
                .iter()
                .map(|(_, value)| value)
                .chain(&class.class_ivar_initializers)
                .chain(&class.unknown_calls)
            {
                check(expr, &methods, Some(names))?;
            }
        }
    }
    fn program(items: &[ProgramItem], methods: &BTreeMap<String, BTreeSet<String>>) -> Result<(), String> {
        for item in items {
            match item {
                ProgramItem::Statement(expr) => check(expr, methods, None)?,
                ProgramItem::Branch {
                    condition,
                    then_items,
                    else_items,
                    ..
                } => {
                    check(condition, methods, None)?;
                    program(then_items, methods)?;
                    program(else_items, methods)?;
                }
                _ => {}
            }
        }
        Ok(())
    }
    for file in &app.file_programs {
        program(&file.items, &methods)?;
    }
    let mut failure = None;
    crate::lower::for_each_emit_body_ref(app, &mut |expr| {
        if failure.is_none() {
            failure = check(expr, &methods, None).err();
        }
    });
    failure.map_or(Ok(()), Err)
}
