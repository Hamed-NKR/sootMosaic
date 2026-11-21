function report = GRID_CONVERGE(grid, evaluate, cfg)
% "GRID_CONVERGE" checks statistic and interval changes on altered grids.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     grid: Configured log INV.Grid or INV.PartialGrid in (nm)
%     evaluate: Function handle result = evaluate(grid, source), where...
%         ...source is expected or measured. Each result has value and sd...
%         ...vectors for the same reported statistics. Expected data stay...
%         ...fixed at the fitted physical solution across all grids; each...
%         ...evaluation refits the inversion and its regularization
%     cfg: Resolved grid tolerances and AAC state for 2D density masks
% Outputs:
%     report: Separate resolution and extent changes, pass flags and...
%         ...the grids. A failure never removes channels or changes data
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Sec. 2.2); resolution and extent...
%     ...changes compared with a quarter of the posterior SD and the...
%     ...relative SD tolerance (config/main_inv/DEFAULTS.md, section 7).

if ~isa(grid, 'INV.Grid') || ~strcmp(grid.discrete, 'log') || ...
        ~isa(evaluate, 'function_handle') || ~strcmp(cfg.grid.resolution_rule, 'converged')
    fail('Input', 'Require a log grid, evaluation callback and converged rule.');
end
factor = cfg.grid.refine_factor;
step = cfg.grid.extent_step_decades;
tol = cfg.grid.statistic_tol_sd;
sd_tol = cfg.grid.sd_rel_tol;
values = [factor, step, tol, sd_tol];
if numel(values) ~= 4 || any(~isfinite(values)) || factor <= 1 || ...
        step <= 0 || tol <= 0 || sd_tol <= 0
    fail('Tolerance', 'Require positive tolerances and refinement above one.');
end
fine_centers = cell(1, grid.dim);
wide_centers = cell(1, grid.dim);
for j = 1:grid.dim
    center = log10(grid.edges{j});
    bounds = log10(grid.nodes{j});
    % Keeping quadrature boundaries fixed for the resolution comparison
    n = ceil(numel(center)*factor);
    h = (bounds(end)-bounds(1))/n;
    fine_centers{j} = 10.^(bounds(1)+h*((1:n)-0.5));
    h = (center(end)-center(1))/(numel(center)-1);
    wide_centers{j} = 10.^(center(1)+h*(-1:numel(center)-1+ceil(step/h)));
end
fine = mask_grid(INV.Grid(fine_centers), cfg);
wide = mask_grid(INV.Grid(wide_centers), cfg);
sources = {'expected', 'measured'};
result = cell(2, 1);
for j = 1:2
    base = checked(evaluate(grid, sources{j}));
    rf = checked(evaluate(fine, sources{j}));
    rw = checked(evaluate(wide, sources{j}));
    if numel(base.value) ~= numel(rf.value) || numel(base.value) ~= numel(rw.value)
        fail('StatisticShape', 'Every evaluation must return the same statistics.');
    end
    resolution = compare(base, rf, tol, sd_tol);
    extent = compare(base, rw, tol, sd_tol);
    result{j} = struct('source', sources{j}, 'base', base, ...
        'resolution', resolution, 'extent', extent, ...
        'pass', resolution.pass && extent.pass);
end
report = struct('pass', result{1}.pass && result{2}.pass, ...
    'comparisons', {result}, 'fine_grid', fine, 'wide_grid', wide, ...
    'statistic_tol_sd', tol, 'sd_rel_tol', sd_tol);
end

function g = mask_grid(g, cfg)
if g.dim == 1, return; end
s = cfg.si.scan;
rho = INV.RHO_EFF(g.elements(:, 1)*1e-9, g.elements(:, 2)*1e-9, ...
    s.aac_temperature_deg_c, s.aac_pressure_kpa, cfg);
bounds = cfg.grid.rho_bounds_kg_m3;
g = g.partial(rho >= bounds(1) & rho <= bounds(2));
end

function result = checked(result)
if ~isstruct(result) || ~isscalar(result) || ...
        ~isfield(result, 'value') || ~isfield(result, 'sd') || ...
        ~isnumeric(result.value) || ~isreal(result.value) || ...
        ~isnumeric(result.sd) || ~isreal(result.sd) || ...
        ~isvector(result.value) || ~isvector(result.sd) || ...
        numel(result.value) ~= numel(result.sd) || ...
        any(~isfinite(result.value(:))) || any(~isfinite(result.sd(:))) || ...
        any(result.sd(:) <= 0)
    fail('Statistic', 'Require finite statistic values and positive posterior SDs.');
end
result.value = result.value(:);
result.sd = result.sd(:);
end

function result = compare(base, other, tol, sd_tol)
shift = abs(other.value-base.value)./base.sd;
sd_change = abs(other.sd./base.sd-1);
result = struct('shift_sd', shift, 'sd_change_1', sd_change, ...
    'value', other.value, 'sd', other.sd, ...
    'pass', all(shift < tol) && all(sd_change < sd_tol));
end

function fail(reason, message)
error(['sootMosaic:GRID_CONVERGE:' reason], '%s', message);
end
