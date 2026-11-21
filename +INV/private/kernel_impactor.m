function eta = kernel_impactor(dm, da, cfg, impactor, caller)
% "kernel_impactor" applies the aerodynamic sigmoid cut to each cell.
% ----------------------------------------------------------------------- %
% Method: 3082 manual (2016, Eq. B-1); Johnson et al. (2018, Eq. 1).
% The sigmoid is an assumed shape (config/main_inv/DEFAULTS.md, section 12).
keys = {'d50_m', 'cut_factor_1', 'sharpness_1'};
for k = 1:numel(keys)
    key = keys{k};
    if ~isfield(impactor, key) || ~isnumeric(impactor.(key)) || ...
            ~isreal(impactor.(key)) || ~isscalar(impactor.(key)) || ...
            ~isfinite(impactor.(key)) || impactor.(key) <= 0
        error(['sootMosaic:' caller ':Impactor'], 'Require the GRID_RULE impactor parameters.');
    end
end
if isempty(da)
    if ~isfield(impactor, 'rho_kg_m3')
        error(['sootMosaic:' caller ':Density'], 'Require the condition density relation.');
    end
    da = aerodynamic_diameter(dm, impactor.rho_kg_m3, ...
        cfg.si.scan.dma_temperature_deg_c, cfg.si.scan.dma_pressure_kpa, cfg);
end
eta = 1./(1+(da/(impactor.d50_m*impactor.cut_factor_1)).^impactor.sharpness_1);
end
