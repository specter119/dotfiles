// Percent-encode the userinfo of a URL so Go's net/url accepts it.
// Go rejects characters such as `^` in a proxy password ("invalid userinfo"),
// which fails every request magpie sends through that proxy.
// Usage: {{url_userinfo_escape enterprise_proxy.url}}
let url = params[0];
let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:!$&'()*+,;=%";
let ascii = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
let hex = "0123456789ABCDEF";

let scheme_end = url.index_of("://");
if scheme_end < 0 {
    return url;
}
let head_len = scheme_end + 3;
let rest = url.sub_string(head_len);
let auth_end = rest.index_of("/");
if auth_end < 0 {
    auth_end = rest.len();
}
let auth = rest.sub_string(0, auth_end);
let tail = rest.sub_string(auth_end);

// The last '@' separates userinfo from host, so an unescaped '@' in the password is encoded.
let at = -1;
let i = 0;
for ch in auth.chars() {
    if ch == '@' {
        at = i;
    }
    i += 1;
}
if at < 0 {
    return url;
}

let out = "";
for ch in auth.sub_string(0, at).chars() {
    if allowed.contains(ch) {
        out += ch;
    } else {
        let idx = ascii.index_of(ch);
        if idx < 0 {
            out += ch;
        } else {
            let code = idx + 32;
            out += "%" + hex.sub_string(code / 16, 1) + hex.sub_string(code % 16, 1);
        }
    }
}

url.sub_string(0, head_len) + out + auth.sub_string(at) + tail
