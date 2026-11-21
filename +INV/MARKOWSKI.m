function [x, g, mse] = MARKOWSKI(a, b, x, iterations_count)
% "MARKOWSKI" smooths a one-dimensional cross-check distribution.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Nonnegative kernel and observations in matching units
%     x: Nonnegative distribution (cm^-3)
%     iterations_count: Maximum smoothing passes, default 1000 (-)
% Outputs:
%     x: Smoothed distribution (cm^-3)
%     g: Three-point smoothing operator (-)
%     mse: Source stopping statistic in squared observation units; NaN...
%         ...when all observations are zero
% ----------------------------------------------------------------------- %
% Method: Markowski (1987, Eq. 7); Twomey (1975, Eq. 7).
% Adopted from +invert/markowski.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: explicit one-dimensional stencil, assigned error...
%     ...output, validated inputs and package calls; no console output.
% Modified 19 Nov 2026: unused source arguments omitted; threshold 2 retained.
% Modified 19 Nov 2026: squared statistic units and empty selection stated.

if nargin < 4, iterations_count = 1000; end
if ~isnumeric(x) || ~isreal(x) || size(x, 2) ~= 1 || numel(x) < 2 || ...
        any(~isfinite(x) | x < 0) || ~isnumeric(iterations_count) || ...
        ~isscalar(iterations_count) || ~isfinite(iterations_count) || ...
        iterations_count < 1 || iterations_count ~= fix(iterations_count)
    error('sootMosaic:MARKOWSKI:Input', ...
        'Require a distribution and positive pass count.');
end
INV.MEAN_SQ_ERR(a, x, b);
n = numel(x);
g = spdiags(repmat([0.25, 0.5, 0.25], n, 1), -1:1, n, n);
g(1, 1) = 0.75;
g(end, end) = 0.75;
for k = 1:iterations_count
    x = g*x;
    mse = INV.MEAN_SQ_ERR(a, x, b);
    if mse > 2, return; end
end
end
