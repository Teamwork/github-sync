#!/usr/bin/env bash

teamwork::get_task_id_from_body() {
  local body=$1
  local task_ids=()

  pat='tasks\/([0-9]{1,})'
  while [[ $body =~ $pat ]]; do
    task_ids+=( "${BASH_REMATCH[1]}" )
    body=${body#*"${BASH_REMATCH[0]}"}
  done

  local task_ids_str
  task_ids_str=$(printf ",%s" "${task_ids[@]}")
  task_ids_str=${task_ids_str:1} # remove initial comma
  echo "$task_ids_str"
}

teamwork::add_comment() {
  local -r body=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Comment: ${body//\"/}"
    return
  fi

  response=$(curl -X "POST" "$TEAMWORK_URI/projects/api/v1/tasks/$TEAMWORK_TASK_ID/comments.json" \
       -u "$TEAMWORK_API_TOKEN"':' \
       -H 'Content-Type: application/json; charset=utf-8' \
       -d "{ \"comment\": { \"body\": \"${body//\"/}\", \"notify\": true, \"content-type\": \"text\", \"isprivate\": false } }" )

  log::message "$response"
}

teamwork::add_tag() {
  local -r tag_name=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Tag Added: ${tag_name//\"/}"
    return
  fi

  if [ "$AUTOMATIC_TAGGING" == true ]; then
    response=$(curl -X "PUT" "$TEAMWORK_URI/projects/api/v1/tasks/$TEAMWORK_TASK_ID/tags.json" \
       -u "$TEAMWORK_API_TOKEN"':' \
       -H 'Content-Type: application/json; charset=utf-8' \
       -d "{ \"tags\": { \"content\": \"${tag_name//\"/}\" } }" )

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
    response=$(curl -X "PUT" "$TEAMWORK_URI/projects/api/v1/tasks/$TEAMWORK_TASK_ID/tags.json" \
         -u "$TEAMWORK_API_TOKEN"':' \
         -H 'Content-Type: application/json; charset=utf-8' \
         -d "{ \"tags\": { \"content\": \"${tag_name//\"/}\" },\"removeProvidedTags\":\"true\" }" )

    log::message "$response"
  fi
}

teamwork::pull_request_opened() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r user=$(github::get_sender_user)
  local -r pr_stats=$(github::get_pr_patch_stats)
  local -r pr_body=$(github::get_pr_body)
  IFS=" " read -r -a pr_stats_array <<< "$pr_stats"

  teamwork::add_comment "
**$user** opened a PR: **$pr_title**
[$pr_url]($pr_url)

---

${pr_body//###/####} 

---

🔢 ${pr_stats_array[0]} commits / 📝 ${pr_stats_array[1]} files updated / ➕ ${pr_stats_array[2]} additions / ➖ ${pr_stats_array[3]} deletions
  "

  teamwork::add_tag "PR Open"
}

teamwork::pull_request_closed() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r pr_merged=$(github::get_pr_merged)

  if [ "$pr_merged" == "true" ]; then
    teamwork::add_comment "
**$user** merged a PR: **$pr_title**
[$pr_url]($pr_url)
"
  teamwork::add_tag "PR Merged"
  teamwork::remove_tag "PR Open"
  teamwork::remove_tag "PR Approved"
  else
    teamwork::add_comment "
**$user** closed a PR without merging: **$pr_title**
[$pr_url]($pr_url)
"
    teamwork::remove_tag "PR Open"
    teamwork::remove_tag "PR Approved"
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
    teamwork::add_comment "
**$user** submitted a review to the PR: **$pr_title**
[$pr_url]($pr_url)

---

Review: **$review_state**
$comment
"
    teamwork::add_tag "PR Approved"
  fi
}

teamwork::pull_request_review_dismissed() {
  local -r user=$(github::get_sender_user)
  teamwork::add_comment "Review dismissed by $user"
}
