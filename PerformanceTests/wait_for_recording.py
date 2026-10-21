import argparse
import ctypes
import math
import sys
import time


def wait_for_recording(name, timeout):
    library = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    token = ctypes.c_int()
    changed = ctypes.c_int()
    if library.notify_register_check(name.encode(), ctypes.byref(token)) != 0:
        raise RuntimeError("Unable to register recording notification")
    try:
        def check():
            if library.notify_check(token, ctypes.byref(changed)) != 0:
                raise RuntimeError("Unable to read recording notification")
            return changed.value != 0

        check()
        print("HOST_LISTENER_READY", flush=True)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if check():
                print("RECORDING_STARTED", flush=True)
                return
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        raise TimeoutError("Timed out waiting for the recorder; do not release the device checkpoint")
    finally:
        library.notify_cancel(token)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("notification")
    parser.add_argument("--timeout", type=float, default=45)
    arguments = parser.parse_args()
    if not math.isfinite(arguments.timeout) or arguments.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    try:
        wait_for_recording(arguments.notification, arguments.timeout)
    except (RuntimeError, TimeoutError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
