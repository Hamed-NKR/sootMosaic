function [draws_cm3_inv, info] = TGIBBS(precision_cm6, rhs_cm3, ...
    options, statistic_1)
% "TGIBBS" samples a Gaussian restricted to nonnegative distributions.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     precision_cm6: Positive definite Gaussian precision (cm^6)
%     rhs_cm3: Whitened a'*b, not precision times the constrained mode (cm^3)
%     options: Optional burn_count=500, batch_count=1000,...
%         ...max_draws_count=16000 and seed_1=27
%     statistic_1: Optional function mapping a state to a column of...
%         ...dimensionless check statistics; default is state / 1 cm^-3
% Outputs:
%     draws_cm3_inv: States by retained sweeps by four chains (cm^-3)
%     info: Split convergence ratios, effective counts and relative...
%         ...Monte Carlo errors of the 2.5 and 97.5 percent endpoints....
%         ...resolved_1 requires all checks; false means unresolved
% ----------------------------------------------------------------------- %
% Method: Bardsley and Fox (2012), nonnegative Gaussian sampling;
%     ...Robert (1995), exponential rejection for truncated normal tails;
%     ...Sipkens et al. (2020, part II, Eqs. 25-26) for Gaussian precision.
% Reimplementation using exact scalar conditional draws. Four dispersed...
%     ...chains extend in batches. Endpoint errors use eight batch...
%     ...quantiles per chain and include between-chain variation.

if nargin < 3, options = struct(); end
if nargin < 4, statistic_1 = @(x) x; end
defaults = struct('burn_count', 500, 'batch_count', 1000, ...
    'max_draws_count', 16000, 'seed_1', 27);
if ~isstruct(options) || ~isscalar(options) || ...
        any(~ismember(fieldnames(options), fieldnames(defaults)))
    error('sootMosaic:TGIBBS:Options', ...
        'Unknown sampler option.');
end
keys = fieldnames(defaults);
for k = 1:numel(keys)
    key = keys{k};
    if ~isfield(options, key), options.(key) = defaults.(key); end
    v = options.(key);
    if ~isnumeric(v) || ~isreal(v) || ~isscalar(v) || ...
            ~isfinite(v) || v < 0 || v ~= fix(v)
        error('sootMosaic:TGIBBS:Options', ...
            'Require nonnegative integer options.');
    end
end
if options.batch_count < 32 || ...
        options.max_draws_count < options.batch_count || ...
        options.seed_1 > 2^32-1 || ~isa(statistic_1, 'function_handle')
    error('sootMosaic:TGIBBS:Options', ...
        'Require valid batch sizes and statistic.');
end
q = precision_cm6;
h = rhs_cm3;
n = numel(h);
if ~isnumeric(q) || ~isreal(q) || ~isequal(size(q), [n, n]) || ...
        ~isnumeric(h) || ~isreal(h) || isempty(h) || size(h, 2) ~= 1 || ...
        any(~isfinite(q(:))) || any(~isfinite(h)) || ...
        norm(q-q', 'fro') > 1e-12*norm(q, 'fro')
    error('sootMosaic:TGIBBS:Precision', ...
        'Require a symmetric finite precision.');
end
q = (q+q')/2;
[~, flag] = chol(q);
if flag ~= 0
    error('sootMosaic:TGIBBS:Precision', ...
        'Require positive definite precision.');
end
saved = rng;
restore = onCleanup(@() rng(saved));
rng(options.seed_1, 'twister');
mu = q\h;
sd = 1./sqrt(diag(q));
state = max(mu, 0) + sd*[0, 1, 3, 6];
for sweep = 1:options.burn_count
    state = advance(state, q, h, sd);
end
draws_cm3_inv = zeros(n, options.max_draws_count, 4);
probe = statistic_1(state(:, 1));
validate_statistic(probe, numel(probe));
stats = zeros(numel(probe), options.max_draws_count, 4);
count = 0;
resolved = false;
while count < options.max_draws_count && ~resolved
    stop = min(options.max_draws_count, count+options.batch_count);
    for sweep = count+1:stop
        state = advance(state, q, h, sd);
        draws_cm3_inv(:, sweep, :) = reshape(state, n, 1, 4);
        for chain = 1:4
            value = statistic_1(state(:, chain));
            validate_statistic(value, numel(probe));
            stats(:, sweep, chain) = value;
        end
    end
    count = stop;
    [rhat, ess, endpoint] = diagnose(stats(:, 1:count, :));
    resolved = all(rhat < 1.01) && all(endpoint(:) < 0.05);
end
draws_cm3_inv = draws_cm3_inv(:, 1:count, :);
info = struct('rhat_1', rhat, 'ess_count', ess, ...
    'endpoint_mcse_share_1', endpoint, 'resolved_1', resolved, ...
    'draws_count', count, 'chains_count', 4);
end

function state = advance(state, q, h, sd)
for chain = 1:4
    for j = 1:size(state, 1)
        center = (h(j)-q(j,:)*state(:,chain)+q(j,j)*state(j,chain))/q(j,j);
        lower = -center/sd(j);
        if lower > 0
            rate = (lower+hypot(lower, 2))/2;
            accepted = false;
            while ~accepted
                z = lower-log(max(realmin, rand))/rate;
                accepted = log(max(realmin, rand)) <= -(z-rate)^2/2;
            end
        else
            tail = 0.5*erfc(lower/sqrt(2));
            z = sqrt(2)*erfcinv(2*tail*max(realmin, rand));
        end
        state(j, chain) = sd(j)*(z-lower);
    end
end
end

function validate_statistic(v, n)
if ~isnumeric(v) || ~isreal(v) || ~isequal(size(v), [n, 1]) || ...
        isempty(v) || any(~isfinite(v))
    error('sootMosaic:TGIBBS:Statistic', ...
        'Require a finite statistic column.');
end
end

function [rhat, ess, endpoint] = diagnose(y)
[n, count, ~] = size(y);
half = floor(count/2);
split = cat(3, y(:, 1:half, :), y(:, count-half+1:count, :));
w = mean(var(split, 0, 2), 3);
between = half*var(mean(split, 2), 0, 3);
v = (half-1)/half*w + between/half;
rhat = sqrt(v./w);
rhat(~isfinite(rhat)) = Inf;
ess = zeros(n, 1);
endpoint = Inf(n, 2);
block = floor(count/8);
for j = 1:n
    z = reshape(y(j, :, :), count, 4);
    bounds = quantiles(z(:), [0.025, 0.975]);
    batch = zeros(32, 2);
    chain_bounds = zeros(4, 2);
    for chain = 1:4
        chain_bounds(chain, :) = quantiles(z(:, chain), [0.025, 0.975]);
        for k = 1:8
            batch((chain-1)*8+k, :) = ...
                quantiles(z((k-1)*block+(1:block), chain), [0.025, 0.975]);
        end
    end
    width = (bounds(2)-bounds(1))/2;
    if width > 0
        endpoint(j, :) = max(std(batch, 0, 1)/sqrt(32), ...
            std(chain_bounds, 0, 1)/2)/width;
    end
    centered = reshape(split(j, :, :), half, 8);
    centered = centered-mean(centered, 1);
    pairs = 0;
    previous = Inf;
    for lag = 1:2:half-2
        pair = 0;
        for offset = 0:1
            shift = lag+offset;
            ac = mean(sum(centered(1:end-shift, :).* ...
                centered(1+shift:end, :), 1)/(half-shift));
            pair = pair + 1-(w(j)-ac)/max(v(j), realmin);
        end
        if pair <= 0, break; end
        pair = min(pair, previous);
        pairs = pairs+pair;
        previous = pair;
    end
    ess(j) = min(8*half, 8*half/max(1, 1+2*pairs));
end
end

function q = quantiles(x, p)
x = sort(x(:));
t = 1+(numel(x)-1)*p;
lo = floor(t);
hi = ceil(t);
q = reshape(x(lo), size(p)).*(hi-t) + ...
    reshape(x(hi), size(p)).*(t-lo);
same = lo == hi;
q(same) = x(lo(same));
end
