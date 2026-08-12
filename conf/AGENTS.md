# Pipeline configuration

This subtree owns pipeline scientific and integration policy, profiles, process selectors, extension arguments,
prefixes, resource settings, and publication. Apply
[`docs/coding-standards/configuration-and-schema.md`](../docs/coding-standards/configuration-and-schema.md).

Put method-family process settings in the relevant `conf/modules/*.config`; `conf/modules.config` is not an edit
target. Keep caller-owned policy out of installed and upstream-bound component bodies.
