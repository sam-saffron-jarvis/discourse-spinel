use roundhouse::{ingest::ingest_app_from_tree, ty::Ty};
use std::{collections::HashMap, path::PathBuf};
#[test]
fn replace_never_invents_a_receiver_contract_after_mixed_or_unknown_mutation() {
    let source = r#"class HashReplaceTypes
  #: (Hash[Symbol, Integer] left, Hash[Symbol, Integer] right) -> untyped
  def self.same(left, right)
    left.replace(right)
  end
  #: (Hash[Symbol, Integer] left, Hash[String, String] right) -> untyped
  def self.mixed(left, right)
    left.replace(right)
  end
  #: (Hash[Symbol, Integer] left, untyped right) -> untyped
  def self.unknown(left, right)
    left.replace(right)
  end
  #: (Hash[Symbol, Integer] left) -> untyped
  def self.arity(left)
    left.replace
  end
end
"#;
    let tree = HashMap::from([
        (
            PathBuf::from("db/schema.rb"),
            b"ActiveRecord::Schema.define do\nend\n".to_vec(),
        ),
        (
            PathBuf::from("config/routes.rb"),
            b"Rails.application.routes.draw do\nend\n".to_vec(),
        ),
        (
            PathBuf::from("lib/hash_replace_types.rb"),
            source.as_bytes().to_vec(),
        ),
    ]);
    let mut app = ingest_app_from_tree(tree).unwrap();
    roundhouse::analyze::Analyzer::new(&app).analyze(&mut app);
    let class = app
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "HashReplaceTypes")
        .unwrap();
    for method in &class.methods {
        if method.name.as_str() == "same" {
            assert!(
                matches!(method.body.ty.as_ref(),Some(Ty::Hash{key,value}) if **key==Ty::Sym && **value==Ty::Int),
                "{method:#?}"
            );
        } else {
            assert!(
                method
                    .body
                    .ty
                    .as_ref()
                    .is_none_or(|ty| ty.mentions_unknown()),
                "{} falsely closed: {:?}",
                method.name.as_str(),
                method.body.ty
            );
        }
    }
}
