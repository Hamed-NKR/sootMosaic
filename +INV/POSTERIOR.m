function [covariance, precision] = POSTERIOR(a, last_l)
% "POSTERIOR" returns the Gaussian covariance for the last-stage operator.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a: Whitened kernel (cm^3)
%     last_l: Scaled prior including any stage-two diagonal (cm^3)
% Outputs:
%     covariance: Conditional Gaussian covariance (cm^-6)
%     precision: Conditional Gaussian precision (cm^6)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eq. 26 and its caveat).
% Conditional on the weights, prior and last-stage diagonal. Approximate...
%     ...under nonnegativity; the constrained mode is not a Gaussian mean.
% Adopted from the precision expression in +invert/tikhonov.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: actual final operator, checked factorization and...
%     ...covariance by triangular solves; no inverse or diagonal clipping.

if ~isnumeric(a) || ~isreal(a) || isempty(a) || ...
        ~isnumeric(last_l) || ~isreal(last_l) || ...
        size(a, 2) ~= size(last_l, 2) || ...
        any(~isfinite(a(:))) || any(~isfinite(last_l(:)))
    error('sootMosaic:POSTERIOR:Input', ...
        'Require finite compatible matrices.');
end
precision = a'*a + last_l'*last_l;
[r, flag] = chol(precision);
if flag ~= 0
    error('sootMosaic:POSTERIOR:Precision', ...
        'Require positive precision.');
end
covariance = r\(r'\eye(size(a, 2)));
covariance = (covariance+covariance')/2;
end
