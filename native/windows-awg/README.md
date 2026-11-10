# FoxWay Windows AWG service controller

MIT wrapper around official amneziawg-windows/v3 v3.1.20260814. Commands up (config on stdin), stats (sanitized counters only), down, service (SCM only). Requires administrative rights. Protected copy of helper, DLL and machine-DPAPI encrypted configuration live below Program Files, not a user-writable service binary path. Service is demand-start, never automatic. Config hooks are rejected before service creation; raw parser errors and native logs are not printed. Only current Windows user's hashed FoxWay tunnel name is controlled. No production VPN servers are configured by development tools.

Compiled and exercised in CI without installing/running a tunnel. Actual service lifecycle and driver tests require a separate Windows test machine. The preview GUI requests elevation; a separate least-privilege installer/controller remains the production refinement. Corresponding upstream sources/license notices must accompany release binaries.
