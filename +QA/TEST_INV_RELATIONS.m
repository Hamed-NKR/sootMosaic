function report = TEST_INV_RELATIONS()
% "TEST_INV_RELATIONS" checks gas and classifier relations on synthetic data.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Any failure raises...
%         ...sootMosaic:QA:InvRelationsFailed
% ----------------------------------------------------------------------- %
% Method: Kim et al. (2005, Eqs. 9, 11 and 34); Sipkens et al....
%     ...(2020, part I, Eqs. 7-9); Kiasadegh et al. (2026, Eqs. 6 and 14);
%     ...Tavakoli and Olfert (2014, Eqs. 3-5 and 7).

try
    root = fileparts(fileparts(mfilename('fullpath')));
    config_file = fullfile(root, 'config', 'main_inv', ...
        'main_inv_config.example.json');
    cfg = UTILS.LOAD_MAIN_INV_CONFIG(config_file);
    folder = tempname;
    [ok, message] = mkdir(folder);
    check(ok, message);
    cleanup = onCleanup(@() rmdir(folder, 's'));
    tests = {@gas_reference, @gas_slip, @gas_state, @gas_refusals, ...
        @charge_peak, @mobility_roundtrip, @aac_equations, @aac_missing, ...
        @aac_missing_flow, @aac_rows, @sphere_density, @unequal_states, ...
        @input_refusals, @gas_records, @setpoint_check};
    names = {'gas reference and SI constants', 'slip reference values', ...
        'gas state scaling', 'gas preset refusals', ...
        'doubly charged apparent peak', 'mobility round trips', ...
        'AAC equations and flow units', 'AAC missing step inputs', ...
        'AAC missing recorded flow', 'AAC per-row recorded states', ...
        '912 kg/m3 sphere', ...
        'unit-density sphere at unequal states', 'input refusals', ...
        'gas model versus recorded properties', 'recorded setpoint warnings'};
    pass = false(size(tests));
    for k = 1:numel(tests)
        tests{k}();
        pass(k) = true;
    end
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
catch err
    error('sootMosaic:QA:InvRelationsFailed', '%s (%s)', ...
        err.message, err.identifier);
end

    function gas_reference()
        [mu, lambda, cc, p] = INV.GAS(296.15, 101325, [], cfg);
        near(mu, 1.83245e-5, 4*eps);
        near(lambda, 67.30e-9, 4*eps);
        check(isempty(cc), 'Empty diameter must give empty slip.');
        check(p.constants.e_c == 1.602176634e-19, 'Charge reference.');
        check(p.constants.kb_j_k == 1.380649e-23, 'Energy reference.');
        check(p.constants.na_mol_inv == 6.02214076e23, 'Amount reference.');
        near(p.constants.ru_j_mol_k, ...
            p.constants.kb_j_k*p.constants.na_mol_inv, 4*eps);
    end

    function gas_slip()
        d = [50 100 200 1000] * 1e-9;
        [~, ~, cc] = INV.GAS(296.15, 101325, d, cfg);
        expected = [5.033977420537194 2.878049195224267 ...
            1.857935203550798 1.156848456224908];
        near(cc, expected, 1e-5);
        near(cc, reference_cc(d, 67.30e-9), 16*eps);
    end

    function gas_state()
        [mu, lambda] = INV.GAS(303.15, 95000, [], cfg);
        [expected_mu, expected_lambda] = reference_gas(303.15, 95000);
        near(mu, expected_mu, 16*eps);
        near(lambda, expected_lambda, 16*eps);
        [mu2, lambda2] = INV.GAS(303.15, 95000/2, [], cfg);
        near(mu2, mu, 4*eps);
        near(lambda2, 2*lambda, 4*eps);
    end

    function gas_refusals()
        presets = {'room', 'flame'};
        for j = 1:numel(presets)
            bad = cfg;
            bad.model.fluid_properties = presets{j};
            expect(@() INV.GAS(296.15, 101325, [], bad), ...
                'GAS:InvalidGasModel', 'without gas presets');
            bad = cfg;
            bad.model_params.si.gas.model = presets{j};
            expect(@() INV.GAS(296.15, 101325, [], bad), ...
                'GAS:InvalidGasModel', 'without gas presets');
        end
        bad = cfg;
        bad.model.profile = 'article1_7658971';
        expect(@() INV.GAS(296.15, 101325, [], bad), ...
            'GAS:InvalidGasModel', 'current');
    end

    function charge_peak()
        [mu, lambda] = reference_gas(296.15, 101325);
        z = 2 * 1.602176634e-19 * reference_cc(200e-9, lambda) / ...
            (3*pi*mu*200e-9);
        apparent = INV.DM_FROM_Z(z, 1, 296.15, 101325, cfg);
        check(abs(apparent*1e9 - 129.4) < 0.05, 'Apparent peak.');
        near(INV.DM_FROM_Z(z, 2, 296.15, 101325, cfg), 200e-9, 1e-10);
        check(abs(apparent/(200e-9*2^(-2/3)) - 1) > 0.02, ...
            'The exact root must discriminate the power approximation.');
    end

    function mobility_roundtrip()
        d = [20 50 100; 200 500 1000] * 1e-9;
        n = [1 -2 3; -4 8 16];
        [mu, lambda] = reference_gas(303.15, 99000);
        z = abs(n)*1.602176634e-19 .* reference_cc(d, lambda) ./ ...
            (3*pi*mu*d);
        near(INV.DM_FROM_Z(z, n, 303.15, 99000, cfg), d, 1e-10);
        z = 3*1.602176634e-19 * reference_cc(d, lambda) ./ (3*pi*mu*d);
        near(INV.DM_FROM_Z(z, 3, 303.15, 99000, cfg), d, 1e-10);
    end

    function aac_equations()
        data.scan = struct('aac_speed_rad_s', 1000, ...
            'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
            'aac_sheath_flow_lpm', 3);
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        near(c.scan.aac_sheath_flow_lpm, 3, 0);
        near(c.si.scan.aac_sheath_flow_lpm, 3e-3/60, 4*eps);
        near([c.si.geometry.aac_inner_radius_m, ...
            c.si.geometry.aac_outer_radius_m, c.si.geometry.aac_length_m], ...
            [0.056 0.060 0.206], 0);
        [tau, da] = INV.AAC_SETPOINT(c, 'synthetic per-scan flow');
        expected = 2*(3e-3/60)/(pi*1000^2*(0.056+0.060)^2*0.206);
        near(tau, expected, 16*eps);
        [mu, lambda] = reference_gas(296.15, 101325);
        near(1000*da^2*reference_cc(da, lambda)/(18*mu), tau, 64*eps);
        data.scan.aac_sheath_flow_lpm = 6;
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        [tau2, da2] = INV.AAC_SETPOINT(c, 'synthetic recorded flow');
        near(tau2, 2*tau, 16*eps);
        check(da2 > da, 'Increasing flow increases the setpoint size.');
        near(1000*da2^2*reference_cc(da2, lambda)/(18*mu), tau2, 64*eps);
    end

    function aac_missing()
        keys = {'aac_speed_rad_s', 'aac_temperature_deg_c', ...
            'aac_pressure_kpa', 'aac_sheath_flow_lpm'};
        values = struct('aac_speed_rad_s', 300, ...
            'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
            'aac_sheath_flow_lpm', 3);
        campaign.values.scan = values;
        campaign.reasons.scan = struct( ...
            'aac_speed_rad_s', 'Synthetic record', ...
            'aac_temperature_deg_c', 'Synthetic record', ...
            'aac_pressure_kpa', 'Synthetic record', ...
            'aac_sheath_flow_lpm', 'Synthetic record');
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, struct(), campaign);
        near(c.si.scan.aac_speed_rad_s, 300, 0);
        INV.AAC_SETPOINT(c, 'synthetic campaign step');
        for j = 1:numel(keys)
            missing = campaign;
            missing.values.scan = rmfield(values, keys{j});
            c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, struct(), missing);
            expect(@() INV.AAC_SETPOINT(c, 'synthetic step 7'), ...
                'AAC_SETPOINT:MissingInput', 'synthetic step 7');
        end
        for j = 1:numel(keys)
            c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, struct(), campaign);
            index = strcmp({c.reading.path}, ['scan.' keys{j}]);
            c.reading(index).source = 'config';
            expect(@() INV.AAC_SETPOINT(c, 'synthetic unlogged step'), ...
                'AAC_SETPOINT:MissingRecordedInput', ['scan.' keys{j}]);
            c.reading(index).source = 'registry';
            expect(@() INV.AAC_SETPOINT(c, 'synthetic registry step'), ...
                'AAC_SETPOINT:MissingRecordedInput', ['scan.' keys{j}]);
        end
    end

    function aac_missing_flow()
        data.scan = struct('aac_speed_rad_s', 1000, ...
            'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325);
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        check(isempty(c.scan.aac_sheath_flow_lpm) && ...
            isempty(c.si.scan.aac_sheath_flow_lpm), ...
            'Missing recorded sheath flow must remain empty.');
        expect(@() INV.AAC_SETPOINT(c, 'synthetic missing flow'), ...
            'AAC_SETPOINT:MissingInput', ...
            ['Step synthetic missing flow requires a positive finite ' ...
            'scan.aac_sheath_flow_lpm in SI.']);
    end

    function aac_rows()
        scan = standalone_fixture();
        rows = scan.conditions;
        tau = zeros(2, 1);
        da = zeros(2, 1);
        for j = 1:2
            data.scan = struct('aac_speed_rad_s', rows.aac_speed_rad_s(j), ...
                'aac_sheath_flow_lpm', rows.aac_sheath_flow_lpm(j), ...
                'aac_temperature_deg_c', rows.aac_temperature_deg_c(j), ...
                'aac_pressure_kpa', rows.aac_pressure_pa(j)/1000, ...
                'aac_setpoint_nm', rows.aac_setpoint_nm(j));
            c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
            [tau(j), da(j)] = INV.AAC_SETPOINT(c, sprintf('scan row %d', j));
            near(c.si.scan.aac_temperature_deg_c, ...
                rows.aac_temperature_deg_c(j)+273.15, 0);
            near(c.si.scan.aac_pressure_kpa, rows.aac_pressure_pa(j), 4*eps);
            [mu, lambda] = reference_gas( ...
                rows.aac_temperature_deg_c(j)+273.15, rows.aac_pressure_pa(j));
            expected = 2*(rows.aac_sheath_flow_lpm(j)*1e-3/60) / ...
                (pi*rows.aac_speed_rad_s(j)^2*0.116^2*0.206);
            near(tau(j), expected, 16*eps);
            near(1000*da(j)^2*reference_cc(da(j), lambda)/(18*mu), ...
                tau(j), 64*eps);
        end
        check(da(1) ~= da(2), 'Row states must remain distinct.');
    end

    function sphere_density()
        dm = [100 200 500] * 1e-9;
        [mu, lambda] = reference_gas(296.15, 101325);
        tau = 912 * dm.^2 .* reference_cc(dm, lambda) / (18*mu);
        da = zeros(size(dm));
        for j = 1:numel(dm)
            c = setpoint_config(tau(j), 296.15, 101325);
            [actual_tau, da(j)] = INV.AAC_SETPOINT(c, 'synthetic sphere');
            near(actual_tau, tau(j), 16*eps);
        end
        near(INV.RHO_EFF(da, dm, 296.15, 101325, cfg), ...
            912*ones(size(dm)), 1e-10);
    end

    function unequal_states()
        d = 100e-9;
        [mu_dma, lambda_dma] = reference_gas(298.15, 101325);
        z = 1.602176634e-19*reference_cc(d, lambda_dma)/(3*pi*mu_dma*d);
        dm = INV.DM_FROM_Z(z, 1, 298.15, 101325, cfg);
        [mu_aac, lambda_aac] = reference_gas(303.15, 99000);
        tau = 1000*d^2*reference_cc(d, lambda_aac)/(18*mu_aac);
        c = setpoint_config(tau, 303.15, 99000);
        [~, da] = INV.AAC_SETPOINT(c, 'synthetic unequal states');
        near(dm, d, 1e-10);
        near(da, d, 1e-10);
        rho = INV.RHO_EFF(da, dm, 303.15, 99000, cfg);
        check(abs(rho-1000) <= 1e-10, 'Unequal-state density round trip.');
        mixed = 1000*(da/dm)^2 * ...
            reference_cc(da, lambda_aac)/reference_cc(dm, lambda_dma);
        check(abs(mixed-1000) > 30, 'Mixed gas states must fail the sphere.');
    end

    function input_refusals()
        expect(@() INV.GAS(NaN, 101325, [], cfg), 'GAS:InvalidState', '');
        expect(@() INV.GAS(296.15, 0, [], cfg), 'GAS:InvalidState', '');
        expect(@() INV.GAS(296.15, 101325, -1, cfg), ...
            'GAS:InvalidDiameter', '');
        expect(@() INV.DM_FROM_Z(0, 1, 296.15, 101325, cfg), ...
            'DM_FROM_Z:InvalidMobility', '');
        for n = [0 1.5 Inf]
            expect(@() INV.DM_FROM_Z(1e-8, n, 296.15, 101325, cfg), ...
                'DM_FROM_Z:InvalidCharge', '');
        end
        expect(@() INV.DM_FROM_Z([1e-8 2e-8], [1; 2], 296.15, 101325, cfg), ...
            'DM_FROM_Z:InvalidCharge', '');
        expect(@() INV.RHO_EFF([1 2], [1; 2], 296.15, 101325, cfg), ...
            'RHO_EFF:InvalidDiameters', '');
        c = setpoint_config(1e-7, 296.15, 101325);
        c.si.geometry.aac_outer_radius_m = c.si.geometry.aac_inner_radius_m;
        expect(@() INV.AAC_SETPOINT(c, 'synthetic geometry'), ...
            'AAC_SETPOINT:InvalidGeometry', 'synthetic geometry');
    end

    function gas_records()
        state = warning;
        cleanup_warning = onCleanup(@() warning(state));
        warning('on', 'sootMosaic:GAS:RecordedPropertyMismatch');
        [mu, lambda] = reference_gas(303.15, 95000);
        [ref_mu, ref_lambda] = reference_gas(290, 100000);
        data.scan = struct('dma_temperature_deg_c', 30, 'dma_pressure_kpa', 95, ...
            'logged_viscosity_pa_s', mu, 'logged_mean_free_path_nm', lambda*1e9, ...
            'reference_temperature_k', 290, 'reference_pressure_kpa', 100, ...
            'reference_viscosity_pa_s', ref_mu, ...
            'reference_mean_free_path_nm', ref_lambda*1e9, 'reference_sutherland_k', 110.4);
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        lastwarn('');
        [a, b] = INV.GAS(320, 85000, [], c);
        [~, id] = lastwarn;
        check(isempty(id), 'Matching DMA and reference records must not warn at an AAC state.');
        [ma, la] = reference_gas(320, 85000);
        near(a, ma, 16*eps); near(b, la, 16*eps);
        keys = {'logged_viscosity_pa_s', 'logged_mean_free_path_nm', ...
            'reference_viscosity_pa_s', 'reference_mean_free_path_nm', ...
            'reference_sutherland_k'};
        for j = 1:numel(keys)
            bad = data;
            bad.scan.(keys{j}) = 2*bad.scan.(keys{j});
            c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, bad);
            lastwarn('');
            [a, b] = INV.GAS(320, 85000, [], c);
            [~, id] = lastwarn;
            check(strcmp(id, 'sootMosaic:GAS:RecordedPropertyMismatch'), ...
                ['Missing comparison: ' keys{j}]);
            near(a, ma, 16*eps); near(b, la, 16*eps);
        end
    end

    function setpoint_check()
        state = warning;
        cleanup_warning = onCleanup(@() warning(state));
        warning('on', 'sootMosaic:AAC_SETPOINT:SetpointMismatch');
        data.scan = struct('aac_speed_rad_s', 1000, ...
            'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
            'aac_sheath_flow_lpm', 3);
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
        [tau, d] = INV.AAC_SETPOINT(c, 'synthetic reference');
        near(c.checks.setpoint_rel_tol, 0.05, 0);
        for ratio = [1.04 1.06]
            data.scan.aac_setpoint_nm = d*1e9/ratio;
            c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
            lastwarn('');
            [actual_tau, actual_d] = INV.AAC_SETPOINT(c, 'synthetic comparison');
            [~, id] = lastwarn;
            if ratio < 1.05
                check(isempty(id), 'Within-tolerance setpoint must not warn.');
            else
                check(strcmp(id, 'sootMosaic:AAC_SETPOINT:SetpointMismatch'), ...
                    'Outside-tolerance setpoint must warn.');
            end
            near(actual_tau, tau, 0); near(actual_d, d, 0);
        end
        c.checks.setpoint_rel_tol = [];
        expect(@() INV.AAC_SETPOINT(c, 'missing tolerance'), ...
            'AAC_SETPOINT:MissingCheckTolerance', 'missing tolerance');
    end

    function c = setpoint_config(tau, temp, pressure)
        omega = sqrt(2*(3e-3/60)/(pi*0.116^2*0.206*tau));
        data.scan = struct('aac_speed_rad_s', omega, ...
            'aac_temperature_deg_c', temp-273.15, ...
            'aac_pressure_kpa', pressure/1000, 'aac_sheath_flow_lpm', 3);
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
    end

    function scan = standalone_fixture()
        lines = {'AAC SASS Scan'; ...
            'Time:|12:00:00|Date:|2024-03-01 (yyyy-mm-dd)'; ...
            ['Cylinder Temperature (C):|18|Sample Flow (lpm):|0.3|' ...
            'Sheath Temperature (C):|18|Sheath Pressure (Pa):|105000|' ...
            'Ambient Temperature (C):|18|Ambient Humidity (%):|30|' ...
            'Mass-Mobility Prefactor:|1000|Mass-Mobility Exponent:|3']; ...
            ['Scan Time (s):|4|Transit time (s):|1|Delay time (s):|0.4|' ...
            'CPC Sampling period (s):|1']; ...
            ['Start size (nm):|200|End size< (nm):|100|' ...
            'Start tau (ns):|100|End tau< (ns):|50']; ...
            'SCAN|1|of|1'; ...
            ['Size Class/dec:|12|Start Speed (rad/s):|300|' ...
            'End Speed (rad/s):|400|Scan Constant:|10']; ...
            ['Scan Time (s)|Real Time|Size (nm)|' ...
            'Size Spectral Density (dN/dLog(Da)/cc)|Tau (ns)|' ...
            'Speed (rad/s)|Sheath (lpm)|Sheath Temp (C)|' ...
            'Classifier Pressure (Pa)']; ...
            '1|12:00:01|200|1|100|300|3|23|101325'; ...
            '2|12:00:02|100|1|50|400|4|30|99000'; ...
            'END OF SCAN|1|of|1'; 'END OF FILE'};
        file = fullfile(folder, 'synthetic_sass.txt');
        fid = fopen(file, 'w');
        check(fid >= 0, 'Cannot open synthetic scan.');
        close_file = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', strrep(strjoin(lines, newline), '|', char(9)));
        clear close_file
        result = INV.READ_AAC(file);
        scan = result.scans{1};
    end
end

function [mu, lambda] = reference_gas(temp, pressure)
% "reference_gas" evaluates Kim et al. (2005, Eqs. 9 and 11) independently.
mu = 1.83245e-5*(temp/296.15)^1.5*(296.15+110.4)/(temp+110.4);
lambda = 67.30e-9*(temp/296.15)^2*(296.15+110.4)/(temp+110.4)*101325/pressure;
end

function cc = reference_cc(d, lambda)
% "reference_cc" evaluates Kim et al. (2005, Eq. 34) independently.
kn = 2*lambda./d;
cc = 1 + kn.*(1.165 + 0.483*exp(-0.997./kn));
end

function near(actual, expected, tolerance)
% "near" checks a relative error without a unit-dependent absolute floor.
check(isequal(size(actual), size(expected)) && ...
    all(isfinite(actual(:))) && ...
    all(abs(actual(:)-expected(:)) <= tolerance*abs(expected(:))), ...
    'Numerical relation exceeds its tolerance.');
end

function check(value, message)
% "check" reports a failed relation.
if ~isscalar(value) || ~value
    error('sootMosaic:QA:InvRelationsFailed', '%s', message);
end
end

function expect(action, suffix, detail)
% "expect" checks the identifier and context of a refused input.
identifier = '';
message = '';
try
    action();
catch err
    identifier = err.identifier;
    message = err.message;
end
check(strcmp(identifier, ['sootMosaic:' suffix]) && ...
    contains(message, detail), ['Unexpected refusal: ' identifier]);
end
