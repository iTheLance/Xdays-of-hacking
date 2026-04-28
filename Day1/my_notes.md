# Day 1 — Git & GitHub
**Lance's Notes | Xdays-of-hacking**

---

## What the original guide covers
Surface-level: how to fork, clone, and submit a pull request to contribute to the repo. Good starting point but Git goes *much* deeper from a security standpoint.

---

## What I actually care about: Git as an attack surface

Git repos are treasure chests. Developers constantly commit secrets, credentials, and config files — then "delete" them thinking that fixes the problem. It doesn't. Git is append-only by design. Everything lives in the object store forever unless you explicitly rewrite history.

### The .git directory internals

```
.git/
├── objects/     ← All file content, commits, trees (SHA1-addressed blobs)
├── refs/        ← Branch/tag pointers (just files containing a SHA)
├── HEAD         ← Points to current branch
├── index        ← Staging area (binary)
├── config       ← Remote URLs, user info
├── logs/        ← Reflog — tracks every HEAD movement
└── packed-refs  ← Compressed version of refs/
```

The key insight: **every version of every file ever committed is still in `objects/`**. `git rm` only removes the file from the working tree and index — the blob object stays.

### How commits actually work

A commit object contains:
- Tree SHA (snapshot of the entire repo at that point)
- Parent SHA (previous commit)
- Author/committer metadata (name, email, timestamp)
- Commit message

The tree object maps filenames → blob SHAs. The blob object IS the file content. None of this is encrypted. It's just zlib-compressed data.

```bash
# Manually inspect any object
git cat-file -p <SHA>

# Walk the full tree of a commit
git ls-tree -r HEAD

# See what changed in a specific commit
git show <SHA>
```

---

## Security-relevant Git concepts

### 1. Secrets in history
Common scenario: dev commits `.env` with AWS keys, realises mistake, does `git rm .env && git commit`. The keys are **still in the previous commit's blob**. You can recover them:

```bash
# Find when the file existed
git log --all -- .env

# Check out the file from a specific commit
git show <commit_SHA>:.env
```

Tools like **trufflehog**, **gitleaks**, and **git-secrets** automate this pattern.

### 2. The reflog
The reflog is a local-only log of every time HEAD moved — including `git commit --amend`, rebases, and squashed commits. On a developer's machine:

```bash
git reflog
# Shows: HEAD@{0}, HEAD@{1} ... all the way back
git show HEAD@{5}  # See a "deleted" commit
```

This is why you should never trust that a sensitive commit was "cleaned up" without a full history rewrite.

### 3. Exposed .git directories
On misconfigured web servers, the `.git/` folder is often publicly accessible. If you can hit `https://target.com/.git/HEAD` and get `ref: refs/heads/main`, you can reconstruct the entire repository:

```bash
# Manual: fetch key files
curl https://target.com/.git/HEAD
curl https://target.com/.git/config
curl https://target.com/.git/logs/HEAD

# Automated
git-dumper https://target.com/.git/ ./dumped_repo
```

Tools: **git-dumper**, **gitjacker**, **GitHack**

### 4. Commit metadata for OSINT
Every commit leaks: author name, email, timestamp, and timezone offset. From a public GitHub repo you can:
- Map email → LinkedIn/Twitter
- Identify internal domains from corporate emails
- Correlate commit times with timezone to narrow geography
- Find personal emails leaked from work accounts

### 5. Force-push and history rewriting
`git push --force` can overwrite remote history, but:
- GitHub keeps a deletion log
- Forks already have the data
- GitHub's own CDN may cache old pack files
- `git reflog` on any clone that had the old commits preserves them

The only real fix for leaked secrets: rotate the credentials. History rewriting is theater.

---

## Build: git_recon.sh

A recon script that automates intel extraction from any local git repo.

**Location:** `codes/git_recon.sh`

**What it does:**
- Dumps all contributor emails + names (OSINT)
- Lists commit counts per author
- Enumerates all branches (local + remote)
- Searches commit history for sensitive filenames (`.env`, `.key`, `password`, etc.)
- Greps diffs for secret patterns: AWS AKIA keys, GitHub tokens (`ghp_`), GitLab tokens (`glpat-`), private key headers
- Lists all files ever deleted (still in object store)
- Shows the 10 largest blobs (useful for finding embedded binaries or data)
- Dumps the reflog

**Usage:**
```bash
chmod +x codes/git_recon.sh
./codes/git_recon.sh /path/to/target/repo
# or: ./codes/git_recon.sh  (defaults to current dir)
```

**Test run on this repo's own history:**
- Pulled 23 unique contributor emails immediately
- Found `config`-named files in history
- Identified the main contributor (proflamyt — 646 commits)

---

## Key commands I want to remember

```bash
# Clone including all branches + full history
git clone --mirror <url>

# Search entire history for a string
git log -p -S "password" --all

# Find all emails that ever committed
git log --format='%aE' | sort -u

# Recover a "deleted" file from history
git log --all --full-history -- "*filename*"
git checkout <SHA>^ -- path/to/file

# Check if .git is exposed on a web server
curl -s https://target.com/.git/HEAD | grep -q "ref:" && echo "EXPOSED"

# Rewrite history to nuke a file (nuclear option)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/secret" \
  --prune-empty --tag-name-filter cat -- --all
# Modern equivalent:
git filter-repo --path path/to/secret --invert-paths
```

---

## Resources I found useful

- [trufflehog](https://github.com/trufflesecurity/trufflehog) — secret scanning across git history
- [gitleaks](https://github.com/gitleaks/gitleaks) — fast, rule-based secret detection  
- [git-dumper](https://github.com/arthaud/git-dumper) — reconstruct repo from exposed .git/
- [git internals book chapter](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain) — essential reading
- [GitLab secret detection docs](https://docs.gitlab.com/ee/user/application_security/secret_detection/) — understand what platforms auto-scan for

---

## Takeaways

1. Git history is **immutable by default**. "Deleting" a secret is not removing it.
2. `.git/` exposure on web servers is a critical misconfiguration — full codebase dump possible.
3. Commit metadata (emails, timestamps) is OSINT fuel.
4. `trufflehog` and `gitleaks` should be in every recon workflow against orgs with public repos.
5. Always rotate leaked credentials. History rewrites are a false sense of security.
