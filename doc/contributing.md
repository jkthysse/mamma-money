# Contributing

## Branching strategy

This project uses trunk-based development. `main` is the single source of truth — there are no long-lived branches, no develop branch, no release branches. Every piece of work branches directly off `main` and merges directly back into `main`.

Feature branches should be short-lived. If a branch is open for more than a day or two, it is drifting from `main` and accumulating merge risk. Break the work into smaller pieces if needed.

## Branch naming

Branches are named using your initials followed by a short description of the work:

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
git checkout -b jt/your-feature
```

2. Make your changes and commit
3. Push your branch and open a pull request against `main` on GitHub
4. Write a short description in the PR body explaining what changed and why — not what the code does, but the reasoning behind the decision

## Merge requirements

A pull request cannot be merged until:

- CI passes — all pipeline jobs must be green
- At least one team member has reviewed and approved

Direct pushes to `main` are not permitted.

When merging, use **Squash and merge**. This keeps the commit history on `main` clean — one commit per feature, with the PR description as the commit message. Your branch's individual commits are squashed away.

## After merging

Delete your branch after it is merged. GitHub will offer to do this automatically on the PR page. There is no reason to keep feature branches around after they land.

Pull `main` before starting your next piece of work:

```bash
git checkout main
git pull
```