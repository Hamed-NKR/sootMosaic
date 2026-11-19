function obs = OBSERVATION(scan, cfg, correction)
% "OBSERVATION" builds route-specific data and applies dilution once.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     scan: One reader scan, optionally carrying campaign dilution metadata
%     cfg: Resolved per-scan configuration from LOAD_MAIN_INV_CONFIG
%     correction: AAC route B factors beta_ideal_ratio, beta_nonideal_ratio,
%         ...software_efficiency_ratio, counting_efficiency_ratio and...
%         ...tube_penetration_ratio, derived by the classifier model
% ----------------------------------------------------------------------- %
%
% Outputs:
%     obs: Labeled values, exposure and route restrictions. AAC route A...
%         ...variants retain both row operations when unresolved. Raw...
%         ...database counts use provisional nominal exposure only
% ----------------------------------------------------------------------- %
% Method: Kiasadegh et al. (2026, Sec. 3.3, p. 703); Wiedensohler et al....
%     ...(2012, Appendix A5.1); Sipkens et al. (2020, part I, Eq. 23);...
%     ...Johnson et al. (2018, Eqs. 9-11); AAC manual (2023, Sec. 2.3.4).

if nargin < 3, correction = struct(); end
if isfield(scan, 'dilution_applied') && scan.dilution_applied
    fail('AlreadyDiluted', 'An observation cannot be diluted twice.');
end
mode = cfg.mode;
if ~any(strcmp(mode, {'tandem', 'smps_1d', 'aac_1d'}))
    fail('Mode', 'Expected tandem, smps_1d or aac_1d.');
end
is_aac = strcmp(scan.source_kind, 'aac_export');
if is_aac ~= strcmp(mode, 'aac_1d')
    fail('InstrumentMode', 'Scan instrument and observation mode differ.');
end
if strcmp(mode, 'tandem'), route = cfg.observation.route;
else, route = cfg.(mode).route;
end
if strcmpi(route, 'auto')
    if is_aac
        route = scan.preferred_route;
    elseif strcmp(scan.source_kind, 'smps_database')
        route = 'A';
    else
        route = 'B';
    end
end
route = upper(route);
if ~any(strcmp(route, {'A', 'B'})), fail('Route', 'Expected A, B or auto.'); end
obs = struct('mode', mode, 'route', route, 'scan_index', scan.scan_index, ...
    'source_kind', scan.source_kind, 'reduced', strcmp(route, 'B'), ...
    'dilution_applied', true, 'flags', {scan.flags}, ...
    'allowed_consumers', {{}}, 'provisional', false, 'report', {{}});
[factor, known] = dilution(scan, cfg);
obs.dilution_factor_ratio = factor;
obs.dilution_known = known;
if ~known
    obs.flags{end+1} = 'Campaign dilution unresolved; values remain unconverted.';
end
if is_aac
    obs.diameter_nm = scan.channels.diameter_nm;
    obs.conditions = scan.conditions;
    if strcmp(route, 'A')
        o = scan.counter_cm3_inv;
        if isempty(o) || any(~isfinite(o) | o < 0)
            fail('CounterSeries', 'Route A requires a complete counter series.');
        end
        r = cfg.reading(strcmp({cfg.reading.path}, 'aac_1d.counting_flow_lpm'));
        if numel(r) ~= 1 || ~any(strcmp(r.source, {'data', 'campaign', 'registry'}))
            fail('MissingRecordedInput', 'AAC counting flow requires a source.');
        end
        flow = positive(cfg.aac_1d.counting_flow_lpm, 'counting flow') * 1000/60;
        obs.counting_flow_source = r.source;
        if strcmp(r.source, 'registry')
            obs.report{end+1} = ...
                'aac_1d.counting_flow_lpm came from the instrument registry.';
        end
        if strcmp(scan.format, 'aacs')
            operations = {'step_average'};
            exposures = positive(scan.averaging_period_s, 'averaging period');
        else
            tc = positive(scan.sampling_period_s, 'sampling period');
            operation = cfg.aac_1d.row_operation;
            if strcmp(operation, 'both')
                operations = {'averaged', 'subsampled'};
            elseif any(strcmp(operation, {'averaged', 'subsampled'}))
                operations = {operation};
            else
                fail('RowOperation', 'Expected both, averaged or subsampled.');
            end
            exposures = zeros(1, numel(operations));
            for k = 1:numel(operations)
                if strcmp(operations{k}, 'averaged')
                    nr = positive(scan.readings_per_row, 'readings per row');
                    if abs(nr-round(nr)) > 64*eps(max(1, nr))
                        fail('RowSpacing', 'Averaging requires an integer row ratio.');
                    end
                    exposures(k) = nr * tc;
                else
                    exposures(k) = tc;
                end
            end
        end
        obs.values = factor * o;
        obs.quantity = 'counter concentration';
        obs.unit = 'cm^-3';
        obs.variance_model = cfg.variance.aac_model;
        obs.counts_are_approximate = true;
        obs.variants = cell(numel(operations), 1);
        for k = 1:numel(operations)
            exposure = exposures(k);
            obs.variants{k} = struct('row_operation', operations{k}, ...
                'exposure_s', exposure, 'forward_average_s', exposure, ...
                'approximate_counts', o * flow * exposure, ...
                'sample_volume_cm3', flow * exposure / factor, ...
                'poisson_variance_cm6_inv', factor^2 * o / (flow * exposure));
        end
        obs.time_s = scan.time_s;
        obs.allowed_consumers = {'KERNEL_AAC'};
        obs.provisional = numel(operations) > 1;
    else
        names = {'beta_ideal_ratio', 'beta_nonideal_ratio', ...
            'software_efficiency_ratio', 'counting_efficiency_ratio', ...
            'tube_penetration_ratio'};
        for k = 1:numel(names)
            if ~isfield(correction, names{k})
                fail('MissingCorrection', ['AAC route B requires ' names{k}]);
            end
            value = correction.(names{k});
            if ~isnumeric(value) || any(~isfinite(value(:)) | value(:) <= 0) || ...
                    ~(isscalar(value) || numel(value) == numel(obs.diameter_nm))
                fail('CorrectionShape', names{k});
            end
            correction.(names{k}) = value(:);
        end
        gain = correction.beta_ideal_ratio ./ correction.beta_nonideal_ratio .* ...
            correction.software_efficiency_ratio ./ ...
            correction.counting_efficiency_ratio ./ correction.tube_penetration_ratio;
        obs.values = scan.channels.values .* gain * factor;
        obs.quantity = 'dN/dlog10Da';
        obs.unit = 'cm^-3';
        obs.correction = correction;
        obs.comparison = scan.corrected_spectrum;
        obs.allowed_consumers = {'PEAK_FIT', 'MOMENTS', 'DIST_DA_TO_DM'};
    end
elseif strcmp(route, 'A')
    if ~strcmp(scan.source_kind, 'smps_database') || ...
            ~strcmp(scan.channels.quantity, 'raw counts')
        fail('RawSource', ...
            'Route A requires time-bin database counts, not mapped export channels.');
    end
    counts = scan.channels.values;
    if any(~isfinite(counts) | counts < 0 | counts ~= fix(counts))
        fail('Counts', 'Time-bin counts must be nonnegative integers.');
    end
    dt = positive(scan.data.scan.bin_time_s, 'bin time');
    require_recorded(cfg, {'scan.counting_flow_lpm'}, 'OBSERVATION');
    flow = positive(cfg.scan.counting_flow_lpm, 'recorded counting flow');
    r = cfg.reading(strcmp({cfg.reading.path}, 'scan.counting_flow_lpm'));
    obs.counting_flow_source = r.source;
    volume = repmat(flow * 1000/60 * dt / factor, size(counts));
    obs.values = counts;
    obs.quantity = 'raw counts';
    obs.unit = 'counts';
    obs.sample_volume_cm3 = volume;
    obs.raw_concentration_cm3_inv = counts ./ volume;
    obs.dead_time = scan.dead_time;
    obs.provisional = true;
    obs.time_s = scan.channels.time_s;
    obs.bin_time_s = dt;
    obs.charge_components = true;
    obs.allowed_consumers = {'KERNEL_1D', 'KERNEL_2D', 'PEAK_FIT'};
    obs.exposure_reason = ...
        'Nominal bin exposure; no dead-time or coincidence correction inferred.';
    obs.classifier_time_s = obs.time_s + dt/2 - ...
        scan.data.scan.delay_s - scan.data.scan.delay_adjustment_s;
    up = positive(scan.data.scan.up_time_s, 'up-scan time');
    low = positive(scan.data.scan.voltage_low_v, 'low voltage');
    high = positive(scan.data.scan.voltage_high_v, 'high voltage');
    if high <= low, fail('VoltageRange', 'High voltage must exceed low voltage.'); end
    t = obs.classifier_time_s;
    holds = [scan.data.scan.low_hold_s, scan.data.scan.high_hold_s];
    if any(~isfinite(holds) | holds < 0) || ...
            any(t < -holds(1) | t > up + holds(2))
        fail('TimingSupport', ...
            'Delayed bin times exceed the recorded voltage history.');
    end
    obs.outside_ramp = t < 0 | t > up;
    ramp_time = min(up, max(0, t));
    obs.voltage_v = low * exp(log(high/low) * ramp_time / up);
    if any(obs.outside_ramp)
        obs.flags{end+1} = 'Some delayed classifier times lie within recorded voltage holds.';
    end
else
    if ~strcmp(scan.source_kind, 'smps_export')
        fail('ReducedSource', 'Route B requires a labeled reduced export.');
    end
    require_recorded(cfg, {'scan.counting_flow_lpm'}, 'OBSERVATION');
    data = scan.data.scan;
    if ~isfield(data, 'weight') || ~strcmpi(data.weight, 'Number')
        fail('Weight', 'Route B requires Number weight.');
    end
    if ~islogical(data.mcc_on) || ~isscalar(data.mcc_on) || ...
            ~islogical(data.dlc_on) || ~isscalar(data.dlc_on)
        fail('CorrectionFlags', 'Route B requires MCC and DLC flags.');
    end
    values = scan.channels.values;
    switch scan.channels.quantity
        case 'dW/dlogDp'
        case 'dW'
            if ~isfield(data, 'channels_per_decade')
                fail('Resolution', 'dW requires Channels/Decade.');
            end
            values = values * positive(data.channels_per_decade, 'Channels/Decade');
        otherwise
            fail('ReducedUnits', 'Route B accepts only dW or dW/dlogDp.');
    end
    if ~isfield(data, 'software_dilution_factor')
        fail('SoftwareDilution', 'Missing export Dilution Factor.');
    end
    software = positive(data.software_dilution_factor, 'software dilution');
    if software ~= 1 && ~campaign_factor_present(scan, cfg)
        fail('MissingCampaignDilution', sprintf( ...
            'Scan %d has software dilution without a campaign factor.', scan.scan_index));
    end
    obs.values = values * factor / software;
    obs.diameter_nm = scan.channels.diameter_nm;
    obs.quantity = 'dN/dlog10Dm';
    obs.unit = 'cm^-3';
    obs.mcc_on = data.mcc_on;
    obs.dlc_on = data.dlc_on;
    obs.charge_components = ~data.mcc_on;
    obs.charge_weight = 'f_n(true diameter) / f_1(apparent diameter)';
    obs.software_dilution_factor_ratio = software;
    obs.allowed_consumers = {'PEAK_FIT', 'MOMENTS'};
    obs.comparison = scan.software_statistics;
end
if any(isinf(obs.values(:)))
    fail('Overflow', 'Observation conversion produced infinite values.');
end
end

function [value, known] = dilution(scan, cfg)
if isfield(scan, 'campaign_dilution_factor')
    value = scan.campaign_dilution_factor;
else
    value = cfg.scan.dilution_factor;
end
known = ~isempty(value) && isscalar(value) && isfinite(value);
if ~known
    value = 1;
else
    value = positive(value, 'campaign dilution');
end
end

function present = campaign_factor_present(scan, cfg)
present = isfield(scan, 'campaign_dilution_factor') && ...
    isscalar(scan.campaign_dilution_factor) && ...
    isfinite(scan.campaign_dilution_factor);
if ~present && isfield(cfg, 'reading')
    for k = 1:numel(cfg.reading)
        r = cfg.reading(k);
        if strcmp(r.path, 'scan.dilution_factor') && strcmp(r.source, 'campaign')
            present = true;
        end
    end
end
end

function value = positive(value, label)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
    fail('PositiveValue', ['Expected a positive ' label '.']);
end
end

function fail(reason, message)
error(['sootMosaic:OBSERVATION:' reason], '%s', message);
end
