function [cfg, provenance] = CONFIG_READ(file, dictionary, opts)
% "CONFIG_READ" resolves and validates a configuration dictionary.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     file: JSON file path; extends names one file relative to its file
%     dictionary: JSON file, row structure array or cell array of rows....
%         ...Each row has path and type; optional fields are unit, default,...
%         ...required, allowed, min, max, alias_of, length, shape, open...
%         ...and allow_nan. Shape is the decoded size vector. Open true...
%         ...allows unlisted members of an object with no child rows....
%         ...Paths use dots and [] for array entries, such as entries[].id....
%         ...Types are number, integer, logical, text, object, vector,...
%         ...matrix, list of text and list of objects. N numbers specifies...
%         ...a vector length. Numbers and integers denote numeric vectors....
%         ...Number or none maps null or "none" using none_value ("Inf"...
%         ...or "empty", default "Inf"). Integer or empty accepts null...
%         ...and []. Text or none maps null to empty text. An alias row...
%         ...names a canonical path in alias_of.
%         ...Coerce "double" or "char" applies that conversion before...
%         ...type checks. Double accepts decoded singleton arrays....
%         ...Row_vector reshapes converted vectors to one row....
%         ...Preserve_empty retains null and [] as [] for text or none.
%         ...Empty_default uses the row default for null or empty input....
%         ...Normalize_text applies lower(strtrim(...)) after coercion....
%         ...Defer_defaults fills child defaults only when the object is...
%         ...present, preserving a required section with optional keys.
%         ...Native_json retains decoded values for selected rows....
%         ...When used, unlisted root members retain decoded values too....
%         ...Type any with open true leaves nested metadata uninterpreted.
%     opts: Optional structure with Strict (false), MaxDepth (16 files),...
%         ...SupportedVersion (1), Base (resolved lower-precedence object)...
%         ...and Overrides (direct arguments, highest precedence)....
%         ...QA and release callers set Strict to true. Base can hold the...
%         ...resolved profile, with stage values merged over common values.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Resolved values, si with the same paths in SI units, and...
%         ...provenance. Comment fields are discarded at every level
%     provenance: Files in base-to-overlay order with file, sha256 and...
%         ...config_version and notes, plus overrides with path, old_value,...
%         ...new_value and source. Dictionary files are recorded separately
% ----------------------------------------------------------------------- %
%
% Defaults are dictionary values below Base. Aliases are mapped per file;...
%     ...a canonical key in that file takes precedence. Warnings occur once...
%     ...per dictionary path per call. Arrays of objects are cell columns,...
%     ...including single-entry arrays. Numeric arrays retain decoded shape.
% jsondecode collapses a one-element numeric array to a scalar. Array...
%     ...identity is retained until validation. Scalar types reject arrays;...
%     ...vector and matrix rows with length or shape reject scalar input....
%     ...Without either constraint these array types accept scalars....
%     ...Length checks numel and shape checks size after decoding.
% A leading UTF-8 byte order mark is skipped and noted per source file;...
%     ...digests cover the original bytes. Profile and instrument registry...
%     ...digests are supplied by their respective loaders.
% Units are dictionary-driven, including keys without a unit suffix....
%     ...Suffixes _lpm, _nm, _kpa, _m, _s, _pa, _k, _kg_m3, _fg and _ugm3...
%     ...must agree with the unit for rows with status "new". Other rows use...
%     ...their dictionary unit regardless of spelling. Unitless counts and...
%     ...presentation units retain their scale. Paths are not expanded.
% Micrograms per cubic metre use ugm3, ug/m3 or micrograms per m3, with...
%     ...a factor of 1e-9 to kg/m3. Hashing uses UTILS.FILE_SHA256 with...
%     ...the JVM available. Otherwise digests are empty with the source...
%     ...note "digest skipped, no JVM".
% ----------------------------------------------------------------------- %

if nargin < 3, opts = struct(); end
if ~isstruct(opts) || ~isscalar(opts)
    error('sootMosaic:CONFIG_READ:InvalidOptions', ...
        'Reader options must be a scalar structure.');
end
strict = option(opts, 'Strict', false);
max_depth = option(opts, 'MaxDepth', 16);
version = option(opts, 'SupportedVersion', 1);
if ~islogical(strict) || ~isscalar(strict) || ...
        ~positive_integer(max_depth) || ~positive_integer(version)
    error('sootMosaic:CONFIG_READ:InvalidOptions', ...
        'Strict must be logical; depth and version must be positive integers.');
end
dict_source = struct('file', {}, 'sha256', {}, 'notes', {});
if ischar(dictionary) || (isstring(dictionary) && isscalar(dictionary))
    dict_file = canonical(dictionary);
    [dictionary, dict_notes] = read_json(dict_file);
    [dict_hash, dict_notes] = file_digest(dict_file, dict_notes);
    dict_source = struct('file', dict_file, ...
        'sha256', dict_hash, 'notes', {dict_notes});
end
if isstruct(dictionary), dictionary = num2cell(dictionary(:)); end
if isnumeric(dictionary) && isempty(dictionary), dictionary = {}; end
if ~iscell(dictionary)
    error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
        'The dictionary must be an array of rows.');
end
schema = node();
paths = cell(1, numel(dictionary));
for k = 1:numel(dictionary)
    row = dictionary{k};
    if ~isstruct(row) || ~isscalar(row) || ~isfield(row, 'path') || ...
            ~ischar(row.path) || ~isfield(row, 'type') || ~ischar(row.type)
        error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
            'Every dictionary row must have text path and type fields.');
    end
    row_names = fieldnames(row);
    for j = 1:numel(row_names)
        if ~strcmp(row_names{j}, 'default')
            row.(row_names{j}) = clean_nulls(row.(row_names{j}));
        end
    end
    dictionary{k} = row;
    if any(strcmp(paths, row.path))
        error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
            'Repeated dictionary path %s.', row.path);
    end
    paths{k} = row.path;
    schema = insert(schema, strsplit(row.path, '.'), row);
end
for k = 1:numel(dictionary)
    row = dictionary{k};
    target = option(row, 'alias_of', '');
    if ~isempty(target)
        j = find(strcmp(paths, target), 1);
        if isempty(j) || ~isempty(option(dictionary{j}, 'alias_of', ''))
            error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
                'Alias %s must name a canonical dictionary row.', row.path);
        end
    end
end
warned_aliases = false(size(dictionary));
native_rows = cellfun(@(r) option(r, 'native_json', false), dictionary);
native_paths = paths(native_rows);
warned_unknown = {};
files = struct('file', {}, 'sha256', {}, 'config_version', {}, 'notes', {});
records = struct('path', {}, 'old_value', {}, 'new_value', {}, 'source', {});
base = option(opts, 'Base', struct());
direct = option(opts, 'Overrides', struct());
require_object(base, 'Base');
require_object(direct, 'Overrides');
base = prepare(base);
[base, base_records] = UTILS.CONFIG_MERGE( ...
    dictionary_defaults(schema), base, '<base>');
[cfg, chain_records] = chain(canonical(file), {}, 1);
direct = prepare(direct);
[cfg, direct_records] = UTILS.CONFIG_MERGE(cfg, direct, '<arguments>');
records = [records; base_records; chain_records; direct_records];
unknowns(cfg, schema, '');
[cfg, si] = validate_object(cfg, schema, '');
if ~isfield(cfg, 'config_version'), cfg.config_version = 1; end
check_version(cfg.config_version);
cfg.si = si;
provenance = struct('files', files, 'dictionary', dict_source, ...
    'overrides', clean_nulls(records));
cfg.provenance = provenance;

    function [value, changes] = chain(name, stack, depth)
        if (ispc && any(strcmpi(stack, name))) || any(strcmp(stack, name))
            error('sootMosaic:CONFIG_READ:ExtendsCycle', ...
                'The extends chain repeats %s.', name);
        end
        if depth > max_depth
            error('sootMosaic:CONFIG_READ:ExtendsDepth', ...
                'The extends chain exceeds %d files.', max_depth);
        end
        if isempty(native_paths)
            [value, notes] = read_json(name);
        else
            [value, notes, decoded] = read_json(name);
            if iscell(value) && isscalar(value) && ...
                    isstruct(decoded) && isscalar(decoded)
                value = value{1};
            end
            for native_index = 1:numel(native_paths)
                parts = strsplit(native_paths{native_index}, '.');
                [item, found] = get_path(decoded, parts);
                if found, value = set_path(value, parts, item); end
            end
            if isstruct(decoded) && isscalar(decoded)
                native_names = fieldnames(decoded);
                for native_name_index = 1:numel(native_names)
                    native_key = native_names{native_name_index};
                    if ~isfield(schema.children, native_key)
                        value.(native_key) = decoded.(native_key);
                    end
                end
            end
        end
        require_object(value, name);
        v = option(value, 'config_version', 1);
        check_version(v);
        parent = option(value, 'extends', '');
        if ~ischar(parent) || (~isempty(parent) && ~isrow(parent))
            error('sootMosaic:CONFIG_READ:InvalidExtends', ...
                'extends must name one file in %s.', name);
        end
        if isfield(value, 'extends'), value = rmfield(value, 'extends'); end
        value = prepare(value);
        changes = records;
        lower = base;
        if ~isempty(parent)
            if ~absolute_path(parent)
                parent = fullfile(fileparts(name), parent);
            end
            [lower, changes] = chain(canonical(parent), [stack {name}], ...
                depth + 1);
        end
        [value, extra] = UTILS.CONFIG_MERGE(lower, value, name);
        changes = [changes; extra];
        [hash, notes] = file_digest(name, notes);
        files(end + 1, 1) = struct('file', name, ...
            'sha256', hash, 'config_version', v, ...
            'notes', {notes});
    end

    function check_version(v)
        if ~positive_integer(v)
            error('sootMosaic:CONFIG_READ:InvalidVersion', ...
                'config_version must be a positive integer.');
        end
        if v > version
            error('sootMosaic:CONFIG_READ:UnsupportedVersion', ...
                'Configuration version %g exceeds supported version %g.', ...
                v, version);
        end
    end

    function value = prepare(value)
        value = strip_comments(value);
        if isfield(value, 'si') || isfield(value, 'provenance')
            error('sootMosaic:CONFIG_READ:ReservedKey', ...
                'si and provenance are reserved output fields.');
        end
        for n = 1:numel(dictionary)
            r = dictionary{n};
            target = option(r, 'alias_of', '');
            if isempty(target), continue; end
            [value, found] = move_alias(value, strsplit(r.path, '.'), ...
                strsplit(target, '.'));
            if found && ~warned_aliases(n)
                warning('sootMosaic:CONFIG_READ:Alias', ...
                    'Key %s is an alias of %s.', r.path, target);
                warned_aliases(n) = true;
            end
        end
        unknowns(value, schema, '');
    end

    function unknowns(value, tree, prefix)
        if ~isstruct(value) || ~isscalar(value), return; end
        if isempty(fieldnames(tree.children)) && ...
                any(strcmp(option(tree.row, 'type', ''), ...
                {'object', 'any'})) && ...
                isequal(option(tree.row, 'open', false), true)
            return
        end
        names = fieldnames(value);
        for n = 1:numel(names)
            key = names{n};
            p = join_path(prefix, key);
            if isempty(prefix) && strcmp(key, 'config_version'), continue; end
            if ~isfield(tree.children, key)
                if strict
                    error('sootMosaic:CONFIG_READ:UnknownKey', ...
                        'Unknown key %s; nearest known key is %s.', ...
                        p, nearest(p, paths));
                elseif ~any(strcmp(warned_unknown, p))
                    warning('sootMosaic:CONFIG_READ:UnknownKey', ...
                        'Unknown key %s; nearest known key is %s.', ...
                        p, nearest(p, paths));
                    warned_unknown{end + 1} = p; %#ok<AGROW>
                end
                child = node();
            else
                child = tree.children.(key);
            end
            item = value.(key);
            if isstruct(item) && ~isscalar(item)
                item = arrayfun(@(x) x, item(:), 'UniformOutput', false);
            end
            if iscell(item)
                for j = 1:numel(item)
                    unknowns(item{j}, child, [p '[]']);
                end
            else
                unknowns(item, child, p);
            end
        end
    end
end

function [value, si] = validate_object(value, tree, prefix)
si = struct();
names = fieldnames(tree.children);
for k = 1:numel(names)
    key = names{k};
    child = tree.children.(key);
    row = child.row;
    path = join_path(prefix, key);
    if ~isempty(option(row, 'alias_of', '')), continue; end
    present = isfield(value, key);
    if ~present
        if isfield(row, 'default')
            value.(key) = row.default;
        elseif option(row, 'required', false)
            error('sootMosaic:CONFIG_READ:MissingKey', ...
                'Required key %s is missing.', path);
        elseif ~child.array && ~isempty(fieldnames(child.children))
            [nested, nested_si] = validate_object(struct(), child, path);
            if ~isempty(fieldnames(nested))
                value.(key) = nested;
                si.(key) = nested_si;
            end
            continue
        else
            continue
        end
    end
    item = value.(key);
    if isfield(row, 'type'), item = check_type(item, row, path); end
    if child.array && ~isempty(fieldnames(child.children))
        if isnumeric(item) && isempty(item), item = cell(0, 1); end
        if isstruct(item), item = num2cell(item(:)); end
        if ~iscell(item) || ~all(cellfun( ...
                @(x) isstruct(x) && isscalar(x), item(:)))
            error('sootMosaic:CONFIG_READ:InvalidType', ...
                '%s must be an array of objects.', path);
        end
        item_si = cell(size(item));
        for j = 1:numel(item)
            [item{j}, item_si{j}] = validate_object( ...
                item{j}, child, [path '[]']);
        end
    elseif ~isempty(fieldnames(child.children))
        require_object(item, path);
        [item, item_si] = validate_object(item, child, path);
    else
        item = clean_nulls(item);
        item_si = item;
    end
    if child.array, [item, ~] = UTILS.CONFIG_MERGE(item, item); end
    if isnumeric(item)
        item_si = item .* unit_factor(option(row, 'unit', 'none'), key, ...
            strcmp(option(row, 'status', ''), 'new'));
    end
    value.(key) = item;
    si.(key) = item_si;
end
value = clean_nulls(value);
end

function value = check_type(value, row, path)
type = lower(strtrim(row.type));
is_null = isequal(value, @null_marker);
is_array = isa(value, 'function_handle') && ~is_null;
if is_array, value = value(); end
if option(row, 'empty_default', false) && (is_null || isempty(value))
    value = clean_nulls(row.default);
    is_null = false;
    is_array = false;
end
coerce = option(row, 'coerce', '');
if is_null && ~isempty(coerce), value = []; end
if strcmp(coerce, 'double')
    value = double(value);
    is_array = false;
elseif strcmp(coerce, 'char')
    value = char(value);
elseif ~isempty(coerce)
    error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
        'Unknown conversion %s for %s.', coerce, path);
end
if option(row, 'row_vector', false), value = reshape(value, 1, []); end
if option(row, 'normalize_text', false)
    value = lower(strtrim(value));
end
if strcmp(type, 'number or none')
    if is_null || (ischar(value) && strcmp(value, 'none'))
        meaning = option(row, 'none_value', 'Inf');
        if strcmp(meaning, 'Inf')
            value = Inf;
        elseif strcmp(meaning, 'empty')
            value = [];
        else
            error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
                'none_value for %s must be Inf or empty.', path);
        end
        return
    end
    type = 'number';
elseif strcmp(type, 'text or none')
    if is_null || (isnumeric(value) && isempty(value))
        if option(row, 'preserve_empty', false)
            value = [];
            return
        end
        value = '';
        return
    end
    type = 'text';
elseif strcmp(type, 'integer or empty')
    if is_null || (isnumeric(value) && isempty(value))
        value = [];
        return
    end
    type = 'integer';
end
n = regexp(type, '^(\d+) numbers$', 'tokens', 'once');
if ~isempty(n)
    row.length = str2double(n{1});
    type = 'vector';
end
switch type
    case 'any'
        value = clean_nulls(value);
        return
    case {'number', 'integer'}
        ok = ~is_array && isnumeric(value) && isscalar(value) && isreal(value);
    case {'vector', 'numbers', 'integers'}
        ok = isnumeric(value) && isreal(value) && ...
            (isvector(value) || isempty(value));
    case 'matrix'
        ok = isnumeric(value) && isreal(value) && ismatrix(value);
    case {'logical', 'boolean'}
        ok = ~is_array && islogical(value) && isscalar(value);
    case 'text'
        ok = ischar(value) && (isrow(value) || isempty(value));
    case 'object'
        ok = isstruct(value) && isscalar(value);
    case 'list of text'
        if isnumeric(value) && isempty(value), value = cell(0, 1); end
        ok = iscell(value) && all(cellfun( ...
            @(x) ischar(x) && (isrow(x) || isempty(x)), value(:)));
    case 'list of objects'
        if isnumeric(value) && isempty(value), value = cell(0, 1); end
        if isstruct(value), value = num2cell(value(:)); end
        ok = iscell(value) && all(cellfun( ...
            @(x) isstruct(x) && isscalar(x), value(:)));
    otherwise
        error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
            'Unknown dictionary type %s for %s.', type, path);
end
if ~ok
    error('sootMosaic:CONFIG_READ:InvalidType', ...
        '%s must have type %s.', path, row.type);
end
if any(strcmp(type, {'vector', 'numbers', 'integers', 'matrix'})) && ...
        (isfield(row, 'length') || isfield(row, 'shape')) && ...
        isscalar(value) && ~is_array
    error('sootMosaic:CONFIG_READ:InvalidType', ...
        '%s requires an array, not a scalar.', path);
end
if isnumeric(value)
    allow_nan = option(row, 'allow_nan', false);
    if any(isinf(value(:))) || (any(isnan(value(:))) && ~allow_nan)
        error('sootMosaic:CONFIG_READ:Nonfinite', ...
            '%s contains a nonfinite number or a disallowed null.', path);
    end
    if any(strcmp(type, {'integer', 'integers'})) && ...
            any(value(:) ~= fix(value(:)))
        error('sootMosaic:CONFIG_READ:InvalidInteger', ...
            '%s must contain integer-valued numbers.', path);
    end
    if (isfield(row, 'min') && any(value(:) < row.min)) || ...
            (isfield(row, 'max') && any(value(:) > row.max))
        error('sootMosaic:CONFIG_READ:OutOfRange', ...
            '%s is outside its dictionary bounds.', path);
    end
end
if isfield(row, 'length') && numel(value) ~= row.length
    error('sootMosaic:CONFIG_READ:InvalidLength', ...
        '%s must contain %g elements.', path, row.length);
end
if isfield(row, 'shape') && ~isequal(size(value), row.shape(:)')
    error('sootMosaic:CONFIG_READ:InvalidShape', ...
        '%s must have decoded shape %s.', path, mat2str(row.shape));
end
if isfield(row, 'allowed')
    allowed = row.allowed;
    if ~iscell(allowed), allowed = num2cell(allowed); end
    if ~any(cellfun(@(x) isequaln(x, value), allowed))
        error('sootMosaic:CONFIG_READ:InvalidValue', ...
            '%s is not an allowed value.', path);
    end
end
end

function factor = unit_factor(unit, key, enforce_suffix)
units = {'L/min', 'lpm', 'nm', 'kPa', 'kpa', 'fg', 'm', 's', 'Pa', ...
    'pa', 'K', 'k', 'kg/m3', 'kg_m3', 'm3/s', 'm/s', 'Pa s', ...
    'kg/mol', 'J/K', '1/mol', 'J/(mol K)', 'C', 'F/m', ...
    'ugm3', 'ug/m3', 'micrograms per m3'};
factors = [1e-3 / 60, 1e-3 / 60, 1e-9, 1e3, 1e3, 1e-18, ...
    ones(1, 17), 1e-9, 1e-9, 1e-9];
identity = {'none', '1', '-', 'count', 'counts', 'points', ...
    'points per orientation', 'angles', 'primaries', 'steps', 'bins', ...
    'row', 'attempts', 'fraction', 'fractions', 'fraction of dp', ...
    'fraction of the step', 'fraction of aggregates', ...
    'smallest primary diameters', 'relative standard error', ...
    'aggregate count ratio', 'dpi', 'pt', 'normalized units', ...
    'figure units', 'presentation'};
j = find(strcmp(units, unit), 1);
if ~isempty(j)
    factor = factors(j);
elseif any(strcmp(identity, unit))
    factor = 1;
else
    error('sootMosaic:CONFIG_READ:UnknownUnit', ...
        'Unknown unit %s for %s.', unit, key);
end
if ~enforce_suffix, return; end
suffixes = {'_f_m', '_c', '_kg_m3', '_lpm', '_kpa', '_nm', '_fg', '_m', '_s', ...
    '_pa', '_k', '_ugm3'};
expected = {'F/m', 'C', 'kg/m3', 'L/min', 'kPa', 'nm', 'fg', ...
    'm', 's', 'Pa', 'K', 'ug/m3'};
for k = 1:numel(suffixes)
    if endsWith(key, suffixes{k})
        synonyms = {{'F/m'}, {'C'}, {'kg/m3', 'kg_m3'}, {'L/min', 'lpm'}, ...
            {'kPa', 'kpa'}, {'nm'}, {'fg'}, {'m'}, {'s'}, ...
            {'Pa', 'pa'}, {'K', 'k'}, {'ugm3', 'ug/m3', 'micrograms per m3'}};
        if ~any(strcmp(synonyms{k}, unit))
            error('sootMosaic:CONFIG_READ:UnitMismatch', ...
                'Key %s requires unit %s.', key, expected{k});
        end
        break
    end
end
end

function tree = node()
tree = struct('row', struct(), 'children', struct(), 'array', false);
end

function value = dictionary_defaults(tree)
value = struct();
names = fieldnames(tree.children);
for k = 1:numel(names)
    key = names{k};
    child = tree.children.(key);
    if ~isempty(option(child.row, 'alias_of', '')), continue; end
    if option(child.row, 'defer_defaults', false), continue; end
    if isfield(child.row, 'default')
        value.(key) = child.row.default;
    elseif ~child.array
        item = dictionary_defaults(child);
        if ~isempty(fieldnames(item)), value.(key) = item; end
    end
end
end

function tree = insert(tree, parts, row)
part = parts{1};
array = endsWith(part, '[]');
if array, part = part(1:end - 2); end
valid_name(part);
if ~isfield(tree.children, part), tree.children.(part) = node(); end
child = tree.children.(part);
child.array = child.array || array;
if isscalar(parts)
    child.row = row;
    child.array = child.array || strcmp(row.type, 'list of objects');
else
    child = insert(child, parts(2:end), row);
end
tree.children.(part) = child;
end

function [value, found] = move_alias(value, from, to)
found = false;
array = find(endsWith(from, '[]'), 1);
if ~isempty(array)
    if ~strcmp(from{1}, to{1})
        error('sootMosaic:CONFIG_READ:InvalidDictionary', ...
            'Aliases in arrays must share their array ancestors.');
    end
    key = strrep(from{1}, '[]', '');
    if ~isfield(value, key), return; end
    if endsWith(from{1}, '[]')
        items = value.(key);
        if isstruct(items), items = num2cell(items(:)); end
        if ~iscell(items), return; end
        for k = 1:numel(items)
            [items{k}, yes] = move_alias(items{k}, from(2:end), to(2:end));
            found = found || yes;
        end
        value.(key) = items;
    else
        [value.(key), found] = move_alias( ...
            value.(key), from(2:end), to(2:end));
    end
    return
end
[item, found] = get_path(value, from);
if found
    [~, exists] = get_path(value, to);
    if ~exists, value = set_path(value, to, item); end
    value = remove_path(value, from);
end
end

function [value, found] = get_path(value, parts)
found = isstruct(value) && isscalar(value) && isfield(value, parts{1});
if ~found, value = []; return; end
value = value.(parts{1});
if numel(parts) > 1, [value, found] = get_path(value, parts(2:end)); end
end

function value = set_path(value, parts, item)
require_object(value, strjoin(parts, '.'));
if isscalar(parts)
    value.(parts{1}) = item;
else
    if ~isfield(value, parts{1}), value.(parts{1}) = struct(); end
    value.(parts{1}) = set_path(value.(parts{1}), parts(2:end), item);
end
end

function value = remove_path(value, parts)
if isscalar(parts)
    value = rmfield(value, parts{1});
else
    value.(parts{1}) = remove_path(value.(parts{1}), parts(2:end));
end
end

function value = strip_comments(value)
if isstruct(value)
    if isfield(value, 'comment'), value = rmfield(value, 'comment'); end
    names = fieldnames(value);
    for j = 1:numel(value)
        for k = 1:numel(names)
            value(j).(names{k}) = strip_comments(value(j).(names{k}));
        end
    end
elseif iscell(value)
    value = cellfun(@strip_comments, value, 'UniformOutput', false);
end
end

function value = clean_nulls(value)
if isa(value, 'function_handle')
    value = value();
elseif isstruct(value)
    names = fieldnames(value);
    for j = 1:numel(value)
        for k = 1:numel(names)
            value(j).(names{k}) = clean_nulls(value(j).(names{k}));
        end
    end
elseif iscell(value)
    value = cellfun(@clean_nulls, value, 'UniformOutput', false);
end
end

function value = option(opts, key, fallback)
if isfield(opts, key), value = opts.(key); else, value = fallback; end
end

function yes = positive_integer(value)
yes = isnumeric(value) && isscalar(value) && isfinite(value) && ...
    isreal(value) && value >= 1 && value == fix(value);
end

function require_object(value, path)
if ~isstruct(value) || ~isscalar(value)
    error('sootMosaic:CONFIG_READ:InvalidObject', ...
        '%s must be an object.', path);
end
end

function path = join_path(prefix, key)
path = key;
if ~isempty(prefix), path = [prefix '.' key]; end
end

function name = canonical(name)
if ~(ischar(name) || (isstring(name) && isscalar(name))) || isempty(name)
    error('sootMosaic:CONFIG_READ:InvalidPath', ...
        'A nonempty file path is required.');
end
name = char(name);
if ~absolute_path(name), name = fullfile(pwd, name); end
[ok, info] = fileattrib(name);
if ok, name = info.Name; else, name = fullfile(name); end
end

function yes = absolute_path(name)
yes = startsWith(name, '/') || startsWith(name, '\') || ...
    ~isempty(regexp(name, '^[A-Za-z]:[\\/]', 'once'));
end

function valid_name(key)
if isempty(key) || numel(key) > namelengthmax || ...
        ~strcmp(key, matlab.lang.makeValidName(key))
    error('sootMosaic:CONFIG_READ:InvalidName', ...
        'Key %s cannot be represented without renaming.', key);
end
end

function best = nearest(path, paths)
best = '<none>';
distance = Inf;
for k = 1:numel(paths)
    other = paths{k};
    previous = 0:numel(other);
    for i = 1:numel(path)
        current = [i zeros(1, numel(other))];
        for j = 1:numel(other)
            current(j + 1) = min([current(j) + 1, previous(j + 1) + 1, ...
                previous(j) + (path(i) ~= other(j))]);
        end
        previous = current;
    end
    if previous(end) < distance
        distance = previous(end);
        best = other;
    end
end
end

function [value, notes, native_value] = read_json(file)
native_value = [];
if ~isfile(file)
    error('sootMosaic:CONFIG_READ:MissingFile', ...
        'Configuration file does not exist: %s', file);
end
try
    fid = fopen(file, 'rb');
    if fid < 0
        error('sootMosaic:CONFIG_READ:ReadFailed', 'Cannot read %s.', file);
    end
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8')';
catch err
    error('sootMosaic:CONFIG_READ:ReadFailed', '%s', err.message);
end
notes = {};
if numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191]))
    bytes = bytes(4:end);
    notes = {'Leading UTF-8 byte order mark skipped.'};
end
text = native2unicode(bytes, 'UTF-8');
if ~isempty(text) && text(1) == char(65279)
    text = text(2:end);
    notes = {'Leading UTF-8 byte order mark skipped.'};
end
% Decoding member names as text before constructing objects
tokens = regexp(text, '"(?:\\.|[^"\\])*"|[{}\[\],:]|[^\s{}\[\],:]+', ...
    'match');
index = 1;
value = parse();
if index <= numel(tokens)
    error('sootMosaic:CONFIG_READ:InvalidJSON', ...
        'Unexpected content after the JSON value.');
end
if nargout > 2, native_value = jsondecode(text); end

    function item = parse()
        if index > numel(tokens), invalid_json(); end
        token = tokens{index};
        index = index + 1;
        if strcmp(token, '{')
            item = struct();
            if at('}'), index = index + 1; return; end
            while true
                if index > numel(tokens) || ~startsWith(tokens{index}, '"')
                    invalid_json();
                end
                try
                    key = jsondecode(tokens{index});
                catch err
                    error('sootMosaic:CONFIG_READ:InvalidJSON', '%s', err.message);
                end
                valid_name(key);
                index = index + 1;
                if ~at(':'), invalid_json(); end
                index = index + 1;
                if isfield(item, key)
                    error('sootMosaic:CONFIG_READ:DuplicateKey', ...
                        'Repeated JSON member %s.', key);
                end
                item.(key) = parse();
                if at('}'), index = index + 1; break; end
                if ~at(','), invalid_json(); end
                index = index + 1;
            end
        elseif strcmp(token, '[')
            start = index - 1;
            item = cell(0, 1);
            if ~at(']')
                while true
                    item{end + 1, 1} = parse(); %#ok<AGROW>
                    if at(']'), break; end
                    if ~at(','), invalid_json(); end
                    index = index + 1;
                end
            end
            index = index + 1;
            if isempty(item) || all(cellfun(@(x) isnumeric(x) || ...
                    islogical(x) || isa(x, 'function_handle'), item))
                item = jsondecode(strjoin(tokens(start:index - 1), ''));
                if ~isempty(item)
                    decoded = item;
                    item = @() decoded;
                end
            end
        elseif strcmp(token, 'null')
            item = @null_marker;
        else
            number = ~isempty(regexp(token, ...
                '^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$', 'once'));
            if ~number && ~startsWith(token, '"') && ...
                    ~any(strcmp(token, {'true', 'false'}))
                invalid_json();
            end
            try
                item = jsondecode(token);
            catch err
                error('sootMosaic:CONFIG_READ:InvalidJSON', '%s', err.message);
            end
        end
    end

    function yes = at(token)
        yes = index <= numel(tokens) && strcmp(tokens{index}, token);
    end

    function invalid_json()
        error('sootMosaic:CONFIG_READ:InvalidJSON', ...
            'Invalid JSON syntax in %s near token %d.', file, index);
    end
end

function value = null_marker()
value = [];
end

function [hash, notes] = file_digest(file, notes)
if usejava('jvm')
    hash = UTILS.FILE_SHA256(file);
else
    hash = '';
    notes{end + 1} = 'digest skipped, no JVM';
end
end
