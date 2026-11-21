function cfg = LOAD_MAIN_TEM_ANALYSIS_CONFIG(config_path, opts)
% "LOAD_MAIN_TEM_ANALYSIS_CONFIG" resolves and validates the TEM analysis task.
% The task names no model_profile and resolves no profile....
%     ...main_tem_analysis_v1 reads the native task fields, not cfg.si,...
%     ...and no consumer reads plots.font.title_size or the entries keys...
%     ...include_in_publication_plots and include_in_hybridity_scatter....
%     ...cfg.si mirrors the resolved task, whose units all have factor 1.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     config_path: Task file, or empty for...
%         ...SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG, then...
%         ...PFAL_MAIN_TEM_ANALYSIS_CONFIG, then the local task file
%     opts: Optional CONFIG_READ controls. QA calls set Strict to true....
%         ...KeywordNames is always set, since aggregate id ranges name...
%         ...their last id with the member end. LoaderFallbacks is set by...
%         ...this loader only
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Validated task. Output folders resolve from the folder of the...
%         ...selected task file and entry files from entries.entry_dir
% ----------------------------------------------------------------------- %
%
% A task without plots.figures, without its...
%     ...subaggregate_count_distribution figure or without...
%     ...plots.frequency_bins is read a second time with the figure and...
%     ...bin sets of this loader as the LoaderFallbacks layer above the...
%     ...direct arguments, so those sets take the same dictionary...
%     ...defaults and checks as configured ones and the provenance keeps...
%     ...the argument records. The second read repeats no unknown-key...
%     ...warning.
% ----------------------------------------------------------------------- %

if nargin < 2, opts = struct(); end
if isstruct(opts) && isscalar(opts)
    opts.KeywordNames = true;
    if isfield(opts, 'LoaderFallbacks')
        opts = rmfield(opts, 'LoaderFallbacks');
    end
end
if nargin < 1 || isempty(config_path)
    config_path = getenv('SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG');
    if isempty(config_path)
        % alternative variable name
        config_path = getenv('PFAL_MAIN_TEM_ANALYSIS_CONFIG');
    end
    if isempty(config_path)
        config_path = fullfile(repo_root(), 'config', 'main_tem_analysis', ...
            'main_tem_analysis_config.local.json');
    end
end

config_path = char(config_path);
if ~isfile(config_path)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingConfig', ...
        ['TEM analysis config not found: %s\n' ...
        'Create it from config/main_tem_analysis/main_tem_analysis_config.example.json, ' ...
        'or set SOOTMOSAIC_MAIN_TEM_ANALYSIS_CONFIG to an explicit config path.'], ...
        config_path);
end

dictionary = fullfile(repo_root(), 'config', 'main_tem_analysis', ...
    'main_tem_analysis.keys.json');
cfg = UTILS.CONFIG_READ(config_path, dictionary, opts);
config_dir = fileparts(config_path);

% Reading again with the figure and bin sets of this loader where the...
    % ...task gives none
sets = fallback_sets(cfg.plots, validate_entries(cfg.entries, config_dir));
fallback_bins = isfield(sets, 'frequency_bins');
fallback_figures = isfield(sets, 'figures') && ~isfield(cfg.plots, 'figures');
if ~isempty(fieldnames(sets))
    opts.LoaderFallbacks = struct('plots', sets);
    cfg = read_again(config_path, dictionary, opts);
end
read_cfg = cfg;

cfg.config_file = config_path;
cfg.analysis = validate_analysis(cfg.analysis);
cfg.outputs = validate_outputs(cfg.outputs, config_dir);
cfg.entries = validate_entries(cfg.entries, config_dir);
cfg.plots = validate_plots(cfg.plots, {cfg.entries.id}, fallback_bins, ...
    fallback_figures);
cfg.entries = validate_stack_palette_lengths(cfg.entries, ...
    cfg.plots.frequency_bins);

% Mirroring the resolved task with the SI numbers of the reader
cfg.si = si_mirror(rmfield(cfg, {'si', 'provenance'}), read_cfg, read_cfg.si);

end

function cfg = read_again(config_path, dictionary, opts)
% "read_again" reads the task with the fallback sets of this loader.
% ----------------------------------------------------------------------- %

% The first read has warned once for each unknown key, so the second...
    % ...read keeps only that warning off and restores its state on exit
warning_id = 'sootMosaic:CONFIG_READ:UnknownKey';
warning_state = warning('query', warning_id);
restore_warning = onCleanup(@() warning(warning_state));
warning('off', warning_id);
cfg = UTILS.CONFIG_READ(config_path, dictionary, opts);
clear restore_warning

end

function analysis = validate_analysis(analysis)
% "validate_analysis" checks the coverage weighting and summary choices.
% ----------------------------------------------------------------------- %

analysis.coverage_threshold = positive_value(analysis.coverage_threshold, ...
    'analysis.coverage_threshold');
analysis.logistic_bandwidth = positive_value(analysis.logistic_bandwidth, ...
    'analysis.logistic_bandwidth');
analysis.random_seed = plain_empty(analysis.random_seed);

summary = analysis.summary;
if summary.confidence_level <= 0 || summary.confidence_level >= 1
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidConfidenceLevel', ...
        'analysis.summary.confidence_level must be strictly between 0 and 1.');
end
summary.morphology_center = lower(char(summary.morphology_center));
if ~ismember(summary.morphology_center, {'median','mean'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidSummaryCenter', ...
        'analysis.summary.morphology_center must be median or mean.');
end
summary.morphology_spread = lower(char(summary.morphology_spread));
if ~ismember(summary.morphology_spread, {'iqr','standard_deviation'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidSummarySpread', ...
        ['analysis.summary.morphology_spread must be iqr or ' ...
        'standard_deviation.']);
end
summary.morphology_interval = lower(char(summary.morphology_interval));
if ~strcmp(summary.morphology_interval, 'bootstrap_percentile')
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidSummaryInterval', ...
        ['analysis.summary.morphology_interval must be ' ...
        'bootstrap_percentile.']);
end
summary.frequency_interval = lower(char(summary.frequency_interval));
if ~strcmp(summary.frequency_interval, 'wilson')
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidFrequencyInterval', ...
        'analysis.summary.frequency_interval must be wilson.');
end
analysis.summary = summary;

end

function outputs = validate_outputs(outputs, config_dir)
% "validate_outputs" resolves the output folders and file names.
% ----------------------------------------------------------------------- %

outputs.data_root = resolve_config_path(require_text_field( ...
    outputs, 'data_root', 'outputs.data_root'), config_dir);
outputs.results_root = resolve_config_path(require_text_field( ...
    outputs, 'results_root', 'outputs.results_root'), config_dir);
outputs.mat_file = require_text_field(outputs, ...
    'mat_file', 'outputs.mat_file');
outputs.model_inputs_csv = require_text_field(outputs, ...
    'model_inputs_csv', 'outputs.model_inputs_csv');
outputs.summary_csv = require_text_field(outputs, ...
    'summary_csv', 'outputs.summary_csv');
outputs.comparison_summary_csv = char(outputs.comparison_summary_csv);

end

function entries = validate_entries(entries_in, config_dir)
% "validate_entries" checks every entry and returns a structure array.
% ----------------------------------------------------------------------- %

if isempty(entries_in)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingEntries', ...
        'The TEM analysis config must contain a non-empty entries array.');
end
entries_out = cell(numel(entries_in), 1);
for i = 1:numel(entries_in)
    entries_out{i} = validate_entry(entries_in{i}, i, config_dir);
end
entries = object_array(entries_out, ...
    'sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InconsistentEntries', ...
    'entries');
entry_ids = {entries.id};
if numel(unique(entry_ids)) ~= numel(entry_ids)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:DuplicateEntryId', ...
        'Every entries.id value must be unique.');
end
if ~any([entries.enabled])
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:NoEnabledEntries', ...
        'At least one TEM entry must be enabled.');
end

end

function entry = validate_entry(entry, index, config_dir)
% "validate_entry" resolves the entry files and its plot style.
% ----------------------------------------------------------------------- %

label = sprintf('entries(%d)', index);
entry.id = require_text_field(entry, 'id', [label '.id']);
entry.label = require_text_field(entry, 'label', [label '.label']);
entry.entry_type = char(entry.entry_type);
entry.entry_dir = resolve_config_path(require_text_field(entry, ...
    'entry_dir', [label '.entry_dir']), config_dir);

entry.aggregate.file = resolve_entry_path(require_text_field( ...
    entry.aggregate, 'file', [label '.aggregate.file']), entry.entry_dir);
entry.aggregate.variable = require_text_field(entry.aggregate, ...
    'variable', [label '.aggregate.variable']);
entry.primary_particles.folder = resolve_entry_path(require_text_field( ...
    entry.primary_particles, 'folder', [label '.primary_particles.folder']), ...
    entry.entry_dir);
entry.primary_particles.file_pattern = require_text_field( ...
    entry.primary_particles, 'file_pattern', ...
    [label '.primary_particles.file_pattern']);
entry.primary_particles.area_column = require_text_field( ...
    entry.primary_particles, 'area_column', ...
    [label '.primary_particles.area_column']);

if isempty(entry.aggregate_ids)
    entry.aggregate_ids = [];
else
    entry.aggregate_ids = parse_aggregate_ids(entry.aggregate_ids, ...
        [label '.aggregate_ids']);
end
if ~isfield(entry, 'primary_particle_aggregate_ids') || ...
        isempty(entry.primary_particle_aggregate_ids)
    % Using the morphology ids for the primary particles as well
    entry.primary_particle_aggregate_ids = entry.aggregate_ids;
else
    entry.primary_particle_aggregate_ids = parse_aggregate_ids( ...
        entry.primary_particle_aggregate_ids, ...
        [label '.primary_particle_aggregate_ids']);
end
if ~isempty(entry.aggregate_ids) && ...
        any(~ismember(entry.primary_particle_aggregate_ids, ...
        entry.aggregate_ids))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:PrimaryIdsOutsideMorphology', ...
        ['%s.primary_particle_aggregate_ids must be a subset of ', ...
        '%s.aggregate_ids.'], label, label);
end

% Taking the colour set of entry_type and the plot block without a style
if isfield(entry, 'style')
    entry.style = validate_entry_style(entry.style, [label '.style']);
else
    plot_cfg = optional_struct_field(entry, 'plot');
    plot_color = optional_text_field(plot_cfg, 'color', '');
    plot_marker = optional_text_field(plot_cfg, 'marker', 'o');
    entry.style = legacy_style(entry.entry_type, plot_color, plot_marker);
end

if isfield(entry, 'model_filter')
    entry.model_filter = validate_filter(entry.model_filter, label);
else
    entry.model_filter = struct();
end

end

function style = validate_entry_style(style, label)
% "validate_entry_style" checks the colours and markers of one entry.
% ----------------------------------------------------------------------- %

style.color = validate_hex_color(require_text_field(style, 'color', ...
    [label '.color']), [label '.color']);
style.secondary_color = validate_hex_color(require_text_field(style, ...
    'secondary_color', [label '.secondary_color']), ...
    [label '.secondary_color']);
style.box_face_color = optional_style_color(style, 'box_face_color', ...
    style.color, label);
style.median_color = optional_style_color(style, 'median_color', ...
    style.secondary_color, label);
style.marker = require_text_field(style, 'marker', [label '.marker']);
style.marker_size = positive_value(style.marker_size, ...
    [label '.marker_size']);
style.line_width = positive_value(style.line_width, [label '.line_width']);
style.stack_colors = validate_stack_colors(style, label);

end

function stack_colors = validate_stack_colors(style, label)
% "validate_stack_colors" reads the per-bin colours of one entry.
% ----------------------------------------------------------------------- %

if ~isfield(style, 'stack_colors')
    % Giving every bin the colour of the entry
    stack_colors = struct('hybridity', {{style.color}}, ...
        'collapse', {{style.color}});
    return
end
stack_colors.hybridity = validate_color_list(style.stack_colors, ...
    'hybridity', [label '.stack_colors.hybridity']);
stack_colors.collapse = validate_color_list(style.stack_colors, ...
    'collapse', [label '.stack_colors.collapse']);

end

function color = optional_style_color(style, field_name, default_color, label)
% "optional_style_color" reads an optional colour or its default colour.

color = default_color;
if isfield(style, field_name) && ~isempty(style.(field_name))
    color = validate_hex_color(style.(field_name), ...
        [label '.' field_name]);
end

end

function style = legacy_style(entry_type, explicit_color, marker)
% "legacy_style" builds the style of an entry from its entry_type.
% ----------------------------------------------------------------------- %

switch lower(char(entry_type))
    case {'low_agglomeration', 'low_agglom', 'lal'}
        color = '#0072B2'; secondary = '#005A9C';
    case {'high_agglomeration', 'high_agglom', 'ex_agglomeration', 'exaglom'}
        color = '#D55E00'; secondary = '#C45100';
    case {'moderate_collapse', 'moderate_agglomeration', 'mod_collapse', 'hal'}
        color = '#009E73'; secondary = '#007A59';
    case {'extra_collapse', 'extreme_collapse', 'ex_collapse', 'excolaps'}
        color = '#CC79A7'; secondary = '#9E4F7F';
    otherwise
        color = '#0072B2'; secondary = '#005A9C';
end
if ~isempty(explicit_color)
    color = validate_hex_color(explicit_color, 'entries.plot.color');
    secondary = color;
end
style = struct('color', color, 'secondary_color', secondary, ...
    'box_face_color', color, 'median_color', secondary, ...
    'marker', marker, 'marker_size', 36, 'line_width', 1.5, ...
    'box_face_alpha', 0.25, 'stack_colors', struct( ...
    'hybridity', {{color}}, 'collapse', {{color}}));

end

function entries = validate_stack_palette_lengths(entries, frequency_bins)
% "validate_stack_palette_lengths" gives one colour to each configured bin.
% ----------------------------------------------------------------------- %

% Each condition supplies one shade per category so every stack stays...
    % ...within its condition hue in the configured category order
metric_names = {'hybridity','collapse'};
for i = 1:numel(entries)
    for j = 1:numel(metric_names)
        metric_name = metric_names{j};
        colors = entries(i).style.stack_colors.(metric_name);
        required_count = numel(frequency_bins.(metric_name));
        if isscalar(colors) && required_count > 1
            colors = repmat(colors, required_count, 1);
            entries(i).style.stack_colors.(metric_name) = colors;
        elseif numel(colors) ~= required_count
            error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidStackPalette', ...
                ['entries(%d).style.stack_colors.%s must contain one ', ...
                'color per configured bin (%d colors).'], ...
                i, metric_name, required_count);
        end
    end
end

end

function plots = validate_plots(plots, entry_ids, fallback_bins, ...
    fallback_figures)
% "validate_plots" checks the export, style, bin and figure settings.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     plots: plots section after the dictionary read
%     entry_ids: Validated entry ids
%     fallback_bins: Bins built by this loader, kept as one row each
%     fallback_figures: Figures built by this loader, categories kept as...
%         ...one row
% ----------------------------------------------------------------------- %

plots.visible = char(plots.visible);

% Reading the export format and resolution keys as the defaults of the...
    % ...pdf, png and png_resolution keys
export_format = optional_text_field(plots, 'format', 'png');
if ~isfield(plots, 'pdf'), plots.pdf = strcmpi(export_format, 'pdf'); end
if ~isfield(plots, 'png'), plots.png = ~strcmpi(export_format, 'pdf'); end
export_resolution = optional_positive_integer_field(plots, 'resolution', 300);
if ~isfield(plots, 'png_resolution')
    plots.png_resolution = export_resolution;
end
plots.png_source = lower(char(plots.png_source));
if ~ismember(plots.png_source, {'figure','pdf'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidPNGSource', ...
        'plots.png_source must be figure or pdf.');
end
if plots.export && ~plots.pdf && ~plots.png && ~plots.save_figures
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:NoFigureFormat', ...
        'At least one of plots.pdf, plots.png, or plots.save_figures must be enabled.');
end
if plots.export && plots.png && strcmp(plots.png_source, 'pdf') && ~plots.pdf
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingPDFForPNG', ...
        'plots.pdf must be enabled when plots.png_source is pdf.');
end
plots.axis_line_width = positive_value(plots.axis_line_width, ...
    'plots.axis_line_width');
plots.axes = validate_axes_style(plots.axes);
plots.boxplot = validate_boxplot_style(plots.boxplot);
plots.font = validate_font(plots.font);
plots.reference = validate_reference(plots.reference);

metric_names = {'hybridity', 'collapse'};
for i = 1:numel(metric_names)
    label = ['plots.frequency_bins.' metric_names{i}];
    bins = object_array(plots.frequency_bins.(metric_names{i}), ...
        'sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidBins', label);
    if fallback_bins, bins = reshape(bins, 1, []); end
    plots.frequency_bins.(metric_names{i}) = validate_bins(bins, label);
end
validate_bin_coverage(plots.frequency_bins.hybridity, 1, Inf, ...
    'plots.frequency_bins.hybridity', true);
validate_bin_coverage(plots.frequency_bins.collapse, 0, 1, ...
    'plots.frequency_bins.collapse', false);

figure_ids = {'dpp_vs_da_manual_tem', ...
    'primary_particle_distributions', ...
    'appendix_a_primary_particle_distributions', ...
    'aggregate_metric_distributions', ...
    'subaggregate_count_distribution', ...
    'subaggregate_count_frequencies', ...
    'collapsed_subaggregate_frequencies', ...
    'dpp_vs_da_by_hybridity'};
for i = 1:numel(figure_ids)
    id = figure_ids{i};
    plots.figures.(id) = validate_figure_config(plots.figures.(id), id, ...
        entry_ids, fallback_figures);
end
arrow_cfg = plots.figures.subaggregate_count_frequencies.arrows;
if arrow_cfg.target_bin_index > numel(plots.frequency_bins.hybridity)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidArrowBin', ...
        ['plots.figures.subaggregate_count_frequencies.' ...
        'arrows.target_bin_index exceeds the configured bin count.']);
end

end

function axes_style = validate_axes_style(axes_style)
% "validate_axes_style" checks the shared axes appearance.

axes_style.layer = char(axes_style.layer);
axes_style.label_position_mode = char(axes_style.label_position_mode);
if ~ismember(lower(axes_style.label_position_mode), {'auto','manual'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisStyle', ...
        'plots.axes.label_position_mode must be auto or manual.');
end
axes_style.x_label_offset = positive_value(axes_style.x_label_offset, ...
    'plots.axes.x_label_offset');
axes_style.y_label_offset = positive_value(axes_style.y_label_offset, ...
    'plots.axes.y_label_offset');

end

function boxplot_style = validate_boxplot_style(boxplot_style)
% "validate_boxplot_style" checks the shared boxplot appearance.

boxplot_style.symbol = char(boxplot_style.symbol);
boxplot_style.median_min_line_width = positive_value( ...
    boxplot_style.median_min_line_width, ...
    'plots.boxplot.median_min_line_width');
boxplot_style.outlier_marker_size = positive_value( ...
    boxplot_style.outlier_marker_size, 'plots.boxplot.outlier_marker_size');
boxplot_style.whisker_line_style = char(boxplot_style.whisker_line_style);

end

function font = validate_font(font)
% "validate_font" checks the shared typography.

font.family = require_text_field(font, 'family', 'plots.font.family');
font.fallback = require_text_field(font, 'fallback', 'plots.font.fallback');
font.axis_size = positive_value(font.axis_size, 'plots.font.axis_size');
font.label_size = positive_value(font.label_size, 'plots.font.label_size');
font.legend_size = positive_value(font.legend_size, ...
    'plots.font.legend_size');
if isfield(font, 'title_size')
    font.title_size = positive_value(font.title_size, ...
        'plots.font.title_size');
else
    font.title_size = font.label_size;
end
font.weight = require_text_field(font, 'weight', 'plots.font.weight');
if ~ismember(lower(font.weight), {'normal','bold'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidFontWeight', ...
        'plots.font.weight must be normal or bold.');
end
font.interpreter = require_text_field(font, 'interpreter', ...
    'plots.font.interpreter');
if ~ismember(lower(font.interpreter), {'tex','latex','none'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidInterpreter', ...
        'plots.font.interpreter must be tex, latex, or none.');
end

end

function reference = validate_reference(reference)
% "validate_reference" checks the style of the reference correlation.

reference.color = validate_hex_color(require_text_field(reference, ...
    'color', 'plots.reference.color'), 'plots.reference.color');
reference.line_style = require_text_field(reference, 'line_style', ...
    'plots.reference.line_style');
reference.line_width = positive_value(reference.line_width, ...
    'plots.reference.line_width');

end

function colors = validate_color_list(src, field_name, label)
% "validate_color_list" reads a nonempty list of hexadecimal colours.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingColors', ...
        '%s must contain at least one color.', label);
end
colors = cellstr(src.(field_name));
for i = 1:numel(colors)
    colors{i} = validate_hex_color(colors{i}, sprintf('%s(%d)', label, i));
end

end

function bins = validate_bins(bins, label)
% "validate_bins" checks every interval and every pair of intervals.
% ----------------------------------------------------------------------- %

% Validating every interval independently, then comparing all interval...
    % ...pairs so boundary inclusivity cannot create an overlap that...
    % ...depends on bin order
if isempty(bins) || ~isstruct(bins)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidBins', ...
        '%s must be a non-empty struct array.', label);
end
ids = cell(numel(bins), 1);
for i = 1:numel(bins)
    item_label = sprintf('%s(%d)', label, i);
    bins(i).id = require_text_field(bins(i), 'id', [item_label '.id']);
    bins(i).label = require_text_field(bins(i), 'label', [item_label '.label']);
    bins(i).lower = optional_bound(bins(i), 'lower', -Inf, item_label);
    bins(i).upper = optional_bound(bins(i), 'upper', Inf, item_label);
    if bins(i).upper < bins(i).lower
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidBins', ...
            '%s upper bound must be >= lower bound.', item_label);
    end
    ids{i} = bins(i).id;
end
if numel(unique(ids)) ~= numel(ids)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:DuplicateBinId', ...
        '%s bin ids must be unique.', label);
end
for i = 1:numel(bins)
    for j = i + 1:numel(bins)
        if intervals_overlap(bins(i), bins(j))
            error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:OverlappingBins', ...
                '%s bins "%s" and "%s" overlap.', ...
                label, bins(i).id, bins(j).id);
        end
    end
end

end

function tf = intervals_overlap(a, b)
% "intervals_overlap" tests two intervals for a shared value.

left = max(a.lower, b.lower);
right = min(a.upper, b.upper);
if left < right
    tf = true;
elseif left > right
    tf = false;
else
    in_a = (left > a.lower || a.include_lower) && ...
        (left < a.upper || a.include_upper);
    in_b = (left > b.lower || b.include_lower) && ...
        (left < b.upper || b.include_upper);
    tf = in_a && in_b;
end

end

function validate_bin_coverage(bins, domain_lower, domain_upper, label, ...
    discrete_domain)
% "validate_bin_coverage" checks that the bins cover their whole domain.

[~, order] = sort([bins.lower]);
bins = bins(order);
if bins(1).lower > domain_lower || ...
        (bins(1).lower == domain_lower && ~bins(1).include_lower)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:IncompleteBins', ...
        '%s does not include its lower domain boundary.', label);
end
for i = 1:numel(bins) - 1
    if discrete_domain
        current_last = floor(bins(i).upper - double(~bins(i).include_upper));
        next_first = ceil(bins(i + 1).lower + ...
            double(~bins(i + 1).include_lower));
        gap_exists = next_first > current_last + 1;
    else
        gap_exists = bins(i).upper < bins(i + 1).lower || ...
            (bins(i).upper == bins(i + 1).lower && ...
            ~bins(i).include_upper && ~bins(i + 1).include_lower);
    end
    if gap_exists
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:IncompleteBins', ...
            '%s contains a gap between "%s" and "%s".', ...
            label, bins(i).id, bins(i + 1).id);
    end
end
if bins(end).upper < domain_upper || ...
        (isfinite(domain_upper) && bins(end).upper == domain_upper && ...
        ~bins(end).include_upper)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:IncompleteBins', ...
        '%s does not include its upper domain boundary.', label);
end

end

function value = optional_bound(src, field_name, default_value, label)
% "optional_bound" reads an interval edge, unbounded when absent or null.

value = default_value;
if isfield(src, field_name) && ~isempty(src.(field_name))
    candidate = double(src.(field_name));
    % A decoded null inside a numeric array is NaN
    if isscalar(candidate) && isnan(candidate)
        return
    end
    value = candidate;
    if ~isscalar(value) || isnan(value)
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidBound', ...
            '%s.%s must be a numeric scalar or null.', label, field_name);
    end
end

end

function figure_cfg = validate_figure_config(figure_cfg, id, entry_ids, ...
    fallback_figures)
% "validate_figure_config" checks the selection, axes and options of a figure.
% ----------------------------------------------------------------------- %

% Every figure has its own ordered condition selection, axis definition,...
    % ...export name, layout style and figure options. kde_enabled,...
    % ...bar_line_width and legend_item_token_size are complete after...
    % ...the dictionary read
label = ['plots.figures.' id];
figure_cfg.condition_ids = require_text_list(figure_cfg, ...
    'condition_ids', [label '.condition_ids']);
unknown = setdiff(figure_cfg.condition_ids, entry_ids);
if ~isempty(unknown)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:UnknownConditionId', ...
        '%s references unknown condition id(s): %s', ...
        label, strjoin(unknown, ', '));
end
figure_cfg.file_name = require_text_field(figure_cfg, 'file_name', ...
    [label '.file_name']);
if any(figure_cfg.position(3:4) <= 0)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidPosition', ...
        '%s.position must have positive width and height.', label);
end
figure_cfg.x_scale = require_scale(figure_cfg, 'x_scale', label);
figure_cfg.y_scale = require_scale(figure_cfg, 'y_scale', label);
figure_cfg.x_limits = axis_vector(figure_cfg, 'x_limits', 2, label);
figure_cfg.y_limits = axis_vector(figure_cfg, 'y_limits', 2, label);
figure_cfg.x_ticks = axis_vector(figure_cfg, 'x_ticks', [], label);
figure_cfg.y_ticks = axis_vector(figure_cfg, 'y_ticks', [], label);
validate_axis_definition(figure_cfg.x_scale, figure_cfg.x_limits, ...
    figure_cfg.x_ticks, [label '.x']);
validate_axis_definition(figure_cfg.y_scale, figure_cfg.y_limits, ...
    figure_cfg.y_ticks, [label '.y']);
figure_cfg.x_minor_ticks = axis_vector(figure_cfg, 'x_minor_ticks', [], ...
    label);
validate_axis_definition(figure_cfg.x_scale, figure_cfg.x_limits, ...
    figure_cfg.x_minor_ticks, [label '.x_minor']);
positive_keys = {'bar_width', 'condition_spacing', 'box_width', ...
    'ensemble_box_width', 'aggregate_box_width', 'kde_offset', ...
    'kde_width', 'group_padding'};
for i = 1:numel(positive_keys)
    key = positive_keys{i};
    figure_cfg.(key) = positive_value(figure_cfg.(key), [label '.' key]);
end
figure_cfg.bar_edge_color = validate_named_or_hex_color( ...
    char(figure_cfg.bar_edge_color), [label '.bar_edge_color'], {'none'});
figure_cfg.layout_padding = char(figure_cfg.layout_padding);
figure_cfg.tile_spacing = char(figure_cfg.tile_spacing);
if ~isstruct(figure_cfg.axis_overrides)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidStruct', ...
        'The TEM analysis config field %s must be a struct.', ...
        'axis_overrides');
end

% Rebuilding the legend from its five keys. The dictionary leaves an...
    % ...object array only when an entry holds one of them
legend_cfg = figure_cfg.legend;
if ~isscalar(legend_cfg)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidLegend', ...
        '%s.legend must be one object when it sets a legend key.', label);
end
figure_cfg.legend = struct( ...
    'location', char(legend_cfg.location), ...
    'orientation', char(legend_cfg.orientation), ...
    'columns', legend_cfg.columns, ...
    'box', legend_cfg.box, ...
    'interpreter', char(legend_cfg.interpreter));

if strcmp(id, 'subaggregate_count_distribution')
    if figure_cfg.enabled && numel(figure_cfg.condition_ids) ~= 2
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidMirroredConditions', ...
            ['%s.condition_ids must contain exactly two conditions when ', ...
            'the mirrored distribution is enabled.'], label);
    end
    if ~isempty(figure_cfg.x_limits) && ...
            (figure_cfg.x_limits(1) >= 0 || figure_cfg.x_limits(2) <= 0)
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidMirroredLimits', ...
            '%s.x_limits must span zero.', label);
    end
    figure_cfg.grid = validate_mirrored_grid(figure_cfg.grid, label);
    figure_cfg.zero_line = validate_zero_line(figure_cfg.zero_line, label);
    for key = {'stem_line_width', 'marker_size', 'marker_edge_width'}
        figure_cfg.(key{1}) = positive_value(figure_cfg.(key{1}), ...
            [label '.' key{1}]);
    end
    figure_cfg.marker_face_color = validate_named_or_hex_color( ...
        char(figure_cfg.marker_face_color), [label '.marker_face_color'], ...
        {'none'});
else
    figure_cfg.grid = struct();
    figure_cfg.zero_line = struct();
end

if strcmp(id, 'dpp_vs_da_by_hybridity')
    figure_cfg.categories = validate_categories(figure_cfg.categories, ...
        label, fallback_figures);
else
    figure_cfg.categories = optional_struct_array_field(figure_cfg, ...
        'categories');
end

if strcmp(id, 'subaggregate_count_frequencies')
    figure_cfg.arrows = validate_arrow_config(figure_cfg, label, entry_ids);
else
    figure_cfg.arrows = struct();
end

end

function categories = validate_categories(items, label, fallback_figures)
% "validate_categories" checks the subaggregate count categories.
% ----------------------------------------------------------------------- %

categories = object_array(items, ...
    'sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidStruct', ...
    [label '.categories']);
if fallback_figures, categories = reshape(categories, 1, []); end
if isempty(categories)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingCategories', ...
        '%s.categories must be configured.', label);
end
for i = 1:numel(categories)
    category_label = sprintf('%s.categories(%d)', label, i);
    c = categories(i);
    c.id = require_text_field(c, 'id', [category_label '.id']);
    c.label = require_text_field(c, 'label', [category_label '.label']);
    c.lower = optional_bound(c, 'lower', -Inf, category_label);
    c.upper = optional_bound(c, 'upper', Inf, category_label);
    c.color = validate_hex_color(require_text_field(c, 'color', ...
        [category_label '.color']), [category_label '.color']);
    c.marker = require_text_field(c, 'marker', [category_label '.marker']);
    c.marker_size = positive_value(c.marker_size, ...
        [category_label '.marker_size']);
    c.line_width = positive_value(c.line_width, ...
        [category_label '.line_width']);
    categories(i) = c;
end
validate_bins(categories, [label '.categories']);

end

function grid_cfg = validate_mirrored_grid(grid_cfg, label)
% "validate_mirrored_grid" checks the grid of the mirrored distribution.

grid_cfg.major_color = validate_hex_color(char(grid_cfg.major_color), ...
    [label '.grid.major_color']);
grid_cfg.minor_color = validate_hex_color(char(grid_cfg.minor_color), ...
    [label '.grid.minor_color']);
grid_cfg.major_line_style = char(grid_cfg.major_line_style);
grid_cfg.minor_line_style = char(grid_cfg.minor_line_style);

end

function zero_line = validate_zero_line(zero_line, label)
% "validate_zero_line" checks the zero line of the mirrored distribution.

zero_line.color = validate_hex_color(char(zero_line.color), ...
    [label '.zero_line.color']);
zero_line.line_width = positive_value(zero_line.line_width, ...
    [label '.zero_line.line_width']);
zero_line.line_style = char(zero_line.line_style);

end

function arrow_cfg = validate_arrow_config(figure_cfg, label, entry_ids)
% "validate_arrow_config" checks the arrows of the count frequencies.
% ----------------------------------------------------------------------- %

arrow_cfg = figure_cfg.arrows;
if ~isscalar(arrow_cfg)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidArrows', ...
        '%s.arrows must be one object.', label);
end
if isfield(arrow_cfg, 'condition_ids') && ~isempty(arrow_cfg.condition_ids)
    arrow_cfg.condition_ids = require_text_list(arrow_cfg, ...
        'condition_ids', [label '.arrows.condition_ids']);
else
    count = min(2, numel(figure_cfg.condition_ids));
    arrow_cfg.condition_ids = figure_cfg.condition_ids(1:count);
end
unknown = setdiff(arrow_cfg.condition_ids, entry_ids);
if ~isempty(unknown)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:UnknownConditionId', ...
        '%s.arrows references unknown condition id(s): %s', ...
        label, strjoin(unknown, ', '));
end
outside_figure = setdiff(arrow_cfg.condition_ids, figure_cfg.condition_ids);
if ~isempty(outside_figure)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidArrowCondition', ...
        '%s.arrows condition ids must be selected by the figure.', ...
        label);
end
for key = {'shaft_length', 'maximum_tail_y', 'line_width', ...
        'head_marker_size'}
    arrow_cfg.(key{1}) = positive_value(arrow_cfg.(key{1}), ...
        [label '.arrows.' key{1}]);
end
arrow_cfg.color = validate_hex_color(char(arrow_cfg.color), ...
    [label '.arrows.color']);
arrow_cfg.head_marker = char(arrow_cfg.head_marker);

end

function validate_axis_definition(scale, limits, ticks, label)
% "validate_axis_definition" checks ticks against the scale and limits.

if ~isempty(ticks) && any(diff(ticks) <= 0)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisVector', ...
        '%s_ticks must be strictly increasing.', label);
end
if strcmpi(scale, 'log') && (any(limits <= 0) || any(ticks <= 0))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisVector', ...
        '%s limits and ticks must be positive on a log scale.', label);
end
if ~isempty(limits) && ~isempty(ticks) && ...
        (ticks(1) < limits(1) || ticks(end) > limits(2))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisVector', ...
        '%s ticks must remain within the configured limits.', label);
end

end

function value = require_scale(src, field_name, label)
% "require_scale" reads linear or log in any letter case.

value = char(src.(field_name));
if ~ismember(lower(value), {'linear','log'})
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidScale', ...
        '%s.%s must be linear or log.', label, field_name);
end

end

function values = axis_vector(src, field_name, expected_length, label)
% "axis_vector" checks an optional axis vector of the dictionary.

values = plain_empty(src.(field_name));
if isempty(values)
    return
end
if ~isempty(expected_length) && numel(values) ~= expected_length
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisVector', ...
        '%s.%s has invalid values or length.', label, field_name);
end
if numel(values) == 2 && values(2) <= values(1)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAxisVector', ...
        '%s.%s must be increasing.', label, field_name);
end

end

function values = require_text_list(src, field_name, label)
% "require_text_list" reads a nonempty list of distinct texts.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingTextList', ...
        '%s must be a non-empty text array.', label);
end
values = cellstr(src.(field_name));
if numel(unique(values)) ~= numel(values)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:DuplicateConditionId', ...
        '%s must not contain duplicates.', label);
end

end

function sets = fallback_sets(plots, entries)
% "fallback_sets" builds the figure and bin sets a task does not give.

sets = struct();
if ~isfield(plots, 'frequency_bins')
    sets.frequency_bins = legacy_frequency_bins();
end
if ~isfield(plots, 'figures')
    sets.figures = legacy_figures(entries);
elseif ~isfield(plots.figures, 'subaggregate_count_distribution')
    sets.figures.subaggregate_count_distribution = ...
        legacy_subaggregate_count_distribution(entries);
end

end

function bins = legacy_frequency_bins()
% "legacy_frequency_bins" builds the subaggregate count and collapse bins.

bins.hybridity = struct( ...
    'id', {'eq_1','eq_2','three_to_five','six_to_ten','gt_10'}, ...
    'label', {'{\it N}_{\rm subagg} = 1','{\it N}_{\rm subagg} = 2', ...
        '3 \leq {\it N}_{\rm subagg} \leq 5', ...
        '6 \leq {\it N}_{\rm subagg} \leq 10', ...
        '{\it N}_{\rm subagg} > 10'}, ...
    'lower', {1,2,3,6,10}, 'upper', {1,2,5,10,[]}, ...
    'include_lower', {true,true,true,true,false}, ...
    'include_upper', {true,true,true,true,false});
bins.collapse = struct( ...
    'id', {'eq_0','zero_to_low','low_to_high','high_to_one','eq_1'}, ...
    'label', {'{\it f}_{\rm col,subagg} = 0', ...
        '0 < {\it f}_{\rm col,subagg} < 0.33', ...
        '0.33 \leq {\it f}_{\rm col,subagg} \leq 0.67', ...
        '0.67 < {\it f}_{\rm col,subagg} < 1', ...
        '{\it f}_{\rm col,subagg} = 1'}, ...
    'lower', {0,0,0.33,0.67,1}, 'upper', {0,0.33,0.67,1,1}, ...
    'include_lower', {true,false,true,false,true}, ...
    'include_upper', {true,false,true,false,true});

end

function figures = legacy_figures(entries)
% "legacy_figures" builds the figure set of a task without plots.figures.
% ----------------------------------------------------------------------- %

ids = {entries([entries.enabled]).id};
if isempty(ids)
    ids = {entries.id};
end
base = struct('enabled', true, 'condition_ids', {ids}, ...
    'file_name', '', 'position', [100 100 900 600], ...
    'x_scale', 'linear', 'y_scale', 'linear', ...
    'x_limits', [], 'y_limits', [], 'x_ticks', [], 'y_ticks', [], ...
    'legend', struct('location','best','orientation','vertical', ...
        'columns',1,'box',false,'interpreter','none'), ...
    'axis_overrides', struct());
names = {'dpp_vs_da_manual_tem','primary_particle_distributions', ...
    'appendix_a_primary_particle_distributions', ...
    'aggregate_metric_distributions','subaggregate_count_frequencies', ...
    'collapsed_subaggregate_frequencies','dpp_vs_da_by_hybridity'};
positions = {[50 50 900 500],[100 0 850 1800],[100 0 850 1800], ...
    [150 50 1050 900],[200 150 900 500],[200 150 900 500], ...
    [250 200 900 500]};
for i = 1:numel(names)
    item = base;
    item.file_name = names{i};
    item.position = positions{i};
    figures.(names{i}) = item;
end
figures.subaggregate_count_distribution = ...
    legacy_subaggregate_count_distribution(entries);
figures.appendix_a_primary_particle_distributions.enabled = false;
figures.subaggregate_count_frequencies.legend.interpreter = 'tex';
figures.collapsed_subaggregate_frequencies.legend.interpreter = 'tex';
figures.dpp_vs_da_by_hybridity.legend.interpreter = 'tex';
figures.dpp_vs_da_by_hybridity.categories = struct( ...
    'id', {'eq_1','eq_2','three_to_five','gt_5'}, ...
    'label', {'{\it N}_{\rm subagg} = 1', ...
        '{\it N}_{\rm subagg} = 2', ...
        '3 \leq {\it N}_{\rm subagg} \leq 5', ...
        '{\it N}_{\rm subagg} > 5'}, ...
    'lower', {1,2,3,5}, 'upper', {1,2,5,[]}, ...
    'include_lower', {true,true,true,false}, ...
    'include_upper', {true,true,true,false}, ...
    'color', {'#0072B2','#E69F00','#009E73','#CC79A7'}, ...
    'marker', {'^','s','h','o'}, 'marker_size', {36,36,48,36}, ...
    'line_width', {1.5,1.5,1.5,1.5});

end

function figure_cfg = legacy_subaggregate_count_distribution(entries)
% "legacy_subaggregate_count_distribution" builds the mirrored figure.
% ----------------------------------------------------------------------- %

% The mirrored figure stays disabled until its two comparison conditions...
    % ...are selected
ids = {entries([entries.enabled]).id};
if isempty(ids)
    ids = {entries.id};
end
ids = ids(1:min(2, numel(ids)));
figure_cfg = struct( ...
    'enabled', false, ...
    'condition_ids', {ids}, ...
    'file_name', 'subaggregate_count_distribution', ...
    'position', [200 0 1000 1800], ...
    'x_scale', 'linear', ...
    'y_scale', 'log', ...
    'x_limits', [-100 100], ...
    'y_limits', [0.85 120], ...
    'x_ticks', -100:20:100, ...
    'x_minor_ticks', [], ...
    'y_ticks', [1 2 3 4 5 10:10:100], ...
    'stem_line_width', 1.5, ...
    'marker_size', 4, ...
    'marker_edge_width', 1.2, ...
    'marker_face_color', 'none', ...
    'legend_item_token_size', [18 12], ...
    'legend', struct('location', 'eastoutside', ...
        'orientation', 'vertical', 'columns', 1, 'box', false, ...
        'interpreter', 'tex'), ...
    'grid', struct('x_major', false, 'x_minor', false, ...
        'y_major', false, 'y_minor', false), ...
    'zero_line', struct('color', '#4D4D4D', 'line_width', 1.0, ...
        'line_style', '-'));

end

function filter = validate_filter(filter, label)
% "validate_filter" checks the model input filter of one entry.

filter.field = require_text_field(filter, 'field', ...
    [label '.model_filter.field']);
filter.operator = require_text_field(filter, 'operator', ...
    [label '.model_filter.operator']);

end

function ids = parse_aggregate_ids(src, label)
% "parse_aggregate_ids" reads ids as a list, a values object or a range.
% ----------------------------------------------------------------------- %

if isnumeric(src)
    ids = double(src(:));
elseif isstruct(src)
    if isfield(src, 'values')
        ids = double(src.values(:));
    else
        start_id = require_positive_integer_field(src, 'start', ...
            [label '.start']);
        end_id = require_positive_integer_field(src, 'end', ...
            [label '.end']);
        step_id = optional_positive_integer_field(src, 'step', 1);
        if end_id < start_id
            error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAggregateIdRange', ...
                '%s.end must be greater than or equal to start.', ...
                label);
        end
        ids = (start_id:step_id:end_id).';
    end
else
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAggregateIds', ...
        '%s must be a numeric array or range struct.', label);
end
if isempty(ids) || any(~isfinite(ids)) || any(ids <= 0) || any(round(ids) ~= ids)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidAggregateIds', ...
        '%s must contain positive integer ids.', label);
end
ids = unique(ids(:), 'stable');

end

function items = object_array(items, identifier, label)
% "object_array" joins decoded entries with equal keys into one array.

if isempty(items)
    items = [];
    return
end
names = fieldnames(items{1});
if any(cellfun(@(item) ~isempty(setxor(fieldnames(item), names)), items))
    error(identifier, '%s entries must share their keys.', label);
end
items = vertcat(items{:});

end

function out = optional_struct_field(src, field_name)
% "optional_struct_field" reads an optional object, empty when absent.

if isfield(src, field_name) && ~isempty(src.(field_name))
    if ~isstruct(src.(field_name))
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidStruct', ...
            'The TEM analysis config field %s must be a struct.', field_name);
    end
    out = src.(field_name);
else
    out = struct();
end

end

function out = optional_struct_array_field(src, field_name)
% "optional_struct_array_field" reads an optional object array.

out = struct([]);
if isfield(src, field_name) && ~isempty(src.(field_name))
    if ~isstruct(src.(field_name))
        error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidStruct', ...
            'The TEM analysis config field %s must be a struct array.', field_name);
    end
    out = src.(field_name);
end

end

function out = require_text_field(src, field_name, label)
% "require_text_field" reads a required nonempty value as text.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingText', ...
        'The TEM analysis config is missing %s.', label);
end
out = char(src.(field_name));

end

function out = optional_text_field(src, field_name, default_value)
% "optional_text_field" reads optional text or its default.

out = default_value;
if isfield(src, field_name) && ~isempty(src.(field_name))
    out = char(src.(field_name));
end

end

function values = require_scalar_field(src, field_name, label)
% "require_scalar_field" reads a required finite numeric scalar.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:MissingScalar', ...
        'The TEM analysis config is missing %s.', label);
end
values = double(src.(field_name));
if ~isscalar(values) || ~isfinite(values)
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidScalar', ...
        'The TEM analysis config field %s must be a finite numeric scalar.', ...
        label);
end

end

function out = require_positive_integer_field(src, field_name, label)
% "require_positive_integer_field" reads a required positive integer.

out = positive_value(require_scalar_field(src, field_name, label), label);
if round(out) ~= out
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidInteger', ...
        'The TEM analysis config field %s must be a positive integer.', ...
        label);
end

end

function out = optional_positive_integer_field(src, field_name, default_value)
% "optional_positive_integer_field" reads a positive integer or its default.

out = default_value;
if isfield(src, field_name) && ~isempty(src.(field_name))
    out = require_positive_integer_field(src, field_name, field_name);
end

end

function out = positive_value(value, label)
% "positive_value" checks a number that the dictionary made finite.

if value <= 0
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidPositiveScalar', ...
        'The TEM analysis config field %s must be positive.', label);
end
out = value;

end

function out = plain_empty(value)
% "plain_empty" returns an empty vector of the dictionary as [].

out = value;
if isempty(out), out = []; end

end

function value = validate_hex_color(value, label)
% "validate_hex_color" reads a six-digit hexadecimal colour in upper case.

value = upper(char(value));
if isempty(regexp(value, '^#[0-9A-F]{6}$', 'once'))
    error('sootMosaic:LOAD_MAIN_TEM_ANALYSIS_CONFIG:InvalidColor', ...
        '%s must be a six-digit hexadecimal color.', label);
end

end

function value = validate_named_or_hex_color(value, label, allowed_names)
% "validate_named_or_hex_color" reads a named or hexadecimal colour.
% ----------------------------------------------------------------------- %

% Permitting the supported named colour controls alongside hexadecimal...
    % ...colours, without colour abbreviations
value = char(value);
if any(strcmpi(value, allowed_names))
    value = lower(value);
    return
end
value = validate_hex_color(value, label);

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

function full_path = resolve_entry_path(path_value, entry_dir)
% "resolve_entry_path" resolves a path from the entry folder.

full_path = char(path_value);
if is_absolute_path(full_path)
    full_path = normalize_path(full_path);
    return
end
full_path = normalize_path(fullfile(entry_dir, full_path));

end

function full_path = resolve_config_path(path_value, config_dir)
% "resolve_config_path" resolves a path from the task folder.

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
