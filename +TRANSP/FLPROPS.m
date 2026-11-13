function [mu_f, lambda_f] = FLPROPS(fl, params_const, opts)
% "FLPROPS" calculates the gas viscosity and mean free path at the fluid...
%     ...temperature and pressure, or returns one of two fixed presets.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     fl: Fluid information structure (temp in K, p in Pa)
%     params_const: Problem's table of constant physical properties
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
    opts.amb = 'flame'; % assume flame conditions as default
end

% Calculating the properties of air at the fluid temperature and pressure
if strcmp(opts.amb, 'sutherland')
    temp = require_state(fl, 'temp', 'sootMosaic:FLPROPS:InvalidTemperature',...
        'fl.temp must be a positive finite temperature (K).');
    p = require_state(fl, 'p', 'sootMosaic:FLPROPS:InvalidPressure',...
        'fl.p must be a positive finite pressure (Pa).');

    % Viscosity of 1.716e-5 Pa.s at 273.15 K, scaled with T^1.5 / (T +...
        % ...110.4) with T in K (README reference 7)
    mu_f = 1.716e-5 * (temp / 273.15)^1.5 * (273.15 + 110.4) /...
        (temp + 110.4);

    % Mean free path of 67.3 nm at 296.15 K and 101325 Pa, scaled with...
        % ...T^2 / (T + 110.4) / p with T in K and p in Pa (README...
        % ...reference 7)
    lambda_f = 67.3e-9 * (temp / 296.15)^2 * (296.15 + 110.4) /...
        (temp + 110.4) * (101325 / p);
    return
end

if strcmp(opts.amb, 'room') % @ 20 c & 1 atm: room conditions; typical of post-flame agglomeration
    mu_f = 1.813e-5; % Viscosity (Pa.s)
    lambda_f = 6.8e-8; % Mean free path (m)
    temp_preset = 293.15; % Preset temperature (K)
elseif strcmp(opts.amb, 'flame') % @ 1700 k & 1 atm: typical of soot formation within flame
    mu_f = 5.647e-5;
    lambda_f = 4.98e-7;
    temp_preset = 1700;
else
    error('sootMosaic:FLPROPS:UnknownModel', ['Unknown fluid property ',...
        'model %s. Known models are sutherland, flame and room.'],...
        char(opts.amb))
end

% Comparing the preset state with the fluid state (1 K, 1 percent)
if isfield(fl, 'temp') && ~isempty(fl.temp) &&...
        abs(fl.temp - temp_preset) > 1
    warning('sootMosaic:FLPROPS:PresetTemperature', ['The %s preset holds ',...
        'gas properties at %.2f K and the fluid is at %.2f K. The ',...
        'sutherland model gives them at the fluid temperature.'],...
        opts.amb, temp_preset, fl.temp)
end
if isfield(fl, 'p') && ~isempty(fl.p) && abs(fl.p / 101325 - 1) > 0.01
    warning('sootMosaic:FLPROPS:PresetPressure', ['The %s preset holds gas ',...
        'properties at 101325 Pa and the fluid is at %.6g Pa. The ',...
        'sutherland model gives them at the fluid pressure.'],...
        opts.amb, fl.p)
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
