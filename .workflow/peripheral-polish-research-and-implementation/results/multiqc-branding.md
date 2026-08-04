# MultiQC branding research

## Recommendation

Use the current MAG pattern for the logo asset and the current Sarek pattern for
the static branding metadata:

1. Add the following to `assets/multiqc_config.yml`:

   ```yaml
   custom_logo: "nf-core-gwas_logo_light.png"
   custom_logo_url: https://github.com/nf-core/gwas/
   custom_logo_title: "nf-core/gwas"
   ```

2. Always stage a logo through the existing `multiqc_logo` input. Resolve that
   input as the user-supplied `--multiqc_logo` when present and otherwise as
   `${projectDir}/assets/nf-core-gwas_logo_light.png`.
3. Keep the module's existing `--cl-config 'custom_logo: ...'` command
   construction unchanged. It makes the explicitly staged logo authoritative
   and avoids relying on an unstaged relative asset path on remote executors.

In concrete terms, the workflow expression should have this shape:

```groovy
multiqc_logo
    ? file(multiqc_logo, checkIfExists: true)
    : file("${projectDir}/assets/nf-core-gwas_logo_light.png", checkIfExists: true)
```

This recommendation deliberately leaves `--multiqc_config` semantics outside
this branding change. The current GWAS workflow treats a user config as a
replacement for the bundled config; changing that to a base-plus-extra merge is
a separate public-interface decision.

## Precedence contract

The effective precedence should be:

1. The bundled light logo is used for an ordinary run.
2. `--multiqc_logo /path/to/logo.png` replaces the bundled logo.
3. If a custom MultiQC config also sets `custom_logo`, the dedicated
   `--multiqc_logo` value wins.

This is predictable because MultiQC loads `--config` files before
`--cl-config`, overwriting conflicts at each later stage. The nf-core MultiQC
module implements `multiqc_logo` with `--cl-config`, so it necessarily wins
over `custom_logo` in a config file. Users who want to customise the logo URL or
hover title as well can set `custom_logo_url` and `custom_logo_title` in their
custom config; those keys do not conflict with the module's command-line logo
path.

## Evidence from reference pipelines

### Sarek

- `.references/sarek/assets/multiqc_config.yml:1-3` sets
  `custom_logo`, `custom_logo_url`, and `custom_logo_title` to the pipeline's
  bundled light logo and public repository identity.
- `.references/sarek/workflows/sarek/main.nf:627-630` selects the bundled
  MultiQC config unless the user supplies `params.multiqc_config`, and passes a
  logo input only when `params.multiqc_logo` is supplied.
- `.references/sarek/modules/nf-core/multiqc/main.nf:26-27` loads the config
  with `--config` and applies the logo input with `--cl-config`.

Sarek establishes the desired static config vocabulary, but its default logo
depends on the relative path named inside the config rather than explicitly
staging that image through the logo input.

### MAG

- `.references/mag/assets/multiqc_config.yml:117-119` defines the same three
  branding keys.
- `.references/mag/workflows/mag.nf:618-626` always stages the bundled config
  and resolves `ch_multiqc_logo` to `params.multiqc_logo` or, by default, a
  bundled light logo.
- `.references/mag/workflows/mag.nf:680-683` supplies base config, extra user
  config, and the resolved logo separately to MultiQC.
- `.references/mag/modules/nf-core/multiqc/main.nf:29-31` puts the logo into
  `--cl-config`, after both config arguments.

MAG therefore provides the safer executor-independent asset-staging pattern and
an unambiguous dedicated-logo override.

### RNA-seq

- `.references/rnaseq/workflows/rnaseq/main.nf:816-818` supplies the bundled
  config, then the optional user config, then an optional user logo.
- `.references/rnaseq/modules/nf-core/multiqc/main.nf:26-27` uses ordered
  `--config` arguments and then `--cl-config` for the logo.
- Its bundled config does not currently set `custom_logo`; it is evidence for
  argument ordering, not for default pipeline branding.

### Current GWAS state

- `assets/nf-core-gwas_logo_light.png` already exists.
- `assets/multiqc_config.yml` contains report comments and section ordering but
  no `custom_logo`, `custom_logo_url`, or `custom_logo_title`.
- `workflows/gwas.nf:446-449` uses the bundled config by default but sends an
  empty logo input unless the user supplies `multiqc_logo`.
- `modules/nf-core/multiqc/main.nf:26-27` already has the required precedence:
  configs are emitted first and the logo is a later `--cl-config` value.

## Official MultiQC behavior

The current official documentation says that conflicting values are loaded in
increasing precedence: command `--config` files, then `--cl-config`, then
specific command-line options. It documents `custom_logo`,
`custom_logo_dark`, `custom_logo_url`, `custom_logo_title`, and
`custom_logo_width` as the report-branding keys. It also advises pipeline
authors to put config files in Nextflow channels so that they are staged
correctly, especially on cloud executors.

Sources:

- [MultiQC configuration and precedence](https://docs.seqera.io/multiqc/getting_started/config/)
- [MultiQC report logo configuration](https://docs.seqera.io/multiqc/reports/customisation/#report-logo--favicon)
- [Using MultiQC in pipelines](https://docs.seqera.io/multiqc/usage/pipelines/)

## Verification

Run two focused reports (a stubbed or smallest fixture-backed workflow is
sufficient) and inspect the generated HTML rather than only the task command:

1. Default run:
   - MultiQC task input contains `nf-core-gwas_logo_light.png`.
   - Report header displays the nf-core/gwas light logo.
   - Logo link targets `https://github.com/nf-core/gwas/`.
   - Hover title is `nf-core/gwas`.
2. Override run with `--multiqc_logo <distinct-test-logo>`:
   - MultiQC task input contains the supplied logo.
   - Report displays the supplied logo, not the bundled one.
   - Task command contains the supplied staged filename in the final
     `--cl-config` argument.
3. Run `nextflow config` (or the repository's normal config validation) to catch
   Groovy/config syntax errors.
4. Run the focused nf-test surface that exercises pipeline completion and
   MultiQC, updating snapshots only if the input staging or command snapshot is
   intentionally affected.

No production files were edited for this research packet.
