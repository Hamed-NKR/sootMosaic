function report = test_ld2_saved_dm(repoRoot)
% "TEST_LD2_SAVED_DM" checks that the saved mobility diameter of LD2 equals...
%   ...the mobility diameter of the population at save time.
% ----------------------------------------------------------------------- %
%
%   report = QA.TEST_LD2_SAVED_DM(repoRoot)
%
%   Input
%   - repoRoot, PFAL root folder (default, the folder above +QA)
%
%   Output
%   - report, struct array with fields name and pass, one entry per case
%
%   Cases 1 to 7 run UTILS.CHECK_SAVED_DM on synthetic populations. Cases...
%   ...8 and 9 read the two LD2 save sites and test that each one stores...
%   ...pars_LD2.dm, calls the check on that field after the store, and...
%   ...never stores pars_LD2.da in dm. Any failed case stops with the...
%   ...identifier PFAL:QA:LD2SavedDmFailed.
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

% synthetic population with mobility and projected-area diameters
pars = struct('da', [40; 80; 160] * 1e-9, 'dm', [55; 105; 190] * 1e-9);
saved = struct('da', [], 'dm', []);

names = cell(9, 1);
pass = false(9, 1);

names{1} = 'saved dm taken from pars.dm passes';
saved.dm = pars.dm;
pass(1) = does_pass(saved.dm, pars.dm);

names{2} = 'saved dm taken from pars.da is rejected';
saved.dm = pars.da;
pass(2) = does_fail(saved.dm, pars.dm);

names{3} = 'size mismatch is rejected';
saved.dm = pars.dm(1:2);
pass(3) = does_fail(saved.dm, pars.dm);

names{4} = 'undefined entries that agree pass';
saved.dm = [pars.dm(1:2); NaN];
pass(4) = does_pass(saved.dm, [pars.dm(1:2); NaN]);

names{5} = 'undefined entry against a value is rejected';
saved.dm = [pars.dm(1:2); NaN];
pass(5) = does_fail(saved.dm, pars.dm);

names{6} = 'row against column is rejected';
saved.dm = pars.dm.';
pass(6) = does_fail(saved.dm, pars.dm);

names{7} = 'empty against empty passes';
saved.dm = zeros(0, 1);
pass(7) = does_pass(saved.dm, zeros(0, 1));

sites = {'main_LD2_v3.m', fullfile('+UTILS', 'RESUME_LD2_V3.m')};
for i = 1 : 2
    names{7 + i} = ['save site stores pars_LD2.dm, ', sites{i}];
    txt = fileread(fullfile(repoRoot, sites{i}));
    store = regexp(txt, ...
        'parsdata\(ind_dat\)\.dm\s*=\s*pars_LD2\.dm\s*;', 'start');
    wrong = regexp(txt, ...
        'parsdata\(ind_dat\)\.dm\s*=\s*pars_LD2\.da\s*;', 'start');
    check = regexp(txt, ['UTILS\.CHECK_SAVED_DM\(\s*parsdata\(ind_dat\)', ...
        '\.dm\s*,\s*pars_LD2\.dm\s*\)\s*;'], 'start');
    pass(7 + i) = isscalar(store) && isempty(wrong) && ...
        isscalar(check) && check > store;
end

report = struct('name', names, 'pass', num2cell(pass));
for i = 1 : numel(pass)
    if pass(i)
        fprintf('PASS %s\n', names{i});
    else
        fprintf('FAIL %s\n', names{i});
    end
end
if ~all(pass)
    error('PFAL:QA:LD2SavedDmFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass))
end

end

function ok = does_pass(dm_saved, dm_now)
ok = true;
try
    UTILS.CHECK_SAVED_DM(dm_saved, dm_now);
catch
    ok = false;
end
end

function ok = does_fail(dm_saved, dm_now)
ok = false;
try
    UTILS.CHECK_SAVED_DM(dm_saved, dm_now);
catch err
    ok = strcmp(err.identifier, 'PFAL:LD2:SavedDmMismatch');
end
end
