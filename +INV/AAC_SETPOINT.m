function [tau_s, da_m] = AAC_SETPOINT(cfg, step_id)
% "AAC_SETPOINT" calculates the relaxation time and aerodynamic setpoint.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     cfg: Resolved inversion configuration for one row or tandem step....
%         ...The si.scan fields supply AAC temperature (K), pressure (Pa),...
%         ...speed (rad/s) and sheath flow (m3/s). The recorded flow key...
%         ...scan.aac_sheath_flow_lpm is read per scan, converted once...
%         ...by the loader. Balanced sheath and exhaust flows are assumed....
%         ...Geometry comes from si.geometry, default registry entry aac...
%         ...(inner radius 0.056 m, outer radius 0.060 m, length 0.206 m)....
%         ...State and speed require a data or campaign reading record
%     step_id: Nonempty row or tandem step label for input errors
% ----------------------------------------------------------------------- %
%
% Outputs:
%     tau_s: Setpoint relaxation time (s)
%     da_m: Setpoint aerodynamic diameter (m)
% ----------------------------------------------------------------------- %
% Method: Tavakoli and Olfert (2013); Johnson et al. (2018, Eq. 2);
%     ...Kiasadegh et al. (2026, Eqs. 6 and 14). Dimensions from the AAC...
%     ...manual v2.43 (Appendix F.1, p. 152).
% The numerical core is the shared private function aac_setpoint_physics.
% Repository: https://github.com/cambustion/tandem
% Source: src/aerosol_psd_fitting_tool.py
% Commit: 0cc733cd4d2f80defd8ef5b93a3bb586778012df
% License: MIT License.
% MIT License
%
% Copyright (c) 2023-24 Cambustion, University of Alberta, NRC Canada
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

if nargin < 2 || ...
        ~((ischar(step_id) && isrow(step_id)) || ...
        isStringScalar(step_id)) || ...
        strlength(strtrim(string(step_id))) == 0
    error('sootMosaic:AAC_SETPOINT:InvalidLabel', ...
        'A row or tandem step label is required.');
end
step_id = char(step_id);
omega = required(cfg, 'scan', 'aac_speed_rad_s', step_id);
temp = required(cfg, 'scan', 'aac_temperature_deg_c', step_id);
pressure = required(cfg, 'scan', 'aac_pressure_kpa', step_id);
qsh = required(cfg, 'scan', 'aac_sheath_flow_lpm', step_id);
r1 = required(cfg, 'geometry', 'aac_inner_radius_m', step_id);
r2 = required(cfg, 'geometry', 'aac_outer_radius_m', step_id);
required(cfg, 'geometry', 'aac_length_m', step_id);
if r2 <= r1
    error('sootMosaic:AAC_SETPOINT:InvalidGeometry', ...
        'Step %s requires an outer radius greater than the inner.', step_id);
end
try
    [tau_s, da_m] = aac_setpoint_physics(omega, qsh, temp, pressure, cfg);
catch err
    switch err.identifier
        case 'sootMosaic:AAC_PHYSICS:GasState'
            error('sootMosaic:AAC_SETPOINT:InvalidGasState', ...
                'Step %s: %s', step_id, err.message);
        case 'sootMosaic:AAC_PHYSICS:RootRange'
            error('sootMosaic:AAC_SETPOINT:RootRange', ...
                'Step %s exceeds the finite setpoint range.', step_id);
        case 'sootMosaic:AAC_PHYSICS:RootConvergence'
            error('sootMosaic:AAC_SETPOINT:RootConvergence', ...
                'Step %s has no converged diameter bracket.', step_id);
        otherwise
            rethrow(err);
    end
end
logged = cfg.si.scan.aac_setpoint_nm;
if ~isempty(logged)
    tol = cfg.checks.setpoint_rel_tol;
    if isempty(tol) || ~isscalar(tol) || ~isfinite(tol) || tol <= 0
        error('sootMosaic:AAC_SETPOINT:MissingCheckTolerance', ...
            'Step %s requires a setpoint comparison tolerance.', step_id);
    end
    if abs(da_m/logged - 1) > tol
        warning('sootMosaic:AAC_SETPOINT:SetpointMismatch', ...
            'Step %s differs from its recorded aerodynamic setpoint.', step_id);
    end
end
end

function value = required(cfg, section, key, step_id)
% "required" reads a positive scalar from a resolved SI section.
value = [];
if isstruct(cfg) && isscalar(cfg) && isfield(cfg, 'si') && ...
        isstruct(cfg.si) && isscalar(cfg.si) && ...
        isfield(cfg.si, section) && isstruct(cfg.si.(section)) && ...
        isscalar(cfg.si.(section)) && isfield(cfg.si.(section), key)
    value = cfg.si.(section).(key);
end
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('sootMosaic:AAC_SETPOINT:MissingInput', ...
        'Step %s requires a positive finite %s.%s in SI.', ...
        step_id, section, key);
end
value = double(value);
if strcmp(section, 'scan')
    require_recorded(cfg, {['scan.' key]}, 'AAC_SETPOINT');
end
end
