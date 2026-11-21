function l = TIKHONOV_LPR(order_1, grid)
% "TIKHONOV_LPR" builds difference penalties with zero exterior values.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     order_1: Difference order 0, 1 or 2 (-)
%     grid: Cell count or uniform log INV.Grid, including INV.PartialGrid
% Outputs:
%     l: Dimensionless penalty per cell index, with both exterior ends...
%         ...included in order 1; order 2 uses centered differences (-)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 38-39);
%     ...Huckle and Sedlacek (2012, Eq. 1).
% Adopted from +invert/tikhonov_lpr.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: zero exterior at both ends, uniform-grid checks,...
%     ...partial-grid gaps as exterior, two-dimensional differences.

if ~isnumeric(order_1) || ~isscalar(order_1) || ...
        ~ismember(order_1, 0:2)
    error('sootMosaic:TIKHONOV_LPR:Order', ...
        'Require order 0, 1 or 2.');
end
if isa(grid, 'INV.Grid')
    dims = grid.ne;
    keep = (1:prod(dims))';
    if isa(grid, 'INV.PartialGrid'), keep = grid.retained; end
    if ~strcmp(grid.discrete, 'log')
        error('sootMosaic:TIKHONOV_LPR:Grid', ...
            'Require log coordinates.');
    end
    for k = 1:grid.dim
        h = diff(log10(grid.edges{k}));
        if max(abs(h-h(1))) > 1e-10*max(1, abs(h(1)))
            error('sootMosaic:TIKHONOV_LPR:Spacing', ...
                'Require uniform log spacing on each axis.');
        end
    end
elseif isnumeric(grid) && isreal(grid) && isscalar(grid) && ...
        isfinite(grid) && grid >= 1 && grid == fix(grid)
    dims = grid;
    keep = (1:grid)';
else
    error('sootMosaic:TIKHONOV_LPR:Grid', ...
        'Require a grid or cell count.');
end
n = prod(dims);
if order_1 == 0
    l = speye(numel(keep));
    return
end
parts = cell(1, numel(dims));
for k = 1:numel(dims)
    nk = dims(k);
    e = speye(nk);
    if order_1 == 1
        t = [e; sparse(1, nk)] - [sparse(1, nk); e];
    else
        t = -e + spdiags(0.5*ones(nk, 2), [-1, 1], nk, nk);
    end
    t = kron(speye(prod(dims(k+1:end))), ...
        kron(t, speye(prod(dims(1:k-1)))));
    if order_1 == 2, t = t(keep, :); end
    parts{k} = t(:, keep);
end
l = vertcat(parts{:});
if size(l, 2) ~= numel(keep) || n < numel(keep)
    error('sootMosaic:TIKHONOV_LPR:Shape', ...
        'Inconsistent grid.');
end
end
