function [result, model] = OBS_VARIANCE(groups, cfg, fitted_counts, ...
    floor_cm6_inv, bootstrap_indices)
% "OBS_VARIANCE" computes the variance of repeat-mean observations.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     groups: Cell array of conditions, each a cell of OBSERVATION results...
%         ...with campaign_id, condition_id and source_id labels. The...
%         ...caller supplies source_id as a stable file/source identity;...
%         ...OBSERVATION retains scan_index, a positive integer. Each...
%         ...source_id/scan_index pair occurs once across all groups....
%         ...Repeats share support; conditions share one campaign and mode
%     cfg: Resolved configuration with variance rules and rng_seed
%     fitted_counts: Empty for pass one, or one channels-by-scans matrix...
%         ...of fitted expected counts per condition for pass two (counts)....
%         ...Counts divided by volume must share one concentration profile
%     floor_cm6_inv: One positive scalar, channel vector or channels-by-...
%         ...scans matrix per pooled condition. Empty for raw counts (cm^-6)
%     bootstrap_indices: Optional conditions-by-draws array of resampled...
%         ...condition indices. Empty draws 200 samples with cfg.rng_seed
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: One structure per condition. Weight variances exclude the...
%         ...between-scan scale term. Joint bootstrap variance columns...
%         ...and between_mean_ratio2_draws propagate fitted components
%     model: Pooled coefficients, their joint draws and percentile bounds....
%         ...Coefficient order is gamma2, tau_within2, tau_between2 for...
%         ...counts, or a, c for pooled concentrations. A false...
%         ...repeat_identified_ratio or bootstrap_available_ratio leaves...
%         ...the corresponding bounds and draws undefined
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2017, Eqs. 8-9); Sipkens et al. (2020, part II,...
%     ...Eqs. 15-16); Sipkens et al. (2023, Eqs. 1, 3-6, Sec. 2.2).

if nargin < 3, fitted_counts = []; end
if nargin < 4, floor_cm6_inv = []; end
if nargin < 5, bootstrap_indices = []; end
validate_config(cfg);
if ~iscell(groups) || isempty(groups) || ~isvector(groups)
    fail('Groups', 'Expected a nonempty cell vector of repeat groups.');
end
ng = numel(groups);
if ~isempty(fitted_counts) && ...
        (~iscell(fitted_counts) || numel(fitted_counts) ~= ng)
    fail('FittedCounts', 'Expected one fitted-count matrix per condition.');
end
if ~isempty(floor_cm6_inv) && ...
        (~iscell(floor_cm6_inv) || numel(floor_cm6_inv) ~= ng)
    fail('Floor', 'Expected one concentration floor per condition.');
end
data = cell(ng, 1);
blocks = cell(ng, 1);
targets = cell(ng, 1);
ids = cell(ng, 1);
sources = cell(ng, 1);
scans = cell(ng, 1);
for g = 1:ng
    data{g} = read_group(groups{g});
    d = data{g};
    sources{g} = d.sources;
    scans{g} = d.scans;
    first = groups{g}{1};
    ids{g} = first.condition_id;
    if g == 1
        anchor = first;
        raw = d.raw;
    elseif ~isequal(first.campaign_id, anchor.campaign_id) || ...
            ~strcmp(first.mode, anchor.mode) || ...
            ~strcmp(first.route, anchor.route) || ...
            ~strcmp(first.quantity, anchor.quantity) || raw ~= d.raw
        fail('PoolScope', 'Pool one campaign, instrument mode and route.');
    end
    for key = {'mcc_on', 'dlc_on'}
        if isfield(anchor, key{1}) && ...
                ~isequal(first.(key{1}), anchor.(key{1}))
            fail('PoolScope', 'Pool one reduced correction state.');
        end
    end
    if raw
        if ~isempty(floor_cm6_inv)
            fail('Floor', 'Raw-count floors come from the bin exposure.');
        end
        d.expected = d.counts;
        if ~isempty(fitted_counts)
            e = fitted_counts{g};
            if ~real_array(e) || ~isequal(size(e), size(d.counts)) || ...
                    any(~isfinite(e(:)) | e(:) < 0)
                fail('FittedCounts', 'Fitted counts must match every bin.');
            end
            d.expected = double(e);
        end
        d.shot = max(d.expected, cfg.variance.floor_counts) ./ d.volume.^2;
        d.floor = cfg.variance.floor_counts ./ d.volume.^2;
        signal = d.expected./d.volume;
        mu = mean(signal, 2);
        if ~isempty(fitted_counts) && ...
                any(any(abs(signal-mu) > 64*eps(max(1, abs(mu)))))
            fail('FittedCounts', ...
                'Fitted counts must share one concentration profile.');
        end
        d.signal = repmat(mu, 1, d.n);
    else
        if ~isempty(fitted_counts)
            fail('FittedRoute', 'Fitted Poisson counts require raw bins.');
        end
        if isempty(floor_cm6_inv)
            fail('Floor', 'Pooled data require an absolute concentration floor.');
        end
        f = floor_cm6_inv{g};
        if ~real_array(f) || ~(isscalar(f) || ...
                (isvector(f) && numel(f) == size(d.values, 1)) || ...
                isequal(size(f), size(d.values))) || ...
                any(~isfinite(f(:)) | f(:) <= 0)
            fail('Floor', 'Concentration floors must be positive and finite.');
        end
        if isequal(size(f), size(d.values))
            d.floor = double(f);
        else
            d.floor = repmat(double(f(:)), size(d.values, 1)/numel(f), d.n);
        end
        d.signal = d.values;
    end
    [blocks{g}, targets{g}] = moment_block(d, cfg.variance.min_repeats);
    data{g} = d;
end
[~, ~, source_index] = unique(vertcat(sources{:}));
scan_index = vertcat(scans{:});
if size(unique([source_index, scan_index], 'rows'), 1) ~= numel(scan_index)
    fail('ScanIdentity', 'Each source-qualified scan must occur only once.');
end
if numel(unique(ids)) ~= ng
    fail('Condition', 'Each condition must occur in exactly one group.');
end
if raw
    p = 3;
else
    p = 2;
end
[coef, identified] = fit_components(vertcat(blocks{:}), ...
    vertcat(targets{:}), p);
if raw && ~identified && any(vertcat(targets{:}) > 0)
    fail('RepeatFit', ...
        'Positive repeat excess requires identifiable components.');
end
if ~raw && ~identified
    fail('RepeatFit', 'Pooled coefficients require identifiable repeats.');
end

% Resampling entire condition blocks preserves within-scan correlation
eligible = find(~cellfun(@isempty, blocks));
ne = numel(eligible);
draws = NaN(p, 0);
available = false;
if ~isempty(bootstrap_indices)
    if ~real_array(bootstrap_indices) || ...
            size(bootstrap_indices, 1) ~= ne || ...
            size(bootstrap_indices, 2) < 2 || ...
            any(~ismember(bootstrap_indices(:), eligible))
        fail('Bootstrap', 'Resamples must index every eligible condition.');
    end
end
if ne >= 2 && identified
    if isempty(bootstrap_indices)
        stream = RandStream('mt19937ar', 'Seed', cfg.rng_seed);
        bootstrap_indices = eligible(randi(stream, ne, ne, 200));
    end
    draws = NaN(p, size(bootstrap_indices, 2));
    for b = 1:size(draws, 2)
        ix = bootstrap_indices(:, b);
        [trial, ok] = fit_components(vertcat(blocks{ix}), ...
            vertcat(targets{ix}), p);
        if ok, draws(:, b) = trial; end
    end
    available = all(isfinite(draws(:)));
elseif ~isempty(bootstrap_indices)
    fail('Bootstrap', 'At least two identifiable condition blocks are needed.');
end
model = struct('campaign_id', anchor.campaign_id, 'mode', anchor.mode, ...
    'route', anchor.route, 'repeat_identified_ratio', identified, ...
    'bootstrap_available_ratio', available, ...
    'bootstrap_condition_indices', bootstrap_indices, ...
    'repeat_conditions_count', ne, 'independent_scans_ratio', true);
if raw
    model.gamma2_cm6_inv = coef(1);
    model.tau_within2_ratio2 = coef(2);
    model.tau_between2_ratio2 = coef(3);
    model.gamma2_cm6_inv_draws = draws(1, :);
    model.tau_within2_ratio2_draws = draws(2, :);
    model.tau_between2_ratio2_draws = draws(3, :);
    bounds = interval(draws, available, 3);
    model.gamma2_interval_cm6_inv = bounds(1, :);
    model.tau_within2_interval_ratio2 = bounds(2, :);
    model.tau_between2_interval_ratio2 = bounds(3, :);
else
    model.a_cm6_inv = coef(1);
    model.c_cm3_inv = coef(2);
    model.a_cm6_inv_draws = draws(1, :);
    model.c_cm3_inv_draws = draws(2, :);
    bounds = interval(draws, available, 2);
    model.a_interval_cm6_inv = bounds(1, :);
    model.c_interval_cm3_inv = bounds(2, :);
end
for g = 1:ng
    d = data{g};
    r = struct('condition_id', ids{g}, 'n_scans', d.n, ...
        'mean_cm3_inv', mean(d.values, 2), 'mean_counts', [], ...
        'variance_mean_cm6_inv', [], 'variance_mean_counts2', [], ...
        'floor_mean_cm6_inv', sum(d.floor, 2)/d.n^2, ...
        'poisson_mean_cm6_inv', [], 'poisson_mean_counts2', [], ...
        'within_mean_cm6_inv', [], 'between_mean_ratio2', 0, ...
        'variance_mean_cm6_inv_draws', [], ...
        'variance_mean_counts2_draws', [], 'between_mean_ratio2_draws', [], ...
        'variance_interval_cm6_inv', [], 'variance_interval_counts2', [], ...
        'pass_count', 1 + ~isempty(fitted_counts), ...
        'nominal_exposure_ratio', raw);
    [r.variance_mean_cm6_inv, r.variance_mean_counts2, ...
        r.within_mean_cm6_inv] = weight_variance(d, coef);
    if raw
        r.mean_counts = mean(d.counts, 2);
        r.poisson_mean_cm6_inv = sum(d.shot, 2)/d.n^2;
        r.poisson_mean_counts2 = ...
            sum(max(d.expected, cfg.variance.floor_counts), 2)/d.n^2;
        r.between_mean_ratio2 = coef(3)/d.n;
    end
    nd = size(draws, 2);
    r.variance_mean_cm6_inv_draws = NaN(size(d.values, 1), nd);
    if raw
        r.variance_mean_counts2_draws = NaN(size(d.values, 1), nd);
        r.between_mean_ratio2_draws = draws(3, :)/d.n;
    end
    for b = 1:nd
        [vc, vn] = weight_variance(d, draws(:, b));
        r.variance_mean_cm6_inv_draws(:, b) = vc;
        if raw, r.variance_mean_counts2_draws(:, b) = vn; end
    end
    r.variance_interval_cm6_inv = interval( ...
        r.variance_mean_cm6_inv_draws, available, size(d.values, 1));
    if raw
        r.variance_interval_counts2 = interval( ...
            r.variance_mean_counts2_draws, available, size(d.values, 1));
    end
    if any(~isfinite(r.variance_mean_cm6_inv) | ...
            r.variance_mean_cm6_inv <= 0) || ...
            any(~isfinite(r.variance_mean_counts2))
        fail('Overflow', 'Variance arithmetic must remain finite and positive.');
    end
    if g == 1, result = repmat(r, 1, ng); end
    result(g) = r;
end
end

function d = read_group(group)
if ~iscell(group) || isempty(group) || ~isvector(group)
    fail('Groups', 'Each condition requires a cell vector of observations.');
end
required = {'campaign_id', 'condition_id', 'mode', 'route', 'source_kind', ...
    'quantity', 'unit', 'values', 'reduced', 'dilution_applied', ...
    'dilution_known'};
for k = 1:numel(group)
    o = group{k};
    if ~isstruct(o) || ~isscalar(o) || ~all(isfield(o, required))
        fail('Observation', 'Expected labeled OBSERVATION results.');
    end
    if ~isfield(o, 'source_id') || ~ischar(o.source_id) || ...
            ~isrow(o.source_id) || isempty(strtrim(o.source_id)) || ...
            ~isfield(o, 'scan_index') || ~real_array(o.scan_index) || ...
            ~isscalar(o.scan_index) || ~isfinite(o.scan_index) || ...
            o.scan_index < 1 || o.scan_index > flintmax || ...
            o.scan_index ~= fix(o.scan_index)
        fail('ScanIdentity', ...
            'Expected a source_id and positive integer scan_index.');
    end
    labels = {'campaign_id', 'condition_id', 'mode', 'route', ...
        'source_kind', 'quantity', 'unit'};
    for j = 1:numel(labels)
        x = o.(labels{j});
        if ~ischar(x) || ~isrow(x) || isempty(x)
            fail('Labels', 'Observation labels must be nonempty character rows.');
        end
    end
    if ~isequal(o.dilution_applied, true) || ~isequal(o.dilution_known, true)
        fail('Dilution', 'Resolve dilution through OBSERVATION before pooling.');
    end
    raw = strcmp(o.route, 'A') && strcmp(o.source_kind, 'smps_database') && ...
        any(strcmp(o.mode, {'smps_1d', 'tandem'})) && ...
        strcmp(o.quantity, 'raw counts') && strcmp(o.unit, 'counts') && ...
        isequal(o.reduced, false);
    reduced_smps = strcmp(o.route, 'B') && ...
        strcmp(o.source_kind, 'smps_export') && ...
        any(strcmp(o.mode, {'smps_1d', 'tandem'})) && ...
        strcmp(o.quantity, 'dN/dlog10Dm') && isequal(o.reduced, true);
    aac = strcmp(o.source_kind, 'aac_export') && strcmp(o.mode, 'aac_1d') && ...
        ((strcmp(o.route, 'A') && strcmp(o.quantity, 'counter concentration') && ...
        isequal(o.reduced, false) && isfield(o, 'counts_are_approximate') && ...
        isequal(o.counts_are_approximate, true)) || ...
        (strcmp(o.route, 'B') && strcmp(o.quantity, 'dN/dlog10Da') && ...
        isequal(o.reduced, true)));
    if ~raw && ~((reduced_smps || aac) && strcmp(o.unit, 'cm^-3'))
        fail('Route', 'Unsupported route, source or observation quantity.');
    end
    corrections = {};
    if reduced_smps
        corrections = {'mcc_on', 'dlc_on'};
        for j = 1:numel(corrections)
            key = corrections{j};
            if ~isfield(o, key) || ~islogical(o.(key)) || ~isscalar(o.(key))
                fail('Correction', 'Reduced scans require correction flags.');
            end
        end
    end
    x = o.values;
    if ~real_array(x) || ~isvector(x) || isempty(x) || ...
            any(~isfinite(x(:)) | x(:) < 0)
        fail('Values', 'Observations require finite nonnegative channel vectors.');
    end
    if raw
        if any(x(:) ~= fix(x(:))) || ...
                (isfield(o, 'counts_are_approximate') && o.counts_are_approximate)
            fail('Counts', 'Poisson weights require unsplit integer counts.');
        end
        if ~isfield(o, 'sample_volume_cm3') || ...
                ~real_array(o.sample_volume_cm3) || ...
                ~isvector(o.sample_volume_cm3) || ...
                numel(o.sample_volume_cm3) ~= numel(x) || ...
                any(~isfinite(o.sample_volume_cm3(:)) | o.sample_volume_cm3(:) <= 0)
            fail('Exposure', 'Each raw bin requires its positive sample volume.');
        end
    end
    if raw
        support = {'time_s', 'classifier_time_s', 'voltage_v', 'bin_time_s'};
    elseif strcmp(o.route, 'A')
        support = {'diameter_nm', 'time_s'};
    else
        support = {'diameter_nm'};
    end
    for j = 1:numel(support)
        key = support{j};
        if ~isfield(o, key) || ~real_array(o.(key)) || ...
                any(~isfinite(o.(key)(:))) || ...
                ~isvector(o.(key)) || ...
                ~(numel(o.(key)) == numel(x) || ...
                (strcmp(key, 'bin_time_s') && isscalar(o.(key))))
            fail('Support', 'Observation support must be finite and explicit.');
        end
        if any(strcmp(key, {'bin_time_s', 'diameter_nm', 'voltage_v'})) && ...
                any(o.(key)(:) <= 0)
            fail('Support', 'Durations, diameters and voltage must be positive.');
        end
    end
    if k == 1
        first = o;
        d = struct('raw', raw, 'n', numel(group), 'values', ...
            zeros(numel(x), numel(group)), 'counts', [], 'volume', []);
        d.sources = cell(numel(group), 1);
        d.scans = zeros(numel(group), 1);
        if raw
            d.counts = zeros(size(d.values));
            d.volume = zeros(size(d.values));
        end
    else
        compare = [labels, support, corrections];
        for j = 1:numel(compare)
            key = compare{j};
            if ~isequal(o.(key), first.(key))
                fail('RepeatSupport', 'Repeats must share labels and measured support.');
            end
        end
        if numel(x) ~= size(d.values, 1)
            fail('RepeatSupport', 'Repeat channel counts must agree.');
        end
    end
    d.sources{k} = o.source_id;
    d.scans(k) = double(o.scan_index);
    if raw
        d.counts(:, k) = double(x(:));
        d.volume(:, k) = double(o.sample_volume_cm3(:));
        d.values(:, k) = d.counts(:, k)./d.volume(:, k);
    else
        d.values(:, k) = double(x(:));
    end
end
end

function [a, y] = moment_block(d, minimum)
a = []; y = [];
if d.n < minimum, return; end
mu = mean(d.values, 2);
s2 = var(d.values, 0, 2);
df = d.n-1;
if ~d.raw
    a = sqrt(df)*[ones(size(mu)), mu];
    y = sqrt(df)*s2;
    return
end
% Fitting marginal and scan-scale moments jointly in concentration units
shot = mean(d.counts./d.volume.^2, 2);
scale = max([mu.^2, shot, ones(size(mu))], [], 2);
a = sqrt(df)*[1./scale, mu.^2./scale, mu.^2./scale];
y = sqrt(df)*(s2-shot)./scale;
m = mu.*mean(d.volume, 2);
if sum(m) <= 0, return; end
w = m/sum(m);
h = zeros(size(mu));
positive = mu > 0;
h(positive) = w(positive)./mu(positive);
z = h'*(d.values-mu);
a(end+1, :) = sqrt(df)*[sum(h.^2), sum(w.^2), 1];
y(end+1, 1) = sqrt(df)*(var(z, 0, 2)-sum(h.^2.*shot));
end

function [coef, identified] = fit_components(a, y, p)
coef = zeros(p, 1);
identified = false;
if isempty(a), return; end
if any(~isfinite(a(:))) || any(~isfinite(y(:)))
    fail('Overflow', 'Repeat moments must remain finite.');
end
scales = sqrt(sum(a.^2, 1));
if any(scales == 0), return; end
an = a./scales;
if rank(an) < p, return; end
identified = true;
best = sum(y.^2);
% Enumerating the faces of the two- or three-component nonnegative fit
for mask = 1:(2^p-1)
    active = logical(bitget(mask, 1:p));
    trial = an(:, active)\y;
    if any(trial < 0), continue; end
    residual = y-an(:, active)*trial;
    score = sum(residual.^2);
    if score < best
        best = score;
        coef(:) = 0;
        coef(active) = trial./scales(active)';
    end
end
end

function [vc, vn, within] = weight_variance(d, c)
vn = [];
if any(~isfinite(c))
    vc = NaN(size(d.values, 1), 1);
    within = vc;
    if d.raw, vn = vc; end
    return
end
if d.raw
    within = c(1) + c(2)*d.signal.^2;
    vc = sum(d.shot+within, 2)/d.n^2;
    vn = sum(max(d.expected, d.floor.*d.volume.^2) + ...
        c(1)*d.volume.^2 + c(2)*(d.signal.*d.volume).^2, 2)/d.n^2;
    within = sum(within, 2)/d.n^2;
else
    vc = sum(max(c(1)+c(2)*mean(d.values, 2), d.floor), 2)/d.n^2;
    within = [];
end
end

function bounds = interval(draws, available, n)
bounds = NaN(n, 2);
if ~available, return; end
ordered = sort(draws, 2);
nd = size(draws, 2);
bounds = ordered(:, max(1, ceil([0.025, 0.975]*nd)));
end

function validate_config(cfg)
if ~isstruct(cfg) || ~isscalar(cfg) || ~isfield(cfg, 'variance') || ...
        ~isstruct(cfg.variance) || ~isscalar(cfg.variance)
    fail('Config', 'Expected resolved variance configuration.');
end
v = cfg.variance;
keys = {'model', 'reduced_model', 'aac_model', 'floor_counts', ...
    'min_repeats', 'repeat_scope', 'repeat_treatment', ...
    'propagate_repeat_uncertainty'};
if ~all(isfield(v, keys)) || ...
        ~any(strcmp(v.model, {'auto', 'poisson_two_pass'})) || ...
        ~strcmp(v.reduced_model, 'pooled') || ~strcmp(v.aac_model, 'pooled') || ...
        ~strcmp(v.repeat_scope, 'campaign_mode') || ...
        ~strcmp(v.repeat_treatment, 'split_within_between') || ...
        ~isequal(v.propagate_repeat_uncertainty, true)
    fail('Config', 'Expected two-pass counts, pooled exports and split repeats.');
end
if ~real_array(v.floor_counts) || ~isscalar(v.floor_counts) || ...
        ~isfinite(v.floor_counts) || v.floor_counts <= 0
    fail('Floor', 'The count floor must be strictly positive.');
end
if ~real_array(v.min_repeats) || ~isscalar(v.min_repeats) || ...
        ~isfinite(v.min_repeats) || v.min_repeats < 2 || ...
        v.min_repeats ~= fix(v.min_repeats)
    fail('Config', 'At least two actual repeats are required for a fit.');
end
if ~isfield(cfg, 'rng_seed') || ~real_array(cfg.rng_seed) || ...
        ~isscalar(cfg.rng_seed) || ~isfinite(cfg.rng_seed) || ...
        cfg.rng_seed < 0 || cfg.rng_seed > 2^32-1 || ...
        cfg.rng_seed ~= fix(cfg.rng_seed)
    fail('Config', 'A finite integer random seed is required.');
end
end

function yes = real_array(x)
yes = isnumeric(x) && isreal(x) && ismatrix(x);
end

function fail(reason, message)
error(['sootMosaic:OBS_VARIANCE:' reason], '%s', message);
end
