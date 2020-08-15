#!/usr/bin/env bash
set -euo pipefail

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [ "$PROJECT_HOME" == "/" ]; then
  PROJECT_HOME=""
fi

export PROJECT_HOME

source "$PROJECT_HOME/src/main.sh"

main "$@"

exit $?
