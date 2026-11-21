function cfg = LOAD_MAIN_LD2_CONFIG(config_path, opts)
% "LOAD_MAIN_LD2_CONFIG" resolves LD2 task and profile settings.
% model_profile resolves LD2 gas, slip, mobility, projection, step,...
%     ...diagnostics and initial velocity choices. The consumer reads the...
%     ...native task fields and model_params.si constants. Saved-data...
%     ...projection still reads projection.n_mc and projection.n_ang....
%     ...cfg.si mirrors the resolved task in SI units.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     config_path: Task file, or empty for selection by the environment
%     opts: Optional CONFIG_READ and MODEL_PROFILE controls. QA calls...
%         ...set Strict to true
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Validated task, resolved profile and source records
% ----------------------------------------------------------------------- %

if nargin < 2, opts = struct(); end

if nargin < 1 || isempty(config_path)
    config_path = getenv('SOOTMOSAIC_MAIN_LD2_CONFIG');
    if isempty(config_path)
        % alternative variable name
        config_path = getenv('PFAL_MAIN_LD2_CONFIG');
    end
    if isempty(config_path)
        error('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingConfigSelection', ...
            ['LD2 config selection is required. Set SOOTMOSAIC_MAIN_LD2_CONFIG ' ...
            'to config/main_ld2/main_ld2_from_main_scatter_config.local.json or ' ...
            'config/main_ld2/main_ld2_from_main_scale_config.local.json, or pass an explicit config path.']);
    end
end

config_path = char(config_path);

if ~isfile(config_path)
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingConfig', ...
        ['LD2 config not found: %s\n' ...
        'Create it from config/main_ld2/main_ld2_from_main_scatter_config.example.json or ' ...
        'config/main_ld2/main_ld2_from_main_scale_config.example.json and fill in the local dataset path.'], ...
        config_path);
end

dictionary = fullfile(repo_root(), 'config', 'main_ld2', ...
    'main_ld2.keys.json');
cfg = UTILS.CONFIG_READ(config_path, dictionary, opts);

config_dir = fileparts(config_path);
cfg.config_file = config_path;

from_registry = isfield(cfg.dataset, 'source_id') && ...
    ~isempty(cfg.dataset.source_id);
fields = {'id', 'file', 'variable'};
for i = 1:numel(fields)
    name = fields{i};
    if ~from_registry || isfield(cfg.dataset, name)
        cfg.dataset.(name) = require_text_field(cfg.dataset, name, ...
            ['dataset.', name]);
    end
end
fields = {'url', 'doi', 'sha256', 'cache_file'};
for i = 1:numel(fields)
    name = fields{i};
    if ~from_registry || isfield(cfg.dataset, name)
        cfg.dataset.(name) = optional_text_field(cfg.dataset, name);
    end
end
cfg.dataset.config_dir = config_dir;

cfg.results.root = require_text_field(cfg.results, 'root', 'results.root');
cfg.results.run_label = require_text_field(cfg.results, 'run_label', 'results.run_label');
cfg.results.checkpoint_prefix = require_text_field(cfg.results, ...
    'checkpoint_prefix', 'results.checkpoint_prefix');
cfg.results.final_prefix = require_text_field(cfg.results, ...
    'final_prefix', 'results.final_prefix');
cfg.results.root = resolve_config_path(cfg.results.root, config_dir);

cfg.simulation.r_n_agg = require_vector_field(cfg.simulation, ...
    'r_n_agg', 'simulation.r_n_agg');

% Resolving the selected profile and explicit task choices
profile_given = isfield(cfg, 'model_profile') && ~isempty(cfg.model_profile);
if profile_given
    profile_name = cfg.model_profile;
else
    profile_name = 'article1_7658971';
    warning('sootMosaic:LOAD_MAIN_LD2_CONFIG:NoModelProfile', ...
        ['The LD2 config has no model_profile. The run uses the ' ...
        'article1_7658971 profile.']);
end
overrides = struct();
if isfield(cfg, 'model_overrides')
    overrides = cfg.model_overrides;
end
[cfg.model, known, cfg.model_params, cfg.model_source] = ...
    UTILS.MODEL_PROFILE(profile_name, 'LD2', overrides, opts);
for i_change = 1:numel(cfg.model_source.overrides)
    if strcmp(cfg.model_source.overrides(i_change).source, '<arguments>')
        cfg.model_source.overrides(i_change).source = config_path;
    end
end

if isfield(cfg.transport, 'user_defined')
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:LegacyTransportConfig', ...
        ['LD2 configs do not support transport.user_defined. Use ' ...
        'transport.domain.volume_fraction, transport.domain.size, and ' ...
        'transport.fluid.temperature instead.']);
end
cfg.transport.fluid.temperature = require_positive_scalar_field( ...
    cfg.transport.fluid, 'temperature', 'transport.fluid.temperature');
% Configs with model_profile must give the pressure. Configs without it run
% at 101325 Pa when the pressure is missing.
if profile_given || (isfield(cfg.transport.fluid, 'pressure') && ...
        ~isempty(cfg.transport.fluid.pressure))
    cfg.transport.fluid.pressure = require_positive_scalar_field( ...
        cfg.transport.fluid, 'pressure', 'transport.fluid.pressure');
else
    cfg.transport.fluid.pressure = 101325;
    warning('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingPressure', ...
        ['The LD2 config has no transport.fluid.pressure and no ' ...
        'model_profile. The run uses 101325 Pa.']);
end

cfg.transport.fluid_options.amb = optional_choice_field( ...
    cfg.transport.fluid_options, 'amb', cfg.model.fluid_properties, ...
    known.fluid_properties, 'transport.fluid_options.amb');
cfg.model.fluid_properties = cfg.transport.fluid_options.amb;
cfg.transport.mobility_options.c_dt = require_positive_scalar_field( ...
    cfg.transport.mobility_options, 'c_dt', 'transport.mobility_options.c_dt');
cfg.transport.mobility_options.step_frac = optional_positive_scalar_field( ...
    cfg.transport.mobility_options, 'step_frac', cfg.model_params.step.step_frac, ...
    'transport.mobility_options.step_frac');
cfg.transport.mobility_options.step_policy = optional_choice_field( ...
    cfg.transport.mobility_options, 'step_policy', cfg.model_params.step.step_policy, ...
    {'warn', 'cap'}, ...
    'transport.mobility_options.step_policy');
cfg.transport.mobility_options.mtd = optional_choice_field( ...
    cfg.transport.mobility_options, 'mtd', cfg.model_params.mobility.method, ...
    known.mobility, 'transport.mobility_options.mtd');
cfg.model.mobility = cfg.transport.mobility_options.mtd;
if strcmp(cfg.model.mobility, 'continuum')
    cfg.model.mobility = 'sorensen_eq17'; % alias of the method name
end
cfg.transport.mobility_options.continuum_diameter = optional_choice_field( ...
    cfg.transport.mobility_options, 'continuum_diameter', ...
    cfg.model.continuum_diameter, known.continuum_diameter, ...
    'transport.mobility_options.continuum_diameter');
cfg.model.continuum_diameter = ...
    cfg.transport.mobility_options.continuum_diameter;
cfg.transport.mobility_options.root_solve = optional_choice_field( ...
    cfg.transport.mobility_options, 'root_solve', cfg.model.root_solve, ...
    known.root_solve, 'transport.mobility_options.root_solve');
cfg.model.root_solve = cfg.transport.mobility_options.root_solve;
cfg.transport.mobility_options.projection = optional_choice_field( ...
    cfg.transport.mobility_options, 'projection', cfg.model.projection, ...
    known.projection, 'transport.mobility_options.projection');
cfg.model.projection = cfg.transport.mobility_options.projection;
cfg.transport.mobility_options.proj_cache = optional_logical_field( ...
    cfg.transport.mobility_options, 'proj_cache', cfg.model.proj_cache, ...
    'transport.mobility_options.proj_cache');
cfg.model.proj_cache = cfg.transport.mobility_options.proj_cache;
for proj_field = {'proj_points', 'proj_orientations', 'proj_replicates'}
    cfg.transport.mobility_options.(proj_field{1}) = ...
        optional_positive_integer_field(cfg.transport.mobility_options, ...
        proj_field{1}, cfg.model.(proj_field{1}), ...
        ['transport.mobility_options.' proj_field{1}]);
    cfg.model.(proj_field{1}) = cfg.transport.mobility_options.(proj_field{1});
end
cfg.transport.mobility_options.proj_tol = optional_tolerance_field( ...
    cfg.transport.mobility_options, 'proj_tol', cfg.model.proj_tol, ...
    'transport.mobility_options.proj_tol');
cfg.model.proj_tol = cfg.transport.mobility_options.proj_tol;
if cfg.model.proj_cache && ~strcmp(cfg.model.projection, 'isotropic')
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidProjection', ...
        'The LD2 config sets proj_cache without the isotropic projection.');
end
if strcmp(cfg.model.projection, 'isotropic') && ...
        mod(cfg.model.proj_orientations, cfg.model.proj_replicates) ~= 0
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidProjection', ...
        'The LD2 config proj_orientations must be a multiple of proj_replicates.');
end
if strcmp(cfg.model.projection, 'isotropic') && ...
        cfg.model.proj_replicates < 2 && isfinite(cfg.model.proj_tol)
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidProjection', ...
        ['The LD2 config sets a finite proj_tol with one proj_replicates ', ...
        'set, which gives no standard error. Set proj_tol to none or use ', ...
        'more sets.']);
end
cfg.transport.mobility_options.slip = optional_choice_field( ...
    cfg.transport.mobility_options, 'slip', cfg.model.slip_correction, ...
    known.slip_correction, 'transport.mobility_options.slip');
cfg.model.slip_correction = cfg.transport.mobility_options.slip;
cfg.transport.location_options.vf = require_text_field( ...
    cfg.transport.location_options, 'vf', 'transport.location_options.vf');
cfg.transport.growth_options.indupdate = require_text_field( ...
    cfg.transport.growth_options, 'indupdate', 'transport.growth_options.indupdate');

% Optional diagnostics, recorded in ensdata and never used in the dynamics
cfg.transport.diagnostics_options.knudsen = optional_logical_field( ...
    cfg.transport.diagnostics_options, 'knudsen', ...
    cfg.model.knudsen_diagnostics, 'transport.diagnostics_options.knudsen');
cfg.model.knudsen_diagnostics = cfg.transport.diagnostics_options.knudsen;

% Optional sampler of the initial velocities
cfg.transport.velocity_options.sampler = optional_choice_field( ...
    cfg.transport.velocity_options, 'sampler', cfg.model.initial_velocity, ...
    known.initial_velocity, 'transport.velocity_options.sampler');
cfg.model.initial_velocity = cfg.transport.velocity_options.sampler;

cfg = record_model(cfg);
for section = {'dataset', 'results', 'simulation', 'projection', 'transport'}
    cfg.si.(section{1}) = cfg.(section{1});
end
cfg.si.config_file = cfg.config_file;

end

function out = require_text_field(src, field_name, label)
% "require_text_field" reads a required nonempty value as text.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingText', ...
        'The LD2 config is missing %s.', label);
end

out = char(src.(field_name));

end

function out = optional_text_field(src, field_name)
% "optional_text_field" reads optional text.

out = '';
if isfield(src, field_name) && ~isempty(src.(field_name))
    out = char(src.(field_name));
end

end

function out = require_scalar_field(src, field_name, label)
% "require_scalar_field" checks a finite numeric scalar.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingScalar', ...
        'The LD2 config is missing %s.', label);
end

value = src.(field_name);
% Check the type before conversion, since double() turns text into...
    % ...character codes and logical values into 0 or 1
if ~isnumeric(value) || ~isreal(value)
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidScalar', ...
        'The LD2 config field %s must be a finite numeric scalar.', label);
end
out = double(value);
if ~isscalar(out) || ~isfinite(out)
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidScalar', ...
        'The LD2 config field %s must be a finite numeric scalar.', label);
end

end

function out = require_positive_scalar_field(src, field_name, label)
% "require_positive_scalar_field" checks a positive numeric scalar.

out = require_scalar_field(src, field_name, label);
if out <= 0
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidPositiveScalar', ...
        'The LD2 config field %s must be positive.', label);
end

end

function out = optional_positive_scalar_field(src, field_name, default_value, label)
% "optional_positive_scalar_field" reads a scalar or its default.

out = default_value;
if isfield(src, field_name) && ~isempty(src.(field_name))
    out = require_positive_scalar_field(src, field_name, label);
end

end

function out = optional_tolerance_field(src, field_name, default_value, label)
% "optional_tolerance_field" reads a tolerance or none for Inf.

if isfield(src, field_name) && (ischar(src.(field_name)) || ...
        isStringScalar(src.(field_name))) && strcmp(char(src.(field_name)), 'none')
    out = Inf;
else
    out = optional_positive_scalar_field(src, field_name, default_value, label);
end

end

function out = optional_choice_field(src, field_name, default_value, choices, label)
% "optional_choice_field" reads an implemented choice or its default.

out = default_value;
if ~isfield(src, field_name) || isempty(src.(field_name))
    return
end
if ~(ischar(src.(field_name)) || isStringScalar(src.(field_name))) || ...
        ~any(strcmp(char(src.(field_name)), choices))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidChoice', ...
        'The LD2 config field %s must be one of %s.', label, ...
        strjoin(choices, ', '));
end
out = char(src.(field_name));

end

function out = optional_positive_integer_field(src, field_name, default_value, label)
% "optional_positive_integer_field" reads an integer or its default.

out = default_value;
if isfield(src, field_name) && ~isempty(src.(field_name))
    out = require_positive_integer_field(src, field_name, label);
end

end

function out = optional_logical_field(src, field_name, default_value, label)
% "optional_logical_field" reads a logical scalar or its default.

out = default_value;
if ~isfield(src, field_name) || isempty(src.(field_name))
    return
end
if ~islogical(src.(field_name)) || ~isscalar(src.(field_name))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidLogical', ...
        'The LD2 config field %s must be true or false.', label);
end
out = src.(field_name);

end

function out = require_positive_integer_field(src, field_name, label)
% "require_positive_integer_field" checks a positive numeric integer.

out = require_scalar_field(src, field_name, label);
if out <= 0 || round(out) ~= out
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidInteger', ...
        'The LD2 config field %s must be a positive integer.', label);
end

end

function out = require_vector_field(src, field_name, label)
% "require_vector_field" flattens finite values into a row.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:MissingVector', ...
        'The LD2 config is missing %s.', label);
end

out = double(src.(field_name));
out = reshape(out, 1, []);
if isempty(out) || any(~isfinite(out))
    error('sootMosaic:LOAD_MAIN_LD2_CONFIG:InvalidVector', ...
        'The LD2 config field %s must be a finite numeric vector.', label);
end

end

function full_path = resolve_config_path(path_value, config_dir)
% "resolve_config_path" resolves a path from the task directory.

full_path = char(path_value);
if is_absolute_path(full_path)
    full_path = normalize_path(full_path);
    return
end

full_path = normalize_path(fullfile(config_dir, full_path));

end

function tf = is_absolute_path(path_value)
% "is_absolute_path" identifies an absolute path.

tf = ~isempty(regexp(path_value, '^[A-Za-z]:[\\/]', 'once')) || ...
    strncmp(path_value, '\\', 2) || ...
    strncmp(path_value, '//', 2) || ...
    strncmp(path_value, '/', 1);

end

function path_value = normalize_path(path_value)
% "normalize_path" collapses relative path segments when available.

try
    path_value = char(java.io.File(path_value).getCanonicalPath());
catch
    path_value = char(path_value);
end

end

function cfg = record_model(cfg)
% "record_model" records explicit task choices and conditional rules.
explicit.gas.model = cfg.model.fluid_properties;
explicit.slip.model = cfg.model.slip_correction;
explicit.mobility.method = cfg.transport.mobility_options.mtd;
explicit.mobility.continuum_diameter = cfg.model.continuum_diameter;
explicit.mobility.root_solve = cfg.model.root_solve;
explicit.projection = struct('method', cfg.model.projection, ...
    'cache', cfg.model.proj_cache, 'points', cfg.model.proj_points, ...
    'orientations', cfg.model.proj_orientations, ...
    'replicates', cfg.model.proj_replicates, 'tol', cfg.model.proj_tol);
explicit.step.step_frac = cfg.transport.mobility_options.step_frac;
explicit.step.step_policy = cfg.transport.mobility_options.step_policy;
explicit.diagnostics.knudsen = cfg.model.knudsen_diagnostics;
explicit.initial_velocity.sampler = cfg.model.initial_velocity;
[cfg.model_params, changes] = UTILS.CONFIG_MERGE( ...
    cfg.model_params, explicit, cfg.config_file);
cfg.model_source.overrides = [cfg.model_source.overrides; changes];
cfg.model_params.si = UTILS.CONFIG_MERGE(cfg.model_params.si, explicit);
cfg.transport.fluid_options.gas = cfg.model_params.si.gas;
cfg.transport.mobility_options.slip_coefficients = cfg.model_params.si.slip;
cfg.model_params.resolved.rho_aero_ref_kg_m3 = ...
    cfg.model_params.constants.rho_aero_ref_kg_m3;
cfg.model_params.resolved.root_tolerance = 'eps_scaled';
if strcmp(cfg.model.slip_correction, 'per_caller_7658971')
    cfg.model_params.resolved.rho_aero_ref_kg_m3 = ...
        cfg.model_params.constants.rho_bc_kg_m3;
    if strcmp(cfg.model.root_solve, 'start_point_7658971')
        cfg.model_params.resolved.root_tolerance = 'default';
    end
end
end

function root = repo_root()
% "repo_root" locates the configuration directory.
root = fileparts(fileparts(mfilename('fullpath')));
end
