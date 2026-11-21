# Inversion defaults

Project defaults in `main_inv.keys.json` are explained below. Section numbers
match the citations.

## 1. Configuration, inputs and outputs

`config_version` (1) is the schema version that the loader reads. Campaign
tables, campaign identifiers and the paths to the SMPS exports, AAC files,
database and output root depend on the local machine and campaign. They are
empty in the example and are set in a local overlay. Time stamps are compared
in UTC, the time base of the instrument database, and `campaigns.time_zone`
holds the local zone of the campaign records. The database reader defaults to
SQLite, which reads the database file directly, with CSV exports of the same
tables as the fallback. `outputs.source_id` is the sources registry entry read
by the validation stage. Every output carries a SHA-256 sidecar, so a changed
file is detected when it is read again. `rng_seed` fixes the random draws of
the bootstrap and Monte Carlo steps, so a rerun reproduces the result. The
profile `current` supplies the gas, slip and constant models of the INV stage.
The profile `article1_7658971` has no INV stage. `model_overrides` is empty,
so the profile values apply unchanged.

## 2. Consistency checks

Each check compares a logged value with the value computed from the other
records. A difference beyond its tolerance warns, and both values stay in the
reading record.

`checks.gas_property_rel_tol` (0.005) compares the logged mean free path and
viscosity with the Sutherland model of Kim et al. (2005, Eqs. 9 and 11). Near
room temperature a 0.5 percent difference in the mean free path corresponds
to about 1 K, so a larger difference points to another gas model or reference
state. Logged values in example exports agree within 0.5 percent.

The project flow tolerance `checks.flow_rel_tol` is 5 percent. Wiedensohler et
al. (2012, Sect. 3.1.3 and Appendix A4) recommend 5 percent for aerosol flow
and 2 percent for sheath flow.

`checks.setpoint_rel_tol` (0.05) lies above the spread of -2.4 to +3.4 percent
between recorded and calculated AAC setpoints in example records.

`checks.impactor_d50_rel_tol` (0.1) compares the cut of the 3082 manual
(Eq. B-1) at the logged nozzle and flow with the logged Impactor D50. The cut
scales roughly with the inverse square root of the flow, so 10 percent in the
cut corresponds to about 20 percent in the flow or to a different nozzle.

## 3. Charge states

The charge sum runs to the smallest charge whose omitted fraction at the
largest grid diameter is below `charging.tail_tol` (1e-3). That fraction is
smaller than the relative Poisson noise of a channel with fewer than 1e6
counts. A null `charging.max_charge` leaves this limit to the tail rule.
`charging.range_policy` warns instead of stopping, because SMPS windows that
start near 14 nm lie below the 20 nm lower limit of the doubly charged
coefficients (Wiedensohler et al. 2012, Appendix A5). Above 1000 nm, the
upper limit of those coefficients, every charge state takes the Gunn form of
the same appendix.

## 4. Transfer, penetration and counting efficiency

The AAC transfer function uses balanced flows (Johnson et al. 2018), the
usual operating mode of the classifier. The unbalanced form of that paper's
supplement applies only where the record shows unequal flows.

Losses inside the DMA column use the fitted electrostatic penetration (0.98)
and effective length (7.1 m) of Karlsson and Martinsson (2003, Table 6) for
the cylindrical type T1 to T3 of their Table 1. These values approximate the
3081A and are not a calibration of it. The 9.1 m equivalent length of the
SMPS software manual (version 11, Appendix B, p. B-14) is the cross-check.

Counting efficiency is unity only inside a bound given with its published
characterization (`cpc.unity_bound_min_diameter_nm`,
`cpc.unity_bound_max_deficit` and `cpc.unity_bound_citation`). The 3789
manual (Ch. 5) gives cut points near 2 nm but no efficiency curve above them.
The bound keys are empty in the example, so unity is never assumed without a
stated source. `cpc.efficiency_file` is empty and names a characterized curve
when one is available.

## 5. Scan response

The logged delay is read as the plug-flow delay plus the counter time
constant, so the plug-flow delay equals the logged delay minus
`scan_response.tau_s_s`. The Savitzky-Golay window and order of the
de-smearing check (Chen et al. 2024, Eqs. 22-26) are set once on a synthetic
step response and never on measured data, so the check cannot be tuned to the
scans it tests. Both keys are empty in the example, and strict loading refuses
them until they are set.

## 6. Calibration factor k(dm)

The project default is k(dm) = 1.27 - 3.598 dm^-0.8376, with dm in nm. The
size-dependent factor corrects systematic density bias and tends to 1.27 at
large diameters. Kiasadegh et al. (2026, Eqs. 33-34) describe the
density-ratio correction. PEG reference measurements appear in Sapkota et al.
(2025, Aerosol Sci. Technol. 59, 1053-1064, Supplement S3, Figure S3). The
configured range of 22 to 600 nm approximates the reference-data range.
Results outside that range are flagged. Calibration uncertainty is specified
for each campaign.

`calibration.k_dm.source_id` identifies the campaign calibration record. The
example does not include that record. `calibration.k_dm.uncertainty` is empty
in the example and holds the relative calibration uncertainty of the campaign.
`calibration.k_dm.data_file` names the reference points or their covariance
when they are available.

## 7. Grid

The grid extent follows the kernel. It starts one cell below the first
diameter whose expected-count column sum exceeds `grid.support_threshold`
(1e-3) of the largest column sum and ends where the column sum falls below
the same fraction. Cells outside that support carry less than 0.1 percent of
the sensitivity of the best cell. The upper end includes the impactor
penetration in aerodynamic diameter, mapped to mobility diameter through the
density relation of the condition.

Resolution starts at `grid.points_per_decade` (32, a diameter step of about
7.5 percent) and is refined by `grid.refine_factor` (1.5) until the reported
statistics change by less than `grid.statistic_tol_sd` (0.25) posterior
standard deviations and their standard deviations by less than
`grid.sd_rel_tol` (10 percent). A quarter of a standard deviation is small
against a 95 percent interval, which spans about four standard deviations.
The 2D grid starts at 12 points per decade, because its cell count grows with
the square of the resolution. The extent test widens the upper end by
`grid.extent_step_decades` (0.15 decades, a factor of about 1.4 in diameter)
and the lower end by one cell. Sipkens et al. (2020, part I, p. 17) found
Tikhonov results insensitive to the bin count above about 35 bins per
mobility range, which favors a convergence rule over a fixed resolution.
Explicit grid limits are accepted only with `TestFixture`, so production runs
always take the extent from the kernel support.

The 2D partial grid keeps cells with effective densities of 20 to
3000 kg/m3 (partial grid of Sipkens et al. 2020, part I, physical domain of
Sipkens et al. 2025, p. 8). The upper bound exceeds the material density of
soot with margin, and the lower bound lies well below the lowest published
soot effective density.

## 8. Inversion

The 1D prior families are Tikhonov of orders 0, 1 and 2 and the exponential
distance prior (Sipkens et al. 2020, part II, Eqs. 38 and 42-45). The 2D
families are Tikhonov of orders 1 and 2. The family is chosen once per
instrument mode from the evidence pooled over its scans, integrated over
lambda and, for the exponential prior, over its length scale. One family per
mode keeps the regularization the same for scans that are compared. The
per-scan average over families is the sensitivity run. The prior mean is
zero, because a prior mean built from the data reuses them in the evidence.
Nonnegativity is imposed with a zero lower bound, and the evidence and
posterior covariance are those of the unconstrained Gaussian (Sipkens et al.
2020, part II, Eq. 26). One stage is used, and the two-stage operator of
Huckle and Sedlacek (2012) and Petters (2021) is a cross-check only.

Lambda follows the evidence of Sipkens et al. (2020, part II, Eqs. 29-34),
marginalized under a log-uniform hyperprior, the scale-invariant choice for
a scale parameter. The support spans 11 decades, 1e-8 to 1e3 times
lambda_ref = sqrt(tr(A'A)/tr(R)), searched on 111 points at 0.1 decade. When
the evidence maximum lies within two points of an end, the maximum may lie
outside the range, so the search widens by two decades and a flag is set.
The search is refined until the mean, standard deviation and 2.5 and
97.5 percent quantiles of log10 lambda change by less than 1 percent of its
standard deviation. The posterior mass within one decade beyond the final
range is reported. The exponential length scale runs over 0.05 to 1 decade
with 20 values, from under two grid cells at 32 points per decade to a full
decade. Route B exports are reduced by the instrument software and do not
enter the 2D kernel.

## 9. Observation variance

Route A uses the Poisson variance in two passes, first from the counts with
a floor of `variance.floor_counts` (one count), then from the expected counts
of the first evidence-based solution. The floor keeps the variance of an
empty channel positive. Repeat variability follows the Poisson-Gaussian model
of Sipkens et al. (2023, Eqs. 5 and 6). Within-scan variability determines
the observation weights. The between-scan term represents a common scale
fluctuation and contributes to the variance of extensive statistics. The
repeat terms are estimated per campaign and mode from at least two repeats
(Sipkens et al. 2023, p. 5), and their estimation uncertainty is propagated.
The unweighted fit is the sensitivity run.

## 10. Observation routes and peak fit

`observation.route` set to `auto` uses route A where database counts exist
and route B otherwise, since raw counts carry their own Poisson variance.
Route B exports without multiple-charge correction are fitted with their
charge components, and campaigns with both routes compare them.

The tandem peak fit uses every channel of the window and one latent
lognormal population in dm, pushed through the full kernel of every retained
charge state. Fits use the Poisson likelihood, with the two-pass weighted and
the unweighted fits as sensitivity runs. A second population enters only
through a parametric-bootstrap likelihood-ratio test at the 1 percent level
with 200 replicates. The null distribution is simulated from the
one-population fit, because an amplitude at zero breaks the usual
asymptotics. With 200 replicates the smallest attainable p-value is 1/201,
about 0.005, below the test level. `peak_fit.first_width_min` (0.0409,
slightly above -ln 0.96) keeps every width positive. `peak_fit.gsd_bound`
limits the additive GSD adjustment to 0.04. This keeps the width adjustment
local to the initial estimate. The window geometric mean is reported as a
check.

## 11. Moments, averaging and reporting

Moments cover the scan window, the range that the measurement observes.
Whole-window moments get delta-method intervals. GM and GSD intervals are
withheld and flagged when the one-population fit is rejected or when its
number fraction above the window top exceeds `moments.edge_fraction_max`
(0.05). These intervals are conditional on the fitted population and its
support within the window. Averages use the two-sided 95 percent Student t
interval of the scan count on the common size support, without
extrapolation. The t interval allows for a standard deviation estimated from
few scans.

Above the window, the number and mass fractions up to `report.d_cap_nm` are
reported as one-sided 95 percent upper bounds and labeled exploratory, since
the window channels constrain them only through multiply charged particles.
The 1400 nm cap is close to the 1384 nm cut calculated from the 3082 manual
(Eq. B-1) for a 0.071 cm nozzle at 0.3 L/min, 296.15 K and 101325 Pa, using
unit-density spheres. A null `report.d_floor_nm` keeps the window start as the lower
limit. Route B results require a validated reduction and a stated charge
setting, because the software reduction is not reproduced. Every result
carries the listed sensitivity runs, the uncertainty budget and the
diagnostic figures. The sensitivity runs cover the model choices that the
data do not fix. `gas.dm_root_rel_tol` (1e-10) is the relative tolerance of
the mobility diameter root, far below the sizing uncertainty.

## 12. Impactor and small-size sensitivity

When the logged flow lies outside the stated range of the logged nozzle
(3082 manual, Table 2-10), the impactor cut and its sharpness run as separate
sensitivity cases. The cut factor range starts at 0.69, the ratio of the calculated
cuts at 0.6 and 0.3 L/min for the same nozzle and reference gas state. It ends
at 1.3, a cut 30 percent above the nominal one. The impactor penetration is a sigmoid in aerodynamic diameter,
1 / (1 + (da / d50)^s). The diameters at 90 and 10 percent penetration then
differ by a factor 9^(2/s), about 4.3 for s = 3 and 1.6 for s = 9. The
sharpness range of 3 to 9 spans a broad to a near-step cut, with 9 as the
sharp comparator of `penetration.impactor_sharpness_1`.

The optional nuisance population represents a small mode in windows starting
below 30 nm. It is off by default, so the window moments include the whole
measured distribution. Its CMD range of 5 to 16 nm places its center below or
near a 14 nm window start. Its GSD range of 1.1 to 1.8 corresponds to
log-diameter standard deviations of about 0.095 to 0.588. These bounds limit
location and width but do not prevent absorption of a genuine small soot
mode. A nuisance share above 1 percent flags a contribution exceeding one
hundredth of the window number.

## 13. Uncertainty and diagnostics

Intervals of nonlinear statistics come from the delta method at the
nonnegative solution, mixed over lambda and kernel draws by the law of total
variance. A truncated Gibbs sampler (Bardsley and Fox 2012) checks one scan
per campaign. The interval of the distribution mode, a grid maximum and not
a smooth statistic, comes from a parametric bootstrap. Kernel uncertainty
uses Latin hypercube draws over the terms of `uncertainty.kernel_terms`.
The design stratifies each term, so few draws cover its range. The draws
start at 20 and are doubled until the standard deviation of each reported
statistic changes by less than 5 percent. Posterior draws continue until the
Monte Carlo error of each interval end is below 5 percent of the half width,
with at least 300 draws. Each tail of a 95 percent interval then holds about
seven draws or more.

Diagnostic flags never change a result or remove a scan. A flag marks a
lambda posterior wider than 0.5 decades, a factor of about 3.16 in lambda.
Another marks a residual sum outside the central 99.8 percent of a
2000-replicate reference. That interval has a nominal tail probability of
0.2 percent. With 2000 replicates, this leaves about two replicates in each
tail, so the flag is a coarse diagnostic. Residual runs and lag-one
correlation are each tested at the 1 percent level. Under a calibrated null,
each test flags about one well-fitted scan in a hundred by chance. Posterior predictive probabilities outside
0.005 to 0.995 mark a two-sided 1 percent level. Further flags mark
cross-check lambdas more than one decade, a factor of 10, from the evidence
lambda that move a statistic by more than one posterior standard deviation.
Another flag marks more than 20 percent of window cells at the zero bound,
where the Gaussian approximation of the posterior weakens.

The project sampler check uses four chains and a split R-hat threshold of
1.01. Split R-hat and effective sample size are described by Gelman et al.
(2013, Sects. 11.4 and 11.5). A check that does not reach the threshold is
flagged as unresolved. Up and down scans (AAC manual p. 52, Chen et al. 2024,
p. 8) and the two routes are compared where both exist. The response gain measures the recovered change along the statistic's
direction. A gain of 0.9 corresponds to recovery of 90 percent of that change.
The response cosine is the squared cosine between the averaging kernel and the
statistic's Jacobian. Its threshold of 0.5 requires at least half of the
kernel's squared norm to lie along that direction. Both thresholds are
diagnostics only. A second mode
is reported when the dip between two maxima exceeds twice the posterior
standard deviation at the dip in at least 95 percent of draws, so a dip of
noise size is not read as a mode.

## 14. Data exclusion

Each excluded scan carries its reason code. X1 removes records that the
instrument software marks invalid. X2 removes scans whose logged flow leaves
plus or minus 5 percent of its setpoint. The project flow tolerance is
5 percent. Wiedensohler et al. (2012, Sect. 3.1.3 and Appendix A4) recommend
5 percent for aerosol flow and 2 percent for sheath flow. X3 removes scans
above the single-count limit of the counter or the charger limit of about
1e6 cm-3 (Wiedensohler et al. 2012, Sect. 2). X4 removes dates listed in
`exclusion.dates`. The example lists February 4 and 5, 2025. Campaign use
requires a recorded exclusion reason. X5 applies the scan selection of the
campaign records. Diagnostic flags never remove data, so a flagged scan stays
in the result and its flag is reported.

## 15. Standalone SMPS and AAC modes

`mode` selects the tandem analysis or a standalone SMPS or AAC analysis, and
each mode reads only its own blocks. Standalone SMPS scans follow the route
rule of section 10 and report moments per scan before averaging, so the
scan-to-scan spread enters the averaged interval. The diffusion loss
correction is kept as delivered by the instrument software, since a second
correction would count the loss twice. Standalone AAC scans use the counter
series where the file holds counts and the spectral density otherwise.
Transmission uses the dm of the tandem fit, and the delay is read as logged.
Averaged and subsampled rows run side by side (AAC manual p. 53), with their
difference in the uncertainty budget. Mass concentration comes from the SMPS
tandem result, which holds the number distribution and the effective density
together.

## 16. Derived quantities

Rows with reading rule X are computed from other settings and are never
configured. The charge-fraction sum is reported without renormalization, so
a sum below one shows the omitted charge states. Mass is the log-quadrature
integral of (pi/6) rho_eff dm^3, and the fitted count median diameter is
that of the singly charged peak. Diffusion coefficients use the mobility
diameter. Penetration ends at the counter inlet, because losses inside the
counter belong to the counting efficiency. Repeats are assumed independent
and are never padded with synthetic values. The linear solution D b serves
only as a start value. Kurtosis is the Pearson kurtosis of log10 diameter.
It equals 3 for an untruncated lognormal diameter distribution. Results are
reported in nm, kg/m3 and micrograms per m3, and every result carries its
provenance record.
