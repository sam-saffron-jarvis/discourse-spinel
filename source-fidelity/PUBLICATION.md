# Publication boundary and verification

This is a source-only snapshot captured 2026-11-04T16:50:14.248738+11:00, including uncommitted work. No complete native application gate was run on this frozen dirty aggregate; previous passing results retain the narrower scopes stated in STATUS.md.

The publication export verified hashes for **30284** source files against the frozen component inventories. No Git metadata, task databases/dumps, runtime logs/captures, sessions, credentials/config volumes, binaries or generated frontend asset bundles were copied. 19 upstream HTTP capture fixtures were additionally omitted to avoid republishing credential-shaped request data.

Gitleaks8.30.1 scanned the complete export. Its 231 matches were reviewed as unchanged public upstream crypto/HMAC/serialization test fixtures; every matching file was byte-compared to its recorded public component base. There were no new or unreviewed credential matches. The test cryptographic values are not operational keys and must not be used as such. Raw scanner reports and private execution evidence are not bundled.

Licenses and third-party notices are preserved in their component directories. The existing adapted demo/history is retained; the newer fidelity work is clearly separated. No running task source was stopped, reset, stashed, cleaned or committed on the user's behalf for this export, and no live service was deployed.
