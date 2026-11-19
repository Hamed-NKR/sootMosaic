function report = TEST_INV_IMPORT()
% "TEST_INV_IMPORT" checks synthetic import, selection and observation data.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: One structure per case with name and pass fields....
%         ...Fixtures are created under tempname and removed on exit....
%         ...Any failed case raises sootMosaic:QA:InvImportFailed
% ----------------------------------------------------------------------- %
% Method: Wiedensohler et al. (2012, Appendices A4 and A5.1); Johnson et...
%     ...al. (2018, Eqs. 9-11); pooled variance identity.

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:InvImportFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
config_file = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'config', 'main_inv', 'main_inv_config.example.json');
cfg = UTILS.LOAD_MAIN_INV_CONFIG(config_file, ...
    struct('scan', struct('counting_flow_lpm', 0.3)));
cfg.mode = 'smps_1d';
cfg.smps_1d.route = 'B';
cfg.scan.dilution_factor = 20;
tests = {@smps_headers, @variable_window, @impactor_missing, ...
    @reduced_routes, @weight_errors, @dilution_rules, @selection_groups, ...
    @single_and_missing, @pooling, @selection_errors, @exclusion_rules, ...
    @aac_headers, @aac_fallback, @aac_exposure, @aac_cancellation, ...
    @aac_step, @database_roundtrip, @database_errors, @raw_observation, ...
    @data_precedence, @route_contract, @aac_distinct_nodes, ...
    @counting_sources, @polarity_signs, @voltage_holds, @counter_range};
names = {'SMPS labels and shifts', '235-channel variable window', ...
    'impactor availability', 'reduced quantities and flags', ...
    'weight and resolution refusals', 'dilution once and missing factor', ...
    'interior case exclusion and groups', 'single scan and finite counts', ...
    'successive pooled variance', 'selection validation', ...
    'exclusion codes and retained flags', 'AAC shuffled bidirectional scans', ...
    'AAC missing counter fallback', 'AAC row exposures and variance', ...
    'AAC route B factor cancellation', 'AACS step header', ...
    'database and csv identity', 'database schema and layout refusals', ...
    'raw exposure and route A refusal', 'instrument source precedence', ...
    'reduced consumer contract', 'AAC distinct diameter nodes', ...
    'recorded counting flow and AAC registry flag', 'recorded polarity signs', ...
    'delayed bins in voltage holds', 'detector single-count range'};
pass = false(size(tests));
for k = 1:numel(tests)
    try
        tests{k}();
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
    if pass(k), label = 'PASS'; else, label = 'FAIL'; end
    fprintf('%s %s\n', label, names{k});
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:InvImportFailed', '%d cases failed.', sum(~pass));
end

    function smps_headers()
        a = smps_fixture('a.csv', 'dW/dlogDp', 'Number', 3, false, false);
        b = smps_fixture('b.csv', 'dW/dlogDp', 'Number', 3, true, false);
        check(isequaln(a.scans{1}.channels, b.scans{1}.channels));
        check(isequaln(a.scans{1}.data, b.scans{1}.data));
        d = a.scans{1}.data.scan;
        near([d.counting_flow_lpm d.counter_inlet_flow_lpm ...
            d.dma_sheath_flow_lpm d.dma_temperature_deg_c d.dma_pressure_kpa ...
            d.logged_mean_free_path_nm d.logged_viscosity_pa_s], ...
            [0.3 0.9 4 24 99 70 1.9e-5]);
        check(~isfield(d, 'dma_aerosol_flow_lpm'));
        check(d.mcc_on == false && d.dlc_on == true);
        near(a.scans{1}.data.instruments.impactor_nozzle_cm, 0.071);
        near(a.scans{1}.data.instruments.impactor_flow_lpm, 0.8);
        near(d.impactor_d50_nm, 900);
        check(a.scans{1}.impactor_available);
        near([d.up_time_s d.retrace_time_s d.delay_s d.column_transit_s ...
            d.low_hold_s], [8 2 0.4 1.2 1]);
        check(isempty(a.scans{1}.purge_time_s));
    end

    function variable_window()
        a = smps_fixture('wide.csv', 'dW/dlogDp', 'Number', 235, true, false);
        check(numel(a.scans{1}.channels.values) == 235);
        check(a.scans{1}.data.scan.channels_per_decade == 128);
        near(a.scans{1}.channels.values, (1:235)');
        b = smps_fixture('narrow.csv', 'dW/dlogDp', 'Number', 7, false, false);
        check(numel(b.scans{1}.channels.values) == 7);
    end

    function impactor_missing()
        smps_fixture('impactor.csv', 'dW/dlogDp', 'Number', 3, false, false);
        file = fullfile(folder, 'impactor.csv');
        text = fileread(file);
        write(file, strrep(text, '0.071 cm cm', 'unknown'));
        a = INV.READ_SMPS(file);
        check(~a.scans{1}.impactor_available);
        check(~isempty(a.scans{1}.impactor_reason));
        write(file, strrep(text, 'Impactor Flow (L/min)', 'Absent Flow'));
        a = INV.READ_SMPS(file);
        check(~isfield(a.scans{1}.data.instruments, 'impactor_flow_lpm'));
        check(~a.scans{1}.impactor_available);
        write(file, strrep(text, 'Impactor D50 (nm)', 'Absent Cut'));
        a = INV.READ_SMPS(file);
        check(~a.scans{1}.impactor_available);
    end

    function reduced_routes()
        a = smps_fixture('reduced.csv', 'dW/dlogDp', 'Number', 3, false, false);
        b = smps_fixture('interval.csv', 'Concentration (dW)', 'Number', 3, false, false);
        sa = a.scans{1}; sb = b.scans{1};
        oa = INV.OBSERVATION(sa, cfg); ob = INV.OBSERVATION(sb, cfg);
        near(oa.values, ob.values);
        check(oa.reduced && oa.charge_components && ~oa.mcc_on && oa.dlc_on);
        check(~ob.mcc_on && ~ob.dlc_on);
        near(sb.channels.values, [1; 2; 3]/128);
        c = smps_fixture('mcc.csv', 'dW/dlogDp', 'Number', 3, false, true);
        oc = INV.OBSERVATION(c.scans{1}, cfg);
        check(~oc.charge_components && oc.mcc_on && oc.dlc_on);
        raw = smps_fixture('raw.csv', 'Raw Counts', 'Number', 3, false, false);
        check(strcmp(raw.scans{1}.channels.quantity, 'raw counts'));
        expect(@() INV.OBSERVATION(raw.scans{1}, cfg), 'OBSERVATION:ReducedUnits');
    end

    function weight_errors()
        for weight = {'Surface', 'Volume', 'Mass', ''}
            a = smps_fixture('weight.csv', 'dW/dlogDp', weight{1}, 3, false, false);
            expect(@() INV.OBSERVATION(a.scans{1}, cfg), 'OBSERVATION:Weight');
        end
        a = smps_fixture('resolution.csv', 'Concentration (dW)', 'Number', 3, false, false);
        scan = a.scans{1};
        scan.data.scan = rmfield(scan.data.scan, 'channels_per_decade');
        expect(@() INV.OBSERVATION(scan, cfg), 'OBSERVATION:Resolution');
    end

    function dilution_rules()
        a = smps_fixture('dilution.csv', 'dW/dlogDp', 'Number', 3, false, false);
        scan = a.scans{1};
        scan.data.scan.software_dilution_factor = 2;
        scan.campaign_dilution_factor = 20;
        obs = INV.OBSERVATION(scan, cfg);
        near(obs.values, [10; 20; 30]);
        near(scan.channels.values, [1; 2; 3]);
        expect(@() INV.OBSERVATION(obs, cfg), 'OBSERVATION:AlreadyDiluted');
        scan = rmfield(scan, 'campaign_dilution_factor');
        expect(@() INV.OBSERVATION(scan, cfg), 'OBSERVATION:MissingCampaignDilution');
        scan.campaign_dilution_factor = NaN;
        scan.data.scan.software_dilution_factor = 1;
        obs = INV.OBSERVATION(scan, cfg);
        check(~obs.dilution_known);
        near(obs.values, scan.channels.values);
    end

    function selection_groups()
        a = smps_fixture('select.csv', 'dW/dlogDp', 'Number', 3, false, false);
        cases = repmat(case_row(1, [1 2], 'g1'), 1, 3);
        cases(2).group = 'removed'; cases(2).exclude = true;
        cases(2).reason = 'settled exclusion'; cases(3).group = 'g2';
        out = INV.SELECT_SCANS(a, cases, cfg);
        check(isequal(out.case_indices, [1 3]));
        check(isequal(out.group_labels, {'g1', 'g2'}));
        check(isequal(out.group_members, {1, 2}));
        near(out.cases{1}.summary.mean, [2; 3; 4]);
        near(out.cases{1}.summary.variance, [2; 2; 2]);
        near(out.cases{1}.summary.n, [2; 2; 2]);
        near(out.cases{1}.scans{1}.campaign_dilution_factor, 20);
        check(~out.cases{1}.summary.dilution_applied);
    end

    function single_and_missing()
        a = smps_fixture('single.csv', 'dW/dlogDp', 'Number', 3, false, false);
        out = INV.SELECT_SCANS(a, case_row(1, 1, 'g'), cfg);
        near(out.cases{1}.summary.variance, zeros(3, 1));
        a.scans{2}.channels.values = [1; NaN; 3];
        out = INV.SELECT_SCANS(a, case_row(1, [1 2], 'g'), cfg);
        near(out.cases{1}.summary.n, [2; 1; 2]);
        near(out.cases{1}.summary.std, zeros(3, 1));
        a.scans{1}.channels.values(2) = NaN;
        out = INV.SELECT_SCANS(a, case_row(1, [1 2], 'g'), cfg);
        check(out.cases{1}.summary.n(2) == 0);
        check(isnan(out.cases{1}.summary.mean(2)));
    end

    function pooling()
        a = summary([10 20 30], [1 2 3; 3 4 5]);
        b = summary([20 30 40], [6 7 8]);
        c = summary([20 30 50], [8 9 10; 10 11 12]);
        ab = INV.POOL_SCANS({a, b});
        abc = INV.POOL_SCANS({ab, c});
        combined = INV.POOL_SCANS({a, b, c});
        near(ab.diameter_nm, [20; 30]);
        near(ab.mean, [4; 5]); near(ab.variance, [4; 4]);
        near(abc.mean, [6; 7]); near(abc.variance, [10; 10]);
        near(abc.n, [5; 5]); near(combined.variance, abc.variance);
        b.n(1) = 0; b.mean(1) = NaN; b.variance(1) = NaN;
        pooled = INV.POOL_SCANS({a, b});
        near(pooled.diameter_nm, 30);
        b.group = 'other';
        expect(@() INV.POOL_SCANS({a, b}), 'POOL_SCANS:Incompatible');
        b.group = 'g'; b.diameter_nm = [60; 70; 80];
        expect(@() INV.POOL_SCANS({a, b}), 'POOL_SCANS:CommonSupport');
    end

    function selection_errors()
        a = smps_fixture('errors.csv', 'dW/dlogDp', 'Number', 3, false, false);
        c = case_row(1, [1 1], 'g');
        expect(@() INV.SELECT_SCANS(a, c, cfg), 'SELECT_SCANS:Indices');
        c.indices = '1:2';
        expect(@() INV.SELECT_SCANS(a, c, cfg), 'SELECT_SCANS:Indices');
        c.indices = [1 2]; c.expected_count = 3;
        expect(@() INV.SELECT_SCANS(a, c, cfg), 'SELECT_SCANS:ScanCount');
        c.expected_count = []; c.indices = 8;
        expect(@() INV.SELECT_SCANS(a, c, cfg), 'SELECT_SCANS:MissingScan');
    end

    function exclusion_rules()
        a = smps_fixture('exclude.csv', 'dW/dlogDp', 'Number', 3, false, false);
        a.scans{1}.data.scan.valid = false;
        a.scans{2}.flags = {'diagnostic flag'};
        out = INV.SELECT_SCANS(a, case_row(1, [1 2], 'g'), cfg);
        check(out.cases{1}.accepted_count == 1);
        check(startsWith(out.excluded(1).reason, 'X1'));
        check(any(strcmp(out.cases{1}.scans{1}.flags, 'diagnostic flag')));
        a.scans{1}.data.scan.valid = true;
        c = case_row(1, [1 2], 'g');
        c.flow_checks = struct('field', 'dma_sheath_flow_lpm', 'setpoint_lpm', 4);
        a.scans{1}.data.scan.dma_sheath_flow_lpm = 4.4;
        out = INV.SELECT_SCANS(a, c, cfg);
        check(startsWith(out.excluded(1).reason, 'X2'));
        a.scans{1}.data.scan.dma_sheath_flow_lpm = 4;
        a.scans{1}.charger_concentration_cm3_inv = 2e6;
        out = INV.SELECT_SCANS(a, c, cfg);
        check(startsWith(out.excluded(1).reason, 'X3'));
        a.scans{1} = rmfield(a.scans{1}, 'charger_concentration_cm3_inv');
        a.scans{1}.timestamp = datetime(2025, 2, 4);
        out = INV.SELECT_SCANS(a, c, cfg);
        check(startsWith(out.excluded(1).reason, 'X4'));
    end

    function aac_headers()
        a = aac_fixture('a.sass', false, false, false);
        b = aac_fixture('b.sass', true, false, false);
        check(numel(a.scans) == 2);
        for j = 1:2
            near(a.scans{j}.channels.values, b.scans{j}.channels.values);
            near(a.scans{j}.conditions.aac_speed_rad_s, ...
                b.scans{j}.conditions.aac_speed_rad_s);
            near(a.scans{j}.row_spacing_s, 2.1);
            near(a.scans{j}.readings_per_row, 3);
        end
        near(a.scans{1}.channels.diameter_nm, [300; 200; 100]);
        near(a.scans{2}.channels.diameter_nm, [100; 200; 300]);
        near([a.scans{1}.scan_constant_s a.scans{2}.scan_constant_s], [10 -10]);
        check(a.scans{2}.lag_warning && ~a.scans{1}.lag_warning);
        near(a.scans{1}.lag_percent, [1; 2; 4]);
    end

    function aac_fallback()
        a = aac_fixture('missing.sass', false, true, false);
        check(strcmp(a.scans{1}.preferred_route, 'B'));
        check(~isempty(a.report));
        acfg = aac_config(); acfg.aac_1d.route = 'auto';
        expect(@() INV.OBSERVATION(a.scans{1}, acfg), 'OBSERVATION:MissingCorrection');
    end

    function aac_exposure()
        a = aac_fixture('exposure.sass', false, false, false);
        acfg = aac_config(); acfg.aac_1d.route = 'A';
        o = INV.OBSERVATION(a.scans{1}, acfg);
        near(o.values, [40; 80; 120]);
        near(o.variants{1}.approximate_counts, [21; 42; 63]);
        near(o.variants{2}.approximate_counts, [7; 14; 21]);
        near(o.variants{1}.sample_volume_cm3, 0.525);
        near(o.variants{2}.sample_volume_cm3, 0.175);
        near(o.variants{1}.poisson_variance_cm6_inv, 400*[2; 4; 6]/10.5);
        near(o.variants{2}.poisson_variance_cm6_inv, 400*[2; 4; 6]/3.5);
        acfg.aac_1d.row_operation = 'subsampled';
        single = INV.OBSERVATION(a.scans{1}, acfg);
        check(isscalar(single.variants));
        near(single.variants{1}.approximate_counts, [7; 14; 21]);
        readings = [1 2 3; 3 4 5; 5 6 7];
        near(mean(readings, 2), [2; 4; 6]);
        near(readings(:, 3), [3; 5; 7]);
    end

    function aac_cancellation()
        a = aac_fixture('factors.sass', false, false, false);
        acfg = aac_config(); acfg.aac_1d.route = 'B';
        factors = struct('beta_ideal_ratio', 0.2, 'beta_nonideal_ratio', 0.1, ...
            'software_efficiency_ratio', 0.8, 'counting_efficiency_ratio', 0.5, ...
            'tube_penetration_ratio', 0.25);
        source = [100; 200; 300];
        scan = a.scans{1};
        scan.channels.values = source * 0.5 * 0.25 * 0.1 / (0.8 * 0.2);
        o = INV.OBSERVATION(scan, acfg, factors);
        near(o.values, 20 * source);
        check(~isequal(o.values, scan.corrected_spectrum.values));
        bad = factors; bad.beta_nonideal_ratio = 0;
        expect(@() INV.OBSERVATION(scan, acfg, bad), 'OBSERVATION:CorrectionShape');
    end

    function aac_step()
        a = aac_fixture('step.aacs', true, false, true);
        near(a.scans{1}.averaging_period_s, 2);
        check(isempty(a.scans{1}.scan_constant_s));
        check(isempty(a.scans{1}.readings_per_row));
        acfg = aac_config(); acfg.aac_1d.route = 'A';
        o = INV.OBSERVATION(a.scans{1}, acfg);
        near(o.variants{1}.approximate_counts, [20; 40; 60]);
    end

    function database_roundtrip()
        [path, dbcfg] = database_fixture('roundtrip');
        a = INV.READ_SMPS_DB(path, dbcfg);
        dbcfg.inputs.database_reader = 'csv';
        b = INV.READ_SMPS_DB('', dbcfg);
        check(numel(a.scans) == 2 && isscalar(a.excluded));
        for j = 1:2
            scan = a.scans{j};
            check(isempty(scan.record.name) && isempty(scan.record.description));
            check(isnan(scan.record.aerosolRH) && isnan(scan.record.aerosolTemp));
            check(isnan(scan.run_header.errorCode));
            for key = {'description', 'interval', 'cpcD50Setting', 'location'}
                check(isempty(scan.run_header.(key{1})));
            end
            for key = {'name', 'productRevision', 'calibrationDate', ...
                    'impactorModel', 'rhtModel', 'rhtSerial'}
                check(isempty(scan.device.(key{1})));
            end
        end
        near(a.scans{1}.channels.values, [1; 3; 5; 7]);
        near(a.scans{1}.dead_time.values, [0; 1; 0; 2]);
        check(strcmp(a.scans{1}.dead_time.unit, 'unknown'));
        near(a.scans{1}.data.scan.bin_time_s, 0.02);
        near([a.scans{1}.data.scan.low_hold_s a.scans{1}.data.scan.up_time_s ...
            a.scans{1}.data.scan.high_hold_s a.scans{1}.data.scan.retrace_time_s], ...
            [0.02 0.08 0.02 0.04]);
        check(strcmp(a.scans{1}.timestamp.TimeZone, 'UTC'));
        check(isequaln(a.scans{1}.data, b.scans{1}.data));
        check(isequaln(a, b));
        near(a.scans{1}.channels.values, b.scans{1}.channels.values);
        check(a.scans{1}.data.scan.mcc_on && ~a.scans{1}.data.scan.dlc_on);
        near(a.scans{1}.data.scan.software_dilution_factor, 2);
        check(a.scans{1}.neutralizer_xray);
        check(a.scans{2}.run_id == 2 && a.scans{2}.scan_index == 3);
        check(~a.scans{2}.data.scan.mcc_on && a.scans{2}.data.scan.dlc_on);
        near(a.scans{2}.channels.values, [2; 4; 6; 8]);
        out = INV.SELECT_SCANS(a, case_row(1, [1 2], 'g'), cfg);
        check(out.cases{1}.accepted_count == 1 && numel(out.excluded) == 2);
    end

    function database_errors()
        required_nulls = {
            'CatenaDataRecord', 'tUp', 'InvalidNumber';
            'CatenaDataRecord', 'isValid', 'InvalidNumber';
            'CatenaDataRecord', 'timestamp', 'Timestamp';
            'CatenaDataRecord', 'hvPolarity', 'MissingField';
            'CatenaDataRecord', 'countsData', 'UndocumentedBlob';
            'CatenaDataRecord', 'deadTimeData', 'UndocumentedBlob';
            'CatenaHeaderRecord', 'refGasTemperature', 'InvalidNumber';
            'CatenaDeviceRecord', 'parentId', 'InvalidNumber'};
        for j = 1:size(required_nulls, 1)
            [null_path, null_cfg] = database_fixture(sprintf('null_%d', j), ...
                required_nulls{j, 1}, required_nulls{j, 2});
            suffix = ['READ_SMPS_DB:' required_nulls{j, 3}];
            expect(@() INV.READ_SMPS_DB(null_path, null_cfg), suffix);
            null_cfg.inputs.database_reader = 'csv';
            expect(@() INV.READ_SMPS_DB('', null_cfg), suffix);
        end
        [path, dbcfg] = database_fixture('db_errors');
        db = sqlite(path, 'connect');
        close_db = onCleanup(@() close(db));
        exec(db, 'UPDATE CatenaDataRecord SET countsData = X''0102'' WHERE id=1');
        expect(@() INV.READ_SMPS_DB(path, dbcfg), 'READ_SMPS_DB:UndocumentedBlob');
        exec(db, 'UPDATE CatenaDataRecord SET countsData = X''312C332C352C37'' WHERE id=1');
        expect(@() INV.READ_SMPS_DB(path, dbcfg), 'READ_SMPS_DB:UndocumentedBlob');
        exec(db, 'UPDATE CatenaDataRecord SET countsData = ''1,2'' WHERE id=1');
        expect(@() INV.READ_SMPS_DB(path, dbcfg), 'READ_SMPS_DB:BinCount');
        exec(db, 'UPDATE CatenaDataRecord SET countsData = ''1,3,5,7'', tUp=90 WHERE id=1');
        expect(@() INV.READ_SMPS_DB(path, dbcfg), 'READ_SMPS_DB:UndocumentedBinLayout');
        exec(db, 'ALTER TABLE CatenaDataRecord RENAME COLUMN sheathFlow TO missingFlow');
        expect(@() INV.READ_SMPS_DB(path, dbcfg), 'READ_SMPS_DB:MissingColumn', 'sheathFlow');
        dbcfg.inputs.database_reader = 'csv';
        csv = fullfile(dbcfg.inputs.csv_fallback_dir, 'CatenaDataRecord.csv');
        write(csv, strrep(fileread(csv), 'sheathFlow', 'missingFlow'));
        expect(@() INV.READ_SMPS_DB('', dbcfg), 'READ_SMPS_DB:MissingColumn', 'sheathFlow');
    end

    function raw_observation()
        [path, dbcfg] = database_fixture('raw');
        a = INV.READ_SMPS_DB(path, dbcfg);
        acfg = UTILS.LOAD_MAIN_INV_CONFIG(config_file, a.scans{1}.data);
        acfg.mode = 'smps_1d'; acfg.smps_1d.route = 'A';
        acfg.scan.dilution_factor = 20;
        acfg.scan.counter_inlet_flow_lpm = 0.9;
        acfg.scan.dma_aerosol_flow_lpm = 0.6;
        o = INV.OBSERVATION(a.scans{1}, acfg);
        near(o.sample_volume_cm3, 0.005*ones(4, 1));
        near(o.raw_concentration_cm3_inv, [200; 600; 1000; 1400]);
        check(o.provisional && o.charge_components && ~o.dead_time.used_in_exposure);
        near(o.values, [1; 3; 5; 7]);
        b = smps_fixture('refuse.csv', 'Raw Counts', 'Number', 3, false, false);
        expect(@() INV.OBSERVATION(b.scans{1}, acfg), 'OBSERVATION:RawSource');
        acfg.mode = 'tandem'; acfg.observation.route = 'A';
        tandem = INV.OBSERVATION(a.scans{1}, acfg);
        near(tandem.raw_concentration_cm3_inv, o.raw_concentration_cm3_inv);
    end

    function data_precedence()
        a = smps_fixture('precedence.csv', 'dW/dlogDp', 'Number', 3, false, false);
        campaign.values.scan.dma_sheath_flow_lpm = 8;
        campaign.reasons.scan.dma_sheath_flow_lpm = 'Synthetic recorded setpoint.';
        resolved = UTILS.LOAD_MAIN_INV_CONFIG(config_file, a.scans{1}.data, campaign);
        near(resolved.scan.dma_sheath_flow_lpm, 4);
        check(~isempty(resolved.reading));
    end

    function route_contract()
        a = smps_fixture('contract.csv', 'dW/dlogDp', 'Number', 3, false, true);
        o = INV.OBSERVATION(a.scans{1}, cfg);
        check(o.reduced && any(strcmp(o.allowed_consumers, 'MOMENTS')));
        check(~any(strcmp(o.allowed_consumers, 'KERNEL_1D')));
        acfg = cfg; acfg.smps_1d.route = 'A';
        expect(@() INV.OBSERVATION(a.scans{1}, acfg), 'OBSERVATION:RawSource');
    end

    function aac_distinct_nodes()
        a = aac_fixture('distinct.sass', false, false, false);
        a.scans{2}.channels.diameter_nm = [110; 210; 310];
        check(isempty(intersect(a.scans{1}.channels.diameter_nm, ...
            a.scans{2}.channels.diameter_nm)));
        out = INV.SELECT_SCANS(a, case_row(1, [1 2], 'g'), cfg);
        check(out.cases{1}.accepted_count == 2 && isempty(out.cases{1}.summary));
        check(numel(out.cases{1}.scans) == 2);
    end

    function counting_sources()
        [path, dbcfg] = database_fixture('counting');
        a = INV.READ_SMPS_DB(path, dbcfg);
        scan = a.scans{1};
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data);
        c.mode = 'smps_1d'; c.smps_1d.route = 'A'; c.scan.dilution_factor = 20;
        o = INV.OBSERVATION(scan, c);
        near(o.sample_volume_cm3, 0.005*ones(4, 1));
        check(strcmp(o.counting_flow_source, 'data'));
        campaign.values.scan.counting_flow_lpm = 0.6;
        campaign.reasons.scan.counting_flow_lpm = 'Synthetic per-scan record';
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data, campaign);
        near(c.scan.counting_flow_lpm, 0.3);
        scan.data.scan = rmfield(scan.data.scan, 'counting_flow_lpm');
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data, campaign);
        c.mode = 'smps_1d'; c.smps_1d.route = 'A'; c.scan.dilution_factor = 20;
        o = INV.OBSERVATION(scan, c);
        near(o.sample_volume_cm3, 0.01*ones(4, 1));
        check(strcmp(o.counting_flow_source, 'campaign'));
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data);
        c.mode = 'smps_1d'; c.smps_1d.route = 'A';
        check(isempty(c.scan.counting_flow_lpm));
        expect(@() INV.OBSERVATION(scan, c), 'OBSERVATION:MissingRecordedInput');
        c.scan.counting_flow_lpm = 0.3;
        expect(@() INV.OBSERVATION(scan, c), 'OBSERVATION:MissingRecordedInput');
        reduced = smps_fixture('missing_flow.csv', 'dW/dlogDp', 'Number', 3, false, false);
        c.smps_1d.route = 'B';
        expect(@() INV.OBSERVATION(reduced.scans{1}, c), ...
            'OBSERVATION:MissingRecordedInput');
        a = aac_fixture('counting.sass', false, false, false);
        scan = a.scans{1};
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data);
        c.mode = 'aac_1d'; c.aac_1d.route = 'A'; c.scan.dilution_factor = 20;
        o = INV.OBSERVATION(scan, c);
        near(o.variants{1}.approximate_counts, [21; 42; 63]);
        check(strcmp(o.counting_flow_source, 'registry'));
        check(any(contains(o.report, 'aac_1d.counting_flow_lpm')) && ...
            any(contains(o.report, 'instrument registry')));
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data, campaign);
        c.mode = 'aac_1d'; c.aac_1d.route = 'A';
        o = INV.OBSERVATION(scan, c);
        near(o.variants{1}.approximate_counts, [42; 84; 126]);
        check(strcmp(o.counting_flow_source, 'campaign') && isempty(o.report));
        scan.data.scan.counting_flow_lpm = 0.9;
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data, campaign);
        c.mode = 'aac_1d'; c.aac_1d.route = 'A';
        o = INV.OBSERVATION(scan, c);
        near(o.variants{1}.approximate_counts, [63; 126; 189]);
        check(strcmp(o.counting_flow_source, 'data') && isempty(o.report));
    end

    function polarity_signs()
        smps_fixture('polarity.csv', 'dW/dlogDp', 'Number', 3, false, false);
        file = fullfile(folder, 'polarity.csv');
        original = fileread(file);
        [path, dbcfg] = database_fixture('polarity');
        db = sqlite(path, 'connect');
        close_db = onCleanup(@() close(db));
        csv = fullfile(dbcfg.inputs.csv_fallback_dir, 'CatenaDataRecord.csv');
        original_csv = fileread(csv);
        hv = {'Negative', 'Positive'}; particle = {'positive', 'negative'};
        for j = 1:2
            write(file, strrep(original, 'HV Polarity,Negative', ['HV Polarity,' hv{j}]));
            a = INV.READ_SMPS(file);
            exec(db, ['UPDATE CatenaDataRecord SET hvPolarity = ' ...
                char(39) hv{j} char(39)]);
            b = INV.READ_SMPS_DB(path, dbcfg);
            write(csv, strrep(original_csv, 'Negative', hv{j}));
            csvcfg = dbcfg; csvcfg.inputs.database_reader = 'csv';
            d = INV.READ_SMPS_DB('', csvcfg);
            for imported = {a, b, d}
                scan = imported{1}.scans{1};
                check(strcmp(scan.data.scan.particle_polarity, particle{j}));
                c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data);
                check(strcmp(c.scan.particle_polarity, particle{j}));
            end
        end
    end

    function voltage_holds()
        [path, dbcfg] = database_fixture('holds');
        a = INV.READ_SMPS_DB(path, dbcfg); scan = a.scans{1};
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, scan.data);
        c.mode = 'smps_1d'; c.smps_1d.route = 'A';
        scan.data.scan.delay_s = 0.02;
        o = INV.OBSERVATION(scan, c);
        near(o.classifier_time_s, [-0.01; 0.01; 0.03; 0.05]);
        near(o.voltage_v, 10*exp(log(10)*[0; 0.01; 0.03; 0.05]/0.08));
        check(isequal(o.outside_ramp, [true; false; false; false]));
        check(any(contains(o.flags, 'recorded voltage holds')));
        scan.data.scan.delay_s = -0.02;
        o = INV.OBSERVATION(scan, c);
        near(o.voltage_v(end), 100);
        check(o.outside_ramp(end));
        scan.data.scan.delay_s = 0.04;
        expect(@() INV.OBSERVATION(scan, c), 'OBSERVATION:TimingSupport');
    end

    function counter_range()
        near(cfg.exclusion.counter_limit_cm3_inv, 200000);
        a = aac_fixture('range.sass', false, false, false);
        a.scans{1}.counter_cm3_inv = [199999; 200000; 1];
        a.scans{2}.counter_cm3_inv = [200001; 1; 1];
        c = case_row(1, [1 2], 'g'); c.dilution_factor = 100;
        out = INV.SELECT_SCANS(a, c, cfg);
        check(out.cases{1}.accepted_count == 1);
        check(out.cases{1}.scans{1}.scan_index == 1);
        check(startsWith(out.excluded(1).reason, 'X3'));
        [path, dbcfg] = database_fixture('range');
        a = INV.READ_SMPS_DB(path, dbcfg);
        a.scans{1}.channels.values = [19999; 20000; 1; 1];
        a.scans{2}.channels.values = [20001; 1; 1; 1];
        c.indices = [1 3];
        out = INV.SELECT_SCANS(a, c, cfg);
        check(out.cases{1}.accepted_count == 1);
        check(out.cases{1}.scans{1}.scan_index == 1);
        check(any(startsWith({out.excluded.reason}, 'X3')));
        a.scans{1}.data.scan = rmfield(a.scans{1}.data.scan, 'counting_flow_lpm');
        campaign.values.scan.counting_flow_lpm = 0.3;
        campaign.reasons.scan.counting_flow_lpm = 'Synthetic scan record';
        resolved = UTILS.LOAD_MAIN_INV_CONFIG(config_file, struct(), campaign);
        out = INV.SELECT_SCANS(a, c, resolved);
        check(out.cases{1}.accepted_count == 1);
        resolved = UTILS.LOAD_MAIN_INV_CONFIG(config_file);
        expect(@() INV.SELECT_SCANS(a, c, resolved), 'SELECT_SCANS:MissingRecordedInput');
    end

    function acfg = aac_config()
        acfg = cfg; acfg.mode = 'aac_1d';
        acfg.aac_1d.counting_flow_lpm = 0.3;
        acfg.aac_1d.row_operation = 'both';
    end

    function c = case_row(file_index, indices, group)
        c = struct('file_index', file_index, 'indices', indices, 'group', group, ...
            'dilution_factor', 20, 'exclude', false, 'reason', '', 'expected_count', []);
    end

    function p = summary(d, values)
        p = struct('diameter_nm', d(:), 'mean', mean(values, 1)', ...
            'variance', var(values, 0, 1)', 'n', size(values, 1)*ones(numel(d), 1), ...
            'quantity', 'dW/dlogDp', 'unit', 'cm^-3', 'group', 'g', ...
            'dilution_applied', false);
    end

    function check(value)
        if ~isscalar(value) || ~value
            error('sootMosaic:QA:InvImportFailed', 'Unexpected fixture result.');
        end
    end

    function near(a, b)
        check(isequal(size(a), size(b)) && ...
            all(abs(a(:)-b(:)) <= 1e-12 * max(1, max(abs(b(:))))));
    end

    function expect(action, suffix, detail)
        if nargin < 3, detail = ''; end
        caught = ''; message = '';
        try
            action();
        catch err
            caught = err.identifier;
            message = err.message;
        end
        if ~strcmp(caught, ['sootMosaic:' suffix]) || ~contains(message, detail)
            error('sootMosaic:QA:InvImportFailed', ...
                'Expected sootMosaic:%s (%s); got %s: %s', ...
                suffix, detail, caught, message);
        end
    end

    function result = smps_fixture(name, units, weight, count, shuffled, mcc)
        dlc = ~strcmp(units, 'Concentration (dW)');
        meta = {'Units', units; 'Weight', weight; 'Channels/Decade', '128'; ...
            'Multiple Charge Correction', lower(mat2str(mcc)); ...
            'Diffusion Loss Correction', lower(mat2str(dlc)); 'HV Polarity', 'Negative'; ...
            'Neutralizer Model', '3088'; 'Tube Length (cm)', '30'; ...
            'Tube Diameter (cm)', '0.5'; 'Reference Gas Viscosity (Pa*s)', '1.8e-5'; ...
            'Reference Mean Free Path (m)', '6e-8'; 'Reference Gas Temperature (K)', '290'; ...
            'Reference Gas Pressure (kPa)', '100'; 'Sutherland Constant (K)', '110'};
        meta_count = size(meta, 1);
        lines = cell(meta_count+5, 1);
        for j = 1:meta_count, lines{j} = strjoin(meta(j, :), ','); end
        lines{meta_count+1} = 'Impactor Model,0.071 cm cm,Impactor S/N,synthetic';
        labels = {'Scan Number', 'DateTime Sample Start', 'Detector Status', ...
            'Classifier Errors', 'Communication Status', 'Neutralizer Status', ...
            'Detector Inlet Flow (L/min)', 'Detector Counting Flow (L/min)', ...
            'Impactor Flow (L/min)', 'Impactor D50 (nm)', 'Sheath Flow (L/min)', ...
            'Sheath Temp (C)', 'Sheath Pressure (kPa)', 'Mean Free Path (m)', ...
            'Gas Viscosity (Pa*s)', 'Low Voltage (V)', 'High Voltage (V)', ...
            'Lower Size (nm)', 'Upper Size (nm)', 'Scan Time (s)', 'Retrace Time (s)', ...
            'DMA Column transit time Tf (s)', 'DMA Exit to Optical Detector Td (s)', ...
            'DMA at Low Voltage (TLOW) (s)', 'Adjustment (s)', 'Dilution Factor', ...
            'Mode (nm)', 'Geo. Mean (nm)', 'Geo. Std. Dev', 'Total Concentration (#/cm3)'};
        values = {'1', '01/03/2024 12:00:00', 'Normal Scan', 'Normal Scan', ...
            '0', 'ON', '0.9', '0.3', '0.8', '900', '4', '24', '99', '7e-8', ...
            '1.9e-5', '10', '100', '10', '1000', '8', '2', '1.2', '0.4', ...
            '1', '0', '1', '30', '35', '1.5', '123'};
        channel_labels = arrayfun(@(j) sprintf('%.10g', 10*10^((j-1)/128)), ...
            1:count, 'UniformOutput', false);
        labels = [labels, channel_labels];
        order = 1:numel(labels);
        if shuffled, order = [2:2:numel(labels), 1:2:numel(labels)]; end
        lines{meta_count+2} = ',,,,Particle Conc. by Midpt (nm)';
        lines{meta_count+3} = [strjoin(labels(order), ',') ','];
        for j = 1:2
            channel_values = (1:count)+2*(j-1);
            if strcmp(units, 'Concentration (dW)'), channel_values = channel_values/128; end
            row = [values, arrayfun(@(v) sprintf('%.17g', v), channel_values, ...
                'UniformOutput', false)];
            row{1} = num2str(j);
            lines{meta_count+3+j} = strjoin(row(order), ',');
        end
        file = fullfile(folder, name);
        write(file, strjoin(lines, newline));
        result = INV.READ_SMPS(file);
    end

    function result = aac_fixture(name, shuffled, missing_counter, stepped)
        tab = char(9);
        kind = 'AAC SASS Scan';
        timing = {'Scan Time (s):', '7', 'Transit time (s):', '1', ...
            'Delay time (s):', '0.4', 'CPC Sampling period (s):', '0.7'};
        if stepped
            kind = 'AAC Step Scan';
            timing = {'Size class/dec:', '12', 'Transit time (s):', '1', ...
                'Extra delay time (s):', '0.4', 'Averaging period (s):', '2'};
        end
        lines = {kind; strjoin({'Time:', '12:00:00', 'Date:', '2024-03-01 (yyyy-mm-dd)'}, tab); ...
            strjoin({'Cylinder Temperature (C):', '20', 'Sample Flow (lpm):', '0.8', ...
            'Sheath Temperature (C):', '25', 'Sheath Pressure (Pa):', '100000', ...
            'Ambient Temperature (C):', '23', 'Ambient Humidity (%):', '30', ...
            'Mass-Mobility Prefactor:', '1000', 'Mass-Mobility Exponent:', '3'}, tab); ...
            strjoin(timing, tab); strjoin({'Start size (nm):', '100', ...
            'End size< (nm):', '300', 'Start tau (ns):', '20', 'End tau< (ns):', '80'}, tab)};
        blocks = cell(2, 1);
        for s = 1:2
            scan_lines = cell(8, 1);
            line_count = 1;
            scan_lines{line_count} = strjoin({'SCAN', num2str(s), 'of', '2'}, tab);
            if ~stepped
                line_count = line_count + 1;
                scan_lines{line_count} = strjoin({'Size Class/dec:', '12', 'Start Speed (rad/s):', ...
                    '100', 'End Speed (rad/s):', '200', 'Scan Constant:', num2str(30-20*s)}, tab);
            end
            labels = {'Scan Time (s)', 'Real Time', 'Size (nm)', ...
                'Size Spectral Density (dN/dLog(Da)/cc)', ...
                'Corrected Size Spectral Density (dN/dLog(Da)/cc)', 'Tau (ns)', ...
                'Tau Spectral Density (dN/dLog(Tp)/cc)', ...
                'Corrected Tau Spectral Density (dN/dLog(Tp)/cc)', ...
                'Serial Detector (#/cc)', 'Speed (rad/s)', 'Sheath (lpm)', ...
                'Sheath Temp (C)', 'Classifier Pressure (Pa)', ...
                'Scan Ramp Time (s)', 'Scan Ramp Speed (rad/s)', 'Speed Error (%)'};
            if stepped, labels(1:2) = {'Datum#', 'Time'}; end
            order = 1:numel(labels);
            if missing_counter, order(order == 9) = []; end
            if stepped, order(order >= 14) = []; end
            if shuffled, order = fliplr(order); end
            line_count = line_count + 1;
            scan_lines{line_count} = strjoin(labels(order), tab);
            for j = 1:3
                d = 400-100*j;
                if s == 2, d = 100*j; end
                time = 0.7 + (j-1)*2.1;
                if stepped, time = j; end
                row = {num2str(time), sprintf('12:00:%02d', j), num2str(d), ...
                    num2str(10*j), num2str(100*j), num2str(20*j), ...
                    num2str(5*j), num2str(50*j), num2str(2*j), ...
                    num2str(100+j), '4', '25', '100000', num2str(time), ...
                    num2str(100+j), num2str(2^(j-1))};
                line_count = line_count + 1;
                scan_lines{line_count} = strjoin(row(order), tab);
            end
            line_count = line_count + 1;
            scan_lines{line_count} = strjoin({'END OF SCAN', num2str(s), 'of', '2'}, tab);
            if s == 2
                line_count = line_count + 1;
                scan_lines{line_count} = 'WARNING speed feedback lag.';
            end
            blocks{s} = scan_lines(1:line_count);
        end
        lines = [lines; vertcat(blocks{:}); {'END OF FILE'}];
        file = fullfile(folder, name);
        write(file, strjoin(lines, newline));
        result = INV.READ_AAC(file);
    end

    function [path, dbcfg] = database_fixture(name, missing_table, missing_column)
        if nargin < 2, missing_table = ''; missing_column = ''; end
        sub = fullfile(folder, name); mkdir(sub);
        path = fullfile(sub, 'fixture.db');
        dbcfg = cfg; dbcfg.inputs.database_reader = 'sqlite';
        dbcfg.inputs.csv_fallback_dir = sub;
        db = sqlite(path, 'create');
        close_db = onCleanup(@() close(db));
        data_names = {'id', 'timestamp', 'dataIndex', 'parentId', 'tLow', 'tUp', ...
            'tHigh', 'tDown', 'vLow', 'vHigh', 'purgeTime', 'samplesPerSecond', ...
            'sheathFlow', 'aerosolFlow', 'gasTemperature', 'gasPressure', ...
            'gasViscosity', 'meanFreePath', 'timeDelay', 'lowerSize', 'upperSize', ...
            'countsData', 'deadTimeData', 'timeDelayAdjustment', 'd50', 'isValid', ...
            'neutralizerXray', 'detectorInletFlow', 'hvPolarity', 'dilution', ...
            'name', 'description', 'aerosolRH', 'aerosolTemp', ...
            'Detector Counting Flow (L/min)'};
        missing_text = string(missing);
        data = {1, '2024-03-01T12:00:00.000Z', 1, 1, 20, 80, 20, 40, 10, 100, ...
            9, 50, 4, 0.6, 24, 99, 1.9e-5, 7e-8, 0.005, 10, 1000, ...
            '1,3,5,7', '0,1,0,2', 0, 900, 1, 1, 0.9, 'Negative', 2, ...
            missing_text, missing_text, NaN, NaN, 0.3};
        invalid = data; invalid{1} = 2; invalid{3} = 2; invalid{26} = 0;
        invalid{22} = 'undocumented invalid scan';
        invalid{5} = NaN;
        second = data; second{1} = 3; second{4} = 2;
        second{22} = '2,4,6,8';
        head_names = {'id', 'parentId', 'multiChargeCorrection', 'diffusionLossCorrection', ...
            'refGasTemperature', 'refGasPressure', 'refGasViscosity', 'refMeanFreePath', ...
            'sutherlandConstant', 'tubeLength', 'tubeDiameter', 'dmaInnerRadius', ...
            'dmaOuterRadius', 'dmaLength', 'description', 'interval', ...
            'errorCode', 'cpcD50Setting', 'location'};
        head = {11, 1, 1, 0, 290, 100, 1.8e-5, 6e-8, 110, 30, 0.5, 0, 0, 0, ...
            missing_text, missing_text, NaN, missing_text, missing_text};
        second_head = head; second_head(1:4) = {5, 2, 0, 1};
        device_names = {'id', 'parentId', 'model', 'dmaModel', 'cpcModel', ...
            'neutralizerModel', 'impactorModel', 'name', 'productRevision', ...
            'calibrationDate', 'rhtModel', 'rhtSerial'};
        device = {1, 1, '3082', '3081', '3789', '3088', missing_text, ...
            missing_text, missing_text, missing_text, missing_text, missing_text};
        second_device = device; second_device(1:2) = {2, 2};
        make_table('CatenaDataRecord', data_names, [data; invalid; second]);
        make_table('CatenaHeaderRecord', head_names, [head; second_head]);
        make_table('CatenaDeviceRecord', device_names, [device; second_device]);

        function make_table(table_name, columns, rows)
            if strcmp(table_name, missing_table)
                j = find(strcmp(columns, missing_column));
                if isnumeric(rows{1, j}), rows{1, j} = NaN;
                else, rows{1, j} = missing_text;
                end
            end
            types = cell(size(columns));
            integer_columns = {'id', 'dataIndex', 'parentId', 'isValid', ...
                'neutralizerXray', 'multiChargeCorrection', ...
                'diffusionLossCorrection', 'aerosolRH', 'errorCode'};
            for j = 1:numel(columns)
                if any(strcmp(columns{j}, integer_columns)), kind = ' INTEGER';
                elseif isnumeric(rows{1, j}), kind = ' REAL';
                else, kind = ' TEXT';
                end
                types{j} = ['"' columns{j} '"' kind];
            end
            exec(db, ['CREATE TABLE ' table_name ' (' strjoin(types, ',') ')']);
            csv_lines = cell(size(rows, 1)+1, 1);
            csv_lines{1} = strjoin(columns, ',');
            for r = 1:size(rows, 1)
                sql_values = cell(size(columns)); csv_values = cell(size(columns));
                for j = 1:numel(columns)
                    value = rows{r, j};
                    if isscalar(value) && ismissing(value)
                        sql_values{j} = 'NULL';
                        value = '';
                    elseif isnumeric(value)
                        value = sprintf('%.17g', value); sql_values{j} = value;
                    else
                        sql_values{j} = ['''' strrep(value, '''', '''''') ''''];
                    end
                    csv_values{j} = ['"' strrep(value, '"', '""') '"'];
                end
                exec(db, ['INSERT INTO ' table_name ' VALUES (' strjoin(sql_values, ',') ')']);
                csv_lines{r+1} = strjoin(csv_values, ',');
            end
            write(fullfile(sub, [table_name '.csv']), strjoin(csv_lines, newline));
        end
    end

    function write(file, text)
        fid = fopen(file, 'wb');
        if fid < 0, error('sootMosaic:QA:InvImportFailed', 'Cannot write fixture.'); end
        closer = onCleanup(@() fclose(fid));
        fwrite(fid, [strrep(text, sprintf('\r\n'), newline) newline], 'char');
    end
end
