function RESUME_LD2_V3(checkpoint_folder, checkpoint_file)
%RESUME_LD2_V3 Resume a saved LD2 checkpoint.

if nargin < 1
    checkpoint_folder = '';
end
if nargin < 2
    checkpoint_file = '';
end

checkpoint_folder = char(checkpoint_folder);
checkpoint_file = char(checkpoint_file);

clc
clf('reset')
close all

if isempty(strtrim(checkpoint_folder))
    checkpoint_folder = input('Checkpoint folder: ', 's');
end
if isempty(strtrim(checkpoint_file))
    checkpoint_file = input('Checkpoint file name: ', 's');
end
checkpoint_path = fullfile(checkpoint_folder, checkpoint_file);

if ~isfile(checkpoint_path)
    error('sootMosaic:ResumeLD2:MissingCheckpoint', ...
        'Checkpoint file not found: %s', checkpoint_path)
end

load(checkpoint_path);

% Restore the random number generator so that the resumed run continues the
% random sequence of the uninterrupted run. Checkpoints written before the
% generator state was stored fall back to a seed derived from the configured
% seed and the checkpoint iteration, which is reproducible but not identical
% to the uninterrupted run. Without either, the run stays unseeded.
if exist('rng_state', 'var') && ~isempty(rng_state) %#ok<NODEF> loaded from the checkpoint
    rng(rng_state);
elseif exist('cfg_sim', 'var') && isfield(cfg_sim, 'rng_seed') && ... %#ok<NODEF>
        ~isempty(cfg_sim.rng_seed)
    rng(mod(cfg_sim.rng_seed + k, 2^32));
    warning('sootMosaic:ResumeLD2:NoRngState', ['Checkpoint has no stored ', ...
        'generator state. Reseeded from simulation.rng_seed plus the ', ...
        'checkpoint iteration.'])
else
    warning('sootMosaic:ResumeLD2:Unseeded', ['Checkpoint has no stored ', ...
        'generator state and no seed. The resumed run is not reproducible.'])
end

% Checkpoints without model options run with the article1_7658971 profile,
% the ambient preset they hold and a fluid pressure of 101325 Pa.
if ~exist('cfg_ld2', 'var')
    cfg_ld2 = struct();
end
if ~isfield(cfg_ld2, 'model') || isempty(cfg_ld2.model)
    cfg_ld2.model = UTILS.MODEL_PROFILE('article1_7658971', 'LD2', ...
        struct(), struct('BuiltinOnly', true));
    if exist('opts_fl', 'var') && isfield(opts_fl, 'amb') && ...
            ~isempty(opts_fl.amb)
        cfg_ld2.model.fluid_properties = char(opts_fl.amb);
    end
    if exist('opts_mobil', 'var') && isfield(opts_mobil, 'mtd') && ...
            ~isempty(opts_mobil.mtd) %#ok<NODEF>
        cfg_ld2.model.mobility = method_name(opts_mobil.mtd);
    end
    warning('sootMosaic:ResumeLD2:NoModelProfile', ['Checkpoint has no ', ...
        'model options. The run continues with the article1_7658971 ', ...
        'profile.'])
end
if ~isfield(fl, 'p') || isempty(fl.p) %#ok<NODEF>
    fl.p = 101325;
end

% Checkpoints with model options but no slip correction model keep the
% constants of each caller at 7658971, as the code that wrote them did.
if ~isfield(cfg_ld2.model, 'slip_correction') || ...
        isempty(cfg_ld2.model.slip_correction)
    cfg_ld2.model.slip_correction = 'per_caller_7658971';
    warning('sootMosaic:ResumeLD2:NoSlipModel', ['Checkpoint has no ', ...
        'slip correction model. The run continues with ', ...
        'per_caller_7658971.'])
end
if exist('opts_mobil', 'var') && (~isfield(opts_mobil, 'slip') || ...
        isempty(opts_mobil.slip))
    opts_mobil.slip = cfg_ld2.model.slip_correction;
end

% Checkpoints with model options but no mobility options ran the method of
% their mobility options with the continuum diameter 0.75 dg and fzero from
% one start point, the settings of 7658971.
if ~isfield(cfg_ld2.model, 'mobility') || isempty(cfg_ld2.model.mobility)
    if exist('opts_mobil', 'var') && isfield(opts_mobil, 'mtd') && ...
            ~isempty(opts_mobil.mtd)
        cfg_ld2.model.mobility = method_name(opts_mobil.mtd);
    else
        cfg_ld2.model.mobility = 'sorensen_eq17'; % default of TRANSP.MOBIL
    end
    cfg_ld2.model.continuum_diameter = 'fixed_075dg';
    cfg_ld2.model.root_solve = 'start_point_7658971';
    warning('sootMosaic:ResumeLD2:NoMobilityModel', ['Checkpoint has no ', ...
        'mobility options in its model. The run continues with ', ...
        'fixed_075dg and start_point_7658971.'])
end
if exist('opts_mobil', 'var')
    if ~isfield(opts_mobil, 'continuum_diameter') || ...
            isempty(opts_mobil.continuum_diameter)
        opts_mobil.continuum_diameter = cfg_ld2.model.continuum_diameter;
    end
    if ~isfield(opts_mobil, 'root_solve') || isempty(opts_mobil.root_solve)
        opts_mobil.root_solve = cfg_ld2.model.root_solve;
    end
end

% Checkpoints with model options but no projected area options computed the
% areas with PAR.PROJECTION at every call, with 100 points and 5
% orientations, the settings of 7658971.
proj_fields = {'projection', 'proj_cache', 'proj_points', ...
    'proj_orientations', 'proj_replicates', 'proj_tol'};
if ~isfield(cfg_ld2.model, 'projection') || isempty(cfg_ld2.model.projection)
    model_a1 = UTILS.MODEL_PROFILE('article1_7658971', 'LD2', ...
        struct(), struct('BuiltinOnly', true));
    for i_f = 1 : numel(proj_fields)
        cfg_ld2.model.(proj_fields{i_f}) = model_a1.(proj_fields{i_f});
    end
    warning('sootMosaic:ResumeLD2:NoProjectionModel', ['Checkpoint has ', ...
        'no projected area options in its model. The run continues with ', ...
        'euler_7658971 without cache.'])
end
if exist('opts_mobil', 'var')
    for i_f = 1 : numel(proj_fields)
        if ~isfield(opts_mobil, proj_fields{i_f}) || ...
                isempty(opts_mobil.(proj_fields{i_f}))
            opts_mobil.(proj_fields{i_f}) = cfg_ld2.model.(proj_fields{i_f});
        end
    end
end

% A model without a diagnostics option continues without the Knudsen...
    % ...diagnostics, since its ensdata holds none
if ~isfield(cfg_ld2.model, 'knudsen_diagnostics') || ...
        isempty(cfg_ld2.model.knudsen_diagnostics)
    cfg_ld2.model.knudsen_diagnostics = false;
    warning('sootMosaic:ResumeLD2:NoKnudsenModel', ['Checkpoint has no ', ...
        'Knudsen diagnostics option in its model. The run continues ', ...
        'without the diagnostics.'])
end
if ~exist('opts_diag', 'var') || ~isfield(opts_diag, 'knudsen') || ...
        isempty(opts_diag.knudsen) %#ok<NODEF>
    opts_diag.knudsen = cfg_ld2.model.knudsen_diagnostics;
end
if opts_diag.knudsen && ~isfield(ensdata, 'kn_pair') %#ok<NODEF>
    ensdata.kn_pair = nan(size(ensdata.tau)); % no values before the resume
    ensdata.knn = nan(size(ensdata.tau));
    ensdata.knn_defined = false(size(ensdata.t));
end

% A model without an initial velocity sampler is recorded as...
    % ...mean_speed_7658971, the resumed steps draw no initial velocities
if ~isfield(cfg_ld2.model, 'initial_velocity') || ...
        isempty(cfg_ld2.model.initial_velocity)
    cfg_ld2.model.initial_velocity = 'mean_speed_7658971';
    warning('sootMosaic:ResumeLD2:NoVelocityModel', ['Checkpoint has no ', ...
        'initial velocity sampler in its model. It is recorded as ', ...
        'mean_speed_7658971.'])
end

% Completing absent parameter records from the fixed built-in profile
if ~isfield(cfg_ld2, 'model_params') || isempty(cfg_ld2.model_params)
    [~, ~, cfg_ld2.model_params, cfg_ld2.model_source] = ...
        UTILS.MODEL_PROFILE('article1_7658971', 'LD2', struct(), ...
        struct('BuiltinOnly', true));
    warning('sootMosaic:RESUME_LD2_V3:NoModelParameters', ...
        ['Checkpoint has no parameter record. The parameter record ', ...
        'uses the fixed built-in profile.']);
end

% set the domain size from the saved domain table for checkpoints...
    % ...saved without it in the growth options
opts_grow.dom_size = params_domain.Value(2:4);

k = k + 1;

fprintf('\n');

while (k <= k_max) && (ind_dat <= n_dat) && (length(pars_LD2.n) > 1)
    % check criteria to stop simulations

    % solve transport equation
    [pars_LD2, delt] = TRANSP.MARCH(pars_LD2, fl, params_const);

    % apply periodic boundary conditions
    pars_LD2 = TRANSP.PBC(params_domain.Value(2:4), pars_LD2);

    % join colliding particles
    pars_LD2 = COL.GROW(pars_LD2, opts_grow);

    % count number of subaggregates
    pars_LD2.n_hyb = COL.HYBRIDITY(pars_LD2.pp, pars_LD2.n);
    
    % update characteristic sizes
    pars_LD2 = PAR.SIZING(pars_LD2);
    
    % update mobility properties
    [pars_LD2, opts_mobil] = TRANSP.MOBIL(pars_LD2, fl, params_const, opts_mobil);
    
    % advance the clock by the step MARCH took, not by the next step
    ensdata.t(k) = ensdata.t(k-1) + delt;
    ensdata.n_agg(k) = length(pars_LD2.pp);
    ensdata.tau(k,1:2) = [mean(pars_LD2.tau), std(pars_LD2.tau)];
    ensdata.kn_kin(k,1:2) = [mean(pars_LD2.kn_kin), std(pars_LD2.kn_kin)];
    ensdata.kn_diff(k,1:2) = [mean(pars_LD2.kn_diff), std(pars_LD2.kn_diff)];
    ensdata.dpp(k,1:2) = [geomean(pars_LD2.dpp_g(:,1)), UTILS.GEOSTD(pars_LD2.dpp_g(:,1))];
    ensdata.sigmapp(k,1:2) = [geomean(pars_LD2.dpp_g(:,2)), UTILS.GEOSTD(pars_LD2.dpp_g(:,2))];
    ensdata.dm(k,1:2) = [geomean(pars_LD2.dm), UTILS.GEOSTD(pars_LD2.dm)];
    if any(strcmp(opts_mobil.mtd, {'interp', 'free_molecular'}))
        ensdata.da(k,1:2) = [geomean(pars_LD2.da), UTILS.GEOSTD(pars_LD2.da)];
    end
    if opts_diag.knudsen
        kn = TRANSP.KNUDSEN(pars_LD2, fl, params_const, opts_mobil);
        ensdata.kn_pair(k,1:2) = [mean(kn.kn_pair), std(kn.kn_pair)];
        ensdata.knn(k,1:2) = [mean(kn.knn), std(kn.knn)];
        ensdata.knn_defined(k) = kn.knn_defined;
    end

    if ensdata.n_agg(k) <= (r_n_agg(ind_dat) * ensdata.n_agg(1))

        % update projected area sizes (if necessary)
        % (methods without da use PAR.PROJECTION with the projection
        % section of the config, not the mobility projection options)
        if ~any(strcmp(opts_mobil.mtd, {'interp', 'free_molecular'}))
            pars_LD2.da = 2 * sqrt(PAR.PROJECTION(pars_LD2, [], n_mc_prj,...
                n_ang_prj, [], opts_prj) / pi);
        end

        % save data of individual aggregates in selected times
        parsdata(ind_dat).pp = pars_LD2.pp;
        parsdata(ind_dat).npp = pars_LD2.n;
        parsdata(ind_dat).dpp = pars_LD2.dpp_g(:,1);
        parsdata(ind_dat).sigmapp = pars_LD2.dpp_g(:,2);
        parsdata(ind_dat).da = pars_LD2.da;
        parsdata(ind_dat).dm = pars_LD2.dm;
        parsdata(ind_dat).dg = pars_LD2.dg;
        parsdata(ind_dat).n_hyb = pars_LD2.n_hyb;

        % saved mobility diameters must match the current population
        UTILS.CHECK_SAVED_DM(parsdata(ind_dat).dm, pars_LD2.dm);

        ind_dat = ind_dat + 1; % update data saving index

    end

    % save workspace once in a while (to recover iterations in case they...
    % ...are interrupted)
    if mod(k, checkpoint_interval) == 1
        rng_state = rng; %#ok<NASGU> saved below, restored on the next resume
        dt = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss')); % current date and time
        save(fullfile(dir_wsp, strcat(cfg_results.checkpoint_prefix, '__', ...
            dt, '.mat')), '-v7.3')
    end

    UTILS.TEXTBAR([k, k_max]); % update progress textbar
    
    k = k + 1; % update iteration index
    
end

% Remove unused elements from the data storage structures
parsdata(ind_dat:end) = [];
ensdata.t(k:end) = [];
ensdata.n_agg(k:end) = [];
ensdata.tau(k:end,:) = [];
ensdata.kn_kin(k:end,:) = [];
ensdata.kn_diff(k:end,:) = [];
ensdata.dpp(k:end,:) = [];
ensdata.sigmapp(k:end,:) = [];
ensdata.da(k:end,:) = [];
ensdata.dm(k:end,:) = [];
if isfield(ensdata, 'kn_pair')
    ensdata.kn_pair(k:end,:) = [];
    ensdata.knn(k:end,:) = [];
    ensdata.knn_defined(k:end) = [];
end

% save the final workspace
dt_final = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
save(fullfile(dir_wsp, strcat(cfg_results.final_prefix, '__', ...
    dt_final, '.mat')), '-v7.3')

end

function name = method_name(mtd)
% "method_name" returns the name of a mobility method, with 'continuum'...
%   ...given as 'sorensen_eq17'.
name = char(mtd);
if strcmp(name, 'continuum')
    name = 'sorensen_eq17';
end
end
