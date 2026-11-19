function result = READ_SMPS_DB(file, cfg)
% "READ_SMPS_DB" reads named raw records and preserves unresolved exposure.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     file: Database file, unused for the configured csv fallback
%     cfg: Resolved import configuration from LOAD_MAIN_INV_CONFIG
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Valid scans and excluded record indices with reasons. Text...
%         ...count lists are decoded; binary layouts are refused. Dead...
%         ...time values retain unknown units and are never subtracted....
%         ...Record, run_header and device retain all named fields, with...
%         ...NaN for missing numbers and empty text for missing text
% ----------------------------------------------------------------------- %
% Method: SMPS software manual (2019, version 11, pp. 4-7, 4-9, A-1,...
%     ...D-1 and D-2); Wiedensohler et al. (2012, Appendix A5.1).

tables = {'CatenaDataRecord', 'CatenaHeaderRecord', 'CatenaDeviceRecord'};
columns = {
    {'id', 'timestamp', 'dataIndex', 'parentId', 'tLow', 'tUp', 'tHigh', ...
    'tDown', 'vLow', 'vHigh', 'purgeTime', 'samplesPerSecond', ...
    'sheathFlow', 'aerosolFlow', 'gasTemperature', 'gasPressure', ...
    'gasViscosity', 'meanFreePath', 'timeDelay', 'lowerSize', 'upperSize', ...
    'countsData', 'deadTimeData', 'timeDelayAdjustment', 'd50', ...
    'isValid', 'neutralizerXray', 'detectorInletFlow', 'hvPolarity', 'dilution'};
    {'id', 'parentId', 'multiChargeCorrection', 'diffusionLossCorrection', ...
    'refGasTemperature', 'refGasPressure', 'refGasViscosity', ...
    'refMeanFreePath', 'sutherlandConstant', 'tubeLength', 'tubeDiameter', ...
    'dmaInnerRadius', 'dmaOuterRadius', 'dmaLength'};
    {'id', 'parentId', 'model', 'dmaModel', 'cpcModel', 'neutralizerModel', ...
    'impactorModel'}};
text_columns = {
    {'timestamp', 'name', 'description', 'countsData', 'deadTimeData', 'hvPolarity'};
    {'name', 'description', 'start', 'end', 'interval', 'status', ...
    'nanoEnhancer', 'cpcD50Setting', 'location', 'timezone', 'waterCpcDetMode'};
    {'name', 'model', 'serialNumber', 'firmwareVersion', 'productRevision', ...
    'calibrationDate', 'config', 'dmaModel', 'cpcModel', 'impactorModel', ...
    'neutralizerModel', 'dmaSerial', 'cpcSerial', 'impactorSerial', ...
    'neutralizerSerial', 'rhtModel', 'rhtSerial'}};
reader = cfg.inputs.database_reader;
if strcmp(reader, 'sqlite')
    if exist('sqlite', 'file') == 0
        fail('MissingInterface', ...
            'Select csv and supply the three externally exported tables.');
    end
    try
        db = sqlite(file, 'readonly');
    catch err
        fail('OpenDatabase', err.message);
    end
    cleanup = onCleanup(@() close(db));
elseif ~strcmp(reader, 'csv')
    fail('InvalidReader', 'database_reader must be sqlite or csv.');
end
records = cell(3, 1);
for t = 1:3
    if strcmp(reader, 'sqlite')
        try
            info = fetch(db, ['SELECT COALESCE(name, '''') AS name FROM ' ...
                'pragma_table_info(''' tables{t} ''') ORDER BY cid']);
            if istable(info), info = table2cell(info); end
            names = cellstr(string(info(:, 1)))';
        catch err
            fail('Schema', [tables{t} ': ' err.message]);
        end
        require_columns(names, columns{t}, tables{t});
        values = read_nullable(db, tables{t}, names, text_columns{t});
    else
        path = fullfile(cfg.inputs.csv_fallback_dir, [tables{t} '.csv']);
        try
            opts = detectImportOptions(path, 'VariableNamingRule', 'preserve');
            opts = setvartype(opts, opts.VariableNames, 'string');
            tab = readtable(path, opts);
        catch err
            fail('ReadCsv', [tables{t} ': ' err.message]);
        end
        names = tab.Properties.VariableNames;
        require_columns(names, columns{t}, tables{t});
        values = table2cell(tab);
        for n = 1:numel(names)
            for j = 1:size(values, 1)
                value = string(values{j, n});
                if any(strcmp(names{n}, text_columns{t}))
                    if ismissing(value), value = ""; end
                    values{j, n} = char(value);
                else
                    values{j, n} = str2double(value);
                end
            end
        end
        [~, order] = sort(cellfun(@numeric, values(:, strcmp(names, 'id'))));
        values = values(order, :);
    end
    record_names = names;
    counting = strcmp(record_names, 'Detector Counting Flow (L/min)');
    if any(counting)
        if any(strcmp(record_names, 'detectorCountingFlow'))
            fail('DuplicateCountingFlow', 'Counting flow has two column labels.');
        end
        record_names{find(counting, 1)} = 'detectorCountingFlow';
    end
    records{t} = cell(size(values, 1), 1);
    for j = 1:size(values, 1)
        records{t}{j} = cell2struct(values(j, :), record_names, 2);
        if t == 2
            for n = 1:numel(columns{t})
                key = columns{t}{n};
                records{t}{j}.(key) = numeric(records{t}{j}.(key));
            end
        elseif t == 3
            records{t}{j}.id = numeric(records{t}{j}.id);
            records{t}{j}.parentId = numeric(records{t}{j}.parentId);
        end
    end
end
result = struct('source_kind', 'smps_database', 'scans', {{}}, ...
    'excluded', struct('scan_index', {}, 'record_id', {}, 'reason', {}), ...
    'report', {{'Dead-time units and count correction remain unresolved.'}});
map = {
    'sheathFlow', 'dma_sheath_flow_lpm', 1;
    'aerosolFlow', 'dma_aerosol_flow_lpm', 1;
    'detectorInletFlow', 'counter_inlet_flow_lpm', 1;
    'gasTemperature', 'dma_temperature_deg_c', 1;
    'gasPressure', 'dma_pressure_kpa', 1;
    'gasViscosity', 'logged_viscosity_pa_s', 1;
    'meanFreePath', 'logged_mean_free_path_nm', 1e9;
    'vLow', 'voltage_low_v', 1;
    'vHigh', 'voltage_high_v', 1;
    'timeDelay', 'delay_s', 1;
    'timeDelayAdjustment', 'delay_adjustment_s', 1;
    'lowerSize', 'window_min_nm', 1;
    'upperSize', 'window_max_nm', 1;
    'd50', 'impactor_d50_nm', 1;
    'dilution', 'software_dilution_factor', 1};
refmap = {
    'refGasTemperature', 'reference_temperature_k', 1;
    'refGasPressure', 'reference_pressure_kpa', 1;
    'refGasViscosity', 'reference_viscosity_pa_s', 1;
    'refMeanFreePath', 'reference_mean_free_path_nm', 1e9;
    'sutherlandConstant', 'reference_sutherland_k', 1};
for k = 1:numel(records{1})
    raw = records{1}{k};
    valid = logical_field(raw.isValid, 'isValid');
    if ~valid
        result.excluded(end+1) = struct('scan_index', k, ...
            'record_id', numeric(raw.id), 'reason', 'X1: isValid false');
        continue
    end
    parent = numeric(raw.parentId);
    head = parent_record(records{2}, parent, tables{2});
    device = parent_record(records{3}, parent, tables{3});
    counts = series(raw.countsData, 'countsData');
    dead = series(raw.deadTimeData, 'deadTimeData');
    if numel(counts) ~= numel(dead)
        fail('BinCount', 'countsData and deadTimeData lengths differ.');
    end
    rate = numeric(raw.samplesPerSecond);
    if rate <= 0, fail('SampleRate', 'samplesPerSecond must be positive.'); end
    dt = 1 / rate;
    duration_s = numel(counts) * dt;
    up = numeric(raw.tUp);
    candidates = [1, 0.001];
    matches = abs(up * candidates - duration_s) <= ...
        16 * eps(max(1, duration_s));
    if sum(matches) ~= 1
        fail('UndocumentedBinLayout', ...
            ['Record ' char(string(raw.id)) ': sample count does not ' ...
            'establish an up-scan-only layout in seconds or milliseconds.']);
    end
    scale = candidates(matches);
    scan = struct('source_kind', 'smps_database', 'scan_index', k, ...
        'record_id', numeric(raw.id), 'run_id', parent, ...
        'run_scan_index', numeric(raw.dataIndex), 'flags', ...
        {{'Provisional exposure; dead-time semantics unresolved.'}}, ...
        'dilution_applied', false);
    scan.timestamp_text = char(string(raw.timestamp));
    if isempty(scan.timestamp_text)
        fail('Timestamp', 'Expected a UTC timestamp ending in Z.');
    end
    try
        scan.timestamp = datetime(scan.timestamp_text, ...
            'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', ...
            'TimeZone', 'UTC');
    catch
        fail('Timestamp', 'Expected a UTC timestamp ending in Z.');
    end
    if isnat(scan.timestamp)
        fail('Timestamp', 'Expected a UTC timestamp ending in Z.');
    end
    scan.channels = struct('values', counts, 'quantity', 'raw counts', ...
        'unit', 'counts', 'time_s', (0:numel(counts)-1)' * dt);
    scan.dead_time = struct('values', dead, 'quantity', 'deadTimeData', ...
        'unit', 'unknown', 'used_in_exposure', false);
    scan.raw_timing = struct('tLow', numeric(raw.tLow), 'tUp', up, ...
        'tHigh', numeric(raw.tHigh), 'tDown', numeric(raw.tDown));
    scan.timing_scale_s = scale;
    scan.timing_reason = ...
        'Time scale checked against list length and samplesPerSecond.';
    scan.purge_time_s = numeric(raw.purgeTime);
    scan.data.scan = struct('valid', true, 'counts', counts, ...
        'timestamp', scan.timestamp_text, 'bin_time_s', dt, ...
        'up_time_s', duration_s, 'low_hold_s', numeric(raw.tLow) * scale, ...
        'high_hold_s', numeric(raw.tHigh) * scale, ...
        'retrace_time_s', numeric(raw.tDown) * scale, ...
        'purge_time_s', scan.purge_time_s, ...
        'mcc_on', logical_field(head.multiChargeCorrection, 'MCC'), ...
        'dlc_on', logical_field(head.diffusionLossCorrection, 'DLC'));
    for j = 1:size(map, 1)
        scan.data.scan.(map{j, 2}) = numeric(raw.(map{j, 1})) * map{j, 3};
    end
    for j = 1:size(refmap, 1)
        scan.data.scan.(refmap{j, 2}) = ...
            numeric(head.(refmap{j, 1})) * refmap{j, 3};
    end
    scan.neutralizer_xray = logical_field(raw.neutralizerXray, ...
        'neutralizerXray');
    neutralizer = regexp(device.neutralizerModel, '^\d+', 'match', 'once');
    if ~isempty(neutralizer), scan.data.scan.neutralizer_id = neutralizer; end
    if isempty(raw.hvPolarity)
        fail('MissingField', 'hvPolarity is required.');
    end
    scan.data.scan.high_voltage_polarity = lower(char(string(raw.hvPolarity)));
    scan.data.scan.particle_polarity = ...
        particle_polarity(scan.data.scan.high_voltage_polarity);
    key = 'detectorCountingFlow';
    if isfield(raw, key) && ~isempty(raw.(key)) && isfinite(raw.(key))
        scan.data.scan.counting_flow_lpm = numeric(raw.(key));
    end
    scan.record = raw;
    scan.run_header = head;
    scan.device = device;
    scan.geometry_reason = ...
        'Database geometry and tube fields retained without inferred units.';
    result.scans{end+1, 1} = scan;
end
end

function values = read_nullable(db, table_name, names, text_names)
% Fetching nonnull values with explicit null and storage-type markers
expressions = cell(1, 3*numel(names));
is_text = ismember(names, text_names);
for n = 1:numel(names)
    quoted = ['"' strrep(names{n}, '"', '""') '"'];
    kind = ['typeof(' quoted ')'];
    if is_text(n)
        value = ['CASE WHEN ' kind ' = ''blob'' THEN '''' ELSE ' ...
            'COALESCE(CAST(' quoted ' AS TEXT), '''') END'];
    else
        value = ['CASE WHEN ' kind ' IN (''integer'', ''real'') THEN ' ...
            quoted ' ELSE 0 END'];
    end
    expressions(3*n-2:3*n) = {value, [quoted ' IS NULL'], kind};
end
rows = fetch(db, ['SELECT ' strjoin(expressions, ',') ' FROM "' ...
    table_name '" ORDER BY "id"']);
if istable(rows), rows = table2cell(rows); end
values = cell(size(rows, 1), numel(names));
for n = 1:numel(names)
    for j = 1:size(rows, 1)
        kind = char(string(rows{j, 3*n}));
        is_null = logical(rows{j, 3*n-1});
        if strcmp(kind, 'blob')
            values{j, n} = uint8([]);
        elseif is_text(n)
            if is_null, values{j, n} = '';
            else, values{j, n} = char(string(rows{j, 3*n-2}));
            end
        elseif is_null || ~any(strcmp(kind, {'integer', 'real'}))
            values{j, n} = NaN;
        else
            values{j, n} = double(rows{j, 3*n-2});
        end
    end
end
end

function row = parent_record(records, parent, name)
match = cellfun(@(r) numeric(r.parentId) == parent, records);
if sum(match) ~= 1
    fail('ParentRecord', [name ' must have one row for each parentId.']);
end
row = records{find(match, 1)};
end

function require_columns(available, required, name)
for k = 1:numel(required)
    if ~any(strcmp(available, required{k}))
        fail('MissingColumn', [name '.' required{k} ' is missing.']);
    end
end
end

function value = logical_field(raw, label)
value = numeric(raw);
if ~ismember(value, [0 1]), fail('InvalidFlag', label); end
value = logical(value);
end

function value = numeric(raw)
if isnumeric(raw), value = double(raw);
else, value = str2double(string(raw));
end
if ~isscalar(value) || ~isfinite(value)
    fail('InvalidNumber', 'Expected a finite scalar database field.');
end
end

function value = series(raw, label)
if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    fail('UndocumentedBlob', [label ' binary representation is undocumented.']);
end
text = strtrim(char(raw));
if isempty(regexp(text, '^\d+(\s*,\s*\d+)*$', 'once'))
    fail('UndocumentedBlob', ...
        [label ' must be a complete comma-separated nonnegative integer list.']);
end
value = str2double(strsplit(text, ','))';
if any(~isfinite(value) | value > flintmax)
    fail('InvalidCounts', [label ' exceeds exact integer representation.']);
end
end

function fail(reason, message)
error(['sootMosaic:READ_SMPS_DB:' reason], '%s', message);
end

function value = particle_polarity(hv)
switch lower(hv)
    case 'negative'
        value = 'positive';
    case 'positive'
        value = 'negative';
    otherwise
        fail('InvalidPolarity', ...
            'Recorded voltage polarity must be positive or negative.');
end
end
