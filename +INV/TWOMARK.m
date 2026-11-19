function [x, info] = TWOMARK(a, b, xi)
% "TWOMARK" alternates multiplicative inversion and smoothing as a check.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Nonnegative kernel and observations in matching units
%     xi: One-dimensional starting distribution (cm^-3), default ones
% Outputs:
%     x: Cross-check number distribution (cm^-3)
%     info: Outer pass count and cross-check flag (-)
% ----------------------------------------------------------------------- %
% Method: Twomey (1975, Eq. 7); Markowski (1987, Eq. 7);
%     ...Sipkens et al. (2020, part I, Sec. 4.2); Buckley et al. (2017).
% Adopted from +invert/twomark.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: package calls, one-dimensional shape validation,...
%     ...default start and diagnostics; no progress or console output.
% Modified 19 Nov 2026: unused source smoothing controls omitted; source...
%     ...limits 40 outer, 150 inversion and 1000 smoothing passes retained.

if nargin < 3 || isempty(xi), xi = ones(size(a, 2), 1); end
if size(a, 2) < 3
    error('sootMosaic:TWOMARK:Size', ...
        'Require at least three distribution cells.');
end
x = INV.TWOMEY(a, b, xi, 150);
previous = roughness(x);
for k = 1:40
    saved = x;
    x = INV.MARKOWSKI(a, b, x, 1000);
    x = INV.TWOMEY(a, b, x, 150);
    current = roughness(x);
    if current > previous
        x = saved;
        break
    end
    previous = current;
end
info = struct('iterations_count', k, 'cross_check_1', true);
end

function r = roughness(x)
r = sum(abs(x(3:end)+x(1:end-2)-2*x(2:end-1)))/(numel(x)-2);
end
