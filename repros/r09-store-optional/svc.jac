node Item {
    has name: str,
        opt_str: str | None = None,
        opt_int: int | None = None;
}

def:pub add(name: str) -> int {
    root.shared ++> Item(name=name);
    return len([root.shared --> [?:Item]]);
}

def:pub names -> list[str] {
    return [i.name for i in [root.shared --> [?:Item]]];
}
