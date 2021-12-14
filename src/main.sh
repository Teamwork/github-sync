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
  export BOARD_COLUMN_OPENED="$5"
  export BOARD_COLUMN_MERGED="$6"
  export BOARD_COLUMN_CLOSED="$7"

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

  local project_id
  IFS=',' read -r -a task_ids <<< "$task_ids_str"
  for task_id in "${task_ids[@]}"; do
    log::message "Task found with the id: $task_id"

    export TEAMWORK_TASK_ID=$task_id
    project_id="$(teamwork::get_project_id_from_task "$task_id")"
    export TEAMWORK_PROJECT_ID=$project_id

    ignored_project_ids=($IGNORE_PROJECT_IDS)
    if (( ${#ignored_project_ids[@]} != 0 )) || in_array $1 "${ignored_project_ids[*]}" then
        log::message "ignored due to IGNORE_PROJECT_IDS"
        exit 0
    fi

    if [ "$event" == "pull_request" ] && [ "$action" == "opened" ]; then
      teamwork::pull_request_opened
    elif [ "$event" == "pull_request" ] && [ "$action" == "closed" ]; then
      teamwork::pull_request_closed
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "submitted" ]; then
      teamwork::pull_request_review_submitted
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "dismissed" ]; then
      teamwork::pull_request_review_dismissed
    elif [ "$ENV" == "test" ]; then # always run pull_request_opened at the very least when in test
      teamwork::pull_request_opened
    else
      log::message "Operation not allowed"
      exit 0
    fi
  done

  exit $?
}
