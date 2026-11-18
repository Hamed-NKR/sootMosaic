function report = TEST_MODEL_PROFILE(repoRoot)
% "TEST_MODEL_PROFILE" checks profile files, overrides and loader records.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     repoRoot: Source root, default the folder above +QA
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Fixtures use tempname and are...
%         ...removed on exit. Failures use sootMosaic:QA:ModelProfileFailed
% ----------------------------------------------------------------------- %

if nargin < 1, repoRoot = fileparts(fileparts(mfilename('fullpath'))); end
folder = tempname;
mkdir(folder);
saved_path = path;
saved_dir = pwd;
saved_warning = warning;
[message, id] = lastwarn;
cleanup = onCleanup(@() restore(folder, saved_dir, saved_path, ...
    saved_warning, message, id));
mkdir(fullfile(folder, 'config'));
copyfile(fullfile(repoRoot, '+UTILS'), fullfile(folder, '+UTILS'));
copyfile(fullfile(repoRoot, 'config', 'profiles'), ...
    fullfile(folder, 'config', 'profiles'));
addpath(repoRoot);
addpath(folder, '-begin');
cd(folder);
clear UTILS.MODEL_PROFILE UTILS.MODEL_DEFAULTS
clear UTILS.LOAD_MAIN_LD1_CONFIG UTILS.LOAD_MAIN_LD2_CONFIG
clear UTILS.RESUME_LD2_V3
warning('on', 'sootMosaic:MODEL_PROFILE:BuiltInProfile');
warning('on', 'sootMosaic:MODEL_PROFILE:ProfileDiffersFromBuiltIn');
warning('off', 'sootMosaic:LOAD_MAIN_LD1_CONFIG:NoModelProfile');
warning('off', 'sootMosaic:LOAD_MAIN_LD2_CONFIG:NoModelProfile');
names = {};
pass = [];
profiles = {'current', 'article1_7658971'};
stages = {'LD1', 'LD2'};
dict = fullfile(folder, 'config', 'profiles', 'profile.keys.json');
strict = struct('Strict', true);
for i = 1:2
    name = profiles{i};
    file = fullfile(folder, 'config', 'profiles', [name '.json']);
    raw = UTILS.CONFIG_READ(file, dict, strict);
    raw = rmfield(raw, {'si', 'provenance'});
    check(['complete mirror ' name], isequal(raw, UTILS.MODEL_DEFAULTS(name)));
    for j = 1:2
        [model, known, params, source] = ...
            UTILS.MODEL_PROFILE(name, stages{j}, struct(), strict);
        [expected, expected_known] = literal_model(name, stages{j});
        check(['literal interface ' name ' ' stages{j}], ...
            isequal(model, expected) && isequal(known, expected_known) && ...
            isequal(fieldnames(model), fieldnames(expected)) && ...
            isequal(fieldnames(known), fieldnames(expected_known)));
        [~, ~, builtin] = UTILS.MODEL_PROFILE(name, stages{j}, struct(), ...
            struct('BuiltinOnly', true));
        check(['stage mirror ' name ' ' stages{j}], ...
            isequal(params, builtin) && source.matches_builtin && ...
            ~source.builtin && isequal(params.projection.tol, model.proj_tol));
        check(['source digest ' name ' ' stages{j}], ...
            strcmp(source.file, file) && isscalar(source.files) && ...
            (~usejava('jvm') || strcmp(source.sha256, UTILS.FILE_SHA256(file))));
    end
end
[~, ~, p] = UTILS.MODEL_PROFILE('current', 'INV', struct(), strict);
[~, ~, b] = UTILS.MODEL_PROFILE('current', 'INV', struct(), ...
    struct('BuiltinOnly', true));
check('current INV mirror and SI values', isequal(p, b) && ...
    p.si.reference.dpp100_nm == 17.8 * 1e-9 && ...
    p.si.reference.m100_fg == 0.267 * 1e-18 && ...
    p.reference.mass_mobility_exponent == 2.48 && ...
    p.si.reference.mass_mobility_exponent == 2.48 && ...
    ~isfield(p.reference, 'd_m'));
check('fixed INV refused', fails(@() UTILS.MODEL_PROFILE( ...
    'article1_7658971', 'INV'), 'sootMosaic:MODEL_PROFILE:UnknownStage'));
check('unknown name and stage refused', ...
    fails(@() UTILS.MODEL_PROFILE('missing', 'LD1'), ...
    'sootMosaic:MODEL_PROFILE:UnknownProfile') && ...
    fails(@() UTILS.MODEL_PROFILE('current', 'LD3'), ...
    'sootMosaic:MODEL_PROFILE:UnknownStage'));
for i = 1:2
    name = profiles{i};
    file = fullfile(folder, 'config', 'profiles', [name '.json']);
    [m, k, p] = UTILS.MODEL_PROFILE(name, 'LD1', struct(), strict);
    movefile(file, [file '.away']);
    lastwarn('');
    [bm, bk, bp, bs] = UTILS.MODEL_PROFILE(name, 'LD1', struct(), strict);
    [~, first] = lastwarn;
    lastwarn('');
    UTILS.MODEL_PROFILE(name, 'LD2', struct(), strict);
    [~, second] = lastwarn;
    check(['missing file once ' name], isequal(m, bm) && ...
        isequal(k, bk) && isequal(p, bp) && bs.builtin && ...
        isempty(bs.file) && isempty(bs.sha256) && ...
        strcmp(first, 'sootMosaic:MODEL_PROFILE:BuiltInProfile') && ...
        isempty(second));
    movefile([file '.away'], file);
end

% Checking the shared warning state when only the dictionary is absent
for i = 1:2
    name = profiles{i};
    [ok, detail] = missing_dictionary(folder, name, strict);
    check(['missing dictionary once ' name], ok, detail);
end

% Checking dimensionless aliases in files, stages and direct overrides
warning('on', 'sootMosaic:CONFIG_READ:Alias');
warning('on', 'sootMosaic:MODEL_PROFILE:Alias');
for i = 1:2
    name = profiles{i};
    file = fullfile(folder, 'config', 'profiles', [name '.json']);
    original = fileread(file);
    write_text(file, strrep(original, '"mass_mobility_exponent"', '"d_m"'));
    lastwarn('');
    [~, ~, p, s] = UTILS.MODEL_PROFILE(name, 'LD1', struct(), strict);
    [~, id] = lastwarn;
    check(['reference alias ' name], ...
        strcmp(id, 'sootMosaic:CONFIG_READ:Alias') && s.matches_builtin && ...
        p.reference.mass_mobility_exponent == 2.48 && ...
        p.si.reference.mass_mobility_exponent == 2.48 && ...
        ~isfield(p.reference, 'd_m'));
    write_text(file, original);
end
alias_file = fullfile(folder, 'config', 'profiles', 'alias_variant.json');
for stage = {'LD1', 'LD2', 'INV'}
    value = struct('extends', 'current.json', 'profile', 'alias_variant');
    value.stages.(stage{1}).reference.d_m = 2.6;
    write_json(alias_file, value);
    [~, ~, p] = UTILS.MODEL_PROFILE('alias_variant', stage{1}, struct(), strict);
    check(['stage reference alias ' stage{1}], ...
        p.reference.mass_mobility_exponent == 2.6 && ...
        p.si.reference.mass_mobility_exponent == 2.6 && ...
        ~isfield(p.reference, 'd_m'));
end
for missing = [false true]
    if missing, movefile(dict, [dict '.away']); end
    override = struct('reference', struct('d_m', 2.6));
    [~, ~, p, s] = UTILS.MODEL_PROFILE('current', 'LD1', override, strict);
    override.reference.mass_mobility_exponent = 2.7;
    [~, ~, canonical] = UTILS.MODEL_PROFILE('current', 'LD1', override, strict);
    check(['override reference alias ' num2str(missing)], ...
        p.reference.mass_mobility_exponent == 2.6 && ...
        p.si.reference.mass_mobility_exponent == 2.6 && ...
        ~isfield(p.reference, 'd_m') && ...
        any(strcmp({s.overrides.path}, 'reference.mass_mobility_exponent')) && ...
        canonical.reference.mass_mobility_exponent == 2.7 && ...
        ~isfield(canonical.reference, 'd_m'));
    if missing, movefile([dict '.away'], dict); end
end
file = fullfile(folder, 'config', 'profiles', 'current.json');
original = fileread(file);
edited = jsondecode(original);
edited.step.step_frac = 0.25;
write_json(file, edited);
lastwarn('');
[~, ~, p, s] = UTILS.MODEL_PROFILE('current', 'LD1', struct(), strict);
[~, id] = lastwarn;
check('edited current warns and records', ...
    strcmp(id, 'sootMosaic:MODEL_PROFILE:ProfileDiffersFromBuiltIn') && ...
    p.step.step_frac == 0.25 && ~s.matches_builtin && ~s.builtin && ...
    (~usejava('jvm') || strcmp(s.sha256, UTILS.FILE_SHA256(file))));
edited.step.step_frac = 'bad';
write_json(file, edited);
check('profile dictionary rejects wrong type', fails(@() ...
    UTILS.MODEL_PROFILE('current', 'LD1', struct(), strict), ...
    'sootMosaic:CONFIG_READ:InvalidType'));
edited = jsondecode(original);
edited.step.typo = 1;
write_json(file, edited);
check('strict reader rejects unknown profile key', fails(@() ...
    UTILS.MODEL_PROFILE('current', 'LD1', struct(), strict), ...
    'sootMosaic:CONFIG_READ:UnknownKey'));
write_text(file, original);
fixed_file = fullfile(folder, 'config', 'profiles', 'article1_7658971.json');
fixed_text = fileread(fixed_file);
custom_file = fullfile(folder, 'config', 'profiles', 'variant.json');
write_json(custom_file, struct('extends', 'article1_7658971.json', ...
    'profile', 'variant', 'description', 'Variant choices', ...
    'stages', struct('LD2', struct('step', struct('step_frac', 0.2)))));
[model, ~, p, s] = UTILS.MODEL_PROFILE('variant', 'LD2', ...
    struct('step', struct('step_policy', 'cap')), strict);
check('custom extends and override records', ...
    strcmp(model.profile, 'variant') && strcmp(model.fluid_properties, 'room') ...
    && p.step.step_frac == 0.2 && strcmp(p.step.step_policy, 'cap') && ...
    numel(s.files) == 2 && ~s.builtin && ~s.matches_builtin && ...
    any(strcmp({s.overrides.path}, 'step.step_policy')));
write_text(fixed_file, strrep(fixed_text, ...
    '"step_frac": 0.5', '"step_frac": 0.25'));
check('edited fixed profile stops', fails(@() ...
    UTILS.MODEL_PROFILE('article1_7658971', 'LD1', struct(), strict), ...
    'sootMosaic:MODEL_PROFILE:EditedLegacyProfile'));
check('edited fixed parent stops', fails(@() ...
    UTILS.MODEL_PROFILE('variant', 'LD2', struct(), strict), ...
    'sootMosaic:MODEL_PROFILE:EditedLegacyProfile'));
check('resume parameter fallback uses mirror', resume_record(folder));
write_text(fixed_file, fixed_text);
[~, ~, p] = UTILS.MODEL_PROFILE('article1_7658971', 'LD1', ...
    struct('slip', struct('model', 'kim2005')), strict);
check('slip override resolves conditional values', ...
    p.resolved.rho_aero_ref_kg_m3 == 1000 && ...
    strcmp(p.resolved.root_tolerance, 'eps_scaled'));
[~, ~, p] = UTILS.MODEL_PROFILE('article1_7658971', 'LD1', ...
    struct('mobility', struct('root_solve', 'bracketed')), strict);
check('bracketed fixed slip uses scaled tolerance', ...
    p.resolved.rho_aero_ref_kg_m3 == 1860 && ...
    strcmp(p.resolved.root_tolerance, 'eps_scaled'));
check('invalid direct override stops', fails(@() ...
    UTILS.MODEL_PROFILE('current', 'LD1', ...
    struct('projection', struct('points', 2.5)), strict), ...
    'sootMosaic:MODEL_PROFILE:InvalidOverride'));
check('unknown direct override stops in strict mode', fails(@() ...
    UTILS.MODEL_PROFILE('current', 'LD1', ...
    struct('step', struct('typo', 1)), strict), ...
    'sootMosaic:MODEL_PROFILE:UnknownKey'));
override = struct('step', struct('step_frac', 0.2), ...
    'projection', struct('tol', []));
[m, k, p] = UTILS.MODEL_PROFILE('current', 'LD1', override, strict);
hide_profiles(folder, true);
movefile(dict, [dict '.away']);
[bm, bk, bp, bs] = UTILS.MODEL_PROFILE('current', 'LD1', override, strict);
check('mirror overrides without profile files or dictionary', ...
    isequal(m, bm) && isequal(k, bk) && isequal(p, bp) && bs.builtin);
movefile([dict '.away'], dict);
hide_profiles(folder, false);

% Checking both loaders on isolated task fixtures
examples = {fullfile('main_ld1', 'main_ld1_config.example.json'), ...
    fullfile('main_ld2', 'main_ld2_from_main_scale_config.example.json'), ...
    fullfile('main_ld2', 'main_ld2_from_main_scatter_config.example.json')};
for i = 1:numel(examples)
    raw = jsondecode(fileread(fullfile(repoRoot, 'config', examples{i})));
    if i == 1
        loader = @(file) UTILS.LOAD_MAIN_LD1_CONFIG(file, strict);
    else
        loader = @(file) UTILS.LOAD_MAIN_LD2_CONFIG(file, strict);
    end
    fixture = fullfile(folder, 'task.json');
    write_json(fixture, raw);
    present = loader(fixture);
    hide_profiles(folder, true);
    absent = loader(fixture);
    hide_profiles(folder, false);
    check(['loader mirror identity ' examples{i}], ...
        isequal(without_source(present), without_source(absent)));
    raw.model_profile = 'article1_7658971';
    raw.transport.fluid_options = struct();
    raw.transport.mobility_options = struct('c_dt', 1, 'mtd', 'continuum', ...
        'slip', 'kim2005');
    raw.model_overrides = struct('step', struct('step_frac', 0.2, ...
        'step_policy', 'cap'), 'mobility', struct('method', 'free_molecular'));
    write_json(fixture, raw);
    cfg = loader(fixture);
    check(['explicit continuum and conditional records ' examples{i}], ...
        strcmp(cfg.transport.mobility_options.mtd, 'continuum') && ...
        strcmp(cfg.model.mobility, 'sorensen_eq17') && ...
        cfg.transport.mobility_options.step_frac == 0.2 && ...
        strcmp(cfg.transport.mobility_options.step_policy, 'cap') && ...
        cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1000 && ...
        strcmp(cfg.model_params.resolved.root_tolerance, 'eps_scaled') && ...
        any(strcmp({cfg.model_source.overrides.path}, 'mobility.method')) && ...
        any(strcmp({cfg.model_source.overrides.source}, fixture)));
    raw.transport.mobility_options.slip = 'per_caller_7658971';
    raw.transport.mobility_options.root_solve = 'bracketed';
    raw.transport.mobility_options.step_frac = 0.1;
    raw.transport.mobility_options.step_policy = 'warn';
    write_json(fixture, raw);
    cfg = loader(fixture);
    check(['explicit step and bracketed precedence ' examples{i}], ...
        cfg.model_params.step.step_frac == 0.1 && ...
        strcmp(cfg.model_params.step.step_policy, 'warn') && ...
        strcmp(cfg.model_params.resolved.root_tolerance, 'eps_scaled'));
    raw = rmfield(raw, {'model_profile', 'model_overrides'});
    raw.transport.mobility_options = struct('c_dt', 1);
    write_json(fixture, raw);
    a = loader(fixture);
    hide_profiles(folder, true);
    b = loader(fixture);
    hide_profiles(folder, false);
    check(['profile-free loader identity ' examples{i}], ...
        isequal(without_source(a), without_source(b)) && ...
        strcmp(a.model.profile, 'article1_7658971') && ...
        a.model_params.step.step_frac == 0.5);
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));

    function check(name, ok, detail)
        if nargin < 3, detail = ''; end
        names{end + 1} = name;
        pass(end + 1) = ok;
        if ~ok
            error('sootMosaic:QA:ModelProfileFailed', '%s%s', name, detail);
        end
    end
end

function [ok, detail] = missing_dictionary(folder, name, strict)
% "missing_dictionary" checks mirror values and the shared warning count.
% Resetting the once-per-profile warning flags at the start of each case
clear(which('UTILS.MODEL_PROFILE'))
dict = fullfile(folder, 'config', 'profiles', 'profile.keys.json');
file = fullfile(folder, 'config', 'profiles', [name '.json']);
override = struct('reference', struct('mass_mobility_exponent', 2.6));
[m, k, p] = UTILS.MODEL_PROFILE(name, 'LD1', override, strict);
movefile(dict, [dict '.away']);
% Reading the warning identifier right after each call, since batch runs
% do not route warnings through evalc
fallback = 'sootMosaic:MODEL_PROFILE:BuiltInProfile';
lastwarn('', '');
[bm, bk, bp, bs] = UTILS.MODEL_PROFILE(name, 'LD1', override, strict);
[~, first] = lastwarn;
lastwarn('', '');
UTILS.MODEL_PROFILE(name, 'LD2', struct(), strict);
[~, second] = lastwarn;
movefile([dict '.away'], dict);
movefile(file, [file '.away']);
lastwarn('', '');
UTILS.MODEL_PROFILE(name, 'LD1', struct(), strict);
[~, third] = lastwarn;
movefile([file '.away'], file);
counts = [strcmp(first, fallback), strcmp(second, fallback), ...
    strcmp(third, fallback)];
labels = {'model equality', 'known equality', 'params equality', ...
    'source.builtin', 'source.matches_builtin', 'empty source.file', ...
    'empty source.sha256', 'empty source.files', 'empty source.dictionary', ...
    'first fallback warning count = 1', 'LD2 fallback warning count = 0', ...
    'missing-file fallback warning count = 0'};
results = [isequal(m, bm), isequal(k, bk), isequal(p, bp), bs.builtin, ...
    bs.matches_builtin, isempty(bs.file), isempty(bs.sha256), ...
    isempty(bs.files), isempty(bs.dictionary), counts == [1 0 0]];
ok = all(results);
detail = '';
if ~ok
    detail = sprintf(['\nFailed conditions: %s\n', ...
        'Fallback warning counts [first LD2 missing-file]: [%d %d %d]\n', ...
        'Last warning identifiers: %s, %s, %s'], ...
        strjoin(labels(~results), ', '), counts(1), counts(2), counts(3), ...
        first, second, third);
end
end

function [model, known] = literal_model(name, stage)
% "literal_model" supplies independent interface fixtures.
known = struct('fluid_properties', {{'sutherland', 'flame', 'room'}}, ...
    'mobility', {{'sorensen_eq17', 'continuum', 'sorensen_backbone', ...
    'interp', 'free_molecular'}}, ...
    'slip_correction', {{'kim2005', 'per_caller_7658971'}}, ...
    'continuum_diameter', {{'sorensen_backbone', 'fixed_075dg'}}, ...
    'root_solve', {{'bracketed', 'start_point_7658971'}}, ...
    'projection', {{'isotropic', 'euler_7658971'}}, ...
    'initial_velocity', {{'maxwell_boltzmann', 'mean_speed_7658971'}});
if strcmp(name, 'current')
    model = struct('profile', 'current', 'fluid_properties', 'sutherland', ...
        'slip_correction', 'kim2005', 'mobility', 'interp', ...
        'continuum_diameter', 'sorensen_backbone', 'root_solve', 'bracketed', ...
        'projection', 'isotropic', 'proj_cache', true, ...
        'proj_points', 1024, 'proj_orientations', 64, 'proj_replicates', 4, ...
        'proj_tol', 0.01, 'knudsen_diagnostics', true, ...
        'initial_velocity', 'maxwell_boltzmann');
else
    model = struct('profile', 'article1_7658971', 'fluid_properties', 'flame', ...
        'slip_correction', 'per_caller_7658971', 'mobility', 'sorensen_eq17', ...
        'continuum_diameter', 'fixed_075dg', ...
        'root_solve', 'start_point_7658971', ...
        'projection', 'euler_7658971', 'proj_cache', false, ...
        'proj_points', 100, 'proj_orientations', 5, 'proj_replicates', 1, ...
        'proj_tol', Inf, 'knudsen_diagnostics', false, ...
        'initial_velocity', 'mean_speed_7658971');
    if strcmp(stage, 'LD2')
        model.fluid_properties = 'room';
        model.mobility = 'interp';
    end
end
end

function cfg = without_source(cfg)
cfg = rmfield(cfg, 'model_source');
end

function ok = resume_record(folder)
% "resume_record" checks completion of a checkpoint at its final step.
[model, ~] = literal_model('current', 'LD2');
data.cfg_ld2 = struct('model', model);
data.rng_state = rng;
restore_rng = onCleanup(@() rng(data.rng_state));
data.fl = struct('p', 101325);
data.opts_diag = struct('knudsen', false);
data.opts_grow = struct();
data.params_domain = table([0; 1; 1; 1], 'VariableNames', {'Value'});
data.k = 1;
data.k_max = 1;
data.ind_dat = 2;
data.parsdata = struct('dm', 1);
data.ensdata = struct('t', 0, 'n_agg', 1, 'tau', [0, 0], ...
    'kn_kin', [0, 0], 'kn_diff', [0, 0], 'dpp', [0, 0], ...
    'sigmapp', [0, 0], 'da', [0, 0], 'dm', [0, 0]);
data.dir_wsp = folder;
data.cfg_results = struct('final_prefix', 'resolved');
file = fullfile(folder, 'resume.mat');
save(file, '-struct', 'data');
warning('on', 'sootMosaic:RESUME_LD2_V3:NoModelParameters');
output = evalc('UTILS.RESUME_LD2_V3(folder, ''resume.mat'');');
files = dir(fullfile(folder, 'resolved__*.mat'));
out = load(fullfile(folder, files(end).name), 'cfg_ld2');
[~, ~, expected] = UTILS.MODEL_PROFILE('article1_7658971', ...
    'LD2', struct(), struct('BuiltinOnly', true));
ok = contains(output, ['Checkpoint has no parameter record. ', ...
    'The parameter record uses the fixed built-in profile.']) && ...
    isequal(out.cfg_ld2.model_params, expected) && ...
    out.cfg_ld2.model_source.builtin && isequal(out.cfg_ld2.model, model);
end

function hide_profiles(folder, hide)
for name = {'current', 'article1_7658971'}
    file = fullfile(folder, 'config', 'profiles', [name{1} '.json']);
    if hide, movefile(file, [file '.away']); else, movefile([file '.away'], file); end
end
end

function ok = fails(fun, id)
ok = false;
try
    fun();
catch err
    ok = strcmp(err.identifier, id);
end
end

function write_json(file, value)
write_text(file, jsonencode(value));
end

function write_text(file, value)
fid = fopen(file, 'wb');
if fid < 0, error('sootMosaic:QA:ModelProfileFailed', 'Cannot write fixture.'); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, value, 'char');
end

function restore(folder, saved_dir, saved_path, state, message, id)
cd(saved_dir);
path(saved_path);
clear UTILS.MODEL_PROFILE UTILS.MODEL_DEFAULTS
clear UTILS.LOAD_MAIN_LD1_CONFIG UTILS.LOAD_MAIN_LD2_CONFIG
clear UTILS.RESUME_LD2_V3
warning(state);
lastwarn(message, id);
if isfolder(folder), rmdir(folder, 's'); end
end
