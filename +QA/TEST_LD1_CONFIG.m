function report = TEST_LD1_CONFIG()
% "TEST_LD1_CONFIG" checks LD1 task reading and profile resolution.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Structure array with name and pass. Temporary fixtures are...
%         ...removed on exit. Failures raise sootMosaic:QA:Ld1ConfigFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok, error('sootMosaic:QA:Ld1ConfigFailed', '%s', message); end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
primary = getenv('SOOTMOSAIC_MAIN_LD1_CONFIG');
fallback = getenv('PFAL_MAIN_LD1_CONFIG');
restore = onCleanup(@() restore_state(state, warn_message, warn_id, ...
    primary, fallback));
warning('on', 'sootMosaic:CONFIG_READ:UnknownKey');
warning('on', 'sootMosaic:LOAD_MAIN_LD1_CONFIG:NoModelProfile');
root = fileparts(fileparts(mfilename('fullpath')));
example = fullfile(root, 'config', 'main_ld1', ...
    'main_ld1_config.example.json');
dictionary = fullfile(root, 'config', 'main_ld1', 'main_ld1.keys.json');
raw = jsondecode(fileread(example));
rows = jsondecode(fileread(dictionary));
if isstruct(rows), rows = num2cell(rows); end
file = fullfile(folder, 'task.json');
strict = struct('Strict', true);
tests = {@coverage, @complete_inputs, @wrapped_inputs, @numeric_inputs, ...
    @text_inputs, @optional_inputs, @pass_through, @profiles, ...
    @choices, @selectors, @overlays, @unknowns, @invalid_inputs, @reader_isolation, ...
    @smoke_config};
names = {'dictionary coverage both ways', 'complete and profile-free tasks', ...
    'native section and whole-task wrappers', 'independent numeric contract', ...
    'text conversion and emptiness', 'optional values and block defaults', ...
    'pass-through and replaced values', 'profile and explicit precedence', ...
    'implemented explicit choices', 'selectors and default path', ...
    'overlays and provenance', ...
    'unknown keys and comments', 'invalid values and required keys', ...
    'reader option isolation', '500 monomers and 50 stored steps'};
pass = false(size(tests));
for k = 1:numel(tests)
    try
        tests{k}();
        pass(k) = true;
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:Ld1ConfigFailed', '%d cases failed.', sum(~pass));
end

    function cfg = load_value(value, controls)
        if nargin < 2, controls = strict; end
        write_text(file, jsonencode(value));
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG(file, controls);
    end

    function cfg = load_text(value, controls)
        if nargin < 2, controls = strict; end
        write_text(file, value);
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG(file, controls);
    end

    function coverage()
        expected = {'config_version', 'extends', 'config_file', ...
            'model_profile', 'model_overrides', 'model', 'model_params', ...
            'model_source', 'results', 'results.root', ...
            'results.library_file', 'results.run_label', 'simulation', ...
            'simulation.n_temporal', 'simulation.n_trial', ...
            'simulation.primary_size_gsd_between_trials', ...
            'simulation.npp_min', 'simulation.npp_max', 'simulation.j_max', ...
            'simulation.rng_seed', 'projection', 'projection.n_mc', ...
            'projection.n_ang', 'projection.options', ...
            'projection.options.tbar', 'transport', 'transport.domain', ...
            'transport.domain.volume_fraction', 'transport.domain.size', ...
            'transport.particles', 'transport.particles.n_par', ...
            'transport.particles.n_pp_mean', 'transport.particles.n_pp_std', ...
            'transport.particles.d_pp_gm', ...
            'transport.particles.d_pp_gsd_between_aggregates', ...
            'transport.particles.d_pp_gsd_within_aggregates', ...
            'transport.fluid', 'transport.fluid.temperature', ...
            'transport.fluid.velocity', 'transport.fluid.pressure', ...
            'transport.fluid_options', 'transport.fluid_options.amb', ...
            'transport.fluid_options.gas', 'transport.mobility_options', ...
            'transport.mobility_options.mtd', ...
            'transport.mobility_options.c_dt', ...
            'transport.mobility_options.step_frac', ...
            'transport.mobility_options.step_policy', ...
            'transport.mobility_options.slip', ...
            'transport.mobility_options.continuum_diameter', ...
            'transport.mobility_options.root_solve', ...
            'transport.mobility_options.projection', ...
            'transport.mobility_options.proj_cache', ...
            'transport.mobility_options.proj_points', ...
            'transport.mobility_options.proj_orientations', ...
            'transport.mobility_options.proj_replicates', ...
            'transport.mobility_options.proj_tol', ...
            'transport.mobility_options.step_warned', ...
            'transport.mobility_options.proj_warned', ...
            'transport.mobility_options.proj_cache_data', ...
            'transport.mobility_options.slip_coefficients', ...
            'transport.location_options', 'transport.location_options.vf', ...
            'transport.location_options.vf_type', 'transport.growth_options', ...
            'transport.growth_options.indupdate', 'transport.growth_options.col', ...
            'transport.growth_options.dom_size', ...
            'transport.diagnostics_options', ...
            'transport.diagnostics_options.knudsen', ...
            'transport.velocity_options', 'transport.velocity_options.sampler'};
        paths = cellfun(@(r) r.path, rows, 'UniformOutput', false);
        check(isequal(sort(paths(:)), sort(expected(:))));
        check(numel(unique(paths)) == numel(paths));
        check(all(ismember(key_paths(raw, ''), paths)));
        explicit = QA.LD1_CONFIG_EXPLICIT_CHOICES(raw);
        check(all(ismember(key_paths(explicit, ''), paths)));
        for n = 1:numel(rows)
            r = rows{n};
            check(all(isfield(r, {'type', 'unit', 'status', 'since', ...
                'reader', 'reading_rule'})) && ~isempty(r.reader) && ...
                ~isempty(r.reading_rule));
            if any(strcmp(r.type, {'object', 'any'}))
                check(isfield(r, 'native_json') && r.native_json);
            end
        end
        contract = numeric_contract();
        for n = 1:size(contract, 1)
            r = rows{strcmp(paths, contract{n, 1})};
            check(strcmp(r.type, contract{n, 2}));
            check(strcmp(r.unit, contract{n, 3}));
            conversion = '';
            if isfield(r, 'coerce'), conversion = r.coerce; end
            check(strcmp(conversion, contract{n, 4}));
            if strcmp(contract{n, 2}, 'integer')
                minimum = 1;
                if strcmp(contract{n, 1}, 'simulation.n_temporal'), minimum = 2; end
                check(r.min == minimum && ~isfield(r, 'max'));
            elseif strcmp(contract{n, 5}, 'vector')
                check(r.row_vector && ~isfield(r, 'min') && ~isfield(r, 'max'));
            elseif strcmp(contract{n, 5}, 'seed')
                check(r.min == 0 && r.max == 4294967295);
            else
                check(~isfield(r, 'min') && ~isfield(r, 'max'));
            end
        end
        required = required_paths();
        marked = cellfun(@(r) isfield(r, 'required') && r.required, rows);
        marked_paths = paths(marked);
        check(isequal(sort(marked_paths(:)), sort(required(:))));
    end

    function complete_inputs()
        a = load_value(raw);
        b = load_value(QA.LD1_CONFIG_EXPLICIT_CHOICES(raw));
        check(isequaln(without_provenance(a), without_provenance(b)));
        value = rmfield(raw, {'model_profile', 'config_version'});
        lastwarn('', '');
        cfg = load_value(value);
        [~, id] = lastwarn;
        check(strcmp(id, 'sootMosaic:LOAD_MAIN_LD1_CONFIG:NoModelProfile'));
        check(cfg.config_version == 1);
        check(~isfield(cfg, 'model_profile') && ~isfield(cfg, 'model_overrides'));
        check(strcmp(cfg.model.profile, 'article1_7658971'));
        for empty = {[], ''}
            value.model_profile = empty{1};
            cfg = load_value(value);
            check(isequal(cfg.model_profile, empty{1}));
            check(strcmp(cfg.model.profile, 'article1_7658971'));
        end
        value = raw;
        value.model_profile = [];
        cfg = load_text(strrep(jsonencode(value), '"model_profile":[]', ...
            '"model_profile":null'));
        check(isempty(cfg.model_profile));
        check(a.config_version == 1 && isequal(a.si.transport, a.transport));
        check(isequal(a.si.results, a.results));
        write_text(file, jsonencode(raw));
        saved_dir = pwd;
        saved_path = path;
        location = onCleanup(@() restore_location(saved_dir, saved_path));
        addpath(root);
        cd(folder);
        relative = UTILS.LOAD_MAIN_LD1_CONFIG('task.json', strict);
        check(strcmp(relative.config_file, 'task.json'));
        check(strcmp(relative.si.config_file, 'task.json'));
        if usejava('jvm')
            check(strcmp(relative.results.root, char(java.io.File( ...
                raw.results.root).getCanonicalPath())));
        else
            check(strcmp(relative.results.root, fullfile('', raw.results.root)));
        end
    end

    function wrapped_inputs()
        paths = {'results', 'simulation', 'projection', 'projection.options', ...
            'transport', 'transport.domain', 'transport.particles', ...
            'transport.fluid', 'transport.fluid_options', ...
            'transport.mobility_options', 'transport.location_options', ...
            'transport.growth_options', 'transport.diagnostics_options', ...
            'transport.velocity_options', 'model_overrides'};
        value = raw;
        value.model_overrides = struct('step', struct('step_frac', 0.3));
        ordinary = load_value(value);
        for n = 1:numel(paths)
            wrapped = put(value, paths{n}, {get(value, paths{n})});
            cfg = load_value(wrapped);
            check(isequaln(without_provenance(cfg), ...
                without_provenance(ordinary)));
        end
        cfg = load_text(['[' jsonencode(value) ']']);
        check(isequaln(without_provenance(cfg), without_provenance(ordinary)));
        value.projection.options = struct();
        a = load_value(value);
        value.projection.options = {struct()};
        b = load_value(value);
        check(isequaln(without_provenance(a), without_provenance(b)));
    end

    function numeric_inputs()
        contract = numeric_contract();
        value = raw;
        value.simulation.npp_min = 1;
        for n = 1:size(contract, 1)
            p = contract{n, 1};
            kind = contract{n, 5};
            if strcmp(kind, 'vector')
                fixtures = {[true false true], 'ABC', [2; 3; 4]};
                expected = {[1 0 1], [65 66 67], [2 3 4]};
                for j = 1:numel(fixtures)
                    cfg = load_value(put(value, p, fixtures{j}));
                    check(isequal(get(cfg, p), expected{j}));
                    check(isequal(get(cfg.si, p), expected{j}));
                end
            elseif strcmp(kind, 'seed')
                fixtures = {[], '', true, 'A', 0, 4294967295};
                expected = {[], [], 1, 65, 0, 4294967295};
                for j = 1:numel(fixtures)
                    cfg = load_value(put(value, p, fixtures{j}));
                    check(isequal(get(cfg, p), expected{j}));
                end
            else
                number = 2;
                if strcmp(kind, 'orientations'), number = 8; end
                cfg = load_value(put(value, p, number));
                check(isequal(get(cfg, p), number));
                check(isequal(get(cfg.si, p), number));
                % Singleton nested arrays decode to the same scalar
                cfg = load_value(put(value, p, {{number}}));
                check(isequal(get(cfg, p), number));
                fails(@() load_value(put(value, p, true)), '');
                fails(@() load_value(put(value, p, 'A')), '');
            end
        end
        cfg = load_value(put(raw, 'transport.domain.volume_fraction', -0.5));
        check(cfg.transport.domain.volume_fraction == -0.5);
        for p = {'transport.particles.n_pp_std', ...
                'transport.particles.d_pp_gsd_between_aggregates', ...
                'transport.particles.d_pp_gsd_within_aggregates'}
            cfg = load_value(put(raw, p{1}, 0));
            check(get(cfg, p{1}) == 0);
        end
        cfg = load_text(strrep(jsonencode(raw), '"rng_seed":[]', ...
            '"rng_seed":[7]'));
        check(cfg.simulation.rng_seed == 7);
        cfg = load_value(drop(raw, 'simulation.rng_seed'));
        check(isequal(cfg.simulation.rng_seed, []));
        cfg = load_text(strrep(jsonencode(raw), '"rng_seed":[]', ...
            '"rng_seed":null'));
        check(isequal(cfg.simulation.rng_seed, []));
    end

    function text_inputs()
        paths = {'results.root', 'results.library_file', 'results.run_label', ...
            'transport.location_options.vf', ...
            'transport.location_options.vf_type', 'projection.options.tbar'};
        fixtures = {65, [65; 66], {'A'; 'BC'}, {''}, {'on'}};
        for n = 1:numel(paths)
            for j = 1:numel(fixtures)
                if strcmp(paths{n}, 'results.root') && j ~= 1, continue; end
                cfg = load_value(put(raw, paths{n}, fixtures{j}));
                expected = char(fixtures{j});
                if strcmp(paths{n}, 'results.root')
                    check(endsWith(cfg.results.root, [filesep expected]));
                else
                    check(isequal(get(cfg, paths{n}), expected));
                end
            end
        end
        for p = {'results.root', 'results.library_file', 'results.run_label', ...
                'transport.location_options.vf'}
            for empty = {[], ''}
                fails(@() load_value(put(raw, p{1}, empty{1})), ...
                    'sootMosaic:LOAD_MAIN_LD1_CONFIG:MissingText');
            end
        end
    end

    function optional_inputs()
        paths = profile_paths();
        for profile = {'current', 'article1_7658971'}
            value = raw;
            value.model_profile = profile{1};
            ordinary = load_value(value);
            for n = 1:numel(paths)
                for empty = {[], ''}
                    cfg = load_value(put(value, paths{n}, empty{1}));
                    check(isequaln(get(cfg, paths{n}), get(ordinary, paths{n})));
                end
                text = jsonencode(put(value, paths{n}, '__null__'));
                cfg = load_text(strrep(text, '"__null__"', 'null'));
                check(isequaln(get(cfg, paths{n}), get(ordinary, paths{n})));
            end
        end
        for p = {'projection.options', 'transport.growth_options'}
            ordinary = load_value(drop(raw, p{1}));
            for input = {[], '', 7, true, {1, 'x'}, struct()}
                cfg = load_value(put(raw, p{1}, input{1}));
                check(isequaln(get(cfg, p{1}), get(ordinary, p{1})));
            end
            text = jsonencode(put(raw, p{1}, '__null__'));
            cfg = load_text(strrep(text, '"__null__"', 'null'));
            check(isequaln(get(cfg, p{1}), get(ordinary, p{1})));
        end
        for p = {'transport.diagnostics_options', 'transport.velocity_options'}
            cfg = load_value(drop(raw, p{1}));
            ordinary = load_value(raw);
            check(isequaln(get(cfg, p{1}), get(ordinary, p{1})));
            fails(@() load_value(put(raw, p{1}, [])), ...
                'sootMosaic:CONFIG_READ:InvalidType');
        end
        for p = {'projection.options.tbar', 'transport.location_options.vf_type'}
            ordinary = load_value(drop(raw, p{1}));
            for empty = {[], ''}
                cfg = load_value(put(raw, p{1}, empty{1}));
                check(isequal(get(cfg, p{1}), get(ordinary, p{1})));
            end
            text = jsonencode(put(raw, p{1}, '__null__'));
            cfg = load_text(strrep(text, '"__null__"', 'null'));
            check(isequal(get(cfg, p{1}), get(ordinary, p{1})));
        end
    end

    function pass_through()
        paths = {'transport.growth_options.indupdate', ...
            'transport.growth_options.col', 'transport.growth_options.dom_size', ...
            'transport.mobility_options.step_warned', ...
            'transport.mobility_options.proj_warned', ...
            'transport.mobility_options.proj_cache_data'};
        fixtures = {[], '', 2, true, [1 2], struct(), 'unused', ...
            [struct('tag', 1); struct('tag', 2)], ...
            struct('values', [1 NaN])};
        for n = 1:numel(paths)
            cfg = load_value(raw);
            check(~has(cfg, paths{n}));
            for j = 1:numel(fixtures)
                value = put(raw, paths{n}, fixtures{j});
                decoded = jsondecode(jsonencode(value));
                cfg = load_value(value);
                check(isequaln(get(cfg, paths{n}), get(decoded, paths{n})));
                check(isequaln(get(cfg.si, paths{n}), get(decoded, paths{n})));
            end
            text = jsonencode(put(raw, paths{n}, '__null__'));
            cfg = load_text(strrep(text, '"__null__"', 'null'));
            check(isequal(get(cfg, paths{n}), []));
        end
        growth = [struct('col', 'agg'); struct('col', 'unused')];
        cfg = load_value(put(raw, 'transport.growth_options', growth));
        check(isequal(cfg.transport.growth_options, growth));
        ordinary = load_value(raw);
        paths = {'config_file', 'model', 'model_params', 'model_source', ...
            'transport.fluid_options.gas', ...
            'transport.mobility_options.slip_coefficients'};
        for n = 1:numel(paths)
            for j = 1:numel(fixtures)
                cfg = load_value(put(raw, paths{n}, fixtures{j}));
                check(isequaln(get(cfg, paths{n}), get(ordinary, paths{n})));
            end
        end
    end

    function profiles()
        current = load_value(raw);
        check(strcmp(current.model.fluid_properties, 'sutherland'));
        check(strcmp(current.model.mobility, 'interp'));
        check(strcmp(current.model.projection, 'isotropic'));
        value = raw;
        value.model_profile = 'article1_7658971';
        cfg = load_value(value);
        [model, ~, params] = UTILS.MODEL_PROFILE('article1_7658971', 'LD1');
        check(isequaln(cfg.model, model));
        check(isequaln(cfg.model_params, params));
        check(strcmp(cfg.transport.fluid_options.amb, 'flame'));
        check(strcmp(cfg.transport.mobility_options.mtd, 'sorensen_eq17'));
        check(strcmp(cfg.model.slip_correction, 'per_caller_7658971'));
        check(strcmp(cfg.model.continuum_diameter, 'fixed_075dg'));
        check(strcmp(cfg.model.root_solve, 'start_point_7658971'));
        check(strcmp(cfg.model.projection, 'euler_7658971'));
        check(~cfg.model.proj_cache && cfg.model.proj_points == 100 && ...
            cfg.model.proj_orientations == 5 && cfg.model.proj_replicates == 1);
        check(isinf(cfg.model.proj_tol) && ~cfg.model.knudsen_diagnostics);
        check(strcmp(cfg.model.initial_velocity, 'mean_speed_7658971'));
        check(cfg.transport.mobility_options.c_dt == 1000);
        check(cfg.projection.n_mc == 100 && cfg.projection.n_ang == 5);
        check(isequal(cfg.transport.fluid_options.gas, params.si.gas));
        check(isequal(cfg.transport.mobility_options.slip_coefficients, ...
            params.si.slip));
        value.model_overrides = struct('step', struct('step_frac', 0.2, ...
            'step_policy', 'cap'), 'mobility', struct('method', 'free_molecular'));
        cfg = load_value(value);
        check(cfg.transport.mobility_options.step_frac == 0.2);
        check(strcmp(cfg.model.mobility, 'free_molecular'));
        value.transport.mobility_options.mtd = 'continuum';
        value.transport.mobility_options.slip = 'kim2005';
        value.transport.mobility_options.step_frac = 0.1;
        cfg = load_value(value);
        check(strcmp(cfg.transport.mobility_options.mtd, 'continuum'));
        check(strcmp(cfg.model.mobility, 'sorensen_eq17'));
        check(cfg.model_params.step.step_frac == 0.1);
        check(cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1000);
        check(strcmp(cfg.model_params.resolved.root_tolerance, 'eps_scaled'));
        check(any(strcmp({cfg.model_source.overrides.source}, file)));
        value.transport.mobility_options.slip = 'per_caller_7658971';
        cfg = load_value(value);
        check(cfg.model_params.resolved.rho_aero_ref_kg_m3 == 1860);
        check(strcmp(cfg.model_params.resolved.root_tolerance, 'default'));
        value.transport.mobility_options.root_solve = 'bracketed';
        cfg = load_value(value);
        check(strcmp(cfg.model_params.resolved.root_tolerance, 'eps_scaled'));
        value = raw;
        value.transport.mobility_options.proj_replicates = 1;
        value.transport.mobility_options.proj_tol = 'none';
        cfg = load_value(value);
        check(isinf(cfg.model.proj_tol));
        value = raw;
        value.model_overrides = struct('step', struct('stepp_frac', 0.1));
        fails(@() load_value(value), 'sootMosaic:MODEL_PROFILE:UnknownKey');
    end

    function selectors()
        first = raw;
        first.results.run_label = 'first';
        second = raw;
        second.results.run_label = 'second';
        one = fullfile(folder, 'one.json');
        two = fullfile(folder, 'two.json');
        write_text(one, jsonencode(first));
        write_text(two, jsonencode(second));
        setenv('SOOTMOSAIC_MAIN_LD1_CONFIG', one);
        setenv('PFAL_MAIN_LD1_CONFIG', two);
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG('', strict);
        check(strcmp(cfg.results.run_label, 'first'));
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG(two, strict);
        check(strcmp(cfg.results.run_label, 'second'));
        setenv('SOOTMOSAIC_MAIN_LD1_CONFIG', '');
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG('', strict);
        check(strcmp(cfg.results.run_label, 'second'));
        setenv('PFAL_MAIN_LD1_CONFIG', '');
        local = fullfile(root, 'config', 'main_ld1', 'main_ld1_config.local.json');
        if isfile(local)
            a = UTILS.LOAD_MAIN_LD1_CONFIG();
            b = UTILS.LOAD_MAIN_LD1_CONFIG(local);
            check(isequaln(a, b));
        else
            fails(@() UTILS.LOAD_MAIN_LD1_CONFIG(), ...
                'sootMosaic:LOAD_MAIN_LD1_CONFIG:MissingConfig');
        end
        fails(@() UTILS.LOAD_MAIN_LD1_CONFIG(fullfile(folder, 'missing.json')), ...
            'sootMosaic:LOAD_MAIN_LD1_CONFIG:MissingConfig');
    end

    function choices()
        selections = {
            'transport.fluid_options.amb', {'sutherland', 'flame', 'room'};
            'transport.mobility_options.mtd', {'sorensen_eq17', ...
                'continuum', 'sorensen_backbone', 'interp', 'free_molecular'};
            'transport.mobility_options.continuum_diameter', ...
                {'sorensen_backbone', 'fixed_075dg'};
            'transport.mobility_options.root_solve', ...
                {'bracketed', 'start_point_7658971'};
            'transport.mobility_options.slip', {'kim2005', 'per_caller_7658971'};
            'transport.mobility_options.step_policy', {'warn', 'cap'};
            'transport.velocity_options.sampler', ...
                {'maxwell_boltzmann', 'mean_speed_7658971'};
            'transport.location_options.vf', {'on', 'On', 'ON', 'off', 'other'};
            'transport.location_options.vf_type', {'pp', 'aggregate', 'other'};
            'projection.options.tbar', {'on', 'On', 'ON', 'off', 'other'}};
        for n = 1:size(selections, 1)
            values = selections{n, 2};
            for j = 1:numel(values)
                cfg = load_value(put(raw, selections{n, 1}, values{j}));
                check(strcmp(get(cfg, selections{n, 1}), values{j}));
            end
        end
        for flag = [false true]
            value = raw;
            value.transport.diagnostics_options.knudsen = flag;
            value.transport.mobility_options.proj_cache = flag;
            cfg = load_value(value);
            check(cfg.model.knudsen_diagnostics == flag);
            check(cfg.model.proj_cache == flag);
        end
        value = raw;
        value.transport.mobility_options.projection = 'euler_7658971';
        value.transport.mobility_options.proj_cache = false;
        cfg = load_value(value);
        check(strcmp(cfg.model.projection, 'euler_7658971'));
        value = raw;
        value.model_overrides = struct('gas', struct('sutherland', ...
            struct('mu_ref_pa_s', 2e-5)));
        cfg = load_value(value);
        check(cfg.transport.fluid_options.gas.sutherland.mu_ref_pa_s == 2e-5);
        params = UTILS.LD1_PARAMS_FROM_CONFIG(cfg.transport.domain, ...
            cfg.transport.particles, cfg.transport.fluid);
        check(params.Value(11) == cfg.transport.fluid.temperature);
    end

    function overlays()
        parent = fullfile(folder, 'parent.json');
        write_text(parent, jsonencode(raw));
        nested = fullfile(folder, 'nested');
        mkdir(nested);
        overlay = fullfile(nested, 'overlay.json');
        value = struct('extends', '../parent.json', 'simulation', ...
            struct('n_trial', 1), 'transport', struct('mobility_options', ...
            struct('step_policy', 'cap')));
        write_text(overlay, jsonencode(value));
        cfg = UTILS.LOAD_MAIN_LD1_CONFIG(overlay, strict);
        check(cfg.simulation.n_trial == 1 && cfg.simulation.j_max == 30000);
        check(strcmp(cfg.transport.mobility_options.step_policy, 'cap'));
        check(~isfield(cfg, 'extends') && numel(cfg.provenance.files) == 2);
        expected = fullfile(nested, raw.results.root);
        if usejava('jvm')
            expected = char(java.io.File(expected).getCanonicalPath());
        end
        check(strcmp(cfg.results.root, expected));
        check(any(strcmp({cfg.provenance.overrides.path}, 'simulation.n_trial')));
        if usejava('jvm')
            check(strcmp(cfg.provenance.files(1).sha256, ...
                UTILS.FILE_SHA256(parent)));
        else
            check(isempty(cfg.provenance.files(1).sha256));
        end
        write_text(overlay, '{"extends":"overlay.json"}');
        fails(@() UTILS.LOAD_MAIN_LD1_CONFIG(overlay, strict), ...
            'sootMosaic:CONFIG_READ:ExtendsCycle');
    end

    function unknowns()
        for p = {'extra', 'simulation.extra', 'transport.mobility_options.extra'}
            value = put(raw, p{1}, [struct('tag', 1); struct('tag', 2)]);
            decoded = jsondecode(jsonencode(value));
            lastwarn('', '');
            cfg = load_value(value, struct('Strict', false));
            [~, id] = lastwarn;
            check(strcmp(id, 'sootMosaic:CONFIG_READ:UnknownKey'));
            check(isequaln(get(cfg, p{1}), get(decoded, p{1})));
            fails(@() load_value(value), 'sootMosaic:CONFIG_READ:UnknownKey');
        end
        value = raw;
        value.comment = 'note';
        value.transport.growth_options.comment = 'note';
        cfg = load_value(value);
        check(~isfield(cfg, 'comment'));
        check(~isfield(cfg.transport.growth_options, 'comment'));
    end

    function invalid_inputs()
        required = required_paths();
        for n = 1:numel(required)
            fails(@() load_value(drop(raw, required{n})), ...
                'sootMosaic:CONFIG_READ:MissingKey');
        end
        for p = {'simulation.n_trial', 'transport.particles.n_par', ...
                'projection.n_mc'}
            fails(@() load_value(put(raw, p{1}, 1.5)), ...
                'sootMosaic:CONFIG_READ:InvalidInteger');
        end
        fails(@() load_value(put(raw, 'simulation.n_temporal', 1)), ...
            'sootMosaic:CONFIG_READ:OutOfRange');
        fails(@() load_value(put(raw, 'simulation.npp_max', 1)), ...
            'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidNppRange');
        fails(@() load_value(put(raw, 'transport.fluid.temperature', 0)), ...
            'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidPositiveScalar');
        fails(@() load_value(put(raw, 'transport.particles.n_pp_std', -1)), ...
            'sootMosaic:LOAD_MAIN_LD1_CONFIG:InvalidNonnegativeScalar');
        fails(@() load_value(put(raw, 'transport.domain.size', [1 2])), ...
            'sootMosaic:CONFIG_READ:InvalidLength');
        fails(@() load_value(put(raw, 'transport.domain.size', [1 NaN 3])), ...
            'sootMosaic:CONFIG_READ:Nonfinite');
        for bad = {-1, 4294967296, 1.5, [1 2]}
            fails(@() load_value(put(raw, 'simulation.rng_seed', bad{1})), '');
        end
        for bad = {2, 1.5}
            fails(@() load_value(put(raw, 'config_version', bad{1})), '');
        end
        fails(@() load_text(strrep(jsonencode(raw), '"model_profile"', ...
            '"bad-key"')), 'sootMosaic:CONFIG_READ:InvalidName');
        fails(@() load_text('{'), 'sootMosaic:CONFIG_READ:InvalidJSON');
        failures = {'projection', 'euler_7658971', 'InvalidProjection'; ...
            'proj_orientations', 30, 'InvalidProjection'; ...
            'proj_replicates', 1, 'InvalidProjection'; ...
            'proj_cache', 'yes', 'InvalidLogical'; ...
            'proj_points', 2.5, 'InvalidInteger'; ...
            'proj_tol', -1, 'InvalidPositiveScalar'; ...
            'mtd', 'mixed', 'InvalidChoice'};
        for n = 1:size(failures, 1)
            value = put(raw, ['transport.mobility_options.' failures{n, 1}], ...
                failures{n, 2});
            fails(@() load_value(value), ...
                ['sootMosaic:LOAD_MAIN_LD1_CONFIG:' failures{n, 3}]);
        end
    end

    function reader_isolation()
        write_text(file, '{"options":7}');
        r = struct('path', 'options', 'type', 'any', 'native_json', true);
        child = struct('path', 'options.flag', 'type', 'any');
        fails(@() UTILS.CONFIG_READ(file, {r, child}), ...
            'sootMosaic:CONFIG_READ:InvalidObject');
        r.struct_fallback = true;
        cfg = UTILS.CONFIG_READ(file, {r, child});
        check(isstruct(cfg.options) && isempty(fieldnames(cfg.options)));
        write_text(file, '{"options":[{"flag":1},{"flag":2}]}');
        cfg = UTILS.CONFIG_READ(file, {r, child});
        check(isequal(cfg.options, [struct('flag', 1); struct('flag', 2)]));
        r = rmfield(r, 'struct_fallback');
        fails(@() UTILS.CONFIG_READ(file, {r, child}), ...
            'sootMosaic:CONFIG_READ:InvalidObject');
        write_text(file, '{"value":[1]}');
        fails(@() UTILS.CONFIG_READ(file, struct('path', 'value', ...
            'type', 'number')), 'sootMosaic:CONFIG_READ:InvalidType');
    end

    function smoke_config()
        value = raw;
        value.transport.particles.n_par = 500;
        value.simulation.j_max = 50;
        value.simulation.n_trial = 1;
        value.simulation.rng_seed = 43;
        value.results.root = 's1_output';
        cfg = load_value(value);
        check(cfg.transport.particles.n_par == 500 && ...
            cfg.transport.particles.n_pp_mean == 1 && ...
            cfg.transport.particles.n_pp_std == 0);
        check(cfg.simulation.j_max == 50 && cfg.simulation.n_trial == 1 && ...
            cfg.simulation.rng_seed == 43);
        [params, constants] = UTILS.LD1_PARAMS_FROM_CONFIG( ...
            cfg.transport.domain, cfg.transport.particles, cfg.transport.fluid, ...
            cfg.model_params.si.constants);
        check(params.Value(5) == 500 && params.Value(6) == 1 && ...
            params.Value(7) == 0 && ~isempty(constants));
    end
end

function contract = numeric_contract()
% Declaring types, units and conversions independently of the dictionary
contract = {
    'simulation.n_temporal', 'integer', 'count', '', 'integer';
    'simulation.n_trial', 'integer', 'count', '', 'integer';
    'simulation.npp_min', 'integer', 'primaries', '', 'integer';
    'simulation.npp_max', 'integer', 'primaries', '', 'integer';
    'simulation.j_max', 'integer', 'steps', '', 'integer';
    'projection.n_mc', 'integer', 'points', '', 'integer';
    'projection.n_ang', 'integer', 'angles', '', 'integer';
    'transport.particles.n_par', 'integer', 'count', '', 'integer';
    'simulation.primary_size_gsd_between_trials', 'number', 'none', '', 'number';
    'transport.domain.volume_fraction', 'number', 'none', '', 'number';
    'transport.particles.n_pp_mean', 'number', 'primaries', '', 'number';
    'transport.particles.n_pp_std', 'number', 'primaries', '', 'number';
    'transport.particles.d_pp_gm', 'number', 'm', '', 'number';
    'transport.particles.d_pp_gsd_between_aggregates', ...
        'number', 'none', '', 'number';
    'transport.particles.d_pp_gsd_within_aggregates', ...
        'number', 'none', '', 'number';
    'transport.fluid.temperature', 'number', 'K', '', 'number';
    'transport.fluid.pressure', 'number', 'Pa', '', 'number';
    'transport.mobility_options.c_dt', 'number', 'none', '', 'number';
    'transport.domain.size', '3 numbers', 'm', 'double', 'vector';
    'transport.fluid.velocity', '3 numbers', 'm/s', 'double', 'vector';
    'simulation.rng_seed', 'integer or empty', 'none', 'double', 'seed';
    'transport.mobility_options.proj_points', 'any', 'points', '', 'integer';
    'transport.mobility_options.proj_orientations', 'any', 'angles', '', ...
        'orientations';
    'transport.mobility_options.proj_replicates', 'any', 'count', '', 'integer';
    'transport.mobility_options.proj_tol', 'any', 'relative standard error', ...
        '', 'number';
    'transport.mobility_options.step_frac', 'any', ...
        'smallest primary diameters', '', 'number'};
end

function paths = required_paths()
paths = {'results', 'simulation', 'projection', 'transport', ...
    'transport.domain', 'transport.particles', 'transport.fluid', ...
    'transport.fluid_options', 'transport.mobility_options', ...
    'transport.location_options', 'results.root', 'results.library_file', ...
    'results.run_label', 'simulation.n_temporal', 'simulation.n_trial', ...
    'simulation.primary_size_gsd_between_trials', 'simulation.npp_min', ...
    'simulation.npp_max', 'simulation.j_max', 'projection.n_mc', ...
    'projection.n_ang', 'transport.domain.volume_fraction', ...
    'transport.domain.size', 'transport.particles.n_par', ...
    'transport.particles.n_pp_mean', 'transport.particles.n_pp_std', ...
    'transport.particles.d_pp_gm', ...
    'transport.particles.d_pp_gsd_between_aggregates', ...
    'transport.particles.d_pp_gsd_within_aggregates', ...
    'transport.fluid.temperature', 'transport.fluid.velocity', ...
    'transport.fluid.pressure', 'transport.mobility_options.c_dt', ...
    'transport.location_options.vf'};
end

function paths = profile_paths()
paths = {'transport.fluid_options.amb', 'transport.mobility_options.mtd', ...
    'transport.mobility_options.slip', ...
    'transport.mobility_options.continuum_diameter', ...
    'transport.mobility_options.root_solve', ...
    'transport.mobility_options.projection', 'transport.mobility_options.proj_cache', ...
    'transport.mobility_options.proj_points', ...
    'transport.mobility_options.proj_orientations', ...
    'transport.mobility_options.proj_replicates', ...
    'transport.mobility_options.proj_tol', 'transport.mobility_options.step_frac', ...
    'transport.mobility_options.step_policy', ...
    'transport.diagnostics_options.knudsen', 'transport.velocity_options.sampler'};
end

function cfg = without_provenance(cfg)
cfg = rmfield(cfg, 'provenance');
end

function check(ok)
if ~ok, error('sootMosaic:QA:Ld1ConfigFailed', 'Assertion failed.'); end
end

function fails(action, expected)
caught = false;
try
    action();
catch err
    caught = isempty(expected) || strcmp(err.identifier, expected);
    if ~caught
        error('sootMosaic:QA:Ld1ConfigFailed', ...
            'Expected %s; received %s.', expected, err.identifier);
    end
end
check(caught);
end

function value = put(value, path, item)
parts = strsplit(path, '.');
key = parts{1};
if isscalar(parts)
    value.(key) = item;
else
    if ~isfield(value, key), value.(key) = struct(); end
    value.(key) = put(value.(key), strjoin(parts(2:end), '.'), item);
end
end

function value = get(value, path)
parts = strsplit(path, '.');
for k = 1:numel(parts), value = value.(parts{k}); end
end

function yes = has(value, path)
parts = strsplit(path, '.');
yes = isstruct(value) && isscalar(value) && isfield(value, parts{1});
if yes && numel(parts) > 1
    yes = has(value.(parts{1}), strjoin(parts(2:end), '.'));
end
end

function value = drop(value, path)
parts = strsplit(path, '.');
if isscalar(parts)
    if isfield(value, parts{1}), value = rmfield(value, parts{1}); end
else
    value.(parts{1}) = drop(value.(parts{1}), strjoin(parts(2:end), '.'));
end
end

function paths = key_paths(value, prefix)
paths = cell(0, 1);
if ~isstruct(value) || ~isscalar(value), return; end
names = fieldnames(value);
groups = cell(numel(names), 1);
for k = 1:numel(names)
    if isempty(prefix)
        child_path = names{k};
    else
        child_path = [prefix '.' names{k}];
    end
    groups{k} = [{child_path}; key_paths(value.(names{k}), child_path)];
end
if ~isempty(groups), paths = vertcat(groups{:}); end
end

function write_text(file, text)
fid = fopen(file, 'w');
if fid < 0, error('sootMosaic:QA:Ld1ConfigFailed', 'Cannot write fixture.'); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, text, 'char');
end

function restore_state(state, message, id, primary, fallback)
warning(state);
lastwarn(message, id);
setenv('SOOTMOSAIC_MAIN_LD1_CONFIG', primary);
setenv('PFAL_MAIN_LD1_CONFIG', fallback);
end

function restore_location(folder, saved_path)
cd(folder);
path(saved_path);
end
