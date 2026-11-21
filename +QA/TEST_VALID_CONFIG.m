function report = TEST_VALID_CONFIG()
% "TEST_VALID_CONFIG" checks validation task reading and profile resolution.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Structure array with name and pass. Temporary fixtures are...
%         ...removed on exit. Failures raise sootMosaic:QA:ValidConfigFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:ValidConfigFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
primary = getenv('SOOTMOSAIC_MAIN_VALID_CONFIG');
fallback = getenv('PFAL_MAIN_VALID_CONFIG');
restore = onCleanup(@() restore_state(state, warn_message, warn_id, ...
    primary, fallback));
warning('off', 'sootMosaic:CONFIG_READ:UnknownKey');
warning('off', 'sootMosaic:LOAD_MAIN_VALID_CONFIG:LD2FractionsUnchecked');
root = fileparts(fileparts(mfilename('fullpath')));
example = fullfile(root, 'config', 'main_valid', ...
    'main_valid_config.example.json');
dictionary = fullfile(root, 'config', 'main_valid', 'main_valid.keys.json');
raw = jsondecode(fileread(example));
rows = jsondecode(fileread(dictionary));
if isstruct(rows), rows = num2cell(rows); end
paths = cellfun(@(r) r.path, rows, 'UniformOutput', false);
task_dir = fullfile(folder, 'tasks', 'valid');
mkdir(task_dir);
file = fullfile(task_dir, 'task.json');
strict = struct('Strict', true);
% LD2 product holding the snapshot fractions of the example conditions
ld2_file = fullfile(folder, 'ld2_product.mat');
save_variables(ld2_file, struct('r_n_agg', [1.0, 0.4, 0.2, 0.1, 0.05]));
base = raw;
base.sources.ld2.file = ld2_file;
tests = {@coverage, @example_forms, @wrapped_inputs, @numeric_inputs, ...
    @text_inputs, @optional_inputs, @pass_through, @profiles, ...
    @selectors, @overlays, @id_forms, @invalid_inputs, @sources, ...
    @fraction_check};
names = {'dictionary coverage both ways', 'example and parent forms', ...
    'native section and whole-task wrappers', ...
    'independent numeric contract', 'text conversion and emptiness', ...
    'optional values and defaults', 'pass-through, replaced and unknown keys', ...
    'profile switch and density precedence', 'selectors and default file', ...
    'overlays, id merge and provenance', ...
    'condition id forms and merge keys', 'invalid values and required keys', ...
    'inline and registry sources', 'LD2 fraction cross-check'};
pass = false(size(tests));
for case_index = 1:numel(tests)
    try
        tests{case_index}();
        pass(case_index) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{case_index}, err.identifier, ...
            err.message);
    end
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:ValidConfigFailed', '%d cases failed.', sum(~pass));
end

    function cfg = load_value(value, controls)
        if nargin < 2, controls = strict; end
        write_text(file, jsonencode(value));
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(file, controls);
    end

    function cfg = load_text(text, controls)
        if nargin < 2, controls = strict; end
        write_text(file, text);
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(file, controls);
    end

    function coverage()
        expected = expected_paths();
        check(isequal(sort(paths(:)), sort(expected(:))));
        check(numel(unique(paths)) == numel(paths));
        check(all(ismember(key_paths(raw, ''), paths)));
        for n = 1:numel(rows)
            r = rows{n};
            check(all(isfield(r, {'type', 'unit', 'status', 'since', ...
                'reader', 'reading_rule'})) && ~isempty(r.reader) && ...
                ~isempty(r.reading_rule));
            if any(strcmp(r.type, {'object', 'any', 'list of objects'}))
                check(isfield(r, 'native_json') && r.native_json);
            end
            check(isfield(r, 'struct_fallback') == strcmp(r.path, 'figures.axes'));
            check(isfield(r, 'native_items') == strcmp(r.path, 'conditions'));
            check(isfield(r, 'id_char') == strcmp(r.path, 'conditions[].id'));
            % Each key is read by a function its row names
            parts = strsplit(strrep(r.path, '[]', ''), '.');
            readers = strsplit(r.reader, ', ');
            found = false;
            for j = 1:numel(readers)
                code = which(['UTILS.' readers{j}]);
                check(~isempty(code));
                found = found || contains(fileread(code), parts{end});
            end
            check(found);
        end
        required = required_paths();
        marked = paths(cellfun(@(r) isfield(r, 'required') && r.required, rows));
        check(isequal(sort(marked(:)), sort(required(:))));
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            r = rows{strcmp(paths, contract{n, 1})};
            check(strcmp(r.type, contract{n, 2}) && strcmp(r.unit, contract{n, 3}));
            conversion = '';
            if isfield(r, 'coerce'), conversion = r.coerce; end
            check(strcmp(conversion, contract{n, 4}));
            check(isequal(row_field(r, 'min'), contract{n, 5}));
            check(isequal(row_field(r, 'max'), contract{n, 6}));
            reshaped = ~isempty(regexp(contract{n, 2}, 'vector|numbers', 'once'));
            check(isequal(isfield(r, 'row_vector') && r.row_vector, reshaped));
        end
        numeric = paths(cellfun(@(r) ~isempty(regexp(r.type, ...
            '^(number|integer|vector|\d+ numbers)$', 'once')), rows));
        declared = contract(~strcmp(contract(:, 2), 'any'), 1);
        check(isequal(sort(numeric(:)), sort([{'config_version'}; declared])));
        defaults = default_contract();
        defaulted = paths(cellfun(@(r) isfield(r, 'default'), rows));
        check(isequal(sort(defaulted(:)), sort(defaults(:, 1))));
        for n = 1:size(defaults, 1)
            r = rows{strcmp(paths, defaults{n, 1})};
            value = r.default;
            if isnumeric(value) && ~isempty(value), value = value(:).'; end
            check(isequaln(value, defaults{n, 2}));
        end
    end

    function example_forms()
        lastwarn('', '');
        cfg = load_text(fileread(example));
        [~, id] = lastwarn;
        check(strcmp(id, 'sootMosaic:LOAD_MAIN_VALID_CONFIG:LD2FractionsUnchecked'));
        check(strcmp(cfg.model_profile, 'current') && cfg.config_version == 1);
        check(isequal(cfg.model, current_model()));
        check(cfg.physics.material_density_kg_m3 == 1860);
        check(isstruct(cfg.conditions) && isequal(size(cfg.conditions), [4 1]));
        check(isequal({cfg.conditions.id}, {'low_agglomeration', ...
            'high_agglomeration', 'moderate_collapse', 'extensive_collapse'}));
        check(isequal(cfg.conditions(1).ld2_fractions, 1));
        check(isequal(cfg.conditions(2).ld2_fractions, [0.1 0.05]));
        check(isequal(size(cfg.conditions(3).ld2_fractions), [0 0]));
        check(strcmp(cfg.config_file, canonical(file)));
        check(strcmp(cfg.outputs.root, ...
            canonical(fullfile(folder, 'results', 'main_valid'))));
        check(strcmp(cfg.sources.ld2.cache_file, canonical(fullfile( ...
            folder, '.sootmosaic-cache', 'main_valid', 'ld2_results.mat'))));
        check(cfg.si.references.dpp_vs_da.value_at_100_nm == 17.8 * 1e-9);
        check(cfg.si.references.rho_eff_vs_dm.value_at_100_nm == 510);
        check(isequal(cfg.si.conditions, cfg.conditions));
        check(strcmp(cfg.si.outputs.root, cfg.outputs.root));
        check(strcmp(cfg.si.config_file, cfg.config_file));
        check(~isfield(cfg.si, 'model') && ~isfield(cfg.si, 'model_params'));
        check(isscalar(cfg.provenance.files) && endsWith( ...
            cfg.provenance.dictionary.file, 'main_valid.keys.json'));
        saved = jsondecode(jsonencode(cfg));
        check(isfield(saved, 'si') && isfield(saved, 'provenance'));
        % Parent form without version and profile, with explicit density
        old = rmfield(raw, {'config_version', 'model_profile'});
        old.physics.material_density_kg_m3 = 1860;
        cfg_old = load_value(old);
        check(~isfield(cfg_old, 'model_profile') && cfg_old.config_version == 1);
        check(isequal(cfg_old.model, article1_model()));
        check(cfg_old.model_params.resolved.rho_aero_ref_kg_m3 == 1860);
        for section = {'sources', 'conditions', 'physics', 'references', ...
                'fits', 'figures', 'outputs'}
            check(isequaln(cfg_old.(section{1}), cfg.(section{1})));
        end
    end

    function wrapped_inputs()
        ordinary = without_records(load_value(base));
        objects = {'sources', 'sources.ld2', 'sources.tem', ...
            'sources.effective_density', 'physics', 'references', ...
            'references.dpp_vs_da', 'references.rho_eff_vs_dm', 'fits', ...
            'fits.dpp_vs_da', 'fits.rho_eff_vs_dm', ...
            'fits.experimental_rho_eff_vs_dm', 'figures', 'figures.axes', ...
            'figures.font', 'figures.legend', 'figures.dpp_vs_da', ...
            'figures.rho_eff_vs_dm', 'outputs'};
        for n = 1:numel(objects)
            value = put(base, objects{n}, {get(base, objects{n})});
            check(isequaln(without_records(load_value(value)), ordinary));
        end
        for key = {'include', 'style'}
            entries = num2cell(base.conditions);
            for k = 1:numel(entries)
                entries{k}.(key{1}) = {entries{k}.(key{1})};
            end
            value = base;
            value.conditions = entries;
            check(isequaln(without_records(load_value(value)), ordinary));
        end
        cfg = load_text(['[' jsonencode(base) ']']);
        check(isequaln(without_records(cfg), ordinary));
        value = base;
        value.conditions = base.conditions(1);
        single = without_records(load_value(value));
        value.conditions = {base.conditions(1)};
        check(isequaln(without_records(load_value(value)), single));
        check(isequal(size(single.conditions), [1 1]));
        check(isequaln(single.conditions, ordinary.conditions(1)));
        value = base;
        value.physics = {struct()};
        check(load_value(value).physics.material_density_kg_m3 == 1860);
    end

    function numeric_inputs()
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            target = contract{n, 1};
            valid = contract{n, 7};
            factor = contract{n, 8};
            scalar = isscalar(valid) && ~any(strcmp(contract{n, 2}, ...
                {'vector', '2 numbers', '4 numbers'}));
            inputs = {valid, {valid}};
            if scalar && valid == fix(valid) && valid >= 1 && valid < 128
                inputs{end + 1} = char(valid); %#ok<AGROW>
            end
            if ~scalar
                inputs{end + 1} = cellfun(@(x) {x}, num2cell(valid(:)), ...
                    'UniformOutput', false); %#ok<AGROW>
            end
            for j = 1:numel(inputs)
                cfg = load_value(set_value(base, target, inputs{j}));
                actual = get_value(cfg, target);
                converted = get_value(cfg.si, target);
                check(isa(actual, 'double') && isequal(actual, valid));
                check(isa(converted, 'double') && ...
                    isequal(converted, valid * factor));
            end
            if scalar && ~strcmp(contract{n, 2}, 'any')
                fails(@() load_value(set_value(base, target, 'ab')), ...
                    'sootMosaic:CONFIG_READ:InvalidType');
            end
            if ~isempty(contract{n, 5})
                fails(@() load_value(set_value(base, target, ...
                    contract{n, 5} - 1 + 0 * valid)), ...
                    'sootMosaic:CONFIG_READ:OutOfRange');
            end
            if ~isempty(contract{n, 6})
                fails(@() load_value(set_value(base, target, ...
                    contract{n, 6} + 1)), 'sootMosaic:CONFIG_READ:OutOfRange');
            end
            if strcmp(contract{n, 2}, 'integer')
                fails(@() load_value(set_value(base, target, valid + 0.5)), ...
                    'sootMosaic:CONFIG_READ:InvalidInteger');
            end
            if any(strcmp(contract{n, 2}, {'2 numbers', '4 numbers'}))
                fails(@() load_value(set_value(base, target, valid(1))), ...
                    'sootMosaic:CONFIG_READ:InvalidType');
                fails(@() load_value(set_value(base, target, [valid valid])), ...
                    'sootMosaic:CONFIG_READ:InvalidLength');
            end
        end
        % Logical and matrix inputs follow the double conversion
        cfg = load_value(set_value(base, 'figures.simulation_marker_alpha', true));
        check(cfg.figures.simulation_marker_alpha == 1);
        cfg = load_value(set_value(base, 'figures.dpp_vs_da.position', ...
            [true false true true]));
        check(isequal(cfg.figures.dpp_vs_da.position, [1 0 1 1]));
        cfg = load_value(set_value(base, 'conditions[].ld2_fractions', ...
            [0.1 0.2; 0.4 1]));
        check(isequal(cfg.conditions(1).ld2_fractions, [0.1 0.4 0.2 1]));
        cfg = load_value(set_value(base, 'fits.dpp_vs_da.prior_mu', 'AB'));
        check(isequal(cfg.fits.dpp_vs_da.prior_mu, [65 66]));
        text = strrep(jsonencode(set_value(base, 'fits.dpp_vs_da.prior_mu', ...
            [1 2])), '"prior_mu":[1,2]', '"prior_mu":[1,null]');
        fails(@() load_text(text), 'sootMosaic:CONFIG_READ:Nonfinite');
        fails(@() load_value(set_value(base, 'figures.axes.tick_length', ...
            [0.02 -0.01])), 'sootMosaic:CONFIG_READ:OutOfRange');
    end

    function text_inputs()
        plain = {'conditions[].label', 'conditions[].style.color', ...
            'conditions[].style.simulation_marker', ...
            'conditions[].style.experimental_marker', ...
            'references.dpp_vs_da.label', 'references.dpp_vs_da.color', ...
            'references.dpp_vs_da.line_style', 'references.rho_eff_vs_dm.label', ...
            'references.rho_eff_vs_dm.color', 'references.rho_eff_vs_dm.line_style', ...
            'figures.font.family', 'figures.font.fallback'};
        for n = 1:numel(plain)
            cfg = load_value(set_value(base, plain{n}, 65));
            check(strcmp(get_value(cfg, plain{n}), 'A'));
            cfg = load_value(set_value(base, plain{n}, {'ab'}));
            check(strcmp(get_value(cfg, plain{n}), 'ab'));
            for empty = {[], ''}
                fails(@() load_value(set_value(base, plain{n}, empty{1})), ...
                    'sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingText');
            end
        end
        choices = { ...
            'figures.visible', 'OFF', 'off'; ...
            'figures.font.weight', 'Bold', 'Bold'; ...
            'figures.font.interpreter', 'LaTeX', 'latex'; ...
            'figures.legend.location', 'NorthEast', 'northeast'; ...
            'figures.legend.orientation', 'Horizontal', 'horizontal'; ...
            'figures.legend.interpreter', 'TeX', 'tex'; ...
            'figures.legend.font_weight', 'BOLD', 'bold'; ...
            'figures.axes.layer', 'Bottom', 'bottom'; ...
            'figures.axes.label_position_mode', 'Manual', 'Manual'; ...
            'fits.dpp_vs_da.x_transform', 'NONE', 'none'; ...
            'fits.rho_eff_vs_dm.y_transform', 'Log10', 'log10'; ...
            'fits.experimental_rho_eff_vs_dm.support_mode', 'Common', 'common'; ...
            'outputs.png_source', 'PDF', 'pdf'};
        for n = 1:size(choices, 1)
            cfg = load_value(set_value(base, choices{n, 1}, choices{n, 2}));
            check(strcmp(get_value(cfg, choices{n, 1}), choices{n, 3}));
        end
        cfg = load_value(set_value(base, 'conditions[].id', 7));
        check(strcmp(cfg.conditions(1).id, char(7)));
        cfg = load_value(set_value(base, 'outputs.root', 'out'));
        check(strcmp(cfg.outputs.root, canonical(fullfile(task_dir, 'out'))));
        absolute = fullfile(folder, 'absolute_results');
        cfg = load_value(set_value(base, 'outputs.root', absolute));
        check(strcmp(cfg.outputs.root, canonical(absolute)));
        cfg = load_value(set_value(base, ...
            'conditions[].style.experimental_marker_face_color', 'k'));
        check(strcmp(cfg.conditions(1).style.experimental_marker_face_color, 'k'));
        cfg = load_value(set_value(base, 'outputs.experimental_summary_csv', 66));
        check(strcmp(cfg.outputs.experimental_summary_csv, 'B'));
    end

    function optional_inputs()
        defaults = default_contract();
        for n = 1:size(defaults, 1)
            target = defaults{n, 1};
            if any(strcmp(target, {'config_version', ...
                    'fits.experimental_rho_eff_vs_dm', 'figures.axes.box'}))
                continue
            end
            expected = defaults{n, 2};
            subject = base;
            if startsWith(target, 'conditions[]')
                subject.conditions(1).enabled = false;
            end
            for item = {[], '', 'NULL_TOKEN', 'ABSENT_TOKEN'}
                if strcmp(item{1}, 'ABSENT_TOKEN')
                    cfg = load_value(drop_value(subject, target));
                elseif strcmp(item{1}, 'NULL_TOKEN')
                    cfg = load_text(strrep(jsonencode(set_value(subject, ...
                        target, 'NULL_TOKEN')), '"NULL_TOKEN"', 'null'));
                else
                    cfg = load_value(set_value(subject, target, item{1}));
                end
                actual = get_value(cfg, target);
                check(isequaln(actual, expected) && ...
                    isequal(size(actual), size(expected)));
            end
        end
        cfg = load_value(drop_value(base, 'figures.axes.box'));
        check(cfg.figures.axes.box == true);
        for item = {5, 'x', true, []}
            value = put(base, 'figures.axes', item{1});
            check(isequal(load_value(value).figures.axes, default_axes()));
        end
        check(isequal(load_value(drop_value(base, 'figures.axes')).figures.axes, ...
            default_axes()));
        value = drop_value(base, 'fits.experimental_rho_eff_vs_dm');
        fit = load_value(value).fits.experimental_rho_eff_vs_dm;
        check(isequal(fit, struct('enabled', false, 'degree', 1, ...
            'support_mode', 'common', 'support_limits_nm', [], ...
            'confidence_level', 0.95)) && isequal(size(fit.support_limits_nm), [0 0]));
        % Conditional defaults follow the values they copy
        value = drop_value(base, 'conditions[].style.experimental_color');
        cfg = load_value(value);
        check(strcmp(cfg.conditions(1).style.experimental_color, ...
            cfg.conditions(1).style.color));
        cfg = load_value(set_value(base, 'conditions[].style.experimental_color', ''));
        check(strcmp(cfg.conditions(1).style.experimental_color, '#0072B2'));
        value = drop_value(base, 'figures.font.title_size');
        value.figures.font.label_size = 21;
        check(load_value(value).figures.font.title_size == 21);
        value.figures.font.title_size = [];
        check(load_value(value).figures.font.title_size == 21);
        value = base;
        value.figures.legend.font_family = '';
        value.figures.font.weight = 'Bold';
        cfg = load_value(value);
        check(strcmp(cfg.figures.legend.font_family, cfg.figures.font.family));
        check(strcmp(cfg.figures.legend.font_fallback, cfg.figures.font.fallback));
        check(strcmp(cfg.figures.legend.font_weight, 'bold'));
        check(strcmp(cfg.figures.font.weight, 'Bold'));
        value = drop_value(base, 'physics.material_density_kg_m3');
        check(load_value(value).physics.material_density_kg_m3 == 1860);
    end

    function pass_through()
        ordinary = without_records(load_value(base));
        replaced = {'config_file', 'model', 'model_params', 'model_source'};
        for n = 1:numel(replaced)
            for item = {struct('x', 1), [1 2], 'text', true}
                value = base;
                value.(replaced{n}) = item{1};
                check(isequaln(without_records(load_value(value)), ordinary));
            end
        end
        value = base;
        value.sources.tem.variables = 'aggregate_table';
        cfg = load_value(value);
        check(strcmp(cfg.sources.tem.variables, 'aggregate_table'));
        value.sources.tem.variables = {'aggregate_table'};
        check(isequal(load_value(value).sources.tem.variables, {'aggregate_table'}));
        value = base;
        value.sources.tem = struct('source_id', 5);
        check(isequal(load_value(value).sources.tem, struct('source_id', 5)));
        % Unknown keys retain their decoded values and fail in strict mode
        value = base;
        value.extra = struct('tag', {1; 2});
        value.figures.extra = {1; 'a'};
        value.sources.ld2.extra = [1 2 3];
        entries = num2cell(value.conditions);
        for k = 1:numel(entries), entries{k}.note_value = k; end
        value.conditions = entries;
        lastwarn('', '');
        cfg = load_value(value, struct('Strict', false));
        [~, id] = lastwarn;
        check(strcmp(id, 'sootMosaic:CONFIG_READ:UnknownKey'));
        check(isequal(cfg.extra, struct('tag', {1; 2})));
        check(isequal(cfg.figures.extra, {1; 'a'}));
        check(isequal(cfg.sources.ld2.extra, [1; 2; 3]));
        check(isequal([cfg.conditions.note_value], 1:4));
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        % Unknown condition metadata keeps decoded id arrays unmerged
        for nested = {'[{"id":"a","value":1},{"id":"b","value":2}]', ...
                '[{"id":"a","value":1},{"id":"a","value":2}]'}
            expected = jsondecode(nested{1});
            entries = num2cell(base.conditions);
            for k = 1:numel(entries), entries{k}.extra = expected; end
            value = base;
            value.conditions = entries;
            cfg = load_value(value, struct('Strict', false));
            for k = 1:numel(cfg.conditions)
                extra = cfg.conditions(k).extra;
                check(isstruct(extra) && isequal(size(extra), [2 1]) && ...
                    isequal(extra, expected));
            end
            check(isequal(cfg.si.conditions, cfg.conditions));
            fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        end
        text = jsonencode(base);
        text = ['{"comment":"note",' text(2:end)];
        text = strrep(text, '"physics":{}', '"physics":{"comment":"empty"}');
        cfg = load_text(text);
        check(~isfield(cfg, 'comment') && isempty(fieldnames(rmfield( ...
            cfg.physics, 'material_density_kg_m3'))));
    end

    function profiles()
        cfg = load_value(base);
        check(isequal(cfg.model, current_model()));
        check(cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1000);
        check(strcmp(cfg.model_params.resolved.root_tolerance, 'eps_scaled'));
        value = base;
        value.model_profile = 'article1_7658971';
        cfg = load_value(value);
        check(isequal(cfg.model, article1_model()));
        check(cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1860);
        check(strcmp(cfg.model_params.resolved.root_tolerance, 'default'));
        check(cfg.physics.material_density_kg_m3 == 1860);
        check(isempty(cfg.model_source.overrides));
        value = rmfield(base, 'model_profile');
        cfg = load_value(value);
        check(~isfield(cfg, 'model_profile'));
        check(isequal(cfg.model, article1_model()));
        value = base;
        value.model_overrides.constants.rho_bc_kg_m3 = 2000;
        cfg = load_value(value);
        check(cfg.physics.material_density_kg_m3 == 2000);
        check(cfg.model_params.si.constants.rho_bc_kg_m3 == 2000);
        value.physics.material_density_kg_m3 = 1500;
        cfg = load_value(value);
        check(cfg.physics.material_density_kg_m3 == 1500);
        check(cfg.model_params.constants.rho_bc_kg_m3 == 1500);
        changed = cfg.model_source.overrides(end);
        check(strcmp(changed.path, 'constants.rho_bc_kg_m3') && ...
            changed.old_value == 2000 && changed.new_value == 1500 && ...
            strcmp(changed.source, cfg.config_file));
        value.model_profile = 'article1_7658971';
        cfg = load_value(value);
        check(cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1500);
        value = base;
        value.model_profile = 'missing_profile_name';
        fails(@() load_value(value), 'sootMosaic:MODEL_PROFILE:UnknownProfile');
        value = base;
        value.model_overrides.constants.unknown_constant = 1;
        fails(@() load_value(value), 'sootMosaic:MODEL_PROFILE:UnknownKey');
    end

    function selectors()
        first = fullfile(folder, 'first.json');
        second = fullfile(folder, 'second.json');
        third = fullfile(folder, 'third.json');
        labels = {first, 'first.csv'; second, 'second.csv'; third, 'third.csv'};
        for n = 1:size(labels, 1)
            value = set_value(base, 'outputs.experimental_summary_csv', labels{n, 2});
            write_text(labels{n, 1}, jsonencode(value));
        end
        setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', first);
        setenv('PFAL_MAIN_VALID_CONFIG', second);
        check(strcmp(selected(''), 'first.csv'));
        check(strcmp(selected(third), 'third.csv'));
        setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', '');
        check(strcmp(selected(''), 'second.csv'));
        setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', fullfile(folder, 'none.json'));
        fails(@() selected(''), 'sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingConfig');
        setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', '');
        setenv('PFAL_MAIN_VALID_CONFIG', '');
        local = fullfile(root, 'config', 'main_valid', ...
            'main_valid_config.local.json');
        if ~isfile(local)
            fails(@() selected(''), 'sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingConfig');
        end
        fails(@() selected(fullfile(folder, 'none.json')), ...
            'sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingConfig');
    end

    function name = selected(path_value)
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(path_value, strict);
        name = cfg.outputs.experimental_summary_csv;
    end

    function overlays()
        parent_file = fullfile(task_dir, 'parent.json');
        write_text(parent_file, jsonencode(base));
        overlay_dir = fullfile(task_dir, 'local');
        mkdir(overlay_dir);
        overlay_file = fullfile(overlay_dir, 'overlay.json');
        write_text(overlay_file, ['{"extends":"../parent.json",' ...
            '"conditions":[{"id":"high_agglomeration","enabled":false}],' ...
            '"outputs":{"root":"overlay_results"}}']);
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict);
        reference = load_value(base);
        check(isequal({cfg.conditions.id}, {reference.conditions.id}));
        check(isequal([cfg.conditions.enabled], [true false false false]));
        check(isequaln(cfg.conditions([1 3 4]), reference.conditions([1 3 4])));
        check(strcmp(cfg.outputs.root, canonical(fullfile(overlay_dir, ...
            'overlay_results'))));
        check(strcmp(cfg.sources.tem.file, canonical(fullfile(overlay_dir, ...
            raw.sources.tem.file))));
        check(numel(cfg.provenance.files) == 2);
        check(endsWith(cfg.provenance.files(1).file, 'parent.json') && ...
            endsWith(cfg.provenance.files(2).file, 'overlay.json'));
        records = {cfg.provenance.overrides.path};
        check(any(strcmp(records, 'conditions[id=high_agglomeration].enabled')));
        added = base.conditions(1);
        added.id = 'added_condition';
        write_text(overlay_file, jsonencode(struct('extends', ...
            '../parent.json', 'conditions', {{added}})));
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict);
        check(numel(cfg.conditions) == 5 && ...
            strcmp(cfg.conditions(5).id, 'added_condition'));
        write_text(overlay_file, '{"extends":"overlay.json"}');
        fails(@() UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict), ...
            'sootMosaic:CONFIG_READ:ExtendsCycle');
        % A single overlay entry merges by id only with native_items
        items = struct('path', {'list'; 'list[].id'; 'list[].x'}, ...
            'type', {'list of objects'; 'any'; 'any'}, ...
            'native_json', {true; true; true});
        lower_file = fullfile(folder, 'lower.json');
        upper_file = fullfile(folder, 'upper.json');
        write_text(lower_file, '{"list":[{"id":"a","x":1},{"id":"b","x":2}]}');
        write_text(upper_file, '{"extends":"lower.json","list":[{"id":"b","x":3}]}');
        with_items = items;
        with_items(1).native_items = true;
        merged = UTILS.CONFIG_READ(upper_file, with_items, strict);
        check(isequal(merged.list, {struct('id', 'a', 'x', 1); ...
            struct('id', 'b', 'x', 3)}));
        fails(@() UTILS.CONFIG_READ(upper_file, items, strict), ...
            'sootMosaic:CONFIG_MERGE:MissingId');
        % Id_char matches ids by their char conversion and stores them as...
            % ...given; nested arrays stay as decoded
        with_items(2).id_char = true;
        with_items(3).open = true;
        write_text(lower_file, ['{"list":[{"id":["a"],"x":1},' ...
            '{"id":["b"],"x":[{"id":"c","v":1},{"id":"c","v":2}]}]}']);
        write_text(upper_file, ['{"extends":"lower.json",' ...
            '"list":[{"id":"a","x":3}]}']);
        merged = UTILS.CONFIG_READ(upper_file, with_items, strict);
        check(numel(merged.list) == 2 && ...
            isequal(merged.list{1}, struct('id', 'a', 'x', 3)));
        check(isequal(merged.list{2}.id, {'b'}));
        check(isequal(merged.list{2}.x, struct('id', {'c'; 'c'}, ...
            'v', {1; 2})));
        fails(@() UTILS.CONFIG_READ(upper_file, ...
            rmfield(with_items, 'id_char'), strict), ...
            'sootMosaic:CONFIG_MERGE:InvalidId');
    end

    function id_forms()
        % Singleton text arrays and numeric code rows load as the parent ids
        ordinary = without_records(load_value(base));
        text = jsonencode(base);
        low = '"id":"low_agglomeration"';
        high = '"id":"high_agglomeration"';
        codes = @(name) ['[[' strjoin(arrayfun(@num2str, double(name), ...
            'UniformOutput', false), ',') ']]'];
        forms = {'["low_agglomeration"]', codes('low_agglomeration')};
        for n = 1:numel(forms)
            cfg = load_text(strrep(text, low, ['"id":' forms{n}]));
            check(isequaln(without_records(cfg), ordinary));
            check(ischar(cfg.conditions(1).id) && ...
                isequal(size(cfg.conditions(1).id), [1 17]));
        end
        cfg = load_text(strrep(text, low, '"id":[7]'));
        check(isequal(cfg.conditions(1).id, char(7)));
        % A one-element array holding empty text gives the parent's empty id
        empty_id = char(jsondecode('[""]'));
        cfg = load_text(strrep(text, low, '"id":[""]'));
        expected = ordinary;
        expected.conditions(1).id = empty_id;
        expected.si.conditions(1).id = empty_id;
        check(isequaln(without_records(cfg), expected));
        check(ischar(cfg.conditions(1).id) && isempty(cfg.conditions(1).id) ...
            && isequal(size(cfg.conditions(1).id), size(empty_id)));
        % An overlay targets the converted ids with plain text
        parent_file = fullfile(task_dir, 'id_parent.json');
        write_text(parent_file, strrep(strrep(text, low, ...
            '"id":["low_agglomeration"]'), high, ...
            ['"id":' codes('high_agglomeration')]));
        overlay_file = fullfile(task_dir, 'id_overlay.json');
        write_text(overlay_file, ['{"extends":"id_parent.json",' ...
            '"conditions":[{"id":"high_agglomeration","enabled":false},' ...
            '{"id":"low_agglomeration","label":"Low"}]}']);
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict);
        expected = base;
        expected.conditions(1).label = 'Low';
        expected.conditions(2).enabled = false;
        reference = load_value(expected);
        check(isequaln(cfg.conditions, reference.conditions));
        records = {cfg.provenance.overrides.path};
        check(any(strcmp(records, 'conditions[id=high_agglomeration].enabled')));
        check(any(strcmp(records, 'conditions[id=low_agglomeration].label')));
        % The overlay may also give an id in an unconverted form
        write_text(overlay_file, ['{"extends":"id_parent.json",' ...
            '"conditions":[{"id":' codes('low_agglomeration') ...
            ',"label":"Low"},{"id":["high_agglomeration"],' ...
            '"enabled":false}]}']);
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict);
        check(isequaln(cfg.conditions, reference.conditions));
        % Converted duplicates and ids the parent could not convert fail
        duplicates = {'["A"]', '"A"'; codes('AB'), '"AB"'; '[7]', '7'; ...
            '[""]', '[""]'};
        for n = 1:size(duplicates, 1)
            fails(@() load_text(strrep(strrep(text, low, ['"id":' ...
                duplicates{n, 1}]), high, ['"id":' duplicates{n, 2}])), ...
                'sootMosaic:CONFIG_MERGE:DuplicateId');
        end
        write_text(overlay_file, ['{"extends":"id_parent.json",' ...
            '"conditions":[{"id":"low_agglomeration","label":"Low"},' ...
            '{"id":["low_agglomeration"],"label":"Again"}]}']);
        fails(@() UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict), ...
            'sootMosaic:CONFIG_MERGE:DuplicateId');
        % An overlay reaches the empty key in the same form
        write_text(parent_file, strrep(text, low, '"id":[""]'));
        write_text(overlay_file, ['{"extends":"id_parent.json",' ...
            '"conditions":[{"id":[""],"label":"Empty"}]}']);
        cfg = UTILS.LOAD_MAIN_VALID_CONFIG(overlay_file, strict);
        check(numel(cfg.conditions) == 4 && ...
            isequal(cfg.conditions(1).id, empty_id) && ...
            strcmp(cfg.conditions(1).label, 'Empty'));
        check(any(strcmp({cfg.provenance.overrides.path}, ...
            'conditions[id=].label')));
        for refused = {'["A","B"]', '[65,66]', 'true', '{"a":1}', '""', ...
                '[]', 'null'}
            fails(@() load_text(strrep(text, low, ['"id":' refused{1}])), ...
                'sootMosaic:CONFIG_MERGE:InvalidId');
        end
    end

    function invalid_inputs()
        required = required_paths();
        for n = 1:numel(required)
            fails(@() load_value(drop_value(base, required{n})), ...
                'sootMosaic:CONFIG_READ:MissingKey');
        end
        positive = {'conditions[].style.simulation_marker_size', ...
            'conditions[].style.experimental_marker_size', ...
            'conditions[].style.experimental_marker_line_width', ...
            'conditions[].style.fit_line_width', ...
            'physics.material_density_kg_m3', ...
            'references.dpp_vs_da.value_at_100_nm', ...
            'references.dpp_vs_da.line_width', ...
            'references.rho_eff_vs_dm.value_at_100_nm', ...
            'references.rho_eff_vs_dm.line_width', ...
            'fits.dpp_vs_da.prior_v_scale', 'fits.dpp_vs_da.prior_a', ...
            'fits.dpp_vs_da.prior_b', 'fits.rho_eff_vs_dm.prior_v_scale', ...
            'fits.rho_eff_vs_dm.prior_a', 'fits.rho_eff_vs_dm.prior_b', ...
            'figures.axis_line_width', 'figures.axes.x_label_offset', ...
            'figures.axes.y_label_offset', 'figures.font.axis_size', ...
            'figures.font.label_size', 'figures.font.legend_size', ...
            'figures.font.title_size'};
        for n = 1:numel(positive)
            fails(@() load_value(set_value(base, positive{n}, 0)), ...
                'sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidPositiveNumber');
        end
        loader = 'sootMosaic:LOAD_MAIN_VALID_CONFIG:';
        cases = { ...
            'fits.dpp_vs_da.credible_level', 1, 'InvalidCredibleLevel'; ...
            'fits.rho_eff_vs_dm.credible_level', 0, 'InvalidCredibleLevel'; ...
            'fits.dpp_vs_da.x_transform', 'ln', 'InvalidTransform'; ...
            'fits.experimental_rho_eff_vs_dm.degree', 2, ...
            'InvalidExperimentalFitDegree'; ...
            'fits.experimental_rho_eff_vs_dm.support_mode', 'all', ...
            'InvalidExperimentalSupportMode'; ...
            'fits.experimental_rho_eff_vs_dm.support_mode', 'explicit', ...
            'MissingExperimentalSupportLimits'; ...
            'fits.experimental_rho_eff_vs_dm.confidence_level', 1, ...
            'InvalidExperimentalConfidenceLevel'; ...
            'fits.experimental_rho_eff_vs_dm.support_limits_nm', [200 80], ...
            'InvalidLimits'; ...
            'figures.visible', 'yes', 'InvalidVisibility'; ...
            'figures.axes.layer', 'middle', 'InvalidAxisLayer'; ...
            'figures.axes.label_position_mode', 'fixed', 'InvalidAxisStyle'; ...
            'figures.axes', struct('box', {true; false}), 'InvalidAxisStyle'; ...
            'figures.font.weight', 'light', 'InvalidFontWeight'; ...
            'figures.font.interpreter', 'html', 'InvalidInterpreter'; ...
            'figures.font.title_size', 'ab', 'InvalidNumber'; ...
            'figures.legend.orientation', 'diagonal', 'InvalidLegendOrientation'; ...
            'figures.legend.interpreter', 'html', 'InvalidLegendInterpreter'; ...
            'figures.legend.font_weight', 'light', 'InvalidLegendFontWeight'; ...
            'figures.dpp_vs_da.x_limits', [1 2 3], 'InvalidLimits'; ...
            'figures.rho_eff_vs_dm.y_limits', [0 10], 'InvalidLimits'; ...
            'outputs.png_source', 'screen', 'InvalidPNGSource'; ...
            'outputs.pdf', false, 'MissingPDFForPNG'; ...
            'outputs.root', '', 'MissingText'; ...
            'sources.ld2.variables', [], 'MissingSourceVariables'; ...
            'sources.tem.id', '', 'MissingText'; ...
            'conditions', [], 'MissingConditions'; ...
            'conditions[].ld2_fractions', [], 'MissingLD2Mapping'; ...
            'conditions[].tem_entry_id', '', 'MissingTEMMapping'; ...
            'conditions[].effective_density_condition_id', '', ...
            'MissingDensityMapping'};
        for n = 1:size(cases, 1)
            fails(@() load_value(set_value(base, cases{n, 1}, cases{n, 2})), ...
                [loader cases{n, 3}]);
        end
        value = base;
        value.conditions(2).id = 65;
        value.conditions(1).id = 'A';
        fails(@() load_value(value), 'sootMosaic:CONFIG_MERGE:DuplicateId');
        value.conditions(2).id = 'A';
        fails(@() load_value(value), 'sootMosaic:CONFIG_MERGE:DuplicateId');
        entries = num2cell(base.conditions);
        entries{2}.note_value = 1;
        value = base;
        value.conditions = entries;
        fails(@() load_value(value, struct('Strict', false)), ...
            [loader 'InconsistentConditions']);
        fails(@() load_value(put(base, 'figures', 5)), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        fails(@() load_value(put(base, 'fits.experimental_rho_eff_vs_dm', [])), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        fails(@() load_value(set_value(base, 'figures.show_raw_simulation', 1)), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        fails(@() load_value(set_value(base, 'conditions[].enabled', [])), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        fails(@() load_value(put(base, 'config_version', 2)), ...
            'sootMosaic:CONFIG_READ:UnsupportedVersion');
        fails(@() load_text('{"sources":'), 'sootMosaic:CONFIG_READ:InvalidJSON');
        fails(@() load_text(strrep(jsonencode(base), '"physics":{}', ...
            '"physics":{"_x":1}')), 'sootMosaic:CONFIG_READ:InvalidName');
    end

    function sources()
        names_ = {'ld2', 'tem', 'effective_density'};
        for n = 1:numel(names_)
            value = base;
            value.sources.(names_{n}) = struct('source_id', 'fixture');
            cfg = load_value(value);
            check(isequal(cfg.sources.(names_{n}), struct('source_id', 'fixture')));
            check(isequal(cfg.si.sources.(names_{n}), cfg.sources.(names_{n})));
            value.sources.(names_{n}) = struct('source_id', 'fixture', ...
                'url', '', 'doi', [], 'cache_file', 'cache.mat');
            cfg = load_value(value);
            src = cfg.sources.(names_{n});
            check(isempty(src.url) && ischar(src.url) && ...
                isempty(src.doi) && ischar(src.doi) && ~isfield(src, 'sha256'));
            check(strcmp(src.cache_file, canonical(fullfile(task_dir, 'cache.mat'))));
            for key = {'id', 'file', 'variables'}
                value = base;
                value.sources.(names_{n}) = rmfield( ...
                    value.sources.(names_{n}), key{1});
                reason = 'MissingText';
                if strcmp(key{1}, 'variables'), reason = 'MissingSourceVariables'; end
                fails(@() load_value(value), ...
                    ['sootMosaic:LOAD_MAIN_VALID_CONFIG:' reason]);
            end
            value = base;
            value.sources.(names_{n}) = rmfield(value.sources.(names_{n}), ...
                {'url', 'doi', 'sha256', 'cache_file'});
            src = load_value(value).sources.(names_{n});
            check(all(cellfun(@(k) ischar(src.(k)) && isempty(src.(k)), ...
                {'url', 'doi', 'sha256', 'cache_file'})));
            value.sources.(names_{n}).doi = 12;
            value.sources.(names_{n}).url = {'u'};
            src = load_value(value).sources.(names_{n});
            check(strcmp(src.doi, char(12)) && strcmp(src.url, 'u'));
        end
    end

    function fraction_check()
        id = 'sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLD2FractionMapping';
        unchecked = 'sootMosaic:LOAD_MAIN_VALID_CONFIG:LD2FractionsUnchecked';
        lastwarn('', '');
        cfg = load_value(base);
        [~, warned] = lastwarn;
        check(isempty(warned) && isequal(cfg.conditions(2).ld2_fractions, [0.1 0.05]));
        % Tolerance max(1e-12, 1e-9 times the fraction) of the run
        within = set_value(base, 'conditions[].ld2_fractions', 1 + 9e-10);
        check(load_value(within).conditions(1).ld2_fractions == 1 + 9e-10);
        fails(@() load_value(set_value(base, 'conditions[].ld2_fractions', ...
            1 + 1.1e-9)), id);
        fails(@() load_value(set_value(base, 'conditions[].ld2_fractions', ...
            [1 0.3])), id);
        small = base;
        small.conditions(1).ld2_fractions = 0.05 + 4e-11;
        load_value(small);
        % A disabled condition is not mapped by the run and not checked
        value = base;
        value.conditions(3).ld2_fractions = 0.3;
        load_value(value);
        value.conditions(3).enabled = true;
        value.conditions(3).include.rho_eff_vs_dm = true;
        fails(@() load_value(value), id);
        % Repeated snapshot fractions match more than one entry
        twice = fullfile(folder, 'ld2_twice.mat');
        save_variables(twice, struct('r_n_agg', [1.0, 0.1, 0.1]));
        value = set_value(base, 'sources.ld2.file', twice);
        message_text = caught_message(@() load_value(value), id);
        check(contains(message_text, 'matches 2'));
        absolute = fullfile(folder, 'ld2_small.mat');
        save_variables(absolute, struct('r_n_agg', [1, 1e-13]));
        value = set_value(base, 'sources.ld2.file', absolute);
        value.conditions(1).ld2_fractions = [1, 5e-13];
        value.conditions(2).ld2_fractions = 1;
        load_value(value);
        % The cache file stands in for a missing product file
        value = base;
        value.sources.ld2.file = fullfile(folder, 'missing.mat');
        value.sources.ld2.cache_file = twice;
        message_text = caught_message(@() load_value(value), id);
        check(contains(message_text, 'ld2_twice.mat'));
        % Products not named on disk leave the check to the run
        not_mat = fullfile(folder, 'not_mat.mat');
        write_text(not_mat, 'text');
        no_fraction = fullfile(folder, 'no_fraction.mat');
        save_variables(no_fraction, struct('parsdata', 1));
        cell_fraction = fullfile(folder, 'cell_fraction.mat');
        save_variables(cell_fraction, struct('r_n_agg', {{1}}));
        unread = {set_value(base, 'sources.ld2.file', fullfile(folder, 'missing.mat')), ...
            set_value(base, 'sources.ld2.file', not_mat), ...
            set_value(base, 'sources.ld2.file', no_fraction), ...
            set_value(base, 'sources.ld2.file', cell_fraction), ...
            set_value(base, 'sources.ld2', struct('source_id', 'fixture'))};
        for n = 1:numel(unread)
            stale = unread{n};
            if isfield(stale.sources.ld2, 'cache_file')
                stale.sources.ld2.cache_file = '';
            end
            stale.conditions(1).ld2_fractions = 0.3;
            lastwarn('', '');
            cfg = load_value(stale);
            [~, warned] = lastwarn;
            check(strcmp(warned, unchecked) && cfg.conditions(1).ld2_fractions == 0.3);
        end
        lastwarn('', '');
        value = set_value(base, 'sources.ld2.file', fullfile(folder, 'missing.mat'));
        value.sources.ld2.cache_file = '';
        [value.conditions.enabled] = deal(false);
        load_value(value);
        [~, warned] = lastwarn;
        check(isempty(warned));
    end
end

function paths = expected_paths()
source_keys = {'source_id', 'id', 'file', 'url', 'doi', 'sha256', ...
    'cache_file', 'variables'};
fit_keys = {'enabled', 'degree', 'resolution', 'posterior_samples', ...
    'rng_seed', 'credible_level', 'show_band', 'x_transform', ...
    'y_transform', 'slope_offset', 'prior_mu', 'prior_v_scale', ...
    'prior_a', 'prior_b'};
paths = [{'config_version'; 'extends'; 'config_file'; 'model_profile'; ...
    'model_overrides'; 'model'; 'model_params'; 'model_source'; 'sources'; ...
    'sources.ld2'; 'sources.tem'; 'sources.effective_density'}; ...
    prefixed('sources.ld2', source_keys); ...
    prefixed('sources.tem', source_keys); ...
    prefixed('sources.effective_density', source_keys); ...
    {'conditions'}; prefixed('conditions[]', {'id', 'label', 'enabled', ...
    'include', 'include.dpp_vs_da', 'include.rho_eff_vs_dm', ...
    'tem_entry_id', 'effective_density_condition_id', 'ld2_fractions', ...
    'style', 'style.color', 'style.experimental_color', ...
    'style.experimental_marker_face_color', ...
    'style.experimental_marker_line_width', 'style.simulation_marker', ...
    'style.experimental_marker', 'style.simulation_marker_size', ...
    'style.experimental_marker_size', 'style.fit_line_width'}); ...
    {'physics'; 'physics.material_density_kg_m3'; 'references'; ...
    'references.dpp_vs_da'; 'references.rho_eff_vs_dm'}; ...
    prefixed('references.dpp_vs_da', {'enabled', 'label', 'exponent', ...
    'value_at_100_nm', 'color', 'line_style', 'line_width'}); ...
    prefixed('references.rho_eff_vs_dm', {'enabled', 'label', ...
    'mass_mobility_exponent', 'value_at_100_nm', 'color', 'line_style', ...
    'line_width'}); ...
    {'fits'; 'fits.dpp_vs_da'; 'fits.rho_eff_vs_dm'; ...
    'fits.experimental_rho_eff_vs_dm'}; ...
    prefixed('fits.dpp_vs_da', fit_keys); ...
    prefixed('fits.rho_eff_vs_dm', fit_keys); ...
    prefixed('fits.experimental_rho_eff_vs_dm', {'enabled', 'degree', ...
    'support_mode', 'support_limits_nm', 'confidence_level'}); ...
    {'figures'}; prefixed('figures', {'visible', 'show_raw_simulation', ...
    'show_tem_error_bars', 'simulation_marker_alpha', 'band_alpha', ...
    'axis_line_width', 'axes', 'font', 'legend', 'dpp_vs_da', ...
    'rho_eff_vs_dm'}); ...
    prefixed('figures.axes', {'box', 'layer', 'tick_length', ...
    'tick_label_rotation', 'label_position_mode', 'x_label_offset', ...
    'y_label_offset'}); ...
    prefixed('figures.font', {'family', 'fallback', 'axis_size', ...
    'label_size', 'legend_size', 'title_size', 'weight', 'interpreter'}); ...
    prefixed('figures.legend', {'location', 'columns', 'box', ...
    'orientation', 'interpreter', 'font_family', 'font_fallback', ...
    'font_weight'}); ...
    prefixed('figures.dpp_vs_da', {'position', 'x_limits', 'y_limits'}); ...
    prefixed('figures.rho_eff_vs_dm', {'position', 'x_limits', 'y_limits'}); ...
    {'outputs'}; prefixed('outputs', {'root', 'export', 'pdf', 'png', ...
    'png_resolution', 'png_source', 'save_figures', ...
    'experimental_summary_csv'})];
end

function paths = required_paths()
fit_keys = {'enabled', 'degree', 'resolution', 'posterior_samples', ...
    'rng_seed', 'credible_level', 'show_band', 'x_transform', ...
    'y_transform', 'slope_offset', 'prior_v_scale', 'prior_a', 'prior_b'};
paths = [{'sources'; 'sources.ld2'; 'sources.tem'; ...
    'sources.effective_density'; 'conditions'}; ...
    prefixed('conditions[]', {'id', 'label', 'enabled', 'include', ...
    'include.dpp_vs_da', 'include.rho_eff_vs_dm', 'style', 'style.color', ...
    'style.simulation_marker', 'style.experimental_marker', ...
    'style.simulation_marker_size', 'style.experimental_marker_size', ...
    'style.fit_line_width'}); ...
    {'physics'; 'references'; 'references.dpp_vs_da'; ...
    'references.rho_eff_vs_dm'}; ...
    prefixed('references.dpp_vs_da', {'enabled', 'label', 'exponent', ...
    'value_at_100_nm', 'color', 'line_style', 'line_width'}); ...
    prefixed('references.rho_eff_vs_dm', {'enabled', 'label', ...
    'mass_mobility_exponent', 'value_at_100_nm', 'color', 'line_style', ...
    'line_width'}); ...
    {'fits'; 'fits.dpp_vs_da'; 'fits.rho_eff_vs_dm'}; ...
    prefixed('fits.dpp_vs_da', fit_keys); ...
    prefixed('fits.rho_eff_vs_dm', fit_keys); ...
    prefixed('fits.experimental_rho_eff_vs_dm', {'enabled', 'degree', ...
    'support_mode', 'confidence_level'}); ...
    {'figures'}; prefixed('figures', {'visible', 'show_raw_simulation', ...
    'show_tem_error_bars', 'simulation_marker_alpha', 'band_alpha', ...
    'font', 'legend', 'dpp_vs_da', 'rho_eff_vs_dm'}); ...
    prefixed('figures.font', {'family', 'fallback', 'axis_size', ...
    'label_size', 'legend_size', 'weight', 'interpreter'}); ...
    prefixed('figures.legend', {'location', 'columns', 'box', ...
    'orientation'}); ...
    {'figures.dpp_vs_da.position'; 'figures.rho_eff_vs_dm.position'; ...
    'outputs'}; prefixed('outputs', {'root', 'export', 'pdf', 'png', ...
    'png_resolution', 'save_figures'})];
end

function contract = numeric_contract()
% Columns: path, type, unit, conversion, min, max, valid value, SI factor
contract = { ...
    'conditions[].ld2_fractions', 'vector', 'fractions', 'double', [], [], [1 0.4], 1; ...
    'conditions[].style.experimental_marker_line_width', 'number', 'pt', 'double', [], [], 2, 1; ...
    'conditions[].style.simulation_marker_size', 'number', 'presentation', 'double', [], [], 3, 1; ...
    'conditions[].style.experimental_marker_size', 'number', 'presentation', 'double', [], [], 40, 1; ...
    'conditions[].style.fit_line_width', 'number', 'pt', 'double', [], [], 2, 1; ...
    'physics.material_density_kg_m3', 'number', 'kg/m3', 'double', [], [], 1800, 1; ...
    'references.dpp_vs_da.exponent', 'number', 'none', 'double', [], [], -0.5, 1; ...
    'references.dpp_vs_da.value_at_100_nm', 'number', 'nm', 'double', [], [], 18, 1e-9; ...
    'references.dpp_vs_da.line_width', 'number', 'pt', 'double', [], [], 2, 1; ...
    'references.rho_eff_vs_dm.mass_mobility_exponent', 'number', 'none', 'double', [], [], 2.5, 1; ...
    'references.rho_eff_vs_dm.value_at_100_nm', 'number', 'kg/m3', 'double', [], [], 500, 1; ...
    'references.rho_eff_vs_dm.line_width', 'number', 'pt', 'double', [], [], 2, 1; ...
    'fits.dpp_vs_da.degree', 'integer', 'none', 'double', 1, [], 2, 1; ...
    'fits.dpp_vs_da.resolution', 'integer', 'points', 'double', 2, [], 50, 1; ...
    'fits.dpp_vs_da.posterior_samples', 'integer', 'count', 'double', 100, [], 120, 1; ...
    'fits.dpp_vs_da.rng_seed', 'integer', 'none', 'double', 0, [], 7, 1; ...
    'fits.dpp_vs_da.credible_level', 'number', 'none', 'double', [], [], 0.9, 1; ...
    'fits.dpp_vs_da.slope_offset', 'number', 'none', 'double', [], [], -2, 1; ...
    'fits.dpp_vs_da.prior_mu', 'vector', 'none', 'double', [], [], [1 2], 1; ...
    'fits.dpp_vs_da.prior_v_scale', 'number', 'none', 'double', [], [], 50, 1; ...
    'fits.dpp_vs_da.prior_a', 'number', 'none', 'double', [], [], 2, 1; ...
    'fits.dpp_vs_da.prior_b', 'number', 'none', 'double', [], [], 3, 1; ...
    'fits.rho_eff_vs_dm.degree', 'integer', 'none', 'double', 1, [], 3, 1; ...
    'fits.rho_eff_vs_dm.resolution', 'integer', 'points', 'double', 2, [], 60, 1; ...
    'fits.rho_eff_vs_dm.posterior_samples', 'integer', 'count', 'double', 100, [], 110, 1; ...
    'fits.rho_eff_vs_dm.rng_seed', 'integer', 'none', 'double', 0, [], 8, 1; ...
    'fits.rho_eff_vs_dm.credible_level', 'number', 'none', 'double', [], [], 0.8, 1; ...
    'fits.rho_eff_vs_dm.slope_offset', 'number', 'none', 'double', [], [], 4, 1; ...
    'fits.rho_eff_vs_dm.prior_mu', 'vector', 'none', 'double', [], [], [3 4 5], 1; ...
    'fits.rho_eff_vs_dm.prior_v_scale', 'number', 'none', 'double', [], [], 60, 1; ...
    'fits.rho_eff_vs_dm.prior_a', 'number', 'none', 'double', [], [], 4, 1; ...
    'fits.rho_eff_vs_dm.prior_b', 'number', 'none', 'double', [], [], 5, 1; ...
    'fits.experimental_rho_eff_vs_dm.degree', 'integer', 'none', 'double', 1, [], 1, 1; ...
    'fits.experimental_rho_eff_vs_dm.support_limits_nm', 'vector', 'nm', 'double', [], [], [80 200], 1e-9; ...
    'fits.experimental_rho_eff_vs_dm.confidence_level', 'number', 'none', 'double', [], [], 0.9, 1; ...
    'figures.simulation_marker_alpha', 'number', 'none', 'double', 0, 1, 0.5, 1; ...
    'figures.band_alpha', 'number', 'none', 'double', 0, 1, 1, 1; ...
    'figures.axis_line_width', 'number', 'pt', 'double', [], [], 2, 1; ...
    'figures.axes.tick_length', '2 numbers', 'normalized units', 'double', 0, [], [0.01 0.03], 1; ...
    'figures.axes.tick_label_rotation', 'number', 'presentation', 'double', 0, 360, 45, 1; ...
    'figures.axes.x_label_offset', 'number', 'normalized units', 'double', [], [], 0.1, 1; ...
    'figures.axes.y_label_offset', 'number', 'normalized units', 'double', [], [], 0.2, 1; ...
    'figures.font.axis_size', 'number', 'pt', 'double', [], [], 11, 1; ...
    'figures.font.label_size', 'number', 'pt', 'double', [], [], 12, 1; ...
    'figures.font.legend_size', 'number', 'pt', 'double', [], [], 10, 1; ...
    'figures.font.title_size', 'any', 'pt', '', [], [], 14, 1; ...
    'figures.legend.columns', 'integer', 'count', 'double', 1, [], 2, 1; ...
    'figures.dpp_vs_da.position', '4 numbers', 'figure units', 'double', [], [], [1 2 3 4], 1; ...
    'figures.dpp_vs_da.x_limits', 'vector', 'presentation', 'double', [], [], [10 500], 1; ...
    'figures.dpp_vs_da.y_limits', 'vector', 'presentation', 'double', [], [], [5 50], 1; ...
    'figures.rho_eff_vs_dm.position', '4 numbers', 'figure units', 'double', [], [], [5 6 7 8], 1; ...
    'figures.rho_eff_vs_dm.x_limits', 'vector', 'presentation', 'double', [], [], [20 600], 1; ...
    'figures.rho_eff_vs_dm.y_limits', 'vector', 'presentation', 'double', [], [], [100 900], 1; ...
    'outputs.png_resolution', 'integer', 'dpi', 'double', 1, [], 300, 1};
end

function defaults = default_contract()
defaults = { ...
    'config_version', 1; ...
    'conditions[].tem_entry_id', ''; ...
    'conditions[].effective_density_condition_id', ''; ...
    'conditions[].ld2_fractions', []; ...
    'conditions[].style.experimental_marker_face_color', 'none'; ...
    'conditions[].style.experimental_marker_line_width', 1.2; ...
    'fits.dpp_vs_da.prior_mu', []; ...
    'fits.rho_eff_vs_dm.prior_mu', []; ...
    'fits.experimental_rho_eff_vs_dm', struct('enabled', false, ...
    'degree', 1, 'support_mode', 'common', 'support_limits_nm', [], ...
    'confidence_level', 0.95); ...
    'fits.experimental_rho_eff_vs_dm.support_limits_nm', []; ...
    'figures.axis_line_width', 1; ...
    'figures.axes.box', true; ...
    'figures.axes.layer', 'top'; ...
    'figures.axes.tick_length', [0.02 0.02]; ...
    'figures.axes.tick_label_rotation', 0; ...
    'figures.axes.label_position_mode', 'auto'; ...
    'figures.axes.x_label_offset', 0.055; ...
    'figures.axes.y_label_offset', 0.075; ...
    'figures.legend.interpreter', 'none'; ...
    'figures.dpp_vs_da.x_limits', []; ...
    'figures.dpp_vs_da.y_limits', []; ...
    'figures.rho_eff_vs_dm.x_limits', []; ...
    'figures.rho_eff_vs_dm.y_limits', []; ...
    'outputs.png_source', 'figure'; ...
    'outputs.experimental_summary_csv', ...
    'experimental_mass_mobility_summary.csv'};
end

function value = default_axes()
value = struct('box', true, 'layer', 'top', 'tick_length', [0.02 0.02], ...
    'tick_label_rotation', 0, 'label_position_mode', 'auto', ...
    'x_label_offset', 0.055, 'y_label_offset', 0.075);
end

function model = current_model()
model = struct('profile', 'current', 'fluid_properties', 'sutherland', ...
    'slip_correction', 'kim2005', 'mobility', 'interp', ...
    'continuum_diameter', 'sorensen_backbone', 'root_solve', 'bracketed', ...
    'projection', 'isotropic', 'proj_cache', true, 'proj_points', 1024, ...
    'proj_orientations', 64, 'proj_replicates', 4, 'proj_tol', 0.01, ...
    'knudsen_diagnostics', true, 'initial_velocity', 'maxwell_boltzmann');
end

function model = article1_model()
model = struct('profile', 'article1_7658971', 'fluid_properties', 'room', ...
    'slip_correction', 'per_caller_7658971', 'mobility', 'interp', ...
    'continuum_diameter', 'fixed_075dg', 'root_solve', ...
    'start_point_7658971', 'projection', 'euler_7658971', ...
    'proj_cache', false, 'proj_points', 100, 'proj_orientations', 5, ...
    'proj_replicates', 1, 'proj_tol', Inf, 'knudsen_diagnostics', false, ...
    'initial_velocity', 'mean_speed_7658971');
end

function paths = prefixed(prefix, keys)
paths = cellfun(@(key) [prefix '.' key], keys(:), 'UniformOutput', false);
end

function value = row_field(row, name)
value = [];
if isfield(row, name), value = row.(name); end
end

function cfg = without_records(cfg)
cfg = rmfield(cfg, 'provenance');
end

function path_value = canonical(path_value)
path_value = char(java.io.File(path_value).getCanonicalPath());
end

function value = set_value(value, path, item)
% Setting a key, in the first condition for conditions[] paths
if startsWith(path, 'conditions[].')
    entries = num2cell(value.conditions);
    if iscell(value.conditions), entries = value.conditions; end
    entries{1} = put(entries{1}, path(14:end), item);
    value.conditions = entries;
else
    value = put(value, path, item);
end
end

function value = drop_value(value, path)
if startsWith(path, 'conditions[].')
    entries = num2cell(value.conditions);
    entries{1} = drop(entries{1}, path(14:end));
    value.conditions = entries;
elseif startsWith(path, 'conditions[]')
    value = drop(value, 'conditions');
else
    value = drop(value, path);
end
end

function value = get_value(cfg, path)
if startsWith(path, 'conditions[].')
    value = get(cfg.conditions(1), path(14:end));
else
    value = get(cfg, path);
end
end

function check(ok)
if ~ok
    stack = dbstack;
    error('sootMosaic:QA:ValidConfigFailed', 'Assertion failed at line %d.', ...
        stack(min(2, numel(stack))).line);
end
end

function fails(action, expected)
caught = false;
try
    action();
catch err
    caught = strcmp(err.identifier, expected);
    if ~caught
        error('sootMosaic:QA:ValidConfigFailed', ...
            'Expected %s; received %s.', expected, err.identifier);
    end
end
check(caught);
end

function text = caught_message(action, expected)
text = '';
try
    action();
catch err
    if ~strcmp(err.identifier, expected)
        error('sootMosaic:QA:ValidConfigFailed', ...
            'Expected %s; received %s.', expected, err.identifier);
    end
    text = err.message;
end
check(~isempty(text));
end

function save_variables(file, values)
save(file, '-struct', 'values');
end

function value = put(value, path, item)
parts = strsplit(path, '.');
key = parts{1};
if isscalar(parts)
    value.(key) = item;
else
    if ~isfield(value, key), value.(key) = struct(); end
    value.(key) = put(value.(key), strjoin(parts(2:end), '.'), item);
end
end

function value = get(value, path)
parts = strsplit(path, '.');
for k = 1:numel(parts), value = value.(parts{k}); end
end

function value = drop(value, path)
parts = strsplit(path, '.');
if isscalar(parts)
    if isfield(value, parts{1}), value = rmfield(value, parts{1}); end
else
    value.(parts{1}) = drop(value.(parts{1}), strjoin(parts(2:end), '.'));
end
end

function paths = key_paths(value, prefix)
paths = cell(0, 1);
if ~isstruct(value), return; end
if ~isscalar(value)
    groups = arrayfun(@(entry) key_paths(entry, [prefix '[]']), value(:), ...
        'UniformOutput', false);
    paths = unique(vertcat(groups{:}));
    return
end
names = fieldnames(value);
groups = cell(numel(names), 1);
for k = 1:numel(names)
    if isempty(prefix)
        child_path = names{k};
    else
        child_path = [prefix '.' names{k}];
    end
    groups{k} = [{child_path}; key_paths(value.(names{k}), child_path)];
end
if ~isempty(groups), paths = vertcat(groups{:}); end
end

function write_text(file, text)
fid = fopen(file, 'w');
if fid < 0, error('sootMosaic:QA:ValidConfigFailed', 'Cannot write fixture.'); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, text, 'char');
end

function restore_state(state, message, id, primary, fallback)
warning(state);
lastwarn(message, id);
setenv('SOOTMOSAIC_MAIN_VALID_CONFIG', primary);
setenv('PFAL_MAIN_VALID_CONFIG', fallback);
end
