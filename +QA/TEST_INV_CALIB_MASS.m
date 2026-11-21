function report = TEST_INV_CALIB_MASS()
% "TEST_INV_CALIB_MASS" checks k(dm) and mass integrals on synthetic data.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Any failure raises...
%         ...sootMosaic:QA:InvCalibMassFailed
% ----------------------------------------------------------------------- %
% Method: Sapkota et al. (2025, SI Sec. S3, Fig. S3), published factor...
%     ...values; Perraud, Smith and Olfert (2023); Kiasadegh et al....
%     ...(2026, Eqs. 33 and 34); Tavakoli and Olfert (2014, Eqs. 3-5...
%     ...and 7); Kim et al. (2005, Eqs. 9, 11 and 34) for the independent...
%     ...slip evaluation. Every input is synthetic.

current = 'setup';
try
    root = fileparts(fileparts(mfilename('fullpath')));
    config_file = fullfile(root, 'config', 'main_inv', ...
        'main_inv_config.example.json');
    base = UTILS.LOAD_MAIN_INV_CONFIG(config_file);
    folder = tempname;
    [ok, message] = mkdir(folder);
    check(ok, message);
    cleanup = onCleanup(@() rmdir(folder, 's'));
    tests = {@published_values, @range_flags, @configured_uncertainty, ...
        @point_file, @covariance_file, @disabled_and_refusals, ...
        @power_law_mass, @factor_once, @pairs_against_power_law, ...
        @mass_refusals, @uncertainty_terms};
    names = {'published factor values', ...
        'calibrated range flags, share and provenance', ...
        'configured uncertainty doubled outside the range', ...
        'uncertainty from a point file', ...
        'uncertainty from a covariance file', ...
        'disabled factor and refused inputs', ...
        'power-law mass against the analytic integral', ...
        'factor applied once', ...
        'AAC pairs and SMPS mass of one relation', ...
        'mass input refusals', ...
        'unavailable and invalid mass uncertainty inputs'};
    pass = false(size(tests));
    for case_index = 1:numel(tests)
        current = names{case_index};
        tests{case_index}();
        pass(case_index) = true;
    end
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
catch err
    error('sootMosaic:QA:InvCalibMassFailed', '%s: %s (%s)', ...
        current, err.message, err.identifier);
end

    function published_values()
        d_nm = [22 50 100 300 800];
        k = INV.CALIB_K(d_nm * 1e-9, base);
        check(isequal(round(k * 1000), [1000 1134 1194 1240 1257]), ...
            'Published factor values to three decimals.');
        near(k, hand_k(d_nm), 1e-14);
        column = INV.CALIB_K([22; 50] * 1e-9, base);
        check(isequal(size(column), [2 1]), 'Shape of the factor.');
    end

    function range_flags()
        d_nm = [20 21.8 100 596 600 800];
        [k, u, in_range, share, provenance] = INV.CALIB_K(d_nm * 1e-9, base);
        check(isequal(in_range, logical([0 1 1 1 0 0])), 'Range flags.');
        check(share == 0.5, 'Flagged share.');
        check(all(isnan(u)), 'No uncertainty is configured by default.');
        near(k, hand_k(d_nm), 1e-14);
        check(strcmp(provenance.source_id, 'aac_k_calibration') && ...
            strcmp(provenance.registry.doi, ...
            '10.1080/02786826.2025.2519093') && ...
            strcmp(provenance.registry.kind, 'processed_measurement'), ...
            'Registry entry of the factor.');
        near(provenance.range_nm, [21.8 596], 1e-12);
        check(provenance.offset == 1.27 && ...
            provenance.coefficient == -3.598 && ...
            provenance.exponent == -0.8376, 'Published coefficients.');
        check(strcmp(provenance.reference_material, 'PEG') && ...
            provenance.reference_density_kg_m3 == 1127, ...
            'Reference material and density.');
        check(contains(provenance.operating_condition, 'PEG') && ...
            contains(provenance.operating_condition, '3789'), ...
            'Operating condition text.');
        check(strcmp(provenance.uncertainty_source, 'none'), ...
            'Uncertainty source without a value.');
    end

    function configured_uncertainty()
        cfg = set_k(base, 'uncertainty', 0.02);
        d_nm = [20 21.8 100 596 600 800];
        [~, u, ~, ~, provenance] = INV.CALIB_K(d_nm * 1e-9, cfg);
        check(isequal(u, [0.04 0.02 0.02 0.02 0.04 0.04]), ...
            'Configured uncertainty and its doubling outside the range.');
        check(strcmp(provenance.uncertainty_source, 'config'), ...
            'Configured uncertainty source.');
        bad = set_k(base, 'uncertainty', 1.5);
        expect(@() INV.CALIB_K(1e-7, bad), 'CALIB_K:InvalidUncertainty');
    end

    function point_file()
        % Three diameters twice with residuals +e and -e give s^2 = 2 e^2...
            % ...and J'J = 2 J3'J3, so the curve error is e at each diameter
        e = 0.012;
        d3 = [30 100 400];
        d = [d3; d3];
        d = d(:);
        signs = repmat([1; -1], 3, 1);
        y = hand_k(d) + signs * e;
        file = fullfile(folder, 'points.csv');
        fid = fopen(file, 'w');
        check(fid >= 0, 'Cannot open the point file.');
        close_file = onCleanup(@() fclose(fid));
        fprintf(fid, 'dm_nm,k\n');
        fprintf(fid, '%.17g,%.17g\n', [d.'; y.']);
        clear close_file
        cfg = set_k(set_k(base, 'data_file', file), 'uncertainty', 0.02);
        query = [d3 800];
        [k, u, in_range, ~, provenance] = INV.CALIB_K(query * 1e-9, cfg);
        near(k, hand_k(query), 1e-14);
        check(isequal(in_range, logical([1 1 1 0])), 'Point file flags.');
        j3 = jacobian_rows(d3);
        se800 = e * norm(jacobian_rows(800) / j3);
        expected = [e ./ hand_k(d3), 2 * se800 / hand_k(800)];
        near(u, expected, 1e-9);
        near(u(2), 0.012 / 1.19399, 1e-5);
        check(strcmp(provenance.uncertainty_source, 'data_file_points') && ...
            provenance.n_points == 6, 'Point file provenance.');
        near(provenance.residual_sd, sqrt(2) * e, 1e-9);
        points = struct('dm_nm', d, 'k', y);
        mat_file = fullfile(folder, 'points.mat');
        save(mat_file, '-struct', 'points');
        [~, u_mat] = INV.CALIB_K(query * 1e-9, ...
            set_k(base, 'data_file', mat_file));
        near(u_mat, expected, 1e-9);
        points = struct('dm_nm', d3(:), 'k', hand_k(d3(:)) + 0.01);
        few = fullfile(folder, 'few.mat');
        save(few, '-struct', 'points');
        expect(@() INV.CALIB_K(1e-7, set_k(base, 'data_file', few)), ...
            'CALIB_K:InvalidDataFile');
        expect(@() INV.CALIB_K(1e-7, set_k(base, 'data_file', ...
            fullfile(folder, 'absent.mat'))), 'CALIB_K:MissingDataFile');
    end

    function covariance_file()
        stored = struct('covariance', diag([1e-4 0 0]));
        file = fullfile(folder, 'covariance.mat');
        save(file, '-struct', 'stored');
        query = [100 300 800];
        [~, u, ~, ~, provenance] = INV.CALIB_K(query * 1e-9, ...
            set_k(base, 'data_file', file));
        near(u, [0.01 0.01 0.02] ./ hand_k(query), 1e-12);
        near(u(1), 0.0083753, 1e-4);
        check(strcmp(provenance.uncertainty_source, ...
            'data_file_covariance'), 'Covariance file provenance.');
    end

    function disabled_and_refusals()
        [k, u, in_range, share] = INV.CALIB_K([10 800] * 1e-9, ...
            set_k(base, 'enabled', false));
        check(isequal(k, [1 1]) && isequal(u, [0 0]) && ...
            all(in_range) && share == 0, 'Disabled factor.');
        expect(@() INV.CALIB_K(0, base), 'CALIB_K:InvalidDiameters');
        expect(@() INV.CALIB_K(2e-9, base), 'CALIB_K:FactorRange');
        expect(@() INV.CALIB_K(1e-7, set_k(base, 'out_of_range', 'hold')), ...
            'CALIB_K:OutOfRangePolicy');
        expect(@() INV.CALIB_K(1e-7, set_k(base, 'source_id', 'absent')), ...
            'CALIB_K:UnknownSource');
    end

    function power_law_mass()
        [grid, states, relation, analytic] = lognormal_case();
        cfg = set_k(set_k(base, 'uncertainty', 0.02), 'range_nm', [1 1e5]);
        relation.covariance = diag([0.05 0.03] .^ 2);
        covariance = diag((0.05 * states) .^ 2);
        result = INV.MASS(grid, states, relation, cfg, ...
            struct('covariance_cm6', covariance));
        near(result.mass_ugm3, analytic.mass_ugm3, 1e-9);
        near(result.mass_ugm3, 13.0884, 1e-5);
        derivative = analytic.mass_ugm3 * [log(10), analytic.exponent_slope];
        near(result.u_relation_ugm3, ...
            sqrt(derivative * relation.covariance * derivative.'), 1e-8);
        near(result.u_calibration_ugm3, 0.02 * result.mass_ugm3, 1e-12);
        g = analytic.particle_kg .* analytic.width * 1e15;
        near(result.u_number_ugm3, ...
            sqrt(sum((g * 0.05 .* states) .^ 2)), 1e-12);
        near(result.u_total_ugm3, sqrt(result.u_number_ugm3^2 + ...
            result.u_relation_ugm3^2 + result.u_calibration_ugm3^2), 1e-14);
        check(numel(result.terms_included) == 3 && ...
            strcmp(result.coordinate, 'mobility'), 'Mass terms.');
    end

    function factor_once()
        [grid, states, relation, analytic] = lognormal_case();
        cfg = set_k(base, 'uncertainty', 0.02);
        once = INV.MASS(grid, states, relation, cfg);
        near(once.mass_ugm3, analytic.mass_ugm3, 1e-9);
        relation.calibrated_1 = false;
        raw = INV.MASS(grid, states, relation, cfg);
        d_nm = grid.elements(:);
        cells = states .* analytic.particle_kg ./ hand_k(d_nm) .* ...
            analytic.width * 1e15;
        near(raw.mass_ugm3, sum(cells), 1e-12);
        outside = d_nm < 21.8 | d_nm > 596;
        near(raw.mass_share_out_of_range, ...
            sum(cells(outside)) / sum(cells), 1e-12);
        u = 0.02 * ones(size(d_nm));
        u(outside) = 0.04;
        near(raw.u_calibration_ugm3, sum(cells .* u), 1e-12);
        check(once.u_calibration_ugm3 > 0 && isnan(once.u_relation_ugm3) && ...
            isnan(once.u_number_ugm3), ...
            'The factor uncertainty enters once for calibrated densities.');
    end

    function pairs_against_power_law()
        cfg = set_k(base, 'uncertainty', 0.02);
        temp = 296.15;
        pressure = 101325;
        lambda = 67.30e-9;
        exponent = 2.4;
        grid_dm = INV.Grid([20 3000], 500);
        dm_nm = grid_dm.elements(:);
        states_dm = lognormal(dm_nm, 1e4, 150, 1.6);
        relation = struct('form', 'power_law', 'rho_ref_kg_m3', 500, ...
            'dm_ref_nm', 100, 'exponent', exponent, 'calibrated_1', false);
        smps = INV.MASS(grid_dm, states_dm, relation, cfg);
        rho = 500 * (dm_nm / 100) .^ (exponent - 3);
        dm = dm_nm * 1e-9;
        target = rho / 1000 .* dm .^ 2 .* reference_cc(dm, lambda);
        lo = dm / 100;
        hi = dm * 100;
        for iteration = 1:200
            mid = sqrt(lo .* hi);
            less = mid .^ 2 .* reference_cc(mid, lambda) < target;
            lo(less) = mid(less);
            hi(~less) = mid(~less);
        end
        da = sqrt(lo .* hi);
        slope = (exponent - 1 + log_slope(dm, lambda)) ./ ...
            (2 + log_slope(da, lambda));
        grid_da = INV.Grid({da.' * 1e9});
        pairs = struct('form', 'pairs', 'dm_nm', dm_nm, ...
            'temperature_k', temp, 'pressure_pa', pressure, ...
            'calibrated_1', false);
        aac = INV.MASS(grid_da, states_dm ./ slope, pairs, cfg);
        near(aac.rho_eff_kg_m3, smps.rho_eff_kg_m3, 1e-9);
        near(aac.mass_ugm3, smps.mass_ugm3, 1e-4);
        near(aac.u_calibration_ugm3, smps.u_calibration_ugm3, 1e-4);
        check(strcmp(aac.coordinate, 'aerodynamic') && ...
            isnan(aac.u_relation_ugm3), 'Pair mass terms.');
    end

    function mass_refusals()
        [grid, states, relation] = lognormal_case();
        missing = rmfield(relation, 'calibrated_1');
        expect(@() INV.MASS(grid, states, missing, base), 'MASS:Relation');
        expect(@() INV.MASS(1, states, relation, base), 'MASS:Grid');
        bad = states;
        bad(3) = -1;
        expect(@() INV.MASS(grid, bad, relation, base), 'MASS:States');
        pairs = struct('form', 'pairs', 'dm_nm', [1 2], ...
            'temperature_k', 296.15, 'pressure_pa', 101325, ...
            'calibrated_1', false);
        expect(@() INV.MASS(grid, states, pairs, base), 'MASS:Relation');
        expect(@() INV.MASS(grid, states, relation, base, ...
            struct('window', 1)), 'MASS:Options');
        expect(@() INV.MASS(grid, states, relation, base, ...
            struct('covariance_cm6', 1)), 'MASS:Covariance');
    end

    function uncertainty_terms()
        [grid, states, relation] = lognormal_case();
        % No configured uncertainty and no covariance: no total is reported
        none = INV.MASS(grid, states, relation, base);
        check(isnan(none.u_total_ugm3) && isnan(none.u_number_ugm3) && ...
            isnan(none.u_relation_ugm3) && isnan(none.u_calibration_ugm3) ...
            && isempty(none.terms_included), 'Unavailable total.');
        % Only the available terms enter the total
        cfg = set_k(base, 'uncertainty', 0.02);
        calibration = INV.MASS(grid, states, relation, cfg);
        near(calibration.u_total_ugm3, calibration.u_calibration_ugm3, 1e-14);
        check(isequal(calibration.terms_included, {'calibration'}), ...
            'Available terms.');
        % The number term is the delta propagation of the statistic
        covariance = diag((0.05 * states) .^ 2);
        covariance(1, 2) = 0.3 * sqrt(covariance(1, 1) * covariance(2, 2));
        covariance(2, 1) = covariance(1, 2);
        mass = INV.MASS(grid, states, relation, base, ...
            struct('covariance_cm6', covariance));
        [~, width] = grid.dr();
        g = analytic_weights(grid, relation, width);
        [~, variance] = INV.DELTA_PROP(states, covariance, ...
            @(x, ~) deal(g.' * x, g.'), true(grid.Ne, 1));
        near(mass.u_number_ugm3, sqrt(variance), 1e-12);
        check(isequal(mass.terms_included, {'number'}) && ...
            mass.u_total_ugm3 == mass.u_number_ugm3, 'Number term only.');
        % Semidefinite singular covariances are valid, indefinite ones not
        zero = INV.MASS(grid, states, relation, base, ...
            struct('covariance_cm6', zeros(grid.Ne)));
        check(zero.u_number_ugm3 == 0, 'Zero covariance.');
        expect(@() INV.MASS(grid, states, relation, base, struct( ...
            'covariance_cm6', -eye(grid.Ne))), 'MASS:Covariance');
        skew = eye(grid.Ne);
        skew(1, 2) = 0.5;
        expect(@() INV.MASS(grid, states, relation, base, ...
            struct('covariance_cm6', skew)), 'MASS:Covariance');
        % Two neighbouring cells at the peak correlated beyond unity
        j = round(grid.Ne / 2) + (0:1);
        indefinite = diag((0.05 * states) .^ 2);
        indefinite(j(1), j(2)) = 2 * sqrt(indefinite(j(1), j(1)) * ...
            indefinite(j(2), j(2)));
        indefinite(j(2), j(1)) = indefinite(j(1), j(2));
        expect(@() INV.MASS(grid, states, relation, base, struct( ...
            'covariance_cm6', indefinite)), 'MASS:Covariance');
        % The power-law covariance obeys the same rules
        relation.covariance = zeros(2);
        zero = INV.MASS(grid, states, relation, base);
        check(zero.u_relation_ugm3 == 0, 'Zero relation covariance.');
        relation.covariance = -eye(2);
        expect(@() INV.MASS(grid, states, relation, base), 'MASS:Relation');
        relation.covariance = [1 0.5; 0 1];
        expect(@() INV.MASS(grid, states, relation, base), 'MASS:Relation');
        relation.covariance = [1 2; 2 1];
        expect(@() INV.MASS(grid, states, relation, base), 'MASS:Relation');
        relation.covariance = [1 0; 0 1i];
        expect(@() INV.MASS(grid, states, relation, base), 'MASS:Relation');
        relation.covariance = [1 0; 0 NaN];
        expect(@() INV.MASS(grid, states, relation, base), 'MASS:Relation');
    end

    function [grid, states, relation, analytic] = lognormal_case()
        % N 1e4 cm^-3, CMD 150 nm, GSD 1.6, rho 500 kg/m3 at 100 nm, Dm 2.4
        grid = INV.Grid([5 8000], 600);
        d_nm = grid.elements(:);
        states = lognormal(d_nm, 1e4, 150, 1.6);
        relation = struct('form', 'power_law', 'rho_ref_kg_m3', 500, ...
            'dm_ref_nm', 100, 'exponent', 2.4, 'calibrated_1', true);
        s2 = log(1.6)^2;
        analytic.mass_ugm3 = 1e4 * 1e6 * pi / 6 * 500 * ...
            (100e-9)^(3 - 2.4) * ...
            (150e-9)^2.4 * exp(2.4^2 * s2 / 2) * 1e9;
        analytic.exponent_slope = log(150 / 100) + 2.4 * s2;
        analytic.particle_kg = pi / 6 * 500 * (d_nm / 100) .^ (2.4 - 3) .* ...
            (d_nm * 1e-9) .^ 3;
        [~, analytic.width] = grid.dr();
    end

    function cfg = set_k(cfg, field, value)
        cfg.calibration.k_dm.(field) = value;
        if strcmp(field, 'range_nm'), value = value * 1e-9; end
        cfg.si.calibration.k_dm.(field) = value;
    end
end

function g = analytic_weights(grid, relation, width)
% "analytic_weights" gives the mass per unit dN/dlog10(d) of each cell (ug/m3).
d = grid.elements(:) * 1e-9;
rho = relation.rho_ref_kg_m3 * ...
    (d / (relation.dm_ref_nm * 1e-9)) .^ (relation.exponent - 3);
g = pi / 6 * rho .* d .^ 3 .* width * 1e15;
end

function k = hand_k(d_nm)
% "hand_k" evaluates the published factor with dm in nm.
k = 1.27 - 3.598 * d_nm .^ -0.8376;
end

function j = jacobian_rows(d_nm)
% "jacobian_rows" gives the derivatives of k in offset, coefficient, exponent.
d_nm = d_nm(:);
j = [ones(size(d_nm)), d_nm .^ -0.8376, -3.598 * d_nm .^ -0.8376 .* log(d_nm)];
end

function n = lognormal(d_nm, total, cmd, gsd)
% "lognormal" gives dN/dlog10(d) of a lognormal number distribution.
s = log10(gsd);
n = total / (sqrt(2 * pi) * s) * exp(-(log10(d_nm / cmd)) .^ 2 / (2 * s^2));
end

function cc = reference_cc(d, lambda)
% "reference_cc" evaluates Kim et al. (2005, Eq. 34) independently.
kn = 2 * lambda ./ d;
cc = 1 + kn .* (1.165 + 0.483 * exp(-0.997 ./ kn));
end

function g = log_slope(d, lambda)
% "log_slope" gives d ln(Cc)/d ln(d) of the same slip correction.
kn = 2 * lambda ./ d;
e = 0.483 * exp(-0.997 ./ kn);
g = -kn .* (1.165 + e .* (1 + 0.997 ./ kn)) ./ reference_cc(d, lambda);
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
    error('sootMosaic:QA:InvCalibMassFailed', '%s', message);
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
