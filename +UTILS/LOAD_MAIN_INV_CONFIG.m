function cfg = LOAD_MAIN_INV_CONFIG(config_path, data, campaign, opts)
% "LOAD_MAIN_INV_CONFIG" resolves inversion settings and their sources.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     config_path: Task file, or empty for the environment selector and...
%         ...the local file beside the example. An absent default local...
%         ...file selects the example
%     data: Scalar structure of per-scan values at dictionary paths, in...
%         ...the recorded units. An absent field means unavailable
%     campaign: One table row with values and reasons structure cells, or...
%         ...a scalar structure with values and reasons. Reasons use the...
%         ...same paths as values. Instrument settings in data win over...
%         ...workbook cells; both values remain in the reading record
%     opts: Strict rejects unknown keys and unresolved placeholders....
%         ...RequiredPaths lists inputs needed by the calling stage....
%         ...Derived supplies X values. TestFixture allows explicit grid...
%         ...limits. ConfigDirectory and RegistryDirectory select fixture...
%         ...folders without changing the tracked files
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cfg: Recorded values and si values converted once, profile, selected...
%         ...registry entries, provenance, reading records and pending keys....
%         ...Missing stage inputs remain pending until RequiredPaths names...
%         ...them. No inversion or measured-data import is performed
% ----------------------------------------------------------------------- %

if nargin < 1, config_path = ''; end
if nargin < 2 || isempty(data), data = struct(); end
if nargin < 3 || isempty(campaign), campaign = struct(); end
if nargin < 4, opts = struct(); end
require_object(opts, 'options');
require_object(data, 'data');
strict = option(opts, 'Strict', false);
fixture = option(opts, 'TestFixture', false);
if ~islogical(strict) || ~isscalar(strict) || ...
        ~islogical(fixture) || ~isscalar(fixture)
    fail('InvalidOptions', 'Strict and TestFixture must be logical scalars.');
end
required = option(opts, 'RequiredPaths', {});
if ~(iscellstr(required) || isstring(required))
    fail('InvalidOptions', 'RequiredPaths must be a list of paths.');
end
required = cellstr(required);
derived = option(opts, 'Derived', struct());
require_object(derived, 'derived values');
[values, reasons] = campaign_values(campaign);
root = fileparts(fileparts(mfilename('fullpath')));
directory = option(opts, 'ConfigDirectory', ...
    fullfile(root, 'config', 'main_inv'));
registry_dir = option(opts, 'RegistryDirectory', ...
    fullfile(root, 'config', 'instruments'));
if isempty(config_path)
    config_path = getenv('SOOTMOSAIC_MAIN_INV_CONFIG');
    if isempty(config_path)
        config_path = fullfile(directory, 'main_inv_config.local.json');
        if ~isfile(config_path)
            config_path = fullfile(directory, 'main_inv_config.example.json');
        end
    end
end
dictionary = fullfile(directory, 'main_inv.keys.json');
rows = read_rows(dictionary);
cfg = read_raw(config_path, dictionary, rows, strict);
original = cfg;
[cfg.model, ~, cfg.model_params, cfg.model_source] = ...
    UTILS.MODEL_PROFILE(cfg.model_profile, 'INV', ...
    option(cfg, 'model_overrides', struct()), struct('Strict', strict));
if ~strcmp(cfg.model.fluid_properties, 'sutherland') || ...
        ~strcmp(cfg.model.slip_correction, 'kim2005')
    fail('InvalidGasModel', 'INV requires logged-state gas and slip models.');
end
rdict = fullfile(registry_dir, 'instruments.keys.json');
rrows = read_rows(rdict);
instruments = read_raw(fullfile(registry_dir, 'instruments.json'), ...
    rdict, rrows, strict);
charging = read_raw(fullfile(registry_dir, 'charging.json'), ...
    rdict, rrows, strict);
check_ids(instruments.entries);
check_ids(charging.models);
groups = {'classifier', 'dma', 'cpc', 'neutralizer', 'aac'};
registry = struct();
cfg.instrument_entries = struct();
cfg.pending = struct('path', {}, 'reason', {});
for k = 1:numel(groups)
    group = groups{k};
    item = pick(instruments.entries, cfg.instruments.(group));
    if ~strcmp(item.kind, group)
        fail('RegistryKind', 'Selected registry entry has the wrong kind.');
    end
    cfg.instrument_entries.(group) = item;
    registry.(group) = item.constants;
    for j = 1:numel(item.pending)
        key = item.pending{j};
        if isempty(get_path(item.constants, key))
            pending(['registry.' group '.' key], source_note(item, key));
        end
    end
end
cfg.charge_model = pick(charging.models, cfg.charging.model);
registry.charge = cfg.charge_model;
ids = [{cfg.charging.model}; cfg.charging.sensitivity_models(:)];
cfg.charge_models = cell(size(ids));
for k = 1:numel(ids)
    item = pick(charging.models, ids{k});
    cfg.charge_models{k} = item;
    if strcmp(item.coefficients_state, 'pending') && ...
            isempty(item.coefficients)
        pending(['charging.' item.id '.coefficients'], ...
            'The cited coefficient table is unavailable.');
    elseif ~strcmp(item.coefficients_state, 'ready') || ...
            isempty(item.coefficients)
        fail('InvalidChargeTable', 'Charge table marker and contents disagree.');
    end
    if isempty(item.ion_mobility_ratio)
        pending(['charging.' item.id '.ion_mobility_ratio'], item.ratio_note);
    end
end
cfg.registry_source = struct('instruments', instruments.provenance, ...
    'charging', charging.provenance);
roles = {'penetration_dma', 'internal_paths', 'op_dma', 'op_aac'};
role_ids = {cfg.penetration.dma, cfg.penetration.internal_paths, ...
    cfg.op_range.dma, cfg.op_range.aac};
for k = 1:numel(roles)
    item = pick(instruments.entries, role_ids{k});
    registry.(roles{k}) = item.constants;
end
cfg.reading = struct('path', {}, 'code', {}, 'effective_code', {}, ...
    'source', {}, 'value', {}, 'from_config', {}, 'reason', {}, ...
    'abs_tol', {}, 'rel_tol', {}, 'comparisons', {});

% Resolving each source in its recorded unit before SI conversion
for k = 1:numel(rows)
    row = rows{k};
    p = row.path;
    if contains(p, '[]'), continue; end
    code = row.reading_rule;
    configured = get_path(original, p);
    if ~option(row, 'configurable', true) && ~isempty(configured)
        fail('ConfiguredSource', ['Read-only source cannot be configured: ' p]);
    end
    sources = struct('config', {configured});
    sources.data = get_path(data, option(row, 'data_from', p));
    if isfield(row, 'resolved_from')
        sources.data = get_path(cfg, row.resolved_from);
    end
    if strcmp(p, 'charging.model') && isempty(sources.data)
        neutralizer = get_path(data, 'scan.neutralizer_id');
        if isequal(neutralizer, '3088')
            sources.data = 'soft_xray_3082_tableB3';
        elseif ischar(neutralizer) && ...
                any(strcmp(neutralizer, {'3077', '3077a', 'kr85'}))
            sources.data = 'kr85_wiedensohler';
        end
    end
    sources.campaign = get_path(values, option(row, 'campaign_from', p));
    sources.derived = get_path(derived, p);
    sources.registry = get_path(registry, option(row, 'registry_path', ''));
    sources.profile = get_path(cfg.model_params, ...
        option(row, 'profile_path', ''));
    if isfield(row, 'derived_value'), sources.derived = row.derived_value; end
    if isempty(sources.config) && isfield(row, 'config_from')
        sources.config = get_path(cfg, row.config_from);
    end
    fallback = option(row, 'registry_fallback', '');
    if isempty(sources.config) && ~isempty(fallback)
        sources.config = get_path(registry, fallback);
    end
    reason = get_path(reasons, option(row, 'campaign_from', p));
    if isempty(reason), reason = ''; end
    if ~isempty(sources.campaign) && ...
            ~(ischar(reason) && isrow(reason) && ~isempty(strtrim(reason)))
        fail('MissingReason', ['Campaign value requires a reason: ' p]);
    end
    rel_tol = tolerance_for(row, cfg);
    effective = code;
    if option(row, 'data_override', false)
        sources.config = sources.registry;
        effective = 'D>C';
    end
    if strcmp(code, 'W>D>C') && option(row, 'instrument_first', false) && ...
            ~isempty(sources.data)
        effective = 'D>C';
    end
    if ~isempty(sources.config) && any(strcmp(p, ...
            {'grid.d_min_nm', 'grid.d_max_nm'})) && ~fixture
        fail('ExplicitGrid', 'Grid limits require TestFixture.');
    end
    if ~has_source(effective, sources)
        if isfield(row, 'placeholder')
            pending(p, row.placeholder);
        elseif ~any(strcmp(code, {'C', 'C~D'}))
            pending(p, ['Unavailable under reading rule ' code]);
        end
        continue
    end
    [value, record] = UTILS.CONFIG_DATA_RULE(effective, sources, ...
        struct('Path', p, 'RelTol', rel_tol, 'Reason', reason));
    if strcmp(row.type, 'list of objects') && isstruct(value)
        value = num2cell(value(:));
    end
    if strcmp(code, 'W>D>C') && ~strcmp(effective, code)
        pair = comparison('data', 'campaign', sources.data, ...
            sources.campaign, p, rel_tol);
        lower_pair = comparison('campaign', 'config', sources.campaign, ...
            sources.config, p, rel_tol);
        record.comparisons = [record.comparisons; pair; lower_pair];
    end
    if isfield(row, 'value_kind') && strcmp(row.value_kind, 'logical') && ...
            (~islogical(value) || ~isscalar(value))
        fail('InvalidSource', ['Expected a logical scan flag: ' p]);
    end
    validate_source(value, row);
    if strcmp(row.type, 'list of objects')
        validate_children(value, p, rows);
    end
    cfg = put_path(cfg, strsplit(p, '.'), value);
    record.code = code;
    record.effective_code = effective;
    record = orderfields(record, fieldnames(cfg.reading));
    if option(row, 'data_override', false) && record.from_config
        record.source = 'registry';
        record.from_config = false;
    end
    if ~isempty(fallback) && isempty(configured) && record.from_config
        record.source = 'registry';
        record.from_config = false;
    end
    cfg.reading(end + 1, 1) = record;
end

% Matching the logged nozzle against the cited range of its registry entry
cfg.impactor_entry = [];
nozzle = cfg.instruments.impactor_nozzle_cm;
if ~isempty(nozzle)
    for k = 1:numel(instruments.entries)
        item = instruments.entries{k};
        if strcmp(item.kind, 'impactor') && ...
                isequal(get_path(item.constants, 'nozzle_cm'), nozzle)
            cfg.impactor_entry = item;
            break
        end
    end
    if isempty(cfg.impactor_entry)
        fail('MissingRegistryId', 'No registry entry matches the nozzle.');
    end
end
cfg.si = original.si;
for k = 1:numel(rows)
    row = rows{k};
    cfg.si = convert_path(cfg.si, cfg, strsplit(row.path, '.'), row.unit);
end
instrument_si = instruments.si;
charge_si = charging.si;
for k = 1:numel(rrows)
    row = rrows{k};
    parts = strsplit(row.path, '.');
    instrument_si = convert_path(instrument_si, instruments, parts, row.unit);
    charge_si = convert_path(charge_si, charging, parts, row.unit);
end
cfg.si.instrument_entries = struct();
for k = 1:numel(groups)
    group = groups{k};
    cfg.si.instrument_entries.(group) = ...
        pick(instrument_si.entries, cfg.instruments.(group));
end
cfg.si.charge_model = pick(charge_si.models, cfg.charging.model);
cfg.si.impactor_entry = [];
if ~isempty(cfg.impactor_entry)
    cfg.si.impactor_entry = pick(instrument_si.entries, cfg.impactor_entry.id);
end
for k = 1:numel(required)
    if ~any(cellfun(@(r) strcmp(r.path, required{k}), rows))
        fail('UnknownRequiredPath', ['Unknown required path: ' required{k}]);
    end
    if isempty(get_path(cfg, required{k}))
        fail('MissingValue', ['Required input is unavailable: ' required{k}]);
    end
end
if strict && ~isempty(cfg.pending)
    unresolved = {cfg.pending.path};
    is_placeholder = startsWith(unresolved, 'registry.') | ...
        endsWith(unresolved, '.coefficients') | ...
        endsWith(unresolved, '.ion_mobility_ratio');
    for k = 1:numel(rows)
        if isfield(rows{k}, 'placeholder')
            is_placeholder = is_placeholder | strcmp(unresolved, rows{k}.path);
        end
    end
    if any(is_placeholder)
        fail('Placeholder', ['Unresolved placeholders: ' ...
            strjoin(unresolved(is_placeholder), ', ')]);
    end
end

    function pending(p, reason)
        cfg.pending(end + 1, 1) = struct('path', p, 'reason', reason);
    end
end

function rows = read_rows(file)
rows = jsondecode(fileread(file));
if isstruct(rows), rows = num2cell(rows); end
end

function cfg = read_raw(file, dictionary, rows, strict)
% Validating recorded values while deferring conversion until selection
schema = rows;
for k = 1:numel(schema)
    unit_scale(schema{k}.unit);
    schema{k}.unit = 'none';
    schema{k}.status = 'keep';
    if strcmp(schema{k}.type, 'text or none') && isempty(schema{k}.default)
        schema{k}.default = '';
    end
    if strcmp(schema{k}.type, 'number or none') && ...
            isfield(schema{k}, 'default') && isempty(schema{k}.default)
        schema{k}.default = 'none';
    end
end
cfg = UTILS.CONFIG_READ(file, schema, struct('Strict', strict));
record = struct('file', dictionary, 'sha256', '', 'notes', {{}});
if usejava('jvm')
    record.sha256 = UTILS.FILE_SHA256(dictionary);
else
    record.notes = {'digest skipped, no JVM'};
end
cfg.provenance.dictionary = record;
end

function [values, reasons] = campaign_values(row)
if istable(row)
    if height(row) ~= 1
        fail('InvalidCampaign', 'Pass exactly one campaign table row.');
    end
    row = table2struct(row);
end
require_object(row, 'campaign row');
values = option(row, 'values', struct());
reasons = option(row, 'reasons', struct());
if iscell(values) && isscalar(values), values = values{1}; end
if iscell(reasons) && isscalar(reasons), reasons = reasons{1}; end
require_object(values, 'campaign values');
require_object(reasons, 'campaign reasons');
end

function check_ids(entries)
ids = cellfun(@(x) x.id, entries, 'UniformOutput', false);
if any(cellfun(@isempty, ids)) || numel(unique(ids)) ~= numel(ids)
    fail('RegistryId', 'Registry ids must be nonempty and unique.');
end
end

function item = pick(entries, id)
index = find(cellfun(@(x) strcmp(x.id, id), entries), 1);
if isempty(index)
    fail('MissingRegistryId', ['Registry id not found: ' id]);
end
item = entries{index};
end

function note = source_note(item, key)
note = 'Source value is not quoted in the supplied design.';
for k = 1:numel(item.sources)
    row = item.sources{k};
    if any(strcmp(row.keys, key)), note = row.note; return; end
end
end

function yes = has_source(code, s)
switch code
    case 'D', names = {'data'};
    case 'D>C', names = {'data', 'config'};
    case {'C', 'C~D'}, names = {'config'};
    case 'R', names = {'registry'};
    case 'P', names = {'profile'};
    case 'W>D>C', names = {'campaign', 'data', 'config'};
    case 'X', names = {'derived'};
    otherwise, fail('ReadingRule', ['Unknown reading rule: ' code]);
end
yes = any(cellfun(@(n) ~isempty(s.(n)), names));
end

function tol = tolerance_for(row, cfg)
path = option(row, 'tolerance', '');
if isempty(path)
    if contains(row.path, 'flow')
        path = 'checks.flow_rel_tol';
    elseif contains(row.path, 'setpoint')
        path = 'checks.setpoint_rel_tol';
    elseif contains(row.path, 'temperature') || ...
            contains(row.path, 'pressure') || contains(row.path, 'viscosity')
        path = 'checks.gas_property_rel_tol';
    end
end
tol = get_path(cfg, path);
if isempty(tol), tol = 0; end
end

function pair = comparison(a, b, va, vb, path, tol)
pair = struct('source_a', {}, 'source_b', {}, 'value_a', {}, ...
    'value_b', {}, 'difference', {}, 'limit', {}, 'different', {}, ...
    'exceeds_tolerance', {});
if isempty(va) || isempty(vb), return; end
different = ~isequaln(va, vb);
delta = [];
limit = [];
exceeds = different;
if isnumeric(va) && isnumeric(vb) && isequal(size(va), size(vb))
    delta = abs(va - vb);
    limit = tol * abs(vb);
    exceeds = any(delta(:) > limit(:));
end
pair = struct('source_a', a, 'source_b', b, 'value_a', {va}, ...
    'value_b', {vb}, 'difference', delta, 'limit', limit, ...
    'different', different, 'exceeds_tolerance', exceeds);
if exceeds
    warning('sootMosaic:LOAD_MAIN_INV_CONFIG:Mismatch', ...
        '%s differs between %s and %s.', path, a, b);
end
end

function validate_source(value, row)
% Checking selected scan values against the task dictionary constraints
type = row.type;
switch type
    case {'number', 'number or none', 'integer', 'integer or empty'}
        valid = isnumeric(value) && isscalar(value) && isreal(value);
    case {'vector', 'matrix'}
        valid = isnumeric(value) && isreal(value);
        if isfield(row, 'value_kind'), valid = islogical(value); end
    case {'text', 'text or none'}
        valid = ischar(value) && (isrow(value) || isempty(value));
    case 'logical', valid = islogical(value) && isscalar(value);
    case 'object', valid = isstruct(value) && isscalar(value);
    case 'list of text', valid = iscellstr(value) || isstring(value);
    case 'list of objects'
        valid = iscell(value) && all(cellfun(@isstruct, value));
    otherwise, valid = false;
end
if ~valid
    fail('InvalidSource', ['Selected value has the wrong type: ' row.path]);
end
if isnumeric(value)
    if any(~isfinite(value(:))) || ...
            (contains(type, 'integer') && any(value(:) ~= fix(value(:)))) || ...
            (isfield(row, 'min') && any(value(:) < row.min)) || ...
            (isfield(row, 'max') && any(value(:) > row.max))
        fail('InvalidSource', ['Selected number is outside its bounds: ' row.path]);
    end
end
if isfield(row, 'length') && numel(value) ~= row.length
    fail('InvalidSource', ['Selected vector has the wrong length: ' row.path]);
end
if isfield(row, 'allowed')
    allowed = row.allowed;
    if ~iscell(allowed), allowed = num2cell(allowed); end
    if ~any(cellfun(@(x) isequaln(x, value), allowed))
        fail('InvalidSource', ['Selected value is not allowed: ' row.path]);
    end
end
end

function validate_children(values, prefix, rows)
for k = 1:numel(rows)
    row = rows{k};
    head = [prefix '[].'];
    if ~startsWith(row.path, head), continue; end
    path = row.path(numel(head) + 1:end);
    for j = 1:numel(values)
        value = get_path(values{j}, path);
        if isempty(value) && option(row, 'required', false)
            fail('InvalidSource', ['Missing segment field: ' row.path]);
        end
        if ~isempty(value), validate_source(value, row); end
    end
end
end

function output = convert_path(output, raw, parts, unit)
key = parts{1};
array = endsWith(key, '[]');
if array, key = key(1:end - 2); end
if ~isfield(raw, key), return; end
value = raw.(key);
if isscalar(parts)
    [scale, offset] = unit_scale(unit);
    if isnumeric(value), value = value .* scale + offset; end
    output.(key) = value;
elseif array
    result = value;
    if isstruct(result), result = num2cell(result); end
    for k = 1:numel(result)
        result{k} = convert_path(output.(key){k}, result{k}, parts(2:end), unit);
    end
    output.(key) = result;
else
    lower = struct();
    if isfield(output, key), lower = output.(key); end
    output.(key) = convert_path(lower, value, parts(2:end), unit);
end
end

function [scale, offset] = unit_scale(unit)
scale = 1;
offset = 0;
switch unit
    case 'L/min', scale = 1e-3 / 60;
    case 'nm', scale = 1e-9;
    case 'cm', scale = 1e-2;
    case 'mm', scale = 1e-3;
    case 'kPa', scale = 1e3;
    case 'degC', offset = 273.15;
    case 'percent', scale = 1e-2;
    case '1/cm3', scale = 1e6;
    case 'ug/m3', scale = 1e-9;
    case {'none', 'counts', 'm', 's', 'K', 'Pa s', 'V', 'rad/s', ...
            'kg/m3', 'm3', 'J/K', 'C', 'F/m'}
    otherwise, fail('UnknownUnit', ['Unsupported recorded unit: ' unit]);
end
end

function value = get_path(object, path)
value = [];
if isempty(path), return; end
parts = strsplit(path, '.');
for k = 1:numel(parts)
    if ~isstruct(object) || ~isscalar(object) || ~isfield(object, parts{k})
        return
    end
    object = object.(parts{k});
end
value = object;
end

function object = put_path(object, parts, value)
key = parts{1};
if isscalar(parts)
    object.(key) = value;
else
    child = struct();
    if isfield(object, key), child = object.(key); end
    object.(key) = put_path(child, parts(2:end), value);
end
end

function value = option(object, key, fallback)
if isfield(object, key), value = object.(key); else, value = fallback; end
end

function require_object(value, label)
if ~isstruct(value) || ~isscalar(value)
    fail('InvalidInput', [label ' must be a scalar structure.']);
end
end

function fail(reason, message)
error(['sootMosaic:LOAD_MAIN_INV_CONFIG:' reason], '%s', message);
end
