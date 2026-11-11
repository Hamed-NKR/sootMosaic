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

% Checkpoints written before the periodic collision search carry no domain
% size in the growth options, so it is set from the saved domain table.
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
    if strcmp(opts_mobil.mtd, 'interp')
        ensdata.da(k,1:2) = [geomean(pars_LD2.da), UTILS.GEOSTD(pars_LD2.da)];
    end
    
    if ensdata.n_agg(k) <= (r_n_agg(ind_dat) * ensdata.n_agg(1))

        % update projected area sizes (if necessary)
        if ~strcmp(opts_mobil.mtd, 'interp')
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

% save the final workspace
dt_final = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
save(fullfile(dir_wsp, strcat(cfg_results.final_prefix, '__', ...
    dt_final, '.mat')), '-v7.3')

end

