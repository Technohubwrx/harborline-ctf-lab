# Harborline CTF Lab

Build scripts for **Harborline**, an easy-to-medium boot2root Capture The Flag
machine, plus a one-command [CTFd](https://ctfd.io) scoreboard. Point it at a
fresh Ubuntu Server VM, run one script, and you have a themed six-flag box that
scores partial credit on a separate server.

These scripts let **educators build the CTF**. Students never see this
repository; they only receive the finished, exported VM.

> **Ethics and scope.** Harborline is vulnerable *by design*. Run it only on an
> isolated lab network you control, for teaching and authorized practice. Never
> deploy it on a network you do not own.

---

## What you get

- **Six staged flags, 800 points.** A player who only reaches the foothold still
  earns partial credit, so the box suits mixed-ability classes.
- **One attack path, no rabbit holes.** Recon -> portal login -> file-upload
  foothold -> password-reuse pivot -> cron privilege escalation.
- **Reproducible.** Every build regenerates fresh random flags, so one class's
  answers do not work for the next.
- **Separate scoreboard.** CTFd runs on its own VM, so compromising the target
  never exposes the scores.

The attack path and solution are intentionally **not** documented here, so this
repo can sit beside a public release without spoiling it.

## Lab layout

| Machine | Role | Scripts |
| --- | --- | --- |
| Ubuntu Server 24.04 VM | The vulnerable CTF machine | `ubuntu/harborline_setup.sh`, `ubuntu/harborline_finalize.sh` |
| Kali Linux VM | CTFd scoreboard (and your test attacker box) | `kali/kali_ctfd_setup.sh`, `kali/push_challenges.py` |

Any hypervisor works (VMware Workstation/Player, VirtualBox). The examples use a
single **NAT** network so the two VMs can reach each other and the Ubuntu box can
fetch packages during the build.

## Quick start

### 1. Base Ubuntu VM

Install **Ubuntu Server 24.04 LTS** in a VM (2 GB RAM, 1 CPU, 20 GB disk is
plenty). Tick **Install OpenSSH server** during setup. Use a sudo-capable build
account -- the examples below assume `srvadm`.

Prefer not to install from scratch? A ready-made clean Ubuntu base image is
linked under [Downloads](#downloads). Log in as **`srvadm` / `srvadm`** and
**change the password** before you do anything else.

### 2. Build the CTF (on Ubuntu)

Copy the Ubuntu scripts over and run the setup:

```bash
scp ubuntu/*.sh srvadm@<ubuntu-ip>:~
ssh srvadm@<ubuntu-ip>
sudo bash harborline_setup.sh
```

In ~5-15 minutes it updates the system and configures every service, the
vulnerable web portal, the privilege-escalation path, and six random flags.
It writes the answer key to `~/harborline_flags.json`.

### 3. Scoreboard (on Kali)

```bash
scp kali/* kali@<kali-ip>:~
ssh kali@<kali-ip>
sudo bash kali_ctfd_setup.sh
```

Then open `http://127.0.0.1:8000`, finish the setup wizard in **User mode**,
create an admin **Access Token** (Settings -> Access Tokens), copy the flags over
and load the challenges:

```bash
scp srvadm@<ubuntu-ip>:harborline_flags.json ~
python3 push_challenges.py --url http://127.0.0.1:8000 --token <TOKEN> --flags harborline_flags.json
```

### 4. Test-solve

Register a **non-admin** player account in CTFd and solve the box end to end
from Kali, submitting each flag. Only the two Recon challenges are unlocked at
first; the rest unlock in sequence as you solve.

### 5. Finalize and export

This is the step that makes the box safe to hand out: it **deletes the `srvadm`
build account** (an easy shortcut to root), wipes the flag files, logs and
histories, and powers the VM off.

```bash
# take a hypervisor snapshot first, so you can get back in later
sudo bash harborline_finalize.sh   # type YES when prompted
```

Then export the powered-off VM (VMware: **File -> Export to OVF**; VirtualBox:
**File -> Export Appliance**). Distribute that OVA/OVF to students and publish its
SHA-256 so they can verify it.

> **Do not distribute the base image from step 1 as the CTF.** Until
> `harborline_finalize.sh` has run, `srvadm` still exists with sudo and the box is
> trivially rootable. Students get the *finalized* export only.

## Rebuilding for a new class

Restore your pre-finalize snapshot, re-run `harborline_setup.sh` (new flags),
copy the new `harborline_flags.json` to Kali, and re-run `push_challenges.py`.
Reloading replaces the challenges and clears their old solves.

## Downloads

- **Clean Ubuntu base image (OVA):** [Google Drive](https://drive.google.com/drive/folders/1mg_gSABh3vBghZXd87VCGwZmH70J91u7?usp=sharing)
  Login: `srvadm` / `srvadm` -- change the password immediately.
  This is a build base for educators, **not** the student CTF box.

## Repository layout

```
ubuntu/
  harborline_setup.sh      build the CTF machine
  harborline_finalize.sh   remove the build account + traces, then power off
kali/
  kali_ctfd_setup.sh       install Docker + CTFd
  push_challenges.py       load challenges, flags, hints, unlock order
  challenges.json          names, points, categories, hints (no flags)
docs/
  screenshots and notes
```

The flag values live only in `harborline_flags.json`, which the build generates
locally and which is **git-ignored** -- it is never committed here.

## License

MIT -- see [LICENSE](LICENSE).
