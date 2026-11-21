function report = TEST_CONSTANTS()
% "TEST_CONSTANTS" checks profile values and table order independence.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and their logical results
% ----------------------------------------------------------------------- %

saved_rng = rng;
restore_rng = onCleanup(@() rng(saved_rng));
names = {};
pass = [];
[~, ~, fixed] = UTILS.MODEL_PROFILE('article1_7658971', 'LD2');
[~, ~, current] = UTILS.MODEL_PROFILE('current', 'INV');
t = UTILS.CONSTANTS_TABLE(fixed.si.constants);
Name = {'rho_bc'; 'M_air'; 'kb'; 'Na'; 'Ru'};
Value = [1.86e3; 28.97e-3; 1.381e-23; 6.022e23; 8.314];
Unit = {'kg/m3'; 'kg/mol'; 'j/k'; 'mol^-1'; 'j/mol.k'};
Description = {'Black Carbon bulk density'; 'Air molar mass'; ...
    'Boltzmann constant'; 'Avogadro constant'; 'Universal gas constant'};
parent = table(Name, Value, Unit, Description);
plain = t;
plain.Properties.RowNames = {};
[names, pass] = add(names, pass, 'table equals parent except row names', ...
    isequal(plain, parent));
parent.Properties.RowNames = Name;
[names, pass] = add(names, pass, 'named literal table equality', ...
    isequal(t, parent) && isequal(t, UTILS.CONSTANTS_TABLE()));
c = current.si.constants;
[names, pass] = add(names, pass, 'exact SI and charge constants', ...
    c.kb_j_k == 1.380649e-23 && c.na_mol_inv == 6.02214076e23 && ...
    c.ru_j_mol_k == 8.31446261815324 && c.e_c == 1.602176634e-19 && ...
    c.eps0_f_m == 8.8541878128e-12 && ...
    ~isfield(fixed.si.constants, 'e_c') && ...
    ~isfield(fixed.si.constants, 'eps0_f_m'));
domain = struct('volume_fraction', 1e-4, 'size', [1 1 1] * 1e-6);
fluid = struct('temperature', 298, 'pressure', 101325, 'velocity', [0 0 0]);
particles = struct('n_par', 2, 'n_pp_mean', 1, 'n_pp_std', 0, ...
    'd_pp_gm', 30e-9, 'd_pp_gsd_between_aggregates', 1, ...
    'd_pp_gsd_within_aggregates', 0);
[~, a] = UTILS.LD1_PARAMS_FROM_CONFIG(domain, particles, fluid);
[~, b] = UTILS.LD2_PARAMS_FROM_CONFIG(domain, fluid);
[names, pass] = add(names, pass, 'unnamed-profile builders use fixed values', ...
    isequal(a, t) && isequal(b, t));
[~, a] = UTILS.LD1_PARAMS_FROM_CONFIG(domain, particles, fluid, c);
[~, b] = UTILS.LD2_PARAMS_FROM_CONFIG(domain, fluid, c);
[names, pass] = add(names, pass, 'builders use current constants', ...
    isequal(a, UTILS.CONSTANTS_TABLE(c)) && isequal(a, b));
override = c;
override.rho_bc_kg_m3 = 2 * c.rho_bc_kg_m3;
over_table = UTILS.CONSTANTS_TABLE(override);
[names, pass] = add(names, pass, 'material density override', ...
    UTILS.CONSTANT_VALUE(over_table, 'rho_bc') == 2 * c.rho_bc_kg_m3);

% Checking explicit validation density against the profile default
root = fileparts(fileparts(mfilename('fullpath')));
saved_dir = pwd;
restore_dir = onCleanup(@() cd(saved_dir));
cd(root);
[~, text_fixed] = TRANSP.INIT_PARAMS('LD1_Params');
[~, text_current] = TRANSP.INIT_PARAMS('LD1_Params', c);
cd(saved_dir);
[names, pass] = add(names, pass, 'text builder uses supplied constants', ...
    isequal(text_fixed, t) && isequal(text_current, UTILS.CONSTANTS_TABLE(c)));
raw = jsondecode(fileread(fullfile(root, 'config', 'main_valid', ...
    'main_valid_config.example.json')));
folder = tempname(root);
mkdir(folder);
restore_folder = onCleanup(@() rmdir(folder, 's'));
file = fullfile(folder, 'validation.json');
density = 1860; % Explicit material density of the fixture (kg/m3)
raw.physics.material_density_kg_m3 = density;
raw.model_profile = 'current';
raw.model_overrides.constants.rho_bc_kg_m3 = 2 * density;
write_json(file, raw);
cfg = UTILS.LOAD_MAIN_VALID_CONFIG(file);
[names, pass] = add(names, pass, 'explicit validation density wins', ...
    cfg.physics.material_density_kg_m3 == density && ...
    cfg.model_params.si.constants.rho_bc_kg_m3 == density && ...
    ~isempty(cfg.model_source.overrides));
raw.physics = rmfield(raw.physics, 'material_density_kg_m3');
write_json(file, raw);
cfg = UTILS.LOAD_MAIN_VALID_CONFIG(file);
[names, pass] = add(names, pass, 'validation density inherits profile', ...
    cfg.physics.material_density_kg_m3 == 2 * density);
raw = rmfield(raw, {'config_version', 'model_profile', 'model_overrides'});
raw.physics.material_density_kg_m3 = density;
write_json(file, raw);
cfg = UTILS.LOAD_MAIN_VALID_CONFIG(file);
[names, pass] = add(names, pass, 'old validation density is unchanged', ...
    cfg.physics.material_density_kg_m3 == density && ...
    strcmp(cfg.model.profile, 'article1_7658971'));

% Comparing seeded callers for named, Name-column and unnamed tables
pp = {[1 30e-9 0 0 0]; [2 30e-9 1e-6 0 0]};
pars = struct('n', [1; 1], 'pp', {pp});
pars.dg = PAR.GYRATION(pp, pars.n);
pars.dmax = PAR.TERRITORY(pp, pars.n);
pars.r = [0 0 0; 1e-6 0 0];
fl = struct('temp', 298, 'p', 101325, 'mu', 1.813e-5, ...
    'lambda', 6.8e-8, 'size', [4e-6 4e-6 4e-6]);
tables = {t, UTILS.CONSTANTS_TABLE(c)};
methods = {'sorensen_eq17', 'continuum', 'sorensen_backbone', ...
    'interp', 'free_molecular'};
slips = {'per_caller_7658971', 'kim2005'};
for q = 1:numel(tables)
    original = tables{q};
    shuffled = original([5 3 1 4 2], :);
    name_only = shuffled;
    name_only.Properties.RowNames = {};
    unnamed = table(original.Value, 'VariableNames', {'Value'});
    variants = {shuffled, name_only, unnamed};
    for j = 1:numel(variants)
        for k = 1:numel(methods)
            for h = 1:numel(slips)
                opts = struct('mtd', methods{k}, 'slip', slips{h}, ...
                    'c_dt', 1e-3, 'step_policy', 'cap');
                rng(39);
                a = TRANSP.MOBIL(pars, fl, original, opts);
                state_a = rng;
                rng(39);
                b = TRANSP.MOBIL(pars, fl, variants{j}, opts);
                [names, pass] = add(names, pass, 'MOBIL table identity', ...
                    isequal(a, b) && isequal(state_a, rng));
                ka = TRANSP.KNUDSEN(a, fl, original, opts);
                kb = TRANSP.KNUDSEN(b, fl, variants{j}, opts);
                [names, pass] = add(names, pass, 'KNUDSEN table identity', ...
                    isequal(ka, kb));
                a.v = zeros(2, 3);
                b.v = a.v;
                rng(40);
                [ma, ta] = TRANSP.MARCH(a, fl, original);
                state_a = rng;
                rng(40);
                [mb, tb] = TRANSP.MARCH(b, fl, variants{j});
                [names, pass] = add(names, pass, 'MARCH table identity', ...
                    isequal(ma, mb) && isequal(ta, tb) && ...
                    isequal(state_a, rng));
                fprintf('constants %d %s %s %.17g %.17g %.17g\n', ...
                    q, methods{k}, slips{h}, a.m(1), a.f(1), a.diff(1));
            end
        end
        for method = {'mean_speed_7658971', 'maxwell_boltzmann'}
            rng(40);
            va = PAR.INIT_VEL(pp, [1; 1], fl.temp, original, method{1});
            state_a = rng;
            rng(40);
            vb = PAR.INIT_VEL(pp, [1; 1], fl.temp, variants{j}, method{1});
            [names, pass] = add(names, pass, 'INIT_VEL table identity', ...
                isequal(va, vb) && isequal(state_a, rng));
        end
    end
end
bad = t;
bad.Properties.RowNames{3} = 'other';
[names, pass] = add(names, pass, 'named table cannot use positional fallback', ...
    raises(@() UTILS.CONSTANT_VALUE(bad, 'kb'), ...
    'sootMosaic:CONSTANT_VALUE:MissingConstant'));
report = struct('name', names, 'pass', num2cell(pass));
if ~all(pass)
    error('sootMosaic:QA:ConstantsFailed', ...
        '%d of %d cases failed.', sum(~pass), numel(pass));
end
end

function [names, pass] = add(names, pass, name, ok)
% "add" records one comparison.
names{end + 1, 1} = name;
pass(end + 1, 1) = logical(ok);
end

function ok = raises(fun, id)
% "raises" checks a diagnostic identifier.
ok = false;
try
    fun();
catch err
    ok = strcmp(err.identifier, id);
end
end

function write_json(file, value)
% "write_json" writes a configuration fixture.
fid = fopen(file, 'w');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(value), 'char');
end
