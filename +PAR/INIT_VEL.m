function pars_v = INIT_VEL(pp, n_pp ,fl_temp, params_const, method)
% "INIT_VEL" draws size dependent initial velocities of the (independent)...
%     ...particles with the sampler named in method.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%     pp: Primary particle information cell array
%     n_pp: Number distribution of primaries
%     fl_temp: Flame temperature
%     params_const: Problem's table of constant physical properties
%     method: Velocity sampler (optional), 'maxwell_boltzmann' or...
%         ...'mean_speed_7658971' (the default)
% ----------------------------------------------------------------------- %
% 
% Output:
%     pars_v: Primary particle velocities
% ----------------------------------------------------------------------- %
%
% 'maxwell_boltzmann' draws the three velocity components of each...
%     ...particle independently from a normal distribution with zero mean...
%     ...and variance kT / m, the Maxwell-Boltzmann distribution of a...
%     ...particle in a gas at temperature T. The mean kinetic energy is...
%     ...1.5 kT and the speed has the mean (8 kT / (pi m))^0.5...
%     ...(Eggersdorfer and Pratsinis 2014, p. 76, README reference 12)....
%     ...It takes three standard normal numbers per particle, all x...
%     ...components first, then y and z.
% 'mean_speed_7658971' is the sampler of the article1_7658971 profile....
%     ...Every particle moves at the mean speed (8 kT / (pi m))^0.5 in the...
%     ...direction of the polar angle pi U1 and the azimuth 2 pi U2, with U1...
%     ...and U2 uniform on [0, 1], two uniform numbers per particle. Its...
%     ...kinetic energy is 4 kT / pi at every particle and its directions...
%     ...are not uniform on the sphere.
% ----------------------------------------------------------------------- %

if nargin < 5 || isempty(method)
    method = 'mean_speed_7658971';
end

rho_bc = params_const.Value(1); % Black Carbon's bulk density (kg/m3)
kb = params_const.Value(3); % Boltzmann's constant (j/k)

n_par = size(n_pp,1); % Total number of (independent) particles
pp = cell2mat(pp);
m_pp = (pi *  rho_bc / 6) .* ((pp(:,2)).^3); % mass of primaries
m_pp = mat2cell(m_pp, n_pp);
m_par = zeros(n_par,1);
for i = 1 : n_par
    m_par(i) = sum(m_pp{i}); % Total mass of (independent) particles
end 

switch method
    case 'maxwell_boltzmann'
        % Standard deviation of each velocity component (m/s)
        v_sd = sqrt(kb * fl_temp ./ m_par);
        pars_v = v_sd .* [randn(n_par, 1), randn(n_par, 1), randn(n_par, 1)];

    case 'mean_speed_7658971'
        vmb_mean_par = ((8 * kb * fl_temp / pi) ./ m_par).^(1/2); % Maxwell-...
            % ...Boltzmann's mean velocity of the (independent) particles

        % Random spherical angles for initial movements of the primaries
        theta_pp = pi * rand(n_par,1);
        phi_pp = 2 * pi * rand(n_par,1);

        pars_v = zeros(n_par,3); % Initialization of the velocity array
        % Assigning random movements to the primaries
        pars_v(:,1) = vmb_mean_par .* sin(theta_pp) .* cos(phi_pp);
        pars_v(:,2) = vmb_mean_par .* sin(theta_pp) .* sin(phi_pp);
        pars_v(:,3) = vmb_mean_par .* cos(theta_pp);

    otherwise
        error('sootMosaic:INIT_VEL:UnknownMethod', ['Unknown initial ', ...
            'velocity sampler %s. Known samplers are maxwell_boltzmann ', ...
            'and mean_speed_7658971.'], method)
end

end
