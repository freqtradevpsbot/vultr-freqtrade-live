# From backtest to live — dry-run first, then the overlay

Nothing in the base bundle changes. Live is three more files (two overlays and a secrets file)
and one more compose file, so a backtest can always be re-run with the base set alone.

## 1. Exchange API key (person)

Binance, for the record the steps were verified on:

- API key type **System-generated** (HMAC key + secret; what freqtrade's `exchange.key/secret`
  take). Self-generated RSA/Ed25519 works too but is the more complex path.
- Permissions: **Enable Reading**, **Enable Spot & Margin Trading**. **Withdrawals off.**
- **Restrict access to trusted IPs only** → the VPS's public IP. Binance requires an IP
  restriction before it lets trading permission on.
- The secret is shown once. It goes nowhere near the chat or the local project; the person
  types it on the VPS (step 3).

## 2. Stage the live files (agent)

From `assets/`: `user_data/config-live.json` (overlay), `docker-compose.live.yml` (overlay),
`user_data/config-live-private.json.example`, and `scripts/make-api-config.sh`.

- `config-live.json`: `dry_run: false`, **`initial_state: "stopped"` for the first start**,
  sizing (`stake_amount` fixed number or `"unlimited"` + `tradable_balance_ratio`),
  `force_entry_enable: true` only if step 5 may need it, and `order_types` with
  `stoploss: "limit"`, `stoploss_on_exchange: true`, `stoploss_on_exchange_limit_ratio: 0.99`.
- `docker-compose.live.yml`: `restart: unless-stopped`, command `trade` with its own
  `--db-url sqlite:////freqtrade/user_data/tradesv3.live.sqlite`, `--logfile`, and the four
  `--config` files in order (base, live, live-private, api-private).
- `make-api-config.sh` writes `config-api-private.json` on the server with random credentials
  for an API server bound to **127.0.0.1:8080** — the agent drives the bot through
  `freqtrade-client` inside the container, and nothing is published on a host port.

Sizing is the person's number. `"unlimited"` × `tradable_balance_ratio` spends that share of
the **free** stake currency at each entry (so it compounds); a fixed `stake_amount` does not.
Say which one is configured and what it will spend at the first entry, in the stake currency.

## 3. Secrets (person)

```bash
cd ~/freqtrade_vps
cp user_data/config-live-private.json.example user_data/config-live-private.json
chmod 600 user_data/config-live-private.json
nano user_data/config-live-private.json        # replace the two placeholders; Ctrl+O, Enter, Ctrl+X
```

The person says "done"; the agent never cats the file. `docker compose -f docker-compose.yml
-f docker-compose.live.yml run --rm freqtrade show-config … 2>&1 | grep -v -e key -e secret`
is the most the agent inspects.

## 4. First start, stopped — proves auth with no order possible

```bash
docker compose -f docker-compose.yml -f docker-compose.live.yml up -d
docker compose -f docker-compose.yml -f docker-compose.live.yml logs --no-color --tail 120 freqtrade
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json balance
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json status
```

Look for the exchange authenticating, the wallet syncing, the strategy loading, and `STOPPED`.
Balance shows free stake currency and what `bot_owned` will be under the sizing rule.

## 5. Startup state sync — the person decides

A fresh bot knows nothing about signals that fired before it started. Compute what the strategy
would be holding right now by backtesting through the **last closed candle** (download with an
end date past today, backtest with the range ending at today's UTC date), then read the last
trade: open with no exit → "in position", otherwise flat.

If flat: start the bot; it waits for the next fresh signal. Done.

If in position, the person chooses:

- **Wait for the next fresh crossover** (cleanest; the bot then matches the backtest rules from
  its first trade). May miss the current leg.
- **Force-enter now**. The bot buys at today's price and its stop sits 5% (or whatever the
  stop is) below **today's fill**, not below the historical signal's entry. The trade is a real
  order the bot's DB records with a tag, so from then on the bot manages it exactly like its own.

Before a force-enter, print and get a yes on: pair, side, `order_type=market`, the stake in the
stake currency (from the balance call × ratio), and the stop that will be placed. Then:

```bash
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json start
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json \
  forceenter BTC/USDT long order_type=market enter_tag=startup_state_sync
```

Then verify: `status` shows the trade with `is_open`, `balance` shows the base currency as
`is_bot_managed`, and the exchange shows an open stop-limit order (trigger price and limit
price — with `limit_ratio 0.99` the limit sits 1% under the trigger). Write those numbers into a
status note next to the configs.

Never fix a missed historical signal by weakening the entry rule to "fast above slow": the
re-entry after a lock would then fire without a crossover, which is a different strategy from the
one that was validated.

## 6. Dry-run is the default; skipping it is a recorded choice

The same overlay with `dry_run: true` and a separate `--db-url` exercises authentication, sizing
and stop placement against real prices with no capital. A day of it costs nothing. If the person
chooses to go straight to live, say so in the final answer in those words.

## 7. Only now: unattended operation

`initial_state: "running"` makes the bot resume trading by itself after any restart of the
container or the VPS — a standing authorization to place orders unattended. Ask for it in those
words and change the overlay only after the yes. The running container is not restarted for
this (the file is read at start); verify the file on the server and leave the position alone.
Then read [operations.md](operations.md) for what can still go wrong.

## Known open question

`cancel_open_orders_on_exit: true` cancels unfilled orders on a graceful stop. Whether that
includes the exchange-side stop-loss order was **not verified** in the session this skill comes
from. Until it is: either test it deliberately at a calm moment (stop the container while
watching the exchange's open orders, then start it and confirm the stop is re-placed), or set it
to `false` while a position is held.
