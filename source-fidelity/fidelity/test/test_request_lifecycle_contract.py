import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from request_lifecycle_contract import require_query_cache_lifecycle, require_context_and_queries_lifecycle


class RequestLifecycleContractTests(unittest.TestCase):
    def test_every_actual_context_and_session_effect_is_required_and_typed(self):
        reference = {"context_and_queries_during_controller": {"ambient_context_absent": True, "query_session_active": True, "interlock_owned_during_controller": True, "interlock_owned_at_context_push": True, "active_connection_during_controller": True, "single_configured_pool": True},
            "context_and_queries_after_response": {key: True for key in ("held_instances_reset", "registered_instances_removed",
                "execution_context_popped", "event_context_cleared", "query_session_finalized", "query_session_released", "interlock_released", "connection_lease_released", "query_session_completed_before_pool")}}
        require_context_and_queries_lifecycle(reference, reference)
        later = copy.deepcopy(reference)
        later["context_and_queries_during_controller"]["active_connection_during_controller"] = False
        require_context_and_queries_lifecycle(later, later)
        with self.assertRaises(AssertionError):
            require_context_and_queries_lifecycle(reference, later)
        for field, effects in reference.items():
            for key in effects:
                for value in (False, 1, None):
                    wrong = copy.deepcopy(reference)
                    wrong[field][key] = value
                    with self.assertRaises(AssertionError):
                        require_context_and_queries_lifecycle(reference, wrong)

    def test_missing_wrong_typed_leaked_or_mutated_scope_is_rejected(self):
        reference = {"query_cache_enabled_during_controller": True,
            "executor_active_during_controller": True, "executor_active_after_response_close": False,
            "reloader_active_during_controller": False, "action_dispatch_callbacks": []}
        candidate = {"query_cache_enabled_during_controller": True, "query_cache_enabled_after_response": False}
        require_query_cache_lifecycle(reference, candidate)
        for key, value in (("query_cache_enabled_during_controller", False),
                           ("query_cache_enabled_during_controller", 1),
                           ("query_cache_enabled_after_response", True)):
            wrong = {**candidate, key: value}
            with self.assertRaises(AssertionError):
                require_query_cache_lifecycle(reference, wrong)
        for key, value in (("executor_active_during_controller", False),
                           ("executor_active_after_response_close", True),
                           ("reloader_active_during_controller", True),
                           ("action_dispatch_callbacks", ["must-run"])):
            wrong = copy.deepcopy(reference)
            wrong[key] = value
            with self.assertRaises(AssertionError):
                require_query_cache_lifecycle(wrong, candidate)


if __name__ == "__main__":
    unittest.main()
