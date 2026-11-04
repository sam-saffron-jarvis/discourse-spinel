//! Separate a result-row's possible NULLs from physical column constraints.
//! A raw FROM can replace a table with a subquery/VALUES source. Its attributes
//! retain their declared scalar type but not the table's NOT NULL guarantee.
//! This is read-shape evidence only: schema SQL and column metadata still use
//! Column::nullable. Unknown model receivers conservatively widen all models.
use crate::{App, expr::{Expr, ExprNode}, ident::ClassId, ty::Ty};
use crate::det::HashSet;

pub fn mark(app: &mut App) {
    let mut models = HashSet::default();
    let mut unknown = false;
    fn receiver(e: &Expr, app: &App) -> Option<ClassId> {
        if let Some(Ty::Relation { of }) = &e.ty {
            return Some(of.clone());
        }
        match &*e.node {
            ExprNode::Const { path } => {
                let name = path.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("::");
                app.models.iter().find(|m| m.name.0.as_str() == name).map(|m| m.name.clone())
            }
            ExprNode::Send { recv: Some(r), .. } => receiver(r, app),
            _ => None,
        }
    }
    fn visit(e: &Expr, app: &App, models: &mut HashSet<ClassId>, unknown: &mut bool) {
        if let ExprNode::Send { recv, method, .. } = &*e.node {
            if method.as_str() == "from" {
                if let Some(model) = recv.as_ref().and_then(|r| receiver(r, app)) {
                    models.insert(model);
                } else {
                    *unknown = true;
                }
            }
        }
        e.node.for_each_child(&mut |child| visit(child, app, models, unknown));
    }
    super::for_each_emit_body_ref(app, &mut |e| visit(e, app, &mut models, &mut unknown));
    let tables: HashSet<_> = app.models.iter().filter(|m| unknown || models.contains(&m.name))
        .map(|m| m.table.0.clone()).collect();
    for table in app.schema.tables.values_mut().filter(|t| tables.contains(&t.name)) {
        for col in &mut table.columns {
            // Primary keys retain required slot types, but carry the same
            // evidence so hydration can explicitly refuse NULL identities.
            col.read_nullable = true;
        }
    }
    for model in &mut app.models {
        if let Some(table) = app.schema.tables.get(&model.table.0) {
            for col in table.columns.iter().filter(|c| c.read_nullable) {
                if let Some(ty) = model.attributes.fields.get_mut(&col.name) {
                    *ty = crate::ingest::model::ty_of_column_slot(col);
                }
            }
        }
    }
}
