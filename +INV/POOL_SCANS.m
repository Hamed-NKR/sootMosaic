function result = POOL_SCANS(parts)
% "POOL_SCANS" pools repeat summaries on common measured diameter bins.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     parts: Cell array of summaries with diameter_nm, mean, variance, n,
%         ...quantity, unit, group and dilution_applied. Variance uses...
%         ...the sample denominator n-1; n is the finite count per bin
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Pooled mean, sample variance and per-bin count. No padding,...
%         ...extrapolation, synthetic repeats or dilution is performed
% ----------------------------------------------------------------------- %
% Method: Pooled variance identity, M2 = sum((n_i-1) s_i^2 +...
%     ...n_i (mean_i-mean)^2), with variance M2/(sum(n_i)-1).

if ~iscell(parts) || isempty(parts)
    fail('Input', 'At least one summary is required in a cell array.');
end
required = {'diameter_nm', 'mean', 'variance', 'n', 'quantity', ...
    'unit', 'group', 'dilution_applied'};
for k = 1:numel(parts)
    p = parts{k};
    for j = 1:numel(required)
        if ~isfield(p, required{j}), fail('MissingField', required{j}); end
    end
    d = p.diameter_nm(:);
    if any(~isfinite(d) | d <= 0) || numel(unique(d)) ~= numel(d) || ...
            numel(p.mean) ~= numel(d) || numel(p.variance) ~= numel(d) || ...
            numel(p.n) ~= numel(d)
        fail('Shape', 'Summary arrays require distinct positive diameter bins.');
    end
    n = p.n(:);
    active = n > 0;
    if any(~isfinite(n) | n < 0 | n ~= fix(n)) || ...
            any(~isfinite(p.mean(active))) || ...
            any(~isfinite(p.variance(active)) | p.variance(active) < 0)
        fail('Summary', 'Invalid counts, means or variances.');
    end
    if any(p.variance(n == 1) ~= 0)
        fail('SingleScanVariance', 'A single scan has zero sample spread.');
    end
    if k == 1
        common = d(active);
    else
        for name = {'quantity', 'unit', 'group', 'dilution_applied'}
            if ~isequal(p.(name{1}), parts{1}.(name{1}))
                fail('Incompatible', ['Cannot pool different ' name{1} '.']);
            end
        end
        common = intersect(common, d(active));
    end
end
common = sort(common);
if isempty(common), fail('CommonSupport', 'No common measured diameter bins.'); end
n = zeros(size(common));
mu = zeros(size(common));
m2 = zeros(size(common));
for k = 1:numel(parts)
    p = parts{k};
    [~, at] = ismember(common, p.diameter_nm);
    ni = reshape(p.n(at), [], 1);
    mi = reshape(p.mean(at), [], 1);
    vi = reshape(p.variance(at), [], 1);
    total = n + ni;
    delta = mi - mu;
    m2 = m2 + (ni-1) .* vi + delta.^2 .* n .* ni ./ total;
    mu = mu + delta .* ni ./ total;
    n = total;
end
result = struct('diameter_nm', common, 'mean', mu, 'n', n, ...
    'variance', m2 ./ max(n-1, 1), 'quantity', parts{1}.quantity, ...
    'unit', parts{1}.unit, 'group', parts{1}.group, ...
    'dilution_applied', parts{1}.dilution_applied);
result.std = sqrt(result.variance);
end

function fail(reason, message)
error(['sootMosaic:POOL_SCANS:' reason], '%s', message);
end
