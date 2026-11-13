function [pa, se, draws, pa_o] = PROJECTION_ISO(pp, n_pts, n_ori, n_rep, draws)
% "PROJECTION_ISO" estimates the orientation averaged projected area of...
%   ...one aggregate over isotropic orientations.
% ----------------------------------------------------------------------- %
%
% Inputs:
%   pp: Primary particle matrix of the aggregate (columns index,...
%       ...diameter, x, y, z, ...)
%   n_pts: Sampling points per orientation, placed on a square grid of...
%       ...ceil(sqrt(n_pts)) points per side
%   n_ori: Number of orientations, n_rep sets of n_ori / n_rep directions
%   n_rep: Number of independent random rotations of the direction set
%   draws: Uniform random numbers in [0, 1) to use (optional, drawn with...
%       ...rand when empty), a structure with fields rot (n_rep x 3) and...
%       ...off (n_ori x 2)
% ----------------------------------------------------------------------- %
%
% Outputs:
%   pa: Orientation averaged projected area (m2)
%   se: Standard error of pa (m2), from the spread of the n_rep set...
%       ...means (n_rep - 1 degrees of freedom). NaN when n_rep = 1, since...
%       ...the directions of one set share one rotation and are not...
%       ...independent, so no standard error is available
%   draws: The random numbers used
%   pa_o: Projected area in each orientation (m2)
% ----------------------------------------------------------------------- %
%
% Directions. Each set holds n_ori / n_rep directions of a spherical...
%   ...Fibonacci lattice on the upper hemisphere (equal-area bands in z,...
%   ...azimuth stepped by the golden angle). The projected area seen...
%   ...along a direction equals the one seen along its opposite, so the...
%   ...hemisphere covers all directions. Each set is turned by its own...
%   ...uniformly distributed rotation (Euler angles z-y-z with uniform...
%   ...first and third angles and uniform cosine of the second, which...
%   ...is the invariant measure on rotations), so every direction is...
%   ...uniform on the sphere and pa is unbiased, while the lattice...
%   ...spreads the directions of a set evenly. The spherical Fibonacci...
%   ...lattice is usually laid over the whole sphere in equal-area bands...
%   ...of z. Here the bands cover the upper hemisphere only, an...
%   ...adaptation to a quantity that is the same for opposite directions.
% Area in one orientation. The discs of the primaries are projected on...
%   ...the plane normal to the direction. A grid of g x g points with...
%   ...one random offset in [0, 1) cells per axis samples the bounding...
%   ...rectangle of the discs, and the area is the number of covered...
%   ...points times the cell area. The randomly shifted grid gives an...
%   ...unbiased area, since with a uniform offset the expected number of...
%   ...grid points in any part of the rectangle is its area divided by...
%   ...the cell area. Covered points are found row by row from the chord...
%   ...of each disc, without a point by primary distance matrix.
% Uncertainty. With n_rep sets, se has n_rep - 1 degrees of freedom and...
%   ...is itself noisy. With the 4 sets of the 'current' profile a...
%   ...nominal two-sided 95 percent interval would need 3.182 se (t...
%   ...distribution with 3 degrees of freedom, under normality), so se is...
%   ...a diagnostic of the resolution, not a confidence guarantee.
% ----------------------------------------------------------------------- %

g = ceil(sqrt(n_pts)); % Grid points per side
k_set = n_ori / n_rep; % Directions per set
if k_set ~= round(k_set) || k_set < 1
    error('sootMosaic:PROJECTION_ISO:InvalidSets', ['The number of ', ...
        'orientations must be a positive multiple of the number of sets.'])
end
if ~exist('draws', 'var') || isempty(draws)
    draws.rot = rand(n_rep, 3);
    draws.off = rand(n_ori, 2);
end

% Directions of one set and two unit vectors spanning each normal plane
kk = (1 : k_set)';
z = (2 * kk - 1) / (2 * k_set);
phi = 2 * pi * mod(kk * (sqrt(5) - 1) / 2, 1);
s = sqrt(1 - z.^2);
e1 = [-sin(phi), cos(phi), zeros(k_set, 1)]'; % 3 x k_set
e2 = [z .* cos(phi), z .* sin(phi), -s]';
ee = reshape([e1; e2], 3, 2 * k_set); % columns e1(1), e2(1), e1(2), ...

% Projected centers in all orientations (n x n_ori each)
n = size(pp, 1);
rad = pp(:, 2) / 2;
xyz = pp(:, 3:5) - mean(pp(:, 3:5), 1);
xy = zeros(n, 2 * n_ori);
for r = 1 : n_rep
    a = 2 * pi * draws.rot(r, 1);
    b = acos(2 * draws.rot(r, 2) - 1);
    c = 2 * pi * draws.rot(r, 3);
    q = rot_z(a) * rot_y(b) * rot_z(c);
    xy(:, (r - 1) * 2 * k_set + (1 : 2 * k_set)) = xyz * (q * ee);
end
x = xy(:, 1 : 2 : end);
y = xy(:, 2 : 2 : end);

% Bounding rectangles, cells and offsets (1 x n_ori)
x0 = min(x - rad, [], 1);
y0 = min(y - rad, [], 1);
hx = (max(x + rad, [], 1) - x0) / g;
hy = (max(y + rad, [], 1) - y0) / g;
ux = draws.off(:, 1)';
uy = draws.off(:, 2)';

% Grid rows crossed by each disc, row j at y0 + (j - 1 + uy) hy
j_lo = max(ceil((y - rad - y0) ./ hy - uy + 1), 1);
j_hi = min(floor((y + rad - y0) ./ hy - uy + 1), g);
n_row = max(j_hi - j_lo + 1, 0);
pair = repelem((1 : n * n_ori)', n_row(:)); % Disc and orientation index
first = cumsum([0; n_row(:)]);
row = reshape(j_lo(pair), [], 1) + ((1 : numel(pair))' - first(pair) - 1);
[i_p, o_p] = ind2sub([n, n_ori], pair);
x_p = reshape(x(pair), [], 1); % Column vectors also when n = 1
y_p = reshape(y(pair), [], 1);

% Columns covered by the chord of each disc in each row
y_row = y0(o_p)' + (row - 1 + uy(o_p)') .* hy(o_p)';
w = sqrt(max(rad(i_p).^2 - (y_row - y_p).^2, 0));
c_lo = max(ceil((x_p - w - x0(o_p)') ./ hx(o_p)' - ux(o_p)' + 1), 1);
c_hi = min(floor((x_p + w - x0(o_p)') ./ hx(o_p)' - ux(o_p)' + 1), g);
keep = c_lo <= c_hi;
col = (o_p(keep) - 1) * g + row(keep); % One column per orientation and row
n_k = nnz(keep);

% Union of the chords in each row by a difference array
dd = accumarray([[c_lo(keep); c_hi(keep) + 1], [col; col]], ...
    [ones(n_k, 1); -ones(n_k, 1)], [g + 1, g * n_ori]);
covered = cumsum(dd(1 : g, :), 1) > 0;
n_in = sum(reshape(sum(covered, 1), g, n_ori), 1);

pa_o = n_in .* hx .* hy;
pa_set = mean(reshape(pa_o, k_set, n_rep), 1);
pa = mean(pa_set);
if n_rep > 1
    se = std(pa_set) / sqrt(n_rep);
else
    se = NaN; % one rotation, no independent sets to estimate the error
end

end

function m = rot_z(t)
m = [cos(t), -sin(t), 0; sin(t), cos(t), 0; 0, 0, 1];
end

function m = rot_y(t)
m = [cos(t), 0, sin(t); 0, 1, 0; -sin(t), 0, cos(t)];
end
