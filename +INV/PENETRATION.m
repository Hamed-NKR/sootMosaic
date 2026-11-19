function [eta, info] = PENETRATION(dm_m, temp_k, pressure_pa, ...
        flow_m3_s, cfg, path_kind, length_m)
% "PENETRATION" calculates diffusion losses up to the counter inlet.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     dm_m: Positive mobility diameters, any shape (m)
%     temp_k: Gas temperature, scalar (K)
%     pressure_pa: Gas pressure, scalar (Pa)
%     flow_m3_s: Aerosol flow through each selected path, scalar (m3/s)
%     cfg: Resolved inversion configuration with loss coefficients
%     path_kind: tube, dma_proxy, internal, software or aac. The internal...
%         ...selection contains four paths; software adds its DMA path....
%         ...Use dma_proxy times internal for the proposed DMA treatment
%     length_m: Nonnegative scalar length, required for tube only (m)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     eta: Penetration with the shape of dm_m (-)
%     info: Diffusivity (m2/s), deposition parameter, component penetration,...
%         ...both branch values, lengths (m), factors and provenance labels....
%         ...Component rows follow dm_m(:); columns follow length_m
% ----------------------------------------------------------------------- %
% Method: Johnson et al. (2018, Eqs. 12-14); Karlsson and Martinsson...
%     ...(2003, Eqs. 13-14, Tables 1 and 6); Wiedensohler et al. (2012,...
%     ...Table 1). Software equivalent lengths from the SMPS software...
%     ...manual version 11 (Appendix B, p. B-14).
% Reimplementation from the published equations. The DMA factor 0.98...
%     ...and length 7.1 m are a proposed cylindrical proxy for the 3081A,...
%     ...not a calibration of that instrument. The software path product...
%     ...uses separate tube penetrations. Counter internal losses belong...
%     ...to counting efficiency. Tube bore cancels in L D/Q.

if nargin < 7, length_m = []; end
if ~positive(dm_m) || isempty(dm_m) || ~positive(flow_m3_s) || ...
        ~isscalar(flow_m3_s)
    fail('InvalidInput', 'Diameters and aerosol flow must be positive.');
end
try
    p = cfg.si.penetration;
    fit = cfg.si.transfer.aac;
    model = cfg.penetration.model;
catch
    fail('InvalidConfig', 'Pass a resolved inversion configuration.');
end
if ~strcmp(model, 'karlsson_martinsson2003')
    fail('InvalidModel', 'Unknown penetration model.');
end
proxy = false;
entrance_factor = 1;
switch path_kind
    case 'tube'
        if ~isnumeric(length_m) || ~isreal(length_m) || ...
                ~isscalar(length_m) || ~isfinite(length_m) || length_m < 0
            fail('InvalidLength', 'Tube length must be nonnegative.');
        end
        lengths = double(length_m);
    case 'dma_proxy'
        lengths = required(p, 'dma_length_m');
        entrance_factor = required(p, 'dma_electrostatic_factor');
        proxy = true;
    case {'internal', 'software'}
        internal_lengths = [required(p, 'impactor_length_m'), ...
            required(p, 'platform_neutralizer_length_m'), ...
            required(p, 'inlet_hose_length_m'), ...
            required(p, 'outlet_hose_length_m')];
        if strcmp(path_kind, 'software')
            lengths = [required(p, 'dma_equivalent_length_m'), ...
                internal_lengths];
        else
            lengths = internal_lengths;
        end
    case 'aac'
        lengths = required(fit, 'effective_length_m');
        entrance_factor = required(fit, 'entrance_efficiency');
    otherwise
        fail('InvalidPath', 'Unknown penetration path.');
end
if entrance_factor > 1
    fail('InvalidFactor', 'Penetration factors cannot exceed one.');
end
try
    [mu, ~, cc, params] = INV.GAS(temp_k, pressure_pa, dm_m, cfg);
catch err
    fail('InvalidGasState', err.message);
end
diffusivity = params.constants.kb_j_k*temp_k*cc./(3*pi*mu*dm_m);
x = diffusivity(:)*lengths/flow_m3_s;
weights = fit.deposition_upper_weights;
rates = fit.deposition_upper_rates;
coeff = fit.deposition_lower_coefficients;
if ~positive(weights) || numel(weights) ~= 3 || ...
        ~positive(rates) || numel(rates) ~= 3 || ...
        ~isnumeric(coeff) || ~isreal(coeff) || numel(coeff) ~= 4 || ...
        any(~isfinite(coeff(:)))
    fail('InvalidCoefficients', ...
        'Require the published deposition coefficients.');
end
branch_point = required(fit, 'deposition_switch');
lower_branch = coeff(1) + coeff(2)*x.^(2/3) + coeff(3)*x + coeff(4)*x.^(4/3);
upper_branch = zeros(size(x));
for k = 1:3
    upper_branch = upper_branch + weights(k)*exp(-rates(k)*x);
end
components = lower_branch;
use_upper = x >= branch_point;
components(use_upper) = upper_branch(use_upper);
if any(~isfinite(x(:))) || any(~isfinite(components(:))) || ...
        any(components(:) < 0) || any(components(:) > 1)
    fail('NumericRange', 'Inputs exceed the finite penetration range.');
end
eta = reshape(entrance_factor*prod(components, 2), size(dm_m));
info = struct('diffusivity_m2_s', diffusivity, 'delta_dep', x, ...
    'components', components, 'lower_branch', lower_branch, ...
    'upper_branch', upper_branch, ...
    'length_m', lengths, 'entrance_factor_ratio', entrance_factor, ...
    'diffusional', reshape(prod(components, 2), size(dm_m)), ...
    'graetz_leading_coefficient_ratio', weights(1), ...
    'dma_proxy', proxy, 'endpoint', 'counter inlet', 'path', path_kind);
if proxy
    info.provenance = 'Proposed cylindrical proxy; not a 3081A calibration';
else
    info.provenance = 'Published equivalent-length tube treatment';
end
end

function value = required(s, key)
% "required" reads a positive scalar in SI.
if ~isfield(s, key) || ~isscalar(s.(key)) || ~positive(s.(key))
    fail('MissingInput', ['A positive SI value is required for ' key '.']);
end
value = double(s.(key));
end

function yes = positive(value)
% "positive" checks finite positive numeric values.
yes = isnumeric(value) && isreal(value) && ...
    all(isfinite(value(:))) && all(value(:) > 0);
end

function fail(reason, message)
% "fail" reports an invalid penetration input.
error(['sootMosaic:PENETRATION:' reason], '%s', message);
end
