function report = TEST_GEOSTD()
% "TEST_GEOSTD" checks the geometric standard deviation against its...
%     ...definition, exp(std(log(x), flag, dim)).
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:GeostdFailed
% ----------------------------------------------------------------------- %

names = {'vector default', 'vector flag 0', 'matrix dim 1', ...
    'matrix dim 2', 'array dim 3', 'known value', 'zero input', ...
    'empty options, empty and NaN data', 'negative input', 'no input', ...
    'single class', 'warning state kept'};
tests = {@vector_default, @vector_flag0, @matrix_dim1, @matrix_dim2, ...
    @array_dim3, @known_value, @zero_input, @empty_options, ...
    @negative_input, @no_input, @single_class, @warning_state};
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
    error('sootMosaic:QA:GeostdFailed', '%d cases failed.', sum(~pass));
end

    function vector_default
        x = [1.2, 3.4, 2.2, 8.1, 5.5];
        close_to(UTILS.GEOSTD(x), exp(std(log(x), 1, 2)));
        close_to(UTILS.GEOSTD(x.'), exp(std(log(x.'), 1, 1)));
    end

    function vector_flag0
        x = [1.2, 3.4, 2.2, 8.1, 5.5];
        close_to(UTILS.GEOSTD(x, 0), exp(std(log(x), 0, 2)));
        close_to(UTILS.GEOSTD(x, 1), exp(std(log(x), 1, 2)));
    end

    function matrix_dim1
        x = test_matrix();
        close_to(UTILS.GEOSTD(x), exp(std(log(x), 1, 1)));
        close_to(UTILS.GEOSTD(x, 0, 1), exp(std(log(x), 0, 1)));
    end

    function matrix_dim2
        x = test_matrix();
        close_to(UTILS.GEOSTD(x, 1, 2), exp(std(log(x), 1, 2)));
        close_to(UTILS.GEOSTD(x, 0, 2), exp(std(log(x), 0, 2)));
    end

    function array_dim3
        x = reshape(test_matrix(), 4, 3, 5);
        close_to(UTILS.GEOSTD(x, 0, 3), exp(std(log(x), 0, 3)));
    end

    function known_value
        % Three values with a log-mean of zero: log values -s, 0, s.
        s = 0.5;
        x = exp([-s, 0, s]);
        check(abs(UTILS.GEOSTD(x, 1) - exp(s * sqrt(2 / 3))) < 1e-12, ...
            'Population value differs from the definition.');
        check(abs(UTILS.GEOSTD(x, 0) - exp(s)) < 1e-12, ...
            'Sample value differs from the definition.');
    end

    function zero_input
        check(isnan(UTILS.GEOSTD([0, 1, 2])), 'Zero input should give NaN.');
    end

    function empty_options
        x = test_matrix();
        close_to(UTILS.GEOSTD(x, [], []), exp(std(log(x), 1, 1)));
        for data = {[], zeros(0, 3), zeros(3, 0), [1, NaN, 2]}
            x = data{1};
            dim = find(size(x) ~= 1, 1);
            if isempty(dim), dim = 1; end
            for flag = [0, 1]
                check(isequaln(UTILS.GEOSTD(x, flag), ...
                    exp(std(log(x), flag, dim))), ...
                    'NaN or empty output differs from the definition.');
            end
        end
    end

    function negative_input
        try
            UTILS.GEOSTD([1, -2, 3]);
        catch err
            check(strcmp(err.identifier, 'geostd:badData'), ...
                'Unexpected identifier for negative input.');
            return
        end
        error('sootMosaic:QA:GeostdFailed', 'Negative input must error.');
    end

    function no_input
        try
            UTILS.GEOSTD();
        catch err
            check(strcmp(err.identifier, 'geostd:notEnoughInputs'), ...
                'Unexpected identifier for missing input.');
            return
        end
        error('sootMosaic:QA:GeostdFailed', 'Missing input must error.');
    end

    function single_class
        x = single([1.5, 2.5, 4.5]);
        value = UTILS.GEOSTD(x);
        check(isa(value, 'single'), 'Single input should stay single.');
        close_to(value, exp(std(log(x), 1, 2)));
    end

    function warning_state
        before = warning('on', 'MATLAB:log:logOfZero');
        restore = onCleanup(@() warning(before));
        UTILS.GEOSTD([0, 1, 2]);
        after = warning('query', 'MATLAB:log:logOfZero');
        check(strcmp(after.state, 'on'), 'Warning state was not restored.');
    end

    function x = test_matrix()
        x = reshape(0.5 + 9 * mod((1:60) * 0.37, 1), 4, 15);
    end

    function close_to(a, b)
        check(isequaln(size(a), size(b)), 'Output size differs.');
        scale = max(abs(b(:)));
        if isempty(scale), scale = 1; end
        check(isempty(a) || all(abs(a(:) - b(:)) <= 1e-12 * max(scale, 1)), ...
            'Values differ from the definition.');
    end

    function check(condition, message)
        if ~condition
            error('sootMosaic:QA:GeostdFailed', '%s', message);
        end
    end
end
