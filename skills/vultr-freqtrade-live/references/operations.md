# Operating the live bot

## What survives what

| Event | Exchange stop order | Bot DB (position memory) | EMA exit / new entries |
|---|---|---|---|
| Container restart (`unless-stopped`) | stays on the exchange | on disk, reloaded | resume only if `initial_state: running` |
| VPS reboot (maintenance, kernel update) | stays | on disk, reloaded | same |
| VPS destroyed / disk lost | stays | **gone** — the bot no longer knows it holds the coin | nothing manages the position |
| Person's home IP changes | unaffected | unaffected | unaffected; only SSH is cut |

So the two things worth protecting are the exchange stop (already there) and the trade DB.

## Backups

Either turn on Vultr automatic backups (about 20% of the plan price) or copy the live DB and the
configs off the box on a schedule:

```powershell
scp -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=<project>\vultr_known_hosts" `
    linuxuser@<VPS_IP>:/home/linuxuser/freqtrade_vps/user_data/tradesv3.live.sqlite <project>\backup\
```

Copy the SQLite while the bot is idle between candles; a daily strategy has 23 quiet hours.

## Preflight after any change

`scripts/vps-preflight.sh` prints: Docker enabled at boot, the container's restart policy,
whether unattended-upgrades is on and whether it is allowed to reboot, whether a reboot is
pending, boot time and recent reboots. Verified defaults on Vultr's Ubuntu 24.04: Docker
enabled, unattended-upgrades enabled, **automatic reboot not configured** (so security updates
do not restart the box on their own).

## Reading the bot

```bash
docker compose -f docker-compose.yml -f docker-compose.live.yml logs -f --no-color freqtrade
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json status
docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json balance
```

Daily habit for the person: bot status, the open orders page on the exchange (the stop must be
there), free balance drift. Errors to know by name: `Insufficient balance` (sizing vs fee
headroom), listen-key / websocket reconnects (harmless if they recover), rate limits.

## Updating the image

`docker compose pull` then `up -d` recreates the container. Do it while flat, or after the
`cancel_open_orders_on_exit` question in [live-cutover.md](live-cutover.md) is settled, because
a recreate is a graceful stop.

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
