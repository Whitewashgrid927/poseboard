# Contributing to Poseboard

Create a branch for each change and open a pull request targeting `main`. Include
the problem, resulting behavior, and checks you ran. Review the PR before merging.
The initial implementation is introduced through the first PR.

## Keep personal data out of Git

Configure this checkout with your GitHub username and the exact noreply email
shown in GitHub Settings → Emails. Keep your personal email private there and
enable GitHub's option to block command-line pushes that expose it if desired.
Do not copy a real email, token, signing identity, local file path, or taught pose
into an issue, screenshot, commit message, fixture, or PR description.

Builds, signing files, user data, captures, and vocabulary exports stay local.
The tests generate synthetic hand landmarks; they never read a real vocabulary
or start the camera. Add test cases using synthetic data rather than recordings.

## Before opening a PR

Select a full Xcode installation with a macOS 26 SDK or newer. Then run:

```sh
python3 Tests/PrivacyTests.py
python3 Scripts/privacy-check.py --history
bash Scripts/test.sh
bash Scripts/build.sh
```

After staging the intended source files, inspect exactly what will be committed:

```sh
git diff --cached --stat
python3 Scripts/privacy-check.py --staged --history
```

The privacy check rejects non-noreply email addresses, common credential patterns,
personal home paths, binaries, symlinks, unreviewed file types, and expanded app
entitlements. It also examines author/committer emails and reachable commit
history. It is a backstop, not a guarantee that every form of personal data is
detectable; review file contents before pushing.

GitHub Actions runs these checks and builds an ad-hoc-signed app on the standard
[macOS 26 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
It does not upload an app, use signing credentials, or release a downloadable build.

## Preserve the app's boundaries

Keep camera startup explicit and discard stale callbacks. Capture pauses when
inactive unless the user enables Float for the current session; visibility, sleep,
and session-deactivation checks still apply. Keep both-hand confidence, ambiguity,
continuity, stable holds, and the fresh zero-hand release gate between additions.
Recognition only edits a local draft. Delivery requires an exact, expiring,
single-use confirmation bound to the draft revision and requested destination.
Keep the camera-only sandbox. Native Services return plain text only to the
requesting service pasteboard. Do not add keyboard injection or press Send.
Keep corrupt local vocabularies intact and writes blocked until loading succeeds.
Do not add telemetry, network access, or automatic communication as incidental
changes. Explain intentional changes to these boundaries in the PR.
