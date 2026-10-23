#!/usr/bin/env bash

ensure::env_variable_exist() {
  if [[ -z "${!1:-}" ]]; then
    log::error "The env variable $1 is required."
    exit 1
  fi
}
