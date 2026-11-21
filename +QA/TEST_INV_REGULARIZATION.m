function report = TEST_INV_REGULARIZATION()
% "TEST_INV_REGULARIZATION" checks evidence on synthetic small systems.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: One name and pass flag per case. Failures raise...
%         ...sootMosaic:QA:InvRegularizationFailed
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 30-34);
%     ...Golub et al. (1979); Hansen (2000);
%     ...Groetsch (1984, Eq. 3.3.3).
% Original synthetic tests; no external source text adopted.

tests = {@logdet_small, @logdet_underflow, @two_by_two, @lambda_peak, ...
    @unconstrained_evidence, @rectangular, @underdetermined_tk2, ...
    @pooled_families, ...
    @length_average, @widening, @refinement, @unresolved, ...
    @cross_checks, @gcv_underflow, @undefined_checks, @posterior_mixture, ...
    @variance_passes, @refusals};
names = {'small log determinants', 'underflow determinant', ...
    'equations 30 to 34', 'lambda grid maximum', ...
    'Gaussian evidence and nonnegative mode', 'rectangular evidence', ...
    'underdetermined tk2 default grid', ...
    'pooled normalized family evidence', 'length probabilities', ...
    'two-decade widening', 'posterior refinement and tails', ...
    'finite search limits', 'three lambda cross-checks', 'GCV underflow', ...
    'undefined cross-checks', 'posterior mixture interface', ...
    'two-pass variance interface', 'input refusals'};
report = repmat(struct('name', '', 'pass', false), numel(tests), 1);
try
    for k = 1:numel(tests)
        report(k).name = names{k};
        tests{k}();
        report(k).pass = true;
    end
catch err
    error('sootMosaic:QA:InvRegularizationFailed', ...
        '%s: %s', err.identifier, err.message);
end
end

function logdet_small()
for a = {[2 1; 1 3], [0 -2; 3 4], diag([2 3 4])}
    near(INV.LOGDET(a{1}), log(det(a{1})), 1e-12);
end
near(INV.LOGDET(sparse([2 1; 1 3])), log(5), 1e-12);
end

function logdet_underflow()
a = diag([1, 1e-200, 1e-200]);
check(det(a) == 0);
near(INV.LOGDET(a), -400*log(10), 1e-12);
end

function two_by_two()
opts = fixture();
opts.lambda_ratio_1 = opts.lambda_ratio_1/sqrt(3/2);
r = INV.BAYESF([1 1; 0 1], [2; 1], 2, opts);
c = r.curves_1{1};
near(c.fit_1(3), -7/10, 1e-12);
near(c.credence_1(3), -log(5)/2, 1e-12);
expected = -7/10-log(5)/2-log(2*pi);
near(c.log_evidence_1(3), expected, 1e-12);
nominal = -57/62+log(9/31)/2-log(2*pi);
near(c.log_bayes_factor_1(3), expected-nominal, 1e-12);
% Evaluating Eq. 30 at zero and Eq. 31 at the Gaussian mean
near(-5/2+9/5-log(5)/2-log(2*pi), expected, 1e-12);
marginal = [3 1; 1 2];
near(-log(det(2*pi*marginal))/2- ...
    [2 1]*(marginal\[2; 1])/2, expected, 1e-12);
end

function lambda_peak()
r = INV.BAYESF(eye(2), [2; 0], 2, fixture());
c = r.curves_1{1};
t = c.lambda_cm3.^2;
expected = -2*t./(1+t)+log(t./(1+t))-log(2*pi);
near(c.log_evidence_1, expected, 1e-12);
near(r.selected_1{1}.lambda_cm3, 1, 1e-12);
near(r.selected_1{1}.map_cm3_inv, [1; 0], 1e-12);
near(r.selected_1{1}.covariance_cm6_inv, eye(2)/2, 1e-12);
near(c.posterior_probability_1, grid_mass(expected), 1e-12);
near(c.log_integral_1, grid_integral(expected), 1e-12);
check(c.interior_1 && ~c.refined_1);
end

function unconstrained_evidence()
p = INV.BAYESF(eye(2), [2; 0], 2, fixture());
n = INV.BAYESF(eye(2), [-2; 0], 2, fixture());
near(n.curves_1{1}.log_evidence_1, p.curves_1{1}.log_evidence_1, 1e-12);
near(n.selected_1{1}.map_cm3_inv, [0; 0], 1e-12);
near(n.curves_1{1}.fit_1(3), -1, 1e-12);
end

function rectangular()
opts = fixture();
opts.lambda_ratio_1 = [1e-8, .25, .5, 1, 2, 4]*sqrt(2);
r = INV.BAYESF([1 0], 2, 2, opts);
c = r.curves_1{1};
t = c.lambda_cm3.^2;
expected = -2*t./(1+t)+log(t./(1+t))/2-log(2*pi)/2;
near(c.log_evidence_1, expected, 1e-10);
near(r.selected_1{1}.lambda_cm3, .5, 1e-12);
end

function underdetermined_tk2()
% Holding the default scale grid fixed for the analytic evidence check
opts = struct('families_1', {{'tk2'}}, ...
    'max_widen_count', 0, 'max_refine_count', 0);
r = INV.BAYESF(ones(1, 511), 2, 511, opts);
c = r.curves_1{1};
% L\ones has entries -i*(512-i); its squared norm is (512^5-512)/30
s2 = (512^5-512)/30;
t = c.lambda_cm3.^2;
expected = -2*t./(s2+t)+log(t./(s2+t))/2-log(2*pi)/2;
check(max(abs(c.log_evidence_1-expected)) <= 1e-8);
near(c.lambda_ref_cm3, sqrt(511/766), 1e-12);
check(abs(c.lambda_cm3(1)/8.167630180635262e-9-1) < 1e-12);
near(r.options_1.lambda_ratio_1, logspace(-8, 3, 111), 1e-12);
check(numel(c.lambda_cm3) == 111 && ~c.interior_1 && ~c.refined_1);
near(r.selected_1{1}.lambda_cm3, 1000*sqrt(511/766), 1e-10);
x = r.selected_1{1}.map_cm3_inv;
check(isequal(size(x), [511, 1]) && all(isfinite(x)) && all(x >= 0));
end

function pooled_families()
opts = fixture(); opts.families_1 = {'tk0', 'tk1', 'tk2'};
r = INV.BAYESF({eye(2), eye(2)}, {[2; 2], [2; 2]}, 2, opts);
ratio2 = opts.lambda_ratio_1(:).^2;
% Symmetric and antisymmetric eigenvalues of the three proper precisions
eigenvalues = [1, 1; 1, 3; 1/4, 9/4];
expected = zeros(1, 3);
for f = 1:3
    t = ratio2*2/sum(eigenvalues(f, :));
    p = t*eigenvalues(f, 1);
    q = t*eigenvalues(f, 2);
    e = -4*p./(1+p)+log(p./(1+p))/2+ ...
        log(q./(1+q))/2-log(2*pi);
    near(r.curves_1{1, f}.log_evidence_1, e, 1e-11);
    expected(f) = grid_integral(e);
end
near(r.family_log_evidence_1, [expected; expected], 1e-11);
near(r.pooled_log_evidence_1, 2*expected, 1e-11);
[~, best] = max(expected);
check(r.selected_family_index_1 == best);
near(sum(r.family_probability_1, 2), [1; 1], 1e-12);
% Distinct scans separate the first-scan winner from the pooled winner
r = INV.BAYESF({eye(2), eye(2)}, {[2; 0], [4; 4]}, 2, opts);
expected = [-3.773553143493938, -3.813769680689547, -3.939372227593270; ...
    -7.146342659819385, -6.275621740178326, -5.583327866501514];
near(r.family_log_evidence_1, expected, 1e-11);
near(r.pooled_log_evidence_1, ...
    [-10.919895803313323, -10.089391420867871, -9.522700094094784], 1e-11);
[~, first] = max(r.family_log_evidence_1(1, :));
check(first == 1 && strcmp(r.families_1{first}, 'tk0'));
check(r.selected_family_index_1 == 3 && strcmp(r.selected_family_1, 'tk2'));
reversed = INV.BAYESF({eye(2), eye(2)}, {[4; 4], [2; 0]}, 2, opts);
near(reversed.family_log_evidence_1, flipud(expected), 1e-11);
near(reversed.pooled_log_evidence_1, r.pooled_log_evidence_1, 1e-11);
check(reversed.selected_family_index_1 == 3 && ...
    strcmp(reversed.selected_family_1, 'tk2'));
end

function length_average()
opts = fixture(); opts.families_1 = {'exp'};
opts.length_grid_decades = [1/log(4), 1/log(2)];
r = INV.BAYESF(eye(2), [2; 2], [10; 100], opts);
c = r.curves_1{1};
logs = zeros(2, 1);
rho = [1/4, 1/2];
for k = 1:2
    near(c(k).lambda_ref_cm3, sqrt(1-rho(k)^2), 1e-12);
    t = c(k).lambda_cm3.^2;
    vplus = 1+(1+rho(k))./t;
    vminus = 1+(1-rho(k))./t;
    e = -4./vplus-log(vplus.*vminus)/2-log(2*pi);
    near(c(k).log_evidence_1, e, 1e-11);
    logs(k) = grid_integral(e);
end
probability = exp(logs-max(logs)); probability = probability/sum(probability);
near([c.length_probability_1]', probability, 1e-12);
near(sum(vertcat(c.joint_probability_1)), 1, 1e-12);
near(r.family_log_evidence_1, ...
    max(logs)+log(sum(exp(logs-max(logs)))/2), 1e-12);
end

function widening()
opts = fixture(); opts.lambda_ratio_1 = .01*2.^(0:4);
opts.max_widen_count = 2;
r = INV.BAYESF(eye(2), [2; 0], 2, opts);
c = r.curves_1{1};
check(c.widen_count == 1 && c.interior_1);
near(c.support_cm3, [.01, 16], 1e-12);
check(r.selected_1{1}.d1_flag_1);
near(r.selected_1{1}.lambda_cm3, .16*10^(6/7), 1e-12);
opts.lambda_ratio_1 = 2.^(0:4);
r = INV.BAYESF(eye(2), [sqrt(202); 0], 2, opts);
c = r.curves_1{1};
check(c.widen_count == 1 && c.interior_1);
near(c.support_cm3, [.01, 16], 1e-12);
end

function refinement()
opts = fixture(); opts.max_refine_count = 6; opts.width_flag_decades = .1;
r = INV.BAYESF(eye(2), [2; 0], 2, opts);
c = r.curves_1{1};
check(c.refined_1 && c.refine_count == 2);
check(numel(c.lambda_cm3) == 17);
near(sum(c.posterior_probability_1), 1, 1e-12);
near(c.log_evidence_1, -2*c.lambda_cm3.^2./(1+c.lambda_cm3.^2)+ ...
    log(c.lambda_cm3.^2./(1+c.lambda_cm3.^2))-log(2*pi), 1e-12);
actual = [c.log10_lambda_mean_1, c.lambda_sd_decades, ...
    c.log10_lambda_quantiles_1, c.log_integral_1, c.tail_mass_1];
expected = [0.0533689757121011, 0.31291466010622165, ...
    -0.529414566520415, 0.5715774499041851, ...
    -3.7640983702017463, 0.46004172455818865];
check(isequal(size(actual), size(expected)) && all(isfinite(actual)) && ...
    max(abs(actual-expected)) <= 1e-10);
check(r.pooled_resolved_1);
check(r.selected_1{1}.d2_flag_1);
end

function unresolved()
opts = fixture(); opts.max_widen_count = 1; opts.max_refine_count = 1;
r = INV.BAYESF(eye(2), [0; 0], 2, opts);
c = r.curves_1{1};
check(c.widen_count == 1 && ~c.interior_1);
near(c.support_cm3, [.25, 400], 1e-12);
check(~r.pooled_resolved_1 && r.selected_1{1}.d1_flag_1);
end

function cross_checks()
lambda = [1e-10, .5, 1, 2, 10]';
r = INV.LAMBDA_XCHECK(eye(2), [2; 0], eye(2), lambda);
t = lambda.^2;
near(r.residual2_1, 4*(t./(1+t)).^2, 1e-12);
check(abs(r.residual2_1(1)/4e-40-1) < 1e-12);
near(r.prior2_cm6_inv, 4./(1+t).^2, 1e-12);
near(r.gcv_1, 2*ones(5, 1), 1e-12);
near(r.curvature_1, t.*(1+t)./(1+t.^2).^(3/2), 1e-12);
near(r.lcurve_lambda_cm3, 1, 1e-12);
near(r.discrepancy_lambda_cm3, 1, 1e-12);
check(r.discrepancy_bracketed_1);
% A strict GCV minimum checks the returned scale as well as the curve
r = INV.LAMBDA_XCHECK(diag([1, 2]), [1; sqrt(2.5)], eye(2), [.5, 1, 2]);
near(r.gcv_1, [703/484; 10/7; 253/169], 1e-12);
near(r.gcv_lambda_cm3, 1, 1e-12);
check(~r.gcv_edge_1);
end

function gcv_underflow()
r = INV.LAMBDA_XCHECK(eye(2), [2; 0], eye(2), [1e-100, 1e-90, 1e-80]);
near(r.gcv_1, 2*ones(3, 1), 1e-12);
end

function undefined_checks()
r = INV.LAMBDA_XCHECK(eye(2), [0; 0], eye(2), [.5, 1, 2]);
check(isnan(r.lcurve_lambda_cm3) && ~r.discrepancy_bracketed_1);
near(r.discrepancy_lambda_cm3, 2, 1e-12);
r = INV.LAMBDA_XCHECK([1; 0], [0; 2], 1, [.5, 1, 2]);
check(isnan(r.discrepancy_lambda_cm3) && isnan(r.lcurve_lambda_cm3));
end

function posterior_mixture()
r = INV.BAYESF(eye(2), [2; 0], 2, fixture());
c = r.curves_1{1}; p = c.posterior_probability_1;
centers = zeros(2, 5); covariances = zeros(2, 2, 5);
for k = 1:5
    [centers(:, k), l] = INV.TIKHONOV(eye(2), [2; 0], ...
        c.lambda_cm3(k), 0, 2, 1);
    covariances(:, :, k) = INV.POSTERIOR(eye(2), l);
end
[center, covariance] = INV.POST_MIX(centers, covariances, p);
v = 1./(1+c.lambda_cm3.^2);
near(center, [2*sum(p.*v); 0], 1e-12);
near(covariance, diag([sum(p.*v)+4*sum(p.*(v-sum(p.*v)).^2), ...
    sum(p.*v)]), 1e-12);
end

function variance_passes()
% Supplying synthetic labeled raw-count observations to the noise interface
o = struct('campaign_id', 'synthetic', 'condition_id', 'synthetic', ...
    'source_id', 'synthetic', 'scan_index', 1, 'mode', 'smps_1d', ...
    'route', 'A', 'source_kind', 'smps_database', 'quantity', 'raw counts', ...
    'unit', 'counts', 'values', [4; 0], 'reduced', false, ...
    'dilution_applied', true, 'dilution_known', true, ...
    'sample_volume_cm3', [1; 1], 'time_s', [0; 1], ...
    'classifier_time_s', [0; 1], 'voltage_v', [10; 20], 'bin_time_s', 1);
cfg = struct('rng_seed', 1, 'variance', struct('model', 'poisson_two_pass', ...
    'reduced_model', 'pooled', 'aac_model', 'pooled', 'floor_counts', 1, ...
    'min_repeats', 2, 'repeat_scope', 'campaign_mode', ...
    'repeat_treatment', 'split_within_between', ...
    'propagate_repeat_uncertainty', true));
v = INV.OBS_VARIANCE({{o}}, cfg);
near(v.variance_mean_counts2, [4; 1], 1e-12);
a = diag([2, 1]); w = 1./sqrt(v.variance_mean_counts2);
r = INV.BAYESF(a.*w, o.values.*w, 2, fixture());
near(r.selected_1{1}.map_cm3_inv, [1; 0], 1e-12);
v = INV.OBS_VARIANCE({{o}}, cfg, {a*r.selected_1{1}.map_cm3_inv});
near(v.variance_mean_counts2, [2; 1], 1e-12);
w = 1./sqrt(v.variance_mean_counts2);
r = INV.BAYESF(a.*w, o.values.*w, 2, fixture());
c = r.curves_1{1}; t = c.lambda_cm3.^2;
expected = -4*t./(2+t)-log((1+2./t).*(1+1./t))/2-log(2*pi);
near(c.log_evidence_1, expected, 1e-12);
end

function refusals()
expect(@() INV.LOGDET(diag([1, 0])), 'sootMosaic:LOGDET:Singular');
expect(@() INV.LOGDET(diag([1, -1])), 'sootMosaic:LOGDET:Nonpositive');
expect(@() INV.LOGDET([1, NaN]), 'sootMosaic:LOGDET:Input');
opts = fixture(); opts.lambda_ratio_1 = [1, 2, 2, 3, 4];
expect(@() INV.BAYESF(eye(2), [2; 0], 2, opts), 'sootMosaic:BAYESF:Options');
opts = fixture(); opts.families_1 = {'exp'};
expect(@() INV.BAYESF(eye(2), [2; 0], 2, opts), 'sootMosaic:BAYESF:Grid');
expect(@() INV.BAYESF(zeros(2), [2; 0], 2), 'sootMosaic:BAYESF:Input');
expect(@() INV.LAMBDA_XCHECK(eye(2), [2; 0], zeros(2), [.5, 1, 2]), ...
    'sootMosaic:LAMBDA_XCHECK:Prior');
end

function opts = fixture()
opts = struct('families_1', {{'tk0'}}, ...
    'lambda_ratio_1', [.25, .5, 1, 2, 4], ...
    'max_widen_count', 0, 'max_refine_count', 0);
end

function p = grid_mass(e)
p = exp(e-max(e)).*[.5; 1; 1; 1; .5]; p = p/sum(p);
end

function value = grid_integral(e)
value = max(e)+log(sum(exp(e-max(e)).*[.5; 1; 1; 1; .5])/4);
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
    error('sootMosaic:QA:InvRegularizationFailed', ...
        'Unexpected synthetic result.');
end
end
