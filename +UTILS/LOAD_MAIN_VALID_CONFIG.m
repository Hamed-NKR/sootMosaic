function cfg = LOAD_MAIN_VALID_CONFIG(config_path, opts)
% "LOAD_MAIN_VALID_CONFIG" resolves validation task and profile settings.
% model_profile resolves the LD2 profile, whose constants.rho_bc gives the...
%     ...material density unless physics.material_density_kg_m3 is set....
%     ...RUN_MAIN_VALIDATION reads the native task fields and...
%     ...physics.material_density_kg_m3. It recomputes the mobility...
%     ...diameter with the DIAMOBIL call defaults and does not read...
%     ...cfg.model. cfg.si mirrors the resolved task in SI units.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     config_path: Task file, or empty for SOOTMOSAIC_MAIN_VALID_CONFIG,...
%         ...then PFAL_MAIN_VALID_CONFIG, then the local task file
%     opts: Optional CONFIG_READ and MODEL_PROFILE controls. QA calls...
%         ...set Strict to true
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Validated task, resolved profile and source records. Task...
%         ...paths are relative to the selected task file
% ----------------------------------------------------------------------- %

if nargin < 2, opts = struct(); end
if nargin < 1 || isempty(config_path)
    config_path = getenv('SOOTMOSAIC_MAIN_VALID_CONFIG');
    if isempty(config_path)
        % alternative variable name
        config_path = getenv('PFAL_MAIN_VALID_CONFIG');
    end
    if isempty(config_path)
        config_path = fullfile(repo_root(), 'config', 'main_valid', ...
            'main_valid_config.local.json');
    end
end
config_path = char(config_path);

if ~isfile(config_path)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingConfig', ...
        ['Validation config not found: %s\nCreate it from ' ...
         'config/main_valid/main_valid_config.example.json or set ' ...
         'SOOTMOSAIC_MAIN_VALID_CONFIG.'], config_path);
end

dictionary = fullfile(repo_root(), 'config', 'main_valid', ...
    'main_valid.keys.json');
cfg = UTILS.CONFIG_READ(config_path, dictionary, opts);
read_cfg = cfg;

config_dir = fileparts(config_path);
cfg.config_file = normalize_path(config_path);

source_names = {'ld2', 'tem', 'effective_density'};
for i = 1:numel(source_names)
    name = source_names{i};
    cfg.sources.(name) = validate_source(cfg.sources.(name), ...
        ['sources.', name], config_dir);
end

% Validating the conditions and returning them as a structure array
if isempty(cfg.conditions)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingConditions', ...
        'The validation config must define a non-empty conditions array.');
end
condition_cells = cell(numel(cfg.conditions), 1);
for i = 1:numel(cfg.conditions)
    condition_cells{i} = validate_condition(cfg.conditions{i}, i);
end
condition_keys = fieldnames(condition_cells{1});
if any(cellfun(@(c) ~isempty(setxor(fieldnames(c), condition_keys)), ...
        condition_cells))
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InconsistentConditions', ...
        'Every configured condition must use the same keys.');
end
cfg.conditions = vertcat(condition_cells{:});
condition_ids = string({cfg.conditions.id});
if numel(unique(condition_ids)) ~= numel(condition_ids)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:DuplicateConditionID', ...
        'Each configured condition must have a unique id.');
end

% Resolving the profile and the explicit material density
profile_name = 'article1_7658971';
if isfield(cfg, 'model_profile'), profile_name = cfg.model_profile; end
overrides = struct();
if isfield(cfg, 'model_overrides'), overrides = cfg.model_overrides; end
[cfg.model, ~, cfg.model_params, cfg.model_source] = ...
    UTILS.MODEL_PROFILE(profile_name, 'LD2', overrides, opts);
if isfield(cfg.physics, 'material_density_kg_m3')
    density = positive_value(cfg.physics.material_density_kg_m3, ...
        'physics.material_density_kg_m3');
    explicit.constants.rho_bc_kg_m3 = density;
    [cfg.model_params, changes] = UTILS.CONFIG_MERGE( ...
        cfg.model_params, explicit, cfg.config_file);
    cfg.model_source.overrides = [cfg.model_source.overrides; changes];
    cfg.model_params.si.constants.rho_bc_kg_m3 = density;
end
cfg.physics.material_density_kg_m3 = ...
    cfg.model_params.si.constants.rho_bc_kg_m3;
if strcmp(cfg.model.slip_correction, 'per_caller_7658971')
    cfg.model_params.resolved.rho_aero_ref_kg_m3 = ...
        cfg.physics.material_density_kg_m3;
end

cfg.references.dpp_vs_da = validate_reference(cfg.references.dpp_vs_da, ...
    'references.dpp_vs_da', 'value_at_100_nm');
cfg.references.rho_eff_vs_dm = validate_reference( ...
    cfg.references.rho_eff_vs_dm, 'references.rho_eff_vs_dm', ...
    'value_at_100_nm');

cfg.fits.dpp_vs_da = validate_fit(cfg.fits.dpp_vs_da, 'fits.dpp_vs_da');
cfg.fits.rho_eff_vs_dm = validate_fit(cfg.fits.rho_eff_vs_dm, ...
    'fits.rho_eff_vs_dm');
cfg.fits.experimental_rho_eff_vs_dm = validate_experimental_fit( ...
    cfg.fits.experimental_rho_eff_vs_dm, 'fits.experimental_rho_eff_vs_dm');

cfg.figures = validate_figures(cfg.figures);
cfg.outputs.root = resolve_config_path(require_text(cfg.outputs, ...
    'root', 'outputs.root'), config_dir);
cfg.outputs.png_source = lower(char(cfg.outputs.png_source));
if ~ismember(cfg.outputs.png_source, {'figure', 'pdf'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidPNGSource', ...
        'outputs.png_source must be figure or pdf.');
end
cfg.outputs.experimental_summary_csv = ...
    char(cfg.outputs.experimental_summary_csv);
if cfg.outputs.export && cfg.outputs.png && ...
        strcmp(cfg.outputs.png_source, 'pdf') && ~cfg.outputs.pdf
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingPDFForPNG', ...
        'outputs.pdf must be enabled when outputs.png_source is pdf.');
end

% Checking the requested fractions against the r_n_agg of the LD2 product
check_ld2_fractions(cfg.conditions, cfg.sources.ld2);

% Mirroring the resolved task with the SI numbers of the reader
task = rmfield(cfg, {'si', 'provenance', 'model', 'model_params', ...
    'model_source'});
cfg.si = si_mirror(task, read_cfg, read_cfg.si);

end

function source = validate_source(source, label, config_dir)
% "validate_source" normalizes inline source fields and relative paths.
% ----------------------------------------------------------------------- %

from_registry = isfield(source, 'source_id') && ~isempty(source.source_id);
if ~from_registry || isfield(source, 'id')
    source.id = require_text(source, 'id', [label, '.id']);
end
if ~from_registry || isfield(source, 'file')
    source.file = resolve_config_path(require_text(source, 'file', ...
        [label, '.file']), config_dir);
end
fields = {'url', 'doi', 'sha256', 'cache_file'};
for i = 1:numel(fields)
    name = fields{i};
    if ~from_registry || isfield(source, name)
        source.(name) = optional_text(source, name, '');
    end
end
if isfield(source, 'cache_file') && ~isempty(source.cache_file)
    source.cache_file = resolve_config_path(source.cache_file, config_dir);
end
if (~from_registry || isfield(source, 'variables')) && ...
        (~isfield(source, 'variables') || isempty(source.variables))
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingSourceVariables', ...
        '%s.variables must list the required MAT variables.', label);
end

end

function condition = validate_condition(condition, index)
% "validate_condition" checks one experimental and simulation mapping.
% ----------------------------------------------------------------------- %

label = sprintf('conditions(%d)', index);
condition.id = require_text(condition, 'id', [label, '.id']);
condition.label = require_text(condition, 'label', [label, '.label']);
condition.tem_entry_id = char(condition.tem_entry_id);
condition.effective_density_condition_id = ...
    char(condition.effective_density_condition_id);
condition.ld2_fractions = plain_empty(condition.ld2_fractions);
style = condition.style;
style.color = require_text(style, 'color', [label, '.style.color']);
style.simulation_marker = require_text(style, 'simulation_marker', ...
    [label, '.style.simulation_marker']);
style.experimental_marker = require_text(style, 'experimental_marker', ...
    [label, '.style.experimental_marker']);
style.simulation_marker_size = positive_value( ...
    style.simulation_marker_size, [label, '.style.simulation_marker_size']);
style.experimental_marker_size = positive_value( ...
    style.experimental_marker_size, ...
    [label, '.style.experimental_marker_size']);
style.experimental_color = optional_text(style, 'experimental_color', ...
    style.color);
style.experimental_marker_face_color = ...
    char(style.experimental_marker_face_color);
style.experimental_marker_line_width = positive_value( ...
    style.experimental_marker_line_width, ...
    [label, '.style.experimental_marker_line_width']);
style.fit_line_width = positive_value(style.fit_line_width, ...
    [label, '.style.fit_line_width']);
condition.style = style;

if condition.enabled && ...
        (condition.include.dpp_vs_da || condition.include.rho_eff_vs_dm) && ...
        isempty(condition.ld2_fractions)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingLD2Mapping', ...
        '%s must provide ld2_fractions when an enabled panel uses simulation data.', ...
        label);
end
if condition.enabled && condition.include.dpp_vs_da && ...
        isempty(condition.tem_entry_id)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingTEMMapping', ...
        '%s must provide tem_entry_id for the dpp_vs_da panel.', label);
end
if condition.enabled && condition.include.rho_eff_vs_dm && ...
        isempty(condition.effective_density_condition_id)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingDensityMapping', ...
        '%s must provide effective_density_condition_id for rho_eff_vs_dm.', label);
end

end

function reference = validate_reference(reference, label, value_field)
% "validate_reference" checks a configurable literature correlation.
% ----------------------------------------------------------------------- %

reference.label = require_text(reference, 'label', [label, '.label']);
reference.(value_field) = positive_value(reference.(value_field), ...
    [label, '.', value_field]);
reference.color = require_text(reference, 'color', [label, '.color']);
reference.line_style = require_text(reference, 'line_style', ...
    [label, '.line_style']);
reference.line_width = positive_value(reference.line_width, ...
    [label, '.line_width']);

end

function fit_cfg = validate_fit(fit_cfg, label)
% "validate_fit" checks the Bayesian fit controls of one panel.
% ----------------------------------------------------------------------- %

if fit_cfg.credible_level <= 0 || fit_cfg.credible_level >= 1
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidCredibleLevel', ...
        '%s.credible_level must be strictly between 0 and 1.', label);
end
fit_cfg.x_transform = validate_transform(require_text(fit_cfg, ...
    'x_transform', [label, '.x_transform']), [label, '.x_transform']);
fit_cfg.y_transform = validate_transform(require_text(fit_cfg, ...
    'y_transform', [label, '.y_transform']), [label, '.y_transform']);
fit_cfg.prior_mu = plain_empty(fit_cfg.prior_mu);
fit_cfg.prior_v_scale = positive_value(fit_cfg.prior_v_scale, ...
    [label, '.prior_v_scale']);
fit_cfg.prior_a = positive_value(fit_cfg.prior_a, [label, '.prior_a']);
fit_cfg.prior_b = positive_value(fit_cfg.prior_b, [label, '.prior_b']);

end

function fit_cfg = validate_experimental_fit(fit_cfg, label)
% "validate_experimental_fit" checks the direct power-law density fit.
% ----------------------------------------------------------------------- %

if fit_cfg.degree ~= 1
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidExperimentalFitDegree', ...
        '%s.degree must be 1 for a single mass-mobility exponent.', label);
end
fit_cfg.support_mode = lower(require_text(fit_cfg, 'support_mode', ...
    [label, '.support_mode']));
if ~ismember(fit_cfg.support_mode, {'common','explicit'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidExperimentalSupportMode', ...
        '%s.support_mode must be common or explicit.', label);
end
fit_cfg.support_limits_nm = limits_value(fit_cfg.support_limits_nm, ...
    [label, '.support_limits_nm']);
if strcmp(fit_cfg.support_mode, 'explicit') && ...
        isempty(fit_cfg.support_limits_nm)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingExperimentalSupportLimits', ...
        '%s.support_limits_nm is required for explicit support.', label);
end
if fit_cfg.confidence_level <= 0 || fit_cfg.confidence_level >= 1
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidExperimentalConfidenceLevel', ...
        '%s.confidence_level must be strictly between 0 and 1.', label);
end

end

function figures = validate_figures(figures)
% "validate_figures" checks the shared typography and panel appearance.
% ----------------------------------------------------------------------- %

figures.visible = lower(require_text(figures, 'visible', 'figures.visible'));
if ~ismember(figures.visible, {'on', 'off'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidVisibility', ...
        'figures.visible must be "on" or "off".');
end
figures.axis_line_width = positive_value(figures.axis_line_width, ...
    'figures.axis_line_width');
axes_cfg = figures.axes;
if ~isscalar(axes_cfg)
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidAxisStyle', ...
        'figures.axes must be one object.');
end
axes_cfg.layer = lower(char(axes_cfg.layer));
if ~ismember(axes_cfg.layer, {'top','bottom'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidAxisLayer', ...
        'figures.axes.layer must be top or bottom.');
end
axes_cfg.label_position_mode = char(axes_cfg.label_position_mode);
if ~ismember(lower(axes_cfg.label_position_mode), {'auto','manual'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidAxisStyle', ...
        'figures.axes.label_position_mode must be auto or manual.');
end
axes_cfg.x_label_offset = positive_value(axes_cfg.x_label_offset, ...
    'figures.axes.x_label_offset');
axes_cfg.y_label_offset = positive_value(axes_cfg.y_label_offset, ...
    'figures.axes.y_label_offset');
figures.axes = axes_cfg;
font = figures.font;
font.family = require_text(font, 'family', 'figures.font.family');
font.fallback = require_text(font, 'fallback', 'figures.font.fallback');
font.axis_size = positive_value(font.axis_size, 'figures.font.axis_size');
font.label_size = positive_value(font.label_size, 'figures.font.label_size');
font.legend_size = positive_value(font.legend_size, ...
    'figures.font.legend_size');
font.title_size = optional_positive_scalar(font, 'title_size', ...
    font.label_size, 'figures.font.title_size');
font.weight = require_text(font, 'weight', 'figures.font.weight');
if ~ismember(lower(font.weight), {'normal','bold'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidFontWeight', ...
        'figures.font.weight must be normal or bold.');
end
font.interpreter = lower(require_text(font, 'interpreter', ...
    'figures.font.interpreter'));
if ~ismember(font.interpreter, {'tex', 'none', 'latex'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidInterpreter', ...
        'figures.font.interpreter must be tex, none, or latex.');
end
figures.font = font;

legend_cfg = figures.legend;
legend_cfg.location = lower(require_text(legend_cfg, 'location', ...
    'figures.legend.location'));
legend_cfg.orientation = lower(require_text(legend_cfg, 'orientation', ...
    'figures.legend.orientation'));
if ~ismember(legend_cfg.orientation, {'horizontal', 'vertical'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLegendOrientation', ...
        'figures.legend.orientation must be horizontal or vertical.');
end
legend_cfg.interpreter = lower(char(legend_cfg.interpreter));
if ~ismember(legend_cfg.interpreter, {'tex', 'none', 'latex'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLegendInterpreter', ...
        'figures.legend.interpreter must be tex, none, or latex.');
end
legend_cfg.font_family = optional_text(legend_cfg, 'font_family', ...
    font.family);
legend_cfg.font_fallback = optional_text(legend_cfg, 'font_fallback', ...
    font.fallback);
legend_cfg.font_weight = lower(optional_text(legend_cfg, 'font_weight', ...
    font.weight));
if ~ismember(legend_cfg.font_weight, {'normal', 'bold'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLegendFontWeight', ...
        'figures.legend.font_weight must be normal or bold.');
end
figures.legend = legend_cfg;
panel_names = {'dpp_vs_da', 'rho_eff_vs_dm'};
for i = 1:numel(panel_names)
    name = panel_names{i};
    panel = figures.(name);
    panel.x_limits = limits_value(panel.x_limits, ...
        ['figures.', name, '.x_limits']);
    panel.y_limits = limits_value(panel.y_limits, ...
        ['figures.', name, '.y_limits']);
    figures.(name) = panel;
end

end

function value = validate_transform(value, label)
% "validate_transform" restricts fit transforms to those of FIT_POLY.
% ----------------------------------------------------------------------- %

value = lower(value);
if ~ismember(value, {'log10', 'none'})
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidTransform', ...
        '%s must be "log10" or "none".', label);
end

end

function check_ld2_fractions(conditions, source)
% "check_ld2_fractions" matches the requested fractions to the LD2 product.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     conditions: Validated conditions; only enabled ones are checked
%     source: Validated sources.ld2 entry
% ----------------------------------------------------------------------- %
%
% Each requested fraction matches exactly one r_n_agg entry within...
%     ...max(1e-12, 1e-9 times the fraction), the rule of...
%     ...RUN_MAIN_VALIDATION. The inline file, then its cache file, is...
%     ...read without download or digest check. A registry selection or...
%     ...a product not on disk leaves the check to the run, with a warning
% ----------------------------------------------------------------------- %

enabled = conditions([conditions.enabled]);
if isempty(enabled) || all(arrayfun(@(c) isempty(c.ld2_fractions), enabled))
    return
end
[fractions, file, reason] = ld2_product_fractions(source);
if ~isempty(reason)
    warning('sootMosaic:LOAD_MAIN_VALID_CONFIG:LD2FractionsUnchecked', ...
        ['conditions.ld2_fractions are checked when RUN_MAIN_VALIDATION ' ...
         'loads the LD2 product, since %s.'], reason);
    return
end
for i = 1:numel(enabled)
    for target = enabled(i).ld2_fractions
        tolerance = max(1e-12, 1e-9 * abs(target));
        matched = nnz(abs(fractions - target) <= tolerance);
        if matched ~= 1
            error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLD2FractionMapping', ...
                ['Condition "%s" requests LD2 fraction %.12g, which ' ...
                 'matches %d r_n_agg entries of %s. Available fractions: %s'], ...
                enabled(i).id, target, matched, file, mat2str(fractions.'));
        end
    end
end

end

function [fractions, file, reason] = ld2_product_fractions(source)
% "ld2_product_fractions" reads r_n_agg from the named LD2 product.
% ----------------------------------------------------------------------- %

fractions = [];
file = '';
reason = '';
if isfield(source, 'source_id') && ~isempty(source.source_id)
    reason = 'sources.ld2 is selected through the source registry';
    return
end
candidates = {source.file, source.cache_file};
for k = 1:numel(candidates)
    if ~isempty(candidates{k}) && isfile(candidates{k})
        file = candidates{k};
        break
    end
end
if isempty(file)
    reason = sprintf('no LD2 product exists at %s', source.file);
    return
end
try
    names = who('-file', file);
catch
    reason = sprintf('%s is not a readable MAT file', file);
    return
end
if ~any(strcmp(names, 'r_n_agg'))
    reason = sprintf('%s holds no r_n_agg', file);
    return
end
loaded = load(file, 'r_n_agg');
if ~(isnumeric(loaded.r_n_agg) || islogical(loaded.r_n_agg))
    reason = sprintf('r_n_agg of %s is not numeric', file);
    return
end
fractions = double(loaded.r_n_agg(:));

end

function si = si_mirror(value, read_value, read_si)
% "si_mirror" copies resolved values with the SI numbers of the reader.
% Numbers the loader leaves unchanged keep their converted reader value.

si = value;
if isstruct(value) && isscalar(value) && isstruct(read_value) && ...
        isscalar(read_value) && isstruct(read_si) && isscalar(read_si)
    names = fieldnames(value);
    for k = 1:numel(names)
        key = names{k};
        if isfield(read_value, key) && isfield(read_si, key)
            si.(key) = si_mirror(value.(key), read_value.(key), ...
                read_si.(key));
        end
    end
elseif isnumeric(value) && strcmp(class(value), class(read_value)) && ...
        isequal(value, read_value) && isnumeric(read_si)
    si = read_si;
end

end

function out = require_text(source, field_name, label)
% "require_text" reads a required nonempty value as text.

if ~isfield(source, field_name) || isempty(source.(field_name))
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:MissingText', ...
        'The validation config is missing %s.', label);
end
out = char(source.(field_name));

end

function out = optional_text(source, field_name, default_value)
% "optional_text" reads optional text or its conditional default.

out = default_value;
if isfield(source, field_name) && ~isempty(source.(field_name))
    out = char(source.(field_name));
end

end

function out = positive_value(value, label)
% "positive_value" checks a number that the dictionary made finite.

if value <= 0
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidPositiveNumber', ...
        '%s must be greater than zero.', label);
end
out = value;

end

function out = optional_positive_scalar(source, field_name, default_value, label)
% "optional_positive_scalar" reads a positive scalar or its default.

out = default_value;
if isfield(source, field_name) && ~isempty(source.(field_name))
    out = double(source.(field_name));
    if ~isscalar(out) || ~isfinite(out)
        error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidNumber', ...
            '%s must be a finite numeric scalar.', label);
    end
    out = positive_value(out, label);
end

end

function out = plain_empty(value)
% "plain_empty" returns an empty vector of the dictionary as [].

out = value;
if isempty(out), out = []; end

end

function out = limits_value(value, label)
% "limits_value" checks empty limits or two increasing positive values.

out = plain_empty(value);
if ~isempty(out) && (numel(out) ~= 2 || any(out <= 0) || out(2) <= out(1))
    error('sootMosaic:LOAD_MAIN_VALID_CONFIG:InvalidLimits', ...
        '%s must be empty or contain two increasing positive values.', label);
end

end

function full_path = resolve_config_path(path_value, config_dir)
% "resolve_config_path" resolves a path from the task directory.

if is_absolute_path(path_value)
    full_path = normalize_path(path_value);
else
    full_path = normalize_path(fullfile(config_dir, path_value));
end

end

function tf = is_absolute_path(path_value)
% "is_absolute_path" identifies an absolute path.

tf = ~isempty(regexp(path_value, '^[A-Za-z]:[\\/]', 'once')) || ...
    strncmp(path_value, '\\', 2) || strncmp(path_value, '//', 2) || ...
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

function root_dir = repo_root()
% "repo_root" locates the repository root.

utils_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(utils_dir);

end
