# Changelog

## 0.1.2 (2026-04-08)

### Core Architecture & Features

- **PID Check for Updates:** Added process ID verification when updating state to improve consistency in [#74](https://github.com/software-mansion-labs/live-stash/pull/74)
- **Default Adapter Update:** Changed the default storage adapter to ETS for better out-of-the-box performance in [#73](https://github.com/software-mansion-labs/live-stash/pull/73)

### Bug Fixes

- **Browser Adapter TTL:** Fixed Time-To-Live (TTL) behavior issues specifically in the browser adapter in [#72](https://github.com/software-mansion-labs/live-stash/pull/72)
- **State Recovery Cleanup:** Improved recovery logic to automatically clear corrupted or "bad" states in [#62](https://github.com/software-mansion-labs/live-stash/pull/62)

### Documentation & Maintenance

- **README Refactor:** Streamlined the main README by removing redundant examples in [#76](https://github.com/software-mansion-labs/live-stash/pull/76)
- **Debug Log Removal:** Removed unnecessary debug logs to keep the production output clean in [#64](https://github.com/software-mansion-labs/live-stash/pull/64)

## 0.1.1 (2026-04-02)

### Internal Changes & Dependencies

- **Dependency Migration:** Replace `elixir_uuid` with `uniq` for improved UUID generation in [#57](https://github.com/software-mansion-labs/live-stash/pull/57).

### Documentation

- **Macro Documentation:** Documented the `__using__/1` macro for better developer experience in [#61](https://github.com/software-mansion-labs/live-stash/pull/61).
- **README Fixes:** Corrected source references and links within the README in [#59](https://github.com/software-mansion-labs/live-stash/pull/59).
- **Documentation Update:** General improvements and updates to the library documentation in [#60](https://github.com/software-mansion-labs/live-stash/pull/60).

## 0.1.0 (2026-03-31)

### Core Architecture & Features

- **Pluggable adapter architecture:** Re-designed the core to support flexible storage and transport layers in [#39](https://github.com/software-mansion-labs/live-stash/pull/39).
- **State recovery in server mode:** Implemented synchronization from other nodes for high availability in [#25](https://github.com/software-mansion-labs/live-stash/pull/25).
- **Security & Encryption:** Added optional data signing and encryption with salt support in [#22](https://github.com/software-mansion-labs/live-stash/pull/22).
- **API Simplification:** Major refactor to streamline the developer interface in [#30](https://github.com/software-mansion-labs/live-stash/pull/30).
- **Node discovery hints:** Added support for node hints to improve state location in [#28](https://github.com/software-mansion-labs/live-stash/pull/28).
- **Server-side UUIDs:** Added automatic UUID generation for server-mode instances in [#33](https://github.com/software-mansion-labs/live-stash/pull/33).
- **Browser memory management:** Improved state isolation by resetting browser memory during initialization in [#44](https://github.com/software-mansion-labs/live-stash/pull/44).

### Documentation & Examples

- **Enhanced Documentation:** Comprehensive update of README and technical docs in [#35](https://github.com/software-mansion-labs/live-stash/pull/35), [#49](https://github.com/software-mansion-labs/live-stash/pull/49).
- **New Architecture Guide:** Updated documentation to reflect the pluggable adapter system in [#45](https://github.com/software-mansion-labs/live-stash/pull/45).
- **Tic-Tac-Toe Example:** Added a side-by-side demo showcasing real-time synchronization in [#50](https://github.com/software-mansion-labs/live-stash/pull/50).
- **Authentication Example:** Added a guide for integrating user authentication in [#27](https://github.com/software-mansion-labs/live-stash/pull/27).
- **Visual Guide:** Added a demonstration video to the repository in [#52](https://github.com/software-mansion-labs/live-stash/pull/52).

### Testing & CI/CD

- **End-to-End Testing:** Introduced a suite of E2E tests for system validation in [#48](https://github.com/software-mansion-labs/live-stash/pull/48).
- **Unit Testing:** Created comprehensive unit tests for both client and server versions in [#37](https://github.com/software-mansion-labs/live-stash/pull/37).
- **Test Infrastructure:** Improved state finder tests and fixed timing-related issues in [#46](https://github.com/software-mansion-labs/live-stash/pull/46), [#51](https://github.com/software-mansion-labs/live-stash/pull/51).
- **Automation:** Added GitHub Actions for testing and automated release workflows in [#26](https://github.com/software-mansion-labs/live-stash/pull/26), [#43](https://github.com/software-mansion-labs/live-stash/pull/43).
