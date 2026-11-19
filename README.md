sootMosaic
==========

sootMosaic (formerly PFAL, the Post-Flame Agglomeration Algorithm) generates
soot-like fractal aggregates with Langevin dynamics (LD). First-stage LD
(LD1) builds an aggregate library. Scale or scatter calibration assigns size
distributions. Second-stage LD (LD2) simulates post-flame agglomeration while
each primary particle retains its assigned size.

Transmission electron microscopy (TEM) analysis runs independently. Validation
compares LD2 populations with processed TEM data and effective-density
measurements from a tandem aerodynamic aerosol classifier (AAC) and scanning
mobility particle sizer (SMPS). It produces diameter and density comparisons,
pointwise predictions, log-space metrics, and source records.

## Getting Started

### 1. Requirements

Use MATLAB R2022a or later with Java enabled and Statistics and Machine
Learning Toolbox. LD uses `lognrnd`, `geomean`, and `knnsearch`, calibration
uses `fitlm` and distribution functions, TEM uses `boxplot`, and validation
uses `gamrnd` and `tinv`. R2020b supplies `pagemtimes` and `exportgraphics`.
On R2020b or R2021 releases, quality-assurance (QA) tests need Signal
Processing Toolbox for `rms`. The separate `post_collapse` script needs R2023a for
`combinations`. Optional particle-outline plots need Image Processing
Toolbox for `viscircles`, and `UTILS.BAYESFIT_POLY2`, `3`, and `4` need
Econometrics Toolbox.

For the example PDF-to-PNG exports, install Poppler and make `pdftocairo`
available to MATLAB's `system` command. Direct raster export uses TEM
`plots.png_source` or validation `outputs.png_source` set to `"figure"`.
Choose installed fonts in each task's local configuration.

```matlab
ver
which pagemtimes
which exportgraphics
which lognrnd
which knnsearch
which fitlm
which gamrnd
which boxplot
which rms
assert(usejava('jvm'))
```

`ver` lists the products, each `which` resolves a function, and the assertion
completes when Java is enabled.

### 2. Getting the code

Install Git. Replace `REPOSITORY_URL` with this repository's clone address
and run this terminal command. It creates the `sootMosaic` folder.

```text
git clone REPOSITORY_URL sootMosaic
```

Start MATLAB in its parent folder. Both `which` calls should find this checkout.

```matlab
cd('sootMosaic')
addpath(pwd)
which main_LD1_v3
which UTILS.LOAD_MAIN_LD1_CONFIG
```

Keep the root as the current folder and repeat `addpath(pwd)` in new sessions.
Main scripts clear workspace variables and figures, so save them before running.

### 3. Local configuration

Copy the examples once to ignored local JSON files, then edit the copies.

```matlab
tasks = {'main_ld1', 'main_scale', 'main_scatter', ...
    'main_valid', 'main_tem_analysis'};
for k = 1:numel(tasks)
    folder = fullfile('config', tasks{k});
    stem = [tasks{k} '_config'];
    copyfile(fullfile(folder, [stem '.example.json']), ...
        fullfile(folder, [stem '.local.json']))
end
for branch = {'main_scatter', 'main_scale'}
    stem = ['main_ld2_from_' branch{1} '_config'];
    copyfile(fullfile('config', 'main_ld2', [stem '.example.json']), ...
        fullfile('config', 'main_ld2', [stem '.local.json']))
end
```

| Task | Keys to fill or check | Settings that can stay |
| --- | --- | --- |
| LD1 | `results.root`, `results.library_file` for output locations | All example settings, with no external input |
| Scale and scatter | `dataset.file` naming the LD1 library and `dataset.variable` of `pp0` | Example input path after LD1, distributions, correlations, sampling, and projection |
| LD2 | Select the scale or scatter local file and set `dataset.file` to its `pars_out` product | Branch output paths, transport, and `simulation.r_n_agg` |
| TEM | `entries[].entry_dir`, `aggregate.file`, `aggregate.variable`, `primary_particles.folder`, `file_pattern`, `area_column`, `aggregate_ids`, and `primary_particle_aggregate_ids` | Analysis, style, and output settings |
| Validation | `sources.ld2.file`, `sources.tem.file`, `sources.effective_density.file`, and enabled `conditions` mappings | Fits, references, physics, style, and output settings |

Task input paths and output roots are relative to the configuration folder.
LD1 `results.library_file` is relative to `results.root`. TEM aggregate files
and primary-particle folders are relative to `entries[].entry_dir`. LD lengths
and calibration particle products use meters. Configured calibration diameters
use nanometers, temperature uses kelvin, and pressure uses pascals.
Geometric standard deviations are dimensionless. Random seeds are set by LD
`simulation.rng_seed`, scatter `options.rng_seed`, and TEM
`analysis.random_seed`. Keep JSON numbers numeric and retain required sections.

An explicit loader filename takes precedence over environment selectors.
For each row below, `SOOTMOSAIC_` takes precedence over `PFAL_`. Use the
`PFAL_` settings when reproducing a setup that uses those variable names.

| Task | Environment selectors | Default local file under `config/` |
| --- | --- | --- |
| LD1 | `SOOTMOSAIC_MAIN_LD1_CONFIG`, `PFAL_MAIN_LD1_CONFIG` | `main_ld1/main_ld1_config.local.json` |
| LD2 | `SOOTMOSAIC_MAIN_LD2_CONFIG`, `PFAL_MAIN_LD2_CONFIG` | Select `main_ld2/main_ld2_from_main_scatter_config.local.json` or the `main_scale` branch |
| Scale | None | `main_scale/main_scale_config.local.json` |
| Scatter | None | `main_scatter/main_scatter_config.local.json` |
| TEM | `SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG`, `PFAL_MAIN_TEM_ANALYSIS_CONFIG` | `main_tem_analysis/main_tem_analysis_config.local.json` |
| Validation | `SOOTMOSAIC_MAIN_VALID_CONFIG`, `PFAL_MAIN_VALID_CONFIG` | `main_valid/main_valid_config.local.json` |

Select LD2 as shown in First runs. Clear a selector with `setenv(name, '')`,
including its paired fallback. Selections last for the MATLAB process.
Use full example copies for these six tasks. Profiles and registries use
`extends` for parent files relative to the overlay. Objects merge recursively,
arrays replace parent arrays, and objects with unique IDs merge by ID.
`config/sources/sources.local.json` overlays the sources registry.
The shared reader warns on unknown dictionary keys. `struct('Strict', true)`
turns these into errors when passed to `UTILS.CONFIG_READ` or as the fourth
argument of `UTILS.MODEL_PROFILE`. Direct task readers check required fields.

Set `model_profile` to `current` for the current models or
`article1_7658971` for the LD model choices of reference 6. To use the
selected profile's model choices, set `transport.fluid_options`,
`transport.velocity_options`, and `transport.diagnostics_options` to `{}`,
and remove `mtd`, `slip`, `continuum_diameter`, `root_solve`, `projection`,
`proj_cache`, `proj_points`, `proj_orientations`, `proj_replicates`, and
`proj_tol` from `transport.mobility_options`. Keep `c_dt` and the step
settings. Inspect `cfg.model` and `cfg.model_params` from the task loader to
see the resolved choices. Custom profiles go in `config/profiles/<name>.json`
with `extends` naming the parent profile.

Inversion (INV) configuration holds inputs, scan settings, and model choices.
The instrument registry holds instrument constants and charge models. Copy the
example below, then fill `campaigns.table`, applicable `inputs` paths,
`outputs.root`, and instrument IDs. Set only fields marked `configurable` in
`config/main_inv/main_inv.keys.json`. Measured scan values are passed in the
second argument of `UTILS.LOAD_MAIN_INV_CONFIG(file, data, campaign, opts)`.
Keep other defaults, including `model_profile` of
`current`. Loading returns settings, instrument entries, International System
of Units (SI) values, and source records. `SOOTMOSAIC_MAIN_INV_CONFIG` selects
another file.

```matlab
copyfile('config/main_inv/main_inv_config.example.json', ...
    'config/main_inv/main_inv_config.local.json')
cfg_inv = UTILS.LOAD_MAIN_INV_CONFIG;
```

Select `mode` and its route. For database CSV input, export
`CatenaDataRecord`, `CatenaHeaderRecord`, and `CatenaDeviceRecord` as same-named
CSV files with column headers. Set `inputs.database_reader` to `csv` and
`inputs.csv_fallback_dir` to their directory. Supply recorded scan settings,
including `scan.counting_flow_lpm` for SMPS, and campaign dilution to the
loader. Select SASS row handling with `aac_1d.row_operation`.

Use `INV.GRID_RULE` to build the grid, `INV.KERNEL_1D` or
`INV.KERNEL_2D` for the forward matrix, and `INV.GRID_CONVERGE`
for grid checks. Run `QA.TEST_INV_KERNEL`.

Grid and kernel references: [method](https://doi.org/10.1016/j.jaerosci.2019.105484)
and [code](https://doi.org/10.17632/sg2zj5yrvr.3).

For AAC setpoints, supply each scan's recorded `scan.aac_speed_rad_s`,
`scan.aac_temperature_deg_c`, `scan.aac_pressure_kpa`, and
`scan.aac_sheath_flow_lpm`. Leave the sheath-flow configuration at `null`;
the AAC reader supplies `Sheath (lpm)` in `scan.conditions` for each row.

For unity counting efficiency, supply `cpc.unity_bound_min_diameter_nm`,
`cpc.unity_bound_max_deficit`, and `cpc.unity_bound_citation`.

### 4. Data

Generate simulation inputs in pipeline order and place measured inputs under
`data/`. `config/sources/sources.json` lists registered products, with `file`
and `cache_file` relative to `data/`. Task `dataset` and `sources` blocks
select input files. Scale, scatter and LD2 configurations can use only
`source_id` in `dataset`; validation can use only `source_id` in each `sources`
entry. Omitted source fields come from the registry.
Dataset loader calls can select a registry entry through
`struct('source_id', '<registered_id>')`, with inline fields taking precedence.

For downloads, fill `url` with a direct MAT address, `doi` with the publication
identifier, and `sha256` with its published SHA-256 digest. Loaders check a
nonempty digest for local, cached, and downloaded files. Obtain missing
digests from the publication or supplier. An empty digest skips verification,
and a URL with an empty digest produces `MissingChecksum`.
Use `UTILS.FILE_SHA256(file)` to obtain a generated file's digest.

### 5. First runs

Run LD1, then either calibration branch, then LD2 from the repository root.

| MATLAB command | Expected product |
| --- | --- |
| `main_LD1_v3` | Prints `Saved LD1 aggregate library` and writes `data/main_ld1/ld1_aggregate_library.mat` with `pp0`, snapshots, gas state, and configuration |
| `main_scatter_v8` | Writes `data/main_scatter/scaled_aggs_for_LD2_from_main_scatter.mat` and a mode-specific copy with `pars_out`, metadata, and summary. Figures go to `results/main_scatter/` |
| `main_scale_v2` | Writes `data/main_scale/scaled_aggs_for_LD2_from_main_scale.mat` with `pars_out`. Figures go to `results/main_scale/` |

Scatter uses `bivariate` by default, with `sequential` and `ideal` selected by
`options.opt_scale`. Calibration outputs use fixed filenames. Select the
matching LD2 input, replacing `main_scatter` with `main_scale` for scale.

```matlab
setenv('SOOTMOSAIC_MAIN_LD2_CONFIG', ...
    'config/main_ld2/main_ld2_from_main_scatter_config.local.json')
main_LD2_v3
```

LD2 writes checkpoints and a final MAT file under
`results/main_ld2_from_main_scatter/LD2__scaled_aggs_for_LD2_from_main_scatter__YYYY-MM-DD/`.
Final names start with `LD2__from_main_scatter__final__` and end in a timestamp.
The scale branch uses `main_scale` in these names. The workspace includes
`parsdata`, `r_n_agg`, `fl`, `cfg_ld2`, and source metadata.
`UTILS.RESUME_LD2_V3` prompts for a checkpoint folder and filename and resumes
into that run folder. Those two strings can also be passed as arguments.

For TEM, place aggregate MAT files and primary-area CSV files in the configured
entry folders, normally `data/tem_analysis/`. The example reads an `Aggs`
structure array with `da` in nanometers and the morphology fields `n_subagg`,
`n_colaps`, `ca`, `zbar_opt`, and `sbar_opt`. CSVs contain an `Area` column in
square nanometers. Set `analysis.primary_area_start_row` to 2 when the first
data row describes the aggregate or background, or 1 when it describes a
primary particle. Aggregate IDs index `Aggs`, and `%d` in
`primary_particles.file_pattern` receives that index. Primary-particle IDs must
be a subset of aggregate IDs. Run
`main_tem_analysis_v1` to write `data/main_tem_analysis/tem_analysis_results.mat`,
summary CSVs, and figures in `results/main_tem_analysis/`. The MAT file
contains `aggregate_table` and `morphology_table`.

For the named grouped density dataset, run this once to create the validation
companion. It reads `dist_grp` and `test_condition`, then writes
`effective_density_data`, `metadata`, and a checksum sidecar.

```matlab
source_file = fullfile('data', 'experimental_effective_density', ...
    'Effective_Density_Compiled-17_Mar_2025-05_00_44.mat');
output_file = fullfile('data', 'experimental_effective_density', ...
    'effective_density_validation_data.mat');
UTILS.NORMALIZE_EFFECTIVE_DENSITY_DATA(source_file, output_file, ...
    'ExpectedSourceSHA256', ...
    '3EEF1BC1981EE654BA5FE0198AF50EA977DAEFA5973D37AE27DD787A5844048C');
```

Set validation `sources.ld2.file` to the final LD2 file and confirm the TEM
and density paths. Map enabled conditions to LD2 fractions, TEM entry IDs,
and density condition IDs. The example selects fraction 1 for low
agglomeration and 0.1 plus 0.05 for high agglomeration. Run `main_valid_v3`.
It writes `validation_dpp_vs_da` and `validation_rho_eff_vs_dm` as PDF/PNG
pairs in `results/main_valid/`. Its `runs/<timestamp>/` folder holds the
resolved configuration, manifest, metrics, predictions, condition summaries,
and `validation_results.mat`.

Import files with the matching reader, then select campaign scans with
`INV.SELECT_SCANS(imports, cases, cfg)`. Resolve each selected scan and its
campaign record before calling `INV.OBSERVATION`. For AAC rows, convert
recorded pressure from Pa to kPa for the loader. AAC route B also requires
the correction factors described in `OBSERVATION`. Use `INV.POOL_SCANS` for
compatible repeat summaries. Select charge models with `opts.Model`.

### 6. Checking the install

Run all 23 QA functions. A pass prints one `PASS TEST_...`
line per file, with all returned `pass` flags true. These checks use synthetic
inputs or source inspection. Expected-warning cases can print warnings.

```matlab
warning('on', 'all')
checks = dir(fullfile('+QA', 'TEST_*.m'));
assert(numel(checks) == 23)
for k = 1:numel(checks)
    [~, name] = fileparts(checks(k).name);
    report = feval(['QA.' name]);
    assert(~isempty(report) && all([report.pass]), name)
    fprintf('PASS %s\n', name)
end
```

For a synthetic validation run, create fixtures and load them as follows.
The fixtures go to `data/main_valid_webtest/server/` and exports go to
`results/main_valid_synthetic/`. The assertion checks that metrics were returned.

```matlab
files = UTILS.CREATE_MAIN_VALID_WEBTEST_FIXTURES;
cfg = UTILS.LOAD_MAIN_VALID_CONFIG( ...
    'config/main_valid/main_valid_config.example.json');
for item = {'ld2', 'tem', 'effective_density'}
    cfg.sources.(item{1}).file = files.(item{1});
end
cfg.figures.visible = 'off';
cfg.outputs.png_source = 'figure';
cfg.outputs.root = fullfile(pwd, 'results', 'main_valid_synthetic');
result = UTILS.RUN_MAIN_VALIDATION(cfg);
assert(~isempty(result.metrics))
```

### 7. When something fails

Errors use `sootMosaic:<FUNCTION>:<Reason>`. Check the named function and the
reported key or file. Capture an error identifier and message with
`try, main_LD2_v3, catch err, disp(err.identifier), disp(err.message), end`.

The scale, scatter and TEM scripts use the caller's warning settings.
When enabled, `sootMosaic:main_tem_analysis_v1:MissingPrimaryCsv` reports a
missing primary CSV skipped during TEM analysis.

| Error or symptom | Action |
| --- | --- |
| Function not found | Run `addpath(pwd)` from the repository root and check `which` and `ver` |
| `MissingConfig` or `MissingConfigSelection` | Copy the example and check both selectors. LD2 requires a branch selection |
| `InvalidConfig`, `InvalidJSON`, or `MissingSection` | Check JSON syntax and required sections against the example |
| `UnknownKey` | Use the key spelling in the dictionary |
| `MissingFileOnDisk`, `MissingFile`, or `MissingAggregateFile` | Generate the upstream product or supply the measurement file at the configured path |
| `MissingVariableInFile`, `MissingVariable`, or `MissingTableVariables` | Supply the expected MAT variables and table columns |
| `MissingChecksum` or `ChecksumMismatch` | Supply the published digest and a matching source or cached file |
| `MissingTEMMapping` or `MissingDensityMapping` | Match enabled condition IDs to the input tables |
| `InvalidProjection` | Use cache with `isotropic`, orientations divisible by replicates, and `proj_tol` of `"none"` for one replicate |
| `RendererFailed` | Install `pdftocairo` or select `"figure"` for `png_source` |

## Soot as a mosaic

In a flame, soot aggregates can grow with primary particles of nearly uniform
size inside each aggregate, while that size differs from one aggregate to the
next. Downstream, as the soot dilutes and cools, the aggregates keep colliding.
A collision can join aggregates of different primary size into one hybrid
structure. Each parent aggregate remains visible as a patch of its own
primary size, giving the hybrid the appearance of a mosaic.

![Hybrid soot TEM examples](https://github.com/user-attachments/assets/db858f62-1e22-471c-90ad-dc06329de681)

## How the Langevin dynamics loop works

1. Read physical, domain, transport, and output parameters.
2. Initialize primary-particle sizes and aggregate morphology.
3. Assign random particle locations and velocities.
4. Compute mobility and Brownian transport properties.
5. March positions and velocities under Brownian motion, drag, and inertia.
6. Apply periodic boundary conditions.
7. Detect collisions and connect touching aggregates.
8. Update geometry, mobility, and saved diagnostics.

## Configuration reference

| Dictionary | Scope |
| --- | --- |
| [`config/profiles/profile.keys.json`](config/profiles/profile.keys.json) | Model choices, constants, stage sections, units, and aliases |
| [`config/sources/sources.keys.json`](config/sources/sources.keys.json) | Registered dataset fields and local `where` selection |
| [`config/main_inv/main_inv.keys.json`](config/main_inv/main_inv.keys.json) | INV defaults, units, and input reading rules |
| [`config/instruments/instruments.keys.json`](config/instruments/instruments.keys.json) | Instrument and charging registry fields |

Task examples and `UTILS.LOAD_MAIN_*_CONFIG` define the task settings. TEM
style uses `plots` and `entries[].style`, and validation style uses `figures`
and `conditions[].style`.

`opts.RequiredPaths` lists required input keys. Resolved SI values are in
`cfg_inv.si`.

### TEM and validation figures

TEM `plots.figures.<figure_id>` controls enabled state, ordered
`condition_ids`, axes, layout, legend, and figure options. `entries[].style`
controls markers, condition colors, box colors, and independent `stack_colors`
for subaggregate count and collapsed-subaggregate frequency figures. Add an
entry and its ID to the required figure lists to include another condition.

`plots.frequency_bins` defines frequency boundaries and their inclusivity. The
example uses blue shades for low agglomeration and orange for high
agglomeration. Shared axes and labels use `plots.axes`, fonts use `plots.font`,
and boxes use `plots.boxplot`. Export controls are scalar fields such as
`plots.export`, `plots.pdf`, `plots.png`, and `plots.png_resolution`.
`plots.format` and `plots.resolution` are accepted export controls.

The TEM figure set includes the manual correlation, two primary-distribution
Appendix variants, aggregate metrics, a mirrored exact-count lollipop
distribution for two conditions, two stacked-frequency figures, and a
subaggregate-category correlation. The mirrored plot has a condition legend and
independent major/minor grids. Figures are built off-screen at configured
dimensions before export, preserving their aspect ratios.

Both examples use normal font weight, 13-point axes, 18-point labels, and
15-point legends. Vector PDFs and 600-dpi PNGs rendered from them share fonts
and geometry. Axis-label offsets and tick rotation are configurable. TEM's
example uses horizontal multiline condition labels.

Validation controls Bayesian degree, credible level, posterior draws, priors,
reference relations, and exports separately. `figures.legend` sets location,
columns, orientation, border, and interpreter. `figures.font.legend_size` sets
text size, `figures.axis_line_width` sets frame/tick weight, and `figures.axes`
sets label offsets and rotation. Each condition's `style.experimental_*` fields
set measurement edges, faces, sizes, and outline widths independently of
simulation color. Example marker faces are `none`. Empty axis limits select
automatic limits.

### Transport models and saved records

Scale, scatter and LD2 products store resolved source metadata in `dataset_src`
and registry/overlay provenance in `dataset_provenance`. Validation stores
provenance in `manifest.sources.<source>.provenance` in `validation_results.mat`
and `sources.<source>.provenance` in `run_manifest.json`.

LD2 final results contain one `r_n_agg` entry per retained snapshot. The
requested schedule remains in `cfg_ld2.simulation.r_n_agg`; validation requests
select only fractions present in the final result.

The LD1 and LD2 configs set the gas temperature and pressure under
`transport.fluid` and the property model under `transport.fluid_options.amb`.
The `current` profile gives the viscosity from 1.83245e-5 Pa s at 296.15 K with
the temperature law of reference 7, Eq. 9 (constant 110.4 K). For the
`sutherland` calculation, `article1_7658971` and calls without a gas section
use the reference viscosity 1.716e-5 Pa s at 273.15 K.
The mean free path is 67.3 nm at 296.15 K and 101325 Pa, scaled with
temperature and pressure as in reference 7, Eq. 11. The `flame` (1700 K) and
`room` (293.15 K) presets hold fixed values at 101325 Pa and warn when the
configured state differs by more than 1 K or 1 percent. The resolved profile is
saved as `cfg_ld1.model` or `cfg_ld2.model` with every result and checkpoint.

The dimensionless reference exponent is `reference.mass_mobility_exponent`.
`reference.d_m` is accepted as an alias. Parameter sections and SI values are
saved in `cfg.model_params`, and file digests, mirror flags and overrides in
`cfg.model_source`. The `current` physical constants use the exact 2019 SI
values `kb_j_k = 1.380649e-23`, `na_mol_inv = 6.02214076e23`, and their exact
decimal product `ru_j_mol_k = 8.31446261815324`. It supplies `e_c =
1.602176634e-19` (2019 SI) and `eps0_f_m = 8.8541878128e-12` (CODATA 2018) for
INV. The `article1_7658971` profile and profile-free calls use rounded
constants. The physical constants table has four columns and five rows in the
order `rho_bc`, `M_air`, `kb`, `Na`, `Ru`, with those names as row names. Named
access accepts reordered tables. Unnamed saved tables use the fixed row order.
Validation `physics.material_density_kg_m3` overrides the profile density and
is recorded in `cfg.model_params` and `cfg.model_source`. The resolved density
uses the material density for `per_caller_7658971` and the aerodynamic
reference density otherwise. The mobility root tolerance is recorded as
`default` only for that slip choice with `start_point_7658971`, and as
`eps_scaled` otherwise. Its dimensional value depends on the diameters at the
solve. Mobility calls without options read `UTILS.CALL_DEFAULTS`, including
method `continuum` and `c_dt` of 1. Sampling and property call defaults are
listed alongside them. `QA.TEST_MODEL_PROFILE` and `QA.TEST_CALL_DEFAULTS`
check the files, mirrors, loaders and call interface.

The slip correction is set under `transport.mobility_options.slip` and computed
by `TRANSP.CUNNINGHAM`. The `kim2005` model uses the constants of Kim et al.
(2005), 1.165, 0.483 and 0.997 with Kn = 2 lambda / d, the same in the
mobility, mobility diameter and aerodynamic diameter functions, with the
aerodynamic diameter at the reference density of 1000 kg/m3. They were fitted
with the classical mean free path that the `sutherland` model gives. The
`per_caller_7658971` model supplies the per-function constants for
`article1_7658971` and calls without the option. The soot property table
`UTILS.TABGEN` accepts only `per_caller_7658971`.

The mobility method is set under `transport.mobility_options.mtd`, with the
profile default when the field is left out. `sorensen_eq17` (alias `continuum`)
gives the continuum mobility diameter dm = 1.29 N^-0.13 dg of Eq. 17 in
Sorensen (2011) at every number of primaries N. Here dm is mobility diameter,
dg is gyration diameter, and dp is primary diameter. `sorensen_backbone` gives
dm = dp for a single primary, Eq. 18a for a doublet (dm = 2^0.46 dp for two
equal touching spheres), Eq. 17 for N from 3 to 74 and dm = 0.75 dg above, the
ratio that Eq. 18b gives for fractal dimension 1.78 and prefactor 1.3. The
crossover is N = 74. Above it, the model uses the diffusion-limited cluster
aggregation (DLCA) ratio of 0.75. `interp` solves
the adjusted sphere relation in the form given by Rogak et al. (1993) between
the projected area diameter and the continuum diameter named by
`continuum_diameter`, `fixed_075dg` (0.75 dg at every N) or `sorensen_backbone`
(the relations above, so that a single primary has dm = dp at every Knudsen
number). `root_solve` is `start_point_7658971` (fzero from one start point) or
`bracketed` (fzero on the interval between the two limit diameters, which holds
the root). `free_molecular` sets dm to the projected area diameter, the free
molecular limit of Sorensen (2011) and Rogak et al. (1993). The `current`
profile uses `interp` with `sorensen_backbone` and `bracketed` in both stages,
`article1_7658971` uses `sorensen_eq17` in LD1 and `interp` with `fixed_075dg`
and `start_point_7658971` in LD2.

`interp` and `free_molecular` take the projected area from the method named by
`projection`. `euler_7658971` calls `PAR.PROJECTION` for every aggregate at
every step with `proj_points` random points and `proj_orientations` triples of
Euler angles drawn uniformly in [0, 2 pi). The `article1_7658971` profile uses
100 points and 5 orientations. `isotropic` uses `PAR.PROJECTION_ISO`. It
rotates `proj_replicates` sets of directions from a spherical Fibonacci lattice
on the half sphere. Independent uniform rotations make each direction uniform
on the sphere. It counts covered points on a randomly shifted square grid with
`ceil(sqrt(proj_points))^2` points in each of the `proj_orientations`
orientations. A single primary has the area pi dp^2 / 4. With `proj_cache` set
to true, `PAR.PROJECTION_CACHE` reuses areas for unchanged geometry and samples
new aggregates after a merge. `proj_tol` controls the sampling-resolution
check. With one replicate, set `proj_tol` to `"none"`. `isotropic` takes
particle structures. Saved projected areas for mobility methods without da use
`PAR.PROJECTION` and the configuration's `projection` section. The `current`
profile uses `isotropic` with the cache, 1024 points, 64 orientations in 4 sets
and `proj_tol` 0.01, and `article1_7658971` uses `euler_7658971` without the
cache.

`TRANSP.MOBIL` stores two single-particle Knudsen numbers with every particle,
the gas Knudsen number `kn_kin` = 2 lambda / dm and `kn_diff` = 2 (m kT)^0.5 /
(f dm). Here m is mass, k is the Boltzmann constant, T is temperature, f is
friction, and lambda is gas mean free path. With
`transport.diagnostics_options.knudsen` set to true, `TRANSP.KNUDSEN` adds two
numbers of the literature at every recorded step. The pair diffusive Knudsen
number of Eq. 11 in reference 10 uses each particle and its nearest neighbor
under the periodic minimum image. It uses reduced mass and friction, combined
Smoluchowski radius (dm_i + dm_j) / 2, and combined projected area pi (da_i +
da_j)^2 / 4. Methods without projected area use dm in place of da. For two
identical spheres it equals `kn_diff` / 2^0.5, Eq. 2 of reference 11. The
nearest-neighbor Knudsen number of reference 11 is (18 D tau)^0.5 / rn with rn
= n^(-1/3) - 2 rmax, from the number concentration n and the mean maximum
radius rmax. D is diffusivity and tau is relaxation time. `ensdata` (`ensdata0`
in LD1) gains `kn_pair` and `knn`, each as mean and standard deviation over the
particles, and `knn_defined`, which is false with `knn` set to NaN where rn is
not positive. The diagnostics change neither the particles nor the random
numbers. The `current` profile records them and `article1_7658971` does not.
Reference 12 gives the particle mean free path of another convention, 3.19
times the length (m kT)^0.5 / f of `kn_diff`.

The initial velocities are drawn by `PAR.INIT_VEL` with the sampler named under
`transport.velocity_options.sampler`, with the profile default when the field
is left out. `maxwell_boltzmann` draws each of the three components from a
normal distribution with zero mean and variance kT / m. The mean kinetic energy
is 1.5 kT. Speeds follow the Maxwell-Boltzmann distribution with mean speed (8
kT / (pi m))^0.5 of reference 12. `mean_speed_7658971` assigns every particle
that mean speed with the polar angle uniform in [0, pi], which gives the mean
kinetic energy 4 kT / pi. The `current` profile uses `maxwell_boltzmann` and
`article1_7658971` uses `mean_speed_7658971`.

## Repository map

| Path | Contents |
| --- | --- |
| `main_LD1_v3.m` | First-stage aggregate-library generation |
| `main_scale_v2.m` | Correlation-based library scaling |
| `main_scatter_v8.m` | Library sampling and scaling |
| `main_LD2_v3.m` | Post-flame agglomeration |
| `main_tem_analysis_v1.m` | TEM analysis and figures |
| `main_valid_v3.m` | LD2, TEM, and effective-density comparisons |
| Other `main_*` and `post_*` scripts | Shielding, collapse, and post-processing analyses with script-level inputs |
| `config/` | Task configurations, profiles, and registries |
| `config/main_ld1/` | LD1 example configuration |
| `config/main_ld2/` | Scale and scatter branch examples for LD2 |
| `config/main_scale/` | Correlation-based calibration example |
| `config/main_scatter/` | Distribution-based calibration example |
| `config/main_tem_analysis/` | TEM inputs, analysis, and figure settings |
| `config/main_valid/` | Validation inputs, condition mappings, and exports |
| `config/main_inv/` | Inversion configuration example and key dictionary |
| `config/main_inv/main_inv_config.example.json` | Inversion configuration example |
| `config/main_inv/main_inv.keys.json` | Inversion settings and reading rules |
| `config/instruments/charging.json` | Published charge-model coefficients |
| `config/instruments/` | Instrument constants, charge models, and dictionary |
| `config/profiles/` | Model profiles and dictionary |
| `config/sources/` | Dataset registry and dictionary |
| `+COL/` | Collision detection, connection, and aggregate growth |
| `+DEPOT/` | Additional simulation and analysis scripts |
| `+INV/` | Instrument import and inversion functions |
| `+INV/READ_SMPS.m` | Labeled SMPS exports |
| `+INV/READ_SMPS_DB.m` | Raw SMPS database records and CSV imports |
| `+INV/READ_AAC.m` | SASS and AACS scans with recorded row conditions |
| `+INV/SELECT_SCANS.m` | Campaign scan selection, exclusions, and dilution records |
| `+INV/OBSERVATION.m` | Route-specific observations and dilution conversion |
| `+INV/POOL_SCANS.m` | Repeat summaries on common diameter bins |
| `+INV/GAS.m` | Gas viscosity, mean free path, and slip at recorded conditions |
| `+INV/DM_FROM_Z.m` | Diameter from electrical mobility and charge state |
| `+INV/AAC_SETPOINT.m` | Relaxation time and aerodynamic setpoint from AAC conditions |
| `+INV/RHO_EFF.m` | Effective density from aerodynamic and mobility diameters |
| `+INV/TFER_DMA.m` | Diffusing DMA transfer function |
| `+INV/TFER_AAC.m` | AAC transfer function and transmission |
| `+INV/PENETRATION.m` | Tube and classifier penetration |
| `+INV/CPC_EFF.m` | Counting efficiency |
| `+INV/CHARGE_FRAC.m` | Bipolar charge fractions and adaptive charge tails |
| `+INV/@Grid/` | One- and two-dimensional grids and quadrature widths |
| `+INV/@PartialGrid/` | Grids with selected cells |
| `+INV/GRID_RULE.m` | Kernel support, impactor settings, and reporting bands |
| `+INV/GRID_CONVERGE.m` | Grid comparisons for statistics and intervals |
| `+INV/KERNEL_1D.m` | Raw SMPS forward kernel |
| `+INV/SCAN_RESPONSE.m` | Scan averaging, delay, and response checks |
| `+INV/KERNEL_2D.m` | Raw AAC-DMA forward kernel |
| `+PAR/` | Particle initialization, sizing, projection, and geometry |
| `+QA/` | Synthetic tests and aggregate geometry checks |
| `+TRANSP/` | Transport properties, mobility, marching, and boundaries |
| `+UTILS/` | Configuration, data loading, checkpoint resume, fitting, and plotting |
| `+VIS/` | Visualization routines |
| `@AGG/` | Aggregate class |
| `data/` | Measured inputs and generated handoff files |
| `results/` | Generated workspaces, figures, and validation records |
| `inputs/` | Tab-delimited parameter files |
| `THIRD_PARTY_NOTICES.md` | Source and license notices for adapted code |

Generated data, `results/`, `outputs/`, `.sootmosaic-cache/`, and
`.pfal-cache/` are ignored by `.gitignore`.

## References

1. Suresh, V., & Gopalakrishnan, R. (2021). Tutorial: Langevin Dynamics
   methods for aerosol particle trajectory simulations and collision rate
   constant modeling. Journal of Aerosol Science, 155, 105746.
2. Heine, M. C., & Pratsinis, S. E. (2007). Brownian coagulation at high
   concentration. Langmuir, 23(19), 9882-9890.
3. Brasil, A. M., Farias, T. L., & Carvalho, M. G. (1999). A recipe for image
   characterization of fractal-like aggregates. Journal of Aerosol Science,
   30(10), 1379-1389.
4. Olfert, J., & Rogak, S. (2019). Universal relations between soot effective
   density and primary particle size for common combustion sources. Aerosol
   Science and Technology, 53(5), 485-492.
5. Baldelli, A., Trivanovic, U., Corbin, J. C., Lobo, P., Gagne, S., Mille,
   J. W., and Rogak, S. (2020). Typical and atypical morphology of
   non-volatile particles from a diesel and natural gas marine engine. Aerosol
   and Air Quality Research, 20(4), 730-740.
6. Nikookar, H., Sipkens, T. A., & Rogak, S. N. (2025). Simulating the effect
   of post-flame agglomeration on the structure of soot. Aerosol Science and
   Technology, 59(1), 1-15.
7. Kim, J. H., Mulholland, G. W., Kukuck, S. R., & Pui, D. Y. H. (2005). Slip
   correction measurements of certified PSL nanoparticles using a nanometer
   differential mobility analyzer (nano-DMA) for Knudsen number from 0.5 to
   83. Journal of Research of the National Institute of Standards and
   Technology, 110(1), 31-54.
8. Sorensen, C. M. (2011). The mobility of fractal aggregates: A review.
   Aerosol Science and Technology, 45(7), 765-779.
9. Rogak, S. N., Flagan, R. C., & Nguyen, H. V. (1993). The mobility and
   structure of aerosol agglomerates. Aerosol Science and Technology, 18(1),
   25-47.
10. Thajudeen, T., Gopalakrishnan, R., & Hogan, C. J., Jr. (2012). The
    collision rate of nonspherical particles and aggregates for all diffusive
    Knudsen numbers. Aerosol Science and Technology, 46(11), 1174-1186.
11. Moran, J., Yon, J., Poux, A., Corbin, F., Ouf, F.-X., & Simeon, A.
    (2020). Monte Carlo Aggregation Code (MCAC) Part 2: Application to soot
    agglomeration, highlighting the importance of primary particles. Journal
    of Colloid and Interface Science, 575, 274-285.
12. Eggersdorfer, M. L., & Pratsinis, S. E. (2014). Agglomerates and
    aggregates of nanoparticles made in the gas phase. Advanced Powder
    Technology, 25(1), 71-90.
13. Kiasadegh, M., Sipkens, T. A., Symonds, J. P. R., & Olfert, J. S.
    (2026). Practical considerations for measuring effective density:
    Operational tradeoffs in resolution, characteristic scan time, and
    calibration. Aerosol Science and Technology, 60(7), 695-714.
    DOI 10.1080/02786826.2026.2659050.
14. tandem (software), release v2.0.0.
    https://github.com/cambustion/tandem.
