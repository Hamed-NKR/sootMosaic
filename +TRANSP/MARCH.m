function [pars, delt_base] = MARCH(pars, fl, params_const)
% "MARCH" solves the equation of motion of particles and finds their new...
%   ...location and velocity alomg with their marching time scale.
%   
% Note: For more detail on the equations used here, see a tutorial on...
%   ...on Langevin Dynamics modeling of aerosols by Suresh &...
%   ...Gopalakrishnan (2021).
% ----------------------------------------------------------------------- %
% 
% Input/Outputs:
%   pars: The particle information structure/class
%   fl: Fluid info structure
%   params_const: Problem's table of constant physical properties
%   delt_base: The universal marching times-step for the poulation of...
%   ...particles
% ----------------------------------------------------------------------- %

% Total number of (independent) particles
if isa(pars, 'AGG')
    n_par = length(pars);
else
    n_par = size(pars.n, 1);
end

kb = params_const.Value(3); % Boltzmann's constant (j/k)

% Compiling/copying properties locally
m = cat(1, pars.m);
v = cat(1, pars.v);
f = cat(1, pars.f);
delt = cat(1, pars.delt);

% All particles march over the smallest per-particle time step,
% which belongs to the particle with the smallest mobility diameter.
% The Langevin solution uses this common step without displacement
% rescaling, preserving each particle's long-time diffusivity.
% The returned delt_base is the elapsed time for this call.
delt_base = min(delt); % Baseline time step
delt = repmat(delt_base, n_par, 1); % Common time step for all particles

% Solving the equation of motion
x_march = f .* delt ./ m; % Time step over the relaxation time m / f
var_march = exp(x_march);
th_march = (1 - (var_march.^(-1))) ./ (1 + (var_march.^(-1))); % tanh(x/2)
vv_march = 1 - (var_march.^(-2)); % 1 - exp(-2x)
rr_march = x_march - 2 .* th_march; % x - 2 tanh(x/2)
% Below x = 2 these forms lose precision by cancellation. The term...
%   ...x - 2 tanh(x/2) is close to x^3 / 12 there and can even turn...
%   ...negative below x of about 1e-5. For x below 2 the terms use tanh,...
%   ...expm1 and the exact form 2 (u cosh(u) - sinh(u)) / cosh(u) with...
%   ...u = x/2. The difference u cosh(u) - sinh(u) is the infinite sum...
%   ...of u^(2k+1) / ((2k+1) (2k-1)!) for k from 1, all terms positive, and...
%   ...ten terms give accuracy to a few eps on both sides of x = 2.
ind_s = x_march < 2;
if any(ind_s)
    u = x_march(ind_s) ./ 2;
    u2 = u.^2;
    k = (10 : -1 : 1)';
    c_ser = 1 ./ ((2 .* k + 1) .* factorial(2 .* k - 1)); % Coefficients
    s_ser = zeros(size(u));
    for i = 1 : numel(k)
        s_ser = c_ser(i) + u2 .* s_ser; % Horner evaluation in u^2
    end
    th_march(ind_s) = tanh(u);
    vv_march(ind_s) = -expm1(-2 .* x_march(ind_s));
    rr_march(ind_s) = 2 .* u .* u2 .* s_ser ./ cosh(u);
end
% Finding the velocity march
rv_dot_rv = (3 .* kb .* fl.temp ./ m) .* vv_march;
par_v_new = v .* (var_march.^(-1)) + sqrt(rv_dot_rv ./ 3) .*...
    [randn(n_par, 1), randn(n_par, 1), randn(n_par, 1)];
% Finding the position march
rr_dot_rr = (6 .* m .* kb .* fl.temp ./ (f.^2)) .* rr_march;
dr = (m ./ f) .* (par_v_new + v) .* th_march +...
    sqrt(rr_dot_rr ./ 3) .* [randn(n_par, 1), randn(n_par, 1),...
    randn(n_par, 1)];  % Translation vectors

% Updating the locations for the structure/class of aggregates
if isa(pars, 'AGG')
    for i = 1 : n_par
        pars(i).v = par_v_new(i, :);
    end
    pars = pars.TRANSLATE(dr);
    
else
    % Moving the primary particles and their center of mass
    [pars.pp, pars.r] = PAR.TRANSLATE(pars.pp, pars.r, pars.n, dr);
    pars.v = par_v_new; % Renewing the velocities
end

end

