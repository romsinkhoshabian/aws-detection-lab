# Vulnerability Assessment / POA&M — detection-lab (Session 3)

## Scan Metadata

- **Scanner:** Nessus Essentials 10.12.4 (engine build 19.18.4)
- **Scan name:** detection-lab-session3
- **Target:** 44.202.234.246 (EC2 instance `i-0e3bc2f5909c89275`, Amazon Linux 2023, AMI `ami-05dee78f58650ed2c`)
- **Scope:** Credentialed host assessment over SSH. External exposure limited to ports 22 (SSH) and 8000 (Splunk Web) per the lab's security group — all other findings come from authenticated local checks, not network-exposed services.
- **Credential status:** Fully authenticated — `ec2-user` via SSH public key, with `sudo` privilege escalation confirmed working (Nessus plugin 110095, "No Issues Found"). Patch-level assessment confirmed functional (plugin 117887).

## Methodology Note

The scan was initially run without privilege escalation configured. This surfaced plugin 110385 ("Insufficient Privilege") — Nessus authenticated successfully but could not complete root-level checks (CPU speculative-execution mitigation flags under `/sys/kernel/debug/x86/`, plus a housekeeping tag write). Root cause was diagnosed by pulling the scan's saved credential configuration via the Nessus REST API (`/editor/scan/{id}`), which revealed **two duplicate SSH credential entries** — one with no escalation configured, one correctly set to `sudo`. The stale, non-escalated duplicate was deleted, the scan was re-run, and full privilege escalation was confirmed (plugin 110095 replaced 110385; additional root-only plugins — SELinux status, netstat listener enumeration — appeared in the results that followed).

## Summary

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| Informational | ~56 (host/software enumeration; no exploitable findings) |

Zero exploitable vulnerabilities identified. The Amazon Linux 2023 AMI is current on all applicable security patches as of the scan date, confirmed via authenticated package-level assessment (plugin 117887).

## Findings / Remediation Items

Tracked below despite Informational severity in Nessus's default scoring, since they represent real, actionable hardening opportunities rather than noise (host/software enumeration plugins are excluded as non-actionable).

### 1. SELinux running in permissive mode

- **Plugin:** 133964 (SELinux Status Check)
- **Detail:** SELinux is enabled, policy `targeted`, status `permissive`. Violations are logged but not enforced.
- **Risk:** No host-based mandatory access control enforcement, despite SELinux being present and configured.
- **Remediation:** Review `audit.log` for accumulated AVC denials, then set `SELINUX=enforcing` in `/etc/selinux/config` (and `setenforce 1` for the running session) once confirmed this won't break Splunk or the SSM Agent.
- **Status:** Open
- **Target completion:** Before session 4 (detections work) adds more services to harden against.

### 2. SSH SHA-1 HMAC algorithms enabled

- **Plugin:** 153588 (SSH SHA-1 HMAC Algorithms Enabled)
- **Detail:** Default OpenSSH config on the instance offers SHA-1-based MAC algorithms alongside stronger SHA-2 options.
- **Risk:** SHA-1 is deprecated for cryptographic integrity use; low practical risk here but a real hardening gap.
- **Remediation:** Restrict `MACs` in `sshd_config` to SHA-2/256+ algorithms only.
- **Status:** Open

### 3. Remote services not using post-quantum ciphers

- **Plugin:** 277650 (Remote Services Not Using Post-Quantum Ciphers)
- **Detail:** SSH does not offer PQC key exchange.
- **Risk:** Forward-looking "harvest now, decrypt later" exposure, not an active vulnerability. Relevant given DoD's PQC transition timeline.
- **Remediation:** No immediate action; revisit once PQC cipher suites are broadly supported in OpenSSH/OpenSSL.
- **Status:** Monitor

## Scan Completeness Statement

Credentialed depth confirmed end-to-end: SSH public-key authentication (`ec2-user`) plus `sudo` privilege escalation validated (plugin 110095). Patch-level comparison against Amazon Linux security advisories confirmed functional (plugin 117887). This scan represents a complete, authenticated assessment of the host's local security posture, not a network-only/unauthenticated pass.
