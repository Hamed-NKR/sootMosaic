function [omega, info] = TFER_AAC(tau_s, da_set_m, dm_m, cfg, ...
        step_id, sizing_scale, width_factor_scale)
% "TFER_AAC" calculates the steady AAC transfer probability.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     tau_s: Positive particle relaxation times (s)
%     da_set_m: Nominal aerodynamic diameter setpoint, scalar (m)
%     dm_m: Mobility diameter for diffusion, scalar or size of tau_s (m)
%     cfg: Resolved configuration with balanced AAC flows and recorded...
%         ...AAC-side temperature and pressure from data or campaign
%     step_id: Nonempty row or tandem step label for input errors
%     sizing_scale: Setpoint diameter multiplier, optional, default 1 (-)
%     width_factor_scale: Width-factor multiplier, optional, default 1 (-)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     omega: Transfer probability, with the expanded input shape (-)
%     info: Height, width factor, transmission, diffusion coefficient...
%         ...(m2/s), setpoint time (s) and published width fit error (%)
% ----------------------------------------------------------------------- %
% Method: Johnson et al. (2018, Eqs. 2, 7, 12-15, Table 1, AAC All);...
%     ...Tavakoli and Olfert (2013, Eqs. 4-11, limited trajectories).
% Reimplementation from the published equations. The default model uses...
%     ...the AAC All fit at da and diffusional transmission at dm. The...
%     ...limited-trajectory variant is a nondiffusing plug-flow model....
%     ...A larger width factor narrows the response and raises its height....
%     ...The variant reports unit external transmission and no fit error;...
%     ...its trajectory loss remains in the transfer probability.

if nargin < 6, sizing_scale = 1; end
if nargin < 7, width_factor_scale = 1; end
if nargin < 5 || ~((ischar(step_id) && isrow(step_id)) || ...
        isStringScalar(step_id)) || strlength(strtrim(string(step_id))) == 0
    error('sootMosaic:TFER_AAC:InvalidLabel', 'A step label is required.');
end
step_id = char(step_id);
if ~positive(tau_s) || isempty(tau_s) || ~positive(dm_m) || ...
        isempty(dm_m) || ~(isscalar(tau_s) || isscalar(dm_m) || ...
        isequal(size(tau_s), size(dm_m))) || ...
        ~positive(da_set_m) || ~isscalar(da_set_m) || ...
        ~positive(sizing_scale) || ~isscalar(sizing_scale) || ...
        ~positive(width_factor_scale) || ~isscalar(width_factor_scale)
    fail('InvalidInput', step_id, ...
        'Require positive, compatible particle inputs.');
end
try
    s = cfg.si.scan;
    fit = cfg.si.transfer.aac;
    model = cfg.transfer.aac.model;
    balance = cfg.transfer.aac.flow_balance;
catch
    fail('InvalidConfig', step_id, 'Pass a resolved inversion configuration.');
end
if ~strcmp(balance, 'balanced')
    fail('InvalidFlows', step_id, 'The AAC models require balanced flows.');
end
qa = required(s, 'aac_sample_flow_lpm', step_id);
qsh = required(s, 'aac_sheath_flow_lpm', step_id);
temp = required(s, 'aac_temperature_deg_c', step_id);
pressure = required(s, 'aac_pressure_kpa', step_id);
require_recorded(cfg, {'scan.aac_temperature_deg_c', ...
    'scan.aac_pressure_kpa', 'scan.aac_sample_flow_lpm', ...
    'scan.aac_sheath_flow_lpm'}, 'TFER_AAC');
beta_ratio = qa/qsh;
if beta_ratio >= 1
    fail('InvalidFlows', step_id, ...
        'The aerosol to sheath ratio must be below one.');
end
da = da_set_m*sizing_scale;
try
    [mu, ~, cc_set, params] = INV.GAS(temp, pressure, da, cfg);
    [~, ~, cc_dm] = INV.GAS(temp, pressure, dm_m, cfg);
catch err
    fail('InvalidGasState', step_id, err.message);
end
tau_set = params.constants.rho_aero_ref_kg_m3*da^2*cc_set/(18*mu);
ratio = tau_s/tau_set + zeros(size(dm_m));
diffusivity = params.constants.kb_j_k*temp*cc_dm./(3*pi*mu*dm_m);
switch model
    case 'johnson2018_nonideal'
        unit_m = required(fit, 'width_diameter_unit_nm', step_id);
        width_factor = width_factor_scale * ...
            (fit.width_a*(da/unit_m)^fit.width_b + fit.width_c);
        if ~positive(width_factor) || ~isscalar(width_factor)
            fail('InvalidWidth', step_id, ...
                'The fitted width factor must be positive.');
        end
        try
            [transmission, loss] = INV.PENETRATION(dm_m, temp, pressure, ...
                qa, cfg, 'aac');
        catch err
            fail('InvalidTransmission', step_id, err.message);
        end
        peak_height = transmission*width_factor;
        omega = peak_height.*max(0, 1-abs(ratio-1)*width_factor/beta_ratio);
        error_percent = cfg.transfer.aac.width_error_percent;
        diffusion_transmission = loss.diffusional;
    case 'tavakoli2013_limited_trajectory'
        g = cfg.si.geometry;
        r1 = required(g, 'aac_inner_radius_m', step_id);
        r2 = required(g, 'aac_outer_radius_m', step_id);
        if r2 <= r1
            fail('InvalidGeometry', step_id, ...
                'The outer radius must exceed the inner.');
        end
        gap2 = r2^2-r1^2;
        inlet2 = r1^2 + qa/(qa+qsh)*gap2;
        outlet2 = r2^2 - qa/(qa+qsh)*gap2;
        adjusted = 1 + width_factor_scale*(ratio-1);
        exponent = -4*qsh*gap2/((r1+r2)^2*(qa+qsh))*adjusted;
        back = exp(exponent);
        rising = (inlet2-outlet2*back)/(inlet2-r1^2);
        falling = (r2^2*back-r1^2)/(inlet2-r1^2);
        omega = width_factor_scale*max(0, min(1, min(rising, falling)));
        width_factor = width_factor_scale;
        peak_back = (inlet2+r1^2)/(outlet2+r2^2);
        peak_height = width_factor_scale * ...
            min(1, (inlet2-outlet2*peak_back)/(inlet2-r1^2));
        transmission = ones(size(dm_m));
        diffusion_transmission = transmission;
        error_percent = [];
    otherwise
        fail('InvalidModel', step_id, 'Unknown AAC transfer model.');
end
if any(~isfinite(omega(:))) || ~isfinite(tau_set) || tau_set <= 0
    fail('NumericRange', step_id, 'Inputs exceed the finite transfer range.');
end
info = struct('beta', beta_ratio, 'width_factor', width_factor, ...
    'height', peak_height, ...
    'transmission', transmission, 'diffusional', diffusion_transmission, ...
    'diffusivity_m2_s', diffusivity, 'tau_set_s', tau_set, ...
    'width_error_percent', error_percent, ...
    'sizing_scale_ratio', sizing_scale, ...
    'width_factor_scale_ratio', width_factor_scale, 'model', model, ...
    'temperature_k', temp, 'pressure_pa', pressure);
end

function value = required(s, key, step_id)
% "required" reads a positive scalar in SI.
if ~isfield(s, key) || ~isscalar(s.(key)) || ~positive(s.(key))
    fail('MissingInput', step_id, ...
        ['A positive SI value is required for ' key '.']);
end
value = double(s.(key));
end

function yes = positive(value)
% "positive" checks finite positive numeric values.
yes = isnumeric(value) && isreal(value) && ...
    all(isfinite(value(:))) && all(value(:) > 0);
end

function fail(reason, step_id, message)
% "fail" reports the affected row or tandem step.
error(['sootMosaic:TFER_AAC:' reason], 'Step %s: %s', step_id, message);
end
