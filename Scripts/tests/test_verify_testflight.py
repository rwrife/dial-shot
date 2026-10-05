import unittest
from Scripts.verify_testflight import await_build, find_build


class TestTestFlightPoller(unittest.TestCase):
    def test_exact_build_only_and_encoded_filters(self):
        paths = []
        def request(path, token):
            paths.append(path)
            if path.startswith('/v1/apps?'):
                return {'data': [{'id': 'app-7'}]}
            return {'data': [
                {'id': 'wrong', 'attributes': {'version': '41', 'processingState': 'VALID'}},
                {'id': 'correct', 'attributes': {'version': '42', 'processingState': 'COMPLETE'}}]}
        self.assertEqual(await_build('com.infinityball.dialshot', '42', lambda: 'token',
                                     request=request), 'correct')
        self.assertIn('filter%5BbundleId%5D=com.infinityball.dialshot', paths[0])
        self.assertIn('filter%5Bapp%5D=app-7', paths[1])

    def test_processing_waits_then_invalid_fails(self):
        states = iter(['PROCESSING', 'INVALID'])
        def request(path, token):
            if path.startswith('/v1/apps?'):
                return {'data': [{'id': 'app'}]}
            return {'data': [{'id': 'build', 'attributes': {'version': '42',
                                'processingState': next(states)}}]}
        with self.assertRaisesRegex(RuntimeError, 'INVALID'):
            await_build('com.infinityball.dialshot', '42', lambda: 'token',
                        request=request, pause=lambda _: None)

    def test_no_app_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, 'one App Store Connect app'):
            await_build('com.infinityball.dialshot', '42', lambda: 'token',
                        request=lambda path, token: {'data': []})


if __name__ == '__main__':
    unittest.main()
