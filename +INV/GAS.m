function [mu_pa_s, lambda_m, cc, params] = GAS(temp_k, pressure_pa, d_m, cfg)
% "GAS" calculates gas properties and slip at the recorded gas state.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     temp_k: Recorded gas temperature, positive scalar (K)
%     pressure_pa: Recorded gas pressure, positive scalar (Pa)
%     d_m: Positive particle diameters, or empty for gas properties (m)
%     cfg: Resolved inversion configuration, optional. The current...
%         ...profile and its logged-state gas model are required
% ----------------------------------------------------------------------- %
%
% Outputs:
%     mu_pa_s: Dynamic viscosity (Pa s)
%     lambda_m: Mean free path (m)
%     cc: Slip correction, with the shape of d_m (-)
%     params: Resolved SI profile sections used for the calculation
% ----------------------------------------------------------------------- %
% Method: Kim et al. (2005, Eqs. 9, 11 and 34); Wiedensohler et al....
%     ...(2012, Appendix A5).

if nargin < 3, d_m = []; end
if nargin < 4 || isempty(cfg)
    [model, ~, profile] = UTILS.MODEL_PROFILE('current', 'INV');
else
    if ~isstruct(cfg) || ~isscalar(cfg) || ...
            ~isfield(cfg, 'model') || ~isfield(cfg, 'model_params')
        error('sootMosaic:GAS:InvalidConfig', ...
            'Pass the resolved inversion configuration.');
    end
    model = cfg.model;
    profile = cfg.model_params;
end
if ~strcmp(model.profile, 'current') || ...
        ~strcmp(model.fluid_properties, 'sutherland') || ...
        ~strcmp(model.slip_correction, 'kim2005') || ...
        ~strcmp(profile.si.gas.model, 'sutherland') || ...
        ~strcmp(profile.si.slip.model, 'kim2005')
    error('sootMosaic:GAS:InvalidGasModel', ...
        'Recorded states require the current profile without gas presets.');
end
if ~positive_scalar(temp_k) || ~positive_scalar(pressure_pa)
    error('sootMosaic:GAS:InvalidState', ...
        'Temperature (K) and pressure (Pa) must be positive finite scalars.');
end
if ~isnumeric(d_m) || ~isreal(d_m) || ...
        any(~isfinite(d_m(:))) || any(d_m(:) <= 0)
    error('sootMosaic:GAS:InvalidDiameter', ...
        'Diameters (m) must be positive and finite.');
end
params = profile.si;
fluid = struct('temp', double(temp_k), 'p', double(pressure_pa));
opts = struct('amb', 'sutherland', 'gas', params.gas);
[mu_pa_s, lambda_m] = TRANSP.FLPROPS(fluid, [], opts);
cc = TRANSP.CUNNINGHAM(double(d_m), lambda_m, ...
    params.slip.model, '', params.slip);
if ~positive_scalar(mu_pa_s) || ~positive_scalar(lambda_m) || ...
        any(~isfinite(cc(:)))
    error('sootMosaic:GAS:PropertyRange', ...
        'The recorded state exceeds the finite property range.');
end
if nargin >= 4 && ~isempty(cfg)
    recorded = cfg.si.scan;
    tol = cfg.checks.gas_property_rel_tol;
    % Logged DMA properties are evaluated at the recorded DMA state.
    if positive_scalar(recorded.dma_temperature_deg_c) && ...
            positive_scalar(recorded.dma_pressure_kpa)
        state = struct('temp', recorded.dma_temperature_deg_c, ...
            'p', recorded.dma_pressure_kpa);
        [mu_dma, lambda_dma] = TRANSP.FLPROPS(state, [], opts);
        compare_property(recorded.logged_viscosity_pa_s, mu_dma, tol, 'DMA viscosity');
        compare_property(recorded.logged_mean_free_path_nm, lambda_dma, tol, ...
            'DMA mean free path');
    end
    if positive_scalar(recorded.reference_temperature_k) && ...
            positive_scalar(recorded.reference_pressure_kpa)
        state = struct('temp', recorded.reference_temperature_k, ...
            'p', recorded.reference_pressure_kpa);
        [mu_ref, lambda_ref] = TRANSP.FLPROPS(state, [], opts);
        compare_property(recorded.reference_viscosity_pa_s, mu_ref, tol, ...
            'Reference viscosity');
        compare_property(recorded.reference_mean_free_path_nm, lambda_ref, tol, ...
            'Reference mean free path');
    end
    compare_property(recorded.reference_sutherland_k, ...
        params.gas.sutherland.s_k, tol, 'Reference Sutherland constant');
end
end

function yes = positive_scalar(value)
% "positive_scalar" checks a finite physical input.
yes = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value > 0;
end

function compare_property(recorded, predicted, tolerance, label)
if isempty(recorded), return; end
if abs(recorded/predicted - 1) > tolerance
    warning('sootMosaic:GAS:RecordedPropertyMismatch', ...
        '%s differs from the gas model by more than %.6g.', ...
        label, tolerance);
end
end
