function result = GROUP_AVG(values, cfg, options)
% "GROUP_AVG" averages per-scan results of a group with their intervals.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     values: Per-scan statistics, one row per scan and one column per...
%         ...statistic, or a cell array of per-scan distributions, each a...
%         ...structure with increasing diameter_nm (nm) and values of the...
%         ...same size, with equal quantity and unit where given
%     cfg: Resolved +INV configuration with averaging.interval_level and...
%         ...averaging.support
%     options: Optional diameter_nm, target diameters inside the common...
%         ...support (nm), by default the first scan's diameters there....
%         ...shared_covariance, covariance of the group mean from...
%         ...calibration terms shared by every scan (squared value units)....
%         ...day, one label per scan, pools the days by random effects
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Mean, sample SD over all scans, the independent, shared and...
%         ...combined terms with degrees of freedom and coverage factors,...
%         ...the interval, the common diameters with the per-scan values...
%         ...on them, and the day summaries with the between-day variance
% ----------------------------------------------------------------------- %
% Method: two-sided Student t interval on n - 1 degrees of freedom of the...
%     ...actual scan count; DerSimonian and Laird (1986, Eqs. 2-4 and the...
%     ...moment estimate of the between-day variance, p. 183) when days are...
%     ...pooled, as named by Kiasadegh et al. (2026, Appendix); effective...
%     ...degrees of freedom of the combined term by Welch-Satterthwaite with...
%     ...the shared term taken as known (JCGM 100:2008, Eq. G.2b). Across...
%     ...days the interval is a Student t interval on the day count less...
%     ...one, an approximation for few days and not an exact coverage...
%     ...result of the random-effects estimate.
% Provenance: earlier averaging code was read as a model of the call...
%     ...layout for Student t group averages, no code text adopted.
% Reimplementation. Distributions are interpolated linearly in log(d) on...
%     ...the common support, with no extrapolation. Shared calibration...
%     ...terms enter the group mean once and are never divided by the scan...
%     ...count. No scan is padded, dropped or weighted.

if nargin < 2
    fail('Input', 'Pass the per-scan values and the configuration.');
end
if nargin < 3 || isempty(options), options = struct(); end
if ~isstruct(options) || ~isscalar(options) || any(~ismember( ...
        fieldnames(options), {'diameter_nm', 'shared_covariance', 'day'}))
    fail('Options', 'Unknown averaging option.');
end
try
    level = cfg.averaging.interval_level;
    support = cfg.averaging.support;
catch
    fail('Config', 'Pass a resolved inversion configuration.');
end
if ~isnumeric(level) || ~isreal(level) || ~isscalar(level) || ...
        ~(level > 0 && level < 1)
    fail('Level', 'The interval level must lie between 0 and 1.');
end
if ~(ischar(support) && strcmp(support, 'common'))
    fail('Support', 'Only the common support without extrapolation exists.');
end
result = struct('mode', 'statistics', 'combination', 'student_t', ...
    'level', level, 'n_scans', [], 'diameter_nm', [], 'support_nm', [], ...
    'scan_values', [], 'mean', [], 'sd', [], 'independent', [], ...
    'shared', [], 'combined', [], 'lower', [], 'upper', [], 'days', []);
if iscell(values)
    [x, d, span] = common_support(values, options);
    result.mode = 'distribution';
    result.diameter_nm = d;
    result.support_nm = span;
    result.scan_values = x;
else
    if isfield(options, 'diameter_nm')
        fail('Options', 'Target diameters apply to distributions only.');
    end
    x = values;
end
if ~isnumeric(x) || ~isreal(x) || ~ismatrix(x) || isempty(x) || ...
        any(~isfinite(x(:)))
    fail('Values', 'Per-scan values must be finite, one row per scan.');
end
x = double(x);
[n, p] = size(x);
if n < 2
    fail('TooFewScans', 'An interval needs at least two scans.');
end
result.n_scans = n;
shared = zeros(p);
if isfield(options, 'shared_covariance')
    shared = options.shared_covariance;
    if ~isnumeric(shared) || ~isreal(shared) || ...
            ~isequal(size(shared), [p p]) || any(~isfinite(shared(:)))
        fail('SharedCovariance', 'Require a finite p x p shared covariance.');
    end
    shared = double(shared);
    scale = max(realmin, norm(shared, 1));
    if norm(shared - shared.', 1) > 1e-12 * scale || ...
            min(eig((shared + shared.') / 2)) < -1e-12 * scale
        fail('SharedCovariance', ...
            'The shared covariance must be symmetric and nonnegative.');
    end
end
result.mean = mean(x, 1);
result.sd = std(x, 0, 1);

% Repeat term, Student t of the scan count or random effects over days
if isfield(options, 'day')
    [result.mean, u, result.days] = random_effects(x, options.day);
    result.combination = 'random_effects';
    nu = (numel(result.days.n) - 1) * ones(1, p);
    independent = struct('u', u, 'dof', nu, ...
        'factor', t_factor(level, nu), 'covariance', []);
else
    u = result.sd / sqrt(n);
    independent = struct('u', u, 'dof', (n - 1) * ones(1, p), ...
        'factor', t_factor(level, (n - 1) * ones(1, p)), ...
        'covariance', cov(x) / n);
end
independent.half_width = independent.factor .* u;
result.independent = independent;

% Shared term added once, Welch-Satterthwaite degrees of freedom
u_shared = sqrt(diag(shared)).';
result.shared = struct('u', u_shared, 'covariance', shared);
u_combined = sqrt(u .^ 2 + u_shared .^ 2);
dof = inf(1, p);
finite = u > 0 & isfinite(independent.dof);
dof(finite) = independent.dof(finite) .* ...
    (u_combined(finite) ./ u(finite)) .^ 4;
factor = t_factor(level, dof);
half_width = factor .* u_combined;
covariance = [];
if ~isempty(independent.covariance)
    covariance = independent.covariance + shared;
end
result.combined = struct('u', u_combined, 'dof', dof, 'factor', factor, ...
    'half_width', half_width, 'covariance', covariance);
result.lower = result.mean - half_width;
result.upper = result.mean + half_width;
end

function [x, target, span] = common_support(scans, options)
% "common_support" interpolates every scan onto diameters all scans cover.
n = numel(scans);
if n < 2, fail('TooFewScans', 'An interval needs at least two scans.'); end
d = cell(n, 1);
y = cell(n, 1);
for k = 1:n
    s = scans{k};
    if ~isstruct(s) || ~isscalar(s) || ~isfield(s, 'diameter_nm') || ...
            ~isfield(s, 'values')
        fail('Distribution', 'Each scan needs diameter_nm and values.');
    end
    d{k} = double(s.diameter_nm(:));
    y{k} = double(s.values(:));
    if ~isnumeric(s.diameter_nm) || ~isreal(s.diameter_nm) || ...
            numel(d{k}) < 2 || any(~isfinite(d{k})) || any(d{k} <= 0) || ...
            any(diff(d{k}) <= 0)
        fail('Diameters', 'Diameters must be positive and increasing.');
    end
    if ~isnumeric(s.values) || ~isreal(s.values) || ...
            numel(y{k}) ~= numel(d{k}) || any(~isfinite(y{k}))
        fail('Values', 'Values must be finite, one per diameter.');
    end
    for name = {'quantity', 'unit'}
        if isfield(s, name{1}) ~= isfield(scans{1}, name{1}) || ...
                (isfield(s, name{1}) && ...
                ~isequal(s.(name{1}), scans{1}.(name{1})))
            fail('Incompatible', ['Scans differ in ' name{1} '.']);
        end
    end
end
lo = max(cellfun(@(v) v(1), d));
hi = min(cellfun(@(v) v(end), d));
if ~(lo < hi)
    fail('NoCommonSupport', 'The scans share no diameter range.');
end
span = [lo, hi];
if isfield(options, 'diameter_nm')
    target = options.diameter_nm;
    if ~isnumeric(target) || ~isreal(target) || isempty(target) || ...
            any(~isfinite(target(:))) || any(target(:) <= 0) || ...
            any(diff(target(:)) <= 0)
        fail('Diameters', 'Target diameters must be positive and increasing.');
    end
    target = double(target(:));
    if any(target < lo | target > hi)
        fail('Extrapolation', 'Target diameters leave the common support.');
    end
else
    target = d{1}(d{1} >= lo & d{1} <= hi);
end
if numel(target) < 1
    fail('NoCommonSupport', 'No target diameter lies in the common support.');
end
x = zeros(n, numel(target));
for k = 1:n
    % Interpolating linearly in log(d), never outside the scan's range
    x(k, :) = interp1(log(d{k}), y{k}, log(target), 'linear').';
end
if any(~isfinite(x(:)))
    fail('Extrapolation', 'Target diameters leave the common support.');
end
target = target.';
end

function [mu, se, days] = random_effects(x, labels)
% "random_effects" pools day means with a between-day variance.
[n, p] = size(x);
if iscellstr(labels) || isstring(labels) || ...
        (isnumeric(labels) && isreal(labels))
    labels = string(labels(:));
else
    fail('Days', 'Day labels must be text or numbers, one per scan.');
end
if numel(labels) ~= n || any(ismissing(labels))
    fail('Days', 'Day labels must be text or numbers, one per scan.');
end
[names, ~, index] = unique(labels, 'stable');
k = numel(names);
if k < 2, fail('Days', 'Random effects need at least two days.'); end
counts = accumarray(index, 1);
if any(counts < 2)
    fail('DayScans', 'Each pooled day needs at least two scans.');
end
day_mean = zeros(k, p);
day_variance = zeros(k, p);
for j = 1:k
    rows = x(index == j, :);
    day_mean(j, :) = mean(rows, 1);
    day_variance(j, :) = var(rows, 0, 1) / counts(j);
end
if any(day_variance(:) <= 0)
    fail('DayVariance', 'Each day needs a positive within-day variance.');
end
w = 1 ./ day_variance;
fixed = sum(w .* day_mean, 1) ./ sum(w, 1);
q = sum(w .* (day_mean - fixed) .^ 2, 1);
tau2 = max(0, (q - (k - 1)) ./ (sum(w, 1) - sum(w .^ 2, 1) ./ sum(w, 1)));
w_star = 1 ./ (day_variance + tau2);
mu = sum(w_star .* day_mean, 1) ./ sum(w_star, 1);
se = 1 ./ sqrt(sum(w_star, 1));
days = struct('labels', {cellstr(names)}, 'n', counts.', ...
    'mean', day_mean, 'variance', day_variance, 'q', q, 'tau2', tau2, ...
    'weights', w_star);
end

function t = t_factor(level, dof)
% "t_factor" gives the two-sided Student t quantile at each dof.
% P(|T| > t) = I(nu/(nu + t^2); nu/2, 1/2), solved through its upper tail
t = zeros(size(dof));
alpha = 1 - level;
for k = 1:numel(dof)
    nu = dof(k);
    if nu > 1e8
        t(k) = sqrt(2) * erfinv(level);
    else
        y = betaincinv(alpha, 0.5, nu / 2, 'upper');
        t(k) = sqrt(nu * y / (1 - y));
    end
end
end

function fail(reason, message)
error(['sootMosaic:GROUP_AVG:' reason], '%s', message);
end
