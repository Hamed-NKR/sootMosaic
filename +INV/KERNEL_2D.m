function [a, info] = KERNEL_2D(grid, observations, configs, impactors, draw)
% "KERNEL_2D" maps a joint aerodynamic-mobility distribution to tandem data.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     grid: Log INV.Grid or INV.PartialGrid, coordinates [da dm] (nm)
%     observations: Cell of route A SMPS observations, one per AAC step
%     configs: Cell of resolved per-step configurations
%     impactors: Cell of GRID_RULE impactor structures, one per step
%     draw: Optional physical draw, common to all steps. Flow multipliers,...
%         ...AAC sizing and width multipliers, penetration multiplier,...
%         ...counting efficiency, charge model and mixing time are supported
% Outputs:
%     a: Rows in step order then SMPS-bin order; columns follow grid.elements
%     info: Step row bounds, component diagnostics and draw
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 23 and 28);
%     ...Rawat et al. (2016); Buckley et al. (2017);
%     ...Johnson et al. (2018, Eqs. 1, 7 and 12-15).
% Repository: https://github.com/tsipkens/bidias
% Commit: fa318b8c6b48b1b4f28bacb7713aba15ba43d52d
% License: MIT License.
% Code citation: Sipkens et al. (2020), doi:10.17632/sg2zj5yrvr.3.
% Adopted structure from +kernel/gen_pma_dma_grid.m.
% Modified 18 Nov 2026: AAC replaces the mass classifier, recorded flows,...
%     ...mobility diffusion, charge tails, whole-cell masks and time bins....
%     ...Block factors use the common mobility response once per step;...
%     ...AAC transmission retains its mobility dependence.
% MIT License
%
% Copyright (c) 2019 Timothy A. Sipkens
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

if nargin < 5, draw = struct(); end
if ~isa(grid, 'INV.Grid') || grid.dim ~= 2 || ~strcmp(grid.discrete, 'log')
    error('sootMosaic:KERNEL_2D:Grid', 'Require a log grid with [da dm] in nm.');
end
if ~iscell(observations) || isempty(observations) || ~iscell(configs) || ...
        ~iscell(impactors) || numel(configs) ~= numel(observations) || ...
        numel(impactors) ~= numel(observations)
    error('sootMosaic:KERNEL_2D:Steps', 'Require matching observation, configuration and impactor cells.');
end
n = numel(observations);
blocks = cell(n, 1);
details = cell(n, 1);
rows = zeros(n, 2);
[dm, ~, map] = unique(grid.elements(:, 2)*1e-9);
da = grid.elements(:, 1)*1e-9;
width = grid.dr();
last = 0;
for j = 1:n
    [c, d] = kernel_settings(configs{j}, draw, 'KERNEL_2D');
    [voltage, h, volume, timing] = kernel_rows(observations{j}, c, d, 'KERNEL_2D');
    require_recorded(c, {'scan.aac_setpoint_nm', 'scan.aac_temperature_deg_c', ...
        'scan.aac_pressure_kpa'}, 'KERNEL_2D');
    setpoint = c.si.scan.aac_setpoint_nm;
    if ~isscalar(setpoint) || ~isfinite(setpoint) || setpoint <= 0
        error('sootMosaic:KERNEL_2D:Setpoint', 'Require a recorded AAC diameter setpoint.');
    end
    INV.AAC_SETPOINT(configs{j}, sprintf('step %d', j));
    [base, component] = kernel_dma(dm, voltage, c, d, 'KERNEL_2D');
    s = c.si.scan;
    [mu, ~, cc, params] = INV.GAS(s.aac_temperature_deg_c, ...
        s.aac_pressure_kpa, da, c);
    tau = params.constants.rho_aero_ref_kg_m3*da.^2.*cc/(18*mu);
    [aac, aac_info] = INV.TFER_AAC(tau, setpoint, dm(map), c, ...
        sprintf('step %d', j), d.aac_sizing_scale_1, d.aac_width_scale_1);
    % Mapping the aerodynamic coordinate to the impactor gas state
    rho = INV.RHO_EFF(da, dm(map), s.aac_temperature_deg_c, ...
        s.aac_pressure_kpa, c);
    da_impactor = aerodynamic_diameter(dm(map), rho, ...
        s.dma_temperature_deg_c, s.dma_pressure_kpa, c);
    imp = kernel_impactor(dm(map), da_impactor, c, impactors{j}, 'KERNEL_2D');
    block = base(:, map).*(aac.*imp.*width).';
    blocks{j} = (h*block).*volume;
    rows(j, :) = [last+1, last+size(blocks{j}, 1)];
    last = rows(j, 2);
    details{j} = struct('dma', component, 'aac', aac_info, 'timing', timing, ...
        'operator_1', h, 'sample_volume_cm3', volume, 'impactor_1', imp);
end
a = vertcat(blocks{:});
info = struct('row_bounds', rows, 'steps', {details}, 'draw', draw, ...
    'distribution_unit', 'cm^-3 per log10(da) per log10(dm)');
end
