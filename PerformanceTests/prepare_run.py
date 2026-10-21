import argparse
import plistlib
from pathlib import Path


def prepare(configuration):
    checker_libraries = {"libMainThreadChecker.dylib", "libRPAC.dylib"}
    for test_configuration in configuration["TestConfigurations"]:
        for target in test_configuration["TestTargets"]:
            target["UITargetAppMainThreadCheckerEnabled"] = False
            target["UITargetAppPerformanceAntipatternCheckerEnabled"] = False
            target["SystemAttachmentLifetime"] = "keepNever"
            target["UserAttachmentLifetime"] = "keepAlways"
            for key in ("TestingEnvironmentVariables", "UITargetAppEnvironmentVariables"):
                environment = target[key]
                libraries = [library for library in environment.get("DYLD_INSERT_LIBRARIES", "").split(":") if library and Path(library).name not in checker_libraries]
                if libraries:
                    environment["DYLD_INSERT_LIBRARIES"] = ":".join(libraries)
                else:
                    environment.pop("DYLD_INSERT_LIBRARIES", None)
    return configuration


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("xctestrun", type=Path)
    arguments = parser.parse_args()
    configuration = plistlib.loads(arguments.xctestrun.read_bytes())
    arguments.xctestrun.write_bytes(plistlib.dumps(prepare(configuration)))
