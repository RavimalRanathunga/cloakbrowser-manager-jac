import from stdjac.graph { jobj }

enum Gpu {
    AUTO,
    NVIDIA,
    INTEL,
}

node Item {
    has n: int;
}

def:pub absent_or_null(a: str | None = None) -> str {
    return "a=" + str(a);
}

def:pub gpu(g: Gpu = Gpu.AUTO) -> str {
    return str(g);
}

def:pub gpu_str(g: str) -> str {
    return g;
}

def:pub add_items(count: int) {
    for i in range(count) {
        root.shared ++> Item(n=i);
    }
}

def:pub order -> list[int] {
    return [i.n for i in [root.shared --> [?:Item]]];
}

def:pub blob_len(data: bytes) -> int {
    return len(data);
}

def:pub blob_make(n: int) -> bytes {
    return b"x" * n;
}

def:pub nullable_nodefault(a: str | None) -> str {
    return "a=" + str(a);
}

def:pub nullable_int(n: int | None = None) -> str {
    return "n=" + str(n);
}

obj Patch {
    has proxy: str | None = None,
        timezone: str | None = None;
}

def:pub patch_obj(p: Patch) -> str {
    return str(p.proxy) + "," + str(p.timezone);
}

obj NotFound(Exception) {}

def:pub boom -> str {
    raise NotFound("Profile not found");
}

enum Lower {
    auto,
    nvidia,
}
