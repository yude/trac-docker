#!/bin/sh
set -eu

TRAC_MODE="${TRAC_MODE:-single}"
TRAC_ENV="${TRAC_ENV:-}"
TRAC_ENV_PARENT="${TRAC_ENV_PARENT:-/var/trac/envs}"

TRAC_PROJECT_NAME="${TRAC_PROJECT_NAME:-trac}"
TRAC_PROJECTS="${TRAC_PROJECTS:-}"

TRAC_DB="${TRAC_DB:-sqlite:db/trac.db}"
TRAC_DB_TEMPLATE="${TRAC_DB_TEMPLATE:-}"

TRAC_PORT="${TRAC_PORT:-8000}"

TRAC_DEFAULT_LANGUAGE="${TRAC_DEFAULT_LANGUAGE:-ja}"
TRAC_DEFAULT_TIMEZONE="${TRAC_DEFAULT_TIMEZONE:-}"

TRAC_AUTH_TYPE="${TRAC_AUTH_TYPE:-basic}"
TRAC_AUTH_REALM="${TRAC_AUTH_REALM:-Trac}"
TRAC_AUTH_FILE="${TRAC_AUTH_FILE:-/var/trac/auth/htpasswd}"

TRAC_ADMIN_USER="${TRAC_ADMIN_USER:-admin}"
TRAC_ADMIN_PASSWORD="${TRAC_ADMIN_PASSWORD:-}"

validate_user_name() {
  name="$1"
  if [ -z "$name" ]; then
    return 1
  fi
  case "$name" in
    *[!A-Za-z0-9._@-]* )
      return 1
      ;;
  esac
  return 0
}

ensure_admin_auth() {
  case "$TRAC_AUTH_TYPE" in
    none)
      return 0
      ;;
    basic)
      if [ -z "$TRAC_ADMIN_USER" ]; then
        echo "[entrypoint] TRAC_AUTH_TYPE=basic requires TRAC_ADMIN_USER" >&2
        exit 2
      fi
      if ! validate_user_name "$TRAC_ADMIN_USER"; then
        echo "[entrypoint] Invalid TRAC_ADMIN_USER: $TRAC_ADMIN_USER" >&2
        exit 2
      fi

      mkdir -p "$(dirname "$TRAC_AUTH_FILE")"

      if [ -z "$TRAC_ADMIN_PASSWORD" ]; then
        TRAC_ADMIN_PASSWORD=$(python - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)
        pwfile="$(dirname "$TRAC_AUTH_FILE")/${TRAC_ADMIN_USER}.password"
        (umask 077 && printf '%s\n' "$TRAC_ADMIN_PASSWORD" >"$pwfile")
        echo "[entrypoint] Generated TRAC_ADMIN_PASSWORD and saved to: $pwfile" >&2
      fi

      if [ ! -f "$TRAC_AUTH_FILE" ]; then
        htpasswd -bc "$TRAC_AUTH_FILE" "$TRAC_ADMIN_USER" "$TRAC_ADMIN_PASSWORD" >/dev/null
      else
        htpasswd -b "$TRAC_AUTH_FILE" "$TRAC_ADMIN_USER" "$TRAC_ADMIN_PASSWORD" >/dev/null
      fi

      TRACD_AUTH_ARGS="--basic-auth *,$TRAC_AUTH_FILE,$TRAC_AUTH_REALM"
      export TRACD_AUTH_ARGS
      ;;
    *)
      echo "[entrypoint] Unknown TRAC_AUTH_TYPE: $TRAC_AUTH_TYPE (use 'none' or 'basic')" >&2
      exit 2
      ;;
  esac
}

if [ -z "$TRAC_ENV" ]; then
  TRAC_ENV="$TRAC_ENV_PARENT/$TRAC_PROJECT_NAME"
fi

validate_project_name() {
  name="$1"
  if [ -z "$name" ]; then
    return 1
  fi
  case "$name" in
    *[!A-Za-z0-9._-]* )
      return 1
      ;;
  esac
  return 0
}

render_db() {
  project="$1"
  if [ -n "$TRAC_DB_TEMPLATE" ]; then
    printf '%s' "$TRAC_DB_TEMPLATE" | sed "s/{project}/$project/g"
  else
    printf '%s' "$TRAC_DB"
  fi
}

init_env_if_missing() {
  env_dir="$1"
  project_name="$2"

  mkdir -p "$env_dir"
  if [ ! -f "$env_dir/VERSION" ]; then
    echo "[entrypoint] Initializing Trac environment: $project_name ($env_dir)"
    trac-admin "$env_dir" initenv "$project_name" "$(render_db "$project_name")"
  fi

  if [ -n "$TRAC_DEFAULT_LANGUAGE" ]; then
    current_lang=$(trac-admin "$env_dir" config get trac default_language 2>/dev/null || true)
    if [ -z "$current_lang" ]; then
      trac-admin "$env_dir" config set trac default_language "$TRAC_DEFAULT_LANGUAGE" >/dev/null
    fi
  fi

  if [ -n "$TRAC_DEFAULT_TIMEZONE" ]; then
    current_tz=$(trac-admin "$env_dir" config get trac default_timezone 2>/dev/null || true)
    if [ -z "$current_tz" ]; then
      trac-admin "$env_dir" config set trac default_timezone "$TRAC_DEFAULT_TIMEZONE" >/dev/null
    fi
  fi

  if [ -n "$TRAC_ADMIN_USER" ]; then
    trac-admin "$env_dir" permission add "$TRAC_ADMIN_USER" TRAC_ADMIN >/dev/null 2>&1 || true
  fi
}

case "$TRAC_MODE" in
  parent)
    mkdir -p "$TRAC_ENV_PARENT"

    ensure_admin_auth

    if [ -z "$TRAC_PROJECTS" ]; then
      TRAC_PROJECTS="$TRAC_PROJECT_NAME"
    fi

    projects_norm=$(printf '%s' "$TRAC_PROJECTS" | tr ',' ' ')
    for project in $projects_norm; do
      if ! validate_project_name "$project"; then
        echo "[entrypoint] Invalid project name: $project" >&2
        exit 2
      fi
      init_env_if_missing "$TRAC_ENV_PARENT/$project" "$project"
    done

    exec tracd --port "$TRAC_PORT" ${TRACD_AUTH_ARGS:-} --env-parent-dir "$TRAC_ENV_PARENT"
    ;;
  single)
    legacy_env_root="/var/trac"

    if [ "$TRAC_ENV" != "$legacy_env_root" ] \
      && [ -f "$legacy_env_root/VERSION" ] \
      && [ ! -f "$TRAC_ENV/VERSION" ]; then
      echo "[entrypoint] Migrating legacy Trac environment: $legacy_env_root -> $TRAC_ENV"
      mkdir -p "$TRAC_ENV"
      for item in VERSION README conf db htdocs log plugins; do
        if [ -e "$legacy_env_root/$item" ] && [ ! -e "$TRAC_ENV/$item" ]; then
          mv "$legacy_env_root/$item" "$TRAC_ENV/"
        fi
      done
    fi

    mkdir -p "$TRAC_ENV"

    ensure_admin_auth

    if [ ! -f "$TRAC_ENV/VERSION" ]; then
      echo "[entrypoint] No Trac environment found at $TRAC_ENV; initializing..."
      trac-admin "$TRAC_ENV" initenv "$TRAC_PROJECT_NAME" "$TRAC_DB"
      echo "[entrypoint] Trac environment initialized."
    fi

    exec tracd --port "$TRAC_PORT" ${TRACD_AUTH_ARGS:-} "$TRAC_ENV"
    ;;
  *)
    echo "[entrypoint] Unknown TRAC_MODE: $TRAC_MODE (use 'single' or 'parent')" >&2
    exit 2
    ;;
esac
