# Resilience Hardening Implementation Plan

## Goal Description

Enhance `quasifind`'s resilience against attacks that attempt to disable or bypass its monitoring capabilities. Specifically, implement mechanisms to detect if the monitoring process is terminated (Heartbeat) and if the configuration files are tampered with.

## User Review Required

> [!IMPORTANT]
> **Heartbeat Strategy**: The heartbeat mechanism will send periodic POST requests to a specified `heartbeat_url`. The user is responsible for setting up the receiving end (e.g., a simple monitoring server or Uptime Kuma) to alert if the heartbeat stops.

> [!WARNING]
> **Config Tamper Alert**: When configuration files are modified, `quasifind` will send an alert. It will _not_ automatically reject the changes (to avoid locking out legitimate admins), but will loudly notify about the event with diffs or checksums.

## Proposed Changes

### Feature 1: Heartbeat Monitoring

#### [MODIFY] [config.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/config.ml)

- Add `heartbeat_url` (string option) and `heartbeat_interval` (int, default 60s) to the configuration record and JSON parser.

#### [MODIFY] [watcher.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/watcher.ml)

- Implement a concurrent fiber (using `Eio`) that wakes up every `heartbeat_interval` seconds.
- Send a HTTP POST request to `heartbeat_url` with a correct payload (timestamp, hostname, pid).
- Handle network errors gracefully (retries or logging, but don't crash the watcher).

### Feature 2: Configuration Tamper Detection

#### [MODIFY] [watcher.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/watcher.ml)

- In the `watch` function, automatically add the configuration directory (or specific files `config.json`, `rules.json`) to the watch list.
- Define a special handler for these files.
- Calculate SHA256 (or fast hash) of the config files on startup.
- On modification event:
  - Re-calculate hash.
  - If changed, trigger an "Integrity Alert" via configured notification channels (Webhook/Slack/Email).
  - Log the event as CRITICAL.

### Feature 3: Self-Diagnostics (Optional/Basic)

#### [MODIFY] [quasifind.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind.ml) (Main entry)

- Add `--self-check` or similar flag to print current binary hash for manual verification.

## Verification Plan

### Automated Tests

- **Heartbeat**: Mock the HTTP server and verify that `watcher` sends requests at the expected interval.
- **Config Watch**:
  1. Start watcher with a config.
  2. Modify `config.json` externally.
  3. Verify that an alert is generated (mock notification function).

### Manual Verification

1. Configure `heartbeat_url` to a local `nc -l` or RequestBin.
2. Run `quasifind ... -w`.
3. Verify heartbeat reception.
4. Kill `quasifind` (`kill -9`) -> Verify heartbeat stops (receiver side logic).
5. Open `config.json` and save it.
6. Verify "Configuration Changed" alert is received.
