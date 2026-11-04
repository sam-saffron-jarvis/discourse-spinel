# A documented divergence (literals are frozen in spinel): the gate expects
# `spinel diff` to answer exception-diff with exit 1.
y = "lit".to_s
y << "!"
p y
