"""Synthetic inputs only: do not paste real credentials or user data into fixtures."""
import importlib.util
import pathlib
import plistlib
import unittest

script = pathlib.Path(__file__).resolve().parents[1] / "Scripts/privacy-check.py"
spec = importlib.util.spec_from_file_location("privacy_check", script)
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyTests(unittest.TestCase):
    def test_clean_source(self):
        self.assertEqual(privacy.inspect("Sources/Example.swift", b"import Foundation\n"), [])

    def test_personal_email(self):
        value = b"person" + b"@" + b"example.invalid"
        self.assertIn("email other than GitHub noreply", privacy.inspect("README.md", value))

    def test_noreply_email(self):
        value = b"123+example" + b"@" + b"users.noreply.github.com"
        self.assertEqual(privacy.inspect("CONTRIBUTING.md", value), [])

    def test_github_automation_identity(self):
        value = b"noreply" + b"@" + b"github.com"
        self.assertIsNotNone(privacy.NOREPLY.fullmatch(value))

    def test_home_path(self):
        value = b"/Users" + b"/example/project"
        self.assertIn("personal home path", privacy.inspect("Scripts/build.sh", value))

    def test_private_key(self):
        value = b"-----BEGIN " + b"PRIVATE KEY-----"
        self.assertIn("private key", privacy.inspect("README.md", value))

    def test_token(self):
        value = b"ghp_" + b"A" * 36
        self.assertIn("GitHub credential", privacy.inspect("Sources/Example.swift", value))

    def test_vocabulary_and_builds(self):
        for path in ["Vocabulary.json", "Resources/Vocabulary.json", ".build/Poseboard", "Captures/hand.png", "UserData/notes.md"]:
            self.assertTrue(privacy.inspect(path, b"{}"), path)

    def test_symlink(self):
        self.assertIn("symlink or non-regular file", privacy.inspect("Sources/Example.swift", b"", "120000"))

    def test_binary_and_size(self):
        self.assertIn("binary file", privacy.inspect("Sources/Example.swift", b"\0\xff"))
        self.assertIn("oversized source file", privacy.inspect("Sources/Example.swift", b"a" * 512_001))

    def test_camera_only_permissions(self):
        path = "Resources/Poseboard.entitlements"
        self.assertEqual(privacy.inspect(path, plistlib.dumps(privacy.ENTITLEMENTS)), [])
        extra = {**privacy.ENTITLEMENTS, "com.apple.security.network.client": True}
        self.assertIn("unexpected app permissions", privacy.inspect(path, plistlib.dumps(extra)))


if __name__ == "__main__":
    unittest.main()
