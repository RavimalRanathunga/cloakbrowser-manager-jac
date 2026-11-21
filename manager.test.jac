import tempfile;
import json;

def must(r: ProfileReply) -> ProfileOut {
    assert r.profile is not None;
    return r.profile;
}

def fresh_data {
    os.environ["CLOAKBROWSER_MANAGER_DATA_DIR"] = tempfile.mkdtemp();
    for p in all_profiles() {
        for t in [p ->:HasTag:->] {
            remove(t);
        }
        for a in [p ->:HasFile:->] {
            remove(a);
        }
        remove(p);
    }
    running.clear();
}

def mk(name: str, extra: str = "") -> ProfileOut {
    body = '{"name": "' + name + '"' + extra + '}';
    return must(create_profile(body));
}

test "create applies the original defaults" {
    fresh_data();
    r = create_profile('{"name": "Test Profile"}');
    assert r.status == 201;
    p = must(r);
    assert p.name == "Test Profile";
    assert p.screen_width == 1920 and p.screen_height == 1080;
    assert p.gpu_family == "auto" and p.search_engine == "google" and p.human_preset == "default";
    assert p.geoip
        and p.clipboard_sync
        and p.allow_3p_cookies
        and p.capture_preview
        and p.restore_session;
    assert not p.humanize
        and not p.auto_launch
        and not p.transparent_proxy
        and not p.portable_cookies;
    assert p.status == "stopped" and p.cdp_url == "" and p.launch_args == [];
    assert 10000 <= p.fingerprint_seed <= 99999;
    assert p.user_data_dir.endswith("/profiles/" + p.id);
}

test "create with all fields round-trips" {
    fresh_data();
    p = mk(
        "Full",
        ', "proxy": "http://u:p@h:8080", "timezone": "Europe/Paris", "locale": "fr-FR", "screen_width": 1366, "screen_height": 768, "gpu_family": "nvidia", "humanize": true, "human_preset": "careful", "geoip": false, "clipboard_sync": false, "auto_launch": true, "color_scheme": "dark", "launch_args": ["--a", "--b"], "extension_paths": ["/x"], "allow_3p_cookies": false, "search_engine": "duckduckgo", "capture_preview": false, "restore_session": false, "transparent_proxy": true, "portable_cookies": true, "notes": "n", "tags": [{"tag": "t1", "color": "#fff"}, {"tag": "t2"}]',
    );
    assert p.proxy == "http://u:p@h:8080" and p.timezone == "Europe/Paris" and p.locale == "fr-FR";
    assert p.screen_width == 1366 and p.gpu_family == "nvidia" and p.human_preset == "careful";
    assert p.humanize and p.auto_launch and p.transparent_proxy and p.portable_cookies;
    assert not p.geoip and not p.clipboard_sync and not p.allow_3p_cookies;
    assert p.color_scheme == "dark"
        and p.launch_args == ["--a", "--b"]
        and p.extension_paths == ["/x"];
    assert p.search_engine == "duckduckgo" and p.notes == "n";
    assert len(p.tags) == 2
        and p.tags[0].tag == "t1"
        and p.tags[0].color == "#fff"
        and p.tags[1].color == "";
}

test "invalid values and unknown fields are rejected with 422" {
    fresh_data();
    assert create_profile('{"name": "x", "gpu_family": "amd"}').status == 422;
    assert create_profile('{"name": "x", "gpu_family": null}').status == 422;
    assert create_profile('{"name": "x", "search_engine": null}').status == 422;
    assert create_profile('{"name": "x", "gpu_vendor": "NVIDIA"}').status == 422;
    assert create_profile('{"fingerprint_seed": 5}').status == 422;
    assert create_profile('{"name": 3}').status == 422;
    assert create_profile('{"name": "x", "launch_args": "nope"}').status == 422;
    assert create_profile('[1]').status == 422;
    assert len(list_profiles().profiles) == 0;
}

test "get, 404, list" {
    fresh_data();
    assert len(list_profiles().profiles) == 0;
    p = mk("A");
    assert must(get_profile(p.id)).name == "A";
    assert get_profile("nope").status == 404;
    assert get_profile("nope").detail == "Profile not found";
    assert len(list_profiles().profiles) == 1;
}

test "new profiles land on top; reorder persists" {
    fresh_data();
    a = mk("A");
    b = mk("B");
    c = mk("C");
    names = [p.name for p in list_profiles().profiles];
    assert names == ["C", "B", "A"];
    assert reorder_profiles([a.id, c.id, b.id]).status == 200;
    assert [p.name for p in list_profiles().profiles] == ["A", "C", "B"];
    assert reorder_profiles(["ghost", b.id]).status == 200;
    assert [p.name for p in list_profiles().profiles] == ["A", "C", "B"];
}

test "update is a patch: absent keeps, null clears" {
    fresh_data();
    p = mk("A", ', "proxy": "http://h:1", "notes": "keep", "launch_args": ["--x"]');
    u = must(update_profile(p.id, '{"name": "B", "proxy": null}'));
    assert u.name == "B" and u.proxy == "";
    assert u.notes == "keep" and u.launch_args == ["--x"];
    assert u.updated_at >= p.updated_at;
    assert update_profile("nope", '{"name": "x"}').status == 404;
    assert update_profile(p.id, '{"gpu_family": null}').status == 422;
    assert update_profile(p.id, '{"bogus": 1}').status == 422;
    assert must(get_profile(p.id)).gpu_family == "auto";
}

test "update replaces tags" {
    fresh_data();
    p = mk("A", ', "tags": [{"tag": "a"}, {"tag": "b"}]');
    u = must(update_profile(p.id, '{"tags": [{"tag": "c", "color": "red"}]}'));
    assert len(u.tags) == 1 and u.tags[0].tag == "c" and u.tags[0].color == "red";
    u2 = must(update_profile(p.id, '{"tags": []}'));
    assert len(u2.tags) == 0;
    assert u2.updated_at == p.updated_at;
}

test "delete removes profile, files and data dir; 404 after" {
    fresh_data();
    p = mk("A");
    os.makedirs(p.user_data_dir + "/Default");
    assert delete_profile(p.id).status == 200;
    assert get_profile(p.id).status == 404;
    assert not os.path.exists(p.user_data_dir);
    assert delete_profile(p.id).status == 404;
}

test "launch / stop / status lifecycle" {
    fresh_data();
    p = mk("A");
    assert launch_profile("nope").status == 404;
    assert profile_status(p.id).state == "stopped";
    assert stop_profile(p.id).status == 404;
    l = launch_profile(p.id);
    assert l.status == 200 and l.state == "running" and l.vnc_ws_port is None;
    assert launch_profile(p.id).status == 409;
    assert profile_status(p.id).state == "running";
    assert must(get_profile(p.id)).status == "running";
    assert must(get_profile(p.id)).cdp_url == "/api/profiles/" + p.id + "/cdp";
    assert system_status().running_count == 1;
    assert stop_profile(p.id).status == 200;
    assert must(get_profile(p.id)).status == "stopped";
}

test "deleting a running profile stops it" {
    fresh_data();
    p = mk("A");
    launch_profile(p.id);
    delete_profile(p.id);
    assert system_status().running_count == 0;
}

test "reset re-rolls the seed and wipes state but keeps preferences" {
    fresh_data();
    p = mk("A", ', "proxy": "http://h:1", "tags": [{"tag": "x"}]');
    d = p.user_data_dir + "/Default";
    os.makedirs(d + "/Cache");
    os.makedirs(d + "/Local Storage");
    for f in ["Cookies", "History", "Bookmarks", "Preferences", "Web Data"] {
        with open(d + "/" + f, "w") as fh {
            fh.write("x");
        }
    }
    launch_profile(p.id);
    r = must(reset_profile(p.id));
    assert r.status == "stopped" and r.proxy == "http://h:1" and len(r.tags) == 1;
    assert not os.path.exists(d + "/Cookies") and not os.path.exists(d + "/History");
    assert not os.path.exists(d + "/Cache") and not os.path.exists(d + "/Local Storage");
    assert os.path.exists(d + "/Bookmarks")
        and os.path.exists(d + "/Preferences")
        and os.path.exists(d + "/Web Data");
    assert reset_profile("nope").status == 404;
}

test "duplicate is config-only by default and keeps the seed" {
    fresh_data();
    p = mk("A", ', "proxy": "http://h:1", "notes": "n", "tags": [{"tag": "t", "color": "c"}]');
    os.makedirs(p.user_data_dir);
    with open(p.user_data_dir + "/Cookies", "w") as fh {
        fh.write("secret");
    }
    d = must(duplicate_profile(p.id));
    assert d.name == "A (copy)" and d.fingerprint_seed == p.fingerprint_seed;
    assert d.id != p.id and d.user_data_dir != p.user_data_dir;
    assert d.proxy == "http://h:1" and d.notes == "n" and d.tags[0].tag == "t";
    assert not os.path.exists(d.user_data_dir);
    assert [x.name for x in list_profiles().profiles][0] == "A (copy)";
    assert duplicate_profile("nope").status == 404;
}

test "duplicate with browser state copies the session, minus singleton locks" {
    fresh_data();
    p = mk("A");
    os.makedirs(p.user_data_dir + "/Default");
    with open(p.user_data_dir + "/Default/Cookies", "w") as fh {
        fh.write("secret");
    }
    with open(p.user_data_dir + "/SingletonCookie", "w") as fh {
        fh.write("lock");
    }
    d = must(duplicate_profile(p.id, '{"include_browser_state": true}'));
    assert os.path.exists(d.user_data_dir + "/Default/Cookies");
    assert not os.path.exists(d.user_data_dir + "/SingletonCookie");
    assert os.path.exists(p.user_data_dir + "/Default/Cookies");
}

test "duplicate: running source refused for state copy, allowed for config; unknown fields 422" {
    fresh_data();
    p = mk("A");
    launch_profile(p.id);
    assert duplicate_profile(p.id, '{"include_browser_state": true}').status == 409;
    assert duplicate_profile(p.id).status == 201;
    assert duplicate_profile(p.id, '{"bogus": true}').status == 422;
    assert len(list_profiles().profiles) == 2;
}

test "settings: masked key, channel, clear, bad channel" {
    fresh_data();
    s = get_settings();
    assert not s.license_key_set and s.license_key_masked == "" and s.release_channel == "stable";
    st = put_settings('{"license_key": "cb_abcdefghijklmnop", "release_channel": "Preview"}');
    assert st.status == 200;
    s2 = get_settings();
    assert s2.license_key_set
        and s2.license_key_masked == "cb_ab…mnop"
        and s2.release_channel == "preview";
    assert put_settings('{"release_channel": "nightly"}').status == 400;
    assert put_settings('{"license_key": ""}').status == 200;
    assert not get_settings().license_key_set;
    assert put_settings('{"nope": 1}').status == 422;
}

test "status counts profiles" {
    fresh_data();
    mk("A");
    mk("B");
    s = system_status();
    assert s.profiles_total == 2
        and s.running_count == 0
        and s.host_os == "linux"
        and s.runtime_mode == "docker";
}

test "runtime config sidebar width" {
    os.environ["SIDEBAR_WIDTH"] = "20rem";
    assert runtime_config().sidebar_width == "20rem";
    os.environ["SIDEBAR_WIDTH"] = "evil;";
    assert runtime_config().sidebar_width == "16rem";
    os.environ["SIDEBAR_WIDTH"] = "";
    assert runtime_config().sidebar_width == "16rem";
}

test "files: upload, list, download, delete" {
    fresh_data();
    p = mk("A");
    assert upload_file("nope", "a.txt", b"x").status == 404;
    u = upload_file(p.id, "../evil/inv oice.pdf", b"hello", "application/pdf");
    assert u.status == 201;
    assert u.artifact is not None;
    a = u.artifact;
    assert a.name == "inv oice.pdf" and a.size == 5 and a.kind == "upload" and a.state == "ready";
    assert a.content_type == "application/pdf"
        and a.container_path.endswith("/" + a.id + "/inv oice.pdf");
    assert [x.id for x in list_files(p.id).artifacts] == [a.id];
    d = download_file(p.id, a.id);
    assert d.status == 200 and d.data == b"hello" and d.name == "inv oice.pdf";
    assert download_file(p.id, "ghost").status == 404;
    assert delete_file(p.id, a.id).status == 200;
    assert len(list_files(p.id).artifacts) == 0;
    assert delete_file(p.id, a.id).status == 404;
    assert not os.path.exists(artifact_dir(p.id) + "/" + a.id);
}

test "files: quota on count" {
    fresh_data();
    p = mk("A");
    max_artifact_count = 2;
    assert upload_file(p.id, "a", b"1").status == 201;
    assert upload_file(p.id, "b", b"1").status == 201;
    assert upload_file(p.id, "c", b"1").status == 507;
    max_artifact_count = 200;
}

test "files: per-file cap" {
    fresh_data();
    p = mk("A");
    max_artifact_bytes = 3;
    assert upload_file(p.id, "a", b"1234").status == 413;
    max_artifact_bytes = 256 * 1024 * 1024;
}

test "deleting a profile removes its artifacts" {
    fresh_data();
    p = mk("A");
    upload_file(p.id, "a", b"1");
    assert os.path.isdir(artifact_dir(p.id));
    delete_profile(p.id);
    assert not os.path.exists(artifact_dir(p.id));
}
