#!/usr/bin/env python3
"""Browser assertion reporting must reject failures even without message text."""
import runpy
import unittest

browser = runpy.run_path('test/topic_browser_smoke.py')


class TopicBrowserFailureTest(unittest.TestCase):
    def test_empty_assertion_is_not_a_successful_browser_case(self):
        evidence = {}
        browser['record_failure'](evidence, AssertionError())
        self.assertEqual({'type': 'AssertionError', 'message': ''}, evidence['error'])
        with self.assertRaises(AssertionError):
            browser['assert_success'](evidence)

    def test_message_bearing_failure_is_preserved_and_rejected(self):
        evidence = {}
        browser['record_failure'](evidence, RuntimeError('actual browser failure'))
        self.assertEqual({'type': 'RuntimeError', 'message': 'actual browser failure'}, evidence['error'])
        with self.assertRaises(AssertionError):
            browser['assert_success'](evidence)

    def test_only_a_case_without_an_error_is_successful(self):
        browser['assert_success']({'topic_id': 5})
        with self.assertRaises(AssertionError):
            browser['assert_success']({'error': ''})


if __name__ == '__main__':
    unittest.main()
