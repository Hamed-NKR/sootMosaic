function report = test_projection_cache(repoRoot)
% "TEST_PROJECTION_CACHE" checks the isotropic projected area of...
%     ...PAR.PROJECTION_ISO, the area cache of PAR.PROJECTION_CACHE, the...
%     ...projection options of TRANSP.MOBIL, their model profile options,...
%     ...the LD1 and LD2 config loaders and LD2 resumes.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     repoRoot: sootMosaic root folder (default the folder above +QA)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Structure array with fields name and pass, one entry per case
% ----------------------------------------------------------------------- %
%
% The orientation averaged projected area of two touching spheres of...
%     ...radius a is (pi + 8/3) a^2 = 1.8488263632 pi a^2 (the overlap of...
%     ...the two discs averaged over a uniform cosine of the axis angle...
%     ...is (pi - 8/3) a^2), evaluated outside MATLAB to ten digits. A...
%     ...failed case stops with the identifier...
%     ...sootMosaic:QA:ProjectionCacheFailed.
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

names = {};
pass = [];
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
res = {1024, 64, 4}; % resolution of the current profile

% sphere and dimer against the analytic areas at the chosen resolution
d = 30e-9;
a = d / 2;
sph = [1, d, 0, 0, 0];
dim = [1, d, -a, 0, 0; 2, d, a, 0, 0];
[names, pass] = add(names, pass, ...
    'dimer area ratio (pi + 8/3) / pi is 1.8488263632', ...
    near((pi + 8 / 3) / pi, 1.8488263632, 1e-9));
rng(21);
e_s = zeros(50, 1);
e_d = zeros(50, 1);
for k = 1 : 50
    e_s(k) = PAR.PROJECTION_ISO(sph, res{:}) / (pi * a^2) - 1;
    e_d(k) = PAR.PROJECTION_ISO(dim, res{:}) / (1.8488263632 * pi * a^2) - 1;
end
[names, pass] = add(names, pass, ...
    'sphere area within 1 percent at 1024 points and 64 orientations', ...
    all(abs(e_s) < 0.01));
[names, pass] = add(names, pass, ...
    'dimer area within 1 percent at 1024 points and 64 orientations', ...
    all(abs(e_d) < 0.01));
fprintf(['50 draws, largest error sphere %.2e, dimer %.2e, rms %.2e ', ...
    'and %.2e\n'], max(abs(e_s)), max(abs(e_d)), rms(e_s), rms(e_d));

% independent references. A straight chain of N touching spheres has the...
    % ...exact mean area (pi + 8 (N - 1) / 3) a^2, since the union of...
    % ...collinear equal discs is one disc plus N - 1 times a disc less...
    % ...the lens of two neighbours. The brute-force reference averages a...
    % ...fine midpoint grid over fixed quadrature directions and shares no...
    % ...code with PAR.PROJECTION_ISO. The convex hull of a cluster has...
    % ...the mean area S / 4 (Cauchy formula), with S from the Steiner...
    % ...formula, an upper bound of the area of the cluster.
ok_bf = true;
ok_ch = true;
err_ch = 0;
rng(17);
for n_ch = [2, 3, 5, 10, 20]
    pp_ch = chain(n_ch, d);
    a_ex = (pi + 8 * (n_ch - 1) / 3) * a^2;
    ok_bf = ok_bf && near(brute_area(pp_ch, 24, 48, 400), a_ex, 1e-3);
    e_ch = zeros(30, 1);
    for k = 1 : 30
        e_ch(k) = PAR.PROJECTION_ISO(pp_ch, res{:}) / a_ex - 1;
    end
    ok_ch = ok_ch && abs(mean(e_ch)) < 3 * std(e_ch) / sqrt(30) + 2e-4 ...
        && all(abs(e_ch) < 0.02);
    err_ch = max(err_ch, max(abs(e_ch)));
end
[names, pass] = add(names, pass, ...
    'brute-force reference gives the exact chain areas within 1e-3', ok_bf);
[names, pass] = add(names, pass, ...
    'chains of 2 to 20 primaries scatter about (pi + 8 (N - 1) / 3) a^2', ...
    ok_ch);
fprintf('chains of 2 to 20 primaries, 30 draws each, largest error %.2e\n', ...
    err_ch);
tet = [1, 1, 1; 1, -1, -1; -1, 1, -1; -1, -1, 1] * d / (2 * sqrt(2));
pp_tet = [(1 : 4)', d * ones(4, 1), tet];
h_tet = hull_area(tet, a);
b_tet = brute_area(pp_tet, 24, 48, 400);
pa_tet = zeros(30, 1);
for k = 1 : 30
    pa_tet(k) = PAR.PROJECTION_ISO(pp_tet, res{:});
end
[names, pass] = add(names, pass, ...
    'tetrahedron of 4 spheres below its hull area 10.6055431699 a^2', ...
    near(h_tet, 10.6055431699 * a^2, 1e-9) && b_tet < h_tet && ...
    all(pa_tet < h_tet) && abs(mean(pa_tet) / b_tet - 1) < ...
    3 * std(pa_tet) / b_tet / sqrt(30) + 2e-4);

% unbiased estimate and its standard error on a 40-primary cluster
rng(4);
clu = cluster(40, d);
pa_ref = brute_area(clu, 32, 64, 600);
h_clu = hull_area(clu(:, 3:5), a);
pa_k = zeros(30, 1);
se_k = zeros(30, 1);
se_16 = zeros(30, 1);
for k = 1 : 30
    [pa_k(k), se_k(k)] = PAR.PROJECTION_ISO(clu, res{:});
    [~, se_16(k)] = PAR.PROJECTION_ISO(clu, 1024, 16, 4);
end
err = pa_k / pa_ref - 1;
[names, pass] = add(names, pass, ...
    'cluster estimates scatter about the reference as their errors say', ...
    abs(mean(err)) < 3 * std(err) / sqrt(30) + 1e-3 && ...
    abs(rms(err) / sqrt(mean((se_k ./ pa_k).^2)) - 1) < 0.6 && ...
    mean(se_k) < mean(se_16) && all(pa_k < h_clu));
fprintf(['cluster of 40, rms error %.2e against the brute-force ', ...
    'reference, mean relative standard error %.2e (16 orientations ', ...
    '%.2e), hull area %.3f times the reference\n'], rms(err), ...
    mean(se_k ./ pa_k), mean(se_16 ./ pa_k), h_clu / pa_ref);
[pa_1, se_1] = PAR.PROJECTION_ISO(clu, 1024, 64, 1);
[names, pass] = add(names, pass, ...
    'one set gives an area and no standard error (NaN)', ...
    isfinite(pa_1) && pa_1 > 0 && isnan(se_1));
[names, pass] = add(names, pass, ...
    'orientations must be a multiple of the sets', ...
    raises_error(@() PAR.PROJECTION_ISO(clu, 100, 10, 4), ...
    'sootMosaic:PROJECTION_ISO:InvalidSets'));

% cached and uncached paths with identical draws
rng(8);
pars = population(d);
n0 = numel(pars.n);
draws1 = make_draws(n0, res);
opts_c = struct('n_pts', res{1}, 'n_ori', res{2}, 'n_rep', res{3}, ...
    'use_cache', true);
opts_u = opts_c;
opts_u.use_cache = false;
[pa1, se1, cache1, n1] = PAR.PROJECTION_CACHE(pars, [], opts_c, draws1);
[pa_u, se_u, cache_u] = PAR.PROJECTION_CACHE(pars, [], opts_u, draws1);
[names, pass] = add(names, pass, ...
    'first call computes every aggregate, cached equals uncached', ...
    isequal(pa1, pa_u) && isequal(se1, se_u) && isempty(cache_u) && ...
    n1 == nnz(pars.n > 1) && all(pa1(pars.n == 1) == pi * d^2 / 4) && ...
    all(se1(pars.n == 1) == 0));
% translate everything, merge two pairs and rotate one aggregate
pars2 = pars;
for i = 1 : n0
    pars2.pp{i}(:, 3:5) = pars2.pp{i}(:, 3:5) + [3.7e-7, -1.1e-7, 2.9e-7];
end
pars2.r = PAR.COM(pars2.pp, pars2.n);
pars2.v = zeros(n0, 3);
pars2.m = ones(n0, 1);
i_rot = 6;
pars2.pp(i_rot) = PAR.ROTATE(pars2.pp(i_rot), pars2.n(i_rot), [0.3, 0.2, 0.1]);
[pars2, i_list] = COL.UNITE(pars2, [2, 3; 7, 9]);
old = i_list(:, 2); % new index of each old aggregate
n2 = numel(pars2.n);
draws2 = make_draws(n2, res);
changed = false(n2, 1);
changed(old([2, 7, i_rot])) = true;
draws_exp = draws2;
for i = 1 : n0
    if ~any(i == [2, 3, 7, 9, i_rot])
        draws_exp{old(i)} = draws1{i};
    end
end
[pa2, ~, cache2, n_new] = PAR.PROJECTION_CACHE(pars2, cache1, opts_c, ...
    draws2);
pa_u2 = PAR.PROJECTION_CACHE(pars2, [], opts_u, draws_exp);
[names, pass] = add(names, pass, ...
    'after a translation, two merges and a rotation the cache recomputes 3', ...
    n_new == 3 && nnz(changed & pars2.n > 1) == 3 && ...
    size(cache2.key, 1) == nnz(pars2.n > 1));
[names, pass] = add(names, pass, ...
    'cached areas equal uncached areas with the same draws', ...
    near(pa2, pa_u2, 1e-12) && isequal(pa2(changed), pa_u2(changed)));
fprintf('cached against uncached areas, largest relative difference %.2g\n', ...
    max(abs(pa2 ./ pa_u2 - 1)));
opts_256 = opts_c;
opts_256.n_pts = 256;
[~, ~, ~, n_set] = PAR.PROJECTION_CACHE(pars2, cache2, opts_256);
[names, pass] = add(names, pass, ...
    'other sampling settings recompute every aggregate', ...
    n_set == nnz(pars2.n > 1));
pars3 = pars2;
k3 = find(pars3.n > 1, 1);
pars3.pp{k3}(end, 3) = pars3.pp{k3}(end, 3) + 1e-6 * d;
[~, ~, ~, n_3] = PAR.PROJECTION_CACHE(pars3, cache2, opts_c);
[names, pass] = add(names, pass, ...
    'moving one primary by 1e-6 dp recomputes its aggregate only', n_3 == 1);
% moves below the tolerance (1e-9 dp) that add up past it, each compared...
    % ...with the reference geometry of the stored area
tol = 1e-9 * d;
k4 = find(pars2.n > 4, 1, 'last');
k5 = find(pars2.n > 1 & (1 : n2)' ~= k4, 1);
pars4 = pars2;
cache4 = cache2;
n_seq = zeros(1, 8);
ok_4 = true;
for s = 1 : 8
    pars4.pp{k4}(end, 4) = pars4.pp{k4}(end, 4) + 0.3 * tol;
    draws4 = make_draws(n2, res);
    [pa4, ~, cache4, n_seq(s)] = PAR.PROJECTION_CACHE(pars4, cache4, ...
        opts_c, draws4);
    if n_seq(s) == 1
        ok_4 = ok_4 && isequal(pa4(k4), PAR.PROJECTION_ISO(pars4.pp{k4}, ...
            res{:}, draws4{k4}));
    end
end
[names, pass] = add(names, pass, ...
    'sub-tolerance moves that add up past 1e-9 dp recompute the area', ...
    isequal(n_seq, [0, 0, 0, 1, 0, 0, 0, 1]) && ok_4);
pars5 = pars2;
pars5.pp{k4}(end, 4) = pars5.pp{k4}(end, 4) + 0.9 * tol;
[~, ~, cache5, n_a] = PAR.PROJECTION_CACHE(pars5, cache2, opts_c);
pars5.pp{k4}(end, 4) = pars5.pp{k4}(end, 4) + 0.2 * tol;
[~, ~, ~, n_b] = PAR.PROJECTION_CACHE(pars5, cache5, opts_c);
pars5 = pars2;
pars5.pp{k4}(end, 4) = pars5.pp{k4}(end, 4) + 1.1 * tol;
[~, ~, ~, n_c] = PAR.PROJECTION_CACHE(pars5, cache2, opts_c);
[names, pass] = add(names, pass, ...
    'tolerance crossing, 0.9 kept, 0.9 + 0.2 and 1.1 recomputed', ...
    n_a == 0 && n_b == 1 && n_c == 1);
% repeated random translations of up to 2.5 micrometers per axis keep...
    % ...every area
pars6 = pars2;
cache6 = cache2;
ok_6 = true;
for s = 1 : 500
    shift = (rand(1, 3) - 0.5) * 5e-6;
    for i = 1 : n2
        pars6.pp{i}(:, 3:5) = pars6.pp{i}(:, 3:5) + shift;
    end
    [pa6, ~, cache6, n_6] = PAR.PROJECTION_CACHE(pars6, cache6, opts_c);
    ok_6 = ok_6 && n_6 == 0 && isequal(pa6, pa2);
end
[names, pass] = add(names, pass, ...
    '500 random translations keep every stored area', ok_6);
% diameter change, coalescence of two primaries and new orders
pars7 = pars2;
pars7.pp{k4}(2, 2) = pars7.pp{k4}(2, 2) * (1 + 1e-12);
[~, ~, ~, n_d] = PAR.PROJECTION_CACHE(pars7, cache2, opts_c);
pars7 = pars2;
q = pars7.pp{k4};
q(end - 1, 2) = (q(end - 1, 2)^3 + q(end, 2)^3)^(1 / 3); % same volume
pars7.pp{k4} = q(1 : end - 1, :);
pars7.n(k4) = pars7.n(k4) - 1;
draws7 = make_draws(n2, res);
[pa7, ~, ~, n_co] = PAR.PROJECTION_CACHE(pars7, cache2, opts_c, draws7);
ok_co = n_co == 1 && isequal(pa7(k4), PAR.PROJECTION_ISO(pars7.pp{k4}, ...
    res{:}, draws7{k4}));
perm = n2 : -1 : 1;
pars8 = struct('n', pars2.n(perm), 'pp', {pars2.pp(perm)});
[pa8, ~, ~, n_r] = PAR.PROJECTION_CACHE(pars8, cache2, opts_c);
pars9 = pars2;
pars9.pp{k4}([2, 3], :) = pars9.pp{k4}([3, 2], :);
pars9.pp{k5}([1, 2], :) = pars9.pp{k5}([2, 1], :);
[~, ~, ~, n_p] = PAR.PROJECTION_CACHE(pars9, cache2, opts_c);
[names, pass] = add(names, pass, ...
    'diameter change, coalescence and reordered primaries recompute', ...
    n_d == 1 && ok_co && n_p == 2);
[names, pass] = add(names, pass, ...
    'reordered aggregates keep their stored areas', ...
    n_r == 0 && isequal(pa8, pa2(perm)));
[names, pass] = add(names, pass, ...
    'AGG objects rejected (UnsupportedClass)', ...
    raises_error(@() PAR.PROJECTION_CACHE(to_agg(pars2), [], ...
    opts_c), 'sootMosaic:PROJECTION_CACHE:UnsupportedClass'));

% MOBIL with the isotropic projection
params_const = table([1800; 0.02897; 1.380649e-23], ...
    'VariableNames', {'Value'});
fl = struct('temp', 298, 'mu', 1.8369e-5, 'lambda', 6.7835e-8);
cur = UTILS.MODEL_PROFILE('current', 'LD2');
mob = struct('mtd', 'interp', 'c_dt', 1e-3, 'slip', 'kim2005', ...
    'continuum_diameter', cur.continuum_diameter, 'root_solve', ...
    cur.root_solve, 'projection', cur.projection, 'proj_cache', ...
    cur.proj_cache, 'proj_points', cur.proj_points, 'proj_orientations', ...
    cur.proj_orientations, 'proj_replicates', cur.proj_replicates, ...
    'proj_tol', cur.proj_tol);
pars = PAR.SIZING(pars);
[p1, o1] = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob));
state = rng;
[p2, o2] = quiet(@() TRANSP.MOBIL(pars, fl, params_const, o1));
[names, pass] = add(names, pass, ...
    'MOBIL isotropic gives monomers da = dm = dp exactly', ...
    all(p1.da(pars.n == 1) == d) && all(p1.dm(pars.n == 1) == d));
[names, pass] = add(names, pass, ...
    'a second MOBIL call on unchanged aggregates draws no random numbers', ...
    isequal(rng, state) && isequal(p2.da, p1.da) && isequal(p2.f, p1.f) ...
    && isequal(o2.proj_cache_data, o1.proj_cache_data));
mob_f = mob;
mob_f.mtd = 'free_molecular';
pf = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_f));
[names, pass] = add(names, pass, ...
    'free_molecular gives dm = da and dp for a sphere', ...
    isequal(pf.dm, pf.da) && all(pf.dm(pars.n == 1) == d));
for d_1 = [7.3e-9, 13.1e-9, 41.7e-9]
    p_1 = struct('n', 1, 'pp', {{[1, d_1, 0, 0, 0, 1]}});
    p_1 = PAR.SIZING(p_1);
    [p_1, ~] = quiet(@() TRANSP.MOBIL(p_1, fl, params_const, mob_f));
    ok_1 = p_1.dm == d_1 && p_1.da == d_1;
    if ~ok_1, break, end
end
[names, pass] = add(names, pass, ...
    'single primaries of other sizes get da = dp exactly', ok_1);
[names, pass] = add(names, pass, ...
    'MOBIL records the largest relative standard error', ...
    o1.proj_rse_max > 0 && o1.proj_rse_max < cur.proj_tol && ~o1.proj_warned);
mob_t = mob;
mob_t.proj_tol = 1e-6;
[~, o_t] = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_t));
[names, pass] = add(names, pass, ...
    'a relative standard error above proj_tol warns once per run', ...
    raises_warning(@() TRANSP.MOBIL(pars, fl, params_const, mob_t), ...
    'sootMosaic:MOBIL:ProjectionNotConverged') && o_t.proj_warned && ...
    no_warning(@() TRANSP.MOBIL(pars, fl, params_const, o_t), ...
    {'sootMosaic:MOBIL:ProjectionNotConverged'}));
rng(13);
pl = quiet(@() TRANSP.MOBIL(pars, fl, params_const, ...
    struct('mtd', 'interp', 'c_dt', 1e-3)));
rng(13);
pa_l = PAR.PROJECTION(pars, [], 1e2, 5, [], struct('tbar', 'off'));
[names, pass] = add(names, pass, ...
    'MOBIL without projection options keeps the 7658971 projection', ...
    isequal(pl.da, 2 * sqrt(pa_l / pi)));
[names, pass] = add(names, pass, ...
    'MOBIL rejects the cache with euler_7658971 and unknown names', ...
    raises_error(@() TRANSP.MOBIL(pars, fl, params_const, ...
    struct('mtd', 'interp', 'proj_cache', true)), ...
    'sootMosaic:MOBIL:InvalidProjection') && ...
    raises_error(@() TRANSP.MOBIL(pars, fl, params_const, ...
    struct('mtd', 'interp', 'projection', 'lattice')), ...
    'sootMosaic:MOBIL:UnknownProjection'));
mob_1 = mob;
mob_1.proj_replicates = 1;
mob_1.proj_tol = Inf;
mob_1.proj_cache = false;
[p_r1, o_r1] = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_1));
mob_1t = mob_1;
mob_1t.proj_tol = 0.01;
[names, pass] = add(names, pass, ...
    'one set reports no standard error and needs proj_tol Inf', ...
    isnan(o_r1.proj_rse_max) && ~o_r1.proj_warned && ...
    all(isfinite(p_r1.da)) && no_warning(@() TRANSP.MOBIL(pars, fl, ...
    params_const, mob_1), {'sootMosaic:MOBIL:ProjectionNotConverged'}) && ...
    raises_error(@() TRANSP.MOBIL(pars, fl, params_const, mob_1t), ...
    'sootMosaic:MOBIL:InvalidProjection'));
% two 1 nm primaries 1 micrometer apart seen by one grid point per...
    % ...orientation give a zero area, NaN positions give no finite area...
    % ...and no finite standard error
far = struct('n', [2; 1], 'pp', {{[1, 1e-9, 0, 0, 0, 1; ...
    2, 1e-9, 1e-6, 0, 0, 1]; [3, d, 5e-6, 0, 0, 2]}});
far = PAR.SIZING(far);
mob_c = mob;
mob_c.proj_points = 1;
mob_c.proj_orientations = 4;
mob_c.proj_replicates = 2;
mob_c.proj_cache = false;
nan_p = far;
nan_p.pp{1}(:, 3:5) = NaN;
rng(19);
[names, pass] = add(names, pass, ...
    'zero or nonfinite areas and standard errors stop MOBIL', ...
    raises_error(@() TRANSP.MOBIL(far, fl, params_const, mob_c), ...
    'sootMosaic:MOBIL:UnresolvedProjection') && ...
    raises_error(@() TRANSP.MOBIL(nan_p, fl, params_const, mob), ...
    'sootMosaic:MOBIL:UnresolvedProjection'));
[names, pass] = add(names, pass, ...
    'MOBIL with AGG objects and the isotropic projection stops', ...
    raises_error(@() TRANSP.MOBIL(to_agg(pars), fl, params_const, ...
    mob), 'sootMosaic:PROJECTION_CACHE:UnsupportedClass'));

% model profiles
m1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
m2 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
m3 = UTILS.MODEL_PROFILE('current', 'LD1');
[m4, known] = UTILS.MODEL_PROFILE('current', 'LD2');
a1 = {'euler_7658971', false, 100, 5, 1, Inf};
c1 = {'isotropic', true, 1024, 64, 4, 0.01};
f = {'projection', 'proj_cache', 'proj_points', 'proj_orientations', ...
    'proj_replicates', 'proj_tol'};
[names, pass] = add(names, pass, 'profile projection defaults', ...
    isequal(cellfun(@(x) m1.(x), f, 'UniformOutput', false), a1) && ...
    isequal(cellfun(@(x) m2.(x), f, 'UniformOutput', false), a1) && ...
    isequal(cellfun(@(x) m3.(x), f, 'UniformOutput', false), c1) && ...
    isequal(cellfun(@(x) m4.(x), f, 'UniformOutput', false), c1) && ...
    isequal(known.projection, {'isotropic', 'euler_7658971'}));

% loaders
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, 's'));
ld1 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld1', ...
    'main_ld1_config.example.json')));
ld2 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld2', ...
    'main_ld2_from_main_scatter_config.example.json')));
ld2s = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld2', ...
    'main_ld2_from_main_scale_config.example.json')));
f1 = @(c) UTILS.LOAD_MAIN_LD1_CONFIG(write_config(tmp, c));
f2 = @(c) UTILS.LOAD_MAIN_LD2_CONFIG(write_config(tmp, c));
examples = {ld1, ld2, ld2s};
loaders = {f1, f2, f2};
stage = {'LD1', 'LD2', 'LD2'};
ok_ex = true;
ok_a1 = true;
ok_bad = true;
ok_one = true;
for i = 1 : 3
    cfg = quiet(@() loaders{i}(examples{i}));
    ok_ex = ok_ex && strcmp(cfg.model.mobility, 'interp') && ...
        isequal(cellfun(@(x) cfg.model.(x), f, 'UniformOutput', false), c1) ...
        && isequal(cellfun(@(x) cfg.transport.mobility_options.(x), f, ...
        'UniformOutput', false), c1);
    c = examples{i};
    c.model_profile = 'article1_7658971';
    c.transport.mobility_options = rmfield(c.transport.mobility_options, ...
        f);
    cfg = quiet(@() loaders{i}(c));
    ok_a1 = ok_a1 && isequal(cellfun(@(x) cfg.model.(x), f, ...
        'UniformOutput', false), a1);
    pre = sprintf('sootMosaic:LOAD_MAIN_%s_CONFIG:', stage{i});
    bad = {struct('projection', 'euler_7658971'), 'InvalidProjection'; ...
        struct('proj_orientations', 30), 'InvalidProjection'; ...
        struct('proj_replicates', 1), 'InvalidProjection'; ...
        struct('proj_cache', 'yes'), 'InvalidLogical'; ...
        struct('proj_points', 2.5), 'InvalidInteger'; ...
        struct('proj_tol', -1), 'InvalidPositiveScalar'; ...
        struct('proj_tol', 'never'), 'InvalidScalar'; ...
        struct('projection', 'lattice'), 'InvalidChoice'};
    for b = 1 : size(bad, 1)
        cb = examples{i};
        fb = fieldnames(bad{b, 1});
        cb.transport.mobility_options.(fb{1}) = bad{b, 1}.(fb{1});
        ok_bad = ok_bad && raises_error(@() loaders{i}(cb), [pre, bad{b, 2}]);
    end
    % one set with the documented no-check value none
    c = examples{i};
    c.transport.mobility_options.proj_replicates = 1;
    c.transport.mobility_options.proj_tol = 'none';
    try
        cfg = quiet(@() loaders{i}(c));
        ok_one = ok_one && cfg.model.proj_replicates == 1 && ...
            cfg.model.proj_tol == Inf && ...
            cfg.transport.mobility_options.proj_tol == Inf;
    catch
        ok_one = false; % the loader rejected the config
    end
end
[names, pass] = add(names, pass, ...
    'example configs run interp with the isotropic cached projection', ok_ex);
[names, pass] = add(names, pass, ...
    'article1_7658971 without projection fields gives the 7658971 settings', ...
    ok_a1);
[names, pass] = add(names, pass, ...
    'loaders reject inconsistent or invalid projection options', ok_bad);
[names, pass] = add(names, pass, ...
    'loaders accept one set with proj_tol none (no check, Inf)', ok_one);

% resume of LD2 checkpoints that advance two transport steps
model_a = rmfield(cur, f);
mob_a = struct('mtd', 'interp', 'c_dt', 1, 'slip', 'kim2005', ...
    'continuum_diameter', 'sorensen_backbone', 'root_solve', 'bracketed');
[ok, out] = resume_checkpoint(fullfile(tmp, 'r1'), model_a, mob_a, true);
[names, pass] = add(names, pass, ...
    'resume without projection options keeps euler_7658971', ok && ...
    isequal(cellfun(@(x) out.cfg_ld2.model.(x), f, 'UniformOutput', ...
    false), a1) && isequal(cellfun(@(x) out.opts_mobil.(x), f, ...
    'UniformOutput', false), a1) && advanced(out));
mob.c_dt = 1;
[ok, out, sv] = resume_checkpoint(fullfile(tmp, 'r2'), cur, mob, false);
same = ismember(cellfun(@(p) p(1, 1), out.pars_LD2.pp), ...
    cellfun(@(p) p(1, 1), sv.pars_LD2.pp)) & out.pars_LD2.n > 1;
[~, j_sv] = ismember(cellfun(@(p) p(1, 1), out.pars_LD2.pp), ...
    cellfun(@(p) p(1, 1), sv.pars_LD2.pp));
same(same) = out.pars_LD2.n(same) == sv.pars_LD2.n(j_sv(same));
[names, pass] = add(names, pass, ...
    'resume continues with the saved area cache', ok && advanced(out) && ...
    isequal(out.cfg_ld2.model, cur) && any(same) && ...
    isequal(out.pars_LD2.da(same), sv.pars_LD2.da(j_sv(same))) && ...
    ~isempty(out.opts_mobil.proj_cache_data));
% a run interrupted at its own checkpoint and resumed against the same run...
    % ...uninterrupted, with the isotropic cached projection of 'current'...
    % ...and with euler_7658971 of the 7658971 settings
ok_c = resume_matches_full(fullfile(tmp, 'r3'), cur, mob);
model_a1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
mob_a1 = struct('mtd', 'interp', 'c_dt', 1, 'slip', ...
    model_a1.slip_correction, 'continuum_diameter', ...
    model_a1.continuum_diameter, 'root_solve', model_a1.root_solve);
for i_f = 1 : numel(f)
    mob_a1.(f{i_f}) = model_a1.(f{i_f});
end
ok_a = resume_matches_full(fullfile(tmp, 'r4'), model_a1, mob_a1);
[names, pass] = add(names, pass, ...
    'resumed run equals the uninterrupted run, cache and generator included', ...
    ok_c && ok_a);

clear cleanup restore_rng
report = struct('name', names, 'pass', num2cell(pass));
for i = 1 : numel(pass)
    if pass(i)
        fprintf('PASS %s\n', names{i});
    else
        fprintf('FAIL %s\n', names{i});
    end
end
if ~all(pass)
    error('sootMosaic:QA:ProjectionCacheFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass))
end

end

function [names, pass] = add(names, pass, name, ok)
names{end + 1, 1} = name;
pass(end + 1, 1) = logical(ok);
end

function ok = near(val, ref, tol)
ok = all(abs(val ./ ref - 1) <= tol);
end

function pp = cluster(n, d)
% Touching primaries of diameter d, each attached to a random earlier...
    % ...one in a random direction without overlap (columns index,...
    % ...diameter, x, y, z)
xyz = zeros(n, 3);
k = 1;
while k < n
    u = randn(1, 3);
    p = xyz(randi(k), :) + d * u / norm(u);
    if all(sum((xyz(1 : k, :) - p).^2, 2) >= (d * (1 - 1e-9))^2)
        k = k + 1;
        xyz(k, :) = p;
    end
end
pp = [(1 : n)', d * ones(n, 1), xyz];
end

function aggs = to_agg(pars)
% AGG objects with the primaries of each aggregate of pars
aggs = AGG();
for i = 1 : numel(pars.n)
    aggs(i) = AGG(struct('id', pars.pp{i}(:, 1), 'd', pars.pp{i}(:, 2), ...
        'r', pars.pp{i}(:, 3:5)));
end
end

function pp = chain(n, d)
% Straight chain of n touching primaries of diameter d along x
pp = [(1 : n)', d * ones(n, 1), d * ((1 : n)' - 1), zeros(n, 2)];
end

function area = brute_area(pp, n_c, n_phi, m)
% Orientation averaged projected area from a fixed quadrature over the...
    % ...upper hemisphere (n_c Gauss-Legendre nodes in the cosine of the...
    % ...polar angle, n_phi equally spaced azimuths) and, in each...
    % ...direction, the covered points of an m x m midpoint grid on the...
    % ...bounding rectangle of the projected discs
[c, w] = gauss_legendre(n_c);
phi = 2 * pi * ((1 : n_phi)' - 0.5) / n_phi;
r = pp(:, 2) / 2;
xyz = pp(:, 3:5) - mean(pp(:, 3:5), 1);
area = 0;
for i = 1 : n_c
    s = sqrt(1 - c(i)^2);
    for j = 1 : n_phi
        u = [s * cos(phi(j)), s * sin(phi(j)), c(i)];
        e1 = [-sin(phi(j)), cos(phi(j)), 0];
        e2 = cross(u, e1);
        x = xyz * e1';
        y = xyz * e2';
        x0 = min(x - r);
        y0 = min(y - r);
        hx = (max(x + r) - x0) / m;
        hy = (max(y + r) - y0) / m;
        xc = x0 + ((1 : m) - 0.5) * hx;
        yc = y0 + ((1 : m)' - 0.5) * hy;
        covered = false(m, m);
        for k = 1 : numel(r)
            jx = find(abs(xc - x(k)) <= r(k));
            jy = find(abs(yc - y(k)) <= r(k));
            covered(jy, jx) = covered(jy, jx) | ...
                ((xc(jx) - x(k)).^2 + (yc(jy) - y(k)).^2 <= r(k)^2);
        end
        area = area + w(i) * nnz(covered) * hx * hy / n_phi;
    end
end
end

function [x, w] = gauss_legendre(n)
% Gauss-Legendre nodes and weights on [0, 1] from the eigenvalues and...
    % ...eigenvectors of the Jacobi matrix of the Legendre polynomials
b = (1 : n - 1) ./ sqrt(4 * (1 : n - 1).^2 - 1);
[v, e] = eig(diag(b, 1) + diag(b, -1));
[x, i] = sort(diag(e));
w = v(1, i)'.^2;
x = (x + 1) / 2;
end

function area = hull_area(v, a)
% Mean projected area of the convex hull of spheres of radius a centred...
    % ...at the rows of v, S / 4 (Cauchy formula) with the surface area...
    % ...S = S_P + a sum(l_e theta_e) + 4 pi a^2 of the hull P of the...
    % ...centres dilated by a (Steiner formula, l_e the length of an edge...
    % ...of P and theta_e the angle between the normals of its two faces)
tri = convhulln(v);
nrm = cross(v(tri(:, 2), :) - v(tri(:, 1), :), ...
    v(tri(:, 3), :) - v(tri(:, 1), :), 2);
s_p = sum(vecnorm(nrm, 2, 2)) / 2;
nrm = nrm ./ vecnorm(nrm, 2, 2);
inward = sum((v(tri(:, 1), :) - mean(v, 1)) .* nrm, 2) < 0;
nrm(inward, :) = -nrm(inward, :);
edges = sort([tri(:, [1, 2]); tri(:, [2, 3]); tri(:, [3, 1])], 2);
face = repmat((1 : size(tri, 1))', 3, 1);
[e_u, ~, g] = unique(edges, 'rows');
s_e = 0;
for q = 1 : size(e_u, 1)
    f2 = face(g == q);
    theta = acos(max(-1, min(1, dot(nrm(f2(1), :), nrm(f2(2), :)))));
    s_e = s_e + norm(v(e_u(q, 1), :) - v(e_u(q, 2), :)) * theta;
end
area = (s_p + a * s_e + 4 * pi * a^2) / 4;
end

function pars = population(d)
% Twelve aggregates (monomers, chains and clusters) placed apart
npp = [1; 2; 3; 1; 5; 8; 4; 1; 6; 12; 2; 20];
pp = cell(numel(npp), 1);
first = 0;
for i = 1 : numel(npp)
    if npp(i) <= 3
        xc = d * ((1 : npp(i))' - 1);
        q = [(1 : npp(i))', d * ones(npp(i), 1), xc, zeros(npp(i), 2)];
    else
        q = cluster(npp(i), d);
    end
    q(:, 1) = q(:, 1) + first;
    q(:, 3) = q(:, 3) + i * 1e-6; % one micrometer apart
    pp{i} = [q, i * ones(npp(i), 1)];
    first = first + npp(i);
end
pars = struct('n', npp, 'pp', {pp});
pars.r = PAR.COM(pars.pp, pars.n);
end

function draws = make_draws(n, res)
draws = cell(n, 1);
for i = 1 : n
    draws{i} = struct('rot', rand(res{3}, 3), 'off', rand(res{2}, 2));
end
end

function varargout = quiet(fun) %#ok<INUSD> called in evalc
% Running fun with its printed output and warnings captured
varargout = cell(1, max(nargout, 1));
[~, varargout{:}] = evalc('fun()');
end

function ok = raises_error(fun, id) %#ok<INUSL> called in evalc
ok = false;
try
    evalc('fun();');
catch err
    ok = strcmp(err.identifier, id);
end
end

function ok = raises_warning(fun, id)
% Turning the warning into an error to read its identifier
state = warning('error', id);
restore = onCleanup(@() warning(state));
ok = raises_error(fun, id);
end

function ok = no_warning(fun, ids) %#ok<INUSL> called in evalc
state = warning;
restore = onCleanup(@() warning(state));
for i = 1 : numel(ids)
    warning('error', ids{i});
end
ok = true;
try
    evalc('fun();');
catch
    ok = false;
end
end

function file = write_config(folder, cfg)
file = fullfile(folder, 'config.local.json');
fid = fopen(file, 'w');
fwrite(fid, jsonencode(cfg));
fclose(fid);
end

function ok = advanced(out)
% Two transport steps after the checkpoint at k = 1
ok = numel(out.ensdata.t) == 3 && all(diff(out.ensdata.t) > 0) && ...
    out.k == 4;
end

function [ok, out, sv] = resume_checkpoint(folder, model, opts_mobil, warns)
% Writing the checkpoint of step 1 with k_max = 3 and resuming it.
sv = write_checkpoint(folder, model, opts_mobil, 3, 50, 0, 1);
resume = @() UTILS.RESUME_LD2_V3(folder, 'checkpoint.mat');
if warns
    ok = raises_warning(resume, 'sootMosaic:ResumeLD2:NoProjectionModel');
    evalc('resume();');
else
    ok = no_warning(resume, {'sootMosaic:ResumeLD2:NoProjectionModel'});
end
out = load_final(folder);
end

function ok = resume_matches_full(folder, model, opts_mobil)
% Writing the checkpoint of step 1 with k_max = 4 and checkpoint_interval...
    % ...2 and running it to the end, the uninterrupted run, which writes...
    % ...its own checkpoint at k = 3. That checkpoint is then resumed. A...
    % ...snapshot is saved at every step (r_n_agg 1, five data points), so...
    % ...the saved data hold the snapshots of k = 2 and 3 before the...
    % ...checkpoint and of k = 4 after it. The resumed run must end with...
    % ...the same particles, ensemble data, saved data, mobility options...
    % ...(projected area cache included) and generator state as the...
    % ...uninterrupted run.
write_checkpoint(folder, model, opts_mobil, 4, 2, ones(1, 5), 5);
run_quiet(@() UTILS.RESUME_LD2_V3(folder, 'checkpoint.mat'));
rng_full = rng;
full = load_final(folder, true);
ck = dir(fullfile(folder, 'ckpt__*.mat'));
delete(fullfile(folder, 'final__*.mat'));
ok = isscalar(ck);
if ~ok
    return
end
mid = load(fullfile(folder, ck(1).name), 'parsdata', 'k');
run_quiet(@() UTILS.RESUME_LD2_V3(folder, ck(1).name));
rng_res = rng;
res = load_final(folder, true);
fields = {'pars_LD2', 'ensdata', 'parsdata', 'opts_mobil', 'k', 'fl'};
ok = mid.k == 3 && numel(mid.parsdata) >= 2 && ...
    snapshots_saved(full.parsdata, 3) && snapshots_saved(res.parsdata, 3) ...
    && isequaln(res.parsdata(1 : 2), mid.parsdata(1 : 2)) && ...
    full.k == 5 && numel(full.ensdata.t) == 4 && ...
    all(diff(full.ensdata.t) > 0) && isequal(rng_full, rng_res) && ...
    all(cellfun(@(x) isequaln(full.(x), res.(x)), fields));
end

function ok = snapshots_saved(parsdata, n)
% n saved data points, each with the primaries and one mobility and one...
    % ...projected area diameter per aggregate
ok = numel(parsdata) == n && all(arrayfun(@(s) isfield(s, 'pp') && ...
    ~isempty(s.pp) && numel(s.dm) == numel(s.npp) && ...
    numel(s.da) == numel(s.npp) && all(s.dm > 0), parsdata));
end

function out = load_final(folder, all_fields)
% Loading the final file of a resumed run
final = dir(fullfile(folder, 'final__*.mat'));
if nargin > 1 && all_fields
    out = load(fullfile(folder, final(end).name), 'cfg_ld2', 'opts_mobil', ...
        'pars_LD2', 'fl', 'ensdata', 'parsdata', 'k');
else
    out = load(fullfile(folder, final(end).name), 'cfg_ld2', 'opts_mobil', ...
        'pars_LD2', 'fl', 'ensdata', 'k');
end
end

function run_quiet(fun) %#ok<INUSD> called in evalc
% Running fun without outputs, its printed output captured
evalc('fun();');
end

function sv = write_checkpoint(folder, model, opts_mobil, k_max, ...
    checkpoint_interval, r_n_agg, n_dat) %#ok<INUSD> saved
% Building a small LD2 state as main_LD2_v3 does (twelve aggregates of 30...
    % ...nm primaries at 298 K and 101325 Pa) and writing it as the...
    % ...checkpoint of step 1.
mkdir(folder);
pars_LD2 = PAR.SIZING(population(30e-9));
[params_domain, params_const, fl] = UTILS.LD2_PARAMS_FROM_CONFIG( ...
    struct('volume_fraction', 1e-4, 'size', [1, 1, 1] * 1e-6), ...
    struct('temperature', 298, 'pressure', 101325));
opts_fl = struct('amb', 'sutherland');
[fl.mu, fl.lambda] = TRANSP.FLPROPS(fl, params_const, opts_fl);
rng(11);
[pars_LD2, opts_mobil] = quiet(@() TRANSP.MOBIL(pars_LD2, fl, ...
    params_const, opts_mobil)); %#ok<ASGLU> saved in the checkpoint
[pars_LD2, params_domain] = quiet(@() PAR.INIT_LOC(pars_LD2, ...
    params_domain, [], struct('vf', 'on')));
fl.size = params_domain.Value(2:4);
pars_LD2.v = PAR.INIT_VEL(pars_LD2.pp, pars_LD2.n, fl.temp, params_const);
opts_grow = struct('indupdate', 'off', 'dom_size', ...
    params_domain.Value(2:4)); %#ok<NASGU>
k = 1; %#ok<NASGU>
ind_dat = 1; %#ok<NASGU>
z1 = zeros(k_max, 1);
z2 = zeros(k_max, 2);
ensdata = struct('t', z1, 'n_agg', z1, 'tau', z2, 'kn_kin', z2, ...
    'kn_diff', z2, 'dpp', z2, 'sigmapp', z2, 'da', z2, 'dm', z2);
ensdata.n_agg(1) = numel(pars_LD2.n); %#ok<STRNU>
parsdata = struct('dm', {1}); %#ok<NASGU>
n_mc_prj = 100; %#ok<NASGU>
n_ang_prj = 5; %#ok<NASGU>
opts_prj = struct('tbar', 'off'); %#ok<NASGU>
dir_wsp = folder; %#ok<NASGU>
cfg_results = struct('checkpoint_prefix', 'ckpt', 'final_prefix', ...
    'final'); %#ok<NASGU>
rng_state = rng; %#ok<NASGU>
cfg_ld2 = struct('config_file', 'checkpoint', 'model', model); %#ok<NASGU>
sv = struct('pars_LD2', pars_LD2);
save(fullfile(folder, 'checkpoint.mat'), '-v7.3')
end
