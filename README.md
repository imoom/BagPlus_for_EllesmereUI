# BagPlus for EllesmereUI Repository

This root README is for maintaining the repo. The packaged user-facing addon README lives at `src/BagPlus_for_EllesmereUI/README.md`.

## Layout

Runtime addon files live in `src/BagPlus_for_EllesmereUI/`. This keeps the installable addon folder separate from repo tooling, release artifacts, and the EllesmereUI compatibility submodule.

## Local installation for testing

Run from the repository root. The installer copies the current development source
and replaces files only inside `BagPlus_for_EllesmereUI` at the selected destination.
Install EllesmereUI and EllesmereUIBags separately in that client first.

Retail uses the existing `.wow-addons-dir` setting or auto-detects a standard install:

```sh
scripts/install-dev.sh --client retail --dry-run
scripts/install-dev.sh --client retail
```

For Forever, supply the actual client AddOns folder on the first install. Replace
the example path below with your installed client's path; beta folder names vary.
Windows paths are also accepted when `wslpath` is available.

```sh
scripts/install-dev.sh --client forever --addons-dir "/path/to/Forever/Interface/AddOns" --dry-run
scripts/install-dev.sh --client forever --addons-dir "/path/to/Forever/Interface/AddOns" --save-path
# Later installs reuse the saved path:
scripts/install-dev.sh --client forever
```

Forever's path is saved in the gitignored `.wow-addons-dir.forever`, independently
of retail. A dry run never installs files or saves configuration. You can also use
`WOW_RETAIL_ADDONS_DIR` or `WOW_FOREVER_ADDONS_DIR`; `WOW_ADDONS_DIR` overrides either,
and `--addons-dir` takes highest priority. Copy mode is the default and recommended
for Windows clients accessing a WSL checkout.

Restart the client after its first installation so it discovers the addon. For
subsequent Lua changes, run the installer again and use `/reload` in game.
The installer copies the addon as-is. Forever support is experimental; use the
in-game checks below after installing.

For the first Forever test, enable EllesmereUI, EllesmereUI Bags, and BagPlus.
Check that BoE gear appears in its own category and that `/bagplus ilvl asc`,
`desc`, and `off` change the displayed order. In the Grid display, try
`/bagplus perrow 5`, `/bagplus compact on`, and `/bagplus emptyrecent on`.
Equip a specialty bag and confirm its items stay under Special Bags. Open the
bank and verify ordinary deposits still work. Warbound and reagent move controls
should be absent on Forever.

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
