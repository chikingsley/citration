# AGENTS.md

## Cursor Cloud specific instructions

### Overview

Zotero is a Firefox/Gecko-based desktop research management application (not Electron, not a web app). It runs as a XUL/XHTML application on a customized Firefox runtime (XULRunner). All build, lint, and test commands are documented in `CLAUDE.md`.

### Key services

| Service | Purpose | How to run |
|---|---|---|
| Build system | Babel transpile JS/JSX, compile SCSS, browserify | `NODE_OPTIONS=--openssl-legacy-provider npm run build` |
| Watch mode | Auto-rebuild on file changes | `NODE_OPTIONS=--openssl-legacy-provider npm start` |
| Test runner | Mocha tests inside Gecko runtime | `CI=1 xvfb-run test/runtests.sh -f -b <testname>` |
| Staging app | Assembled Zotero application | `ZOTERO_TEST=1 app/scripts/dir_build -q` |
| ESLint | Linting | `npx eslint <file>` |

### Non-obvious caveats

- **`NODE_OPTIONS=--openssl-legacy-provider`** is required for `npm run build` due to pdf-worker's Webpack configuration. Without it, the build fails.
- **`rsync`** must be installed (not included by default) — it's needed by `app/scripts/dir_build` via `prepare_build`.
- **Git LFS** must be pulled (`git lfs pull`) before `dir_build` can assemble the staging app. It needs `app/linux/updater.tar.xz`.
- **Git submodules** must be initialized recursively. Many core features (translators, styles, reader, pdf-worker, note-editor, utilities, translate framework) are submodules.
- **XULRunner** must be fetched once via `app/scripts/fetch_xulrunner -p l -a x64` (downloads ~80MB Firefox runtime). This only needs to be redone when `app/config.sh` changes the Gecko version.
- When running tests, the `-b` flag skips bundled translator/style installation for faster startup. Use `CI=1` to run headless without opening a JS console. Always use `-f` to bail on first failure.
- The test runner automatically triggers `npm run build` if the watch process isn't running, so you don't need to manually build before tests. However, it does NOT set `NODE_OPTIONS`, so either run the build manually first or ensure the watch process is active.
- **xdotool does not work** with Zotero's Gecko/XUL window for GUI automation. To test core functionality, use the test runner (`test/runtests.sh`) which exercises the API and data model inside the Gecko runtime.
- The staging app is rebuilt by `test/runtests.sh` automatically via `app/scripts/dir_build -q`, so you generally don't need to run it manually before tests.
