function result = OP_RANGE(setting, cfg)
% "OP_RANGE" screens the DMA, AAC and tandem operating ranges at given flows.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     setting: Scalar structure with the gas temperature_k (K) and...
%         ...pressure_pa (Pa), and dma_sheath_flow_m3_s with...
%         ...dma_aerosol_flow_m3_s, aac_sheath_flow_m3_s with...
%         ...aac_aerosol_flow_m3_s, or both pairs (m3/s). Balanced sheath...
%         ...and exhaust flows are assumed. Optional relation with...
%         ...rho_100_kg_m3 (kg/m3) and mass_mobility_exponent (2 < Dm <= 3)...
%         ...maps the AAC range to mobility diameter for the tandem...
%         ...overlap, unit-density spheres by default. Optional dm_m and...
%         ...da_m are mobility and aerodynamic setpoints to screen (m)
%     cfg: Resolved +INV configuration. Voltage, speed and sheath flow...
%         ...limits come from op_range, the geometry from geometry. The...
%         ...op_range ids must name the configured DMA and AAC. A sheath...
%         ...flow outside its inclusive limits is refused
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Gas state, DMA mobility limits with the voltage limits and...
%         ...resolution, AAC aerodynamic limits with the speed limits, the...
%         ...speed line and resolution, the tandem overlap in mobility...
%         ...diameter (NaN when empty) and the screen flags (m, rad/s, s)
% ----------------------------------------------------------------------- %
% Method: Kiasadegh et al. (2026, Sec. 2.4 and Table 1; SI Secs. S1.1...
%     ...and S1.2, Eqs. S1-S7); Johnson et al. (2018, Eqs. 1 and 2).
% Repository: https://github.com/MortezaKiasadegh/acorc
% Source: script.js (calculateDMARange, calculateAACRange and...
%     ...da_rhoeff2dm), release v2.0
% Commit: 21889c61289e16936d7b8256b839c4090351c192
% License: MIT License.
% Code citation: Kiasadegh (2025), ACORC, Aerosol Classifier Operational...
%     ...Range Calculator, Zenodo, doi:10.5281/zenodo.15620940.
% Modified 20 Nov 2026: roots are bracketed instead of started from fixed...
%     ...guesses; the speed line is evaluated at the given sheath flow;...
%     ...gas properties, constants and geometry come from the...
%     ...configuration through INV.GAS, INV.DM_FROM_Z and INV.RHO_EFF;...
%     ...the AAC relaxation time and diameter come from the private...
%     ...function aac_setpoint_physics;...
%     ...plotting, the mass classifier and the sheath flow sweep are omitted.
% MIT License
%
% Copyright (c) 2025 Morteza Kiasadegh
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
%The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

if nargin < 2
    fail('Input', 'Pass a setting and the resolved configuration.');
end
allowed = {'temperature_k', 'pressure_pa', 'dma_sheath_flow_m3_s', ...
    'dma_aerosol_flow_m3_s', 'aac_sheath_flow_m3_s', ...
    'aac_aerosol_flow_m3_s', 'relation', 'dm_m', 'da_m'};
if ~isstruct(setting) || ~isscalar(setting) || ...
        any(~ismember(fieldnames(setting), allowed))
    fail('Setting', 'Unknown setting field or a nonscalar setting.');
end
temp = positive_field(setting, 'temperature_k', 'State');
pressure = positive_field(setting, 'pressure_pa', 'State');
has_dma = isfield(setting, 'dma_sheath_flow_m3_s') || ...
    isfield(setting, 'dma_aerosol_flow_m3_s');
has_aac = isfield(setting, 'aac_sheath_flow_m3_s') || ...
    isfield(setting, 'aac_aerosol_flow_m3_s');
if ~has_dma && ~has_aac
    fail('Setting', 'Give the flows of the DMA, the AAC or both.');
end
if (isfield(setting, 'relation') && ~(has_dma && has_aac)) || ...
        (isfield(setting, 'dm_m') && ~has_dma) || ...
        (isfield(setting, 'da_m') && ~has_aac)
    fail('Setting', 'A screen or relation needs the classifier it refers to.');
end
try
    limits = cfg.si.op_range;
    geometry = cfg.si.geometry;
    same_dma = strcmp(cfg.op_range.dma, cfg.instruments.dma);
    same_aac = strcmp(cfg.op_range.aac, cfg.instruments.aac);
catch
    fail('Config', 'Pass a resolved inversion configuration.');
end
try
    [~, ~, ~, params] = INV.GAS(temp, pressure, [], cfg);
catch err
    fail('State', err.message);
end
rho0 = params.constants.rho_aero_ref_kg_m3;
result = struct('temperature_k', temp, 'pressure_pa', pressure, ...
    'dma', [], 'aac', [], 'tandem', []);

% DMA mobility limits at the voltage limits, Eqs. S2 and S3 with Z = e B
if has_dma
    if ~same_dma
        fail('Instrument', 'The range DMA differs from the configured DMA.');
    end
    qsh = positive_field(setting, 'dma_sheath_flow_m3_s', 'Flows');
    qa = positive_field(setting, 'dma_aerosol_flow_m3_s', 'Flows');
    check_flow(qsh, limits, 'dma_sheath_flow_limits_lpm');
    volts = limit_pair(limits, 'voltage_limits_v');
    [r1, r2, len] = annulus(geometry, 'dma');
    z = qsh * log(r2 / r1) ./ (2 * pi * len * volts);
    d = INV.DM_FROM_Z(z, 1, temp, pressure, cfg);
    result.dma = struct('d_min_m', d(1), 'd_max_m', d(2), ...
        'voltage_limits_v', volts, 'sheath_flow_m3_s', qsh, ...
        'aerosol_flow_m3_s', qa, 'resolution', qsh / qa, ...
        'inside', screen(setting, 'dm_m', d));
end

% AAC aerodynamic limits at the speed limits, Eqs. S5 to S7
if has_aac
    if ~same_aac
        fail('Instrument', 'The range AAC differs from the configured AAC.');
    end
    qsh = positive_field(setting, 'aac_sheath_flow_m3_s', 'Flows');
    qa = positive_field(setting, 'aac_aerosol_flow_m3_s', 'Flows');
    check_flow(qsh, limits, 'aac_sheath_flow_limits_lpm');
    speeds = limit_pair(limits, 'speed_limits_rad_s');
    intercepts = line_pair(limits, 'speed_limit_intercepts_rad_s');
    slopes = line_pair(limits, 'speed_limit_slopes_rad_s_per_lpm');
    switch_flow = limits.speed_limit_switch_flow_lpm;
    if ~isnumeric(switch_flow) || ~isscalar(switch_flow) || ...
            ~isfinite(switch_flow) || switch_flow <= 0
        fail('MissingLimits', 'The speed line switch flow is unavailable.');
    end
    branch = 1 + (qsh > switch_flow);
    w_line = intercepts(branch) + slopes(branch) * qsh;
    w_up = min(speeds(2), w_line);
    if ~(w_up > speeds(1))
        fail('SpeedRange', 'The upper speed falls below the lower speed.');
    end
    annulus(geometry, 'aac'); % refuses unavailable or inverted geometry
    w = [w_up, speeds(1)];
    tau = zeros(1, 2);
    da = zeros(1, 2);
    for k = 1:2
        try
            [tau(k), da(k)] = aac_setpoint_physics(w(k), qsh, temp, ...
                pressure, cfg);
        catch err
            prefix = 'sootMosaic:AAC_PHYSICS:';
            if startsWith(err.identifier, prefix)
                fail(extractAfter(err.identifier, prefix), err.message);
            end
            rethrow(err);
        end
    end
    result.aac = struct('da_min_m', da(1), 'da_max_m', da(2), ...
        'tau_min_s', tau(1), 'tau_max_s', tau(2), ...
        'speed_limits_rad_s', w([2 1]), 'speed_max_rad_s', speeds(2), ...
        'speed_line_rad_s', w_line, 'line', branch, ...
        'line_limited', w_line < speeds(2), 'sheath_flow_m3_s', qsh, ...
        'aerosol_flow_m3_s', qa, 'resolution', qsh / qa, ...
        'inside', screen(setting, 'da_m', da));
end

% Tandem overlap in mobility diameter through the effective density
if has_dma && has_aac
    relation = struct('rho_100_kg_m3', rho0, 'mass_mobility_exponent', 3);
    if isfield(setting, 'relation'), relation = setting.relation; end
    if ~isstruct(relation) || ~isscalar(relation) || ...
            ~isfield(relation, 'rho_100_kg_m3') || ...
            ~isfield(relation, 'mass_mobility_exponent') || ...
            ~positive_scalar(relation.rho_100_kg_m3) || ...
            ~positive_scalar(relation.mass_mobility_exponent) || ...
            relation.mass_mobility_exponent <= 2 || ...
            relation.mass_mobility_exponent > 3
        fail('Relation', 'Require rho_100_kg_m3 and 2 < Dm <= 3.');
    end
    dm_aac = [mobility_diameter(da(1), relation, temp, pressure, cfg), ...
        mobility_diameter(da(2), relation, temp, pressure, cfg)];
    lo = max(result.dma.d_min_m, dm_aac(1));
    hi = min(result.dma.d_max_m, dm_aac(2));
    empty = ~(lo < hi);
    if empty, lo = NaN; hi = NaN; end
    result.tandem = struct('dm_min_m', lo, 'dm_max_m', hi, ...
        'aac_dm_min_m', dm_aac(1), 'aac_dm_max_m', dm_aac(2), ...
        'empty', empty, 'relation', relation, ...
        'inside', screen(setting, 'dm_m', [lo, hi]));
end
end

function check_flow(qsh, limits, key)
% "check_flow" refuses a sheath flow outside its inclusive limits (m3/s).
bounds = limit_pair(limits, key);
slack = 1e-12; % relative, for the round-off of the unit conversion
if qsh < bounds(1) * (1 - slack) || qsh > bounds(2) * (1 + slack)
    fail('Flows', sprintf( ...
        'The sheath flow must lie between %.4g and %.4g L/min.', ...
        bounds(1) * 60000, bounds(2) * 60000));
end
end

function dm = mobility_diameter(da, relation, temp, pressure, cfg)
% "mobility_diameter" brackets dm where RHO_EFF(da, dm) meets the relation.
% The residual falls with dm for 2 < Dm <= 3, so one sign change exists.
rho = @(dm) relation.rho_100_kg_m3 * ...
    (dm / 100e-9) .^ (relation.mass_mobility_exponent - 3);
residual = @(dm) log(INV.RHO_EFF(da, dm, temp, pressure, cfg)) - ...
    log(rho(dm));
lo = da;
hi = da;
try
    for k = 1:30
        r = residual([lo, hi]);
        if r(1) > 0 && r(2) < 0, break; end
        if r(1) <= 0, lo = lo / 10; end
        if r(2) >= 0, hi = hi * 10; end
    end
    if ~(r(1) > 0 && r(2) < 0)
        fail('Relation', 'No mobility diameter matches the relation.');
    end
    % Narrowing the bracket 32 times per pass on a logarithmic grid
    for iteration = 1:24
        nodes = exp(linspace(log(lo), log(hi), 33));
        r = residual(nodes);
        k = find(r <= 0, 1);
        if isempty(k), k = numel(nodes); end
        k = max(k, 2);
        lo = nodes(k - 1);
        hi = nodes(k);
        if hi - lo <= 4 * eps(hi), break; end
    end
catch err
    if startsWith(err.identifier, 'sootMosaic:OP_RANGE:'), rethrow(err); end
    fail('Relation', err.message);
end
dm = sqrt(lo * hi);
end

function [r1, r2, len] = annulus(geometry, prefix)
% "annulus" reads the inner and outer radius and the length (m).
names = strcat(prefix, {'_inner_radius_m', '_outer_radius_m', '_length_m'});
values = zeros(1, 3);
for k = 1:3
    if ~isfield(geometry, names{k}) || ~positive_scalar(geometry.(names{k}))
        fail('Geometry', ['The ' upper(prefix) ' geometry is unavailable.']);
    end
    values(k) = geometry.(names{k});
end
r1 = values(1);
r2 = values(2);
len = values(3);
if r2 <= r1, fail('Geometry', 'The outer radius must exceed the inner.'); end
end

function value = limit_pair(limits, key)
% "limit_pair" reads an increasing pair of positive operating limits.
value = line_pair(limits, key);
if any(value <= 0) || value(2) <= value(1)
    fail('Limits', ['Limits must be positive and increasing: ' key]);
end
end

function value = line_pair(limits, key)
% "line_pair" reads two finite values from the operating limits.
value = [];
if isfield(limits, key), value = limits.(key); end
if isempty(value)
    fail('MissingLimits', ['The operating limit is unavailable: ' key]);
end
if ~isnumeric(value) || ~isreal(value) || numel(value) ~= 2 || ...
        any(~isfinite(value(:)))
    fail('Limits', ['Two finite values are required: ' key]);
end
value = double(value(:).');
end

function inside = screen(setting, key, bounds)
% "screen" flags setpoints inside the closed range (m).
inside = [];
if ~isfield(setting, key), return; end
x = setting.(key);
if ~isnumeric(x) || ~isreal(x) || isempty(x) || ...
        any(~isfinite(x(:))) || any(x(:) <= 0)
    fail('Setpoints', ['Setpoints must be positive and finite: ' key]);
end
inside = x >= bounds(1) & x <= bounds(2);
end

function value = positive_field(setting, key, reason)
% "positive_field" reads a required positive finite scalar.
if ~isfield(setting, key) || ~positive_scalar(setting.(key))
    fail(reason, ['A positive finite scalar is required: ' key]);
end
value = double(setting.(key));
end

function yes = positive_scalar(value)
yes = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value > 0;
end

function fail(reason, message)
error(['sootMosaic:OP_RANGE:' reason], '%s', message);
end
