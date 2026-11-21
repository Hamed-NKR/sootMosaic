function result = MOMENTS(grid, states, covariances, window_nm, cfg, options)
% "MOMENTS" reports fixed-window log moments and above-window bounds.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     grid: One-dimensional log INV.Grid (nm)
%     states: dN/dlog10(d), one column per lambda node (cm^-3), or one...
%         ...labeled reduced OBSERVATION with values on the grid
%     covariances: Conditional covariance pages (cm^-6), or empty for...
%         ...point estimates only
%     window_nm: Recorded lower and upper scan limits (nm)
%     cfg: Resolved +INV configuration
%     options: Optional weights_1, mass_kg per cell, peak_fit result,...
%         ...resolution_1 pages, and posterior nodes with precision_cm6...
%         ...and rhs_cm3 for a requested TGIBBS check. sampler_options...
%         ...passes to TGIBBS. Supplied draws_cm3_inv and draws_resolved_1...
%         ...may replace sampling; draw_weights_1 gives their probabilities
% Outputs:
%     result: N, GM, GSD, skewness, Pearson kurtosis and refined mode;...
%         ...delta intervals, TF, conditional FN/FM upper bounds, response...
%         ...diagnostics, bimodality and interval-withholding flags. The...
%         ...mode interval needs a refined vertex at every weighted node
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eq. 23; part II, Eq. 26).
% Reimplementation of central log moments, delta propagation and total...
%     ...variance. GM/GSD withholding and tail reporting follow...
%     ...config/main_inv/DEFAULTS.md, section 11. Delta propagation and...
%     ...mixture variance follow section 13.
% The refined-mode delta interval differs from the grid-maximum bootstrap
%     ...interval described there. Failed refinement withholds this interval.
% Mass is held fixed per cell. Shared density/calibration variation enters...
%     ...as outer nodes, with their joint probabilities supplied by caller.

if nargin < 6, options = struct(); end
allowed = {'weights_1', 'mass_kg', 'peak_fit', 'resolution_1', ...
    'posterior', 'sampler_options', 'draws_cm3_inv', ...
    'draws_resolved_1', 'draw_weights_1'};
if ~isstruct(options) || ~isscalar(options) || ...
        any(~ismember(fieldnames(options), allowed))
    error('sootMosaic:MOMENTS:Options', 'Unknown statistic option.');
end
reduced = isstruct(states);
if reduced
    if ~isscalar(states) || ~all(isfield(states, ...
            {'reduced', 'quantity', 'unit', 'values'})) || ...
            ~isequal(states.reduced, true) || ...
            ~any(strcmp(states.quantity, ...
            {'dN/dlog10Dm', 'dN/dlog10Da'})) || ...
            ~strcmp(states.unit, 'cm^-3')
        error('sootMosaic:MOMENTS:Observation', ...
            'Require a labeled reduced number distribution.');
    end
    states = states.values(:);
end
if ~isa(grid, 'INV.Grid') || grid.dim ~= 1 || ...
        ~strcmp(grid.discrete, 'log') || ~isnumeric(states) || ...
        ~isreal(states) || size(states, 1) ~= grid.Ne || ...
        isempty(states) || any(~isfinite(states(:)) | states(:) < 0) || ...
        ~isnumeric(window_nm) || ~isreal(window_nm) || ...
        numel(window_nm) ~= 2 || any(~isfinite(window_nm)) || ...
        window_nm(1) <= 0 || window_nm(2) <= window_nm(1)
    error('sootMosaic:MOMENTS:Input', ...
        'Require a grid, states and fixed window.');
end
edges = grid.nodes{1};
if window_nm(1) < edges(1) || window_nm(2) > edges(end)
    error('sootMosaic:MOMENTS:Support', ...
        'The grid must cover the scan window.');
end
nodes = size(states, 2);
weights = get_option(options, 'weights_1', ones(nodes, 1));
if ~isnumeric(weights) || ~isreal(weights) || numel(weights) ~= nodes || ...
        any(~isfinite(weights(:)) | weights(:) < 0) || sum(weights(:)) <= 0
    error('sootMosaic:MOMENTS:Weights', 'Require positive total node weight.');
end
weights = weights(:)/sum(weights(:));
have_covariance = ~isempty(covariances);
if ~have_covariance, covariances = zeros(grid.Ne, grid.Ne, nodes); end
if size(covariances, 1) ~= grid.Ne || ...
        size(covariances, 2) ~= grid.Ne || size(covariances, 3) ~= nodes
    error('sootMosaic:MOMENTS:Covariance', 'Require one covariance per node.');
end
have_mass = isfield(options, 'mass_kg');
mass = get_option(options, 'mass_kg', ones(grid.Ne, 1));
if ~isnumeric(mass) || ~isreal(mass) || numel(mass) ~= grid.Ne || ...
        any(~isfinite(mass(:)) | mass(:) <= 0)
    error('sootMosaic:MOMENTS:Mass', 'Require positive mass per grid cell.');
end
mass = mass(:);
cap = cfg.report.d_cap_nm;
if ~isscalar(cap) || ~isfinite(cap) || cap <= 0 || ...
        ~isscalar(cfg.report.bound_level) || ...
        cfg.report.bound_level <= 0.5 || ...
        cfg.report.bound_level >= 1 || ...
        ~strcmp(cfg.moments.range, 'scan') || ...
        ~strcmp(cfg.moments.interval_method, 'delta') || ...
        ~isempty(cfg.report.d_floor_nm)
    error('sootMosaic:MOMENTS:Config', ...
        'Require fixed scan moments and delta intervals.');
end
above = cfg.report.above_window && ~reduced;
supported = cap <= edges(end) && cap > window_nm(2);
% Keeping the internal band on the grid when no bound can be reported
calc_cap = min(cap, edges(end));
calc_cap = max(calc_cap, window_nm(2));
statistic = @(x, mask) evaluate(x, mask, grid, window_nm, calc_cap, mass);
mask = true(grid.Ne, 1);
values = zeros(9, nodes);
pushed = zeros(9, 9, nodes);
refined = false(nodes, 1);
for k = 1:nodes
    [values(:, k), pushed(:, :, k)] = INV.DELTA_PROP(states(:, k), ...
        covariances(:, :, k), statistic, mask);
    [~, ~, node_shape] = peak_statistics(states(:, k), grid, window_nm, ...
        calc_cap, mass);
    refined(k) = node_shape.mode_refined_1;
end
% A mode interval needs the refined vertex at every weighted node
mode_refined = all(refined(weights > 0));
[center, covariance] = INV.POST_MIX(values, pushed, weights);
[state, state_covariance] = INV.POST_MIX(states, covariances, weights);
[~, jacobian, shape] = peak_statistics(state, grid, window_nm, calc_cap, mass);
sd = sqrt(max(0, diag(covariance)));
interval = center + 1.95996398454005*sd*[-1, 1];
if ~have_covariance, interval(:) = NaN; sd(:) = NaN; end
interval([2, 3, 9], :) = 10.^interval([2, 3, 9], :);
point = center;
point([2, 3, 9]) = 10.^point([2, 3, 9]);
screen_missing = true;
structured = false;
edge_limited = false;
if isfield(options, 'peak_fit')
    peak = options.peak_fit;
    if ~isstruct(peak) || ~all(isfield(peak, ...
            {'population_test', 'one_population'})) || ...
            ~isfield(peak.population_test, 'resolved_1') || ...
            ~isfield(peak.population_test, 'rejected_1') || ...
            ~isfield(peak.one_population, 'above_top_fraction_1')
        error('sootMosaic:MOMENTS:PeakScreen', ...
            'Require the same-scan PEAK_FIT result.');
    end
    screen_missing = ~peak.population_test.resolved_1;
    structured = peak.population_test.rejected_1;
    edge_limited = peak.one_population.above_top_fraction_1 > ...
        cfg.moments.edge_fraction_max;
end
withheld = screen_missing || structured || edge_limited;
if withheld, interval(2:3, :) = NaN; end
if shape.mode_boundary_1 || ~mode_refined, interval(9, :) = NaN; end
result = struct('N_cm3_inv', point(1), 'GM_nm', point(2), ...
    'GSD_1', point(3), 'skewness_1', point(4), ...
    'kurtosis_1', point(5), 'mode_nm', point(9), ...
    'interval_names', {{'N_cm3_inv', 'GM_nm', 'GSD_1', ...
    'skewness_1', 'kurtosis_1', 'mode_nm'}}, ...
    'interval', interval([1:5, 9], :), ...
    'interval_withheld_1', withheld, 'structure_flag_1', structured, ...
    'edge_flag_1', edge_limited, 'screen_missing_1', screen_missing, ...
    'mode_boundary_1', shape.mode_boundary_1, ...
    'mode_refined_1', mode_refined, ...
    'TF_1', point(8), 'TF_sd_1', sd(8), 'TF_interval_1', interval(8, :), ...
    'window_nm', window_nm(:)', 'label', 'conditional on smoothness prior', ...
    'FN', empty_bound('not requested'), ...
    'FM', empty_bound('mass not supplied'), ...
    'response', [], 'bimodal_1', false, 'bimodal_resolved_1', false, ...
    'bimodal_draw_share_1', NaN, 'gibbs', [], 'D13_1', false);
if reduced
    result.label = 'software-reduced distribution';
    result.TF_1 = NaN;
    result.TF_sd_1 = NaN;
    result.TF_interval_1(:) = NaN;
end
if above && supported && have_covariance
    z = sqrt(2)*erfinv(2*cfg.report.bound_level-1);
    result.FN = upper_bound(center(6), sd(6), z);
    if have_mass, result.FM = upper_bound(center(7), sd(7), z); end
elseif above
    result.FN = empty_bound('no bound');
    if have_mass, result.FM = empty_bound('no bound'); end
end
if isfield(options, 'peak_fit') && isfinite(result.FN.upper_1) && ...
        isfield(options.peak_fit, 'FN') && ...
        isfield(options.peak_fit.FN, 'value_1')
    result.D13_1 = options.peak_fit.FN.value_1 > result.FN.upper_1;
end
if isfield(options, 'resolution_1')
    result.response = INV.STAT_RESPONSE(jacobian([2, 3, 6, 7, 8], :), ...
        options.resolution_1, weights);
    result.response.names = {'log10_GM', 'log10_GSD', 'FN', 'FM', 'TF'};
end
if isfield(options, 'posterior')
    if ~isfield(options, 'sampler_options')
        options.sampler_options = struct();
    end
    if ~isfield(options.sampler_options, 'seed_1')
        options.sampler_options.seed_1 = cfg.rng_seed;
    end
end
[draws, draw_weights, resolved, sampler_info] = ...
    posterior_draws(options, nodes, weights, ...
    @(x, mask) check_statistics(x, mask, statistic, ...
    any(abs(jacobian) > 0, 2)));
if ~isempty(draws)
    if size(draws, 1) ~= grid.Ne || any(~isfinite(draws(:)) | draws(:) < 0)
        error('sootMosaic:MOMENTS:Draws', ...
            'Require nonnegative posterior draws.');
    end
    dip_sd = sqrt(max(0, diag(state_covariance)));
    if ~have_covariance
        draw_center = draws*draw_weights;
        dip_sd = sqrt((draws-draw_center).^2*draw_weights);
    end
    samples = zeros(9, size(draws, 2));
    dip = false(size(draws, 2), 1);
    for k = 1:size(draws, 2)
        samples(:, k) = statistic(draws(:, k), mask);
        dip(k) = has_dip(draws(:, k), dip_sd, ...
            grid, window_nm, cfg.diagnostics.bimodal_dip_sd);
    end
    result.bimodal_draw_share_1 = draw_weights'*double(dip);
    result.bimodal_resolved_1 = resolved;
    result.bimodal_1 = resolved && result.bimodal_draw_share_1 >= ...
        cfg.diagnostics.bimodal_draw_share;
    bounds = weighted_interval(samples, draw_weights);
    bounds([2, 3, 9], :) = 10.^bounds([2, 3, 9], :);
    if ~resolved, bounds(:) = NaN; end
    if reduced, bounds(6:8, :) = NaN; end
    if withheld, bounds(2:3, :) = NaN; end
    if shape.mode_boundary_1, bounds(9, :) = NaN; end
    result.gibbs = struct('interval', bounds([1:5, 9], :), ...
        'TF_interval_1', bounds(8, :), ...
        'resolved_1', resolved, 'sampler', {sampler_info});
elseif have_covariance && ~any(state_covariance(:))
    result.bimodal_resolved_1 = true;
    result.bimodal_1 = has_dip(state, zeros(grid.Ne, 1), grid, ...
        window_nm, cfg.diagnostics.bimodal_dip_sd);
    result.bimodal_draw_share_1 = double(result.bimodal_1);
end
end

function [v, j] = evaluate(x, mask, grid, window, cap, mass)
if ~all(mask)
    error('sootMosaic:MOMENTS:Mask', 'The reporting window is fixed.');
end
[v, j] = peak_statistics(x, grid, window, cap, mass);
end

function value = check_statistics(x, mask, statistic, rows)
value = statistic(x, mask);
value = value(rows);
end

function b = empty_bound(status)
b = struct('upper_1', NaN, 'sd_1', NaN, 'status', status, ...
    'label', 'exploratory; conditional on smoothness prior');
end

function b = upper_bound(value, sd, z)
b = empty_bound('upper bound');
b.sd_1 = sd;
upper = value+z*sd;
if upper >= 1
    b.status = 'no bound';
else
    b.upper_1 = max(0, upper);
end
end

function [draws, weights, resolved, info] = posterior_draws(o, nodes, w, fun)
draws = [];
weights = [];
resolved = false;
info = {};
if isfield(o, 'posterior') && isfield(o, 'draws_cm3_inv')
    error('sootMosaic:MOMENTS:Draws', ...
        'Choose posterior nodes or supplied draws.');
end
if isfield(o, 'posterior')
    if numel(o.posterior) ~= nodes
        error('sootMosaic:MOMENTS:Posterior', ...
            'Require one posterior per node.');
    end
    blocks = cell(nodes, 1);
    probabilities = cell(nodes, 1);
    info = cell(nodes, 1);
    resolved = true;
    for k = 1:nodes
        p = o.posterior(k);
        opt = get_option(o, 'sampler_options', struct());
        opt.seed_1 = mod(get_option(opt, 'seed_1', 27)+k-1, 2^32);
        [d, info{k}] = INV.TGIBBS(p.precision_cm6, p.rhs_cm3, opt, ...
            @(x) fun(x, true(numel(x), 1)));
        blocks{k} = reshape(d, size(d, 1), []);
        probabilities{k} = repmat(w(k)/size(blocks{k}, 2), ...
            size(blocks{k}, 2), 1);
        resolved = resolved && info{k}.resolved_1;
    end
    draws = cat(2, blocks{:});
    weights = cat(1, probabilities{:});
elseif isfield(o, 'draws_cm3_inv')
    draws = o.draws_cm3_inv;
    resolved = isequal(get_option(o, 'draws_resolved_1', false), true);
    weights = get_option(o, 'draw_weights_1', ones(size(draws, 2), 1));
    if ~isnumeric(weights) || ~isreal(weights) || ...
            numel(weights) ~= size(draws, 2) || ...
            any(~isfinite(weights(:)) | weights(:) < 0) || sum(weights(:)) <= 0
        error('sootMosaic:MOMENTS:Weights', ...
            'Require positive total draw weight.');
    end
    weights = weights(:)/sum(weights(:));
end
end

function flag = has_dip(x, sd, grid, window, threshold)
t = grid.elements(:);
ids = find(t >= window(1) & t <= window(2));
peaks = ids(2:end-1);
peaks = peaks(x(peaks) > x(peaks-1) & x(peaks) >= x(peaks+1));
flag = false;
for k = 1:numel(peaks)-1
    [bottom, relative] = min(x(peaks(k):peaks(k+1)));
    index = peaks(k)+relative-1;
    if min(x(peaks(k:k+1)))-bottom > threshold*sd(index)
        flag = true;
        return;
    end
end
end

function limits = weighted_interval(samples, weights)
limits = zeros(size(samples, 1), 2);
for k = 1:size(samples, 1)
    [s, order] = sort(samples(k, :));
    cumulative = cumsum(weights(order));
    limits(k, 1) = s(find(cumulative >= 0.025-8*eps, 1));
    limits(k, 2) = s(find(cumulative >= 0.975-8*eps, 1));
end
end

function v = get_option(o, key, fallback)
v = fallback;
if isfield(o, key), v = o.(key); end
end
