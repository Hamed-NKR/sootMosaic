function report = TEST_INV_KERNEL()
% "TEST_INV_KERNEL" checks grids and forward kernels with synthetic inputs.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Named cases and pass flags. Any failure raises...
%         ...sootMosaic:QA:InvKernelFailed. Step fitting uses 200 fixed-seed...
%         ...Poisson realizations; no measured instrument files are read
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Sec. 2.2, Eqs. 23 and 28);
%     ...Chen et al. (2024, Eqs. 2, 5, 22-26, 36-39);
%     ...Collins et al. (2002, Eqs. 9-14); grid and impactor rules of...
%     ...config/main_inv/DEFAULTS.md, sections 7 and 12. The checks cover...
%     ...grid mechanics and conditional amplitude. Refits of the...
%     ...distribution and regularization with N, GM and GSD posterior...
%     ...comparisons are outside this test.

try
    root = fileparts(fileparts(mfilename('fullpath')));
    file = fullfile(root, 'config', 'main_inv', 'main_inv_config.example.json');
    data.scan = struct('dma_aerosol_flow_lpm', 0.3, ...
        'dma_sheath_flow_lpm', 2.5, 'dma_excess_flow_lpm', 2.5, ...
        'dma_temperature_deg_c', 23, 'dma_pressure_kpa', 101.325, ...
        'aac_temperature_deg_c', 23, 'aac_pressure_kpa', 101.325, ...
        'aac_sample_flow_lpm', 0.3, 'aac_sheath_flow_lpm', 3, ...
        'aac_setpoint_nm', 100, 'aac_speed_rad_s', 362.77443708913876, ...
        'neutralizer_on', true, ...
        'particle_polarity', 'positive', 'delay_s', 0.1, ...
        'delay_adjustment_s', 0, 'bin_time_s', 0.02, ...
        'low_hold_s', 1, 'up_time_s', 120, 'high_hold_s', 2, ...
        'voltage_low_v', 10, 'voltage_high_v', 10000, ...
        'window_min_nm', 14.1, 'window_max_nm', 964.7, ...
        'impactor_d50_nm', 1384);
    data.instruments = struct('impactor_nozzle_cm', 0.071, 'impactor_flow_lpm', 0.3);
    data.penetration.tubes = {struct('id', 'synthetic zero external path', ...
        'length_m', 0, 'bore_mm', 4, 'flow_lpm', 0.3)};
    cfg = UTILS.LOAD_MAIN_INV_CONFIG(file, data);
    % Declaring a synthetic efficiency characterization for these fixtures
    cfg.cpc.unity_bound_citation = 'Synthetic bound for QA only';
    cfg.cpc.unity_bound_max_deficit = 0.02;
    cfg.si.cpc.unity_bound_max_deficit = 0.02;
    cfg.cpc.unity_bound_min_diameter_nm = 1;
    cfg.si.cpc.unity_bound_min_diameter_nm = 1e-9;
    cfg.scan_response.enabled = false;
    imp = struct('d50_m', 1384e-9, 'cut_factor_1', 1, ...
        'sharpness_1', 9, 'rho_kg_m3', 1000);
    draw = struct('charge_e', 1, 'diffusing_1', false);
    old_rng = rng;
    rng_cleanup = onCleanup(@() rng(old_rng));
    old_warning = warning('off', 'sootMosaic:CHARGE_FRAC:OutsideRange');
    warning_cleanup = onCleanup(@() warning(old_warning));
    rng(25, 'twister');
    tests = {@grids, @partial_grid, @reduced_guard, @hand_forward, ...
        @quadrature, @travel, @interval_operator, @step_fit, ...
        @desmearing, @exposure_order, @scan_cmd, @tandem_integral, ...
        @aac_marginal, @support_rule, @convergence, @refusals_and_draws};
    names = {'Grid centers boundaries and widths', 'Partial density mask', ...
        'Reduced observation refusal', 'Hand forward distribution', ...
        'Lognormal independent quadrature and two refinements', ...
        'Travel density normalization and mean', 'Delay and interval averaging', ...
        'Analytical step and repeated Poisson fit', ...
        'Derivative and causal de-smearing', 'Unequal exposures after smearing', ...
        'Forward and de-smeared CMD on up and down histories', ...
        'Tandem independent integral', 'Ideal AAC marginal identity', ...
        'Impactor and charge-dependent grid support', ...
        'Point and SD grid convergence', 'Recorded inputs and kernel draws'};
    pass = false(size(tests));
    for k = 1:numel(tests)
        tests{k}();
        pass(k) = true;
    end
    report = struct('name', names(:), 'pass', num2cell(pass(:)));
catch err
    error('sootMosaic:QA:InvKernelFailed', '%s (%s)', err.message, err.identifier);
end

    function grids()
        g = INV.Grid([0.01, 100; 10, 1000], [10, 12]);
        check(isequal(g.ne, [10, 12]) && g.Ne == 120, 'Upstream demo shape.');
        near(g.edges{1}, 10.^(-2+(0:9)*4/9), 1e-11);
        [area, w1, w2] = g.dr();
        near(w1, repmat(4/9, 120, 1), 3e-15);
        near(w2, repmat(2/11, 120, 1), 3e-15);
        near(area, repmat(8/99, 120, 1), 3e-15);
        g = INV.Grid({[10, 100, 1000]});
        near(g.nodes{1}, sqrt(10)*[1, 10, 100, 1000], 1e-11);
        near(g.dr(), ones(3, 1), 1e-14);
        g = INV.Grid({[1, 2, 4]}, [], 'linear');
        near(g.nodes{1}, [0.5, 1.5, 3, 5], 0);
        near(g.dr(), [1; 1.5; 2], 0);
        g = INV.Grid({[10, 20], [30, 40, 50]});
        near(g.elements, [10,30;20,30;10,40;20,40;10,50;20,50], 0);
        near(g.vectorize(g.reshape((1:6).')), (1:6).', 0);
        near(full(g.l1()*ones(6, 1)), zeros(7, 1), 0);
    end

    function partial_grid()
        g = INV.Grid({[20, 50, 100, 250, 1000], [20, 80, 300, 1000]});
        rho = INV.RHO_EFF(g.elements(:, 1)*1e-9, ...
            g.elements(:, 2)*1e-9, 296.15, 101325, cfg);
        keep = rho >= 20 & rho <= 3000;
        near(find(keep), [1;2;6;7;8;11;12;13;14;18;19;20], 0);
        p = g.partial(keep);
        near(p.elements, g.elements(keep, :), 0);
        w = g.dr();
        near(p.dr(), w(keep), 0);
        near(full(p.adj), full(g.adj(keep, keep)), 0);
        x = [(1:g.Ne).', (g.Ne:-1:1).'];
        restored = p.partial2full(p.full2partial(x));
        near(restored(keep, :), x(keep, :), 0);
        near(restored(~keep, :), zeros(nnz(~keep), 2), 0);
        near(p.retained, find(keep), 0);
        v = (1:p.Ne).';
        near(p.vectorize(p.reshape(v)), v, 0);
    end

    function reduced_guard()
        g = INV.Grid({[50, 100, 200]});
        o = observation(voltage(100e-9), 1);
        for label = {'dW', 'dW/dlogDp', 'dN/dlog10Dm'}
            reduced = o;
            reduced.quantity = label{1};
            reduced.reduced = true;
            reduced.route = 'B';
            expect(@() INV.KERNEL_1D(g, reduced, cfg, imp), ...
                'sootMosaic:KERNEL_1D:ReducedObservation');
            g2 = INV.Grid({[50, 100], [50, 100]});
            expect(@() INV.KERNEL_2D(g2, {reduced}, {cfg}, {imp}), ...
                'sootMosaic:KERNEL_2D:ReducedObservation');
        end
        o.quantity = 'dW';
        expect(@() INV.KERNEL_1D(g, o, cfg, imp), ...
            'sootMosaic:KERNEL_1D:ReducedObservation');
    end

    function hand_forward()
        g = INV.Grid({[50, 100, 200]});
        o = observation(voltage(100e-9), 2);
        [a, meta] = INV.KERNEL_1D(g, o, cfg, imp, draw);
        f1 = 10^(-2.35889+0.45169*2+0.99798*4-0.48173*8+0.02631*16+0.00804*32);
        loss = 0.98;
        for length_m = [7.1, 2.1, 1.51, 0.33, 0.25]
            u = 6.813809258593193e-10*length_m/(0.3/60000);
            loss = loss*(1-5.5*u^(2/3)+3.77*u+0.814*u^(4/3));
        end
        expected = 2*f1*loss/(1+(100/1384)^9)*log10(2)*1000;
        near(a*[0; 1000; 0], expected, 2e-9);
        near(meta.concentration_kernel(1, [1, 3]), [0, 0], 0);
        o.quantity = 'raw concentration';
        b = INV.KERNEL_1D(g, o, cfg, imp, draw);
        near(a, 2*b, 1e-14);
    end

    function quadrature()
        o = observation(voltage(100e-9), 1);
        d = struct('charge_e', [1, 2, 3]);
        f = @(u) direct(10.^u*1e-9, o.voltage_v, [1, 2, 3]).*lognormal(u, 120, 1.5);
        reference = integral(f, log10(40), log10(400), ...
            'Waypoints', log10([80, 100, 150, 200, 300]), ...
            'AbsTol', 1e-8, 'RelTol', 1e-8);
        values = zeros(1, 3);
        for j = 1:3
            n = 256*2^(j-1);
            g = midpoint_grid(40, 400, n);
            a = INV.KERNEL_1D(g, o, cfg, imp, d);
            values(j) = a*lognormal(log10(g.elements), 120, 1.5);
        end
        check(all(abs(diff(values))/reference < 1e-3), 'Two reconstruction refinements.');
        check(abs(values(end)/reference-1) < 1e-3, 'Independent forward quadrature.');
    end

    function travel()
        s = struct('time_s', linspace(0.17, 0.17+40*0.23, 20001).', ...
            'tp_s', 0.17, 'tau_s_s', 0.23);
        [e, meta] = INV.SCAN_RESPONSE('travel', s);
        near(trapz(s.time_s, e), 1, 4e-7);
        near(trapz(s.time_s, s.time_s.*e), 0.4, 4e-7);
        near(meta.mean_s, 0.4, 1e-15);
        s.tau_s_s = 0;
        [e, meta] = INV.SCAN_RESPONSE('travel', s);
        near(e, zeros(size(e)), 0);
        near([meta.atom_mass_1, meta.atom_time_s], [1, 0.17], 0);
    end

    function interval_operator()
        s = struct('source_edges_s', (0:3).', 'bin_start_s', [0.5; 1; 2], ...
            'bin_end_s', [1.5; 2; 3], 'tp_s', 0.5, 'tau_s_s', 0, ...
            'initial_steady_1', false);
        h = INV.SCAN_RESPONSE('operator', s);
        near(full(h), [1,0,0;0.5,0.5,0;0,0.5,0.5], 1e-14);
        s.tp_s = 0;
        s.tau_s_s = 1;
        s.bin_start_s = (0:2).';
        s.bin_end_s = (1:3).';
        h = INV.SCAN_RESPONSE('operator', s);
        r = exp(-1);
        reference = [r,0,0;(1-r)^2,r,0;(1-r)^2*r,(1-r)^2,r];
        near(full(h), reference, 2e-15);
        s.initial_steady_1 = true;
        h = INV.SCAN_RESPONSE('operator', s);
        near(full(sum(h, 2)), ones(3, 1), 2e-15);
    end

    function step_fit()
        s = struct('bin_start_s', (0:0.02:1.98).', ...
            'bin_end_s', (0.02:0.02:2).', 'step_time_s', 0.2, ...
            'tp_s', 0.1, 'tau_s_s', 0.233);
        response = INV.SCAN_RESPONSE('step', s);
        after = s.bin_start_s >= 0.3+1e-12;
        expected = 0.233/0.02*(1-exp(-0.02/0.233))* ...
            exp(-(s.bin_start_s(after)-0.3)/0.233);
        near(response(after), expected, 2e-14);
        near(response(s.bin_end_s < 0.3), ones(nnz(s.bin_end_s < 0.3), 1), 1e-14);
        s.volume_cm3 = ones(size(response));
        s.plateau_cm3_inv = 80;
        s.initial_s = [0.08, 0.2];
        fitted = zeros(200, 2);
        for j = 1:200
            s.counts = poisson(80*response);
            fitted(j, :) = INV.SCAN_RESPONSE('fit_step', s);
        end
        check(abs(mean(fitted(:, 1))-0.1) < 0.01, 'Repeated delay recovery.');
        check(abs(mean(fitted(:, 2))-0.233) < 0.01, 'Repeated mixing recovery.');
    end

    function desmearing()
        dt = 0.002;
        edges = (0:dt:2).';
        t = (edges(1:end-1)+edges(2:end))/2;
        source = 1+0.1*t+0.05*t.^2;
        s = struct('source_edges_s', edges, 'bin_start_s', edges(1:end-1), ...
            'bin_end_s', edges(2:end), 'tp_s', 0, 'tau_s_s', 0.1, ...
            'initial_steady_1', false);
        h = INV.SCAN_RESPONSE('operator', s);
        y = h*source;
        back = INV.SCAN_RESPONSE('backsub', struct('operator_1', h, 'values', y));
        near(back, source, 2e-10);
        bad = eye(3);
        bad(1, 2) = eps;
        expect(@() INV.SCAN_RESPONSE('backsub', ...
            struct('operator_1', bad, 'values', ones(3, 1))), ...
            'sootMosaic:SCAN_RESPONSE:Causality');
        expect(@() INV.SCAN_RESPONSE('backsub', ...
            struct('operator_1', zeros(3), 'values', ones(3, 1))), ...
            'sootMosaic:SCAN_RESPONSE:Causality');
        expect(@() INV.SCAN_RESPONSE('backsub', ...
            struct('operator_1', ones(3, 2), 'values', ones(3, 1))), ...
            'sootMosaic:SCAN_RESPONSE:Causality');
        % Using explicit synthetic derivative settings, independent of defaults
        ds = struct('time_s', edges(2:end), 'values', y, 'tau_s_s', 0.1, ...
            'window_count', 7, 'order_count', 2);
        recovered = INV.SCAN_RESPONSE('desmear', ds);
        near(recovered(5:end-4), source(5:end-4), 5e-4);
        ramp = struct('voltage_low_v', 10, 'voltage_high_v', 1000, ...
            'duration_s', 120, 'direction_sign_1', 1, 'tau_s_s', 0.233);
        [up, meta] = INV.SCAN_RESPONSE('ramp', ramp);
        near(up, 120/log(100), 1e-13);
        near(meta.tau_s_over_abs_tau_v_1, 0.233*log(100)/120, 1e-15);
        ramp.direction_sign_1 = -1;
        near(INV.SCAN_RESPONSE('ramp', ramp), -up, 0);
    end

    function exposure_order()
        g = INV.Grid({[50, 100, 200]});
        o = observation(voltage([50; 100; 200]*1e-9), [1; 2; 4]);
        o.time_s = (0:2).';
        o.bin_time_s = 1;
        o.history_edges_s = (0:3).';
        o.history_voltage_v = o.voltage_v;
        c = cfg;
        c.scan_response.enabled = true;
        c.si.scan.delay_s = 1;
        c.si.scan.bin_time_s = 1;
        d = struct('charge_e', 1, 'diffusing_1', false, 'tau_s_s', 1);
        [a, meta] = INV.KERNEL_1D(g, o, c, imp, d);
        r = exp(-1);
        h = [1,0,0;1-r,r,0;r*(1-r),(1-r)^2,r];
        near(a, diag([1,2,4])*h*meta.concentration_kernel, 2e-14);
        check(norm(a-h*diag([1,2,4])*meta.concentration_kernel, 'fro') > 1e-3, ...
            'Exposures must not be mixed.');
        d.tau_s_s = 0;
        c.si.scan.delay_s = 0.5;
        [a, meta] = INV.KERNEL_1D(g, o, c, imp, d);
        h = [1,0,0;0.5,0.5,0;0,0.5,0.5];
        near(a, diag([1,2,4])*h*meta.concentration_kernel, 2e-14);
    end

    function scan_cmd()
        g = midpoint_grid(60, 180, 12);
        truth = lognormal(log10(g.elements), 105, 1.2);
        dt = 0.02;
        n = 401;
        c = cfg;
        c.scan_response.enabled = true;
        d = struct('charge_e', 1, 'tau_s_s', 0.04);
        medians = zeros(2, 4);
        for delay_case = 1:2
            delay_bins = (delay_case-1)*2;
            tp = delay_bins*dt;
            c.si.scan.delay_s = d.tau_s_s+tp;
            for direction = 1:2
                apparent = logspace(log10(50), log10(220), n).';
                if direction == 2, apparent = flipud(apparent); end
                o = observation(voltage(apparent*1e-9), ones(n, 1));
                o.time_s = (0:n-1)'*dt;
                o.bin_time_s = dt;
                o.history_edges_s = (0:n)'*dt;
                o.history_voltage_v = o.voltage_v;
                [a, meta] = INV.KERNEL_1D(g, o, c, imp, d);
                % Integrating constant source cells using Chen et al....
                %     ...(2024, Eqs. 2 and 5) and a steady initial history
                independent_kernel = zeros(n, g.Ne);
                u = zeros(n, 1);
                for row = 1:n
                    response = direct(g.elements*1e-9, ...
                        o.history_voltage_v(row), 1);
                    independent_kernel(row, :) = (response.*g.dr()).';
                    u(row) = sum(response.*truth.*g.dr());
                end
                z = u(max(1, (1:n).'-delay_bins));
                r = exp(-dt/d.tau_s_s);
                cavg = d.tau_s_s/dt*(1-r);
                state = z(1);
                y = zeros(n, 1);
                for row = 1:n
                    y(row) = (1-cavg)*z(row) + cavg*state;
                    state = r*state + (1-r)*z(row);
                end
                y = y.*o.sample_volume_cm3;
                fit_forward = a\y;
                near(meta.timing.tp_s, tp, 0);
                % Shifting the source onto detector cells before removing mixing
                source_rows = max(1, (1:n).'-delay_bins);
                delayed_kernel = independent_kernel(source_rows, :);
                response = struct('source_edges_s', o.history_edges_s, ...
                    'bin_start_s', o.time_s, 'bin_end_s', o.time_s+dt, ...
                    'tp_s', 0, 'tau_s_s', d.tau_s_s, 'initial_steady_1', true);
                mixing = INV.SCAN_RESPONSE('operator', response);
                check(nnz(triu(mixing, 1)) == 0 && all(diag(mixing) > 0), ...
                    'Aligned mixing must be causal with positive diagonal.');
                if tp == 0
                    near(meta.operator_1, mixing, 0);
                else
                    expect(@() INV.SCAN_RESPONSE('backsub', ...
                        struct('operator_1', meta.operator_1, 'values', y)), ...
                        'sootMosaic:SCAN_RESPONSE:Causality');
                end
                back = INV.SCAN_RESPONSE('backsub', ...
                    struct('operator_1', mixing, ...
                    'values', y./o.sample_volume_cm3));
                near(back, z, 1e-6);
                fit_back = delayed_kernel\back;
                near(fit_forward, truth, 1e-6);
                near(fit_back, truth, 1e-6);
                medians(delay_case, 2*direction-1:2*direction) = ...
                    [cmd(g, fit_forward), cmd(g, fit_back)];
                ds = struct('time_s', o.time_s+dt, ...
                    'values', y./o.sample_volume_cm3, ...
                    'tau_s_s', 0.04, 'window_count', 7, 'order_count', 2);
                y0 = INV.SCAN_RESPONSE('desmear', ds);
                use = 5:n-4;
                fit_ds = delayed_kernel(use, :)\y0(use);
                check(abs(cmd(g, fit_ds)/cmd(g, truth)-1) < 0.01, 'Derivative CMD recovery.');
            end
        end
        near(medians, repmat(cmd(g, truth), 2, 4), 1e-6);
    end

    function tandem_integral()
        g = INV.Grid({midpoint_centers(70, 140, 160), midpoint_centers(50, 200, 200)});
        o = observation(voltage(100e-9), 1);
        d = struct('charge_e', [1, 2]);
        a = INV.KERNEL_2D(g, {o}, {cfg}, {imp}, d);
        x = lognormal(log10(g.elements(:, 1)), 100, 1.15).* ...
            lognormal(log10(g.elements(:, 2)), 100, 1.2)/1000;
        value = a*x;
        reference = integral2(@integrand2, log10(70), log10(140), ...
            log10(50), log10(200), 'AbsTol', 1e-6, 'RelTol', 2e-5);
        check(abs(value/reference-1) < 1e-3, 'Full tandem quadrature.');
        keep = INV.RHO_EFF(g.elements(:, 1)*1e-9, ...
            g.elements(:, 2)*1e-9, 296.15, 101325, cfg);
        mask = keep >= 20 & keep <= 3000;
        partial = INV.KERNEL_2D(g.partial(mask), {o}, {cfg}, {imp}, d);
        near(partial, a(:, mask), 1e-14);
    end

    function value = integrand2(u, v)
        shape = size(u);
        da = 10.^u(:)*1e-9;
        dm = 10.^v(:)*1e-9;
        base = direct(dm, voltage(100e-9), [1, 2]);
        % Replacing the 1D unit-density impactor with the aerodynamic axis
        base = base.*(1+(dm/imp.d50_m).^9)./(1+(da/imp.d50_m).^9);
        [mu, ~, cc, params] = INV.GAS(296.15, 101325, da, cfg);
        tau = params.constants.rho_aero_ref_kg_m3*da.^2.*cc/(18*mu);
        aa = INV.TFER_AAC(tau, 100e-9, dm, cfg, 'synthetic integral');
        value = reshape(base.*aa.*lognormal(u(:), 100, 1.15).* ...
            lognormal(v(:), 100, 1.2)/1000, shape);
    end

    function aac_marginal()
        % The ideal factor identity uses unit DMA and charge factors
        g = INV.Grid({[70, 100, 140], [98, 100, 102]});
        [~, wa, wm] = g.dr();
        da = g.elements(:, 1)*1e-9;
        dm = g.elements(:, 2)*1e-9;
        [mu, ~, cc, params] = INV.GAS(296.15, 101325, da, cfg);
        tau = params.constants.rho_aero_ref_kg_m3*da.^2.*cc/(18*mu);
        [aa, meta] = INV.TFER_AAC(tau, 100e-9, dm, cfg, 'ideal marginal');
        aa = aa./meta.transmission;
        o = observation(voltage(100e-9), 1);
        actual = INV.KERNEL_2D(g, {o}, {cfg}, {imp}, draw);
        gm = INV.Grid({[98, 100, 102]});
        [~, one] = INV.KERNEL_1D(gm, o, cfg, imp, draw);
        base = one.concentration_kernel./(gm.dr().'.*one.impactor_1.');
        base = repelem(base, 3).';
        removed = base.*meta.transmission./(1+(da/imp.d50_m).^9);
        ideal_kernel = actual./removed.';
        x = reshape(1:9, [], 1);
        near(ideal_kernel, (aa.*wa.*wm).', 1e-13);
        marginal = sum(reshape(x.*wm, 3, 3), 2);
        near(ideal_kernel*x, (aa(1:3).*wa(1:3)).'*marginal, 1e-13);
    end

    function support_rule()
        ds = logspace(log10(14.1), log10(964.7), ...
            ceil(128*log10(964.7/14.1))+1).';
        o = observation(voltage(ds*1e-9), ones(size(ds)));
        rho = @(dm) 510*(dm/100e-9).^(-0.65);
        [g, rule] = INV.GRID_RULE(o, cfg, rho);
        near(rule.impactor.d50_m*1e9, 1384, 1);
        check(rule.outside_nozzle_range_1, 'Out-of-range impactor flow flag.');
        check(numel(rule.sensitivity_cases) == 4, 'Separate impactor cases.');
        near([rule.sensitivity_cases.cut_factor_1], [0.69, 1.3, 1, 1], 0);
        near([rule.sensitivity_cases.sharpness_1], [9, 9, 3, 9], 0);
        p = rule.probe_centers_nm;
        first = find(rule.relative_column_sum_1 > cfg.grid.support_threshold, 1);
        near(g.edges{1}(1), p(first-1), 1e-10);
        check(abs(log10(rule.support_centers_nm(2)/16800)) <= 1/cfg.grid.points_per_decade, ...
            'Soft x-ray support must lie within one cell of 16.8 um.');
        near(rule.window_band_m(1), 14.1e-9, 1e-23);
        near(rule.above_window_band_m, [964.7, 1400]*1e-9, 1e-21);
        check(g.edges{1}(end) > 1400, 'The reporting cap must not truncate the kernel.');
        c = cfg;
        c.si.report.d_floor_nm = 20e-9;
        [gf, rf] = INV.GRID_RULE(o, c, rho);
        near(gf.elements, g.elements, 0);
        near(rf.article_floor_m, 14.1e-9, 1e-23);
        near(rf.window_band_m(1), 20e-9, 0);
    end

    function convergence()
        g = midpoint_grid(40, 400, 32);
        good = INV.GRID_CONVERGE(g, @stable_statistic, cfg);
        check(good.pass, 'Converged point values and SDs.');
        bad = INV.GRID_CONVERGE(g, @unstable_sd, cfg);
        check(~bad.pass, 'An unconverged SD must fail.');
        bad = INV.GRID_CONVERGE(g, @unstable_value, cfg);
        check(~bad.pass, 'An unconverged point value must fail.');
        near(good.fine_grid.nodes{1}([1,end]), g.nodes{1}([1,end]), 1e-10);
        check(good.wide_grid.edges{1}(1) < g.edges{1}(1), 'Lower extent widens.');
        check(log10(good.wide_grid.edges{1}(end)/g.edges{1}(end)) >= 0.15, ...
            'Upper extent widens by at least 0.15 decades.');
        % Checking grid convergence on the P1 and P2 shapes with an exact...
            % ...scalar Gaussian amplitude posterior
        gp = midpoint_grid(10, 30000, 1024);
        for phantom = 1:2
            volts = voltage([60; 120; 300]*1e-9);
            expected = zeros(3, 1);
            for row = 1:3
                expected(row) = integral(@(u) direct(10.^u*1e-9, ...
                    volts(row), [1, 2, 3]).*phantom_shape(u, phantom), ...
                    1, log10(30000), 'RelTol', 1e-7, 'AbsTol', 1e-7);
            end
            evaluator = @(gg, source) amplitude_posterior(gg, source, ...
                phantom, volts, expected);
            result = INV.GRID_CONVERGE(gp, evaluator, cfg);
            check(result.pass, 'P1/P2 conditional amplitude grid convergence.');
        end
    end

    function result = amplitude_posterior(g, source, phantom, volts, expected)
        o = observation(volts, 1);
        a = INV.KERNEL_1D(g, o, cfg, imp, struct('charge_e', [1, 2, 3]));
        response = a*phantom_shape(log10(g.elements), phantom);
        y = expected;
        if strcmp(source, 'measured'), y = round(expected); end
        precision = sum(response.^2./expected)+1e-4;
        result = struct('value', sum(response.*y./expected)/precision, ...
            'sd', 1/sqrt(precision));
    end

    function result = stable_statistic(g, source)
        check(any(strcmp(source, {'expected', 'measured'})), 'Fixed data source label.');
        % A known P1-type lognormal evaluated on each reconstruction grid
        x = lognormal(log10(g.elements), 120, 1.5);
        w = g.dr();
        total = sum(w.*x);
        gm = exp(sum(w.*x.*log(g.elements))/total);
        result = struct('value', [total; gm], 'sd', [100; 10]);
    end

    function result = unstable_sd(g, source)
        result = stable_statistic(g, source);
        result.sd = result.sd*(g.Ne/32);
    end

    function result = unstable_value(g, source)
        result = stable_statistic(g, source);
        result.value = result.value + result.sd*(g.Ne/32);
    end

    function refusals_and_draws()
        g = INV.Grid({[50, 100, 200]});
        o = observation(voltage(100e-9), 1);
        c = cfg;
        idx = strcmp({c.reading.path}, 'scan.dma_sheath_flow_lpm');
        c.reading(idx).source = 'config';
        expect(@() INV.KERNEL_1D(g, o, c, imp, draw), ...
            'sootMosaic:TFER_DMA:MissingRecordedInput');
        c = cfg;
        c.si.cpc.unity_bound_min_diameter_nm = [];
        expect(@() INV.KERNEL_1D(g, o, c, imp, draw), ...
            'sootMosaic:CPC_EFF:UncharacterizedEfficiency');
        d = draw;
        d.cpc_scale_1 = 0.99;
        a = INV.KERNEL_1D(g, o, cfg, imp, draw);
        b = INV.KERNEL_1D(g, o, cfg, imp, d);
        near(b, 0.99*a, 1e-14);
        d = struct('charge_e', [1, 2, 3]);
        [~, meta] = INV.KERNEL_1D(g, o, cfg, imp, d);
        near(meta.components.charge.charge_e, [1, 2, 3], 0);
        d.impactor_cut_factor_1 = 0.69;
        expect(@() INV.KERNEL_1D(g, o, cfg, imp, d), ...
            'sootMosaic:KERNEL_1D:Draw');
        c = cfg;
        c.si.scan.dma_excess_flow_lpm = 2.55/60000;
        [~, meta] = INV.KERNEL_1D(g, o, c, imp, draw);
        near(meta.components.aerosol_over_sample_flow_1, 1.2, 1e-13);
        c = cfg;
        c.si.scan.aac_speed_rad_s = [];
        g2 = INV.Grid({[50, 100], [50, 100]});
        expect(@() INV.KERNEL_2D(g2, {o}, {c}, {imp}, draw), ...
            'sootMosaic:AAC_SETPOINT:MissingInput');
        [~, setpoint] = INV.AAC_SETPOINT(cfg, 'synthetic recorded step');
        near(setpoint, 100e-9, 1e-20);
        % Checking recorded consistency independently of the sheath-flow draw
        saved = warning('on', 'sootMosaic:AAC_SETPOINT:SetpointMismatch');
        restore = onCleanup(@() warning(saved));
        d = draw;
        d.aac_sheath_scale_1 = 1.2;
        lastwarn('');
        INV.KERNEL_2D(g2, {o}, {cfg}, {imp}, d);
        [~, identifier] = lastwarn;
        check(~strcmp(identifier, 'sootMosaic:AAC_SETPOINT:SetpointMismatch'), ...
            'A sheath-flow draw must not change the recorded setpoint check.');
        c = cfg;
        c.si.scan.aac_speed_rad_s = 2*c.si.scan.aac_speed_rad_s;
        lastwarn('');
        INV.KERNEL_2D(g2, {o}, {c}, {imp}, draw);
        [~, identifier] = lastwarn;
        check(strcmp(identifier, 'sootMosaic:AAC_SETPOINT:SetpointMismatch'), ...
            'Inconsistent recorded speed must warn.');
    end

    function out = direct(dm, v, charges)
        shape = size(dm);
        dm = dm(:);
        [mu, ~, cc, params] = INV.GAS(296.15, 101325, dm, cfg);
        f = INV.CHARGE_FRAC(dm, charges, 296.15, 101325, struct('Config', cfg));
        out = zeros(size(dm));
        for q = 1:numel(charges)
            z = charges(q)*params.constants.e_c*cc./(3*pi*mu*dm);
            out = out + f(:, q).*INV.TFER_DMA(z, v, charges(q), cfg);
        end
        internal = INV.PENETRATION(dm, 296.15, 101325, 0.3/60000, cfg, 'internal');
        proxy = INV.PENETRATION(dm, 296.15, 101325, 0.3/60000, cfg, 'dma_proxy');
        out = out.*internal.*proxy.*INV.CPC_EFF(dm, cfg)./(1+(dm/imp.d50_m).^9);
        out = reshape(out, shape);
    end

    function v = voltage(dm)
        [mu, ~, cc, params] = INV.GAS(296.15, 101325, dm, cfg);
        z = params.constants.e_c*cc./(3*pi*mu*dm);
        geom = cfg.si.geometry;
        v = cfg.si.scan.dma_sheath_flow_lpm*log(geom.dma_outer_radius_m/ ...
            geom.dma_inner_radius_m)./(2*pi*geom.dma_length_m*z);
    end
end

function o = observation(voltage_v, volume)
n = numel(voltage_v);
if isscalar(volume), volume = repmat(volume, n, 1); end
o = struct('route', 'A', 'reduced', false, 'quantity', 'raw counts', ...
    'source_kind', 'smps_database', 'values', zeros(n, 1), ...
    'voltage_v', voltage_v(:), 'sample_volume_cm3', volume(:));
end

function g = midpoint_grid(low, high, n)
g = INV.Grid({midpoint_centers(low, high, n)});
end

function d = midpoint_centers(low, high, n)
h = log10(high/low)/n;
d = 10.^(log10(low)+h*((1:n)-0.5));
end

function x = lognormal(logd, median_nm, gsd)
sigma = log10(gsd);
x = 1000/(sqrt(2*pi)*sigma)*exp(-0.5*((logd-log10(median_nm))/sigma).^2);
end

function x = phantom_shape(logd, phantom)
if phantom == 1
    x = 20*lognormal(logd, 120, 1.7);
else
    x = 3*lognormal(logd, 60, 1.5)+2*lognormal(logd, 300, 1.6);
end
end

function median_nm = cmd(g, x)
w = g.dr();
logd = log(g.elements);
a = [ones(size(logd)), logd, logd.^2];
% Fitting the latent lognormal at positive cells
use = x > max(x)*1e-8 & w > 0;
coef = a(use, :)\log(x(use));
median_nm = exp(-coef(2)/(2*coef(3)));
end

function y = poisson(mean_value)
% Inverting the Poisson CDF at the modest means of the step fixture
y = zeros(size(mean_value));
for j = 1:numel(y)
    p = exp(-mean_value(j));
    total = p;
    u = rand;
    k = 0;
    while u > total
        k = k+1;
        p = p*mean_value(j)/k;
        total = total+p;
        if k > 1000
            error('sootMosaic:QA:InvKernelFailed', 'Poisson fixture exceeded its range.');
        end
    end
    y(j) = k;
end
end

function near(actual, expected, tolerance)
check(isequal(size(actual), size(expected)), 'Array shapes differ.');
check(all(isfinite(actual(:))) && ...
    all(abs(actual(:)-expected(:)) <= tolerance), 'Numeric comparison failed.');
end

function expect(fn, identifier)
try
    fn();
catch err
    check(strcmp(err.identifier, identifier), ['Unexpected identifier ' err.identifier]);
    return;
end
error('sootMosaic:QA:InvKernelFailed', 'Expected refusal did not occur.');
end

function check(condition, message)
if ~isscalar(condition) || ~condition
    error('sootMosaic:QA:InvKernelFailed', '%s', message);
end
end
