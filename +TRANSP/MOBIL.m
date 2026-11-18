function [pars, opts] = MOBIL(pars, fl, params_const, opts)
% "MOBIL" calculates the transport properties of aggregates.
% ----------------------------------------------------------------------- %
%
% Inputs/Outputs:
%     pars: Aggregates information structure containing their...
%         ...geometrical and diffusive properties
%     fl: Fluid info structure
%     params_const: Problem's table of constant physical properties
%     opts: Mobility calculation options. opts.mtd names the method,...
%         ...'sorensen_eq17' (Eq. 17 of reference 8 of the README at...
%         ...every N, the default, also named 'continuum'),...
%         ...'sorensen_backbone' (TRANSP.CONTINUUM_DM 'backbone'),...
%         ...'interp' (TRANSP.DIAMOBIL, the adjusted sphere of Rogak et...
%         ...al. 1993, p. 28) or 'free_molecular' (dm = da, the free...
%         ...molecular limit in which the drag follows the orientation...
%         ...averaged projected area, Sorensen 2011, p. 771, and Rogak et...
%         ...al. 1993, pp. 27 and 28, references 8 and 9 of the README)....
%         ...opts.continuum_diameter and opts.root_solve are the...
%         ...continuum diameter and root solve of TRANSP.DIAMOBIL...
%         ...(defaults 'fixed_075dg' and 'start_point_7658971')....
%         ...opts.projection names the projected area of 'interp' and...
%         ...'free_molecular', 'euler_7658971' (PAR.PROJECTION, the...
%         ...default) or 'isotropic' (PAR.PROJECTION_CACHE), with...
%         ...opts.proj_points points and opts.proj_orientations...
%         ...orientations per aggregate (defaults 100 and 5),...
%         ...opts.proj_replicates rotated direction sets (default 1)...
%         ...and opts.proj_cache (default false) to reuse the areas of...
%         ...unchanged aggregates, kept in opts.proj_cache_data. A...
%         ...warning is shown once per run when the relative standard...
%         ...error of an isotropic area exceeds opts.proj_tol (default...
%         ...Inf, no check), and proj_rse_max records the largest value....
%         ...With one set no standard error is available,...
%         ...proj_rse_max is NaN and the check is off, so a finite...
%         ...proj_tol with fewer than two sets stops with...
%         ...sootMosaic:MOBIL:InvalidProjection. The standard error of...
%         ...a few sets is a diagnostic of the resolution, not a...
%         ...confidence interval. With 4 sets it has 3 degrees of...
%         ...freedom, and a nominal two-sided 95 percent interval would...
%         ...need 3.182 standard errors under normality (see...
%         ...PAR.PROJECTION_ISO). Loaded configs give proj_tol 'none'...
%         ...for no check, which arrives here as Inf. An isotropic...
%         ...area of an aggregate of several primaries that is not...
%         ...positive and finite, or whose standard error is not finite,...
%         ...stops with sootMosaic:MOBIL:UnresolvedProjection. The...
%         ...isotropic projection takes the particle structure only, not...
%         ...AGG objects. The projected areas that the main scripts save...
%         ...for methods without da come from PAR.PROJECTION with the...
%         ...projection section of the config, not from these options....
%         ...opts.slip names the slip...
%         ...correction model of TRANSP.CUNNINGHAM (default...
%         ...'per_caller_7658971'). The returned copy records in...
%         ...step_warned whether the step-limit warning was shown, so...
%         ...callers that pass it back get the warning once per run.
% ----------------------------------------------------------------------- %

% Initializing call options
call_defaults = UTILS.CALL_DEFAULTS();

% Initializing the calculation method
if ~exist('opts', 'var') 
    opts = struct();
end
if (~isfield(opts, 'mtd')) || isempty(opts.mtd)
    opts.mtd = call_defaults.mobil.mtd;
end
if (~isfield(opts, 'continuum_diameter')) || isempty(opts.continuum_diameter)
    opts.continuum_diameter = call_defaults.mobil.continuum_diameter;
end
if (~isfield(opts, 'root_solve')) || isempty(opts.root_solve)
    opts.root_solve = call_defaults.mobil.root_solve;
end

% initialize projected area variables
if (~isfield(opts, 'projection')) || isempty(opts.projection)
    opts.projection = call_defaults.mobil.projection;
end
if (~isfield(opts, 'proj_cache')) || isempty(opts.proj_cache)
    opts.proj_cache = call_defaults.mobil.proj_cache;
end
if (~isfield(opts, 'proj_points')) || isempty(opts.proj_points)
    opts.proj_points = call_defaults.mobil.proj_points;
end
if (~isfield(opts, 'proj_orientations')) || isempty(opts.proj_orientations)
    opts.proj_orientations = call_defaults.mobil.proj_orientations;
end
if (~isfield(opts, 'proj_replicates')) || isempty(opts.proj_replicates)
    opts.proj_replicates = call_defaults.mobil.proj_replicates;
end
if (~isfield(opts, 'proj_tol')) || isempty(opts.proj_tol)
    opts.proj_tol = call_defaults.mobil.proj_tol;
end
if (~isfield(opts, 'proj_warned')) || isempty(opts.proj_warned)
    opts.proj_warned = call_defaults.mobil.proj_warned;
end

% initialize slip correction model variable
if (~isfield(opts, 'slip')) || isempty(opts.slip)
    opts.slip = call_defaults.mobil.slip;
end

% initialize time-step sensitivity variable
if (~isfield(opts, 'c_dt')) || isempty(opts.c_dt)
    opts.c_dt = call_defaults.mobil.c_dt;
end
if ~isnumeric(opts.c_dt) || ~isreal(opts.c_dt) || ~isscalar(opts.c_dt) || ...
        ~isfinite(opts.c_dt) || opts.c_dt <= 0
    error('sootMosaic:MOBIL:InvalidTimeStepFactor', ...
        'opts.c_dt must be a positive finite real numeric scalar.')
end

% initialize the limit on the displacement per time step
if (~isfield(opts, 'step_frac')) || isempty(opts.step_frac)
    opts.step_frac = call_defaults.mobil.step_frac;
end
if ~isnumeric(opts.step_frac) || ~isreal(opts.step_frac) || ...
        ~isscalar(opts.step_frac) || ~isfinite(opts.step_frac) || ...
        opts.step_frac <= 0
    error('sootMosaic:MOBIL:InvalidStepFraction', ...
        'opts.step_frac must be a positive finite real numeric scalar.')
end
if (~isfield(opts, 'step_policy')) || isempty(opts.step_policy)
    opts.step_policy = call_defaults.mobil.step_policy;
end
if ~any(strcmp(opts.step_policy, {'warn', 'cap'}))
    error('sootMosaic:MOBIL:InvalidStepPolicy', ...
        'opts.step_policy must be warn or cap.')
end
if (~isfield(opts, 'step_warned')) || isempty(opts.step_warned)
    opts.step_warned = call_defaults.mobil.step_warned;
end

% Total number of (independent) particles
if isa(pars, 'AGG')
    n_par = length(pars);
else
    n_par = size(pars.n, 1);
end

% Calculating mobility properties

% Mobility size
npp = cat(1, pars.n);
switch opts.mtd
    case {'sorensen_eq17', 'continuum'} % 'continuum' is the earlier name
        dm = TRANSP.CONTINUUM_DM(npp, cat(1, pars.dg), [], 'eq17');
    case 'sorensen_backbone'
        dm = TRANSP.CONTINUUM_DM(npp, cat(1, pars.dg), ...
            single_primary_diameter(pars, npp), 'backbone');
    case {'interp', 'free_molecular'}
        [da, opts] = projected_diameter(pars, opts);
        if strcmp(opts.mtd, 'interp')
            opts_dia = struct('continuum', opts.continuum_diameter, ...
                'root', opts.root_solve);
            if strcmp(opts.continuum_diameter, 'sorensen_backbone')
                opts_dia.npp = npp;
                opts_dia.dpp1 = single_primary_diameter(pars, npp);
            end
            dm = TRANSP.DIAMOBIL(pars.dg, da, fl, opts.slip, opts_dia);
        else
            dm = da; % free molecular limit of the projected area
        end
    otherwise
        error('sootMosaic:MOBIL:UnknownMethod', ['Unknown mobility ', ...
            'method %s. Known methods are sorensen_eq17 (or continuum), ', ...
            'sorensen_backbone, interp and free_molecular.'], opts.mtd)
end

% Cunningham correction factor (-)
kn_kin = (2 * fl.lambda) ./ dm; % Gas (kinetic) Knudsen number 2 lambda / dm (-)
cc = TRANSP.CUNNINGHAM(dm, fl.lambda, opts.slip, 'MOBIL');

% Aggregate mass (kg) and smallest primary diameter (m)
m = ones(n_par,1);
dpp_min = inf;
for i = 1 : n_par
    if isa(pars, 'AGG')
        m(i) = (params_const.Value(1) * pi / 6) * sum((pars(i).pp.d(:)).^3);
        dpp_min = min(dpp_min, min(pars(i).pp.d(:)));
    else
        m(i) = (params_const.Value(1) * pi / 6) * sum((pars.pp{i}(:,2)).^3);
        dpp_min = min(dpp_min, min(pars.pp{i}(:,2)));
    end
end

rho = (6 / pi) * (m ./ (dm.^3)); % Effective density (kg/m3)
tau = rho .* (dm.^2) .* cc ./ (18 * fl.mu); % Response (relaxation) time (s)
kb = params_const.Value(3); % Boltzmann's constant (j/k)
f = (3 * pi * fl.mu) .* dm ./ cc; % Friction factor (-)
delt = opts.c_dt * f .* (dm.^2) ./ (6 * kb * fl.temp); % Marching timestep
diff = (kb * (fl.temp)) ./ f; % Particle diffusivity (m2/s)

% Check the displacement per time step against the collision scale.
% MARCH moves every particle over the common step delt_base = min(delt).
% For the Langevin step of Ermak and Buckholz (1980) with velocities in...
    % ...equilibrium, the mean square 3D displacement of particle i over...
    % ...a step t is 6 D_i tau_i (x - 1 + exp(-x)) with x = t / tau_i,...
    % ...which is 6 D_i t in the diffusive limit and 3 kT t^2 / m_i in...
    % ...the ballistic limit. The RMS relative displacement s_rel of the...
    % ...two particles that move most is kept below step_frac times the...
    % ...smallest primary diameter, since CONNECT captures a pair whose...
    % ...nearest primaries are within one primary diameter.
% s_rel grows with t, so the cap policy finds the step t_cap that gives...
    % ...s_rel = step_frac dpp_min and scales all steps by t_cap /...
    % ...delt_base, which is c_dt_max / c_dt.
if n_par > 1
    s_lim2 = (opts.step_frac * dpp_min)^2; % Squared step limit (m2)
    s_rel = sqrt(rel_step2(min(delt), tau, diff));
    if s_rel^2 > s_lim2
        t_cap = fzero(@(t) rel_step2(t, tau, diff) - s_lim2, ...
            [0, min(delt)], optimset('TolX', 1e-12 * min(delt)));
            % Relative tolerance, since the default absolute one is...
            % ...coarse for steps near 1e-9 s
        c_dt_max = opts.c_dt * t_cap / min(delt);
        if strcmp(opts.step_policy, 'cap')
            delt = delt .* (t_cap / min(delt));
        elseif ~opts.step_warned
            warning('sootMosaic:MOBIL:LargeStep', ['The RMS relative step ', ...
                'is %.3g smallest primary diameters, above step_frac ', ...
                '%.3g. c_dt %.4g exceeds c_dt_max %.4g. Set step_policy ', ...
                'to cap to limit the step. This warning is shown once ', ...
                'per run.'], s_rel / dpp_min, opts.step_frac, ...
                opts.c_dt, c_dt_max)
            opts.step_warned = true;
        end
    end
end

% Single-particle diffusive Knudsen number 2 (m kT)^0.5 / (f dm). The pair...
    % ...and nearest-neighbor forms of the literature are in TRANSP.KNUDSEN.
lambda = sqrt(m .* kb .* (fl.temp)) ./ f; % Length (m kT)^0.5 / f (m)
kn_diff = 2 * lambda ./ dm; % Diffusive Knudsen number (-)

% Updating the transport properties for the structure/class of aggregates
if isa(pars, 'AGG')
    for i = 1 : n_par
        pars(i).rho = rho(i);
        pars(i).m = m(i);
        pars(i).tau = tau(i);
        pars(i).f = f(i);
        pars(i).delt = delt(i);
        pars(i).diff = diff(i);
        pars(i).lambda = lambda(i);
        pars(i).kn_kin = kn_kin(i);
        pars(i).kn_diff = kn_diff(i);
    end

else
    pars.rho = rho;
    pars.m = m;
    pars.dm = dm;
    if any(strcmp(opts.mtd, {'interp', 'free_molecular'})); pars.da = da; end
    pars.tau = tau;
    pars.f = f;
    pars.delt = delt;
    pars.diff = diff;
    pars.lambda = lambda;
    pars.kn_kin = kn_kin;
    pars.kn_diff = kn_diff;
end

end

function s2 = rel_step2(t, tau, d_coef)
% "rel_step2" returns the mean square relative 3D displacement over a step...
%   ...t of the two particles with the largest displacements, from the...
%   ...equilibrium Langevin displacement variance (Ermak and Buckholz 1980).
x = t ./ tau;
g = x + expm1(-x); % x - 1 + exp(-x)
ind_s = x < 1e-2; % Series below 1e-2 avoids cancellation
g(ind_s) = x(ind_s).^2 / 2 - x(ind_s).^3 / 6 + x(ind_s).^4 / 24 - ...
    x(ind_s).^5 / 120;
s2 = sum(maxk(6 .* d_coef .* tau .* g, 2));
end

function [da, opts] = projected_diameter(pars, opts)
% "projected_diameter" returns the projected area equivalent diameters...
%   ...of the method set in opts.projection.
switch opts.projection
    case 'euler_7658971'
        if opts.proj_cache
            error('sootMosaic:MOBIL:InvalidProjection', ['The projected ', ...
                'area cache needs the isotropic projection.'])
        end
        opts_proj.tbar = 'off';
        da = 2 * sqrt(PAR.PROJECTION(pars, [], opts.proj_points, ...
            opts.proj_orientations, [], opts_proj) / pi);
    case 'isotropic'
        if ~isfield(opts, 'proj_cache_data')
            opts.proj_cache_data = [];
        end
        opts_iso = struct('n_pts', opts.proj_points, 'n_ori', ...
            opts.proj_orientations, 'n_rep', opts.proj_replicates, ...
            'use_cache', opts.proj_cache);
        has_se = opts.proj_replicates >= 2; % independent sets give se
        if ~has_se && isfinite(opts.proj_tol)
            error('sootMosaic:MOBIL:InvalidProjection', ['proj_tol ', ...
                'needs at least two proj_replicates, one set gives no ', ...
                'standard error. Set proj_tol to Inf or use more sets.'])
        end
        [pa, se, opts.proj_cache_data] = PAR.PROJECTION_CACHE(pars, ...
            opts.proj_cache_data, opts_iso);
        is_1 = (pars.n(:) == 1); % a sphere has da = dp exactly
        bad = ~is_1 & ~(isfinite(pa) & pa > 0);
        if has_se
            bad = bad | (~is_1 & ~isfinite(se));
        end
        if any(bad)
            error('sootMosaic:MOBIL:UnresolvedProjection', ['The ', ...
                'isotropic projected area of %d aggregates is not a ', ...
                'positive finite value or has no finite standard error ', ...
                '(first aggregate %d, %d primaries). Raise proj_points or ', ...
                'proj_orientations.'], nnz(bad), find(bad, 1), ...
                pars.n(find(bad, 1)))
        end
        da = 2 * sqrt(pa / pi);
        da(is_1) = cellfun(@(p) p(1, 2), pars.pp(is_1));
        if has_se
            rse = max(se ./ pa);
        else
            rse = NaN; % no standard error, the check is off
        end
        opts.proj_rse_max = rse;
        if rse > opts.proj_tol && ~opts.proj_warned
            warning('sootMosaic:MOBIL:ProjectionNotConverged', ['The ', ...
                'relative standard error of a projected area is %.3g, ', ...
                'above proj_tol %.3g. Raise proj_points or ', ...
                'proj_orientations. This warning is shown once per run.'], ...
                rse, opts.proj_tol)
            opts.proj_warned = true;
        end
    otherwise
        error('sootMosaic:MOBIL:UnknownProjection', ['Unknown projected ', ...
            'area method %s. Known methods are euler_7658971 and ', ...
            'isotropic.'], opts.projection)
end
end

function dpp1 = single_primary_diameter(pars, npp)
% "single_primary_diameter" returns the primary diameter of each...
%   ...single-primary aggregate and NaN for the others.
dpp1 = nan(size(npp));
for i = find(npp(:)' == 1)
    if isa(pars, 'AGG')
        dpp1(i) = pars(i).pp.d(1);
    else
        dpp1(i) = pars.pp{i}(1, 2);
    end
end
end
