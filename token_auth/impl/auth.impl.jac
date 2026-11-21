impl TokenAuth.configured -> str {
    try {
        return self.token.get();
    } except Exception {
        return "";
    }
}

impl TokenAuth.open {}

impl TokenAuth.matches(given: str) -> bool {
    expected = self.configured();
    return given != "" and hmac.compare_digest(given.encode("utf-8"), expected.encode("utf-8"));
}

impl TokenAuth.caller(headers: dict[str, str]) -> str | None {
    if self.configured() == "" {
        return "operator";
    }
    auth = headers.get("authorization", "");
    if auth.startswith("Bearer ") and self.matches(auth[7:]) {
        return "operator";
    }
    for part in headers.get("cookie", "").split(";") {
        pair = part.strip().partition("=");
        if pair[0] == "auth_token" and self.matches(pair[2]) {
            return "operator";
        }
    }
    return None;
}

impl TokenAuth.asks(headers: dict[str, str]) -> SignIn {
    field = SignInField(name="token", label="Access token", secret=True, choices=[]);
    action = SignInAction(name="login", label="Sign in", needs=["token"], redirect="", keeps={});
    return SignIn(fields=[field], actions=[action], redirect="", session=None);
}

impl TokenAuth.answer(action: str, given: dict[str, str], client: str) -> Session {
    supplied = given.get("token", "");
    if self.configured() == "" or self.matches(supplied) {
        return Session(user="operator", token=supplied, name="");
    }
    raise Rejected(detail="Invalid token", retry_after=0);
}

impl TokenAuth.leave(headers: dict[str, str]) {}
