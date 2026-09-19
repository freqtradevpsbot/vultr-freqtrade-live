# Handing SSH to the agent without handing over the key

Goal: the agent runs commands on the VPS; the person never types the passphrase into chat and
the agent never reads the private key file.

## ssh-agent on Windows (person)

Once, in an **administrator** PowerShell:

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

Then in a normal PowerShell, typing the passphrase locally:

```powershell
ssh-add "$env:USERPROFILE\.ssh\vultr_freqtrade"
ssh-add -l
```

One fingerprint line means loaded. Windows' ssh-agent persists loaded keys across reboots, so
this is a one-time step — which also means the key stays usable by any process running as this
user until it is removed:

```powershell
ssh-add -d "$env:USERPROFILE\.ssh\vultr_freqtrade"
```

Say this out loud to the person: **while the key is loaded, the agent can reach the VPS at any
time.** That is the point of the hand-off, and the reason to remove the key when the work is
done, or to use a dedicated key.

## A dedicated agent key (recommended for long engagements)

Make a second key pair for the agent's use, add its `.pub` as its own line in the VPS
`~/.ssh/authorized_keys`, and load only that one into ssh-agent. Revocation is then deleting one
line on the server; the person's own key never leaves their hands.

## What the agent's sandbox can and cannot do (Codex desktop, verified)

- The sandboxed shell cannot read `~/.ssh` (permission denied on the identity file and on the
  person's `known_hosts`) and cannot open the ssh-agent socket (`ssh-add -l` → permission denied).
- SSH therefore runs as **escalated** commands. The platform's own reviewer judges each one
  against what the person authorized in the conversation; expect to justify every command in
  one sentence and expect a deny when a step exceeds what was said (one live-config upload was
  denied for exactly that reason and the agent asked the person first). That is the safety net
  working, not an obstacle to route around.
- Keep a **project-local `known_hosts`** because the person's file is unreadable:

```powershell
ssh -o BatchMode=yes -o ConnectTimeout=15 `
    -o StrictHostKeyChecking=accept-new `
    -o "UserKnownHostsFile=<project>\vultr_known_hosts" `
    linuxuser@<VPS_IP> "hostname; whoami; free -h; df -h /; sudo -n true && echo SUDO_OK"
```

  First connection uses `accept-new` (trust on first use — acceptable when the person has already
  connected to the same address from the same machine); every later command uses
  `StrictHostKeyChecking=yes`. Add the file to `.gitignore`; it carries the server's address.

- `BatchMode=yes` makes a missing key fail fast instead of hanging on a prompt the agent cannot
  answer. `-o IdentitiesOnly=yes -i <path>` selects the key by path while the agent still signs
  through ssh-agent; the passphrase is never asked.
- Never `Get-Content` a private key, never echo `ssh-add` output beyond the fingerprint line, never
  put a key or passphrase in a command line.

## Shell traps between Windows and the VPS

- PowerShell rewrites nested quotes inside the remote command string; a Python one-liner with
  `\"` dies with a syntax error on the far side. Generate files server-side with `jq` /
  `openssl rand`, or ship a script file with `scp` and run it.
- Files edited on Windows carry CRLF. On the VPS: `sed -i 's/\r$//' *.sh && chmod 750 *.sh`.
- Long jobs (`docker compose pull`, data downloads): add `-o ServerAliveInterval=30` and `-tt`
  only when the remote tool needs a TTY; compose's progress bars then flood the output — pipe
  through `--no-color`/`--quiet` variants where they exist.
- `scp -r <folder> linuxuser@<VPS_IP>:/home/linuxuser/` copies the whole bundle; re-upload single
  files after edits rather than the folder.
