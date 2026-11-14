#!/usr/bin/env bash
# Read-only: lists the tasks a deploy would change, i.e. what drifted from the repo.
# No --diff on purpose: the rendered .env files carry vault values.
# Exit 1 when something drifted, so a timer can act on it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

out=$(ansible-playbook playbooks/stacks.yml --check 2>&1)
if ! printf '%s\n' "$out" | grep -q '^PLAY RECAP'; then
  printf '%s\n' "$out" | tail -15
  exit 2
fi

# A stopped container is not drift, but it hides its own checks.
down=$(printf '%s\n' "$out" | awk '/^PLAY RECAP/ {rcap=1} rcap && /unreachable=[1-9]/ {print $1}')
[ -n "$down" ] && echo "unreachable, not checked: $down"
drift=$(printf '%s\n' "$out" \
  | awk '/^TASK \[/ { task = $0 } /^changed: \[/ { print task }' \
  | sed 's/^TASK \[//; s/\].*//' | sort -u)

if [ -n "$drift" ]; then
  echo "drift — a deploy would change:"
  printf '%s\n' "$drift" | sed 's/^/  /'
  exit 1
fi
echo "no drift"
