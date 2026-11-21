function [tau_s, da_m] = aac_setpoint_physics(omega_rad_s, ...
    sheath_flow_m3_s, temp_k, pressure_pa, cfg)
% "aac_setpoint_physics" gives the relaxation time and aerodynamic diameter.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     omega_rad_s: Positive rotational speed (rad/s)
%     sheath_flow_m3_s: Positive sheath flow, balanced with the exhaust...
%         ...flow (m3/s)
%     temp_k: Gas temperature (K)
%     pressure_pa: Gas pressure (Pa)
%     cfg: Resolved inversion configuration. Geometry comes from...
%         ...si.geometry (aac_inner_radius_m, aac_outer_radius_m and...
%         ...aac_length_m), gas and slip from INV.GAS
% ----------------------------------------------------------------------- %
%
% Outputs:
%     tau_s: Relaxation time at the speed and sheath flow (s)
%     da_m: Aerodynamic diameter whose relaxation time equals tau_s (m)
% ----------------------------------------------------------------------- %
% Method: Tavakoli and Olfert (2013); Johnson et al. (2018, Eq. 2);
%     ...Kiasadegh et al. (2026, Eqs. 6 and 14). Dimensions from the AAC...
%     ...manual v2.43 (Appendix F.1, p. 152).
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
%The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

geometry = cfg.si.geometry;
r1 = geometry.aac_inner_radius_m;
r2 = geometry.aac_outer_radius_m;
len = geometry.aac_length_m;
try
    [mu, lambda, ~, params] = INV.GAS(temp_k, pressure_pa, [], cfg);
catch err
    error('sootMosaic:AAC_PHYSICS:GasState', '%s', err.message);
end
tau_s = (2 * sheath_flow_m3_s) / (pi * omega_rad_s^2 * (r1 + r2)^2 * len);
a = 18 * mu * tau_s / params.constants.rho_aero_ref_kg_m3;
slip = params.slip;
b = 2 * lambda * (slip.kim2005.a + slip.kim2005.b);
% Bracketing d^2 Cc(d) = a, with 1 <= Cc(d) <= 1 + b/d
hi = sqrt(a);
lo = a / (hi + b);
if ~isfinite(tau_s) || ~isfinite(hi) || lo <= 0
    error('sootMosaic:AAC_PHYSICS:RootRange', ...
        'The setpoint exceeds the finite diameter range.');
end
for iteration = 1:256
    mid = lo + (hi - lo) / 2;
    cc = TRANSP.CUNNINGHAM(mid, lambda, slip.model, '', slip);
    if mid^2 * cc < a, lo = mid; else, hi = mid; end
    if hi - lo <= 4 * eps(mid), break; end
end
if hi - lo > 4 * eps(mid)
    error('sootMosaic:AAC_PHYSICS:RootConvergence', ...
        'The diameter bracket did not converge.');
end
da_m = lo + (hi - lo) / 2;
end
