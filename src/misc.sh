#!/usr/bin/env bash

log::error() {
  echo "$@" 1>&2
}

log::message() {
  echo "--------------"
  echo "$@"
}

utils::in_array() {
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
