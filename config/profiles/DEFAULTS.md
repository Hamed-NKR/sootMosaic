# Model profile defaults

Project defaults in `profile.keys.json` are explained below. Section numbers
match the citations. Published citations and the project defaults below
identify the reference values used by the profiles. The stage sections LD1,
LD2 and INV repeat the common rows and cite the same sources.

## 1. Material constants

`constants.rho_bc_kg_m3` (1860 kg/m3) is the material density of soot. It
converts primary particle volume to mass, and the same value in every profile
keeps mass differences between runs a matter of structure alone.
`constants.m_air_kg_mol` (28.97 g/mol) is the molar mass of dry air, the
carrier gas of every stage.

## 2. Gas property presets

The `flame` and `room` presets hold fixed gas properties for the
`article1_7658971` profile, which reproduces the computations of Nikookar et
al. (2025). That work sets in-flame air at 1700 K (Sect. 2.2) and post-flame
agglomeration at room air conditions (Sect. 2.5). The flame preset holds
5.647e-5 Pa s and 498 nm. These lie within 0.1 percent of the Sutherland
viscosity from 1.716e-5 Pa s at 273.15 K and of the mean free path scaling of
Wiedensohler et al. (2012, Appendix A5) at 1700 K and 101325 Pa. The room
preset holds 1.813e-5 Pa s, the same Sutherland viscosity at 293.15 K, and
68 nm, about 2 percent above the 66.4 nm that the scaling gives there. The
`sutherland` model of the `current` profile computes both properties at the
configured temperature and pressure instead.

The current profile uses the viscosity reference values of Kim et al. (2005,
Eq. 9). The `article1_7658971` profile uses project values of 1.716e-5 Pa s
at 273.15 K with the same 110.4 K Sutherland constant. This paired reference
defines its viscosity curve and preserves the computations represented by
that profile.

A preset warns when the configured state differs from it by more than 1 K or
by more than 1 percent of 101325 Pa. Near room temperature 1 K changes the
viscosity by about 0.3 percent and the mean free path by about 0.4 percent,
and 1 percent in pressure changes the mean free path by 1 percent.

## 3. Slip correction coefficient sets

The `kim2005` constants and the `diamobil` and `aerodyn` sets of
`per_caller_7658971` are those of Kim et al. (2005, Eq. 34). The `mobil` set
(1.254, 0.4, 1.1) and the `tabgen` set (1.257, 0.4, 0.55) complete the
per-function constants of `per_caller_7658971`. They are kept so that the
`article1_7658971` profile reproduces the computations of Nikookar et al.
(2025). `TRANSP.CUNNINGHAM` documents the form that each function applies.
The `kim2005` model applies one set of constants in every function.

## 4. Doublet gyration radius

`mobility.doublet_divisor` (1.6) is the squared gyration radius of two
touching equal spheres in units of the squared sphere radius a. Each center
lies a from the common center, and each sphere adds its own 0.6 a^2, so
Rg^2 = 1.6 a^2. With Eq. 18a of Sorensen (2011) the doublet ratio of mobility
to gyration radius is 2^0.46 / sqrt(1.6), about 1.09.

## 5. Projected area sampling

The `current` profile samples the projected area of each aggregate on 1024
points per orientation over 64 orientations, split into 4 independently
rotated sets. The spread of the set means gives a standard error with
3 degrees of freedom, a diagnostic of resolution and not a confidence
interval. A relative standard error above `projection.tol` (1 percent) warns
once per run. `projection.cache_tol` (1e-9) reuses the area of an aggregate
whose primaries moved by less than 1e-9 of its smallest primary diameter, a
change far below the sampling error. The `article1_7658971` profile keeps
100 points and 5 orientations in one set with no tolerance, the sampling of
the reproduced computations.

## 6. Time step

`step.step_frac` (0.5) limits the root mean square relative displacement of
the two particles that move most in one step to half the smallest primary
diameter. Collision detection captures a pair whose nearest primaries come
within one primary diameter, so a shorter step makes it unlikely that a pair
crosses the capture distance unseen. `step.step_policy` either warns when a
step exceeds the limit or scales the steps down to it.

## 7. Numerical tolerances and switches

`numerics.mobil_step_root_tol` (1e-12) is the tolerance, relative to the
smallest time step, of the root solve that finds the limited step.
`numerics.mobil_series_switch` (1e-2) is the ratio of step to relaxation time
below which x - 1 + exp(-x) is evaluated by its series, since the direct form
loses digits by cancellation near zero. `numerics.march_series_switch` (2)
and `numerics.march_series_terms` (10) play the same role in the position and
velocity update, where ten terms keep the error near machine precision on
both sides of x = 2. `numerics.connect_margin` (1e-13) is the round-off
margin of the overlap test as a fraction of the pair diameter sum, a few
hundred times the double precision round-off. `numerics.projection_default_n`
(1e4) is the default number of Monte Carlo points per orientation of the
Euler projection, and `numerics.projection_min_n` (1e2) is the count below
which a resolution warning is shown.
