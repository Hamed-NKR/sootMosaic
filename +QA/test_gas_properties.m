function report = test_gas_properties(repoRoot)
% "TEST_GAS_PROPERTIES" checks the gas properties of TRANSP.FLPROPS, the...
%     ...property model passed by TRANSP.INIT_DOM, the fluid checks of the...
%     ...LD1 and LD2 config loaders and the model profile of LD2 resumes.
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
% Reference values are the mean free path of 67.3 nm and viscosity of...
%     ...1.83e-5 Pa.s at 296.15 K and 101325 Pa, 498.0 nm at 1700 K and...
%     ...101325 Pa, 538.4 nm at 1830 K and 101325 Pa, 545.5 nm at 1830 K...
%     ...and 1e5 Pa (all within 0.5 percent) and 531 nm at 1830 K and...
%     ...101325 Pa (within 2 percent). A failed case stops with the...
%     ...identifier sootMosaic:QA:GasPropertiesFailed.
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

names = {};
pass = [];
atm = 101325;
sut = struct('amb', 'sutherland');

% hand calculated values at 101325 Pa (mu in Pa.s, lambda in m)
ref_mu_298 = 1.836437388e-5;
ref_mu_1700 = 5.644640720e-5;
ref_lam_298 = 67.834769e-9;
ref_lam_1700 = 497.999444e-9;

% gas properties from temperature and pressure
[mu, lam] = props(296.15, atm, sut);
[names, pass] = add(names, pass, 'mean free path 67.3 nm at 296.15 K', ...
    near(lam, 67.3e-9, 0.005));
[names, pass] = add(names, pass, 'viscosity 1.83e-5 Pa.s at 296.15 K', ...
    near(mu, 1.83e-5, 0.005));
[~, lam] = props(1700, atm, sut);
[names, pass] = add(names, pass, 'mean free path 498.0 nm at 1700 K', ...
    near(lam, 498.0e-9, 0.005));
[~, lam_1830] = props(1830, atm, sut);
[names, pass] = add(names, pass, ...
    'mean free path 538.4 nm at 1830 K and 101325 Pa', ...
    near(lam_1830, 538.4e-9, 0.005));
[~, lam] = props(1830, 1e5, sut);
[names, pass] = add(names, pass, ...
    'mean free path 545.5 nm at 1830 K and 1e5 Pa', ...
    near(lam, 545.5e-9, 0.005));
[names, pass] = add(names, pass, ...
    'mean free path 531 nm at 1830 K within 2 percent', ...
    near(lam_1830, 531e-9, 0.02));
[~, lam_1] = props(1700, atm, sut);
[~, lam_2] = props(1700, 2 * atm, sut);
[names, pass] = add(names, pass, 'mean free path halves at 2 atm', ...
    abs(lam_2 / lam_1 - 0.5) < 1e-14);

% independent expectations at 298 K and 1700 K (relative tolerance 1e-6)
[mu_298, lam_298] = props(298, atm, sut);
[mu_1700, lam_1700] = props(1700, atm, sut);
[names, pass] = add(names, pass, 'viscosity 1.836437388e-5 Pa.s at 298 K', ...
    near(mu_298, ref_mu_298, 1e-6));
[names, pass] = add(names, pass, 'viscosity 5.644640720e-5 Pa.s at 1700 K', ...
    near(mu_1700, ref_mu_1700, 1e-6));
[names, pass] = add(names, pass, 'mean free path 67.834769 nm at 298 K', ...
    near(lam_298, ref_lam_298, 1e-6));
[names, pass] = add(names, pass, ...
    'mean free path 497.999444 nm at 1700 K', near(lam_1700, ref_lam_1700, 1e-6));
[mu_2, lam_2] = props(1700, 2 * atm, sut);
[names, pass] = add(names, pass, ...
    'doubling the pressure keeps the viscosity and halves the mean free path', ...
    mu_2 == mu_1700 && near(lam_2, ref_lam_1700 / 2, 1e-6));

% presets of the article1_7658971 profile
preset_ids = {'sootMosaic:FLPROPS:PresetTemperature', ...
    'sootMosaic:FLPROPS:PresetPressure'};
flame = struct('amb', 'flame');
room = struct('amb', 'room');
fl = struct('temp', 1700, 'p', atm);
[mu, lam] = quiet(@() TRANSP.FLPROPS(fl, [], flame));
[names, pass] = add(names, pass, 'flame preset values', ...
    isequal(mu, 5.647e-5) && isequal(lam, 4.98e-7));
[mu, lam] = quiet(@() TRANSP.FLPROPS(fl, []));
[names, pass] = add(names, pass, 'flame preset is the default', ...
    isequal(mu, 5.647e-5) && isequal(lam, 4.98e-7));
[names, pass] = add(names, pass, ...
    'flame preset at 1700 K and 101325 Pa is silent', ...
    no_warning(@() TRANSP.FLPROPS(fl, [], flame), preset_ids));
fl = struct('temp', 293.15, 'p', atm);
[mu, lam] = quiet(@() TRANSP.FLPROPS(fl, [], room));
[names, pass] = add(names, pass, 'room preset values', ...
    isequal(mu, 1.813e-5) && isequal(lam, 6.8e-8));
[names, pass] = add(names, pass, ...
    'room preset at 293.15 K and 101325 Pa is silent', ...
    no_warning(@() TRANSP.FLPROPS(fl, [], room), preset_ids));
fl = struct('temp', 1500, 'p', atm);
[names, pass] = add(names, pass, 'flame preset at 1500 K warns', ...
    raises_warning(@() TRANSP.FLPROPS(fl, [], flame), preset_ids{1}));
fl = struct('temp', 1700, 'p', 1e5);
[names, pass] = add(names, pass, 'flame preset at 1e5 Pa warns', ...
    raises_warning(@() TRANSP.FLPROPS(fl, [], flame), preset_ids{2}));
fl = struct('temp', 298, 'p', atm);
[names, pass] = add(names, pass, 'room preset at 298 K warns', ...
    raises_warning(@() TRANSP.FLPROPS(fl, [], room), preset_ids{1}));

% invalid fluid states and model names
bad = {struct('temp', 0, 'p', atm), struct('temp', -5, 'p', atm), ...
    struct('temp', NaN, 'p', atm), struct('temp', 298, 'p', 0), ...
    struct('temp', 298, 'p', -1), struct('temp', 298, 'p', Inf), ...
    struct('temp', 298)};
bad_id = [repmat({'sootMosaic:FLPROPS:InvalidTemperature'}, 1, 3), ...
    repmat({'sootMosaic:FLPROPS:InvalidPressure'}, 1, 4)];
ok = true;
for i = 1 : numel(bad)
    ok = ok && raises_error(@() TRANSP.FLPROPS(bad{i}, [], sut), bad_id{i});
end
[names, pass] = add(names, pass, ...
    'nonpositive or undefined T and p rejected', ok);
[names, pass] = add(names, pass, 'unknown property model rejected', ...
    raises_error(@() TRANSP.FLPROPS(struct('temp', 298, 'p', atm), [], ...
    struct('amb', 'air')), 'sootMosaic:FLPROPS:UnknownModel'));

% property model passed through INIT_DOM
[params_ud, params_const] = UTILS.LD1_PARAMS_FROM_CONFIG( ...
    struct('volume_fraction', 1e-4, 'size', [1, 1, 1] * 1e-6), ...
    struct('n_par', 10, 'n_pp_mean', 1, 'n_pp_std', 0, ...
    'd_pp_gm', 15e-9, 'd_pp_gsd_between_aggregates', 1, ...
    'd_pp_gsd_within_aggregates', 0), ...
    struct('temperature', 298, 'velocity', [0, 0, 0], 'pressure', atm));
[~, fl] = TRANSP.INIT_DOM(params_ud, params_const, sut);
[names, pass] = add(names, pass, 'INIT_DOM passes the property model', ...
    near(fl.mu, ref_mu_298, 1e-6) && near(fl.lambda, ref_lam_298, 1e-6) && ...
    fl.temp == 298 && fl.p == atm);
[~, fl] = quiet(@() TRANSP.INIT_DOM(params_ud, params_const));
[names, pass] = add(names, pass, ...
    'INIT_DOM without options uses the flame preset', ...
    isequal([fl.mu, fl.lambda], [5.647e-5, 4.98e-7]));

% model profiles
m1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
m2 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
m3 = UTILS.MODEL_PROFILE('current', 'LD2');
[names, pass] = add(names, pass, 'profile defaults', ...
    strcmp(m1.fluid_properties, 'flame') && ...
    strcmp(m2.fluid_properties, 'room') && ...
    strcmp(m3.fluid_properties, 'sutherland'));
[names, pass] = add(names, pass, 'unknown profile rejected', ...
    raises_error(@() UTILS.MODEL_PROFILE('article2', 'LD1'), ...
    'sootMosaic:MODEL_PROFILE:UnknownProfile'));

% LD1 config loader
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, 's'));
ld1 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld1', ...
    'main_ld1_config.example.json')));
f1 = @(c) UTILS.LOAD_MAIN_LD1_CONFIG(write_config(tmp, c));
cfg = f1(ld1);
[names, pass] = add(names, pass, ...
    'LD1 example uses the current profile at 101325 Pa', ...
    strcmp(cfg.model.profile, 'current') && ...
    strcmp(cfg.model.fluid_properties, 'sutherland') && ...
    cfg.transport.fluid.pressure == atm);
c = ld1;
c.transport.fluid.temperature = 0;
ok = raises_error(@() f1(c), ...
    'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidPositiveScalar');
c = ld1;
c.transport.fluid.pressure = -1;
ok = ok && raises_error(@() f1(c), ...
    'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidPositiveScalar');
[names, pass] = add(names, pass, ...
    'LD1 loader rejects nonpositive T and p', ok);
c = ld1;
c.transport.fluid_options.amb = 'air';
ok = raises_error(@() f1(c), 'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidChoice');
c = ld1;
c.transport.mobility_options.mtd = 'kinetic';
ok = ok && raises_error(@() f1(c), ...
    'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidChoice');
c = ld1;
c.model_profile = 'article2';
ok = ok && raises_error(@() f1(c), 'sootMosaic:MODEL_PROFILE:UnknownProfile');
[names, pass] = add(names, pass, ...
    'LD1 loader rejects unknown model names', ok);
c = rmfield(ld1, 'model_profile');
c.transport.fluid_options = rmfield(c.transport.fluid_options, 'amb');
ok = raises_warning(@() f1(c), ...
    'sootMosaic:LOAD_MAIN_LD1_CONFIG:NoModelProfile');
cfg = quiet(@() f1(c));
[names, pass] = add(names, pass, ...
    'LD1 config without profile runs article1_7658971', ...
    ok && strcmp(cfg.model.profile, 'article1_7658971') && ...
    strcmp(cfg.transport.fluid_options.amb, 'flame'));

% LD2 config loader
ld2 = jsondecode(fileread(fullfile(repoRoot, 'config', 'main_ld2', ...
    'main_ld2_from_main_scatter_config.example.json')));
f2 = @(c) UTILS.LOAD_MAIN_LD2_CONFIG(write_config(tmp, c));
cfg = f2(ld2);
[names, pass] = add(names, pass, ...
    'LD2 example uses the current profile at 101325 Pa', ...
    strcmp(cfg.model.profile, 'current') && ...
    strcmp(cfg.model.fluid_properties, 'sutherland') && ...
    cfg.transport.fluid.pressure == atm);
c = ld2;
c.transport.fluid.temperature = 0;
ok = raises_error(@() f2(c), ...
    'sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidPositiveScalar');
c = ld2;
c.transport.fluid.temperature = -298;
ok = ok && raises_error(@() f2(c), ...
    'sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidPositiveScalar');
c = ld2;
c.transport.fluid.pressure = 0;
ok = ok && raises_error(@() f2(c), ...
    'sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidPositiveScalar');
[names, pass] = add(names, pass, ...
    'LD2 loader rejects nonpositive T and p', ok);
c = ld2;
c.transport.fluid_options.amb = 'air';
ok = raises_error(@() f2(c), 'sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidChoice');
c = ld2;
c.transport.mobility_options.mtd = 'kinetic';
ok = ok && raises_error(@() f2(c), ...
    'sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidChoice');
[names, pass] = add(names, pass, ...
    'LD2 loader rejects unknown model names', ok);
c = ld2;
c.transport.fluid = rmfield(c.transport.fluid, 'pressure');
[names, pass] = add(names, pass, ...
    'LD2 config with profile and no pressure rejected', ...
    raises_error(@() f2(c), 'sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingScalar'));
c = rmfield(c, 'model_profile');
c.transport.fluid_options.amb = 'room';
ok = raises_warning(@() f2(c), ...
    'sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingPressure') && ...
    raises_warning(@() f2(c), 'sootMosaic:LOAD_MAIN_LD2_CONFIG:NoModelProfile');
cfg = quiet(@() f2(c));
[~, ~, fl] = UTILS.LD2_PARAMS_FROM_CONFIG(cfg.transport.domain, ...
    cfg.transport.fluid);
[names, pass] = add(names, pass, ...
    'LD2 config without profile and pressure runs at 101325 Pa', ...
    ok && cfg.transport.fluid.pressure == atm && fl.p == atm && ...
    strcmp(cfg.model.profile, 'article1_7658971') && ...
    strcmp(cfg.model.fluid_properties, 'room'));

% resume of LD2 checkpoints with and without model options
[sv, out, ok] = resume_checkpoint(fullfile(tmp, 'r1'), false);
fl_exp = sv.fl;
fl_exp.p = atm;
[names, pass] = add(names, pass, ...
    'resume without model options runs article1_7658971', ...
    ok && isequal(out.cfg_ld2.model, ...
    UTILS.MODEL_PROFILE('article1_7658971', 'LD2')) && ...
    strcmp(out.cfg_ld2.model.fluid_properties, 'room') && ...
    isequal(out.fl, fl_exp) && isequal(out.opts_fl, sv.opts_fl) && ...
    isequal([out.fl.mu, out.fl.lambda], [1.813e-5, 6.8e-8]));
[sv, out, ok] = resume_checkpoint(fullfile(tmp, 'r2'), true);
[names, pass] = add(names, pass, 'resume keeps saved model options', ...
    ok && isequal(out.cfg_ld2.model, sv.cfg_ld2.model) && ...
    isequal(out.fl, sv.fl) && isequal(out.opts_fl, sv.opts_fl) && ...
    out.fl.p == 1e5 && strcmp(out.cfg_ld2.model.fluid_properties, ...
    out.opts_fl.amb));

% properties of the LD1 example config reach the fluid structure
cfg = f1(ld1);
part = cfg.transport.particles;
part.n_par = 10;
[p_ud, p_const] = UTILS.LD1_PARAMS_FROM_CONFIG(cfg.transport.domain, ...
    part, cfg.transport.fluid);
[~, fl] = TRANSP.INIT_DOM(p_ud, p_const, cfg.transport.fluid_options);
[names, pass] = add(names, pass, ...
    'LD1 example config gives the 1700 K properties', ...
    near(fl.mu, ref_mu_1700, 1e-6) && near(fl.lambda, ref_lam_1700, 1e-6) && ...
    fl.temp == 1700 && fl.p == atm);

% LD1 passes the configured model to INIT_DOM and saves fl0
txt = fileread(fullfile(repoRoot, 'main_LD1_v3.m'));
init = regexp(txt, ['TRANSP\.INIT_DOM\(\s*params0_ud\s*,\s*', ...
    'params0_const\s*,\s*opts0_fl\s*\)'], 'start');
direct = regexp(txt, 'TRANSP\.FLPROPS\(', 'start');
saved = regexp(txt, 'save\(metadata\.output_file[^)]*''fl0''', 'start');
[names, pass] = add(names, pass, ...
    'LD1 sets properties in INIT_DOM and saves fl0', ...
    isscalar(init) && isempty(direct) && isscalar(saved));

clear cleanup
report = struct('name', names, 'pass', num2cell(pass));
for i = 1 : numel(pass)
    if pass(i)
        fprintf('PASS %s\n', names{i});
    else
        fprintf('FAIL %s\n', names{i});
    end
end
if ~all(pass)
    error('sootMosaic:QA:GasPropertiesFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass))
end

end

function [names, pass] = add(names, pass, name, ok)
names{end + 1, 1} = name;
pass(end + 1, 1) = logical(ok);
end

function [mu, lam] = props(temp, p, opts)
[mu, lam] = TRANSP.FLPROPS(struct('temp', temp, 'p', p), [], opts);
end

function ok = near(val, ref, tol)
ok = abs(val / ref - 1) <= tol;
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

function [sv, out, ok] = resume_checkpoint(folder, with_model)
% Writing a checkpoint at its last iteration, so the resume saves the...
    % ...final workspace without marching. With model options the fluid...
    % ...holds the sutherland properties at 298 K and 1e5 Pa, without...
    % ...them the room preset values and no pressure.
mkdir(folder);
k = 3; %#ok<NASGU>
k_max = 3; %#ok<NASGU>
ind_dat = 2; %#ok<NASGU>
n_dat = 1; %#ok<NASGU>
pars_LD2 = struct('n', [1; 1]); %#ok<NASGU>
params_domain = table((1 : 4)', 'VariableNames', {'Value'}); %#ok<NASGU>
opts_grow = struct(); %#ok<NASGU>
parsdata = struct('dm', {1}); %#ok<NASGU>
z1 = zeros(3, 1);
z2 = zeros(3, 2);
ensdata = struct('t', z1, 'n_agg', z1, 'tau', z2, 'kn_kin', z2, ...
    'kn_diff', z2, 'dpp', z2, 'sigmapp', z2, 'da', z2, 'dm', z2); %#ok<NASGU>
dir_wsp = folder; %#ok<NASGU>
cfg_results = struct('final_prefix', 'final'); %#ok<NASGU>
rng_state = rng; %#ok<NASGU>
cfg_ld2 = struct('config_file', 'checkpoint');
if with_model
    opts_fl = struct('amb', 'sutherland');
    [mu, lam] = props(298, 1e5, opts_fl);
    fl = struct('size', [1; 1; 1], 'temp', 298, 'p', 1e5, 'mu', mu, ...
        'lambda', lam);
    cfg_ld2.model = UTILS.MODEL_PROFILE('current', 'LD2');
else
    opts_fl = struct('amb', 'room');
    fl = struct('size', [1; 1; 1], 'temp', 298, 'mu', 1.813e-5, ...
        'lambda', 6.8e-8);
end
sv = struct('cfg_ld2', cfg_ld2, 'fl', fl, 'opts_fl', opts_fl);
save(fullfile(folder, 'checkpoint.mat'), '-v7.3')
resume = @() UTILS.RESUME_LD2_V3(folder, 'checkpoint.mat');
if with_model
    ok = no_warning(resume, {'sootMosaic:ResumeLD2:NoModelProfile'});
else
    ok = raises_warning(resume, 'sootMosaic:ResumeLD2:NoModelProfile');
    evalc('resume();');
end
final = dir(fullfile(folder, 'final__*.mat'));
out = load(fullfile(folder, final(end).name), 'cfg_ld2', 'fl', 'opts_fl');
end
