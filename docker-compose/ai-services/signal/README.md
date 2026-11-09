# signal-cli

The Signal daemon behind hermes' `signal` platform plugin. Not the
`bbernhard/signal-cli-rest-api` bridge: the adapter speaks signal-cli's own HTTP
interface (`/api/v1/rpc`, `/api/v1/events`, `/api/v1/check`).

## Link the account

```sh
docker exec -it signal-cli signal-cli link -n hermes
# scan the sgnl:// URI in Signal: Ajustes > Dispositivos vinculados
docker exec signal-cli signal-cli listAccounts
```

Keys live in `./data`. To keep the agent on its own number, register instead
(needs an SMS/voice code): `signal-cli -a +NUMBER register` + `verify CODE`.

## Hermes side

`SIGNAL_HTTP_URL=http://signal-cli:8080`, `SIGNAL_ACCOUNT=+NNN`,
`SIGNAL_ALLOWED_USERS=+NNN` in the profile's `.env`. Those two credentials are
the activation; no `gateway.platforms.signal` block is needed. Everyone not in
the allowlist is denied. `Note to Self` counts as inbound, which is how you talk
to an agent linked to your own account.
