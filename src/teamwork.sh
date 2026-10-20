#!/usr/bin/env bash

teamwork::get_task_id_from_body() {
  local body=$1
  local task_ids=()

  pat='tasks\/([0-9]{1,})'
  while [[ $body =~ $pat ]]; do
    if ! utils::in_array "${BASH_REMATCH[1]}" "${task_ids[*]}"; then
      task_ids+=( "${BASH_REMATCH[1]}" )
    fi
    body=${body#*"${BASH_REMATCH[0]}"}
  done

  local task_ids_str
  task_ids_str=$(printf ",%s" "${task_ids[@]}")
  task_ids_str=${task_ids_str:1} # remove initial comma
  echo "$task_ids_str"
}

# Calls the Teamwork API and prints the response body. Fails on network errors,
# timeouts and HTTP error statuses, printing the error body in the latter case.
teamwork::request() {
  local -r method=$1
  local -r path=$2
  local -r payload=${3:-}

  local args=(-sS --fail-with-body --max-time 30 -X "$method" -u "$TEAMWORK_API_TOKEN"':')
  if [ -n "$payload" ]; then
    args+=(-H 'Content-Type: application/json; charset=utf-8' -d "$payload")
  fi

  curl "${args[@]}" "$TEAMWORK_URI$path"
}

# Logs a failed request and records it, so the run fails once every task has
# been processed.
teamwork::request_failed() {
  log::error "$1"
  TEAMWORK_FAILED_REQUESTS=$((TEAMWORK_FAILED_REQUESTS + 1))
}

teamwork::get_project_id_from_task() {
  local -r task_id=$1

  if [ "$ENV" == "test" ]; then
    echo "$task_id"
    return
  fi

  teamwork::request GET "/projects/api/v1/tasks/$task_id.json" |\
    jq -r '.["todo-item"]["project-id"]'
}

# Resolves a workflow stage name to its "<workflowId> <stageId>" pair within the
# task's project. Matching is a case-sensitive substring match against the stage
# name (mirroring the legacy board-column behaviour), and the first match wins.
# Echoes nothing when no stage name is provided or no stage matches, and fails
# when the stages can't be fetched.
teamwork::get_workflow_stage() {
  local -r stage_name=$1

  if [ -z "$stage_name" ]; then
    return
  fi

  if [ "$ENV" == "test" ]; then
    echo "$TEAMWORK_PROJECT_ID $TEAMWORK_PROJECT_ID"
    return
  fi

  # A single call scoped to the project sideloads every stage across the
  # project's workflow(s); each stage carries its parent workflow id, which the
  # move endpoint also needs.
  teamwork::request GET "/projects/api/v3/workflows.json?projectIds=$TEAMWORK_PROJECT_ID&include=stages" |\
    jq -r --arg stage_name "$stage_name" \
      '[.included.stages[]? | select(.name | contains($stage_name)) | "\(.workflow.id) \(.id)"][0] // empty'
}

teamwork::move_task_to_stage() {
  local -r stage_name=$1

  if [ -z "$stage_name" ]; then
    log::message "No workflow stage name provided"
    return
  fi

  local stage
  if ! stage=$(teamwork::get_workflow_stage "$stage_name"); then
    teamwork::request_failed "Failed to fetch the workflow stages of project $TEAMWORK_PROJECT_ID"
    return
  fi
  if [ -z "$stage" ]; then
    log::message "Failed to find a matching workflow stage for '$stage_name'"
    return
  fi

  local workflow_id stage_id
  read -r workflow_id stage_id <<< "$stage"

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Project ID: $TEAMWORK_PROJECT_ID - Workflow ID: $workflow_id - Stage ID: $stage_id"
    return
  fi

  if ! response=$(teamwork::request PATCH "/projects/api/v3/tasks/$TEAMWORK_TASK_ID/workflows/$workflow_id.json" \
      "{ \"stageId\": $stage_id, \"positionAfterTask\": -1 }"); then
    teamwork::request_failed "Failed to move task $TEAMWORK_TASK_ID to the '$stage_name' workflow stage: $response"
    return
  fi

  log::message "$response"
}

teamwork::add_comment() {
  local -r body=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Comment: $body"
    return
  fi

  # jq escapes the body (quotes, backslashes, newlines...) into valid JSON
  local -r payload=$(jq -n --arg body "$body" \
    '{ comment: { body: $body, notify: true, "content-type": "text", isprivate: false } }')

  if ! response=$(teamwork::request POST "/tasks/$TEAMWORK_TASK_ID/comments.json" "$payload"); then
    teamwork::request_failed "Failed to add a comment to task $TEAMWORK_TASK_ID: $response"
    return
  fi

  log::message "$response"
}

teamwork::add_tag() {
  local -r tag_name=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Tag Added: ${tag_name//\"/}"
    return
  fi

  if [ "$AUTOMATIC_TAGGING" == true ]; then
    if ! response=$(teamwork::request PUT "/tasks/$TEAMWORK_TASK_ID/tags.json" \
        "{ \"tags\": { \"content\": \"${tag_name//\"/}\" } }"); then
      teamwork::request_failed "Failed to add the '$tag_name' tag to task $TEAMWORK_TASK_ID: $response"
      return
    fi

    log::message "$response"
  fi
}

teamwork::remove_tag() {
  local -r tag_name=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Tag Removed: ${tag_name//\"/}"
    return
  fi

  if [ "$AUTOMATIC_TAGGING" == true ]; then
    if ! response=$(teamwork::request PUT "/tasks/$TEAMWORK_TASK_ID/tags.json" \
        "{ \"tags\": { \"content\": \"${tag_name//\"/}\" },\"removeProvidedTags\":\"true\" }"); then
      teamwork::request_failed "Failed to remove the '$tag_name' tag from task $TEAMWORK_TASK_ID: $response"
      return
    fi

    log::message "$response"
  fi
}

teamwork::pull_request_opened() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r head_ref=$(github::get_head_ref)
  local -r base_ref=$(github::get_base_ref)
  local -r user=$(github::get_sender_user)
  local -r pr_stats=$(github::get_pr_patch_stats)
  local -r pr_body=$(github::get_pr_body)
  IFS=" " read -r -a pr_stats_array <<< "$pr_stats"

  if [ "$LIGHTWEIGHT_COMMENT" == "true" ]; then
    teamwork::add_comment "PR [**\"$pr_title\"**]($pr_url) opened by **$user**"
  else
    teamwork::add_comment "
**$user** opened a PR: **$pr_title**
[$pr_url]($pr_url)
\`$base_ref\` ⬅️ \`$head_ref\`

---

${pr_body}

---

🔢 ${pr_stats_array[0]} commits / 📝 ${pr_stats_array[1]} files updated / ➕ ${pr_stats_array[2]} additions / ➖ ${pr_stats_array[3]} deletions

"
  fi

  teamwork::add_tag "PR Open"
  teamwork::move_task_to_stage "$WORKFLOW_STAGE_OPENED"
}

teamwork::pull_request_closed() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r pr_merged=$(github::get_pr_merged)

  if [ "$pr_merged" == "true" ]; then
    if [ "$LIGHTWEIGHT_COMMENT" == "true" ]; then
      teamwork::add_comment "PR [**\"$pr_title\"**]($pr_url) merged by **$user**"
    else
      teamwork::add_comment "
**$user** merged a PR: **$pr_title**
[$pr_url]($pr_url)
"
    fi
    teamwork::add_tag "PR Merged"
    teamwork::remove_tag "PR Open"
    teamwork::remove_tag "PR Approved"
    teamwork::move_task_to_stage "$WORKFLOW_STAGE_MERGED"
  else
    if [ "$LIGHTWEIGHT_COMMENT" == "true" ]; then
      teamwork::add_comment "PR [**\"$pr_title\"**]($pr_url) closed without merging by **$user**"
    else
      teamwork::add_comment "
**$user** closed a PR without merging: **$pr_title**
[$pr_url]($pr_url)
"
    fi
    teamwork::remove_tag "PR Open"
    teamwork::remove_tag "PR Approved"
    teamwork::move_task_to_stage "$WORKFLOW_STAGE_CLOSED"
  fi
}

teamwork::pull_request_review_submitted() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r review_state=$(github::get_review_state)
  local -r comment=$(github::get_review_comment)

  # Only add a message if the PR has been approved
  if [ "$review_state" == "approved" ]; then
    if [ "$LIGHTWEIGHT_COMMENT" == "true" ]; then
      teamwork::add_comment "PR [**\"$pr_title\"**]($pr_url) approved by **$user**"
    else
      teamwork::add_comment "
**$user** submitted a review to the PR: **$pr_title**
[$pr_url]($pr_url)

---

Review: **$review_state**
$comment
"
    fi
    teamwork::add_tag "PR Approved"
  fi
}

teamwork::pull_request_review_dismissed() {
  local -r user=$(github::get_sender_user)
  teamwork::add_comment "Review dismissed by $user"
}
