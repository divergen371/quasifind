# Resilience Hardening Walkthrough

This document outlines the verification steps for the new resilience features in Quasifind.

## Changes Verified

### 1. Heartbeat Monitoring

The watcher now supports sending periodic heartbeat signals to a specified URL. This allows external monitoring systems (like Uptime Kuma) to detect if the Quasifind process has been terminated.

**Verification Step:**
Start a listener (e.g., using `nc`):

```bash
nc -l 8080
```

In another terminal, run Quasifind with heartbeat config (or manually set in config.json):

```bash
# Note: config.json editing required as CLI arg not fully exposed for heartbeat url yet,
# or use internal implementation details.
# Actually, the logic repurposes `heartbeat_url` from config.
```

Since we didn't expose `--heartbeat-url` in CLI explicitly (only in config), we can verify by editing `~/.config/quasifind/config.json`:

```json
{
  ...
  "heartbeat_url": "http://localhost:8080",
  "heartbeat_interval": 5
}
```

Run watch mode:

```bash
quasifind . -w
```

You should see JSON payloads appearing in the `nc` window every 5 seconds.

### 2. Configuration Tamper Detection

The watcher automatically calculates the SHA256 hash of `config.json` and `rules.json` on startup. If these files change while the watcher is running, a CRITICAL alert is triggered.

**Verification Step:**

1. Start `quasifind . -w` (ensure you have a `~/.config/quasifind/config.json`).
2. Open another terminal and modify the config file:
   ```bash
   echo " " >> ~/.config/quasifind/config.json
   ```
3. Observe the output in the Quasifind terminal. You should see:
   `[CRITICAL] INTEGRITY ALERT: .../config.json has been modified!`
4. If webhook/slack is configured, an alert will be sent there too.

### 3. Binary Integrity Check

Added `--integrity` (or `-I`) flag to print the SHA256 hash of the running executable.

**Verification Step:**

```bash
quasifind --integrity
# Output: <sha256_hash>  <path_to_executable>
```

You can compare this hash against a known good value to ensure the binary hasn't been backdoored.

## Conclusion

The implemented features significantly improve the resilience of Quasifind as a monitoring agent.

- **Availability**: Heartbeats ensure you know if it stops.
- **Integrity**: Config watching ensures you know if rules are changed.
- **Trust**: Binary hashing allows verifying the executable itself.
