function [x, info] = TWOMEY(a, b, xi, iterations_count, stopping_1)
% "TWOMEY" computes a multiplicative inversion for a cross-check.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Nonnegative kernel and observation in matching units
%     xi: Nonnegative starting distribution (cm^-3), default ones
%     iterations_count: Maximum full passes, default 100 (-)
%     stopping_1: Enable the source mean-square stopping rule, default true
% Outputs:
%     x: Number distribution per logarithmic diameter (cm^-3)
%     info: Pass count and cross-check flag (-)
% ----------------------------------------------------------------------- %
% Method: Twomey (1975, Eq. 7); Markowski (1987, Eqs. 3-4).
% Adopted from +invert/twomey.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: package calls, validation and finite zero rows.
% Modified 19 Nov 2026: no progress output; explicit cross-check diagnostics.

if nargin < 3 || isempty(xi), xi = ones(size(a, 2), 1); end
if nargin < 4 || isempty(iterations_count), iterations_count = 100; end
if nargin < 5 || isempty(stopping_1), stopping_1 = true; end
if ~isnumeric(a) || ~isreal(a) || isempty(a) || ...
        any(~isfinite(a(:)) | a(:) < 0) || ~isnumeric(b) || ...
        ~isreal(b) || ~isequal(size(b), [size(a, 1), 1]) || ...
        any(~isfinite(b) | b < 0) || ~isnumeric(xi) || ~isreal(xi) || ...
        ~isequal(size(xi), [size(a, 2), 1]) || ...
        any(~isfinite(xi) | xi < 0) || ...
        ~isnumeric(iterations_count) || ~isscalar(iterations_count) || ...
        ~isfinite(iterations_count) || iterations_count < 1 || ...
        iterations_count ~= fix(iterations_count) || ...
        ~islogical(stopping_1) || ~isscalar(stopping_1)
    error('sootMosaic:TWOMEY:Input', ...
        'Require nonnegative arrays and valid controls.');
end
x = xi;
peak = max(a, [], 2);
if any(peak == 0 & b > 0)
    error('sootMosaic:TWOMEY:Support', ...
        'A positive observation has zero response.');
end
s = zeros(size(peak));
keep = peak > 0 & peak >= max(peak)*1e-10;
s(keep) = 1./peak(keep);
a = a.*s;
b = b.*s;
for k = 1:iterations_count
    for j = 1:numel(b)
        if b(j) ~= 0
            y = a(j, :)*x;
            if y ~= 0
                factor = 1+(b(j)/y-1)*a(j, :)';
                x = factor.*x;
            end
        end
    end
    if stopping_1 && INV.MEAN_SQ_ERR(a, x, b) < 0.6
        break
    end
end
if any(~isfinite(x))
    error('sootMosaic:TWOMEY:Finite', ...
        'Iteration produced a nonfinite value.');
end
info = struct('iterations_count', k, 'cross_check_1', true);
end
