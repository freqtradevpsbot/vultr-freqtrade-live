# vultr-freqtrade-live

An [Agent Skill](https://github.com/agentskills/agentskills) for taking a backtested crypto
strategy to a [freqtrade](https://www.freqtrade.io/) bot running in Docker on a
[Vultr](https://www.vultr.com/) VPS — with an AI coding agent (Codex, Claude Code, or any
agent that reads `SKILL.md`) doing the server work while the person keeps every secret and
every money decision.

It is an operations runbook. The one strategy file in it is a port template — an EMA crossover
with a fixed stop and a post-stop lock — kept so the commands have something to run; it is not a
recommendation, and nothing here is a signal or a claim about returns.

## What it covers

1. **Porting** a rule set to a freqtrade `IStrategy` and the places ports silently diverge
   (fill model, fees, `minimal_roi`, protections, warm-up).
2. **Vultr console** — plain Ubuntu, SSH key registered before deploy, Limited User Login,
   a firewall group with one inbound rule (TCP 22 from a single `/32`), backups, and an honest
   account of what an SSH passphrase does and does not protect.
3. **Handing SSH to the agent** through ssh-agent, without the key or passphrase ever entering
   the conversation; what an agent sandbox can and cannot reach; a project-local `known_hosts`.
4. **Docker backtest on the VPS** with the official image and the flags that matter
   (`--enable-protections`, `--cache none`, `--timeframe-detail`).
5. **Ledger parity** — trade-by-trade comparison against the original backtest as the gate
   before any exchange key exists.
6. **Live cutover** — dry-run by default; secrets in a mode-600 file the person types; first
   start `stopped` to prove authentication with no order possible; startup state computed from
   the last closed candle; force-enter only after an explicit yes on the exact amount;
   exchange-side stop-loss; `initial_state: running` as a separately requested authorization.
7. **Operations** — what survives a restart or a lost disk, backups of the trade DB, preflight
   checks, image updates, and a hand-over rule for changing parameters while a position is open.

Everything in it ran end to end on 2026-09-18: freqtrade 2026.8, Ubuntu 24.04 on a 1 vCPU /
1 GB Vultr instance, Windows 11 client with PowerShell + OpenSSH, Codex desktop as the agent.
53 of 54 backtest trades matched the original engine's ledger; the 54th was the forced close
on a different end date.

## Install

Codex / ChatGPT desktop — ask the agent, which uses its built-in `skill-installer`:

```
$skill-installer install the skill at https://github.com/freqtradevpsbot/vultr-freqtrade-live/tree/main/skills/vultr-freqtrade-live
```

Any agent, via the [skills.sh](https://skills.sh) CLI:

```
npx skills add https://github.com/freqtradevpsbot/vultr-freqtrade-live --skill vultr-freqtrade-live
```

Claude Code: copy `skills/vultr-freqtrade-live` into `~/.claude/skills/` (verified), or add
the repo as a plugin marketplace — `/plugin marketplace add freqtradevpsbot/vultr-freqtrade-live` —
which uses the manifests under `.claude-plugin/` (present, not yet exercised).

## Layout

```
skills/vultr-freqtrade-live/
  SKILL.md                 the workflow, roles, hard rules, verified gotchas
  references/              one document per phase
  assets/                  compose (backtest, dry, live), configs, strategy template, backtest scripts — pinned to the verified image
  scripts/                 extract-trades.py · make-api-config.sh · backup-db.sh · vps-preflight.sh
```

## Disclaimer

Trading cryptocurrencies with real capital can lose all of it. This repository documents a
procedure; it does not recommend any strategy, position size, exchange or provider, and past
backtest agreement between two engines says nothing about future returns. Every order placed
by following it is placed by the person's explicit decision.

## License

MIT — see [LICENSE](LICENSE).
