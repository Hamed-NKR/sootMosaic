function report = TEST_DATASET_SOURCE()
% "TEST_DATASET_SOURCE" checks source selection and checksum roles.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Fixtures use tempname and a local...
%         ...copy function for downloads. A failed case stops with...
%         ...sootMosaic:QA:DatasetSourceFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:DatasetSourceFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
restore = onCleanup(@() restore_warnings(state, warn_message, warn_id));
loaders = {@UTILS.LOAD_MAIN_LD2_DATASET, @UTILS.LOAD_MAIN_SCALE_DATASET, ...
    @UTILS.LOAD_SCATTER_LD1_DATASET, @UTILS.LOAD_VALIDATION_SOURCE};
callers = {'LOAD_MAIN_LD2_DATASET', 'LOAD_MAIN_SCALE_DATASET', ...
    'LOAD_SCATTER_LD1_DATASET', 'LOAD_VALIDATION_SOURCE'};
for k = 1:4
    warning('on', ['sootMosaic:' callers{k} ':MissingChecksum']);
end
payload = [1 2; 3 4];
extra = 9;
remote = fullfile(folder, 'remote.mat');
save(remote, 'payload', 'extra');
digest = UTILS.FILE_SHA256(remote);
downloads = 0;
opts = struct('Download', @download_copy, 'Strict', true);
tests = {@local_match, @local_mismatch, @missing_digest, ...
    @validation_cache, @validation_bad_download, @dataset_downloads, ...
    @cache_alias, @default_destinations, @ld2_doi, @registry_equivalence, ...
    @registry_overlay, @registry_errors, @sidecar_format, @example_identity};
names = {'local match and loader metadata', 'local mismatch persists', ...
    'URL without digest warns', 'validation cache reuse and rejection', ...
    'validation bad download remains cached', 'dataset downloads repeat', ...
    'alternate cache folder read', 'default download destinations', ...
    'LD2 workspace DOI', 'registry and inline equivalence', ...
    'local registry selection and provenance', 'registry validation', ...
    'sidecar bytes', 'tracked example variable and metadata identity'};
pass = false(size(tests));
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
    error('sootMosaic:QA:DatasetSourceFailed', '%d cases failed.', sum(~pass));
end

    function download_copy(destination, address)
        downloads = downloads + 1;
        [copied, detail] = copyfile(address, destination, 'f');
        if ~copied
            error('sootMosaic:QA:DatasetSourceFailed', '%s', detail);
        end
    end

    function src = fixture(index, tag)
        src = struct('id', 'fixture', 'file', remote, ...
            'url', remote, 'doi', '10.0000/fixture', 'sha256', digest, ...
            'cache_file', fullfile(folder, [tag '.mat']));
        if index == 4
            src.variables = {'payload'; 'extra'};
        else
            src.variable = 'payload';
            src.config_dir = folder;
        end
    end

    function check(value)
        if ~value
            error('sootMosaic:QA:DatasetSourceFailed', ...
                'The source result differs from the expected value.');
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

    function local_match()
        for i = 1:4
            src = fixture(i, 'unused');
            src.sha256 = upper(digest);
            before = downloads;
            [data, actual, provenance] = loaders{i}(src, opts);
            expected = src;
            if i == 4
                expected.resolved_file = remote;
                expected.loaded_variables = src.variables;
                check(isequal(data, ...
                    struct('payload', payload, 'extra', extra)));
            else
                check(isequal(data, payload));
            end
            check(isequal(actual, expected) && ...
                isempty(fieldnames(provenance)));
            check(downloads == before);
        end
    end

    function local_mismatch()
        for i = 1:4
            src = fixture(i, 'unused');
            src.sha256 = repmat('0', 1, 64);
            before = downloads;
            for repeat = 1:2
                expect_error(@() loaders{i}(src, opts), ...
                    ['sootMosaic:' callers{i} ':ChecksumMismatch']);
            end
            check(downloads == before && ...
                strcmp(UTILS.FILE_SHA256(remote), digest));
        end
    end

    function missing_digest()
        for i = 1:4
            src = fixture(i, 'unsigned');
            src.sha256 = '';
            lastwarn('', '');
            loaders{i}(src, opts);
            [~, identifier] = lastwarn;
            check(strcmp(identifier, ...
                ['sootMosaic:' callers{i} ':MissingChecksum']));
            src.url = '';
            lastwarn('', '');
            loaders{i}(src, opts);
            [~, identifier] = lastwarn;
            check(isempty(identifier));
        end
    end

    function validation_cache()
        src = fixture(4, 'validation_cache');
        src.file = fullfile(folder, 'absent.mat');
        copyfile(remote, src.cache_file);
        before = downloads;
        for repeat = 1:2
            [data, actual] = loaders{4}(src, opts);
            check(isequal(data.payload, payload));
            check(strcmp(actual.file, src.file));
            check(strcmp(actual.resolved_file, src.cache_file));
        end
        src.sha256 = repmat('0', 1, 64);
        for repeat = 1:2
            expect_error(@() loaders{4}(src, opts), ...
                'sootMosaic:LOAD_VALIDATION_SOURCE:ChecksumMismatch');
        end
        check(downloads == before && isfile(src.cache_file));
    end

    function validation_bad_download()
        src = fixture(4, 'bad_download');
        src.file = fullfile(folder, 'absent.mat');
        src.sha256 = repmat('0', 1, 64);
        before = downloads;
        for repeat = 1:2
            expect_error(@() loaders{4}(src, opts), ...
                'sootMosaic:LOAD_VALIDATION_SOURCE:ChecksumMismatch');
            check(downloads == before + 1);
        end
        check(strcmp(UTILS.FILE_SHA256(src.cache_file), digest));
    end

    function dataset_downloads()
        for i = 1:3
            src = fixture(i, sprintf('download_%d', i));
            src.file = fullfile(folder, 'absent.mat');
            before = downloads;
            for repeat = 1:2
                [data, actual] = loaders{i}(src, opts);
                check(isequal(data, payload) && ...
                    strcmp(actual.file, src.cache_file));
                check(downloads == before + repeat && ~isfile(src.file));
            end
            src.sha256 = repmat('0', 1, 64);
            for repeat = 1:2
                expect_error(@() loaders{i}(src, opts), ...
                    ['sootMosaic:' callers{i} ':ChecksumMismatch']);
                check(downloads == before + 2 + repeat);
            end
        end
    end

    function cache_alias()
        src = fixture(4, 'unused');
        src.file = fullfile(folder, 'absent.mat');
        src.cache_file = fullfile(folder, '.sootmosaic-cache', 'source.mat');
        alternate = fullfile(folder, '.pfal-cache', 'source.mat');
        mkdir(fileparts(alternate));
        copyfile(remote, alternate);
        before = downloads;
        [data, actual] = loaders{4}(src, opts);
        check(isequal(data.payload, payload));
        check(strcmp(actual.resolved_file, alternate) && downloads == before);
        src.sha256 = repmat('0', 1, 64);
        for repeat = 1:2
            expect_error(@() loaders{4}(src, opts), ...
                'sootMosaic:LOAD_VALIDATION_SOURCE:ChecksumMismatch');
        end
        check(downloads == before);
        mkdir(fileparts(src.cache_file));
        copyfile(remote, src.cache_file);
        src.sha256 = digest;
        [~, actual] = loaders{4}(src, opts);
        check(strcmp(actual.resolved_file, src.cache_file));
    end

    function default_destinations()
        for i = 1:4
            src = fixture(i, 'unused');
            src.file = fullfile(folder, sprintf('default_%d.mat', i));
            src.cache_file = '';
            settings = opts;
            settings.DefaultCacheDir = ...
                fullfile(folder, sprintf('cache_%d', i));
            expected = src.file;
            if i == 2 || i == 3
                [~, name, ext] = fileparts(src.file);
                expected = fullfile(settings.DefaultCacheDir, [name ext]);
            end
            before = downloads;
            for repeat = 1:2
                [~, actual] = loaders{i}(src, settings);
                selected = actual.file;
                if i == 4, selected = actual.resolved_file; end
                check(strcmp(selected, expected));
            end
            check(downloads == before + 1 + double(i == 2 || i == 3));
        end
    end

    function ld2_doi()
        [pars_LD2, dataset_src] = loaders{1}(fixture(1, 'unused'), opts);
        checkpoint = fullfile(folder, 'checkpoint.mat');
        final_file = fullfile(folder, 'final.mat');
        save(checkpoint, 'pars_LD2', 'dataset_src');
        save(final_file, 'pars_LD2', 'dataset_src');
        a = load(checkpoint);
        b = load(final_file);
        check(isequal(a, b) && isequal(a.pars_LD2, payload));
        check(strcmp(a.dataset_src.doi, '10.0000/fixture'));
    end

    function [settings, registry, id] = registry_fixture(tag)
        root = fileparts(fileparts(mfilename('fullpath')));
        directory = fullfile(folder, tag);
        mkdir(directory);
        settings = opts;
        settings.DataRoot = folder;
        settings.RegistryFile = fullfile(directory, 'sources.json');
        settings.RegistryDictionary = fullfile(directory, 'sources.keys.json');
        settings.LocalFile = fullfile(directory, 'sources.local.json');
        original = fullfile(root, 'config', 'sources');
        copyfile(fullfile(original, 'sources.keys.json'), ...
            settings.RegistryDictionary);
        registry = jsondecode(fileread(fullfile(original, 'sources.json')));
        id = 'ld1_aggregate_library';
        registry.(id).file = 'remote.mat';
        registry.(id).variable = 'payload';
        registry.(id).variables = {'payload'; 'extra'};
        registry.(id).sha256 = digest;
        registry.(id).doi = '10.0000/fixture';
        write_text(settings.RegistryFile, jsonencode(registry));
    end

    function registry_equivalence()
        [settings, registry, id] = registry_fixture('equivalence');
        for i = 1:4
            selected = struct('source_id', id);
            inline = registry.(id);
            inline.id = id;
            inline.file = remote;
            if i < 4
                selected.config_dir = folder;
                inline.config_dir = folder;
            end
            [a, sa, provenance] = loaders{i}(selected, settings);
            [b, sb] = loaders{i}(inline, settings);
            check(isequal(a, b) && isequal(sa, sb));
            check(strcmp(provenance.files.sha256, ...
                UTILS.FILE_SHA256(settings.RegistryFile)));
            check(strcmp(provenance.dictionary.sha256, ...
                UTILS.FILE_SHA256(settings.RegistryDictionary)));
        end
        selected.doi = '10.0000/inline';
        [~, source] = loaders{1}(selected, settings);
        check(strcmp(source.doi, selected.doi));
        selected.file = fullfile(folder, 'absent.mat');
        selected.url = '';
        expect_error(@() loaders{1}(selected, settings), ...
            'sootMosaic:LOAD_MAIN_LD2_DATASET:MissingFileOnDisk');
    end

    function registry_overlay()
        [settings, ~, id] = registry_fixture('overlay');
        local = struct();
        local.(id) = struct('where', 'web', 'url', remote, ...
            'cache_file', 'overlay_cache.mat', 'doi', '10.0000/local');
        write_text(settings.LocalFile, jsonencode(local));
        before = downloads;
        [data, source, provenance] = ...
            loaders{1}(struct('source_id', id), settings);
        check(isequal(data, payload) && downloads == before + 1);
        check(strcmp(source.file, fullfile(folder, 'overlay_cache.mat')));
        check(strcmp(source.doi, '10.0000/local') && ...
            numel(provenance.files) == 2);
        check(strcmp(provenance.files(2).sha256, ...
            UTILS.FILE_SHA256(settings.LocalFile)));
        local.(id).where = 'file';
        write_text(settings.LocalFile, jsonencode(local));
        [~, source] = loaders{1}(struct('source_id', id), settings);
        check(strcmp(source.file, remote) && downloads == before + 1);
    end

    function registry_errors()
        [settings, registry, id] = registry_fixture('errors');
        expect_error(@() loaders{1}( ...
            struct('source_id', 'absent'), settings), ...
            'sootMosaic:LOAD_MAIN_LD2_DATASET:UnknownSource');
        registry.(id).where = 'web';
        write_text(settings.RegistryFile, jsonencode(registry));
        expect_error(@() loaders{1}(struct('source_id', id), settings), ...
            'sootMosaic:LOAD_MAIN_LD2_DATASET:InvalidWhere');
        registry.(id) = rmfield(registry.(id), 'where');
        registry.(id).unexpected = 1;
        write_text(settings.RegistryFile, jsonencode(registry));
        expect_error(@() loaders{1}(struct('source_id', id), settings), ...
            'sootMosaic:CONFIG_READ:UnknownKey');
    end

    function sidecar_format()
        file = fullfile(folder, 'bytes.dat');
        write_text(file, 'abc');
        [hash, sidecar] = UTILS.WRITE_SHA256_SIDECAR(file);
        expected_hash = ['ba7816bf8f01cfea414140de5dae2223' ...
            'b00361a396177a9cb410ff61f20015ad'];
        check(strcmp(hash, expected_hash));
        fid = fopen(sidecar, 'rb');
        close_file = onCleanup(@() fclose(fid));
        bytes = fread(fid, Inf, '*uint8').';
        check(isequal(bytes, ...
            uint8(sprintf('%s  bytes.dat\n', expected_hash))));
        check(strcmp(sidecar, [file '.sha256']));
        clear close_file
        [hash, sidecar] = UTILS.WRITE_SHA256_SIDECAR(remote);
        check(strcmp(hash, digest));
        check(strcmp(fileread(sidecar), sprintf('%s  remote.mat\n', digest)));
    end

    function example_identity()
        root = fileparts(fileparts(mfilename('fullpath')));
        paths = { ...
            'main_ld2/main_ld2_from_main_scale_config.example.json', ...
            'main_ld2/main_ld2_from_main_scatter_config.example.json', ...
            'main_scale/main_scale_config.example.json', ...
            'main_scatter/main_scatter_config.example.json', ...
            'main_valid/main_valid_config.example.json'};
        indices = [1 1 2 3 4];
        for j = 1:numel(paths)
            cfg = jsondecode(fileread(fullfile(root, 'config', paths{j})));
            if j < 5
                sources = {cfg.dataset};
            else
                keys = fieldnames(cfg.sources);
                sources = cellfun(@(key) cfg.sources.(key), keys, ...
                    'UniformOutput', false);
            end
            for n = 1:numel(sources)
                src = sources{n};
                values = struct();
                if j < 5
                    values.(src.variable) = payload;
                    variables = {src.variable};
                else
                    variables = src.variables(:);
                    for v = 1:numel(variables)
                        values.(variables{v}) = payload;
                    end
                end
                fixture_file = fullfile(folder, ...
                    sprintf('example_%d_%d.mat', j, n));
                save(fixture_file, '-struct', 'values');
                src.file = fixture_file;
                src.url = fixture_file;
                src.sha256 = UTILS.FILE_SHA256(fixture_file);
                src.cache_file = '';
                if j < 5, src.config_dir = folder; end
                [data, actual] = loaders{indices(j)}(src, opts);
                expected = src;
                if j < 5
                    check(isequal(data, payload));
                else
                    check(isequal(data, values));
                    expected.variables = variables;
                    expected.resolved_file = fixture_file;
                    expected.loaded_variables = variables;
                end
                check(isequal(actual, expected));
            end
        end
    end
end

function write_text(file, value)
fid = fopen(file, 'wb');
if fid < 0
    error('sootMosaic:QA:DatasetSourceFailed', 'Could not write a fixture.');
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, value, 'char');
end

function restore_warnings(state, message, identifier)
warning(state);
lastwarn(message, identifier);
end
