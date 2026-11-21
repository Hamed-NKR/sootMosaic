function value_1 = LOGDET(a)
% "LOGDET" computes a real log determinant without forming its magnitude.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a: Finite real square matrix in a fixed reference unit
% Outputs:
%     value_1: Natural log determinant relative to that reference (-)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 30-34).
% Adopted from +tools/logdet.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% The source has no copyright or license block; see repository LICENSE.
% Modified 19 Nov 2026: package name, argument checks and header layout.
% Modified 19 Nov 2026: reject singular and negative determinants instead...
%     ...of discarding the imaginary part of their logarithm.

if ~isnumeric(a) || ~isreal(a) || ~ismatrix(a) || isempty(a) || ...
        size(a, 1) ~= size(a, 2) || any(~isfinite(a(:)))
    error('sootMosaic:LOGDET:Input', 'Require a finite real square matrix.');
end
[~, u, p] = lu(double(a));
d = diag(u);
if any(d == 0)
    error('sootMosaic:LOGDET:Singular', 'Require a nonzero determinant.');
end
sign_1 = det(p)*prod(sign(d));
if sign_1 <= 0
    error('sootMosaic:LOGDET:Nonpositive', ...
        'Require a positive determinant for a real logarithm.');
end
value_1 = sum(log(abs(d)));
end
