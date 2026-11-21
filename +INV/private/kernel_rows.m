function [voltage, h, volume, info] = kernel_rows(obs, cfg, draw, caller)
% "kernel_rows" maps recorded voltage history to detector counting intervals.
% ----------------------------------------------------------------------- %
% Method: Chen et al. (2024, Eqs. 2 and 5, Table 2).
% OBSERVATION voltage is delay-corrected; the forward history is not.
if ~isstruct(obs) || ~isscalar(obs) || ~isfield(obs, 'reduced') || ...
        ~islogical(obs.reduced) || ~isscalar(obs.reduced) || ...
        obs.reduced || ~isfield(obs, 'route') || ~strcmp(obs.route, 'A') || ...
        ~isfield(obs, 'quantity') || ...
        ~any(strcmp(obs.quantity, {'raw counts', 'raw concentration'}))
    error(['sootMosaic:' caller ':ReducedObservation'], ...
        'Only labeled route A raw counts or raw concentration enter a kernel.');
end
if ~isfield(obs, 'source_kind') || ~strcmp(obs.source_kind, 'smps_database')
    error(['sootMosaic:' caller ':RawSource'], 'Require unsplit database time bins.');
end
if ~isfield(obs, 'values') || ~isnumeric(obs.values) || ...
        ~isreal(obs.values) || ~isvector(obs.values) || isempty(obs.values) || ...
        any(~isfinite(obs.values(:)) | obs.values(:) < 0)
    error(['sootMosaic:' caller ':Observation'], 'Require finite nonnegative observations.');
end
n = numel(obs.values);
volume = ones(n, 1);
if strcmp(obs.quantity, 'raw counts')
    if ~isfield(obs, 'sample_volume_cm3') || ...
            ~isnumeric(obs.sample_volume_cm3) || ~isreal(obs.sample_volume_cm3) || ...
            ~isvector(obs.sample_volume_cm3) || ...
            numel(obs.sample_volume_cm3) ~= n || ...
            any(~isfinite(obs.sample_volume_cm3(:)) | obs.sample_volume_cm3(:) <= 0) || ...
            any(obs.values(:) ~= fix(obs.values(:)))
        error(['sootMosaic:' caller ':Exposure'], 'Require integer counts and positive bin volumes.');
    end
    volume = obs.sample_volume_cm3(:);
end
info = struct('tau_v_s', [], 'tau_s_over_abs_tau_v_1', [], ...
    'tp_s', [], 'source_edges_s', [], 'initial_steady_1', false, ...
    'ramp_log_slope_relative_spread_1', []);
if ~cfg.scan_response.enabled
    if ~isfield(obs, 'voltage_v') || numel(obs.voltage_v) ~= n
        error(['sootMosaic:' caller ':Voltage'], 'Require one voltage per observation.');
    end
    voltage = obs.voltage_v(:);
    h = speye(n);
else
    if ~strcmp(cfg.scan_response.delay_reading, 'mean_travel_time')
        error(['sootMosaic:' caller ':DelayReading'], 'Require the mean-travel-time reading.');
    end
    require_recorded(cfg, {'scan.delay_s', 'scan.delay_adjustment_s', ...
        'scan.bin_time_s'}, caller);
    if ~isfield(obs, 'time_s') || numel(obs.time_s) ~= n || ...
            ~isfield(obs, 'bin_time_s') || ~isscalar(obs.bin_time_s) || ...
            ~isfinite(obs.bin_time_s) || obs.bin_time_s <= 0
        error(['sootMosaic:' caller ':Timing'], 'Require bin starts and bin duration.');
    end
    if ~isscalar(cfg.si.scan.bin_time_s) || ...
            abs(obs.bin_time_s-cfg.si.scan.bin_time_s) > ...
            64*eps(max(1, obs.bin_time_s))
        error(['sootMosaic:' caller ':Timing'], ...
            'Observation duration must match the recorded counting interval.');
    end
    tp = cfg.si.scan.delay_s + cfg.si.scan.delay_adjustment_s - draw.tau_s_s;
    if ~isscalar(tp) || ~isfinite(tp) || tp < 0
        error(['sootMosaic:' caller ':Delay'], 'Mean delay must be at least the mixing time.');
    end
    if isfield(obs, 'history_edges_s') && isfield(obs, 'history_voltage_v')
        edges = obs.history_edges_s(:);
        voltage = obs.history_voltage_v(:);
        if numel(edges) ~= numel(voltage)+1
            error(['sootMosaic:' caller ':History'], 'History requires one voltage per cell.');
        end
        if any(~isfinite(voltage) | voltage <= 0) || ...
                any(~isfinite(edges)) || any(diff(edges) <= 0)
            error(['sootMosaic:' caller ':History'], 'Require increasing times and positive voltages.');
        end
        centers = (edges(1:end-1)+edges(2:end))/2;
        slopes = diff(log(voltage))./diff(centers);
        slopes = slopes(abs(slopes) > 64*eps);
        if ~isempty(slopes)
            if any(slopes > 0) && any(slopes < 0)
                error(['sootMosaic:' caller ':History'], ...
                    'Split opposing ramps into separate observations.');
            end
            slope = median(slopes);
            info.tau_v_s = 1/slope;
            info.tau_s_over_abs_tau_v_1 = draw.tau_s_s*abs(slope);
            info.ramp_log_slope_relative_spread_1 = ...
                max(abs(slopes/slope-1));
        end
    else
        require_recorded(cfg, {'scan.low_hold_s', 'scan.up_time_s', ...
            'scan.high_hold_s', 'scan.voltage_low_v', 'scan.voltage_high_v'}, caller);
        s = cfg.si.scan;
        vals = [s.low_hold_s, s.up_time_s, s.high_hold_s, ...
            s.voltage_low_v, s.voltage_high_v];
        if numel(vals) ~= 5 || any(~isfinite(vals)) || ...
                s.low_hold_s < 0 || s.high_hold_s < 0 || s.up_time_s <= 0 || ...
                s.voltage_low_v <= 0 || s.voltage_high_v <= s.voltage_low_v
            error(['sootMosaic:' caller ':History'], 'Require recorded holds, ramp and voltage limits.');
        end
        last = s.up_time_s+s.high_hold_s;
        first = -s.low_hold_s;
        count = ceil((last-first)/obs.bin_time_s);
        edges = linspace(first, last, count+1).';
        t = (edges(1:end-1)+edges(2:end))/2;
        t = min(s.up_time_s, max(0, t));
        voltage = s.voltage_low_v*exp(log(s.voltage_high_v/s.voltage_low_v)*t/s.up_time_s);
        ramp = struct('voltage_low_v', s.voltage_low_v, ...
            'voltage_high_v', s.voltage_high_v, 'duration_s', s.up_time_s, ...
            'direction_sign_1', 1, 'tau_s_s', draw.tau_s_s);
        [info.tau_v_s, r] = INV.SCAN_RESPONSE('ramp', ramp);
        info.tau_s_over_abs_tau_v_1 = r.tau_s_over_abs_tau_v_1;
        info.ramp_log_slope_relative_spread_1 = 0;
    end
    response = struct('source_edges_s', edges, ...
        'bin_start_s', obs.time_s(:), 'bin_end_s', obs.time_s(:)+obs.bin_time_s, ...
        'tp_s', tp, 'tau_s_s', draw.tau_s_s, 'initial_steady_1', true);
    [h, r] = INV.SCAN_RESPONSE('operator', response);
    if any(abs(r.row_sum_1-1) > 1e-8)
        error(['sootMosaic:' caller ':History'], 'Voltage history does not cover the response.');
    end
    info.tp_s = tp;
    info.source_edges_s = edges;
    info.initial_steady_1 = true;
end
if ~isnumeric(voltage) || ~isreal(voltage) || ...
        any(~isfinite(voltage) | voltage <= 0)
    error(['sootMosaic:' caller ':Voltage'], 'Classifier voltages must be positive.');
end
end
