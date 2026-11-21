"""Runs the scenarios of manager.test.jac against the ORIGINAL Python app (FastAPI TestClient).

Run: ORIGINAL_REPO=../CloakBrowser-Manager python3 -I -m pytest parity -q -p no:cacheprovider
If these pass, the expectations hard-coded in manager.test.jac are the original's real behaviour.
"""
import os
import sys
import types
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

ORIG = Path(os.environ.get("ORIGINAL_REPO", "../CloakBrowser-Manager")).resolve()
sys.path.insert(0, str(ORIG))

mock_cb = types.ModuleType("cloakbrowser")
mock_cb.launch_persistent_context_async = AsyncMock()
mock_dl = types.ModuleType("cloakbrowser.download")
mock_dl.ensure_binary = MagicMock()
mock_lic = types.ModuleType("cloakbrowser.license")
mock_lic.resolve_license_key = lambda key=None: key
mock_lic.validate_license = lambda key: None
mock_lic.get_pro_latest_version = lambda channel=None: None
mock_lic.CloakBrowserLicenseError = type("CloakBrowserLicenseError", (RuntimeError,), {})
mock_lic.license_error_for_code = lambda code: None
mock_lic.read_denial_file = lambda path: None
sys.modules.setdefault("cloakbrowser", mock_cb)
sys.modules.setdefault("cloakbrowser.download", mock_dl)
sys.modules.setdefault("cloakbrowser.license", mock_lic)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from backend import database as db  # noqa: E402
from backend.runtime import RuntimeConfig  # noqa: E402


@pytest.fixture()
def c(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "profiles.db")
    monkeypatch.setattr(db, "DATA_DIR", tmp_path)
    db.init_db()
    from backend import main, artifacts
    monkeypatch.setattr(main.browser_mgr, "runtime", RuntimeConfig("linux", "docker", "vnc", tmp_path))
    monkeypatch.setattr(main.browser_mgr.vnc, "enabled", True)
    monkeypatch.setattr(main.browser_mgr.vnc, "validate_available", MagicMock())
    monkeypatch.setattr(main.browser_mgr, "cleanup_stale", AsyncMock())
    monkeypatch.setattr(main.browser_mgr, "cleanup_all", AsyncMock())
    monkeypatch.setattr(main.browser_mgr.vnc, "cleanup_stale", AsyncMock())
    monkeypatch.setattr(main.browser_mgr, "resolve_binary_status", MagicMock())
    monkeypatch.setattr(main.browser_mgr, "auto_launch_all", AsyncMock())
    monkeypatch.setattr(artifacts, "sync_picker_view", MagicMock())
    monkeypatch.setattr(artifacts, "refresh_picker_bookmarks", MagicMock())
    monkeypatch.setattr(artifacts, "reclaim_all", MagicMock(return_value=0))
    monkeypatch.setattr(main, "load_settings", lambda: {})
    monkeypatch.setattr(main, "save_settings", lambda d: None)
    with TestClient(main.app) as client:
        yield client


def mk(c, name, **extra):
    r = c.post("/api/profiles", json={"name": name, **extra})
    assert r.status_code == 201, r.text
    return r.json()


def test_create_defaults(c):
    r = c.post("/api/profiles", json={"name": "Test Profile"})
    assert r.status_code == 201
    p = r.json()
    assert (p["screen_width"], p["screen_height"]) == (1920, 1080)
    assert (p["gpu_family"], p["search_engine"], p["human_preset"]) == ("auto", "google", "default")
    assert all(p[k] for k in ("geoip", "clipboard_sync", "allow_3p_cookies", "capture_preview", "restore_session"))
    assert not any(p[k] for k in ("humanize", "auto_launch", "transparent_proxy", "portable_cookies"))
    assert p["status"] == "stopped" and p["cdp_url"] is None and p["launch_args"] == []
    assert 10000 <= p["fingerprint_seed"] <= 99999
    assert p["user_data_dir"].endswith("/profiles/" + p["id"])


def test_create_all_fields(c):
    p = mk(c, "Full", proxy="http://u:p@h:8080", timezone="Europe/Paris", locale="fr-FR", screen_width=1366,
           screen_height=768, gpu_family="nvidia", humanize=True, human_preset="careful", geoip=False,
           clipboard_sync=False, auto_launch=True, color_scheme="dark", launch_args=["--a", "--b"],
           extension_paths=["/x"], allow_3p_cookies=False, search_engine="duckduckgo", capture_preview=False,
           restore_session=False, transparent_proxy=True, portable_cookies=True, notes="n",
           tags=[{"tag": "t1", "color": "#fff"}, {"tag": "t2"}])
    assert p["gpu_family"] == "nvidia" and p["human_preset"] == "careful" and p["color_scheme"] == "dark"
    assert [t["tag"] for t in p["tags"]] == ["t1", "t2"] and p["tags"][1]["color"] is None


def test_rejections_422(c):
    for body in ({"name": "x", "gpu_family": "amd"}, {"name": "x", "gpu_family": None},
                 {"name": "x", "search_engine": None}, {"name": "x", "gpu_vendor": "NVIDIA"},
                 {"fingerprint_seed": 5}, {"name": 3}, {"name": "x", "launch_args": "nope"}):
        assert c.post("/api/profiles", json=body).status_code == 422, body
    assert c.post("/api/profiles", json=[1]).status_code == 422
    assert c.get("/api/profiles").json() == []


def test_get_404_list(c):
    p = mk(c, "A")
    assert c.get(f"/api/profiles/{p['id']}").json()["name"] == "A"
    r = c.get("/api/profiles/nope")
    assert r.status_code == 404 and r.json()["detail"] == "Profile not found"
    assert len(c.get("/api/profiles").json()) == 1


def test_order_and_reorder_with_ghost(c):
    a, b, cc = mk(c, "A"), mk(c, "B"), mk(c, "C")
    names = lambda: [p["name"] for p in c.get("/api/profiles").json()]
    assert names() == ["C", "B", "A"]
    assert c.post("/api/profiles/reorder", json={"ordered_ids": [a["id"], cc["id"], b["id"]]}).status_code == 200
    assert names() == ["A", "C", "B"]
    c.post("/api/profiles/reorder", json={"ordered_ids": ["ghost", b["id"]]})
    assert names() == ["A", "C", "B"]  # b gets sort_order 1, ties with C; newer (C) wins


def test_update_is_a_patch(c):
    p = mk(c, "A", proxy="http://h:1", notes="keep", launch_args=["--x"])
    u = c.put(f"/api/profiles/{p['id']}", json={"name": "B", "proxy": None}).json()
    assert u["name"] == "B" and u["proxy"] is None and u["notes"] == "keep" and u["launch_args"] == ["--x"]
    assert c.put("/api/profiles/nope", json={"name": "x"}).status_code == 404
    assert c.put(f"/api/profiles/{p['id']}", json={"gpu_family": None}).status_code == 422
    assert c.put(f"/api/profiles/{p['id']}", json={"bogus": 1}).status_code == 422
    assert c.get(f"/api/profiles/{p['id']}").json()["gpu_family"] == "auto"


def test_update_replaces_tags(c):
    p = mk(c, "A", tags=[{"tag": "a"}, {"tag": "b"}])
    u = c.put(f"/api/profiles/{p['id']}", json={"tags": [{"tag": "c", "color": "red"}]}).json()
    assert u["tags"] == [{"tag": "c", "color": "red"}]
    u2 = c.put(f"/api/profiles/{p['id']}", json={"tags": []}).json()
    assert u2["tags"] == []
    assert u2["updated_at"] == p["updated_at"]  # a tags-only update does not bump updated_at


def test_delete(c):
    p = mk(c, "A")
    os.makedirs(p["user_data_dir"] + "/Default")
    assert c.delete(f"/api/profiles/{p['id']}").status_code == 200
    assert c.get(f"/api/profiles/{p['id']}").status_code == 404
    assert not os.path.exists(p["user_data_dir"])
    assert c.delete(f"/api/profiles/{p['id']}").status_code == 404


def test_status_and_not_running(c):
    p = mk(c, "A")
    assert c.get(f"/api/profiles/{p['id']}/status").json()["status"] == "stopped"
    assert c.get("/api/profiles/nope/status").status_code == 404
    assert c.post("/api/profiles/nope/launch").status_code == 404
    assert c.post(f"/api/profiles/{p['id']}/stop").status_code == 404


def test_reset(c):
    p = mk(c, "A", proxy="http://h:1", tags=[{"tag": "x"}])
    d = Path(p["user_data_dir"]) / "Default"
    (d / "Cache").mkdir(parents=True)
    (d / "Local Storage").mkdir()
    for f in ("Cookies", "History", "Bookmarks", "Preferences", "Web Data"):
        (d / f).write_text("x")
    r = c.post(f"/api/profiles/{p['id']}/reset").json()
    assert r["status"] == "stopped" and r["proxy"] == "http://h:1" and len(r["tags"]) == 1
    assert not (d / "Cookies").exists() and not (d / "History").exists()
    assert not (d / "Cache").exists() and not (d / "Local Storage").exists()
    assert all((d / f).exists() for f in ("Bookmarks", "Preferences", "Web Data"))
    assert c.post("/api/profiles/nope/reset").status_code == 404


def test_duplicate_config_only(c):
    p = mk(c, "A", proxy="http://h:1", notes="n", tags=[{"tag": "t", "color": "c"}])
    Path(p["user_data_dir"]).mkdir(parents=True)
    (Path(p["user_data_dir"]) / "Cookies").write_text("secret")
    r = c.post(f"/api/profiles/{p['id']}/duplicate")
    assert r.status_code == 201
    d = r.json()
    assert d["name"] == "A (copy)" and d["fingerprint_seed"] == p["fingerprint_seed"] and d["id"] != p["id"]
    assert d["proxy"] == "http://h:1" and d["notes"] == "n" and d["tags"][0]["tag"] == "t"
    assert not Path(d["user_data_dir"]).exists()
    assert c.get("/api/profiles").json()[0]["name"] == "A (copy)"
    assert c.post("/api/profiles/nope/duplicate").status_code == 404


def test_duplicate_with_state(c):
    p = mk(c, "A")
    base = Path(p["user_data_dir"])
    (base / "Default").mkdir(parents=True)
    (base / "Default" / "Cookies").write_text("secret")
    (base / "SingletonCookie").write_text("lock")
    d = c.post(f"/api/profiles/{p['id']}/duplicate", json={"include_browser_state": True}).json()
    assert (Path(d["user_data_dir"]) / "Default" / "Cookies").exists()
    assert not (Path(d["user_data_dir"]) / "SingletonCookie").exists()
    assert c.post(f"/api/profiles/{p['id']}/duplicate", json={"bogus": True}).status_code == 422


def test_settings(c):
    s = c.get("/api/settings").json()
    assert s == {"license_key_set": False, "license_key_masked": None, "release_channel": "stable"}
    assert c.put("/api/settings", json={"license_key": "cb_abcdefghijklmnop", "release_channel": "Preview"}).status_code == 200
    s2 = c.get("/api/settings").json()
    assert s2["license_key_masked"] == "cb_ab…mnop" and s2["release_channel"] == "preview"
    assert c.put("/api/settings", json={"release_channel": "nightly"}).status_code == 400
    assert c.put("/api/settings", json={"license_key": ""}).status_code == 200
    assert c.get("/api/settings").json()["license_key_set"] is False


def test_status(c):
    mk(c, "A"); mk(c, "B")
    s = c.get("/api/status").json()
    assert (s["profiles_total"], s["running_count"], s["host_os"], s["runtime_mode"]) == (2, 0, "linux", "docker")


def test_sidebar(c, monkeypatch):
    monkeypatch.setenv("SIDEBAR_WIDTH", "20rem")
    assert c.get("/api/config").json()["sidebar_width"] == "20rem"
    monkeypatch.setenv("SIDEBAR_WIDTH", "evil;")
    assert c.get("/api/config").json()["sidebar_width"] == "16rem"


def test_files(c):
    p = mk(c, "A")
    pid = p["id"]
    r = c.post(f"/api/profiles/{pid}/files", content=b"hello",
               headers={"X-File-Name": "../evil/inv oice.pdf", "Content-Type": "application/pdf"})
    assert r.status_code == 201
    a = r.json()
    assert a["name"] == "inv oice.pdf" and a["size"] == 5 and a["kind"] == "upload" and a["state"] == "ready"
    assert a["content_type"] == "application/pdf" and a["container_path"].endswith("/" + a["id"] + "/inv oice.pdf")
    assert [x["id"] for x in c.get(f"/api/profiles/{pid}/files").json()] == [a["id"]]
    d = c.get(f"/api/profiles/{pid}/files/{a['id']}")
    assert d.status_code == 200 and d.content == b"hello"
    assert c.get(f"/api/profiles/{pid}/files/ghost").status_code == 404
    assert c.delete(f"/api/profiles/{pid}/files/{a['id']}").status_code == 200
    assert c.get(f"/api/profiles/{pid}/files").json() == []
    assert c.delete(f"/api/profiles/{pid}/files/{a['id']}").status_code == 404
    assert c.post("/api/profiles/nope/files", content=b"x", headers={"X-File-Name": "a"}).status_code == 404
