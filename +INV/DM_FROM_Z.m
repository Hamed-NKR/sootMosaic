function dm_m = DM_FROM_Z(z_m2_v_s, charge, temp_k, pressure_pa, cfg)
% "DM_FROM_Z" solves the electrical mobility relation for diameter.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     z_m2_v_s: Positive electrical mobility magnitude (m2/(V s))
%     charge: Nonzero integer charge state, scalar or the shape of z....
%         ...Either polarity uses its magnitude (-)
%     temp_k: Recorded DMA temperature, positive scalar (K)
%     pressure_pa: Recorded DMA pressure, positive scalar (Pa)
%     cfg: Resolved inversion configuration, optional
% ----------------------------------------------------------------------- %
%
% Outputs:
%     dm_m: Mobility diameters, with the shape of z_m2_v_s (m)
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 7-9).
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

if nargin < 5, cfg = []; end
if ~isnumeric(z_m2_v_s) || ~isreal(z_m2_v_s) || isempty(z_m2_v_s) || ...
        any(~isfinite(z_m2_v_s(:))) || any(z_m2_v_s(:) <= 0)
    error('sootMosaic:DM_FROM_Z:InvalidMobility', ...
        'Mobility magnitudes must be positive and finite.');
end
if ~isnumeric(charge) || ~isreal(charge) || isempty(charge) || ...
        any(~isfinite(charge(:))) || any(charge(:) == 0) || ...
        any(charge(:) ~= fix(charge(:))) || ...
        any(abs(charge(:)) > flintmax) || ...
        ~(isscalar(charge) || isequal(size(charge), size(z_m2_v_s)))
    error('sootMosaic:DM_FROM_Z:InvalidCharge', ...
        'Charge must be a nonzero integer scalar or match the mobility.');
end
[mu, lambda, ~, params] = INV.GAS(temp_k, pressure_pa, [], cfg);
slip = params.slip;
b = 2 * lambda * (slip.kim2005.a + slip.kim2005.b);
dm_m = zeros(size(z_m2_v_s));
for k = 1:numel(dm_m)
    if isscalar(charge), n = abs(double(charge));
    else, n = abs(double(charge(k)));
    end
    a = n * params.constants.e_c / (3 * pi * mu * double(z_m2_v_s(k)));
    % Bracketing d = a Cc(d), with 1 <= Cc(d) <= 1 + b/d
    lo = a;
    hi = a + sqrt(a) * sqrt(b);
    if ~isfinite(hi) || lo <= 0
        error('sootMosaic:DM_FROM_Z:RootRange', ...
            'The mobility exceeds the finite diameter range.');
    end
    for iteration = 1:256
        mid = lo + (hi - lo) / 2;
        cc = TRANSP.CUNNINGHAM(mid, lambda, slip.model, '', slip);
        if mid < a * cc, lo = mid; else, hi = mid; end
        if hi - lo <= 4 * eps(mid), break; end
    end
    if hi - lo > 4 * eps(mid)
        error('sootMosaic:DM_FROM_Z:RootConvergence', ...
            'The diameter bracket did not converge.');
    end
    dm_m(k) = lo + (hi - lo) / 2;
end
end
