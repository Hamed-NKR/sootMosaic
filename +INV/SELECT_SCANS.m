function result = SELECT_SCANS(imports, cases, cfg)
% "SELECT_SCANS" selects numeric scan indices and summarizes repeats.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     imports: Reader results in a cell array
%     cases: Campaign structures with file_index, indices, group and...
%         ...dilution_factor. Optional exclude, reason, expected_count,...
%         ...flags and flow_checks apply to the original case indices....
%         ...Each flow check names a field and setpoint_lpm
%     cfg: Resolved configuration containing exclusion rules
% ----------------------------------------------------------------------- %
%
% Outputs:
%     result: Accepted cases, original case indices, exclusion reasons...
%         ...and group membership. Summaries retain per-bin counts;...
%         ...dilution factors remain metadata
% ----------------------------------------------------------------------- %
% Method: Pooled variance identity, sum of within- and between-group...
%     ...squared deviations; Wiedensohler et al. (2012, Appendix A1).

if ~iscell(imports), imports = {imports}; end
if istable(cases), cases = table2struct(cases); end
if ~isstruct(cases), fail('Cases', 'Campaign cases must be structures or a table.'); end
result = struct('cases', {{}}, 'case_indices', [], 'group_labels', {{}}, ...
    'group_members', {{}}, 'excluded', struct('case_index', {}, ...
    'scan_index', {}, 'reason', {}), 'report', {{}});
for c = 1:numel(cases)
    item = cases(c);
    required = {'file_index', 'indices', 'group', 'dilution_factor'};
    for j = 1:numel(required)
        if ~isfield(item, required{j}), fail('CampaignField', required{j}); end
    end
    if iscell(item.indices) && isscalar(item.indices), item.indices = item.indices{1}; end
    indices = item.indices;
    if ~isnumeric(indices) || ~isvector(indices) || isempty(indices) || ...
            any(~isfinite(indices) | indices < 1 | indices ~= fix(indices)) || ...
            numel(unique(indices)) ~= numel(indices)
        fail('Indices', 'Scan indices must be distinct positive integers.');
    end
    if isfield(item, 'expected_count') && ~isempty(item.expected_count)
        if ~isscalar(item.expected_count) || item.expected_count ~= numel(indices)
            fail('ScanCount', 'Campaign scan count differs from numeric selection.');
        end
    end
    factors = item.dilution_factor;
    if isempty(factors), factors = NaN; end
    if ~isnumeric(factors) || ~(isscalar(factors) || numel(factors) == numel(indices)) || ...
            any(isinf(factors(:)) | factors(:) <= 0)
        fail('Dilution', 'Campaign factors must be positive or unresolved NaN.');
    end
    if isscalar(factors), factors = repmat(factors, size(indices)); end
    f = item.file_index;
    if ~isnumeric(f) || ~isscalar(f) || f ~= fix(f) || f < 1 || f > numel(imports)
        fail('FileIndex', 'Campaign file_index is outside the import list.');
    end
    if isfield(item, 'exclude') && item.exclude
        if ~isfield(item, 'reason') || isempty(item.reason)
            fail('ExclusionReason', 'An excluded case requires a reason.');
        end
        exclude(NaN, ['X4: ' char(item.reason)]);
        continue
    end
    input = imports{f};
    if ~isfield(item, 'flow_checks') || isempty(item.flow_checks)
        result.report{end+1} = sprintf( ...
            'Case %d has no flow setpoint checks; X2 is not evaluated.', c);
    end
    ids = cellfun(@(x) x.scan_index, input.scans);
    if numel(unique(ids)) ~= numel(ids)
        fail('DuplicateScan', 'Reader scan indices must be unique.');
    end
    for index = ids(:)'
        if ~ismember(index, indices), exclude(index, 'X5: outside campaign selection'); end
    end
    selected = cell(numel(indices), 1);
    selected_count = 0;
    for position = 1:numel(indices)
        index = indices(position);
        where = find(ids == index);
        if isempty(where)
            if isfield(input, 'excluded') && ...
                    any([input.excluded.scan_index] == index)
                ex = input.excluded([input.excluded.scan_index] == index);
                exclude(index, ex(1).reason);
                continue
            end
            fail('MissingScan', sprintf('Case %d has no scan %d.', c, index));
        end
        scan = input.scans{where};
        if ~isfield(scan, 'charger_concentration_cm3_inv')
            result.report{end+1} = sprintf( ...
                'Case %d scan %d lacks charger inlet concentration for X3.', c, index);
        end
        reason = screen(scan, item, cfg);
        if ~isempty(reason), exclude(index, reason); continue; end
        scan.campaign_dilution_factor = factors(position);
        scan.group = item.group;
        if isfield(item, 'flags') && ~isempty(item.flags)
            flags = item.flags;
            if ischar(flags) || isstring(flags), flags = cellstr(flags); end
            scan.flags = [scan.flags(:); flags(:)]';
        end
        selected_count = selected_count + 1;
        selected{selected_count} = scan;
    end
    selected = selected(1:selected_count);
    if isempty(selected), continue; end
    entry = struct('case_index', c, 'group', item.group, 'scans', {selected}, ...
        'requested_count', numel(indices), 'accepted_count', numel(selected), ...
        'dilution_factor', item.dilution_factor, 'summary', []);
    if all(cellfun(@(x) strcmp(x.source_kind, 'smps_export'), selected))
        entry.summary = summarize(selected);
        entry.summary.group = item.group;
    else
        result.report{end+1} = ...
            'Scans retained individually for processing on a common grid.';
    end
    result.cases{end+1, 1} = entry;
    result.case_indices(end+1) = c;
    group_index = find(cellfun(@(g) isequal(g, item.group), result.group_labels));
    if isempty(group_index)
        result.group_labels{end+1} = item.group;
        result.group_members{end+1} = numel(result.cases);
    else
        result.group_members{group_index}(end+1) = numel(result.cases);
    end
end
if isempty(cfg.exclusion.counter_limit_cm3_inv)
    result.report{end+1} = ['Counter single-count limit unavailable; ' ...
        'X3 counter check not run.'];
end

    function exclude(index, reason)
        result.excluded(end+1) = struct('case_index', c, ...
            'scan_index', index, 'reason', reason);
    end
end

function reason = screen(scan, item, cfg)
reason = '';
data = scan.data.scan;
if cfg.exclusion.invalid_record && isfield(data, 'valid') && ...
        isequal(data.valid, false)
    reason = 'X1: isValid false';
    return
end
if isfield(scan, 'timestamp') && ~isempty(scan.timestamp)
    stamp = scan.timestamp;
    if ~isdatetime(stamp), stamp = datetime(stamp, 'ConvertFrom', 'datenum'); end
    stamp.Format = 'yyyy-MM-dd';
    date = char(stamp);
    if any(strcmp(date, cfg.exclusion.dates))
        reason = 'X4: excluded campaign date';
        return
    end
end
if isfield(item, 'flow_checks')
    checks = item.flow_checks;
    if iscell(checks) && isscalar(checks), checks = checks{1}; end
    for j = 1:numel(checks)
        key = checks(j).field;
        if isfield(data, key), flow = data.(key);
        elseif isfield(scan, 'conditions') && isfield(scan.conditions, key)
            flow = scan.conditions.(key);
        else
            fail('MissingFlow', ['Flow check lacks recorded ' key]);
        end
        setpoint = checks(j).setpoint_lpm;
        if ~isscalar(setpoint) || ~isfinite(setpoint) || setpoint <= 0 || ...
                any(~isfinite(flow(:)))
            fail('FlowCheck', 'Flow checks require finite data and a positive setpoint.');
        end
        if any(abs(flow(:) / setpoint - 1) > cfg.exclusion.flow_rel_tol)
            reason = ['X2: flow outside setpoint tolerance, ' key];
            return
        end
    end
end
counter = [];
if isfield(scan, 'counter_cm3_inv')
    counter = scan.counter_cm3_inv;
elseif strcmp(scan.source_kind, 'smps_database')
    if isfield(data, 'counting_flow_lpm') && ~isempty(data.counting_flow_lpm)
        flow = data.counting_flow_lpm;
    else
        require_recorded(cfg, {'scan.counting_flow_lpm'}, 'SELECT_SCANS');
        flow = cfg.scan.counting_flow_lpm;
    end
    dt = data.bin_time_s;
    if ~isscalar(flow) || ~isfinite(flow) || flow <= 0 || ...
            ~isscalar(dt) || ~isfinite(dt) || dt <= 0
        fail('CountingExposure', 'Recorded counting exposure must be positive.');
    end
    counter = scan.channels.values ./ (flow * 1000/60 * dt);
end
if ~isempty(counter) && ~isempty(cfg.exclusion.counter_limit_cm3_inv) && ...
        any(counter > cfg.exclusion.counter_limit_cm3_inv)
    reason = 'X3: counter single-count range exceeded';
elseif isfield(scan, 'charger_concentration_cm3_inv') && ...
        any(scan.charger_concentration_cm3_inv > cfg.exclusion.charger_limit_cm3_inv)
    reason = 'X3: charger concentration limit exceeded';
end
end

function result = summarize(scans)
first = scans{1};
d = first.channels.diameter_nm(:);
for k = 2:numel(scans)
    if ~strcmp(first.channels.quantity, scans{k}.channels.quantity) || ...
            ~strcmp(first.channels.unit, scans{k}.channels.unit)
        fail('Quantity', 'Repeat quantities and units must agree.');
    end
    d = intersect(d, scans{k}.channels.diameter_nm(:));
end
if isempty(d), fail('CommonSupport', 'Repeats have no common diameter bins.'); end
values = NaN(numel(scans), numel(d));
for k = 1:numel(scans)
    [~, col] = ismember(d, scans{k}.channels.diameter_nm);
    values(k, :) = scans{k}.channels.values(col);
end
n = sum(isfinite(values), 1);
zero = values;
zero(~isfinite(zero)) = 0;
mu = sum(zero, 1) ./ max(n, 1);
delta = values - mu;
delta(~isfinite(delta)) = 0;
variance = sum(delta.^2, 1) ./ max(n-1, 1);
mu(n == 0) = NaN;
variance(n == 0) = NaN;
result = struct('diameter_nm', d, 'mean', mu(:), ...
    'variance', variance(:), 'n', n(:), 'std', sqrt(variance(:)), ...
    'quantity', first.channels.quantity, 'unit', first.channels.unit, ...
    'dilution_applied', false);
end

function fail(reason, message)
error(['sootMosaic:SELECT_SCANS:' reason], '%s', message);
end
