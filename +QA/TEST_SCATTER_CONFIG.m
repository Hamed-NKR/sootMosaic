function report = TEST_SCATTER_CONFIG()
% "TEST_SCATTER_CONFIG" checks scatter configuration and source reading rules.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Structure array with name and pass. Fixtures use tempname...
%         ...and are removed on exit. A failed case raises...
%         ...sootMosaic:QA:ScatterConfigFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:ScatterConfigFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
primary = getenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG');
fallback = getenv('PFAL_MAIN_SCATTER_CONFIG');
restore = onCleanup(@() restore_state(state, warn_message, warn_id, ...
    primary, fallback));
warning('on', 'sootMosaic:CONFIG_READ:UnknownKey');
root = fileparts(fileparts(mfilename('fullpath')));
example = fullfile(root, 'config', 'main_scatter', ...
    'main_scatter_config.example.json');
dictionary = fullfile(root, 'config', 'main_scatter', ...
    'main_scatter.keys.json');
raw = jsondecode(fileread(example));
rows = jsondecode(fileread(dictionary));
if isstruct(rows), rows = num2cell(rows); end
file = fullfile(folder, 'task.json');
strict = struct('Strict', true);
tests = {@coverage, @complete_inputs, @selectors, @numeric_inputs, ...
    @task_options, @optional_sources, @registry_sources, @overlays, ...
    @profiles, ...
    @unknowns, @versions, @invalid_values, @payload_checks};
names = {'dictionary coverage both ways', 'complete config inputs', ...
    'selector precedence and default path', 'numeric conversions and SI', ...
    'mode defaults, normalization and seed bounds', ...
    'optional source presence and empty values', ...
    'registry and inline data', ...
    'relative overlays and provenance', ...
    'LD1 profile metadata and overrides', ...
    'unknown keys and comments', 'versions and member names', ...
    'required fields and numeric checks', 'payload and download checks'};
pass = false(size(tests));
for k = 1:numel(tests)
    try
        tests{k}();
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:ScatterConfigFailed', '%d cases failed.', sum(~pass));
end

    function cfg = load_value(value, controls)
        if nargin < 2, controls = strict; end
        write_text(file, jsonencode(value));
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, controls);
    end

    function coverage()
        % Matching the consumer contract independently of dictionary rows
        expected = {'config_version', 'config_file', 'extends', ...
            'model_profile', ...
            'model_overrides', 'dataset', 'dataset.source_id', ...
            'dataset.id', 'dataset.file', 'dataset.variable', ...
            'dataset.variables', ...
            'dataset.url', 'dataset.doi', 'dataset.sha256', ...
            'dataset.cache_file', 'dataset.config_dir', 'correlation', ...
            'correlation.universal', 'correlation.universal.D_TEM', ...
            'correlation.universal.dpp100', ...
            'correlation.universal.da_lim_uc', ...
            'correlation.universal.n_da_uc', 'correlation.brasil', ...
            'correlation.brasil.alpha_a', 'correlation.brasil.k_a', ...
            'correlation.brasil.npp_lim_bc', ...
            'correlation.brasil.n_npp_uc', 'distribution', ...
            'distribution.gm_da', 'distribution.gsd_da', ...
            'distribution.gm_dpp', 'distribution.gsd_dpp', 'sampling', ...
            'sampling.cn_scat', 'projection', ...
            'projection.n_mc', 'projection.n_ang', 'options', ...
            'options.rng_seed', 'options.opt_scale', 'options.opts_nppcor'};
        paths = cellfun(@(r) r.path, rows, 'UniformOutput', false);
        check(numel(paths) == numel(unique(paths)));
        check(isequal(sort(paths(:)), sort(expected(:))));
        check(all(ismember(key_paths(raw, ''), paths)));
        for n = 1:numel(rows)
            row = rows{n};
            check(all(isfield(row, ...
                {'type', 'unit', 'status', 'since', ...
                'reader', 'reading_rule'})));
            readers = strsplit(row.reader, ', ');
            for j = 1:numel(readers)
                check(~isempty(which(['UTILS.' readers{j}])) || ...
                    isfile(fullfile(root, [readers{j} '.m'])));
            end
        end
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(example, strict);
        check(cfg.projection.n_mc == 100 && cfg.projection.n_ang == 5);
        text = fileread(fullfile(root, 'main_scatter_v8.m'));
        groups = {'correlation.universal', 'correlation.brasil', ...
            'distribution', 'sampling', 'projection', 'options'};
        variables = {'cfg_uc', 'cfg_bc', 'cfg_dist', ...
            'cfg_sampling', 'cfg_projection', 'cfg_options'};
        for n = 1:numel(groups)
            check(contains(text, ['cfg_scatter.' groups{n}]));
            tokens = regexp(text, ...
                [variables{n} '\.([A-Za-z]\w*)'], 'tokens');
            actual = unique(cellfun(@(x) [groups{n} '.' x{1}], ...
                tokens, 'UniformOutput', false));
            listed = paths(startsWith(paths, [groups{n} '.']));
            check(isequal(sort(actual(:)), sort(listed(:))));
        end
        check(contains(text, 'cfg_scatter.config_file'));
        text = fileread(fullfile(root, '+UTILS', 'LOAD_DATASET_SOURCE.m'));
        tokens = regexp(text, ...
            'required_text\(source_cfg, ''(\w+)''', 'tokens');
        tokens = [tokens, regexp(text, ...
            'option\(source_cfg, ''(\w+)''', 'tokens')];
        optional = regexp(text, 'fields = \{([^}]+)\}', 'tokens', 'once');
        tokens = [tokens, regexp(optional{1}, '''(\w+)''', 'tokens')];
        actual = unique(cellfun(@(x) ['dataset.' x{1}], ...
            tokens, 'UniformOutput', false));
        % Checking retained source metadata outside the scalar data branch
        check(contains(text, 'inline = rmfield(source_cfg, ''source_id'')'));
        check(contains(text, 'UTILS.CONFIG_MERGE(entry, inline'));
        actual = [actual, {'dataset.variables'}];
        listed = paths(startsWith(paths, 'dataset.'));
        check(isequal(sort(actual(:)), sort(listed(:))));
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            index = find(strcmp(paths, contract{n, 1}));
            check(isscalar(index));
            row = rows{index};
            check(strcmp(row.type, contract{n, 2}));
            check(strcmp(row.unit, contract{n, 3}));
            check(isfield(row, 'coerce') && ...
                strcmp(row.coerce, contract{n, 4}));
            if strcmp(contract{n, 2}, '2 numbers')
                check(isfield(row, 'row_vector') && row.row_vector);
            end
            if ~strcmp(contract{n, 1}, 'options.rng_seed')
                check(row.required && ~isfield(row, 'default'));
                check(~isfield(row, 'min') && ~isfield(row, 'max'));
            else
                check(isequal(row.default, []) && row.min == 0 && ...
                    row.max == 4294967295);
            end
        end
        retained = {'dataset.source_id', 'dataset.variables', ...
            'dataset.url', 'dataset.doi', 'dataset.sha256', ...
            'dataset.cache_file', 'dataset.config_dir', 'config_file'};
        for n = 1:numel(retained)
            row = rows{strcmp(paths, retained{n})};
            check(strcmp(row.type, 'any') && ~isfield(row, 'coerce') && ...
                ~isfield(row, 'default'));
            check(row.native_json && row.open);
        end
        for key = {'dataset.id', 'dataset.file', 'dataset.variable'}
            row = rows{strcmp(paths, key{1})};
            check(strcmp(row.type, 'any') && ~isfield(row, 'coerce'));
            check(row.native_json && row.open);
        end
        row = rows{strcmp(paths, 'options')};
        check(row.required && row.defer_defaults);
        keys = {'options.opt_scale', 'options.opts_nppcor'};
        defaults = {'bivariate', 'off'};
        allowed = {{'bivariate'; 'sequential'; 'ideal'}, {'on'; 'off'}};
        for n = 1:numel(keys)
            row = rows{strcmp(paths, keys{n})};
            check(strcmp(row.type, 'text') && strcmp(row.coerce, 'char'));
            check(strcmp(row.default, defaults{n}));
            check(row.empty_default && row.normalize_text);
            check(isequal(row.allowed(:), allowed{n}));
        end
    end

    function complete_inputs()
        value = rmfield(raw, {'config_version', 'model_profile'});
        cfg = load_value(value);
        expected = value;
        expected.correlation.universal.da_lim_uc = ...
            reshape(expected.correlation.universal.da_lim_uc, 1, []);
        expected.correlation.brasil.npp_lim_bc = ...
            reshape(expected.correlation.brasil.npp_lim_bc, 1, []);
        expected.config_file = file;
        expected.dataset.config_dir = folder;
        additions = {'config_version', 'si', 'provenance', ...
            'model_profile', 'model_overrides', 'model', ...
            'model_params', 'model_source'};
        check(isequal(rmfield(cfg, additions), expected));
        other = UTILS.LOAD_MAIN_SCATTER_CONFIG(string(file), strict);
        check(isequaln(cfg, other));
        % Comparing singleton object arrays with ordinary object inputs
        sections = {'dataset', 'correlation', 'correlation.universal', ...
            'correlation.brasil', 'distribution', 'sampling', ...
            'projection', 'options'};
        ordinary = rmfield(cfg, 'provenance');
        for n = 1:numel(sections)
            section = get_path(value, sections{n});
            wrapped = put_path(value, sections{n}, {section});
            other = load_value(wrapped);
            check(isequaln(rmfield(other, 'provenance'), ordinary));
        end
        other = load_value({value});
        check(isequaln(rmfield(other, 'provenance'), ordinary));
        empty_options = value;
        empty_options.options = struct();
        ordinary = load_value(empty_options);
        empty_options.options = {struct()};
        check(contains(jsonencode(empty_options), '"options":[{}]'));
        other = load_value(empty_options);
        check(isequaln(rmfield(other, 'provenance'), ...
            rmfield(ordinary, 'provenance')));
        check(isempty(other.options.rng_seed));
        check(strcmp(other.options.opt_scale, 'bivariate'));
        check(strcmp(other.options.opts_nppcor, 'off'));
        value.dataset.config_dir = 'ignored';
        other = load_value(value);
        check(strcmp(other.dataset.config_dir, folder));
        text = strrep(jsonencode(value), ...
            '"config_dir":"ignored"', '"config_dir":{}');
        check(contains(text, '"config_dir":{}'));
        write_text(file, text);
        other = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
        check(strcmp(other.dataset.config_dir, fileparts(file)));
        check(strcmp(other.si.dataset.config_dir, fileparts(file)));
        value.config_file = struct();
        other = load_value(value);
        check(strcmp(other.config_file, file));
        check(strcmp(other.si.config_file, file));
        value.config_file = struct('unused', 7);
        value.dataset.config_dir = struct('unused', true);
        other = load_value(value);
        check(strcmp(other.config_file, file));
        check(strcmp(other.si.config_file, file));
        check(strcmp(other.dataset.config_dir, folder));
        check(strcmp(other.si.dataset.config_dir, folder));
        value = rmfield(value, 'config_file');
        value.dataset = rmfield(value.dataset, 'config_dir');
        write_text(file, jsonencode(value));
        current = pwd;
        search_path = path;
        restore_path = onCleanup(@() path(search_path));
        restore_dir = onCleanup(@() cd(current));
        addpath(root, '-begin');
        cd(folder);
        check(strcmp(which('UTILS.LOAD_MAIN_SCATTER_CONFIG'), ...
            fullfile(root, '+UTILS', 'LOAD_MAIN_SCATTER_CONFIG.m')));
        relative = UTILS.LOAD_MAIN_SCATTER_CONFIG('task.json', strict);
        check(strcmp(relative.config_file, 'task.json'));
        check(isempty(relative.dataset.config_dir));
        relative.config_file = file;
        relative.si.config_file = file;
        relative.dataset.config_dir = folder;
        relative.si.dataset.config_dir = folder;
        check(isequaln(cfg, relative));
    end

    function selectors()
        a = load_value(raw);
        second = fullfile(folder, 'second.json');
        value = raw;
        value.sampling.cn_scat = 0.25;
        write_text(second, jsonencode(value));
        setenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG', file);
        setenv('PFAL_MAIN_SCATTER_CONFIG', second);
        b = UTILS.LOAD_MAIN_SCATTER_CONFIG;
        check(isequaln(a, b));
        b = UTILS.LOAD_MAIN_SCATTER_CONFIG([], strict);
        check(isequaln(a, b));
        b = UTILS.LOAD_MAIN_SCATTER_CONFIG(second, strict);
        check(b.sampling.cn_scat == 0.25);
        setenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG', '');
        b = UTILS.LOAD_MAIN_SCATTER_CONFIG('', strict);
        check(b.sampling.cn_scat == 0.25);
        setenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG', fullfile(folder, 'absent'));
        fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG, ...
            'sootMosaic:LOAD_MAIN_SCATTER_CONFIG:MissingConfig');
        setenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG', '');
        setenv('PFAL_MAIN_SCATTER_CONFIG', '');
        local = fullfile(root, 'config', 'main_scatter', ...
            'main_scatter_config.local.json');
        if isfile(local)
            b = UTILS.LOAD_MAIN_SCATTER_CONFIG;
            check(strcmp(b.config_file, local));
        else
            fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG, ...
                'sootMosaic:LOAD_MAIN_SCATTER_CONFIG:MissingConfig');
        end
    end

    function numeric_inputs()
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            key = contract{n, 1};
            factor = contract{n, 5};
            values = {true, 'A', 2};
            expected = {1, 65, 2};
            if strcmp(contract{n, 2}, '2 numbers')
                values = {[true false], 'AB', [2; 3]};
                expected = {[1 0], [65 66], [2 3]};
            end
            for j = 1:numel(values)
                value = put_path(raw, key, values{j});
                cfg = load_value(value);
                check(isequal(get_path(cfg, key), expected{j}));
                check(isequal(get_path(cfg.si, key), ...
                    expected{j} .* factor));
            end
        end
        value = raw;
        value.dataset.id = 65;
        cfg = load_value(value);
        check(strcmp(cfg.dataset.id, 'A'));
        for key = {'id', 'file', 'variable'}
            for item = {{''}, {'text'}, [65; 66]}
                value = raw;
                value.dataset.(key{1}) = item{1};
                cfg = load_value(value);
                decoded = jsondecode(jsonencode(value));
                expected_text = char(decoded.dataset.(key{1}));
                check(isequal(cfg.dataset.(key{1}), expected_text));
                check(isequal(cfg.si.dataset.(key{1}), expected_text));
            end
        end
        text = jsonencode(raw);
        text = strrep(text, '"n_mc":100', '"n_mc":[[100]]');
        text = strrep(text, '"cn_scat":0.13', '"cn_scat":[0.13]');
        write_text(file, text);
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
        check(cfg.projection.n_mc == 100 && cfg.sampling.cn_scat == 0.13);
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            if ~strcmp(contract{n, 2}, 'number'), continue; end
            value = put_path(raw, contract{n, 1}, -0.5);
            cfg = load_value(value);
            check(get_path(cfg, contract{n, 1}) == -0.5);
        end
        for number = [0 -1]
            value = put_path(raw, 'correlation.universal.n_da_uc', number);
            cfg = load_value(value);
            check(cfg.correlation.universal.n_da_uc == number);
        end
        % Checking that unmarked dictionary rows retain scalar type checks
        write_text(file, '{"x":[1]}');
        fails(@() UTILS.CONFIG_READ(file, ...
            struct('path', 'x', 'type', 'number')), ...
            'sootMosaic:CONFIG_READ:InvalidType');
    end

    function task_options()
        value = raw;
        value.options = struct();
        cfg = load_value(value);
        check(isempty(cfg.options.rng_seed));
        check(strcmp(cfg.options.opt_scale, 'bivariate'));
        check(strcmp(cfg.options.opts_nppcor, 'off'));
        keys = {'opt_scale', 'opts_nppcor'};
        defaults = {'bivariate', 'off'};
        for n = 1:numel(keys)
            for literal = {'[]', 'null', '""'}
                value = raw;
                value.options.(keys{n}) = 'fixture';
                text = strrep(jsonencode(value), ...
                    ['"' keys{n} '":"fixture"'], ...
                    ['"' keys{n} '":' literal{1}]);
                check(contains(text, ['"' keys{n} '":' literal{1}]));
                write_text(file, text);
                cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
                check(strcmp(cfg.options.(keys{n}), defaults{n}));
                check(strcmp(cfg.si.options.(keys{n}), defaults{n}));
            end
        end
        modes = {'bivariate', 'sequential', 'ideal'};
        corrections = {'on', 'off'};
        for n = 1:numel(modes)
            for j = 1:numel(corrections)
                value = raw;
                value.options.opt_scale = ['  ' upper(modes{n}) '  '];
                value.options.opts_nppcor = ['  ' upper(corrections{j}) '  '];
                cfg = load_value(value);
                check(strcmp(cfg.options.opt_scale, modes{n}));
                check(strcmp(cfg.options.opts_nppcor, corrections{j}));
                value.options.opt_scale = modes(n);
                value.options.opts_nppcor = corrections(j);
                cfg = load_value(value);
                check(strcmp(cfg.options.opt_scale, modes{n}));
                check(strcmp(cfg.options.opts_nppcor, corrections{j}));
            end
        end
        for n = 1:numel(keys)
            for item = {'invalid', '   '}
                value = raw;
                value.options.(keys{n}) = item{1};
                fails(@() load_value(value), ...
                    'sootMosaic:CONFIG_READ:InvalidValue');
            end
        end
        for item = {[], '', 0, 4294967295, true, 'A'}
            value = raw;
            value.options.rng_seed = item{1};
            cfg = load_value(value);
            check(isequal(cfg.options.rng_seed, double(item{1})));
        end
        for literal = {'null', '[7]'}
            text = strrep(jsonencode(raw), '"rng_seed":[]', ...
                ['"rng_seed":' literal{1}]);
            check(contains(text, ['"rng_seed":' literal{1}]));
            write_text(file, text);
            cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
            if strcmp(literal{1}, 'null')
                check(isempty(cfg.options.rng_seed));
            else
                check(cfg.options.rng_seed == 7);
            end
        end
        invalid = {-1, 4294967296, 1.5, [1 2]};
        reasons = {'OutOfRange', 'OutOfRange', ...
            'InvalidInteger', 'InvalidType'};
        for n = 1:numel(invalid)
            value = raw;
            value.options.rng_seed = invalid{n};
            fails(@() load_value(value), ...
                ['sootMosaic:CONFIG_READ:' reasons{n}]);
        end
        % Checking that the opt-in attributes do not affect other rows
        write_text(file, '{"x":"  ON  "}');
        cfg = UTILS.CONFIG_READ(file, struct('path', 'x', 'type', 'text'));
        check(strcmp(cfg.x, '  ON  '));
        write_text(file, '{"x":null}');
        row = struct('path', 'x', 'type', 'text', 'default', 'off');
        fails(@() UTILS.CONFIG_READ(file, row), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        write_text(file, '{}');
        rows_local = {struct('path', 'options', 'type', 'object', ...
            'required', true), struct('path', 'options.x', ...
            'type', 'text', 'default', 'off')};
        cfg = UTILS.CONFIG_READ(file, rows_local);
        check(strcmp(cfg.options.x, 'off'));
        write_text(file, '{"x":[{"unused":1},{"unused":2}]}');
        row = struct('path', 'x', 'type', 'any');
        cfg = UTILS.CONFIG_READ(file, row);
        check(iscell(cfg.x));
        row.native_json = true;
        row.open = true;
        cfg = UTILS.CONFIG_READ(file, row, strict);
        decoded = jsondecode(fileread(file));
        check(isequal(cfg.x, decoded.x));
    end

    function optional_sources()
        fields = {'source_id', 'url', 'doi', 'sha256', 'cache_file'};
        for j = 1:numel(fields)
            key = fields{j};
            value = raw;
            if isfield(value.dataset, key)
                value.dataset = rmfield(value.dataset, key);
            end
            cfg = load_value(value);
            check(~isfield(cfg.dataset, key));
            for item = {'', [], 7, true, [1 2], struct(), ...
                    struct('unused', 7), 'fixture'}
                value.dataset.(key) = item{1};
                cfg = load_value(value);
                decoded = jsondecode(jsonencode(value));
                check(isequal(cfg.dataset.(key), decoded.dataset.(key)));
                check(isequal(cfg.si.dataset.(key), decoded.dataset.(key)));
            end
            text = strrep(jsonencode(value), ...
                ['"' key '":"fixture"'], ['"' key '":null']);
            write_text(file, text);
            cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
            check(isequal(cfg.dataset.(key), []));
        end
    end

    function registry_sources()
        payload = [1 2; 3 4];
        save(fullfile(folder, 'payload.mat'), 'payload');
        entry = struct('file', 'payload.mat', 'variable', 'payload', ...
            'url', '', 'doi', 'fixture', 'sha256', '', 'cache_file', '');
        entry.variables = {'registry_unused'};
        registry_file = fullfile(folder, 'sources.json');
        write_text(registry_file, jsonencode(struct('fixture', entry)));
        keys = fieldnames(entry);
        dict = cell(size(keys));
        for j = 1:numel(keys)
            type = 'text';
            if strcmp(keys{j}, 'variables'), type = 'list of text'; end
            dict{j} = struct('path', ['fixture.' keys{j}], 'type', type);
        end
        options = struct('RegistryFile', registry_file, ...
            'RegistryDictionary', {dict}, 'LocalFile', '', ...
            'DataRoot', folder, 'Strict', true);
        value = raw;
        value.dataset = struct('source_id', 'fixture');
        cfg = load_value(value);
        check(isequal(cfg.dataset, ...
            struct('source_id', 'fixture', 'config_dir', folder)));
        [data, source] = UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset, options);
        check(isequal(data, payload) && strcmp(source.doi, 'fixture'));
        value.dataset.id = 'inline';
        value.dataset.file = 'payload.mat';
        value.dataset.variable = 'payload';
        value.dataset.variables = {'inline_unused'; 'also_unused'};
        value.dataset.doi = [];
        cfg = load_value(value);
        check(isequal(cfg.dataset.variables, value.dataset.variables));
        check(isequal(cfg.si.dataset.variables, value.dataset.variables));
        [data, source, provenance] = ...
            UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset, options);
        check(isequal(data, payload) && strcmp(source.id, 'inline'));
        check(strcmp(source.variable, 'payload') && ...
            ~isfield(source, 'variables'));
        records = provenance.overrides;
        index = find(strcmp({records.path}, 'variables'), 1, 'last');
        check(~isempty(index) && ...
            isequal(records(index).old_value, entry.variables) && ...
            isequal(records(index).new_value, value.dataset.variables));
        check(isempty(source.doi));
        value.dataset = rmfield(value.dataset, 'source_id');
        cfg = load_value(value);
        [data, source, provenance] = ...
            UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset, options);
        check(isequal(data, payload) && isempty(source.doi));
        check(isempty(fieldnames(provenance)));
        value.dataset.variables = 'fixture';
        for literal = {'[]', 'null', '"unused"', ...
                '[{"unused":1},{"unused":2}]', ...
                '{"unused":[1,null]}'}
            text = strrep(jsonencode(value), '"variables":"fixture"', ...
                ['"variables":' literal{1}]);
            check(contains(text, ['"variables":' literal{1}]));
            parent = jsondecode(text);
            write_text(file, text);
            cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict);
            check(isequaln(cfg.dataset.variables, parent.dataset.variables));
            check(isequaln(cfg.si.dataset.variables, ...
                parent.dataset.variables));
            [data, source] = UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset);
            check(isequal(data, payload));
            check(strcmp(source.variable, 'payload') && ...
                ~isfield(source, 'variables'));
        end
        value.dataset = rmfield(value.dataset, 'variable');
        fails(@() load_value(value), ...
            'sootMosaic:LOAD_MAIN_SCATTER_CONFIG:MissingText');
    end

    function overlays()
        parent = fullfile(folder, 'parent.json');
        write_text(parent, jsonencode(raw));
        nested = fullfile(folder, 'nested');
        mkdir(nested);
        overlay = fullfile(nested, 'overlay.json');
        value = struct('extends', '../parent.json', ...
            'sampling', struct('cn_scat', 0.25));
        write_text(overlay, jsonencode(value));
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(overlay, strict);
        check(cfg.sampling.cn_scat == 0.25);
        check(isequal(cfg.options, raw.options));
        check(strcmp(cfg.dataset.config_dir, nested));
        check(~isfield(cfg, 'extends') && numel(cfg.provenance.files) == 2);
        records = cfg.provenance.overrides;
        index = find(strcmp({records.path}, 'sampling.cn_scat'), 1, 'last');
        check(~isempty(index) && records(index).old_value == 0.13 && ...
            records(index).new_value == 0.25);
        if usejava('jvm')
            check(numel(cfg.provenance.files(1).sha256) == 64);
            check(numel(cfg.provenance.dictionary.sha256) == 64);
        end
        write_text(overlay, '{"extends":"overlay.json"}');
        fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG(overlay, strict), ...
            'sootMosaic:CONFIG_READ:ExtendsCycle');
    end

    function profiles()
        cfg = load_value(raw);
        check(strcmp(cfg.model.profile, 'current'));
        check(strcmp(cfg.model.fluid_properties, 'sutherland'));
        check(strcmp(cfg.model.projection, 'isotropic'));
        value = raw;
        value.model_profile = 'article1_7658971';
        cfg = load_value(value);
        [model, ~, params] = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
        check(isequaln(cfg.model, model) && ...
            isequaln(cfg.model_params, params));
        check(strcmp(cfg.model.fluid_properties, 'flame'));
        check(strcmp(cfg.model.mobility, 'sorensen_eq17'));
        check(strcmp(cfg.model.slip_correction, 'per_caller_7658971'));
        check(strcmp(cfg.model.projection, 'euler_7658971'));
        check(strcmp(cfg.model.root_solve, 'start_point_7658971'));
        check(strcmp(cfg.model.continuum_diameter, 'fixed_075dg'));
        value.model_overrides.projection.method = 'isotropic';
        cfg = load_value(value);
        check(strcmp(cfg.model.projection, 'isotropic'));
        check(~isempty(cfg.model_source.overrides));
        check(cfg.projection.n_mc == 100 && cfg.projection.n_ang == 5);
        value.model_overrides.projection.methd = 'isotropic';
        fails(@() load_value(value), 'sootMosaic:MODEL_PROFILE:UnknownKey');
    end

    function unknowns()
        value = raw;
        value.sampling.cn_scale = 0.5;
        cfg = load_value(value, struct('Strict', false));
        [message, identifier] = lastwarn;
        check(strcmp(identifier, 'sootMosaic:CONFIG_READ:UnknownKey'));
        check(contains(message, 'sampling.cn_scale'));
        check(contains(message, 'sampling.cn_scat'));
        check(cfg.sampling.cn_scale == 0.5);
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        value = raw;
        value.extra = [struct('tag', 1); struct('tag', 2)];
        decoded = jsondecode(jsonencode(value));
        cfg = load_value(value, struct('Strict', false));
        check(isequaln(cfg.extra, decoded.extra));
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        value = raw;
        value.sampling.extra = [struct('tag', 1); struct('tag', 2)];
        decoded = jsondecode(jsonencode(value));
        cfg = load_value(value, struct('Strict', false));
        check(isequaln(cfg.sampling.extra, decoded.sampling.extra));
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        value = raw;
        value.comment = 'task note';
        value.options.comment = 'section note';
        cfg = load_value(value);
        check(~isfield(cfg, 'comment') && ~isfield(cfg.options, 'comment'));
    end

    function versions()
        value = rmfield(raw, 'config_version');
        cfg = load_value(value);
        check(cfg.config_version == 1);
        value.config_version = 2;
        fails(@() load_value(value), ...
            'sootMosaic:CONFIG_READ:UnsupportedVersion');
        value.config_version = 1.5;
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:InvalidVersion');
        text = strrep(jsonencode(raw), '"options":{', ...
            '"options":{"bad-key":1,');
        check(contains(text, '"bad-key":1'));
        write_text(file, text);
        fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG(file), ...
            'sootMosaic:CONFIG_READ:InvalidName');
    end

    function invalid_values()
        for n = 1:numel(rows)
            row = rows{n};
            if isfield(row, 'required') && row.required
                value = remove_path(raw, row.path);
                fails(@() load_value(value), ...
                    'sootMosaic:CONFIG_READ:MissingKey');
            end
            if strcmp(row.type, 'integer') && ...
                    ~strcmp(row.path, 'config_version')
                value = put_path(raw, row.path, 1.5);
                fails(@() load_value(value), ...
                    'sootMosaic:CONFIG_READ:InvalidInteger');
            end
        end
        for key = {'id', 'file', 'variable'}
            for selected = {raw.dataset, struct('source_id', 'fixture')}
                value = raw;
                value.dataset = selected{1};
                value.dataset.(key{1}) = '';
                fails(@() load_value(value), ...
                    'sootMosaic:LOAD_MAIN_SCATTER_CONFIG:MissingText');
            end
            value = raw;
            value.dataset = rmfield(value.dataset, key{1});
            fails(@() load_value(value), ...
                'sootMosaic:LOAD_MAIN_SCATTER_CONFIG:MissingText');
        end
        value = put_path(raw, 'sampling.cn_scat', [1 2]);
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:InvalidType');
        value = put_path(raw, 'correlation.universal.da_lim_uc', [1 2 3]);
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:InvalidLength');
        value = put_path(raw, 'correlation.universal.da_lim_uc', [1 NaN]);
        fails(@() load_value(value), 'sootMosaic:CONFIG_READ:Nonfinite');
        text = strrep(jsonencode(raw), '"n_mc":100', '"n_mc":null');
        write_text(file, text);
        fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict), ...
            'sootMosaic:CONFIG_READ:InvalidType');
        text = strrep(jsonencode(raw), '"n_mc":100', '"n_mc":1e999');
        write_text(file, text);
        fails(@() UTILS.LOAD_MAIN_SCATTER_CONFIG(file, strict), ...
            'sootMosaic:CONFIG_READ:Nonfinite');
        value = put_path(raw, 'sampling.cn_scat', -1);
        cfg = load_value(value);
        check(cfg.sampling.cn_scat == -1);
    end

    function payload_checks()
        text = fileread(fullfile(root, 'main_scatter_v8.m'));
        check(contains(text, 'UTILS.LOAD_SCATTER_LD1_DATASET(cfg_dataset)'));
        check(contains(text, 'size(pars_raw.pp{i}, 1)'));
        payload = {ones(2, 5)};
        save(fullfile(folder, 'payload.mat'), 'payload');
        value = raw;
        value.dataset = struct('id', 'fixture', 'file', 'payload.mat', ...
            'variable', 'payload');
        cfg = load_value(value);
        data = UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset);
        check(isequal(data, payload));
        value.dataset.variable = 'absent';
        cfg = load_value(value);
        fails(@() UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset), ...
            'sootMosaic:LOAD_SCATTER_LD1_DATASET:MissingVariableInFile');
        value.dataset.variable = 'payload';
        value.dataset.file = 'missing.mat';
        value.dataset.url = fullfile(folder, 'payload.mat');
        value.dataset.cache_file = 'download.mat';
        value.dataset.sha256 = UTILS.FILE_SHA256(value.dataset.url);
        cfg = load_value(value);
        downloads = 0;
        options = struct('Download', @download);
        for j = 1:2
            data = UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset, options);
            check(isequal(data, payload));
        end
        check(downloads == 2);
        cfg.dataset.sha256 = repmat('0', 1, 64);
        fails(@() UTILS.LOAD_SCATTER_LD1_DATASET(cfg.dataset, options), ...
            'sootMosaic:LOAD_SCATTER_LD1_DATASET:ChecksumMismatch');

        function download(destination, source)
            downloads = downloads + 1;
            [copied, detail] = copyfile(source, destination, 'f');
            if ~copied
                error('sootMosaic:QA:ScatterConfigFailed', '%s', detail);
            end
        end
    end
end

function contract = numeric_contract()
% Declaring paths, types, units, conversions and SI factors
contract = {
    'correlation.universal.D_TEM', ...
        'number', 'none', 'double', 1;
    'correlation.universal.dpp100', ...
        'number', 'nm', 'double', 1e-9;
    'correlation.universal.da_lim_uc', ...
        '2 numbers', 'nm', 'double', 1e-9;
    'correlation.universal.n_da_uc', ...
        'integer', 'points', 'double', 1;
    'correlation.brasil.alpha_a', ...
        'number', 'none', 'double', 1;
    'correlation.brasil.k_a', ...
        'number', 'none', 'double', 1;
    'correlation.brasil.npp_lim_bc', ...
        '2 numbers', 'primaries', 'double', 1;
    'correlation.brasil.n_npp_uc', ...
        'number', 'points', 'double', 1;
    'distribution.gm_da', 'number', 'nm', 'double', 1e-9;
    'distribution.gsd_da', 'number', 'none', 'double', 1;
    'distribution.gm_dpp', 'number', 'nm', 'double', 1e-9;
    'distribution.gsd_dpp', 'number', 'none', 'double', 1;
    'sampling.cn_scat', 'number', 'fraction', 'double', 1;
    'projection.n_mc', 'number', 'points', 'double', 1;
    'projection.n_ang', 'number', 'angles', 'double', 1;
    'options.rng_seed', 'integer or empty', 'none', 'double', 1};
end

function paths = key_paths(value, prefix)
paths = {};
if ~isstruct(value) || ~isscalar(value), return; end
names = fieldnames(value);
groups = cell(numel(names), 1);
for k = 1:numel(names)
    if isempty(prefix)
        child_path = names{k};
    else
        child_path = [prefix '.' names{k}];
    end
    groups{k} = [{child_path}; ...
        key_paths(value.(names{k}), child_path)];
end
if ~isempty(groups), paths = vertcat(groups{:}); end
end

function value = get_path(value, path)
parts = strsplit(path, '.');
for k = 1:numel(parts), value = value.(parts{k}); end
end

function value = put_path(value, path, item)
parts = strsplit(path, '.');
if isscalar(parts)
    value.(parts{1}) = item;
else
    value.(parts{1}) = put_path(value.(parts{1}), ...
        strjoin(parts(2:end), '.'), item);
end
end

function value = remove_path(value, path)
parts = strsplit(path, '.');
if isscalar(parts)
    value = rmfield(value, parts{1});
else
    value.(parts{1}) = remove_path(value.(parts{1}), ...
        strjoin(parts(2:end), '.'));
end
end

function check(value)
if ~value
    error('sootMosaic:QA:ScatterConfigFailed', ...
        'Unexpected scatter config value.');
end
end

function fails(action, identifier)
caught = '';
try
    action();
catch err
    caught = err.identifier;
end
check(strcmp(caught, identifier));
end

function write_text(file, value)
fid = fopen(file, 'wb');
if fid < 0
    error('sootMosaic:QA:ScatterConfigFailed', 'Cannot write a fixture.');
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, value, 'char');
end

function restore_state(state, message, identifier, primary, fallback)
warning(state);
lastwarn(message, identifier);
setenv('SOOTMOSAIC_MAIN_SCATTER_CONFIG', primary);
setenv('PFAL_MAIN_SCATTER_CONFIG', fallback);
end
