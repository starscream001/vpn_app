import unittest
from service import ApiError, Store


class ControlApiTests(unittest.TestCase):
    def setUp(self):
        self.store = Store(':memory:')
        self.store.provision('user', {'schema': 1, 'profiles': [{'id': 'owned'}], 'revoked_ids': []})

    def tearDown(self):
        self.store.db.close()

    def test_code_can_only_be_used_once(self):
        code = self.store.issue_code('user')
        token = self.store.exchange(code)['access_token']
        self.assertEqual(self.store.authorize(token), 'user')
        with self.assertRaises(ApiError):
            self.store.exchange(code)

    def test_expired_code_and_token_rejected(self):
        code = self.store.issue_code('user')
        self.store.db.execute('UPDATE codes SET expires=0')
        self.store.db.commit()
        with self.assertRaises(ApiError):
            self.store.exchange(code)
        with self.assertRaises(ApiError):
            self.store.authorize('invalid')

    def report(self):
        return {'schema': 1, 'reports': [{'profile_id': 'owned', 'protocol': 'amnezia',
                'ok': True, 'latency_ms': 42, 'rx_delta': 100, 'tx_delta': 50,
                'reason': 'https_204', 'at': '2026-11-10T00:00:00Z'}]}

    def test_quality_report_persisted(self):
        self.assertEqual(self.store.report('user', self.report()), {'accepted': 1})
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM reports').fetchone()[0], 1)

    def test_reject_secret_fields_and_unowned_profile(self):
        body = self.report()
        body['reports'][0]['private_key'] = 'never-store'
        with self.assertRaises(ApiError):
            self.store.report('user', body)
        body = self.report()
        body['reports'][0]['profile_id'] = 'someone-else'
        with self.assertRaises(ApiError):
            self.store.report('user', body)
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM reports').fetchone()[0], 0)

    def test_report_rate_limit(self):
        for _ in range(10):
            self.store.report('user', self.report())
        with self.assertRaises(ApiError) as caught:
            self.store.report('user', self.report())
        self.assertEqual(caught.exception.status, 429)
