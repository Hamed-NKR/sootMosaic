function report = TEST_INV_GROUP_RANGE()
% "TEST_INV_GROUP_RANGE" checks group averages and operating ranges.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Any failure raises...
%         ...sootMosaic:QA:InvGroupRangeFailed
% ----------------------------------------------------------------------- %
% Method: Student t quantiles solved independently from the regularized...
%     ...incomplete beta function; DerSimonian and Laird (1986, Eqs. 2-4,...
%     ...p. 183) evaluated by hand in exact fractions; Kiasadegh et al....
%     ...(2026, SI Eqs. S2-S7) solved independently with Kim et al....
%     ...(2005, Eqs. 9, 11 and 34). Every input is synthetic.

current = 'setup';
try
    root = fileparts(fileparts(mfilename('fullpath')));
    config_file = fullfile(root, 'config', 'main_inv', ...
        'main_inv_config.example.json');
    base = UTILS.LOAD_MAIN_INV_CONFIG(config_file);
    tests = {@t_factors, @four_scans, @common_support, @shared_terms, ...
        @random_effects, @calculator_ranges, @independent_roots, ...
        @speed_limit, @tandem_relation, @sheath_flow_limits, @refusals};
    names = {'Student t factors of the actual scan count', ...
        'interval and covariance of four scans', ...
        'common support without extrapolation', ...
        'shared terms passed through once', ...
        'random effects against a hand calculation', ...
        'calculator ranges to the printed precision', ...
        'range limits against independent roots', ...
        'AAC speed limit lines and setpoint check', ...
        'tandem overlap through a density relation', ...
        'sheath flow limits of the registry', ...
        'refused inputs'};
    pass = false(size(tests));
    for case_index = 1:numel(tests)
        current = names{case_index};
        tests{case_index}();
        pass(case_index) = true;
    end
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
catch err
    error('sootMosaic:QA:InvGroupRangeFailed', '%s: %s (%s)', ...
        current, err.message, err.identifier);
end

    function t_factors()
        n = [2 3 10];
        printed = [12.71 4.30 2.26];
        for k = 1:3
            g = INV.GROUP_AVG((1:n(k)).', base);
            check(g.independent.dof == n(k) - 1, 'Degrees of freedom.');
            check(round(100 * g.independent.factor) / 100 == printed(k), ...
                'Printed t factor.');
            near(g.independent.factor, t_reference(n(k) - 1, 0.95), 1e-10);
            near(g.combined.factor, g.independent.factor, 1e-14);
        end
    end

    function four_scans()
        x = [1 2; 2 1; 3 5; 4 4];
        g = INV.GROUP_AVG(x, base);
        check(isequal(g.mean, [2.5 3]) && g.n_scans == 4, 'Mean and count.');
        near(g.sd, sqrt([5/3 10/3]), 1e-14);
        near(g.independent.u, sqrt([5/12 10/12]), 1e-14);
        near(g.independent.covariance, [5/12 5/12; 5/12 5/6], 1e-14);
        t3 = 3.18244630528371;
        near(g.combined.half_width, t3 * sqrt([5/12 10/12]), 1e-13);
        near(g.lower, [2.5 3] - t3 * sqrt([5/12 10/12]), 1e-13);
        near(g.upper, [2.5 3] + t3 * sqrt([5/12 10/12]), 1e-13);
        check(strcmp(g.mode, 'statistics') && ...
            strcmp(g.combination, 'student_t'), 'Mode labels.');
    end

    function common_support()
        d1 = logspace(1, 3, 41);
        d2 = logspace(log10(20), log10(500), 30);
        d2([1 end]) = [20 500];
        d3 = logspace(log10(15), log10(800), 25);
        c = [1 2 3];
        nodes = {d1, d2, d3};
        scans = cell(1, 3);
        for k = 1:3
            scans{k} = struct('diameter_nm', nodes{k}, ...
                'values', c(k) + 2 * log10(nodes{k}), ...
                'quantity', 'dN/dlog10d', 'unit', 'cm^-3');
        end
        g = INV.GROUP_AVG(scans, base);
        check(strcmp(g.mode, 'distribution'), 'Distribution mode.');
        check(isequal(g.support_nm, [20 500]), 'Common support.');
        check(all(g.diameter_nm >= 20 & g.diameter_nm <= 500), ...
            'No value outside the common support.');
        check(isequal(g.diameter_nm, d1(d1 >= 20 & d1 <= 500)), ...
            'First scan diameters inside the support.');
        near(g.mean, 2 + 2 * log10(g.diameter_nm), 1e-12);
        near(g.scan_values(2, :), 2 + 2 * log10(g.diameter_nm), 1e-12);
        target = [20 100 500];
        g = INV.GROUP_AVG(scans, base, struct('diameter_nm', target));
        near(g.mean, 2 + 2 * log10(target), 1e-12);
        near(g.sd, [1 1 1], 1e-12);
        expect(@() INV.GROUP_AVG(scans, base, ...
            struct('diameter_nm', [20 600])), ':Extrapolation');
        expect(@() INV.GROUP_AVG(scans, base, ...
            struct('diameter_nm', [19 100])), ':Extrapolation');
    end

    function shared_terms()
        x = [1; 2; 3; 4];
        g = INV.GROUP_AVG(x, base, struct('shared_covariance', 0.25));
        check(g.shared.covariance == 0.25 && g.shared.u == 0.5, ...
            'Shared term unchanged.');
        near(g.combined.u, sqrt(2/3), 1e-14);
        near(g.combined.dof, 7.68, 1e-12);
        near(g.combined.factor, t_reference(7.68, 0.95), 1e-10);
        near(g.combined.half_width, ...
            t_reference(7.68, 0.95) * sqrt(2/3), 1e-10);
        near(g.independent.half_width, 3.18244630528371 * sqrt(5/12), 1e-13);
        large = INV.GROUP_AVG(repmat(x, 4, 1), base, ...
            struct('shared_covariance', 0.25));
        check(large.shared.u == 0.5, 'Shared term not divided by the count.');
        near(large.independent.u, sqrt(4/3 / 16), 1e-14);
        sigma = [0.04 0.01; 0.01 0.09];
        g = INV.GROUP_AVG([1 2; 2 1; 3 5; 4 4], base, ...
            struct('shared_covariance', sigma));
        check(isequal(g.shared.covariance, sigma), 'Covariance kept.');
        near(g.combined.u, sqrt([5/12 10/12] + [0.04 0.09]), 1e-14);
        near(g.combined.covariance, [5/12 5/12; 5/12 5/6] + sigma, 1e-14);
    end

    function random_effects()
        y = [10; 12; 14; 16; 15; 20; 22];
        day = {'a'; 'a'; 'b'; 'b'; 'b'; 'c'; 'c'};
        g = INV.GROUP_AVG(y, base, struct('day', {day}));
        check(strcmp(g.combination, 'random_effects'), 'Combination label.');
        check(isequal(g.days.labels, {'a'; 'b'; 'c'}) && ...
            isequal(g.days.n, [2 3 2]), 'Day labels and counts.');
        check(isequal(g.days.mean, [11; 15; 21]), 'Day means.');
        near(g.days.variance, [1; 1/3; 1], 1e-14);
        near(g.days.q, 51.2, 1e-13);
        near(g.days.tau2, 123/7, 1e-13);
        near(g.days.weights, [7/130; 21/376; 7/130], 1e-13);
        near(g.mean, 62587/3997, 1e-13);
        near(g.independent.u, sqrt(24440/3997), 1e-13);
        % Student t on the day count less one, three days leave two
        t2 = 4.30265272974946;
        near(g.independent.factor, t2, 1e-12);
        near(g.independent.factor, t_reference(2, 0.95), 1e-10);
        check(isequal(g.independent.dof, 2), 'Day degrees of freedom.');
        near(g.combined.half_width, t2 * sqrt(24440/3997), 1e-12);
        check(isequal(round(1000 * [g.lower g.upper]), [5019 26298]), ...
            'Three-day interval.');
        g = INV.GROUP_AVG([10; 12; 11; 13], base, struct('day', [1; 1; 2; 2]));
        check(g.days.tau2 == 0, 'Homogeneous days give no between term.');
        near(g.days.q, 0.5, 1e-14);
        near(g.mean, 11.5, 1e-14);
        near(g.independent.u, sqrt(1/2), 1e-14);
        % Two days leave one degree of freedom
        t1 = 12.706204736174698;
        near(g.independent.factor, t1, 1e-12);
        near(g.combined.half_width, t1 * sqrt(1/2), 1e-12);
        check(isequal(round(1000 * [g.lower g.upper]), [2515 20485]), ...
            'Two-day interval.');
        % A shared term keeps the finite day degrees of freedom
        g = INV.GROUP_AVG([10; 12; 11; 13], base, struct( ...
            'day', [1; 1; 2; 2], 'shared_covariance', 0.5));
        near(g.combined.dof, 1 * (1 / (1/2))^2, 1e-12);
        check(isfinite(g.combined.dof), 'Finite combined degrees of freedom.');
    end

    function calculator_ranges()
        % The calculator's constants, e = 1.6e-19 C and its viscosity...
            % ...reference, reproduce its printed ranges
        cfg = calculator_constants(base);
        r = INV.OP_RANGE(flows(3, 0.3, 3, 0.3), cfg);
        check(isequal(round([r.dma.d_min_m r.dma.d_max_m] * 1e10) / 10, ...
            [12.7 828.7]), 'DMA range at 3 L/min.');
        check(isequal(round([r.tandem.dm_min_m r.tandem.dm_max_m] * ...
            1e10) / 10, [32.6 828.7]), 'AAC-DMA overlap at 0.3 L/min.');
        check(r.aac.line == 1 && r.aac.line_limited, 'Speed line used.');
        near(r.aac.speed_limits_rad_s, [200 * pi / 30, 694.09], 1e-12);
        near(r.dma.resolution, 10, 1e-14);
        near(r.aac.resolution, 10, 1e-14);
    end

    function independent_roots()
        e = 1.602176634e-19;
        cases = [3 0.3; 15 1.5];
        for j = 1:2
            q = cases(j, 1);
            r = INV.OP_RANGE(flows(q, cases(j, 2), q, cases(j, 2)), base);
            [mu, lambda] = kim_gas(298.15, 101325);
            factor = 2 * 0.44369 * e / ...
                (3 * mu * q / 60000 * log(0.01961 / 0.00937));
            dma = [nm_root(@(d) d - factor * 10 * 1e9 * cc(d, lambda), ...
                [1 100]), nm_root(@(d) d - factor * 1e4 * 1e9 * ...
                cc(d, lambda), [10 5000])];
            near([r.dma.d_min_m r.dma.d_max_m] * 1e9, dma, 1e-9);
            w_up = min(7000 * pi / 30, ...
                (q <= 10) * (723.7 - 9.87 * q) + (q > 10) * (875 - 25 * q));
            w = [w_up, 20];
            a = 36 * mu * q / 60000 ./ ...
                (pi * 1000 * w .^ 2 * (0.056 + 0.06)^2 * 0.206) * 1e18;
            aac = [nm_root(@(d) d^2 * cc(d, lambda) - a(1), [1 1e4]), ...
                nm_root(@(d) d^2 * cc(d, lambda) - a(2), [1 1e5])];
            near([r.aac.da_min_m r.aac.da_max_m] * 1e9, aac, 1e-9);
            near(r.tandem.aac_dm_min_m, r.aac.da_min_m, 1e-12);
            near(r.tandem.dm_min_m, max(dma(1), aac(1)) * 1e-9, 1e-9);
            near(r.tandem.dm_max_m, min(dma(2), aac(2)) * 1e-9, 1e-9);
        end
    end

    function speed_limit()
        q = [3 12 10];
        expected = [694.09 575 625];
        branch = [1 2];
        for k = 1:3
            r = INV.OP_RANGE(flows([], [], q(k), 0.3), base);
            near(r.aac.speed_line_rad_s, expected(k), 1e-12);
            check(r.aac.line_limited, 'Speed line below the maximum.');
            % Both lines meet at the switch flow, so only k < 3 fixes one
            if k < 3, check(r.aac.line == branch(k), 'Line branch.'); end
        end
        cfg = base;
        cfg.si.op_range.speed_limits_rad_s = [20; 600];
        r = INV.OP_RANGE(flows([], [], 3, 0.3), cfg);
        check(r.aac.speed_limits_rad_s(2) == 600 && ~r.aac.line_limited, ...
            'Maximum speed below the line.');
        % AAC_SETPOINT at the upper speed gives the lower AAC limit
        r = INV.OP_RANGE(flows([], [], 3, 0.3), base);
        data.scan = struct('aac_speed_rad_s', 694.09, ...
            'aac_temperature_deg_c', 25, 'aac_pressure_kpa', 101.325, ...
            'aac_sheath_flow_lpm', 3);
        recorded = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        [tau, da] = INV.AAC_SETPOINT(recorded, 'synthetic step');
        near(r.aac.da_min_m, da, 1e-12);
        near(r.aac.tau_min_s, tau, 1e-12);
        cfg = base;
        cfg.si.op_range.speed_limits_rad_s = [600; 700];
        expect(@() INV.OP_RANGE(flows([], [], 15, 1.5), cfg), ':SpeedRange');
        check(isequal(base.si.op_range.speed_limits_rad_s(1), 20), ...
            'Registry lower speed.');
    end

    function tandem_relation()
        relation = struct('rho_100_kg_m3', 500, 'mass_mobility_exponent', 2.5);
        s = flows(3, 0.3, 3, 0.3);
        s.relation = relation;
        s.dm_m = [10 50 900] * 1e-9;
        s.da_m = [20 100 3100] * 1e-9;
        r = INV.OP_RANGE(s, base);
        dm = [r.tandem.aac_dm_min_m r.tandem.aac_dm_max_m];
        da = [r.aac.da_min_m r.aac.da_max_m];
        rho = INV.RHO_EFF(da, dm, 298.15, 101325, base);
        near(rho, 500 * (dm / 100e-9) .^ -0.5, 1e-10);
        check(dm(1) > da(1) && dm(2) > da(2), 'Low density moves dm up.');
        near(r.tandem.dm_min_m, max(r.dma.d_min_m, dm(1)), 1e-15);
        near(r.tandem.dm_max_m, min(r.dma.d_max_m, dm(2)), 1e-15);
        check(isequal(r.dma.inside, [false true false]), 'DMA screen.');
        check(isequal(r.tandem.inside, [false true false]), 'Tandem screen.');
        check(isequal(r.aac.inside, [false true false]), 'AAC screen.');
        r = INV.OP_RANGE(flows(30, 3, 15, 1.5), base);
        check(r.tandem.empty && isnan(r.tandem.dm_min_m) && ...
            r.dma.d_max_m < r.aac.da_min_m, 'Empty overlap.');
    end

    function sheath_flow_limits()
        e = 1e-3 / 60;
        near(base.si.op_range.dma_sheath_flow_limits_lpm, [2; 30] * e, 1e-14);
        near(base.si.op_range.aac_sheath_flow_limits_lpm, [2; 15] * e, 1e-14);
        % Both endpoints are inside, values just outside are refused
        r = INV.OP_RANGE(flows(2, 0.2, 2, 0.2), base);
        check(r.dma.sheath_flow_m3_s == 2 / 60000 && ...
            r.aac.sheath_flow_m3_s == 2 / 60000, 'Lower endpoints.');
        r = INV.OP_RANGE(flows(30, 3, 15, 1.5), base);
        check(r.dma.sheath_flow_m3_s == 0.0005 && ...
            r.aac.sheath_flow_m3_s == 0.00025, 'Upper endpoints.');
        r = INV.OP_RANGE(flows(30 * (1 + 1e-13), 3, 15, 1.5), base);
        check(r.dma.d_max_m > 0, 'Round-off at an endpoint.');
        outside = {flows(1.99, 0.2, 2, 0.2), flows(30.01, 3, 2, 0.2), ...
            flows(2, 0.2, 1.99, 0.2), flows(2, 0.2, 15.01, 1.5)};
        for k = 1:numel(outside)
            expect(@() INV.OP_RANGE(outside{k}, base), 'OP_RANGE:Flows');
        end
        expect(@() INV.OP_RANGE(flows(1.99, 0.2, [], []), base), ...
            'OP_RANGE:Flows');
        expect(@() INV.OP_RANGE(flows([], [], 15.01, 1.5), base), ...
            'OP_RANGE:Flows');
        cfg = base;
        cfg.si.op_range.aac_sheath_flow_limits_lpm = [];
        expect(@() INV.OP_RANGE(flows([], [], 3, 0.3), cfg), ...
            'OP_RANGE:MissingLimits');
        % The AAC setpoint calculation is shared with the recorded-step path
        s = flows([], [], 3, 0.3);
        r = INV.OP_RANGE(s, base);
        data.scan = struct('aac_speed_rad_s', 20, ...
            'aac_temperature_deg_c', 25, 'aac_pressure_kpa', 101.325, ...
            'aac_sheath_flow_lpm', 3);
        recorded = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        [tau, da] = INV.AAC_SETPOINT(recorded, 'synthetic step');
        near(r.aac.da_max_m, da, 1e-12);
        near(r.aac.tau_max_s, tau, 1e-12);
    end

    function refusals()
        expect(@() INV.GROUP_AVG(1, base), ':TooFewScans');
        expect(@() INV.GROUP_AVG([1; NaN], base), ':Values');
        expect(@() INV.GROUP_AVG([1; 2], base, struct('weights', 1)), ...
            ':Options');
        expect(@() INV.GROUP_AVG([1; 2], base, ...
            struct('diameter_nm', 10)), ':Options');
        cfg = base;
        cfg.averaging.support = 'union';
        expect(@() INV.GROUP_AVG([1; 2], cfg), ':Support');
        cfg = base;
        cfg.averaging.interval_level = 1.2;
        expect(@() INV.GROUP_AVG([1; 2], cfg), ':Level');
        expect(@() INV.GROUP_AVG([1; 2; 3], base, ...
            struct('day', {{'a'; 'a'; 'b'}})), ':DayScans');
        expect(@() INV.GROUP_AVG([1; 2], base, ...
            struct('day', {{'a'; 'a'}})), ':Days');
        expect(@() INV.GROUP_AVG([1; 1; 2; 3], base, ...
            struct('day', [1; 1; 2; 2])), ':DayVariance');
        expect(@() INV.GROUP_AVG([1; 2], base, ...
            struct('shared_covariance', eye(2))), ':SharedCovariance');
        expect(@() INV.GROUP_AVG([1 2; 2 3], base, ...
            struct('shared_covariance', [1 0.5; 0 1])), ':SharedCovariance');
        a = struct('diameter_nm', [10 20], 'values', [1 2]);
        b = struct('diameter_nm', [30 40], 'values', [1 2]);
        expect(@() INV.GROUP_AVG({a, b}, base), ':NoCommonSupport');
        expect(@() INV.GROUP_AVG({a, struct('diameter_nm', [20 10], ...
            'values', [1 2])}, base), ':Diameters');
        c = a;
        c.quantity = 'dN/dlog10d';
        expect(@() INV.GROUP_AVG({a, c}, base), ':Incompatible');
        s = flows(3, 0.3, 3, 0.3);
        bad = s;
        bad.sheath = 1;
        expect(@() INV.OP_RANGE(bad, base), ':Setting');
        expect(@() INV.OP_RANGE(struct('temperature_k', 298.15, ...
            'pressure_pa', 101325), base), ':Setting');
        bad = rmfield(s, 'temperature_k');
        expect(@() INV.OP_RANGE(bad, base), ':State');
        bad = s;
        bad.aac_sheath_flow_m3_s = -1;
        expect(@() INV.OP_RANGE(bad, base), ':Flows');
        bad = flows(3, 0.3, [], []);
        bad.relation = struct('rho_100_kg_m3', 500, ...
            'mass_mobility_exponent', 2.5);
        expect(@() INV.OP_RANGE(bad, base), ':Setting');
        bad = s;
        bad.relation = struct('rho_100_kg_m3', 500, ...
            'mass_mobility_exponent', 2);
        expect(@() INV.OP_RANGE(bad, base), ':Relation');
        bad = s;
        bad.dm_m = -1e-9;
        expect(@() INV.OP_RANGE(bad, base), ':Setpoints');
        cfg = base;
        cfg.si.op_range.voltage_limits_v = [];
        expect(@() INV.OP_RANGE(s, cfg), ':MissingLimits');
        cfg = base;
        cfg.si.op_range.voltage_limits_v = [1e4; 10];
        expect(@() INV.OP_RANGE(s, cfg), ':Limits');
        cfg = base;
        cfg.op_range.dma = 'other';
        expect(@() INV.OP_RANGE(s, cfg), ':Instrument');
    end
end

function s = flows(dma_lpm, dma_aerosol_lpm, aac_lpm, aac_aerosol_lpm)
% "flows" builds a range setting at 298.15 K and 101325 Pa from L/min.
s = struct('temperature_k', 298.15, 'pressure_pa', 101325);
if ~isempty(dma_lpm)
    s.dma_sheath_flow_m3_s = dma_lpm / 60000;
    s.dma_aerosol_flow_m3_s = dma_aerosol_lpm / 60000;
end
if ~isempty(aac_lpm)
    s.aac_sheath_flow_m3_s = aac_lpm / 60000;
    s.aac_aerosol_flow_m3_s = aac_aerosol_lpm / 60000;
end
end

function cfg = calculator_constants(cfg)
% "calculator_constants" sets the charge, viscosity and 200 rpm lower speed.
cfg.si.op_range.speed_limits_rad_s = ...
    [200 * pi / 30; cfg.si.op_range.speed_limits_rad_s(2)];
cfg.model_params.si.constants.e_c = 1.6e-19;
cfg.model_params.si.gas.sutherland.mu_ref_pa_s = 1.81809e-5;
cfg.model_params.si.gas.sutherland.t_ref_k = 293.15;
end

function t = t_reference(nu, level)
% "t_reference" solves P(|T| > t) = 1 - level with fzero and betainc.
tail = @(t) betainc(nu / (nu + t^2), nu / 2, 0.5) - (1 - level);
t = fzero(tail, [1e-3 1e3]);
end

function [mu, lambda] = kim_gas(temp, pressure)
% "kim_gas" evaluates Kim et al. (2005, Eqs. 9 and 11) independently (m).
mu = 1.83245e-5 * (temp / 296.15)^1.5 * (296.15 + 110.4) / (temp + 110.4);
lambda = 67.3 * (temp / 296.15)^2 * (296.15 + 110.4) / (temp + 110.4) * ...
    101325 / pressure;
end

function value = cc(d_nm, lambda_nm)
% "cc" evaluates Kim et al. (2005, Eq. 34) with both lengths in nm.
kn = 2 * lambda_nm ./ d_nm;
value = 1 + kn .* (1.165 + 0.483 * exp(-0.997 ./ kn));
end

function d = nm_root(fn, bracket)
% "nm_root" finds a bracketed root in nm to round-off.
d = fzero(fn, bracket, optimset('TolX', 1e-14));
end

function near(actual, expected, tolerance)
% "near" checks a relative error without a unit-dependent absolute floor.
check(isequal(size(actual), size(expected)) && ...
    all(isfinite(actual(:))) && ...
    all(abs(actual(:) - expected(:)) <= tolerance * abs(expected(:))), ...
    'Numerical relation exceeds its tolerance.');
end

function check(value, message)
% "check" reports a failed relation.
if ~isscalar(value) || ~value
    error('sootMosaic:QA:InvGroupRangeFailed', '%s', message);
end
end

function expect(action, suffix)
% "expect" checks the identifier of a refused input.
identifier = '';
try
    action();
catch err
    identifier = err.identifier;
end
check(endsWith(identifier, suffix), ['Expected refusal ' suffix]);
end
