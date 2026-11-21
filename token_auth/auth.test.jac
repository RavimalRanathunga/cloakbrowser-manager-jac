import os;

test "open mode: no token configured, everyone is the operator" {
    os.environ["AUTH_TOKEN"] = "";
    a = TokenAuth();
    assert a.caller({}) == "operator";
    assert a.answer("login", {}, "127.0.0.1").user == "operator";
}

test "bearer header and cookie are checked against the token" {
    os.environ["AUTH_TOKEN"] = "s3cret";
    a = TokenAuth();
    assert a.caller({}) is None;
    assert a.caller({"authorization": "Bearer s3cret"}) == "operator";
    assert a.caller({"authorization": "Bearer nope"}) is None;
    assert a.caller({"authorization": "Basic s3cret"}) is None;
    assert a.caller({"cookie": "x=1; auth_token=s3cret"}) == "operator";
    assert a.caller({"cookie": "auth_token=wrong"}) is None;
}

test "sign in answers a session for the right token and refuses the wrong one" {
    os.environ["AUTH_TOKEN"] = "s3cret";
    a = TokenAuth();
    s = a.answer("login", {"token": "s3cret"}, "c");
    assert s.user == "operator" and s.token == "s3cret";
    refused = False;
    try {
        a.answer("login", {"token": "bad"}, "c");
    } except Rejected as e {
        refused = e.detail == "Invalid token";
    }
    assert refused;
    assert len(a.asks({}).fields) == 1 and a.asks({}).fields[0].secret;
}
