#!/bin/bash
# secret-guard.test.sh — regression / e2e suite for secret-guard.sh
#
# Drives the guard exactly the way Claude Code does: feeds a PreToolUse JSON
# payload ({tool_name, tool_input}) on stdin and asserts the contract —
# exit 0 = allow, exit 2 = block — plus the block reason on stderr.
#
# By default it runs the DEPLOYED hook (~/.claude/hooks/secret-guard.sh, the
# symlink Claude Code actually executes); override with HOOK=/path ./…test.sh.
# Also validates the settings.json wiring (registration + valid JSON).
#
# Usage:  claude/hooks/secret-guard.test.sh
# Exit:   0 = all green, 1 = at least one failure.

set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DEPLOYED="$HOME/.claude/hooks/secret-guard.sh"
HOOK_REPO="$DIR/secret-guard.sh"
HOOK="${HOOK:-$([ -e "$HOOK_DEPLOYED" ] && echo "$HOOK_DEPLOYED" || echo "$HOOK_REPO")}"
SETTINGS="$DIR/../settings.json"

pass=0; fail=0
FAILS=()

# assert <expected_exit> <reason_substr|-> <tool> <field> <value>
assert() {
    local exp="$1" reason="$2" tool="$3" field="$4" value="$5"
    local out rc ok=1
    out=$(jq -nc --arg t "$tool" --arg k "$field" --arg v "$value" \
              '{tool_name:$t, tool_input:{($k):$v}}' | "$HOOK" 2>&1)
    rc=$?
    [ "$rc" = "$exp" ] || ok=0
    if [ "$reason" != "-" ]; then
        printf '%s' "$out" | grep -qiF "$reason" || ok=0
    fi
    if [ "$ok" = 1 ]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        FAILS+=("[$tool] $value → exit=$rc (want $exp) :: $(printf '%s' "$out" | head -1)")
    fi
}

blkB() { assert 2 "$1" Bash command "$2"; }   # block bash, reason substr
blkA() { assert 2 -    Bash command "$1"; }   # block bash, any reason (dual-nature cmd)
alwB() { assert 0 -    Bash command "$1"; }   # allow bash
blkG() { assert 2 "$1" Grep pattern "$2"; }   # block grep tool
alwG() { assert 0 -    Grep pattern "$1"; }   # allow grep tool

echo "Hook under test: $HOOK"
echo

# ---------------------------------------------------------------- 1. files
echo "## secret file reads (expect BLOCK)"
for f in .env .env.local .env.production .env.development ".env.local.bak"; do
    blkB "reading a secret file" "cat $f"
done
blkB "reading a secret file" "head -n5 .env"
blkB "reading a secret file" "tail -f .env"
blkB "reading a secret file" "less .env"
blkB "reading a secret file" "bat .env"
blkB "reading a secret file" "sed -n '1,3p' .env"
blkB "reading a secret file" "awk -F= '{print \$2}' .env"
blkB "reading a secret file" "cut -d= -f2 .env"
blkB "reading a secret file" "xxd .env | head"
blkB "reading a secret file" "strings .env"
blkB "reading a secret file" "base64 .env"
blkB "reading a secret file" "nl .env"
blkB "reading a secret file" "tac .env"
blkB "reading a secret file" "cat ~/.ssh/id_rsa"
blkB "reading a secret file" "cat id_ed25519"
blkB "reading a secret file" "cat /etc/ssl/server.pem"
blkB "reading a secret file" "cat tls.key"
blkB "reading a secret file" "cat foo.secrets"
blkB "reading a secret file" "cat zsh/.zshrc.secrets"
blkB "reading a secret file" "cat ssh/config.local"
blkB "reading a secret file" "cat ~/.netrc"
blkB "reading a secret file" "cat ~/.pgpass"
blkB "reading a secret file" "cat ~/.aws/credentials"
blkB "reading a secret file" "cat /vault/secrets/db.txt"
blkB "reading a secret file" "cat config/secrets.yaml"
blkB "reading a secret file" "cat credentials.json"
blkB "reading a secret file" "source .env"
blkB "reading a secret file" ". ./.env"
blkB "reading a secret file" "while read l; do :; done < .env"
blkB "reading a secret file" "x=\$(<.env)"
blkB "reading a secret file" "cat ./config/secrets.yml"

echo "## env-file scaffolds & non-secret files (expect ALLOW)"
alwB "cat .env.example"
alwB "cat .env.template"
alwB "cat .env.sample"
alwB "cat .env.dist"
alwB "cat README.md"
alwB "cat package.json"
alwB "cat config.json"
alwB "cat claude/hooks/secret-guard.sh"
alwB "tail -5 claude/hooks/secret-guard.test.sh"
alwB "cat src/secret-manager.ts"
alwB "ls -la .env"
alwB "rm -f .env.bak"
alwB "mv .env .env.bak"
alwB "stat .env"
alwB "test -f .env && echo yes"

# ------------------------------------------------------------ 2. key search
echo "## secret key-name searches (expect BLOCK)"
blkB "searching for secret key names" "grep -r SECRET ."
blkB "searching for secret key names" "grep -ri token src/"
blkB "searching for secret key names" "rg API_KEY"
blkB "searching for secret key names" "rg ACCESS_KEY ."
blkB "searching for secret key names" "rg PRIVATE_KEY"
blkB "searching for secret key names" "ag PASSWORD"
blkB "searching for secret key names" "egrep CREDENTIALS ."
blkB "searching for secret key names" "cat app.log | grep API_SECRET"

echo "## non-secret searches (expect ALLOW)"
alwB "grep -r getSecretManager src"
alwB "grep -r secretsauce ."
alwB "grep -rn TODO ."
alwB "rg 'function main' src"
alwB "git log --grep=TOKEN"
alwB "git commit -m 'fix token refresh flow'"

echo "## commands that only MENTION secrets in quoted args (expect ALLOW)"
alwB "git commit -m \"feat: block reading .env, *.secrets and credentials.json\""
alwB "git commit -m \"fix grep over SECRET and TOKEN handling\""
alwB "echo \"see .aws/credentials and *.pem docs\""
alwB "git commit -m \"done. wired secret-guard for .env.* via Grep\""
# multi-line commit body (title + body) mentioning secrets — must be stripped whole
alwB "git commit -m \"feat: secret-guard\" -m \"blocks .env, *.secrets and grep over TOKEN
across multiple lines with credentials.json mentioned too\""

# ------------------------------------------------------------- 3. env dump
echo "## environment dumps & secret vars (expect BLOCK)"
blkB "dumping the environment" "printenv"
blkB "dumping the environment" "env"
blkA "env | grep TOKEN"   # dual-nature: env-dump AND key-search — block either way
blkB "dumping the environment" "printenv | sort"
blkB "dumping exported variables" "export -p"
blkB "dumping exported variables" "declare -x"
blkB "reading a secret environment variable" "printenv AWS_SECRET_ACCESS_KEY"

echo "## legit env usage (expect ALLOW)"
alwB "env NODE_ENV=prod node app.js"
alwB "env FOO=bar ./run.sh"
alwB "printenv PATH"
alwB "printenv HOME"

# ----------------------------------------------------- 4. variable echoing
echo "## echoing secret-named vars (expect BLOCK)"
blkB "echoing a secret-named variable" "echo \$API_TOKEN"
blkB "echoing a secret-named variable" "echo \"\${DB_PASSWORD}\""
blkB "echoing a secret-named variable" "printf '%s' \$AWS_SECRET_ACCESS_KEY"
blkB "echoing a secret-named variable" "echo \$MY_CLIENT_SECRET"

echo "## echoing safe vars (expect ALLOW)"
alwB "echo \$HOME"
alwB "echo \$PATH"
alwB "echo 'hello world'"
alwB "echo \$NODE_ENV"

# --------------------------------------------------------- 5. Grep tool
echo "## native Grep tool (expect BLOCK)"
blkG "Grep pattern targets secret key names" "API_SECRET"
blkG "Grep pattern targets secret key names" "PASSWORD"
blkG "Grep pattern targets secret key names" "(?i)token"
blkG "Grep pattern targets secret key names" "ACCESS_KEY"

echo "## native Grep tool (expect ALLOW)"
alwG "TODO|FIXME"
alwG "function\\s+main"
alwG "getSecretManager"
alwG "import React"

# --------------------------------------------- 6. documented bypass gaps
# These slip through because the read is hidden inside an interpreter the guard
# does not parse. The suite asserts the CURRENT behaviour (allow) so the doc
# stays honest — if any ever start blocking, that's an intentional change.
echo "## known bypass gaps (documented; expect ALLOW)"
alwB "python3 -c \"print(open('.env').read())\""
alwB "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\""
alwB "ruby -e 'puts File.read(\".env\")'"
# Quoting the path defeats the quote-stripping reader check (price of not
# false-positiving on commit messages / echo prose).
alwB "cat \".env\""
# A single compound `cp .env x && cat x` IS caught (both .env and cat appear in
# one command). The true gap is copy-then-read across SEPARATE tool calls, which
# the guard cannot correlate — not expressible as one payload.
echo "## compound copy-then-read in one command (expect BLOCK)"
blkB "reading a secret file" "cp .env /tmp/x && cat /tmp/x"

# ------------------------------------------------------------ 7. wiring
echo
echo "## settings.json wiring"
wpass=0; wfail=0
chk() { if eval "$2" >/dev/null 2>&1; then wpass=$((wpass+1)); else wfail=$((wfail+1)); echo "  FAIL: $1"; fi; }
chk "settings.json is valid JSON"            "jq -e . '$SETTINGS'"
chk "secret-guard registered for Bash"       "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[] | select(.command|test(\"secret-guard\"))' '$SETTINGS'"
chk "secret-guard registered for Grep"       "jq -e '.hooks.PreToolUse[] | select(.matcher==\"Grep\") | .hooks[] | select(.command|test(\"secret-guard\"))' '$SETTINGS'"
chk "deny rule for .env present"             "jq -e '.permissions.deny | index(\"Read(**/.env)\")' '$SETTINGS'"
chk "deny rule for *.secrets present"        "jq -e '.permissions.deny | index(\"Read(**/*.secrets)\")' '$SETTINGS'"
chk "deployed hook is executable"            "[ -x '$HOOK' ]"

# -------------------------------------------------------------- summary
echo
echo "=================== RESULTS ==================="
echo "tool-call assertions : $pass passed, $fail failed"
echo "wiring checks        : $wpass passed, $wfail failed"
if [ "$fail" -gt 0 ]; then
    echo
    echo "FAILURES:"
    for f in "${FAILS[@]}"; do echo "  - $f"; done
fi
echo "=============================================="
[ "$fail" -eq 0 ] && [ "$wfail" -eq 0 ]
