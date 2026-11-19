function result = BAYESF(a, b, grid, opts)
% "BAYESF" selects a shared prior family and integrates its scale evidence.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Whitened kernel (cm^3) and column observation (-), or matching...
%         ...cell vectors for independent scans of one instrument mode....
%         ...Use OBS_VARIANCE weight variances before calling this function
%     grid: INV.Grid, diameter vector (nm), or cell count; one shared...
%         ...grid or a cell vector matching the scans
%     opts: Optional scalar structure with the following fields
%     families_1: Cell vector from tk0, tk1, tk2, exp (-). Defaults to...
%         ...all four in 1D with diameters, tk1/tk2 in 2D, tk0/tk1/tk2...
%         ...with only a cell count. All scans must support every family
%     length_grid_decades: Distinct positive lengths, default 20 values...
%         ...linearly spaced from 0.05 to 1 (decades)
%     lambda_ratio_1: Increasing relative scale grid, default...
%         ...logspace(-8, 3, 111), relative to each prior's lambda_ref (-)
%     max_widen_count: Two-decade extensions allowed per side, default 6
%     max_refine_count: Midpoint refinements per support, default 6
%     posterior_tol_1: Moment and quantile change / SD, default 0.01 (-)
%     width_flag_decades: D2 threshold, default 0.5 (decades)
% Outputs:
%     result: Curves per scan/family/length, normalized lambda and length...
%         ...probabilities, integrated and pooled family scores, selected...
%         ...nonnegative modes and cross-checks. All log scores refer to...
%         ...whitened data and omit the common whitening Jacobian
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 30-34).
% Adopted from +invert/bayesf_precomp.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: documented package solvers, zero-mean proper priors,
%     ...unconstrained evidence and a separate nonnegative reported mode.
% Modified 19 Nov 2026: prior-whitened singular values replace GSVD index...
%     ...assumptions; log ratios retain null data directions and constants.
% Modified 19 Nov 2026: singular-vector fit with orthogonal residuals...
%     ...evaluates evidence without augmented-system rank tests.
% Modified 19 Nov 2026: normalized log-scale quadrature, length averaging,
%     ...pooled family scores, widening, refinement and tail diagnostics.
% Modified 19 Nov 2026: unit-bearing fields, validation, report curves and...
%     ...quiet cross-check calls. No dialogs or data-based stage-two prior.
% Evidence is conditional on estimated weights and their reference scale.
% Conditional probabilities at each length multiply length_probability_1...
%     ...before POST_MIX; selected_1 is a point diagnostic, not that mixture.

if nargin < 3 || isempty(grid)
    if iscell(a)
        grid = cellfun(@(v) size(v, 2), a, 'UniformOutput', false);
    else
        grid = size(a, 2);
    end
end
if nargin < 4, opts = struct; end
if ~iscell(a), a = {a}; end
if ~iscell(b), b = {b}; end
if ~isvector(a) || isempty(a) || ~isvector(b) || numel(a) ~= numel(b)
    fail('Shape', 'Require one kernel and column observation per scan.');
end
ns = numel(a);
if ~iscell(grid), grid = repmat({grid}, ns, 1); end
if ~isvector(grid) || numel(grid) ~= ns
    fail('Grid', 'Require one grid per scan.');
end
opts = options(opts, grid{1});
nf = numel(opts.families_1);
curves = cell(ns, nf);
scores = zeros(ns, nf);
resolved = false(ns, nf);
for i = 1:ns
    if ~isnumeric(a{i}) || ~isreal(a{i}) || ~ismatrix(a{i}) || ...
            isempty(a{i}) || any(~isfinite(a{i}(:))) || ...
            ~isnumeric(b{i}) || ~isreal(b{i}) || ...
            ~isequal(size(b{i}), [size(a{i}, 1), 1]) || ...
            any(~isfinite(b{i})) || norm(a{i}, 'fro') == 0
        fail('Input', 'Require finite compatible data and a nonzero kernel.');
    end
    a{i} = double(a{i}); b{i} = double(b{i});
    if isnumeric(grid{i}), grid{i} = double(grid{i}); end
    for f = 1:nf
        family = opts.families_1{f};
        lengths = NaN;
        if strcmp(family, 'exp'), lengths = opts.length_grid_decades; end
        parts = cell(numel(lengths), 1);
        for k = 1:numel(lengths)
            l = prior(family, lengths(k), grid{i}, size(a{i}, 2));
            parts{k} = integrate(a{i}, b{i}, l, opts);
            parts{k}.length_decades = lengths(k);
        end
        c = vertcat(parts{:});
        logs = [c.log_integral_1]';
        total = logsum(logs);
        scores(i, f) = total-log(numel(c));
        for k = 1:numel(c)
            c(k).length_probability_1 = exp(logs(k)-total);
            c(k).joint_probability_1 = ...
                c(k).posterior_probability_1*c(k).length_probability_1;
        end
        curves{i, f} = c;
        resolved(i, f) = all([c.interior_1] & [c.refined_1]);
    end
end
pooled = sum(scores, 1);
[~, chosen] = max(pooled);
probability = zeros(ns, nf);
selected = cell(ns, 1);
for i = 1:ns
    probability(i, :) = exp(scores(i, :)-logsum(scores(i, :)));
    c = curves{i, chosen};
    [~, k] = max(arrayfun(@(v) max(v.log_evidence_1), c));
    [~, j] = max(c(k).log_evidence_1);
    lambda = c(k).lambda_cm3(j);
    family = opts.families_1{chosen};
    if strcmp(family, 'exp')
        [x, last_l, precision] = INV.EXP_DIST(a{i}, b{i}, lambda, ...
            c(k).length_decades, grid{i});
    else
        g = solver_grid(grid{i}, size(a{i}, 2));
        [x, last_l, precision] = INV.TIKHONOV(a{i}, b{i}, lambda, ...
            str2double(family(end)), g, 1);
    end
    covariance = INV.POSTERIOR(a{i}, last_l);
    l = prior(family, c(k).length_decades, grid{i}, size(a{i}, 2));
    checks = INV.LAMBDA_XCHECK(a{i}, b{i}, l, c(k).lambda_cm3);
    log_lambda = vertcat(c.log10_lambda_1);
    weights = vertcat(c.joint_probability_1);
    center = sum(weights.*log_lambda);
    width = sqrt(sum(weights.*(log_lambda-center).^2));
    selected{i} = struct('lambda_cm3', lambda, ...
        'length_decades', c(k).length_decades, 'map_cm3_inv', x, ...
        'last_l_cm3', last_l, 'precision_cm6', precision, ...
        'covariance_cm6_inv', covariance, 'xcheck_1', checks, ...
        'lambda_sd_decades', width, ...
        'd2_flag_1', width > opts.width_flag_decades, ...
        'd1_flag_1', any([c.widen_count] > 0) || any(~[c.interior_1]), ...
        'resolved_1', all([c.interior_1] & [c.refined_1]));
end
result = struct('families_1', {opts.families_1}, 'curves_1', {curves}, ...
    'family_log_evidence_1', scores, 'pooled_log_evidence_1', pooled, ...
    'family_probability_1', probability, ...
    'family_resolved_1', resolved, 'pooled_resolved_1', all(resolved(:)), ...
    'selected_family_index_1', chosen, ...
    'selected_family_1', opts.families_1{chosen}, ...
    'selected_1', {selected}, 'options_1', opts);
end

function c = integrate(a, b, l, opts)
[~, r] = qr(full(l), 0);
if rcond(r) <= eps, fail('Prior', 'Require a proper full-rank prior.'); end
[u, s, ~] = svd(full(a/r), 'econ');
m = size(a, 1);
k = min(size(a));
s = diag(s(1:k, 1:k));
u = u(:, 1:k);
y = u'*b;
q = norm(b-u*y)^2;
if k == m, q = 0; end
reference = norm(a, 'fro')/norm(l, 'fro');
z = log10(reference)+log10(opts.lambda_ratio_1(:));
step = max(diff(z));
widen = [0, 0];
rounds = 0;
while true
    [e, fit, credence] = evaluate(s, y, q, m, z);
    [left, right] = boundary(e);
    [next_z, widen, changed] = extend_grid(z, step, left, right, ...
        widen, opts.max_widen_count);
    if changed, z = next_z; continue; end
    [p, integral, moments] = quadrature(z, e);
    refined = false;
    for k = 1:opts.max_refine_count
        old = moments;
        mid = (z(1:end-1)+z(2:end))/2;
        [em, fm, cm] = evaluate(s, y, q, m, mid);
        refined_grid = zeros(2*numel(z)-1, 4);
        refined_grid(1:2:end, :) = [z, e, fit, credence];
        refined_grid(2:2:end, :) = [mid, em, fm, cm];
        z = refined_grid(:, 1); e = refined_grid(:, 2);
        fit = refined_grid(:, 3); credence = refined_grid(:, 4);
        [p, integral, moments] = quadrature(z, e);
        rounds = rounds+1;
        if max(abs(moments-old)) <= opts.posterior_tol_1*moments(2)
            refined = true;
            break
        end
    end
    [left, right] = boundary(e);
    [next_z, widen, changed] = extend_grid(z, step, left, right, ...
        widen, opts.max_widen_count);
    if ~changed, break; end
    z = next_z;
end
[left, right] = boundary(e);
interior = ~left && ~right;
% Integrating the two adjacent decades without changing the support
nt = max(2, ceil(1/max(diff(z))));
zl = linspace(z(1)-1, z(1), nt+1)';
zr = linspace(z(end), z(end)+1, nt+1)';
el = evaluate(s, y, q, m, zl);
er = evaluate(s, y, q, m, zr);
[~, il] = quadrature(zl, el);
[~, ir] = quadrature(zr, er);
core = integral+log(z(end)-z(1));
tails = logsum([il; ir]);
tail_mass = exp(tails-logsum([core; tails]));
nominal = evaluate(s, y, q, m, log10(reference));
c = struct('lambda_ref_cm3', reference, 'lambda_cm3', 10.^z, ...
    'log10_lambda_1', z, 'log_evidence_1', e, 'fit_1', fit, ...
    'credence_1', credence, 'log_bayes_factor_1', e-nominal, ...
    'posterior_probability_1', p, 'log_integral_1', integral, ...
    'log10_lambda_mean_1', moments(1), 'lambda_sd_decades', moments(2), ...
    'log10_lambda_quantiles_1', moments(3:4), ...
    'support_cm3', 10.^[z(1), z(end)], 'tail_mass_1', tail_mass, ...
    'widen_count', sum(widen), 'refine_count', rounds, ...
    'interior_1', interior, 'refined_1', refined);
end

function [z, widen, changed] = extend_grid(z, step, left, right, widen, limit)
side = 0;
if right && widen(2) < limit
    side = 2;
elseif left && widen(1) < limit
    side = 1;
end
changed = side ~= 0;
if ~changed, return; end
count = max(2, ceil(2/step));
extended = zeros(numel(z)+count, 1);
if side == 1
    extended(1:count) = z(1)-2+(0:count-1)'*2/count;
    extended(count+1:end) = z;
else
    extended(1:numel(z)) = z;
    extended(numel(z)+1:end) = z(end)+(1:count)'*2/count;
end
widen(side) = widen(side)+1;
z = extended;
end

function [e, fit, credence] = evaluate(s, y, q, m, z)
fit = zeros(numel(z), 1);
credence = fit;
for j = 1:numel(z)
    lambda = 10^z(j);
    if ~isfinite(lambda) || lambda <= 0
        fail('Scale', 'Search exceeded finite positive scales.');
    end
    fit(j) = -0.5*(q + norm((lambda./hypot(s, lambda)).*y)^2);
    d = log(s)-log(lambda);
    credence(j) = -sum(max(d, 0)+log1p(exp(-2*abs(d)))/2);
end
e = fit+credence-m*log(2*pi)/2;
if any(~isfinite(e)), fail('Evidence', 'Evidence must remain finite.'); end
end

function [p, integral, moments] = quadrature(z, e)
dz = diff(z);
weights = [dz(1); dz(1:end-1)+dz(2:end); dz(end)]/2;
scaled = exp(e-max(e));
mass = weights.*scaled;
p = mass/sum(mass);
integral = max(e)+log(sum(mass))-log(z(end)-z(1));
center = sum(p.*z);
width = sqrt(sum(p.*(z-center).^2));
% Inverting the piecewise-linear density within each integration cell
segments = dz.*(scaled(1:end-1)+scaled(2:end))/2;
cdf = [0; cumsum(segments)]/sum(segments);
q = zeros(1, 2);
levels = [0.025, 0.975];
for k = 1:2
    j = find(cdf(2:end) >= levels(k), 1);
    target = (levels(k)-cdf(j))*sum(segments)/dz(j);
    v = scaled(j);
    slope = scaled(j+1)-v;
    root = sqrt(max(0, v^2+2*slope*target));
    if v+root > 0, fraction = 2*target/(v+root); else, fraction = 0; end
    q(k) = z(j)+dz(j)*min(1, max(0, fraction));
end
moments = [center, width, q];
end

function l = prior(family, length_decades, grid, n)
if strcmp(family, 'exp')
    if isnumeric(grid) && isscalar(grid)
        fail('Grid', 'Exponential lengths require diameter coordinates.');
    end
    l = INV.EXP_DIST_LPR(length_decades, grid);
else
    l = INV.TIKHONOV_LPR(str2double(family(end)), solver_grid(grid, n));
end
if size(l, 2) ~= n, fail('Grid', 'Grid must match kernel columns.'); end
end

function g = solver_grid(grid, n)
g = grid;
if isnumeric(grid) && ~isscalar(grid)
    if ~isreal(grid) || ~isvector(grid) || numel(grid) ~= n || ...
            any(~isfinite(grid)) || any(grid <= 0) || ...
            any(diff(grid(:)) <= 0)
        fail('Grid', 'Require ordered positive diameter coordinates.');
    end
    spacing = diff(log10(grid(:)));
    if max(abs(spacing-spacing(1))) > 1e-10*max(1, abs(spacing(1)))
        fail('Grid', 'Difference priors require uniform log spacing.');
    end
    g = n;
end
end

function opts = options(opts, grid)
if ~isstruct(opts) || ~isscalar(opts)
    fail('Options', 'Use scalar options.');
end
families = {'tk0', 'tk1', 'tk2', 'exp'};
if isa(grid, 'INV.Grid') && grid.dim == 2
    families = {'tk1', 'tk2'};
elseif isnumeric(grid) && isscalar(grid)
    families = {'tk0', 'tk1', 'tk2'};
end
defaults = struct('families_1', {families}, ...
    'length_grid_decades', linspace(0.05, 1, 20), ...
    'lambda_ratio_1', logspace(-8, 3, 111), 'max_widen_count', 6, ...
    'max_refine_count', 6, 'posterior_tol_1', 0.01, ...
    'width_flag_decades', 0.5);
keys = fieldnames(opts);
if any(~ismember(keys, fieldnames(defaults)))
    fail('Options', 'Unknown regularization option.');
end
keys = fieldnames(defaults);
for k = 1:numel(keys)
    if ~isfield(opts, keys{k}), opts.(keys{k}) = defaults.(keys{k}); end
end
f = opts.families_1;
if ~iscell(f) || ~isvector(f) || isempty(f) || ...
        ~all(cellfun(@ischar, f)) || ...
        any(~ismember(f, {'tk0', 'tk1', 'tk2', 'exp'})) || ...
        numel(unique(f)) ~= numel(f)
    fail('Families', 'Require distinct supported prior families.');
end
for key = {'length_grid_decades', 'lambda_ratio_1'}
    value = opts.(key{1});
    if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
            isempty(value) || any(~isfinite(value)) || any(value <= 0) || ...
            any(diff(value(:)) <= 0)
        fail('Options', 'Require positive increasing grids.');
    end
    opts.(key{1}) = double(value);
end
if numel(opts.lambda_ratio_1) < 5
    fail('Options', 'Require at least five relative scales.');
end
for key = {'max_widen_count', 'max_refine_count'}
    value = opts.(key{1});
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value < 0 || value ~= fix(value)
        fail('Options', 'Require nonnegative integer iteration limits.');
    end
end
for key = {'posterior_tol_1', 'width_flag_decades'}
    value = opts.(key{1});
    if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
            ~isfinite(value) || value <= 0
        fail('Options', 'Require positive finite diagnostic thresholds.');
    end
end
end

function value = logsum(values)
peak = max(values(:));
value = peak+log(sum(exp(values(:)-peak)));
end

function [left, right] = boundary(e)
tolerance = 64*eps(max(1, max(abs(e))));
left = max(e(1:2)) >= max(e)-tolerance;
right = max(e(end-1:end)) >= max(e)-tolerance;
end

function fail(reason, message)
error(['sootMosaic:BAYESF:' reason], '%s', message);
end
