#!/usr/bin/env bash

# shellcheck disable=SC1090
source "$PROJECT_HOME/src/ensure.sh"
source "$PROJECT_HOME/src/github.sh"
source "$PROJECT_HOME/src/misc.sh"
source "$PROJECT_HOME/src/teamwork.sh"

main() {
  log::message "Running the process..."

  # Ensure env vars and args exist
  ensure::env_variable_exist "GITHUB_REPOSITORY"
  ensure::env_variable_exist "GITHUB_EVENT_PATH"

  export GITHUB_TOKEN="$1"
  export TEAMWORK_URI="$2"
  export TEAMWORK_API_TOKEN="$3"
  export AUTOMATIC_TAGGING="$4"

  env::set_environment

  # Check if there is a task link in the PR
  local -r pr_body=$(github::get_pr_body)
  local -r task_ids_str=$(teamwork::get_task_id_from_body "$pr_body" )

  if [ "$task_ids_str" == "" ]; then
    log::message "Task not found"
    exit 0
  fi

  local -r event=$(github::get_event_name)
  local -r action=$(github::get_action)

  log::message "Event: $event - Action: $action"

  IFS=',' read -r -a task_ids <<< "$task_ids_str"
  for task_id in "${task_ids[@]}"; do
    log::message "Task found with the id: $task_id"

    export TEAMWORK_TASK_ID=$task_id

    if [ "$event" == "pull_request" ] && [ "$action" == "review_requested" ]; then
      teamwork::pull_request_opened
    elif [ "$event" == "pull_request" ] && [ "$action" == "closed" ]; then
      teamwork::pull_request_closed
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "submitted" ]; then
      teamwork::pull_request_review_submitted
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "dismissed" ]; then
      teamwork::pull_request_review_dismissed
    else
      log::message "Operation not allowed"
      exit 0
    fi
  done

  exit $?
}
