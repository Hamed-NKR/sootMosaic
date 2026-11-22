# Getting started

Set up the staged simulations and measurement analysis from the repository root.

[Back to README](../README.md)

## Requirements

| Dependency | Use |
| --- | --- |
| `MATLAB R2022a` or later with Java enabled | Main workflows |
| `Statistics and Machine Learning Toolbox` | LD `lognrnd`, `geomean`, `knnsearch`, calibration `fitlm` and distribution functions, TEM `boxplot`, validation `gamrnd` and `tinv` |
| R2020b functions `pagemtimes` and `exportgraphics` | Array products and figure exports |
| `Signal Processing Toolbox` on R2020b or R2021 releases | QA use of `rms` |
| R2023a for `post_collapse` | `combinations` |
| `Image Processing Toolbox` | Optional particle-outline plots through `viscircles` |
| `Econometrics Toolbox` | `UTILS.BAYESFIT_POLY2`, `UTILS.BAYESFIT_POLY3`, `UTILS.BAYESFIT_POLY4` |
| `Poppler` with `pdftocairo` available to `system` | Example PDF-to-PNG exports |

Direct raster exports use TEM `plots.png_source` or validation
`outputs.png_source` set to `"figure"`. Choose installed fonts in each local configuration.

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

## Getting the code

Replace `REPOSITORY_URL` with this repository's clone address.
The terminal command requires `Git` and creates the `sootMosaic` folder.

```text
git clone REPOSITORY_URL sootMosaic
```

Start the command session in its parent folder. Both `which` calls should find this checkout.

```matlab
cd('sootMosaic')
addpath(pwd)
which main_LD1_v3
which UTILS.LOAD_MAIN_LD1_CONFIG
```

Keep the root as the current folder and repeat `addpath(pwd)` in new sessions.
Main scripts clear workspace variables and figures, so save them before running.

## Local configuration

Copy the examples once to ignored local JSON files, then edit the copies.
The [configuration reference](configuration.md#configuration-files) lists the
examples and dictionaries. All seven tasks support `extends` for overrides.

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
| Post-processing scripts | The `post` entries a script needs, listed below | Entries of scripts that are not run |

### Paths, units, and seeds

Task input paths and configurable output roots are relative to the configuration
folder. LD1 `results.library_file` is relative to `results.root`. TEM aggregate
files and primary-particle folders are relative to `entries[].entry_dir`.
Calibration output locations are fixed by the scripts.

| Quantity | Unit or setting |
| --- | --- |
| LD lengths and calibration particle products | Meters |
| Configured calibration diameters | Nanometers |
| Temperature and pressure | Kelvin and pascals |
| Geometric standard deviations | Dimensionless |
| LD random seed | `simulation.rng_seed` |
| Scatter random seed | `options.rng_seed` |
| TEM random seed | `analysis.random_seed` |

Keep JSON numbers numeric and retain required sections.

### Post-processing inputs

Set the `post` entries used by the scripts being run.

| Selected task file | Input keys |
| --- | --- |
| LD2 | `post.ld2.results_file` |
| LD2 | `post.shield.results_file`, `post.shield.input_file` |
| LD2 | `post.collapse.results_file`, `post.collapse.fluid_file` |
| LD2 | `post.valid.aggregate_file`, `post.valid.aggregate_dalpha_file`, `post.valid.aggregate_kalpha_file`, `post.valid.experiment_file` |
| Scatter | `post.charsize.aggregate_file`, `post.collapse.aggregate_file` |
| LD1 | `post.colaps.aggregate_file` for `test_colaps` |

The `post_*` and `main_collapse_*` scripts, `main_shield_v2`, and `test_valid*`
read the applicable LD2 or scatter entries through `UTILS.POST_PATH`.

### Configuration selection

An explicit loader filename takes precedence over environment selectors.
For each pair, `SOOTMOSAIC_` takes precedence over `PFAL_`.
The `PFAL_` names also select configurations for reproduction runs.

| Task | Environment selectors | Local file under `config/` |
| --- | --- | --- |
| LD1 | `SOOTMOSAIC_MAIN_LD1_CONFIG`, `PFAL_MAIN_LD1_CONFIG` | `main_ld1/main_ld1_config.local.json` |
| LD2 | `SOOTMOSAIC_MAIN_LD2_CONFIG`, `PFAL_MAIN_LD2_CONFIG` | Select `main_ld2/main_ld2_from_main_scatter_config.local.json` or the `main_scale` branch |
| Scale | `SOOTMOSAIC_MAIN_SCALE_CONFIG`, `PFAL_MAIN_SCALE_CONFIG` | `main_scale/main_scale_config.local.json` |
| Scatter | `SOOTMOSAIC_MAIN_SCATTER_CONFIG`, `PFAL_MAIN_SCATTER_CONFIG` | `main_scatter/main_scatter_config.local.json` |
| TEM | `SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG`, `PFAL_MAIN_TEM_ANALYSIS_CONFIG` | `main_tem_analysis/main_tem_analysis_config.local.json` |
| Validation | `SOOTMOSAIC_MAIN_VALID_CONFIG`, `PFAL_MAIN_VALID_CONFIG` | `main_valid/main_valid_config.local.json` |

LD2 requires a branch selection, as shown under [LD2 and checkpoints](#ld2-and-checkpoints).
Clear a selector with `setenv(name, '')`, including its paired fallback.
Selections last for the command process.

### Configuration inheritance

Full example copies provide editable local settings. Task files, profiles, and
registries accept `extends`, with parent files relative to the overlay.

| Value | Merge rule |
| --- | --- |
| Objects | Merge recursively |
| Arrays | Replace the parent array |
| Object arrays with unique IDs | Merge entries by ID |

`config/sources/sources.local.json` overlays the sources registry.
The shared reader warns on unknown dictionary keys. `struct('Strict', true)`
turns those warnings into errors when passed to `UTILS.CONFIG_READ` or as
the fourth argument of `UTILS.MODEL_PROFILE`. Task readers check required fields.

### Model profiles

Set `model_profile` to `current` for the current models or
`article1_7658971` for the LD model choices of reference 6 in the
[README references](../README.md#references).

To use the selected profile's model choices:

1. Set `transport.fluid_options`, `transport.velocity_options`, and
   `transport.diagnostics_options` to `{}`.
2. Remove `mtd`, `slip`, `continuum_diameter`, `root_solve`, `projection`,
   `proj_cache`, `proj_points`, `proj_orientations`, `proj_replicates`, and
   `proj_tol` from `transport.mobility_options`.
3. Keep `c_dt` and the step settings.
4. Inspect `cfg.model` and `cfg.model_params` from the task loader to see the
   resolved choices.

Custom profiles go in `config/profiles/<name>.json` with `extends` naming the
parent profile. `config/profiles/DEFAULTS.md` explains the project defaults of
the profile dictionary.

The [transport guide](transport_models.md) describes both profiles and their saved records.

### Inversion setup

The [inversion guide](inversion.md#configuration) covers the INV example copy,
instrument IDs, recorded scan values, and input routes. Its [processing sequence](inversion.md#processing-sequence)
continues through kernels, variance weighting, peak fitting, calibration, and group means.

## Data

Generate simulation inputs in pipeline order and place measured inputs under `data/`.

### Registered sources

- `config/sources/sources.json` lists the registered products. Their `file` and `cache_file` paths are relative to `data/`.
- Each task picks its inputs through its `dataset` or `sources` block.
- Scale, scatter and LD2 configs may give only `source_id` in `dataset`, and validation only `source_id` in each `sources` entry. Missing fields come from the registry.
- A direct loader call takes `struct('source_id', '<registered_id>')`. Inline fields override the registry.

### Downloads and checksums

- Fill `url` with a direct MAT address, `doi` with the publication identifier and `sha256` with the published SHA-256 digest. A missing digest comes from the publication or the data supplier.
- Loaders check every nonempty digest, for local, cached and downloaded files alike.
- An empty digest skips the check. A URL with an empty digest stops with `MissingChecksum`.
- Use `UTILS.FILE_SHA256(file)` to obtain a generated file's digest.

Generated data, `results/`, `outputs/`, `.sootmosaic-cache/`, and `.pfal-cache/`
are ignored by `.gitignore`.

## First runs

### LD1 and calibration

Run LD1, then either calibration branch, then LD2 from the repository root.

| Command | Expected product |
| --- | --- |
| `main_LD1_v3` | Prints `Saved LD1 aggregate library` and writes `data/main_ld1/ld1_aggregate_library.mat` with `pp0`, snapshots, gas state, and configuration |
| `main_scatter_v8` | Writes `data/main_scatter/scaled_aggs_for_LD2_from_main_scatter.mat` and a mode-specific copy with `pars_out`, metadata, and summary. Figures go to `results/main_scatter/` |
| `main_scale_v2` | Writes `data/main_scale/scaled_aggs_for_LD2_from_main_scale.mat` with `pars_out`. Figures go to `results/main_scale/` |

Scatter uses `bivariate` by default, with `sequential` and `ideal` selected by
`options.opt_scale`. Calibration outputs use fixed filenames. Select the
matching LD2 input, replacing `main_scatter` with `main_scale` for scale.

### LD2 and checkpoints

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
into the folder of that checkpoint. Those two strings can also be passed as arguments.

### TEM analysis

Place aggregate MAT files and primary-area CSV files in the configured entry
folders, normally `data/tem_analysis/`.

| Input | Content |
| --- | --- |
| Aggregate MAT | `Aggs` structure array with `da` in nanometers |
| Morphology fields | `n_subagg`, `n_colaps`, `ca`, `zbar_opt`, `sbar_opt` |
| Primary-particle CSV | `Area` column in square nanometers |

Set `analysis.primary_area_start_row` to 2 when the first data row describes
the aggregate or background, or 1 when it describes a primary particle.
Aggregate IDs index `Aggs`. The `%d` in `primary_particles.file_pattern`
receives that index. Primary-particle IDs must be a subset of aggregate IDs.

Run `main_tem_analysis_v1` to write `data/main_tem_analysis/tem_analysis_results.mat`,
summary CSVs, and figures in `results/main_tem_analysis/`.
The MAT file contains `aggregate_table` and `morphology_table`.

### Effective-density data and validation

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

### Inversion scans

Import files with the matching reader, then select campaign scans with
`INV.SELECT_SCANS(imports, cases, cfg)`. Resolve each selected scan and campaign
record before calling `INV.OBSERVATION`.
The [scan input guide](inversion.md#scan-inputs) gives the AAC pressure conversion,
route B corrections, repeat pooling, and charge-model selection.

## Checking the install

Run all 38 QA functions. A pass prints one `PASS TEST_...`
line per file, with all returned `pass` flags true. These checks use synthetic
inputs or source inspection. Expected-warning cases can print warnings.

```matlab
warning('on', 'all')
checks = dir(fullfile('+QA', 'TEST_*.m'));
assert(numel(checks) == 38)
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

## When something fails

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
| `InvalidConfig`, `InvalidJSON`, `MissingKey`, `MissingField`, `MissingScalar`, or `MissingText` | Check JSON syntax and the required sections and values against the example |
| `UnknownKey` | Use the key spelling in the dictionary |
| `MissingFileOnDisk`, `MissingFile`, or `MissingAggregateFile` | Generate the upstream product or supply the measurement file at the configured path |
| `MissingVariableInFile`, `MissingVariable`, or `MissingTableVariables` | Supply the expected MAT variables and table columns |
| `MissingChecksum` or `ChecksumMismatch` | Supply the published digest and a matching source or cached file |
| `MissingTEMMapping` or `MissingDensityMapping` | Match enabled condition IDs to the input tables |
| `InvalidProjection` | Use cache with `isotropic`, orientations divisible by replicates, and `proj_tol` of `"none"` for one replicate |
| `RendererFailed` | Install `pdftocairo` or select `"figure"` for `png_source` |
