#!/usr/bin/env bash

source "$PROJECT_HOME/src/ensure.sh"
source "$PROJECT_HOME/src/github.sh"
source "$PROJECT_HOME/src/misc.sh"
source "$PROJECT_HOME/src/teamwork.sh"

main() {
  log::message "Running the process..."

  # Ensure env vars and args exist
  ensure::env_variable_exist "GITHUB_REPOSITORY"
  ensure::env_variable_exist "GITHUB_EVENT_PATH"
  ensure::total_args 3 "$@"

  export GITHUB_TOKEN="$1"
  export TEAMWORK_URI="$2"
  export TEAMWORK_API_TOKEN="$3"

  # Check if there is a task link in the PR
  local -r pr_body=$(github::get_pr_body)
  local -r task_id=$(teamwork::get_task_id_from_body "$pr_body" )

  if [ "$task_id" == "" ]; then
    log::message "Task not found"
    exit 0
  fi

  log::message "Task found with the id: "$task_id

  export TEAMWORK_TASK_ID=$task_id

  local -r event=$(github::get_event_name)
  local -r action=$(github::get_action)

  log::message "Event: " $event " - Action: " $action

  if [ "$event" == "pull_request" ] && [ "$action" == "opened" ]; then
    teamwork::pull_request_opened
  elif [ "$event" == "pull_request" ] && [ "$action" == "closed" ]; then
    teamwork::pull_request_closed
  elif [ "$event" == "pull_request_review" ] && [ "$action" == "submitted" ]; then
    teamwork::pull_request_review_submitted
  elif [ "$event" == "pull_request_review" ] && [ "$action" == "dismissed" ]; then
    teamwork::pull_request_review_dismissed
  elif [ "$event" == "pull_request_review_comment" ] && [ "$action" == "deleted" ]; then
    teamwork::pull_request_review_comment_deleted
  else
    log::message "Operation not allowed"
    exit 0
  fi

  exit $?
}
