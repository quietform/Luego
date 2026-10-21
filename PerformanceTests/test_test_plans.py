import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).parent


class TestPlanTests(unittest.TestCase):
    def test_manual_plan_is_explicit_and_selects_only_profiler_tests(self):
        scheme = ET.parse(ROOT / "LuegoPerformance.xcodeproj/xcshareddata/xcschemes/LuegoPerformance.xcscheme")
        references = scheme.findall("./TestAction/TestPlans/TestPlanReference")
        manual_plans = [ref for ref in references if ref.attrib.get("default") != "YES"]
        self.assertEqual(len(manual_plans), 1, "An explicit profiling plan must remain available")
        plan = json.loads((ROOT / manual_plans[0].attrib["reference"].removeprefix("container:")).read_text())
        methods = re.findall(r"func (test\w+WithProfiler)\(", (ROOT / "UITests/ReaderHitchTests.swift").read_text())
        target = plan["testTargets"][0]
        self.assertEqual(set(target["selectedTests"]) - set(target.get("skippedTests", [])),
                         {f"ReaderHitchTests/{name}()" for name in methods})
        default = json.loads((ROOT / "ReaderHitches.xctestplan").read_text())
        self.assertEqual(plan["defaultOptions"], default["defaultOptions"])

    def test_default_plan_excludes_manual_checkpoints(self):
        methods = set(re.findall(r"func (test\w+)\(", (ROOT / "UITests/ReaderHitchTests.swift").read_text()))
        manual = {f"ReaderHitchTests/{name}()" for name in methods if name.endswith("WithProfiler")}
        automatic = {f"ReaderHitchTests/{name}()" for name in methods if not name.endswith("WithProfiler")}
        self.assertTrue(manual)
        self.assertTrue(automatic)
        scheme = ET.parse(ROOT / "LuegoPerformance.xcodeproj/xcshareddata/xcschemes/LuegoPerformance.xcscheme")
        defaults = scheme.findall("./TestAction/TestPlans/TestPlanReference[@default='YES']")
        self.assertEqual(len(defaults), 1)
        plan = json.loads((ROOT / defaults[0].attrib["reference"].removeprefix("container:")).read_text())
        target = plan["testTargets"][0]
        selected = set(target.get("selectedTests", manual | automatic)) - set(target.get("skippedTests", []))
        self.assertEqual(selected & manual, set(), "Default Run All must never await a manual recorder checkpoint")
        self.assertEqual(selected & automatic, automatic)


if __name__ == "__main__":
    unittest.main()
