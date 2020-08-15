#!/usr/bin/env bash

log::error() {
  echo "$@" 1>&2
}

log::message() {
  echo "--------------"
  echo "$@"
}
