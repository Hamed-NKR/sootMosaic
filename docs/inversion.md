# Inversion of tandem data

The `+INV` package imports instrument scans and provides functions for distributions, effective density, and mass.
Start with a local configuration and resolve each scan before constructing observations.

[Back to README](../README.md)

## Configuration

INV configuration holds inputs, scan settings, and model choices.
The instrument registry holds instrument constants and charge models.

```matlab
copyfile('config/main_inv/main_inv_config.example.json', ...
    'config/main_inv/main_inv_config.local.json')
cfg_inv = UTILS.LOAD_MAIN_INV_CONFIG;
```

| Setting | Content |
| --- | --- |
| `campaigns.table` | Campaign table |
| Applicable `inputs` paths | Measurement files or directories |
| `outputs.root` | Output location |
| `instruments` IDs | Registry entries for the instruments |
| `model_profile` | `current` |
| `SOOTMOSAIC_MAIN_INV_CONFIG` | Selector for another task file |

Set only fields marked `configurable` in `config/main_inv/main_inv.keys.json`.
Its citation field identifies each row's reference, record, registry entry, or
project default. `config/main_inv/DEFAULTS.md` explains the project defaults.
Keep other defaults while filling the input and instrument settings.

Measured scan values go in the second argument of
`UTILS.LOAD_MAIN_INV_CONFIG(file, data, campaign, opts)`.
The loader returns settings, instrument entries, SI values, and source records.
`opts.RequiredPaths` names required input keys for the calling stage.
Resolved SI values are in `cfg_inv.si` when the result is assigned to `cfg_inv`.

## Scan inputs

Select `mode` and its route, then import files with the matching reader.

| Input | Reader |
| --- | --- |
| Labeled SMPS exports | `INV.READ_SMPS` |
| Raw SMPS database records or database CSV exports | `INV.READ_SMPS_DB` |
| SASS and AACS scans with recorded row conditions | `INV.READ_AAC` |

For database CSV input, export `CatenaDataRecord`, `CatenaHeaderRecord`, and
`CatenaDeviceRecord` as same-named CSV files with column headers.
Set `inputs.database_reader` to `csv` and `inputs.csv_fallback_dir` to their directory.

Supply recorded scan settings and campaign dilution to the loader.
SMPS scans require `scan.counting_flow_lpm`.
Select SASS row handling with `aac_1d.row_operation`.

### AAC conditions

| Recorded setting | Loader key |
| --- | --- |
| Speed | `scan.aac_speed_rad_s` |
| Temperature | `scan.aac_temperature_deg_c` |
| Pressure | `scan.aac_pressure_kpa` |
| Sheath flow | `scan.aac_sheath_flow_lpm` |

For AAC rows, convert recorded pressure from Pa to kPa for the loader.
Leave the sheath-flow configuration at `null`. The AAC reader supplies
`Sheath (lpm)` in `scan.conditions` for each row.

AAC route B also requires the factors listed in `INV.OBSERVATION`.
These are `beta_ideal_ratio`, `beta_nonideal_ratio`, `software_efficiency_ratio`,
`counting_efficiency_ratio`, and `tube_penetration_ratio`.

### Counting efficiency and charge

For unity counting efficiency, supply `cpc.unity_bound_min_diameter_nm`,
`cpc.unity_bound_max_deficit`, and `cpc.unity_bound_citation`.
Select charge models with `opts.Model` in `INV.CHARGE_FRAC` calls.
Published charge-model coefficients are in `config/instruments/charging.json`.

## Processing sequence

### Select scans and build observations

Select campaign scans with `INV.SELECT_SCANS(imports, cases, cfg)`.
Resolve each selected scan and its campaign record before calling `INV.OBSERVATION`.
Use `INV.POOL_SCANS` for compatible repeat summaries on common diameter bins.

### Construct grids and kernels

Use `INV.GRID_RULE` to build the grid, `INV.KERNEL_1D` or `INV.KERNEL_2D`
for the forward matrix, and `INV.GRID_CONVERGE` for grid checks.
Run `QA.TEST_INV_KERNEL`.

Grid and kernel sources are the [method paper](https://doi.org/10.1016/j.jaerosci.2019.105484)
and [code release](https://doi.org/10.17632/sg2zj5yrvr.3).

### Weight observations and solve

Group `INV.OBSERVATION` results by campaign, mode, route, and condition before
calling `INV.OBS_VARIANCE`. Keep a stable `source_id` beside each `scan_index`.

| Variance call | Required input |
| --- | --- |
| Second raw-bin call | Fitted counts with one concentration profile |
| Pooled data | Positive variance floor for each condition, as a scalar, channel vector, or channels-by-scans matrix |

Weight the kernel and observation using the variances from `INV.OBS_VARIANCE`
before solving. Pass the returned final solve operator to `INV.POSTERIOR`.
Combine statistic values and propagated covariances with `INV.POST_MIX`.

Pass weighted kernels, observations, and grids to `INV.BAYESF` for scans of one
instrument mode. `INV.LOGDET` computes log determinants.
`INV.LAMBDA_XCHECK` supplies comparison scales.

### Fit peaks and calculate moments

Pass scan observations and a resolved configuration to `INV.PEAK_FIT`.
For route A counts, supply the `INV.BAYESF` selection for the same scan as its check.
Pass distributions, their scan limits, and the same-scan `INV.PEAK_FIT` result
to `INV.MOMENTS`.

### Calibrate density and integrate mass

Pass mobility diameters and the resolved configuration to `INV.CALIB_K`.
Divide each measured effective density by the returned factor once.
Pass a number distribution, its density relation, and the configuration to `INV.MASS`.

### Average groups and screen setpoints

Pass per-scan statistics or distributions and the resolved configuration to `INV.GROUP_AVG`.
Before a run, pass flows, temperature, and pressure to `INV.OP_RANGE` to screen setpoints.
Sheath flows outside the instrument range are refused.

## Function reference

Each file is under `+INV/`. Function help gives the arguments and units.

### Import and observations

| File | Purpose |
| --- | --- |
| `READ_SMPS.m` | Labeled SMPS exports |
| `READ_SMPS_DB.m` | Raw SMPS database records and CSV imports |
| `READ_AAC.m` | SASS and AACS scans with recorded row conditions |
| `SELECT_SCANS.m` | Campaign scan selection, exclusions, and dilution records |
| `OBSERVATION.m` | Route-specific observations and dilution conversion |
| `POOL_SCANS.m` | Repeat summaries on common diameter bins |

### Instrument physics

| File | Purpose |
| --- | --- |
| `GAS.m` | Gas viscosity, mean free path, and slip at recorded conditions |
| `DM_FROM_Z.m` | Diameter from electrical mobility and charge state |
| `AAC_SETPOINT.m` | Relaxation time and aerodynamic setpoint from AAC conditions |
| `RHO_EFF.m` | Effective density from aerodynamic and mobility diameters |
| `TFER_DMA.m` | Diffusing DMA transfer function |
| `TFER_AAC.m` | AAC transfer function and transmission |
| `PENETRATION.m` | Tube and classifier penetration |
| `CPC_EFF.m` | Counting efficiency |
| `CHARGE_FRAC.m` | Bipolar charge fractions and adaptive charge tails |

### Grids and forward response

| File | Purpose |
| --- | --- |
| `@Grid/` | One- and two-dimensional grids and quadrature widths |
| `@PartialGrid/` | Grids with selected cells |
| `GRID_RULE.m` | Kernel support, impactor settings, and reporting bands |
| `GRID_CONVERGE.m` | Grid comparisons for statistics and intervals |
| `KERNEL_1D.m` | Raw SMPS forward kernel |
| `SCAN_RESPONSE.m` | Scan averaging, delay, and response checks |
| `KERNEL_2D.m` | Raw AAC-DMA forward kernel |
| `OBS_VARIANCE.m` | Repeat-mean variances and pooled noise coefficients |

### Solvers and covariance

| File | Purpose |
| --- | --- |
| `TIKHONOV.m` | Nonnegative regularized distributions and explicit solve stages |
| `TIKHONOV_LPR.m` | Difference penalties on full and partial grids |
| `LSQ.m` | Weighted least-squares solves |
| `EXP_DIST.m` | Distributions with an exponential distance prior |
| `EXP_DIST_LPR.m` | Exponential distance covariance factors |
| `TWOMEY.m` | Multiplicative inversion cross-check |
| `TWOMARK.m` | Smoothed multiplicative inversion cross-check |
| `MARKOWSKI.m` | Three-point distribution smoothing |
| `MEAN_SQ_ERR.m` | Squared residual mean over nonzero observations |
| `POSTERIOR.m` | Conditional covariance and precision |
| `POST_MIX.m` | Weighted combinations of conditional moments |
| `DELTA_PROP.m` | Fixed-window statistic propagation |
| `TGIBBS.m` | Nonnegative Gaussian draws |
| `BAYESF.m` | Regularization evidence, scale probabilities, and pooled prior selection |
| `LOGDET.m` | Log determinants of matrices with positive determinants |
| `LAMBDA_XCHECK.m` | Regularization scales from three comparison criteria |

### Statistics and operating ranges

| File | Purpose |
| --- | --- |
| `PEAK_FIT.m` | Latent lognormal peak fitting |
| `MOMENTS.m` | Scan-window moments and tail bounds |
| `STAT_RESPONSE.m` | Statistic response diagnostics |
| `CALIB_K.m` | Density calibration factor, range flags, and source record |
| `MASS.m` | Mass concentration from number distributions |
| `GROUP_AVG.m` | Group means of per-scan results with Student t or day random-effects intervals |
| `OP_RANGE.m` | DMA, AAC and tandem operating ranges at given flows |

Measurement methods are cited in the [README references](../README.md#references),
including references 13 through 16.
