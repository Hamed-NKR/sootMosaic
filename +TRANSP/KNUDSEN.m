function kn = KNUDSEN(pars, fl, params_const, opts)
% "KNUDSEN" computes the pair diffusive and the nearest-neighbor Knudsen...
%     ...numbers of a particle population in the periodic domain. It is a...
%     ...diagnostic only and changes neither the particles nor the state...
%     ...of the random number generator.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     pars: Particle information structure after TRANSP.MOBIL, with the...
%         ...centers of mass r, the primaries pp and n, the maximum extent...
%         ...diameters dmax (from PAR.TERRITORY when missing), the mass m,...
%         ...friction f, mobility diameter dm, diffusivity diff, response...
%         ...time tau and, for the methods that set it, the projected area...
%         ...diameter da
%     fl: Fluid info structure with temp (K) and size, the lengths of the...
%         ...periodic domain (m)
%     params_const: Problem's table of constant physical properties
%     opts: Options structure. opts.mtd is the mobility method of...
%         ...TRANSP.MOBIL. The projected area diameter da is used for...
%         ...'interp' and 'free_molecular' and dm for the other methods.
% ----------------------------------------------------------------------- %
%
% Output:
%     kn: Structure of diagnostics, one entry per particle unless noted
%         nn: Index of the periodic nearest neighbor (0 without another...
%             ...particle)
%         d_nn: Center of mass distance to it under the minimum image...
%             ...convention (m)
%         kn_pair: Pair diffusive Knudsen number of the particle and its...
%             ...nearest neighbor (-)
%         lambda_p: Persistence distance (18 D tau)^0.5 (m)
%         n_density: Number concentration (m^-3), scalar
%         rn: Nearest-neighbor distance n^(-1/3) - 2 rmax (m), scalar
%         knn: Nearest-neighbor Knudsen number lambda_p / rn (-), NaN...
%             ...when rn <= 0
%         knn_defined: false when rn <= 0, scalar
% ----------------------------------------------------------------------- %
%
% Pair diffusive Knudsen number. Eq. 11 of Thajudeen et al. (2012, p. 1177,...
%     ...README reference 10), KnD = (kT m_ij)^0.5 pi R_S,ij / (f_ij PA_ij),...
%     ...with reduced mass 1 / m_ij = 1 / m_i + 1 / m_j (p. 1177) and the...
%     ...reduced friction 1 / f_ij = 1 / f_i + 1 / f_j (p. 1175). The...
%     ...result is an approximate pair diagnostic with two substitutions....
%     ...The combined Smoluchowski radius is taken as R_S,ij = (dm_i +...
%     ...dm_j) / 2, the sum of the mobility radii. The mobility radius is...
%     ...the capacity radius of the paper only in the continuum limit and...
%     ...tends to the projected area radius in the free molecular limit....
%     ...The combined projected area is taken as PA_ij = pi (da_i + da_j)^2...
%     .../ 4, the sum of the projected area radii (dm in place of da for...
%     ...methods that set no projected area). Both are exact for two...
%     ...spheres. For aggregate pairs they are not the computed R_S,ij and...
%     ...PA_ij of the paper. Its Table 1 (p. 1180, N from 6 to 48) shows...
%     ...that sums of the single-aggregate capacity radii and projected...
%     ...areas give KnD 1.16 to 1.46 times the value from the computed...
%     ...pair geometry. That factor belongs to the capacity radii of the...
%     ...paper and does not bound the diagnostic here, whose mobility...
%     ...radii depend on the transport regime, so only the order of...
%     ...magnitude of KnD is meaningful for aggregate pairs. For two...
%     ...identical spheres the expression is Eq. 2 of MCAC part 2 (Moran et...
%     ...al. 2020, p. 278, README reference 11), KnD = (2 m kT)^0.5 / (f...
%     ...dm), which is kn_diff of TRANSP.MOBIL divided by 2^0.5. The regime...
%     ...limits of the paper, continuum below KnD = 0.035 and free molecular...
%     ...above 3.7 (p. 1180), belong to the definition with the computed...
%     ...R_S,ij and PA_ij and only indicate the regime here.
% Nearest-neighbor Knudsen number. MCAC part 2 (p. 275), Knn = lambda_p /...
%     ...rn with the persistence distance lambda_p = (18 D tau)^0.5 and rn =...
%     ...n^(-1/3) - 2 rmax, n the number concentration and rmax the average...
%     ...maximum radius (half the mean of dmax). Agglomeration tends to be...
%     ...ballistic at high Knn and diffusion limited as Knn goes to 0.
% Single-particle numbers of TRANSP.MOBIL. kn_kin = 2 lambda / dm is the...
%     ...gas Knudsen number lambda / rm of Eggersdorfer and Pratsinis (2014,...
%     ...p. 75, README reference 12). kn_diff = 2 (m kT)^0.5 / (f dm) takes...
%     ...the length (m kT)^0.5 / f. Their particle mean free path 16 D /...
%     ...(pi u) with u = (8 kT / (pi m))^0.5 (p. 76) is 3.19 times this...
%     ...length and lambda_p is 18^0.5 = 4.24 times it, so diffusive Knudsen...
%     ...numbers of different conventions differ by these factors.
% Nearest neighbors. The positions are wrapped into the domain and a first...
%     ...k-d tree search without periodic images gives each particle a...
%     ...neighbor distance d0, which bounds its periodic nearest-neighbor...
%     ...distance from above. The images of the particles within max(d0) of...
%     ...a face, an edge or a corner are added and the search is repeated....
%     ...Every image closer than d0 to a particle in the domain is among...
%     ...them. When max(d0) reaches half the smallest domain length, all...
%     ...pairs are compared under the minimum image convention instead.
% ----------------------------------------------------------------------- %

if isa(pars, 'AGG')
    error('sootMosaic:KNUDSEN:UnsupportedClass', ['The Knudsen ', ...
        'diagnostics take the particle structure, not AGG objects.'])
end
if nargin < 4 || isempty(opts)
    opts = struct();
end
mtd = '';
if isfield(opts, 'mtd') && ~isempty(opts.mtd)
    mtd = char(opts.mtd);
end

kb = UTILS.CONSTANT_VALUE(params_const, 'kb'); % Thermal constant (J/K)
temp = fl.temp; % Gas temperature (K)
dom_size = reshape(double(fl.size), 1, 3); % Domain lengths (m)
n_par = size(pars.n, 1); % Total number of (independent) particles

m = pars.m(:);
f = pars.f(:);
dm = pars.dm(:);
if any(strcmp(mtd, {'interp', 'free_molecular'})) && ...
        isfield(pars, 'da') && numel(pars.da) == n_par
    da = pars.da(:); % Projected area diameter set by TRANSP.MOBIL
else
    da = dm; % No projected area from the mobility method
end
if isfield(pars, 'dmax') && numel(pars.dmax) == n_par
    dmax = pars.dmax(:);
else
    dmax = PAR.TERRITORY(pars.pp, pars.n);
end

% Periodic nearest neighbor of each particle
[nn, d_nn] = periodic_nearest(cat(1, pars.r), dom_size);

% Pair diffusive Knudsen number with the nearest neighbor
kn_pair = nan(n_par, 1);
ii = find(nn > 0);
jj = nn(ii);
m_ij = m(ii) .* m(jj) ./ (m(ii) + m(jj)); % Reduced mass (kg)
f_ij = f(ii) .* f(jj) ./ (f(ii) + f(jj)); % Reduced friction (kg/s)
rs_ij = (dm(ii) + dm(jj)) / 2; % Combined Smoluchowski radius (m)
pa_ij = pi * ((da(ii) + da(jj)) / 2).^2; % Combined projected area (m2)
kn_pair(ii) = sqrt(kb * temp * m_ij) * pi .* rs_ij ./ (f_ij .* pa_ij);

% Nearest-neighbor Knudsen number
lambda_p = sqrt(18 * pars.diff(:) .* pars.tau(:)); % Persistence distance (m)
n_density = n_par / prod(dom_size); % Number concentration (m^-3)
r_max = mean(dmax) / 2; % Average maximum radius (m)
rn = n_density^(-1/3) - 2 * r_max; % Nearest-neighbor distance (m)
knn_defined = rn > 0;
if knn_defined
    knn = lambda_p / rn;
else
    knn = nan(n_par, 1); % Not defined, the particles overlap on average
end

kn = struct('nn', nn, 'd_nn', d_nn, 'kn_pair', kn_pair, 'lambda_p', ...
    lambda_p, 'n_density', n_density, 'rn', rn, 'knn', knn, ...
    'knn_defined', knn_defined);

end

function [nn, d_nn] = periodic_nearest(r, dom_size)
% "periodic_nearest" returns the index and distance of the nearest other...
%   ...particle under the minimum image convention.
n_par = size(r, 1);
nn = zeros(n_par, 1);
d_nn = nan(n_par, 1);
if n_par < 2
    return
end
x = mod(r, dom_size); % Positions wrapped into [0, L)

% Neighbor distance without images, an upper bound of the periodic one
[~, d0] = knnsearch(x, x, 'K', 2);
d_lim = max(d0(:, 2)) * (1 + 1e-9);
if d_lim >= min(dom_size) / 2
    [nn, d_nn] = all_pairs(x, dom_size, (1 : n_par)', nn, d_nn);
    return
end

% Images of the particles within d_lim of the faces, edges and corners
[s1, s2, s3] = ndgrid(-1 : 1);
shifts = [s1(:), s2(:), s3(:)];
shifts(all(shifts == 0, 2), :) = [];
pts = {x};
src = {(1 : n_par)'};
for q = 1 : size(shifts, 1)
    keep = true(n_par, 1);
    for a = 1 : 3
        if shifts(q, a) < 0
            keep = keep & (x(:, a) >= dom_size(a) - d_lim);
        elseif shifts(q, a) > 0
            keep = keep & (x(:, a) <= d_lim);
        end
    end
    pts{end + 1, 1} = x(keep, :) + shifts(q, :) .* dom_size; %#ok<AGROW>
    src{end + 1, 1} = find(keep); %#ok<AGROW>
end
pts = cat(1, pts{:});
src = cat(1, src{:});

% Two nearest points, the particle itself and its nearest neighbor (the...
    % ...order of the two can swap when two particles coincide)
[idx, d] = knnsearch(pts, x, 'K', 2);
other = src(idx) ~= (1 : n_par)';
pick = 1 + ~other(:, 1); % first result that is another particle
ok = other(sub2ind(size(other), (1 : n_par)', pick));
rows = find(ok);
nn(rows) = src(idx(sub2ind(size(idx), rows, pick(rows))));
d_nn(rows) = d(sub2ind(size(d), rows, pick(rows)));
if ~all(ok)
    [nn, d_nn] = all_pairs(x, dom_size, find(~ok), nn, d_nn);
end
end

function [nn, d_nn] = all_pairs(x, dom_size, rows, nn, d_nn)
% "all_pairs" compares the particles of rows with all others under the...
%   ...minimum image convention.
for i = rows(:)'
    dx = x - x(i, :);
    dx = dx - dom_size .* round(dx ./ dom_size);
    d2 = sum(dx.^2, 2);
    d2(i) = Inf;
    [d2_min, nn(i)] = min(d2);
    d_nn(i) = sqrt(d2_min);
end
end
