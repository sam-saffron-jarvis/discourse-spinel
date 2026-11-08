# Continuous publication

Committed migration checkpoints are checked every ten minutes. A changed source
head produces a new audited snapshot; unchanged heads produce no empty commits.
Only this public repository is updated, not upstream component repositories.

The publisher reads immutable Git objects without stopping, resetting, stashing or
editing active source trees. Uncommitted work waits until its source commit.
Each candidate has a complete per-file SHA-256 inventory and pinned component
heads. Source archives exclude runtime/build/data/credential directories and the
previously excluded upstream HTTP captures. Original licences remain intact.

Gitleaks 8.30.1 scans the candidate before publication. Reviewed public upstream
fixtures and non-secret source-hash/test-control metadata findings are accepted
ONLY while the entire file hash is unchanged. New/changed findings block
publication for review, not migration work.
No raw scanner report or private runtime evidence is published. Publication uses
a single lock and normal fast-forward Git pushes; it never force-pushes.

Historical helper snapshots and the legacy root backend are preserved, not used
as proof of current native-page acceptance. Publication is not deployment.
