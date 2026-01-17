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
}

case "$TRAC_MODE" in
  parent)
    mkdir -p "$TRAC_ENV_PARENT"

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

    exec tracd --port "$TRAC_PORT" --env-parent-dir "$TRAC_ENV_PARENT"
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

    if [ ! -f "$TRAC_ENV/VERSION" ]; then
      echo "[entrypoint] No Trac environment found at $TRAC_ENV; initializing..."
      trac-admin "$TRAC_ENV" initenv "$TRAC_PROJECT_NAME" "$TRAC_DB"
      echo "[entrypoint] Trac environment initialized."
    fi

    exec tracd --port "$TRAC_PORT" "$TRAC_ENV"
    ;;
  *)
    echo "[entrypoint] Unknown TRAC_MODE: $TRAC_MODE (use 'single' or 'parent')" >&2
    exit 2
    ;;
esac
