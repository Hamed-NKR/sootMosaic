function [model, known, params, source] = MODEL_PROFILE(name, stage, ...
        overrides, opts)
% "MODEL_PROFILE" resolves profile values and records their sources.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     name: Profile basename in config/profiles
%     stage: LD1, LD2 or INV
%     overrides: Optional common-section values, applied after the stage
%     opts: Optional reader controls. Strict rejects unknown keys....
%         ...Directory selects a profile folder for isolated fixtures....
%         ...BuiltinOnly reads the mirror for checkpoint completion
% ----------------------------------------------------------------------- %
%
% Outputs:
%     model: Model choices saved with the run
%     known: Implemented choices, in interface order
%     params: Resolved sections, SI values and conditional rules
%     source: File, digest, mirror flags, chain and override records
% ----------------------------------------------------------------------- %

persistent warned
if nargin < 3, overrides = struct(); end
if nargin < 4, opts = struct(); end
known.fluid_properties = {'sutherland', 'flame', 'room'};
known.mobility = {'sorensen_eq17', 'continuum', 'sorensen_backbone', ...
    'interp', 'free_molecular'};
known.slip_correction = {'kim2005', 'per_caller_7658971'};
known.continuum_diameter = {'sorensen_backbone', 'fixed_075dg'};
known.root_solve = {'bracketed', 'start_point_7658971'};
known.projection = {'isotropic', 'euler_7658971'};
known.initial_velocity = {'maxwell_boltzmann', 'mean_speed_7658971'};
if ~(ischar(name) || isStringScalar(name)) || isempty(name) || ...
        isempty(regexp(char(name), '^[A-Za-z0-9_]+$', 'once'))
    error('sootMosaic:MODEL_PROFILE:UnknownProfile', ...
        'A profile basename is required.');
end
if ~(ischar(stage) || isStringScalar(stage)) || ...
        ~any(strcmp(char(stage), {'LD1', 'LD2', 'INV'}))
    error('sootMosaic:MODEL_PROFILE:UnknownStage', ...
        'The stage must be LD1, LD2 or INV.');
end
name = char(name);
stage = char(stage);
if ~isstruct(opts) || ~isscalar(opts) || ...
        ~isstruct(overrides) || ~isscalar(overrides)
    error('sootMosaic:MODEL_PROFILE:InvalidOptions', ...
        'Overrides and reader controls must be scalar structures.');
end
directory = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'config', 'profiles');
if isfield(opts, 'Directory'), directory = opts.Directory; end
strict = false;
if isfield(opts, 'Strict'), strict = opts.Strict; end
builtin_only = false;
if isfield(opts, 'BuiltinOnly'), builtin_only = opts.BuiltinOnly; end
if ~islogical(strict) || ~isscalar(strict) || ...
        ~islogical(builtin_only) || ~isscalar(builtin_only)
    error('sootMosaic:MODEL_PROFILE:InvalidOptions', ...
        'Strict and BuiltinOnly must be scalar logical values.');
end
file = fullfile(directory, [name '.json']);
dictionary = fullfile(directory, 'profile.keys.json');
mirror = UTILS.MODEL_DEFAULTS(name);
records = struct('path', {}, 'old_value', {}, 'new_value', {}, 'source', {});
source = struct('file', '', 'sha256', '', 'builtin', false, ...
    'matches_builtin', false, 'files', [], 'dictionary', [], ...
    'overrides', records);
if ~builtin_only && isfile(file) && isfile(dictionary)
    [profile, provenance] = UTILS.CONFIG_READ(file, dictionary, ...
        struct('Strict', strict));
    profile = rmfield(profile, {'si', 'provenance'});
    source.file = provenance.files(end).file;
    source.sha256 = provenance.files(end).sha256;
    source.files = provenance.files;
    source.dictionary = provenance.dictionary;
    source.overrides = provenance.overrides;
    source.matches_builtin = isequal(profile, mirror);
    if ~isempty(mirror) && ~source.matches_builtin
        if strcmp(name, 'article1_7658971')
            error('sootMosaic:MODEL_PROFILE:EditedLegacyProfile', ...
                'The fixed profile is edited. Use a custom profile.');
        end
        warning('sootMosaic:MODEL_PROFILE:ProfileDiffersFromBuiltIn', ...
            'Profile %s differs from its built-in mirror.', name);
    end
    % Checking fixed parents before accepting a custom extends chain
    for k = 1:numel(provenance.files) - 1
        parent = provenance.files(k).file;
        [~, parent_name] = fileparts(parent);
        if strcmp(parent_name, 'article1_7658971')
            fixed = UTILS.CONFIG_READ(parent, dictionary, ...
                struct('Strict', strict));
            fixed = rmfield(fixed, {'si', 'provenance'});
            if ~isequal(fixed, UTILS.MODEL_DEFAULTS(parent_name))
                error('sootMosaic:MODEL_PROFILE:EditedLegacyProfile', ...
                    'The fixed parent is edited. Use a custom profile.');
            end
        end
    end
else
    if isempty(mirror)
        error('sootMosaic:MODEL_PROFILE:UnknownProfile', ...
            'No profile file or built-in mirror exists for %s.', name);
    end
    profile = mirror;
    source.builtin = true;
    source.matches_builtin = true;
    if isempty(warned), warned = {}; end
    if ~builtin_only && ~any(strcmp(warned, name))
        warning('sootMosaic:MODEL_PROFILE:BuiltInProfile', ...
            ['Profile %s or its dictionary is missing. ', ...
            'Using the built-in mirror.'], name);
        warned{end + 1} = name;
    end
end
if ~isfield(profile.stages, stage)
    error('sootMosaic:MODEL_PROFILE:UnknownStage', ...
        'Profile %s has no %s stage.', name, stage);
end
params = rmfield(profile, {'config_version', 'profile', ...
    'description', 'stages'});
params = UTILS.CONFIG_MERGE(params, profile.stages.(stage));
% Validating direct overrides against the same dictionary as file values
if ~isempty(fieldnames(overrides))
    if isfile(dictionary)
        rows = jsondecode(fileread(dictionary));
        if isstruct(rows), rows = num2cell(rows); end
    else
        template = UTILS.MODEL_DEFAULTS('current');
        template = rmfield(template, {'config_version', 'profile', ...
            'description', 'stages'});
        rows = mirror_rows(template, '', known);
    end
    overrides = validate_overrides(overrides, rows, '', strict);
    [params, changes] = UTILS.CONFIG_MERGE(params, overrides, '<arguments>');
    source.overrides = [source.overrides; changes];
end
model = struct('profile', name, 'fluid_properties', params.gas.model, ...
    'slip_correction', params.slip.model, ...
    'mobility', params.mobility.method, ...
    'continuum_diameter', params.mobility.continuum_diameter, ...
    'root_solve', params.mobility.root_solve, ...
    'projection', params.projection.method, ...
    'proj_cache', params.projection.cache, ...
    'proj_points', params.projection.points, ...
    'proj_orientations', params.projection.orientations, ...
    'proj_replicates', params.projection.replicates, ...
    'proj_tol', params.projection.tol, ...
    'knudsen_diagnostics', params.diagnostics.knudsen, ...
    'initial_velocity', params.initial_velocity.sampler);
if strcmp(model.mobility, 'continuum'), model.mobility = 'sorensen_eq17'; end
choices = fieldnames(known);
for k = 1:numel(choices)
    key = choices{k};
    if ~any(strcmp(model.(key), known.(key)))
        error('sootMosaic:MODEL_PROFILE:UnknownModel', ...
            'No implementation exists for %s in %s.', model.(key), key);
    end
end
params.si = params;
params.si.reference.dpp100_nm = params.reference.dpp100_nm * 1e-9;
params.si.reference.m100_fg = params.reference.m100_fg * 1e-18;
params.resolved.rho_aero_ref_kg_m3 = params.constants.rho_aero_ref_kg_m3;
params.resolved.root_tolerance = 'eps_scaled';
if strcmp(model.slip_correction, 'per_caller_7658971')
    params.resolved.rho_aero_ref_kg_m3 = params.constants.rho_bc_kg_m3;
    if strcmp(model.root_solve, 'start_point_7658971')
        params.resolved.root_tolerance = 'default';
    end
end
end

function rows = mirror_rows(value, prefix, known)
% "mirror_rows" infers override constraints when only the mirror is present.
rows = {};
names = fieldnames(value);
integers = {'points', 'orientations', 'replicates', 'backbone_crossover_n', ...
    'march_series_terms', 'projection_default_n', 'projection_min_n'};
choice_paths = {'gas.model', 'slip.model', 'mobility.method', ...
    'mobility.continuum_diameter', 'mobility.root_solve', ...
    'projection.method', 'initial_velocity.sampler'};
choice_fields = {'fluid_properties', 'slip_correction', 'mobility', ...
    'continuum_diameter', 'root_solve', 'projection', 'initial_velocity'};
for k = 1:numel(names)
    key = names{k};
    path = key;
    if ~isempty(prefix), path = [prefix '.' key]; end
    item = value.(key);
    row = struct('path', path, 'type', 'number');
    if isstruct(item)
        row.type = 'object';
    elseif ischar(item)
        row.type = 'text';
        j = find(strcmp(choice_paths, path), 1);
        if ~isempty(j), row.allowed = known.(choice_fields{j}); end
        if strcmp(path, 'step.step_policy'), row.allowed = {'warn', 'cap'}; end
    elseif islogical(item)
        row.type = 'logical';
    else
        if ~isscalar(item), row.type = '3 numbers'; end
        if any(strcmp(integers, key)), row.type = 'integer'; end
        if strcmp(path, 'projection.tol'), row.type = 'number or none'; end
        if ~strcmp(path, 'mobility.eq17.exponent'), row.min = 0; end
        if strcmp(row.type, 'integer'), row.min = 1; end
    end
    rows{end + 1, 1} = row; %#ok<AGROW>
    if strcmp(path, 'reference.mass_mobility_exponent')
        row.path = 'reference.d_m';
        row.alias_of = path;
        rows{end + 1, 1} = row; %#ok<AGROW>
    end
    if isstruct(item)
        rows = [rows; mirror_rows(item, path, known)]; %#ok<AGROW>
    end
end
end

function value = validate_overrides(value, rows, prefix, strict)
% "validate_overrides" checks section values using dictionary constraints.
names = fieldnames(value);
paths = cellfun(@(r) r.path, rows, 'UniformOutput', false);
for k = 1:numel(names)
    key = names{k};
    if strcmp(key, 'comment'), value = rmfield(value, key); continue; end
    path = key;
    if ~isempty(prefix), path = [prefix '.' key]; end
    j = find(strcmp(paths, path), 1);
    if any(strcmp(key, {'stages', 'profile', 'description', ...
            'config_version', 'extends'})) && isempty(prefix)
        error('sootMosaic:MODEL_PROFILE:InvalidOverride', ...
            'Only common-section values can be overridden.');
    end
    if isempty(j)
        if strict
            error('sootMosaic:MODEL_PROFILE:UnknownKey', ...
                'Unknown override key %s; nearest known key is %s.', ...
                path, nearest(path, paths));
        end
        warning('sootMosaic:MODEL_PROFILE:UnknownKey', ...
            'Unknown override key %s; nearest known key is %s.', ...
            path, nearest(path, paths));
        value = rmfield(value, key);
        continue
    end
    row = rows{j};
    if isfield(row, 'alias_of') && ~isempty(row.alias_of)
        parts = strsplit(row.alias_of, '.');
        target = parts{end};
        warning('sootMosaic:MODEL_PROFILE:Alias', ...
            'Key %s is an alias of %s.', path, row.alias_of);
        item = value.(key);
        value = rmfield(value, key);
        if isfield(value, target), continue; end
        key = target;
        value.(key) = item;
        path = row.alias_of;
        row = rows{find(strcmp(paths, path), 1)};
    end
    item = value.(key);
    type = row.type;
    if strcmp(type, 'number or none') && ((isnumeric(item) && isempty(item)) || ...
            isequal(item, 'none') || isequal(item, Inf))
        value.(key) = Inf;
        continue
    end
    switch type
        case 'object'
            valid = isstruct(item) && isscalar(item);
        case 'text'
            valid = ischar(item) && isrow(item);
        case 'logical'
            valid = islogical(item) && isscalar(item);
        otherwise
            valid = isnumeric(item) && isreal(item) && ...
                all(isfinite(item(:)));
            if strcmp(type, '3 numbers')
                valid = valid && isvector(item) && numel(item) == 3;
                item = item(:);
            else
                valid = valid && isscalar(item);
            end
            if strcmp(type, 'integer')
                valid = valid && item == fix(item);
            end
    end
    if valid && isfield(row, 'allowed')
        valid = any(strcmp(item, row.allowed));
    end
    if valid && isnumeric(item) && isfield(row, 'min')
        valid = all(item(:) >= row.min);
    end
    if ~valid
        error('sootMosaic:MODEL_PROFILE:InvalidOverride', ...
            'Override %s does not meet its dictionary constraints.', path);
    end
    if strcmp(type, 'object')
        item = validate_overrides(item, rows, path, strict);
    end
    value.(key) = item;
end
end

function best = nearest(path, paths)
% "nearest" finds the dictionary path with the fewest character edits.
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
