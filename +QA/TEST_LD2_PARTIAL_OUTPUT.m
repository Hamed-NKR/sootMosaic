function report = TEST_LD2_PARTIAL_OUTPUT()
% "TEST_LD2_PARTIAL_OUTPUT" checks snapshot and fraction finalization.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:LD2PartialOutputFailed
% ----------------------------------------------------------------------- %

names = {'partial run', 'resumed run', 'complete run', ...
    'column fractions', 'no stored thresholds', 'retained fraction', ...
    'unavailable fraction', 'finalizer calls'};
tests = {@partial_run, @resumed_run, @complete_run, @column_fractions, ...
    @no_thresholds, @() validation_fraction(0.8), ...
    @() validation_fraction(0.4), @finalizer_calls};
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
    error('sootMosaic:QA:LD2PartialOutputFailed', ...
        '%d cases failed.', sum(~pass));
end
end

function [parsdata, fractions] = fixture()
fractions = [1, 0.8, 0.6, 0.4];
parsdata = repmat(struct('dpp', [], 'da', [], 'dg', [], 'pp', []), 4, 1);
for k = 1:4
    parsdata(k).dpp = (10 + k) * 1e-9;
    parsdata(k).da = (20 + k) * 1e-9;
    parsdata(k).dg = (30 + k) * 1e-9;
    parsdata(k).pp = {[k, (10 + k) * 1e-9, 0, 0, 0]};
end
end

function partial_run()
[expected, schedule] = fixture();
cfg_ld2.simulation.r_n_agg = schedule;
pending = expected;
pending(3:4) = repmat(struct('dpp', [], 'da', [], 'dg', [], 'pp', []), 2, 1);
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule, 3);
check(isequal(saved, expected(1:2)) && ...
    isequal(fractions, [1, 0.8]), 'Partial snapshot pairing differs.');
check(isequal(cfg_ld2.simulation.r_n_agg, schedule), ...
    'The requested schedule changed.');
end

function resumed_run()
[expected, schedule] = fixture();
checkpoint.parsdata = expected;
checkpoint.parsdata(3:4) = repmat( ...
    struct('dpp', [], 'da', [], 'dg', [], 'pp', []), 2, 1);
checkpoint.r_n_agg = schedule;
checkpoint.ind_dat = 3;
resumed = checkpoint;
resumed.parsdata(resumed.ind_dat) = expected(3);
resumed.ind_dat = resumed.ind_dat + 1;
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(resumed.parsdata, ...
    resumed.r_n_agg, resumed.ind_dat);
check(isequal(saved, expected(1:3)) && ...
    isequal(fractions, [1, 0.8, 0.6]), 'Resumed snapshot pairing differs.');
check(isequal(checkpoint.r_n_agg, schedule) && ...
    isequal(resumed.r_n_agg, schedule), 'The checkpoint schedule changed.');
end

function complete_run()
[pending, schedule] = fixture();
expected = pending;
expected(5:end) = [];
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule, 5);
check(isequal(saved, expected) && isequal(fractions, schedule), ...
    'Complete output differs.');
end

function column_fractions()
[pending, schedule] = fixture();
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule.', 3);
check(isequal(saved, pending(1:2)) && ...
    isequal(fractions, [1; 0.8]), 'Column output differs.');
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule.', 5);
check(isequal(saved, pending) && isequal(fractions, schedule.'), ...
    'Complete column output differs.');
end

function no_thresholds()
[pending, schedule] = fixture();
expected = pending;
expected(1:end) = [];
[saved, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule, 1);
check(isequal(saved, expected) && isempty(fractions), ...
    'An unstored threshold was retained.');
end

function validation_fraction(requested)
[pending, schedule] = fixture();
[parsdata, fractions] = UTILS.TRIM_LD2_OUTPUT(pending, schedule, 3);
ld2_data = struct('parsdata', parsdata, 'r_n_agg', fractions); %#ok<NASGU>
source = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+UTILS', 'RUN_MAIN_VALIDATION.m'));
% Execute the validation length guard and population selector directly...
    % ...from their source, without loading measurements or drawing figures
guard = regexp(source, ['(?m)^if ~isstruct\(ld2_data\.parsdata\)' ...
    '[\s\S]*?^end'], 'match');
selector = regexp(source, ...
    ['(?m)^function population = select_simulation_population[^\r\n]*' ...
    '\r?\n([\s\S]*?)^end\s*\r?\n\s*function simulation ='], 'tokens');
check(isscalar(guard) && isscalar(selector), ...
    'Expected one validation guard and selector.');
eval(guard{1});
population = [];
try
    eval(selector{1}{1});
catch err
    check(requested == 0.4 && strcmp(err.identifier, ...
        'sootMosaic:RUN_MAIN_VALIDATION:InvalidLD2FractionMapping'), ...
        'Unexpected validation rejection.');
    return
end
check(requested == 0.8 && isequal(population, pending(2)), ...
    'Validation selected an unavailable or different population.');
end

function finalizer_calls()
root = fileparts(fileparts(mfilename('fullpath')));
files = {'main_LD2_v3.m', fullfile('+UTILS', 'RESUME_LD2_V3.m')};
for k = 1:numel(files)
    source = fileread(fullfile(root, files{k}));
    call = strfind(source, ['[parsdata, r_n_agg] = ' ...
        'UTILS.TRIM_LD2_OUTPUT(parsdata, r_n_agg, ind_dat);']);
    checkpoint = strfind(source, 'cfg_results.checkpoint_prefix');
    final = strfind(source, 'cfg_results.final_prefix');
    check(isscalar(call) && isscalar(checkpoint) && isscalar(final) && ...
        checkpoint < call && call < final, ...
        'Expected finalization after checkpoints and before final save.');
end
end

function check(value, message)
if ~value
    error('sootMosaic:QA:LD2PartialOutputFailed', '%s', message);
end
end
