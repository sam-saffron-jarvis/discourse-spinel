"""Typed comparison of actual supported request lifetime effects.

This does not accept reloading, the generic executor registry, optional
middleware profiles, streaming bodies, full query/options or a browser page.
"""


def require_query_cache_lifecycle(reference, candidate):
    expected = reference["query_cache_enabled_during_controller"]
    observed = candidate["query_cache_enabled_during_controller"]
    assert type(expected) is bool and type(observed) is bool, "request query-cache state must be a boolean"
    assert reference["executor_active_during_controller"] is True
    assert reference["executor_active_after_response_close"] is False
    assert reference["reloader_active_during_controller"] is False, "reloading profile is not supported"
    assert not reference["action_dispatch_callbacks"], "configured request callbacks require actual implementation, not omission"
    if expected != observed:
        raise AssertionError(
            "original request query-cache executor hook is not implemented: "
            f"during controller expected={expected!r}, candidate={observed!r}; "
            "ActiveRecord::QueryCache::ExecutorHooks.run/complete and the response-close boundary must execute")
    assert candidate["query_cache_enabled_after_response"] is False, "request query cache leaked past response completion"


def require_context_and_queries_lifecycle(reference, candidate):
    """Compare actual entry/held-instance/session/cleanup effects, not hook labels."""
    for phase, keys in (
        ("during_controller", ("ambient_context_absent", "query_session_active", "interlock_owned_during_controller", "interlock_owned_at_context_push", "active_connection_during_controller", "single_configured_pool")),
        ("after_response", ("held_instances_reset", "registered_instances_removed", "execution_context_popped",
                            "event_context_cleared", "query_session_finalized", "query_session_released", "interlock_released", "connection_lease_released", "query_session_completed_before_pool")),
    ):
        field = "context_and_queries_" + phase
        for key in keys:
            expected = reference[field][key]
            actual = candidate[field][key]
            assert type(expected) is bool and type(actual) is bool, f"{field}.{key} must be boolean"
            if key != "active_connection_during_controller":
                assert expected is True, f"original context/session applicability changed: {field}.{key}={expected!r}"
            assert actual == expected, f"actual context/session lifecycle mismatch: {field}.{key}: {actual!r} != {expected!r}"
