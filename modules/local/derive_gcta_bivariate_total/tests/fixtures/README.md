# `derive_gcta_bivariate_total` test fixtures

Two kinds of fixture, for two different jobs.

## Hand-computable test vectors

`synthetic_diagonal.{hsq,log}` and `synthetic_covariance.{hsq,log}` are **not** GCTA output. They are test
vectors written in GCTA's exact bivariate REML layout, with round variance components and a sampling
variance/covariance matrix chosen so that the total, its delta-method standard error, each sum's own standard
error and every runtime cross-check can be worked out on paper. They exist so the mathematics is pinned by
arithmetic rather than by a recorded number.

Both carry the same variance components:

| parameter | `V(Gk)_tr1` | `V(Gk)_tr2` | `C(Gk)_tr12` |
| --------- | ----------- | ----------- | ------------ |
| `G1`      | 1           | 1           | 0.5          |
| `G2`      | 3           | 3           | 1.5          |
| residual  | 4           | 4           | 2            |

so `a = 4`, `b = 4`, `c = 2` and

```
rg_total = c / sqrt(a * b) = 2 / sqrt(16) = 0.500000        (exactly)
gradient = (-rg/(2a), -rg/(2b), 1/sqrt(ab)) = (-0.0625, -0.0625, 0.25)   per component
```

**`synthetic_diagonal`** — the sampling covariance is `0.01 * I(9)`, so every printed standard error is
`sqrt(0.01) = 0.100000` and

```
var(rg) = 0.01 * 2 * (0.0625^2 + 0.0625^2 + 0.25^2) = 0.01 * 2 * 0.0703125 = 0.00140625
se(rg)  = 0.037500                                          (exactly)
se(sum V(Gk)_tr1) = sqrt(0.01 + 0.01) = 0.141421            (and the same for the other two sums)
rG1 = 0.5, se = sqrt(0.25 * (0.01/4 + 0.01/4 + 0.01/0.25)) = 0.106066
rG2 = 0.5, se = sqrt(0.25 * (0.01/36 + 0.01/36 + 0.01/2.25)) = 0.035355
```

**`synthetic_covariance`** — the same matrix with two off-diagonal entries added, one inside a component's
own block and one between the two components:

```
Cov(V(G1)_tr1, C(G1)_tr12) = 0.004
Cov(C(G1)_tr12, C(G2)_tr12) = 0.005

var(rg) = 0.00140625 + 2 * (-0.0625) * 0.004 * 0.25 + 2 * 0.25 * 0.005 * 0.25
        = 0.00140625 - 0.000125 + 0.000625 = 0.00190625
se(rg)  = 0.043661
se(sum C(Gk)_tr12) = sqrt(0.01 + 0.01 + 2 * 0.005) = 0.173205
rG1 se  = 0.096177   (the within-block entry enters GCTA's own per-component formula)
```

Every diagonal entry is unchanged, so this pair differs from the first only in what the delta-method standard
error of the total depends on. It is the case that goes red when the derivation drops the off-diagonal terms
(`se(rg)` returns to `0.037500`) or takes the wrong sign on the two variance-sum gradients (`0.046435`).

## Real GCTA output

Produced on the pinned image `community.wave.seqera.io/library/gcta:1.94.1--9bc35dc424fcf6e9` (GCTA
`v1.94.1 Linux`, built Nov 15 2022) from this repository's own compact fixture bundle — 200 samples, 2200
autosomal variants, `fixtures/genotypes/example_all.{bed,bim,fam}` and `fixtures/pheno_cov/example.pheno`,
which are the pipeline's simulated test data and carry no third-party licence. The phenotype passed to GCTA is
the fixture's `QT` column and its `BT` column recoded to 0/1, headerless.

Two GRM families were built:

```console
# LD-score-stratified, two LD bins over one MAF bin -- the shape the LDMS route builds
gcta --bfile example_all --ld-score-region 50 --out ldscore --thread-num 2
# median split of ldscore.score.ld's mean_rsq into ld01_maf01.snp and ld02_maf01.snp (1100 variants each)
gcta --bfile example_all --extract ld01_maf01.snp --make-grm --out ldms1 --thread-num 2
gcta --bfile example_all --extract ld02_maf01.snp --make-grm --out ldms2 --thread-num 2
# BIM halves, used only for the no-residual-covariance fit
gcta --bfile example_all --extract half1.snp --make-grm --out grm1 --thread-num 2
gcta --bfile example_all --extract half2.snp --make-grm --out grm2 --thread-num 2
```

| fixture                        | invocation                                                                                                                                       | K / P | why it is here                                                                                                                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `two_stratum.{hsq,log}`        | `gcta --reml-bivar 1 2 --mgrm ldms_two.mgrm --pheno qt_bt.pheno --reml-bivar-prevalence 0.1 --reml-maxit 500 --reml-no-constrain --thread-num 2` | 2 / 9 | the primary multi-component case; converged, zero constrained components, GCTA's bending note present, `total rg = -4.774394 (34.712390)`                                               |
| `one_stratum.{hsq,log}`        | the same with `--mgrm ldms_one.mgrm` and without `--reml-no-constrain`                                                                           | 1 / 6 | the degenerate case, and the production one-stratum layout: a one-entry `--mgrm` list makes GCTA suppress the component ordinal, so it writes `V(G)_*` and `rG` exactly as `--grm` does |
| `two_stratum_nocove.{hsq,log}` | `gcta --reml-bivar 1 2 --mgrm two.mgrm --pheno qt_bt.pheno --reml-bivar-prevalence 0.1 --reml-maxit 500 --reml-bivar-nocove --thread-num 2`      | 2 / 8 | the `P = 3K + 2` layout, and the `dropped_by_request` decision read out of the log's `Accepted options:` echo                                                                           |

Measured on those runs, and the reason the parser reads the log rather than the result:

- the `Sampling variance/covariance of the estimates of variance components:` block appears in the `.log`
  once and in no `.hsq`, for all three layouts (issue #34);
- the square root of its diagonal reproduces every `.hsq` standard error to at most `4.87e-07`, and the
  block is exactly symmetric;
- with `--reml-bivar-prevalence` the liability-scale `V(G)/Vp_*_L` rows are likewise in the `.log` only,
  while the univariate `--prevalence` control writes `V(G)/Vp_L` into its `.hsq` (issue #41).

The magnitudes on a 200-sample fixture are not scientifically meaningful; the layout, the cross-checks and the
warning vocabulary are what these fixtures pin.
