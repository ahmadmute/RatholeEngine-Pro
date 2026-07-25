#!/usr/bin/env python3
"""test_hub.py — task 8: barresi build_node_cmd adaptive allow-list + input validation"""
import sys, os, unittest, importlib.util, types

# ---- hub.py ra load mikonim bedoon ajra-ye main ----
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
HUB_PATH = os.path.join(REPO_ROOT, "rathole-manager", "ratholehub", "hub.py")

def _load_hub():
    spec = importlib.util.spec_from_file_location("hub", HUB_PATH)
    mod = importlib.util.module_from_spec(spec)
    # stub environment so hub doesn't try to read config files
    import io
    os.environ.setdefault("RATHOLEHUB_MOCK", "1")
    os.environ.setdefault("RATHOLEHUB_CONF", "/dev/null")
    os.environ.setdefault("RATHOLEHUB_INV",  "/dev/null")
    spec.loader.exec_module(mod)
    return mod

hub = _load_hub()
build_node_cmd = hub.build_node_cmd
WRITE_ACTIONS  = hub.WRITE_ACTIONS


class TestAdaptiveAllowList(unittest.TestCase):

    # --- adaptive_off: bedoon arg ---
    def test_adaptive_off_no_args(self):
        self.assertEqual(build_node_cmd("adaptive_off", {}),
                         ["ratholenode", "adaptive", "off"])

    # --- adaptive_status: read-only ---
    def test_adaptive_status(self):
        self.assertEqual(build_node_cmd("adaptive_status", {}),
                         ["ratholenode", "adaptive", "status"])

    # --- adaptive_test: --json bayad ezafe shavad ---
    def test_adaptive_test_json(self):
        self.assertEqual(build_node_cmd("adaptive_test", {}),
                         ["ratholenode", "adaptive", "test", "--json"])

    # --- adaptive_on: motabar ---
    def test_adaptive_on_valid(self):
        self.assertEqual(
            build_node_cmd("adaptive_on", {"interval": "30", "failures": "3", "recoveries": "5"}),
            ["ratholenode", "adaptive", "on", "--interval", "30", "--failures", "3", "--recoveries", "5"],
        )

    # --- adaptive_on: injection dar interval ---
    def test_adaptive_on_injection_interval(self):
        self.assertIsNone(build_node_cmd("adaptive_on", {"interval": "30;id", "failures": "3", "recoveries": "5"}))

    # --- adaptive_on: injection dar failures ---
    def test_adaptive_on_injection_failures(self):
        self.assertIsNone(build_node_cmd("adaptive_on", {"interval": "30", "failures": "3$(id)", "recoveries": "5"}))

    # --- adaptive_on: meghdar-e ghayr-adadi ---
    def test_adaptive_on_non_numeric(self):
        self.assertIsNone(build_node_cmd("adaptive_on", {"interval": "abc", "failures": "3", "recoveries": "5"}))

    # --- adaptive_on: khaali (default-ha lazem ast) ---
    def test_adaptive_on_defaults(self):
        cmd = build_node_cmd("adaptive_on", {})
        # bayad default-ha ra estefade konad (30, 3, 5)
        self.assertIsNotNone(cmd)
        self.assertIn("--interval", cmd)
        self.assertIn("30", cmd)

    # --- adaptive_off dar WRITE_ACTIONS ast ---
    def test_adaptive_off_in_write_actions(self):
        self.assertIn("adaptive_off", WRITE_ACTIONS)

    # --- adaptive_on dar WRITE_ACTIONS ast ---
    def test_adaptive_on_in_write_actions(self):
        self.assertIn("adaptive_on", WRITE_ACTIONS)

    # --- adaptive_status NIST dar WRITE_ACTIONS (read-only) ---
    def test_adaptive_status_not_in_write_actions(self):
        self.assertNotIn("adaptive_status", WRITE_ACTIONS)

    # --- adaptive_test NIST dar WRITE_ACTIONS ---
    def test_adaptive_test_not_in_write_actions(self):
        self.assertNotIn("adaptive_test", WRITE_ACTIONS)

    # --- JSON namotabar bayad field-e amn bargardanad ---
    def test_parse_adaptive_state_malformed(self):
        """parse_adaptive_state (agar vojood darad) bayad baraye JSON namotabar safe bemanad"""
        if hasattr(hub, "parse_adaptive_state"):
            result = hub.parse_adaptive_state("not-json")
            self.assertIsNotNone(result)
            # nabayad exception biahandazad va nabayad field-e makhfi dashte bashad
            self.assertNotIn("WS_PATH", str(result))
        else:
            # tabe vojood nadarad hanooz — skip mikonim
            self.skipTest("parse_adaptive_state hanooz piade nashode (Task 8 step 2)")

    # --- hich field-e makhfi az adaptive_test CMD pass nemishavad ---
    def test_no_secret_in_adaptive_test_cmd(self):
        cmd = build_node_cmd("adaptive_test", {"WS_PATH": "/_rh/secret", "token": "abc"})
        self.assertIsNotNone(cmd)
        self.assertNotIn("/_rh/secret", cmd)
        self.assertNotIn("abc", cmd)


class TestHubSecurity(unittest.TestCase):
    def test_ssh_user_rejects_option_injection(self):
        self.assertTrue(hub.RE_SSH_USER.fullmatch("root"))
        self.assertTrue(hub.RE_SSH_USER.fullmatch("ubuntu_22"))
        for user in ("-oProxyCommand=id", "bad user", "", "a" * 33):
            self.assertFalse(bool(hub.RE_SSH_USER.fullmatch(user)), user)
        with self.assertRaises(ValueError):
            hub._ssh_base({"ssh_opts": [], "ssh_key_path": ""},
                          {"ssh_user": "-F", "host": "example.com", "ssh_port": 22})

    def test_port_range_validation(self):
        for p in ("1", "22", "443", "65535"):
            self.assertTrue(hub.valid_port(p), p)
        for p in ("", "0", "65536", "99999", "-1", "abc"):
            self.assertFalse(hub.valid_port(p), p)
        self.assertIsNone(hub.build_iran_cmd("plain_on", {"port": "99999"}))

    def test_password_hash_and_legacy_compatibility(self):
        encoded = hub.hash_password("a-strong-password")
        self.assertTrue(encoded.startswith("pbkdf2_sha256$"))
        self.assertTrue(hub.verify_password(encoded, "a-strong-password"))
        self.assertFalse(hub.verify_password(encoded, "wrong-password"))
        legacy = hub.hashlib.sha256(b"old-password").hexdigest()
        self.assertTrue(hub.verify_password(legacy, "old-password"))
        self.assertTrue(hub.password_is_legacy(legacy))

    def test_ui_does_not_persist_api_token(self):
        self.assertNotIn("rh_token", hub.UI_HTML)
        self.assertNotIn("localStorage.setItem('rh_token'", hub.UI_HTML)
        self.assertIn("RatholeEngine Pro", hub.UI_HTML)

    def test_http_login_cookie_and_security_headers(self):
        import tempfile, threading, urllib.request, urllib.error, json, time
        from http.server import ThreadingHTTPServer
        with tempfile.TemporaryDirectory() as td:
            conf = os.path.join(td, "config.json")
            inv = os.path.join(td, "inventory.json")
            audit = os.path.join(td, "audit.log")
            with open(conf, "w", encoding="utf-8") as f:
                json.dump({
                    "api_token": "a" * 48,
                    "admin_password_hash": hub.hash_password("correct horse battery staple"),
                    "listen_host": "127.0.0.1", "listen_port": 0,
                    "ssh_key_path": "", "ssh_opts": [], "bundle_dir": td,
                }, f)
            with open(inv, "w", encoding="utf-8") as f:
                json.dump([], f)
            old = (hub.CONF_PATH, hub.INV_PATH, hub.AUDIT_PATH)
            hub.CONF_PATH, hub.INV_PATH, hub.AUDIT_PATH = conf, inv, audit
            server = ThreadingHTTPServer(("127.0.0.1", 0), hub.Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = "http://127.0.0.1:%d" % server.server_address[1]
            try:
                with urllib.request.urlopen(base + "/") as r:
                    self.assertEqual(r.status, 200)
                    self.assertEqual(r.headers.get("X-Frame-Options"), "DENY")
                    self.assertIn("default-src 'self'", r.headers.get("Content-Security-Policy", ""))
                    self.assertEqual(r.headers.get("Cache-Control"), "no-store, max-age=0")

                payload = json.dumps({"password": "correct horse battery staple"}).encode()
                req = urllib.request.Request(base + "/api/login", data=payload,
                                             headers={"Content-Type": "application/json"}, method="POST")
                with urllib.request.urlopen(req) as r:
                    body = json.loads(r.read().decode())
                    cookie = r.headers.get("Set-Cookie")
                    self.assertEqual(body, {"ok": True})
                    self.assertIn("HttpOnly", cookie)
                    self.assertIn("SameSite=Strict", cookie)
                    self.assertNotIn("token", body)

                req = urllib.request.Request(base + "/api/servers", headers={"Cookie": cookie.split(";", 1)[0]})
                with urllib.request.urlopen(req) as r:
                    self.assertEqual(json.loads(r.read().decode()), [])

                req = urllib.request.Request(base + "/api/logout", data=b"{}",
                                             headers={"Cookie": cookie.split(";", 1)[0], "Content-Type": "application/json"},
                                             method="POST")
                with urllib.request.urlopen(req) as r:
                    self.assertIn("Max-Age=0", r.headers.get("Set-Cookie", ""))
            finally:
                server.shutdown(); server.server_close(); thread.join(timeout=2)
                hub.CONF_PATH, hub.INV_PATH, hub.AUDIT_PATH = old


if __name__ == "__main__":
    unittest.main(verbosity=2)
