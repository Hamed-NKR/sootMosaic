function value = PUBLIC_COPY(value)
% "PUBLIC_COPY" returns a copy of a value with local paths reduced to names.
% Structures, structure arrays, cells and table variables are copied...
%     ...recursively. A text value is a local path when it is absolute...
%     ...(drive letter, network share or leading slash) or when it holds...
%     ...a folder separator under a path field such as file, files,...
%     ...config_dir, results_root, cache_file, dir_wsp or OutputDir. A...
%     ...path keeps its file name with extension, a folder its final...
%     ...folder name. In change records with path, old_value, new_value...
%     ...and source, source is a path and the two values follow the last...
%     ...part of the record path. URLs, digests, numbers, shapes and...
%     ...other text are kept.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     value: Any value to be written to disk
% ----------------------------------------------------------------------- %
%
% Outputs:
%     value: Copy for saving. The value in the caller is unchanged
% ----------------------------------------------------------------------- %

value = copy_value(value, '');
end

function value = copy_value(value, key)
% Copying one value under the name of the field that holds it
if isstruct(value)
    names = fieldnames(value);
    record = all(ismember({'path', 'old_value', 'new_value', 'source'}, ...
        names));
    for j = 1:numel(value)
        for k = 1:numel(names)
            child = names{k};
            context = child;
            if record && any(strcmp(child, {'old_value', 'new_value'}))
                context = last_part(value(j).path);
            elseif record && strcmp(child, 'source')
                context = 'file';
            end
            value(j).(child) = copy_value(value(j).(child), context);
        end
    end
elseif iscell(value)
    for j = 1:numel(value)
        value{j} = copy_value(value{j}, key);
    end
elseif istable(value)
    names = value.Properties.VariableNames;
    for k = 1:numel(names)
        value.(names{k}) = copy_value(value.(names{k}), names{k});
    end
    value.Properties.UserData = copy_value(value.Properties.UserData, '');
elseif ischar(value)
    if ~isempty(value) && isrow(value)
        value = reduce_text(value, path_key(key));
    end
elseif isstring(value)
    for j = 1:numel(value)
        if ~ismissing(value(j))
            value(j) = string(reduce_text(char(value(j)), path_key(key)));
        end
    end
end
end

function text = reduce_text(text, is_path_key)
% Reducing a local path to its final name
if is_url(text)
    return
end
absolute = ~isempty(regexp(text, ...
    '^([A-Za-z]:[\\/]|\\\\|/|~[\\/]|file:/)', 'once'));
if absolute || (is_path_key && any(text == '/' | text == '\'))
    text = regexprep(text, '^file:/*', '');
    text = regexprep(text, '[\\/]+$', '');
    parts = regexp(text, '[\\/]', 'split');
    text = parts{end};
    if ~isempty(regexp(text, '^[A-Za-z]:$', 'once'))
        text = '';
    end
end
end

function tf = is_url(text)
% Network addresses other than file URLs
tf = ~isempty(regexp(text, '^[A-Za-z][A-Za-z0-9+.-]*://', 'once')) && ...
    ~strncmpi(text, 'file:', 5);
end

function tf = path_key(key)
% Field names that hold file or folder paths
tf = ~isempty(regexp(key, ['(^|_)(file|files|path|paths|dir|dirs|' ...
    'directory|folder|folders|root|roots)$'], 'once')) || ...
    ~isempty(regexp(key, ['[a-z0-9](File|Files|Path|Paths|Dir|Dirs|' ...
    'Directory|Folder|Folders|Root|Roots)$'], 'once')) || ...
    ~isempty(regexp(key, '^f?(dir|folder)\d*(_|$)', 'once'));
end

function name = last_part(path)
% Last part of a dotted configuration path
name = '';
if ischar(path) || (isstring(path) && isscalar(path))
    parts = strsplit(char(path), '.');
    name = parts{end};
end
end
