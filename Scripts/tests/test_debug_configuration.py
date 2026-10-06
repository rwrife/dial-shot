"""Keep UI automation compiled in Debug, never in Release."""
from pathlib import Path
import re
import unittest

PROJECT = Path(__file__).resolve().parents[2] / "DialShot.xcodeproj/project.pbxproj"


class DebugConfigurationTests(unittest.TestCase):
    def test_project_debug_defines_debug_condition(self):
        text = PROJECT.read_text()
        # Project-level configurations provide the inherited Swift settings.
        configurations = re.findall(
            r'/\* (Debug|Release) \*/ = \{isa = XCBuildConfiguration; '
            r'buildSettings = \{([^}]+)\}; name = \1;\};', text)
        self.assertEqual({name for name, _ in configurations}, {"Debug", "Release"})
        for name, settings in configurations:
            if name == "Debug":
                self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) DEBUG";', settings)
            else:
                self.assertNotIn("DEBUG", settings)
        # A target-level override could silently disable the inherited hook.
        self.assertEqual(text.count("SWIFT_ACTIVE_COMPILATION_CONDITIONS"), 1)


if __name__ == "__main__":
    unittest.main()
