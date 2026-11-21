# Transport models and saved records

LD1 and LD2 resolve gas properties, mobility, projection, and velocity sampling from task settings and a model profile.
Select a profile with the [configuration instructions](getting_started.md#model-profiles).
Reference numbers in this page refer to the [README references](../README.md#references).

[Back to README](../README.md)

## Saved products and source records

Saved products and checkpoints retain filenames and SHA-256 digests.
Saved path fields contain file or folder names.

| Product | Record |
| --- | --- |
| Scale, scatter, and LD2 | `dataset_src` for resolved source metadata and `dataset_provenance` for registry and overlay records |
| Validation MAT | `manifest.sources.<source>.provenance` in `validation_results.mat` |
| Validation JSON | `sources.<source>.provenance` in `run_manifest.json` |
| LD1 and LD2 results and checkpoints | Resolved profile in `cfg_ld1.model` or `cfg_ld2.model` |
| Resolved configuration | Parameter sections and SI values in `cfg.model_params` |
| Model source record | File digests, mirror flags, and overrides in `cfg.model_source` |

`UTILS.PUBLIC_COPY` copies saved values with path fields reduced to file and
folder names. `UTILS.SAVE_PUBLIC_MAT` saves caller variables through that copy.

LD2 final results contain one `r_n_agg` entry per retained snapshot.
The requested schedule stays in `cfg_ld2.simulation.r_n_agg`.
Validation selects only fractions present in the final result.

## Gas properties

Gas temperature and pressure are set under `transport.fluid`.
`transport.fluid_options.amb` selects the property model.

| Calculation | Values |
| --- | --- |
| `current` viscosity | Reference viscosity 1.83245e-5 Pa s at 296.15 K |
| `article1_7658971` and calls without a gas section, when using `sutherland` | Reference viscosity 1.716e-5 Pa s at 273.15 K |
| Viscosity temperature law | Reference 7, Eq. 9, with constant 110.4 K |
| Mean free path | 67.3 nm at 296.15 K and 101325 Pa, scaled with temperature and pressure by reference 7, Eq. 11 |
| `flame` preset | Fixed properties at 1700 K and 101325 Pa |
| `room` preset | Fixed properties at 293.15 K and 101325 Pa |

The presets warn when the configured state differs by more than 1 K or 1 percent in pressure.

## Physical constants and reference parameters

The dimensionless reference exponent is `reference.mass_mobility_exponent`.
`reference.d_m` is accepted as an alias.

| `current` constant | Value | Basis |
| --- | --- | --- |
| `kb_j_k` | 1.380649e-23 | Exact 2019 SI |
| `na_mol_inv` | 6.02214076e23 | Exact 2019 SI |
| `ru_j_mol_k` | 8.31446261815324 | Exact decimal product of the preceding constants |
| `e_c` | 1.602176634e-19 | Exact 2019 SI, used by INV |
| `eps0_f_m` | 8.8541878128e-12 | CODATA 2018, used by INV |

The `article1_7658971` profile and profile-free calls use rounded constants.
The physical constants table has four columns and five rows, in the order
`rho_bc`, `M_air`, `kb`, `Na`, `Ru`, with those names as row names.
Named access accepts reordered tables. Unnamed saved tables use the fixed row order.

Validation `physics.material_density_kg_m3` overrides the profile density.
The value is recorded in `cfg.model_params` and `cfg.model_source`.
The resolved density uses the material density for `per_caller_7658971`
and the aerodynamic reference density otherwise.

## Slip correction

`transport.mobility_options.slip` selects the correction computed by `TRANSP.CUNNINGHAM`.

| Model | Calculation |
| --- | --- |
| `kim2005` | Constants 1.165, 0.483, and 0.997 from reference 7, with Kn = 2 lambda / d |
| `per_caller_7658971` | Per-function constants used by `article1_7658971` and calls without the option |

The `kim2005` constants are shared by mobility, mobility diameter, and
aerodynamic diameter calculations. Aerodynamic diameter uses a reference density
of 1000 kg/m3. The constants were fitted with the classical mean free path
computed by `sutherland`. The soot property table `UTILS.TABGEN` accepts only `per_caller_7658971`.

## Mobility diameter

`transport.mobility_options.mtd` selects the method. An omitted field uses the
profile default. Here dm is mobility diameter, dg is gyration diameter,
dp is primary diameter, and N is the number of primaries.

| Method | Relation |
| --- | --- |
| `sorensen_eq17`, alias `continuum` | dm = 1.29 N^-0.13 dg at every N, reference 8, Eq. 17 |
| `sorensen_backbone`, N = 1 | dm = dp |
| `sorensen_backbone`, N = 2 | Reference 8, Eq. 18a, giving dm = 2^0.46 dp for two equal touching spheres |
| `sorensen_backbone`, N from 3 to 74 | Reference 8, Eq. 17 |
| `sorensen_backbone`, N above 74 | dm = 0.75 dg |
| `interp` | Adjusted sphere relation of reference 9 between the projected-area and selected continuum diameters |
| `free_molecular` | dm equals projected-area diameter, the free molecular limit of references 8 and 9 |

The backbone crossover is N = 74. Above it, 0.75 is the diffusion-limited cluster
aggregation (DLCA) ratio from reference 8, Eq. 18b, for fractal dimension 1.78
and prefactor 1.3.

### Continuum diameter and root solution

For `interp`, `continuum_diameter` selects `fixed_075dg` or `sorensen_backbone`.
The first uses 0.75 dg at every N. The second uses the relations above and gives
dm = dp for a single primary at every Knudsen number.

| `root_solve` | Calculation |
| --- | --- |
| `start_point_7658971` | `fzero` from one start point |
| `bracketed` | `fzero` on the interval between the two limit diameters, which contains the root |

The mobility root tolerance is recorded as `default` for the combination of
`per_caller_7658971` and `start_point_7658971`, and as `eps_scaled` otherwise.
Its dimensional value depends on the diameters at the solve.

| Profile | LD1 | LD2 |
| --- | --- | --- |
| `current` | `interp`, `sorensen_backbone`, `bracketed` | `interp`, `sorensen_backbone`, `bracketed` |
| `article1_7658971` | `sorensen_eq17` | `interp`, `fixed_075dg`, `start_point_7658971` |

### Calls without options

Mobility calls without options read `UTILS.CALL_DEFAULTS`, including method
`continuum` and `c_dt` of 1. Sampling and property call defaults are listed in
the same file. `QA.TEST_MODEL_PROFILE` and `QA.TEST_CALL_DEFAULTS` check the
files, mirrors, loaders, and call interface.

## Projected area

`interp` and `free_molecular` take projected area from the method selected by
`projection` under `transport.mobility_options`.

### Random-angle projection

`euler_7658971` calls `PAR.PROJECTION` for every aggregate at every step.
It uses `proj_points` random points and `proj_orientations` triples of Euler angles
drawn uniformly in [0, 2 pi).

### Isotropic projection

`isotropic` uses `PAR.PROJECTION_ISO` with `proj_replicates` sets of directions
from a spherical Fibonacci lattice on the half sphere. Independent uniform
rotations make each direction uniform on the sphere.

Covered points are counted on a randomly shifted square grid with
`ceil(sqrt(proj_points))^2` points in each of the `proj_orientations` orientations.
A single primary has area pi dp^2 / 4. The method takes particle structures.

With `proj_cache` set to true, `PAR.PROJECTION_CACHE` reuses areas for unchanged
geometry and samples new aggregates after a merge. `proj_tol` controls the
sampling-resolution check. With one replicate, set `proj_tol` to `"none"`.

| Profile | Projection | Points | Orientations | Replicates | Cache | `proj_tol` |
| --- | --- | --- | --- | --- | --- | --- |
| `current` | `isotropic` | 1024 | 64 | 4 | Enabled | 0.01 |
| `article1_7658971` | `euler_7658971` | 100 | 5 | 1 | Disabled | No check |

Saved projected areas for mobility methods without da use `PAR.PROJECTION`
and the configuration's separate `projection` section.

## Knudsen diagnostics

`TRANSP.MOBIL` stores two single-particle Knudsen numbers with every particle.

| Field | Definition |
| --- | --- |
| `kn_kin` | Gas Knudsen number, 2 lambda / dm |
| `kn_diff` | 2 (m kT)^0.5 / (f dm) |

Here m is mass, k is the Boltzmann constant, T is temperature, f is friction,
and lambda is gas mean free path.

Setting `transport.diagnostics_options.knudsen` to true adds the following
diagnostics through `TRANSP.KNUDSEN` at every recorded step.

### Pair diffusive Knudsen number

The pair number uses each particle and its nearest neighbor under the periodic
minimum image, with the relation of reference 10, Eq. 11.
It uses reduced mass and friction, combined Smoluchowski radius
(dm_i + dm_j) / 2, and combined projected area pi (da_i + da_j)^2 / 4.
Methods without projected area use dm in place of da.
For two identical spheres the result equals `kn_diff` / 2^0.5, reference 11, Eq. 2.

### Nearest-neighbor Knudsen number

The nearest-neighbor number of reference 11 is (18 D tau)^0.5 / rn,
with rn = n^(-1/3) - 2 rmax. Here n is number concentration, rmax is the mean
maximum radius, D is diffusivity, and tau is relaxation time.

`ensdata`, or `ensdata0` in LD1, gains `kn_pair` and `knn` as means and standard
deviations over particles. `knn_defined` is false and `knn` is NaN where rn is
not positive. The diagnostics leave particles and random numbers unchanged.
The `current` profile records them. `article1_7658971` leaves them disabled.

Reference 12 uses a particle mean free path 3.19 times the length
(m kT)^0.5 / f used in `kn_diff`.

## Initial velocities

`PAR.INIT_VEL` uses `transport.velocity_options.sampler`.
An omitted field uses the profile default.

| Sampler | Velocity distribution | Mean kinetic energy |
| --- | --- | --- |
| `maxwell_boltzmann` | Each of three components is normal with zero mean and variance kT / m | 1.5 kT |
| `mean_speed_7658971` | Every particle has speed (8 kT / (pi m))^0.5, with polar angle uniform in [0, pi] | 4 kT / pi |

The normal-component sampler gives the thermal speed distribution of reference 12
with mean speed (8 kT / (pi m))^0.5. The `current` profile uses
`maxwell_boltzmann`. `article1_7658971` uses `mean_speed_7658971`.
