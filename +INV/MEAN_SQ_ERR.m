function mse = MEAN_SQ_ERR(a, x, b)
% "MEAN_SQ_ERR" averages squared residuals at nonzero observations.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a: Nonnegative kernel mapping x into the observation unit
%     x: Nonnegative distribution column (cm^-3)
%     b: Nonnegative observation column in the same unit as a*x
% Outputs:
%     mse: Mean squared residual in squared observation units; NaN when...
%         ...all observations are zero. No error normalization is applied
% ----------------------------------------------------------------------- %
% Method: Markowski (1987, Eq. 8), mean-square stopping criterion;
%     ...Twomey (1975, Eq. 7). The source statistic is unweighted and...
%     ...excludes zero observations, unlike the error-scaled paper criterion.
% Adopted from +tools/mean_sq_err.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: package name, identifiers and header layout.
% Modified 19 Nov 2026: finite nonnegative matrix and column validation.
% Modified 19 Nov 2026: documented squared units and empty-selection NaN;
%     ...the source squared residual and nonzero-observation mean are kept.

if ~isnumeric(a) || ~isreal(a) || ~ismatrix(a) || isempty(a) || ...
        any(~isfinite(a(:)) | a(:) < 0) || ~isnumeric(x) || ...
        ~isreal(x) || ~isequal(size(x), [size(a, 2), 1]) || ...
        any(~isfinite(x) | x < 0) || ~isnumeric(b) || ~isreal(b) || ...
        ~isequal(size(b), [size(a, 1), 1]) || any(~isfinite(b) | b < 0)
    error('sootMosaic:MEAN_SQ_ERR:Input', ...
        'Require finite nonnegative arrays with compatible columns.');
end
sq_err = (a*x-b).^2;
mse = mean(sq_err(b ~= 0));
end
