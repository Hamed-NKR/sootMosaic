function [value, jacobian, detail] = peak_statistics(x, grid, window_nm, ...
    cap_nm, mass_kg)
% "peak_statistics" integrates fixed bands of a cellwise distribution.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     x: Cell densities dN/dlog10(d) (cm^-3)
%     grid: One-dimensional log grid (nm)
%     window_nm: Fixed reporting limits (nm)
%     cap_nm: Upper end of fraction bands (nm)
%     mass_kg: Positive mass per particle per cell (kg)
% Outputs:
%     value: N, log10 GM, log10 GSD, skewness, Pearson kurtosis,...
%         ...FN, FM, TF and log10 mode, in that order
%     jacobian: Derivatives on the same scales
%     detail: Mode locations, boundary flag and refinement status
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eq. 23), log-cell quadrature;
%     ...Sipkens et al. (2020, part II, Eq. 26), covariance propagation.
% Reimplementation of normalized central log moments and ratio derivatives.

edges = log10(grid.nodes{1}(:));
lo = max(edges(1:end-1), log10(window_nm(1)));
hi = max(lo, min(edges(2:end), log10(window_nm(2))));
w = hi-lo;
total = w'*x;
if total <= 0
    error('sootMosaic:peak_statistics:EmptyWindow', ...
        'Require positive number in the reporting window.');
end
mu = ((hi.^2-lo.^2)/2)'*x/total;
central = zeros(numel(x), 5);
central(:, 1) = w;
for k = 1:4
    central(:, k+1) = ((hi-mu).^(k+1)-(lo-mu).^(k+1))/(k+1);
end
mom = central'*x/total;
v = mom(3);
if v <= 0
    error('sootMosaic:peak_statistics:Degenerate', ...
        'Require positive log variance.');
end
dmu = (central(:, 2)/total)';
dv = ((central(:, 3)-v*w)/total)';
d3 = ((central(:, 4)-mom(4)*w)/total)'-3*v*dmu;
d4 = ((central(:, 5)-mom(5)*w)/total)'-4*mom(4)*dmu;
value = [total; mu; sqrt(v); mom(4)/v^1.5; mom(5)/v^2; 0; 0; 0; 0];
jacobian = zeros(9, numel(x));
jacobian(1:5, :) = [w'; dmu; dv/(2*sqrt(v)); ...
    d3/v^1.5-1.5*mom(4)*dv/v^2.5; ...
    d4/v^2-2*mom(5)*dv/v^3];
upper = max(window_nm(2), cap_nm);
a = band(edges, window_nm(1), upper);
b = band(edges, window_nm(2), upper);
[value(6), jacobian(6, :)] = fraction(x, a, b);
[value(7), jacobian(7, :)] = fraction(x, a.*mass_kg, b.*mass_kg);
a = band(edges, window_nm(1), 10^edges(end));
b = band(edges, window_nm(2), 10^edges(end));
[value(8), jacobian(8, :)] = fraction(x, a, b);
[value(9), jacobian(9, :), detail] = refined_mode(x, grid, window_nm);
end

function w = band(edges, lo, hi)
w = max(0, min(edges(2:end), log10(hi))- ...
    max(edges(1:end-1), log10(lo)));
end

function [r, j] = fraction(x, a, b)
denominator = a'*x;
if denominator <= 0
    error('sootMosaic:peak_statistics:EmptyBand', ...
        'Require positive band total.');
end
r = (b'*x)/denominator;
j = ((b-r*a)/denominator)';
end

function [mode, derivative, detail] = refined_mode(x, grid, window)
t = log10(grid.elements(:));
use = find(t >= log10(window(1)) & t <= log10(window(2)));
if isempty(use)
    error('sootMosaic:peak_statistics:ModeGrid', ...
        'Require centers in the window.');
end
[~, index] = max(x(use));
index = use(index);
mode = t(index);
derivative = zeros(1, numel(x));
boundary = index == use(1) || index == use(end);
% Refined only for a finite concave vertex between the neighbor centers;...
    % ...otherwise the center stays as a point value without a derivative
refined = false;
if ~boundary && all(x(index-1:index+1) > 0)
    ids = index-1:index+1;
    u = t(ids)-t(index);
    matrix = [u.^2, u, ones(3, 1)];
    coefficient = matrix\log(x(ids));
    if coefficient(1) < 0
        shift = -coefficient(2)/(2*coefficient(1));
        if isfinite(shift) && shift >= u(1) && shift <= u(3)
            mode = t(index)+shift;
            row = [coefficient(2)/(2*coefficient(1)^2), ...
                -1/(2*coefficient(1)), 0]/matrix;
            derivative(ids) = row./x(ids)';
            refined = true;
        end
    end
end
peaks = use(2:end-1);
peaks = peaks(x(peaks) > x(peaks-1) & x(peaks) >= x(peaks+1));
detail = struct('mode_nm', 10^mode, 'mode_boundary_1', boundary, ...
    'mode_refined_1', refined, 'peak_indices', peaks, ...
    'peak_nm', 10.^t(peaks));
end
