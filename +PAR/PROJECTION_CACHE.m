function [pa, se, cache, n_new] = PROJECTION_CACHE(pars, cache, opts, draws)
% "PROJECTION_CACHE" returns the isotropic projected areas of all...
%   ...aggregates from PAR.PROJECTION_ISO, reusing the areas of...
%   ...aggregates whose geometry has not changed since their areas were...
%   ...computed.
% ----------------------------------------------------------------------- %
%
% Inputs:
%   pars: Particle information structure
%   cache: Cache returned by the previous call (empty for none)
%   opts: Projection options structure
%       n_pts, n_ori, n_rep: Sampling settings of PAR.PROJECTION_ISO
%       use_cache: true to reuse areas, false to compute every aggregate
%   draws: Random numbers of PAR.PROJECTION_ISO for each aggregate...
%       ...(optional cell array, one entry per aggregate, empty entries...
%       ...drawn with rand)
% ----------------------------------------------------------------------- %
%
% Outputs:
%   pa: Projected area of each aggregate (m2)
%   se: Standard error of pa (m2)
%   cache: Cache for the next call (empty when use_cache is false)
%   n_new: Number of aggregates whose area was computed in this call
% ----------------------------------------------------------------------- %
%
% A single primary has the area pi d^2 / 4 and no sampling error. An...
%   ...aggregate of several primaries is found in the cache by its first...
%   ...primary index and its number of primaries. Each stored area keeps...
%   ...its reference geometry, the primary indices, diameters and...
%   ...positions relative to the first primary at which the area was...
%   ...computed. The area is reused only when the primary indices and...
%   ...diameters equal those of the reference and every relative...
%   ...position differs from the reference by at most 1e-9 of the...
%   ...smallest primary diameter. A reused area keeps its reference, so...
%   ...small changes cannot add up past the tolerance without a new...
%   ...computation. A merge in COL.UNITE, a change of a primary diameter,...
%   ...a removed or added primary and a new order of the primaries change...
%   ...the key or the index list, and any other change of shape moves...
%   ...the relative positions, so each leads to a new computation. A...
%   ...translation changes the relative positions only by the rounding...
%   ...of the absolute coordinates, about eps times the coordinate (1e-21...
%   ...m in a 5 micrometer box against a tolerance near 1e-17 m for 10 nm...
%   ...primaries). These rounding errors can add up over very many moves...
%   ...and then lead to a new computation, never to a stale area. Areas...
%   ...computed with other sampling settings are not reused. The...
%   ...returned cache holds the aggregates of this call only, so the...
%   ...row order of pars does not matter.
% Only the particle structure is accepted. AGG objects stop with...
%   ...sootMosaic:PROJECTION_CACHE:UnsupportedClass.
% ----------------------------------------------------------------------- %

if isa(pars, 'AGG')
    error('sootMosaic:PROJECTION_CACHE:UnsupportedClass', ['The ', ...
        'isotropic projected area takes the particle structure, not AGG ', ...
        'objects.'])
end
if ~exist('draws', 'var')
    draws = {};
end

n_agg = numel(pars.n);
pa = zeros(n_agg, 1);
se = zeros(n_agg, 1);
settings = [opts.n_pts, opts.n_ori, opts.n_rep];

% Entries of the previous call made with the same settings
use_old = opts.use_cache && ~isempty(cache) && ...
    isequal(cache.settings, settings);
if use_old
    key_old = cache.key;
else
    key_old = zeros(0, 2);
end

% Entries of this call (aggregates of more than one primary)
multi = find(pars.n(:) > 1);
key = zeros(numel(multi), 2);
pp_rel = cell(numel(multi), 1);
for m = 1 : numel(multi)
    pp_i = pars.pp{multi(m)};
    key(m, :) = [pp_i(1, 1), size(pp_i, 1)];
    pp_rel{m} = [pp_i(:, 1:2), pp_i(:, 3:5) - pp_i(1, 3:5)];
end
[found, loc] = ismember(key, key_old, 'rows');
entry = zeros(n_agg, 1); % Entry of each aggregate in key
entry(multi) = 1 : numel(multi);

n_new = 0;
for i = 1 : n_agg
    pp_i = pars.pp{i};
    if size(pp_i, 1) == 1
        pa(i) = pi * pp_i(1, 2)^2 / 4; % a sphere
        continue
    end
    m = entry(i);
    if found(m) && same_geometry(pp_rel{m}, cache.pp_ref{loc(m)})
        pa(i) = cache.pa(loc(m));
        se(i) = cache.se(loc(m));
        pp_rel{m} = cache.pp_ref{loc(m)}; % keep the reference geometry
    else
        if numel(draws) >= i && ~isempty(draws{i})
            [pa(i), se(i)] = PAR.PROJECTION_ISO(pp_i, opts.n_pts, ...
                opts.n_ori, opts.n_rep, draws{i});
        else
            [pa(i), se(i)] = PAR.PROJECTION_ISO(pp_i, opts.n_pts, ...
                opts.n_ori, opts.n_rep);
        end
        n_new = n_new + 1;
    end
end

if opts.use_cache
    cache = struct('settings', settings, 'key', key, ...
        'pp_ref', {pp_rel}, 'pa', pa(multi), 'se', se(multi));
else
    cache = [];
end

end

function tf = same_geometry(a, b)
% Same primary indices and diameters as the reference b, relative...
    % ...positions within 1e-9 of the smallest primary diameter of it
tf = isequal(size(a), size(b)) && isequal(a(:, 1:2), b(:, 1:2)) && ...
    max(abs(a(:, 3:5) - b(:, 3:5)), [], 'all') <= 1e-9 * min(a(:, 2));
end
