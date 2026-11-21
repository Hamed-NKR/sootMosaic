function report = TEST_KNUDSEN_DIAGNOSTICS(repoRoot)
% "TEST_KNUDSEN_DIAGNOSTICS" checks the pair diffusive and nearest-neighbor...
%     ...Knudsen numbers of TRANSP.KNUDSEN, the periodic nearest neighbor,...
%     ...the diagnostics option of the model profiles and loaders, LD2...
%     ...resumes, and that the dynamics do not change with the diagnostics.
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
% Reference values are written out below as literals of ten digits. They...
%     ...follow from the sutherland properties at 101325 Pa, the kim2005...
%     ...slip correction, dm = dp for a monomer, the soot...
%     ...density 1860 kg/m3 and k = 1.381e-23 J/K of the parameter tables,...
%     ...with KnD = (kT m_ij)^0.5 pi R_S,ij / (f_ij PA_ij) (Eq. 11 of...
%     ...README reference 10) and Knn = (18 D tau)^0.5 / (n^(-1/3) - 2 rmax)...
%     ...(README reference 11, p. 275). A failed case stops with the...
%     ...identifier sootMosaic:QA:KnudsenDiagnosticsFailed.
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

names = {};
pass = [];
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
params_const = table([1860; 0.02897; 1.381e-23], 'VariableNames', {'Value'});
cur = UTILS.MODEL_PROFILE('current', 'LD1');
mob_cur = struct('mtd', cur.mobility, 'c_dt', 1, 'slip', ...
    cur.slip_correction, 'continuum_diameter', cur.continuum_diameter, ...
    'root_solve', cur.root_solve, 'projection', cur.projection, ...
    'proj_cache', cur.proj_cache, 'proj_points', cur.proj_points, ...
    'proj_orientations', cur.proj_orientations, 'proj_replicates', ...
    cur.proj_replicates, 'proj_tol', cur.proj_tol);

% hand values for monomers of 15 and 30 nm at 1700 K and 298 K under the...
%     ...current profile, eight monomers on a periodic lattice with the...
%     ...number concentration of the volume fraction fv
temps = [1700, 1700, 298, 298];
dps = [15e-9, 30e-9, 15e-9, 30e-9];
ref_kin = [66.3999258; 33.1999629; 9.044635866; 4.522317933];
ref_diff = [16.13785433; 5.733053305; 2.918200538; 1.071249385];
ref_pair = [11.41118623; 4.053880869; 2.06347939; 0.7574877043];
ref_lp = [5.1350338035e-07; 3.6484927818e-07; 9.2856572530e-08; ...
    6.8173893388e-08];
ref_rn3 = [1.0589939655e-07; 2.1179879310e-07; 1.0589939655e-07; ...
    2.1179879310e-07]; % rn at fv = 1e-3
ref_knn3 = [4.848973621; 1.722622083; 0.8768375983; 0.3218804621];
ref_knn7 = [0.1982869328; 0.07044242267; 0.03585613195; 0.01316251532];
ok_hand = true;
ok_sqrt2 = true;
for c = 1 : 4
    fl = sutherland(temps(c), params_const);
    [kn3, p] = lattice(dps(c), 1e-3, fl, params_const, mob_cur);
    kn7 = lattice(dps(c), 1e-7, fl, params_const, mob_cur);
    ok_hand = ok_hand && all(p.dm == dps(c)) && ...
        near(p.kn_kin, ref_kin(c), 1e-9) && ...
        near(p.kn_diff, ref_diff(c), 1e-9) && ...
        near(kn3.kn_pair, ref_pair(c), 1e-9) && ...
        near(kn3.lambda_p, ref_lp(c), 1e-9) && ...
        near(kn3.rn, ref_rn3(c), 1e-9) && ...
        near(kn3.knn, ref_knn3(c), 1e-9) && ...
        near(kn7.knn, ref_knn7(c), 1e-9) && kn3.knn_defined && ...
        kn7.knn_defined;
    ok_sqrt2 = ok_sqrt2 && near(kn3.kn_pair, p.kn_diff / sqrt(2), 1e-14);
end
[names, pass] = add(names, pass, ...
    'hand values for 15 and 30 nm monomers at 1700 K and 298 K', ok_hand);
[names, pass] = add(names, pass, ...
    'identical spheres give pair KnD = kn_diff / 2^0.5', ok_sqrt2);

% mixed pair of a 15 nm and a 30 nm monomer
ref_mix = [6.34565017, 1.15515737];
ok_mix = true;
for c = 1 : 2
    fl = sutherland(temps(2 * c), params_const);
    fl.size = [1, 1, 1] * 1e-6;
    pars = monomers([15e-9; 30e-9], [0.2, 0.5, 0.5; 0.3, 0.5, 0.5] * 1e-6);
    pars = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_cur));
    kn = TRANSP.KNUDSEN(pars, fl, params_const, mob_cur);
    ok_mix = ok_mix && isequal(kn.nn, [2; 1]) && near(kn.kn_pair, ...
        ref_mix(c), 1e-9);
end
[names, pass] = add(names, pass, ...
    'mixed pair of 15 and 30 nm monomers at 1700 K and 298 K', ok_mix);

% review table B5, article 1 settings (flame preset, Eq. 17, MOBIL...
%     ...constants), kn_diff 16.2 and 5.76, Knn 4.87, 0.199, 1.73 and 0.071
fl = struct('temp', 1700, 'mu', 5.647e-5, 'lambda', 4.98e-7);
mob_a1 = struct('mtd', 'continuum', 'c_dt', 1);
b5_diff = [16.2, 5.76];
b5_knn = [4.87, 0.199; 1.73, 0.071];
ok_b5 = true;
for c = 1 : 2
    [kn3, p] = lattice(dps(c), 1e-3, fl, params_const, mob_a1);
    kn7 = lattice(dps(c), 1e-7, fl, params_const, mob_a1);
    ok_b5 = ok_b5 && near(p.kn_diff, b5_diff(c), 5e-3) && ...
        near(kn3.knn, b5_knn(c, 1), 5e-3) && near(kn7.knn, b5_knn(c, 2), 5e-3);
end
[names, pass] = add(names, pass, ...
    'article 1 settings reproduce review table B5 within 0.5 percent', ok_b5);

% LD2 aggregate of table B5 (N = 24, dp = 30 nm, dm = 125 nm, 298 K,...
%     ...room preset, MOBIL constants), mass and friction as literals, two...
%     ...such aggregates as nearest neighbors
m_b5 = 6.3108313225e-19;
f_b5 = 8.4666937556e-12;
fl = struct('temp', 298, 'mu', 1.813e-5, 'lambda', 6.8e-8, ...
    'size', [1, 1, 1] * 2e-6);
kt = 1.381e-23 * 298;
pp = {[(1 : 24)', 30e-9 * ones(24, 1), zeros(24, 3), ones(24, 1)]; ...
    [(25 : 48)', 30e-9 * ones(24, 1), zeros(24, 3), 2 * ones(24, 1)]};
pars = struct('n', [24; 24], 'pp', {pp}, 'r', [0.5, 1, 1; 1.5, 1, 1] * 1e-6, ...
    'dmax', [300e-9; 300e-9], 'm', [m_b5; m_b5], 'f', [f_b5; f_b5], ...
    'dm', [125e-9; 125e-9], 'da', [130e-9; 130e-9], ...
    'diff', kt / f_b5 * [1; 1], 'tau', m_b5 / f_b5 * [1; 1]);
kn_e = TRANSP.KNUDSEN(pars, fl, params_const, struct('mtd', 'sorensen_eq17'));
kn_i = TRANSP.KNUDSEN(pars, fl, params_const, struct('mtd', 'interp'));
kd_b5 = 2 * sqrt(m_b5 * kt) / (f_b5 * 125e-9);
[names, pass] = add(names, pass, ...
    'LD2 aggregate of table B5, kn_diff 0.0963 and pair KnD 0.0681', ...
    near(kd_b5, 0.09630623143, 1e-9) && near(kd_b5, 0.096, 5e-3) && ...
    near(kn_e.kn_pair, 0.06809878932, 1e-9) && ...
    near(kn_e.lambda_p, 2.5537045993e-08, 1e-9));
[names, pass] = add(names, pass, ...
    'interp takes da for the combined projected area (da = 130 nm)', ...
    near(kn_i.kn_pair, 0.06296115876, 1e-9));

% periodic nearest neighbor across a face, an edge and a corner
L = [1, 1, 1] * 1e-6;
x3 = [0.02, 0.5, 0.5; 0.97, 0.5, 0.5; 0.30, 0.5, 0.5] * 1e-6;
[nn3, d3] = nearest_of(x3, L);
rng(21);
x_many = 0.1e-6 + 0.8e-6 * rand(1000, 3); % away from the faces
x_many(1 : 4, :) = [0.001, 0.5, 0.5; 0.998, 0.5, 0.5; ...
    0.001, 0.001, 0.001; 0.999, 0.999, 0.998] * 1e-6;
[nnm, dm_] = nearest_of(x_many, L);
[names, pass] = add(names, pass, ...
    'periodic nearest neighbor found across a face', ...
    nn3(1) == 2 && nn3(2) == 1 && near(d3(1), 0.05e-6, 1e-12) && ...
    nnm(1) == 2 && nnm(2) == 1 && near(dm_(1), 0.003e-6, 1e-9));
[names, pass] = add(names, pass, ...
    'periodic nearest neighbor found across an edge and a corner', ...
    nnm(3) == 4 && nnm(4) == 3 && near(dm_(3), sqrt(0.002^2 + 0.002^2 + ...
    0.003^2) * 1e-6, 1e-9));
ok_bf = true;
Lb = [1, 0.7, 1.3] * 1e-6;
for n = [2, 3, 7, 60, 3000]
    x = (rand(n, 3) - 0.1) .* Lb * 1.2; % some outside the domain
    [nn, d] = nearest_of(x, Lb);
    [nn_b, d_b] = brute(x, Lb);
    ok_bf = ok_bf && isequal(nn, nn_b) && near(d, d_b, 1e-12);
end
[names, pass] = add(names, pass, ...
    'nearest neighbors equal an all-pairs minimum image search', ok_bf);

% rn <= 0, Knn not defined
fl = sutherland(298, params_const);
fl.size = [1, 1, 1] * 50e-9;
pars = monomers(30e-9 * ones(8, 1), lattice_points(25e-9));
pars = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_cur));
kn = TRANSP.KNUDSEN(pars, fl, params_const, mob_cur);
[names, pass] = add(names, pass, ...
    'Knn not defined when rn <= 0 (NaN with knn_defined false)', ...
    ~kn.knn_defined && kn.rn < 0 && all(isnan(kn.knn)) && ...
    all(isfinite(kn.kn_pair)));
fl.size = [1, 1, 1] * 1e-6;
pars1 = monomers(30e-9, [0.5, 0.5, 0.5] * 1e-6);
pars1 = quiet(@() TRANSP.MOBIL(pars1, fl, params_const, mob_cur));
kn1 = TRANSP.KNUDSEN(pars1, fl, params_const, mob_cur);
[names, pass] = add(names, pass, ...
    'a single particle has no neighbor and pair KnD NaN', ...
    kn1.nn == 0 && isnan(kn1.kn_pair) && isnan(kn1.d_nn));

% diagnostics change neither the particles nor the generator state
rng(4);
s0 = rng;
x = rand(500, 3) * 1e-6;
pars = monomers(30e-9 * (1 + rand(500, 1)), x);
pars = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob_cur));
s1 = rng;
p_before = pars;
kn = TRANSP.KNUDSEN(pars, fl, params_const, mob_cur);
[names, pass] = add(names, pass, ...
    'KNUDSEN leaves the particles and the random number state unchanged', ...
    isequal(rng, s1) && ~isequal(s0, s1) && isequaln(pars, p_before) && ...
    all(isfinite(kn.kn_pair)));

% model profiles and loaders
m1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
m2 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
m3 = UTILS.MODEL_PROFILE('current', 'LD1');
m4 = UTILS.MODEL_PROFILE('current', 'LD2');
[names, pass] = add(names, pass, 'profile diagnostics defaults', ...
    isequal(m1.knudsen_diagnostics, false) && ...
    isequal(m2.knudsen_diagnostics, false) && ...
    isequal(m3.knudsen_diagnostics, true) && ...
    isequal(m4.knudsen_diagnostics, true));
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, 's'));
ld1 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld1', ...
    'main_ld1_config.example.json')));
ld1 = QA.LD1_CONFIG_EXPLICIT_CHOICES(ld1);
ld2 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld2', ...
    'main_ld2_from_main_scatter_config.example.json')));
ld2 = QA.LD2_CONFIG_EXPLICIT_CHOICES(ld2);
ld2s = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld2', ...
    'main_ld2_from_main_scale_config.example.json')));
ld2s = QA.LD2_CONFIG_EXPLICIT_CHOICES(ld2s);
f1 = @(c) UTILS.LOAD_MAIN_LD1_CONFIG(write_config(tmp, c));
f2 = @(c) UTILS.LOAD_MAIN_LD2_CONFIG(write_config(tmp, c));
examples = {ld1, ld2, ld2s};
loaders = {f1, f2, f2};
stage = {'LD1', 'LD2', 'LD2'};
ok_ex = true;
ok_def = true;
ok_bad = true;
ok_ovr = true;
for i = 1 : 3
    cfg = quiet(@() loaders{i}(examples{i}));
    ok_ex = ok_ex && isequal(cfg.model.knudsen_diagnostics, true) && ...
        isequal(cfg.transport.diagnostics_options.knudsen, true);
    c = examples{i};
    c.transport = rmfield(c.transport, 'diagnostics_options');
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && isequal(cfg.model.knudsen_diagnostics, true) && ...
        isequal(cfg.transport.diagnostics_options.knudsen, true);
    c.model_profile = 'article1_7658971';
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && isequal(cfg.model.knudsen_diagnostics, false);
    c = examples{i};
    c.model_profile = 'current';
    c.transport.diagnostics_options.knudsen = false;
    cfg = quiet(@() loaders{i}(c));
    ok_ovr = ok_ovr && isequal(cfg.model.knudsen_diagnostics, false) && ...
        isequal(cfg.transport.diagnostics_options.knudsen, false);
    c = examples{i};
    c.model_profile = 'article1_7658971';
    c.transport.diagnostics_options.knudsen = true;
    cfg = quiet(@() loaders{i}(c));
    ok_ovr = ok_ovr && isequal(cfg.model.knudsen_diagnostics, true) && ...
        isequal(cfg.transport.diagnostics_options.knudsen, true);
    c = examples{i};
    c.model_profile = 'article1_7658971';
    c.transport.diagnostics_options.knudsen = false;
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && isequal(cfg.model.knudsen_diagnostics, false);
    c.transport.diagnostics_options.knudsen = 'yes';
    ok_bad = ok_bad && raises_error(@() loaders{i}(c), sprintf( ...
        'sootMosaic:LOAD_MAIN_%s_CONFIG:InvalidLogical', stage{i}));
    c.transport.diagnostics_options = 1;
    section_id = 'sootMosaic:CONFIG_READ:InvalidType';
    ok_bad = ok_bad && raises_error(@() loaders{i}(c), section_id);
end
[names, pass] = add(names, pass, ...
    'task fixtures record the diagnostics and save the option', ok_ex);
[names, pass] = add(names, pass, ...
    'profile default without the field, explicit field wins', ok_def);
[names, pass] = add(names, pass, ...
    'explicit option overrides the profile default in both loaders', ok_ovr);
[names, pass] = add(names, pass, ...
    'loaders reject a non-logical option and a non-struct section', ok_bad);

% LD2 resumes that advance two transport steps
model_c = UTILS.MODEL_PROFILE('current', 'LD2');
model_off = model_c;
model_off.knudsen_diagnostics = false;
mob = struct('mtd', 'interp', 'c_dt', 1, 'slip', 'kim2005', ...
    'continuum_diameter', 'sorensen_backbone', 'root_solve', 'bracketed');
[ok_on, on] = resume_checkpoint(fullfile(tmp, 'r1'), model_c, ...
    struct('knudsen', true), mob, false);
[ok_off, off] = resume_checkpoint(fullfile(tmp, 'r2'), model_off, ...
    struct('knudsen', false), mob, false);
common = setdiff(fieldnames(on.ensdata), {'kn_pair', 'knn', 'knn_defined'});
same = true;
for i = 1 : numel(common)
    same = same && isequaln(on.ensdata.(common{i}), off.ensdata.(common{i}));
end
[names, pass] = add(names, pass, ...
    'dynamics bit identical with and without the diagnostics', ...
    ok_on && ok_off && isequaln(on.pars_LD2, off.pars_LD2) && same && ...
    isequaln(on.opts_mobil, off.opts_mobil) && advanced(on) && ...
    ~isfield(off.ensdata, 'kn_pair') && isfield(on.ensdata, 'kn_pair'));
[names, pass] = add(names, pass, ...
    'resume records the diagnostics after the checkpoint', ...
    all(isnan(on.ensdata.kn_pair(1, :))) && ...
    all(isfinite(on.ensdata.kn_pair(2 : 3, :)), 'all') && ...
    all(isfinite(on.ensdata.knn(2 : 3, :)), 'all') && ...
    isequal(on.ensdata.knn_defined(:)', [false, true, true]) && ...
    isequal(on.cfg_ld2.model, model_c));
model_p17 = rmfield(model_c, 'knudsen_diagnostics');
[ok, out] = resume_checkpoint(fullfile(tmp, 'r3'), model_p17, [], mob, true);
[names, pass] = add(names, pass, ...
    'resume without the option warns NoKnudsenModel and records none', ...
    ok && isequal(out.cfg_ld2.model.knudsen_diagnostics, false) && ...
    ~isfield(out.ensdata, 'kn_pair') && advanced(out) && ...
    isequaln(out.pars_LD2, off.pars_LD2));

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
    error('sootMosaic:QA:KnudsenDiagnosticsFailed', '%d of %d cases failed.', ...
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

function fl = sutherland(temp, params_const)
% Gas properties of the sutherland model at temp and 101325 Pa
fl = struct('temp', temp, 'p', 101325);
[fl.mu, fl.lambda] = TRANSP.FLPROPS(fl, params_const, ...
    struct('amb', 'sutherland'));
end

function pars = monomers(dpp, r)
% Single primaries of diameters dpp at the positions r (columns index,...
%     ...diameter, x, y, z and subaggregate label)
n = numel(dpp);
pp = cell(n, 1);
for i = 1 : n
    pp{i} = [i, dpp(i), r(i, :), i];
end
pars = PAR.SIZING(struct('n', ones(n, 1), 'pp', {pp}, 'r', r));
end

function x = lattice_points(a)
% Eight points of a cubic lattice of spacing a in a box of side 2 a
[i1, i2, i3] = ndgrid([0.5, 1.5]);
x = a * [i1(:), i2(:), i3(:)];
end

function [kn, pars] = lattice(dpp, fv, fl, params_const, mob)
% Eight identical monomers with the number concentration fv / (pi dpp^3 / 6)
a = (fv / (pi * dpp^3 / 6))^(-1/3);
fl.size = [2, 2, 2] * a;
pars = monomers(dpp * ones(8, 1), lattice_points(a));
pars = quiet(@() TRANSP.MOBIL(pars, fl, params_const, mob));
kn = TRANSP.KNUDSEN(pars, fl, params_const, mob);
end

function [nn, d] = nearest_of(x, dom_size)
% Nearest neighbors through TRANSP.KNUDSEN with placeholder properties
n = size(x, 1);
pars = struct('n', ones(n, 1), 'pp', {num2cell(ones(n, 1))}, 'r', x, ...
    'dmax', 1e-9 * ones(n, 1), 'm', ones(n, 1), 'f', ones(n, 1), ...
    'dm', ones(n, 1), 'diff', ones(n, 1), 'tau', ones(n, 1));
fl = struct('temp', 300, 'size', dom_size);
kn = TRANSP.KNUDSEN(pars, fl, table(1.381e-23 * [1; 1; 1], ...
    'VariableNames', {'Value'}));
nn = kn.nn;
d = kn.d_nn;
end

function [nn, d] = brute(x, dom_size)
% All pairs under the minimum image convention, written out here
n = size(x, 1);
nn = zeros(n, 1);
d = zeros(n, 1);
for i = 1 : n
    best = Inf;
    for j = 1 : n
        if j == i
            continue
        end
        dx = mod(x(j, :) - x(i, :) + dom_size / 2, dom_size) - dom_size / 2;
        dj = norm(dx);
        if dj < best
            best = dj;
            nn(i) = j;
        end
    end
    d(i) = best;
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

function [ok, out] = resume_checkpoint(folder, model, opts_diag, opts_mobil, ...
    warns)
% Building a small LD2 state as main_LD2_v3 does (eight chains of 30 nm...
%     ...primaries at 298 K and 101325 Pa), writing it as the checkpoint...
%     ...of step 1 with k_max = 3 and resuming it. An empty opts_diag...
%     ...writes a checkpoint without the diagnostics option.
mkdir(folder);
npp = [1; 1; 2; 2; 3; 3; 5; 5];
pp = cell(8, 1);
for i = 1 : 8
    xc = 30e-9 * ((1 : npp(i))' - (npp(i) + 1) / 2);
    pp{i} = [sum(npp(1 : i - 1)) + (1 : npp(i))', 30e-9 * ones(npp(i), 1), ...
        xc, zeros(npp(i), 2), i * ones(npp(i), 1)];
end
pars_LD2 = PAR.SIZING(struct('n', npp, 'pp', {pp}));
[params_domain, params_const, fl] = UTILS.LD2_PARAMS_FROM_CONFIG( ...
    struct('volume_fraction', 1e-4, 'size', [1, 1, 1] * 1e-6), ...
    struct('temperature', 298, 'pressure', 101325));
opts_fl = struct('amb', 'sutherland');
[fl.mu, fl.lambda] = TRANSP.FLPROPS(fl, params_const, opts_fl);
rng(11);
pars_LD2 = quiet(@() TRANSP.MOBIL(pars_LD2, fl, params_const, opts_mobil));
[pars_LD2, params_domain] = quiet(@() PAR.INIT_LOC(pars_LD2, ...
    params_domain, [], struct('vf', 'on')));
fl.size = params_domain.Value(2:4);
pars_LD2.v = PAR.INIT_VEL(pars_LD2.pp, pars_LD2.n, fl.temp, params_const);
opts_grow = struct('indupdate', 'off', 'dom_size', ...
    params_domain.Value(2:4)); %#ok<NASGU>
k = 1; %#ok<NASGU>
k_max = 3;
ind_dat = 1; %#ok<NASGU>
n_dat = 1; %#ok<NASGU>
r_n_agg = 0; %#ok<NASGU>
z1 = zeros(k_max, 1);
z2 = zeros(k_max, 2);
ensdata = struct('t', z1, 'n_agg', z1, 'tau', z2, 'kn_kin', z2, ...
    'kn_diff', z2, 'dpp', z2, 'sigmapp', z2, 'da', z2, 'dm', z2);
ensdata.n_agg(1) = numel(pars_LD2.n); %#ok<STRNU>
parsdata = struct('dm', {1}); %#ok<NASGU>
n_mc_prj = 100; %#ok<NASGU>
n_ang_prj = 5; %#ok<NASGU>
opts_prj = struct('tbar', 'off'); %#ok<NASGU>
checkpoint_interval = 50; %#ok<NASGU>
dir_wsp = folder; %#ok<NASGU>
cfg_results = struct('checkpoint_prefix', 'ckpt', 'final_prefix', ...
    'final'); %#ok<NASGU>
rng_state = rng; %#ok<NASGU>
cfg_ld2 = struct('config_file', 'checkpoint', 'model', model); %#ok<NASGU>
if isempty(opts_diag)
    clear opts_diag % a checkpoint without the option
end
save(fullfile(folder, 'checkpoint.mat'), '-v7.3')
resume = @() UTILS.RESUME_LD2_V3(folder, 'checkpoint.mat');
if warns
    ok = raises_warning(resume, 'sootMosaic:ResumeLD2:NoKnudsenModel');
    evalc('resume();');
else
    ok = no_warning(resume, {'sootMosaic:ResumeLD2:NoKnudsenModel'});
end
final = dir(fullfile(folder, 'final__*.mat'));
out = load(fullfile(folder, final(end).name), 'cfg_ld2', 'opts_mobil', ...
    'pars_LD2', 'fl', 'ensdata', 'k');
end
