function report = TEST_PUBLIC_COPY()
% "TEST_PUBLIC_COPY" checks the reduced copies of saved products.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. A failed case raises...
%         ...sootMosaic:QA:PublicCopyFailed
% ----------------------------------------------------------------------- %
%
% A synthetic product holds absolute and relative paths in nested...
%     ...structures, structure arrays, cells, strings and tables, next to...
%     ...digests, URLs, numbers and ordinary text. Saved files go to a...
%     ...temporary folder removed on exit.

names = {'paths reduced, other values kept', 'input unchanged', ...
    'whole workspace round trip', 'named variables round trip', ...
    'caller variables unchanged'};
tests = {@reduced_copy, @input_unchanged, @workspace_round_trip, ...
    @named_round_trip, @caller_unchanged};
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
    error('sootMosaic:QA:PublicCopyFailed', '%d cases failed.', sum(~pass));
end
end

function [product, expected] = fixture()
% Synthetic product and its expected public copy
h1 = repmat('a', 1, 64);
h2 = repmat('b', 1, 64);
product = struct();
product.config_file = 'C:\work\project\config\task.local.json';
product.dataset = struct('id', 'library', ...
    'file', '../../data/main_ld2/library.mat', ...
    'config_dir', 'D:\work\project\config\main_ld2', ...
    'url', 'https://zenodo.org/records/1/files/library.mat', ...
    'doi', '10.5281/zenodo.1', 'sha256', h1, 'cache_file', '');
product.results = struct('root', '/home/work/results/', ...
    'run_label', 'LD2__run');
product.unit = 'm/s';
product.note = 'Sheath flow range 2 to 30 L/min';
product.label = 'D:\work\label.txt';
product.provenance.files = struct('file', ...
    {'C:\work\one.json', '\\server\share\two.json'}, 'sha256', {h1, h2});
product.provenance.overrides = struct( ...
    'path', {'dataset.file', 'simulation.k_max', 'unit'}, ...
    'old_value', {'../a/old.mat', 10, 'm/s'}, ...
    'new_value', {'../b/new.mat', 20, 'km/h'}, ...
    'source', {'C:\work\task.json', '<inline>', 'rel/task.json'});
product.list_files = {'C:\work\one.mat'; 'rel/two.mat'};
product.OutputDir = 'results/overlap_audit';
product.dir_wsp = 'results\LD2__run__2026-01-01\';
product.matrix = magic(3);
product.texts = ["C:\work\b.txt", "plain/text"; "x", "y"];
product.table = table({'C:\work\p1.csv'; 'C:\work\p2.csv'}, [1; 2], ...
    {'x/y'; 'u/v'}, 'VariableNames', {'csv_file', 'n', 'label'});
product.file_url = 'file:///C:/work/c.mat';
product.root_drive = struct('root', 'C:\');
product.empty = struct('file', {});

expected = product;
expected.config_file = 'task.local.json';
expected.dataset.file = 'library.mat';
expected.dataset.config_dir = 'main_ld2';
expected.results.root = 'results';
expected.label = 'label.txt';
[expected.provenance.files.file] = deal('one.json', 'two.json');
[expected.provenance.overrides.old_value] = deal('old.mat', 10, 'm/s');
[expected.provenance.overrides.new_value] = deal('new.mat', 20, 'km/h');
[expected.provenance.overrides.source] = deal('task.json', '<inline>', ...
    'task.json');
expected.list_files = {'one.mat'; 'two.mat'};
expected.OutputDir = 'overlap_audit';
expected.dir_wsp = 'LD2__run__2026-01-01';
expected.texts = ["b.txt", "plain/text"; "x", "y"];
expected.table.csv_file = {'p1.csv'; 'p2.csv'};
expected.file_url = 'c.mat';
expected.root_drive.root = '';
end

function reduced_copy()
[product, expected] = fixture();
public = UTILS.PUBLIC_COPY(product);
check(isequal(public, expected), 'The public copy differs.');
check(isequal(size(public.provenance.files), [1, 2]) && ...
    isequal(size(public.list_files), [2, 1]) && ...
    isequal(size(public.texts), [2, 2]) && ...
    isequal(size(public.empty), [0, 0]), 'A shape changed.');
check(isempty(absolute_leaves(public)), 'An absolute path survived.');
end

function input_unchanged()
[product, ~] = fixture();
before = product;
UTILS.PUBLIC_COPY(product);
check(isequal(product, before), 'The input changed.');
end

function workspace_round_trip()
[product, expected] = fixture();
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
file = fullfile(folder, 'workspace.mat');
save_workspace(file, product);
saved = load(file);
check(isequal(sort(fieldnames(saved)), {'count'; 'file'; 'product'}), ...
    'The saved variable names differ.');
check(isequal(saved.product, expected) && saved.count == 3 && ...
    strcmp(saved.file, 'workspace.mat'), 'A saved value differs.');
check(isempty(absolute_leaves(saved)), 'An absolute path was saved.');
clear cleanup
end

function named_round_trip()
[product, expected] = fixture(); %#ok<ASGLU> product is saved by name
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
file = fullfile(folder, 'named.mat');
count = 3; %#ok<NASGU>
UTILS.SAVE_PUBLIC_MAT(file, {'-v7.3'}, 'product', 'count');
saved = load(file);
check(isequal(sort(fieldnames(saved)), {'count'; 'product'}), ...
    'The saved variable names differ.');
check(isequal(saved.product, expected) && saved.count == 3, ...
    'A saved value differs.');
check(isempty(absolute_leaves(saved)), 'An absolute path was saved.');
clear cleanup
end

function caller_unchanged()
[product, ~] = fixture();
before = product;
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
UTILS.SAVE_PUBLIC_MAT(fullfile(folder, 'kept.mat'), {}, 'product');
check(isequal(product, before), 'The caller variable changed.');
clear cleanup
end

function save_workspace(file, product) %#ok<INUSD>
% Saving the whole workspace of this function
count = 3; %#ok<NASGU>
UTILS.SAVE_PUBLIC_MAT(file, {});
end

function found = absolute_leaves(value)
% Text leaves holding a drive letter path or starting with a slash
found = {};
if isstruct(value)
    names = fieldnames(value);
    for j = 1:numel(value)
        for k = 1:numel(names)
            found = [found, absolute_leaves(value(j).(names{k}))]; %#ok<AGROW>
        end
    end
elseif iscell(value)
    for j = 1:numel(value)
        found = [found, absolute_leaves(value{j})]; %#ok<AGROW>
    end
elseif istable(value)
    found = absolute_leaves(table2struct(value));
elseif isstring(value)
    found = absolute_leaves(cellstr(value(~ismissing(value))));
elseif ischar(value) && ~isempty(regexp(value(:).', ...
        '((^|[^A-Za-z])[A-Za-z]:[\\/]|^[\\/])', 'once'))
    found = {value(:).'};
end
end

function check(value, message)
if ~value
    error('sootMosaic:QA:PublicCopyFailed', '%s', message);
end
end
