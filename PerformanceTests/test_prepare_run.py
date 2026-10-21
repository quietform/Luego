import unittest

from prepare_run import prepare


class PrepareRunTests(unittest.TestCase):
    def test_disables_exported_checkers_without_removing_test_injection(self):
        target = {
            "IsUITestBundle": True,
            "TestingEnvironmentVariables": {
                "DYLD_INSERT_LIBRARIES": "/usr/lib/libMainThreadChecker.dylib:/usr/lib/libRPAC.dylib:/usr/lib/libXCTestBundleInject.dylib",
                "XCODE_SCHEME_NAME": "LuegoPerformance",
            },
            "UITargetAppEnvironmentVariables": {"APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore"},
            "UITargetAppMainThreadCheckerEnabled": True,
            "UITargetAppPerformanceAntipatternCheckerEnabled": True,
            "SystemAttachmentLifetime": "deleteOnSuccess",
        }
        configuration = {"TestConfigurations": [{"TestTargets": [target]}]}

        prepared = prepare(configuration)["TestConfigurations"][0]["TestTargets"][0]

        self.assertFalse(prepared["UITargetAppMainThreadCheckerEnabled"])
        self.assertFalse(prepared["UITargetAppPerformanceAntipatternCheckerEnabled"])
        self.assertEqual(prepared["TestingEnvironmentVariables"]["DYLD_INSERT_LIBRARIES"], "/usr/lib/libXCTestBundleInject.dylib")
        self.assertEqual(prepared["TestingEnvironmentVariables"]["XCODE_SCHEME_NAME"], "LuegoPerformance")
        self.assertEqual(prepared["UITargetAppEnvironmentVariables"], {"APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore"})
        self.assertEqual(prepared["SystemAttachmentLifetime"], "keepNever")
        self.assertEqual(prepared["UserAttachmentLifetime"], "keepAlways")


if __name__ == "__main__":
    unittest.main()
