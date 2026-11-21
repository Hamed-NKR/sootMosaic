function result = READ_SMPS(file)
% "READ_SMPS" reads labeled mobility distributions and scan metadata.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     file: Delimited export with labeled metadata and diameter columns
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Scans in cells, with channels, comparison statistics and...
%         ...data at configuration paths in recorded units. No dilution...
%         ...is applied. Missing impactor inputs carry a reason
% ----------------------------------------------------------------------- %
% Method: Wiedensohler et al. (2012, Appendices A4 and A5.1); SMPS...
%     ...software manual (2019, version 11, pp. 4-3, 4-4 and 4-9).

try
    lines = regexp(fileread(file), '\r\n|\n|\r', 'split');
catch err
    fail('ReadFile', err.message);
end
metadata_rows = cell(numel(lines), 1);
header = {};
for k = 1:numel(lines)
    row = csv_row(lines{k});
    if any(strcmp(row, 'Scan Number'))
        header = row;
        first = k + 1;
        break
    end
    keys = 1:2:numel(row)-1;
    keys = keys(~cellfun(@isempty, row(keys)));
    metadata_rows{k} = [row(keys)', row(keys+1)'];
end
metadata = vertcat(metadata_rows{:});
if isempty(metadata), metadata = cell(0, 2); end
if isempty(header), fail('MissingHeader', 'Missing Scan Number header.'); end
while ~isempty(header) && isempty(header{end}), header(end) = []; end
if numel(unique(header)) ~= numel(header)
    fail('DuplicateHeader', 'Scan column labels must be unique.');
end
diameters = str2double(header);
columns = find(isfinite(diameters) & diameters > 0);
if isempty(columns), fail('MissingChannels', 'No diameter columns found.'); end
[diameters, order] = sort(diameters(columns));
columns = columns(order);
if any(diff(diameters) <= 0)
    fail('DuplicateDiameter', 'Channel diameters must be distinct.');
end
units = meta('Units');
switch lower(units)
    case 'raw counts', quantity = 'raw counts';
    case 'concentration (dw)', quantity = 'dW';
    case 'dw/dlogdp', quantity = 'dW/dlogDp';
    otherwise, fail('UnsupportedUnits', ['Unsupported Units: ' units]);
end
common = struct('units', units, 'weight', meta('Weight'), ...
    'channels_per_decade', str2double(meta('Channels/Decade')), ...
    'mcc_on', flag(meta('Multiple Charge Correction')), ...
    'dlc_on', flag(meta('Diffusion Loss Correction')));
common.high_voltage_polarity = lower(meta('HV Polarity'));
common.particle_polarity = particle_polarity(common.high_voltage_polarity);
common.neutralizer_id = meta('Neutralizer Model');
refs = {
    'Reference Gas Viscosity (Pa*s)', 'reference_viscosity_pa_s', 1;
    'Reference Mean Free Path (m)', 'reference_mean_free_path_nm', 1e9;
    'Reference Gas Temperature (K)', 'reference_temperature_k', 1;
    'Reference Gas Pressure (kPa)', 'reference_pressure_kpa', 1;
    'Sutherland Constant (K)', 'reference_sutherland_k', 1;
    'Tube Length (cm)', 'equalizer_length_cm', 1;
    'Tube Diameter (cm)', 'equalizer_bore_cm', 1};
for j = 1:size(refs, 1)
    common.(refs{j, 2}) = str2double(meta(refs{j, 1})) * refs{j, 3};
end
model = meta('Impactor Model');
token = regexp(model, '^\s*([0-9]+(?:\.[0-9]+)?)\s+cm(?:\s+cm)?\s*$', ...
    'tokens', 'once');
nozzle = NaN;
if ~isempty(token), nozzle = str2double(token{1}); end
map = {
    'Detector Counting Flow (L/min)', 'counting_flow_lpm', 1;
    'Detector Inlet Flow (L/min)', 'counter_inlet_flow_lpm', 1;
    'Sheath Flow (L/min)', 'dma_sheath_flow_lpm', 1;
    'Sheath Temp (C)', 'dma_temperature_deg_c', 1;
    'Sheath Pressure (kPa)', 'dma_pressure_kpa', 1;
    'Mean Free Path (m)', 'logged_mean_free_path_nm', 1e9;
    'Gas Viscosity (Pa*s)', 'logged_viscosity_pa_s', 1;
    'Low Voltage (V)', 'voltage_low_v', 1;
    'High Voltage (V)', 'voltage_high_v', 1;
    'Lower Size (nm)', 'window_min_nm', 1;
    'Upper Size (nm)', 'window_max_nm', 1;
    'Scan Time (s)', 'up_time_s', 1;
    'Retrace Time (s)', 'retrace_time_s', 1;
    'DMA Column transit time Tf (s)', 'column_transit_s', 1;
    'DMA Exit to Optical Detector Td (s)', 'delay_s', 1;
    'DMA at Low Voltage (TLOW) (s)', 'low_hold_s', 1;
    'Adjustment (s)', 'delay_adjustment_s', 1;
    'Dilution Factor', 'software_dilution_factor', 1;
    'Impactor D50 (nm)', 'impactor_d50_nm', 1};
result = struct('source_kind', 'smps_export', 'metadata', {metadata}, ...
    'scans', {{}}, 'report', {{}});
for k = first:numel(lines)
    if isempty(strtrim(lines{k})), continue; end
    row = csv_row(lines{k});
    if numel(row) < numel(header)
        fail('ShortRow', sprintf('Incomplete scan at line %d.', k));
    end
    if numel(row) > numel(header) && any(~cellfun(@isempty, ...
            row(numel(header)+1:end)))
        fail('LongRow', sprintf('Unlabeled scan fields at line %d.', k));
    end
    scan = struct('source_kind', 'smps_export', 'source_line', k, ...
        'scan_index', number('Scan Number'), 'flags', {{}}, ...
        'dilution_applied', false);
    values = str2double(row(columns));
    missing = cellfun(@(x) isempty(x) || ...
        any(strcmpi(x, {'N/A', 'NaN'})), row(columns));
    if any(~isfinite(values) & ~missing)
        fail('InvalidChannels', 'Invalid numeric channel value.');
    end
    scan.channels = struct('diameter_nm', diameters(:), ...
        'values', values(:), 'quantity', quantity, 'weight', common.weight, ...
        'unit', units);
    scan.data.scan = common;
    for j = 1:size(map, 1)
        scan.data.scan.(map{j, 2}) = number(map{j, 1}) * map{j, 3};
    end
    stamp = field('DateTime Sample Start');
    scan.timestamp_text = stamp;
    scan.data.scan.timestamp = stamp;
    try
        scan.timestamp = datetime(stamp, 'InputFormat', 'dd/MM/yyyy HH:mm:ss');
    catch
        fail('InvalidTimestamp', sprintf('Invalid timestamp at line %d.', k));
    end
    scan.data.scan.valid = [];
    scan.data.scan.neutralizer_on = flag(field('Neutralizer Status'));
    scan.status = struct('detector', field('Detector Status'), ...
        'classifier', field('Classifier Errors'), ...
        'communication', field('Communication Status'));
    scan.impactor_model = model;
    scan.data.instruments = struct('impactor_nozzle_cm', nozzle, ...
        'impactor_flow_lpm', number('Impactor Flow (L/min)'));
    scan.impactor_reason = {};
    if ~isfinite(nozzle) || nozzle <= 0
        scan.impactor_reason{end+1} = 'Missing or unparsable Impactor Model.';
    end
    if ~(scan.data.instruments.impactor_flow_lpm > 0)
        scan.impactor_reason{end+1} = 'Missing or invalid Impactor Flow.';
    end
    if ~(scan.data.scan.impactor_d50_nm > 0)
        scan.impactor_reason{end+1} = 'Missing or invalid Impactor D50.';
    end
    scan.impactor_available = isempty(scan.impactor_reason);
    scan.purge_time_s = [];
    scan.purge_reason = 'No purge field; TLOW is an internal low-voltage hold.';
    scan.software_statistics = struct('mode_nm', number('Mode (nm)'), ...
        'geometric_mean_nm', number('Geo. Mean (nm)'), ...
        'geometric_sd_ratio', number('Geo. Std. Dev'), ...
        'total_cm3_inv', NaN);
    total_col = find(startsWith(header, 'Total Concentration (#/cm'));
    if isscalar(total_col)
        scan.software_statistics.total_cm3_inv = str2double(row{total_col});
    end
    scan.data = omit_missing(scan.data);
    result.scans{end+1, 1} = scan;
end
if isempty(result.scans), fail('NoScans', 'The export contains no scans.'); end
indices = cellfun(@(s) s.scan_index, result.scans);
if any(~isfinite(indices) | indices < 1 | indices ~= fix(indices)) || ...
        numel(unique(indices)) ~= numel(indices)
    fail('ScanIndex', 'Scan Number must contain distinct positive integers.');
end

    function value = meta(label)
        idx = find(strcmp(metadata(:, 1), label));
        value = '';
        if numel(idx) > 1, fail('DuplicateMetadata', label); end
        if ~isempty(idx), value = metadata{idx, 2}; end
    end

    function value = field(label)
        idx = find(strcmp(header, label));
        value = '';
        if ~isempty(idx), value = row{idx}; end
    end

    function value = number(label)
        value = str2double(field(label));
    end
end

function result = omit_missing(result)
names = fieldnames(result);
for k = 1:numel(names)
    value = result.(names{k});
    if isstruct(value)
        result.(names{k}) = omit_missing(value);
    elseif isnumeric(value) && isscalar(value) && isnan(value)
        result = rmfield(result, names{k});
    end
end
end

function value = flag(text)
if any(strcmpi(text, {'true', 'on', '1'})), value = true;
elseif any(strcmpi(text, {'false', 'off', '0'})), value = false;
elseif isempty(text), value = [];
else, fail('InvalidFlag', ['Unrecognized flag: ' text]);
end
end

function cells = csv_row(line)
cells = cell(1, numel(line)+1);
value = blanks(numel(line));
cell_count = 0;
value_count = 0;
quoted = false;
k = 1;
while k <= numel(line)
    c = line(k);
    if c == '"'
        if quoted && k < numel(line) && line(k+1) == '"'
            value_count = value_count + 1;
            value(value_count) = '"';
            k = k + 1;
        else
            quoted = ~quoted;
        end
    elseif c == ',' && ~quoted
        cell_count = cell_count + 1;
        cells{cell_count} = strtrim(value(1:value_count));
        value_count = 0;
    else
        value_count = value_count + 1;
        value(value_count) = c;
    end
    k = k + 1;
end
if quoted, fail('QuotedField', 'Unclosed quoted field.'); end
cell_count = cell_count + 1;
cells{cell_count} = strtrim(value(1:value_count));
cells = cells(1:cell_count);
end

function fail(reason, message)
error(['sootMosaic:READ_SMPS:' reason], '%s', message);
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
