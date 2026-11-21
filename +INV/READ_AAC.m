function result = READ_AAC(file)
% "READ_AAC" reads labeled aerodynamic scans in acquisition order.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     file: SASS or AACS scan export
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Scans, header pairs and report lines. Row conditions retain...
%         ...their recorded units. Spectra carry quantity labels; the...
%         ...corrected spectrum is comparison data only
% ----------------------------------------------------------------------- %
% Method: AAC manual (2023, v2.43, Secs. 2.3.4 and 2.5.3); Johnson et...
%     ...al. (2018, Eqs. 9-11, pp. 660-661).

try
    lines = regexp(fileread(file), '\r\n|\n|\r', 'split');
catch err
    fail('ReadFile', err.message);
end
metadata_rows = cell(numel(lines), 1);
starts = zeros(1, numel(lines));
start_count = 0;
for k = 1:numel(lines)
    row = split_row(lines{k});
    if strcmpi(row{1}, 'SCAN')
        start_count = start_count + 1;
        starts(start_count) = k;
    end
    if start_count == 0, metadata_rows{k} = pairs(row); end
end
starts = starts(1:start_count);
metadata = vertcat(metadata_rows{:});
if isempty(metadata), metadata = cell(0, 2); end
if isempty(starts), fail('NoScans', 'No SCAN blocks found.'); end
if contains(lower(lines{1}), 'sass')
    format = 'sass';
elseif contains(lower(lines{1}), 'step')
    format = 'aacs';
else
    fail('Format', 'Expected a scanning or stepped aerodynamic export.');
end
result = struct('source_kind', 'aac_export', 'format', format, ...
    'metadata', {metadata}, 'scans', {{}}, 'report', {{}});
for s = 1:numel(starts)
    begin = starts(s);
    if s < numel(starts), last = starts(s+1)-1;
    else, last = numel(lines);
    end
    pair_rows = cell(last-begin, 1);
    labels = {};
    finish = [];
    for k = begin+1:last
        row = split_row(lines{k});
        if any(strcmpi(row, 'Size (nm)'))
            labels = row;
            data_start = k + 1;
            break
        end
        pair_rows{k-begin} = pairs(row);
    end
    scan_pairs = vertcat(pair_rows{:});
    if isempty(scan_pairs), scan_pairs = cell(0, 2); end
    if isempty(labels), fail('MissingHeader', 'Missing Size (nm) header.'); end
    if numel(unique(lower(string(labels)))) ~= numel(labels)
        fail('DuplicateHeader', 'Data column labels must be unique.');
    end
    cells = cell(last-data_start+1, numel(labels));
    row_count = 0;
    for k = data_start:last
        row = split_row(lines{k});
        if startsWith(upper(row{1}), 'END OF SCAN')
            finish = k;
            break
        end
        if isempty(strtrim(lines{k})), continue; end
        if numel(row) ~= numel(labels)
            fail('RowWidth', sprintf('Column count differs at line %d.', k));
        end
        row_count = row_count + 1;
        cells(row_count, :) = row;
    end
    cells = cells(1:row_count, :);
    if isempty(finish) || isempty(cells)
        fail('IncompleteScan', 'A scan is empty or lacks END OF SCAN.');
    end
    scan = struct('source_kind', 'aac_export', 'format', format, ...
        'scan_index', s, 'flags', {{}}, 'dilution_applied', false, ...
        'metadata', {scan_pairs}, 'column_labels', {labels});
    start_row = split_row(lines{begin});
    scan.scan_index = str2double(start_row{2});
    if ~isfinite(scan.scan_index) || scan.scan_index < 1 || ...
            scan.scan_index ~= fix(scan.scan_index)
        fail('ScanIndex', 'SCAN requires a positive integer index.');
    end
    scan.channels = struct('diameter_nm', column('Size (nm)', true), ...
        'values', column('Size Spectral Density (dN/dLog(Da)/cc)', true), ...
        'quantity', 'dN/dlog10Da', 'unit', 'cm^-3');
    scan.corrected_spectrum = struct('values', ...
        column('Corrected Size Spectral Density (dN/dLog(Da)/cc)', false), ...
        'quantity', 'dN/dlog10Da', 'unit', 'cm^-3', ...
        'role', 'comparison only');
    scan.spectra = struct('label', {}, 'values', {}, 'quantity', {}, 'unit', {});
    for j = 1:numel(labels)
        if contains(lower(labels{j}), 'spectral density')
            scan.spectra(end+1) = struct('label', labels{j}, ...
                'values', column(labels{j}, true), ...
                'quantity', labels{j}, 'unit', 'as labeled');
        end
    end
    scan.counter_cm3_inv = column('Serial Detector (#/cc)', false);
    if any(~isfinite(scan.channels.diameter_nm) | scan.channels.diameter_nm <= 0)
        fail('Diameter', 'Aerodynamic diameter must be finite and positive.');
    end
    scan.conditions = struct('aac_setpoint_nm', scan.channels.diameter_nm, ...
        'aac_speed_rad_s', column('Speed (rad/s)', true), ...
        'aac_sheath_flow_lpm', column('Sheath (lpm)', true), ...
        'aac_temperature_deg_c', column('Sheath Temp (C)', true), ...
        'aac_pressure_pa', column('Classifier Pressure (Pa)', true), ...
        'relaxation_time_ns', column('Tau (ns)', true));
    scan.lag_percent = column('Speed Error (%)', false);
    scan.ramp_time_s = column('Scan Ramp Time (s)', false);
    scan.ramp_speed_rad_s = column('Scan Ramp Speed (rad/s)', false);
    scan.data.scan = struct('aac_sample_flow_lpm', ...
        meta_number('Sample Flow (lpm):'), 'valid', []);
    scan.header_conditions = struct('cylinder_temperature_deg_c', ...
        meta_number('Cylinder Temperature (C):'), 'sheath_temperature_deg_c', ...
        meta_number('Sheath Temperature (C):'), 'sheath_pressure_pa', ...
        meta_number('Sheath Pressure (Pa):'), 'ambient_temperature_deg_c', ...
        meta_number('Ambient Temperature (C):'), 'ambient_humidity_percent', ...
        meta_number('Ambient Humidity (%):'), 'mass_mobility_prefactor', ...
        meta_number('Mass-Mobility Prefactor:'), 'mass_mobility_exponent', ...
        meta_number('Mass-Mobility Exponent:'));
    scan.timestamp_text = [meta('Date:') ' ' meta('Time:')];
    date = regexp(meta('Date:'), '^\d{4}-\d{2}-\d{2}', 'match', 'once');
    try
        scan.timestamp = datetime([date ' ' meta('Time:')], ...
            'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    catch
        fail('Timestamp', 'Invalid recorded scan date or time.');
    end
    scan.data.scan.timestamp = [date ' ' meta('Time:')];
    scan.transit_time_s = meta_number('Transit time (s):');
    scan.window_nm = [meta_number('Start size (nm):'), ...
        meta_number('End size< (nm):')];
    scan.row_spacing_s = [];
    scan.readings_per_row = [];
    if strcmp(format, 'sass')
        scan.time_s = column('Scan Time (s)', true);
        scan.real_time = text_column('Real Time');
        scan.scan_time_s = meta_number('Scan Time (s):');
        scan.sampling_period_s = meta_number('CPC Sampling period (s):');
        scan.delay_s = meta_number('Delay time (s):');
        scan.scan_constant_s = scan_number('Scan Constant:');
        scan.speed_limits_rad_s = [scan_number('Start Speed (rad/s):'), ...
            scan_number('End Speed (rad/s):')];
        scan.classes_per_decade = scan_number('Size Class/dec:');
        if numel(scan.time_s) > 1
            spacing = diff(scan.time_s);
            if any(spacing <= 0), fail('TimeOrder', 'Row times must increase.'); end
            if max(spacing)-min(spacing) <= 64*eps(max(scan.time_s))
                scan.row_spacing_s = mean(spacing);
                scan.readings_per_row = ...
                    scan.row_spacing_s / scan.sampling_period_s;
            else
                scan.flags{end+1} = 'Irregular saved row spacing.';
            end
        end
        scan.data.scan.aac_sampling_period_s = scan.sampling_period_s;
        scan.data.scan.aac_delay_s = scan.delay_s;
    else
        scan.datum_index = column('Datum#', true);
        scan.real_time = text_column('Time');
        scan.time_s = [];
        scan.averaging_period_s = meta_number('Averaging period (s):');
        scan.extra_delay_s = meta_number('Extra delay time (s):');
        scan.classes_per_decade = meta_number('Size class/dec:');
        scan.scan_constant_s = [];
    end
    scan.lag_warning = false;
    for k = finish:last
        if contains(lower(lines{k}), 'warning') && ...
                contains(lower(lines{k}), 'speed')
            scan.lag_warning = true;
        end
    end
    if scan.lag_warning, scan.flags{end+1} = 'Reported scan speed lag.'; end
    if isempty(scan.counter_cm3_inv) || ~any(isfinite(scan.counter_cm3_inv))
        scan.preferred_route = 'B';
        scan.flags{end+1} = 'Counter series unavailable; use AAC route B.';
    else
        scan.preferred_route = 'A';
    end
    result.report = [result.report, scan.flags];
    result.scans{end+1, 1} = scan;
end
indices = cellfun(@(s) s.scan_index, result.scans);
if numel(unique(indices)) ~= numel(indices)
    fail('ScanIndex', 'SCAN indices must be unique.');
end

    function value = column(label, required)
        idx = find(strcmpi(labels, label));
        if isempty(idx)
            if required, fail('MissingColumn', label); end
            value = [];
            return
        end
        raw = cells(:, idx);
        value = str2double(strrep(raw, ',', '.'));
        missing = cellfun(@(x) isempty(x) || ...
            any(strcmpi(x, {'N/A', 'NaN'})), raw);
        if any(~isfinite(value) & ~missing)
            fail('InvalidNumber', ['Invalid numeric column: ' label]);
        end
    end

    function value = text_column(label)
        idx = find(strcmpi(labels, label));
        if isempty(idx), fail('MissingColumn', label); end
        value = cells(:, idx);
    end

    function value = meta(label)
        idx = find(strcmpi(metadata(:, 1), label));
        if numel(idx) ~= 1, fail('MissingMetadata', label); end
        value = metadata{idx, 2};
    end

    function value = meta_number(label)
        value = str2double(strrep(meta(label), ',', '.'));
        if ~isfinite(value), fail('InvalidMetadata', label); end
    end

    function value = scan_number(label)
        idx = find(strcmpi(scan_pairs(:, 1), label));
        if numel(idx) ~= 1, fail('MissingMetadata', label); end
        value = str2double(strrep(scan_pairs{idx, 2}, ',', '.'));
        if ~isfinite(value), fail('InvalidMetadata', label); end
    end
end

function row = split_row(line)
row = strsplit(line, char(9), 'CollapseDelimiters', false);
row = strtrim(row);
end

function result = pairs(row)
result = cell(max(0, numel(row)-1), 2);
count = 0;
for j = 1:numel(row)-1
    if endsWith(row{j}, ':')
        count = count + 1;
        result(count, :) = row(j:j+1);
    end
end
result = result(1:count, :);
end

function fail(reason, message)
error(['sootMosaic:READ_AAC:' reason], '%s', message);
end
