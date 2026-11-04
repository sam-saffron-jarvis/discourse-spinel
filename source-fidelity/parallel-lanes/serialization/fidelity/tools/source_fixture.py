"""Read-only source-scope TEST data, never an implementation of Topic queries.

Every column is projected from an actual seed row except deliberately varied
predicate/NULL/type inputs. The original scope lambdas filter this derived table.
No schema/rows/settings are created on PostgreSQL. Synthetic rows are explicitly
labelled fixture observations, separate from the nonempty live-row evidence.
"""
import json


def source_fixture(columns, category_security=False):
    replacements = {
        "id": "controls.case_id",
        "archetype": "controls.archetype",
        "visible": "controls.visible",
        "deleted_at": "controls.deleted_at",
        "category_id": "CASE controls.category_mode WHEN 1 THEN NULL::integer WHEN 2 THEN -987654321 ELSE seed.category_id END",
        "title": "'Fidelity O''Reilly? \\ literal'::varchar",
        "score": "CASE WHEN controls.case_id = 110 THEN NULL::float8 ELSE -0.5::float8 END",
        "percent_rank": "1.25::float8",
        "excerpt": "CASE WHEN controls.case_id = 110 THEN NULL::varchar ELSE 'quote '' and ?'::varchar END",
        "user_id": "CASE WHEN controls.case_id = 110 THEN NULL::integer ELSE seed.user_id END",
        "created_at": "TIMESTAMP '2024-02-03 04:05:06.123456'",
    }
    if category_security:
        replacements["category_id"] = "CASE controls.category_mode WHEN 1 THEN NULL::integer WHEN 2 THEN -987654321 WHEN 3 THEN (SELECT id FROM public.categories WHERE read_restricted ORDER BY id LIMIT 1) ELSE seed.category_id END"
    selected = [f'{replacements.get(col, "seed." + col)} AS "{col}"' for col in columns]
    cases = [
        (101, "regular", "TRUE", "NULL", 0, "included regular"),
        (102, "private_message", "TRUE", "NULL", 0, "excluded by original listable_topics"),
        (103, "regular", "FALSE", "NULL", 0, "excluded by original visible"),
        (104, None, "TRUE", "NULL", 0, "excluded: SQL NULL archetype is not != private_message"),
        (105, "banner", "TRUE", "NULL", 0, "included non-private non-default archetype"),
        (106, "regular", "TRUE", "TIMESTAMP '2020-01-01'", 0, "excluded by original Trashable default_scope"),
        (107, "regular", "NULL", "NULL", 0, "excluded: NULL visible"),
        (108, "regular", "TRUE", "NULL", 1, "included with NULL category_id; loaded nil association"),
        (109, "regular", "TRUE", "NULL", 2, "included dangling category_id; loaded nil association"),
        (110, "regular", "TRUE", "NULL", 0, "included nullable scalar fields"),
    ]
    if category_security:
        cases += [(111, "regular", "TRUE", "NULL", 3, "excluded by original anonymous category permission"),
                  (112, "private_message", "TRUE", "NULL", 3, "excluded private message in restricted category"),
                  (113, "regular", "TRUE", "TIMESTAMP '2020-01-01'", 1, "excluded deleted topic with NULL category")]
    values = []
    for case, archetype, visible, deleted, category, _ in cases:
        arch = "NULL::text" if archetype is None else "'" + archetype + "'::text"
        values.append(f"({case},{arch},{visible}::boolean,{deleted}::timestamp,{category})")
    sql = "SELECT " + ", ".join(selected) + " FROM (SELECT * FROM public.topics WHERE category_id IS NOT NULL ORDER BY id LIMIT 1) seed CROSS JOIN (VALUES " + ", ".join(values) + ") controls(case_id,archetype,visible,deleted_at,category_mode)"
    if category_security:
        # Select real unrestricted/restricted categories, never a saved/canned
        # allow-list. Guardian still reads the actual Category table itself.
        sql = sql.replace("SELECT * FROM public.topics WHERE category_id IS NOT NULL ORDER BY id LIMIT 1", "SELECT topics.* FROM public.topics JOIN public.categories ON categories.id = topics.category_id WHERE categories.read_restricted = FALSE ORDER BY topics.id LIMIT 1")
    manifest = {"kind": "SELECT-only derived TEST fixture", "cases": [{"id": row[0], "purpose": row[5]} for row in cases],
                "expected_ids": [101, 105, 108, 109, 110], "wrong_scope_expected_ids": [101, 103, 105, 107, 108, 109, 110],
                "source_predicates": ["app/models/topic.rb:371", "app/models/topic.rb:375", "app/models/concerns/trashable.rb:7"],
                "sql": sql}
    if category_security:
        for case in manifest["cases"]:
            if case["id"] == 103:
                case["purpose"] = "included false visibility: .visible is outside this partial original expression"
            elif case["id"] == 107:
                case["purpose"] = "included NULL visibility: strict parity must not accept hydration as false"
        manifest.update(expected_ids=[101, 103, 105, 107, 108, 109, 110],
                        wrong_scope_expected_ids=[101, 103, 105, 107, 108, 109, 110, 111],
                        source_predicates=["app/models/topic.rb:371", "app/models/concerns/trashable.rb:7", "lib/guardian/topic_guardian.rb:272-286", "lib/guardian/category_guardian.rb:61-67"],
                        limitation="Anonymous original security slice only; no original visible call in projected statements, so false/NULL visibility remains")
        return "", manifest
    methods = '''
  def self.fixture_relation
    Topic.listable_topics.visible.from(%s).order("topics.id ASC").includes(:category)
  end
  # Deliberately wrong TEST consumer: original scope declaration is unchanged.
  # Omitting visible must be detected by comparison against the real oracle.
  def self.wrong_scope_relation
    Topic.listable_topics.from(%s).order("topics.id ASC").includes(:category)
  end
''' % (json.dumps("(" + sql + ") AS topics"), json.dumps("(" + sql + ") AS topics"))
    return methods, manifest
