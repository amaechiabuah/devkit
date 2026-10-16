# Windows: set up WSL

**What you'll do:** Install the Windows Subsystem for Linux (WSL 2) with an Ubuntu distribution, then install
Docker and Compose v2 inside it, so you can run the dev kit on a Windows machine.

**What you need first:** A Windows 10 (2004+) or Windows 11 machine, and Administrator rights to install WSL.

The dev kit's scripts are POSIX shell, so on Windows you run everything from inside a WSL Linux
distribution, not from PowerShell or `cmd`. Ubuntu, the default distribution, is assumed from here on.

---

## 1. Install WSL

1. Open **PowerShell as Administrator** and run:

   ```powershell
   wsl.exe --install
   ```

   This installs the Windows Subsystem for Linux if it is not already present, and enables the Virtual
   Machine Platform feature it depends on.

2. **Reboot** when it finishes. The reboot is what turns the new features on.

## 2. Install Ubuntu

1. After the reboot, open PowerShell and run the same command again:

   ```powershell
   wsl.exe --install
   ```

   This time it downloads the Ubuntu distribution, then prompts you to create a user account.

2. Choose a **username and password** for Linux.

   > **This account is not your Windows account.** It exists only inside Ubuntu, and its password is the
   > one `sudo` asks for. Pick something you will remember.

When it finishes you are at an Ubuntu shell. Every command in the rest of this page, and in the rest of the
documentation, runs there.

## 3. Install Docker and Compose

1. Update the package index, upgrade installed packages, and install Docker and Compose v2.

   ```bash
   sudo apt update && sudo apt upgrade -y && sudo apt install -y docker.io docker-compose-v2
   ```

2. Add your user to the `docker` group, so you do not need `sudo` for every Docker command.

   ```bash
   sudo usermod -aG docker $USER
   ```

3. Leave the shell. Group membership is only read at login, so the change needs a fresh session.

   ```bash
   exit
   ```

4. Back in PowerShell, start Ubuntu again.

   ```powershell
   wsl ~
   ```

   The `~` drops you into your Linux home directory rather than the Windows directory PowerShell was in.

5. Check both at once.

   ```bash
   docker --version && docker compose version
   ```

   You should see a Docker version line, then a Compose line reading `v2.x` or newer. If `docker` reports
   it cannot connect to the daemon, start it with `sudo service docker start` and try again.

## 4. Keep the dev kit in the Linux filesystem

Clone the repo under your Linux home (`~`), not under `/mnt/c/...`. Files on the Windows drive are
far slower to read from Linux, and the build and hot-load loop touches a lot of files.

## What's next

WSL is ready, and `python3` ships with Ubuntu, so the [prerequisites](prerequisites.md) are met.
Continue with [1. Install and sign in](install.md) and run `./run.sh` from inside WSL, as that page describes.
