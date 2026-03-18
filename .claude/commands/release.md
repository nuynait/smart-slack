---
description: Create a new versioned release — bumps Info.plist, commits, tags, pushes, and creates a GitHub release with a detailed changelog.
---

# Release SmartSlack

You are creating a new release for the SmartSlack project. Follow these steps exactly in order. If any step fails, stop and report the error.

## Step 1: Pre-flight checks

1. Ensure you are on the `main` branch. If not, abort with: "You must be on the main branch to release."
2. Run `git fetch origin` and check that main is up to date with `origin/main`. If behind, abort with: "Local main is behind origin/main. Pull first."
3. Check `git status` for uncommitted changes. If the working tree is dirty, abort with: "Working tree is not clean. Commit or stash changes first."

## Step 2: Determine version bump

1. Read the current version from `SmartSlack/Info.plist` (`CFBundleShortVersionString`).
2. Get the latest git tag to confirm it matches.
3. Ask the user: "Current version is **X.Y.Z**. Bump **major**, **minor**, or **patch**?"
4. Wait for the user's answer before proceeding. Calculate the new version accordingly:
   - **major**: X+1.0.0
   - **minor**: X.Y+1.0
   - **patch**: X.Y.Z+1

## Step 3: Update version in Info.plist

1. Edit `SmartSlack/Info.plist` — change `CFBundleShortVersionString` from the old version to the new version.
2. Verify the edit is correct by reading the file back.

## Step 4: Commit and tag

1. Stage only `SmartSlack/Info.plist`.
2. Commit with message: `chore: bump version to <new_version>`
3. Create an annotated git tag: `git tag -a v<new_version> -m "v<new_version>"`
4. Push the commit: `git push`
5. Push the tag: `git push origin v<new_version>`

## Step 5: Generate changelog

1. Find the previous release tag (the one before the new tag).
2. Run `git log <previous_tag>..HEAD --oneline` to get all commits since the last release.
3. Group the commits by type (feat, fix, refactor, chore, etc.) based on conventional commit prefixes.
4. Write a detailed changelog in this format:

```
## What's New

### Features
- Description of each feat commit (rewrite for clarity, don't just paste the commit message)

### Bug Fixes
- Description of each fix commit

### Other Changes
- Description of refactor/chore/style commits
```

Omit empty sections. Make descriptions user-friendly — explain what changed from the user's perspective, not implementation details.

## Step 6: Create GitHub release

1. Use `gh release create v<new_version>` with:
   - Title: `v<new_version>`
   - Body: the changelog from Step 5
   - `--latest` flag
2. Print the release URL when done.

## Important

- NEVER skip the pre-flight checks
- NEVER proceed past Step 2 without the user's explicit answer
- If `gh` CLI is not available, abort with instructions to install it
- The version format is always `MAJOR.MINOR.PATCH` (semver)
