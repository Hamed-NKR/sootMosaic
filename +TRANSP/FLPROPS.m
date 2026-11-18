function [mu_f, lambda_f] = FLPROPS(fl, params_const, opts)
% "FLPROPS" calculates the gas viscosity and mean free path at the fluid...
%     ...temperature and pressure, or returns one of two fixed presets.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     fl: Fluid information structure (temp in K, p in Pa)
%     params_const: Physical constants table (unused)
%     opts.gas: Gas section of the resolved SI profile (optional)
%     opts.amb: Property model, 'sutherland' (from fl.temp and fl.p),...
%         ...'flame' (preset for 1700 K and 101325 Pa) or 'room' (preset...
%         ...for 293.15 K and 101325 Pa), default 'flame'
% ----------------------------------------------------------------------- %
%
% Outputs:
%     mu_f: Fluid viscosity (Pa.s)
%     lambda_f: Gas mean free path (m)
% ----------------------------------------------------------------------- %

% M_air = params_const.Value(2); % Air molar mass (kg/mol)
% Na = params_const.Value(4); % Avogadro constant (mol^-1)
% Ru = params_const.Value(5); % Universal gas constant (j/mol.k)
% 
% d_kin = (0.79 * 3.64 + 0.21 * 3.46) * 1e-10; % Air kinetic diameter...
% % ...(an average estimate based on values for N2 and O2)
% sig_col = pi * (d_kin^2); % Collision area (m2)
% mu_f = 2 * sqrt(M_air*Ru*(fl.temp)) / (3*sqrt(pi)*Na*sig_col); % Viscosity
% lambda_f = mu_f / (0.499*(fl.p)*sqrt(8*M_air/(pi*Ru*(fl.temp)))); % Mean...
%     % ...free path 

% initialize ambient variable
if ~exist('opts', 'var') 
    opts = struct();
end
if (~isfield(opts, 'amb')) || isempty(opts.amb)
    defaults = UTILS.CALL_DEFAULTS();
    opts.amb = defaults.flprops.amb;
end

% Reading the supplied gas section over the fixed call values
defaults = UTILS.MODEL_DEFAULTS('article1_7658971');
gas = defaults.gas;
if isfield(opts, 'gas') && ~isempty(opts.gas)
    gas = UTILS.CONFIG_MERGE(gas, opts.gas);
end
validate_gas(gas);

% Calculating viscosity and mean free path (README reference 7, Eqs. 9, 11)
if strcmp(opts.amb, 'sutherland')
    temp = require_state(fl, 'temp', 'sootMosaic:FLPROPS:InvalidTemperature',...
        'fl.temp must be a positive finite temperature (K).');
    p = require_state(fl, 'p', 'sootMosaic:FLPROPS:InvalidPressure',...
        'fl.p must be a positive finite pressure (Pa).');
    v = gas.sutherland;
    g = gas.mean_free_path;
    mu_f = v.mu_ref_pa_s * (temp / v.t_ref_k)^1.5 * ...
        (v.t_ref_k + v.s_k) / (temp + v.s_k);
    lambda_f = g.lambda_ref_m * (temp / g.t_ref_k)^2 * ...
        (g.t_ref_k + g.s_k) / (temp + g.s_k) * (g.p_ref_pa / p);
    return
end

if any(strcmp(opts.amb, {'room', 'flame'}))
    preset = gas.presets.(opts.amb);
    mu_f = preset.mu_pa_s;
    lambda_f = preset.lambda_m;
    temp_preset = preset.t_k;
else
    error('sootMosaic:FLPROPS:UnknownModel', ['Unknown fluid property ',...
        'model %s. Known models are sutherland, flame and room.'],...
        char(opts.amb))
end

% Comparing the preset state with the fluid state
w = gas.preset_warning;
if isfield(fl, 'temp') && ~isempty(fl.temp) &&...
        abs(fl.temp - temp_preset) > w.temperature_tol_k
    warning('sootMosaic:FLPROPS:PresetTemperature', ['The %s preset holds ',...
        'gas properties at %.2f K and the fluid is at %.2f K. The ',...
        'sutherland model gives them at the fluid temperature.'],...
        opts.amb, temp_preset, fl.temp)
end
if isfield(fl, 'p') && ~isempty(fl.p) && ...
        abs(fl.p / w.p_ref_pa - 1) > w.pressure_rel_tol
    warning('sootMosaic:FLPROPS:PresetPressure', ['The %s preset holds gas ',...
        'properties at %.6g Pa and the fluid is at %.6g Pa. The ',...
        'sutherland model gives them at the fluid pressure.'],...
        opts.amb, w.p_ref_pa, fl.p)
end

end

function val = require_state(fl, field_name, id, msg)
% "REQUIRE_STATE" returns a fluid state field after checking that it is...
%     ...a positive finite real scalar.
if ~isfield(fl, field_name) || ~isnumeric(fl.(field_name)) ||...
        ~isscalar(fl.(field_name)) || ~isreal(fl.(field_name)) ||...
        ~isfinite(fl.(field_name)) || fl.(field_name) <= 0
    error(id, msg)
end
val = double(fl.(field_name));
end

function validate_gas(gas)
% "validate_gas" checks numeric gas parameters before evaluation.
sections = {gas.sutherland, gas.mean_free_path, gas.presets.room, ...
    gas.presets.flame, gas.preset_warning};
for k = 1:numel(sections)
    names = fieldnames(sections{k});
    for j = 1:numel(names)
        name = names{j};
        value = sections{k}.(name);
        zero_ok = any(strcmp(name, {'temperature_tol_k', ...
            'pressure_rel_tol', 's_k'}));
        if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
                ~isfinite(value) || value < 0 || (~zero_ok && value == 0)
            error('sootMosaic:FLPROPS:InvalidGasParameter', ...
                'Gas parameter %s is outside its physical range.', name);
        end
    end
end
end
