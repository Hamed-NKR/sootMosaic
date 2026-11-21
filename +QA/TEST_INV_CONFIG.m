function report = TEST_INV_CONFIG()
% "TEST_INV_CONFIG" checks inversion configuration and source selection.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Synthetic campaign tables and...
%         ...registry fixtures use tempname and are removed on exit....
%         ...Failures use sootMosaic:QA:InvConfigFailed
% ----------------------------------------------------------------------- %

root = fileparts(fileparts(mfilename('fullpath')));
folder = tempname;
mkdir(folder);
state = warning;
[message, id] = lastwarn;
selector = getenv('SOOTMOSAIC_MAIN_INV_CONFIG');
cleanup = onCleanup(@() restore(folder, state, message, id, selector));
setenv('SOOTMOSAIC_MAIN_INV_CONFIG', '');
warning('on', 'sootMosaic:CONFIG_READ:UnknownKey');
warning('on', 'sootMosaic:CONFIG_DATA_RULE:Mismatch');
names = {'example without a local file', 'dictionary coverage both ways', ...
    'recorded units to SI', 'D data only and required missing value', ...
    'recorded counting flow and AAC fallback', 'C ignores measured alternatives', ...
    'recorded DMA excess flow', 'R selection and database geometry', ...
    'P current gas slip and constants', 'W>D>C campaign and reason', ...
    'instrument file wins over workbook', 'X supplied and configured refusal', ...
    'strict placeholders', 'unknown keys normal and strict', ...
    'missing registry id', 'soft x-ray primary and sensitivities', ...
    'legacy INV stage refusal', 'selector local overlay and explicit path', ...
    'grid rule and fixture exception', 'registry marker and strict completion', ...
    'impactor registry and SI range', 'array segment conversion', ...
    'inversion grid and report defaults', 'registry dictionary coverage', ...
    'provenance digests', 'invalid source types and campaign shape', ...
    'dictionary defaults without extends'};
pass = false(size(names));
for k = 1:numel(names)
    directory = fullfile(folder, sprintf('case_%02d', k));
    mkdir(directory);
    copyfile(fullfile(root, 'config', 'main_inv'), ...
        fullfile(directory, 'main_inv'));
    copyfile(fullfile(root, 'config', 'instruments'), ...
        fullfile(directory, 'instruments'));
    opts = struct('ConfigDirectory', fullfile(directory, 'main_inv'), ...
        'RegistryDirectory', fullfile(directory, 'instruments'));
    try
        run_case(k, directory, opts);
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
    setenv('SOOTMOSAIC_MAIN_INV_CONFIG', '');
    if pass(k), fprintf('PASS %s\n', names{k}); end
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:InvConfigFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass));
end
end

function run_case(index, folder, opts)
example = fullfile(opts.ConfigDirectory, 'main_inv_config.example.json');
dictionary = fullfile(opts.ConfigDirectory, 'main_inv.keys.json');
data = struct();
campaign = struct();
switch index
    case 1
        cfg = load_config('', data, campaign, opts);
        check(strcmp(cfg.mode, 'tandem') && ~isempty(cfg.pending));
        check(strcmp(cfg.provenance.files(end).file, canonical(example)));
    case 2
        rows = read_rows(dictionary);
        raw = jsondecode(fileread(example));
        known = cellfun(@(r) r.path, rows, 'UniformOutput', false);
        paths = leaves(raw, '', known);
        check(numel(unique(known)) == numel(known));
        check_paths(paths, known);
        for k = 1:numel(rows)
            row = rows{k};
            if ~contains(row.path, '[]')
                check(has_path(raw, row.path));
            end
            check(isfield(row, 'citation') && ~isempty(row.citation));
            check(isfield(row, 'reading_rule') && isfield(row, 'unit'));
        end
    case 3
        data.scan = struct('counting_flow_lpm', .3, ...
            'dma_temperature_deg_c', 26.85, 'dma_pressure_kpa', 99, ...
            'logged_mean_free_path_nm', 67.3, 'logged_viscosity_pa_s', 2e-5, ...
            'reference_temperature_k', 296.15, 'equalizer_length_cm', 42, ...
            'delay_s', 1.1, 'voltage_low_v', 100, 'aac_speed_rad_s', 1000, ...
            'counts', [2 3]);
        opts.Derived.derived = struct('sample_volume_m3', .02, 'mass_ugm3', 2);
        cfg = load_config(example, data, campaign, opts);
        near(cfg.si.scan.counting_flow_lpm, 5e-6);
        near(cfg.si.scan.dma_temperature_deg_c, 300);
        near(cfg.si.scan.dma_pressure_kpa, 99000);
        near(cfg.si.scan.logged_mean_free_path_nm, 67.3e-9);
        near(cfg.si.scan.logged_viscosity_pa_s, 2e-5);
        near(cfg.si.scan.reference_temperature_k, 296.15);
        near(cfg.si.scan.equalizer_length_cm, .42);
        near(cfg.si.scan.delay_s, 1.1);
        near(cfg.si.scan.voltage_low_v, 100);
        near(cfg.si.scan.aac_speed_rad_s, 1000);
        near(cfg.si.scan.counts, [2 3]);
        near(cfg.si.geometry.dma_inner_radius_m, .00937);
        near(cfg.si.grid.rho_bounds_kg_m3, [20; 3000]);
        near(cfg.si.derived.sample_volume_m3, .02);
        near(cfg.si.derived.mass_ugm3, 2e-9);
        near(cfg.si.transfer.aac.width_error_percent, [-.128; .174]);
        near(cfg.si.exclusion.charger_limit_cm3_inv, 1e12);
        near(cfg.si.gas.kb_j_k, 1.380649e-23);
        near(cfg.si.gas.e_c, cfg.model_params.constants.e_c);
        near(cfg.si.gas.eps0_f_m, cfg.model_params.constants.eps0_f_m);
        check(cfg.scan.counting_flow_lpm == .3);
        check(cfg.scan.dma_temperature_deg_c == 26.85);
    case 4
        data.scan.delay_s = 1.25;
        opts.RequiredPaths = {'scan.delay_s'};
        cfg = load_config(example, data, campaign, opts);
        check(cfg.scan.delay_s == 1.25);
        r = reading(cfg, 'scan.delay_s');
        check(strcmp(r.source, 'data'));
        fails(@() load_config(example, struct(), campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:MissingValue');
        file = overlay(opts, struct('scan', struct('delay_s', 2)));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:ConfiguredSource');
    case 5
        data.scan.counting_flow_lpm = .3;
        cfg = load_config(example, data, campaign, opts);
        near(cfg.scan.counting_flow_lpm, .3);
        r = reading(cfg, 'scan.counting_flow_lpm');
        check(strcmp(r.source, 'data'));
        cfg = load_config(example, struct(), campaign, opts);
        check(isempty(cfg.scan.counting_flow_lpm));
        r = reading(cfg, 'aac_1d.counting_flow_lpm');
        check(strcmp(r.source, 'registry'));
        file = overlay(opts, struct('scan', struct('counting_flow_lpm', .4)));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:ConfiguredSource');
    case 6
        data.scan_response.tau_s_s = 8;
        cfg = load_config(example, data, campaign, opts);
        check(cfg.scan_response.tau_s_s == .233);
    case 7
        data.scan.dma_sheath_flow_lpm = 3;
        data.scan.dma_excess_flow_lpm = 3.05;
        cfg = load_config(example, data, campaign, opts);
        near(cfg.scan.dma_excess_flow_lpm, 3.05);
        r = reading(cfg, 'scan.dma_excess_flow_lpm');
        check(strcmp(r.source, 'data') && strcmp(r.code, 'D'));
        data.scan = rmfield(data.scan, 'dma_excess_flow_lpm');
        cfg = load_config(example, data, campaign, opts);
        check(isempty(cfg.scan.dma_excess_flow_lpm));
        file = overlay(opts, struct('scan', struct('dma_excess_flow_lpm', 3)));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:ConfiguredSource');
    case 8
        cfg = load_config(example, data, campaign, opts);
        near(cfg.geometry.aac_inner_radius_m, .056);
        near(cfg.penetration.dma_length_m, 7.1);
        near(cfg.penetration.dma_equivalent_length_m, 9.1);
        r = reading(cfg, 'geometry.aac_inner_radius_m');
        check(strcmp(r.source, 'registry'));
        data.geometry.dma_inner_radius_m = .01;
        cfg = load_config(example, data, campaign, opts);
        near(cfg.geometry.dma_inner_radius_m, .01);
    case 9
        cfg = load_config(example, data, campaign, opts);
        check(strcmp(cfg.model.profile, 'current'));
        check(strcmp(cfg.gas.model, 'sutherland'));
        check(strcmp(cfg.gas.slip_model, 'kim2005'));
        near(cfg.model_params.gas.sutherland.mu_ref_pa_s, 1.83245e-5);
        near(cfg.model_params.gas.sutherland.t_ref_k, 296.15);
        r = reading(cfg, 'gas.model');
        check(strcmp(r.source, 'profile'));
    case 10
        values.scan.dilution_factor = 20;
        reasons.scan.dilution_factor = 'Synthetic dilution chain';
        campaign = campaign_table(folder, values, reasons);
        data.scan.dilution_factor = 2;
        cfg = load_config(example, data, campaign, opts);
        r = reading(cfg, 'scan.dilution_factor');
        check(cfg.scan.dilution_factor == 20 && numel(r.comparisons) == 3);
        check(strcmp(r.source, 'campaign'));
        cfg = load_config(example, data, struct(), opts);
        check(cfg.scan.dilution_factor == 2);
        cfg = load_config(example, struct(), struct(), opts);
        check(cfg.scan.dilution_factor == 1);
        campaign = campaign_table(folder, values, struct());
        fails(@() load_config(example, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:MissingReason');
    case 11
        values.scan.dma_sheath_flow_lpm = 3;
        reasons.scan.dma_sheath_flow_lpm = 'Synthetic workbook cell';
        campaign = campaign_table(folder, values, reasons);
        data.scan.dma_sheath_flow_lpm = 2.5;
        cfg = load_config(example, data, campaign, opts);
        r = reading(cfg, 'scan.dma_sheath_flow_lpm');
        check(cfg.scan.dma_sheath_flow_lpm == 2.5);
        check(strcmp(r.source, 'data') && strcmp(r.code, 'W>D>C'));
        check(strcmp(r.comparisons(end).source_b, 'campaign'));
        check(r.comparisons(end).value_b == 3);
        cfg = load_config(example, struct(), campaign, opts);
        check(cfg.scan.dma_sheath_flow_lpm == 3);
    case 12
        opts.Derived.derived.beta = .12;
        cfg = load_config(example, data, campaign, opts);
        check(cfg.derived.beta == .12);
        r = reading(cfg, 'derived.beta');
        check(strcmp(r.source, 'derived'));
        check(strcmp(cfg.statistics.kurtosis, 'pearson'));
        file = overlay(opts, struct('derived', struct('beta', .1)));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:ConfiguredSource');
    case 13
        opts.Strict = true;
        fails(@() load_config(example, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:Placeholder');
    case 14
        file = overlay(opts, struct('unexpected_key', 1));
        lastwarn('');
        load_config(file, data, campaign, opts);
        [~, id] = lastwarn;
        check(strcmp(id, 'sootMosaic:CONFIG_READ:UnknownKey'));
        opts.Strict = true;
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:CONFIG_READ:UnknownKey');
    case 15
        file = overlay(opts, struct('instruments', struct('dma', 'missing')));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:MissingRegistryId');
        file = overlay(opts, struct('charging', struct('model', 'missing')));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:MissingRegistryId');
    case 16
        cfg = load_config(example, data, campaign, opts);
        check(strcmp(cfg.charge_model.id, 'soft_xray_3082_tableB3'));
        near(cfg.charge_model.ion_mobility_ratio, .975);
        check(strcmp(cfg.charge_models{2}.id, 'kr85_wiedensohler'));
        near(cfg.charge_models{2}.ion_mobility_ratio, .875);
        check(strcmp(cfg.charge_models{3}.id, 'gopalakrishnan_2013'));
        check(isequal(size(cfg.charge_model.coefficients), [6 5]));
        check(strcmp(cfg.charge_model.coefficients_state, 'ready'));
        check(isequal(size(cfg.charge_models{3}.coefficients), [4 5]));
        data.scan.neutralizer_id = 'kr85';
        cfg = load_config(example, data, campaign, opts);
        r = reading(cfg, 'charging.model');
        check(strcmp(cfg.charging.model, 'soft_xray_3082_tableB3'));
        check(r.comparisons.exceeds_tolerance);
    case 17
        file = overlay(opts, struct('model_profile', 'article1_7658971'));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:MODEL_PROFILE:UnknownStage');
    case 18
        file = overlay(opts, struct('rng_seed', 7));
        setenv('SOOTMOSAIC_MAIN_INV_CONFIG', file);
        cfg = load_config('', data, campaign, opts);
        check(cfg.rng_seed == 7);
        cfg = load_config(example, data, campaign, opts);
        check(cfg.rng_seed == 1);
        setenv('SOOTMOSAIC_MAIN_INV_CONFIG', '');
        copyfile(file, fullfile(opts.ConfigDirectory, 'main_inv_config.local.json'));
        cfg = load_config('', data, campaign, opts);
        check(cfg.rng_seed == 7 && numel(cfg.provenance.files) == 2);
        setenv('SOOTMOSAIC_MAIN_INV_CONFIG', fullfile(folder, 'missing.json'));
        fails(@() load_config('', data, campaign, opts), ...
            'sootMosaic:CONFIG_READ:MissingFile');
    case 19
        file = overlay(opts, struct('grid', struct('d_min_nm', 10, 'd_max_nm', 2000)));
        fails(@() load_config(file, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:ExplicitGrid');
        opts.TestFixture = true;
        cfg = load_config(file, data, campaign, opts);
        near(cfg.si.grid.d_max_nm, 2e-6);
    case 20
        complete_fixture(opts);
        opts.Strict = true;
        cfg = load_config(example, data, campaign, opts);
        check(strcmp(cfg.charge_model.coefficients_state, 'ready'));
        file = fullfile(opts.RegistryDirectory, 'charging.json');
        raw = jsondecode(fileread(file));
        raw.models(1).coefficients = [];
        write_json(file, raw);
        fails(@() load_config(example, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:InvalidChargeTable');
    case 21
        data.instruments = struct('impactor_nozzle_cm', .071, ...
            'impactor_flow_lpm', .3);
        cfg = load_config(example, data, campaign, opts);
        check(strcmp(cfg.impactor_entry.id, 'impactor_0071'));
        near(cfg.si.instruments.impactor_nozzle_cm, .00071);
        near(cfg.si.impactor_entry.constants.flow_range_lpm, [1e-5; 3.5e-5]);
        data.instruments.impactor_nozzle_cm = .999;
        fails(@() load_config(example, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:MissingRegistryId');
    case 22
        values.penetration.tubes = {struct('id', 'synthetic', ...
            'length_m', .35, 'bore_mm', 5, 'flow_lpm', .3)};
        reasons.penetration.tubes = 'Synthetic plumbing';
        campaign = campaign_table(folder, values, reasons);
        cfg = load_config(example, data, campaign, opts);
        tube = cfg.si.penetration.tubes{1};
        near(tube.length_m, .35);
        near(tube.bore_mm, .005);
        near(tube.flow_lpm, 5e-6);
    case 23
        cfg = load_config(example, data, campaign, opts);
        check(strcmp(cfg.inversion.lambda_selection, 'evidence_marginal'));
        check(cfg.inversion.lambda_grid.n == 111);
        check(cfg.inversion.lambda_grid.min == 1e-8);
        check(strcmp(cfg.inversion.family_scope, 'instrument_mode'));
        check(cfg.grid.points_per_decade == 32 && cfg.grid.grid2d_points_per_decade == 12);
        check(cfg.grid.statistic_tol_sd == .25 && cfg.grid.sd_rel_tol == .1);
        check(cfg.report.d_cap_nm == 1400 && isempty(cfg.report.d_floor_nm));
        check(strcmp(cfg.variance.model, 'poisson_two_pass'));
        check(strcmp(cfg.peak_fit.window, 'all_channels'));
        check(cfg.uncertainty.kernel_draws.start == 20);
        check(~cfg.exclusion.flags_remove_data && ~cfg.nuisance.enabled);
        check(cfg.moments.withhold_structured_intervals);
        check(cfg.diagnostics.predictive_replicates >= 2000);
        check(isempty(cfg.cpc.unity_bound_max_deficit) && isempty(cfg.calibration.k_dm.uncertainty));
    case 24
        rows = read_rows(fullfile(opts.RegistryDirectory, 'instruments.keys.json'));
        known = cellfun(@(r) r.path, rows, 'UniformOutput', false);
        paths = {};
        for file = {'instruments.json', 'charging.json'}
            raw = jsondecode(fileread(fullfile(opts.RegistryDirectory, file{1})));
            paths = [paths, leaves(raw, '', known)]; %#ok<AGROW>
        end
        check_paths(paths, known);
        check(all(ismember(known, paths)));
    case 25
        cfg = load_config(example, data, campaign, opts);
        check(~isempty(cfg.registry_source.instruments.dictionary.file));
        if usejava('jvm')
            check(numel(cfg.provenance.dictionary.sha256) == 64);
            check(numel(cfg.registry_source.instruments.files(1).sha256) == 64);
            check(numel(cfg.registry_source.charging.files(1).sha256) == 64);
            check(numel(cfg.model_source.sha256) == 64);
        end
    case 26
        data.scan.delay_s = 'invalid';
        fails(@() load_config(example, data, campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:InvalidSource');
        campaign = campaign_table(folder, struct(), struct());
        campaign = [campaign; campaign];
        fails(@() load_config(example, struct(), campaign, opts), ...
            'sootMosaic:LOAD_MAIN_INV_CONFIG:InvalidCampaign');
    case 27
        file = fullfile(opts.ConfigDirectory, 'minimal.json');
        write_json(file, struct('config_version', 1));
        cfg = load_config(file, data, campaign, opts);
        check(strcmp(cfg.mode, 'tandem'));
        check(isempty(cfg.calibration.k_dm.uncertainty));
        check(cfg.report.d_cap_nm == 1400);
end
end

function cfg = load_config(file, data, campaign, opts)
cfg = UTILS.LOAD_MAIN_INV_CONFIG(file, data, campaign, opts);
end

function row = reading(cfg, path)
index = find(strcmp({cfg.reading.path}, path), 1);
check(~isempty(index));
row = cfg.reading(index);
end

function file = overlay(opts, value)
value.extends = 'main_inv_config.example.json';
file = fullfile(opts.ConfigDirectory, 'fixture.json');
write_json(file, value);
end

function row = campaign_table(folder, values, reasons)
row = table({values}, {reasons}, 'VariableNames', {'values', 'reasons'});
save(fullfile(folder, 'campaign.mat'), 'row');
end

function complete_fixture(opts)
% Supplying synthetic values to exercise strict validation, not physics
file = fullfile(opts.ConfigDirectory, 'main_inv_config.example.json');
raw = jsondecode(fileread(file));
rows = read_rows(fullfile(opts.ConfigDirectory, 'main_inv.keys.json'));
for k = 1:numel(rows)
    row = rows{k};
    if isfield(row, 'placeholder') && ...
            (~isfield(row, 'configurable') || row.configurable)
        value = 1;
        if strcmp(row.type, 'text'), value = 'synthetic'; end
        raw = put_path(raw, strsplit(row.path, '.'), value);
    elseif strcmp(row.type, 'number or none') && ...
            isempty(get_path(raw, row.path))
        raw = put_path(raw, strsplit(row.path, '.'), NaN);
    end
end
write_json(file, raw);
file = fullfile(opts.RegistryDirectory, 'instruments.json');
raw = jsondecode(fileread(file));
entries = raw.entries;
if isstruct(entries), entries = num2cell(entries); end
for k = 1:numel(entries)
    entry = entries{k};
    for j = 1:numel(entry.pending)
        key = entry.pending{j};
        value = 1;
        if contains(key, 'limits') || contains(key, 'range'), value = [1 2]; end
        entry.constants.(key) = value;
    end
    entry.pending = {};
    entries{k} = entry;
end
raw.entries = entries;
write_json(file, raw);
file = fullfile(opts.RegistryDirectory, 'charging.json');
raw = jsondecode(fileread(file));
for k = 1:numel(raw.models)
    if isempty(raw.models(k).ion_mobility_ratio)
        raw.models(k).ion_mobility_ratio = 1;
    end
end
write_json(file, raw);
end

function paths = leaves(value, prefix, known)
paths = {};
if isstruct(value) && isscalar(value)
    names = fieldnames(value);
    if isempty(names), paths = {prefix}; return; end
    for k = 1:numel(names)
        key = names{k};
        path = key;
        if ~isempty(prefix), path = [prefix '.' key]; end
        item = value.(key);
        if any(startsWith(known, [path '[].']))
            paths{end + 1} = path; %#ok<AGROW>
            if isstruct(item), item = num2cell(item); end
            for j = 1:numel(item)
                paths = [paths, leaves(item{j}, [path '[]'], known)]; %#ok<AGROW>
            end
        elseif isstruct(item)
            paths{end + 1} = path; %#ok<AGROW>
            paths = [paths, leaves(item, path, known)]; %#ok<AGROW>
        else
            paths{end + 1} = path; %#ok<AGROW>
        end
    end
end
paths = unique(paths);
end

function check_paths(paths, known)
for k = 1:numel(paths)
    path = paths{k};
    check(any(strcmp(known, path)) || any(startsWith(known, [path '.'])));
end
end

function value = get_path(value, path)
parts = strsplit(path, '.');
for k = 1:numel(parts)
    if ~isstruct(value) || ~isfield(value, parts{k}), value = []; return; end
    value = value.(parts{k});
end
end

function yes = has_path(value, path)
parts = strsplit(path, '.');
yes = true;
for k = 1:numel(parts)
    if ~isstruct(value) || ~isfield(value, parts{k}), yes = false; return; end
    value = value.(parts{k});
end
end

function value = put_path(value, parts, item)
if isscalar(parts)
    value.(parts{1}) = item;
else
    value.(parts{1}) = put_path(value.(parts{1}), parts(2:end), item);
end
end

function rows = read_rows(file)
rows = jsondecode(fileread(file));
if isstruct(rows), rows = num2cell(rows); end
end

function write_json(file, value)
fid = fopen(file, 'wb');
if fid < 0, error('sootMosaic:QA:InvConfigFailed', 'Cannot write fixture.'); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, [jsonencode(value), newline], 'char');
end

function path = canonical(path)
[ok, info] = fileattrib(path);
check(ok);
path = info.Name;
end

function near(actual, expected)
check(numel(actual) == numel(expected));
limit = max(1e-30, 1e-12 * abs(expected(:)));
check(all(abs(actual(:) - expected(:)) <= limit));
end

function check(pass)
if ~pass, error('sootMosaic:QA:InvConfigFailed', 'Case assertion failed.'); end
end

function fails(action, id)
try
    action();
catch err
    check(strcmp(err.identifier, id));
    return
end
error('sootMosaic:QA:InvConfigFailed', 'Expected error %s.', id);
end

function restore(folder, state, message, id, selector)
warning(state);
lastwarn(message, id);
setenv('SOOTMOSAIC_MAIN_INV_CONFIG', selector);
if isfolder(folder), rmdir(folder, 's'); end
end
