function [l, distance, covariance] = EXP_DIST_LPR(length_decades, grid)
% "EXP_DIST_LPR" factors an exponential covariance in logarithmic size.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     length_decades: Positive correlation length (decades)
%     grid: One-dimensional log INV.Grid or increasing diameter vector (nm)
% Outputs:
%     l: Prior factor satisfying l'*l = covariance inverse (-)
%     distance: Pairwise distance divided by correlation length (-)
%     covariance: Unit-amplitude exponential covariance (-)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 42-46), in one dimension.
% Adopted from +invert/exp_dist_lpr.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: exact covariance factor without distance cutoff,...
%     ...boundary overwrites or pseudoinverse; validated one-dimensional grid.

if isa(grid, 'INV.Grid')
    if grid.dim ~= 1 || ~strcmp(grid.discrete, 'log')
        error('sootMosaic:EXP_DIST_LPR:Grid', ...
            'Require a one-dimensional log grid.');
    end
    grid = grid.elements;
end
if ~isnumeric(grid) || ~isreal(grid) || ~isvector(grid) || ...
        isempty(grid) || any(~isfinite(grid)) || any(grid <= 0) || ...
        any(diff(grid(:)) <= 0) || ~isnumeric(length_decades) || ...
        ~isreal(length_decades) || ~isscalar(length_decades) || ...
        ~isfinite(length_decades) || length_decades <= 0
    error('sootMosaic:EXP_DIST_LPR:Input', ...
        'Require positive ordered sizes and length.');
end
z = log10(grid(:));
distance = abs(z-z')/length_decades;
covariance = exp(-distance);
[r, flag] = chol(covariance, 'lower');
if flag ~= 0
    error('sootMosaic:EXP_DIST_LPR:Covariance', ...
        'Covariance is not positive definite.');
end
l = r\eye(numel(z));
end
