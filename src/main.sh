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
  ensure::env_variable_exist "GITHUB_EVENT_NAME"

  # $1 used to be GITHUB_TOKEN, which was never needed.
  export TEAMWORK_URI="$2"
  export TEAMWORK_API_TOKEN="$3"
  export AUTOMATIC_TAGGING="$4"
  export WORKFLOW_STAGE_OPENED="$5"
  export WORKFLOW_STAGE_MERGED="$6"
  export WORKFLOW_STAGE_CLOSED="$7"
  export LIGHTWEIGHT_COMMENT="$8"
  # BOARD_COLUMN_* are deprecated aliases kept for backwards compatibility.
  export BOARD_COLUMN_OPENED="${9:-}"
  export BOARD_COLUMN_MERGED="${10:-}"
  export BOARD_COLUMN_CLOSED="${11:-}"

  # Fall back to the deprecated BOARD_COLUMN_* inputs when their WORKFLOW_STAGE_*
  # replacements are not set.
  : "${WORKFLOW_STAGE_OPENED:=$BOARD_COLUMN_OPENED}"
  : "${WORKFLOW_STAGE_MERGED:=$BOARD_COLUMN_MERGED}"
  : "${WORKFLOW_STAGE_CLOSED:=$BOARD_COLUMN_CLOSED}"

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

  # Pick the handler before touching the API, so unsupported events make no
  # requests at all
  local handler
  if [ "$event" == "pull_request" ] && [ "$action" == "opened" ]; then
    handler=teamwork::pull_request_opened
  elif [ "$event" == "pull_request" ] && [ "$action" == "closed" ]; then
    handler=teamwork::pull_request_closed
  elif [ "$event" == "pull_request_review" ] && [ "$action" == "submitted" ]; then
    handler=teamwork::pull_request_review_submitted
  elif [ "$event" == "pull_request_review" ] && [ "$action" == "dismissed" ]; then
    handler=teamwork::pull_request_review_dismissed
  elif [ "$ENV" == "test" ]; then # always run pull_request_opened at the very least when in test
    handler=teamwork::pull_request_opened
  else
    log::message "Operation not allowed"
    exit 0
  fi

  TEAMWORK_FAILED_REQUESTS=0

  local project_id
  IFS=',' read -r -a task_ids <<< "$task_ids_str"
  for task_id in "${task_ids[@]}"; do
    log::message "Task found with the id: $task_id"

    export TEAMWORK_TASK_ID=$task_id
    if ! project_id="$(teamwork::get_project_id_from_task "$task_id")" || [[ ! $project_id =~ ^[0-9]+$ ]]; then
      teamwork::request_failed "Failed to get the project of task $task_id, check the task exists and the API token's user can access it"
      continue
    fi
    export TEAMWORK_PROJECT_ID=$project_id

    ignored_project_ids=("${IGNORE_PROJECT_IDS:-}")
    if utils::in_array "$project_id" "${ignored_project_ids[*]}"
    then
        log::message "ignored due to IGNORE_PROJECT_IDS"
        continue
    fi

    "$handler"
  done

  if ((TEAMWORK_FAILED_REQUESTS > 0)); then
    log::error "$TEAMWORK_FAILED_REQUESTS Teamwork request(s) failed, see the errors above"
    exit 1
  fi

  exit 0
}
