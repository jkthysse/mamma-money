# Contributing

## Branching strategy

This project uses trunk-based development. `main` is the single source of truth — there are no long-lived branches, no develop branch, no release branches. Every piece of work branches directly off `main` and merges directly back into `main`.

Feature branches should be short-lived. If a branch is open for more than a day or two, it is drifting from `main` and accumulating merge risk. Break the work into smaller pieces if needed.

## Branch naming

Branches are named using author initials followed by a short work description:

```
jt/add-healthz-endpoint
jt/update-base-image
jt/fix-port-binding
```

## Commit messages

Start with an uppercase letter. Keep the rest lowercase. No special characters, no punctuation at the end.

```
Add healthz endpoint
Update distroless base image to debian13
Fix port binding when env var is unset
```

## Opening a pull request

1. Branch off `main`

```bash
git checkout main
git pull
git checkout -b jt/feature-description
```

2. Make changes and commit
3. Push branch and open a pull request against `main` on GitHub
4. Write a short description in the PR body explaining what changed and why — not what the code does, but the reasoning behind the decision

## Merge requirements

A pull request cannot be merged until:

- CI passes — all pipeline jobs must be green
- At least one team member has reviewed and approved
- All review threads are resolved

Direct pushes to `main` are not permitted.

Allowed merge methods are **Merge commit** and **Squash and merge**.

## Explicit `main` branch rules

The `main` branch is protected by active GitHub branch rules with no bypass actors. The following rules are in effect:

- Branch deletion is blocked.
- Non-fast-forward updates are blocked (no force pushes).
- Linear history is required.
- Pull requests are required for changes to `main`.
- Minimum approvals: **1**.
- Stale approvals are dismissed when new commits are pushed.
- Last-push approval is not required.
- Review threads must be resolved before merge.
- Allowed pull request merge methods: **merge** and **squash**.
- Code scanning gate: **CodeQL** must pass with security alerts at **high or higher** and overall alerts at **errors** threshold.
- Code quality gate: **errors** severity is enforced.
- Copilot code review runs on push to pull requests and does not run on draft pull requests.

## After merging

Delete feature branches after merge. GitHub offers this automatically on the pull request page.

Pull `main` before starting the next work item:

```bash
git checkout main
git pull
```