function [data, source, provenance] = LOAD_DATASET_SOURCE(source_cfg, opts)
% "LOAD_DATASET_SOURCE" resolves, verifies and loads a data source.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     source_cfg: Inline source fields or source_id with field overrides
%     opts: Caller options. ReuseCache selects cache reuse. ReturnStruct...
%         ...selects variables and a structure result. ResolvePaths and...
%         ...CanonicalPaths select path handling. DefaultCacheDir sets the...
%         ...download folder, or empty uses file. Caller names errors....
%         ...Download is a function accepting destination and url, with...
%         ...websave as default. RegistryFile, RegistryDictionary,...
%         ...LocalFile and DataRoot select registry inputs. Strict enables...
%         ...strict dictionary checks. An empty LocalFile skips the overlay
% ----------------------------------------------------------------------- %
%
% Outputs:
%     data: Requested variable or structure of requested variables
%     source: Resolved source metadata in the calling loader format
%     provenance: Registry configuration digests and inline overrides
% ----------------------------------------------------------------------- %

if nargin < 2, opts = struct(); end
if ~isstruct(opts) || ~isscalar(opts)
    error('sootMosaic:LOAD_DATASET_SOURCE:InvalidOptions', ...
        'Source options must be a scalar structure.');
end
caller = option(opts, 'Caller', 'LOAD_DATASET_SOURCE');
as_struct = option(opts, 'ReturnStruct', false);
if nargin < 1 || ~isstruct(source_cfg) || ~isscalar(source_cfg)
    reason = 'MissingDatasetConfig';
    if as_struct, reason = 'MissingConfig'; end
    fail(caller, reason, 'A scalar source configuration is required.');
end
root = fileparts(fileparts(mfilename('fullpath')));
provenance = struct();
where = 'file';
if isfield(source_cfg, 'where')
    fail(caller, 'InvalidWhere', 'where belongs in sources.local.json.');
end
if isfield(source_cfg, 'source_id')
    id = required_text(source_cfg, 'source_id', caller);
    registry_file = option(opts, 'RegistryFile', ...
        fullfile(root, 'config', 'sources', 'sources.json'));
    dictionary = option(opts, 'RegistryDictionary', ...
        fullfile(root, 'config', 'sources', 'sources.keys.json'));
    local_file = option(opts, 'LocalFile', ...
        fullfile(fileparts(registry_file), 'sources.local.json'));
    read_opts = struct('Strict', option(opts, 'Strict', false));
    [registry, provenance] = UTILS.CONFIG_READ( ...
        registry_file, dictionary, read_opts);
    entries = rmfield(registry, {'si', 'provenance', 'config_version'});
    names = fieldnames(entries);
    for k = 1:numel(names)
        if isstruct(entries.(names{k})) && ...
                isfield(entries.(names{k}), 'where')
            fail(caller, 'InvalidWhere', ...
                'where belongs in sources.local.json.');
        end
    end
    if ~isempty(local_file) && isfile(local_file)
        read_opts.Base = entries;
        [registry, local_provenance] = UTILS.CONFIG_READ( ...
            local_file, dictionary, read_opts);
        provenance.files = [provenance.files; local_provenance.files];
        provenance.overrides = [provenance.overrides; ...
            local_provenance.overrides];
    end
    if ~isfield(registry, id) || ...
            any(strcmp(id, {'si', 'provenance', 'config_version'}))
        fail(caller, 'UnknownSource', 'The source_id is not registered.');
    end
    entry = registry.(id);
    entry.id = id;
    where = option(entry, 'where', 'file');
    if isfield(entry, 'where'), entry = rmfield(entry, 'where'); end
    data_root = option(opts, 'DataRoot', fullfile(root, 'data'));
    entry.file = resolve_path(entry.file, data_root, ...
        option(opts, 'CanonicalPaths', false));
    if ~isempty(entry.cache_file)
        entry.cache_file = resolve_path(entry.cache_file, data_root, ...
            option(opts, 'CanonicalPaths', false));
    end
    inline = rmfield(source_cfg, 'source_id');
    [source_cfg, changes] = UTILS.CONFIG_MERGE(entry, inline, '<inline>');
    provenance.overrides = [provenance.overrides; changes];
end

% Normalizing the fields used by the calling loader
if as_struct, source = source_cfg; else, source = struct(); end
source.id = required_text(source_cfg, 'id', caller);
source.file = required_text(source_cfg, 'file', caller);
if as_struct
    if ~isfield(source_cfg, 'variables') || isempty(source_cfg.variables)
        fail(caller, 'MissingField', 'Source variables are required.');
    end
    variables = variable_names(source_cfg.variables, caller);
else
    source.variable = required_text(source_cfg, 'variable', caller);
    variables = {source.variable};
end
fields = {'url', 'doi', 'sha256', 'cache_file'};
for k = 1:numel(fields)
    source.(fields{k}) = optional_text(source_cfg, fields{k}, caller);
end
if as_struct
    source.variables = variables;
else
    source.config_dir = option(source_cfg, 'config_dir', '');
    if isempty(source.config_dir)
        source.config_dir = fullfile(root, 'config');
    else
        source.config_dir = char(source.config_dir);
    end
end
if option(opts, 'ResolvePaths', ~as_struct)
    base = option(source, 'config_dir', fullfile(root, 'config'));
    canonical = option(opts, 'CanonicalPaths', false);
    source.file = resolve_path(source.file, base, canonical);
    if ~isempty(source.cache_file)
        source.cache_file = resolve_path(source.cache_file, base, canonical);
    end
end
if ~isempty(source.url) && isempty(source.sha256)
    warning(['sootMosaic:' caller ':MissingChecksum'], ...
        'Source "%s" has a URL without a SHA-256 digest.', source.id);
end

% Selecting the local file, reusable cache or download destination
resolved = source.file;
found = strcmp(where, 'file') && isfile(resolved);
if ~found && option(opts, 'ReuseCache', false) && ...
        ~isempty(source.cache_file)
    resolved = source.cache_file;
    found = isfile(resolved);
    if ~found
        alternate = regexprep(resolved, ...
            '(^|[\\/])\.sootmosaic-cache([\\/])', '$1.pfal-cache$2');
        if isfile(alternate)
            resolved = alternate;
            found = true;
        end
    end
end
if ~found
    if isempty(source.url)
        reason = 'MissingFileOnDisk';
        if as_struct, reason = 'MissingFile'; end
        fail(caller, reason, sprintf(['Source "%s" was not found at %s ', ...
            'and has no URL. Place the file there or set its url in ', ...
            'the source registry.'], source.id, source.file));
    end
    resolved = source.cache_file;
    if isempty(resolved)
        folder = option(opts, 'DefaultCacheDir', '');
        resolved = source.file;
        if ~isempty(folder)
            [~, name, ext] = fileparts(source.file);
            resolved = fullfile(folder, [name ext]);
        end
    end
    parent = fileparts(resolved);
    if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
    download = option(opts, 'Download', @websave);
    try
        download(resolved, source.url);
    catch err
        fail(caller, 'DownloadFailed', ...
            sprintf('Could not download source "%s" from %s: %s', ...
            source.id, source.url, err.message));
    end
end

% Checking bytes before loading the requested variables
if ~isempty(source.sha256)
    actual = UTILS.FILE_SHA256(resolved);
    if ~strcmpi(actual, source.sha256)
        fail(caller, 'ChecksumMismatch', ...
            sprintf(['SHA-256 mismatch for source "%s" (%s).\n', ...
            'Expected: %s\nActual:   %s'], source.id, resolved, ...
            source.sha256, actual));
    end
end
loaded = load(resolved, variables{:});
for k = 1:numel(variables)
    if ~isfield(loaded, variables{k})
        reason = 'MissingVariableInFile';
        if as_struct, reason = 'MissingVariable'; end
        fail(caller, reason, ...
            sprintf('Variable "%s" was not found in %s', ...
            variables{k}, resolved));
    end
end
if as_struct
    data = loaded;
    source.resolved_file = resolved;
    source.loaded_variables = variables;
else
    data = loaded.(source.variable);
    source.file = resolved;
end
end

function value = option(opts, name, fallback)
value = fallback;
if isfield(opts, name), value = opts.(name); end
end

function value = optional_text(src, name, caller)
value = '';
if isfield(src, name) && ~isempty(src.(name))
    item = src.(name);
    if ~((ischar(item) && isrow(item)) || ...
            (isstring(item) && isscalar(item) && ~ismissing(item)))
        fail(caller, 'InvalidText', 'Source fields must be scalar text.');
    end
    value = char(item);
end
end

function value = required_text(src, name, caller)
value = optional_text(src, name, caller);
if isempty(value)
    fail(caller, 'MissingField', sprintf('Source %s is required.', name));
end
end

function names = variable_names(value, caller)
if ischar(value)
    names = {value};
elseif isstring(value)
    names = cellstr(value(:));
elseif iscell(value)
    names = cellfun(@char, value(:), 'UniformOutput', false);
else
    fail(caller, 'InvalidVariables', 'variables must contain text names.');
end
end

function path = resolve_path(path, base, canonical)
absolute = ~isempty(regexp(path, '^[A-Za-z]:[\\/]', 'once')) || ...
    strncmp(path, '\\', 2) || strncmp(path, '//', 2) || ...
    strncmp(path, '/', 1);
if ~absolute, path = fullfile(base, path); end
if canonical
    try
        path = char(java.io.File(path).getCanonicalPath());
    catch
        path = char(path);
    end
end
end

function fail(caller, reason, message)
error(['sootMosaic:' caller ':' reason], '%s', message);
end
