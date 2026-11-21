function report = TEST_INV_SOLVERS()
% "TEST_INV_SOLVERS" checks inversion operators using synthetic inputs.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: One name and pass flag per case. Failures raise...
%         ...sootMosaic:QA:InvSolversFailed. Random cases use fixed seeds
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 26, 38, 42-46);
%     ...Huckle and Sedlacek (2012, Eqs. 1-2); Twomey (1975, Eq. 7);
%     ...Markowski (1987, Eq. 7); Bardsley and Fox (2012).

tests = {@order_zero, @order_one, @order_two, @active_set, ...
    @trust_bound, @two_stages, @stage_shapes, @posterior, ...
    @exponential, @partial_grid, @mixture, @delta_linear, @delta_gm, ...
    @gibbs_one, @gibbs_two, @gibbs_correlated, @gibbs_tail, ...
    @cross_checks, @smoothing, @zero_rows, @physical_inputs, @refusals, ...
    @mean_square, @twomey_stopping, @twomey_scaling, ...
    @smoothing_limits, @twomark_stopping, @stage_floor, @gibbs_cap, ...
    @small_covariances, @upstream_demo};
names = {'order zero closed form', 'order one closed form', ...
    'order two closed form', 'independent active set', 'trust zero bound', ...
    'explicit equal-order stages', 'unequal stage row counts', ...
    'posterior covariance and Gaussian draws', ...
    'exponential factor and solve', ...
    'partial-grid exterior', 'total variance mixture', ...
    'linear delta and Monte Carlo', 'broad geometric mean delta', ...
    'one-dimensional truncated moments', ...
    'two-dimensional truncated moments', ...
    'correlated orthant moments', 'far-tail truncated draws', ...
    'multiplicative cross-checks', 'smoothing stencil', ...
    'zero response rows', 'existing kernel and variance calls', 'refusals', ...
    'source mean square and empty selection', 'multiplicative stopping', ...
    'row-scaled stopping', 'smoothing stopping and limits', ...
    'outer limit and roughness rollback', 'active stage-two floor', ...
    'sampler extension to unresolved cap', 'small covariance validation', ...
    'pinned upstream demo with deterministic kernel'};
report = repmat(struct('name', '', 'pass', false), numel(tests), 1);
saved = rng;
restore = onCleanup(@() rng(saved));
try
    for k = 1:numel(tests)
        report(k).name = names{k};
        tests{k}();
        report(k).pass = true;
    end
catch err
    error('sootMosaic:QA:InvSolversFailed', ...
        '%s: %s', ...
        err.identifier, err.message);
end
end

function order_zero()
orders(0, eye(3), [1; 2; 1]/2);
end

function order_one()
orders(1, [1 0 0; -1 1 0; 0 -1 1; 0 0 -1], [5; 8; 5]/7);
end

function order_two()
orders(2, [-1 .5 0; .5 -1 .5; 0 .5 -1], [18; 28; 18]/17);
end

function orders(order, expected_l, expected_x)
[x, l, q, info] = INV.TIKHONOV(eye(3), [1; 2; 1], 1, order);
near(full(l), expected_l, 1e-12);
near(x, expected_x, 1e-9);
near(x, (eye(3)+expected_l'*expected_l)\[1; 2; 1], 1e-9);
near(full(q), eye(3)+expected_l'*expected_l, 1e-12);
check(info.stages_count == 1 && ~info.cross_check_1);
end

function active_set()
a = [1 1; 0 1]; b = [0; 1];
aug = [a; eye(2)]; rhs = [b; 0; 0];
x = INV.TIKHONOV(a, b, 1, 0);
near(x, enumerate_faces(aug, rhs), 1e-10);
near(x, [0; 1/3], 1e-10);
near(INV.LSQ(aug, rhs, [], 'algebraic'), [-1; 2]/5, 1e-10);
end

function trust_bound()
a = [1 1; 0 1; 1 0; 0 1]; b = [0; 1; 0; 0];
x = INV.LSQ(a, b, [], 'trust-region-reflective');
near(x, enumerate_faces(a, b), 1e-7);
check(all(x >= 0));
x = INV.LSQ(a, b, [-10; -10], 'interior-point');
near(x, [0; 1/3], 1e-7);
end

function two_stages()
b = [1; 2; 1];
[x, last, q, info] = INV.TIKHONOV(eye(3), b, 1, [2 2], 3, 2, .01);
first = [18; 28; 18]/17;
l = [-1 .5 0; .5 -1 .5; 0 .5 -1]*diag(1./first);
near(info.stage_cm3_inv(:, 1), first, 1e-9);
near(full(last), l, 1e-9);
near(x, enumerate_faces([eye(3); l], [b; zeros(3, 1)]), 1e-9);
near(full(q), eye(3)+l'*l, 1e-9);
[c, returned] = INV.POSTERIOR(eye(3), last);
near(c, (eye(3)+l'*l)\eye(3), 1e-9);
near(returned, q, 1e-12);
check(info.stages_count == 2 && info.cross_check_1);
check(norm(q-(eye(3)+INV.TIKHONOV_LPR(2, 3)'* ...
    INV.TIKHONOV_LPR(2, 3)), 'fro') > .1);
end

function stage_shapes()
[x, l, ~, info] = INV.TIKHONOV(eye(3), [1; 2; 1], ...
    [1 2], [0 1], 3, 2, .1);
check(isequal(size(l), [4, 3]) && info.stages_count == 2);
near(x, enumerate_faces([eye(3); l], [1; 2; 1; zeros(4, 1)]), 1e-9);
end

function posterior()
[c, q] = INV.POSTERIOR(eye(2), diag([1, 2]));
near(c, diag([.5, .2]), 1e-12);
near(q, diag([2, 5]), 1e-12);
rng(27, 'twister');
draws = chol(c, 'lower')*randn(2, 40000);
near(cov(draws', 1), c, .015);
end

function stage_floor()
[x, last, q, info] = INV.TIKHONOV(eye(2), [0; 2], ...
    [1 2], [0 0], 2, 2, .5);
near(info.stage_cm3_inv(:, 1), [0; 1], 1e-12);
near(full(last), diag([4, 2]), 1e-12);
near(full(q), diag([17, 5]), 1e-12);
near(x, [0; 2/5], 1e-12);
check(info.stages_count == 2 && info.cross_check_1);
end

function exponential()
g = INV.Grid({[1, 2]});
[l, d, c] = INV.EXP_DIST_LPR(log10(2)/log(2), g);
near(d, [0 1; 1 0]*log(2), 1e-12);
near(c, [1 .5; .5 1], 1e-12);
near(l'*l, [4 -2; -2 4]/3, 1e-12);
[x, last, q, info] = INV.EXP_DIST(eye(2), [1; 1], ...
    1, log10(2)/log(2), g);
near(x, [.6; .6], 1e-9);
near(q, eye(2)+last'*last, 1e-12);
check(info.stages_count == 1);
end

function partial_grid()
g = INV.Grid({[1 2], [1 2]});
p = INV.PartialGrid(g, [true; false; true; true]);
l = INV.TIKHONOV_LPR(1, p);
near(full(l'*l), [4 -1 0; -1 4 -1; 0 -1 4], 1e-12);
l = INV.TIKHONOV_LPR(2, p);
near(full(l'*l), [2.25 -1 0; -1 2.5 -1; 0 -1 2.25], 1e-12);
end

function mixture()
[m, c] = INV.POST_MIX([1, 3], reshape([2, 4], 1, 1, 2), [.25, .75]);
near(m, 2.5, 1e-12); near(c, 4.25, 1e-12);
[m, c] = INV.POST_MIX([1, 3], reshape([2, 4], 1, 1, 2), [1, 0]);
near(m, 1, 1e-12); near(c, 2, 1e-12);
end

function delta_linear()
x = [10; 20; 10]; c = diag([1, 4, 1]);
[v, s] = INV.DELTA_PROP(x, c, @linear_stat, true(3, 1));
near(v, 60, 1e-12); near(s, 18, 1e-12);
rng(270, 'twister');
draws = x+chol(c, 'lower')*randn(3, 40000);
check(abs(var([1 2 1]*draws, 1)/s-1) < .05);
end

function [v, j] = linear_stat(x, window)
j = [1 2 1].*window'; v = j*x;
end

function delta_gm()
x = [10; 20; 10]; c = diag([1, 4, 1]);
[v, s] = INV.DELTA_PROP(x, c, @gm_stat, true(3, 1));
near(v, 2, 1e-12); near(s, log(2)^2/200, 1e-12);
rng(271, 'twister');
draws = x+chol(c, 'lower')*randn(3, 40000);
gm = exp([0 log(2) log(4)]*draws./sum(draws, 1));
check(abs(var(gm, 1)/s-1) < .1);
end

function [v, j] = gm_stat(x, window)
w = double(window); z = [0; log(2); log(4)];
total = w'*x; center = (w.*z)'*x/total;
v = exp(center); j = (v*w.*(z-center)/total)';
end

function options = sampler_options()
options = struct('burn_count', 500, 'batch_count', 4000, ...
    'max_draws_count', 16000, 'seed_1', 27);
end

function gibbs_one()
[draws, info] = INV.TGIBBS(1, 0, sampler_options());
z = draws(:);
near(mean(z), sqrt(2/pi), .025);
near(var(z, 1), 1-2/pi, .025);
check(all(z >= 0) && all(info.ess_count > 100));
check(info.resolved_1 && info.chains_count == 4);
check(all(info.rhat_1 < 1.01));
check(all(info.endpoint_mcse_share_1(:) < .05));
end

function gibbs_cap()
opts = struct('burn_count', 0, 'batch_count', 32, ...
    'max_draws_count', 64, 'seed_1', 27);
[~, info] = INV.TGIBBS(1, 0, opts, @(x) 1);
check(~info.resolved_1 && info.draws_count == 64);
check(all(isinf(info.rhat_1)));
check(all(isinf(info.endpoint_mcse_share_1(:))));
end

function gibbs_two()
draws = INV.TGIBBS(diag([1, .25]), [0; 0], sampler_options());
z = reshape(draws, 2, []);
near(mean(z, 2), sqrt(2/pi)*[1; 2], .04);
near(cov(z', 1), (1-2/pi)*diag([1, 4]), .06);
end

function gibbs_correlated()
rho = .5; c = [1 rho; rho 1];
draws = INV.TGIBBS(c\eye(2), [0; 0], sampler_options());
z = reshape(draws, 2, []);
probability = 1/4+asin(rho)/(2*pi);
m = (1+rho)/(2*sqrt(2*pi)*probability);
second = 1+rho*sqrt(1-rho^2)/(2*pi*probability);
cross = rho+sqrt(1-rho^2)/(2*pi*probability);
expected = [second cross; cross second]-m^2;
near(mean(z, 2), [m; m], .04);
near(cov(z', 1), expected, .06);
end

function gibbs_tail()
draws = INV.TGIBBS(1, -8, sampler_options());
z = draws(:);
ratio = sqrt(2/pi)/erfcx(8/sqrt(2));
near(mean(z), ratio-8, .01);
near(var(z, 1), 1+8*ratio-ratio^2, .005);
check(all(z >= 0) && all(isfinite(z)));
end

function cross_checks()
phantom = [1; 2; 1]; a = eye(3);
[x, t] = INV.TWOMEY(a, phantom, ones(3, 1));
[y, m] = INV.TWOMARK(a, phantom, ones(3, 1));
reference = INV.TIKHONOV(a, phantom, 1, 2);
near(x, phantom, 1e-12);
near(y, phantom, 1e-12);
check(t.cross_check_1 && m.cross_check_1 && all(isfinite(reference)));
check(t.iterations_count == 1);
% Recording comparisons without an agreement threshold against the solver
fprintf('Cross-check values [penalized multiplicative smoothed]:\n');
fprintf('%.9g %.9g %.9g\n', [reference, x, y]');
end

function smoothing()
[x, g, mse] = INV.MARKOWSKI(eye(3), [0; 4; 0], [0; 4; 0], 10);
near(full(g), [.75 .25 0; .25 .5 .25; 0 .25 .75], 1e-12);
near(x, [1; 2; 1], 1e-12);
near(mse, 4, 1e-12);
end

function zero_rows()
[x, info] = INV.TWOMEY([eye(3); zeros(1, 3)], [1; 2; 1; 0]);
near(x, [1; 2; 1], 1e-12);
check(info.iterations_count == 1);
[x, info] = INV.TWOMEY(zeros(2, 3), zeros(2, 1));
near(x, ones(3, 1), 1e-12);
check(info.iterations_count == 100);
end

function physical_inputs()
file = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'config', 'main_inv', 'main_inv_config.example.json');
data.scan = struct('dma_aerosol_flow_lpm', .3, ...
    'dma_sheath_flow_lpm', 2.5, 'dma_excess_flow_lpm', 2.5, ...
    'dma_temperature_deg_c', 23, 'dma_pressure_kpa', 101.325, ...
    'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
    'aac_sample_flow_lpm', .3, 'aac_sheath_flow_lpm', 3, ...
    'neutralizer_on', true, 'particle_polarity', 'positive', ...
    'counting_flow_lpm', .3);
data.penetration.tubes = {struct('id', 'synthetic zero external path', ...
    'length_m', 0, 'bore_mm', 4, 'flow_lpm', .3)};
cfg = UTILS.LOAD_MAIN_INV_CONFIG(file, data);
cfg.mode = 'smps_1d'; cfg.smps_1d.route = 'A';
cfg.scan.dilution_factor = 1; cfg.scan_response.enabled = false;
cfg.cpc.unity_bound_citation = 'Synthetic bound for QA only';
cfg.cpc.unity_bound_max_deficit = .02;
cfg.si.cpc.unity_bound_max_deficit = .02;
cfg.cpc.unity_bound_min_diameter_nm = 1;
cfg.si.cpc.unity_bound_min_diameter_nm = 1e-9;
scan = struct('source_kind', 'smps_database', 'scan_index', 1, ...
    'flags', {{}}, 'dead_time', zeros(3, 1));
scan.channels = struct('values', [1; 4; 1], 'quantity', 'raw counts', ...
    'time_s', [0; .02; .04]);
scan.data.scan = struct('bin_time_s', .02, 'delay_s', 0, ...
    'delay_adjustment_s', 0, 'up_time_s', 1, 'voltage_low_v', 10, ...
    'voltage_high_v', 100, 'low_hold_s', 0, 'high_hold_s', 0);
o = INV.OBSERVATION(scan, cfg);
o.campaign_id = 'synthetic'; o.condition_id = 'synthetic';
o.source_id = 'synthetic';
noise = INV.OBS_VARIANCE({{o}}, cfg);
near(noise.variance_mean_counts2, [1; 4; 1], 1e-12);
grid = INV.Grid({[50, 100, 200]});
dm = grid.elements*1e-9;
[mu, ~, cc, gas] = INV.GAS(296.15, 101325, dm, cfg);
mobility = gas.constants.e_c*cc./(3*pi*mu*dm);
geom = cfg.si.geometry;
o.voltage_v = cfg.si.scan.dma_sheath_flow_lpm* ...
    log(geom.dma_outer_radius_m/geom.dma_inner_radius_m)./ ...
    (2*pi*geom.dma_length_m*mobility);
imp = struct('d50_m', 1384e-9, 'cut_factor_1', 1, ...
    'sharpness_1', 9, 'rho_kg_m3', 1000);
a = INV.KERNEL_1D(grid, o, cfg, imp, ...
    struct('charge_e', 1, 'diffusing_1', false));
check(all(diag(a) > 0));
w = 1./sqrt(noise.variance_mean_counts2);
aw = a.*w; bw = o.values.*w;
[x, l] = INV.TIKHONOV(aw, bw, .01, 0, grid);
near(x, (aw'*aw+l'*l)\(aw'*bw), 1e-8);
noise2 = INV.OBS_VARIANCE({{o}}, cfg, {a*x});
near(noise2.variance_mean_counts2, max(a*x, 1), 1e-9);
end

function refusals()
expect(@() INV.TIKHONOV(eye(2), [0; 1], 1, 0, 2, 1, [], ...
    'algebraic'), 'sootMosaic:TIKHONOV:Solver');
expect(@() INV.EXP_DIST(eye(2), [1; 1], 1, 1, [1 2], ...
    'algebraic'), 'sootMosaic:EXP_DIST:Solver');
expect(@() INV.TIKHONOV(eye(3), ones(3, 1), 1, [2 2]), ...
    'sootMosaic:TIKHONOV:Parameters');
expect(@() INV.TIKHONOV(eye(3), ones(3, 1), 1, 2, 3, 2), ...
    'sootMosaic:TIKHONOV:Floor');
expect(@() INV.TIKHONOV_LPR(3, 3), 'sootMosaic:TIKHONOV_LPR:Order');
expect(@() INV.POSTERIOR(zeros(2), zeros(2)), ...
    'sootMosaic:POSTERIOR:Precision');
expect(@() INV.EXP_DIST_LPR(0, [1 2]), 'sootMosaic:EXP_DIST_LPR:Input');
expect(@() INV.LSQ(eye(2), [1; NaN]), 'sootMosaic:LSQ:Input');
expect(@() INV.POST_MIX(1, 1, -1), 'sootMosaic:POST_MIX:Input');
expect(@() INV.TGIBBS([1 2; 2 1], [0; 0]), 'sootMosaic:TGIBBS:Precision');
expect(@() INV.MEAN_SQ_ERR(eye(2), [1; 1], [1 1]), ...
    'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.MEAN_SQ_ERR(eye(2), 1, [1; 1]), ...
    'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.MEAN_SQ_ERR(1, 1, NaN), 'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.MEAN_SQ_ERR(-1, 1, 1), 'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.MEAN_SQ_ERR([], [], []), 'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.MARKOWSKI(-eye(2), [1; 1], [1; 1]), ...
    'sootMosaic:MEAN_SQ_ERR:Input');
expect(@() INV.TWOMEY(zeros(1, 2), 1), 'sootMosaic:TWOMEY:Support');
end

function small_covariances()
expect(@() INV.POST_MIX(0, -1e-12, 1), ...
    'sootMosaic:POST_MIX:Covariance');
expect(@() INV.DELTA_PROP(0, -1e-12, @identity_stat, true), ...
    'sootMosaic:DELTA_PROP:Covariance');
expect(@() INV.TGIBBS(1e-14*[1 0; 1 1], [0; 0]), ...
    'sootMosaic:TGIBBS:Precision');
[~, c] = INV.POST_MIX(0, 0, 1);
near(c, 0, 0);
[~, c] = INV.DELTA_PROP(0, 0, @identity_stat, true);
near(c, 0, 0);
end

function [v, j] = identity_stat(x, window)
j = double(window)'; v = j*x;
end

function mean_square()
a = eye(3); x = [3; 100; 6]; b = [1; 0; 2];
near(INV.MEAN_SQ_ERR(a, x, b), 10, 1e-12);
near(INV.MEAN_SQ_ERR(2*a, x, 2*b), 40, 1e-12);
near(INV.MEAN_SQ_ERR(a, b, b), 0, 1e-12);
check(isnan(INV.MEAN_SQ_ERR(a, x, zeros(3, 1))));
end

function twomey_stopping()
a = ones(5, 1);
[x, info] = INV.TWOMEY(a, [1; 1; 2; 2; 2], 1, 3);
near(x, 2, 1e-12); check(info.iterations_count == 1);
[x, info] = INV.TWOMEY(a, [1; 1; 1; 2; 2], 1, 3);
near(x, 2, 1e-12); check(info.iterations_count == 3);
[x, info] = INV.TWOMEY(a, [1; 1; 1; 1; 2], 1, 3);
near(x, 2, 1e-12); check(info.iterations_count == 3);
[x, info] = INV.TWOMEY(a, [1; 1; 2; 2; 2], 1, 3, false);
near(x, 2, 1e-12); check(info.iterations_count == 3);
[x, info] = INV.TWOMEY(1, 1, 0);
near(x, 0, 1e-12); check(info.iterations_count == 100);
end

function twomey_scaling()
[x, info] = INV.TWOMEY([10; 100], [10; 200], 1, 3);
near(x, 2, 1e-12); check(info.iterations_count == 1);
[x, info] = INV.TWOMEY([1; 1e-11], [1; 1], 1, 3);
near(x, 1, 1e-12); check(info.iterations_count == 1);
[x, info] = INV.TWOMEY([1; 1e-10], [1; 2e-10], 1, 3);
near(x, 2, 1e-12); check(info.iterations_count == 1);
end

function smoothing_limits()
[x, ~, mse] = INV.MARKOWSKI(eye(3), [1; 2; 1], [1; 2; 1], 2);
near(x, [21; 22; 21]/16, 1e-12); near(mse, 25/128, 1e-12);
[x, ~, mse] = INV.MARKOWSKI(eye(3), [1; 2; 1], [0; 8; 0], 2);
near(x, [2.5; 3; 2.5], 1e-12); near(mse, 11/6, 1e-12);
[x, ~, mse] = INV.MARKOWSKI(eye(3), zeros(3, 1), [0; 4; 0], 2);
near(x, [1.25; 1.5; 1.25], 1e-12); check(isnan(mse));
end

function twomark_stopping()
[x, info] = INV.TWOMARK(eye(3), ones(3, 1));
near(x, ones(3, 1), 1e-12);
check(info.iterations_count == 40 && info.cross_check_1);
[x, info] = INV.TWOMARK(zeros(2, 3), zeros(2, 1));
near(x, ones(3, 1), 1e-12);
check(info.iterations_count == 40 && info.cross_check_1);
a = [1 0 0 0; 0 0 0 1]; start = [4; 8; 12; 16];
[x, info] = INV.TWOMARK(a, [4; 16], start);
near(x, start, 1e-12);
check(info.iterations_count == 1 && info.cross_check_1);
end

function upstream_demo()
% Method: Twomey (1975, Eq. 7); Markowski (1987, Eq. 7).
% Fixture: main_dma.m and +tools/gen_data.m from odias, GPL-3,
%     ...commit 8de95745486b01cf5ede0b186d044656eb3fde33.
% This test uses a synthetic kernel.
[a, b, d_nm, setpoint_nm] = demo_fixture();
xi = demo_initial(a, b, d_nm, setpoint_nm);
[x_two, two] = INV.TWOMEY(a, b, xi, [], true);
[x_twomark, twomark] = INV.TWOMARK(a, b, xi);
indices_count = [1 30 80 140 200 260 300 325 350 400 450 500]';
% Fixed regression outputs of get_init, twomey and twomark on this fixture.
expected_init_samples_cm3_inv = [0; 0; 0.00028096570491423657; ...
    0.063569903132393871; 0.51768099393896871; 0.51775175620656344; ...
    0.87251892310574553; 0.99603885471551856; 0; 0; 0; 0];
expected_init_sum_cm3_inv = 100.20716136202975;
expected_init_norm_cm3_inv = 8.0141310701029642;
expected_two_samples_cm3_inv = [0; 0; 0.00026146444860310718; ...
    0.061163678667723008; 0.51954061796566575; 0.51359026044561773; ...
    0.85379175594712187; 2.5137480271456276; 0; 0; 0; 0];
expected_two_sum_cm3_inv = 103.7917127714328;
expected_two_norm_cm3_inv = 8.9581725779465717;
expected_two_iterations_count = 2;
expected_twomark_samples_cm3_inv = [1.2193261703114769e-06; ...
    2.8396123120244696e-08; 4.1098197358351096e-05; ...
    0.048590372395998768; 0.54843645735063007; 0.4905055203226551; ...
    0.90737364363667017; 1.0041491430525771; 0.82293509352519512; ...
    0.60088654575109701; 0.44780783856959211; 0.39280996774403737];
expected_twomark_sum_cm3_inv = 204.64938706867139;
expected_twomark_norm_cm3_inv = 11.549087284214192;
expected_twomark_iterations_count = 40;
near(xi(indices_count), expected_init_samples_cm3_inv, 1e-10);
near(sum(xi), expected_init_sum_cm3_inv, 1e-10);
near(norm(xi), expected_init_norm_cm3_inv, 1e-10);
near(x_two(indices_count), expected_two_samples_cm3_inv, 1e-10);
near(sum(x_two), expected_two_sum_cm3_inv, 1e-10);
near(norm(x_two), expected_two_norm_cm3_inv, 1e-10);
check(two.iterations_count == expected_two_iterations_count);
near(x_twomark(indices_count), expected_twomark_samples_cm3_inv, 1e-10);
near(sum(x_twomark), expected_twomark_sum_cm3_inv, 1e-10);
near(norm(x_twomark), expected_twomark_norm_cm3_inv, 1e-10);
check(twomark.iterations_count == expected_twomark_iterations_count);
end

function [a, b, d_nm, setpoint_nm] = demo_fixture()
d_nm = logspace(log10(10), log10(1e3), 500)';
setpoint_nm = logspace(log10(13.1), log10(200), 114)';
% Synthetic singly charged continuum mobility ratio Z/Zstar = dstar/d.
% A triangular transfer of half-width .1 is integrated in log10 diameter.
beta_1 = .1;
width_decades = log10(d_nm(2))-log10(d_nm(1));
a = max(0, 1-abs(setpoint_nm./d_nm'-1)/beta_1)*width_decades;
mu_nm = [200, 200/3];
sigma_1 = [1.55, 1.55/1.15];
weight_1 = [1, .5];
x0 = zeros(size(d_nm));
for k = 1:2
    % gen_data's normpdf(log(d),log(mu),log(s))*sqrt(2*pi)*log(s).
    x0 = x0+weight_1(k)*exp(-.5*((log(d_nm)-log(mu_nm(k)))/ ...
        log(sigma_1(k))).^2);
end
% Noiseless commented main_dma case; Lb is identity, so a,b are unchanged.
b = a*x0;
end

function xi = demo_initial(a, b, d_nm, setpoint_nm)
% Method: Twomey (1975, Eq. 7), starting from a response-normalized...
%     ...linear interpolation as in the pinned +invert/get_init.m demo rule.
% get_init is not a package file; this helper is local to the QA case.
response = a*ones(numel(d_nm), 1);
xi = interp1(setpoint_nm, full(b)./response, d_nm);
xi(~isfinite(xi)) = 0;
xi = max(0, xi);
end

function best = enumerate_faces(a, b)
n = size(a, 2); best = zeros(n, 1); objective = Inf;
for code = 0:2^n-1
    free = logical(bitget(code, 1:n));
    x = zeros(n, 1);
    if any(free), x(free) = a(:, free)\b; end
    if all(x >= -1e-12) && norm(a*x-b)^2 < objective
        best = x; objective = norm(a*x-b)^2;
    end
end
end

function expect(action, identifier)
try
    action();
catch err
    check(strcmp(err.identifier, identifier));
    return
end
check(false);
end

function near(a, b, tolerance)
check(isequal(size(a), size(b)) && all(isfinite(a(:))) && ...
    max(abs(a(:)-b(:))) <= tolerance*max(1, max(abs(b(:)))));
end

function check(pass)
if ~isscalar(pass) || ~pass
    error('sootMosaic:QA:InvSolversFailed', ...
        'Unexpected synthetic result.');
end
end
