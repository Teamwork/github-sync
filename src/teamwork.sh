#!/usr/bin/env bash

teamwork::get_task_id_from_body() {
  local -r body=$1

  pat='tasks\/[0-9]{1,}'
  task=$(echo $body | grep -Eo $pat)
  task_id=$(echo $task | tr -cd  '[[:digit:]]')

  echo $task_id
}

teamwork::add_comment() {
  local -r body=$1

  response=$(curl -X "POST" "$TEAMWORK_URI/projects/api/v1/tasks/$TEAMWORK_TASK_ID/comments.json" \
       -u $TEAMWORK_API_TOKEN':' \
       -H 'Content-Type: application/json; charset=utf-8' \
       -d "{ \"comment\": { \"body\": \"$body\", \"notify\": \"\", \"content-type\": \"text\", \"isprivate\": false } }" )

  echo $response
}

teamwork::pull_request_opened() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r user=$(github::get_sender_user)

  teamwork::add_comment "
  **$user** opened a PR: **$pr_title**
  [$pr_url]($pr_url)
  "
}

teamwork::pull_request_synchronize() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r user=$(github::get_sender_user)

  teamwork::add_comment "
  **$user** updated a PR: **$pr_title**
  [$pr_url]($pr_url)
  "
}

teamwork::pull_request_closed() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)

  teamwork::add_comment "
  **$user** closed a PR: **$pr_title**
  [$pr_url]($pr_url)
  "
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
  fi
}

teamwork::pull_request_review_dismissed() {
  teamwork::add_comment "Review dismissed"
}

teamwork::pull_request_review_comment_deleted() {
  teamwork::add_comment "Review deleted"
}

teamwork::issue_comment_created() {
  local -r user=$(github::get_sender_user)
  teamwork::add_comment "Comment added by $user"
}
