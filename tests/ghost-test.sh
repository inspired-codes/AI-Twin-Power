#!/usr/bin/env bash
# Tests for bin/ghost. Runs in a throwaway folder and never touches a real bus.
#   bash tests/ghost-test.sh
set -uo pipefail

G="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/ghost"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
unset GHOST_AGENT_PID
export GHOST_POLL=0.2 GHOST_SETTLE=0.5 GHOST_DIR="$T/.ghosts" GHOST_PROJECT="alpha"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
BUS="$GHOST_DIR/bus.jsonl"

pass=0; fail=0
check() { if eval "$2"; then pass=$((pass + 1)); echo "  ok   $1"; else fail=$((fail + 1)); echo "  FAIL $1"; fi; }
start_wait() { WAIT_OUT="$T/wait.$RANDOM.out"; "$G" wait "$1" --timeout "${2:-5}" > "$WAIT_OUT" 2>&1 & WAIT_PID=$!; sleep 0.5; }
finish_wait() { wait "$WAIT_PID"; WAIT_RC=$?; }

echo "Ghost Bus tests"

# init and lookup
"$G" init "$T" >/dev/null
check "init creates bus and config" '[ -f "$BUS" ] && [ -f "$GHOST_DIR/config" ]'
check "init refuses an existing bus" '! "$G" init "$T" 2>/dev/null'
mkdir -p "$T/a/b"
check "finds the bus in a parent folder" '(cd "$T/a/b" && env -u GHOST_DIR "$G" status | grep -F "($T/.ghosts)" >/dev/null)'
check "status works on an empty bus" '"$G" status >/dev/null'
check "log works on an empty bus" '"$G" log >/dev/null'
check "help needs no bus" '(cd / && env -u GHOST_DIR "$G" help | grep "ghost send" >/dev/null)'

# waiting and addressing
"$G" send agy claude message "old history" >/dev/null
"$G" wait claude --timeout 1 >/dev/null; rc=$?
check "first wait skips old history and times out (exit 3)" '[ $rc -eq 3 ]'
"$G" wait agy --timeout 1 >/dev/null
start_wait claude
"$G" send agy claude question "Page or modal?" --body "Option A vs B" --ref spec.md:1-9 >/dev/null
finish_wait
check "event wakes the recipient (exit 0)" '[ $WAIT_RC -eq 0 ]'
check "output shows names, body and ref" 'grep -q "alpha-agy → alpha-claude \[question\]" "$WAIT_OUT" && grep -q "Option A vs B" "$WAIT_OUT" && grep -q "spec.md:1-9" "$WAIT_OUT"'
check "waiter files are removed" '[ ! -e "$GHOST_DIR/wait.alpha-claude.pid" ] && [ ! -e "$GHOST_DIR/watch.alpha-claude.json" ]'
start_wait agy
"$G" send claude agy spark "Use pure CSS" >/dev/null
"$G" send claude agy answer "Option A" >/dev/null
finish_wait
check "a burst is delivered in one wake" 'grep -q "2 event(s) for alpha-agy" "$WAIT_OUT"'
start_wait claude
"$G" wait claude --timeout 1 >/dev/null 2>&1; rc=$?
check "second waiter is refused (exit 4)" '[ $rc -eq 4 ]'
kill "$WAIT_PID"; wait "$WAIT_PID" 2>/dev/null
check "a killed waiter does not block the next one" '"$G" wait claude --timeout 1 >/dev/null 2>&1; [ $? -eq 3 ]'
start_wait claude
GHOST_PROJECT=beta "$G" send beta-agy alpha-claude request "Sync config" >/dev/null
finish_wait
check "message from another project wakes the recipient" 'grep -q "beta-agy → alpha-claude \[request\]" "$WAIT_OUT"'
"$G" send claude all message "mine" >/dev/null
"$G" wait claude --timeout 1 >/dev/null; rc=$?
check "own events never wake the sender" '[ $rc -eq 3 ]'
GHOST_PROJECT=beta "$G" wait agy --timeout 1 >/dev/null
"$G" send agy all review-request "review it" >/dev/null
GHOST_PROJECT=beta "$G" wait agy --timeout 1 >/dev/null; rc=$?
check "'all' does not wake another project" '[ $rc -eq 3 ]'
out="$("$G" wait claude --timeout 3)"
check "'all' wakes the same project" 'grep -q "review it" <<<"$out"'
"$G" send agy "*" message "to everyone" >/dev/null
out="$(GHOST_PROJECT=beta "$G" wait agy --timeout 3)"
check "'*' wakes another project" 'grep -q "to everyone" <<<"$out"'
"$G" wait claude --timeout 3 >/dev/null
"$G" send human "*-claude" message "to all claudes" >/dev/null
out="$("$G" wait claude --timeout 3)"
check "'*-claude' from the human wakes claude" 'grep -q "human → \*-claude" <<<"$out"'
"$G" send agy log message "silent" >/dev/null
"$G" wait claude --timeout 1 >/dev/null; rc=$?
check "'log' wakes nobody" '[ $rc -eq 3 ]'

# names and validation
check "project names with hyphens work" 'GHOST_PROJECT="My.Long-Project" "$G" send claude agy message hi | grep "my-long-project-claude → my-long-project-agy" >/dev/null'
check "invalid sender is refused" '! "$G" send nobody claude message hi 2>/dev/null'
check "invalid recipient is refused" '! "$G" send agy "*-nobody" message hi 2>/dev/null'
check "invalid type is refused" '! "$G" send agy claude gossip hi 2>/dev/null'
check "missing arguments are refused" '! "$G" send agy claude 2>/dev/null'

# config
cp "$GHOST_DIR/config" "$T/config.bak"
printf 'agents = claude zed # comment\nhuman = boss\naliases = cld:claude\nprojects = alpha:al\n' > "$GHOST_DIR/config"
check "config: agents, aliases and project names" '"$G" send cld zed message hi | grep "al-claude → al-zed" >/dev/null'
check "config: human name" '"$G" send boss zed message hi >/dev/null'
check "config: removed agents are refused" '! "$G" send agy zed message hi 2>/dev/null'
printf 'agents = claude\nhuman = $(touch %s/pwned)\n' "$T" > "$GHOST_DIR/config"
"$G" status >/dev/null 2>&1
check "config is never executed" '[ ! -e "$T/pwned" ]'
cp "$T/config.bak" "$GHOST_DIR/config"

# concurrency
before="$(tail -n 1 "$BUS" | jq .seq)"
pids=(); for i in $(seq 1 30); do "$G" send agy log message "parallel $i" >/dev/null & pids+=($!); done; wait "${pids[@]}"
check "30 parallel sends get 30 gap-free numbers" '[ $(( $(tail -n 1 "$BUS" | jq .seq) - before )) -eq 30 ] && [ "$(jq .seq "$BUS" | sort -n | uniq -d | wc -l)" -eq 0 ]'
pids=(); for i in $(seq 1 20); do a=claude; [ $((i % 2)) -eq 0 ] && a=agy; GHOST_PROJECT="p$i" "$G" lock acquire race "$a" x >> "$T/race" & pids+=($!); done; wait "${pids[@]}"
check "20 parallel acquires have exactly one winner" '[ "$(grep -c ACQUIRED "$T/race")" -eq 1 ]'

# locks
"$G" lock acquire server:web agy "deploying" >/dev/null
"$G" lock acquire server:web claude "want it" >/dev/null; rc=$?
check "a held lock is refused" '[ $rc -eq 1 ]'
"$G" lock acquire server:web gpt "me too" >/dev/null
check "lock status shows the holder" '"$G" lock status | grep "server:web .*HELD by alpha-agy" >/dev/null'
check "only the holder can release" '! "$G" lock release server:web claude >/dev/null'
start_wait claude
"$G" lock release server:web agy >/dev/null
finish_wait
check "release wakes a refused agent" 'grep -q "lock server:web released by alpha-agy" "$WAIT_OUT"'
check "release notifies every refused agent" 'jq -e "select(.type==\"lock\" and .to==\"alpha-gpt\")" "$BUS" >/dev/null'
"$G" lock acquire server:web agy "again" >/dev/null
check "steal needs a reason" '! "$G" lock steal server:web claude 2>/dev/null'
"$G" lock steal server:web claude "agent crashed" >/dev/null
check "steal takes the lock and is announced to everyone" 'tail -n 1 "$BUS" | jq -e ".to==\"*\" and (.text|contains(\"agent crashed\"))" >/dev/null'

# git hook
R="$T/repo"; git init -q -b main "$R"; git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
commit() { (cd "$R" && echo "$RANDOM" >> f && git add f && git commit -q -m "$1"); }
(cd "$R" && "$G" install >/dev/null)
"$G" lock acquire repo:alpha agy "hook test" >/dev/null
commit "feat: hook test"
check "a commit is posted in the name of the lock holder" 'tail -n 1 "$BUS" | jq -e ".type==\"commit\" and .from==\"alpha-agy\" and (.text|contains(\"hook test\"))" >/dev/null'
"$G" lock release repo:alpha agy >/dev/null
commit "feat: no lock"
check "without a lock the sender is unknown" 'tail -n 1 "$BUS" | jq -e ".type==\"commit\" and .from==\"unknown\"" >/dev/null'
check "install can be repeated" '(cd "$R" && "$G" install >/dev/null)'
printf '#!/bin/sh\necho mine\n' > "$R/.git/hooks/post-commit"
check "install never replaces another hook" '! (cd "$R" && "$G" install 2>/dev/null) && grep -q mine "$R/.git/hooks/post-commit"'
git -C "$R" config core.hooksPath custom
check "install respects core.hooksPath" '! (cd "$R" && "$G" install 2>/dev/null) && [ "$(git -C "$R" config core.hooksPath)" = custom ]'

# presence
sleep 300 & AGENT=$!
GHOST_AGENT_PID=$AGENT "$G" state agy working "building" >/dev/null
check "status: live agent is WORKING" '"$G" status | grep -E "^alpha-agy +WORKING" >/dev/null'
kill $AGENT; wait $AGENT 2>/dev/null
check "status: dead agent is GONE" '"$G" status | grep -E "^alpha-agy +GONE" >/dev/null'

# damage
echo 'not json' >> "$BUS"
check "send refuses a damaged bus" '! "$G" send agy claude message hi 2>/dev/null'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
