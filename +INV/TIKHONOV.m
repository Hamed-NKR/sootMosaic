function [x, last_l, precision, info] = TIKHONOV(a, b, lambda_cm3, ...
    order_1, grid, stages_count, floor_cm3_inv, solver)
% "TIKHONOV" solves a zero-mean penalized inversion in explicit stages.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Kernel and observation whitened with OBS_VARIANCE variances
%     lambda_cm3: Positive penalty scale, scalar or one per stage (cm^3)
%     order_1: Order 0 to 2, scalar or one per stage (-)
%     grid: INV.Grid or cell count matching the kernel columns
%     stages_count: Explicit 1 (reported solve) or 2 (cross-check only)
%     floor_cm3_inv: Positive reweighting floor for stage 2 (cm^-3)
%     solver: Nonnegative LSQ solver, non-neg by default
% Outputs:
%     x: Number distribution per logarithmic diameter (cm^-3)
%     last_l: Complete scaled operator used in the last solve (cm^3)
%     precision: Conditional Gaussian precision (cm^6)
%     info: Stage solutions, stage count and cross-check flag
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 26, 38-39);
%     ...Huckle and Sedlacek (2012, Eqs. 1-2); Petters (2021, Eq. 6).
% Petters (2018) is a different paper from the cited Petters (2021).
% Adopted from +invert/tikhonov.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: algebraic diagnostics refused by this wrapper.
% Modified 19 Nov 2026: explicit stages, zero mean and nonnegative default.
% Modified 19 Nov 2026: final reweighted operator retained in precision;
%     ...reweighting uses x divided by 1 cm^-3 to keep scale units fixed.
% Modified 19 Nov 2026: grid penalties, explicit floor and stage diagnostics.

if nargin < 5 || isempty(grid), grid = size(a, 2); end
if nargin < 6 || isempty(stages_count), stages_count = 1; end
if nargin < 7, floor_cm3_inv = []; end
if nargin < 8, solver = 'non-neg'; end
if strcmp(solver, 'algebraic')
    error('sootMosaic:TIKHONOV:Solver', ...
        'Require a nonnegative solver.');
end
if ~isscalar(stages_count) || ~ismember(stages_count, [1, 2])
    error('sootMosaic:TIKHONOV:Stages', ...
        'Require one or two explicit stages.');
end
if ~isnumeric(lambda_cm3) || ~isreal(lambda_cm3) || ...
        ~isvector(lambda_cm3) || any(~isfinite(lambda_cm3)) || ...
        any(lambda_cm3 <= 0) || ...
        ~ismember(numel(lambda_cm3), [1, stages_count]) || ...
        ~isnumeric(order_1) || ~isvector(order_1) || ...
        any(~ismember(order_1, 0:2)) || ...
        ~ismember(numel(order_1), [1, stages_count])
    error('sootMosaic:TIKHONOV:Parameters', ...
        'Require one value per stage.');
end
if stages_count == 2 && (~isnumeric(floor_cm3_inv) || ...
        ~isreal(floor_cm3_inv) || ~isscalar(floor_cm3_inv) || ...
        ~isfinite(floor_cm3_inv) || floor_cm3_inv <= 0)
    error('sootMosaic:TIKHONOV:Floor', ...
        'Require a positive stage-two floor.');
end
lambda_cm3 = lambda_cm3(:).*ones(stages_count, 1);
order_1 = order_1(:).*ones(stages_count, 1);
n = size(a, 2);
values = zeros(n, stages_count);
x = [];
for k = 1:stages_count
    last_l = lambda_cm3(k)*INV.TIKHONOV_LPR(order_1(k), grid);
    if size(last_l, 2) ~= n
        error('sootMosaic:TIKHONOV:Shape', ...
            'Grid must match kernel columns.');
    end
    if k > 1
        d2 = spdiags(1./max(abs(x), floor_cm3_inv), 0, n, n);
        last_l = last_l*d2;
    end
    x = INV.LSQ([a; last_l], [b; zeros(size(last_l, 1), 1)], x, solver);
    values(:, k) = x;
end
[~, precision] = INV.POSTERIOR(a, last_l);
info = struct('stages_count', stages_count, 'stage_cm3_inv', values, ...
    'cross_check_1', stages_count > 1, ...
    'active_share_1', mean(x <= 0));
end
