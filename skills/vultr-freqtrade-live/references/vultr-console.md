# Vultr console — what the person clicks

The agent cannot press these buttons (they start billing and register credentials), so it
guides, checks screenshots when offered, and never asks for the account password or the key.

## Instance

- **Products → Compute → Deploy.** Type `Shared CPU`, plan `Cloud Compute`. For one pair on a
  daily timeframe, **1 vCPU / 1 GB / 25 GB / 1 TB** is enough (verified: daily + 1-hour-detail
  backtests over eight years, one at a time). Pick 2 GB for several pairs or hyperopt.
- Location: a region from which the exchange allows API access — Binance blocks several server
  countries (freqtrade's exchange notes name Canada, Malaysia, the Netherlands and the United
  States as a non-exhaustive list; US accounts use the `binanceus` exchange id). Within the
  allowed regions, nearest is fine; latency is irrelevant on a daily strategy.
- **Software: plain `Ubuntu 24.04 LTS x64`.** Not a marketplace Docker or freqtrade image.
- Hostname/label: something like `freqtrade-btc-01`.
- Automatic backups: off is fine while testing; **on before going live** (about 20% of the
  instance price). IPv6 optional. VPC, block storage, DDoS: not needed. Startup script: empty.
- **Deploy starts billing. Stopping the instance does not stop billing; only destroying does.**

## SSH key (before Deploy)

The person generates the key on their own machine — Windows PowerShell shown:

```powershell
ssh-keygen -t ed25519 -a 100 -f "$env:USERPROFILE\.ssh\vultr_freqtrade"
Get-Content "$env:USERPROFILE\.ssh\vultr_freqtrade.pub"
```

The `.pub` line (starts with `ssh-ed25519`) is what goes into Vultr. The file without an
extension is the private key: never uploaded, never pasted, never shared.

**Passphrase: recommended, not required.** Be honest about what it protects:

- It protects the key **file at rest** — a backup, a cloud-synced `.ssh` folder, a stolen laptop
  without disk encryption, malware that copies files.
- It does **not** protect against a process running as the same user once the key is loaded
  into ssh-agent; that is exactly how the agent will use it. Windows' ssh-agent keeps loaded keys
  across reboots, so a passphrase costs one prompt, ever.
- The firewall's single-IP rule narrows the exposure but does not remove it: that `/32` is the
  household router's public address, shared by every device behind it, and a copy of the key
  used from the person's own PC has the same address. On the VPS this key is root in practice
  (Limited User Login grants passwordless sudo; the docker group is root-equivalent).
- If the person declines a passphrase: confirm disk encryption is on and `.ssh` is not synced.

Register it: **Orchestration → SSH Keys → Add SSH Key** (older UI: account menu → SSH Keys),
name it, paste the one `.pub` line. Back on the deploy page, refresh, select it. Changing keys
after deploy through the console can mean a reinstall; afterwards edit `authorized_keys` on the
server instead.

## Limited User Login

Turn it on. Login becomes `linuxuser` (not root), with `sudo` for what needs it. Verified: the
user has passwordless sudo, so treat the key as root and protect it accordingly.

## Firewall group (before Deploy)

**Network → Firewall → Add Firewall Group**, description e.g. `freqtrade-ssh-only`. Inbound IPv4:

| Field | Value |
|---|---|
| Protocol | SSH (TCP) |
| Port | 22 |
| Source | My IP (Vultr fills `<ip>/32` — exactly one address) |
| Note | e.g. `home PC` |

The pre-existing, uneditable **drop** rules for IPv4 and IPv6 are the default deny; leave them.
Do not open 8080 (FreqUI/API). By default the API lives inside the container and is reached
with `docker exec`; if the person wants FreqUI, the optional set-up in
[live-cutover.md](live-cutover.md) publishes it on the host's loopback only and an SSH tunnel
carries it — still nothing on the public interface. Refresh the deploy
page and pick the group in the Firewall Group field; linking happens at deploy.

When the person's ISP changes their public IP, only SSH is cut; the bot keeps running. Fix: edit
the rule's source to My IP again.

## First connection (person, not agent)

```powershell
ssh -i "$env:USERPROFILE\.ssh\vultr_freqtrade" linuxuser@<VPS_IP>
```

Two prompts look alike and mean opposite things:

- `Enter passphrase for key '...vultr_freqtrade':` — the key's own passphrase. Normal.
- `linuxuser@<VPS_IP>'s password:` — the server is asking for a password, so key auth did not
  work (wrong key selected at deploy, wrong file). Stop and fix before anything else.

Then hand SSH to the agent: [agent-ssh-handoff.md](agent-ssh-handoff.md).
