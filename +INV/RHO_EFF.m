function rho_kg_m3 = RHO_EFF(da_m, dm_m, temp_k, pressure_pa, cfg)
% "RHO_EFF" calculates effective density from aerodynamic and mobility size.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     da_m: Aerodynamic diameters at the AAC state (m)
%     dm_m: Mobility diameters from DM_FROM_Z at the DMA state, scalar...
%         ...or the shape of da_m. Either diameter may be scalar (m)
%     temp_k: Recorded AAC temperature, positive scalar (K)
%     pressure_pa: Recorded AAC pressure, positive scalar (Pa)
%     cfg: Resolved inversion configuration, optional
% ----------------------------------------------------------------------- %
%
% Outputs:
%     rho_kg_m3: Effective density, using both slips at the AAC state...
%         ...(kg/m3)
% ----------------------------------------------------------------------- %
% Method: Tavakoli and Olfert (2014, Eqs. 3-5 and 7); Kiasadegh et al....
%     ...(2026, Eqs. 26-31).

if nargin < 5, cfg = []; end
if isempty(da_m) || isempty(dm_m) || ...
        ~(isscalar(da_m) || isscalar(dm_m) || isequal(size(da_m), size(dm_m)))
    error('sootMosaic:RHO_EFF:InvalidDiameters', ...
        'Diameters must be nonempty and scalar or of matching shape.');
end
[~, lambda, cc_da, params] = INV.GAS(temp_k, pressure_pa, da_m, cfg);
if ~isnumeric(dm_m) || ~isreal(dm_m) || ...
        any(~isfinite(dm_m(:))) || any(dm_m(:) <= 0)
    error('sootMosaic:RHO_EFF:InvalidDiameters', ...
        'Mobility diameters (m) must be positive and finite.');
end
cc_dm = TRANSP.CUNNINGHAM(double(dm_m), lambda, ...
    params.slip.model, '', params.slip);
rho_kg_m3 = params.constants.rho_aero_ref_kg_m3 * ...
    (double(da_m) ./ double(dm_m)).^2 .* (cc_da ./ cc_dm);
if any(~isfinite(rho_kg_m3(:))) || any(rho_kg_m3(:) <= 0)
    error('sootMosaic:RHO_EFF:DensityRange', ...
        'The diameters exceed the finite density range.');
end
end
