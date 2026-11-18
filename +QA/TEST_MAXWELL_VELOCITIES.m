function report = TEST_MAXWELL_VELOCITIES(repoRoot)
% "TEST_MAXWELL_VELOCITIES" checks the initial velocity samplers of...
%     ...PAR.INIT_VEL, their model profile option, the LD1 and LD2 config...
%     ...loaders and LD2 resumes.
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
% The distribution tests use 1e5 seeded particles of one to three primaries...
%     ...of 10 to 50 nm at 1700 K. Velocity components are scaled by...
%     ...(kT / m)^0.5 with the mass written out here, and compared with the...
%     ...standard normal distribution, and the scaled speeds with the...
%     ...Maxwell distribution, whose cumulative distribution is the...
%     ...regularized lower incomplete gamma function P(3/2, s^2 / 2). The...
%     ...Kolmogorov-Smirnov statistic is checked against 1.9494 / n^0.5,...
%     ...the asymptotic critical value at the 0.001 level. A failed case...
%     ...stops with the identifier sootMosaic:QA:MaxwellVelocitiesFailed.
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

names = {};
pass = [];
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
params_const = table([1860; 0.02897; 1.381e-23], 'VariableNames', {'Value'});
kt = 1.381e-23 * 1700;

% seeded population
rng(31);
n = 1e5;
[pp, npp, m] = population(n);
d_crit = 1.9494 / sqrt(n);

% legacy sampler, its expression written out with the same seed
rng(7);
v_def = PAR.INIT_VEL(pp, npp, 1700, params_const);
s_def = rng;
rng(7);
v_leg = PAR.INIT_VEL(pp, npp, 1700, params_const, 'mean_speed_7658971');
s_leg = rng;
rng(7);
m_old = old_mass(pp, npp, params_const);
u_old = ((8 * params_const.Value(3) * 1700 / pi) ./ m_old).^(1/2);
theta = pi * rand(n, 1);
phi = 2 * pi * rand(n, 1);
v_old = zeros(n, 3);
v_old(:, 1) = u_old .* sin(theta) .* cos(phi);
v_old(:, 2) = u_old .* sin(theta) .* sin(phi);
v_old(:, 3) = u_old .* cos(theta);
[names, pass] = add(names, pass, ...
    'legacy sampler bit identical to 7658971, also without the option', ...
    isequal(v_def, v_old) && isequal(v_leg, v_old) && ...
    isequal(s_def, rng) && isequal(s_leg, rng));
ke_leg = 0.5 * m .* sum(v_leg.^2, 2) / kt;
[names, pass] = add(names, pass, ...
    'legacy sampler gives every particle the kinetic energy 4 kT / pi', ...
    max(abs(ke_leg / (4 / pi) - 1)) < 1e-12);

% Maxwell-Boltzmann sampler and its random number use
rng(8);
v = PAR.INIT_VEL(pp, npp, 1700, params_const, 'maxwell_boltzmann');
s_mb = rng;
rng(8);
v_w = sqrt(params_const.Value(3) * 1700 ./ m_old) .* ...
    [randn(n, 1), randn(n, 1), randn(n, 1)];
[names, pass] = add(names, pass, ...
    'maxwell_boltzmann takes three normal numbers per particle', ...
    isequal(v, v_w) && isequal(s_mb, rng));

z = v ./ sqrt(kt ./ m); % components in units of (kT / m)^0.5
d_comp = zeros(1, 3);
for a = 1 : 3
    d_comp(a) = ks(z(:, a), @(x) 0.5 * erfc(-x / sqrt(2)));
end
var_z = var(z);
fprintf(['components, KS statistic %.4f %.4f %.4f (limit %.4f), ', ...
    'variance / (kT / m) %.4f %.4f %.4f\n'], d_comp, d_crit, var_z);
[names, pass] = add(names, pass, ...
    'each component is normal with variance kT / m (KS on 1e5 samples)', ...
    all(d_comp < d_crit) && all(abs(var_z - 1) < 0.02) && ...
    all(abs(mean(z)) < 4 / sqrt(n)));
ke = mean(0.5 * m .* sum(v.^2, 2)) / kt;
fprintf('mean kinetic energy %.5f kT\n', ke);
[names, pass] = add(names, pass, ...
    'mean kinetic energy is 1.5 kT within 2 percent', abs(ke / 1.5 - 1) < 0.02);
c = corrcoef(z);
c_off = [c(1, 2), c(1, 3), c(2, 3)];
fprintf('component correlations %.4f %.4f %.4f (limit %.4f)\n', c_off, ...
    4 / sqrt(n));
[names, pass] = add(names, pass, 'the components are uncorrelated', ...
    all(abs(c_off) < 4 / sqrt(n)));

% speed distribution, Maxwell for the sampler, not for a fixed speed
maxwell = @(s) gammainc(s.^2 / 2, 1.5);
d_mb = ks(sqrt(sum(z.^2, 2)), maxwell);
rng(9);
w = randn(n, 3);
w = w ./ sqrt(sum(w.^2, 2)); % isotropic directions
v_fix = sqrt(8 / pi) * w; % fixed speed, the Maxwell mean
d_fix = ks(sqrt(sum(v_fix.^2, 2)), maxwell);
d_leg = ks(sqrt(sum((v_leg ./ sqrt(kt ./ m)).^2, 2)), maxwell);
fprintf(['speed KS statistic, maxwell_boltzmann %.4f, fixed speed ', ...
    'isotropic %.4f, mean_speed_7658971 %.4f (limit %.4f)\n'], d_mb, ...
    d_fix, d_leg, d_crit);
[names, pass] = add(names, pass, ...
    'speeds are Maxwellian and a fixed-speed isotropic sampler fails', ...
    d_mb < d_crit && d_fix > d_crit && d_leg > d_crit);
[names, pass] = add(names, pass, 'unknown sampler rejected', ...
    raises_error(@() PAR.INIT_VEL(pp(1 : 3), npp(1 : 3), 1700, ...
    params_const, 'uniform'), 'sootMosaic:INIT_VEL:UnknownMethod'));

% model profiles and loaders
m1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
m2 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
m3 = UTILS.MODEL_PROFILE('current', 'LD1');
[m4, known] = UTILS.MODEL_PROFILE('current', 'LD2');
[names, pass] = add(names, pass, 'profile sampler defaults', ...
    strcmp(m1.initial_velocity, 'mean_speed_7658971') && ...
    strcmp(m2.initial_velocity, 'mean_speed_7658971') && ...
    strcmp(m3.initial_velocity, 'maxwell_boltzmann') && ...
    strcmp(m4.initial_velocity, 'maxwell_boltzmann') && ...
    isequal(known.initial_velocity, {'maxwell_boltzmann', ...
    'mean_speed_7658971'}));
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
ok_def = true;
ok_bad = true;
for i = 1 : 3
    cfg = quiet(@() loaders{i}(examples{i}));
    ok_ex = ok_ex && strcmp(cfg.model.initial_velocity, ...
        'maxwell_boltzmann') && strcmp(cfg.transport.velocity_options.sampler, ...
        'maxwell_boltzmann');
    c = examples{i};
    c.transport = rmfield(c.transport, 'velocity_options');
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && strcmp(cfg.model.initial_velocity, 'maxwell_boltzmann');
    c.model_profile = 'article1_7658971';
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && strcmp(cfg.model.initial_velocity, ...
        'mean_speed_7658971') && strcmp(cfg.transport.velocity_options.sampler, ...
        'mean_speed_7658971');
    c = examples{i};
    c.model_profile = 'article1_7658971';
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && strcmp(cfg.model.initial_velocity, 'maxwell_boltzmann');
    c = examples{i};
    c.model_profile = 'current';
    c.transport.velocity_options.sampler = 'mean_speed_7658971';
    cfg = quiet(@() loaders{i}(c));
    ok_def = ok_def && strcmp(cfg.model.initial_velocity, ...
        'mean_speed_7658971') && strcmp(cfg.transport.velocity_options.sampler, ...
        'mean_speed_7658971');
    c = examples{i};
    c.model_profile = 'article1_7658971';
    c.transport.velocity_options.sampler = 'uniform';
    ok_bad = ok_bad && raises_error(@() loaders{i}(c), sprintf( ...
        'sootMosaic:LOAD_MAIN_%s_CONFIG:InvalidChoice', stage{i}));
    c.transport.velocity_options = 'maxwell_boltzmann';
    ok_bad = ok_bad && raises_error(@() loaders{i}(c), sprintf( ...
        'sootMosaic:LOAD_MAIN_%s_CONFIG:MissingSection', stage{i}));
end
[names, pass] = add(names, pass, ...
    'example configs name maxwell_boltzmann and save it', ok_ex);
[names, pass] = add(names, pass, ...
    'profile default without the field, explicit field wins', ok_def);
[names, pass] = add(names, pass, ...
    'loaders reject unknown samplers and a non-struct section', ok_bad);

% LD2 resumes that advance two transport steps. Each checkpoint is also...
%     ...continued by the primitives of the main loop under its saved...
%     ...generator state, which gives the uninterrupted reference.
model_c = UTILS.MODEL_PROFILE('current', 'LD2');
mob = struct('mtd', 'interp', 'c_dt', 1, 'slip', 'kim2005', ...
    'continuum_diameter', 'sorensen_backbone', 'root_solve', 'bracketed');
[ok_c, out_c] = resume_checkpoint(fullfile(tmp, 'r1'), model_c, mob, false, ...
    'maxwell_boltzmann');
model_p18 = rmfield(model_c, 'initial_velocity');
[ok_p, out_p] = resume_checkpoint(fullfile(tmp, 'r2'), model_p18, mob, true, ...
    'mean_speed_7658971');
[names, pass] = add(names, pass, ...
    'resume keeps a saved sampler name and records mean_speed_7658971 if missing', ...
    ok_c && ok_p && isequal(out_c.cfg_ld2.model, model_c) && ...
    strcmp(out_p.cfg_ld2.model.initial_velocity, 'mean_speed_7658971') && ...
    isequal(rmfield(out_p.cfg_ld2.model, 'initial_velocity'), model_p18) && ...
    numel(out_c.ensdata.t) == 3 && out_c.k == 4 && out_p.k == 4);
ke_p = 0.5 * out_p.m0 .* sum(out_p.v0.^2, 2) / (1.381e-23 * out_p.temp);
[names, pass] = add(names, pass, ...
    'resume continues the checkpoint velocities and generator state', ...
    max(abs(ke_p / (4 / pi) - 1)) < 1e-12 && ...
    isequaln(out_p.pars_LD2, out_p.ref_pars) && ...
    isequal(out_p.rng_res, out_p.rng_ref) && ...
    isequaln(out_c.pars_LD2, out_c.ref_pars) && ...
    isequal(out_c.rng_res, out_c.rng_ref) && ...
    ~isequaln(out_c.pars_LD2.v, out_p.pars_LD2.v));

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
    error('sootMosaic:QA:MaxwellVelocitiesFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass))
end

end

function [names, pass] = add(names, pass, name, ok)
names{end + 1, 1} = name;
pass(end + 1, 1) = logical(ok);
end

function [pp, npp, m] = population(n)
% n particles of one to three primaries of 10 to 50 nm (columns index,...
%     ...diameter, x, y, z and subaggregate label) and their masses
npp = randi(3, n, 1);
pp = cell(n, 1);
m = zeros(n, 1);
first = [0; cumsum(npp)];
for i = 1 : n
    d = 10e-9 + 40e-9 * rand(npp(i), 1);
    pp{i} = [first(i) + (1 : npp(i))', d, zeros(npp(i), 3), ...
        i * ones(npp(i), 1)];
    m(i) = 1860 * pi / 6 * sum(d.^3);
end
end

function m = old_mass(pp, npp, params_const)
% Particle masses in the order of operations of the legacy sampler
pp = cell2mat(pp);
m_pp = (pi * params_const.Value(1) / 6) .* ((pp(:, 2)).^3);
m_pp = mat2cell(m_pp, npp);
m = zeros(numel(npp), 1);
for i = 1 : numel(npp)
    m(i) = sum(m_pp{i});
end
end

function d = ks(x, cdf)
% Kolmogorov-Smirnov statistic of the sample x against the distribution cdf
x = sort(x(:));
n = numel(x);
f = cdf(x);
d = max(max((1 : n)' / n - f), max(f - (0 : n - 1)' / n));
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

function [ok, out] = resume_checkpoint(folder, model, opts_mobil, warns, sampler)
% Building a small LD2 state as main_LD2_v3 does (eight chains of 30 nm...
%     ...primaries at 298 K and 101325 Pa, velocities of the named...
%     ...sampler), writing it as the checkpoint of step 1 with k_max = 3,...
%     ...continuing it with the primitives of the main loop as the...
%     ...reference and resuming it.
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
pars_LD2.v = PAR.INIT_VEL(pars_LD2.pp, pars_LD2.n, fl.temp, params_const, ...
    sampler);
opts_grow = struct('indupdate', 'off', 'dom_size', ...
    params_domain.Value(2:4)); %#ok<NASGU>
opts_diag = struct('knudsen', false); %#ok<NASGU>
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
save(fullfile(folder, 'checkpoint.mat'), '-v7.3')

% uninterrupted continuation of the saved state
st = load(fullfile(folder, 'checkpoint.mat'));
rng(st.rng_state);
p = st.pars_LD2;
o = st.opts_mobil;
for f = {'projection', 'proj_cache', 'proj_points', 'proj_orientations', ...
        'proj_replicates', 'proj_tol'} % projected area options of the model
    if ~isfield(o, f{1})
        o.(f{1}) = st.model.(f{1});
    end
end
for kk = st.k + 1 : st.k_max
    p = TRANSP.MARCH(p, st.fl, st.params_const);
    p = TRANSP.PBC(st.params_domain.Value(2:4), p);
    p = COL.GROW(p, st.opts_grow);
    p.n_hyb = COL.HYBRIDITY(p.pp, p.n);
    p = PAR.SIZING(p);
    [p, o] = quiet(@() TRANSP.MOBIL(p, st.fl, st.params_const, o));
end
rng_ref = rng;

resume = @() UTILS.RESUME_LD2_V3(folder, 'checkpoint.mat');
if warns
    ok = raises_warning(resume, 'sootMosaic:ResumeLD2:NoVelocityModel');
    evalc('resume();');
else
    ok = no_warning(resume, {'sootMosaic:ResumeLD2:NoVelocityModel'});
end
rng_res = rng;
final = dir(fullfile(folder, 'final__*.mat'));
out = load(fullfile(folder, final(end).name), 'cfg_ld2', 'opts_mobil', ...
    'pars_LD2', 'fl', 'ensdata', 'k');
out.ref_pars = p;
out.rng_ref = rng_ref;
out.rng_res = rng_res;
out.v0 = st.pars_LD2.v;
out.m0 = st.pars_LD2.m;
out.temp = st.fl.temp;
end
