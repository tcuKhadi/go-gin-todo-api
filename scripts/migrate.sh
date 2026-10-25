#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere: move to the project root (the parent of scripts/)
cd "$(dirname "$0")/.."

# Load .env line by line, skipping comments and blank lines
if [[ -f .env ]]; then
    while IFS='=' read -r key value; do
        key="${key//[[:space:]]/}"
        value="${value%$'\r'}"
        [[ -z "$key" || "$key" == \#* || -z "$value" ]] && continue
        export "$key=$value"
    done < .env
fi

migrate_cmd() {
    : "${DATABASE_URL:?DATABASE_URL is not set. Check .env}"
    migrate -path migrations -database "$DATABASE_URL" "$@"
}

command="${1:-}"
name="${2:-}"

case "$command" in
    up)
        migrate_cmd up
        ;;
    down)
        count="${name:-1}"
        read -r -p "Rolling back $count migration(s). Continue? [y/N] " confirm
        if [[ "$confirm" == "y" ]]; then
            migrate_cmd down "$count"
        else
            echo "Cancelled."
        fi
        ;;
    create)
        [[ -n "$name" ]] || { echo "Usage: $0 create <name>"; exit 1; }
        migrate create -ext sql -dir migrations -seq "$name"
        ;;
    force)
        [[ -n "$name" ]] || { echo "Usage: $0 force <version>"; exit 1; }
        migrate_cmd force "$name"
        ;;
    *)
        echo "Usage: $0 {up | down [n] | create <name> | force <version>}"
        exit 1
        ;;
esac
