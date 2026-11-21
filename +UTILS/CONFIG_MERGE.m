function [value, overrides] = CONFIG_MERGE(base, overlay, source, path, ...
    id_char)
% "CONFIG_MERGE" merges configuration objects and records overrides.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     base: Lower-precedence value
%     overlay: Higher-precedence value. Objects merge recursively; arrays...
%         ...replace, except object arrays with unique text or numeric ids....
%         ...An empty overlay leaves an id array unchanged. Every object...
%         ...entry over an id array must supply its id
%     source: Source file or layer label (default empty)
%     path: Key path at the merge root (default empty)
%     id_char: Id rows relative to the merge root, such as conditions[].id...
%         ...or [].id for an array at the root (default none). Their arrays...
%         ...match and check entries by string({char(id)}), which may be...
%         ...empty text. Each id must be nonempty as given and is stored...
%         ...unchanged
% ----------------------------------------------------------------------- %
%
% Outputs:
%     value: Merged value. Object arrays use cells when fields differ
%     overrides: Records with path, old_value, new_value and source
% ----------------------------------------------------------------------- %

if nargin < 3, source = ''; end
if nargin < 4, path = ''; end
if nargin < 5, id_char = {}; end
if ischar(id_char), id_char = {id_char}; end
overrides = struct('path', {}, 'old_value', {}, 'new_value', {}, ...
    'source', {});
char_key = any(strcmp(id_char, '[].id'));
[a, ids_a, list_a] = id_list(base, char_key);
[b, ids_b, list_b] = id_list(overlay, char_key);
if list_a && ~list_b && ~isempty(overlay) && ...
        (iscell(overlay) || isstruct(overlay))
    error('sootMosaic:CONFIG_MERGE:MissingId', ...
        'Every overlay entry in an id array must have an id.');
end
if list_a && isempty(overlay) && ...
        (isnumeric(overlay) || iscell(overlay) || isstruct(overlay))
    value = a;
elseif list_a && list_b
    count = numel(a);
    value = [a; cell(numel(b), 1)];
    ids_a = [ids_a; cell(numel(b), 1)];
    entry_ids = below(id_char, '[]');
    for k = 1:numel(b)
        j = find(cellfun(@(id) isequal(id, ids_b{k}), ids_a(1:count)), 1);
        entry_path = sprintf('%s[id=%s]', path, char(string(ids_b{k})));
        if isempty(j)
            count = count + 1;
            value{count} = b{k};
            ids_a{count} = ids_b{k};
        else
            [value{j}, records] = UTILS.CONFIG_MERGE( ...
                value{j}, b{k}, source, entry_path, entry_ids);
            overrides = [overrides; records]; %#ok<AGROW>
        end
    end
    value = value(1:count);
elseif isstruct(base) && isscalar(base) && ...
        isstruct(overlay) && isscalar(overlay)
    value = base;
    names = fieldnames(overlay);
    for k = 1:numel(names)
        key = names{k};
        child = key;
        if ~isempty(path), child = [path '.' key]; end
        if isfield(base, key)
            [value.(key), records] = UTILS.CONFIG_MERGE( ...
                base.(key), overlay.(key), source, child, ...
                below(id_char, key));
            overrides = [overrides; records]; %#ok<AGROW>
        else
            value.(key) = overlay.(key);
        end
    end
else
    value = overlay;
    if ~isequaln(comparable(base), comparable(overlay))
        overrides(1, 1) = struct('path', path, 'old_value', {base}, ...
            'new_value', {overlay}, 'source', source);
    end
end
end

function value = comparable(value)
% Resolving internal decoded-array and null values for the change record
if isa(value, 'function_handle')
    value = value();
elseif iscell(value)
    value = cellfun(@comparable, value, 'UniformOutput', false);
elseif isstruct(value)
    names = fieldnames(value);
    for j = 1:numel(value)
        for k = 1:numel(names)
            value(j).(names{k}) = comparable(value(j).(names{k}));
        end
    end
end
end

function [items, ids, yes] = id_list(value, char_key)
items = {};
ids = {};
yes = false;
if isstruct(value) && ~isscalar(value) && ~isempty(value)
    items = num2cell(value(:));
elseif iscell(value) && ~isempty(value) && all(cellfun( ...
        @(x) isstruct(x) && isscalar(x), value(:)))
    items = value(:);
else
    return
end
has_id = cellfun(@(x) isfield(x, 'id'), items);
if ~all(has_id)
    if any(has_id)
        error('sootMosaic:CONFIG_MERGE:MissingId', ...
            'Every entry in an id array must have an id.');
    end
    return
end
ids = cell(size(items));
for k = 1:numel(items)
    id = items{k}.id;
    if char_key
        id = text_key(id);
    elseif ~((ischar(id) && isrow(id) && ~isempty(id)) || ...
            (isnumeric(id) && isscalar(id) && isfinite(id)))
        error('sootMosaic:CONFIG_MERGE:InvalidId', ...
            'Array ids must be nonempty text or finite scalar numbers.');
    end
    if any(cellfun(@(x) isequal(x, id), ids(1:k - 1)))
        error('sootMosaic:CONFIG_MERGE:DuplicateId', ...
            'An object array contains a repeated id.');
    end
    ids{k} = id;
end
yes = true;
end

function key = text_key(id)
% Comparing a nonempty id by its char conversion, empty text included
id = comparable(id);
key = [];
if ~isempty(id)
    try
        key = string({char(id)});
    catch
        key = [];
    end
end
if ~(isstring(key) && isscalar(key))
    error('sootMosaic:CONFIG_MERGE:InvalidId', ...
        'Array ids must be nonempty and convert to one row of text.');
end
end

function paths = below(paths, key)
% Selecting the id rows under one member, relative to that member
if isempty(paths), return; end
prefix = [key '.'];
paths = paths(startsWith(paths, prefix) | startsWith(paths, [key '[]']));
for k = 1:numel(paths)
    if startsWith(paths{k}, prefix)
        paths{k} = paths{k}(numel(prefix) + 1:end);
    else
        paths{k} = paths{k}(numel(key) + 1:end);
    end
end
end
