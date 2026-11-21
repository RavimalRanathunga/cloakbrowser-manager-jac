# token_auth

`auth` plugin reproducing the original's optional `AUTH_TOKEN`: one shared token, accepted as
`Authorization: Bearer <token>` or an `auth_token` cookie. With `AUTH_TOKEN` unset every caller is the
single local `operator` (the original's open local-dev mode). Every caller that passes shares one `root`.

(The module docstring that said this was deleted by `neojac fmt --fix` under the default lint — see
LIMITATIONS.md L-019.)
