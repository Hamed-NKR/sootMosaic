# Third-party notices

## Tandem classifier source

Repository: https://github.com/cambustion/tandem
Source: `src/aerosol_psd_fitting_tool.py`, lines 48-60 and 169-259.
Commit: `0cc733cd4d2f80defd8ef5b93a3bb586778012df` (29 Oct 2026).
License: MIT License.
Consumers: `+INV/DM_FROM_Z.m` and `+INV/AAC_SETPOINT.m`.
Published methods: Sipkens et al. (2020, part I, Eqs. 7-9),
Johnson et al. (2018, Eq. 2), and Kiasadegh et al. (2026, Eqs. 6 and 14).
Kiasadegh et al. (2026) cites software release v2.0.0 (21e5a71).

MIT License

Copyright (c) 2023-24 Cambustion, University of Alberta, NRC Canada

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Owner's fork, provenance only

Repository: https://github.com/Hamed-NKR/odias
Commit: c654348abf11599e24b63374622c31d8458cd7e4 (12 May 2025).
License: GPL-3. The following files were read for logic, field lists or
formulas only; no code text was copied.

- `DAT.m`: `+INV/READ_SMPS.m`, `+INV/SELECT_SCANS.m`,
  `+INV/POOL_SCANS.m` and `+INV/RHO_EFF.m`.
- `main_aac_HN_1d.m`: `+INV/READ_AAC.m`.
- `main_dma_HN_1d_v3.m`: `+INV/SELECT_SCANS.m` and `+INV/POOL_SCANS.m`.
- `main_loss_HN.m`: `+INV/PENETRATION.m`.

## Import and relation methods

- `+INV/READ_SMPS.m` and `+INV/READ_SMPS_DB.m`: SMPS software manual
  (2019, version 11); Wiedensohler et al. (2012, Appendices A4 and A5.1).
- `+INV/READ_AAC.m`: AAC manual (2023, v2.43, Sections 2.3.4 and 2.5.3);
  Johnson et al. (2018, Eqs. 9-11).
- `+INV/SELECT_SCANS.m` and `+INV/POOL_SCANS.m`: pooled within- and
  between-group sums-of-squares identity.
- `+INV/OBSERVATION.m`: Kiasadegh et al. (2026, Section 3.3);
  Sipkens et al. (2020, part I, Eq. 23); Johnson et al. (2018, Eqs. 9-11).
- `+INV/GAS.m`: Kim et al. (2005, Eqs. 9, 11 and 34).

## Transfer functions and losses, published methods

The following files are reimplementations from published equations:

- `+INV/TFER_DMA.m`: Stolzenburg (2018, Eqs. 10, 16, 18, 26, 29-34,
  39-40 and A2-A5, A15); Sipkens et al. (2020, part I, Eqs. 5-9).
- `+INV/TFER_AAC.m`: Johnson et al. (2018, Eqs. 2, 7, 12-15, Table 1);
  Tavakoli and Olfert (2013, Eqs. 4-11).
- `+INV/PENETRATION.m`: Johnson et al. (2018, Eqs. 12-14); Karlsson and
  Martinsson (2003, Eqs. 13-14, Tables 1 and 6); Wiedensohler et al.
  (2012, Table 1); SMPS software manual version 11 (Appendix B, p. B-14).
- `+INV/CPC_EFF.m`: Johnson et al. (2018, Eq. 8); CPC 3789 operation
  manual revision C (2021, Ch. 5).

No code from the transfer-function package is included. These entries
record method provenance and impose no additional code notice obligation.

## Charge methods

- `+INV/CHARGE_FRAC.m`: 3082 manual (2016, Eqs. B-2 and B-3,
  Tables B-2 and B-3); Wiedensohler et al. (2012, Table A7);
  Gopalakrishnan et al. (2013, Eq. 10, Table 2).

## Two-dimensional inversion package

Repository: https://github.com/tsipkens/bidias
Commit: fa318b8c6b48b1b4f28bacb7713aba15ba43d52d (9 Apr 2024).
License: MIT License.

Adopted files:

- `@Grid/Grid.m` into `+INV/@Grid/Grid.m`.
- `@PartialGrid/PartialGrid.m` into `+INV/@PartialGrid/PartialGrid.m`.
- The charge-sum and grid-factorization structure of
  `+kernel/gen_pma_dma_grid.m` into `+INV/KERNEL_2D.m`.

Modified 18 Nov 2026. Grids add one-dimensional coordinates, validation,
preallocation and explicit whole-cell masks. The tandem kernel uses the AAC
coordinate, recorded settings, mobility-dependent diffusion, interval
averaging, exposure and the existing physical functions. Plotting and
interactive output are omitted. Each adopted file includes the MIT notice.

Method citation: Sipkens et al. (2020, part I), Journal of Aerosol Science
140, 105484, doi:10.1016/j.jaerosci.2019.105484, Sec. 2.2 and Eqs. 23, 28.
Code citation: Sipkens et al. (2020), doi:10.17632/sg2zj5yrvr.3.
The source README requests both the method and code citations for adopted
code. Its additional Twomey-Markowski citation, Buckley et al. (2017), is
retained in the tandem kernel provenance. No mass-analyzer transfer code
is adopted. The pinned source has no `+kernel/build.m`.
MIT License

Copyright (c) 2019 Timothy A. Sipkens

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## One-dimensional inversion package

Repository: https://github.com/tsipkens/odias
Commit: 8de95745486b01cf5ede0b186d044656eb3fde33 (8 Jan 2024).
License: GNU General Public License, version 3 (GPL-3).

`+kernel/gen_smps.m` is adopted into `+INV/KERNEL_1D.m`; its charge
accumulation is shared in `+INV/private/kernel_dma.m`. Both are modified
18 Nov 2026. Named charge options, adaptive tails, existing physical calls,
penetration, the aerodynamic impactor, log quadrature, raw-observation
checks and exposure after interval averaging replace the source wrappers.
Display, progress reporting and response thresholding are omitted.

The source file carries an authorship line, represented by the author-year
attribution Sipkens (2020), and has no copyright or license block. The
repository GPL-3 text is the repository `LICENSE`.
The modified source is shipped with this distribution. The combined work
containing the adopted GPL-3 kernel is distributed under GPL-3; existing
MIT notices remain attached to their respective components.

Methods: Sipkens et al. (2020, part I, Eqs. 23 and 28) and Chen et al.
(2024, Eqs. 3 and 5). The source README contains credits but no additional
formal citation request for this kernel.

## Grid support and scan-response methods

`+INV/SCAN_RESPONSE.m` is reimplemented from Chen et al. (2024,
Eqs. 2, 5, 22-26, 33 and 36-39) and Collins et al. (2002, Eqs. 9-14).
`+INV/GRID_RULE.m` and `+INV/GRID_CONVERGE.m` implement the supplied support
and convergence rules using Sipkens et al. (2020, part I, Sec. 2.2),
Johnson et al. (2018, Eqs. 1 and 7) and 3082 manual (2016, Eq. B-1).
No external source text is adopted into these three files.
