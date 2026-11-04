//! Runtime includes/references meet across method boundaries (and merge), where
//! a chain-local eager-load rewrite cannot see both halves. Supply declaration
//! metadata, not application SQL. Only unscoped direct belongs_to is currently
//! safe here: collection joins need joined-row de-duplication/hydration, and
//! scoped/polymorphic associations must not silently lose their restrictions.
use crate::dialect::{Association, MethodDef, Model};
use crate::ident::Symbol;
use crate::ty::Ty;

pub(super) fn method(model: &Model, models: &[Model], registry: &crate::lower::scope_chain::AssocRegistry) -> MethodDef {
    let mut source = String::from("def self._include_reference_join(name, reference)\n");
    for assoc in model.associations() {
        let target = match assoc {
            Association::BelongsTo { target, .. } | Association::HasMany { target, .. }
                | Association::HasOne { target, .. } | Association::HasAndBelongsToMany { target, .. } => target,
        };
        let table = models.iter().find(|m| &m.name == target).map(|m| m.table.0.as_str())
            .unwrap_or("");
        source.push_str(&format!("  if name == :{} && (reference == {:?} || reference == {:?})\n", assoc.name(), assoc.name().as_str(), table));
        let supported = matches!(assoc, Association::BelongsTo { polymorphic: false, .. })
            && models.iter().find(|m| &m.name == target).is_some_and(|m| crate::lower::default_scope::default_scope(m).is_none());
        if supported {
            // An association-name reference may require a table alias. Do not
            // guess at Rails' alias tracker for that unsupported shape.
            source.push_str(&format!("    raise NotImplementedError, \"association-name reference needs alias tracking\" unless reference == {table:?}\n"));
            let sql = format!("LEFT OUTER JOIN {}", registry.join_tail(&model.name, assoc.name()).expect("direct belongs_to join"));
            source.push_str(&format!("    return {sql:?}\n"));
        } else {
            source.push_str("    raise NotImplementedError, \"referenced includes requires an unscoped direct belongs_to association\"\n");
        }
        source.push_str("  end\n");
    }
    source.push_str("  raise NotImplementedError, \"unknown referenced include\" if reference == name.to_s\n  \"\"\nend\n");
    let mut method = crate::runtime_src::parse_methods(&source).expect("reference join metadata").remove(0);
    method.enclosing_class = Some(model.name.0.clone());
    method.signature = Some(super::fn_sig(vec![
        (Symbol::from("name"), Ty::Sym), (Symbol::from("reference"), Ty::Str),
    ], Ty::Str));
    method
}
