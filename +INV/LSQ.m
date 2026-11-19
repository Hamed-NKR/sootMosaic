function [x, d, info] = LSQ(a, b, xi, solver)
% "LSQ" solves a weighted least-squares system with a zero lower bound.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Weighted matrix and column data, including any prior rows
%     xi: Optional start in solution units; never a lower bound
%     solver: non-neg (default), interior-point, trust-region-reflective,...
%         ...or algebraic for an unconstrained diagnostic only
% Outputs:
%     x: Solution in the distribution unit
%     d: Unconstrained inverse operator, empty for constrained solves
%     info: Bound share and relative optimality residual (-)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eq. 38).
% Adopted from +invert/lsq.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: validation, zero bounds, feasible starts, quiet...
%     ...solves, optimality checks and verified nonnegative retry.
% Modified 19 Nov 2026: direct least squares replaces normal inversion.
% Modified 19 Nov 2026: optimality checks every strictly positive coordinate.

if nargin < 3, xi = []; end
if nargin < 4 || isempty(solver), solver = 'non-neg'; end
if ~isnumeric(a) || ~isreal(a) || isempty(a) || ...
        any(~isfinite(a(:))) || ~isnumeric(b) || ~isreal(b) || ...
        size(b, 2) ~= 1 || size(a, 1) ~= numel(b) || ...
        any(~isfinite(b)) || size(a, 1) < size(a, 2)
    error('sootMosaic:LSQ:Input', ...
        'Require a finite tall system.');
end
n = size(a, 2);
if ~isempty(xi) && (~isnumeric(xi) || ~isreal(xi) || ...
        ~isequal(size(xi), [n, 1]) || any(~isfinite(xi)))
    error('sootMosaic:LSQ:Start', ...
        'Require one finite start per column.');
end
if ~any(strcmp(solver, {'non-neg', 'interior-point', ...
        'trust-region-reflective', 'algebraic'}))
    error('sootMosaic:LSQ:Solver', ...
        'Unknown solver.');
end
if rank(full(a)) < n
    error('sootMosaic:LSQ:Rank', ...
        'Require full column rank.');
end
d = [];
if strcmp(solver, 'algebraic')
    x = a\b;
    d = a\eye(size(a, 1));
else
    if strcmp(solver, 'non-neg')
        x = lsqnonneg(full(a), b, optimset('Display', 'off'));
    else
        if isempty(xi), xi = a\b; end
        xi = max(xi, 0);
        options = optimoptions('lsqlin', 'Algorithm', solver, ...
            'Display', 'off');
        x = lsqlin(a, b, [], [], [], [], zeros(n, 1), [], xi, options);
    end
    if optimality(a, b, x) > 1e-8
        x = lsqnonneg(full(a), b, optimset('Display', 'off'));
    end
    if optimality(a, b, x) > 1e-8
        error('sootMosaic:LSQ:Optimality', ...
            'Nonnegative solve failed.');
    end
end
info = struct('active_share_1', mean(x <= 0), ...
    'optimality_1', optimality(a, b, x));
end

function value = optimality(a, b, x)
if isempty(x) || any(~isfinite(x))
    value = Inf;
    return
end
g = a'*(a*x-b);
scale = max(1, norm(a'*b, Inf));
free = x > 0;
r = g;
r(~free) = min(g(~free), 0);
value = max(norm(r, Inf)/scale, ...
    max(0, -min(x))/max(1, norm(x, Inf)));
end
