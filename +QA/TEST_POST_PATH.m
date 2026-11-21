function report = TEST_POST_PATH()
% "TEST_POST_PATH" checks the input paths of the post-processing scripts.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:PostPathFailed
% ----------------------------------------------------------------------- %

root = fileparts(fileparts(mfilename('fullpath')));
ld2_file = fullfile(root, 'config', 'main_ld2', ...
    'main_ld2_from_main_scatter_config.example.json');
scatter_file = fullfile(root, 'config', 'main_scatter', ...
    'main_scatter_config.example.json');
names = {'LD2 relative path', 'scatter relative path', ...
    'absolute path kept', 'missing key', 'empty value', ...
    'path keys in the examples'};
tests = {@ld2_relative, @scatter_relative, @absolute_kept, ...
    @missing_key, @empty_value, @example_keys};
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
    error('sootMosaic:QA:PostPathFailed', '%d cases failed.', sum(~pass));
end

    function ld2_relative
        cfg = UTILS.LOAD_MAIN_LD2_CONFIG(ld2_file, struct('Strict', true));
        value = UTILS.POST_PATH(cfg, 'ld2.results_file');
        check(strcmp(value, fullfile(fileparts(ld2_file), ...
            cfg.post.ld2.results_file)), 'Relative path not resolved.');
    end

    function scatter_relative
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(scatter_file, ...
            struct('Strict', true));
        value = UTILS.POST_PATH(cfg, 'charsize.aggregate_file');
        check(strcmp(value, fullfile(fileparts(scatter_file), ...
            cfg.post.charsize.aggregate_file)), ...
            'Relative path not resolved.');
    end

    function absolute_kept
        cfg = struct('config_file', ld2_file);
        full = fullfile(tempdir, 'library.mat');
        cfg.post.ld2.results_file = full;
        check(strcmp(UTILS.POST_PATH(cfg, 'ld2.results_file'), full), ...
            'Absolute path changed.');
    end

    function missing_key
        cfg = struct('config_file', ld2_file);
        expect_error(@() UTILS.POST_PATH(cfg, 'ld2.results_file'));
        cfg.post.ld2 = struct();
        expect_error(@() UTILS.POST_PATH(cfg, 'ld2.results_file'));
    end

    function empty_value
        cfg = struct('config_file', ld2_file);
        cfg.post.ld2.results_file = '';
        expect_error(@() UTILS.POST_PATH(cfg, 'ld2.results_file'));
        cfg.post.ld2.results_file = 3;
        expect_error(@() UTILS.POST_PATH(cfg, 'ld2.results_file'));
    end

    function example_keys
        keys = {'ld2.results_file', 'shield.results_file', ...
            'shield.input_file', 'collapse.results_file', ...
            'collapse.fluid_file', 'valid.aggregate_file', ...
            'valid.aggregate_dalpha_file', ...
            'valid.aggregate_kalpha_file', 'valid.experiment_file'};
        for branch = {'scatter', 'scale'}
            file = fullfile(root, 'config', 'main_ld2', ['main_ld2_from_' ...
                'main_' branch{1} '_config.example.json']);
            cfg = UTILS.LOAD_MAIN_LD2_CONFIG(file, struct('Strict', true));
            for j = 1:numel(keys)
                check(~isempty(UTILS.POST_PATH(cfg, keys{j})), keys{j});
            end
        end
        cfg = UTILS.LOAD_MAIN_SCATTER_CONFIG(scatter_file, ...
            struct('Strict', true));
        check(~isempty(UTILS.POST_PATH(cfg, 'collapse.aggregate_file')), ...
            'collapse.aggregate_file');
    end

    function expect_error(fcn)
        try
            fcn();
        catch err
            check(strcmp(err.identifier, ...
                'sootMosaic:POST_PATH:MissingKey'), ...
                ['Unexpected identifier ' err.identifier]);
            return
        end
        error('sootMosaic:QA:PostPathFailed', 'An error was expected.');
    end

    function check(condition, message)
        if ~condition
            error('sootMosaic:QA:PostPathFailed', '%s', message);
        end
    end
end
