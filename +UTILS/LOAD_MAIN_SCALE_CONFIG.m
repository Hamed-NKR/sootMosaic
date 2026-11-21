function cfg = LOAD_MAIN_SCALE_CONFIG(config_path, opts)
% "LOAD_MAIN_SCALE_CONFIG" resolves scale settings and profile metadata.
% model_profile resolves LD1 profile metadata. The scale calculation...
%     ...keeps its existing projection calls and native-unit inputs.
% cfg.si is returned for later consumers.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     config_path: Task file, or empty for SOOTMOSAIC_MAIN_SCALE_CONFIG,...
%         ...then PFAL_MAIN_SCALE_CONFIG, then the local task file
%     opts: Optional CONFIG_READ controls; Strict rejects unknown keys
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Task values, SI values, configuration provenance and the LD1...
%         ...profile. Dataset paths are relative to the selected task file
% ----------------------------------------------------------------------- %

root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1 || isempty(config_path)
    config_path = getenv('SOOTMOSAIC_MAIN_SCALE_CONFIG');
    if isempty(config_path)
        config_path = getenv('PFAL_MAIN_SCALE_CONFIG');
    end
    if isempty(config_path)
        config_path = fullfile(root, 'config', 'main_scale', ...
            'main_scale_config.local.json');
    end
end
if nargin < 2, opts = struct(); end
config_path = char(config_path);
if ~isfile(config_path)
    error('sootMosaic:LOAD_MAIN_SCALE_CONFIG:MissingConfig', ...
        'Scale config not found: %s', config_path);
end
dictionary = fullfile(root, 'config', 'main_scale', 'main_scale.keys.json');
cfg = UTILS.CONFIG_READ(config_path, dictionary, opts);
cfg.config_file = config_path;

% Checking fields supplied inline against the selected source
from_registry = isfield(cfg.dataset, 'source_id') && ...
    ~isempty(cfg.dataset.source_id);
fields = {'id', 'file', 'variable'};
for k = 1:numel(fields)
    key = fields{k};
    if (~from_registry || isfield(cfg.dataset, key)) && ...
            (~isfield(cfg.dataset, key) || isempty(cfg.dataset.(key)))
        error('sootMosaic:LOAD_MAIN_SCALE_CONFIG:MissingText', ...
            'The scale config is missing dataset.%s.', key);
    end
end
cfg.dataset.config_dir = fileparts(config_path);
cfg.si.dataset.config_dir = cfg.dataset.config_dir;

% Resolving the profile for the first-stage aggregate library
strict = false;
if isfield(opts, 'Strict'), strict = opts.Strict; end
[cfg.model, ~, cfg.model_params, cfg.model_source] = ...
    UTILS.MODEL_PROFILE(cfg.model_profile, 'LD1', ...
    cfg.model_overrides, struct('Strict', strict));
end
