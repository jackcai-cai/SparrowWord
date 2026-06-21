# Contributing To SparrowWord

This repo is the code source for SparrowWord. The collaboration rule is simple:

- develop locally
- version with git
- sync through GitHub
- deploy to the server only after code is committed and pushed

## Branching

- `main`: stable branch
- `feature/<name>`: new feature work
- `fix/<name>`: bug fixes
- `docs/<name>`: documentation-only changes
- `chore/<name>`: maintenance or tooling

Examples:

- `feature/web-prototype`
- `fix/chinese-reverse-lookup`
- `docs/git-bootstrap`

## Basic Daily Flow

Check your state:

```bash
git status
```

Pull the latest `main`:

```bash
git switch main
git pull
```

Start a branch:

```bash
git switch -c feature/your-change
```

After making changes:

```bash
git add .
git commit -m "feat: describe the change"
git push -u origin feature/your-change
```

## Commit Style

Use short commit prefixes:

- `feat:`
- `fix:`
- `docs:`
- `chore:`
- `refactor:`
- `test:`

Examples:

- `feat: add quick reverse lookup candidates`
- `fix: clean malformed system dictionary meanings`
- `docs: add GitHub publishing playbook`

## Server Rule

Do not use the server as the main development environment.

The server should:

- pull code from GitHub
- run deployed services
- store runtime logs and server-side data

The server should not be where collaborators hand-edit production code.

## Before Opening A PR Or Sharing A Branch

- make sure `git status` is clean or intentionally scoped
- run the relevant local build or verification command
- keep the branch focused on one topic
- explain user-facing behavior changes clearly

## First-Time Setup

See the [README](README.md) for how to build the macOS app and run the web app + dictionary API locally.
