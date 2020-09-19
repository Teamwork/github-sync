# Contributing

## Getting started

## Setup local environment

* [Install Docker](https://docs.docker.com/get-docker/)
* [Install act tool](https://github.com/nektos/act)

## Usage

Simulate a new pull request

```
act pull_request -e tests/events/pull_request_opened.json
```

Simulate a pull request has been approved

```
act pull_request_review -e tests/events/pull_request_approved.json
```

Simulate a pull request has been merged

```
act pull_request -e tests/events/pull_request_merged.json
```
