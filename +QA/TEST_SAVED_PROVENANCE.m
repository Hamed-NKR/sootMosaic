function report = TEST_SAVED_PROVENANCE()
% "TEST_SAVED_PROVENANCE" checks source records in saved products.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:SavedProvenanceFailed
% ----------------------------------------------------------------------- %
%
% Testing loader calls and save assembly without running the full tasks.
% Fixtures use a temporary folder removed on exit.

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:SavedProvenanceFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
names = {'scale', 'scatter canonical', 'scatter method', ...
    'LD2 workspace', 'validation ld2', 'validation tem', ...
    'validation effective_density'};
pass = false(size(names));
try
    root = fileparts(fileparts(mfilename('fullpath')));
    payload = [1 2; 3 4];
    input_file = fullfile(folder, 'input.mat');
    save(input_file, 'payload');
    digest = UTILS.FILE_SHA256(input_file);
    check(numel(digest) == 64);
    entry = struct('file', 'input.mat', 'variable', 'payload', ...
        'variables', {{'payload'}}, 'url', '', 'doi', 'registry', ...
        'sha256', digest, 'cache_file', '');
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
        'LocalFile', fullfile(folder, 'sources.local.json'), ...
        'DataRoot', folder, 'Strict', true, 'Download', @reject_download);
    write_text(opts.RegistryFile, jsonencode(registry));
    write_text(opts.RegistryDictionary, jsonencode(rows));
    write_text(opts.LocalFile, ...
        jsonencode(struct('fixture', struct('doi', 'local'))));
    selected = struct('source_id', 'fixture', 'doi', 'inline');
    loaders = {@UTILS.LOAD_MAIN_SCALE_DATASET, ...
        @UTILS.LOAD_SCATTER_LD1_DATASET, @UTILS.LOAD_MAIN_LD2_DATASET};
    files = {'main_scale_v2.m', 'main_scatter_v8.m', 'main_LD2_v3.m'};
    texts = cellfun(@(file) fileread(fullfile(root, file)), files, ...
        'UniformOutput', false);
    valid_text = fileread(fullfile(root, '+UTILS', 'RUN_MAIN_VALIDATION.m'));
catch err
    error('sootMosaic:QA:SavedProvenanceFailed', ...
        'Fixture setup failed (%s): %s', err.identifier, err.message);
end
for k = 1:numel(names)
    try
        product_file = fullfile(folder, 'product.mat');
        if k <= 4
            index = min(k, 3);
            if k == 3, index = 2; end
            if k == 4, index = 3; end
            txt = texts{index};
            compact = regexprep(txt, '\s|\.\.\.|%#ok<NASGU>', '');
            lhs = 'pars_raw.pp';
            if index == 3, lhs = 'pars_LD2'; end
            capture = ['[' lhs ',dataset_src,dataset_provenance]=' ...
                func2str(loaders{index}) '(cfg_dataset);'];
            check(contains(compact, capture));
            [data, source, provenance] = loaders{index}(selected, opts);
            check(isequal(data, payload));
            if index < 3
                lists = regexp(txt, '''pars_out''[^)]*', 'match');
                site = 1;
                if k == 3, site = 2; end
                check(numel(lists) == index);
                tokens = regexp(lists{site}, '''([^'']*)''', 'tokens');
                list = cellfun(@(item) item{1}, tokens, ...
                    'UniformOutput', false);
                product = struct('pars_out', data, 'dataset_src', source, ...
                    'dataset_provenance', provenance);
                if index == 2
                    product.scatter_metadata = struct('fixture', 7);
                    product.scatter_summary = [5 6];
                end
                save(product_file, '-struct', 'product', list{:});
                saved = load(product_file);
                check(isequal(saved, product));
            else
                sites = regexp(txt, ...
                    'save\(fullfile\(dir_wsp,.*?''-v7.3''\)', 'match');
                check(numel(sites) == 2);
                for j = 1:2
                    tail = regexp(sites{j}, ...
                        '\)\),\s*''-v7.3''\)$', 'once');
                    check(~isempty(tail));
                end
                check(isscalar(strfind(txt, 'dataset_provenance')));
                save_workspace(product_file, data, source, provenance);
                saved = load(product_file);
                check(isequal(saved.pars_LD2, payload));
            end
            check(isequal(saved.dataset_src, source));
            check(strcmp(saved.dataset_src.id, 'fixture'));
            check(strcmp(saved.dataset_src.doi, 'inline'));
            check_record(saved.dataset_provenance, opts);
        else
            keys = {'ld2', 'tem', 'effective_density'};
            key = keys{k - 4};
            compact = regexprep(valid_text, '\s|\.\.\.', '');
            check(contains(compact, ['source_info.' key ...
                ',source_provenance.' key ']=UTILS.LOAD_VALIDATION_SOURCE(' ...
                'cfg.sources.' key ');']));
            check(contains(compact, ['source_manifest(source_info.' key ...
                ',source_provenance.' key ')']));
            check(contains(compact, ...
                'build_manifest(cfg,source_info,source_provenance,'));
            [data, source, provenance] = ...
                UTILS.LOAD_VALIDATION_SOURCE(selected, opts);
            check(isequal(data, struct('payload', payload)));
            body = regexp(valid_text, ...
                ['function output = source_manifest\(source, provenance\)' ...
                '(.*?)\nend'], 'tokens', 'once');
            check(~isempty(body));
            manifest.sources.(key) = ...
                assemble_source(source, provenance, body{1});
            save(product_file, 'data', 'manifest');
            saved = load(product_file);
            check(isequal(saved.data, data));
            record = saved.manifest.sources.(key);
            check_record(record.provenance, opts);
            baseline_body = regexprep(body{1}, ...
                ',\s*\.\.\.\s*''provenance'', provenance', '');
            baseline = assemble_source(source, provenance, baseline_body);
            check(isequal(rmfield(record, 'provenance'), baseline));
            check(strcmp(record.sha256, digest));
            check(strcmp(record.id, 'fixture'));
            check(isequal(record.loaded_variables, source.loaded_variables));
            encoded = jsondecode(jsonencode(saved.manifest));
            check_record(encoded.sources.(key).provenance, opts);
            check(strcmp(encoded.sources.(key).sha256, digest));
        end
        check(strcmp(UTILS.FILE_SHA256(input_file), digest));
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:SavedProvenanceFailed', ...
        '%d cases failed.', sum(~pass));
end
end

function save_workspace(file, pars_LD2, dataset_src, dataset_provenance) %#ok<INUSD>
% Saving the captured variables through a workspace save
save(file, '-v7.3');
end

function output = assemble_source(source, provenance, body) %#ok<INUSD>
% Evaluating the source manifest assembly from the validation caller
output = [];
eval(body);
end

function check_record(provenance, opts)
check(numel(provenance.files) == 2);
check(all(arrayfun(@(item) numel(item.sha256) == 64, provenance.files)));
check(strcmp(provenance.files(1).sha256, ...
    UTILS.FILE_SHA256(opts.RegistryFile)));
check(strcmp(provenance.files(2).sha256, ...
    UTILS.FILE_SHA256(opts.LocalFile)));
changes = provenance.overrides;
inline = strcmp({changes.path}, 'doi') & ...
    strcmp({changes.source}, '<inline>');
check(sum(inline) == 1);
check(strcmp(changes(inline).old_value, 'local'));
check(strcmp(changes(inline).new_value, 'inline'));
local = strcmp({changes.path}, 'fixture.doi');
check(sum(local) == 1);
check(strcmp(changes(local).old_value, 'registry'));
check(strcmp(changes(local).new_value, 'local'));
end

function check(value)
if ~value
    error('sootMosaic:QA:SavedProvenanceFailed', ...
        'The saved source record differs from the expected value.');
end
end

function reject_download(~, ~)
error('sootMosaic:QA:SavedProvenanceFailed', ...
    'The fixture must load from a local file.');
end

function write_text(file, value)
fid = fopen(file, 'wb');
if fid < 0
    error('sootMosaic:QA:SavedProvenanceFailed', ...
        'Could not write a fixture.');
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, value, 'char');
end
