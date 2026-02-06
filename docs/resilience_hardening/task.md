# Resilience Hardening Tasks

- [ ] **Design & Planning**
  - [ ] Create implementation plan (`docs/resilience_hardening/implementation_plan.md`)
  - [ ] Review plan with user

- [ ] **Implementation: Heartbeat Monitoring**
  - [ ] Update `Config` module to support `heartbeat_url` and `heartbeat_interval`
  - [ ] Implement periodic heartbeat mechanism in `Watcher` module
  - [ ] Verify heartbeat signals using a mock server

- [ ] **Implementation: Configuration Tamper Detection**
  - [ ] Modify `Watcher` to automatically include config files (`config.json`, `rules.json`) in the watch list
  - [ ] Implement integrity check logic (compare hash/checksum on change)
  - [ ] Add specific alert notification for configuration changes

- [ ] **Implementation: Binary Integrity (Basic)**
  - [ ] Add CLI option to output self-hash for verification
  - [ ] (Optional) Self-check on startup against a known good hash (if provided)

- [ ] **Documentation**
  - [ ] Update `README.md` with new configuration options and resilience best practices
  - [ ] Create `walkthrough.md` validating the new features
