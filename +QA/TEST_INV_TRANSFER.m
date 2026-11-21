function report = TEST_INV_TRANSFER()
% "TEST_INV_TRANSFER" checks transfer functions and losses on synthetic data.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Any failure raises...
%         ...sootMosaic:QA:InvTransferFailed
% ----------------------------------------------------------------------- %
% Method: Stolzenburg (2018, Eqs. 18, 30, 34, A2-A5); Johnson et al....
%     ...(2018, Eqs. 7, 12-15); Tavakoli and Olfert (2013, Eqs. 4-11);...
%     ...Karlsson and Martinsson (2003, Eqs. 13-14, Table 6).

try
    root = fileparts(fileparts(mfilename('fullpath')));
    config_file = fullfile(root, 'config', 'main_inv', ...
        'main_inv_config.example.json');
    data.scan = struct('dma_aerosol_flow_lpm', 2, ...
        'dma_sheath_flow_lpm', 20, 'dma_excess_flow_lpm', 20, ...
        'dma_temperature_deg_c', 23, 'dma_pressure_kpa', 101.325, ...
        'aac_sample_flow_lpm', 0.3, 'aac_sheath_flow_lpm', 3, ...
        'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325);
    cfg = UTILS.LOAD_MAIN_INV_CONFIG(config_file, data);
    [mu, ~, cc, params] = INV.GAS(296.15, 101325, 20e-9, cfg);
    z20 = params.constants.e_c*cc/(3*pi*mu*20e-9);
    voltage = dma_voltage(cfg, z20);
    tests = {@dma_nondiffusing, @dma_geometry, @dma_diffusion, ...
        @dma_flows, @aac_branches, @aac_width_transmission, ...
        @aac_scales, @aac_state, @aac_limited, @tube_losses, ...
        @internal_losses, @cpc_unity, @refusals, @recorded_inputs};
    names = {'DMA area and log FWHM', 'DMA geometry at each flow ratio', ...
        'DMA diffusion width and independent convolution', ...
        'DMA sheath and unequal flows', 'AAC deposition branches', ...
        'AAC width and mobility diffusion', 'AAC scale arguments', ...
        'AAC recorded gas state', 'AAC limited trajectories', ...
        'Tube penetration and leading coefficient', ...
        'Software paths and DMA proxy', 'CPC sourced efficiency bound', ...
        'Input refusals', 'recorded transfer inputs'};
    pass = false(size(tests));
    for k = 1:numel(tests)
        tests{k}();
        pass(k) = true;
    end
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
catch err
    error('sootMosaic:QA:InvTransferFailed', '%s (%s)', ...
        err.message, err.identifier);
end

    function dma_nondiffusing()
        z = linspace(0.8, 1.2, 4001);
        [response, meta] = INV.TFER_DMA(z*z20, voltage, 1, cfg, false);
        near(trapz(z, response), meta.beta, 1e-12);
        fn = @(x) INV.TFER_DMA(exp(x)*z20, voltage, 1, cfg, false)-0.5;
        left = fzero(fn, log([0.9, 1]));
        right = fzero(fn, log([1, 1.1]));
        near(right-left, log((1+meta.beta/2)/(1-meta.beta/2)), 1e-10);
        near(meta.sigma_z_ratio, zeros(size(z)), 0);
    end

    function dma_geometry()
        [~, a] = INV.TFER_DMA(z20, voltage, 1, cfg);
        near(a.g_dma, 3.026, 1e-3);
        near([a.xa_ratio, a.xs_ratio, a.ic_difference_ratio], ...
            [0.881161319040852, 0.306010409492049, 0.653011913836782], 2e-12);
        c = cfg;
        c.si.scan.dma_aerosol_flow_lpm = 2.4/60000;
        [~, b] = INV.TFER_DMA(z20, voltage, 1, c);
        near(b.beta, 0.12, 1e-14);
        near(b.g_dma, 3.105853495387849, 2e-11);
        check(b.g_dma > a.g_dma, 'Geometry must change with flow ratio.');
    end

    function dma_diffusion()
        ratios = [0.85, 0.95, 1, 1.05, 1.15];
        [response, meta] = INV.TFER_DMA(ratios*z20, voltage, 1, cfg);
        near(voltage, 163.503159479169, 1e-10);
        near(meta.sigma_z_ratio, sqrt(ratios)*0.0217311900637359, 2e-12);
        independent_response = zeros(size(ratios));
        for j = 1:numel(ratios)
            sig = 0.0217311900637359*sqrt(ratios(j));
            density = @(u) max(0, 1-abs(u-1)/0.1).* ...
                exp(-(ratios(j)-u).^2/(2*sig^2))/(sqrt(2*pi)*sig);
            independent = integral(density, 0.9, 1.1, ...
                'Waypoints', 1, 'AbsTol', 1e-12, 'RelTol', 1e-11);
            independent_response(j) = independent;
            near(response(j), independent, 2e-10);
        end
        population = [1, 2, 4, 2, 1]/10;
        kernel_result = response*population.';
        reference_result = independent_response*population.';
        check(abs(kernel_result/reference_result-1) < 0.01, ...
            'Synthetic kernel row must agree within one percent.');
        check(dma_width(cfg) >= log(1.05/0.95), ...
            'Diffusion cannot narrow the balanced response in this fixture.');
    end

    function dma_flows()
        recorded = data;
        recorded.scan.dma_aerosol_flow_lpm = 0.3;
        recorded.scan.dma_sheath_flow_lpm = 2.5;
        recorded.scan.dma_excess_flow_lpm = 2.5;
        a = UTILS.LOAD_MAIN_INV_CONFIG(config_file, recorded);
        recorded.scan.dma_sheath_flow_lpm = 7;
        recorded.scan.dma_excess_flow_lpm = 7;
        b = UTILS.LOAD_MAIN_INV_CONFIG(config_file, recorded);
        check(dma_width(a) > dma_width(b), ...
            'Sheath flow must narrow the response.');
        recorded.scan.dma_sheath_flow_lpm = 3;
        recorded.scan.dma_excess_flow_lpm = 3.05;
        a = UTILS.LOAD_MAIN_INV_CONFIG(config_file, recorded);
        near(a.scan.dma_excess_flow_lpm, 3.05, 0);
        v = dma_voltage(a, z20);
        z = linspace(0.8, 1.2, 4841);
        [response, meta] = INV.TFER_DMA(z*z20, v, 1, a, false);
        near(meta.delta, -1/11, 1e-13);
        near(max(response), 5/6, 1e-13);
        near(trapz(z, response), meta.beta*(1+meta.delta), 1e-12);
    end

    function aac_branches()
        [~, detail] = INV.PENETRATION(50e-9, 296.15, 101325, ...
            0.3/60000, cfg, 'tube', 1);
        len = 0.007*(0.3/60000)/detail.diffusivity_m2_s;
        [at_join, detail] = INV.PENETRATION(50e-9, 296.15, 101325, ...
            0.3/60000, cfg, 'tube', len);
        near(detail.lower_branch, 0.8262, 5e-5);
        near(detail.upper_branch, 0.8246, 5e-5);
        check(abs(detail.lower_branch-detail.upper_branch) < 0.002, ...
            'Published branch gap tolerance is 0.002 without smoothing.');
        near(detail.delta_dep, 0.007, 2e-18);
        near(at_join, detail.upper_branch, 0.002);
        above = INV.PENETRATION(50e-9, 296.15, 101325, ...
            0.3/60000, cfg, 'tube', len*(1+1e-8));
        near(above, detail.upper_branch, 2e-9);
        below = INV.PENETRATION(50e-9, 296.15, 101325, ...
            0.3/60000, cfg, 'tube', len*(1-1e-8));
        near(below, detail.lower_branch, 2e-9);
    end

    function aac_width_transmission()
        diameters = [100, 500]*1e-9;
        expected = [0.503294457001331, 0.577461419269024];
        for j = 1:2
            tau = relaxation(diameters(j), 296.15, 101325);
            [response, meta] = INV.TFER_AAC(tau, diameters(j), ...
                50e-9, cfg, 'synthetic width');
            near(meta.width_factor, expected(j), 2e-14);
            near(meta.diffusional, 0.658, 0.001);
            near(meta.transmission, 0.526, 0.001);
            near(response, meta.height, 2e-14);
            near(meta.width_error_percent, [-12.8; 17.4], 0);
            x = linspace(1-0.1/expected(j), 1+0.1/expected(j), 2001);
            y = INV.TFER_AAC(x*tau, diameters(j), 50e-9, cfg, 'area');
            near(trapz(x, y), 0.1*meta.transmission, 1e-12);
        end
        tau = relaxation(100e-9, 296.15, 101325);
        [~, a] = INV.TFER_AAC(tau, 100e-9, 20e-9, cfg, 'dm 20');
        [~, b] = INV.TFER_AAC(tau, 100e-9, 50e-9, cfg, 'dm 50');
        near(a.diffusivity_m2_s, 1.378300209822590e-8, 2e-20);
        near(b.diffusivity_m2_s, 2.383598029701685e-9, 2e-21);
        check(a.transmission < b.transmission, 'Diffusion must use dm.');
        near(a.width_factor, b.width_factor, 0);
    end

    function aac_scales()
        tau = relaxation(100e-9, 296.15, 101325);
        x = [0.9, 1, 1.1]*tau;
        [a, ma] = INV.TFER_AAC(x, 100e-9, 50e-9, cfg, 'scales');
        [b, mb] = INV.TFER_AAC(x, 100e-9, 50e-9, cfg, 'scales', 1, 1);
        check(isequal(a, b) && isequal(ma, mb), 'Unit scales must be exact.');
        [peak_value, wide] = INV.TFER_AAC(tau, 100e-9, 50e-9, ...
            cfg, 'width draw', 1, 1.1);
        near(wide.width_factor, 1.1*ma.width_factor, 1e-14);
        near(peak_value, 1.1*ma.height, 1e-14);
        scaled_tau = relaxation(110e-9, 296.15, 101325);
        [peak, shifted] = INV.TFER_AAC(scaled_tau, 100e-9, 50e-9, ...
            cfg, 'sizing draw', 1.1, 1);
        near(shifted.tau_set_s, scaled_tau, 1e-20);
        near(peak, shifted.height, 1e-14);
        near(shifted.transmission, ma.transmission, 0);
    end

    function aac_state()
        c = cfg;
        c.si.scan.aac_temperature_deg_c = 310;
        c.si.scan.aac_pressure_kpa = 90000;
        tau = relaxation(100e-9, 310, 90000);
        [peak, meta] = INV.TFER_AAC(tau, 100e-9, 50e-9, c, 'warm row');
        near(peak, meta.height, 1e-14);
        near(meta.temperature_k, 310, 0);
        near(meta.pressure_pa, 90000, 0);
        [~, expected] = INV.PENETRATION(50e-9, 310, 90000, ...
            0.3/60000, c, 'aac');
        near(meta.diffusivity_m2_s, expected.diffusivity_m2_s, 0);
        c.si.scan.aac_pressure_kpa = [];
        expect(@() INV.TFER_AAC(tau, 100e-9, 50e-9, c, 'missing step'), ...
            'TFER_AAC:MissingInput', 'missing step');
        c = cfg;
        index = strcmp({c.reading.path}, 'scan.aac_pressure_kpa');
        c.reading(index).source = 'config';
        expect(@() INV.TFER_AAC(tau, 100e-9, 50e-9, c, 'unlogged step'), ...
            'TFER_AAC:MissingRecordedInput', 'scan.aac_pressure_kpa');
    end

    function aac_limited()
        c = cfg;
        c.transfer.aac.model = 'tavakoli2013_limited_trajectory';
        tau = relaxation(100e-9, 296.15, 101325);
        x = [0.5, 0.95, 1, 1.05, 1.5];
        response = INV.TFER_AAC(x*tau, 100e-9, 50e-9, c, 'trajectories');
        r1sq = 0.056^2;
        r2sq = 0.060^2;
        growth = exp(4*(r2sq-r1sq)/(1.1*(0.056+0.060)^2)*x);
        radius_ratio = r1sq/r2sq;
        flow_ratio = 0.1;
        % Evaluating Tavakoli and Olfert (2013, Eqs. 9 and 11, p. 919)
        f1 = ((1+flow_ratio) - ...
            (1+flow_ratio-flow_ratio*(1-radius_ratio))./growth) / ...
            (flow_ratio*(1-radius_ratio)) - 1/flow_ratio;
        f2 = (1+flow_ratio)/flow_ratio * ...
            (1-(1-1./growth)/(1-radius_ratio));
        % Taking the limiting fraction with balanced flows, f3 = 1
        near(response, max(0, min(1, min(f1, f2))), 1e-13);
        unit = INV.TFER_AAC(x*tau, 100e-9, 50e-9, c, 'trajectories', 1, 1);
        check(isequal(response, unit), 'Limited-trajectory unit scales.');
    end

    function tube_losses()
        [eta, meta] = INV.PENETRATION([20, 50]*1e-9, 296.15, ...
            101325, 0.5/60000, cfg, 'tube', 1.88);
        near(eta, [0.895, 0.965], 0.001);
        near(eta, [0.894921626131680, 0.965692806824127], 2e-13);
        exact_leading = 8*0.749/7.312;
        near(exact_leading, 0.8195, 5e-5);
        near(meta.graetz_leading_coefficient_ratio, exact_leading, 0.001);
        len = 0.8*(0.5/60000)/meta.diffusivity_m2_s(1);
        asymptotic = INV.PENETRATION(20e-9, 296.15, 101325, ...
            0.5/60000, cfg, 'tube', len);
        near(asymptotic*exp(11.5*0.8), exact_leading, 0.001);
        near(INV.PENETRATION([20, 50]*1e-9, 296.15, 101325, ...
            0.5/60000, cfg, 'tube', 0), [1, 1], 0);
    end

    function internal_losses()
        d = [20, 50, 100]*1e-9;
        [software, meta] = INV.PENETRATION(d, 296.15, 101325, ...
            0.3/60000, cfg, 'software');
        expected = [0.425807282439650, 0.769616110385197, ...
            0.891741466011662];
        near(software, expected, 2e-13);
        near(meta.length_m, [9.1, 2.1, 1.51, 0.33, 0.25], 0);
        ref = zeros(3, 5);
        diffusivity = [1.378300209822590e-8; ...
            2.383598029701685e-9; 6.813809258593193e-10];
        for j = 1:5
            ref(:, j) = ...
                reference_tube(diffusivity*meta.length_m(j)/(0.3/60000));
        end
        near(meta.components, ref, 2e-13);
        internal = INV.PENETRATION(d, 296.15, 101325, ...
            0.3/60000, cfg, 'internal');
        near(internal, prod(ref(:, 2:5), 2).', 2e-13);
        [proxy, detail] = INV.PENETRATION(d, 296.15, 101325, ...
            0.3/60000, cfg, 'dma_proxy');
        near(proxy, [0.666046375093707, 0.871403064199928, ...
            0.930923130192840], 2e-13);
        near(proxy, (0.98*reference_tube( ...
            diffusivity*7.1/(0.3/60000))).', 2e-13);
        check(detail.dma_proxy && contains(detail.provenance, 'proxy'), ...
            'DMA loss must identify the cylindrical proxy.');
        check(strcmp(detail.endpoint, 'counter inlet'), ...
            'Penetration endpoint.');
    end

    function cpc_unity()
        d = [14, 20, 50, 100]*1e-9;
        expect(@() INV.CPC_EFF(d, cfg), ...
            'CPC_EFF:UncharacterizedEfficiency', 'sourced bound');
        folder = tempname; mkdir(folder);
        cleanup = onCleanup(@() rmdir(folder, 's'));
        raw = struct('extends', config_file);
        raw.cpc.unity_bound_min_diameter_nm = 14;
        raw.cpc.unity_bound_max_deficit = 0.02;
        raw.cpc.unity_bound_citation = 'Synthetic efficiency bound for QA only';
        file = fullfile(folder, 'bound.json');
        write_config(file, raw);
        c = UTILS.LOAD_MAIN_INV_CONFIG(file, data);
        [eta, meta] = INV.CPC_EFF(d, c);
        near(eta, ones(size(d)), 0);
        check(meta.approximation && meta.margin_quantified, 'Bound must be reported.');
        near(meta.unity_margin_ratio, 0.02, 0);
        near(meta.start_m, 14e-9, 1e-23);
        check(strcmp(meta.citation, raw.cpc.unity_bound_citation), 'Bound source.');
        expect(@() INV.CPC_EFF(13e-9, c), ...
            'CPC_EFF:UncharacterizedEfficiency', 'sourced bound');
        keys = {'unity_bound_min_diameter_nm', 'unity_bound_max_deficit', ...
            'unity_bound_citation'};
        for j = 1:numel(keys)
            missing = raw;
            missing.cpc = rmfield(missing.cpc, keys{j});
            write_config(file, missing);
            c = UTILS.LOAD_MAIN_INV_CONFIG(file, data);
            expect(@() INV.CPC_EFF(d, c), ...
                'CPC_EFF:UncharacterizedEfficiency', 'sourced bound');
        end
    end

    function recorded_inputs()
        dma = {'dma_aerosol_flow_lpm', 'dma_sheath_flow_lpm', ...
            'dma_excess_flow_lpm', 'dma_temperature_deg_c', 'dma_pressure_kpa'};
        aac = {'aac_sample_flow_lpm', 'aac_sheath_flow_lpm', ...
            'aac_temperature_deg_c', 'aac_pressure_kpa'};
        for group = 1:2
            if group == 1, keys = dma; caller = 'TFER_DMA';
            else, keys = aac; caller = 'TFER_AAC'; end
            for j = 1:numel(keys)
                c = cfg;
                index = strcmp({c.reading.path}, ['scan.' keys{j}]);
                for source = {'config', 'registry'}
                    c.reading(index).source = source{1};
                    expect(@() transfer_call(c, group), ...
                        [caller ':MissingRecordedInput'], ['scan.' keys{j}]);
                end
                c.reading(index) = [];
                expect(@() transfer_call(c, group), ...
                    [caller ':MissingRecordedInput'], ['scan.' keys{j}]);
            end
        end
        campaign.values.scan = rmfield(data.scan, 'dma_excess_flow_lpm');
        keys = fieldnames(campaign.values.scan);
        for j = 1:numel(keys)
            campaign.reasons.scan.(keys{j}) = 'Synthetic recorded scan';
        end
        recorded.scan.dma_excess_flow_lpm = data.scan.dma_excess_flow_lpm;
        c = UTILS.LOAD_MAIN_INV_CONFIG(config_file, recorded, campaign);
        near(transfer_call(c, 1), transfer_call(cfg, 1), 0);
        near(transfer_call(c, 2), transfer_call(cfg, 2), 0);
    end

    function response = transfer_call(c, group)
        if group == 1
            response = INV.TFER_DMA(z20, voltage, 1, c);
        else
            response = INV.TFER_AAC(1e-7, 100e-9, 50e-9, c, 'synthetic source');
        end
    end

    function refusals()
        expect(@() INV.TFER_DMA(z20, voltage, 0, cfg), ...
            'TFER_DMA:InvalidInput', 'charge');
        c = cfg;
        c.si.scan.dma_excess_flow_lpm = 30/60000;
        expect(@() INV.TFER_DMA(z20, voltage, 1, c), ...
            'TFER_DMA:InvalidFlows', 'sample');
        expect(@() INV.PENETRATION(20e-9, 296.15, 101325, ...
            0.3/60000, cfg, 'tube', -1), ...
            'PENETRATION:InvalidLength', 'length');
        expect(@() INV.TFER_AAC(1e-7, 100e-9, 50e-9, ...
            cfg, 'bad scale', 0), ...
            'TFER_AAC:InvalidInput', 'bad scale');
        c = cfg;
        c.transfer.aac.flow_balance = 'unbalanced';
        expect(@() INV.TFER_AAC(1e-7, 100e-9, 50e-9, c, 'unbalanced'), ...
            'TFER_AAC:InvalidFlows', 'balanced');
    end

    function tau = relaxation(d, temp, pressure)
        [viscosity, ~, slip, constants] = INV.GAS(temp, pressure, d, cfg);
        tau = constants.constants.rho_aero_ref_kg_m3*d^2*slip/(18*viscosity);
    end

    function fwhm_ln = dma_width(c)
        v = dma_voltage(c, z20);
        fn = @(x) INV.TFER_DMA(exp(x)*z20, v, 1, c);
        center = fminbnd(@(x) -fn(x), log(0.8), log(1.2));
        half = fn(center)/2;
        left = fzero(@(x) fn(x)-half, [log(0.4), center]);
        right = fzero(@(x) fn(x)-half, [center, log(1.6)]);
        fwhm_ln = right-left;
    end
end

function voltage = dma_voltage(cfg, mobility)
% "dma_voltage" sets the voltage for a chosen centroid mobility.
s = cfg.si.scan;
g = cfg.si.geometry;
voltage = (s.dma_sheath_flow_lpm+s.dma_excess_flow_lpm) * ...
    log(g.dma_outer_radius_m/g.dma_inner_radius_m) / ...
    (4*pi*g.dma_length_m*mobility);
end

function eta = reference_tube(x)
% "reference_tube" evaluates the published branches independently.
eta = 1 - 5.50*x.^(2/3) + 3.77*x + 0.814*x.^(4/3);
mask = x >= 0.007;
eta(mask) = 0.819*exp(-11.5*x(mask)) + ...
    0.0975*exp(-70.1*x(mask)) + 0.0325*exp(-179*x(mask));
end

function near(actual, expected, tolerance)
% "near" checks absolute error with an explicit tolerance.
check(isequal(size(actual), size(expected)) && ...
    all(isfinite(actual(:))) && ...
    all(abs(actual(:)-expected(:)) <= tolerance), ...
    'Numeric reference mismatch.');
end

function expect(fn, identifier, fragment)
% "expect" checks a refusal and its diagnostic text.
try
    fn();
catch err
    check(strcmp(err.identifier, ['sootMosaic:' identifier]) && ...
        contains(err.message, fragment), 'Unexpected input refusal.');
    return
end
check(false, 'Expected an input refusal.');
end

function check(condition, message)
% "check" reports a failed synthetic transfer test.
if ~condition, error('sootMosaic:QA:InvTransferFailed', '%s', message); end
end

function write_config(file, raw)
fid = fopen(file, 'w');
check(fid >= 0, 'Cannot write synthetic configuration.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(raw));
end
