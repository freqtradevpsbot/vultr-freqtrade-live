---
name: vultr-freqtrade-live
description: Take a backtested crypto strategy to a freqtrade bot running in Docker on a Vultr VPS, with an AI agent doing the server work and the person keeping every secret and every money decision. Covers Vultr console hardening (SSH key, Limited User Login, firewall group with a single-IP rule), handing SSH to the agent without sharing the key or passphrase, a Docker backtest on the VPS that must reproduce the original trade ledger trade by trade, and only then a Binance cutover (separate secrets file the person types, exchange-side stop-loss, startup state sync via force-enter, restart policy, backups). Use when the user asks to deploy or run a freqtrade bot on a VPS, to move a strategy from a backtester to freqtrade, to set up a Vultr server for a trading bot, or to go from dry-run to live.
license: MIT
metadata:
  verified-on: "freqtrade 2026.8 · Ubuntu 24.04 (Vultr Cloud Compute, 1 vCPU / 1 GB) · Vultr console 2026-09 · Windows 11 client with PowerShell + OpenSSH · Codex desktop as the agent"
  last-verified: "2026-09-18"
---

# vultr-freqtrade-live

An operations runbook, not a trading strategy. It says nothing about what to buy or when; it
says how to get a strategy the person has already validated onto a server, prove the port is
faithful, and switch it on without the agent ever holding a secret or making a money decision.

## Who does what

The person does these, always, and the agent never asks them to paste any of it into chat:

- Creates the Vultr instance, registers the SSH public key, creates the firewall group.
- Generates the SSH key pair on their own machine and (recommended) gives it a passphrase.
- Creates the exchange API key and types the key and secret into a file on the VPS themselves.
- Decides the position size, whether to skip dry-run, and whether to force-enter an existing
  signal, and says "yes" to the exact amount before any real order.

The agent does everything else over SSH: OS packages, Docker, uploading files, running
backtests, comparing ledgers, staging configs, starting the bot, reading balances and logs.

Three things never cross into the conversation: the SSH private key or its passphrase, the
exchange API secret, and the decision to place an order. If a step seems to need one of them
in chat, the step is wrong.

## The workflow, in order

Read the reference for the phase you are in. Skipping a phase is the person's call and gets
recorded in the answer ("dry-run skipped at the user's request").

1. **Port the strategy** to a freqtrade `IStrategy` — [references/strategy-port.md](references/strategy-port.md).
   Fill model, fees, stop, protections and `minimal_roi = {}` are where ports silently diverge.
2. **Vultr console** — [references/vultr-console.md](references/vultr-console.md). Plain Ubuntu,
   SSH key selected at deploy, Limited User Login on, firewall group with one inbound rule
   (TCP 22 from the person's IP /32), nothing else open. Deploy starts billing.
3. **Hand SSH to the agent** — [references/agent-ssh-handoff.md](references/agent-ssh-handoff.md).
   The person loads the key into ssh-agent; the agent connects with a project-local
   `known_hosts`, `BatchMode=yes`, and never reads or prints the key.
4. **Docker backtest on the VPS** — [references/docker-backtest.md](references/docker-backtest.md).
   Official image, backtest-only compose file, `--enable-protections` or the lock is silently
   off, results kept as the zip freqtrade writes.
5. **Ledger parity** — [references/ledger-parity.md](references/ledger-parity.md). Compare every
   trade's open/close date, rates, exit reason and profit ratio against the original backtest.
   Totals can agree by accident; ledgers cannot. Go live only when they match.
6. **Dry-run, then live** — [references/live-cutover.md](references/live-cutover.md). Dry-run
   runs first, on its own overlay and database, before any exchange key exists. Live is a
   config overlay copied from an example the person fills in, plus a secrets file the person
   types; the bot starts `stopped` so authentication is proven with no order possible; the
   startup state is read off a backtest through the last closed candle (a trade force-closed at
   the range end means "in position") and the person chooses wait or force-enter.
7. **Operate** — [references/operations.md](references/operations.md). Restart policy, backups
   (the trade DB is the bot's memory of the position), IP changes, image updates, and how to
   change parameters while holding a position.

## Hard rules

- **Backtest bundle first, then the dry overlay, then the live overlay.** The base config keeps
  `dry_run: true` and empty exchange keys; dry-run and live are second config files merged on
  top, plus a private secrets file that is git-ignored and mode 600. The live overlay ships only
  as an `.example` whose stake is a placeholder — the person's number goes in, never a default.
- **Pin the image.** `freqtradeorg/freqtrade:<release>` as verified, never `stable`; updating is a
  changelog read, a backtest on the new tag, and a swap while flat.
- **Market-order strategies leave `cancel_open_orders_on_exit` false.** Their only open order is
  the exchange stop; `true` would protect nothing and may take the stop down on every graceful
  stop until the bot is back and running.
- **Nothing listens on a public port.** FreqUI and the REST API bind to 127.0.0.1 inside the
  container with generated credentials; the person reaches them through an SSH tunnel if at all.
- **The first live start is `initial_state: stopped`.** It proves the API key, the balance
  sync and the strategy load with no order possible. Switch to running as a separate step.
- **State an order before placing it.** Pair, side, order type, the stake in the stake
  currency, and where the stop will sit. Wait for an explicit yes. Then place it once.
- **`initial_state: running` is a standing authorization to trade unattended.** Ask for it in
  those words. Do not set it because a restart policy seems to need it.
- **Never widen a rule to make a step easier.** No `0.0.0.0/0` inbound, no withdrawal permission
  on the API key, no API key in the base config, no key file copied to the VPS.
- **Record what the person chose to skip.** Dry-run, backups, passphrase: their call, written
  down in the final answer so they can revisit it.

## Gotchas verified on 2026-09-18

- freqtrade 2026.8 refuses a config without `entry_pricing` and `exit_pricing` blocks, and
  validates `api_server.jwt_secret_key` length (≥ 32 chars) even when `api_server.enabled` is
  false — omit the block entirely for backtests.
- `docker compose run … list-strategies --strategy-path user_data/strategies` shows every strategy
  twice as `DUPLICATE NAME` when the compose command already passes the same path. Not a real
  duplicate; pass the path once.
- `StoplossGuard` and every other protection do nothing in backtesting unless the command has
  `--enable-protections`. A backtest that matches the original only without the lock is a hint
  the lock was silently off, not that the lock is harmless.
- Shell scripts written on Windows arrive with CRLF; run `sed -i 's/\r$//' *.sh` on the VPS
  before `chmod +x`.
- A remote Python one-liner with nested quotes is mangled by PowerShell before it reaches ssh.
  Write the file with `jq` or `openssl rand` on the server, or send it base64-encoded.
- The agent's sandbox (Codex desktop) cannot read `~/.ssh` nor talk to the Windows ssh-agent;
  SSH steps run as escalated commands the platform's reviewer approves one by one. Keep a
  project-local `known_hosts`; the person's own file is unreadable from the sandbox.
- On a 1 GB instance run one freqtrade command at a time; an `--timeframe-detail 1h` backtest
  over eight years fits, a hyperopt does not. Check `swapon --show` first — the tested Vultr
  Ubuntu image came with a 2.3 GB swap, which is not a promise about every image.
- A backtest never leaves a trade open: whatever is still held at the range end is force-closed
  and recorded with `exit_reason: force_exit` on `backtest_end`. That row is how the startup
  state is read — not the absence of an exit.
- `freqtrade-client … reload_config` applies a config-file change to a running bot without
  recreating the container (state goes `RELOAD_CONFIG` → `RUNNING` in seconds). On 2026.8 it
  left the exchange stop order in place even with `cancel_open_orders_on_exit: true` (measured
  while holding); what a full container stop does to that order is still untested.
- In dry-run the wallet is `dry_run_wallet`, not the account, and an exchange stop is "assumed
  filled" rather than placed. Dry-run proves plumbing and signals; the `stopped` live start
  proves the key, the balance and the stop order.
- Vultr's console moved SSH keys under **Orchestration → SSH Keys** (older UI: Account → SSH
  Keys). The deploy page shows an empty SSH Keys list until one is registered and the page is
  refreshed.
- `stake_amount: "unlimited"` with `tradable_balance_ratio` spends that share of the account's
  stake-currency balance (the docs say total balance, not free) at each entry — it compounds.
  In a backtest `0.995` leaves room for the entry fee; `1.0` fails.

## What is in this folder

- `assets/` — the file set that ran, pinned to the verified image: backtest compose + dry and
  live overlays, base config + dry overlay + live overlay **example** + secrets-file example, a
  strategy template with a post-stop lock, the two backtest scripts.
- `scripts/` — `extract-trades.py` (result zip → CSV for parity; prints the last trade beside
  `backtest_end`), `make-api-config.sh` (localhost-only API credentials generated on the
  server), `backup-db.sh` (consistent copy of the live DB through SQLite's backup API),
  `vps-preflight.sh` (restart policy, unattended-upgrade reboot setting, reboot-required,
  uptime, non-loopback listeners).
- `references/` — one document per phase, with the exact commands that were verified.
