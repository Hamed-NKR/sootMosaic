function report = TEST_TASK_REGISTRY_INPUTS()
% "TEST_TASK_REGISTRY_INPUTS" checks task source selection and overrides.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Fixtures use tempname and are...
%         ...removed on exit. A failed case raises...
%         ...sootMosaic:QA:TaskRegistryInputsFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:TaskRegistryInputsFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
restore = onCleanup(@() restore_warnings(state, warn_message, warn_id));
tests = {@registry_only, @inline_override, @digest_mismatch, ...
    @inline_only, @empty_overrides, @required_overrides, @complete_identity};
names = {'registry-only inheritance', 'explicit inline overrides', ...
    'inherited digest mismatch', 'inline-only inputs', ...
    'explicit empty optional fields', 'required inline fields', ...
    'complete source identity'};
pass = false(size(tests));
try
    root = fileparts(fileparts(mfilename('fullpath')));
    task_folder = fullfile(folder, 'tasks');
    data_folder = fullfile(folder, 'data');
    mkdir(task_folder);
    mkdir(data_folder);
    config_file = fullfile(task_folder, 'task.json');
    remote = fullfile(data_folder, 'registry.mat');
    override_file = fullfile(task_folder, 'override.mat');
    payload = [1 2; 3 4];
    extra = 9;
    alternate = [-1 -2];
    alternate_extra = 7;
    save(remote, 'payload', 'extra');
    save(override_file, 'alternate', 'alternate_extra');
    digest = UTILS.FILE_SHA256(remote);
    override_digest = UTILS.FILE_SHA256(override_file);
    check(~isempty(digest) && ~strcmp(digest, override_digest));
    entry = struct('file', 'registry.mat', 'variable', 'payload', ...
        'variables', {{'payload'; 'extra'}}, 'url', 'registry.mat', ...
        'doi', 'fixture-registry', 'sha256', digest, ...
        'cache_file', 'registry-cache.mat');
    registry = struct('config_version', 1, 'fixture', entry);
    fields = fieldnames(entry);
    rows = cell(numel(fields), 1);
    for k = 1:numel(fields)
        type = 'text';
        if strcmp(fields{k}, 'variables'), type = 'list of text'; end
        rows{k} = struct('path', ['fixture.' fields{k}], ...
            'type', type, 'required', true);
    end
    opts = struct('RegistryFile', fullfile(folder, 'sources.json'), ...
        'RegistryDictionary', fullfile(folder, 'sources.keys.json'), ...
        'DataRoot', data_folder, 'LocalFile', '', 'Strict', true, ...
        'Download', @reject_download);
    write_text(opts.RegistryFile, jsonencode(registry));
    write_text(opts.RegistryDictionary, jsonencode(rows));
    paths = { ...
        'main_scale/main_scale_config.example.json', ...
        'main_scatter/main_scatter_config.example.json', ...
        'main_ld2/main_ld2_from_main_scale_config.example.json', ...
        'main_ld2/main_ld2_from_main_scatter_config.example.json', ...
        'main_valid/main_valid_config.example.json'};
    config_loaders = {@UTILS.LOAD_MAIN_SCALE_CONFIG, ...
        @UTILS.LOAD_MAIN_SCATTER_CONFIG, @UTILS.LOAD_MAIN_LD2_CONFIG, ...
        @UTILS.LOAD_MAIN_LD2_CONFIG, @UTILS.LOAD_MAIN_VALID_CONFIG};
    data_loaders = {@UTILS.LOAD_MAIN_SCALE_DATASET, ...
        @UTILS.LOAD_SCATTER_LD1_DATASET, @UTILS.LOAD_MAIN_LD2_DATASET, ...
        @UTILS.LOAD_MAIN_LD2_DATASET, @UTILS.LOAD_VALIDATION_SOURCE};
    callers = {'LOAD_MAIN_SCALE_DATASET', 'LOAD_SCATTER_LD1_DATASET', ...
        'LOAD_MAIN_LD2_DATASET', 'LOAD_MAIN_LD2_DATASET', ...
        'LOAD_VALIDATION_SOURCE'};
    source_names = {'ld2', 'tem', 'effective_density'};
    templates = cell(size(paths));
    for k = 1:numel(paths)
        templates{k} = jsondecode(fileread( ...
            fullfile(root, 'config', paths{k})));
    end
catch err
    error('sootMosaic:QA:TaskRegistryInputsFailed', ...
        'Fixture setup failed (%s): %s', err.identifier, err.message);
end
for k = 1:numel(tests)
    try
        tests{k}();
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
    if pass(k), label = 'PASS'; else, label = 'FAIL'; end
    fprintf('%s %s\n', label, names{k});
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:TaskRegistryInputsFailed', ...
        '%d cases failed.', sum(~pass));
end

    function [cfg, sources] = task(index, selected)
        cfg = templates{index};
        if index < 5
            cfg.dataset = selected;
        else
            for n = 1:numel(source_names)
                cfg.sources.(source_names{n}) = selected;
            end
        end
        write_text(config_file, jsonencode(cfg));
        cfg = config_loaders{index}(config_file);
        if index < 5
            sources = {cfg.dataset};
        else
            sources = cellfun(@(name) cfg.sources.(name), ...
                source_names, 'UniformOutput', false);
        end
    end

    function registry_only()
        for i = 1:numel(paths)
            [~, sources] = task(i, struct('source_id', 'fixture'));
            for j = 1:numel(sources)
                selected = sources{j};
                expected = struct('source_id', 'fixture');
                if i < 5, expected.config_dir = task_folder; end
                check(isequal(selected, expected));
                [data, source] = data_loaders{i}(selected, opts);
                check_data(i, data, false);
                check(strcmp(source.id, 'fixture'));
                check(strcmp(source.file, remote));
                check(strcmp(source.sha256, digest));
                check(strcmp(source.url, entry.url));
                check(strcmp(source.doi, entry.doi));
                check(strcmp(source.cache_file, ...
                    fullfile(data_folder, entry.cache_file)));
                check_variables(i, source, false);
            end
        end
    end

    function inline_override()
        selected = struct('source_id', 'fixture', 'id', 'inline', ...
            'file', 'override.mat', 'variable', 'alternate', ...
            'variables', {{'alternate'; 'alternate_extra'}}, ...
            'url', 'override.mat', 'doi', 'fixture-inline', ...
            'sha256', override_digest, 'cache_file', 'inline-cache.mat');
        for i = 1:numel(paths)
            [~, sources] = task(i, selected);
            for j = 1:numel(sources)
                [data, source] = data_loaders{i}(sources{j}, opts);
                check_data(i, data, true);
                check(strcmp(source.id, selected.id));
                check(strcmp(source.file, override_file));
                check(strcmp(source.sha256, override_digest));
                check(strcmp(source.url, selected.url));
                check(strcmp(source.doi, selected.doi));
                check(strcmp(source.cache_file, ...
                    fullfile(task_folder, selected.cache_file)));
                check_variables(i, source, true);
            end
        end
    end

    function digest_mismatch()
        selected = struct('source_id', 'fixture', 'file', 'override.mat', ...
            'variable', 'alternate', ...
            'variables', {{'alternate'; 'alternate_extra'}});
        for i = 1:numel(paths)
            [~, sources] = task(i, selected);
            for j = 1:numel(sources)
                expect_error(@() data_loaders{i}(sources{j}, opts), ...
                    ['sootMosaic:' callers{i} ':ChecksumMismatch']);
            end
        end
    end

    function inline_only()
        for i = 1:numel(paths)
            selected = complete_source(i);
            selected = rmfield(selected, {'url', 'doi', ...
                'sha256', 'cache_file'});
            [~, sources] = task(i, selected);
            for j = 1:numel(sources)
                [data, source, provenance] = ...
                    data_loaders{i}(sources{j}, opts);
                check_data(i, data, true);
                expected = selected;
                expected.file = override_file;
                expected.url = '';
                expected.doi = '';
                expected.sha256 = '';
                expected.cache_file = '';
                if i < 5
                    expected.config_dir = task_folder;
                else
                    expected.resolved_file = override_file;
                    expected.loaded_variables = selected.variables;
                end
                check(isequal(source, expected));
                check(isempty(fieldnames(provenance)));
            end
        end
    end

    function empty_overrides()
        for i = 1:numel(paths)
            for value = {'', []}
                selected = struct('source_id', 'fixture', ...
                    'file', 'override.mat', 'variable', 'alternate', ...
                    'variables', {{'alternate'; 'alternate_extra'}}, ...
                    'url', value{1}, 'doi', value{1}, ...
                    'sha256', value{1}, 'cache_file', value{1});
                [~, sources] = task(i, selected);
                for j = 1:numel(sources)
                    [data, source] = data_loaders{i}(sources{j}, opts);
                    check_data(i, data, true);
                    for name = {'url', 'doi', 'sha256', 'cache_file'}
                        check(isfield(sources{j}, name{1}));
                        check(isempty(source.(name{1})));
                    end
                end
            end
        end
    end

    function required_overrides()
        for i = 1:numel(paths)
            fields = {'id', 'file', 'variable'};
            if i == 5, fields{3} = 'variables'; end
            caller = func2str(config_loaders{i});
            caller = strrep(caller, 'UTILS.', '');
            for j = 1:numel(fields)
                selected = struct('source_id', 'fixture');
                selected.(fields{j}) = '';
                reason = 'MissingText';
                if i == 5 && j == 3, reason = 'MissingSourceVariables'; end
                expect_error(@() task(i, selected), ...
                    ['sootMosaic:' caller ':' reason]);
                selected = rmfield(complete_source(i), fields{j});
                expect_error(@() task(i, selected), ...
                    ['sootMosaic:' caller ':' reason]);
            end
        end
    end

    function complete_identity()
        for i = 1:numel(paths)
            selected = complete_source(i);
            [inline_cfg, inline_sources] = task(i, selected);
            selected.source_id = 'fixture';
            [registry_cfg, registry_sources] = task(i, selected);
            if i < 5
                registry_cfg.dataset = rmfield( ...
                    registry_cfg.dataset, 'source_id');
                if i == 1
                    registry_cfg.si.dataset = rmfield( ...
                        registry_cfg.si.dataset, 'source_id');
                    inline_cfg = rmfield(inline_cfg, 'provenance');
                    registry_cfg = rmfield(registry_cfg, 'provenance');
                end
            else
                for j = 1:numel(source_names)
                    name = source_names{j};
                    registry_cfg.sources.(name) = rmfield( ...
                        registry_cfg.sources.(name), 'source_id');
                end
            end
            check(isequaln(inline_cfg, registry_cfg));
            for j = 1:numel(inline_sources)
                [a, sa] = data_loaders{i}(inline_sources{j}, opts);
                [b, sb] = data_loaders{i}(registry_sources{j}, opts);
                check(isequal(a, b) && isequal(sa, sb));
            end
        end
    end

    function selected = complete_source(index)
        selected = struct('id', 'inline', 'file', 'override.mat', ...
            'url', 'override.mat', 'doi', 'fixture-inline', ...
            'sha256', override_digest, 'cache_file', 'inline-cache.mat');
        selected.variable = 'alternate';
        if index == 5
            selected.variables = {'alternate'; 'alternate_extra'};
        end
    end

    function check_data(index, data, overridden)
        if overridden
            expected = alternate;
            if index == 5
                expected = struct('alternate', alternate, ...
                    'alternate_extra', alternate_extra);
            end
        else
            expected = payload;
            if index == 5
                expected = struct('payload', payload, 'extra', extra);
            end
        end
        check(isequal(data, expected));
    end

    function check_variables(index, source, overridden)
        variable = 'payload';
        variables = {'payload'; 'extra'};
        if overridden
            variable = 'alternate';
            variables = {'alternate'; 'alternate_extra'};
        end
        if index < 5
            check(strcmp(source.variable, variable));
        else
            check(isequal(source.variables, variables));
            check(isequal(source.loaded_variables, variables));
            check(strcmp(source.resolved_file, source.file));
        end
    end
end

function check(value)
if ~value
    error('sootMosaic:QA:TaskRegistryInputsFailed', ...
        'The task source differs from the expected value.');
end
end

function expect_error(action, identifier)
caught = '';
try
    action();
catch err
    caught = err.identifier;
end
check(strcmp(caught, identifier));
end

function reject_download(~, ~)
error('sootMosaic:QA:TaskRegistryInputsFailed', ...
    'The fixture must load from a local file.');
end

function write_text(file, value)
fid = fopen(file, 'wb');
if fid < 0
    error('sootMosaic:QA:TaskRegistryInputsFailed', ...
        'Could not write a fixture.');
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, value, 'char');
end

function restore_warnings(state, message, identifier)
warning(state);
lastwarn(message, identifier);
end
