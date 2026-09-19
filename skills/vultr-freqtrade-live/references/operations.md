# Operating the live bot

## What survives what

| Event | Exchange stop order | Bot DB (memory of the position) | Signal exits / new entries |
|---|---|---|---|
| Graceful stop: `down`, recreate, image update, VPS shutdown | Stays with `cancel_open_orders_on_exit: false`. With `true` it may be cancelled and is re-placed only once the bot is back **and** `RUNNING` | On disk, reloaded | Resume only when running (`initial_state: running`, or `/start`) |
| Crash, power loss, kernel panic | Stays | On disk, last committed state | Same |
| VPS destroyed or disk lost | Stays | **Gone** — the bot no longer knows it holds the coin | Nothing manages the position |
| Person's home IP changes | Unaffected | Unaffected | Unaffected; only SSH is cut |

Two things are worth protecting: the exchange stop (keep the option `false`, see
[live-cutover.md](live-cutover.md)) and the trade DB.

## Backups

Do not `scp` the live `.sqlite` file itself — the bot can be mid-transaction, and a copy of the
main file without its journal is not a consistent database. `scripts/backup-db.sh` makes a
consistent snapshot through SQLite's online backup API (python3's `sqlite3` module, present on
Ubuntu), runs `PRAGMA integrity_check`, and prints the file to fetch:

```bash
cd ~/freqtrade_vps && ./backup-db.sh          # → backups/tradesv3.live.<stamp>.sqlite
```

```powershell
scp -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=<project>\vultr_known_hosts" `
    linuxuser@<VPS_IP>:/home/linuxuser/freqtrade_vps/backups/tradesv3.live.<stamp>.sqlite <project>\backup\
```

Also copy the three config files the person edited. Vultr's automatic backups (about 20% of the
plan price) cover the whole disk and are the simpler answer when the person accepts the cost;
turn them on before going live if so.

## Preflight after any change

`scripts/vps-preflight.sh` prints: Docker enabled at boot, the container's restart policy,
whether unattended-upgrades is on and whether it is allowed to reboot, whether a reboot is
pending, boot time and recent reboots, memory and disk, and anything listening on a non-loopback
address (expected: nothing but sshd). Verified defaults on Vultr's Ubuntu 24.04: Docker
enabled, unattended-upgrades enabled, **automatic reboot not configured** (security updates do
not restart the box on their own).

## Reading the bot

```bash
docker compose -f docker-compose.yml -f docker-compose.live.yml logs -f --no-color freqtrade
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json status
docker exec freqtrade-bot freqtrade-client --config /freqtrade/user_data/config-api-private.json balance
```

Daily habit for the person: bot status, the open orders page on the exchange (the stop must be
there), free balance drift. Errors to know by name: `Insufficient balance` (sizing versus fee
headroom), listen-key / websocket reconnects (harmless if they recover), rate limits.

## Updating the image

The compose file pins a release tag. Updating is a procedure, not a `pull`:

1. Read the release notes for every version between the pinned tag and the target.
2. Change the tag in `docker-compose.yml`, run the backtest with it, and compare the ledger with
   the run on the old tag (`scripts/extract-trades.py` twice). A changed ledger is a changed
   engine; decide whether the difference is acceptable before the bot runs on it.
3. Swap the live container (`up -d` recreates it) **while flat**, or at least with
   `cancel_open_orders_on_exit: false` confirmed, because a recreate is a graceful stop.

## Changing parameters while a position is open

Editing the strategy file and restarting is "replace the strategy", not "re-select
parameters": the open trade is thereafter managed by the **new** exit and stop rules. Decide
the hand-over rule first. With the stop kept where it is and the size unchanged, only the exit
timing changes, so the practical rule is a one-time state sync at the switch:

| Real position | New parameters say | Action |
|---|---|---|
| long | long | keep the position; new exit rule applies from now; stop unchanged |
| long | flat | exit now (the new rule's crossover already happened; the bot will not see it again) |
| flat | long | enter now (force-enter, with the usual explicit yes) |
| flat | flat | nothing |

Record the switch date and old/new values beside the configs. Note for people who validated a
walk-forward: most backtesters' walk-forward curves splice each window's returns and do not
model this hand-over or its fees, so the live procedure is an extra rule the backtest never
priced. Freqtrade can read parameter values from a JSON file next to the strategy (its
hyperopt "parameter file" mechanism for `IntParameter` / `DecimalParameter` attributes), which
keeps the code fixed and turns a monthly re-selection into a JSON edit plus a restart at the
right moment — see the freqtrade hyperopt documentation for the file's format.

## Revoking the agent

Delete its line from `~/.ssh/authorized_keys` on the VPS (if it has its own key) or `ssh-add -d`
on the person's machine; the bot does not depend on the agent being able to log in.
