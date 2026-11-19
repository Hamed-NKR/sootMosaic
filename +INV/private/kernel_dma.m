function [k, info] = kernel_dma(dm, voltage, cfg, draw, caller)
% "kernel_dma" combines existing charge, DMA, loss and counting functions.
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 23 and 28).
% Diameters are (m), voltage is (V), response is dimensionless.
% Adopted charge accumulation from +kernel/gen_smps.m.
% Repository: https://github.com/tsipkens/odias
% Commit: 8de95745486b01cf5ede0b186d044656eb3fde33
% License: GNU General Public License, version 3 (GPL-3).
% Source attribution: Sipkens (2020).
% Modified 18 Nov 2026: shared accumulation with existing physical calls,...
%     ...recorded polarity, charge tails, external paths and loss diagnostics.
% The complete GPL-3 text is supplied in the repository LICENSE file.
require_recorded(cfg, {'scan.neutralizer_on', 'scan.particle_polarity'}, caller);
if ~isequal(cfg.scan.neutralizer_on, true) || ...
        ~any(strcmp(cfg.scan.particle_polarity, {'positive', 'negative'}))
    error(['sootMosaic:' caller ':ChargingState'], ...
        'Require a recorded active neutralizer and particle polarity.');
end
s = cfg.si.scan;
t = s.dma_temperature_deg_c;
p = s.dma_pressure_kpa;
[mu, ~, cc, params] = INV.GAS(t, p, dm, cfg);
opts = struct('Model', draw.charge_model, ...
    'RangePolicy', cfg.charging.range_policy, ...
    'TailPolarity', cfg.scan.particle_polarity, ...
    'TailTolerance_frac', cfg.charging.tail_tol, 'Config', cfg);
charges = draw.charge_e;
if isempty(charges) && ~isempty(cfg.charging.max_charge)
    q = cfg.charging.max_charge;
    if ~isscalar(q) || ~isfinite(q) || q < 2 || q ~= fix(q)
        error(['sootMosaic:' caller ':Charge'], 'Adaptive charge cap must be an integer of at least two.');
    end
    opts.MaxCharge_e = q;
end
[f, charge_info] = INV.CHARGE_FRAC(dm, charges, t, p, opts);
charges = charge_info.charge_e;
sign_value = 1;
if strcmp(cfg.scan.particle_polarity, 'negative'), sign_value = -1; end
if any(sign(charges) ~= sign_value) || any(~isfinite(f(:)))
    error(['sootMosaic:' caller ':Charge'], 'Charge states must match the recorded polarity.');
end
z1 = params.constants.e_c*cc./(3*pi*mu*dm);
k = zeros(numel(voltage), numel(dm));
for j = 1:numel(charges)
    for i = 1:numel(voltage)
        omega = INV.TFER_DMA(abs(charges(j))*z1, voltage(i), ...
            charges(j), cfg, draw.diffusing_1);
        k(i, :) = k(i, :) + f(:, j).'.*omega(:).';
    end
end
[internal, internal_info] = INV.PENETRATION(dm, t, p, ...
    s.dma_aerosol_flow_lpm, cfg, 'internal');
[dma, dma_info] = INV.PENETRATION(dm, t, p, ...
    s.dma_aerosol_flow_lpm, cfg, 'dma_proxy');
sample_flow = s.dma_aerosol_flow_lpm + s.dma_sheath_flow_lpm - ...
    s.dma_excess_flow_lpm;
if sample_flow ~= s.dma_aerosol_flow_lpm
    [outlet, outlet_info] = INV.PENETRATION(dm, t, p, sample_flow, cfg, 'tube', ...
        cfg.si.penetration.outlet_hose_length_m);
    internal = reshape(prod(internal_info.components(:, 1:3), 2), ...
        size(dm)).*outlet;
    internal_info.components(:, 4) = outlet(:);
    internal_info.delta_dep(:, 4) = outlet_info.delta_dep;
    internal_info.lower_branch(:, 4) = outlet_info.lower_branch;
    internal_info.upper_branch(:, 4) = outlet_info.upper_branch;
    internal_info.diffusional = internal;
end
internal_info.path_flow_m3_s = [repmat(s.dma_aerosol_flow_lpm, 1, 3), sample_flow];
flow_ratio = s.dma_aerosol_flow_lpm/sample_flow;
loss = internal.*dma;
tubes = cfg.si.penetration.tubes;
if isempty(tubes)
    error(['sootMosaic:' caller ':ExternalPath'], ...
        'Record external tubes, including an explicit zero length when absent.');
end
require_recorded(cfg, {'penetration.tubes'}, caller);
for j = 1:numel(tubes)
    if iscell(tubes), tube = tubes{j}; else, tube = tubes(j); end
    loss = loss.*INV.PENETRATION(dm, t, p, tube.flow_lpm, cfg, ...
        'tube', tube.length_m*draw.penetration_length_scale_1);
end
[eta, cpc_info] = INV.CPC_EFF(dm, cfg);
if draw.cpc_scale_1 < 1-cpc_info.unity_margin_ratio
    error(['sootMosaic:' caller ':EfficiencyDraw'], 'Efficiency draw exceeds the sourced deficit.');
end
loss = loss.*eta*draw.cpc_scale_1;
k = flow_ratio*k.*loss(:).';
info = struct('charge', charge_info, 'loss_1', loss, ...
    'internal', internal_info, 'dma', dma_info, 'cpc', cpc_info, ...
    'aerosol_over_sample_flow_1', flow_ratio);
end
