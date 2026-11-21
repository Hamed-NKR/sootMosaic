function report = TEST_INV_CHARGE()
% "TEST_INV_CHARGE" checks bipolar charge fractions on synthetic inputs.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: One structure per case with name and pass fields....
%         ...Failures raise sootMosaic:QA:InvChargeFailed
% ----------------------------------------------------------------------- %
% Method: Wiedensohler (1988, Eqs. 1-2, Table 2, p. 388); Wiedensohler...
%     ...et al. (2012, Appendix A5, Table A7, pp. 681-682); 3082 manual...
%     ...(2016, Eqs. B-2 and B-3, Tables B-2 and B-3, pp. B-10 and B-11),...
%     ...after Knobel et al. (2013); Gopalakrishnan et al. (2013, Eq. 10,...
%     ...Table 2, spherical row, pp. 140 and 143).
% Reference fractions are independent power-sum evaluations of the tables.

state = warning;
[message, identifier] = lastwarn;
cleanup = onCleanup(@() restore(state, message, identifier));
try
    warning('on', 'sootMosaic:CHARGE_FRAC:OutsideRange');
    ids = {'soft_xray_3082_tableB3', 'kr85_wiedensohler', ...
        'gopalakrishnan_2013'};
    names = {'default soft x-ray table', 'corrected Kr-85 tables', ...
        'spherical cubic table', 'unnormalized diagnostics', ...
        '1000 nm boundary', 'signed higher charges and recorded gas', ...
        'adaptive bipolar tail', 'adaptive positive tail', ...
        'range warnings and stops', 'unresolved third-model ratio', ...
        'input refusals', 'strict registry and loader selection'};
    tests = {@default_table, @kr_table, @cubic_table, @diagnostics, ...
        @boundary, @higher_charges, @bipolar_tail, @positive_tail, ...
        @ranges, @missing_ratio, @refusals, @registry};
    expected = reference_fractions();
    jumps = NaN(3, 5);
    pass = false(size(tests));
    for k = 1:numel(tests)
        tests{k}();
        pass(k) = true;
    end
    printed_percent = [0.17 16.35 71.03 12.35 0.10; ...
        5.67 27.42 42.36 20.75 3.24; 15.09 18.60 18.28 14.33 8.95];
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
    fprintf('Boundary jumps, rows by model and columns n=-2:2:\n');
    disp(jumps);
    fprintf('Table 2 differences in percentage points:\n');
    disp(100*expected{2} - printed_percent);
    fprintf('Third-model boundary: MissingIonMobilityRatio\n');
catch err
    error('sootMosaic:QA:InvChargeFailed', '%s (%s)', ...
        err.message, err.identifier);
end

    function default_table()
        [f, info] = INV.CHARGE_FRAC([30 100 500]*1e-9, -2:2, ...
            296.15, 101325);
        near(f, expected{1}, 2e-12);
        check(strcmp(info.model_id, ids{1}), 'Default model.');
        near(info.ion_mobility_ratio_1, .975, 0);
        check(isequal(info.charge_e, -2:2), 'Column order.');
        check(~any(info.below_range_mask_1(:)), 'Inside lower limits.');
        check(isempty(info.tail_bound_frac), 'Explicit charges have no tail.');
        f = evaluate([30; 100; 500]*1e-9, [2 0 -1], 1);
        near(f, expected{1}(:, [5 3 2]), 2e-12);
    end

    function kr_table()
        near(evaluate([30 100 500]*1e-9, -2:2, 2), expected{2}, 2e-12);
        root = fileparts(fileparts(mfilename('fullpath')));
        raw = jsondecode(fileread(fullfile(root, 'config', ...
            'instruments', 'charging.json')));
        % Checking every Table B-2 entry against the Table A7 transcription
        table_b2 = [-26.3328 -2.3197 -.0003 -2.3484 -44.4756; ...
            35.9044 .6175 -.1014 .6044 79.3772; ...
            -21.4608 .6201 .3073 .4800 -62.8900; ...
            7.0867 -.1105 -.3372 .0013 26.4492; ...
            -1.3088 -.1260 .1023 -.1553 -5.7480; ...
            .1051 .0297 -.0105 .0320 .5049];
        near(raw.models(2).coefficients, table_b2, 0);
    end

    function cubic_table()
        near(evaluate([30 100 500]*1e-9, -2:2, 3), expected{3}, 2e-12);
    end

    function diagnostics()
        [f, info] = INV.CHARGE_FRAC(100e-9, -2:2, 296.15, 101325);
        near(f(4), .2295, 5e-5);
        near(info.sum_requested_frac, sum(expected{1}(2, :)), 2e-12);
        [f, info] = evaluate(100e-9, -2:2, 2);
        near(info.sum_requested_frac, 1.006796649569760, 2e-12);
        check(info.sum_requested_frac > 1, 'Fractions were renormalized.');
        near(f, expected{2}(2, :), 2e-12);
    end

    function boundary()
        polynomial = [.112776860379927 .123888216252263 ...
            .129981037753031 .113794166729040 .095308141296592; ...
            .126066588352448 .138452244294238 .123480960785860 ...
            .103896280490904 .075352905023547; ...
            .108701861062371 .133786489842553 .129267237849317 ...
            .118294288574949 .088730662901820];
        for j = 1:3
            near(evaluate(1000*1e-9, -2:2, j), polynomial(j, :), 2e-12);
            near(evaluate(1000e-9*(1-1e-8), -2:2, j), ...
                polynomial(j, :), 3e-9);
        end
        for j = 1:2
            ratio = [.975 .875];
            [f, info] = evaluate(1000e-9*(1+1e-8), -2:2, j);
            near(f, reference_high(1000e-9*(1+1e-8), -2:2, ...
                296.15, ratio(j)), 2e-14);
            check(all(info.above_range_mask_1), 'Upper branch mask.');
            jumps(j, :) = reference_high(1000e-9, -2:2, ...
                296.15, ratio(j)) - polynomial(j, :);
        end
        % Keeping the measured boundary jump without a continuity threshold
        expect(@() evaluate(1000e-9*(1+1e-8), -2:2, 3), ...
            'CHARGE_FRAC:MissingIonMobilityRatio');
    end

    function higher_charges()
        ratio = [.975 .875];
        for j = 1:2
            near(evaluate(100e-9, [-3 3], j), ...
                reference_high(100e-9, [-3 3], 296.15, ratio(j)), 2e-14);
            near(evaluate(1400e-9, -3:3, j), ...
                reference_high(1400e-9, -3:3, 296.15, ratio(j)), 2e-14);
            opts = struct('Model', ids{j});
            f = INV.CHARGE_FRAC(100e-9, [-3 3], 320, 90000, opts);
            near(f, reference_high(100e-9, [-3 3], 320, ratio(j)), 2e-14);
            near(INV.CHARGE_FRAC(100e-9, [-3 3], 320, 45000, opts), ...
                f, 2e-14);
            near(INV.CHARGE_FRAC(100e-9, -2:2, 320, 90000, opts), ...
                expected{j}(2, :), 2e-12);
        end
    end

    function bipolar_tail()
        sizes_nm = [30 100 500 700 1400 2000];
        limits_e = [2 3 7 8 12 14; 2 3 7 9 13 15];
        tails_frac = [6.908724697926e-8 .000102855747802 ...
            .000329088978561 .000606071914916 .000389913640617 ...
            .000596548261469; 7.432022335408e-8 .000116439781545 ...
            .000514021443507 .000243121006520 .000378608283482 ...
            .000893402620340];
        for j = 1:2
            for h = 1:numel(sizes_nm)
                [f, info] = evaluate(sizes_nm(h)*1e-9, [], j);
                q = limits_e(j, h);
                check(info.max_charge_e == q, 'Adaptive bipolar limit.');
                check(isequal(info.charge_e, -q:q), 'Adaptive columns.');
                near(info.tail_bound_frac, tails_frac(j, h), 2e-12);
                check(info.tail_bound_frac + f(1) + f(end) >= .001, ...
                    'The selected charge limit is not minimal.');
            end
        end
        [~, info] = evaluate([100 700 30]*1e-9, [], 1);
        check(info.max_charge_e == 8, 'Largest grid diameter selection.');
        near(info.tail_diameter_m, 700e-9, 1e-21);
        opts = struct('MaxCharge_e', 6);
        expect(@() INV.CHARGE_FRAC(700e-9, [], 296.15, 101325, opts), ...
            'CHARGE_FRAC:TailNotConverged');
        opts.MaxCharge_e = 2;
        expect(@() INV.CHARGE_FRAC(2000e-9, [], 296.15, 101325, opts), ...
            'CHARGE_FRAC:TailNotConverged');
    end

    function positive_tail()
        limits_e = [7 11 13; 7 9 11];
        sizes_nm = [700 1400 2000];
        for j = 1:2
            opts = struct('Model', ids{j}, 'TailPolarity', 'positive');
            for h = 1:3
                [f, info] = INV.CHARGE_FRAC(sizes_nm(h)*1e-9, [], ...
                    296.15, 101325, opts);
                q = limits_e(j, h);
                check(info.max_charge_e == q, 'Adaptive positive limit.');
                check(isequal(info.charge_e, 1:q), 'Positive columns.');
                check(info.tail_bound_frac < .001 && ...
                    info.tail_bound_frac + f(end) >= .001, 'Positive tail.');
            end
        end
        opts = struct('Model', ids{2}, 'TailPolarity', 'negative');
        [f, info] = INV.CHARGE_FRAC(700e-9, [], 296.15, 101325, opts);
        check(info.max_charge_e == 8, 'Adaptive negative limit.');
        check(isequal(info.charge_e, -8:-1), 'Negative columns.');
        check(info.tail_bound_frac < .001 && ...
            info.tail_bound_frac + f(1) >= .001, 'Negative tail.');
    end

    function ranges()
        lastwarn('');
        [f, info] = evaluate(10e-9, [-2 2], 1);
        [~, id] = lastwarn;
        check(strcmp(id, 'sootMosaic:CHARGE_FRAC:OutsideRange'), ...
            'Missing lower-range warning.');
        near(f, [0 0], 0);
        check(all(info.below_range_mask_1), 'Lower branch mask.');
        check(all(isfinite(evaluate(20e-9, [-2 2], 1))), '20 nm endpoint.');
        check(all(isfinite(evaluate(1e-9, -1:1, 2))), '1 nm endpoint.');
        check(all(isnan(evaluate(.5e-9, -2:2, 1))), 'Below 1 nm.');
        check(all(isnan(evaluate(4e-9, -2:2, 3))), 'Below 5 nm.');
        check(all(isfinite(evaluate(5e-9, -2:2, 3))), '5 nm endpoint.');
        opts = struct('RangePolicy', 'stop');
        expect(@() INV.CHARGE_FRAC(10e-9, 2, 296.15, 101325, opts), ...
            'CHARGE_FRAC:OutsideRange');
        expect(@() INV.CHARGE_FRAC(1001e-9, 0, 296.15, 101325, opts), ...
            'CHARGE_FRAC:OutsideRange');
        expect(@() INV.CHARGE_FRAC(.5e-9, [], 296.15, 101325), ...
            'CHARGE_FRAC:TailUnavailable');
    end

    function missing_ratio()
        expect(@() evaluate(100e-9, 3, 3), ...
            'CHARGE_FRAC:MissingIonMobilityRatio');
        expect(@() evaluate(100e-9, [], 3), ...
            'CHARGE_FRAC:MissingIonMobilityRatio');
        expect(@() evaluate(1400e-9, 0, 3), ...
            'CHARGE_FRAC:MissingIonMobilityRatio');
    end

    function refusals()
        for value = {0, -1, NaN, Inf, 1i, [], ones(2)}
            expect(@() evaluate(value{1}, 1, 1), ...
                'CHARGE_FRAC:InvalidDiameter');
        end
        for value = {[1 1], .5, NaN, Inf, 1i, ones(2), 2*flintmax}
            expect(@() evaluate(100e-9, value{1}, 1), ...
                'CHARGE_FRAC:InvalidCharge');
        end
        expect(@() INV.CHARGE_FRAC(100e-9, 1, 0, 101325), 'GAS:InvalidState');
        expect(@() INV.CHARGE_FRAC(100e-9, 1, 296.15, NaN), ...
            'GAS:InvalidState');
        options = {struct('Model', 'missing'), ...
            struct('RangePolicy', 'ignore'), ...
            struct('TailTolerance_frac', 0), struct('MaxCharge_e', 1), ...
            struct('TailPolarity', 'other'), struct('Unknown', 1), []};
        for j = 1:numel(options)
            suffix = 'CHARGE_FRAC:InvalidOptions';
            if j == 1, suffix = 'CHARGE_FRAC:UnknownModel'; end
            expect(@() INV.CHARGE_FRAC(100e-9, 1, 296.15, 101325, ...
                options{j}), suffix);
        end
    end

    function registry()
        root = fileparts(fileparts(mfilename('fullpath')));
        directory = fullfile(root, 'config', 'instruments');
        r = UTILS.CONFIG_READ(fullfile(directory, 'charging.json'), ...
            fullfile(directory, 'instruments.keys.json'), ...
            struct('Strict', true));
        for j = 1:3
            check(strcmp(r.models{j}.coefficients_state, 'ready'), ...
                'Coefficient marker.');
            check(isequal(size(r.models{j}.coefficients), ...
                [6-2*(j == 3) 5]), 'Coefficient shape.');
        end
        check(isempty(r.models{3}.ion_mobility_ratio), 'Unresolved ratio.');
        cfg = UTILS.LOAD_MAIN_INV_CONFIG(fullfile(root, 'config', ...
            'main_inv', 'main_inv_config.example.json'));
        near(cfg.charging.coefficients, r.models{1}.coefficients, 0);
        check(~any(endsWith({cfg.pending.path}, '.coefficients')), ...
            'Coefficient tables must not remain pending.');
        check(any(strcmp({cfg.pending.path}, ...
            'charging.gopalakrishnan_2013.ion_mobility_ratio')), ...
            'Missing ratio must stay pending.');
        f = INV.CHARGE_FRAC(100e-9, -2:2, 296.15, 101325, ...
            struct('Config', cfg));
        near(f, expected{1}(2, :), 2e-12);
        cfg.model.fluid_properties = 'room';
        expect(@() INV.CHARGE_FRAC(100e-9, 1, 296.15, 101325, ...
            struct('Config', cfg)), 'GAS:InvalidGasModel');
    end

    function [f, info] = evaluate(d, n, model)
        [f, info] = INV.CHARGE_FRAC(d, n, 296.15, 101325, ...
            struct('Model', ids{model}));
    end
end

function expected = reference_fractions()
expected = { ...
    [.001583777488485 .145060103788655 .698899619298928 ...
        .130318794997338 .001254754169097; ...
     .047306410930567 .252772602569946 .422911991921224 ...
        .229514432306684 .039183208939411; ...
     .133830457321877 .174931673835673 .185082505913073 ...
        .160853400377699 .112605903763492], ...
    [.001680618984066 .157866709426204 .702787840573461 ...
        .120660907611731 .000966199875430; ...
     .056078966337453 .279318692225397 .425892507667207 ...
        .213796208950223 .031710274389480; ...
     .148999591534884 .181580678872213 .181804433979605 ...
        .140330984337924 .089097759369510], ...
    [.001440733442009 .157318122879135 .687738880917831 ...
        .153040431543685 .001597633968029; ...
     .053621368447854 .242933828820602 .418313910450885 ...
        .223941996460791 .044504633540879; ...
     .128059823022041 .183896307258083 .184512333164896 ...
        .161431117811076 .105566462604076]};
end

function f = reference_high(d_m, n, temp_k, ratio)
% Evaluating Eq. B-3 directly, with the SI constants used by GAS
e_c = 1.602176634e-19;
eps0_f_m = 8.8541878128e-12;
kb_j_k = 1.380649e-23;
a = 2*pi*eps0_f_m*d_m*kb_j_k*temp_k / e_c^2;
f = e_c / sqrt(4*pi^2*eps0_f_m*d_m*kb_j_k*temp_k) .* ...
    exp(-(n - a*log(ratio)).^2 / (2*a));
end

function near(actual, expected, tol)
check(isequal(size(actual), size(expected)) && ...
    all(isfinite(actual(:))) && all(abs(actual(:)-expected(:)) <= tol), ...
    'Reference fraction mismatch.');
end

function expect(action, suffix)
try
    action();
catch err
    check(strcmp(err.identifier, ['sootMosaic:' suffix]), ...
        ['Unexpected refusal: ' err.identifier]);
    return
end
check(false, ['Expected refusal: ' suffix]);
end

function check(condition, message)
if ~condition, error('sootMosaic:QA:InvChargeFailed', '%s', message); end
end

function restore(state, message, identifier)
warning(state);
lastwarn(message, identifier);
end
