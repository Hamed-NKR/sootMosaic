function report = TEST_WARNING_STATE()
% "TEST_WARNING_STATE" checks that diagnostics retain caller settings.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:WarningStateFailed
% ----------------------------------------------------------------------- %

root = fileparts(fileparts(mfilename('fullpath')));
files = {'main_scale_v2.m', 'main_scatter_v8.m', ...
    'main_tem_analysis_v1.m'};
names = {'scale source', 'scatter source', 'TEM source', ...
    'sequential warning enabled', 'sequential warning disabled'};
tests = {@() inspect_source(files{1}), @() inspect_source(files{2}), ...
    @() inspect_source(files{3}), @() sequential_warning('on'), ...
    @() sequential_warning('off')};
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
    error('sootMosaic:QA:WarningStateFailed', ...
        '%d cases failed.', sum(~pass));
end

    function inspect_source(file)
        source = fileread(fullfile(root, file));
        % Reject literal state setters, including identifier-specific ones.
        % These scripts only emit diagnostics and need no scoped suppression.
        source = regexprep(source, '\.\.\.[^\r\n]*[\r\n]+', ' ');
        pattern = '\<warning\s*\(\s*[''"](?:off|on)[''"]\s*[,)]';
        command = '(?m)^\s*warning\s+(?:off|on)\b';
        check(isempty(regexpi(source, pattern, 'once')) && ...
            isempty(regexpi(source, command, 'once')), ...
            ['Warning state setter in ' file]);
    end

    function sequential_warning(setting)
        source = fileread(fullfile(root, files{2}));
        pattern = ['(?m)^if strcmp\(opt_scale, ''sequential''\)' ...
            '[\s\S]*?^end\s*$'];
        block = regexp(source, pattern, 'match');
        check(isscalar(block), 'Expected one sequential warning block.');

        state = warning();
        [message, identifier] = lastwarn;
        restore = onCleanup(@() restore_warnings(state, message, identifier));
        id = 'sootMosaic:main_scatter_v8:SequentialScaleMode';
        warning(setting, id);
        before = warning();
        % Execute the source block without loading the aggregate library.
        opt_scale = 'sequential'; %#ok<NASGU>
        eval(block{1});
        after = warning();
        check(isequal(before, after), 'The warning settings changed.');
    end
end

function check(value, message)
if ~value
    error('sootMosaic:QA:WarningStateFailed', '%s', message);
end
end

function restore_warnings(state, message, identifier)
warning(state);
lastwarn(message, identifier);
end
