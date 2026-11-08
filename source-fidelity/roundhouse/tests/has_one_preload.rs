//! Unscoped `has_one` participates in Relation `preload` / `includes`
//! batching through the load-once cache.
//!
//! Scoped singular reads preload with their real reader (N+1 allowed).
//! Unclaimed: scoped `has_one` optimized batching; polymorphic
//! `as:` preload batch; separate `eager_load` emit_and_run pin.

#[path = "support/emit_and_run.rs"]
mod emit_and_run;
#[path = "support/has_one_overlay.rs"]
mod has_one_overlay;

use has_one_overlay::profile_schema_edit;

#[test]
fn preloading_has_one_distributes_each_owners_child() {
    let (path, from, to) = profile_schema_edit();
    emit_and_run::real_blog()
        .edit(path, from, to)
        .write(
            "app/models/profile.rb",
            "class Profile < ApplicationRecord\n  belongs_to :article\nend\n",
        )
        .edit(
            "app/models/article.rb",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy\n  has_one :profile\n  scope :with_profiles, -> { preload(:profile) }",
        )
        .run_ruby(
            r#"
a = Article.create!(title: "Alpha", body: "abcdefghij")
b = Article.create!(title: "Beta", body: "abcdefghij")
c = Article.create!(title: "Gamma", body: "abcdefghij")
Profile.create!(article_id: a.id, bio: "a-bio")
Profile.create!(article_id: c.id, bio: "c-bio")
rows = Article.with_profiles.order(:id).to_a
raise "count" unless rows.size == 3
raise "alpha" unless rows[0].profile.bio == "a-bio"
raise "beta should be nil" unless rows[1].profile.nil?
raise "gamma" unless rows[2].profile.bio == "c-bio"
puts "has_one preload passed"
"#,
        )
        .assert_passes();
}

/// `includes(:assoc)` — sibling Relation spelling of the same batch path.
#[test]
fn includes_has_one_distributes_each_owners_child() {
    let (path, from, to) = profile_schema_edit();
    emit_and_run::real_blog()
        .edit(path, from, to)
        .write(
            "app/models/profile.rb",
            "class Profile < ApplicationRecord\n  belongs_to :article\nend\n",
        )
        .edit(
            "app/models/article.rb",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy\n  has_one :profile\n  scope :including_profiles, -> { includes(:profile) }",
        )
        .run_ruby(
            r#"
a = Article.create!(title: "Alpha", body: "abcdefghij")
b = Article.create!(title: "Beta", body: "abcdefghij")
Profile.create!(article_id: a.id, bio: "via-includes")
rows = Article.including_profiles.order(:id).to_a
raise "alpha" unless rows[0].profile.bio == "via-includes"
raise "beta nil" unless rows[1].profile.nil?
puts "has_one includes passed"
"#,
        )
        .assert_passes();
}

/// Renamed association: `class_name:` + `foreign_key:` preloads under the
/// declared name, not the target class name.
#[test]
fn preload_honors_class_name_and_foreign_key() {
    let (path, from, to) = profile_schema_edit();
    emit_and_run::real_blog()
        .edit(path, from, to)
        .write(
            "app/models/profile.rb",
            "class Profile < ApplicationRecord\n  belongs_to :article\nend\n",
        )
        .edit(
            "app/models/article.rb",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy",
            "class Article < ApplicationRecord\n  has_many :comments, dependent: :destroy\n  has_one :spotlight, class_name: \"Profile\", foreign_key: :article_id\n  scope :with_spotlights, -> { preload(:spotlight) }",
        )
        .run_ruby(
            r#"
a = Article.create!(title: "Alpha", body: "abcdefghij")
b = Article.create!(title: "Beta", body: "abcdefghij")
Profile.create!(article_id: a.id, bio: "spot")
rows = Article.with_spotlights.order(:id).to_a
raise "spotlight" unless rows[0].spotlight.bio == "spot"
raise "missing is nil" unless rows[1].spotlight.nil?
puts "has_one preload class_name/foreign_key passed"
"#,
        )
        .assert_passes();
}

/// Scoped singular associations use their actual reader rather than an FK-only
/// batch that would erase the scope. Cache nil too; query counts may be N+1.
#[test]
fn scoped_has_one_preload_preserves_scope_and_memoizes_missing() {
    let (path, from, to) = profile_schema_edit();
    emit_and_run::real_blog()
        .edit(path, from, to)
        .write("app/models/profile.rb", "class Profile < ApplicationRecord\n  belongs_to :article\nend\n")
        .edit("app/models/article.rb", "  has_many :comments, dependent: :destroy",
              "  has_many :comments, dependent: :destroy\n  has_one :selected_profile, -> { where(bio: 'selected') }, class_name: 'Profile'\n  scope :with_selected_profile, -> { includes(:selected_profile) }")
        .run_ruby(r#"
a = Article.create!(title: 'Alpha', body: 'abcdefghij')
b = Article.create!(title: 'Beta', body: 'abcdefghij')
Profile.create!(article_id: a.id, bio: 'wrong')
p = Profile.create!(article_id: a.id, bio: 'selected')
Profile.create!(article_id: b.id, bio: 'wrong')
rows = Article.with_selected_profile.order(:id).to_a
repeated = Db.capture_sql do
  raise 'scope erased' unless rows[0].selected_profile.id == p.id
  raise 'missing scope result' unless rows[1].selected_profile.nil?
  raise 'missing memoization' unless rows.all?(&:selected_profile_loaded?)
  rows.each { |row| row.selected_profile }
end
raise 'repeat queried' unless repeated.empty?
puts 'scoped has_one read preloading passed'
"#).assert_passes();
}

/// A collection through a belongs_to is keyed from the real intermediate
/// record, not the owner's id. Preloaded readers remain Relations (including
/// a missing parent), with constraints intact when forked with where.
#[test]
fn belongs_to_through_collection_preserves_parent_key_and_relation_cache() {
    let (path, from, to) = profile_schema_edit();
    emit_and_run::real_blog()
        .edit(path, from, to)
        .edit("db/schema.rb", "  create_table \"articles\", force: :cascade do |t|",
              "  create_table \"articles\", force: :cascade do |t|\n    t.integer \"profile_id\"")
        .write("app/models/profile.rb", "class Profile < ApplicationRecord\n  belongs_to :article\n  has_many :notes, class_name: 'Comment', foreign_key: :article_id, primary_key: :article_id\nend\n")
        .edit("app/models/article.rb", "  has_many :comments, dependent: :destroy",
              "  has_many :comments, dependent: :destroy\n  belongs_to :profile, optional: true\n  has_many :related_comments, through: :profile, source: :notes\n  scope :with_related_comments, -> { includes(:related_comments) }")
        .run_ruby(r#"
a = Article.create!(title: 'Alpha', body: 'abcdefghij')
b = Article.create!(title: 'Beta', body: 'abcdefghij')
c = Article.create!(title: 'Gamma', body: 'abcdefghij')
p = Profile.create!(article_id: b.id, bio: 'parent')
a.profile_id = p.id
a.save!
x = Comment.create!(article_id: a.id, commenter: 'wrong', body: 'wrong owner')
y = Comment.create!(article_id: b.id, commenter: 'right', body: 'actual parent')
raise 'lazy parent FK' unless a.related_comments.to_a.map(&:id) == [y.id]
rows = Article.with_related_comments.order(:id).to_a
repeated = Db.capture_sql do
  raise 'cached relation' unless rows[0].related_comments.is_a?(ActiveRecord::Relation)
  raise 'parent key' unless rows[0].related_comments.to_a.map(&:id) == [y.id]
  raise 'nil parent' unless rows[1].related_comments.to_a.empty?
  raise 'missing memoization' unless rows.all?(&:related_comments_loaded?)
end
raise 'repeat queried' unless repeated.empty?
raise 'fork dropped parent constraint' unless rows[0].related_comments.where(id: x.id).to_a.empty?
raise 'fork lost actual row' unless rows[0].related_comments.where(id: y.id).to_a.map(&:id) == [y.id]
raise 'nil parent fork' unless rows[2].related_comments.where(id: y.id).to_a.empty?
puts 'belongs_to through read preloading passed'
"#).assert_passes();
}
