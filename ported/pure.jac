def mask_key(key: any) -> any;

def parse_version(text: any) -> any;

def version_gt(latest: any, current: any) -> any;

def netloc_of(host: any, port: any) -> any;

with entry:__main__ {
    print(mask_key("cb_abcdefghijklmnop"), mask_key("short"), mask_key(None));
    print(parse_version("v0.1.1-1-g367823f"), parse_version("x"));
    print(version_gt("v0.2.0", "0.1.9"), version_gt("0.1.1", "0.1.1"));
    print(netloc_of("h", 8080), netloc_of("h", 443));
}
