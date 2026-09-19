# From backtest to live — dry-run first, then the overlay

Nothing in the base bundle changes. Dry-run is one overlay, live is another plus a secrets file
the person types, so a backtest can always be re-run with the base set alone. Do the steps in
this order; a step the person chooses to skip is written into the final answer in those words.

## 1. Exchange API key (person)

Binance, the exchange the steps were verified on:

- API key type **System-generated** (HMAC key + secret; what freqtrade's `exchange.key/secret`
  take). Self-generated RSA/Ed25519 works too but is the more complex path.
- Permissions: **Enable Reading**, **Enable Spot & Margin Trading**. **Withdrawals off.**
- **Restrict access to trusted IPs only** → the VPS's public IP. Binance requires an IP
  restriction before it lets trading permission on.
- The secret is shown once. It goes nowhere near the chat or the local project; the person
  types it on the VPS (step 4).

## 2. Dry-run (agent) — no key needed

Files: `user_data/config-dry.json` and `docker-compose.dry.yml` (own database
`tradesv3.dryrun.sqlite`, own log). Create the API credentials first if they do not exist yet
(`scripts/make-api-config.sh`), then:

```bash
docker compose -f docker-compose.yml -f docker-compose.dry.yml up -d
docker compose -f docker-compose.yml -f docker-compose.dry.yml logs --no-color --tail 80 freqtrade
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json status
```

What it proves: the strategy loads and computes the same signals on the live candle feed, the
sizing rule produces an order, the bot records it in its own DB, and the compose, logging and
restart plumbing work. What it does not prove — freqtrade's docs are explicit — the wallet is
the simulated `dry_run_wallet`, not the account, and with `stoploss_on_exchange` the stop is
"assumed to be filled" rather than placed as an exchange order. So the live start below still
begins `stopped` to prove the key, the real balance and the stop order.

Leave it running for as long as the person allows (a day sees one daily candle close). Stop it
with `docker compose -f docker-compose.yml -f docker-compose.dry.yml down` before the live
overlay starts — the two share the container name on purpose so they cannot run together.

## 3. Stage the live files (agent)

Copy `user_data/config-live.json.example` to `user_data/config-live.json` (git-ignored) and put
the person's sizing in. The example ships with `stake_amount` set to a placeholder string so
the bot refuses to start until someone has decided:

- a fixed `stake_amount` in the stake currency, or
- `"unlimited"` with `tradable_balance_ratio` — the ratio of the account's **total** stake-currency
  balance the bot may trade (freqtrade's wording); with `max_open_trades: 1` that whole share
  goes into one position, and it compounds as the balance grows.

Say, in the stake currency, what the first entry will spend. The example's other defaults stay:
`initial_state: stopped`, `force_entry_enable: false` (turn on only if step 6 needs it),
`cancel_open_orders_on_exit: false` (why: last section), market orders, exchange stop-limit
with `stoploss_on_exchange_limit_ratio: 0.99`.

`docker-compose.live.yml` adds `restart: unless-stopped`, the `trade` command, its own
`--db-url sqlite:////freqtrade/user_data/tradesv3.live.sqlite`, a log file, and the four
`--config` files in order (base, live, live-private, api-private). It publishes no port.

## 4. Secrets (person)

```bash
cd ~/freqtrade_vps
cp user_data/config-live-private.json.example user_data/config-live-private.json
chmod 600 user_data/config-live-private.json
nano user_data/config-live-private.json        # replace the two placeholders; Ctrl+O, Enter, Ctrl+X
```

The person says "done"; the agent never cats the file. `docker compose -f docker-compose.yml
-f docker-compose.live.yml run --rm freqtrade show-config … 2>&1 | grep -v -e key -e secret`
is the most the agent inspects.

## 5. First live start, stopped — proves auth with no order possible

```bash
docker compose -f docker-compose.yml -f docker-compose.live.yml up -d
docker compose -f docker-compose.yml -f docker-compose.live.yml logs --no-color --tail 120 freqtrade
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json balance
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json status
```

Look for the exchange authenticating, the wallet syncing, the strategy loading, and `STOPPED`.
`balance` shows the stake currency and what `bot_owned` will be under the sizing rule.

## 6. Startup state sync — the person decides

A fresh bot knows nothing about signals that fired before it started. Compute what the strategy
would be holding right now: download candles to a range end past today, then backtest with the
range ending at today's UTC date. **A backtest never leaves a trade open** — whatever is still
held at the range end is force-closed and recorded with `exit_reason: force_exit` and a
`close_date` equal to `backtest_end`. Read the last trade (`scripts/extract-trades.py` prints
it beside `backtest_end`):

- `exit_reason == force_exit` and `close_date == backtest_end` → the strategy was **in
  position** at the last closed candle.
- anything else (a signal exit or a stop before the range end) → **flat**.

If flat: start the bot; it waits for the next fresh signal. Done.

If in position, the person chooses:

- **Wait for the next fresh crossover** (cleanest; the bot then matches the backtest rules from
  its first trade). May miss the current leg.
- **Force-enter now.** The bot buys at today's price and its stop sits the strategy's distance
  below **today's fill**, not below the historical signal's entry. The trade is a real order the
  bot's DB records with a tag, so from then on the bot manages it exactly like its own.

Force-enter needs `force_entry_enable: true` in `config-live.json`, which is read at start:
set it, recreate the container (`up -d` — nothing is held yet, so the graceful-stop question
below does not arise), then print and get a yes on pair, side, `order_type=market`, the stake
in the stake currency (from `balance` × the sizing rule), and the stop that will be placed:

```bash
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json start
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json \
  forceenter BTC/USDT long order_type=market enter_tag=startup_state_sync
```

Verify: `status` shows the trade with `is_open`, `balance` shows the base currency as
`is_bot_managed`, and the exchange shows an open stop-limit order (trigger price and limit
price — with `limit_ratio 0.99` the limit sits 1% under the trigger). Write those numbers into a
status note next to the configs. Set `force_entry_enable` back to `false` in the file; it takes
effect at the next restart, which you schedule for the next flat moment (see the last section).

Never fix a missed historical signal by weakening the entry rule to "fast above slow": the
re-entry after a lock would then fire without a crossover, which is a different strategy from the
one that was validated.

## 7. Only now: unattended operation

`initial_state: "running"` makes the bot resume trading by itself after any restart of the
container or the VPS — a standing authorization to place orders unattended. Ask for it in those
words and change the overlay only after the yes. The running container is not restarted for
this (the file is read at start); verify the file on the server and leave the position alone.
Then read [operations.md](operations.md) for what can still go wrong.

## Optional: FreqUI through an SSH tunnel

By default the API server binds to 127.0.0.1 **inside the container** and nothing is published,
so the only way in is `docker exec … freqtrade-client` — an SSH tunnel to the host's port 8080
would find nothing there. If the person wants FreqUI, follow freqtrade's Docker guidance: set
`listen_ip_address` to `0.0.0.0` in `config-api-private.json` and uncomment the two `ports`
lines in `docker-compose.live.yml` (`"127.0.0.1:8080:8080"` — host loopback only; the docs warn
that `"8080:8080"` hands the bot to anyone who reaches the server). Then from the person's
machine `ssh -L 8080:127.0.0.1:8080 linuxuser@<VPS_IP>` and open `http://127.0.0.1:8080`.
Applying this recreates the container, so do it while flat or before the first live start.

## `cancel_open_orders_on_exit` — why the example says false

Freqtrade's docs: the option cancels open orders when `/stop` is issued, Ctrl+C is pressed or
the bot dies unexpectedly, "to cancel unfilled and partially filled orders in the event of a
market crash", and "does not impact open positions". For a strategy whose entries and exits are
market orders, the only open order it ever holds is the **exchange stop**. `true` therefore
protects nothing here, and if the stop order counts as an open order — the docs do not say; an
independent review that read the implementation says it does — every graceful stop (`docker
compose down`, an image update, a VPS shutdown) removes the stop until the bot is back and
`RUNNING`, and a bot that comes back `stopped` does not re-place it at all. `false` leaves the
stop on the exchange through a graceful stop; a crash leaves it either way. If a setup does use
resting limit orders, weigh the two risks explicitly instead of inheriting either default.
