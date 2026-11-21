impl mask_key(key: any) -> any {
    if not key {
        return None;
    }
    if len(key) <= 9 {
        return "…";
    }
    return f"{key[:5]}…{key[-4:]}";
}

impl parse_version(text: any) -> any {
    core: any = text.strip().lstrip("v").split("-", 1)[0];
    if not core {
        return None;
    }
    parts: any = [];
    for part in core.split(".") {
        if not part.isdigit() {
            return None;
        }
        parts.append(`int(part));
    }
    return parts;
}

impl version_gt(latest: any, current: any) -> any {
    a: any = parse_version(latest);
    b: any = parse_version(current);
    if a is None or b is None {
        return False;
    }
    length: any = max(len(a), len(b));
    while len(a) < length {
        a.append(0);
    }
    while len(b) < length {
        b.append(0);
    }
    return a > b;
}

impl netloc_of(host: any, port: any) -> any {
    if port and port not in (80, 443) {
        return f"{host}:{port}";
    }
    return host;
}
