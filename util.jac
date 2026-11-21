"""Pure helpers shared by the server modules, hand-ported from the Python backend."""

import re;
import unicodedata;
import os;

glob MAX_NAME_BYTES: int = 255;
glob DEFAULT_SIDEBAR_WIDTH: str = "16rem";
glob WINDOWS_RESERVED: set[str] = {
    "CON", "PRN", "AUX", "NUL",
    "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
    "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    "COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"
};

"""Trim stem + suffix to `budget` bytes, keeping as much suffix as possible."""
def fit_bytes(stem: str, suffix: str, budget: int) -> str {
    sfx = suffix;
    st = stem;
    while sfx != "" and len(sfx.encode("utf-8")) > budget - 1 {
        sfx = sfx[:-1];
    }
    room = budget - len(sfx.encode("utf-8"));
    while len(st.encode("utf-8")) > room {
        st = st[:-1];
    }
    joined = st + sfx;
    if joined != "" {
        return joined;
    }
    if sfx != "" {
        return sfx;
    }
    return st;
}

"""A valid single path component on every platform the manager runs on."""
def safe_filename(name: str | None, fallback: str = "file") -> str {
    raw = "";
    if name is not None {
        raw = name;
    }
    cleaned = unicodedata.normalize("NFC", raw.strip()).replace("\\", "/");
    cleaned = cleaned.rsplit("/", 1)[-1];
    cleaned = re.sub(r"[\x00-\x1f\x7f]", "", cleaned);
    cleaned = re.sub(r'[<>:"/\\|?*]', "_", cleaned);
    cleaned = cleaned.rstrip(". ");
    if cleaned == "" or cleaned == "." or cleaned == ".." {
        return fallback;
    }
    stem = cleaned.partition(".")[0];
    if stem.upper() in WINDOWS_RESERVED {
        cleaned = "_" + cleaned;
    }
    if len(cleaned.encode("utf-8")) <= MAX_NAME_BYTES {
        return cleaned;
    }
    parts = cleaned.rpartition(".");
    fitted = "";
    if parts[1] != "" {
        fitted = fit_bytes(parts[0], "." + parts[2], MAX_NAME_BYTES);
    } else {
        fitted = fit_bytes(cleaned, "", MAX_NAME_BYTES);
    }
    if fitted == "" {
        return fallback;
    }
    return fitted;
}

"""Show enough of a license key to recognise it, never the whole thing."""
def mask_key(key: str | None) -> str | None {
    if key is None or key == "" {
        return None;
    }
    if len(key) <= 9 {
        return "…";
    }
    return key[:5] + "…" + key[-4:];
}

"""'v0.1.1-1-g367823f' / '0.1.1' -> [0, 1, 1]; an empty list when unparseable."""
def parse_version(text: str) -> list[int] {
    core = text.strip().lstrip("v").split("-", 1)[0];
    if core == "" {
        return [];
    }
    out: list[int] = [];
    for part in core.split(".") {
        if not part.isdigit() {
            return [];
        }
        out.append(int(part));
    }
    return out;
}

"""True if `latest` is a strictly newer semver than `current`."""
def version_gt(latest: str, current: str) -> bool {
    a = parse_version(latest);
    b = parse_version(current);
    if len(a) == 0 or len(b) == 0 {
        return False;
    }
    length = max(len(a), len(b));
    while len(a) < length {
        a.append(0);
    }
    while len(b) < length {
        b.append(0);
    }
    return a > b;
}

"""A validated CSS length for the profile sidebar (SIDEBAR_WIDTH)."""
def sidebar_width -> str {
    value = os.environ.get("SIDEBAR_WIDTH", "").strip();
    if value == "" {
        return DEFAULT_SIDEBAR_WIDTH;
    }
    if re.fullmatch(r"\d+(?:\.\d+)?(?:px|rem|em|vw)", value) is not None {
        return value;
    }
    return DEFAULT_SIDEBAR_WIDTH;
}

"""The Manager's state directory: the env override, else the host default."""
def data_dir -> str {
    configured = os.environ.get("CLOAKBROWSER_MANAGER_DATA_DIR", "");
    if configured != "" {
        return os.path.expanduser(configured);
    }
    legacy = os.environ.get("CLOAKBROWSER_DATA_DIR", "");
    if legacy != "" {
        return os.path.expanduser(legacy);
    }
    return "/data";
}
