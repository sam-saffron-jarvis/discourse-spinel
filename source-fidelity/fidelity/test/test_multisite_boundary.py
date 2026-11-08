import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from probe_core_multisite import validate_boundary
from probe_core_multisite_renderer import validate_renderer


class MultisiteBoundaryValidationTest(unittest.TestCase):
    def proof(self):
        # Checker-only input, not an application/provider fixture or native input.
        return {
            "successful_oracle": True, "final_same_namespace_object": True,
            "lifecycle": [
                {"order": 1, "current_db_present": False, "default_present": False,
                 "same_namespace_object": True, "source": ["/gem/namespace.rb", 1]},
                {"order": 2, "same_namespace_object": True, "safe_each_present": True,
                 "source": ["/core/lib/freedom_patches/rails_multisite.rb", 36]},
            ],
            "initializer_points": [
                {"order": 3, "event": "line", "safe_each_present": True, "source": ["/core/config/initializers/005-site_settings.rb", 17]},
                {"order": 5, "event": "b_call", "safe_each_present": True, "source": ["/core/config/initializers/005-site_settings.rb", 17]},
            ],
            "initializer_require_attempts": [
                {"order": 0, "target": "/core/lib/freedom_patches/rails_multisite.rb", "safe_each_present": False,
                 "source": ["/core/config/initializers/002-freedom_patches.rb", 6]},
                {"order": 4, "target": "/core/lib/freedom_patches/other.rb", "safe_each_present": True,
                 "source": ["/core/config/initializers/002-freedom_patches.rb", 11]},
            ],
            "freedom_patch_source_census": {"/core/lib/freedom_patches/rails_multisite.rb": "a" * 64,
                                           "/core/lib/freedom_patches/other.rb": "b" * 64},
            "callable_descriptors": {"current_db": {"arity": -1}, "safe_each_connection": {"source": ["/core/lib/freedom_patches/rails_multisite.rb", 13]}},
            "all_selected_return_types": [{"method": "instance", "module_value": False, "result_class": "RailsMultisite::ConnectionManagement::NullInstance"}],
        }

    def test_valid_source_lifecycle(self):
        validate_boundary(self.proof())

    def test_wrong_order_identity_arity_or_class_value_fails(self):
        for mutate in (
            lambda p: p["lifecycle"][-1].update(order=4),
            lambda p: p.update(final_same_namespace_object=False),
            lambda p: p["lifecycle"][0].update(current_db_present=True),
            lambda p: p["initializer_points"][0].update(safe_each_present=False),
            lambda p: p["callable_descriptors"]["current_db"].update(arity=0),
            lambda p: p["all_selected_return_types"][0].update(module_value=True),
            lambda p: p["initializer_require_attempts"].pop(),
            lambda p: p["initializer_require_attempts"][0].update(safe_each_present=True),
            lambda p: p["initializer_require_attempts"][-1].update(order=2),
            lambda p: p["initializer_points"][-1].update(order=3),
            lambda p: p["initializer_require_attempts"][-1].update(target="/core/lib/freedom_patches/rails_multisite.rb"),
            lambda p: p["freedom_patch_source_census"].update({"/core/lib/freedom_patches/missing.rb": "c" * 64}),
        ):
            proof = copy.deepcopy(self.proof())
            mutate(proof)
            with self.assertRaises(AssertionError):
                validate_boundary(proof)


class MultisiteRendererValidationTest(unittest.TestCase):
    def proof(self):
        # CHECKER-ONLY data, not a provider, saved oracle input or native fixture.
        rows = []
        for branch in (False, True):
            rows += [
                {"branch": branch, "callbacks": [["checker-site", "String", True]],
                 "returned": "callback_result", "nonlocal": ["checker-site", "String"]},
                {"branch": branch, "no_block": None, "block_break": "block_break_result",
                 "caught_throw": ["checker-site", "String"]},
            ]
            for error in ("PG::ConnectionBad", "PG::UnableToSend", "PG::ServerError", "ArgumentError"):
                rows.append({"branch": branch, "rescued_error": error,
                             "callbacks": [["checker-site", "String"]], "returned": None})
            rows[-1]["genuine_stderr_puts"] = [[True, "puts"]]
        rows.append({"lookup_result": "checker-only", "lookup_class": "String",
                     "literal_frozen": True, "other_path": None})
        return {"results": rows, "descriptors": {
            "safe_each_connection": {"arity": 0, "parameters": []},
            "each_active_connection": {"arity": 0, "parameters": [["block", "blk"]]},
        }, "genuine_error_lines": [
            "URGENT: Failed to initialize site checker-site: ArgumentError isolated standard callback fault"] * 2}

    def test_complete_renderer_control(self):
        validate_renderer(self.proof())

    def test_dropped_or_changed_callback_lifetime_error_or_descriptor_fails(self):
        for mutate in (
            lambda p: p["results"].pop(2),
            lambda p: p["results"][6].update(branch=False),
            lambda p: p["results"][0].update(returned="lost"),
            lambda p: p["results"][0].update({"nonlocal": ["wrong-site", "String"]}),
            lambda p: p["results"][1].update(block_break=None),
            lambda p: p["results"][1].update(caught_throw=None),
            lambda p: p["results"][2].update(rescued_error="wrong"),
            lambda p: p["results"][3].update(returned="continued"),
            lambda p: p["results"][4].update(callbacks=[]),
            lambda p: p["results"][5].update(genuine_stderr_puts=[]),
            lambda p: p["descriptors"]["safe_each_connection"].update(arity=-1),
            lambda p: p["genuine_error_lines"].__setitem__(0, "truncated"),
            lambda p: p["results"][-1].update(literal_frozen=False),
        ):
            proof = copy.deepcopy(self.proof())
            mutate(proof)
            with self.assertRaises(AssertionError):
                validate_renderer(proof)


if __name__ == "__main__":
    unittest.main()
