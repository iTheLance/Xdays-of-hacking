#!/bin/bash
# git_recon.sh — Git Repository Intelligence Tool
# Day1 Build | iTheLance | Xdays-of-hacking
#
# Usage: ./git_recon.sh [path_to_repo]
# Default: current directory
#
# What it does:
#   - Dumps contributor emails and names (OSINT gold)
#   - Lists all branches (local + remote)
#   - Shows commits that touched sensitive-looking files
#   - Greps diffs for common secret patterns (API keys, passwords, tokens)
#   - Shows files that were deleted (devs love deleting secrets and thinking they're gone)
#   - Prints the full reflog summary (catches squashed/amended commits)

RED='\033[0;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYN}"
    echo "  ██████╗ ██╗████████╗    ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗"
    echo "  ██╔════╝ ██║╚══██╔══╝    ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║"
    echo "  ██║  ███╗██║   ██║       ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║"
    echo "  ██║   ██║██║   ██║       ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║"
    echo "  ╚██████╔╝██║   ██║       ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║"
    echo "   ╚═════╝ ╚═╝   ╚═╝       ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝"
    echo -e "${NC}"
    echo -e "${YEL}  Git Repository Intelligence Tool | Day1 Build${NC}"
    echo "  ──────────────────────────────────────────────────"
}

section() {
    echo ""
    echo -e "${GRN}[+] $1${NC}"
    echo "  ──────────────────────────────────"
}

warn() {
    echo -e "${RED}[!] $1${NC}"
}

REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
    warn "Not a git repo: $REPO"
    exit 1
fi

cd "$REPO" || exit 1

banner
echo -e "  Target repo: ${CYN}$(pwd)${NC}"
echo ""

# ── 1. CONTRIBUTORS (OSINT) ─────────────────────────────────────────────────
section "Contributors (names + emails)"
git log --format='%aN <%aE>' | sort -u

# ── 2. COMMIT COUNT PER AUTHOR ───────────────────────────────────────────────
section "Commit count per author"
git shortlog -sne --all

# ── 3. ALL BRANCHES ──────────────────────────────────────────────────────────
section "Branches (local + remote)"
git branch -a

# ── 4. TAGS ───────────────────────────────────────────────────────────────────
section "Tags"
git tag -l | head -20
[ "$(git tag | wc -l)" -gt 20 ] && echo "  ... ($(git tag | wc -l) total)"

# ── 5. SENSITIVE FILE COMMITS ────────────────────────────────────────────────
section "Commits touching sensitive filenames"
SENSITIVE_PATTERNS=(".env" "config" "secret" "password" "passwd" "credential" \
                    "id_rsa" "id_dsa" ".pem" ".key" "token" "api_key" "access_key" \
                    "auth" ".htpasswd" "shadow" "wallet" "private")

for pat in "${SENSITIVE_PATTERNS[@]}"; do
    hits=$(git log --all --name-only --format="" -- "*$pat*" 2>/dev/null | grep -i "$pat" | sort -u)
    if [ -n "$hits" ]; then
        warn "Pattern '$pat' found in history:"
        echo "$hits" | while read -r f; do echo "      $f"; done
    fi
done

# ── 6. SECRET GREP IN DIFFS ──────────────────────────────────────────────────
section "Secret patterns in diffs (last 500 commits)"
SECRET_REGEX='(password|passwd|secret|api[_-]?key|access[_-]?key|token|private[_-]?key|BEGIN (RSA|EC|OPENSSH)|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|glpat-[0-9A-Za-z]{20})'

git log --all -p --max-count=500 2>/dev/null \
    | grep -iE "^\+.*$SECRET_REGEX" \
    | grep -v "^+++\|^---" \
    | head -50 \
    | while IFS= read -r line; do
        warn "  $line"
    done

echo "  (Showing up to 50 hits)"

# ── 7. DELETED FILES ─────────────────────────────────────────────────────────
section "Deleted files (still in history)"
git log --all --diff-filter=D --name-only --format="" | sort -u | head -40

# ── 8. LARGE BLOBS (potential binary secrets / embedded data) ─────────────────
section "Largest objects in pack (top 10)"
git rev-list --objects --all 2>/dev/null \
    | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
    | awk '/^blob/ {print $3, $4}' \
    | sort -rn \
    | head -10 \
    | while read -r size path; do
        printf "  %8d bytes  %s\n" "$size" "$path"
    done

# ── 9. REFLOG ─────────────────────────────────────────────────────────────────
section "Reflog (local) — catches amended/squashed commits"
git reflog --format="%h %gd %gs" 2>/dev/null | head -20

# ── 10. REMOTE ORIGINS ────────────────────────────────────────────────────────
section "Remote URLs"
git remote -v

echo ""
echo -e "${CYN}[*] Recon complete.${NC}"
echo ""
