function [f_frac, info] = CHARGE_FRAC(d_m, charge_e, temp_k, pressure_pa, opts)
% "CHARGE_FRAC" calculates bipolar charge fractions at a recorded gas state.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     d_m: Positive diameter vector, one output row per diameter (m)
%     charge_e: Distinct integer charge states, one output column per...
%         ...state. Empty selects the smallest charge range...
%         ...meeting the tail tolerance at the largest diameter (e)
%     temp_k: Recorded DMA temperature, as passed to GAS (K)
%     pressure_pa: Recorded DMA pressure, as passed to GAS (Pa)
%     opts: Optional scalar structure with Model, RangePolicy,...
%         ...TailPolarity, TailTolerance_frac, MaxCharge_e and Config....
%         ...TailPolarity is both (default), positive or negative. Model is...
%         ...soft_xray_3082_tableB3 (default), kr85_wiedensohler or...
%         ...gopalakrishnan_2013. Config is the optional GAS configuration.
%         ...RangePolicy is warn (default) or stop. TailTolerance_frac...
%         ...defaults to 1e-3 (-); MaxCharge_e is a search cap, 4096 (e).
% ----------------------------------------------------------------------- %
%
% Outputs:
%     f_frac: Diameter by charge fractions, without renormalization (-)
%     info: Model, charge_e, temp_k, sum_requested_frac and range masks....
%         ...Adaptive calls include max_charge_e and tail_bound_frac...
%         ...at tail_diameter_m. Explicit calls leave these empty.
% ----------------------------------------------------------------------- %
% Method: Wiedensohler (1988, Eqs. 1-2), corrected by Wiedensohler et al....
%     ...(2012, Appendix A5, Table A7, pp. 681-682); 3082 manual (2016,...
%     ...Eqs. B-2 and B-3, Tables B-2 and B-3, pp. B-10 and B-11), after...
%     ...Knobel et al. (2013); Gopalakrishnan et al. (2013, Eq. 10,...
%     ...Table 2, spherical row, pp. 140 and 143).
% Reimplemented from the published formulas and tables.
% The manual regressions cover 1-1000 nm for |n| <= 1 and 20-1000 nm...
%     ...for |n| = 2. Below 20 nm, warn returns zero for |n| = 2; below...
%     ...1 nm it returns NaN. The spherical cubic covers 5-2000 nm in...
%     ...the source; this interface uses 5-1000 nm and returns NaN below...
%     ...5 nm. Above 1000 nm, warn selects Eq. B-3 for every charge.
% Every out-of-range request warns or stops. Eq. B-3 uses the selected...
%     ...model ratio and GAS constants at temp_k. A missing ratio stops...
%     ...requests for |n| > 2, adaptive tails or the upper extension.
% The regression temperature is fixed by its published coefficients.

if nargin < 5, opts = struct(); end
if ~isstruct(opts) || ~isscalar(opts) || any(~ismember(fieldnames(opts), ...
        {'Model'; 'RangePolicy'; 'TailPolarity'; 'TailTolerance_frac'; ...
        'MaxCharge_e'; 'Config'}))
    fail('InvalidOptions', 'Pass only the documented options.');
end
if ~isnumeric(d_m) || ~isreal(d_m) || ~isvector(d_m) || isempty(d_m) || ...
        any(~isfinite(d_m(:))) || any(d_m(:) <= 0)
    fail('InvalidDiameter', 'Diameters (m) must be a positive finite vector.');
end
if ~isnumeric(charge_e) || ~isreal(charge_e) || ...
        ~(isempty(charge_e) || isvector(charge_e)) || ...
        any(~isfinite(charge_e(:))) || ...
        any(charge_e(:) ~= fix(charge_e(:))) || ...
        any(abs(charge_e(:)) > flintmax) || ...
        numel(unique(charge_e)) ~= numel(charge_e)
    fail('InvalidCharge', ...
        'Charge states (e) must be distinct finite integers.');
end
model = option(opts, 'Model', 'soft_xray_3082_tableB3');
policy = option(opts, 'RangePolicy', 'warn');
if isstring(model) && isscalar(model), model = char(model); end
if isstring(policy) && isscalar(policy), policy = char(policy); end
if ~ischar(policy) || ~isrow(policy) || ...
        ~any(strcmp(policy, {'warn', 'stop'}))
    fail('InvalidOptions', 'RangePolicy must be warn or stop.');
end
ids = {'soft_xray_3082_tableB3', 'kr85_wiedensohler', ...
    'gopalakrishnan_2013'};
if ~ischar(model) || ~isrow(model) || ~any(strcmp(model, ids))
    fail('UnknownModel', 'Select a named charge model.');
end
tol = option(opts, 'TailTolerance_frac', 1e-3);
cap = option(opts, 'MaxCharge_e', 4096);
polarity = option(opts, 'TailPolarity', 'both');
if isstring(polarity) && isscalar(polarity), polarity = char(polarity); end
if ~ischar(polarity) || ~isrow(polarity) || ...
        ~any(strcmp(polarity, {'both', 'positive', 'negative'}))
    fail('InvalidOptions', 'TailPolarity must be both, positive or negative.');
end
if ~positive_scalar(tol) || tol >= 1 || ~positive_scalar(cap) || ...
        cap ~= fix(cap) || cap < 2 || cap > 4096
    fail('InvalidOptions', ...
        'Tail tolerance must be in (0,1); charge cap an integer in [2,4096].');
end
[~, ~, ~, params] = INV.GAS(temp_k, pressure_pa, [], ...
    option(opts, 'Config', []));
root = fileparts(fileparts(mfilename('fullpath')));
directory = fullfile(root, 'config', 'instruments');
registry = UTILS.CONFIG_READ(fullfile(directory, 'charging.json'), ...
    fullfile(directory, 'instruments.keys.json'), struct('Strict', true));
index = find(cellfun(@(r) strcmp(r.id, model), registry.models));
if numel(index) ~= 1
    fail('InvalidTable', 'The selected model must have one registry entry.');
end
entry = registry.models{index};
cubic = strcmp(model, 'gopalakrishnan_2013');
rows = 6 - 2 * cubic;
if ~strcmp(entry.coefficients_state, 'ready') || ...
        ~isequal(size(entry.coefficients), [rows 5]) || ...
        any(~isfinite(entry.coefficients(:)))
    fail('InvalidTable', 'The selected coefficient table is not ready.');
end
d = double(d_m(:));
charges = double(charge_e(:).');
if any(~isfinite(d / 1e-9))
    fail('DiameterRange', 'Diameters exceed the finite regression range.');
end
c = params.constants;
s = 2*pi*c.eps0_f_m*c.kb_j_k*double(temp_k) / c.e_c^2 .* d;
if any(~isfinite(s)) || any(s <= 0)
    fail('DiameterRange', 'The gas state exceeds the finite charge range.');
end
qmax = [];
tail = [];
tail_d = [];
if isempty(charges)
    require_ratio(entry);
    [tail_d, largest] = max(d);
    [qmax, tail] = charge_limit(tail_d, s(largest), entry, cubic, ...
        policy, tol, cap, polarity);
    charges = -qmax:qmax;
    if strcmp(polarity, 'positive'), charges = 1:qmax; end
    if strcmp(polarity, 'negative'), charges = -qmax:-1; end
end
[f_frac, low, high] = fractions(d, charges, s, entry, cubic, policy);
info = struct('model_id', model, 'charge_e', charges, ...
    'temp_k', double(temp_k), 'ion_mobility_ratio_1', ...
    entry.ion_mobility_ratio, 'sum_requested_frac', sum(f_frac, 2), ...
    'below_range_mask_1', low, 'above_range_mask_1', high, ...
    'max_charge_e', qmax, 'tail_bound_frac', tail, ...
    'tail_diameter_m', tail_d, 'tail_polarity', polarity);
end

function [f, low, high] = fractions(d, charges, s, entry, cubic, policy)
% Evaluating the regression only inside its diameter interval
nm = d / 1e-9;
nm(abs(nm - 1000) <= 8*eps(1000)) = 1000;
lower_nm = ones(size(charges));
lower_nm(abs(charges) == 2) = 20;
if cubic, lower_nm(:) = 5; end
low = nm + 8*eps(nm) < lower_nm;
high = repmat(nm > 1000, 1, numel(charges));
if any(low(:)) || any(high(:))
    message = ['Diameter outside the regression range. Warn uses zero ' ...
        'for manual double charges below 20 nm, NaN below the model ' ...
        'minimum, and the high-charge expression above 1000 nm.'];
    if strcmp(policy, 'stop'), fail('OutsideRange', message); end
    warning('sootMosaic:CHARGE_FRAC:OutsideRange', '%s', message);
end
use_high = high | repmat(abs(charges) > 2, numel(d), 1);
if any(use_high(:)), require_ratio(entry); end
f = NaN(numel(d), numel(charges));
for j = 1:numel(charges)
    regression = ~use_high(:, j) & ~low(:, j);
    if any(regression)
        a = entry.coefficients(:, charges(j) + 3);
        x = log10(nm(regression));
        if cubic, x = log(nm(regression)); end
        y = zeros(size(x));
        for k = numel(a):-1:1, y = y .* x + a(k); end
        if cubic, f(regression, j) = exp(y);
        else, f(regression, j) = 10.^y;
        end
    end
    selected = use_high(:, j) & ~low(:, j);
    if any(selected)
        f(selected, j) = gaussian(s(selected), charges(j), ...
            entry.ion_mobility_ratio);
    end
    if ~cubic && abs(charges(j)) == 2
        f(low(:, j) & nm >= 1, j) = 0;
    end
end
end

function [limit, tail] = charge_limit(d, s, entry, cubic, policy, tol, ...
        cap, polarity)
% Bounding the discrete omitted mass without subtracting from unity
mu = s * log(entry.ion_mobility_ratio);
if cap <= abs(mu)
    fail('TailNotConverged', 'Charge cap does not reach the decreasing tail.');
end
remainder_pos = 0.5 * erfc((cap - mu) / sqrt(2*s));
remainder_neg = 0.5 * erfc((cap + mu) / sqrt(2*s));
remainder = remainder_pos + remainder_neg;
if strcmp(polarity, 'positive'), remainder = remainder_pos; end
if strcmp(polarity, 'negative'), remainder = remainder_neg; end
if remainder >= tol
    fail('TailNotConverged', 'Charge cap does not bound the omitted mass.');
end
charges = -cap:cap;
f = fractions(d, charges, s, entry, cubic, policy);
if any(~isfinite(f))
    fail('TailUnavailable', 'The diameter has no finite charge distribution.');
end
shell = f(cap + 2:end) + fliplr(f(1:cap));
if strcmp(polarity, 'positive'), shell = f(cap + 2:end); end
if strcmp(polarity, 'negative'), shell = fliplr(f(1:cap)); end
% Integrating each decreasing outer tail from cap bounds the uncomputed...
    % ...integer terms. Reverse sums avoid cancellation in small tails
omitted = [fliplr(cumsum(fliplr(shell))) 0] + remainder;
index = find(omitted < tol, 1);
if isempty(index)
    fail('TailNotConverged', 'Charge cap does not meet the tail tolerance.');
end
limit = index - 1;
tail = omitted(index);
end

function f = gaussian(s, n, ratio)
mu = s .* log(ratio);
f = exp(-(n - mu).^2 ./ (2*s)) ./ sqrt(2*pi*s);
end

function require_ratio(entry)
if ~positive_scalar(entry.ion_mobility_ratio)
    fail('MissingIonMobilityRatio', entry.ratio_note);
end
end

function yes = positive_scalar(value)
yes = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value > 0;
end

function value = option(opts, key, fallback)
if isfield(opts, key), value = opts.(key); else, value = fallback; end
end

function fail(reason, message)
error(['sootMosaic:CHARGE_FRAC:' reason], '%s', message);
end
