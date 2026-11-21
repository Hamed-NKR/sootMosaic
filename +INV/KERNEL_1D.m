function [a, info] = KERNEL_1D(grid, obs, cfg, impactor, draw)
% "KERNEL_1D" maps a mobility number distribution to a raw SMPS observation.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     grid: One-dimensional log INV.Grid in mobility diameter (nm)
%     obs: Route A OBSERVATION, or its raw concentration view (cm^-3)
%     cfg: Resolved per-scan configuration
%     impactor: GRID_RULE impactor with d50_m, cut_factor_1, sharpness_1...
%         ...and rho_kg_m3 (positive scalar or function of diameter in m)
%     draw: Optional scalar kernel-draw structure. charge_e accepts a...
%         ...vector of charge states; empty uses the configured tail rule
%     draw: Flow scales dma_aerosol_scale_1, dma_sheath_scale_1,...
%         ...dma_excess_scale_1, aac_sample_scale_1, aac_sheath_scale_1;...
%         ...aac_sizing_scale_1, aac_width_scale_1,...
%         ...penetration_length_scale_1 and cpc_scale_1 are dimensionless....
%         ...tau_s_s is seconds, charge_model names a registry model,...
%         ...charge_e is in elementary charges, diffusing_1 is logical
% Outputs:
%     a: Forward matrix for x = dN/dlog10(dm) (cm^-3). Counts use each...
%         ...bin volume after smearing, diag(V) H K, without dilution again
%     info: Unsmeared concentration kernel, interval operator, exposure,...
%         ...charge and loss diagnostics and the kernel draw
%     info.operator_1: Full history-to-observation operator, including...
%         ...transport delay and mixing. It can be rectangular or singular;...
%         ...backsubstitution requires a separate delay-aligned mixing map
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 23 and 28);
%     ...Chen et al. (2024, Eqs. 3 and 5).
% Adopted and modified from +kernel/gen_smps.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% Method citation: Sipkens et al. (2020, part I), Journal of Aerosol Science
%     140, 105484, doi:10.1016/j.jaerosci.2019.105484.
% The source file has no copyright or license block.
% The complete GPL-3 text is supplied in the repository LICENSE file.
% Modified 18 Nov 2026: package calls replace transfer-package calls.
% Modified 18 Nov 2026: named charge options and adaptive charge tails.
% Modified 18 Nov 2026: no display, progress bar or response thresholding.
% Modified 18 Nov 2026: log quadrature, penetration and aerodynamic impactor.
% Modified 18 Nov 2026: raw-observation guard, interval response and exposure.
% Modified 18 Nov 2026: shared physical draw and component diagnostics.
% Modified 18 Nov 2026: inlet/sample flow ratio of Chen et al. (2024, Eq. 3).

if nargin < 5, draw = struct(); end
[c, draw] = kernel_settings(cfg, draw, 'KERNEL_1D');
[voltage, h, volume, time_info] = kernel_rows(obs, c, draw, 'KERNEL_1D');
if ~isa(grid, 'INV.Grid') || grid.dim ~= 1 || ...
        ~strcmp(grid.discrete, 'log') || grid.Ne < 2
    error('sootMosaic:KERNEL_1D:Grid', 'Require a one-dimensional log grid in nm.');
end
dm = grid.elements(:, 1)*1e-9;
[k, components] = kernel_dma(dm, voltage, c, draw, 'KERNEL_1D');
imp = kernel_impactor(dm, [], c, impactor, 'KERNEL_1D');
k = k.*(imp.*grid.dr()).';
a = (h*k).*volume;
info = struct('concentration_kernel', k, 'operator_1', h, ...
    'sample_volume_cm3', volume, 'timing', time_info, ...
    'components', components, 'impactor_1', imp, 'draw', draw, ...
    'distribution_unit', 'cm^-3 per log10(dm)');
end
