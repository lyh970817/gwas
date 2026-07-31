# P27-LDAK result

Status: complete

Accepted:

- Added one focused negative test for the unsupported `ldak_reml` estimator.
- Removed the fictitious standalone `meta` output from `meta.yml`.
- Documented exactly 12 emitted channels: 11 metadata-bearing result tuples and
  one `[process, tool, version]` tuple.
- Retained runtime code, all eight strict joins, positive/stub tests, and
  snapshots unchanged.

Verification:

- Red seam: the new test using valid `reml` executed successfully and failed
  both rejection assertions.
- Direct Docker nf-test after switching to `ldak_reml`: 6/6 passed in 141.186
  seconds, with the expected guard message.
- `nf-core subworkflows lint grm_heritability_ldak --passed`: 35 passed,
  0 warnings, 0 failures.
- Docker wrapper: passed both stability runs after retrying one transient
  remote-ref lookup failure.
- Targeted pre-commit checks: passed.

Commit:

- `bfc1a88f1dc13edb06d4bcb00e0d301b11f34165`
  (`Document LDAK heritability outputs and reject invalid selectors`)
- `ab385b5227be6bbd2a450c34eaeb5bb7675f298b`
  (`Verify the LDAK estimator guard failure`) — review correction adding an
  exact guard-message assertion; focused Docker nf-test passed 6/6 in 200.062
  seconds.

Worktree:

- `/home/andongni/Yandex.Disk/Projects/Research/qc_dev/modules/.worktrees/modules/grm-heritability-ldak-hygiene`
