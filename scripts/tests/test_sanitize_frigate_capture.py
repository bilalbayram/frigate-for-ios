"""Tests for scripts/sanitize-frigate-capture. Run: python3 -I -m unittest discover -s scripts/tests"""

import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "sanitize-frigate-capture"
loader = importlib.machinery.SourceFileLoader("sanitize_frigate_capture", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
sanitizer = importlib.util.module_from_spec(spec)
loader.exec_module(sanitizer)

SECRETS = [
    "front_door_cam", "Backyard", "driveway_zone", "family_group", "AB12CDE", "Alice Smith",
    "10.20.30.40", "nvr.home.example", "hunter2", "1700000000.1-abcdef", "c2VjcmV0aW1hZ2VieXRlcw==",
    "mqtt.home.example", "owner@example.org",
]


def write_capture(directory: Path) -> None:
    files = {
        "version": "0.18.2-abc1234",
        "config": {
            "version": "0.18-0",
            "mqtt": {"enabled": True, "host": "mqtt.home.example", "user": "owner@example.org", "password": "hunter2"},
            "auth": {"enabled": True, "roles": {"admin": [], "viewer": []}},
            "go2rtc": {"streams": {"front_door_cam": ["rtsp://admin:hunter2@10.20.30.40:554/stream"]}},
            "camera_groups": {"family_group": {"cameras": ["front_door_cam"], "icon": "LuHouse", "order": 1}},
            "cameras": {
                "front_door_cam": {
                    "name": "front_door_cam", "enabled": True,
                    "ffmpeg": {"inputs": [{"path": "rtsp://admin:hunter2@10.20.30.40:554/stream", "roles": ["detect"]}]},
                    "onvif": {"host": "10.20.30.40", "port": 80, "user": "admin", "password": "hunter2"},
                    "zones": {"driveway_zone": {"coordinates": "0,0,1,1"}},
                    "live": {"streams": {"main": "front_door_cam"}},
                    "review": {"alerts": {"labels": ["person"], "required_zones": ["driveway_zone"]}},
                    "unknown_future_field": "nvr.home.example",
                },
                "Backyard": {"name": "Backyard", "enabled": False, "live": {"streams": {"main": "Backyard"}}},
            },
        },
        "review_limit_50": [{
            "id": "1700000000.1-abcdef", "camera": "front_door_cam", "start_time": 1_700_000_000.1, "end_time": None,
            "severity": "alert", "has_been_reviewed": False,
            "thumb_path": "/media/frigate/clips/review/thumb-front_door_cam-1700000000.1-abcdef.webp",
            "data": {"objects": ["person"], "zones": ["driveway_zone"], "sub_labels": ["Alice Smith"],
                     "detections": ["1700000000.1-abcdef"], "audio": []},
        }],
        "review_summary": {"last24Hours": {"total_alert": 1}, "2023-11-14": {"day": "2023-11-14", "total_alert": 1}},
        "events_limit_50": [{
            "id": "1700000000.1-abcdef", "camera": "front_door_cam", "label": "car", "sub_label": ["AB12CDE", 0.93],
            "zones": ["driveway_zone"], "start_time": 1_700_000_000.1, "end_time": 1_700_000_050.0,
            "thumbnail": "c2VjcmV0aW1hZ2VieXRlcw==", "has_clip": True, "has_snapshot": True,
        }],
        "timeline_limit_50": [{"timestamp": 1_700_000_001.0, "camera": "front_door_cam", "source": "tracked_object",
                               "source_id": "1700000000.1-abcdef", "class_type": "visible",
                               "data": {"label": "car", "sub_label": "AB12CDE"}}],
        "recognized_license_plates": ["AB12CDE"],
        "sub_labels": ["Alice Smith"],
        "go2rtc_streams": {"front_door_cam": {"producers": [{"url": "rtsp://admin:hunter2@10.20.30.40:554/stream"}]}},
        "stats": {"cameras": {"front_door_cam": {"camera_fps": 5.0, "pid": 123}},
                  "cpu_usages": {"123": {"cmdline": "ffmpeg -i rtsp://admin:hunter2@10.20.30.40"}},
                  "service": {"version": "0.18.2-abc1234", "storage": {"/media/frigate": {}}}},
        "recordings_storage": {"front_door_cam": {"usage": 1.0}},
    }
    for name, value in files.items():
        (directory / f"{name}.json").write_text(value if isinstance(value, str) else json.dumps(value))


class SanitizeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.raw = Path(self.tmp.name)
        write_capture(self.raw)
        self.out, self.renamer = sanitizer.sanitize(self.raw)
        self.text = json.dumps(self.out)

    def tearDown(self):
        self.tmp.cleanup()

    def test_no_planted_secret_survives(self):
        for secret in SECRETS:
            self.assertNotIn(secret.lower(), self.text.lower(), secret)
        self.assertEqual(sanitizer.leaks(self.out, self.renamer), [])

    def test_unknown_and_credential_fields_are_dropped(self):
        camera = self.out["config"]["cameras"]["camera_1"]
        self.assertNotIn("ffmpeg", camera)
        self.assertNotIn("unknown_future_field", camera)
        self.assertNotIn("password", camera["onvif"])
        self.assertEqual(self.out["config"]["mqtt"], {"enabled": True})
        self.assertNotIn("cpu_usages", self.out["stats"])
        self.assertNotIn("thumbnail", self.out["events"][0])

    def test_references_stay_consistent(self):
        review, event, timeline = self.out["review"][0], self.out["events"][0], self.out["timeline"][0]
        self.assertEqual(review["camera"], "camera_1")
        self.assertEqual(review["data"]["detections"], [event["id"]])
        self.assertEqual(timeline["source_id"], event["id"])
        self.assertEqual(review["data"]["zones"], ["zone_1"])
        self.assertEqual(self.out["config"]["cameras"]["camera_1"]["live"]["streams"], {"main": "camera_1"})
        self.assertEqual(self.out["config"]["camera_groups"]["group_1"]["cameras"], ["camera_1"])
        self.assertEqual(list(self.out["go2rtc_streams"]), ["camera_1"])

    def test_plates_become_test_plates_everywhere(self):
        self.assertEqual(self.out["recognized_license_plates"], ["TEST001"])
        self.assertEqual(self.out["events"][0]["sub_label"], ["TEST001", 0.93])
        self.assertEqual(self.out["timeline"][0]["data"]["sub_label"], "TEST001")

    def test_times_and_days_shift_together(self):
        shifted = self.out["review"][0]["start_time"]
        self.assertGreater(shifted, 1_890_000_000)
        days = [k for k in self.out["review_summary"] if k != "last24Hours"]
        self.assertEqual(len(days), 1)
        self.assertTrue(days[0].startswith("2029-"), days[0])

    def test_leak_check_catches_a_survivor(self):
        self.renamer.sensitive.add("leftover_camera")
        self.out["config"]["cameras"]["camera_1"]["name"] = "leftover_camera"
        self.assertEqual(sanitizer.leaks(self.out, self.renamer), ["leftover_camera"])


if __name__ == "__main__":
    unittest.main()
