test "safe_filename strips path, illegal and reserved names" {
    assert safe_filename("a/b/c.txt") == "c.txt";
    assert safe_filename("..\\x\\y.pdf") == "y.pdf";
    assert safe_filename("a<b>:c.txt") == "a_b__c.txt";
    assert safe_filename("NUL.txt") == "_NUL.txt";
    assert safe_filename("trail. ") == "trail";
    assert safe_filename("") == "file";
    assert safe_filename("..") == "file";
    assert safe_filename(None) == "file";
}

test "safe_filename fits 255 bytes keeping the extension" {
    n = safe_filename("é" * 300 + ".pdf");
    assert len(n.encode("utf-8")) <= 255;
    assert n.endswith(".pdf");
}

test "mask_key" {
    assert mask_key(None) is None;
    assert mask_key("") is None;
    assert mask_key("short") == "…";
    assert mask_key("cb_abcdefghijklmnop") == "cb_ab…mnop";
}

test "versions" {
    assert parse_version("v0.1.1-1-g367823f") == [0, 1, 1];
    assert parse_version("x") == [];
    assert version_gt("v0.2.0", "0.1.9");
    assert not version_gt("0.1.1", "0.1.1");
    assert version_gt("1.0", "0.9.9");
    assert not version_gt("garbage", "1.0");
}
