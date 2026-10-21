from pathlib import Path
import selectors
import subprocess
import sys
import unittest
import uuid


SCRIPT = Path(__file__).with_name("wait_for_recording.py")


@unittest.skipUnless(sys.platform == "darwin", "Darwin notifications require macOS")
class RecordingNotificationTests(unittest.TestCase):
    def test_waits_for_real_notification_after_registration(self):
        name = f"com.esoxjem.Luego.test.{uuid.uuid4()}"
        process = subprocess.Popen([sys.executable, "-B", str(SCRIPT), name, "--timeout", "5"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                self.assertTrue(selector.select(timeout=5), "Listener must acknowledge registration")
                self.assertEqual(process.stdout.readline().strip(), "HOST_LISTENER_READY")
                self.assertFalse(selector.select(timeout=0.15), "Registration alone must not release the checkpoint")
            subprocess.run(["notifyutil", "-p", name], check=True, capture_output=True, timeout=5)
            output, errors = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(output.strip(), "RECORDING_STARTED")
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()

    def test_missing_notification_fails_without_releasing_checkpoint(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT),
                                 f"com.esoxjem.Luego.test.{uuid.uuid4()}", "--timeout", "0.15"],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), "HOST_LISTENER_READY")
        self.assertIn("Timed out", result.stderr)


if __name__ == "__main__":
    unittest.main()
