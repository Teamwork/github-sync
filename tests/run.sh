#!/usr/bin/env bash
# Runs the action's Docker image against a mock Teamwork API
# (tests/mock-teamwork.py) for every case in tests/cases, and compares the exit
# code, stderr and requests the mock received with the case's expected file.
#
# A case is a directory with:
#   event.json  the GitHub event payload
#   inputs      KEY=VALUE lines: GITHUB_EVENT_NAME, the INPUT_* env vars GitHub
#               creates for the action's inputs, and any other env such as
#               IGNORE_PROJECT_IDS. Inputs that aren't set are empty.
#   expected    what the run should produce
#
# Usage: tests/run.sh [--update] [filter]
#   --update  rewrites the expected files from the current output
#   filter    only runs the cases whose name contains it
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=github-sync:test
NETWORK=github-sync-test
MOCK=github-sync-teamwork

update=false
filter=
for arg in "$@"; do
  if [ "$arg" == "--update" ]; then
    update=true
  else
    filter=$arg
  fi
done

stop_mock() {
  docker rm --force "$MOCK" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}

work=$(mktemp -d)
trap 'stop_mock; rm -rf "$work"' EXIT

# The action's args, in action.yml order, as the input each one comes from
# (empty for the '' placeholders). The GitHub runner builds them the same way.
arg_inputs=()
while IFS= read -r item || [ -n "$item" ]; do
  case $item in
    "''") arg_inputs+=("") ;;
    "\${{ inputs."*" }}")
      item=${item#"\${{ inputs."}
      arg_inputs+=("${item%" }}"}") ;;
    *)
      echo "Unsupported item in action.yml's runs.args: $item" >&2
      exit 1 ;;
  esac
done < <(sed -n '/^  args:/,/^[^ #]/ s/^    - //p' "$ROOT/action.yml")

# Runs the action for the case in $1 the way GitHub does: inputs as INPUT_* env
# vars, passed by name only, and as positional args built from action.yml.
run_case() (
  local -r dir=$1

  export INPUT_TEAMWORK_URI=http://teamwork:8080
  export INPUT_TEAMWORK_API_TOKEN=test-token
  local env_names=(INPUT_TEAMWORK_URI INPUT_TEAMWORK_API_TOKEN)
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|'#'*) continue ;; esac
    export "${line%%=*}=${line#*=}"
    env_names+=("${line%%=*}")
  done < "$dir/inputs"

  local docker_args=(--rm --network "$NETWORK" --volume "$dir/event.json:/github/workflow/event.json:ro"
    --env GITHUB_REPOSITORY=acme/webapp --env GITHUB_EVENT_PATH=/github/workflow/event.json)
  local env_name
  for env_name in "${env_names[@]}"; do
    docker_args+=(--env "$env_name")
  done

  local action_args=() input value
  for input in "${arg_inputs[@]}"; do
    value=
    if [ -n "$input" ]; then
      env_name="INPUT_$input"
      value=${!env_name:-}
    fi
    action_args+=("$value")
  done

  docker run "${docker_args[@]}" "$IMAGE" "${action_args[@]}"
)

docker build --quiet --tag "$IMAGE" "$ROOT" >/dev/null

stop_mock
docker network create "$NETWORK" >/dev/null
docker run --detach --name "$MOCK" --network "$NETWORK" --network-alias teamwork \
  --volume "$ROOT/tests/mock-teamwork.py:/mock-teamwork.py:ro" --volume "$work:/out" \
  python:3.13-alpine python /mock-teamwork.py /out/requests >/dev/null
for _ in $(seq 50); do
  if docker logs "$MOCK" 2>&1 | grep -q listening; then
    break
  fi
  sleep 0.1
done
if ! docker logs "$MOCK" 2>&1 | grep -q listening; then
  echo "The mock Teamwork API didn't start:" >&2
  docker logs "$MOCK" >&2
  exit 1
fi

ran=0
failed=0
for dir in "$ROOT"/tests/cases/*/; do
  dir=${dir%/}
  name=$(basename "$dir")
  case $name in *"$filter"*) ;; *) continue ;; esac
  ran=$((ran + 1))

  : > "$work/requests"
  code=0
  run_case "$dir" > "$work/stdout" 2> "$work/stderr" || code=$?
  {
    echo "exit code: $code"
    if [ -s "$work/stderr" ]; then
      echo
      echo "stderr:"
      sed 's/^/  /' "$work/stderr"
    fi
    cat "$work/requests"
  } > "$work/actual"

  if $update; then
    cp "$work/actual" "$dir/expected"
    echo "updated  $name"
  elif diff -u "$dir/expected" "$work/actual" > "$work/diff" 2>&1; then
    echo "ok       $name"
  else
    failed=$((failed + 1))
    echo "FAIL     $name"
    sed 's/^/    /' "$work/diff"
    echo "    action stdout:"
    sed 's/^/      /' "$work/stdout"
  fi
done

echo
if ((ran == 0)); then
  echo "No cases match '$filter'"
  exit 1
fi
if $update; then
  echo "Updated $ran expected file(s), review them before committing"
elif ((failed > 0)); then
  echo "$failed of $ran case(s) failed"
  exit 1
else
  echo "All $ran case(s) passed"
fi
