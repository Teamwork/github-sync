<p align="center">
  <a href="https://www.teamwork.com?ref=github">
    <img src="https://www.teamwork.com/app/themes/teamwork-theme/dist/images/twork-slate.svg" width="139px" height="30px"/>
  </a>
</p>

<h1 align="center">
  Teamwork Github Sync
</h1>

<p align="center">
    This action helps you to keep in sync your PRs with your Teamwork tasks.
</p>

## Getting Started

### Prerequisites
Create the next environment vars in your repository:
* `TEAMWORK_URI`: The URL of your installation (e.g.: https://yourcompany.teamwork.com)
* `TEAMWORK_API_TOKEN`: The API token to authenticate the workflow

`GITHUB_TOKEN` doesn't need to be setup in the repository, this var is always available during the workflows execution.

### Installation
Create a new file `/.github/workflows/teamwork.yml` with the following:

```yaml
name: teamwork

on:
  pull_request:
    types: [opened, synchronize, closed]
  pull_request_review:
    types: [submitted, edited, dismissed]
  pull_request_review_comment:
    types: [created, deleted]
  issue_comment:
    types: [created]

jobs:
  teamwork-sync:
    runs-on: ubuntu-latest
    name: Teamwork Sync
    steps:
      - uses: miguelbemartin/teamwork-github@v1
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TEAMWORK_URI: ${{ secrets.TEAMWORK_URI }}
          TEAMWORK_API_TOKEN: ${{ secrets.TEAMWORK_API_TOKEN }}
```

## Usage
When creating a new PR, write in the description of the PR the URL of the task. The action will automatically add a comment in the task.

## Contributing
* Open a PR: https://github.com/miguelbemartin/teamwork-github/pulls
* Open an issue: https://github.com/miguelbemartin/teamwork-github/issues

## Authors
* **Miguel Ángel Martín** - [@miguelbemartin](https://twitter.com/miguelbemartin)

## License
This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
