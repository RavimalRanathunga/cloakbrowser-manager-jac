import from stdjac.server { HTTPMethod, restspec }

@restspec(method=HTTPMethod.GET, path="/p/{id}")
def:pub get_p(id: str) -> str {
    return id;
}

@restspec(method=HTTPMethod.PUT, path="/p")
def:pub put_p -> str {
    return "put";
}

@restspec(method=HTTPMethod.DELETE, path="/p")
def:pub del_p -> str {
    return "del";
}
