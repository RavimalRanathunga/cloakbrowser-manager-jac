"""Pure helpers lifted verbatim from CloakBrowser-Manager backend/main.py (and slimmed to port's core)."""


def mask_key(key):
    if not key:
        return None
    if len(key) <= 9:
        return "…"
    return f"{key[:5]}…{key[-4:]}"


def parse_version(text):
    core = text.strip().lstrip("v").split("-", 1)[0]
    if not core:
        return None
    parts = []
    for part in core.split("."):
        if not part.isdigit():
            return None
        parts.append(int(part))
    return parts


def version_gt(latest, current):
    a = parse_version(latest)
    b = parse_version(current)
    if a is None or b is None:
        return False
    length = max(len(a), len(b))
    while len(a) < length:
        a.append(0)
    while len(b) < length:
        b.append(0)
    return a > b


def netloc_of(host, port):
    if port and port not in (80, 443):
        return f"{host}:{port}"
    return host


if __name__ == "__main__":
    print(mask_key("cb_abcdefghijklmnop"), mask_key("short"), mask_key(None))
    print(parse_version("v0.1.1-1-g367823f"), parse_version("x"))
    print(version_gt("v0.2.0", "0.1.9"), version_gt("0.1.1", "0.1.1"))
    print(netloc_of("h", 8080), netloc_of("h", 443))
