# Contributing Guide

*How to set up, code, test, review, and release so contributions meet our Definition of Done.*

To contribute, simply create your own branch and make your desired contributions, then open a pull request. The tests will automatically run when your pull request is opened.
Once your PR is approved, it will automatically get merged into main.


## Code of Conduct

**Reference the project/community behavior expectations and reporting process.**

## Getting Started

*List prerequisites, setup steps, environment variables/secrets handling, and how to run the app locally.*

We are still figuring out how we will make our project so this section will be updated later.


## Branching & Workflow

*Describe the workflow (e.g., trunk-based or GitFlow), default branch, branch naming, and when to rebase vs. merge.*

Trunk-based workflow. Default branch is called "main". We will mainly be merging, except when updating individual feature branches, in which we will be rebasing to keep history clean.
Feature branches should be named after their feature e.g. "error 7 fix".

## Issues & Planning

*Explain how to file issues, required templates/labels, estimation, and triage/assignment practices.*

Issues will be filed through the "issues" slack channel.

Required parts of an issue request:
- How to recreate it
- Number (issues will be filed in numerical order of when they were opened)
- What attempts (if any) have been made so far to resolve it



## Commit Messages

*State the convention (e.g., Conventional Commits), include examples, and how to reference issues.*

Conventional commit style. Example: "Fix error 7 (API not communicating)". Reference issues by their number.



## Code Style, Linting & Formatting

*Name the formatter/linter, config file locations, and the exact commands to check/fix locally.*

We are still figuring out what formatter/linters we will be using, so this section will also be updated later.


## Testing

*Define required test types, how to run tests, expected coverage thresholds, and when new/updated tests are mandatory.*

- Required types: unit tests, integration tests, end-to-end tests
- How to run tests: Through github workflows, tests will run automatically when a PR is opened. You can also run them anytime with github actions.
- Expected coverage thresholds: unit tests -> small features. Integration tests -> small workflows. End-to-end: entire workflows.

## Definition of Done

*List the checks a change must pass before it merges (tests, review, docs updated, lint and security checks), each with the CI job, hook, or test that enforces it. For a gate not built yet, name the sprint it lands in and its owner.*

Before a change merges, it must pass all code and linting/formatting tests (done using hook through github actions, managed by Quinn and Jack). The sprint it will be implemented in is currently unknown.


## Contribution Norm

*State the floor (every contributor lands at least one piece of accepted work per sprint), where each kind of work lives (the repository, the issue tracker, the partner's system), and what accepted means for each.*

- Floor: every contributor lands at least one piece of accepted work per sprint. 
- Code lives in the repo, issues live in slack.
- For code, "accepted" means it passes all code and linting/formatting tests. For issues, it means that it is resolved and a clear reason is found for the bug (will be noted in the slack).
- We make the norm workable by working in sub-teams (AI, Backend, Frontend) to organize our efforts and hold each other accountable.


## Pull Requests & Reviews

*Outline PR requirements (template, checklist, size limits), reviewer expectations, approval rules, and required status checks.*

- No pull request template. This will be updated if we do in the future.
- All PRs must pass all tests to be opened (automatically done in a hook, as noted above).
- Tests to pass: unit, integration, e2e, linting, formatting.

Reviewer expectations:
- If the reviewer approves, the message does not need to be very long unless the reviewer has any concerns.
- If the reviewer disapproves, the message must be detailed as to why, and contain advice on how to improve the code before opening another PR with it.


## CI/CD

*Link to pipeline definitions, list mandatory jobs, how to view logs/re-run jobs, and what must pass before merge/release.*

Pipeline definitions are in the .github/workflows/ directory.

Mandatory jobs/tests: unit, integration, e2e, linting, formatting.


## Security & Secrets

*State how to report vulnerabilities, prohibited patterns (hard-coded secrets), dependency update policy, and scanning tools.*
- Report all vulnerabilities in the slack.
- By under no circumstances should environment files be committed to the repo.
- Change readme if dependencies update.


## Documentation Expectations

*Specify what must be updated (README, docs/, API refs, CHANGELOG) and docstring/comment standards.*

The README should be updated every time a commit is made to reflect the changes made with the commit.


## Release Process

*Describe versioning scheme, tagging, changelog generation, packaging/publishing steps, and rollback process.*

- Versioning Scheme: semantic versioning system (MAJOR.MINOR.PATCH, 0.11.0 > 0.4.0)
- Tags are created manually.
- Changelog generation will also be manual.
- We are currently figuring out how we will be packaging and publishing this project.
- Rollback Processs: Don't delete or overwrite published versions. Revest the offending change on main, and ship a patch release.


## Support & Contact

*Provide maintainer contact channel, expected response windows, and where to ask questions.*

Maintainer contact channel: email taylorahacker@gmail.com for now. We are currently working on a platform for support.
Expected response windows: 9-5 Monday-Friday.
