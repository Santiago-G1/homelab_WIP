#!/bin/sh
# Converge the Postgres credentials of an existing data directory with the
# stack's rendered .env.
#
# `POSTGRES_USER`/`POSTGRES_PASSWORD` are only consumed by the first initdb, so
# rotating them in the vault re-renders .env while the cluster keeps the roles it
# was born with. The app then dies with `28P01 password authentication failed`
# (and the server log says `Role "X" does not exist` when the user was renamed).
#
# This rotates the password of the declared role and, when that role does not
# exist yet, renames the data dir's superuser (the owner of the declared
# database) instead of wiping the volume. Ownership and grants follow the role
# OID, so the data is untouched.
#
# Usage: postgres-credentials.sh <compose_dir> <service> <container> \
#                               <user_env> <password_env> <database_env>
# Prints changed=1 on stdout when the role had to be renamed, changed=0 when it
# was already there. Exits non-zero and refuses to guess on anything unexpected.
set -eu

COMPOSE_DIR=${1:?compose dir}
SERVICE=${2:?compose service}
CONTAINER=${3:?container name}
USER_VAR=${4:?user env var}
PASSWORD_VAR=${5:?password env var}
DATABASE_VAR=${6:?database env var}

log() { printf 'postgres-credentials: %s\n' "$*" >&2; }

# Read .env the way Compose does and look the values up by name, so no secret is
# ever passed on a command line (where `ps` would show it).
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

# psql as an existing role over the local socket (pg_hba: local ... trust),
# tuples only. Silent on failure: callers use it to probe.
q() {
  docker exec "$CONTAINER" psql -U "$1" -d postgres -tAqc "$2" 2>/dev/null
}

role_exists() { [ "$(q "$1" 'select 1')" = "1" ]; }

cd "$COMPOSE_DIR"
# The database has to be up before anything can be reconciled; the app
# containers are started afterwards by the caller.
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
  # The initdb superuser owns the application database; that is the only role we
  # are willing to rename. Names are read from pg_authid on disk and then
  # validated over SQL: a rename leaves dead tuples behind, so finding a name in
  # that file does not prove the role still exists.
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
  # A session cannot rename its own role, so the rename runs from a throwaway
  # superuser (local socket auth is trust, so it needs no password).
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

# Always converge the password: it is the one thing that keeps a cluster created
# by an older .env from rejecting the credentials the stack was just deployed
# with. Applied unconditionally, so it is not reported as changed.
# The value travels in the environment and is read by psql with \getenv.
docker exec -e PW="$PG_PASSWORD" -i "$CONTAINER" \
  psql -U "$PG_ROLE" -d postgres -q -v ON_ERROR_STOP=1 <<SQL
\getenv pw PW
ALTER ROLE "$PG_ROLE" WITH PASSWORD :'pw';
SQL

if [ "$(q "$PG_ROLE" 'select 1')" != "1" ]; then
  log "ERROR: role $PG_ROLE is unusable after the update"
  exit 1
fi

log "role $PG_ROLE ready on database $PG_DATABASE"
echo "changed=$changed"
