function dae = AERODYN(pp, dm, rho0, fl, slip, params)
% "AERODYN" calculates the aerodynamic diameter from mass and mobility...
%   ...diameter of aggregates.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%   pp: a series of 2d arrays containing primary particle data for...
%       ...different aggregates.    
%     params: Resolved SI profile sections (optional)
%   dm: mobility diameter of aggregates
%   rho0: material density for fractal aggregates (kg/m3)
%   fl: fluid flow characteristics structure (lambda in m), needed by...
%       ...the 'kim2005' slip correction
%   slip: Slip correction model of TRANSP.CUNNINGHAM, default...
%       ...'per_caller_7658971'. That model uses rho0 as the reference...
%       ...density, so a sphere at dm = d has dae = d. The other models...
%       ...use the aerodynamic reference density of 1000 kg/m3.
% ----------------------------------------------------------------------- %
% 
% Outputs:
%   dae: Aerodynamic diameter of aggregates
% ----------------------------------------------------------------------- %

if nargin < 6 || isempty(params)
    params = UTILS.MODEL_DEFAULTS('article1_7658971');
end
if ~exist('slip', 'var') || isempty(slip)
    slip = 'per_caller_7658971'; % Per-caller slip coefficients
end
if exist('fl', 'var') && isfield(fl, 'lambda') && ~isempty(fl.lambda)
    lambda = fl.lambda;
elseif strcmp(slip, 'per_caller_7658971')
    lambda = []; % not used by this model in AERODYN
else
    error('sootMosaic:AERODYN:MissingMeanFreePath', ['The slip ', ...
        'correction model %s needs the gas mean free path fl.lambda.'], ...
        char(slip))
end

% Cunningham correction factor (x: particle diameter in m)
cc = @(x) TRANSP.CUNNINGHAM(x, lambda, slip, 'AERODYN', params.slip);

dae0 = PAR.EQUIV(pp); % initial guess (volume-equivalent diameter)

dae = zeros(length(dae0),1); % allocate aerodynamic diameter array

m = zeros(length(dae0),1); % allocate aggregate mass array

% The per_caller_7658971 model keeps the default tolerance of fzero...
    % ...(TolX = eps). The other models set TolX to eps times the initial...
    % ...guess, an absolute tolerance scaled by the diameter.
legacy = strcmp(slip, 'per_caller_7658971');
opts_fz = optimset('TolX', eps);
if legacy
    rho_ref = rho0; % reference density of the article1_7658971 equation
else
    rho_ref = params.constants.rho_aero_ref_kg_m3; % Density (kg/m3)
end

for i = 1 : length(dae0)
    
    % calculate aggregate mass
    m(i) = rho0 * (pi/6) * sum(pp{i}(:,2) .^ 3);
    
    % define nonlinear equation
    df = @(x) x - sqrt((6/(pi*rho_ref)) * (m(i)/dm(i)) * (cc(dm(i))/cc(x)));
    
    % solve the equation
    if legacy
        dae(i) = fzero(df, dae0(i));
    else
        opts_fz.TolX = eps * dae0(i);
        dae(i) = fzero(df, dae0(i), opts_fz);
    end

end

end

