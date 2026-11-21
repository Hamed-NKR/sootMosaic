function da = aerodynamic_diameter(dm, rho, t, p, cfg)
% "aerodynamic_diameter" maps mobility size and effective density to size.
% ----------------------------------------------------------------------- %
% Method: Johnson et al. (2018, Eq. 1); Kiasadegh et al. (2026, Eq. 26).
% Diameters are (m), density is (kg/m3), state is (K, Pa).
if isa(rho, 'function_handle'), rho = rho(dm); end
if ~isnumeric(rho) || ~isreal(rho) || ...
        ~(isscalar(rho) || isequal(size(rho), size(dm))) || ...
        any(~isfinite(rho(:)) | rho(:) <= 0)
    error('sootMosaic:aerodynamic_diameter:Density', 'Require a positive effective density at every size.');
end
[~, ~, cc, params] = INV.GAS(t, p, dm, cfg);
target = rho/params.constants.rho_aero_ref_kg_m3.*dm.^2.*cc;
lo = dm.*min(1, rho/params.constants.rho_aero_ref_kg_m3)/100;
hi = dm.*max(1, rho/params.constants.rho_aero_ref_kg_m3)*100;
for j = 1:80
    mid = sqrt(lo.*hi);
    [~, ~, cm] = INV.GAS(t, p, mid, cfg);
    less = mid.^2.*cm < target;
    lo(less) = mid(less);
    hi(~less) = mid(~less);
end
da = sqrt(lo.*hi);
end
