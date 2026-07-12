# Testing

Citration separates compilation, functional behavior, performance, and live acceptance so unrelated work does not compete inside one undifferentiated parallel process.

`just check` is the required deterministic development gate. It runs formatting, strict linting, and compilation for CitrationCore, the CLI, Mac, and iPad. It does not disguise a failed test as a successful check.

`just test-core` runs CitrationCore functional coverage sequentially. This lane uses real temporary SQLite databases, real files, captured Zotero API objects, migrations, attachment transfer state, synchronization state, conflict recovery, search, and integrity checks. The isolated value, design-token, fabricated-provider, fake-reader, and synthetic-parser unit suites were removed.

`just test-mac` runs the Mac application integration suite through Xcode. Retained coverage exercises production stores with temporary databases and files, actual reader documents and packages, credential files, and API response contracts. It does not make live network calls implicitly.

`just test-ipad` runs the iPad application and UI suite through Xcode against the designated simulator. It covers real SQLite/file-backed scene restoration, cached documents, EPUB packages, PDF annotations, and adaptive native UI behavior.

`just test-performance` runs the 10,000-item real-SQLite benchmark alone, in an optimized release build, and without parallel test execution. Its ingestion, full-table read, FTS, and integrity budgets remain strict; ordinary tests and unrelated test processes no longer compete inside that measurement.

`just test-all` runs the four functional and performance lanes in order. `just verify` runs `just check` followed by `just test-all`.

Live Zotero Self-Host and Zotero Desktop acceptance remains explicit because it touches external accounts, credentials, deployed services, and cleanup. Those drills are never triggered by a local build or ordinary test command.
