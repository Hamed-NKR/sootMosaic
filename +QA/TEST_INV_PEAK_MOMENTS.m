function report = TEST_INV_PEAK_MOMENTS(run_long)
% "TEST_INV_PEAK_MOMENTS" checks scan statistics on synthetic distributions.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     run_long: Optional logical, false by default. True adds simulated...
%         ...population tests, interval bootstrap, sampler, coverage and...
%         ...window GM scatter, and structured, edge and control scans...
%         ...through MOMENTS
% Outputs:
%     report: Struct array with name, pass and detail, one entry per...
%         ...executed case. Detail holds the numbers a case reports without...
%         ...a pass threshold, else it is empty
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Eqs. 23 and 28; part II, Eq. 26);
%     ...Kiasadegh et al. (2026, Eqs. 25-31). Synthetic checks of the...
%     ...rules of config/main_inv/DEFAULTS.md, sections 10, 11 and 13,...
%     ...and a truncation comparison of fitted against software modes for...
%     ...windows that end below the impactor cut. Wilson (1927)
%     ...score limits judge the coverage rates.
% Reimplementation from the published methods.

if nargin < 1, run_long = false; end
try
    check(islogical(run_long) && isscalar(run_long), 'Logical long switch.');
    cfg = configuration();
    saved = rng;
    restore = onCleanup(@() rng(saved));
    rng(29019, 'twister');
    old_warning = warning('off', 'sootMosaic:CHARGE_FRAC:OutsideRange');
    restore_warning = onCleanup(@() warning(old_warning));
    tests = {@lognormal_moments, @bimodal, @mixture_bounds, ...
        @response, @withholding, @reduced_moments, @direct_propagation, ...
        @single_charge, @multiple_charge, @reduced_peak, ...
        @concentration_view, @inverted_peak, @width_guard, @guards, ...
        @profile_disagreement, @mode_refinement, @window_checks, ...
        @truncation_comparison};
    names = {'Lognormal central moments and refined mode', ...
        'Bimodal draw rule', 'Mixed FN FM bounds and no bound', ...
        'Statistic response diagnostics', ...
        'Structured and edge withholding', ...
        'Reduced distribution moments', 'Direct posterior propagation', ...
        'Single charge kernel recovery and profile agreement', ...
        'Multiple charge kernel recovery and weighting', ...
        'Reduced correction states and tail guard', ...
        'Raw concentration agrees with counts', ...
        'Inverted peak with full posterior covariance', ...
        'Positive width guard', 'Input guards', ...
        'Profile and Fisher disagreement flag', ...
        'Unrefined interior mode keeps no interval', ...
        'Observed window GM and evidence inversion check', ...
        'Synthetic truncation comparison without threshold'};
    if run_long
        tests = [tests, {@population_one, @population_two, ...
            @bootstrap_interval, @sampler_check, @coverage, ...
            @structured_scan, @edge_scan, @control_scan}];
        names = [names, {'Long one-population simulated-null test', ...
            'Long two-population detection', 'Long interval bootstrap', ...
            'Long constrained posterior comparison', ...
            'Long 150 to 1500 count coverage and window GM scatter', ...
            ['Long two-mode scan on the 14.1-964.7 nm window flagged ', ...
            'as structured'], ...
            ['Long 600 nm scan on the 85.1-582.9 nm window flagged at ', ...
            'the edge'], ...
            ['Long broad 250 nm scan on the 14.1-964.7 nm window keeps ', ...
            'its intervals']}];
    end
    report = repmat(struct('name', '', 'pass', false, 'detail', []), ...
        numel(tests), 1);
    for case_index = 1:numel(tests)
        case_detail = [];
        tests{case_index}();
        report(case_index) = struct('name', names{case_index}, ...
            'pass', true, 'detail', case_detail);
    end
catch err
    error('sootMosaic:QA:InvPeakMomentsFailed', '%s (%s)', ...
        err.message, err.identifier);
end

    function lognormal_moments()
        g = midpoint_grid(1, 10000, 800);
        x = phantom(g, 1000, 100, 1.5);
        c = cfg; c.report.d_cap_nm = 2000;
        r = INV.MOMENTS(g, x, zeros(g.Ne), [1.01, 9900], c, ...
            struct('peak_fit', screen(false, 0)));
        near(r.GM_nm, 100, 1e-8);
        near(r.mode_nm, 100, 2e-3);
        near(r.skewness_1, 0, 1e-8);
        near(r.kurtosis_1, 3, 1e-5);
        near(r.GSD_1, 1.5, 2e-4);
        check(~r.bimodal_1 && ~r.interval_withheld_1, 'Single mode.');
    end

    function bimodal()
        g = midpoint_grid(5, 2000, 240);
        x = phantom(g, 1000, 50, 1.2)+phantom(g, 1000, 400, 1.2);
        opt = struct('draws_cm3_inv', repmat(x, 1, 100), ...
            'draws_resolved_1', true, 'peak_fit', screen(true, 0));
        r = INV.MOMENTS(g, x, zeros(g.Ne), [6, 1500], cfg, opt);
        check(r.bimodal_1 && r.bimodal_draw_share_1 == 1, 'Two maxima.');
        opt.draws_resolved_1 = false;
        r = INV.MOMENTS(g, x, zeros(g.Ne), [6, 1500], cfg, opt);
        check(~r.bimodal_1 && ~r.bimodal_resolved_1, 'Unresolved draws.');
    end

    function mixture_bounds()
        g = midpoint_grid(10, 1000, 2);
        x = [2, 1; 1, 3];
        c = cfg; c.report.d_cap_nm = g.nodes{1}(end);
        window = [g.nodes{1}(1), 100];
        opt = struct('weights_1', [0.25; 0.75], 'mass_kg', [1; 4]);
        r = INV.MOMENTS(g, x, zeros(2, 2, 2), window, c, opt);
        % Each cell spans one decade, so FN is x2/(x1+x2)
        f = [1/3; 3/4];
        center = [0.25, 0.75]*f;
        sd = sqrt([0.25, 0.75]*(f-center).^2);
        z = sqrt(2)*erfinv(0.9);
        near(r.FN.upper_1, center+z*sd, 1e-12);
        fm = [2/3; 12/13];
        mean_mass = [0.25, 0.75]*fm;
        sd_mass = sqrt([0.25, 0.75]*(fm-mean_mass).^2);
        near(r.FM.sd_1, sd_mass, 1e-12);
        check(mean_mass+z*sd_mass >= 1 && ...
            strcmp(r.FM.status, 'no bound') && isnan(r.FM.upper_1), ...
            'Uninformative mass bound.');
        r = INV.MOMENTS(g, [2; 1], 100*eye(2), window, c, opt_single());
        check(strcmp(r.FN.status, 'no bound'), 'Large number variance.');
        r = INV.MOMENTS(g, [eps/4; 1], zeros(2), window, c, opt_single());
        check(strcmp(r.FN.status, 'no bound'), 'Boundary at one.');
        c.report.above_window = false;
        r = INV.MOMENTS(g, [2; 1], eye(2), window, c);
        check(isnan(r.FN.upper_1), 'No requested bound.');
    end

    function response()
        j = [1, -2, 3; 0, 0, 0];
        r = INV.STAT_RESPONSE(j, eye(3));
        near(r.gain_1(1), 1, 0); near(r.cosine_1(1), 1, 0);
        check(isnan(r.gain_1(2)) && r.diagnostic_only_1, 'Zero derivative.');
        r = INV.STAT_RESPONSE(j(1, :), 0.5*eye(3));
        near(r.gain_1, 0.5, 0); near(r.cosine_1, 1, 0);
        r = INV.STAT_RESPONSE(j(1, :), cat(3, eye(3), zeros(3)), [1; 3]);
        near(r.gain_1, 0.25, 0);
        r = INV.STAT_RESPONSE(j(1, :), zeros(3));
        near(r.gain_1, 0, 0); check(isnan(r.cosine_1), 'Zero response.');
    end

    function withholding()
        g = midpoint_grid(10, 2000, 80);
        x = phantom(g, 100, 150, 1.6);
        for variant = 1:3
            opt.peak_fit = screen(variant == 2, 0.06*(variant == 3));
            r = INV.MOMENTS(g, x, eye(g.Ne), [15, 700], cfg, opt);
            check(r.interval_withheld_1 == (variant > 1), ...
                'Structured and edge-fraction interval withholding.');
            check(all(isfinite([r.GM_nm, r.GSD_1])), 'Point values kept.');
            if variant > 1
                check(all(all(isnan(r.interval(2:3, :)))), ...
                    'Intervals withheld.');
            else
                check(all(all(isfinite(r.interval(2:3, :)))), ...
                    'Intervals kept.');
            end
        end
        r = INV.MOMENTS(g, x, eye(g.Ne), [15, 700], cfg);
        check(r.screen_missing_1 && r.interval_withheld_1, 'Missing screen.');
    end

    function reduced_moments()
        g = midpoint_grid(10, 2000, 80);
        o = reduced_observation(g, phantom(g, 100, 150, 1.6), true);
        r = INV.MOMENTS(g, o, [], [15, 700], cfg);
        check(strcmp(r.label, 'software-reduced distribution') && ...
            isnan(r.TF_1) && isnan(r.FN.upper_1), 'Reduced tail withheld.');
        check(all(all(isnan(r.interval))), 'No invented covariance.');
    end

    function direct_propagation()
        g = midpoint_grid(10, 1000, 6);
        x = [2; 4; 6; 5; 3; 1];
        variance = 1e-4*eye(6);
        rng(29019, 'twister');
        draws = x+0.01*randn(6, 600);
        check(all(draws(:) > 0), 'Small Gaussian case stays positive.');
        window = [g.nodes{1}(1), g.nodes{1}(end)];
        opt = struct('peak_fit', screen(false, 0), ...
            'draws_cm3_inv', draws, 'draws_resolved_1', true);
        r = INV.MOMENTS(g, x, variance, window, cfg, opt);
        % Independent integration of within-cell first and second moments
        edges = log10(g.nodes{1}(:));
        h = diff(edges); t = (edges(1:end-1)+edges(2:end))/2;
        n = h'*draws;
        mu = (h.*t)'*draws./n;
        v = sum(h.*((t-mu).^2+h.^2/12).*draws, 1)./n;
        third = sum(((edges(2:end)-mu).^4- ...
            (edges(1:end-1)-mu).^4)/4.*draws, 1)./n;
        fourth = sum(((edges(2:end)-mu).^5- ...
            (edges(1:end-1)-mu).^5)/5.*draws, 1)./n;
        modes = zeros(1, size(draws, 2));
        for j = 1:size(draws, 2)
            [~, index] = max(draws(:, j));
            local = log(draws(index-1:index+1, j));
            shift = h(index)/2*(local(1)-local(3))/ ...
                (local(1)-2*local(2)+local(3));
            modes(j) = 10^(t(index)+shift);
        end
        direct = [n; 10.^mu; 10.^sqrt(v); third./v.^1.5; ...
            fourth./v.^2; modes];
        empirical = sample_interval(direct);
        near(r.gibbs.interval, empirical, 1e-9);
        near(r.gibbs.TF_interval_1, [0, 0], 0);
        delta_sd = (log10(r.interval(2, 2))-log10(r.interval(2, 1)))/ ...
            (2*1.95996398454005);
        near(std(mu), delta_sd, 0.12*delta_sd);
    end

    function single_charge()
        [o, g, c, imp, opt] = fixture(1, 10000, false);
        opt.profile_check_1 = true;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        contains(r.interval(2, :), 180);
        contains(r.interval(3, :), 1.3);
        check(r.profile.resolved_1, 'Profile refits converge.');
        contains(r.profile.CMD_interval_nm, 180);
        check(r.one_population.information_resolved_1, 'Identified peak.');
        check(r.profile.agreement_checked_1 && ...
            r.profile.endpoint_difference_share_1 <= 0.10 && ...
            ~r.profile.disagreement_1, 'Profile agrees with Fisher.');
        opt.profile_check_1 = false;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(~r.profile.agreement_checked_1 && ...
            ~r.profile.disagreement_1 && ...
            isnan(r.profile.endpoint_difference_share_1), ...
            'An absent profile is unchecked, not a disagreement.');
    end

    function multiple_charge()
        [o, g, c, imp, opt] = fixture(1:3, 10000, false);
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        contains(r.interval(2, :), 180);
        contains(r.interval(3, :), 1.3);
        check(numel(r.one_population.parameter) == 3, 'Charges are tied.');
        check(r.variance_first.pass_count == 1 && ...
            r.variance_second.pass_count == 2, 'Two variance passes.');
        check(r.weighted_sensitivity.converged_1 && ...
            r.unweighted_sensitivity.converged_1, 'Sensitivity fits.');
        check(~r.second_population_detected_1, 'No untested population.');
    end

    function reduced_peak()
        [raw, g, c, imp, opt] = fixture(1:3, 10000, false);
        a = INV.KERNEL_1D(g, raw, c, imp, opt.kernel_draw);
        d1 = opt.kernel_draw; d1.charge_e = 1;
        a1 = INV.KERNEL_1D(g, raw, c, imp, d1);
        d = 1./sum(a1, 2);
        x = phantom(g, 5000, 180, 1.3);
        o = raw;
        o.route = 'B'; o.reduced = true; o.source_kind = 'smps_export';
        o.quantity = 'dN/dlog10Dm'; o.unit = 'cm^-3';
        o.mcc_on = false; o.dlc_on = true;
        o.values = d.*(a*x);
        o.diameter_nm = raw.diameter_nm;
        opt.raw_observation = raw;
        opt.variance_function = @(unused) pooled_variance(o, c, d.^2);
        opt.software_mode_nm = 175; opt.impactor_d50_nm = 1384;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        near(r.CMD_nm, 180, 0.02);
        near(r.GSD_1, 1.3, 2e-4);
        check(isnan(r.FN.value_1), 'Unvalidated reduction has no tail value.');
        near(r.software_comparison.fit_minus_mode_nm, r.CMD_nm-175, 0);
        near(r.software_comparison.impactor_minus_top_nm, 684, 0);
        opt.reduction_validated_1 = true; opt.charge_setting_known_1 = true;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(isfinite(r.FN.value_1), 'Validated conditional tail.');
        o = reduced_observation(g, x, true);
        use = o.diameter_nm >= 15 & o.diameter_nm <= 700;
        o.values = o.values(use); o.diameter_nm = o.diameter_nm(use);
        opt.variance_function = @(unused) pooled_variance(o, c, ...
            ones(numel(o.values), 1));
        r = INV.PEAK_FIT(o, g, c, [], opt);
        near(r.CMD_nm, 180, 0.02);
        check(isnan(r.FN.value_1), 'MCC-on has no tail inference.');
    end

    function concentration_view()
        [o, g, c, imp, opt] = fixture(1:3, 10000, false);
        counts = INV.PEAK_FIT(o, g, c, imp, opt);
        opt.raw_counts_count = o.values;
        o.values = o.values./o.sample_volume_cm3;
        o.quantity = 'raw concentration'; o.unit = 'cm^-3';
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        near(r.CMD_nm, counts.CMD_nm, 1e-10);
        near(r.GSD_1, counts.GSD_1, 1e-12);
    end

    function inverted_peak()
        g = midpoint_grid(15, 700, 120);
        c = cfg;
        c.scan.window_min_nm = g.nodes{1}(1);
        c.scan.window_max_nm = g.nodes{1}(end);
        o = reduced_observation(g, phantom(g, 1000, 180, 1.3), true);
        o.route = 'inverted'; o.reduced = false;
        opt = struct('distribution_covariance_cm6_inv', ...
            eye(g.Ne)+0.1*ones(g.Ne), 'profile_check_1', false);
        r = INV.PEAK_FIT(o, g, c, [], opt);
        near(r.CMD_nm, 180, 0.02);
        near(r.GSD_1, 1.3, 2e-4);
        contains(r.interval(2, :), 180);
    end

    function width_guard()
        g = midpoint_grid(15, 700, 120);
        c = cfg;
        c.scan.window_min_nm = g.nodes{1}(1);
        c.scan.window_max_nm = g.nodes{1}(end);
        o = reduced_observation(g, phantom(g, 1000, 180, 1.01), true);
        o.route = 'inverted'; o.reduced = false;
        opt = struct('distribution_covariance_cm6_inv', eye(g.Ne), ...
            'profile_check_1', false);
        r = INV.PEAK_FIT(o, g, c, [], opt);
        check(r.one_population.width_bound_1 && r.GSD_1 > 1, ...
            'Width guard is positive and flagged.');
        check(all(isnan(r.interval(:))), 'Bound intervals withheld.');
    end

    function guards()
        g = midpoint_grid(10, 1000, 12);
        expect(@() INV.MOMENTS(g, zeros(12, 1), eye(12), [15, 700], cfg), ...
            'sootMosaic:peak_statistics:EmptyWindow');
        expect(@() INV.STAT_RESPONSE([1, 2], eye(3)), ...
            'sootMosaic:STAT_RESPONSE:Input');
        [o, g, c, imp, opt] = fixture(1, 1000, false);
        c.nuisance.enabled = true;
        expect(@() INV.PEAK_FIT(o, g, c, imp, opt), ...
            'sootMosaic:PEAK_FIT:Config');
    end

    function profile_disagreement()
        % Ten expected counts leave a skewed likelihood in the CMD
        [o, g, c, imp, opt, expected] = fixture(1:3, 10, false);
        opt.profile_check_1 = true;
        stream = rng;
        rng(29031, 'twister');
        o.values = poisson_direct(expected);
        rng(stream);
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(r.profile.agreement_checked_1 && ...
            r.profile.endpoint_difference_share_1 > 0.10 && ...
            r.profile.disagreement_1, 'Disagreement is flagged.');
        share = max(abs(r.profile.CMD_interval_nm-r.interval(2, :)))/ ...
            (r.interval(2, 2)-r.interval(2, 1));
        near(r.profile.endpoint_difference_share_1, share, 1e-12);
        check(all(isfinite([r.CMD_nm, r.interval(2, :)])), ...
            'The flag keeps the Fisher interval.');
        case_detail = [r.interval(2, :), r.profile.CMD_interval_nm, share];
    end

    function mode_refinement()
        % Three window cells, a zero neighbor leaves the vertex unrefined
        g = midpoint_grid(10, 1000, 3);
        window = [g.nodes{1}(1), g.nodes{1}(end)];
        opt = struct('peak_fit', screen(false, 0));
        bare = [0; 1; 0.25];
        r = INV.MOMENTS(g, bare, 0.01*eye(3), window, cfg, opt);
        check(~r.mode_refined_1 && ~r.mode_boundary_1, ...
            'Interior mode without refinement.');
        near(r.mode_nm, g.elements(2), 1e-9*g.elements(2));
        check(all(isnan(r.interval(6, :))), 'Unrefined interval withheld.');
        filled = [0.5; 1; 0.25];
        r = INV.MOMENTS(g, filled, 0.01*eye(3), window, cfg, opt);
        check(r.mode_refined_1 && all(isfinite(r.interval(6, :))) && ...
            r.interval(6, 2) > r.interval(6, 1), 'Refined mode interval.');
        pages = 0.01*cat(3, eye(3), eye(3));
        opt.weights_1 = [0.5; 0.5];
        r = INV.MOMENTS(g, [filled, bare], pages, window, cfg, opt);
        check(~r.mode_refined_1 && all(isnan(r.interval(6, :))), ...
            'One unrefined weighted node withholds the interval.');
        opt.weights_1 = [1; 0];
        r = INV.MOMENTS(g, [filled, bare], pages, window, cfg, opt);
        check(r.mode_refined_1 && all(isfinite(r.interval(6, :))), ...
            'A node without weight does not withhold.');
    end

    function window_checks()
        % Raw counts, concentration weights at the channel diameters
        [o, g, c, imp, opt] = fixture(1:3, 10000, false);
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        weight = o.values./o.sample_volume_cm3;
        direct = 10^(weight'*log10(o.diameter_nm)/sum(weight));
        near(r.window_GM_nm, direct, 1e-9*direct);
        check(strcmp(r.window_GM_source, 'raw concentration per channel') ...
            && isfinite(r.model_window_GM_nm) && ...
            strcmp(r.inversion_check.status, 'unavailable') && ...
            isnan(r.inversion_check.CMD_nm), 'Observed GM without check.');
        % Evidence-selected full-kernel inversion of the same counts
        a = INV.KERNEL_1D(g, o, c, imp, opt.kernel_draw);
        v = INV.OBS_VARIANCE({{o}}, c, []);
        sd = sqrt(v.variance_mean_counts2(:));
        bayes = INV.BAYESF(a./sd, o.values./sd, g, ...
            struct('families_1', {{'tk2'}}));
        opt.evidence_inversion = bayes.selected_1{1};
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        inverted_median = count_median(g, bayes.selected_1{1}.map_cm3_inv);
        near(r.inversion_check.CMD_nm, inverted_median, 1e-8*inverted_median);
        near(r.inversion_check.minus_fit_nm, inverted_median-r.CMD_nm, ...
            1e-8*inverted_median);
        check(strcmp(r.inversion_check.status, 'computed') && ...
            abs(r.inversion_check.relative_1) < 0.02 && ...
            r.inversion_check.lambda_cm3 == ...
            bayes.selected_1{1}.lambda_cm3, 'Inversion check near the fit.');
        % Inverted rows at the grid centers of the window
        g = midpoint_grid(15, 700, 120);
        c = cfg;
        c.scan.window_min_nm = g.nodes{1}(1);
        c.scan.window_max_nm = g.nodes{1}(end);
        x = phantom(g, 1000, 180, 1.3);
        o = reduced_observation(g, x, true);
        o.route = 'inverted'; o.reduced = false;
        opt = struct('distribution_covariance_cm6_inv', eye(g.Ne), ...
            'profile_check_1', false);
        r = INV.PEAK_FIT(o, g, c, [], opt);
        m = INV.MOMENTS(g, x, [], ...
            [c.scan.window_min_nm, c.scan.window_max_nm], c);
        near(r.window_GM_nm, m.GM_nm, 1e-10*m.GM_nm);
        check(strcmp(r.window_GM_source, 'distribution cell quadrature'), ...
            'Cell quadrature of the supplied distribution.');
        opt.evidence_inversion = struct('map_cm3_inv', x, ...
            'lambda_cm3', 1, 'resolved_1', true);
        expect(@() INV.PEAK_FIT(o, g, c, [], opt), ...
            'sootMosaic:PEAK_FIT:Inversion');
    end

    function truncation_comparison()
        % Fitted MCC-off CMD against the computed MCC-on software mode
        comparison = truncation_table([700, 500, 400, 300, 250], 1384);
        check(all(isfinite(comparison(:))), 'Every window top compared.');
        near(comparison(:, 5), comparison(:, 4)-comparison(:, 3), 1e-9);
        near(comparison(:, 2), 1384-comparison(:, 1), 1e-9);
        case_detail = comparison;
    end

    function population_one()
        [o, g, c, imp, opt] = fixture(1:3, 10000, false);
        c.peak_fit.max_populations = 2;
        c.peak_fit.population_test.replicates = 100;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(r.population_test.resolved_1 && ...
            ~r.second_population_detected_1, 'Refuse a second population.');
    end

    function population_two()
        [o, g, c, imp, opt] = fixture(1:3, 60000, true);
        c.peak_fit.max_populations = 2;
        c.peak_fit.population_test.replicates = 100;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(r.population_test.resolved_1 && ...
            r.second_population_detected_1, ...
            'Admit two separated populations.');
        check(numel(r.second_population_sensitivity.CMD_nm) == 2, ...
            'Both conditional medians returned.');
    end

    function bootstrap_interval()
        [o, g, c, imp, opt] = fixture(1:3, 800, false);
        opt.bootstrap_max_count = 2400;
        r = INV.PEAK_FIT(o, g, c, imp, opt);
        check(r.bootstrap.replicates_count >= 300, 'Minimum draw count.');
        if r.bootstrap.resolved_1
            check(all(r.bootstrap.endpoint_relative_error_1(:) <= 0.05), ...
                'Endpoint precision.');
            contains(r.bootstrap.interval(2, :), 180);
        else
            check(all(isnan(r.bootstrap.interval(:))), ...
                'Unresolved is withheld.');
        end
    end

    function sampler_check()
        g = midpoint_grid(10, 1000, 4);
        x = [0.4; 1; 0.8; 0.3];
        covariance = 0.04*eye(4);
        opt = struct('posterior', struct('precision_cm6', 25*eye(4), ...
            'rhs_cm3', 25*x), 'peak_fit', screen(false, 0));
        opt.sampler_options = struct('burn_count', 500, ...
            'batch_count', 1000, 'max_draws_count', 16000, 'seed_1', 29019);
        window = [g.nodes{1}(1), g.nodes{1}(end)];
        r = INV.MOMENTS(g, x, covariance, window, cfg, opt);
        rng(29020, 'twister');
        draws = zeros(4, 20000);
        for j = 1:4
            lower = 0.5*erfc(x(j)/(0.2*sqrt(2)));
            probability = lower+(1-lower)*rand(1, 20000);
            draws(j, :) = x(j)+0.2*sqrt(2)*erfinv(2*probability-1);
        end
        direct_opt = struct('draws_cm3_inv', draws, ...
            'draws_resolved_1', true, 'peak_fit', screen(false, 0));
        direct = INV.MOMENTS(g, x, covariance, window, cfg, direct_opt);
        check(r.gibbs.resolved_1, 'Constrained sampler resolves.');
        scale = direct.gibbs.interval(:, 2)-direct.gibbs.interval(:, 1);
        check(all(all(abs(r.gibbs.interval-direct.gibbs.interval) <= ...
            0.12*max(scale, eps))), 'Independent truncated draws.');
    end

    function coverage()
        % Judging the 0.90 to 0.99 band against binomial counts. A rate of...
            % ...200 draws spreads by about 0.015 about its coverage, so 18...
            % ...observed rates held to the band fail a calibrated nominal...
            % ...95 percent interval for a sizeable share of seeds. Each...
            % ...combination fails when its Wilson interval at z = 3 (about...
            % ...0.05 familywise over 20 checks) lies outside the band, and...
            % ...the pooled rate of 1800 draws per statistic (spread about...
            % ...0.005) is held to the band itself
        % A fitted CMD spread below the...
            % ...observed window GM spread is a target, not an assumption,...
            % ...so both spreads are returned per combination without a...
            % ...threshold
        counts = [150, 800, 1500];
        truth = [180, 1.3];
        hits = zeros(9, 2);
        spread = zeros(9, 6);
        row = 0;
        for charge_count = 1:3
            for count = counts
                row = row+1;
                [o, g, c, imp, opt, expected] = ...
                    fixture(1:charge_count, count, false);
                fitted = zeros(200, 2);
                for j = 1:200
                    o.values = poisson_direct(expected);
                    r = INV.PEAK_FIT(o, g, c, imp, opt);
                    limits = r.interval(2:3, :)';
                    hits(row, :) = hits(row, :)+ ...
                        (truth >= limits(1, :) & truth <= limits(2, :));
                    fitted(j, :) = [r.CMD_nm, r.window_GM_nm];
                end
                spread(row, :) = [charge_count, count, ...
                    mean(fitted(:, 1)), std(fitted(:, 1)), ...
                    mean(fitted(:, 2)), std(fitted(:, 2))];
            end
        end
        check(all(isfinite(spread(:))), 'Window GM of every draw.');
        case_detail = [spread, hits];
        [lower, upper] = wilson(hits, 200, 3);
        check(all(upper(:) >= 0.90 & lower(:) <= 0.99), ...
            'CMD and GSD coverage of each charge and count combination.');
        pooled = sum(hits, 1)/1800;
        check(all(pooled >= 0.90 & pooled <= 0.99), ...
            'Pooled CMD and GSD coverage on independent fine-grid counts.');
    end

    function structured_scan()
        % Modes at 250 and 700 nm, 14.1-964.7 nm window, 1e6 counts
        % ...(structured)
        rng(29041, 'twister');
        [r, m] = window_scan([14.1, 964.7], 2.5, ...
            [0.7, 250, 1.5; 0.3, 700, 1.4], 1e6);
        check(r.population_test.resolved_1 && m.structure_flag_1 && ...
            m.interval_withheld_1 && ~m.screen_missing_1, ...
            'Rejected one population withholds GM and GSD intervals.');
        kept_points(m);
        case_detail = scan_summary(r, m);
    end

    function edge_scan()
        % One mode at 600 nm, 85.1-582.9 nm window, 1e3 counts (edge fraction)
        rng(29042, 'twister');
        [r, m] = window_scan([85.1, 582.9], 4.5, [1, 600, 1.6], 1e3);
        check(r.population_test.resolved_1 && m.edge_flag_1 && ...
            r.one_population.above_top_fraction_1 > 0.05 && ...
            m.interval_withheld_1, ...
            'Number above the top withholds GM and GSD intervals.');
        kept_points(m);
        case_detail = scan_summary(r, m);
    end

    function control_scan()
        % One broad mode at 250 nm, 14.1-964.7 nm window, 1e6 counts
        rng(29043, 'twister');
        [r, m] = window_scan([14.1, 964.7], 2.5, [1, 250, 2.0], 1e6);
        check(r.population_test.resolved_1 && ~m.structure_flag_1 && ...
            ~m.edge_flag_1 && ~m.screen_missing_1 && ...
            ~m.interval_withheld_1, 'Control screen passes.');
        kept_points(m);
        check(all(all(isfinite(m.interval(2:3, :)))) && ...
            all(m.interval(2:3, 2) > m.interval(2:3, 1)), ...
            'Control GM and GSD intervals stay.');
        check(strcmp(r.inversion_check.status, 'computed') && ...
            abs(r.inversion_check.relative_1) < 0.05, ...
            'Inversion check near the fit.');
        case_detail = scan_summary(r, m);
    end
end

function kept_points(m)
check(all(isfinite([m.GM_nm, m.GSD_1])), 'Point values kept.');
if m.interval_withheld_1
    check(all(all(isnan(m.interval(2:3, :)))), ...
        'Flagged scan withholds GM and GSD intervals.');
end
end

function s = scan_summary(r, m)
% CMD, GSD, above-top share, test p value, failed replicates, inversion...
    % ...check relative difference, window GM, in-window GM and GSD and...
    % ...withheld flag
s = [r.CMD_nm, r.GSD_1, r.one_population.above_top_fraction_1, ...
    r.population_test.p_1, r.population_test.failed_count, ...
    r.inversion_check.relative_1, ...
    r.window_GM_nm, m.GM_nm, m.GSD_1, m.interval_withheld_1];
end

function cfg = configuration(sheath_lpm, window_nm)
if nargin < 1, sheath_lpm = 2.5; end
if nargin < 2, window_nm = [15, 700]; end
root = fileparts(fileparts(mfilename('fullpath')));
path = fullfile(root, 'config', 'main_inv', 'main_inv_config.example.json');
data.scan = struct('dma_aerosol_flow_lpm', 0.3, ...
    'dma_sheath_flow_lpm', sheath_lpm, ...
    'dma_excess_flow_lpm', sheath_lpm, ...
    'dma_temperature_deg_c', 23, 'dma_pressure_kpa', 101.325, ...
    'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
    'neutralizer_on', true, 'particle_polarity', 'positive', ...
    'delay_s', 0.3, 'delay_adjustment_s', 0, 'bin_time_s', 0.02, ...
    'low_hold_s', 1, 'up_time_s', 120, 'high_hold_s', 2, ...
    'voltage_low_v', 10, 'voltage_high_v', 10000, ...
    'window_min_nm', window_nm(1), 'window_max_nm', window_nm(2));
data.instruments = struct('impactor_nozzle_cm', 0.071, ...
    'impactor_flow_lpm', 0.3);
data.penetration.tubes = {struct('id', 'synthetic path', ...
    'length_m', 0, 'bore_mm', 4, 'flow_lpm', 0.3)};
cfg = UTILS.LOAD_MAIN_INV_CONFIG(path, data);
cfg.cpc.unity_bound_citation = 'Synthetic efficiency bound';
cfg.cpc.unity_bound_max_deficit = 0.02;
cfg.si.cpc.unity_bound_max_deficit = 0.02;
cfg.cpc.unity_bound_min_diameter_nm = 1;
cfg.si.cpc.unity_bound_min_diameter_nm = 1e-9;
cfg.scan_response.enabled = false;
cfg.mode = 'smps_1d';
cfg.peak_fit.max_populations = 1;
cfg.rng_seed = 29019;
end

function [o, g, c, imp, opt, expected] = fixture(charges, count, two)
c = configuration();
g = midpoint_grid(5, 3000, 384);
fine = midpoint_grid(5, 3000, 1536);
o = raw_scan(c, logspace(log10(15), log10(700), 90)');
imp = impactor(1384);
opt = struct('kernel_draw', ...
    struct('charge_e', charges, 'diffusing_1', true), ...
    'bootstrap_max_count', 0, 'profile_check_1', false);
a = INV.KERNEL_1D(fine, o, c, imp, opt.kernel_draw);
x = phantom(fine, 1000, 180, 1.3);
if two
    x = phantom(fine, 1000, 60, 1.2)+phantom(fine, 1000, 350, 1.2);
end
expected = a*x;
o.sample_volume_cm3(:) = count/sum(expected);
expected = expected*count/sum(expected);
o.values = round(expected);
end

function o = raw_scan(c, diameter)
% Route A raw count rows at singly charged channel diameters (nm)
diameter = diameter(:);
n = numel(diameter);
[mu, ~, cc, params] = INV.GAS(296.15, 101325, diameter*1e-9, c);
z = params.constants.e_c*cc./(3*pi*mu*diameter*1e-9);
geometry = c.si.geometry;
voltage = c.si.scan.dma_sheath_flow_lpm*log(geometry.dma_outer_radius_m/ ...
    geometry.dma_inner_radius_m)./(2*pi*geometry.dma_length_m*z);
o = struct('route', 'A', 'reduced', false, 'quantity', 'raw counts', ...
    'unit', 'counts', 'source_kind', 'smps_database', ...
    'values', zeros(n, 1), 'voltage_v', voltage, ...
    'sample_volume_cm3', ones(n, 1), 'diameter_nm', diameter, ...
    'mode', 'smps_1d', 'campaign_id', 'synthetic', ...
    'condition_id', 'one', 'source_id', 'synthetic scan', 'scan_index', 1, ...
    'time_s', (0:n-1)'*0.02, 'classifier_time_s', (0:n-1)'*0.02, ...
    'bin_time_s', 0.02, 'dilution_applied', true, 'dilution_known', true);
end

function imp = impactor(d50_nm)
imp = struct('d50_m', d50_nm*1e-9, 'cut_factor_1', 1, ...
    'sharpness_1', 9, 'rho_kg_m3', 1000);
end

function comparison = truncation_table(tops, cut)
% A noise-free tandem peak below a fixed impactor cut. Per...
    % ...window top the MCC-off export is fitted through the charge...
    % ...copies, and its largest-size-first MCC-on reduction gives the...
    % ...software mode through MOMENTS. Rows of top, cut minus top,...
    % ...software mode, fitted CMD and fitted minus mode (nm)
g = midpoint_grid(5, 3000, 384);
x = phantom(g, 5000, 180, 1.4);
imp = impactor(cut);
comparison = zeros(numel(tops), 5);
for k = 1:numel(tops)
    c = configuration(2.5, [15, tops(k)]);
    rows = find(g.elements(:) >= 15 & g.elements(:) <= tops(k));
    raw = raw_scan(c, g.elements(rows));
    copies = cell(1, 3);
    for charge = 1:3
        copies{charge} = INV.KERNEL_1D(g, raw, c, imp, ...
            struct('charge_e', charge, 'diffusing_1', true));
    end
    single = sum(copies{1}, 2);
    off = (copies{1}+copies{2}+copies{3})*x./single;
    state = zeros(g.Ne, 1);
    state(rows) = largest_first(off, copies(2:3), single, rows, g.Ne);
    m = INV.MOMENTS(g, reduced_observation(g, state, true), [], ...
        [15, tops(k)], c);
    o = reduced_observation(g, off, false);
    o.diameter_nm = raw.diameter_nm;
    opt = struct('kernel_draw', ...
        struct('charge_e', 1:3, 'diffusing_1', true), ...
        'bootstrap_max_count', 0, 'profile_check_1', false, ...
        'raw_observation', raw, 'software_mode_nm', m.mode_nm, ...
        'impactor_d50_nm', cut);
    opt.variance_function = @(unused) pooled_variance(o, c, 1./single.^2);
    r = INV.PEAK_FIT(o, g, c, imp, opt);
    comparison(k, :) = [tops(k), ...
        r.software_comparison.impactor_minus_top_nm, ...
        m.mode_nm, r.CMD_nm, r.software_comparison.fit_minus_mode_nm];
end
end

function on = largest_first(off, copies, single, rows, n)
% Subtracting multiple charge copies from the top channel down, using...
    % ...only the channels already corrected, so particles above the top...
    % ...stay unknown to the reduction
on = zeros(numel(off), 1);
estimate = zeros(n, 1);
for i = numel(off):-1:1
    extra = 0;
    for k = 1:numel(copies)
        extra = extra+copies{k}(i, :)*estimate;
    end
    on(i) = max(0, off(i)-extra/single(i));
    estimate(rows(i)) = on(i);
end
end

function [r, m] = window_scan(window, sheath, populations, count)
% Window at 128 channels per decade. Poisson counts from...
    % ...a fine grid, an evidence-selected inversion of the same scan and...
    % ...the PEAK_FIT screen passed to MOMENTS. Populations are rows of...
    % ...number share, CMD (nm) and GSD
c = configuration(sheath, window);
c.peak_fit.max_populations = 2;
c.peak_fit.population_test.replicates = 100;
g = midpoint_grid(5, 3000, 384);
fine = midpoint_grid(5, 3000, 1536);
o = raw_scan(c, 10.^(log10(window(1)):1/128:log10(window(2)))');
imp = impactor(1384);
draw = struct('charge_e', 1:3, 'diffusing_1', true);
x = zeros(fine.Ne, 1);
for k = 1:size(populations, 1)
    x = x+phantom(fine, populations(k, 1), populations(k, 2), ...
        populations(k, 3));
end
expected = INV.KERNEL_1D(fine, o, c, imp, draw)*x;
o.sample_volume_cm3(:) = count/sum(expected);
o.values = poisson_direct(expected*count/sum(expected));
a = INV.KERNEL_1D(g, o, c, imp, draw);
v = INV.OBS_VARIANCE({{o}}, c, []);
sd = sqrt(v.variance_mean_counts2(:));
bayes = INV.BAYESF(a./sd, o.values./sd, g, struct('families_1', {{'tk2'}}));
selected = bayes.selected_1{1};
opt = struct('kernel_draw', draw, 'bootstrap_max_count', 0, ...
    'profile_check_1', false, 'evidence_inversion', selected);
r = INV.PEAK_FIT(o, g, c, imp, opt);
m = INV.MOMENTS(g, selected.map_cm3_inv, selected.covariance_cm6_inv, ...
    window, c, struct('peak_fit', r));
end

function d = count_median(g, x)
% Root of the cumulative number, linear in log10(d) within each cell
edges = log10(g.nodes{1}(:));
total = x(:)'*diff(edges);
cumulative = @(t) x(:)'*min(max(t-edges(1:end-1), 0), diff(edges));
d = 10^fzero(@(t) cumulative(t)-total/2, [edges(1), edges(end)], ...
    optimset('TolX', 1e-14));
end

function g = midpoint_grid(lo, hi, n)
h = log10(hi/lo)/n;
g = INV.Grid({10.^(log10(lo)+h*((1:n)-0.5))});
end

function x = phantom(g, n, median, gsd)
% Using independent midpoint subquadrature within each cell
edges = log10(g.nodes{1}(:));
t = edges(1:end-1)+diff(edges)*(((1:32)-0.5)/32);
s = log10(gsd);
x = mean(n/(sqrt(2*pi)*s)*exp(-0.5*((t-log10(median))/s).^2), 2);
end

function s = screen(reject, tail)
s = struct('population_test', struct('resolved_1', true, ...
    'rejected_1', reject), 'one_population', ...
    struct('above_top_fraction_1', tail));
end

function o = opt_single()
o = struct('mass_kg', [1; 4]);
end

function o = reduced_observation(g, x, mcc)
o = struct('values', x, 'quantity', 'dN/dlog10Dm', ...
    'unit', 'cm^-3', 'reduced', true, 'route', 'B', ...
    'source_kind', 'smps_export', 'mode', 'smps_1d', ...
    'mcc_on', mcc, 'dlc_on', true, 'diameter_nm', g.elements(:), ...
    'campaign_id', 'synthetic', 'condition_id', 'target', ...
    'source_id', 'synthetic target', 'scan_index', 1, ...
    'dilution_applied', true, 'dilution_known', true);
end

function r = pooled_variance(o, cfg, floor)
% Borrowing the pooled repeat law for a single target scan
calibration = o;
calibration.condition_id = 'calibration';
calibration.source_id = 'synthetic calibration';
repeats = cell(1, 3);
for k = 1:3
    repeats{k} = calibration;
    repeats{k}.scan_index = k;
    repeats{k}.values = (0.9+0.1*k)*max(o.values, 1);
end
pooled = INV.OBS_VARIANCE({{o}, repeats}, cfg, [], {floor, floor});
r = pooled(1);
end

function y = poisson_direct(mu)
% Counting arrivals independently of the fitting sampler
y = zeros(size(mu));
for k = 1:numel(mu)
    arrival = -log(rand);
    while arrival <= mu(k)
        y(k) = y(k)+1;
        arrival = arrival-log(rand);
    end
end
end

function [lower, upper] = wilson(hits, n, z)
% Wilson score limits of binomial rates (Wilson 1927)
p = hits/n;
center = (p+z^2/(2*n))/(1+z^2/n);
half = z*sqrt(p.*(1-p)/n+z^2/(4*n^2))/(1+z^2/n);
lower = center-half;
upper = center+half;
end

function q = sample_interval(x)
x = sort(x, 2);
q = x(:, ceil(size(x, 2)*[0.025, 0.975]));
end

function contains(interval, value)
check(all(isfinite(interval)) && interval(1) <= value && ...
    value <= interval(2), 'Known parameter lies in its interval.');
end

function near(actual, expected, tolerance)
check(isequal(size(actual), size(expected)) && ...
    all(isfinite(actual(:))) && ...
    all(abs(actual(:)-expected(:)) <= tolerance), 'Numerical comparison.');
end

function expect(fun, identifier)
caught = false;
try
    fun();
catch err
    caught = strcmp(err.identifier, identifier);
end
check(caught, 'Expected refusal.');
end

function check(condition, message)
if ~isscalar(condition) || ~condition
    error('sootMosaic:QA:InvPeakMomentsFailed', '%s', message);
end
end
