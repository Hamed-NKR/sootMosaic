function path_out = POST_PATH(cfg, key)
% "POST_PATH" returns an input file of a post-processing script.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     cfg: Task values from a LOAD_MAIN_*_CONFIG call
%     key: Entry of the post section, such as 'ld2.results_file'
% ----------------------------------------------------------------------- %
%
% Outputs:
%     path_out: File path. A relative path in the task file is resolved...
%         ...from the folder of that file
% ----------------------------------------------------------------------- %

node = [];
if isstruct(cfg) && isfield(cfg, 'post')
    node = cfg.post;
end
for part = strsplit(char(key), '.')
    if isstruct(node) && isfield(node, part{1})
        node = node.(part{1});
    else
        node = [];
        break
    end
end
if isempty(node) || ~(ischar(node) || (isstring(node) && isscalar(node)))
    error('sootMosaic:POST_PATH:MissingKey', ...
        'The task file does not set post.%s as text.', char(key));
end
path_out = char(node);
if isempty(path_out)
    error('sootMosaic:POST_PATH:MissingKey', ...
        'The task file does not set post.%s as text.', char(key));
end

absolute = ~isempty(regexp(path_out, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(path_out, {'\\', '/'});
if ~absolute
    path_out = fullfile(fileparts(cfg.config_file), path_out);
end

end
