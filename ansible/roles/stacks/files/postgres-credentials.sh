#!/bin/sh
# Converge the Postgres cluster in <compose_dir> with the credentials of the
# stack's rendered .env.
#
# POSTGRES_USER/POSTGRES_PASSWORD are only consumed by the first initdb, so a
# vault rotation re-renders .env while the cluster keeps the roles it was born
# with. This renames the initdb superuser to the declared role when needed
# (ownership and grants follow the role OID, no volume is wiped) and always
# applies the password. It refuses to guess and exits non-zero on anything
# unexpected.
#
# Usage: postgres-credentials.sh <compose_dir> <service> <container> \
#                               <user_env> <password_env> <database_env>
# Prints changed=1 when the role had to be renamed, changed=0 when it was there.
set -eu

COMPOSE_DIR=${1:?compose dir}
SERVICE=${2:?compose service}
CONTAINER=${3:?container name}
USER_VAR=${4:?user env var}
PASSWORD_VAR=${5:?password env var}
DATABASE_VAR=${6:?database env var}

log() { printf 'postgres-credentials: %s\n' "$*" >&2; }

# Read .env the way Compose does, so no secret ever lands on a command line.
set -a
. "$COMPOSE_DIR/.env"
set +a
PG_ROLE=$(printenv "$USER_VAR")
PG_PASSWORD=$(printenv "$PASSWORD_VAR")
PG_DATABASE=$(printenv "$DATABASE_VAR")

if [ -z "$PG_ROLE" ] || [ -z "$PG_DATABASE" ]; then
  log "ERROR: $USER_VAR / $DATABASE_VAR are empty in $COMPOSE_DIR/.env"
  exit 1
fi

# psql over the local socket (pg_hba: local ... trust), tuples only. Silent on
# failure: callers use it to probe.
q() {
  docker exec "$CONTAINER" psql -U "$1" -d postgres -tAqc "$2" 2>/dev/null
}

role_exists() { [ "$(q "$1" 'select 1')" = "1" ]; }

cd "$COMPOSE_DIR"
docker compose up -d "$SERVICE" >/dev/null

tries=0
until docker exec "$CONTAINER" pg_isready -q -d postgres >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then
    log "ERROR: $CONTAINER did not become ready"
    docker logs --tail 20 "$CONTAINER" >&2 || true
    exit 1
  fi
  sleep 2
done

changed=0

if role_exists "$PG_ROLE"; then
  log "role $PG_ROLE already exists"
else
  # Only the owner of the application database is renamed. The name is read from
  # pg_authid on disk only to get candidates: a rename leaves dead tuples there,
  # so it is validated over SQL before being used.
  candidates=$(docker exec "$CONTAINER" sh -c \
    'grep -a -oE "[A-Za-z_][A-Za-z0-9_]{2,30}" "$PGDATA/global/1260" | sort -u' || true)
  owner=
  for c in $candidates; do
    role_exists "$c" || continue
    if [ "$(q "$c" "select pg_get_userbyid(datdba) from pg_database where datname = '$PG_DATABASE'")" = "$c" ]; then
      owner=$c
      break
    fi
  done
  if [ -z "$owner" ]; then
    log "ERROR: role $PG_ROLE is missing and no owner of database $PG_DATABASE was found"
    log "       refusing to guess; inspect: docker exec $CONTAINER psql -U <role> -d postgres -c '\\du'"
    exit 1
  fi
  # A session cannot rename its own role: a throwaway superuser does it.
  tmp="tmp_reconcile_$$"
  if ! q "$owner" "create role \"$tmp\" login superuser" >/dev/null; then
    log "ERROR: cannot create the temporary role from $owner"
    exit 1
  fi
  q "$tmp" "alter role \"$owner\" rename to \"$PG_ROLE\"" >/dev/null || {
    q "$owner" "drop role \"$tmp\"" >/dev/null || true
    log "ERROR: rename of $owner to $PG_ROLE failed"
    exit 1
  }
  q "$PG_ROLE" "drop role \"$tmp\"" >/dev/null || true
  log "renamed $owner -> $PG_ROLE (database $PG_DATABASE keeps its owner and grants)"
  changed=1
fi

# Converged unconditionally, so it is not reported as changed. The statement
# goes in through stdin, and the quotes are doubled here because psql 14 has no
# \getenv: this has to work on the oldest cluster we run.
escaped_password=$(printf '%s' "$PG_PASSWORD" | sed "s/'/''/g")
docker exec -i "$CONTAINER" psql -U "$PG_ROLE" -d postgres -q -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE "$PG_ROLE" WITH PASSWORD '$escaped_password';
SQL

if [ "$(q "$PG_ROLE" 'select 1')" != "1" ]; then
  log "ERROR: role $PG_ROLE is unusable after the update"
  exit 1
fi

log "role $PG_ROLE ready on database $PG_DATABASE"
echo "changed=$changed"
