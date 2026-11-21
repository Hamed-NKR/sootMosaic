% test_colaps_min.m
% Minimal, dependency-free driver to test COLAPS on one aggregate (pp0)
% The aggregate comes from the LD1 library named by post.colaps.aggregate_file
% in the task file selected by SOOTMOSAIC_MAIN_LD1_CONFIG.

clc; clear; close all;

%% ---- Load a single aggregate (pp0 must be N x 6) ----
if exist('pp0','var') ~= 1
    cfg_ld1 = UTILS.LOAD_MAIN_LD1_CONFIG;
    library_file = UTILS.POST_PATH(cfg_ld1, 'colaps.aggregate_file');
    if isfile(library_file)
        S = load(library_file, 'pp0');   % expects a variable named pp0 inside
        if isfield(S,'pp0')
            pp0 = S.pp0;
        else
            error('The LD1 library must contain variable "pp0".');
        end
        if iscell(pp0); pp0 = pp0{1}; end   % first aggregate of the library
    else
        error('No "pp0" in workspace and the LD1 library was not found.');
    end
end

% basic sanity check
assert(size(pp0,2) >= 5, 'pp0 must be N x 6 (id, d, x, y, z, subagg).');

%% ---- Collapse settings (start conservative, reproducible) ----
n_steps = 1e4; % keep it short at first; bump later if needed

specs = struct();
specs.k_spring = 0.2;   % global pull to center (keeps everyone moving inward)
specs.k_decay  = 1.0;   % no decay while debugging
specs.jit      = 0.0;   % turn noise off for reproducibility
specs.jit_decay= 0.98;  % unused since jit=0
specs.lj_eps   = 0.5;   % “stickiness” strength
specs.lj_decay = 0.93;  % velocity damping (friction-like)
specs.dt       = 0.002;  % time step (we’ll tune later)

opts = struct('showProgress', false);

%% ---- Run collapse ----
[pps, n_steps] = PAR.COLAPS_NEW(pp0, n_steps, specs, opts);

%% ---- Simple diagnostics over time (no heavy toolboxes) ----
N = size(pp0,1);
ncomp    = zeros(n_steps,1);
min_gap  = zeros(n_steps,1); % min (distance - (ri+rj))
max_step = zeros(n_steps,1); % max per-particle displacement since previous step

prevXYZ = [];
for k = 1:n_steps
    pp = pps{k};
    d  = pp(:,2);
    r  = d/2;
    xyz = pp(:,3:5);

    % pairwise distances
    dvec = permute(xyz,[1 3 2]) - permute(xyz,[3 1 2]);
    ds   = sqrt(sum(dvec.^2,3));
    ds(1:N+1:end) = inf;

    % “touching” distance ~ contact
    rij = r + r';
    min_gap(k) = min(ds(:) - rij(:));

    % adjacency if within 5% of contact
    touch = 1.15 * rij;
    A = (ds <= touch); A(1:N+1:end) = 0;
    % connected components via BFS/DFS (avoid graph() to be toolbox-free)
    ncomp(k) = count_components(A);

    % max per-particle displacement per step
    if ~isempty(prevXYZ)
        max_step(k) = max(vecnorm(xyz - prevXYZ, 2, 2));
    else
        max_step(k) = 0;
    end
    prevXYZ = xyz;
end

%% ---- Print quick summary ----
split_at = find(ncomp > 1, 1, 'first');
if isempty(split_at)
    fprintf('OK: no splits in %d steps.  minGap(min)=%.3g,  maxΔx(max)=%.3g\n', ...
        n_steps, min(min_gap), max(max_step));
else
    fprintf('SPLIT at step %d.  minGap(min)=%.3g,  maxΔx(max)=%.3g\n', ...
        split_at, min(min_gap(1:split_at)), max(max_step(1:split_at)));
end

%% ---- Quick visuals (initial / middle / final) ----
figure('Color','w','Position',[100 100 1100 350]);

subplot(1,3,1);  scatter_pp(pps{1});      title('Initial');    axis equal vis3d
subplot(1,3,2);  scatter_pp(pps{ceil(n_steps/2)}); title('Mid'); axis equal vis3d
subplot(1,3,3);  scatter_pp(pps{n_steps}); title('Final');      axis equal vis3d

% time series
figure('Color','w','Position',[100 500 1100 350]);
subplot(1,3,1); plot(ncomp,'LineWidth',1.5);     grid on; title('# components'); xlabel('step');
subplot(1,3,2); plot(min_gap,'LineWidth',1.5);   grid on; title('min gap (d - (ri+rj))'); xlabel('step');
subplot(1,3,3); plot(max_step,'LineWidth',1.5);  grid on; title('max per-step displacement'); xlabel('step');

%% ---- helpers ----
function scatter_pp(pp)
    % simple 3D scatter scaled by diameter
    d  = pp(:,2);
    xyz= pp(:,3:5);
    s  = 5*(d/median(d)).^2; % scale visually
    scatter3(xyz(:,1), xyz(:,2), xyz(:,3), s, d, 'filled'); view(30,20);
    xlabel('x'); ylabel('y'); zlabel('z'); box on;
end

function nc = count_components(A)
    % count connected components in an unweighted undirected adjacency A
    N = size(A,1);
    seen = false(N,1);
    nc = 0;
    for i = 1:N
        if ~seen(i)
            nc = nc + 1;
            % BFS
            q = i;
            seen(i) = true;
            while ~isempty(q)
                v = q(1); q(1) = [];
                nbrs = find(A(v,:));
                new  = nbrs(~seen(nbrs));
                seen(new) = true;
                q = [q, new]; %#ok<AGROW>
            end
        end
    end
end
