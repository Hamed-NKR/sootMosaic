function require_recorded(cfg, paths, caller)
% Require a scan or campaign source for each resolved input.
for k = 1:numel(paths)
    if ~isfield(cfg, 'reading')
        r = [];
    else
        r = cfg.reading(strcmp({cfg.reading.path}, paths{k}));
    end
    if numel(r) ~= 1 || ...
            ~any(strcmp(r.source, {'data', 'campaign'}))
        error(['sootMosaic:' caller ':MissingRecordedInput'], ...
            'A recorded scan value is required for %s.', paths{k});
    end
end
end
