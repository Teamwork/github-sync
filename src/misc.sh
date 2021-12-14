#!/usr/bin/env bash

log::error() {
  echo "$@" 1>&2
}

log::message() {
  echo "--------------"
  echo "$@"
}

env::set_environment() {
  if [ "$TEAMWORK_URI" == "localhost" ] && [ "$TEAMWORK_API_TOKEN" == "test_api_token" ]; then
    export ENV="test"
  else
    export ENV="prod"
  fi
}

in_array {
  ARRAY=$2
  for e in ${ARRAY[*]}
  do
    if [[ "$e" == "$1" ]]
    then
      return 0
    fi
  done
  return 1
}
