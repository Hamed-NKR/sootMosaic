function [grid, info] = GRID_RULE(obs, cfg, rho_kg_m3, draw, aac_setpoints_m)
% "GRID_RULE" selects diameter support from expected-count kernel columns.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     obs: Route A observation with sample_volume_cm3 for the support test
%     cfg: Resolved scan settings, nozzle registry and grid rules
%     rho_kg_m3: Condition density, scalar or function of mobility size (m)
%     draw: Optional physical kernel draw, as for KERNEL_1D
%     aac_setpoints_m: Optional aerodynamic setpoints for a 2D partial grid
% Outputs:
%     grid: Log grid (nm), or partial [da dm] grid with density bounds
%     info: Impactor, separate cut and sharpness cases, support diagnostic...
%         ...and reporting bands (m). A floor never removes kernel cells
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Sec. 2.2, Eqs. 23 and 28);
%     ...Johnson et al. (2018, Eqs. 1 and 7); 3082 manual (2016, Eq. B-1,...
%     ...Table 2-10). Support and convergence rules are described in...
%     ...config/main_inv/DEFAULTS.md, sections 7 and 12.

if nargin < 4, draw = struct(); end
if nargin < 5, aac_setpoints_m = []; end
require_recorded(cfg, {'instruments.impactor_nozzle_cm', ...
    'instruments.impactor_flow_lpm', 'scan.impactor_d50_nm', ...
    'scan.window_min_nm', 'scan.window_max_nm', ...
    'scan.dma_temperature_deg_c', 'scan.dma_pressure_kpa'}, 'GRID_RULE');
if ~strcmp(cfg.grid.range_rule, 'kernel_support') || ...
        ~isempty(cfg.grid.d_min_nm) || ~isempty(cfg.grid.d_max_nm)
    fail('RangeRule', 'Grid limits are selected from kernel support.');
end
[c, physical_draw] = kernel_settings(cfg, draw, 'GRID_RULE');
nozzle_m = positive(c.si.instruments.impactor_nozzle_cm, 'nozzle');
flow = positive(c.si.instruments.impactor_flow_lpm, 'impactor flow');
logged = positive(c.si.scan.impactor_d50_nm, 'logged impactor D50');
t = positive(c.si.scan.dma_temperature_deg_c, 'temperature');
p = positive(c.si.scan.dma_pressure_kpa, 'pressure');
if ~isfield(c.si, 'impactor_entry') || isempty(c.si.impactor_entry)
    fail('Nozzle', 'The recorded nozzle has no complete registry entry.');
end
entry = c.si.impactor_entry.constants;
if ~isscalar(entry.nozzle_cm) || abs(entry.nozzle_cm-nozzle_m) > 1e-12
    fail('Nozzle', 'The resolved nozzle and registry entry disagree.');
end
if ~isfield(entry, 'stk50') || numel(entry.flow_range_lpm) ~= 2 || ...
        any(~isfinite(entry.flow_range_lpm)) || any(entry.flow_range_lpm <= 0)
    fail('Nozzle', 'Require the published nozzle flow range and Stk50.');
end
[mu, ~, ~, params] = INV.GAS(t, p, [], c);
% Solving Eq. B-1 with slip at the aerodynamic diameter
target = 9*pi*mu*nozzle_m^3*entry.stk50 / ...
    (4*params.constants.rho_aero_ref_kg_m3*flow);
lo = 1e-10;
hi = 1e-2;
for k = 1:80
    mid = sqrt(lo*hi);
    [~, ~, cc] = INV.GAS(t, p, mid, c);
    if mid^2*cc < target, lo = mid; else, hi = mid; end
end
d50 = sqrt(lo*hi);
sharpness = positive(cfg.penetration.impactor_sharpness_1, 'impactor sharpness');
impactor = struct('d50_m', d50, 'cut_factor_1', 1, ...
    'sharpness_1', sharpness, 'rho_kg_m3', rho_kg_m3);
outside = flow < entry.flow_range_lpm(1) || flow > entry.flow_range_lpm(2);
cases = repmat(impactor, 1, 4*outside);
if outside
    cut = cfg.penetration.impactor_cut_factor_range;
    sharp = cfg.penetration.impactor_sharpness_range;
    if numel(cut) ~= 2 || numel(sharp) ~= 2 || ...
            any(~isfinite([cut(:); sharp(:)])) || any([cut(:); sharp(:)] <= 0)
        fail('Sensitivity', 'Require two positive cut and sharpness endpoints.');
    end
    cases(1).cut_factor_1 = cut(1);
    cases(2).cut_factor_1 = cut(2);
    cases(3).sharpness_1 = sharp(1);
    cases(4).sharpness_1 = sharp(2);
end
window = [positive(cfg.si.scan.window_min_nm, 'window minimum'), ...
    positive(cfg.si.scan.window_max_nm, 'window maximum')];
if window(2) <= window(1), fail('Window', 'Window limits must increase.'); end
ppd = positive(cfg.grid.points_per_decade, 'grid resolution');
if ~isempty(aac_setpoints_m)
    ppd = positive(cfg.grid.grid2d_points_per_decade, '2D resolution');
end
tol = positive(cfg.grid.support_threshold, 'support threshold');
if tol >= 1, fail('Threshold', 'Support threshold must be below one.'); end
if ~isfield(obs, 'sample_volume_cm3') || ...
        numel(obs.sample_volume_cm3) ~= numel(obs.values)
    fail('Exposure', 'The support test requires the original bin exposures.');
end
probe_obs = obs;
% Preserving the raw-route guard before using expected-count support
if ~isfield(obs, 'reduced') || ~isequal(obs.reduced, false) || ...
        ~isfield(obs, 'route') || ~strcmp(obs.route, 'A') || ...
        ~any(strcmp(obs.quantity, {'raw counts', 'raw concentration'}))
    fail('ReducedObservation', 'Kernel support requires a raw route A observation.');
end
probe_obs.quantity = 'raw counts';
probe_obs.values = zeros(size(obs.values));
support_impactor = impactor;
if ~isempty(aac_setpoints_m)
    support_impactor.rho_kg_m3 = min(cfg.grid.rho_bounds_kg_m3);
end
low_log = floor(log10(window(1)*1e9)*ppd)/ppd-0.3;
high_log = ceil(log10(window(2)*1e9)*ppd)/ppd+0.6;
resolved = false;
for attempt = 1:12
    centers = 10.^(low_log:(1/ppd):high_log);
    candidate = INV.Grid({centers});
    a = INV.KERNEL_1D(candidate, probe_obs, cfg, support_impactor, draw);
    signal = sum(a, 1);
    peak = max(signal);
    if ~isfinite(peak) || peak <= 0
        fail('NoSupport', 'The expected-count kernel has no positive support.');
    end
    signals = zeros(numel(cases)+1, numel(signal));
    signals(1, :) = signal;
    nominal = kernel_impactor(candidate.elements*1e-9, [], c, ...
        support_impactor, 'GRID_RULE');
    for j = 1:numel(cases)
        variant = cases(j);
        variant.rho_kg_m3 = support_impactor.rho_kg_m3;
        penetration = kernel_impactor(candidate.elements*1e-9, [], c, ...
            variant, 'GRID_RULE');
        signals(j+1, :) = signal.*(penetration./nominal).';
    end
    active = signal > tol*peak;
    first = find(active, 1);
    last = find(active, 1, 'last');
    pad = max(2, ceil(0.3*ppd));
    lower_ok = first >= 3;
    upper_ok = last <= numel(centers)-pad;
    for j = 2:size(signals, 1)
        case_peak = max(signals(j, :));
        if ~isfinite(case_peak) || case_peak <= 0
            fail('NoSupport', 'An impactor case has no finite positive support.');
        end
        use = signals(j, :) > tol*case_peak;
        lower_ok = lower_ok && find(use, 1) >= 3;
        upper_ok = upper_ok && find(use, 1, 'last') <= numel(centers)-pad;
    end
    if lower_ok && upper_ok
        resolved = true;
        break;
    end
    if ~lower_ok, low_log = low_log-0.3; end
    if ~upper_ok, high_log = high_log+0.6; end
end
if ~resolved, fail('SupportSearch', 'Support did not close within the search range.'); end
selected = first-1:last+1;
grid = INV.Grid({centers(selected)});
support_nm = centers([first, last]);
case_grids = cell(numel(cases), 1);
for j = 1:numel(cases)
    use = signals(j+1, :) > tol*max(signals(j+1, :));
    ids = find(use, 1)-1:find(use, 1, 'last')+1;
    case_grids{j} = INV.Grid({centers(ids)});
end
density = [];
if ~isempty(aac_setpoints_m)
    if ~isnumeric(aac_setpoints_m) || ~isreal(aac_setpoints_m) || ...
            any(~isfinite(aac_setpoints_m(:)) | aac_setpoints_m(:) <= 0)
        fail('AACRange', 'Require positive aerodynamic setpoints.');
    end
    da_span = aac_extent(aac_setpoints_m(:), c, physical_draw);
    na = max(2, ceil(log10(da_span(2)/da_span(1))*ppd)+1);
    full = INV.Grid({logspace(log10(da_span(1)*1e9), ...
        log10(da_span(2)*1e9), na), grid.edges{1}});
    s = c.si.scan;
    density = INV.RHO_EFF(full.elements(:, 1)*1e-9, ...
        full.elements(:, 2)*1e-9, s.aac_temperature_deg_c, s.aac_pressure_kpa, c);
    bounds = cfg.grid.rho_bounds_kg_m3;
    if numel(bounds) ~= 2 || any(~isfinite(bounds)) || ...
            bounds(1) <= 0 || bounds(2) <= bounds(1)
        fail('DensityBounds', 'Require positive increasing density bounds.');
    end
    grid = full.partial(density >= bounds(1) & density <= bounds(2));
end
floor_m = cfg.si.report.d_floor_nm;
if isempty(floor_m), floor_m = window(1); end
if ~isscalar(floor_m) || ~isfinite(floor_m) || ...
        floor_m < window(1) || floor_m >= window(2)
    fail('Floor', 'The reporting floor must lie inside the scan window.');
end
cap = positive(cfg.si.report.d_cap_nm, 'reporting cap');
info = struct('impactor', impactor, 'sensitivity_cases', cases, ...
    'sensitivity_mobility_grids', {case_grids}, ...
    'outside_nozzle_range_1', outside, 'd50_relative_difference_1', d50/logged-1, ...
    'd50_mismatch_1', abs(d50/logged-1) > cfg.checks.impactor_d50_rel_tol, ...
    'support_centers_nm', support_nm, 'probe_centers_nm', centers, ...
    'relative_column_sum_1', signal/peak, ...
    'window_band_m', [floor_m, window(2)], ...
    'above_window_band_m', [window(2), max(window(2), cap)], ...
    'tail_band_m', [window(2), grid.edges{end}(end)*1e-9], ...
    'full_density_kg_m3', density, 'article_floor_m', window(1));
end

function span = aac_extent(setpoints, c, draw)
% Mapping the transfer half widths in relaxation time to diameter
require_recorded(c, {'scan.aac_temperature_deg_c', 'scan.aac_pressure_kpa', ...
    'scan.aac_sample_flow_lpm', 'scan.aac_sheath_flow_lpm'}, 'GRID_RULE');
s = c.si.scan;
ends = [min(setpoints), max(setpoints)]*draw.aac_sizing_scale_1;
span = zeros(1, 2);
for j = 1:2
    [mu, ~, cc, params] = INV.GAS(s.aac_temperature_deg_c, ...
        s.aac_pressure_kpa, ends(j), c);
    tau = params.constants.rho_aero_ref_kg_m3*ends(j)^2*cc/(18*mu);
    [~, meta] = INV.TFER_AAC(tau, ends(j), ends(j), c, 'grid extent', ...
        1, draw.aac_width_scale_1);
    target = tau*(1+(2*j-3)*meta.beta/meta.width_factor);
    if target <= 0, fail('AACRange', 'AAC lower half width reaches zero relaxation time.'); end
    lo = ends(j)/100;
    hi = ends(j)*100;
    for k = 1:80
        mid = sqrt(lo*hi);
        [~, ~, cm] = INV.GAS(s.aac_temperature_deg_c, s.aac_pressure_kpa, mid, c);
        value = params.constants.rho_aero_ref_kg_m3*mid^2*cm/(18*mu);
        if value < target, lo = mid; else, hi = mid; end
    end
    span(j) = sqrt(lo*hi);
end
end

function value = positive(value, label)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    fail('Input', ['Require a positive ' label '.']);
end
end

function fail(reason, message)
error(['sootMosaic:GRID_RULE:' reason], '%s', message);
end
