function [omega, info] = TFER_DMA(zp, voltage_v, charge, cfg, diffusing)
% "TFER_DMA" calculates the cylindrical DMA transfer probability.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     zp: Positive electrical mobility magnitude, any shape (m2/(V s))
%     voltage_v: Positive classifier voltage magnitude, scalar (V)
%     charge: Nonzero integer charge state, scalar (-)
%     cfg: Resolved inversion configuration. SI scan flows are aerosol,...
%         ...sheath and excess; sample flow follows from conservation....
%         ...Temperature, pressure and geometry belong to the DMA
%     diffusing: Logical scalar, optional, defaults to true (-)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     omega: Probability per entering particle, with the shape of zp (-)
%     info: Flow ratios, geometry factor, centroid mobility and diffusion...
%         ...standard deviation in normalized mobility, sigma_z_ratio (-)
% ----------------------------------------------------------------------- %
% Method: Stolzenburg (2018, Eqs. 10, 16, 18, 26, 29-34, 39-40 and...
%     ...A2-A5, A15); Sipkens et al. (2020, part I, Eqs. 5-9).
% Reimplementation from the published equations.

if nargin < 5, diffusing = true; end
if ~islogical(diffusing) || ~isscalar(diffusing)
    fail('InvalidDiffusion', 'The diffusion switch must be logical.');
end
if ~positive(zp) || isempty(zp) || ~positive(voltage_v) || ...
        ~isscalar(voltage_v) || ~isnumeric(charge) || ~isreal(charge) || ...
        ~isscalar(charge) || ~isfinite(charge) || charge == 0 || ...
        charge ~= fix(charge)
    fail('InvalidInput', ...
        'Require positive mobility, voltage and integer charge.');
end
try
    s = cfg.si.scan;
    g = cfg.si.geometry;
    model = cfg.transfer.dma.model;
catch
    fail('InvalidConfig', 'Pass a resolved inversion configuration.');
end
if ~strcmp(model, 'stolzenburg2018_diffusing')
    fail('InvalidModel', 'Unknown DMA transfer model.');
end
require_recorded(cfg, {'scan.dma_aerosol_flow_lpm', ...
    'scan.dma_sheath_flow_lpm', 'scan.dma_excess_flow_lpm', ...
    'scan.dma_temperature_deg_c', 'scan.dma_pressure_kpa'}, 'TFER_DMA');
qa = required(s, 'dma_aerosol_flow_lpm');
qc = required(s, 'dma_sheath_flow_lpm');
qm = required(s, 'dma_excess_flow_lpm');
qs = qc + qa - qm;
if qs <= 0
    fail('InvalidFlows', 'The conserved sample flow must be positive.');
end
r1 = required(g, 'dma_inner_radius_m');
r2 = required(g, 'dma_outer_radius_m');
len = required(g, 'dma_length_m');
if r2 <= r1
    fail('InvalidGeometry', 'The outer radius must exceed the inner.');
end
temp = required(s, 'dma_temperature_deg_c');
pressure = required(s, 'dma_pressure_kpa');
try
    [~, ~, ~, params] = INV.GAS(temp, pressure, [], cfg);
catch err
    fail('InvalidGasState', err.message);
end
beta_ratio = (qs + qa) / (qm + qc);
delta = (qs - qa) / (qs + qa);
if beta_ratio >= 1
    fail('InvalidFlows', 'The aerosol to sheath ratio must be below one.');
end

% Integrating between the aerosol mid-streamlines of Eq. 30
c = (r1/r2)^2;
lc = log(c);
ac = 1 / (-(1+c)*lc/2 - (1-c));
fc = @(x) ac*((1-c)*log(x) - (1-x)*lc);
fcum = @(x) -ac*((1-x).^2*lc/(2*(1-c)) + x.*log(x) + 1-x);
xa = streamline(beta_ratio*(1-delta)/(2*(1+beta_ratio)), c, fcum);
xs = streamline(1-beta_ratio*(1+delta)/(2*(1+beta_ratio)), c, fcum);
ic = integral(@(x) fc(x).^2.*x, xs, xa, ...
    'AbsTol', 1e-13, 'RelTol', 1e-12) / (1-c);
g_dma = (4*(1+beta_ratio)^2*ic/(1-c) + (xa-xs)/(len/r2)^2)*(-lc/2);
zstar = (qc+qm)*log(r2/r1)/(4*pi*len*voltage_v);
ratio = double(zp)/zstar;
sigma = zeros(size(ratio));
if diffusing
    sigma = sqrt(ratio*g_dma*params.constants.kb_j_k*temp / ...
        (abs(charge)*params.constants.e_c*voltage_v));
end

% Evaluating the trapezoid and its decaying diffusion correction
offset = ratio - 1;
omega = max(0, min(beta_ratio-abs(offset), beta_ratio*(1-abs(delta)))) / ...
    (beta_ratio*(1-delta));
if diffusing
    edges = [beta_ratio, -beta_ratio, beta_ratio*delta, -beta_ratio*delta];
    signs = [1, 1, -1, -1];
    correction = zeros(size(ratio));
    for k = 1:4
        arg = abs(offset + edges(k))./(sqrt(2)*sigma);
        ec = zeros(size(arg));
        active = arg < 26;
        u = arg(active);
        ec(active) = exp(-u.^2)/sqrt(pi) - u.*erfc(u);
        correction = correction + signs(k)*ec;
    end
    omega = omega + sigma.*correction/(sqrt(2)*beta_ratio*(1-delta));
    omega = max(0, min(min(1, qs/qa), omega));
end
if any(~isfinite(omega(:))) || ~isfinite(g_dma) || ...
        ~isfinite(zstar) || any(~isfinite(sigma(:)))
    fail('NumericRange', 'Inputs exceed the finite transfer range.');
end
info = struct('beta', beta_ratio, 'delta', delta, 'g_dma', g_dma, ...
    'zstar_m2_v_s', zstar, 'sigma_z_ratio', sigma, ...
    'sample_flow_m3_s', qs, 'xa_ratio', xa, 'xs_ratio', xs, ...
    'ic_difference_ratio', ic, 'diffusing', diffusing);
end

function x = streamline(target, c, fcum)
% "streamline" locates a cumulative flow fraction by bisection.
lo = c;
hi = 1;
for k = 1:64
    mid = lo + (hi-lo)/2;
    if fcum(mid) > target, lo = mid; else, hi = mid; end
end
x = lo + (hi-lo)/2;
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
% "fail" reports an invalid transfer input.
error(['sootMosaic:TFER_DMA:' reason], '%s', message);
end
