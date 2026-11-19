function [c, d] = kernel_settings(cfg, draw, caller)
% "kernel_settings" applies one declared physical draw to resolved settings.
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 23 and 28).
% Inputs are resolved settings and dimensionless draw multipliers; tau is (s).
c = cfg;
d = struct('dma_aerosol_scale_1', 1, 'dma_sheath_scale_1', 1, ...
    'dma_excess_scale_1', 1, 'aac_sample_scale_1', 1, ...
    'aac_sheath_scale_1', 1, 'aac_sizing_scale_1', 1, ...
    'aac_width_scale_1', 1, 'penetration_length_scale_1', 1, ...
    'cpc_scale_1', 1, 'tau_s_s', cfg.scan_response.tau_s_s, ...
    'charge_model', cfg.charging.model, 'charge_e', [], ...
    'diffusing_1', true);
if ~isstruct(draw) || ~isscalar(draw)
    error(['sootMosaic:' caller ':Draw'], 'Require a scalar kernel draw.');
end
names = fieldnames(draw);
for k = 1:numel(names)
    key = names{k};
    if ~isfield(d, key)
        error(['sootMosaic:' caller ':Draw'], 'Unknown kernel draw field %s.', key);
    end
    d.(key) = draw.(key);
end
names = fieldnames(d);
for k = 1:numel(names)
    key = names{k};
    if endsWith(key, '_scale_1')
        v = d.(key);
        if ~isnumeric(v) || ~isreal(v) || ~isscalar(v) || ~isfinite(v) || v <= 0
            error(['sootMosaic:' caller ':Draw'], 'Require positive draw multipliers.');
        end
    end
end
if d.cpc_scale_1 > 1 || ~islogical(d.diffusing_1) || ~isscalar(d.diffusing_1) || ...
        ~isnumeric(d.tau_s_s) || ~isreal(d.tau_s_s) || ...
        ~isscalar(d.tau_s_s) || ~isfinite(d.tau_s_s) || d.tau_s_s < 0
    error(['sootMosaic:' caller ':Draw'], 'Invalid efficiency, diffusion or mixing draw.');
end
flows = {'dma_aerosol', 'dma_sheath', 'dma_excess', 'aac_sample', 'aac_sheath'};
for k = 1:numel(flows)
    field = [flows{k} '_flow_lpm'];
    c.si.scan.(field) = c.si.scan.(field)*d.([flows{k} '_scale_1']);
end
lengths = {'dma_length_m', 'dma_equivalent_length_m', ...
    'platform_neutralizer_length_m', 'inlet_hose_length_m', ...
    'outlet_hose_length_m', 'impactor_length_m'};
for k = 1:numel(lengths)
    c.si.penetration.(lengths{k}) = ...
        c.si.penetration.(lengths{k})*d.penetration_length_scale_1;
end
c.si.transfer.aac.effective_length_m = ...
    c.si.transfer.aac.effective_length_m*d.penetration_length_scale_1;
end
