"""The Manager's server: profiles, tags, files and settings, kept as a graph under root."""

import os;
import json;
import random;
import shutil;
import threading;
import datetime;
import from stdjac.graph { jobj, remove }

glob lock: threading.Lock = threading.Lock(),
     running: dict[str, bool] = {},
     live_key: str = "",
     live_channel: str = "",
     settings_loaded: bool = False,
     max_artifact_bytes: int = 256 * 1024 * 1024,
     max_artifact_count: int = 200,
     max_profile_bytes: int = 2 * 1024 * 1024 * 1024;

glob FIELD_KINDS: dict[str, str] = {
    "name": "str",
    "fingerprint_seed": "int?",
    "proxy": "str?",
    "timezone": "str?",
    "locale": "str?",
    "screen_width": "int",
    "screen_height": "int",
    "gpu_family": "enum:auto|nvidia|intel",
    "humanize": "bool",
    "human_preset": "enum:default|careful",
    "geoip": "bool",
    "clipboard_sync": "bool",
    "auto_launch": "bool",
    "color_scheme": "enum?:light|dark|no-preference",
    "launch_args": "strlist",
    "extension_paths": "strlist",
    "allow_3p_cookies": "bool",
    "search_engine": "enum:google|bing|duckduckgo|none",
    "capture_preview": "bool",
    "restore_session": "bool",
    "transparent_proxy": "bool",
    "portable_cookies": "bool",
    "notes": "str?",
    "tags": "tags",
};

glob RESET_FILES: list[str] = [
    "Cookies",
    "Cookies-journal",
    "History",
    "History-journal",
    "History Provider Cache",
    "Login Data",
    "Login Data-journal",
    "Favicons",
    "Favicons-journal",
    "Shortcuts",
    "Shortcuts-journal",
    "Top Sites",
    "Top Sites-journal",
    "Visited Links",
    "Network Action Predictor",
    "Network Action Predictor-journal",
    "TransportSecurity",
    "Current Session",
    "Current Tabs",
    "Last Session",
    "Last Tabs",
    "affiliation_db",
    "coupon_db",
    "DownloadMetadata",
];

glob RESET_DIRS: list[str] = [
    "Cache",
    "Code Cache",
    "GPUCache",
    "Service Worker",
    "Service Worker/CacheStorage",
    "Local Storage",
    "Session Storage",
    "IndexedDB",
    "databases",
    "blob_storage",
    "File System",
    "GCM Store",
    "Extension Rules",
    "Extension Scripts",
    "Extension State",
    "Platform Notifications",
];

glob DUPLICATE_SKIP: set[str] = {
    "SingletonLock",
    "SingletonCookie",
    "SingletonSocket",
    "preview.png",
};

edge HasTag: Profile --> Tag {}

edge HasFile: Profile --> Artifact {}

node Tag {
    has tag: str,
        color: str = "";
}

node Artifact {
    has name: str,
        size: int,
        kind: str = "upload",
        state: str = "ready",
        content_type: str = "",
        created_at: str = "",
        picker_name: str = "";
}

node Profile {
    has name: str,
        fingerprint_seed: int,
        proxy: str = "",
        timezone: str = "",
        locale: str = "",
        screen_width: int = 1920,
        screen_height: int = 1080,
        gpu_family: str = "auto",
        humanize: bool = False,
        human_preset: str = "default",
        geoip: bool = True,
        clipboard_sync: bool = True,
        auto_launch: bool = False,
        color_scheme: str = "",
        launch_args: list[str] = [],
        extension_paths: list[str] = [],
        allow_3p_cookies: bool = True,
        search_engine: str = "google",
        capture_preview: bool = True,
        restore_session: bool = True,
        transparent_proxy: bool = False,
        portable_cookies: bool = False,
        notes: str = "",
        user_data_dir: str = "",
        created_at: str = "",
        updated_at: str = "",
        sort_order: int = 0;
}

node Settings {
    has license_key: str = "",
        release_channel: str = "stable";
}

glob OPTIONAL_KEYS: set[str] = {"proxy", "timezone", "locale", "color_scheme", "notes"};

def now -> str {
    return datetime.datetime.now(datetime.timezone.utc).isoformat();
}

def user_data_dir_for(profile_id: str) -> str {
    return os.path.join(data_dir(), "profiles", profile_id);
}

def artifact_dir(profile_id: str) -> str {
    return os.path.join(data_dir(), "artifacts", profile_id);
}

def find_profile(profile_id: str) -> Profile | None {
    n = jobj(profile_id);
    if isinstance(n, Profile) {
        return n;
    }
    return None;
}

def all_profiles -> list[Profile] {
    return [root --> [?:Profile]];
}

"""sort_order ascending, then created_at descending (the original's SQL ORDER BY)."""
def ordered_profiles -> list[Profile] {
    ps = sorted(all_profiles(), key=lambda (p: Profile) -> str { p.created_at }, reverse=True);
    return sorted(ps, key=lambda (p: Profile) -> int { p.sort_order });
}

def to_out(p: Profile) -> ProfileOut {
    pid = jid(p);
    tags = [TagOut(tag=t.tag, color=t.color) for t in [p ->:HasTag:->]];
    is_running = pid in running;
    cdp = "";
    if is_running {
        cdp = "/api/profiles/" + pid + "/cdp";
    }
    return ProfileOut(
        id=pid,
        name=p.name,
        fingerprint_seed=p.fingerprint_seed,
        proxy=p.proxy,
        timezone=p.timezone,
        locale=p.locale,
        screen_width=p.screen_width,
        screen_height=p.screen_height,
        gpu_family=p.gpu_family,
        humanize=p.humanize,
        human_preset=p.human_preset,
        geoip=p.geoip,
        clipboard_sync=p.clipboard_sync,
        auto_launch=p.auto_launch,
        color_scheme=p.color_scheme,
        launch_args=p.launch_args,
        extension_paths=p.extension_paths,
        allow_3p_cookies=p.allow_3p_cookies,
        search_engine=p.search_engine,
        capture_preview=p.capture_preview,
        restore_session=p.restore_session,
        transparent_proxy=p.transparent_proxy,
        portable_cookies=p.portable_cookies,
        notes=p.notes,
        user_data_dir=p.user_data_dir,
        created_at=p.created_at,
        updated_at=p.updated_at,
        sort_order=p.sort_order,
        tags=tags,
        status="running" if is_running else "stopped",
        cdp_url=cdp,
    );
}

def not_found -> ProfileReply {
    return ProfileReply(status=404, detail="Profile not found");
}

"""An error message for a bad value, or "" when `value` fits `kind`."""
def check_value(key: str, kind: str, value: any) -> str {
    if kind == "str" {
        if not isinstance(value, str) {
            return key + ": Input should be a valid string";
        }
    } elif kind == "str?" {
        if value is not None and not isinstance(value, str) {
            return key + ": Input should be a valid string";
        }
    } elif kind == "int" or kind == "int?" {
        if value is None and kind == "int?" {
            return "";
        }
        if not isinstance(value, int) or isinstance(value, bool) {
            return key + ": Input should be a valid integer";
        }
    } elif kind == "bool" {
        if not isinstance(value, bool) {
            return key + ": Input should be a valid boolean";
        }
    } elif kind == "strlist" {
        if not isinstance(value, list) {
            return key + ": Input should be a valid list";
        }
        for item in value {
            if not isinstance(item, str) {
                return key + ": Input should be a valid string";
            }
        }
    } elif kind == "tags" {
        if value is None {
            return "";
        }
        if not isinstance(value, list) {
            return key + ": Input should be a valid list";
        }
        for item in value {
            if not isinstance(item, dict) or "tag" not in item or not isinstance(item["tag"], str) {
                return key + ": each tag needs a string 'tag'";
            }
        }
    } elif kind.startswith("enum") {
        allowed = kind.split(":", 1)[1].split("|");
        if value is None {
            if kind.startswith("enum?") {
                return "";
            }
            return key + ": value cannot be null";
        }
        if not isinstance(value, str) or value not in allowed {
            return key + ": Input should be one of " + ", ".join(allowed);
        }
    }
    return "";
}

"""Validate a JSON object of profile fields (all of them known, each well typed)."""
def validate_fields(data: dict[str, any], creating: bool) -> str {
    for key in data.keys() {
        if key not in FIELD_KINDS {
            return key + ": Extra inputs are not permitted";
        }
    }
    if creating and "name" not in data {
        return "name: Field required";
    }
    for (key, value) in data.items() {
        err = check_value(key, FIELD_KINDS[key], value);
        if err != "" {
            return err;
        }
    }
    return "";
}

def parse_object(text: str) -> dict[str, any] | None {
    if text.strip() == "" {
        return {};
    }
    try {
        parsed = json.loads(text);
        if isinstance(parsed, dict) {
            return parsed;
        }
    } except Exception {
        return None;
    }
    return None;
}

def set_tags(p: Profile, tags: any) {
    for t in [p ->:HasTag:->] {
        remove(t);
    }
    if tags is None {
        return;
    }
    for item in tags {
        color = "";
        if "color" in item and item["color"] is not None {
            color = item["color"];
        }
        p +>:HasTag:+> Tag(tag=item["tag"], color=color);
    }
}

def apply_fields(p: Profile, data: dict[str, any]) {
    for (key, value) in data.items() {
        if key == "tags" {
            set_tags(p, value);
        } elif key == "fingerprint_seed" {
            if value is not None {
                p.fingerprint_seed = value;
            }
        } elif key in OPTIONAL_KEYS and value is None {
            setattr(p, key, "");
        } else {
            setattr(p, key, value);
        }
    }
}

def new_seed -> int {
    return random.randint(10000, 99999);
}

def:pub health -> str {
    return "ok";
}

def:protect runtime_config -> ConfigOut {
    return ConfigOut(sidebar_width=sidebar_width());
}

def:pub auth_status -> AuthStatusOut {
    return AuthStatusOut(auth_required=os.environ.get("AUTH_TOKEN", "") != "", authenticated=False);
}

def:protect list_profiles -> ProfilesReply {
    return ProfilesReply(profiles=[to_out(p) for p in ordered_profiles()]);
}

def:protect get_profile(profile_id: str) -> ProfileReply {
    p = find_profile(profile_id);
    if p is None {
        return not_found();
    }
    return ProfileReply(profile=to_out(p));
}

def:protect create_profile(fields_json: str) -> ProfileReply {
    data = parse_object(fields_json);
    if data is None {
        return ProfileReply(status=422, detail="body: Input should be a valid JSON object");
    }
    err = validate_fields(data, True);
    if err != "" {
        return ProfileReply(status=422, detail=err);
    }
    with lock {
        ps = all_profiles();
        order = 0;
        if len(ps) > 0 {
            order = min([q.sort_order for q in ps]) - 1;
        }
        stamp = now();
        p = Profile(
            name=data["name"],
            fingerprint_seed=new_seed(),
            created_at=stamp,
            updated_at=stamp,
            sort_order=order,
        );
        p.user_data_dir = user_data_dir_for(jid(p));
        apply_fields(p, data);
        root ++> p;
        return ProfileReply(status=201, profile=to_out(p));
    }
}

def:protect update_profile(profile_id: str, fields_json: str) -> ProfileReply {
    p = find_profile(profile_id);
    if p is None {
        return not_found();
    }
    data = parse_object(fields_json);
    if data is None {
        return ProfileReply(status=422, detail="body: Input should be a valid JSON object");
    }
    err = validate_fields(data, False);
    if err != "" {
        return ProfileReply(status=422, detail=err);
    }
    with lock {
        apply_fields(p, data);
        if len([k for k in data.keys() if k != "tags"]) > 0 {
            p.updated_at = now();
        }
    }
    return ProfileReply(profile=to_out(p));
}

def:protect reorder_profiles(ordered_ids: list[str]) -> OkReply {
    with lock {
        for (index, pid) in enumerate(ordered_ids) {
            p = find_profile(pid);
            if p is not None {
                p.sort_order = index;
            }
        }
    }
    return OkReply();
}

def:protect delete_profile(profile_id: str) -> OkReply {
    p = find_profile(profile_id);
    if p is None {
        return OkReply(status=404, detail="Profile not found");
    }
    with lock {
        running.pop(profile_id, None);
        for t in [p ->:HasTag:->] {
            remove(t);
        }
        for a in [p ->:HasFile:->] {
            remove(a);
        }
        shutil.rmtree(p.user_data_dir, ignore_errors=True);
        shutil.rmtree(artifact_dir(profile_id), ignore_errors=True);
        remove(p);
    }
    return OkReply();
}

def:protect reset_profile(profile_id: str) -> ProfileReply {
    p = find_profile(profile_id);
    if p is None {
        return not_found();
    }
    with lock {
        running.pop(profile_id, None);
        default_dir = os.path.join(p.user_data_dir, "Default");
        if os.path.isdir(default_dir) {
            for fname in RESET_FILES {
                target = os.path.join(default_dir, fname);
                if os.path.isfile(target) or os.path.islink(target) {
                    os.remove(target);
                }
            }
            for dname in RESET_DIRS {
                shutil.rmtree(os.path.join(default_dir, dname), ignore_errors=True);
            }
        }
        p.fingerprint_seed = new_seed();
        p.updated_at = now();
    }
    return ProfileReply(profile=to_out(p));
}

def:protect duplicate_profile(profile_id: str, options_json: str = "") -> ProfileReply {
    src = find_profile(profile_id);
    if src is None {
        return not_found();
    }
    opts = parse_object(options_json);
    if opts is None {
        return ProfileReply(status=422, detail="body: Input should be a valid JSON object");
    }
    include_state = False;
    for (key, value) in opts.items() {
        if key != "include_browser_state" {
            return ProfileReply(status=422, detail=key + ": Extra inputs are not permitted");
        }
        if not isinstance(value, bool) {
            return ProfileReply(status=422, detail=key + ": Input should be a valid boolean");
        }
        include_state = value;
    }
    if include_state and profile_id in running {
        return ProfileReply(
            status=409, detail="Stop the profile before duplicating its browser state"
        );
    }
    with lock {
        ps = all_profiles();
        stamp = now();
        clone = Profile(
            name=src.name + " (copy)",
            fingerprint_seed=src.fingerprint_seed,
            proxy=src.proxy,
            timezone=src.timezone,
            locale=src.locale,
            screen_width=src.screen_width,
            screen_height=src.screen_height,
            gpu_family=src.gpu_family,
            humanize=src.humanize,
            human_preset=src.human_preset,
            geoip=src.geoip,
            clipboard_sync=src.clipboard_sync,
            auto_launch=src.auto_launch,
            color_scheme=src.color_scheme,
            launch_args=list(src.launch_args),
            extension_paths=list(src.extension_paths),
            allow_3p_cookies=src.allow_3p_cookies,
            search_engine=src.search_engine,
            capture_preview=src.capture_preview,
            restore_session=src.restore_session,
            transparent_proxy=src.transparent_proxy,
            portable_cookies=src.portable_cookies,
            notes=src.notes,
            created_at=stamp,
            updated_at=stamp,
            sort_order=min([q.sort_order for q in ps]) - 1,
        );
        clone.user_data_dir = user_data_dir_for(jid(clone));
        if include_state and os.path.isdir(src.user_data_dir) {
            try {
                shutil.copytree(
                    src.user_data_dir,
                    clone.user_data_dir,
                    symlinks=True,
                    dirs_exist_ok=True,
                    ignore=lambda (d: str, names: list[str]) -> set[str] {
                        {n for n in names if n in DUPLICATE_SKIP}
                    },
                );
            } except OSError as e {
                shutil.rmtree(clone.user_data_dir, ignore_errors=True);
                return ProfileReply(status=500, detail="Failed to copy browser state: " + str(e));
            }
        }
        for t in [src ->:HasTag:->] {
            clone +>:HasTag:+> Tag(tag=t.tag, color=t.color);
        }
        root ++> clone;
        return ProfileReply(status=201, profile=to_out(clone));
    }
}

def:protect launch_profile(profile_id: str) -> LaunchReply {
    p = find_profile(profile_id);
    if p is None {
        return LaunchReply(status=404, detail="Profile not found");
    }
    if profile_id in running {
        return LaunchReply(status=409, detail="Profile is already running");
    }
    running[profile_id] = True;
    return LaunchReply(profile_id=profile_id, cdp_url="/api/profiles/" + profile_id + "/cdp");
}

def:protect stop_profile(profile_id: str) -> OkReply {
    if profile_id not in running {
        return OkReply(status=404, detail="Profile is not running");
    }
    running.pop(profile_id, None);
    return OkReply();
}

def:protect profile_status(profile_id: str) -> LaunchReply {
    p = find_profile(profile_id);
    if p is None {
        return LaunchReply(status=404, detail="Profile not found");
    }
    if profile_id in running {
        return LaunchReply(
            profile_id=profile_id, state="running", cdp_url="/api/profiles/" + profile_id + "/cdp"
        );
    }
    return LaunchReply(profile_id=profile_id, state="stopped");
}

def load_settings {
    if settings_loaded {
        return;
    }
    found = [root --> [?:Settings]];
    stored_key = "";
    stored_channel = "";
    if len(found) > 0 {
        stored_key = found[0].license_key;
        stored_channel = found[0].release_channel;
    }
    env_key = os.environ.get("CLOAKBROWSER_LICENSE_KEY", "");
    env_channel = os.environ.get("CLOAKBROWSER_RELEASE_CHANNEL", "");
    live_key = env_key if env_key != "" else stored_key;
    live_channel = env_channel if env_channel != "" else stored_channel;
    settings_loaded = True;
}

def:protect system_status -> StatusOut {
    return StatusOut(running_count=len(running), profiles_total=len(all_profiles()));
}

def masked_or_empty(key: str | None) -> str {
    masked = mask_key(key);
    if masked is None {
        return "";
    }
    return masked;
}

def:protect get_settings -> SettingsOut {
    load_settings();
    key: str | None = None;
    if live_key != "" {
        key = live_key;
    }
    channel = "stable";
    if live_channel != "" {
        channel = live_channel;
    }
    return SettingsOut(
        license_key_set=live_key != "", license_key_masked=masked_or_empty(key), release_channel=channel
    );
}

def:protect put_settings(patch_json: str) -> StatusOut {
    load_settings();
    data = parse_object(patch_json);
    if data is None {
        return StatusOut(status=422, detail="body: Input should be a valid JSON object");
    }
    for key in data.keys() {
        if key != "license_key" and key != "release_channel" {
            return StatusOut(status=422, detail=key + ": Extra inputs are not permitted");
        }
    }
    new_channel = "";
    if "release_channel" in data and data["release_channel"] is not None {
        raw = data["release_channel"];
        if not isinstance(raw, str) {
            return StatusOut(status=422, detail="release_channel: Input should be a valid string");
        }
        new_channel = raw.strip().lower();
        if new_channel != "stable" and new_channel != "preview" {
            return StatusOut(status=400, detail="release_channel must be 'stable' or 'preview'");
        }
    }
    found = [root --> [?:Settings]];
    st: Settings;
    if len(found) > 0 {
        st = found[0];
    } else {
        st = root ++> Settings();
    }
    if "license_key" in data and data["license_key"] is not None {
        raw_key = data["license_key"];
        if not isinstance(raw_key, str) {
            return StatusOut(status=422, detail="license_key: Input should be a valid string");
        }
        st.license_key = raw_key.strip();
        live_key = raw_key.strip();
    }
    if new_channel != "" {
        st.release_channel = new_channel;
        live_channel = new_channel;
    }
    return system_status();
}

def artifact_path(profile_id: str, artifact_id: str, name: str) -> str {
    return os.path.join(artifact_dir(profile_id), artifact_id, safe_filename(name));
}

def to_artifact_out(profile_id: str, a: Artifact) -> ArtifactOut {
    aid = jid(a);
    return ArtifactOut(
        id=aid,
        profile_id=profile_id,
        name=a.name,
        size=a.size,
        kind=a.kind,
        state=a.state,
        content_type=a.content_type,
        created_at=a.created_at,
        picker_name=a.picker_name,
        container_path=artifact_path(profile_id, aid, a.name),
    );
}

def find_artifact(p: Profile, artifact_id: str) -> Artifact | None {
    n = jobj(artifact_id);
    if isinstance(n, Artifact) {
        for a in [p ->:HasFile:->] {
            if a is n {
                return a;
            }
        }
    }
    return None;
}

"""An error message when another artifact of `incoming` bytes would breach the caps, else ""."""
def check_quota(p: Profile, incoming: int) -> str {
    files = [p ->:HasFile:->];
    if len(files) >= max_artifact_count {
        return "profile already holds "
            + str(len(files))
            + " artifacts (max "
            + str(max_artifact_count)
            + ")";
    }
    used = sum([a.size for a in files if a.state == "ready"]);
    if used + incoming > max_profile_bytes {
        return "profile artifact storage would reach "
            + str(used + incoming)
            + " bytes (max "
            + str(max_profile_bytes)
            + ")";
    }
    return "";
}

def:protect list_files(profile_id: str) -> ArtifactsReply {
    p = find_profile(profile_id);
    if p is None {
        return ArtifactsReply(status=404, detail="Profile not found");
    }
    files = sorted(
        [a for a in [p ->:HasFile:->]],
        key=lambda (a: Artifact) -> str { a.created_at },
        reverse=True,
    );
    return ArtifactsReply(artifacts=[to_artifact_out(profile_id, a) for a in files]);
}

def:protect upload_file(
    profile_id: str, name: str, data: bytes, content_type: str = ""
) -> ArtifactReply {
    p = find_profile(profile_id);
    if p is None {
        return ArtifactReply(status=404, detail="Profile not found");
    }
    if len(data) > max_artifact_bytes {
        return ArtifactReply(
            status=413, detail="upload exceeds " + str(max_artifact_bytes) + " bytes"
        );
    }
    with lock {
        err = check_quota(p, len(data));
        if err != "" {
            return ArtifactReply(status=507, detail=err);
        }
        clean = safe_filename(name);
        a = Artifact(name=clean, size=len(data), created_at=now(), picker_name=clean);
        if content_type != "" {
            a.content_type = content_type;
        }
        target = artifact_path(profile_id, jid(a), clean);
        os.makedirs(os.path.dirname(target), exist_ok=True);
        with open(target, "wb") as fh {
            fh.write(data);
        }
        p +>:HasFile:+> a;
        return ArtifactReply(status=201, artifact=to_artifact_out(profile_id, a));
    }
}

def:protect download_file(profile_id: str, artifact_id: str) -> FileReply {
    p = find_profile(profile_id);
    if p is None {
        return FileReply(status=404, detail="Profile not found");
    }
    a = find_artifact(p, artifact_id);
    if a is None {
        return FileReply(status=404, detail="Artifact not found");
    }
    if a.state == "pending" {
        return FileReply(status=409, detail="Download is still in progress");
    }
    path = artifact_path(profile_id, artifact_id, a.name);
    if not os.path.isfile(path) {
        return FileReply(status=404, detail="Artifact bytes are missing");
    }
    with open(path, "rb") as fh {
        return FileReply(name=a.name, data=fh.read());
    }
}

def:protect delete_file(profile_id: str, artifact_id: str) -> OkReply {
    p = find_profile(profile_id);
    if p is None {
        return OkReply(status=404, detail="Profile not found");
    }
    a = find_artifact(p, artifact_id);
    if a is None {
        return OkReply(status=404, detail="Artifact not found");
    }
    if a.state == "pending" and profile_id in running {
        return OkReply(
            status=409, detail="Download is still in progress; it cannot be removed yet"
        );
    }
    remove(a);
    shutil.rmtree(os.path.join(artifact_dir(profile_id), artifact_id), ignore_errors=True);
    return OkReply();
}
