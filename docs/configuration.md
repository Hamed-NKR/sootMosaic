# Configuration

Task JSON files select inputs, physical settings, analysis, and figure exports.
Create local files with the [setup commands](getting_started.md#local-configuration).

[Back to README](../README.md)

## Configuration files

| Folder | Example or role |
| --- | --- |
| `config/main_ld1/` | `main_ld1_config.example.json` for aggregate-library generation |
| `config/main_scale/` | `main_scale_config.example.json` for correlation-based calibration |
| `config/main_scatter/` | `main_scatter_config.example.json` for distribution-based calibration |
| `config/main_ld2/` | `main_ld2_from_main_scale_config.example.json` and `main_ld2_from_main_scatter_config.example.json` |
| `config/main_tem_analysis/` | `main_tem_analysis_config.example.json` for measurements, analysis, and figures |
| `config/main_valid/` | `main_valid_config.example.json` for inputs, condition mappings, and exports |
| `config/main_inv/` | `main_inv_config.example.json` for inversion settings |
| `config/profiles/` | Model profiles and dictionary |
| `config/sources/` | Dataset registry and dictionary |
| `config/instruments/` | Instrument constants, charge models, and dictionary |

Task examples and `UTILS.LOAD_MAIN_*_CONFIG` define the task settings.

| Dictionary | Scope |
| --- | --- |
| [`config/profiles/profile.keys.json`](../config/profiles/profile.keys.json) | Model choices, constants, stage sections, units, and aliases |
| [`config/sources/sources.keys.json`](../config/sources/sources.keys.json) | Registered dataset fields and local `where` selection |
| [`config/main_inv/main_inv.keys.json`](../config/main_inv/main_inv.keys.json) | INV defaults, units, and input reading rules |
| [`config/main_scale/main_scale.keys.json`](../config/main_scale/main_scale.keys.json) | Scale inputs, units, and reading rules |
| [`config/main_scatter/main_scatter.keys.json`](../config/main_scatter/main_scatter.keys.json) | Scatter inputs, units, and reading rules |
| [`config/main_ld1/main_ld1.keys.json`](../config/main_ld1/main_ld1.keys.json) | LD1 inputs, units, and reading rules |
| [`config/main_ld2/main_ld2.keys.json`](../config/main_ld2/main_ld2.keys.json) | LD2 inputs, units, and reading rules |
| [`config/main_valid/main_valid.keys.json`](../config/main_valid/main_valid.keys.json) | Validation inputs, units, and reading rules |
| [`config/main_tem_analysis/main_tem_analysis.keys.json`](../config/main_tem_analysis/main_tem_analysis.keys.json) | TEM analysis inputs, units, and reading rules |
| [`config/instruments/instruments.keys.json`](../config/instruments/instruments.keys.json) | Instrument and charging registry fields |

`config/profiles/DEFAULTS.md` gives the reasoning and sources for profile defaults.
`config/main_inv/DEFAULTS.md` does the same for inversion defaults.
Published charge-model coefficients are in `config/instruments/charging.json`.

The [setup guide](getting_started.md#configuration-selection) lists environment
selectors, precedence, and local filenames. Its [inheritance rules](getting_started.md#configuration-inheritance)
cover `extends`, ID merges, registry overlays, and strict reading.

## LD1 and LD2 settings

| Setting | Purpose |
| --- | --- |
| LD1 `results.root`, `results.library_file` | Library destination |
| LD2 `dataset.file`, `dataset.variable` | Matching calibration product and `pars_out` |
| LD2 `simulation.r_n_agg` | Requested saved aggregate fractions |
| `transport.fluid` | Gas temperature and pressure |
| `transport.fluid_options` | Gas-property model |
| `transport.mobility_options` | Mobility, slip, projection, and time stepping |
| `transport.velocity_options` | Initial velocity sampler |
| `transport.diagnostics_options` | Knudsen diagnostics |
| `simulation.rng_seed` | Random seed |

Select the LD2 branch explicitly. The [model-profile instructions](getting_started.md#model-profiles)
explain how task options interact with `current` and `article1_7658971`.
The [transport guide](transport_models.md) gives the equations and saved fields.

## Scale and scatter settings

| Setting | Purpose |
| --- | --- |
| `dataset.file` | LD1 library |
| `dataset.variable` | `pp0` |
| `distribution`, `correlation` | Target sizes and size relations |
| `sampling`, `projection` | Library sampling and projected-area calculation |
| Scatter `options.opt_scale` | `bivariate`, `sequential`, or `ideal` |
| Scatter `options.rng_seed` | Random seed |

Calibration diameters in the configurations use nanometers. Particle products
use meters. Output filenames are fixed by the scripts, as listed in
[first runs](getting_started.md#ld1-and-calibration).

## TEM inputs and figures

TEM style uses `plots` and `entries[].style`. Entry folders, aggregate files,
CSV patterns, and aggregate IDs select the measured inputs.
The [TEM data instructions](getting_started.md#tem-analysis) give the fields and units.

| Setting | Control |
| --- | --- |
| `plots.figures.<figure_id>` | Enabled state, ordered `condition_ids`, axes, layout, legend, and figure options |
| `entries[].style` | Markers, condition colors, and box colors |
| `entries[].style.stack_colors` | Independent colors for subaggregate count and collapsed-subaggregate frequencies |
| `plots.frequency_bins` | Frequency boundaries and their inclusivity |
| `plots.axes` | Shared axes, labels, label offsets, and tick rotation |
| `plots.font` | Fonts |
| `plots.boxplot` | Boxes |
| `plots.export`, `plots.pdf`, `plots.png`, `plots.png_resolution` | Scalar export controls |
| `plots.format`, `plots.resolution` | Defaults for format and resolution when specific export fields are absent |

Add an entry and its ID to the required figure lists to include another condition.
The example uses blue shades for low agglomeration and orange for high agglomeration.
Its condition labels are horizontal and multiline.

### TEM figure set

| Figure | Content |
| --- | --- |
| Manual correlation | Primary-particle diameter against projected-area diameter |
| Primary distributions | Two Appendix variants |
| Aggregate metrics | Morphology distributions |
| Mirrored exact-count distribution | Lollipop plot for two conditions with a condition legend and independent major/minor grids |
| Stacked frequencies | Separate subaggregate-count and collapsed-subaggregate figures |
| Subaggregate-category correlation | Size relation by subaggregate category |

Figures are built off-screen at configured dimensions before export to preserve
their aspect ratios. Figures go to `results/main_tem_analysis/`.

## Validation settings and figures

Validation reads the configured LD2, TEM, and effective-density sources.
Each enabled condition maps LD2 fractions, a TEM entry ID, and a density condition ID.
The example uses fraction 1 for low agglomeration and 0.1 plus 0.05 for high agglomeration.

| Setting | Control |
| --- | --- |
| `fits` | Bayesian degree, credible level, posterior draws, and priors |
| `references` | Reference relations |
| `outputs` | Exports |
| `figures.legend` | Location, columns, orientation, border, and interpreter |
| `figures.font.legend_size` | Legend text size |
| `figures.axis_line_width` | Frame and tick-line weight |
| `figures.axes` | Label offsets and tick rotation |
| `conditions[].style.experimental_*` | Measurement edge and face colors, sizes, and outline widths independently of simulation color |

Example marker faces are `none`. Empty axis limits select automatic limits.
TEM `entries[].style` and validation `conditions[].style` set condition styles independently.

## Figure export settings

| Setting | Example value |
| --- | --- |
| Font weight | Normal |
| Axis text | 13 points |
| Axis labels | 18 points |
| Legends | 15 points |
| PDF | Vector |
| PNG | 600 dpi, rendered from the PDF |

PDF-rendered PNGs share the PDF fonts and geometry. Both tasks expose axis-label
offsets and tick rotation. TEM uses `plots.png_source` and validation uses
`outputs.png_source`. The `"pdf"` choice requires `pdftocairo`. The `"figure"`
choice uses direct raster rendering.

## Inversion settings

`opts.RequiredPaths` lists required input keys for the calling stage.
Resolved International System of Units (SI) values are in `cfg_inv.si` when the
loader result is assigned to `cfg_inv`.
The [inversion configuration guide](inversion.md#configuration) describes reading rules,
instrument registries, scan values, and source records.
