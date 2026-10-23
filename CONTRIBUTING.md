# Contributing

## Setup local environment

* [Install Docker](https://docs.docker.com/get-docker/)

## Running the tests

The tests run the action's Docker image against a mock Teamwork API (`tests/mock-teamwork.py`) and check what it sends:

```
./tests/run.sh
```

Each directory in `tests/cases` is a test case:

* `event.json`: the GitHub event the action receives
* `inputs`: the action's inputs as the `INPUT_*` environment variables GitHub creates for them, plus `GITHUB_EVENT_NAME` and any other environment variables such as `IGNORE_PROJECT_IDS`
* `expected`: the exit code, errors and requests the mock Teamwork API should end up with

`./tests/run.sh <filter>` only runs the cases whose name contains the filter.

To add a case, create its `event.json` and `inputs`, run `./tests/run.sh --update <case name>` to record its `expected` file, and check that file is right before committing it. The mock's data (which tasks exist, their projects and the workflow stages) is at the top of `tests/mock-teamwork.py`.
