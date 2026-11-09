# signal-cli

The Signal daemon Hermes' bundled `signal` platform plugin talks to. Not the
`bbernhard/signal-cli-rest-api` bridge: the adapter speaks signal-cli's own HTTP
interface (`/api/v1/rpc` for JSON-RPC 2.0, `/api/v1/events` for the SSE stream,
`/api/v1/check` for the health probe), which the JVM build serves directly.

## First run: link the account

There is no account in the image; link one once with a disposable QR.

```sh
docker exec -it signal-cli signal-cli link -n hermes
# prints sgnl://linkdevice?uuid=... — scan it in Signal: Ajustes > Dispositivos vinculados
```

The linked account keeps its keys in `./data`, which is what makes this
persistent. A linked device speaks as the account it was linked to; to keep the
agent on its own number, register instead of linking (needs an SMS/voice code):

```sh
docker exec -it signal-cli signal-cli -a +NUMBER register
docker exec -it signal-cli signal-cli -a +NUMBER verify CODE
```

`signal-cli listAccounts` shows what the daemon serves; with a single account no
`--account` flag is needed anywhere.

## Hermes side

Three variables in the agent's `.env` (profile `default`), then restart:

| variable | value |
|---|---|
| `SIGNAL_HTTP_URL` | `http://signal-cli:8080` (the container name on `ai-stack`) |
| `SIGNAL_ACCOUNT` | the linked number in E.164, e.g. `+15551234567` |
| `SIGNAL_ALLOWED_USERS` | comma-separated numbers/UUIDs allowed to DM the agent |

Credentials in the environment *are* the activation: with `SIGNAL_HTTP_URL` and
`SIGNAL_ACCOUNT` present the gateway enables the platform on its own, no
`gateway.platforms.signal` block required. Everyone else is denied, groups stay
off unless `SIGNAL_GROUP_ALLOWED_USERS` lists them, and `SIGNAL_HOME_CHANNEL`
routes cron/notification delivery. `Note to Self` messages count as inbound
(`syncMessage.sentMessage`), which is how you talk to an agent linked to your own
account.

## Notes

- No published port on purpose: the daemon authenticates nobody.
- `./data` is the whole state; a deploy never touches it (it is not in git).
