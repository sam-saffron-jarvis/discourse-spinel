use std::collections::BTreeSet;
use std::io;
use std::path::{Path, PathBuf};

use crate::gems::Lockfile;
use crate::vfs::Vfs;

pub(crate) const MOUNT: &str = ".roundhouse/source_gems";

/// Is `path` a file of `gem` at `version`, compiled from source? The
/// file is recorded at its installed path or under the app's mount.
pub(crate) fn file_of(path: &str, gem: &str, version: &str) -> bool {
    let dir = format!("{gem}-{version}");
    path.contains(&format!("/gems/{dir}/")) || path.contains(&format!("{MOUNT}/{dir}/"))
}

pub(super) struct SourceGem {
    pub mount: PathBuf,
    installed: PathBuf,
    files: BTreeSet<PathBuf>,
    name: String,
}

pub(super) fn resolve<V: Vfs + ?Sized>(
    vfs: &V,
    dir: &Path,
    lock: Option<&Lockfile>,
    names: &[String],
) -> Result<Vec<SourceGem>, String> {
    if names.is_empty() {
        return Ok(Vec::new());
    }
    let Some(lock) = lock else {
        return Err(format!("source_gems names {} but the app has no Gemfile.lock", names.join(", ")));
    };
    let roots = crate::i18n::gems::gem_roots(vfs, dir);
    let mut gems = Vec::new();
    for name in names {
        let Some(version) = lock.version_of(name) else {
            return Err(format!("source_gems names {name:?}, which Gemfile.lock does not resolve"));
        };
        if lock.is_in_repo(name) {
            return Err(format!("source_gems names {name:?}, which Gemfile.lock already takes from the app's tree"));
        }
        let Some(installed) = crate::i18n::gems::installed_gem(vfs, &roots, name, version) else {
            return Err(format!(
                "source_gems names {name:?} {version}, which no gem root holds (BUNDLE_PATH, GEM_HOME, GEM_PATH): run bundle install"
            ));
        };
        // Not lexical first: a `..` after a linked app dir resolves through the link, as the OS reads it
        let installed = vfs.canonical(&installed).unwrap_or_else(|| normalize(&installed));
        let files = required_files(vfs, &installed, name, lock.gemfile_requires.get(name), None)?;
        gems.push(SourceGem { mount: dir.join(MOUNT).join(format!("{name}-{version}")), installed, files, name: name.clone() });
    }
    Ok(gems)
}

/// A target-aware ingest may distinguish mutually exclusive source files only
/// for engine tests that agree on Ruby and Spinel. Source consumers retain the
/// unspecialized inventory. The caller records this restricted runtime profile.
pub(super) fn specialize_ruby_family<V: Vfs + ?Sized>(
    vfs: &V, dir: &Path, lock: Option<&Lockfile>, gems: &mut [SourceGem],
) -> Result<bool, String> {
    use ruby_prism::Visit;
    struct World(bool, bool, usize);
    impl<'pr> Visit<'pr> for World {
        fn visit_class_node(&mut self, node: &ruby_prism::ClassNode<'pr>) {
            let path = node.constant_path();
            if matches!(path.location().as_slice(), b"String" | b"::String" | b"Object" | b"::Object" | b"BasicObject" | b"Class" | b"Module" | b"TrueClass" | b"FalseClass" | b"NilClass") { self.0 = false; }
            self.2 += 1;
            ruby_prism::visit_class_node(self, node);
            self.2 -= 1;
        }
        fn visit_module_node(&mut self, node: &ruby_prism::ModuleNode<'pr>) {
            self.2 += 1;
            ruby_prism::visit_module_node(self, node);
            self.2 -= 1;
        }
        fn visit_def_node(&mut self, node: &ruby_prism::DefNode<'pr>) {
            self.2 += 1;
            ruby_prism::visit_def_node(self, node);
            self.2 -= 1;
        }
        fn visit_call_node(&mut self, node: &ruby_prism::CallNode<'pr>) {
            let method = node.name();
            // App lib/model file-level calls do not have gem FileProgram IR.
            // A computed/opaque call there could load the alternative or change
            // engine lookup and otherwise disappear before the finite guard.
            if self.1 && self.2 == 0 {
                let literal_require = node.receiver().is_none()
                    && matches!(method.as_slice(), b"require" | b"require_relative")
                    && node.arguments().is_some_and(|args| {
                        let args: Vec<_> = args.arguments().iter().collect();
                        matches!(args.as_slice(), [arg] if arg.as_string_node().is_some())
                    });
                if !literal_require { self.0 = false; }
            }
            if matches!(method.as_slice(), b"const_set" | b"remove_const" | b"refine" | b"using") { self.0 = false; }
            if node.receiver().is_some_and(|receiver| matches!(receiver.location().as_slice(), b"String" | b"::String" | b"Object" | b"::Object" | b"BasicObject" | b"Class" | b"Module" | b"TrueClass" | b"FalseClass" | b"NilClass"))
                && matches!(method.as_slice(), b"define_method" | b"define_singleton_method" | b"prepend" | b"include" | b"extend" | b"class_eval" | b"module_eval" | b"instance_eval" | b"send" | b"public_send" | b"__send__") { self.0 = false; }
            ruby_prism::visit_call_node(self, node);
        }
    }
    fn fixed(text: &str, unretained_root: bool) -> bool {
        // Any spelling of an assignment, including a lexical shadow or a
        // compound write, invalidates use of the builtin engine binding.
        for (_, rest) in text.match_indices("RUBY_ENGINE").map(|(at, name)| (at, &text[at + name.len()..])) {
            let rest = rest.trim_start();
            if (rest.starts_with('=') && !rest.starts_with("==") && !rest.starts_with("=~"))
                || rest.starts_with("||=") || rest.starts_with("&&=") { return false; }
        }
        let parsed = super::prism::parse_silent(text.as_bytes());
        if parsed.errors().next().is_some() { return false; }
        let mut world = World(true, unretained_root, 0);
        world.visit(&parsed.node());
        world.0
    }
    if gems.is_empty() { return Ok(false); }
    let Some(lock) = lock else { return Ok(false); };
    let mut pending = ["app", "lib", "config", "Gemfile"].map(|path| dir.join(path)).to_vec();
    let mut checked = BTreeSet::new();
    let mut application_edges = Vec::new();
    while let Some(path) = pending.pop() {
        if !checked.insert(path.clone()) { continue; }
        if vfs.is_symlink(&path) { return Ok(false); }
        if vfs.is_dir(&path) {
            let Ok(entries) = vfs.read_dir(&path) else { return Ok(false); };
            pending.extend(entries);
        } else if path.extension().is_some_and(|extension| extension == "rb") || path.file_name().is_some_and(|name| name == "Gemfile") {
            if !vfs.exists(&path) { continue; }
            let Ok(text) = vfs.read_to_string(&path) else { return Ok(false); };
            if !fixed(&text, path.starts_with(dir.join("app")) || path.starts_with(dir.join("lib"))) { return Ok(false); }
            application_edges.extend(requires_for_engines(&text, Some(&["ruby", "spinel"])).into_iter().map(|(relative, feature)| (path.clone(), relative, feature)));
        }
    }
    for gem in gems.iter() {
        for file in gem.files.iter().filter(|file| file.extension().is_some_and(|extension| extension == "rb")) {
            let path = gem.installed.join(file);
            if path.ancestors().take_while(|path| *path != gem.installed).any(|path| vfs.is_symlink(path)) { return Ok(false); }
            let text = vfs.read_to_string(&path).map_err(|error| error.to_string())?;
            if !fixed(&text, false) { return Ok(false); }
        }
    }
    let selections: Vec<_> = gems.iter().map(|gem| required_files(vfs, &gem.installed, &gem.name, lock.gemfile_requires.get(&gem.name), Some(&["ruby", "spinel"]))).collect::<Result<_, _>>()?;
    // An explicit app or cross-gem require can still load the alternative.
    // Do not remove it merely because one registration branch is false.
    for (gem, selected) in gems.iter().zip(&selections) {
        for file in selected.iter().filter(|file| file.extension().is_some_and(|extension| extension == "rb")) {
            let path = gem.installed.join(file);
            let text = vfs.read_to_string(&path).map_err(|error| error.to_string())?;
            application_edges.extend(requires_for_engines(&text, Some(&["ruby", "spinel"])).into_iter().map(|(relative, feature)| (path.clone(), relative, feature)));
        }
    }
    for (from, relative, feature) in &application_edges {
        let file = if feature.ends_with(".rb") { feature.clone() } else { format!("{feature}.rb") };
        for (gem, selected) in gems.iter().zip(&selections) {
            for excluded in gem.files.difference(selected) {
                let referenced = if *relative {
                    normalize(&from.parent().unwrap().join(&file)) == normalize(&gem.installed.join(excluded))
                } else {
                    excluded == &PathBuf::from("lib").join(&file)
                };
                if referenced { return Ok(false); }
            }
        }
    }
    let mut changed = false;
    for (gem, selected) in gems.iter_mut().zip(selections) {
        changed |= selected != gem.files;
        gem.files = selected;
    }
    Ok(changed)
}

fn required_files<V: Vfs + ?Sized>(
    vfs: &V,
    gem: &Path,
    name: &str,
    gemfile_requires: Option<&Vec<String>>,
    engines: Option<&[&str]>,
) -> Result<BTreeSet<PathBuf>, String> {
    let lib = gem.join("lib");
    // Not the gem's name when the app's Gemfile says what Bundler requires (svg-graph has no `svg-graph.rb`).
    let entries: Vec<PathBuf> = match gemfile_requires.filter(|features| !features.is_empty()) {
        Some(features) => {
            let mut entries = Vec::new();
            for feature in features {
                let path = lib.join(if feature.ends_with(".rb") { feature.clone() } else { format!("{feature}.rb") });
                if !vfs.exists(&path) {
                    return Err(format!("source gem {name:?}: the Gemfile requires {feature:?}, which its lib/ does not hold"));
                }
                entries.push(path);
            }
            entries
        }
        None => [name.to_string(), name.replace('-', "/")]
            .into_iter()
            .map(|feature| lib.join(format!("{feature}.rb")))
            .find(|path| vfs.exists(path))
            .into_iter()
            .collect(),
    };
    if entries.is_empty() {
        return Err(format!("source gem {name:?} has no lib/{name}.rb to require"));
    }
    let mut seen = BTreeSet::new();
    let mut pending = entries;
    while let Some(file) = pending.pop() {
        if !seen.insert(file.strip_prefix(gem).unwrap().to_path_buf()) {
            continue;
        }
        let text = vfs.read_to_string(&file).map_err(|e| format!("{}: {e}", file.display()))?;
        // Not only what is required: `Zeitwerk::Loader.for_gem` autoloads every file under lib/ by its constant name.
        if let Some(ignored) = zeitwerk_ignores(&text, file.parent().unwrap()) {
            let mut dirs = vec![lib.clone()];
            while let Some(dir) = dirs.pop() {
                let Ok(entries) = vfs.read_dir(&dir) else { continue };
                for entry in entries {
                    if vfs.is_symlink(&entry) || ignored.iter().any(|i| entry.starts_with(i)) {
                        continue;
                    }
                    if vfs.is_dir(&entry) {
                        dirs.push(entry);
                    } else if entry.extension().is_some_and(|e| e == "rb") {
                        pending.push(entry);
                    }
                }
            }
        }
        for (relative, feature) in requires_for_engines(&text, engines) {
            let base = if relative { file.parent().unwrap().to_path_buf() } else { lib.clone() };
            let path = base.join(if feature.ends_with(".rb") { feature } else { format!("{feature}.rb") });
            let path = normalize(&path);
            if path.starts_with(&lib) && vfs.exists(&path) {
                pending.push(path);
            }
        }
    }
    // An engine's app/ is no require target: Rails puts it on the host's load paths, so it is the gem's code too
    if super::app::declares_rails_engine(vfs, &lib) {
        let mut dirs = vec![gem.join("app")];
        while let Some(dir) = dirs.pop() {
            let Ok(entries) = vfs.read_dir(&dir) else { continue };
            for entry in entries {
                // A link could reach outside the gem, or back into it
                if vfs.is_symlink(&entry) {
                    continue;
                }
                if vfs.is_dir(&entry) {
                    dirs.push(entry);
                } else if let Ok(rel) = entry.strip_prefix(gem) {
                    seen.insert(rel.to_path_buf());
                }
            }
        }
    }
    Ok(seen)
}

// `None` for an ignore written other than `"#{__dir__}/…"`: mounting what it leaves out would ingest code the gem never loads.
fn zeitwerk_ignores(text: &str, dir: &Path) -> Option<Vec<PathBuf>> {
    if !text.contains("Zeitwerk::Loader.for_gem") || !text.contains(".setup") {
        return None;
    }
    let mut out = Vec::new();
    for (at, _) in text.match_indices(".ignore(") {
        let rest = &text[at + ".ignore(".len()..];
        let arg = rest.split(')').next()?.trim();
        let rel = arg.strip_prefix("\"#{__dir__}/")?.strip_suffix('"')?;
        if rel.contains('#') || rel.contains('*') {
            return None;
        }
        out.push(normalize(&dir.join(rel)));
    }
    Some(out)
}

#[cfg(test)]
fn requires(text: &str) -> Vec<(bool, String)> {
    requires_for_engines(text, None)
}

fn requires_for_engines(text: &str, engines: Option<&[&str]>) -> Vec<(bool, String)> {
    struct Finder<'a>(Vec<(bool, String)>, usize, Option<&'a [&'a str]>);
    impl<'pr> ruby_prism::Visit<'pr> for Finder<'_> {
        fn visit_if_node(&mut self, node: &ruby_prism::IfNode<'pr>) {
            let choice = self.2.and_then(|engines| engine_consensus(&node.predicate(), engines));
            match choice {
                Some(true) => { if let Some(body) = node.statements() { self.visit(&body.as_node()); } }
                Some(false) => { if let Some(body) = node.subsequent() { self.visit(&body); } }
                None => ruby_prism::visit_if_node(self, node),
            }
        }

        fn visit_def_node(&mut self, node: &ruby_prism::DefNode<'pr>) {
            self.1 += 1;
            ruby_prism::visit_def_node(self, node);
            self.1 -= 1;
        }

        fn visit_call_node(&mut self, node: &ruby_prism::CallNode<'pr>) {
            let method = node.name();
            let relative = match method.as_slice() {
                b"require" => Some(false),
                b"require_relative" => Some(true),
                _ => None,
            };
            let args: Vec<_> = node.arguments().map(|a| a.arguments().iter().collect()).unwrap_or_default();
            let feature = match (relative, args.as_slice()) {
                (Some(_), [arg]) => arg.as_string_node(),
                (None, [name, arg]) if method.as_slice() == b"autoload" && self.1 == 0 && name.as_symbol_node().is_some() => {
                    arg.as_string_node()
                }
                _ => None,
            };
            if let (Some(feature), None) = (feature, node.receiver()) {
                self.0.push((relative == Some(true), String::from_utf8_lossy(feature.unescaped()).into_owned()));
            }
            ruby_prism::visit_call_node(self, node);
        }
    }
    let parsed = super::prism::parse_silent(text.as_bytes());
    let mut finder = Finder(Vec::new(), 0, engines);
    ruby_prism::Visit::visit(&mut finder, &parsed.node());
    finder.0
}

/// Only engine predicates agreeing on BOTH the original CRuby reference and
/// native Spinel can select this source inventory. Other conditions retain all
/// dependencies. This changes no source expression or loader execution order.
fn engine_consensus(node: &ruby_prism::Node<'_>, engines: &[&str]) -> Option<bool> {
    fn truth(node: &ruby_prism::Node<'_>, engine: &str) -> Option<bool> {
        if node.as_true_node().is_some() { return Some(true); }
        if node.as_false_node().is_some() || node.as_nil_node().is_some() { return Some(false); }
        let call = node.as_call_node()?;
        if call.block().is_some() { return None; }
        let receiver = call.receiver()?;
        let args: Vec<_> = call.arguments().map(|args| args.arguments().iter().collect()).unwrap_or_default();
        if call.name().as_slice() == b"!" && args.is_empty() { return truth(&receiver, engine).map(|value| !value); }
        let [argument] = args.as_slice() else { return None; };
        let equal = match call.name().as_slice() { b"==" => true, b"!=" => false, _ => return None };
        let (constant, literal) = if receiver.as_constant_read_node().is_some() { (&receiver, argument) } else { (argument, &receiver) };
        if constant.as_constant_read_node()?.name().as_slice() != b"RUBY_ENGINE" { return None; }
        let literal = literal.as_string_node()?;
        Some((literal.unescaped() == engine.as_bytes()) == equal)
    }
    let first = truth(node, *engines.first()?)?;
    engines.iter().all(|engine| truth(node, engine) == Some(first)).then_some(first)
}

/// The shared IR form of the same guarded Ruby/Spinel engine consensus.
/// Only callers with the validated inventory profile may use this proof.
pub(crate) fn ruby_family_truth(expr: &crate::expr::Expr) -> Option<bool> {
    use crate::expr::{ExprNode, Literal};
    match &*expr.node {
        ExprNode::Lit { value: Literal::Bool { value } } => Some(*value),
        ExprNode::Lit { value: Literal::Nil } => Some(false),
        ExprNode::Send { recv: Some(recv), method, args, block: None, .. }
            if method.as_str() == "!" && args.is_empty() => ruby_family_truth(recv).map(|value| !value),
        ExprNode::Send { recv: Some(recv), method, args, block: None, .. }
            if matches!(method.as_str(), "==" | "!=") && args.len() == 1 => {
            let (constant, literal) = if matches!(&*recv.node, ExprNode::Const { .. }) { (recv, &args[0]) } else { (&args[0], recv) };
            if !matches!(&*constant.node, ExprNode::Const { path } if path.len() == 1 && path[0].as_str() == "RUBY_ENGINE") { return None; }
            let ExprNode::Lit { value: Literal::Str { value } } = &*literal.node else { return None; };
            let equal = method.as_str() == "==";
            let ruby = (value == "ruby") == equal;
            let spinel = (value == "spinel") == equal;
            (ruby == spinel).then_some(ruby)
        }
        _ => None,
    }
}

fn normalize(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::ParentDir if matches!(out.components().next_back(), Some(Component::Normal(_))) => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

pub(super) struct MountVfs<'a, V: Vfs + ?Sized> {
    pub inner: &'a V,
    pub gems: &'a [SourceGem],
}

impl<V: Vfs + ?Sized> MountVfs<'_, V> {
    fn mounted(&self, path: &Path) -> Option<(&SourceGem, PathBuf)> {
        self.gems.iter().find_map(|gem| path.strip_prefix(&gem.mount).ok().map(|rel| (gem, rel.to_path_buf())))
    }

    fn file(&self, path: &Path) -> io::Result<PathBuf> {
        match self.mounted(path) {
            Some((gem, rel)) if gem.files.contains(&rel) => Ok(gem.installed.join(rel)),
            Some(_) => Err(io::Error::new(io::ErrorKind::NotFound, "not required by the source gem")),
            None => Ok(path.to_path_buf()),
        }
    }
}

impl<V: Vfs + ?Sized> Vfs for MountVfs<'_, V> {
    fn read(&self, path: &Path) -> io::Result<Vec<u8>> {
        self.inner.read(&self.file(path)?)
    }

    fn read_to_string(&self, path: &Path) -> io::Result<String> {
        self.inner.read_to_string(&self.file(path)?)
    }

    fn read_dir(&self, path: &Path) -> io::Result<Vec<PathBuf>> {
        let Some((gem, rel)) = self.mounted(path) else { return self.inner.read_dir(path) };
        let children: BTreeSet<PathBuf> = gem
            .files
            .iter()
            .filter_map(|file| file.strip_prefix(&rel).ok()?.components().next().map(|c| path.join(c)))
            .collect();
        if children.is_empty() {
            return Err(io::Error::new(io::ErrorKind::NotFound, "not required by the source gem"));
        }
        Ok(children.into_iter().collect())
    }

    fn exists(&self, path: &Path) -> bool {
        match self.mounted(path) {
            Some((gem, rel)) => gem.files.iter().any(|file| file.starts_with(&rel)),
            None => self.inner.exists(path),
        }
    }

    fn is_dir(&self, path: &Path) -> bool {
        match self.mounted(path) {
            Some((gem, rel)) => gem.files.iter().any(|file| file.starts_with(&rel) && *file != rel),
            None => self.inner.is_dir(path),
        }
    }

    fn is_symlink(&self, path: &Path) -> bool {
        match self.mounted(path) {
            // The mount is a name, not a directory on disk, so it has no link to report
            Some(_) => false,
            None => self.inner.is_symlink(path),
        }
    }

    fn canonical(&self, path: &Path) -> Option<PathBuf> {
        match self.mounted(path) {
            Some(_) => None,
            None => self.inner.canonical(path),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_dependency_prototype_requires_ruby_native_consensus() {
        let source = r#"module Example
  if RUBY_ENGINE == 'jruby'
    autoload :Connection, 'example/jdbc'
  else
    autoload :Connection, 'example/native'
  end
end
"#;
        assert_eq!(requires(source), vec![(false, "example/jdbc".into()), (false, "example/native".into())]);
        assert_eq!(requires_for_engines(source, Some(&["ruby", "spinel"])), vec![(false, "example/native".into())]);
        // A predicate that disagrees between the reference and native runtime
        // cannot select either source inventory for a shared proof.
        let divergent = source.replace("'jruby'", "'ruby'");
        assert_eq!(requires_for_engines(&divergent, Some(&["ruby", "spinel"])).len(), 2);
        let unknown = source.replace("RUBY_ENGINE == 'jruby'", "ENV['ADAPTER'] == 'jdbc'");
        assert_eq!(requires_for_engines(&unknown, Some(&["ruby", "spinel"])).len(), 2);
        let opposite = source.replace("RUBY_ENGINE == 'jruby'", "'jruby' != RUBY_ENGINE");
        assert_eq!(requires_for_engines(&opposite, Some(&["ruby", "spinel"])), vec![(false, "example/jdbc".into())]);
    }

    #[test]
    fn a_bundle_path_above_the_app_keeps_the_required_files() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("app/.bundle/config", "---\nBUNDLE_PATH: \"../shared/bundle\"\n");
        let gem = "shared/bundle/ruby/3.4.0/gems/widgets-1.0";
        write(&format!("{gem}/lib/widgets.rb"), "require \"widgets/part\"\n");
        write(&format!("{gem}/lib/widgets/part.rb"), "module Widgets; end\n");
        write(&format!("{gem}/lib/widgets/rspec.rb"), "module Widgets; end\n");
        let lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    widgets (1.0)\n\nDEPENDENCIES\n  widgets\n");
        let gems = resolve(&crate::vfs::FsVfs::new(), &root.join("app"), Some(&lock), &["widgets".to_string()]).unwrap();
        let files: Vec<_> = gems[0].files.iter().map(|p| p.display().to_string()).collect();
        assert_eq!(files, vec!["lib/widgets/part.rb", "lib/widgets.rb"]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_gemfile_require_names_the_entry_files() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-require-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("app/.bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n");
        let gem = "app/vendor/bundle/ruby/3.4.0/gems/svg-graph-2.2.2";
        write(&format!("{gem}/lib/SVG/Graph/TimeSeries.rb"), "require_relative \"Plot\"\n");
        write(&format!("{gem}/lib/SVG/Graph/Plot.rb"), "module SVG; end\n");
        write(&format!("{gem}/lib/svggraph.rb"), "module SVG; end\n");
        let lock_with = |requires: &[&str]| {
            let mut lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    svg-graph (2.2.2)\n\nDEPENDENCIES\n  svg-graph\n");
            lock.gemfile_requires.insert("svg-graph".to_string(), requires.iter().map(|r| r.to_string()).collect());
            lock
        };
        let vfs = crate::vfs::FsVfs::new();
        let names = ["svg-graph".to_string()];
        let gems = resolve(&vfs, &root.join("app"), Some(&lock_with(&["SVG/Graph/TimeSeries", "svggraph.rb"])), &names).unwrap();
        let files: Vec<_> = gems[0].files.iter().map(|p| p.display().to_string()).collect();
        assert_eq!(files, vec!["lib/SVG/Graph/Plot.rb", "lib/SVG/Graph/TimeSeries.rb", "lib/svggraph.rb"]);
        let err = resolve(&vfs, &root.join("app"), Some(&lock_with(&["SVG/Graph/TimeSeries", "SVG/Missing"])), &names).err().unwrap();
        assert!(err.contains("\"SVG/Missing\""), "{err}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_autoloaded_file_is_compiled_with_the_gem() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-autoload-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("app/.bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n");
        let gem = "app/vendor/bundle/ruby/3.4.0/gems/widgets-1.0";
        write(
            &format!("{gem}/lib/widgets.rb"),
            "module Widgets\n  autoload :Base, \"widgets/base\"\n  def self.later\n    autoload :Later, \"widgets/later\"\n  end\nend\n",
        );
        write(&format!("{gem}/lib/widgets/later.rb"), "module Widgets; class Later; end; end\n");
        write(&format!("{gem}/lib/widgets/base.rb"), "module Widgets; class Base; end; end\n");
        let lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    widgets (1.0)\n\nDEPENDENCIES\n  widgets\n");
        let gems = resolve(&crate::vfs::FsVfs::new(), &root.join("app"), Some(&lock), &["widgets".to_string()]).unwrap();
        let files: Vec<_> = gems[0].files.iter().map(|p| p.display().to_string()).collect();
        assert_eq!(files, vec!["lib/widgets/base.rb", "lib/widgets.rb"]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_zeitwerk_gem_brings_every_lib_file_it_does_not_ignore() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-zeitwerk-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("app/.bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n");
        let gem = "app/vendor/bundle/ruby/3.4.0/gems/widgets-1.0";
        write(
            &format!("{gem}/lib/widgets.rb"),
            "require \"zeitwerk\"\nloader = Zeitwerk::Loader.for_gem\nloader.ignore(\"#{__dir__}/widgets/templates\")\nloader.setup\nmodule Widgets; end\n",
        );
        write(&format!("{gem}/lib/widgets/part.rb"), "module Widgets; class Part; end; end\n");
        write(&format!("{gem}/lib/widgets/part/kind.rb"), "module Widgets; class Part; class Kind; end; end; end\n");
        write(&format!("{gem}/lib/widgets/templates/model.rb"), "class <%= name %>; end\n");
        write(&format!("{gem}/lib/widgets/notes.txt"), "not ruby\n");
        let lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    widgets (1.0)\n\nDEPENDENCIES\n  widgets\n");
        let gems = resolve(&crate::vfs::FsVfs::new(), &root.join("app"), Some(&lock), &["widgets".to_string()]).unwrap();
        let files: Vec<_> = gems[0].files.iter().map(|p| p.display().to_string()).collect();
        assert_eq!(files, vec!["lib/widgets/part/kind.rb", "lib/widgets/part.rb", "lib/widgets.rb"]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    #[cfg(unix)]
    fn a_bundle_path_through_a_linked_app_dir_resolves_as_the_os_does() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-link-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("releases/1/.bundle/config", "---\nBUNDLE_PATH: \"../shared/bundle\"\n");
        std::os::unix::fs::symlink(root.join("releases/1"), root.join("current")).unwrap();
        let gem = "releases/shared/bundle/ruby/3.4.0/gems/widgets-1.0";
        write(&format!("{gem}/lib/widgets.rb"), "require \"widgets/part\"\n");
        write(&format!("{gem}/lib/widgets/part.rb"), "module Widgets; end\n");
        let lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    widgets (1.0)\n\nDEPENDENCIES\n  widgets\n");
        let gems = resolve(&crate::vfs::FsVfs::new(), &root.join("current"), Some(&lock), &["widgets".to_string()]).unwrap();
        assert_eq!(gems[0].files.len(), 2);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_engine_gem_brings_its_app_dir_and_a_library_does_not() {
        let root = std::env::temp_dir().join(format!("rh-source-gems-engine-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let write = |path: &str, text: &str| {
            let full = root.join(path);
            std::fs::create_dir_all(full.parent().unwrap()).unwrap();
            std::fs::write(full, text).unwrap();
        };
        write("app/.bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n");
        let gems = "app/vendor/bundle/ruby/3.4.0/gems";
        write(&format!("{gems}/auth-1.0/lib/auth.rb"), "require \"auth/rails\"\n");
        write(&format!("{gems}/auth-1.0/lib/auth/rails.rb"), "module Auth\n  class Engine < ::Rails::Engine\n  end\nend\n");
        write(&format!("{gems}/auth-1.0/app/controllers/auth/sessions_controller.rb"), "class Auth::SessionsController\nend\n");
        write(&format!("{gems}/auth-1.0/app/views/auth/sessions/new.html.erb"), "<p>sign in</p>\n");
        write(&format!("{gems}/plain-1.0/lib/plain.rb"), "module Plain\nend\n");
        write(&format!("{gems}/plain-1.0/app/models/plain/thing.rb"), "class Plain::Thing\nend\n");
        write("outside/secret.rb", "SECRET = 1\n");
        #[cfg(unix)]
        std::os::unix::fs::symlink(root.join("outside"), root.join(format!("{gems}/auth-1.0/app/linked"))).unwrap();
        let lock = Lockfile::parse("GEM\n  remote: https://rubygems.org/\n  specs:\n    auth (1.0)\n    plain (1.0)\n\nDEPENDENCIES\n  auth\n  plain\n");
        let gems = resolve(&crate::vfs::FsVfs::new(), &root.join("app"), Some(&lock), &["auth".to_string(), "plain".to_string()]).unwrap();
        let files = |i: usize| gems[i].files.iter().map(|p| p.display().to_string()).collect::<Vec<_>>();
        assert!(files(0).contains(&"app/controllers/auth/sessions_controller.rb".to_string()), "{:?}", files(0));
        assert!(files(0).contains(&"app/views/auth/sessions/new.html.erb".to_string()), "{:?}", files(0));
        assert!(!files(0).iter().any(|f| f.contains("linked") || f.contains("secret")), "{:?}", files(0));
        assert_eq!(files(1), vec!["lib/plain.rb"]);
        let _ = std::fs::remove_dir_all(&root);
    }
}
