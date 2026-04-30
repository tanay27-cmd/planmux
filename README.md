# proxycli

Local proxy that turns your **Claude** and **ChatGPT** plan logins into an
OpenAI/Anthropic/Gemini-compatible API endpoint, so coding agents and scripts
can call Claude and OpenAI models — including **`gpt-image-2`** image
generation — without burning API credit.

This is a fork of the upstream
[`router-for-me/CLIProxyAPI`](https://github.com/router-for-me/CLIProxyAPI)
(MIT). All implementation credit belongs upstream; see
[`UPSTREAM_README.md`](./UPSTREAM_README.md) for the full feature reference,
SDK docs, and contributor list.

---

## Quick start (for an agent)

```bash
git clone https://github.com/tanay27-cmd/proxycli.git
cd proxycli
bash setup.sh
```

`setup.sh` will:

1. Download the latest `cliproxyapi` release binary for your OS/arch into
   `~/bin` (no Go toolchain needed). Set `BUILD_FROM_SOURCE=1` to compile
   from this checkout instead.
2. Write `~/.cli-proxy-api/config.yaml` with a freshly generated API key.
3. Open a browser for **Claude OAuth** — sign in with the Claude account that
   has the subscription you want to use.
4. Open a browser for **Codex OAuth** — sign in with the ChatGPT
   Plus/Pro/Team account. (`CODEX_DEVICE_FLOW=1` for headless boxes.)
5. Print the **Base URL** and **API key**.

Then start the server:

```bash
~/bin/cliproxyapi -config ~/.cli-proxy-api/config.yaml
```

Leave it running, or wrap it with `pm2` / `launchd` / `systemd`.

---

## What you get

A single endpoint at `http://127.0.0.1:8317` accepting:

| Client format | Path                                          |
| ------------- | --------------------------------------------- |
| OpenAI Chat   | `POST /v1/chat/completions`                   |
| OpenAI Resp.  | `POST /v1/responses`                          |
| Anthropic     | `POST /v1/messages`                           |
| Gemini        | `POST /v1beta/models/{model}:generateContent` |
| **Images**    | `POST /v1/images/generations`                 |

Auth: `Authorization: Bearer <api-key from config.yaml>`.

### Claude via OpenAI SDK

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8317/v1", api_key="<api-key>")
client.chat.completions.create(
    model="claude-sonnet-4",
    messages=[{"role": "user", "content": "hi"}],
)
```

### Image generation via your ChatGPT plan (the trick)

The proxy exposes OpenAI's image-2 model as `gpt-image-2`. Requests to it are
routed through your **Codex OAuth**, so generation is billed against the
ChatGPT Plus/Pro subscription instead of OpenAI API credit:

```bash
curl http://127.0.0.1:8317/v1/images/generations \
  -H "Authorization: Bearer <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-image-2",
    "prompt": "a red bicycle on a beach, golden hour",
    "size": "1024x1024",
    "n": 1
  }'
```

No extra config in `config.yaml` is needed — once `-codex-login` has run, the
`gpt-image-2` model is available on `/v1/images/generations` automatically.
If your ChatGPT account hits its image quota, add a second Codex login
(re-run `-codex-login` with another account) for round-robin.

### Claude Code / Codex CLI

Point the official CLIs at the proxy:

```bash
# Claude Code
export ANTHROPIC_BASE_URL=http://127.0.0.1:8317
export ANTHROPIC_API_KEY=<api-key>

# Codex CLI
export OPENAI_BASE_URL=http://127.0.0.1:8317/v1
export OPENAI_API_KEY=<api-key>
```

---

## Re-authenticating

Tokens refresh automatically. To swap accounts or recover from an expired
login:

```bash
~/bin/cliproxyapi -config ~/.cli-proxy-api/config.yaml -claude-login
~/bin/cliproxyapi -config ~/.cli-proxy-api/config.yaml -codex-login
```

To rotate the API key, edit `~/.cli-proxy-api/config.yaml` and restart.

---

## Files the setup creates

```
~/bin/cliproxyapi                              # the proxy binary
~/.cli-proxy-api/config.yaml                   # host/port/api-keys
~/.cli-proxy-api/claude-<email>.json           # Claude OAuth tokens
~/.cli-proxy-api/codex-<email>-<plan>.json     # Codex OAuth tokens
```

The JSON files contain refresh tokens — treat them like passwords.

---

## Environment variables for `setup.sh`

| Var | Default | Purpose |
| --- | --- | --- |
| `INSTALL_DIR` | `~/bin` | Where to put the binary |
| `CONFIG_DIR` | `~/.cli-proxy-api` | Where config + auth tokens live |
| `HOST` | `127.0.0.1` | Bind host |
| `PORT` | `8317` | Bind port |
| `CODEX_DEVICE_FLOW` | unset | Use device-code login (headless boxes) |
| `BUILD_FROM_SOURCE` | unset | `go build` from this checkout instead of downloading |

---

## Troubleshooting

- **Browser didn't open / headless server**: pass `-no-browser` to the login
  commands and paste the callback URL back. For Codex specifically,
  `CODEX_DEVICE_FLOW=1 bash setup.sh` is easier.
- **`401` from the proxy**: API key in the request doesn't match the one in
  `config.yaml`.
- **Image gen fails with quota errors**: ChatGPT plan's image quota is
  exhausted — wait for reset or add another Codex login for round-robin.

---

## Building from source

```bash
go build -o ~/bin/cliproxyapi ./cmd/server
```

Or via the setup script:

```bash
BUILD_FROM_SOURCE=1 bash setup.sh
```

For everything else — full feature list, SDK usage, management API, advanced
configuration — see [`UPSTREAM_README.md`](./UPSTREAM_README.md).

---

## License

MIT, inherited from upstream `router-for-me/CLIProxyAPI`. See
[`LICENSE`](./LICENSE).
