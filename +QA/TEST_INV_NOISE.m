function report = TEST_INV_NOISE()
% "TEST_INV_NOISE" checks observation variances on synthetic repeats.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: One structure per case with name and pass fields....
%         ...Failures raise sootMosaic:QA:InvNoiseFailed
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2017, Eqs. 8-9); Sipkens et al. (2020, part II,...
%     ...Eqs. 15-16); Sipkens et al. (2023, Eqs. 1, 3-6, Sec. 2.2).

report = repmat(struct('name', '', 'pass', false), 100, 1);
ncase = 0;
try
    path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'config', 'main_inv', 'main_inv_config.example.json');
    cfg = UTILS.LOAD_MAIN_INV_CONFIG(path, ...
        struct('scan', struct('counting_flow_lpm', 0.3)));
    cfg.mode = 'smps_1d';
    cfg.smps_1d.route = 'A';
    cfg.scan.dilution_factor = 1;
    names = {'single raw exposure', 'mean with unequal exposures', ...
        'fitted-count second pass', 'zero-count absolute floor', ...
        'deterministic Poisson quantile arithmetic', ...
        'split multiplicative recovery', ...
        'additive and multiplicative recovery', 'independent repeat structure', ...
        'pooled linear coefficients', 'pooled active boundary', ...
        'pooled zero-spread floor', 'pooled bootstrap propagation', ...
        'AAC route A pooled default', 'AAC route B pooled model', ...
        'dilution through observation', 'unidentified repeat reporting', ...
        'seeded bootstrap state', 'single scan borrows campaign fit', ...
        'paired raw bootstrap propagation', 'pooled per-scan floors', ...
        'distinct scan identities', 'negative classifier time support'};
    tests = {@single_raw, @unequal_exposure, @second_pass, @zero_floor, ...
        @poisson_quantiles, @split_repeat, @additive_repeat, ...
        @independent_repeat, @pooled, @pooled_boundary, @pooled_floor, ...
        @pooled_bootstrap, @aac_raw, @aac_reduced, @dilution, ...
        @unidentified, @seeded, @borrow, @raw_bootstrap, @scan_floors, ...
        @distinct_scans, @negative_classifier_time};
    for k = 1:numel(tests)
        tests{k}();
        add_case(names{k});
    end
    refusals();
    report = report(1:ncase);
catch err
    error('sootMosaic:QA:InvNoiseFailed', '%s: %s', ...
        err.identifier, err.message);
end

    function single_raw()
        g = raw_group([0; 4], 0.1, 'one');
        [r, m] = INV.OBS_VARIANCE({g}, cfg);
        near(r.mean_cm3_inv, [0; 40]);
        near(r.variance_mean_counts2, [1; 4]);
        near(r.variance_mean_cm6_inv, [100; 400]);
        check(~m.repeat_identified_ratio && r.nominal_exposure_ratio);
    end

    function unequal_exposure()
        g = raw_group([4 8; 8 16], [1 2], 'one');
        r = INV.OBS_VARIANCE({g}, cfg);
        near(r.mean_cm3_inv, [4; 8]);
        near(r.mean_counts, [6; 12]);
        near(r.variance_mean_cm6_inv, [1.5; 3]);
        near(r.variance_mean_counts2, [3; 6]);
        near(r.floor_mean_cm6_inv, [0.3125; 0.3125]);
    end

    function second_pass()
        g = raw_group([4 8; 8 16], [1 2], 'one');
        [r, m] = INV.OBS_VARIANCE({g}, cfg, {[6 12; 10 20]});
        near(r.variance_mean_cm6_inv, [2.25; 3.75]);
        near(r.variance_mean_counts2, [4.5; 7.5]);
        near(r.mean_cm3_inv, [4; 8]);
        check(r.pass_count == 2 && m.repeat_identified_ratio);
        r = INV.OBS_VARIANCE({g}, cfg, {zeros(2)});
        near(r.variance_mean_counts2, [0.5; 0.5]);
    end

    function zero_floor()
        g = raw_group(zeros(2), 0.1, 'one');
        r = INV.OBS_VARIANCE({g}, cfg);
        near(r.variance_mean_counts2, [0.5; 0.5]);
        near(r.variance_mean_cm6_inv, [50; 50]);
    end

    function poisson_quantiles()
        % Checking deterministic quantile arithmetic with counting alone
        % Sampling-error validation remains assigned to patch 31a
        g = raw_group([0 0 0 1 1 1 2 3], 2, 'one');
        c = cfg; c.variance.min_repeats = 9;
        [r, m] = INV.OBS_VARIANCE({g}, c);
        check(~m.repeat_identified_ratio && m.repeat_conditions_count == 0);
        near(r.mean_cm3_inv, 0.5);
        near(r.variance_mean_cm6_inv, 11/256);
        r = INV.OBS_VARIANCE({g}, c, {ones(1, 8)});
        near(r.variance_mean_cm6_inv, 1/32);
        near(var([0 0 0 1 1 1 2 3]/2, 0, 2)/8, 1/28);
    end

    function split_repeat()
        groups = split_groups(false, true);
        [r, m] = INV.OBS_VARIANCE(groups, cfg, [], [], [1 1 2 2; 1 2 1 2]);
        near([m.gamma2_cm6_inv; m.tau_within2_ratio2; ...
            m.tau_between2_ratio2], [0; 1/64; 1/16]);
        near(r(1).variance_mean_cm6_inv, [20; 128; 468]/9);
        near(r(1).within_mean_cm6_inv, [4; 64; 324]/9);
        near(r(1).between_mean_ratio2, 1/144);
        near(m.tau_between2_interval_ratio2, [1/16 1/16]);
        near(r(1).variance_interval_cm6_inv, repmat([20; 128; 468]/9, 1, 2));
        check(m.bootstrap_available_ratio);
        expected = {repmat(2*[16; 64; 144], 1, 9), ...
            repmat(2*[16; 64; 144], 1, 9)};
        [r, m] = INV.OBS_VARIANCE(groups, cfg, expected);
        near(m.tau_within2_ratio2, 1/64);
        near(m.tau_between2_ratio2, 1/16);
        near(r(1).variance_mean_counts2, [48; 384; 1584]/9);
    end

    function additive_repeat()
        [r, m] = INV.OBS_VARIANCE(split_groups(true, true), cfg);
        near([m.gamma2_cm6_inv; m.tau_within2_ratio2; ...
            m.tau_between2_ratio2], [4; 1/16; 1/16]);
        near(r(1).variance_mean_cm6_inv, [25; 289; 1369]/9);
    end

    function independent_repeat()
        [r, m] = INV.OBS_VARIANCE(split_groups(false, false), cfg);
        near(m.tau_within2_ratio2, 1/64);
        near(m.tau_between2_ratio2, 0);
        near(r(1).variance_mean_cm6_inv, [20; 128; 468]/9);
    end

    function raw_bootstrap()
        a = split_groups(false, false);
        b = split_groups(false, true, false);
        groups = {a{1}, b{2}};
        [r, m] = INV.OBS_VARIANCE(groups, cfg, [], [], [1 1 2 2; 1 2 1 2]);
        near(m.gamma2_cm6_inv_draws, zeros(1, 4));
        near(m.tau_within2_ratio2_draws, [1/64 1/128 1/128 0]);
        near(m.tau_between2_ratio2_draws, [0 1/32 1/32 1/16]);
        near([m.tau_within2_ratio2; m.tau_between2_ratio2], [1/128; 1/32]);
        for j = 1:2
            near(r(j).variance_mean_cm6_inv_draws(1, :), [20 18 18 16]/9);
            near(r(j).variance_mean_counts2_draws(1, :), [20 18 18 16]/9);
            near(r(j).between_mean_ratio2_draws, [0 1/288 1/288 1/144]);
            near(r(j).variance_mean_cm6_inv(1), 2);
            near(r(j).between_mean_ratio2, 1/288);
        end
        check(m.bootstrap_available_ratio);
    end

    function pooled()
        [r, m] = INV.OBS_VARIANCE(pooled_groups(1), cfg, [], {1, 1});
        near([m.a_cm6_inv; m.c_cm3_inv], [2; 0.5]);
        near(r(1).variance_mean_cm6_inv, [1.5; 3]);
        check(isempty(r(1).variance_mean_counts2));
    end

    function pooled_boundary()
        g = reduced_group([0 0; 2 4], 'one', 'smps');
        [r, m] = INV.OBS_VARIANCE({g}, cfg, [], {0.1});
        near([m.a_cm6_inv; m.c_cm3_inv], [0; 2/3]);
        near(r.variance_mean_cm6_inv, [0.05; 1]);
        g = reduced_group([0 2; 10 10], 'one', 'smps');
        [~, m] = INV.OBS_VARIANCE({g}, cfg, [], {0.1});
        near([m.a_cm6_inv; m.c_cm3_inv], [1; 0]);
    end

    function pooled_floor()
        g = reduced_group([2 2; 8 8], 'one', 'smps');
        [r, m] = INV.OBS_VARIANCE({g}, cfg, [], {[0.2; 0.8]});
        near([m.a_cm6_inv; m.c_cm3_inv], [0; 0]);
        near(r.variance_mean_cm6_inv, [0.1; 0.4]);
    end

    function pooled_bootstrap()
        [r, m] = INV.OBS_VARIANCE(pooled_groups(2), cfg, [], ...
            {0.1, 0.1}, [1 1 2 2; 1 2 1 2]);
        near([m.a_cm6_inv; m.c_cm3_inv], [3; 0.75]);
        near(m.a_cm6_inv_draws, [2 3 3 4]);
        near(m.c_cm3_inv_draws, [0.5 0.75 0.75 1]);
        near(r(1).variance_mean_cm6_inv_draws, ...
            [1.5 2.25 2.25 3; 3 4.5 4.5 6]);
        near(r(1).variance_interval_cm6_inv, [1.5 3; 3 6]);
    end

    function scan_floors()
        floors = {[1 9; 1 1], [1 9; 1 1]};
        [r, m] = INV.OBS_VARIANCE(pooled_groups(1), cfg, [], ...
            floors, [1 1 2 2; 1 2 1 2]);
        near([m.a_cm6_inv; m.c_cm3_inv], [2; 0.5]);
        near(r(1).floor_mean_cm6_inv, [2.5; 0.5]);
        near(r(1).variance_mean_cm6_inv, [3; 3]);
        near(r(1).variance_mean_cm6_inv_draws, 3*ones(2, 4));
        r = INV.OBS_VARIANCE(pooled_groups(2), cfg, [], ...
            floors, [1 1 2 2; 1 2 1 2]);
        near(r(1).variance_mean_cm6_inv_draws, ...
            [3 3.375 3.375 3.75; 3 4.5 4.5 6]);
        g = {reduced_group([2 2], 'one', 'smps'), ...
            reduced_group([8 8], 'two', 'smps')};
        r = INV.OBS_VARIANCE(g, cfg, [], {[1 9], 1});
        near(r(1).floor_mean_cm6_inv, 2.5);
        near(r(1).variance_mean_cm6_inv, 2.5);
    end

    function aac_raw()
        g = reduced_group([1 3; 6 10], 'one', 'aac_A');
        [r, m] = INV.OBS_VARIANCE({g}, cfg, [], {0.2});
        near([m.a_cm6_inv; m.c_cm3_inv], [0; 1]);
        near(r.variance_mean_cm6_inv, [1; 4]);
        check(isempty(r.poisson_mean_cm6_inv));
        check(numel(g{1}.variants) == 2);
    end

    function aac_reduced()
        g = reduced_group([1 3; 6 10], 'one', 'aac_B');
        r = INV.OBS_VARIANCE({g}, cfg, [], {0.2});
        near(r.variance_mean_cm6_inv, [1; 4]);
    end

    function dilution()
        g = raw_group([4; 8], 1, 'one');
        c = cfg; c.scan.dilution_factor = 2; c.scan.counting_flow_lpm = 3;
        scan = raw_scan([4; 8], 1);
        o = INV.OBSERVATION(scan, c);
        o.campaign_id = 'synthetic'; o.condition_id = 'one';
        o.source_id = 'synthetic_one';
        a = INV.OBS_VARIANCE({g}, cfg);
        b = INV.OBS_VARIANCE({{o}}, cfg);
        near(b.mean_cm3_inv, 2*a.mean_cm3_inv);
        near(b.variance_mean_cm6_inv, 4*a.variance_mean_cm6_inv);
        near(b.variance_mean_counts2, a.variance_mean_counts2);
    end

    function unidentified()
        [r, m] = INV.OBS_VARIANCE({raw_group([4 4], 1, 'one')}, cfg);
        check(~m.repeat_identified_ratio && ~m.bootstrap_available_ratio);
        check(all(isnan(m.tau_between2_interval_ratio2)));
        near(r.variance_mean_counts2, 2);
    end

    function seeded()
        state = rng;
        [~, a] = INV.OBS_VARIANCE(split_groups(false, true), cfg);
        [~, b] = INV.OBS_VARIANCE(split_groups(false, true), cfg);
        check(isequal(state, rng));
        check(isequal(a.bootstrap_condition_indices, b.bootstrap_condition_indices));
        check(isequal(size(a.tau_within2_ratio2_draws), [1 200]));
    end

    function borrow()
        groups = split_groups(false, true);
        groups{3} = raw_group([16; 64; 144], 1, 'three');
        [r, m] = INV.OBS_VARIANCE(groups, cfg);
        check(r(3).n_scans == 1 && m.repeat_conditions_count == 2);
        near(r(3).variance_mean_counts2, [20; 128; 468]);
        near(r(3).between_mean_ratio2, 1/16);
    end

    function distinct_scans()
        g = raw_group([4 4; 8 8], 1, 'one');
        r = INV.OBS_VARIANCE({g}, cfg);
        near(r.variance_mean_counts2, [2; 4]);
        g{2}.source_id = 'another_source'; g{2}.scan_index = 1;
        r = INV.OBS_VARIANCE({g}, cfg);
        near(r.variance_mean_counts2, [2; 4]);
    end

    function negative_classifier_time()
        scan = raw_scan([4; 8], 1);
        scan.data.scan.delay_s = 0.02;
        scan.data.scan.low_hold_s = 0.02;
        c = cfg; c.scan.counting_flow_lpm = 3;
        o = INV.OBSERVATION(scan, c);
        o.campaign_id = 'synthetic'; o.condition_id = 'one';
        o.source_id = 'synthetic_one';
        near(o.classifier_time_s, [-0.01; 0.01]);
        r = INV.OBS_VARIANCE({{o}}, cfg);
        near(r.variance_mean_counts2, [4; 8]);
    end

    function refusals()
        good = {raw_group([4 4; 8 8], 1, 'one')};
        changes = {'source_kind', 'smps_export', 'Route'; ...
            'quantity', 'dW', 'Route'; 'reduced', true, 'Route'; ...
            'unit', 'cm^-3', 'Route'; 'route', 'B', 'Route'; ...
            'mode', 'aac_1d', 'Route'; 'values', [1.5; 2], 'Counts'; ...
            'values', [-1; 2], 'Values'; 'values', [NaN; 2], 'Values'; ...
            'values', [Inf; 2], 'Values'; 'values', [1+1i; 2], 'Values'; ...
            'sample_volume_cm3', [0; 1], 'Exposure'; ...
            'sample_volume_cm3', [Inf; 1], 'Exposure'; ...
            'sample_volume_cm3', 1, 'Exposure'; ...
            'counts_are_approximate', true, 'Counts'; ...
            'dilution_known', false, 'Dilution'; ...
            'dilution_applied', false, 'Dilution'; ...
            'campaign_id', '', 'Labels'; 'voltage_v', [NaN; 2], 'Support'; ...
            'time_s', 0, 'Support'; 'classifier_time_s', 0, 'Support'; ...
            'voltage_v', 10, 'Support'; 'bin_time_s', 0, 'Support'; ...
            'bin_time_s', [0.02; -0.02], 'Support'; ...
            'voltage_v', [0; 10], 'Support'; ...
            'voltage_v', [-10; 10], 'Support'; ...
            'source_id', '', 'ScanIdentity'; ...
            'source_id', 1, 'ScanIdentity'; ...
            'scan_index', 0, 'ScanIdentity'; ...
            'scan_index', 1.5, 'ScanIdentity'; ...
            'scan_index', Inf, 'ScanIdentity'};
        for j = 1:size(changes, 1)
            g = good;
            g{1}{1}.(changes{j, 1}) = changes{j, 2};
            reject(@() INV.OBS_VARIANCE(g, cfg), changes{j, 3}, ...
                sprintf('reject %s variant %d', changes{j, 1}, j));
        end
        g = good; g{1}{2}.classifier_time_s = [0.2; 0.4];
        reject(@() INV.OBS_VARIANCE(g, cfg), 'RepeatSupport', 'reject shifted bins');
        g = [good, {raw_group([4 4; 8 8], 1, 'two')}];
        g{2}{1}.campaign_id = 'another';
        g{2}{2}.campaign_id = 'another';
        reject(@() INV.OBS_VARIANCE(g, cfg), 'PoolScope', 'reject campaign mixing');
        g = [good, {raw_group([4 4; 8 8], 1, 'two')}];
        g{2}{1}.condition_id = 'one'; g{2}{2}.condition_id = 'one';
        reject(@() INV.OBS_VARIANCE(g, cfg), ...
            'Condition', 'reject duplicate conditions');
        for key = {'source_id', 'scan_index'}
            g = good; g{1}{1} = rmfield(g{1}{1}, key{1});
            reject(@() INV.OBS_VARIANCE(g, cfg), 'ScanIdentity', ...
                ['reject missing ' key{1}]);
        end
        g = good; g{1}{2} = g{1}{1};
        reject(@() INV.OBS_VARIANCE(g, cfg), ...
            'ScanIdentity', 'reject duplicate scan within group');
        g = [good, good];
        g{2}{1}.condition_id = 'two'; g{2}{2}.condition_id = 'two';
        reject(@() INV.OBS_VARIANCE(g, cfg), ...
            'ScanIdentity', 'reject duplicate scan across conditions');
        g = {raw_group([4; 8; 12; 16], 1, 'one')};
        g{1}{1}.time_s = reshape(g{1}{1}.time_s, 2, 2);
        reject(@() INV.OBS_VARIANCE(g, cfg), 'Support', 'reject matrix raw support');
        g = [good, {reduced_group([1 3; 6 10], 'two', 'smps')}];
        reject(@() INV.OBS_VARIANCE(g, cfg), 'PoolScope', 'reject route mixing');
        c = cfg; c.variance.floor_counts = 0;
        reject(@() INV.OBS_VARIANCE(good, c), 'Floor', 'reject zero count floor');
        c = cfg; c.variance.min_repeats = 1;
        reject(@() INV.OBS_VARIANCE(good, c), 'Config', 'reject repeat minimum');
        c = cfg; c.variance.aac_model = 'poisson';
        reject(@() INV.OBS_VARIANCE(good, c), 'Config', 'reject AAC Poisson weights');
        c = cfg; c.variance.repeat_treatment = 'full_covariance';
        reject(@() INV.OBS_VARIANCE(good, c), 'Config', 'reject full repeat whitening');
        reject(@() INV.OBS_VARIANCE(good, cfg, {ones(3)}), ...
            'FittedCounts', 'reject fitted shape');
        reject(@() INV.OBS_VARIANCE(good, cfg, {[-1 1; 2 2]}), ...
            'FittedCounts', 'reject negative fit');
        g = split_groups(false, true);
        expected = {repmat([16; 64; 144], 1, 9), ...
            repmat([16; 64; 144], 1, 9)};
        expected{1}(1, :) = [8 8 8 8 8 8 8 8 80];
        reject(@() INV.OBS_VARIANCE(g, cfg, expected), ...
            'FittedCounts', 'reject unequal fitted concentration profiles');
        g = {raw_group([0 100], 1, 'one')};
        reject(@() INV.OBS_VARIANCE(g, cfg), ...
            'RepeatFit', 'reject unidentified positive repeat excess');
        reject(@() INV.OBS_VARIANCE(good, cfg, [], {1}), ...
            'Floor', 'reject concentration floor on counts');
        p = pooled_groups(1);
        reject(@() INV.OBS_VARIANCE(p, cfg), 'Floor', 'reject missing pooled floor');
        reject(@() INV.OBS_VARIANCE(p, cfg, [], {0, 1}), ...
            'Floor', 'reject zero pooled floor');
        bad_floors = {[1 9 1], [1 NaN; 1 1], [1 0; 1 1], ...
            [1 Inf; 1 1], [1 -1; 1 1]};
        for j = 1:numel(bad_floors)
            reject(@() INV.OBS_VARIANCE(p, cfg, [], {bad_floors{j}, 1}), ...
                'Floor', sprintf('reject pooled floor matrix %d', j));
        end
        for value = {100, [0; 200], [-100; 200]}
            g = p; g{1}{1}.diameter_nm = value{1};
            reject(@() INV.OBS_VARIANCE(g, cfg, [], {1, 1}), ...
                'Support', sprintf('reject diameter support %g', value{1}(1)));
        end
        g = {reduced_group([1; 2; 3; 4], 'one', 'smps')};
        g{1}{1}.diameter_nm = reshape(g{1}{1}.diameter_nm, 2, 2);
        reject(@() INV.OBS_VARIANCE(g, cfg, [], {1}), ...
            'Support', 'reject matrix diameter support');
        reject(@() INV.OBS_VARIANCE(p, cfg, {ones(2), ones(2)}, {1, 1}), ...
            'FittedRoute', 'reject Poisson fit on reduced data');
        reject(@() INV.OBS_VARIANCE(p, cfg, [], {1, 1}, [1 3; 1 2]), ...
            'Bootstrap', 'reject invalid resample');
        g = p; g{1}{2}.mcc_on = false;
        reject(@() INV.OBS_VARIANCE(g, cfg, [], {1, 1}), ...
            'RepeatSupport', 'reject mixed correction states');
        g = p; g{1}{1} = rmfield(g{1}{1}, 'dlc_on');
        reject(@() INV.OBS_VARIANCE(g, cfg, [], {1, 1}), ...
            'Correction', 'reject missing correction state');
        g = {reduced_group([1; 2], 'one', 'smps')};
        reject(@() INV.OBS_VARIANCE(g, cfg, [], {1}), ...
            'RepeatFit', 'reject missing pooled repeats');
        g = {reduced_group([1 1; 1 1], 'one', 'smps')};
        reject(@() INV.OBS_VARIANCE(g, cfg, [], {1}), ...
            'RepeatFit', 'reject constant-mean pooled fit');
        reject(@() INV.OBS_VARIANCE({}, cfg), 'Groups', 'reject empty groups');
        g = good; g{1}{1} = rmfield(g{1}{1}, 'quantity');
        reject(@() INV.OBS_VARIANCE(g, cfg), 'Observation', 'reject unlabeled input');
    end

    function reject(action, reason, name)
        caught = '';
        try
            action();
        catch err
            caught = err.identifier;
        end
        check(strcmp(caught, ['sootMosaic:OBS_VARIANCE:' reason]));
        add_case(name);
    end

    function add_case(name)
        ncase = ncase+1;
        report(ncase) = struct('name', name, 'pass', true);
    end

    function groups = split_groups(additive, between, independent)
        if nargin < 3, independent = true; end
        h = [1 1 1 1 1 1 1 1; 1 -1 1 -1 1 -1 1 -1; ...
            1 1 -1 -1 1 1 -1 -1; 1 -1 -1 1 1 -1 -1 1; ...
            1 1 1 1 -1 -1 -1 -1; 1 -1 1 -1 -1 1 -1 1; ...
            1 1 -1 -1 -1 -1 1 1; 1 -1 -1 1 -1 1 1 -1];
        if additive
            mu = [12; 60; 140];
            shot = [4; 8; 12]; within = mu/4; common = mu/4;
        else
            mu = [16; 64; 144];
            shot = [4; 8; 12]; within = mu/8; common = mu/4;
        end
        counts = mu + shot.*h(2:4, :) + ...
            double(independent)*within.*h(5:7, :) + ...
            double(between)*common.*h(8, :);
        counts(:, 9) = mu;
        groups = {raw_group(counts, 1, 'one'), raw_group(counts, 1, 'two')};
    end

    function groups = pooled_groups(multiplier)
        mu = [2; 8]; delta = sqrt([1.5; 3]);
        a = reduced_group([mu-delta, mu+delta], 'one', 'smps');
        delta = sqrt(multiplier)*delta;
        b = reduced_group([mu-delta, mu+delta], 'two', 'smps');
        groups = {a, b};
    end

    function group = raw_group(counts, volumes, id)
        group = cell(1, size(counts, 2));
        if isscalar(volumes), volumes = repmat(volumes, size(group)); end
        for j = 1:numel(group)
            scan = raw_scan(counts(:, j), volumes(j));
            scan.scan_index = j;
            c = cfg; c.scan.counting_flow_lpm = 3*volumes(j);
            o = INV.OBSERVATION(scan, c);
            o.campaign_id = 'synthetic'; o.condition_id = id;
            o.source_id = ['synthetic_' id];
            group{j} = o;
        end
    end

    function scan = raw_scan(counts, volume)
        scan = struct('source_kind', 'smps_database', 'scan_index', 1, ...
            'flags', {{}}, 'dead_time', zeros(size(counts)));
        scan.channels = struct('values', counts, 'quantity', 'raw counts', ...
            'time_s', (0:numel(counts)-1)'*0.02);
        scan.data.scan = struct('bin_time_s', 0.02, 'delay_s', 0, ...
            'delay_adjustment_s', 0, 'up_time_s', 1, ...
            'voltage_low_v', 10, 'voltage_high_v', 100, ...
            'low_hold_s', 0, 'high_hold_s', 0, 'counting_flow_lpm', 3*volume);
    end

    function group = reduced_group(values, id, kind)
        group = cell(1, size(values, 2));
        for j = 1:numel(group)
            scan = struct('scan_index', j, 'flags', {{}}, ...
                'source_kind', 'smps_export', 'software_statistics', struct());
            scan.channels = struct('values', values(:, j), ...
                'quantity', 'dW/dlogDp', ...
                'diameter_nm', (1:size(values, 1))'*100);
            scan.data.scan = struct('weight', 'Number', 'mcc_on', true, ...
                'dlc_on', true, 'software_dilution_factor', 1);
            c = cfg; c.smps_1d.route = 'B';
            correction = struct();
            if ~strcmp(kind, 'smps')
                scan.source_kind = 'aac_export';
                scan.conditions = struct(); scan.format = 'sass';
                scan.counter_cm3_inv = values(:, j);
                scan.sampling_period_s = 0.7; scan.readings_per_row = 3;
                scan.time_s = (1:size(values, 1))'*2.1;
                scan.corrected_spectrum = values(:, j);
                c.mode = 'aac_1d'; c.aac_1d.route = kind(end);
                c.aac_1d.counting_flow_lpm = 0.3;
                c.aac_1d.row_operation = 'both';
                ix = strcmp({c.reading.path}, 'aac_1d.counting_flow_lpm');
                c.reading(ix).source = 'registry';
                correction = struct('beta_ideal_ratio', 1, ...
                    'beta_nonideal_ratio', 1, 'software_efficiency_ratio', 1, ...
                    'counting_efficiency_ratio', 1, 'tube_penetration_ratio', 1);
            end
            o = INV.OBSERVATION(scan, c, correction);
            o.campaign_id = 'synthetic'; o.condition_id = id;
            o.source_id = ['synthetic_' id];
            group{j} = o;
        end
    end
end

function near(actual, expected)
check(isequal(size(actual), size(expected)) && all(isfinite(actual(:))) && ...
    all(abs(actual(:)-expected(:)) <= 1e-9*max(1, max(abs(expected(:))))));
end

function check(yes)
if ~isscalar(yes) || ~yes
    error('sootMosaic:QA:InvNoiseFailed', 'Unexpected synthetic result.');
end
end
