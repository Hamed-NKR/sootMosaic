function [out, info] = SCAN_RESPONSE(action, s)
% "SCAN_RESPONSE" averages the delayed mixing response over counting bins.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     action: operator, travel, step, fit_step, desmear, backsub or ramp
%     s: Scalar structure. Times are seconds. operator uses source_edges_s,...
%         ...bin_start_s, bin_end_s, tp_s, tau_s_s, initial_steady_1....
%         ...Source values are constant within each source cell; an initial...
%         ...steady history extends the first value to minus infinity.
%     s: travel uses time_s, tp_s and tau_s_s. step uses bin_start_s,...
%         ...bin_end_s, step_time_s, tp_s and tau_s_s for a falling unit step.
%     s: fit_step adds counts, volume_cm3, plateau_cm3_inv and initial_s...
%         ...([tp tau]) to the step times. desmear uses time_s, values,...
%         ...tau_s_s, window_count and order_count for local polynomial fits.
%     s: backsub uses operator_1 and concentration values with a square...
%         ...causal mixing operator on delay-aligned source cells. A pure...
%         ...transport delay shifts the source times before this inversion
%     s: ramp uses voltage_low_v, voltage_high_v, duration_s,...
%         ...direction_sign_1 (+1 up, -1 down) and tau_s_s
% Outputs:
%     out: Operator, travel density, step response, fitted [tp tau],...
%         ...de-smeared series, backsubstituted series or signed ramp time
%     info: Method diagnostics. Travel includes the zero-width atom;...
%         ...de-smearing returns the delayed interval average, not R_nsp
% ----------------------------------------------------------------------- %
% Method: Chen et al. (2024, Eqs. 2, 5, 22-26, 33, 36-39, Table 2);
%     ...Collins et al. (2002, Eqs. 9-14).
% Reimplementation from the published equations.

if ~isstruct(s) || ~isscalar(s)
    fail('Input', 'Pass a scalar structure.');
end
info = struct();
switch action
    case 'operator'
        [a, b] = bins(s);
        tau = scalar(s, 'tau_s_s', true);
        tp = scalar(s, 'tp_s', true);
        e = vector(s, 'source_edges_s');
        if numel(e) < 2 || any(diff(e) <= 0) || ...
                ~isfield(s, 'initial_steady_1') || ...
                ~islogical(s.initial_steady_1) || ~isscalar(s.initial_steady_1)
            fail('History', 'Require increasing history edges and an initial-state switch.');
        end
        if any(b-tp > e(end)+64*eps(max(1, abs(e(end)))))
            fail('History', 'The source history ends before the counting response.');
        end
        out = zeros(numel(a), numel(e)-1);
        for j = 1:numel(e)-1
            out(:, j) = (primitive(time_lag(b, tp, e(j)), tau) - ...
                primitive(time_lag(a, tp, e(j)), tau) - ...
                primitive(time_lag(b, tp, e(j+1)), tau) + ...
                primitive(time_lag(a, tp, e(j+1)), tau))./(b-a);
        end
        if s.initial_steady_1
            out(:, 1) = out(:, 1) + 1 - ...
                (primitive(time_lag(b, tp, e(1)), tau)- ...
                primitive(time_lag(a, tp, e(1)), tau))./(b-a);
        end
        if any(out(:) < -1e-8)
            fail('Cancellation', 'Time coordinates exceed the averaging precision.');
        end
        out = sparse(max(out, 0));
        info.row_sum_1 = full(sum(out, 2));
        info.initial_steady_1 = s.initial_steady_1;
    case 'travel'
        t = vector(s, 'time_s');
        tau = scalar(s, 'tau_s_s', true);
        tp = scalar(s, 'tp_s', true);
        out = zeros(size(t));
        cdf = zeros(size(t));
        use = t >= tp;
        if tau == 0
            cdf(use) = 1;
            info.atom_mass_1 = 1;
        else
            out(use) = exp(-(t(use)-tp)/tau)/tau;
            cdf(use) = -expm1(-(t(use)-tp)/tau);
            info.atom_mass_1 = 0;
        end
        info.atom_time_s = tp;
        info.cdf_1 = cdf;
        info.mean_s = tp+tau;
    case 'step'
        [a, b] = bins(s);
        tp = scalar(s, 'tp_s', true);
        tau = scalar(s, 'tau_s_s', true);
        t0 = scalar(s, 'step_time_s', false);
        out = falling(a-t0-tp, b-t0-tp, tau);
    case 'fit_step'
        [a, b] = bins(s);
        t0 = scalar(s, 'step_time_s', false);
        y = vector(s, 'counts');
        v = vector(s, 'volume_cm3');
        r0 = scalar(s, 'plateau_cm3_inv', false);
        initial = vector(s, 'initial_s');
        if numel(y) ~= numel(a) || numel(v) ~= numel(a) || ...
                any(y < 0 | y ~= fix(y)) || any(v <= 0) || r0 <= 0 || ...
                numel(initial) ~= 2 || any(initial <= 0) || nnz(y) < 3
            fail('StepData', 'Require counts, positive exposures, plateau and initial times.');
        end
        objective = @(u) poisson_loss(y, v*r0.* ...
            falling(a-t0-exp(u(1)), b-t0-exp(u(1)), exp(u(2))));
        options = optimset('Display', 'off', 'TolX', 1e-9, 'TolFun', 1e-9, ...
            'MaxIter', 1000, 'MaxFunEvals', 3000);
        [u, value, flag] = fminsearch(objective, log(initial(:).'), options);
        if flag <= 0 || any(~isfinite(u))
            fail('StepFit', 'The step likelihood did not converge.');
        end
        out = exp(u);
        info.negative_log_likelihood_1 = value;
        info.expected_counts = v*r0.*falling(a-t0-out(1), b-t0-out(1), out(2));
    case 'desmear'
        t = vector(s, 'time_s');
        y = matrix(s, 'values');
        tau = scalar(s, 'tau_s_s', true);
        w = scalar(s, 'window_count', false);
        order = scalar(s, 'order_count', true);
        if any(diff(t) <= 0) || size(y, 1) ~= numel(t) || ...
                w ~= fix(w) || mod(w, 2) ~= 1 || w < 3 || w > numel(t) || ...
                order < 1 || order ~= fix(order) || order >= w
            fail('Derivative', 'Require increasing times and an odd polynomial window.');
        end
        derivative = zeros(size(y));
        smoothed = zeros(size(y));
        for j = 1:numel(t)
            first = max(1, min(j-(w-1)/2, numel(t)-w+1));
            ids = first:first+w-1;
            dt = t(ids)-t(j);
            scale = max(abs(dt));
            x = (dt/scale).^(0:order);
            coefficients = x\y(ids, :);
            smoothed(j, :) = coefficients(1, :);
            derivative(j, :) = coefficients(2, :)/scale;
        end
        out = smoothed + tau*derivative;
        info.derivative_per_s = derivative;
        info.smoothed = smoothed;
        info.delayed_average = true;
    case 'backsub'
        h = matrix(s, 'operator_1');
        y = matrix(s, 'values');
        n = size(h, 1);
        if size(h, 2) ~= n || size(y, 1) ~= n || ...
                nnz(triu(h, 1)) ~= 0 || any(diag(h) <= 0)
            fail('Causality', 'Require a square causal operator with positive diagonal.');
        end
        out = zeros(size(y));
        for j = 1:n
            out(j, :) = (y(j, :)-h(j, 1:j-1)*out(1:j-1, :))/h(j, j);
        end
    case 'ramp'
        low = scalar(s, 'voltage_low_v', false);
        high = scalar(s, 'voltage_high_v', false);
        duration = scalar(s, 'duration_s', false);
        direction = scalar(s, 'direction_sign_1', false);
        tau = scalar(s, 'tau_s_s', true);
        if low <= 0 || high <= low || duration <= 0 || ~ismember(direction, [-1, 1])
            fail('Ramp', 'Require positive voltage limits, duration and scan direction.');
        end
        out = direction*duration/log(high/low);
        info.tau_s_over_abs_tau_v_1 = tau/abs(out);
    otherwise
        fail('Action', 'Unknown scan-response action.');
end
end

function lag = time_lag(t, tp, edge)
% Resolving coincident boundaries at the precision of the time coordinates
lag = t-tp-edge;
roundoff = eps(abs(t)) + eps(abs(tp)) + eps(abs(edge));
lag(abs(lag) <= roundoff) = 0;
end

function p = primitive(x, tau)
% Integrating the causal exponential step response
p = max(x, 0);
if tau > 0, p = p + tau*expm1(-p/tau); end
end

function y = falling(a, b, tau)
% Averaging the falling step with a steady pre-step concentration
y = zeros(size(a));
before = b <= 0;
after = a >= 0;
middle = ~before & ~after;
y(before) = 1;
if tau > 0
    y(after) = tau*exp(-a(after)/tau).* ...
        (-expm1(-(b(after)-a(after))/tau))./(b(after)-a(after));
    y(middle) = (-a(middle)-tau*expm1(-b(middle)/tau))./ ...
        (b(middle)-a(middle));
else
    y(middle) = -a(middle)./(b(middle)-a(middle));
end
end

function value = poisson_loss(y, mean_value)
if any(~isfinite(mean_value)) || any(mean_value < 0)
    value = realmax;
else
    value = sum(mean_value - y.*log(max(mean_value, realmin)));
end
end

function [a, b] = bins(s)
a = vector(s, 'bin_start_s');
b = vector(s, 'bin_end_s');
if numel(a) ~= numel(b) || any(b <= a)
    fail('Bins', 'Counting intervals must have positive duration.');
end
end

function x = scalar(s, key, nonnegative)
x = vector(s, key);
if ~isscalar(x) || (nonnegative && x < 0)
    fail('Scalar', ['Invalid scalar ' key '.']);
end
end

function x = vector(s, key)
x = matrix(s, key);
if ~isvector(x), fail('Shape', ['Require a vector for ' key '.']); end
x = double(x(:));
end

function x = matrix(s, key)
if ~isfield(s, key) || ~isnumeric(s.(key)) || ~isreal(s.(key)) || ...
        isempty(s.(key)) || any(~isfinite(s.(key)(:)))
    fail('Input', ['Require finite numeric ' key '.']);
end
x = s.(key);
end

function fail(reason, message)
error(['sootMosaic:SCAN_RESPONSE:' reason], '%s', message);
end
