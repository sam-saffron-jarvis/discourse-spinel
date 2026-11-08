//! Render resolved finite feature IR. Class bodies are still the ordinary
//! lowered declaration output, but live in their one canonical feature rather
//! than behind a second declaration-file identity. Both native and CRuby run
//! these same files; Kernel's loader retains its rescue/rollback/retry path.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write;

use crate::lower::file_programs::{normalize, Plan, Step};
use crate::{App, ClassId};

fn relative(from: &str, to: &str) -> String {
    let from: Vec<_> = from.split('/').filter(|p| !p.is_empty()).collect();
    let to: Vec<_> = to.split('/').filter(|p| !p.is_empty()).collect();
    let shared = from
        .iter()
        .zip(&to[..to.len().saturating_sub(1)])
        .take_while(|(a, b)| a == b)
        .count();
    std::iter::repeat_n("..", from.len() - shared)
        .chain(to[shared..].iter().copied())
        .collect::<Vec<_>>()
        .join("/")
}

pub(super) fn refusal(message: String) -> String {
    let diagnostic = crate::diagnostic::Diagnostic::unsupported(
        crate::span::Span::synthetic(),
        Some(crate::Symbol::from("spinel")),
        "finite file program",
        message,
    );
    let message = diagnostic.message.clone();
    crate::emit::diagnostics::push(diagnostic);
    message
}

pub(super) fn apply(files: &mut Vec<(String, String)>, app: &App, plan: &Plan) -> Result<(), String> {
    let mut anchors: BTreeMap<String, (usize, Vec<&ClassId>)> = BTreeMap::new();
    for (name, resource) in &plan.declarations {
        let anchor = crate::emit::ruby::library_file_anchor(name.0.as_str(), app);
        let entry = anchors.entry(anchor.clone()).or_insert((*resource, Vec::new()));
        if entry.0 != *resource {
            return Err(format!(
                "finite native file-program profile: declaration file {anchor} merges different resources"
            ));
        }
        entry.1.push(name);
    }
    let bodies: BTreeMap<_, _> = files
        .iter()
        .filter_map(|(path, body)| {
            let anchor = path.strip_prefix("app/")?.strip_suffix(".rb")?;
            anchors.contains_key(anchor).then(|| (anchor.to_string(), body.clone()))
        })
        .collect();
    for anchor in anchors.keys() {
        if !bodies.contains_key(anchor) {
            return Err(format!(
                "finite native file-program profile: missing declaration output {anchor}"
            ));
        }
    }
    for (resource, program) in plan.programs.iter().enumerate() {
        let dir = program.anchor.rsplit_once('/').map(|(dir, _)| dir).unwrap_or("");
        let mut body = format!("{}# Finite file-program feature: {}\n# Literal owner/resource identities; Kernel owns cache, failure rollback and retry.\n", program.literal_policy.directive(), program.source);
        let mut written = BTreeSet::new();
        let mut required = BTreeSet::new();
        for step in &program.steps {
            match step {
                Step::Opened(chains) => {
                    for chain in chains {
                        let namespace = chain
                            .iter()
                            .map(|(name, _)| name.as_str())
                            .collect::<Vec<_>>()
                            .join("::");
                        // The shared plan proves this very namespace object is
                        // already bound at every entry to a compact resource.
                        // Do not create a second deferred namespace definition.
                        if plan.compact_headers.iter().any(|name| {
                            plan.declarations[name] == resource
                                && name.0.as_str().starts_with(&format!("{namespace}::"))
                        }) {
                            continue;
                        }
                        for (name, class) in chain {
                            write!(body, "{} {name}; ", if *class { "class" } else { "module" }).unwrap();
                        }
                        writeln!(body, "{}", vec!["end"; chain.len()].join("; ")).unwrap();
                    }
                }
                Step::Declared(names) => {
                    for name in names {
                        let anchor = crate::emit::ruby::library_file_anchor(name.0.as_str(), app);
                        if !written.insert(anchor.clone()) {
                            continue;
                        }
                        let decl_dir = anchor.rsplit_once('/').map(|(dir, _)| dir).unwrap_or("");
                        for line in bodies[&anchor].lines() {
                            if let Some(path) = line
                                .strip_prefix("require_relative \"")
                                .and_then(|s| s.strip_suffix('"'))
                            {
                                let dependency = normalize(&format!("{decl_dir}/{path}"));
                                if let Some((target, names)) = anchors.get(&dependency) {
                                    // These are derived declaration dependencies, not
                                    // source requires (those have their own Step).
                                    // A pending autoload must run at its actual read,
                                    // not be forced by a hoisted dependency preamble.
                                    let autoload = names.iter().all(|name| {
                                        plan.autoloaded.iter().any(|binding| {
                                            name.0 == binding.0
                                                || name.0.as_str().starts_with(&format!("{}::", binding.0))
                                        })
                                    });
                                    // A proved empty source namespace opening
                                    // already bound this ancestor. Its main body
                                    // is NOT a dependency of the child's feature;
                                    // real constant reads still run in place and
                                    // may raise before that later body loads.
                                    let namespace = names.iter().all(|parent| {
                                        plan.namespace_wrappers.contains(parent)
                                            && anchors[&anchor].1.iter().all(|child| {
                                                child.0.as_str().starts_with(&format!("{}::", parent.0))
                                            })
                                    });
                                    if *target == resource || required.contains(target) || autoload || namespace {
                                        continue;
                                    }
                                    return Err(format!("finite native file-program profile: unproved declaration dependency {anchor} -> {dependency}"));
                                }
                                writeln!(body, "require_relative {:?}", relative(dir, &dependency)).unwrap();
                            } else {
                                writeln!(body, "{line}").unwrap();
                            }
                        }
                    }
                }
                Step::Statement(expr) => {
                    if let Some(marker) = crate::emit::ruby::source_markers::marker_for(&expr.span) {
                        writeln!(body, "{marker}").unwrap();
                    }
                    writeln!(body, "{}", crate::emit::ruby::emit_expr(expr)).unwrap();
                }
                Step::Require(target) => {
                    // Do not deduplicate source requires: repeated/circular
                    // calls retain the loader's true/false and failure behavior.
                    writeln!(
                        body,
                        "require_relative {:?}",
                        relative(dir, &plan.programs[*target].anchor)
                    )
                    .unwrap();
                    required.insert(*target);
                }
                Step::Autoload { owner, name, resource } => {
                    writeln!(
                        body,
                        "{owner}.autoload(:{name}, File.expand_path({:?}, __dir__))",
                        relative(dir, &format!("{}.rb", plan.programs[*resource].anchor))
                    )
                    .unwrap();
                }
            }
        }
        files.push((format!("app/{}.rb", program.anchor), body));
    }
    // No declaration path may be a second independently executable copy of
    // the source body. Keep it only as a compatibility require of the feature.
    for (path, content) in files.iter_mut() {
        if let Some(anchor) = path.strip_prefix("app/").and_then(|s| s.strip_suffix(".rb")) {
            if let Some((resource, _)) = anchors.get(anchor) {
                let dir = anchor.rsplit_once('/').map(|(dir, _)| dir).unwrap_or("");
                *content = format!(
                    "require_relative {:?}\n",
                    relative(dir, &plan.programs[*resource].anchor)
                );
            }
        }
    }
    let Some((_, models)) = files.iter_mut().find(|(path, _)| path == "app/models.rb") else {
        return Err("finite native file-program profile: missing model aggregator".into());
    };
    let kept = models
        .lines()
        .filter(|line| {
            !line
                .strip_prefix("require_relative \"")
                .and_then(|s| s.strip_suffix('"'))
                .is_some_and(|s| anchors.contains_key(s))
        })
        .collect::<Vec<_>>()
        .join("\n");
    let mut boot = String::from("# Finite source-gem feature roots, in original boot order.\n");
    for resource in &plan.boot {
        writeln!(boot, "require_relative {:?}", plan.programs[*resource].anchor).unwrap();
    }
    *models = format!("{boot}{kept}\n");
    Ok(())
}

/// A finite feature graph is a graph-loader contract, never the default
/// eager-inline load model. Do not write an ignored manifest key; use spin's
/// supported compiler-argument seam and name the requirement in the artifact.
pub(super) fn graph_build(files: &mut Vec<(String, String)>) {
    for (path, content) in files.iter_mut() {
        if path == "Makefile" {
            *content = content
                .replace("$(SPIN) build\n", "$(SPIN) build -- --load-model=graph\n")
                .replace(
                    "$(SPINEL) $(SPIN_TEST_FLAGS)",
                    "$(SPINEL) --load-model=graph $(SPIN_TEST_FLAGS)",
                );
        }
        if path.starts_with("scripts/") {
            *content = content.replace("spin build\n", "spin build -- --load-model=graph\n");
        }
    }
    files.push(("FILE_PROGRAMS.md".into(), "# Finite source-gem file programs\n\nThis tree requires native graph loading. Build with `make build` or\n`spin build -- --load-model=graph`; direct compiler consumers must also pass\n`--load-model=graph`. The default inline/eager mode is not this artifact's\nload model. CRuby can execute the same lowered Ruby files.\n\nLiteral owners and resources are proved before emission. Kernel's loader\npreserves lazy body effects, feature/cache identity, circular require,\nfailed-load restoration and retry. Dynamic/reflected owner/resource worlds\nremain refused; the reflective Ruby-family helper is not enabled natively.\n".into()));
}
