function tab = TABGEN(dpp, dm, slip, coefficients)
% "TABGEN" generates a table of properties for typical fractal soot...
%   ...according to the well-established literature correlations that...
%   ...can be found in Sipkens et al. (2023)'s review on soot morphology.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%   dpp: Mean primary particle diameter (nm)
%   dm: Mobility diameter (nm)
%     coefficients: Resolved slip section, or [a b c] (optional)
%   slip: Slip correction model of TRANSP.CUNNINGHAM. Only...
%       ...'per_caller_7658971' is supported.
% ----------------------------------------------------------------------- %
%
% Outputs:
%   tab: table of morphological properties of soot using the benchmark...
%       ...correlations.
% ----------------------------------------------------------------------- %

if nargin < 4, coefficients = []; end

%%% define constants %%%
dpp_100 = 17.8; % universal correlation prefactor
D_TEM = 0.35; % universal correlation exponent
k_a = 1.16; % screening prefactor
alpha_a = 1.1; % screening exponent
k_f = 1.3; % fractal prefactor
D_f = 1.78; % fractal dimension
rho_m = 1860; % estimate for continuum density of black carbon
k_m = 2.93; % mass-mobility prefactor
D_m = 2.48; % mass-mobility exponent
rho_0 = 1000; % normalized density for aerodynamic diameter
magg_100 = 2.93e-6; % aggregate mass at 100 nm mobility diameter
%%%%%%%%%%%%%%%%%%%%%%%%

if ~exist('slip', 'var') || isempty(slip)
    slip = 'per_caller_7658971'; % Per-caller slip coefficients
end
if ~(ischar(slip) || isStringScalar(slip)) || ...
        ~strcmp(slip, 'per_caller_7658971')
    error('sootMosaic:TABGEN:ModelUnavailable', ...
        ['UTILS.TABGEN supports only the ', ...
        'per_caller_7658971 slip model.'])
end

da = exp(log(dpp/dpp_100) / D_TEM + log(100)); % projected area diameter (nm)

npp = k_a * (da ./ dpp).^alpha_a; % number of primaries (not rounded!)

Rg = exp(log(npp/k_f) / D_f + log(dpp/2)); % radius of gyration (nm)

magg1 = 1e18 * rho_m * pi * (npp .* (1e-9*dpp).^3) / 6; % mass obtained from geometry (fg)

magg2 = magg_100 * (dm / 100).^D_m; % mass from scaling law (fg)

dve = 1e9 * (6 * (1e-18*magg2) / (rho_m * pi)).^(1/3); % volume equivalent diameter (nm)

rho_eff = (6 * (1e18*magg2)) ./ (pi * (1e-9*dm).^3); % effective density (kg/m3)

x = (rho_m./rho_eff).^(1/3) .* (cunningham_nm(dve, coefficients) ./ ...
    cunningham_nm(dm, coefficients)); % shape factor

% trial and error for aerodynamic diameter
dae_i = 2 * rand(length(dm),1) .* dm; % initial guess
dae = dm;
ind = 0;
while any(abs((dae - dae_i) ./ dae_i) > 0.01) && (ind < 1e3)
    if ind~=0; dae_i = dae; end
    
    dae = dm.^((D_m - 1) / 2) .* sqrt((cunningham_nm(dm, coefficients) ./ ...
        cunningham_nm(dae_i, coefficients)) *...
        6 * k_m / (pi * rho_0));
    
    ind = ind + 1;
end

tab = table(dm, magg1, magg2, rho_eff, dve, x, dae, dpp,...
    npp, Rg); % make the table of properties

end

function cc = cunningham_nm(dp, coefficients)
% Cunningham correction factor of the per_caller_7658971 model, which...
    % ...takes the diameters in nm as TABGEN passes them

lambda = 6.8e-8; % ambient air mean free path (m)

cc = TRANSP.CUNNINGHAM(dp, lambda, 'per_caller_7658971', 'TABGEN', ...
    coefficients);

end
