sootMosaic
==========

sootMosaic (formerly PFAL, the Post-Flame Agglomeration Algorithm) generates
soot-like fractal aggregates with a staged Langevin dynamics workflow. The core
simulation pipeline has three stages:

1. `main_LD1_v3.m` generates a raw first-stage aggregate library.
2. `main_scale_v2.m` or `main_scatter_v8.m` calibrates that library to target
   primary-particle and projected-area distributions.
3. `main_LD2_v3.m` runs second-stage post-flame agglomeration on the calibrated
   aggregate population.

`main_tem_analysis_v1.m` is a separate analysis workflow for TEM aggregate and
primary-particle measurements. It produces summary tables, model-input
statistics, and publication figures from configured datasets.

`main_valid_v3.m` compares selected LD2 populations with the processed TEM and
tandem AAC-SMPS effective-density measurements. It produces manuscript-ready
`d_pp` versus `d_a` and `rho_eff` versus `d_m` figures together with pointwise
predictions, log-space validation metrics, and source provenance.

The model represents soot aggregates that first form as compact
diffusion-limited clusters, acquire realistic size distributions, and continue
agglomerating after dilution or cooling. It is intended for studies of hybrid
soot structures with nonuniform primary-particle sizes.

Examples of hybrid soot imaged under transmission electron microscopy:

![Hybrid soot TEM examples](https://github.com/user-attachments/assets/db858f62-1e22-471c-90ad-dc06329de681)

## Soot as a mosaic

In a flame, soot aggregates can grow with primary particles of nearly uniform
size inside each aggregate, while that size differs from one aggregate to the
next. Downstream, as the soot dilutes and cools, the aggregates keep colliding,
and a collision can join aggregates of different primary size into one hybrid
structure. The result reads like a mosaic, with each parent aggregate still
visible as a patch of its own primary size. The TEM images above show such
hybrid aggregates.

The simulation is built in the same order. First-stage Langevin dynamics (LD1)
builds a library of aggregates that stands for the soot leaving the flame, and
a scaling or scatter step calibrates that library to measured primary-particle
and projected-area distributions. Second-stage Langevin dynamics (LD2) then
lets these pieces agglomerate after the flame, and every primary particle keeps
the size it was given. The resulting aggregates are compared with TEM
measurements of primary size against aggregate size and with tandem AAC-SMPS
measurements of effective density.

## How the Langevin dynamics loop works

Discrete element Langevin dynamics in sootMosaic follows these repeated operations:

1. Read physical, domain, transport, and output parameters.
2. Initialize primary-particle sizes and aggregate morphology.
3. Randomly initialize particle locations and velocities.
4. Compute mobility and Brownian transport properties.
5. March positions and velocities under Brownian motion, drag, and inertia.
6. Apply periodic boundary conditions.
7. Detect collisions and connect touching aggregates.
8. Update geometry, mobility, and saved diagnostics.

## Main Workflow

```text
main_LD1_v3
first-stage Langevin dynamics
        |
        v
data/main_ld1/ld1_aggregate_library.mat
        |
        +------------------------------+
        |                              |
        v                              v
main_scale_v2                    main_scatter_v8
correlation-based scaling        bivariate scatter sampling (default)
        |                              |
        v                              v
data/main_scale/                 data/main_scatter/
scaled_aggs_for_LD2_             scaled_aggs_for_LD2_
from_main_scale.mat              from_main_scatter.mat
        |                              |
        +--------------+---------------+
                       |
                       v
                 main_LD2_v3
        second-stage Langevin dynamics
                       |
                       v
     results/main_ld2_from_main_*/
       LD2__*__YYYY-MM-DD/
```

### Stage 1: LD1 Aggregate Library

`main_LD1_v3.m` performs first-stage Langevin dynamics. It initializes primary
particles, assigns positions and velocities, evaluates mobility, marches the
particles, applies periodic boundaries, joins collisions, and updates size and
mobility properties after every growth step.

LD1 saves its default output to:

```text
data/main_ld1/ld1_aggregate_library.mat
```

The file contains:

- `pp0`: flat cell array of aggregate primary-particle matrices, directly
  usable by `main_scale_v2.m` and `main_scatter_v8.m`.
- `pp0_n`: number of primaries in each saved aggregate.
- `pars_ld1`: structured version of the saved aggregate library.
- `ensdata0`, `parsdata0`: real-time ensemble summaries and saved aggregate
  properties.
- `fl0`: gas temperature (K), pressure (Pa), viscosity (Pa s) and mean free
  path (m) of the run.
- `cfg_ld1`, `metadata`: config and run provenance.

```text
LD1 config JSON
      |
      v
main_LD1_v3
      |
      +-- pp0                 flat aggregate cell library
      |     |
      |     +--> main_scale_v2
      |     |
      |     `--> main_scatter_v8
      |
      +-- pp0_n               primary-particle counts
      |
      +-- pars_ld1            sizing fields and aggregate structure
      |
      `-- ensdata0, parsdata0 diagnostics and saved snapshots
```

### Stage 2A: Scale Or Scatter

Both calibration scripts start from the LD1 `pp0` library.

`main_scale_v2.m` rescales and filters LD1 aggregates against the Brasil et al.
(1999) aggregate correlation and the Olfert and Rogak (2019) universal
correlation. It writes:

```text
data/main_scale/scaled_aggs_for_LD2_from_main_scale.mat
```

`main_scatter_v8.m` samples a projected-area/primary-particle size
distribution, assigns LD1 aggregate seeds to those targets, and rescales the
selected aggregates. Bivariate sampling is the default. The `sequential` and
`ideal` modes remain available for sensitivity runs through
`options.opt_scale` in the scatter config.

Every scatter run writes the canonical LD2 input:

```text
data/main_scatter/scaled_aggs_for_LD2_from_main_scatter.mat
```

It also writes a mode-specific copy, such as:

```text
data/main_scatter/scaled_aggs_for_LD2_from_main_scatter_bivariate.mat
```

Both calibration workflows save the aggregate payload as `pars_out`, the input
variable expected by LD2. Scatter outputs also contain `scatter_metadata` and
`scatter_summary`.

### Stage 2B: LD2 Post-Flame Agglomeration

`main_LD2_v3.m` loads one of the calibrated `pars_out` files, reinitializes the
aggregate population in a second domain, and performs post-flame Langevin
dynamics. The LD2 config chooses whether the source is the scale output or the
scatter output.

Set `SOOTMOSAIC_MAIN_LD2_CONFIG` before running LD2, for example:

```matlab
setenv('SOOTMOSAIC_MAIN_LD2_CONFIG', ...
    'config/main_ld2/main_ld2_from_main_scatter_config.local.json')
main_LD2_v3
```

LD2 creates a dated run directory under the configured `results.root` and
writes checkpoint and final MAT files using the configured prefixes. An
interrupted checkpoint can be resumed with:

```matlab
UTILS.RESUME_LD2_V3(checkpoint_folder, checkpoint_file)
```

Calling `UTILS.RESUME_LD2_V3` without arguments prompts for both values.

### TEM Measurement Analysis

`main_tem_analysis_v1.m` processes configured TEM datasets independently of
the LD simulation pipeline. Each config entry identifies an aggregate MAT file
(the example expects an `Aggs` variable), ImageJ primary-particle area CSV
files, and a complete publication style. `aggregate_ids` selects the aggregate
MAT records used for morphology summaries. The optional
`primary_particle_aggregate_ids` field selects the subset with manual
primary-particle CSVs; when omitted, it inherits `aggregate_ids` for backward
compatibility. Figure-specific `condition_ids`
control which enabled conditions appear and in what order. The default profiles
select only low and high agglomeration. A collapse condition can be added later
by defining one entry and adding its ID to the required figure lists; plotting
code changes are not required.

The profile is organized into four editing areas:

- `analysis` and `outputs` control calculations and file locations.
- `plots.font`, `plots.axes`, `plots.boxplot`, and `plots.export` control the
  shared publication format.
- `plots.figures.<figure_id>` controls one figure, including its enabled state,
  condition list, axis settings, layout, legend, and figure-specific options.
- `entries` defines each condition, its data sources, marker, condition colors,
  boxplot colors, and same-hue stacked-bar palettes.

For the usual paper update, edit only `entries[].style` and the relevant
`condition_ids`, axis limits, or ticks. Frequency-bin definitions are grouped
separately under `plots.frequency_bins` because they affect only the two
stacked-frequency diagnostics.

Run the default paper profile from MATLAB:

```matlab
main_tem_analysis_v1
```

Run a specific profile explicitly:

```matlab
setenv('SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG', ...
    'config/main_tem_analysis/main_tem_analysis_config.local.file.json')
main_tem_analysis_v1
```

The script name is not a PowerShell command. From PowerShell, launch MATLAB in
batch mode instead:

```powershell
matlab -batch "cd('<path to sootMosaic>'); main_tem_analysis_v1"
```

The figure configuration controls output formats and resolution, typography,
condition colors and markers, reference lines, axes, legends, category
definitions, and all frequency-bin boundaries and inclusivity rules. Each
condition also defines independent `stack_colors` arrays for the subaggregate-
count and collapsed-subaggregate frequency figures. The paper profile uses
blue shades for low agglomeration and orange shades for high agglomeration.
Segoe UI Semilight is the default face, Segoe UI is its fallback, and all font
weights are normal. The larger paper defaults are 13-point axis text,
18-point labels, and 15-point legends. The default export is vector PDF plus a
600-dpi PNG rendered from that PDF, so both formats use identical embedded
fonts and geometry. This `png_source` setting requires `pdftocairo`, supplied
by Poppler and common TeX distributions; set it to `figure` to use MATLAB's
direct raster renderer. Shared axis-label offsets and tick-label rotation are
configurable under `plots.axes`; the paper profile uses horizontal, multiline
condition labels.

Figures are constructed off-screen at their configured `position` dimensions
before export. This preserves tall publication aspect ratios even when the
interactive MATLAB window cannot fit them on the current monitor.

With the example output settings, the main machine-readable files are:

```text
data/main_tem_analysis/tem_analysis_results.mat
data/main_tem_analysis/model_inputs.csv
data/main_tem_analysis/summary_table.csv
data/main_tem_analysis/hybridity_frequency_summary.csv
data/main_tem_analysis/collapse_frequency_summary.csv
data/main_tem_analysis/subaggregate_count_distribution_summary.csv
```

`data/tem_analysis/` contains source MAT and ImageJ files and is never written
by the workflow. `data/main_tem_analysis/` contains derived outputs created by
`main_tem_analysis_v1`; the similar names identify input and output roles rather
than duplicate datasets. The saved MAT file keeps `aggregate_table` for
dpp-dependent aggregates and `morphology_table` for configured aggregate MAT
records.

The exported figure set includes the manual TEM correlation, both
primary-particle Appendix variants, aggregate metrics, a mirrored exact-count
lollipop distribution for a configured pair of conditions, separate stacked-
frequency figures for subaggregate counts and collapsed-subaggregate fractions,
and the subaggregate-category correlation. The mirrored distribution uses a
colored condition legend and independently configurable major and minor x-axis
grids. Figures are written to `results/main_tem_analysis/`.

### Experimental Validation

The validation workflow consumes processed data and does not rerun TEM or
ODIAS analysis. Keep the original ODIAS workspace at:

```text
data/experimental_effective_density/Effective_Density_Compiled-17_Mar_2025-05_00_44.mat
```

Create the small, self-describing companion used by validation once:

```matlab
source_file = fullfile('data', 'experimental_effective_density', ...
    'Effective_Density_Compiled-17_Mar_2025-05_00_44.mat');
output_file = fullfile('data', 'experimental_effective_density', ...
    'effective_density_validation_data.mat');
UTILS.NORMALIZE_EFFECTIVE_DENSITY_DATA(source_file, output_file, ...
    'ExpectedSourceSHA256', ...
    '3EEF1BC1981EE654BA5FE0198AF50EA977DAEFA5973D37AE27DD787A5844048C');
```

The normalizer loads only `dist_grp` and `test_condition`, copies all four
condition groups without rounding or recalculation, and proves exact numerical
round-trip equality before replacing the companion. The original workspace is
never modified. Its raw tandem distributions, saved figures, and fit objects
are not required by sootMosaic.

The TEM input is the existing processed artifact:

```text
data/main_tem_analysis/tem_analysis_results.mat
```

`main_valid_v3.m` uses only `aggregate_table.entry_id`, `da_nm`, `dbarpp_nm`,
and the optional `dbarpp_ci95_*` columns. Set the validation config and run:

```matlab
setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', ...
    'config/main_valid/main_valid_config.local.json')
main_valid_v3
```

Low and high agglomeration are enabled by default. Moderate and extensive
collapse remain named, disabled conditions that can be activated after their
TEM and LD2 mappings are supplied. Bayesian fitting, degree, credible level,
posterior samples, priors, plot styling, Segoe UI typography, reference
relations, and exports are controlled independently in JSON.
Legend location, column count, orientation, border visibility, text interpreter,
and text size are configurable under `figures.legend` and
`figures.font.legend_size`. All text uses Segoe UI Semilight at normal weight in the
manuscript profile, including 13-point tick labels, 18-point axis labels, and
15-point legends. The plot-frame and tick-line weight is controlled by
`figures.axis_line_width`; label offsets and tick-label rotation are controlled
under `figures.axes`.
Measurement edge color, marker-face color, outline width, and marker size are
configured per condition through the `conditions[].style.experimental_*`
fields, independently of the numerical-population color. The default marker
face is `none`, leaving the darker measurement outlines transparent.

Stable PDF and matching PDF-rendered PNG figures are written to
`results/main_valid/`. Every run also
creates `results/main_valid/runs/<timestamp>/` with the resolved config, source
hashes, pointwise predictions, summary metrics, and a MAT result bundle.

## Configuration and Running

Each configurable workflow has an example JSON file committed under `config/`.
Copy the required example to the corresponding `.local.json` name and edit the
dataset paths and, where present, output settings before running it. Files
matching `.local*.json` are ignored by Git.

```text
config/
|-- main_ld1/
|   `-- main_ld1_config.example.json
|-- main_scale/
|   `-- main_scale_config.example.json
|-- main_scatter/
|   `-- main_scatter_config.example.json
|-- main_ld2/
|   |-- main_ld2_from_main_scale_config.example.json
|   `-- main_ld2_from_main_scatter_config.example.json
|-- main_tem_analysis/
|   `-- main_tem_analysis_config.example.json
`-- main_valid/
    `-- main_valid_config.example.json
```

The tree lists tracked examples only. Local copies are ignored.
In the validation example, `sources.ld2.file` names
`../../results/main_ld2_from_main_scatter/LD2_RESULTS_PLACEHOLDER.mat`.
Set this placeholder to the selected LD2 result in the local config.
For TEM, `entries[].entry_dir` and `outputs.data_root` are independent
paths resolved relative to the config folder. Input file names within an
entry are resolved relative to its `entry_dir`; `outputs.data_root`
selects the output data folder.

Config selection follows the script loaders:

| Script | Config selection |
| --- | --- |
| `main_LD1_v3.m` | `SOOTMOSAIC_MAIN_LD1_CONFIG`, then `PFAL_MAIN_LD1_CONFIG`, then `config/main_ld1/main_ld1_config.local.json` |
| `main_scale_v2.m` | `config/main_scale/main_scale_config.local.json` |
| `main_scatter_v8.m` | `config/main_scatter/main_scatter_config.local.json` |
| `main_LD2_v3.m` | `SOOTMOSAIC_MAIN_LD2_CONFIG`, then `PFAL_MAIN_LD2_CONFIG`, with no default file |
| `main_tem_analysis_v1.m` | `SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG`, then `PFAL_MAIN_TEM_ANALYSIS_CONFIG`, then `config/main_tem_analysis/main_tem_analysis_config.local.json` |
| `main_valid_v3.m` | `SOOTMOSAIC_MAIN_VALID_CONFIG`, then `PFAL_MAIN_VALID_CONFIG`, then `config/main_valid/main_valid_config.local.json` |

Each loader uses the first nonempty environment variable in its row. A config
path passed directly to a loader overrides both.

Typical run order:

```matlab
main_LD1_v3
main_scatter_v8      % default bivariate calibration branch
setenv('SOOTMOSAIC_MAIN_LD2_CONFIG', ...
    'config/main_ld2/main_ld2_from_main_scatter_config.local.json')
main_LD2_v3
```

To use correlation-based scaling instead, run `main_scale_v2` in place of
`main_scatter_v8` and select
`config/main_ld2/main_ld2_from_main_scale_config.local.json` for LD2.

The LD1 and LD2 configs set the gas temperature and pressure under
`transport.fluid` and the property model under `transport.fluid_options.amb`.
The `sutherland` model gives the viscosity from 1.716e-5 Pa s at 273.15 K
with the temperature law of reference 7 (constant 110.4 K) and the mean
free path from 67.3 nm at 296.15 K and 101325 Pa, scaled with temperature and
pressure as in Kim et al. (2005). The `flame` (1700 K) and `room` (293.15 K)
presets hold fixed values at 101325 Pa and warn when the configured state
differs by more than 1 K or 1 percent. The top-level `model_profile` names the
default models, `current` or `article1_7658971` (the models of commit
7658971). A config without `model_profile` runs with `article1_7658971`, and
an LD2 config without `model_profile` and pressure runs at 101325 Pa. The
resolved profile is saved as `cfg_ld1.model` or `cfg_ld2.model` with every
result and checkpoint.

Profile files live in `config/profiles` and are checked against
`profile.keys.json`. Stage sections override common sections, then
`model_overrides` applies section-shaped task values, and explicit transport
options take precedence. A custom file can use
`"extends": "article1_7658971.json"` and set its own `profile` name.
An edited fixed profile stops the run; an edited `current` profile warns.
A missing shipped file or profile dictionary uses the built-in mirror with
one warning per profile per session. The dimensionless reference exponent is
`reference.mass_mobility_exponent`; `reference.d_m` is accepted as an alias.
Parameter sections and SI values are saved in `cfg.model_params`,
and file digests, mirror flags and overrides in `cfg.model_source`.
The resolved density uses the material density for `per_caller_7658971`
and the aerodynamic reference density otherwise. The mobility root tolerance
is recorded as `default` only for that slip choice with
`start_point_7658971`, and as `eps_scaled` otherwise; its dimensional value
depends on the diameters at the solve. A checkpoint without parameter records
receives the fixed built-in values and a `NoModelParameters` warning.
Mobility calls without options read `UTILS.CALL_DEFAULTS`, including method
`continuum` and `c_dt` of 1; sampling and property call defaults are listed
alongside them. `QA.TEST_MODEL_PROFILE` and
`QA.TEST_CALL_DEFAULTS` check the files, mirrors, loaders and call interface.

The slip correction is set under `transport.mobility_options.slip` and
computed by `TRANSP.CUNNINGHAM`. The `kim2005` model uses the constants of
Kim et al. (2005), 1.165, 0.483 and 0.997 with Kn = 2 lambda / d, the same in
the mobility, mobility diameter and aerodynamic diameter functions, with the
aerodynamic diameter at the reference density of 1000 kg/m3. They were fitted
with the classical mean free path that the `sutherland` model gives. The
`per_caller_7658971` model keeps the form and constants each function used at
commit 7658971 and is the default of the `article1_7658971` profile and of
calls without the option. The soot property table `UTILS.TABGEN` runs with
`per_caller_7658971` only until its mass and density units are reviewed.
Explicit `slip` and `amb` fields in a config win over the profile defaults, so
the example configs keep `kim2005` and `sutherland` when only `model_profile`
is changed. The results of 7658971 are reproduced when the resolved options
match its settings.

The mobility method is set under `transport.mobility_options.mtd`, with the
profile default when the field is left out. `sorensen_eq17` (also accepted
under its earlier name `continuum` and saved as `sorensen_eq17`) gives the
continuum mobility diameter dm = 1.29 N^-0.13 dg of Eq. 17 in Sorensen (2011)
at every number of primaries N. `sorensen_backbone` gives dm = dp for a single
primary, Eq. 18a for a doublet (dm = 2^0.46 dp for two equal touching
spheres), Eq. 17 for N from 3 to 74 and dm = 0.75 dg above, the ratio that
Eq. 18b gives for fractal dimension 1.78 and prefactor 1.3. The crossover
N = 74 is where Eqs. 18a and 18b meet, and dm steps up by 1.7 percent between
N = 74 and 75 for the same gyration diameter. The ratio 0.75 is the large-N
value for DLCA aggregates, so its use for aggregates of other morphology, like
the doublet relation for unequal primaries, is an extrapolation. `interp`
solves the adjusted sphere relation in the form given by Rogak et al. (1993)
between the projected area
diameter and the continuum diameter named by `continuum_diameter`,
`fixed_075dg` (0.75 dg at every N) or `sorensen_backbone` (the relations
above, so that a single primary has dm = dp at every Knudsen number).
`root_solve` is `start_point_7658971` (fzero from one start point) or
`bracketed` (fzero on the interval between the two limit diameters, which
holds the root). `free_molecular` sets dm to the projected area diameter,
the free molecular limit of Sorensen (2011) and Rogak et al. (1993).
The `current` profile uses `interp` with `sorensen_backbone` and `bracketed`
in both stages, `article1_7658971` uses `sorensen_eq17` in LD1 and `interp`
with `fixed_075dg` and `start_point_7658971` in LD2. The example configs name
the continuum diameter and the root solve explicitly.

`interp` and `free_molecular` take the projected area from the method named
by `projection`. `euler_7658971` calls `PAR.PROJECTION` for every aggregate at
every step with `proj_points` random points and `proj_orientations` triples of
Euler angles drawn uniformly in [0, 2 pi), as commit 7658971 did with 100 and
5. `isotropic` uses `PAR.PROJECTION_ISO`. It turns `proj_replicates` sets of
directions from a spherical Fibonacci lattice on the half sphere by
independent uniformly distributed rotations, so that every direction is
uniform on the sphere, and counts the covered points of a randomly shifted
square grid of `proj_points` points in each of the `proj_orientations`
orientations, which gives an unbiased orientation averaged area. A single
primary has the area pi dp^2 / 4. With `proj_cache` set to true,
`PAR.PROJECTION_CACHE` keeps the area of every aggregate whose primaries are
unchanged and whose relative positions lie within 1e-9 smallest primary
diameters of the positions at which the area was computed, so after a merge
only the new aggregate is sampled and small changes cannot add up unnoticed.
The standard error of each area comes from the spread of the set means, and a
warning is shown once per run when its ratio to the area exceeds
`proj_tol`. With 4 sets it has 3 degrees of freedom, so a nominal two-sided 95
percent interval would need 3.182 standard errors under normality, and it
serves as a check of the resolution, not as a confidence interval. One set
gives no standard error, so `proj_tol` must then be `"none"` (no check, read
as Inf). An area that is not positive and finite stops the run with a request
for a finer resolution. `isotropic` takes the particle structure, not AGG
objects. The projected areas saved for methods without da
still come from `PAR.PROJECTION` with the `projection` section of the config.
The `current` profile uses `isotropic` with the cache, 1024 points, 64
orientations in 4 sets and `proj_tol` 0.01, and `article1_7658971` uses
`euler_7658971` without the cache. The example configs name the projection,
the cache and the sampling settings explicitly, and the LD1 example runs
`interp`.

`TRANSP.MOBIL` stores two single-particle Knudsen numbers with every
particle, the gas Knudsen number `kn_kin` = 2 lambda / dm and `kn_diff` =
2 (m kT)^0.5 / (f dm). With `transport.diagnostics_options.knudsen` set to
true, `TRANSP.KNUDSEN` adds two numbers of the literature at every recorded
step. The pair diffusive Knudsen number of Eq. 11 in reference 10 is taken
for each particle and its nearest neighbor under the periodic minimum image,
with the reduced mass and friction of the pair, the combined Smoluchowski
radius (dm_i + dm_j) / 2 and the combined projected area
pi (da_i + da_j)^2 / 4 (dm in place of da for methods that set no projected
area). Both are sums of single-particle radii, exact for two spheres, and the
mobility radius equals the capacity radius of reference 10 only in the
continuum limit. For aggregate pairs the number is therefore an approximate
diagnostic. The comparison of reference 10 (Table 1), where sums of capacity
radii and projected areas give values 1.16 to 1.46 times those of the computed
pair geometry, does not bound it, and the regime limits 0.035 and 3.7 of
reference 10 belong to the computed definition and only indicate the regime
here. For two identical spheres it equals `kn_diff` / 2^0.5, Eq. 2 of
reference 11. The nearest-neighbor Knudsen number of reference 11 is
(18 D tau)^0.5 / rn with rn = n^(-1/3) - 2 rmax, from the number
concentration n and the mean maximum radius rmax, and is not defined when rn
is not positive. `ensdata` (`ensdata0` in LD1) gains `kn_pair` and `knn`,
each as mean and standard deviation over the particles, and `knn_defined`,
which is false with `knn` set to NaN where rn is not positive. The
diagnostics change neither the particles nor the random numbers. The
`current` profile records them and `article1_7658971` does not. Reference 12
gives the particle mean free path of another convention, 3.19 times the
length (m kT)^0.5 / f of `kn_diff`, so diffusive Knudsen numbers can only be
compared within one convention.

The initial velocities are drawn by `PAR.INIT_VEL` with the sampler named
under `transport.velocity_options.sampler`, with the profile default when the
field is left out. `maxwell_boltzmann` draws the three components of each
particle from a normal distribution with zero mean and variance kT / m, so the
mean kinetic energy is 1.5 kT and the speeds follow the Maxwell-Boltzmann
distribution with the mean speed (8 kT / (pi m))^0.5 of reference 12.
`mean_speed_7658971` keeps the sampler and the random numbers of commit
7658971, every particle at that mean speed in a direction with the polar angle
uniform in [0, pi], which gives the mean kinetic energy 4 kT / pi. The
`current` profile uses `maxwell_boltzmann` and `article1_7658971` uses
`mean_speed_7658971`. The example configs name the sampler explicitly.

The TEM analysis runs separately with `main_tem_analysis_v1` after its local
config and source datasets have been prepared. The four TEM profiles share the
complete schema; `local.json` is the default low/high paper profile, and
`local.webtest.json` uses invisible figures for automated execution.

Validation also has `local.file`, `local`, and `local.webtest` profiles. The
web-test profile uses compact fixtures created by:

```matlab
UTILS.CREATE_MAIN_VALID_WEBTEST_FIXTURES
```

Serve `data/main_valid_webtest/server/` on localhost port 8765, select
`main_valid_config.local.webtest.json`, and run `main_valid_v3` to exercise the
URL fallback without transferring the full experimental workspace.

## Repository Map

```text
sootMosaic/
|-- main_LD1_v3.m          first-stage aggregate-library generation
|-- main_scale_v2.m        correlation-based LD1 library scaling
|-- main_scatter_v8.m      LD1 library sampling/scaling; bivariate by default
|-- main_LD2_v3.m          second-stage post-flame agglomeration
|-- main_tem_analysis_v1.m TEM measurement analysis and figure generation
|-- main_valid_v3.m        LD2/TEM/effective-density validation figures
|-- main_*                 validation, shielding, collapse, and utility scripts
|-- post_*                 post-processing scripts for generated results
|-- config/                JSON templates and ignored local configs
|-- data/                  local inputs and generated workflow handoff files
|-- results/               LD2 workspaces and exported TEM figures
|-- inputs/                legacy tab-delimited parameter files
|-- +PAR/                  particle initialization, sizing, projection, geometry
|-- +TRANSP/               transport properties, mobility, marching, boundaries
|-- +COL/                  collision detection, connection, aggregate growth
|-- +UTILS/                config, checkpoint-resume, plotting, fitting, and IO helpers
|-- +VIS/                  visualization routines
|-- @AGG/                  aggregate class utilities
`-- +DEPOT/                archived or experimental scripts, including legacy PFA
```

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
