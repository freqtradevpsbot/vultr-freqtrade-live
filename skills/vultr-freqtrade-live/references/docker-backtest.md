# Docker on the VPS and the backtest that proves the port

Everything here runs over SSH as the agent; nothing needs an exchange key. The bundle in
`assets/` is backtest-only by construction: `config.json` has `dry_run: true` and empty
exchange keys, and the compose file's default command is `list-strategies`.

## Install Docker (Ubuntu 24.04, verified)

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker linuxuser
sudo systemctl enable --now docker
docker --version && docker compose version
```

Ubuntu's own packages were enough (Docker 29.x, Compose 2.40). The docker group takes effect on
the next login; commands in the same session still work through `sudo` or a fresh SSH session.
Swap: run `swapon --show` before adding any — the tested Vultr image came with ~2.3 GB, which
is an observation about that image, not a guarantee. If it prints nothing, create a 2 GB
swapfile before running freqtrade on 1 GB.

## Upload the bundle

```powershell
scp -r -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=<project>\vultr_known_hosts" `
    <project>\freqtrade_vps linuxuser@<VPS_IP>:/home/linuxuser/
```

Then on the VPS: `cd ~/freqtrade_vps && sed -i 's/\r$//' *.sh && chmod 750 *.sh && docker compose config -q`.

## Check the strategy loads

```bash
docker compose pull
docker compose run --rm freqtrade list-strategies
```

The strategy must appear with status `OK`. Two things seen on 2026.8:

- `DUPLICATE NAME` beside the strategy when the compose command and the CLI both pass
  `--strategy-path user_data/strategies` — the same folder scanned twice. Pass it once.
- A refusal about `api_server.jwt_secret_key` length even with `api_server.enabled: false`.
  Remove the block from the backtest config; the live API config is a separate file.
- A refusal about missing `entry_pricing` / `exit_pricing` — required blocks since 2026.x; the
  asset `config.json` carries them.

## Download data with warm-up margin

```bash
docker compose run --rm freqtrade download-data \
  --config user_data/config.json --pairs BTC/USDT \
  --timeframes 1d --timerange 20170817-20260903
```

Start the range well before the backtest start so `startup_candle_count` is satisfied (Binance
BTC/USDT begins 2017-08-17). Data lands under `user_data/data/binance/`.

## Backtest

```bash
docker compose run --rm freqtrade backtesting \
  --config user_data/config.json --strategy EmaCrossStopLock \
  --pairs BTC/USDT --timeframe 1d --timerange 20180401-20260901 \
  --dry-run-wallet 1000 --fee 0.001 \
  --enable-protections --cache none --export trades --breakdown year
```

- The ranges above (and the defaults in the two scripts) are the values that were verified, not
  values to keep: set `DATA_RANGE` and `TEST_RANGE` to the person's data and today's date.
- `--enable-protections` — without it the post-stop lock never runs and the run still
  "succeeds". Check `locks` in the result (one lock per losing stop is what a working guard
  looks like).
- `--cache none` — a cached run hides a config change.
- `--timerange` end is exclusive of the end day's candle; the last open trade is force-closed
  there (`exit_reason: force_exit`).
- `--export trades --breakdown year` — the ledger and the per-year table the parity check reads.
- Optional second run with `--timeframe-detail 1h` (download `--timeframes 1d 1h` first): same
  signals, intrabar stop timing from hourly candles. If trade count, stop count and return do
  not move, intrabar assumptions are not what the result hangs on. Run it after the daily one,
  not in parallel, on 1 GB.

Results: `user_data/backtest_results/backtest-result-<stamp>.zip` holding the JSON (`strategy.<Name>`
with `trades`, `locks`, `results_per_enter_tag`, `exit_reason_summary`, yearly `periodic_breakdown`,
`wallet_stats`), the config used, the strategy file, and two feathers (market change, wallet).
`.last_result.json` names the newest. Copy the zip and its `.meta.json` back to the person's
machine with `scp` and keep them beside the bundle; `scripts/extract-trades.py` turns the JSON
into the CSV the parity step compares.

## Reading the headline numbers honestly

`profit_total` and `final_balance` are the all-in compounding result of `stake_amount:
"unlimited"` × `tradable_balance_ratio`; `market_change` is buy-and-hold over the same range;
`wallet_stats.max_drawdown_account` is the drawdown of the marked-to-market wallet (the number
most people mean by drawdown), while the top-level `max_drawdown_account` is measured on closed
trades only — on the verified run 24.3% against 16.2%, so name which one you quote. None of
these compare to a backtester with a different sizing rule or a different span — the ledger
does. Say which span and which sizing every number came from.
