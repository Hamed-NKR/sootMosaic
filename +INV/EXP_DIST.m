function [x, last_l, precision, info] = EXP_DIST(a, b, lambda_cm3, ...
    length_decades, grid, solver)
% "EXP_DIST" solves a nonnegative inversion with an exponential prior.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Kernel and data whitened with OBS_VARIANCE variances
%     lambda_cm3: Positive penalty scale (cm^3)
%     length_decades: Correlation length supplied by the caller (decades)
%     grid: One-dimensional log grid or diameter vector (nm)
%     solver: Nonnegative LSQ solver, non-neg by default
% Outputs:
%     x: Number distribution per logarithmic diameter (cm^-3)
%     last_l: Scaled prior operator (cm^3)
%     precision: Conditional Gaussian precision (cm^6)
%     info: Stage count and diagnostic flag (-)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 26, 38, 42-46).
% Adopted from +invert/exp_dist.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: algebraic diagnostics refused by this wrapper.
% Modified 19 Nov 2026: validated scales, exact covariance factor, zero...
%     ...prior mean, package calls and explicit one-stage diagnostics.

if nargin < 6, solver = 'non-neg'; end
if strcmp(solver, 'algebraic')
    error('sootMosaic:EXP_DIST:Solver', ...
        'Require a nonnegative solver.');
end
if ~isnumeric(lambda_cm3) || ~isreal(lambda_cm3) || ...
        ~isscalar(lambda_cm3) || ~isfinite(lambda_cm3) || lambda_cm3 <= 0
    error('sootMosaic:EXP_DIST:Lambda', ...
        'Require a positive scalar scale.');
end
last_l = lambda_cm3*INV.EXP_DIST_LPR(length_decades, grid);
if size(last_l, 2) ~= size(a, 2)
    error('sootMosaic:EXP_DIST:Shape', ...
        'Grid must match kernel columns.');
end
x = INV.LSQ([a; last_l], [b; zeros(size(last_l, 1), 1)], [], solver);
[~, precision] = INV.POSTERIOR(a, last_l);
info = struct('stages_count', 1, 'cross_check_1', ...
    false, 'active_share_1', mean(x <= 0));
end
