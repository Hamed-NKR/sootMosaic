function result = PEAK_FIT(obs, grid, cfg, impactor, options)
% "PEAK_FIT" fits latent lognormal populations through a scan response.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     obs: Labeled OBSERVATION with every channel of the fixed scan window
%     grid: One-dimensional log INV.Grid in diameter (nm)
%     cfg: Resolved configuration, including the fixed reporting window
%     impactor: GRID_RULE impactor for KERNEL_1D; empty for distributions
%     options: Optional kernel_draw, raw_observation for MCC-off exports,...
%         ...variance_function, mass_kg, software_mode_nm, impactor_d50_nm,...
%         ...reduction_validated_1 and charge_setting_known_1. The variance...
%         ...function takes fitted counts (empty for pass one) and returns...
%         ...one OBS_VARIANCE result for this scan (n_scans = 1). A raw...
%         ...singleton uses OBS_VARIANCE directly when no function is given
%     options: distribution_covariance_cm6_inv supplies the full posterior
%         ...covariance for an inverted distribution, replacing the variance
%         ...callback. Density and calibration draws remain outer inputs
%     options: profile_check_1 defaults true; bootstrap_max_count defaults...
%         ...to eight times uncertainty.draws_min. Zero explicitly skips...
%         ...the interval bootstrap and leaves it unresolved. Raw...
%         ...concentration requires the original raw_counts_count vector
%     options: evidence_inversion takes one selected_1 entry of BAYESF for...
%         ...this route A scan on this grid (map_cm3_inv, lambda_cm3,...
%         ...resolved_1), computed by the caller with the full kernel
% Outputs:
%     result: One-population CMD and GSD, conditional intervals, observed...
%         ...and model window GM, evidence-inversion CMD check, whole-grid...
%         ...latent distribution, FN/FM, second-population test and...
%         ...sensitivity, weighted and unweighted fits, profile check with...
%         ...its agreement flag and interval bootstrap. No channel is removed
% ----------------------------------------------------------------------- %
% Method: Kiasadegh et al. (2026, Sec. 3.3, Eqs. 25-31), lognormal peak;
%     ...Sipkens et al. (2020, part I, Eqs. 23 and 28; part II, Eq. 26),
%     ...forward response and Gaussian information; Sipkens et al. (2023,
%     ...Eqs. 5-6), observation variance. Poisson fitting, the population
%     ...test, window GM and tail reporting follow
%     ...config/main_inv/DEFAULTS.md, sections 10 and 11.
% The profile check flags endpoint differences above 10 percent of the
%     ...Fisher interval width. A caller-supplied evidence inversion gives
%     ...an independent CMD check.
% Reimplementation from the published methods.
% Populations share their charge copies through KERNEL_1D. The width guard
%     ...is ln(GSD); charge copies have no independent width or amplitude.

if nargin < 5, options = struct(); end
allowed = {'kernel_draw', 'raw_observation', 'variance_function', ...
    'mass_kg', 'software_mode_nm', 'impactor_d50_nm', ...
    'reduction_validated_1', 'charge_setting_known_1', ...
    'profile_check_1', 'bootstrap_max_count', 'raw_counts_count', ...
    'distribution_covariance_cm6_inv', 'evidence_inversion'};
if ~isstruct(options) || ~isscalar(options) || ...
        any(~ismember(fieldnames(options), allowed))
    fail('Options', 'Unknown peak option.');
end
validate_inputs(obs, grid, cfg);
saved = rng;
restore = onCleanup(@() rng(saved));
rng(cfg.rng_seed, 'twister');
[a, y, kind, raw, meta] = forward(obs, grid, cfg, impactor, options);
window = [cfg.scan.window_min_nm, cfg.scan.window_max_nm];
context = struct('a', a, 'edges', log(grid.nodes{1}(:)), ...
    'width_min', cfg.peak_fit.first_width_min, 'kind', kind, ...
    'variance', ones(size(y)), 'y', y, 'whitener', []);
v1 = variance_result(raw, cfg, options, [], kind);
context.variance = variance_vector(v1, kind, numel(y));
if ~isempty(meta.reduction_cm3_inv_count_inv)
    context.variance = max(context.variance, ...
        meta.reduction_cm3_inv_count_inv.^2);
end
if isfield(options, 'distribution_covariance_cm6_inv')
    if ~strcmp(obs.route, 'inverted')
        fail('Covariance', ...
            'Full distribution covariance requires an inversion.');
    end
    covariance = options.distribution_covariance_cm6_inv;
    if ~isnumeric(covariance) || ~isreal(covariance) || ...
            ~isequal(size(covariance), [numel(y), numel(y)]) || ...
            any(~isfinite(covariance(:))) || ...
            norm(covariance-covariance', 'fro') > ...
            1e-10*norm(covariance, 'fro')
        fail('Covariance', 'Require a symmetric distribution covariance.');
    end
    [factor, flag] = chol((covariance+covariance')/2, 'lower');
    if flag ~= 0, fail('Covariance', 'Require positive covariance.'); end
    context.whitener = factor\eye(numel(y));
end
one = solve(context, 1, []);
if ~one.converged_1
    fail('Convergence', 'The one-population fit did not converge.');
end
% Reweighting once from the first weighted fit, with the counting floor
weighted_context = context;
weighted_context.kind = 'gaussian';
first_weighted = solve(weighted_context, 1, one.parameter);
if ~first_weighted.converged_1
    fail('Convergence', 'The first weighted fit did not converge.');
end
v2 = v1;
if strcmp(kind, 'poisson')
    v2 = variance_result(raw, cfg, options, first_weighted.expected, kind);
end
weighted_context.variance = variance_vector(v2, kind, numel(y));
if ~isempty(meta.reduction_cm3_inv_count_inv)
    weighted_context.variance = max(weighted_context.variance, ...
        meta.reduction_cm3_inv_count_inv.^2);
end
weighted = solve(weighted_context, 1, first_weighted.parameter);
plain_context = weighted_context;
plain_context.variance = ones(size(y));
plain_context.whitener = [];
plain = solve(plain_context, 1, one.parameter);
test = struct('method', 'bootstrap_lrt', 'statistic_1', NaN, ...
    'p_1', NaN, 'replicates_count', 0, 'resolved_1', false, ...
    'rejected_1', false, 'failed_count', 0);
two = [];
if cfg.peak_fit.max_populations == 2
    two = solve(context, 2, one.parameter);
    test.statistic_1 = max(0, 2*(one.loss-two.loss));
    count = cfg.peak_fit.population_test.replicates;
    exceed = 0;
    for k = 1:count
        simulated = context;
        simulated.y = simulate(one.expected, context);
        null_fit = solve(simulated, 1, one.parameter);
        alternative = solve(simulated, 2, null_fit.parameter);
        ok = null_fit.converged_1 && alternative.converged_1;
        test.failed_count = test.failed_count + ~ok;
        exceed = exceed + (ok && ...
            2*(null_fit.loss-alternative.loss) >= test.statistic_1-1e-9);
    end
    test.replicates_count = count;
    test.resolved_1 = two.converged_1 && test.failed_count == 0 && ...
        1/(count+1) <= cfg.peak_fit.population_test.alpha;
    if test.resolved_1
        test.p_1 = (1+exceed)/(1+count);
        test.rejected_1 = test.p_1 <= cfg.peak_fit.population_test.alpha;
    end
end
one = summarize(one, context, grid, window, cfg, options, meta);
weighted = summarize(weighted, weighted_context, grid, window, ...
    cfg, options, meta);
plain = summarize(plain, plain_context, grid, window, cfg, options, meta);
profile = struct('CMD_interval_nm', [NaN, NaN], 'resolved_1', false);
if get_option(options, 'profile_check_1', true)
    profile = profile_cmd(context, one);
end
% Comparing the profile and Fisher CMD limits within 10 percent of the...
    % ...Fisher width. An unresolved comparison is not a disagreement
profile.agreement_checked_1 = profile.resolved_1 && ...
    one.information_resolved_1 && diff(one.interval(2, :)) > 0;
profile.endpoint_difference_share_1 = NaN;
profile.disagreement_1 = false;
if profile.agreement_checked_1
    profile.endpoint_difference_share_1 = ...
        max(abs(profile.CMD_interval_nm-one.interval(2, :))) / ...
        diff(one.interval(2, :));
    profile.disagreement_1 = ...
        profile.endpoint_difference_share_1 > 0.10;
end
bootstrap = interval_bootstrap(context, one, cfg, options);
if ~isempty(two)
    two = summarize(two, context, grid, window, cfg, options, meta);
end
[observed_gm, gm_source] = observed_window_gm(obs, raw, window);
check = inversion_check(obs, grid, options, one.CMD_nm);
result = struct('CMD_nm', one.CMD_nm, 'GSD_1', one.GSD_1, ...
    'N_cm3_inv', one.N_cm3_inv, 'interval', one.interval, ...
    'interval_names', {{'N_cm3_inv', 'CMD_nm', 'GSD_1'}}, ...
    'one_population', one, 'population_test', test, ...
    'second_population_detected_1', test.rejected_1, ...
    'second_population_sensitivity', [], 'weighted_sensitivity', weighted, ...
    'unweighted_sensitivity', plain, 'variance_first', v1, ...
    'variance_second', v2, 'profile', profile, 'bootstrap', bootstrap, ...
    'FN', one.FN, 'FM', one.FM, 'window_GM_nm', observed_gm, ...
    'window_GM_source', gm_source, ...
    'model_window_GM_nm', one.model_window_GM_nm, ...
    'inversion_check', check, ...
    'label', 'conditional on one lognormal population', ...
    'seed_1', cfg.rng_seed, 'forward', meta, 'window_nm', window, ...
    'software_comparison', []);
if test.rejected_1, result.second_population_sensitivity = two; end
if isfield(options, 'software_mode_nm')
    mode = options.software_mode_nm;
    cut = get_option(options, 'impactor_d50_nm', NaN);
    if ~isscalar(mode) || ~isfinite(mode) || mode <= 0 || ...
            ~isscalar(cut) || (~isnan(cut) && (~isfinite(cut) || cut <= 0))
        fail('SoftwareMode', 'Require positive diameters for the comparison.');
    end
    result.software_comparison = struct('mode_nm', mode, ...
        'fit_minus_mode_nm', one.CMD_nm-mode, ...
        'impactor_minus_top_nm', cut-window(2));
end
end

function validate_inputs(obs, grid, cfg)
if ~isa(grid, 'INV.Grid') || grid.dim ~= 1 || ...
        ~strcmp(grid.discrete, 'log') || ~isstruct(obs) || ...
        ~isscalar(obs) || ~all(isfield(obs, ...
        {'values', 'quantity', 'route', 'reduced', 'unit'})) || ...
        ~isnumeric(obs.values) || ~isreal(obs.values) || ...
        ~isvector(obs.values) || numel(obs.values) < 4 || ...
        any(~isfinite(obs.values(:)) | obs.values(:) < 0) || ...
        sum(obs.values(:)) <= 0
    fail('Input', 'Require a positive scan and one-dimensional log grid.');
end
w = [cfg.scan.window_min_nm, cfg.scan.window_max_nm];
if numel(w) ~= 2 || any(~isfinite(w)) || w(1) <= 0 || w(2) <= w(1) || ...
        w(1) < grid.nodes{1}(1) || w(2) > grid.nodes{1}(end)
    fail('Window', 'Require the recorded scan window inside the grid.');
end
if isfield(obs, 'diameter_nm')
    d = obs.diameter_nm(:);
    if numel(d) ~= numel(obs.values) || any(~isfinite(d)) || ...
            any(d < w(1)*(1-1e-12) | d > w(2)*(1+1e-12))
        fail('Window', 'Observation rows must span the recorded scan only.');
    end
end
p = cfg.peak_fit;
if ~strcmp(p.components, 'latent_population') || ...
        ~strcmp(p.window, 'all_channels') || ...
        ~strcmp(p.weighting, 'poisson_likelihood') || ...
        ~ismember(p.max_populations, [1, 2]) || ...
        ~strcmp(p.population_test.method, 'bootstrap_lrt') || ...
        ~isscalar(p.first_width_min) || ~isfinite(p.first_width_min) || ...
        p.first_width_min <= 0 || ...
        ~isscalar(p.population_test.alpha) || ...
        p.population_test.alpha <= 0 || p.population_test.alpha >= 1 || ...
        ~isscalar(p.population_test.replicates) || ...
        p.population_test.replicates < 1 || ...
        p.population_test.replicates ~= ...
        fix(p.population_test.replicates) || ...
        cfg.nuisance.enabled || ~isempty(cfg.report.d_floor_nm)
    fail('Config', 'Require the latent-population rules and the scan floor.');
end
end

function [a, y, kind, raw, meta] = forward(o, g, c, imp, opt)
draw = get_option(opt, 'kernel_draw', struct());
y = o.values(:);
raw = o;
meta = struct('kind', '', 'kernel', [], 'reduction_cm3_inv_count_inv', [], ...
    'tail_allowed_1', false);
if strcmp(o.route, 'A') && ~o.reduced
    if strcmp(o.quantity, 'raw concentration') && strcmp(o.unit, 'cm^-3')
        if ~isfield(opt, 'raw_counts_count') || ...
                numel(opt.raw_counts_count) ~= numel(y)
            fail('Counts', 'Raw concentration requires the original counts.');
        end
        raw.values = opt.raw_counts_count(:);
        raw.quantity = 'raw counts';
        raw.unit = 'counts';
        if any(abs(raw.values./raw.sample_volume_cm3(:)-y) > ...
                1e-10*max(1, y))
            fail('Counts', 'Raw counts and concentration must agree.');
        end
    elseif ~strcmp(o.quantity, 'raw counts') || ~strcmp(o.unit, 'counts')
        fail('Route', ...
            'Require unsplit raw counts or their concentration view.');
    end
    [a, meta.kernel] = INV.KERNEL_1D(g, raw, c, imp, draw);
    y = raw.values(:);
    kind = 'poisson';
    meta.tail_allowed_1 = true;
elseif strcmp(o.route, 'B') && o.reduced && ...
        strcmp(o.quantity, 'dN/dlog10Da') && strcmp(o.unit, 'cm^-3')
    kind = 'gaussian';
    a = distribution_rows(o, g);
elseif strcmp(o.route, 'B') && o.reduced && ...
        strcmp(o.quantity, 'dN/dlog10Dm') && strcmp(o.unit, 'cm^-3') && ...
        isfield(o, 'mcc_on') && islogical(o.mcc_on) && isscalar(o.mcc_on)
    kind = 'gaussian';
    if o.mcc_on
        a = distribution_rows(o, g);
    else
        if ~isfield(opt, 'raw_observation')
            fail('Reduction', 'MCC-off requires a raw-response observation.');
        end
        raw = opt.raw_observation;
        [full, meta.kernel] = INV.KERNEL_1D(g, raw, c, imp, draw);
        single_draw = draw;
        single_draw.charge_e = 1;
        single = INV.KERNEL_1D(g, raw, c, imp, single_draw);
        response = sum(single, 2);
        if numel(response) ~= numel(y) || any(response <= 0)
            fail('Reduction', ...
                'Each export row needs a positive single response.');
        end
        d = 1./response;
        a = full.*d;
        meta.reduction_cm3_inv_count_inv = d;
        meta.tail_allowed_1 = ...
            isequal(get_option(opt, ...
            'reduction_validated_1', false), true) && ...
            isequal(get_option(opt, 'charge_setting_known_1', false), true);
    end
elseif strcmp(o.route, 'inverted') && ~o.reduced && ...
        any(strcmp(o.quantity, {'dN/dlog10Dm', 'dN/dlog10Da'})) && ...
        strcmp(o.unit, 'cm^-3')
    kind = 'gaussian';
    a = distribution_rows(o, g);
else
    fail('Route', 'Unsupported correction state or observation quantity.');
end
meta.kind = kind;
end

function a = distribution_rows(o, g)
if ~isfield(o, 'diameter_nm') || numel(o.diameter_nm) ~= numel(o.values)
    fail('Support', 'Require a diameter for every distribution row.');
end
d = o.diameter_nm(:);
[distance, ids] = min(abs(log(d)-log(g.elements(:)')), [], 2);
if any(distance > 1e-10) || numel(unique(ids)) ~= numel(ids)
    fail('Support', 'Distribution diameters must be distinct grid centers.');
end
a = sparse((1:numel(d))', ids, 1, numel(d), g.Ne);
end

function r = variance_result(raw, cfg, opt, expected, kind)
if isfield(opt, 'distribution_covariance_cm6_inv')
    covariance = opt.distribution_covariance_cm6_inv;
    r = struct('n_scans', 1, 'variance_mean_cm6_inv', diag(covariance), ...
        'pass_count', 1, 'source', 'distribution posterior covariance');
elseif isfield(opt, 'variance_function')
    if ~isa(opt.variance_function, 'function_handle')
        fail('Variance', 'Require an OBS_VARIANCE callback.');
    end
    r = opt.variance_function(expected);
elseif strcmp(kind, 'poisson')
    fitted = [];
    if ~isempty(expected), fitted = {expected}; end
    r = INV.OBS_VARIANCE({{raw}}, cfg, fitted);
else
    fail('Variance', 'Reduced and inverted data require supplied variance.');
end
if ~isstruct(r) || ~isscalar(r) || ~isfield(r, 'n_scans') || r.n_scans ~= 1
    fail('Variance', 'Require a variance result for one scan.');
end
end

function v = variance_vector(r, kind, n)
if strcmp(kind, 'poisson'), key = 'variance_mean_counts2';
else, key = 'variance_mean_cm6_inv';
end
if ~isfield(r, key), fail('Variance', 'Missing observation variance.'); end
v = r.(key);
v = v(:);
if numel(v) ~= n || any(~isfinite(v) | v <= 0)
    fail('Variance', 'Require a finite positive variance for every row.');
end
end

function fit = solve(c, populations, warm)
% Searching separated and coincident starts without selecting channels
low = c.edges(1);
high = c.edges(end);
if isempty(warm)
    centers = low+(high-low)*[0.25, 0.5, 0.75];
    starts = zeros(3, 6);
    for k = 1:6
        p = [0; centers(1+mod(k-1, 3)); log(1.2)];
        if k > 3, p(3) = log(1.7); end
        f = latent(p, c.edges);
        p(1) = log(max(sum(c.y)/max(sum(c.a*f), realmin), realmin));
        starts(:, k) = p;
    end
elseif populations == 1
    starts = warm(1:3);
else
    starts = zeros(6, 5);
    for k = 1:4
        shift = [0.25, 0.6, 1.0, 1.5];
        p = warm(1:3);
        p(1) = p(1)-log(2);
        starts(:, k) = [p; p];
        starts(2, k) = max(low+1e-5, p(2)-shift(k)/2);
        starts(5, k) = min(high-1e-5, p(2)+shift(k)/2);
    end
    starts(:, 5) = [warm(1:3); warm(1:3)];
    starts([1, 4], 5) = warm(1)-log(2);
end
settings = optimset('Display', 'off', 'TolX', 1e-8, 'TolFun', 1e-8, ...
    'MaxIter', 6000, 'MaxFunEvals', 12000);
best = Inf;
parameter = starts(:, 1);
converged = false;
for k = 1:size(starts, 2)
    [p, loss, exitflag] = fminsearch(@(v) objective(v, c), ...
        starts(:, k), settings);
    % Restarting a simplex that stops at its evaluation limit from its...
        % ...best vertex, at most twice
    for restart = 1:2
        if exitflag ~= 0 || ~isfinite(loss), break; end
        [p, loss, exitflag] = fminsearch(@(v) objective(v, c), p, settings);
    end
    if isfinite(loss) && loss < best && exitflag > 0
        best = loss;
        parameter = p;
        converged = true;
    end
end
if populations == 2
    blocks = reshape(parameter, 3, 2);
    [~, order] = sort(blocks(2, :));
    parameter = reshape(blocks(:, order), 6, 1);
end
[x, derivative] = latent(parameter, c.edges);
mu = c.a*x;
j = c.a*derivative;
if strcmp(c.kind, 'poisson'), variance = max(mu, realmin);
else, variance = c.variance;
end
jw = j./sqrt(variance);
if ~isempty(c.whitener), jw = c.whitener*j; end
information = jw'*jw;
resolved = converged && rcond(information) > 1e-12;
covariance = NaN(numel(parameter));
if resolved
    covariance = INV.POSTERIOR(jw, zeros(0, numel(parameter)));
end
guard = any(parameter(3:3:end) <= c.width_min*(1+1e-4));
edge = any(parameter(2:3:end) <= low+1e-6 | ...
    parameter(2:3:end) >= high-1e-6);
if guard || edge, resolved = false; end
fit = struct('parameter', parameter, 'loss', best, 'expected', mu, ...
    'latent_cm3_inv', x, 'latent_derivative', derivative, ...
    'covariance', covariance, 'converged_1', converged, ...
    'information_resolved_1', resolved, 'width_bound_1', guard, ...
    'parameter_edge_1', edge);
end

function loss = objective(p, c)
if any(~isfinite(p)) || any(abs(p(1:3:end)) > 600) || ...
        any(p(2:3:end) < c.edges(1) | p(2:3:end) > c.edges(end)) || ...
        any(p(3:3:end) < c.width_min)
    loss = Inf;
    return;
end
mu = c.a*latent(p, c.edges);
if any(~isfinite(mu)) || any(mu < 0)
    loss = Inf;
elseif strcmp(c.kind, 'poisson')
    if any(mu == 0 & c.y > 0), loss = Inf; return; end
    positive = c.y > 0;
    term = zeros(size(mu));
    term(positive) = c.y(positive).*log(c.y(positive)./mu(positive));
    loss = sum(mu-c.y+term);
else
    if isempty(c.whitener)
        loss = sum((c.y-mu).^2./c.variance)/2;
    else
        loss = sum((c.whitener*(c.y-mu)).^2)/2;
    end
end
end

function [x, derivative] = latent(p, edges)
% Integrating each lognormal exactly over the logarithmic cells
width = diff(edges);
x = zeros(numel(width), 1);
derivative = zeros(numel(width), numel(p));
for k = 1:3:numel(p)
    n = exp(p(k));
    s = p(k+2);
    z = (edges-p(k+1))/s;
    probability = diff(0.5*erfc(-z/sqrt(2)));
    upper = z(1:end-1) > 0;
    probability(upper) = -diff_selected(0.5*erfc(z/sqrt(2)), upper);
    density = exp(-z.^2/2)/sqrt(2*pi);
    component = n*max(0, probability)./width*log(10);
    x = x+component;
    derivative(:, k) = component;
    derivative(:, k+1) = -n*diff(density)/s./width*log(10);
    derivative(:, k+2) = -n*diff(z.*density)/s./width*log(10);
end
end

function d = diff_selected(x, mask)
d = diff(x);
d = d(mask);
end

function out = summarize(f, c, g, window, cfg, opt, meta)
out = f;
p = reshape(f.parameter, 3, []);
out.N_cm3_inv = exp(p(1, :));
out.CMD_nm = exp(p(2, :));
out.GSD_1 = exp(p(3, :));
out.interval = NaN(numel(f.parameter), 2);
if f.information_resolved_1
    sd = sqrt(max(0, diag(f.covariance)));
    out.interval = exp(f.parameter+1.95996398454005*sd*[-1, 1]);
end
mass = get_option(opt, 'mass_kg', ones(g.Ne, 1));
if ~isnumeric(mass) || ~isreal(mass) || numel(mass) ~= g.Ne || ...
        any(~isfinite(mass(:)) | mass(:) <= 0)
    fail('Mass', 'Require a positive fixed particle mass in each cell.');
end
cap = max(window(2), min(cfg.report.d_cap_nm, g.nodes{1}(end)));
statistic = @(x, mask) peak_statistics(x, g, window, cap, mass(:));
v = statistic(f.latent_cm3_inv, true(g.Ne, 1));
out.model_window_GM_nm = 10^v(2);
out.above_top_fraction_1 = v(8);
out.FN = tail_value();
out.FM = tail_value();
tail_allowed = cfg.report.above_window && meta.tail_allowed_1 && ...
    cfg.report.d_cap_nm <= g.nodes{1}(end) && ...
    cfg.report.d_cap_nm > window(2);
if tail_allowed
    out.FN = tail_value(v(6));
    if isfield(opt, 'mass_kg'), out.FM = tail_value(v(7)); end
    if f.information_resolved_1
        % Pushing the parameter covariance to the cells, then through...
            % ...the fraction Jacobians
        state = f.latent_derivative*f.covariance*f.latent_derivative';
        [~, pushed] = INV.DELTA_PROP(f.latent_cm3_inv, ...
            (state+state')/2, statistic, true(g.Ne, 1));
        out.FN.sd_1 = sqrt(max(0, pushed(6, 6)));
        out.FN.interval_1 = v(6)+1.95996398454005*out.FN.sd_1*[-1, 1];
        if isfield(opt, 'mass_kg')
            out.FM.sd_1 = sqrt(max(0, pushed(7, 7)));
            out.FM.interval_1 = v(7)+1.95996398454005*out.FM.sd_1*[-1, 1];
        end
    end
end
out.label = 'conditional on lognormal populations';
out.fit_kind = c.kind;
end

function t = tail_value(value)
if nargin == 0, value = NaN; end
t = struct('value_1', value, 'sd_1', NaN, 'interval_1', [NaN, NaN], ...
    'label', 'exploratory; conditional on population model');
end

function [gm, source] = observed_window_gm(o, raw, window)
% Averaging log diameter over the recorded rows, independent of the fit
gm = NaN;
source = 'unavailable';
if ~isfield(o, 'diameter_nm'), return; end
t = log10(o.diameter_nm(:));
if strcmp(o.route, 'A')
    % Raw concentration per channel at its singly charged diameter
    weight = raw.values(:)./raw.sample_volume_cm3(:);
    total = sum(weight);
    moment = weight'*t;
    label = 'raw concentration per channel';
else
    % Log-cell quadrature of the supplied density, with cells bounded by...
        % ...the midpoints between rows and by the window limits
    [t, order] = sort(t);
    y = o.values(:);
    y = y(order);
    middle = (t(1:end-1)+t(2:end))/2;
    lo = max([2*t(1)-middle(1); middle], log10(window(1)));
    hi = max(lo, min([middle; 2*t(end)-middle(end)], log10(window(2))));
    total = (hi-lo)'*y;
    moment = ((hi.^2-lo.^2)/2)'*y;
    label = 'distribution cell quadrature';
end
if total > 0
    gm = 10^(moment/total);
    source = label;
end
end

function check = inversion_check(o, grid, opt, cmd)
% Count median of the evidence-selected full-kernel inversion, a check...
    % ...beside the fitted CMD, which stays primary
check = struct('status', 'unavailable', 'CMD_nm', NaN, ...
    'minus_fit_nm', NaN, 'relative_1', NaN, 'lambda_cm3', NaN, ...
    'resolved_1', false, 'label', 'check only, the fitted CMD is primary');
if ~isfield(opt, 'evidence_inversion'), return; end
e = opt.evidence_inversion;
if ~strcmp(o.route, 'A') || o.reduced
    fail('Inversion', 'The inversion check applies to route A counts.');
end
if ~isstruct(e) || ~isscalar(e) || ...
        ~all(isfield(e, {'map_cm3_inv', 'lambda_cm3', 'resolved_1'})) || ...
        ~isnumeric(e.map_cm3_inv) || ~isreal(e.map_cm3_inv) || ...
        numel(e.map_cm3_inv) ~= grid.Ne || ...
        any(~isfinite(e.map_cm3_inv(:)) | e.map_cm3_inv(:) < 0) || ...
        ~isscalar(e.lambda_cm3) || ~isfinite(e.lambda_cm3) || ...
        e.lambda_cm3 <= 0 || ~islogical(e.resolved_1) || ...
        ~isscalar(e.resolved_1)
    fail('Inversion', 'Require one BAYESF selection on the fit grid.');
end
% Cumulative number with constant density in log10(d) within each cell
edges = log10(grid.nodes{1}(:));
number = e.map_cm3_inv(:).*diff(edges);
cumulative = [0; cumsum(number)];
if cumulative(end) <= 0
    fail('Inversion', 'Require a positive inverted number.');
end
k = find(cumulative >= cumulative(end)/2, 1)-1;
share = (cumulative(end)/2-cumulative(k))/number(k);
check.CMD_nm = 10^(edges(k)+share*(edges(k+1)-edges(k)));
check.minus_fit_nm = check.CMD_nm-cmd;
check.relative_1 = check.minus_fit_nm/cmd;
check.lambda_cm3 = e.lambda_cm3;
check.resolved_1 = e.resolved_1;
check.status = 'computed';
end

function profile = profile_cmd(c, fit)
limits = NaN(1, 2);
p = fit.parameter;
valid = fit.information_resolved_1;
if valid
    sd = sqrt(fit.covariance(2, 2));
    settings = optimset('Display', 'off', 'TolX', 1e-8, ...
        'TolFun', 1e-8, 'MaxIter', 6000, 'MaxFunEvals', 12000);
    for side = 1:2
        direction = 2*side-3;
        inner = p(2);
        outer = p(2)+direction*2*sd;
        crossed = false;
        for attempt = 1:16
            outer = min(c.edges(end), max(c.edges(1), outer));
            [~, loss, flag] = fminsearch(@(v) profile_loss(v, outer, c), ...
                p([1, 3]), settings);
            if flag <= 0, break; end
            if 2*(loss-fit.loss) >= 3.84145882069412
                crossed = true;
                break;
            end
            if outer == c.edges(1) || outer == c.edges(end), break; end
            outer = p(2)+2*(outer-p(2));
        end
        if ~crossed, valid = false; continue; end
        for step = 1:32
            middle = (inner+outer)/2;
            [~, loss, flag] = fminsearch(@(v) profile_loss(v, middle, c), ...
                p([1, 3]), settings);
            if flag <= 0, valid = false; break; end
            if 2*(loss-fit.loss) < 3.84145882069412, inner = middle;
            else, outer = middle;
            end
        end
        limits(side) = exp((inner+outer)/2);
    end
end
if ~valid, limits(:) = NaN; end
profile = struct('CMD_interval_nm', limits, 'resolved_1', valid);
end

function loss = profile_loss(v, median, context)
loss = objective([v(1); median; v(2)], context);
end

function b = interval_bootstrap(c, fit, cfg, opt)
minimum = max(300, cfg.uncertainty.draws_min);
maximum = get_option(opt, 'bootstrap_max_count', 8*minimum);
if ~isscalar(maximum) || ~isfinite(maximum) || maximum < 0 || ...
        maximum ~= fix(maximum)
    fail('Bootstrap', 'Require a nonnegative integer draw limit.');
end
b = struct('interval', NaN(3, 2), 'resolved_1', false, ...
    'replicates_count', 0, 'failed_count', 0, ...
    'endpoint_relative_error_1', NaN(3, 2));
if ~strcmp(c.kind, 'poisson') || maximum == 0, return; end
samples = NaN(3, maximum);
for k = 1:maximum
    trial = c;
    trial.y = simulate(fit.expected, c);
    f = solve(trial, 1, fit.parameter);
    if f.converged_1 && ~f.width_bound_1 && ~f.parameter_edge_1
        samples(:, k) = exp(f.parameter);
    else
        b.failed_count = b.failed_count+1;
    end
    b.replicates_count = k;
    if k >= minimum && (mod(k, minimum) == 0 || k == maximum) && ...
            b.failed_count == 0
        limits = quantiles(samples(:, 1:k));
        batches = zeros(3, 2, 10);
        for j = 1:10
            batches(:, :, j) = quantiles(samples(:, j:10:k));
        end
        endpoint_error = std(batches, 0, 3)/sqrt(10);
        relative = endpoint_error./max((limits(:, 2)-limits(:, 1))/2, realmin);
        b.endpoint_relative_error_1 = relative;
        if all(relative(:) <= cfg.uncertainty.interval_mc_rel_tol)
            b.interval = limits;
            b.resolved_1 = true;
            return;
        end
    end
end
end

function y = simulate(mu, context)
if strcmp(context.kind, 'poisson')
    % Summing independent small-rate draws avoids large-rate underflow
    y = zeros(size(mu));
    for i = 1:numel(mu)
        pieces = max(1, ceil(mu(i)/20));
        rate = mu(i)/pieces;
        for k = 1:pieces
            product = 1;
            count = -1;
            while product > exp(-rate)
                product = product*rand;
                count = count+1;
            end
            if rate > 0, y(i) = y(i)+count; end
        end
    end
else
    if isempty(context.whitener)
        y = mu+sqrt(context.variance).*randn(size(mu));
    else
        y = mu+context.whitener\randn(size(mu));
    end
end
end

function q = quantiles(x)
x = sort(x, 2);
n = size(x, 2);
q = x(:, max(1, ceil(n*[0.025, 0.975])));
end

function v = get_option(s, key, fallback)
v = fallback;
if isfield(s, key), v = s.(key); end
end

function fail(reason, message)
error(['sootMosaic:PEAK_FIT:' reason], '%s', message);
end
