# BagPlus for EllesmereUI Repository

This root README is for maintaining the repo. The packaged user-facing addon README lives at `src/BagPlus_for_EllesmereUI/README.md`.

## Layout

Runtime addon files live in `src/BagPlus_for_EllesmereUI/`. This keeps the installable addon folder separate from repo tooling, release artifacts, and the EllesmereUI compatibility submodule.

## Release

The addon version in `src/BagPlus_for_EllesmereUI/BagPlus_for_EllesmereUI.toc` is the source of truth. Release archives are written to `releases/<version>/BagPlus_for_EllesmereUI.zip`, and the `releases/` folder is ignored by Git.

Normal release flow:

```text
# Update src/BagPlus_for_EllesmereUI/BagPlus_for_EllesmereUI.toc and changelog.md first, then commit.
scripts/release.sh --tag --push
```

The release script expects the current commit to be tagged `v<version>` where `<version>` matches the `.toc` version. Passing `--tag` creates that annotated tag if it is missing. Passing `--push` pushes the current branch and release tag to GitHub after the archive is built. If the tag already exists on the remote, run `scripts/release.sh --fetch-tags` after pulling/fetching so the local tag can be validated.

For a local test archive before committing, run:

```text
scripts/release.sh --allow-dirty --no-tag-check --force
```

The zip contains only the addon folder and release package files: `.toc`, `.lua`, the source README, `LICENSE`, and `changelog.md`.

## Tests

Run the local addon checks with:

```text
scripts/test.sh
```

The script parses the addon Lua file and then runs a dependency-free Lua harness in `tests/run.lua`. The harness mocks the small WoW and EllesmereUI surface BagPlus uses, so it is useful for catching syntax errors, startup failures, saved-variable migrations, slash command regressions, category routing, and the BagPlus post-render layout rules.

These tests do not replace in-game testing. They cannot prove that Blizzard's live API or EllesmereUI internals are unchanged; they only guard the compatibility assumptions represented by the mocks.
