//! Explicit request roots for a Spinel build. Whole-app analysis and its gap
//! inventory remain intact; only the emitted request closure is projected.
use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::App;
use crate::dialect::{ControllerBodyItem, LibraryClass, MethodReceiver, ModelBodyItem};
use crate::ide::TraceHop;

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct EntrySlice {
    pub patterns: Vec<String>,
    pub unmatched: Vec<String>,
    pub universe: BTreeSet<String>,
    pub classes: BTreeSet<String>,
    pub methods: BTreeSet<(String, bool, String)>,
}

impl EntrySlice {
    pub fn matches(&self, path: &str) -> bool {
        self.patterns.iter().any(|p| p == path)
    }

    pub fn method(&self, owner: &str, class_side: bool, name: &str) -> bool {
        self.methods.contains(&(owner.to_string(), class_side, name.to_string()))
    }

    /// Unseen generated specializations are kept conservatively. Classes in
    /// the analyzed universe are retained only when the request reaches them.
    pub fn filter_classes(&self, classes: &mut Vec<LibraryClass>) {
        if self.universe.is_empty() { return; }
        classes.retain(|c| !self.universe.contains(c.name.0.as_str()) || self.classes.contains(c.name.0.as_str()));
        for c in classes {
            if !self.universe.contains(c.name.0.as_str()) { continue; }
            c.methods.retain(|m| crate::source_gem_shake::implicit_method(m)
                || self.method(c.name.0.as_str(), m.receiver == MethodReceiver::Class, m.name.as_str()));
        }
    }
}

pub fn parse_patterns(value: &str) -> Result<Vec<String>, String> {
    let mut patterns = Vec::new();
    for path in value.split(',').map(str::trim) {
        if !path.starts_with('/') || path.contains('?') || path.contains('#') || path.contains("(.:format)") || path.is_empty() {
            return Err(format!("--entry-routes expects comma-separated path patterns without format suffixes: {path:?}"));
        }
        if !patterns.iter().any(|p| p == path) { patterns.push(path.to_string()); }
    }
    Ok(patterns)
}

/// Use the MCP request-chain builder for filter/concern/view roots, and the
/// source-gem worklist for the transitive typed/self/dynamic call closure.
/// The final Ruby-family text shaker still runs over this smaller universe.
pub fn select(app: &mut App, patterns: Vec<String>) -> Result<(), String> {
    if patterns.is_empty() { return Err("--entry-routes requires at least one path".into()); }
    let routes = crate::lower::routes::flatten_routes(app);
    let selected: Vec<_> = routes.iter().filter(|r| patterns.contains(&r.path)).collect();
    if selected.is_empty() { return Err(format!("--entry-routes matched no ingested route: {}", patterns.join(","))); }
    let unmatched: Vec<_> = patterns.iter().filter(|p| !selected.iter().any(|r| &r.path == *p)).cloned().collect();
    for path in &unmatched {
        eprintln!("roundhouse: entry route {path:?} was not ingested; no route or response is invented for it");
    }
    let mut roots = BTreeSet::new();
    let mut live = BTreeSet::new();
    let mut views = BTreeSet::new();
    for route in &selected {
        let owner = route.controller.0.to_string();
        live.insert(owner.clone());
        roots.insert((owner.clone(), false, route.action.to_string()));
        roots.insert((owner.clone(), false, "process_action".to_string()));
        if let Some(trace) = crate::ide::traceroute(app, &format!("{}#{}", owner, route.action)) {
            for hop in trace.hops {
                match hop {
                    TraceHop::Filter(f) if f.applies => {
                        live.insert(f.defined_in.clone());
                        live.insert(f.included_via.clone());
                        roots.insert((f.defined_in, false, f.name));
                    }
                    TraceHop::View { name, partials, .. } => {
                        views.insert(name); views.extend(partials);
                    }
                    _ => {}
                }
            }
        }
    }
    if app.controllers.iter().any(|c| c.name.0.as_str() == "ApplicationController") {
        live.insert("ApplicationController".into());
    }
    // This build deliberately has JSON entry points, not an HTML/Ember app.
    // Tests, seeds and assets are separate executables/resources, not roots.
    app.views.retain(|v| v.format.as_str() != "html" && views.contains(v.name.as_str()));
    app.test_modules.clear(); app.fixtures.clear(); app.seeds = None;
    app.binary_assets.clear(); app.stylesheets.clear(); app.importmap = None;
    app.vite_manifest = None; app.inertia = None;
    app.entry_slice = Some(EntrySlice { patterns, unmatched, ..EntrySlice::default() });
    let classes = crate::emit::ruby::entry_library_classes(app);
    let universe = classes.iter().map(|c| c.name.0.to_string()).collect();
    let reached = crate::source_gem_shake::entry_reach(&classes, &roots.into_iter().collect::<Vec<_>>(), live.into_iter().collect(), &app.boot_program);
    let slice = app.entry_slice.as_mut().unwrap();
    slice.universe = universe;
    slice.classes = reached.classes.into_iter().collect();
    slice.methods = reached.methods.into_iter().collect();
    let before = (app.controllers.len(), app.models.len(), app.library_classes.len());
    app.controllers.retain(|c| slice.classes.contains(c.name.0.as_str()));
    for c in &mut app.controllers {
        c.body.retain(|item| match item {
            ControllerBodyItem::Action { action, .. } => slice.method(c.name.0.as_str(), false, action.name.as_str()),
            ControllerBodyItem::ClassMethod { method, .. } => slice.method(c.name.0.as_str(), true, method.name.as_str()),
            _ => true,
        });
    }
    app.models.retain(|m| slice.classes.contains(m.name.0.as_str()));
    for model in &mut app.models {
        model.body.retain(|item| match item {
            ModelBodyItem::Method { method, .. } => crate::source_gem_shake::implicit_method(method)
                || slice.method(model.name.0.as_str(), method.receiver == MethodReceiver::Class, method.name.as_str()),
            _ => true,
        });
    }
    slice.filter_classes(&mut app.library_classes);
    app.library_class_files.retain_mut(|(_, names)| {
        names.retain(|name| slice.classes.contains(name.0.as_str()));
        !names.is_empty()
    });
    // Keep all original schema columns of reached tables. An association's
    // schema evidence is not a reason to import that other model's methods.
    let tables: BTreeSet<_> = app.models.iter().map(|m| m.table.0.clone()).collect();
    app.schema.tables.retain(|name, _| tables.contains(name));
    eprintln!("roundhouse: entry slice: {} route rows; controllers {} -> {}, models {} -> {}, libraries {} -> {}; {} reached methods",
        selected.len(), before.0, app.controllers.len(), before.1, app.models.len(), before.2, app.library_classes.len(), slice.methods.len());
    Ok(())
}
