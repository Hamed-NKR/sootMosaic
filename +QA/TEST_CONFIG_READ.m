function report = TEST_CONFIG_READ()
% "TEST_CONFIG_READ" checks configuration resolution and source rules.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Structure array with name and pass, one entry per case....
%         ...Fixtures are written under tempname and removed on exit....
%         ...A failed case stops with sootMosaic:QA:ConfigReadFailed
% ----------------------------------------------------------------------- %

folder = tempname;
[ok, message] = mkdir(folder);
if ~ok
    error('sootMosaic:QA:ConfigReadFailed', '%s', message);
end
cleanup = onCleanup(@() rmdir(folder, 's'));
state = warning;
[warn_message, warn_id] = lastwarn;
restore = onCleanup(@() restore_warnings(state, warn_message, warn_id));
warning('on', 'sootMosaic:CONFIG_READ:Alias');
warning('on', 'sootMosaic:CONFIG_READ:UnknownKey');
warning('on', 'sootMosaic:CONFIG_DATA_RULE:Mismatch');
tests = {@merge_objects, @merge_ids, @chain_resolution, @chain_limits, ...
    @types, @invalid_types, @nulls, @constraints, @defaults, @units, ...
    @aliases, @unknown_keys, @member_names, @versions, @digests, ...
    @json_rules, @data_rules, @tolerances, @si_values, @open_objects, ...
    @data_only, @byte_order_mark, @array_shapes, @micrograms, ...
    @missing_overlay_ids, @digest_vectors};
names = {'objects and array replacement', 'object arrays merged by id', ...
    'resolution order and relative extends', 'depth and cycle stops', ...
    'dictionary types', 'type rejection', 'null rules', ...
    'bounds lengths and allowed values', 'defaults and required keys', ...
    'SI conversion and round trips', 'alias mapping and warning scope', ...
    'unknown keys and strict mode', 'raw member names', ...
    'configuration versions', 'chain and dictionary digests', ...
    'JSON syntax and comments', 'source selection codes', ...
    'tolerance comparisons and report records', 'unchanged SI values', ...
    'open object members', 'data-only mismatches', 'UTF-8 byte order mark', ...
    'decoded lengths shapes and array identity', 'micrograms per cubic metre', ...
    'overlay entries require ids', 'source digest reference vectors'};
pass = false(size(tests));
for k = 1:numel(tests)
    try
        pass(k) = tests{k}(folder);
    catch err
        fprintf('FAIL %s (%s) %s\n', names{k}, err.identifier, err.message);
    end
    if pass(k), label = 'PASS'; else, label = 'FAIL'; end
    fprintf('%s %s\n', label, names{k});
end
report = struct('name', names(:), 'pass', num2cell(pass(:)));
fprintf('%d of %d cases pass.\n', sum(pass), numel(pass));
if ~all(pass)
    error('sootMosaic:QA:ConfigReadFailed', '%d of %d cases failed.', ...
        sum(~pass), numel(pass));
end
end

function ok = merge_objects(~)
a = struct('obj', struct('x', 1, 'y', 2), 'array', [1 2 3]);
b = struct('obj', struct('x', 4), 'array', [8 9]);
[v, changes] = UTILS.CONFIG_MERGE(a, b, 'overlay.json');
ok = v.obj.x == 4 && v.obj.y == 2 && isequal(v.array, [8 9]) && ...
    numel(changes) == 2 && strcmp(changes(1).path, 'obj.x') && ...
    changes(1).old_value == 1 && changes(1).new_value == 4 && ...
    strcmp(changes(1).source, 'overlay.json');
[v, same] = UTILS.CONFIG_MERGE(a, a);
ok = ok && isequal(v, a) && isempty(same);
v = UTILS.CONFIG_MERGE(a, struct('array', []));
ok = ok && isempty(v.array) && isfield(v, 'obj');
v = UTILS.CONFIG_MERGE({struct('x', 1)}, {struct('x', 2)});
ok = ok && isscalar(v) && v{1}.x == 2;
end

function ok = merge_ids(~)
a = {struct('id', 'a', 'x', 1, 'y', 2); struct('id', 'b', 'x', 3)};
b = {struct('id', 'a', 'x', 4); struct('id', 'c', 'x', 5)};
[v, changes] = UTILS.CONFIG_MERGE(a, b, 'ids.json', 'entries');
ok = numel(v) == 3 && v{1}.x == 4 && v{1}.y == 2 && ...
    v{2}.x == 3 && v{3}.x == 5 && ...
    strcmp(changes.path, 'entries[id=a].x');
v = UTILS.CONFIG_MERGE(a(1), b(1));
ok = ok && isscalar(v) && v{1}.y == 2;
v = UTILS.CONFIG_MERGE(a, []);
ok = ok && isequal(v, a);
a = struct('id', {1, 2}, 'x', {4, 5});
b = {struct('id', 2, 'x', 6)};
v = UTILS.CONFIG_MERGE(a, b);
ok = ok && v{1}.x == 4 && v{2}.x == 6;
ok = ok && raises(@() UTILS.CONFIG_MERGE( ...
    {struct('id', 'a'); struct('id', 'a')}, b), ...
    'sootMosaic:CONFIG_MERGE:DuplicateId');
ok = ok && raises(@() UTILS.CONFIG_MERGE( ...
    {struct('id', 'a'); struct('x', 1)}, b), ...
    'sootMosaic:CONFIG_MERGE:MissingId');
end

function ok = chain_resolution(folder)
dict = {row('group.x', 'number', 'default', 0), ...
    row('group.y', 'number'), row('entries', 'list of objects'), ...
    row('entries[].id', 'text', 'required', true), ...
    row('entries[].x', 'number'), row('entries[].y', 'number')};
write(folder, 'base.json', ...
    '{"group":{"x":1},"entries":[{"id":"a","x":1,"y":2}]}');
mkdir(fullfile(folder, 'nested'));
file = write(folder, fullfile('nested', 'local.json'), ...
    ['{"extends":"../base.json","group":{"x":2},' ...
    '"entries":[{"id":"a","x":3},{"id":"b","x":4}]}']);
opts = strict();
opts.Base = struct('group', struct('x', -1, 'y', 8));
opts.Overrides = struct('group', struct('x', 5));
[cfg, p] = UTILS.CONFIG_READ(file, dict, opts);
ok = cfg.group.x == 5 && cfg.group.y == 8 && ...
    cfg.entries{1}.x == 3 && cfg.entries{1}.y == 2 && ...
    strcmp(cfg.entries{2}.id, 'b') && ~isfield(cfg, 'extends') && ...
    numel(p.files) == 2 && numel(p.overrides) == 5 && ...
    p.overrides(1).old_value == 0 && p.overrides(1).new_value == -1 && ...
    p.overrides(2).old_value == -1 && p.overrides(2).new_value == 1 && ...
    endsWith(p.overrides(2).source, 'base.json') && ...
    strcmp(p.overrides(end).source, '<arguments>');
file = write(folder, 'complete.json', '{"group":{"x":7}}');
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = ok && cfg.group.x == 7 && isscalar(cfg.provenance.files);
end

function ok = chain_limits(folder)
dict = {row('x', 'number')};
write(folder, 'depth1.json', '{"x":1}');
file = write(folder, 'depth2.json', '{"extends":"depth1.json"}');
opts = strict();
opts.MaxDepth = 2;
cfg = UTILS.CONFIG_READ(file, dict, opts);
ok = cfg.x == 1;
opts.MaxDepth = 1;
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, opts), ...
    'sootMosaic:CONFIG_READ:ExtendsDepth');
write(folder, 'depth1.json', '{"extends":"./depth2.json"}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:ExtendsCycle');
file = write(folder, 'missing_parent.json', '{"extends":"absent.json"}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:MissingFile');
file = write(folder, 'bad_parent.json', '{"extends":["base.json"]}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidExtends');
end

function ok = types(folder)
dict = {row('n', 'number'), row('i', 'integer'), row('b', 'logical'), ...
    row('s', 'text'), row('o', 'object'), row('v', 'vector'), ...
    row('m', 'matrix'), row('t', 'list of text'), ...
    row('a', 'list of objects'), row('a[].id', 'text'), ...
    row('triplet', '3 numbers'), row('ints', 'integers'), ...
    row('nums', 'numbers'), row('seed', 'integer or empty'), ...
    row('tol', 'number or none')};
file = write(folder, 'types.json', ['{"n":1.25,"i":2,"b":true,' ...
    '"s":"on","o":{},"v":[1,2],"m":[[1,2],[3,4]],' ...
    '"t":["x","y"],"a":[{"id":"a"}],"triplet":[1,2,3],' ...
    '"ints":[1,2],"nums":[0.1,0.2],"seed":3,"tol":0.01}']);
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = cfg.n == 1.25 && cfg.i == 2 && cfg.b && strcmp(cfg.s, 'on') && ...
    isstruct(cfg.o) && isequal(cfg.v, [1; 2]) && ...
    isequal(cfg.m, [1 2; 3 4]) && isequal(cfg.t, {'x'; 'y'}) && ...
    iscell(cfg.a) && strcmp(cfg.a{1}.id, 'a') && ...
    isequal(cfg.triplet, [1; 2; 3]) && isequal(cfg.ints, [1; 2]) && ...
    isequal(cfg.nums, [0.1; 0.2]) && cfg.seed == 3 && cfg.tol == 0.01;
end

function ok = invalid_types(folder)
cases = {'number', '"1"'; 'integer', 'true'; 'logical', '1'; ...
    'text', '7'; 'object', '[]'; 'vector', '[[1,2],[3,4]]'; ...
    'matrix', '"matrix"'; 'list of text', '[1,2]'; ...
    'list of objects', '["a"]'; 'number or none', '[]'; ...
    'integer or empty', '"none"'; 'numbers', 'true'; ...
    'integers', '["a"]'};
ok = true;
for k = 1:size(cases, 1)
    file = write(folder, 'bad_type.json', ['{"x":' cases{k, 2} '}']);
    dict = {row('x', cases{k, 1})};
    ok = raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
        'sootMosaic:CONFIG_READ:InvalidType') && ok;
end
file = write(folder, 'fraction.json', '{"x":1.5}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, ...
    {row('x', 'integer')}, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidInteger');
end

function ok = nulls(folder)
file = write(folder, 'nulls.json', ...
    '{"tol":null,"off":"none","seed":null,"blank":[],"v":[1,null]}');
dict = {row('tol', 'number or none'), row('off', 'number or none'), ...
    row('seed', 'integer or empty'), row('blank', 'integer or empty'), ...
    row('v', 'vector', 'allow_nan', true)};
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = isinf(cfg.tol) && isinf(cfg.off) && isempty(cfg.seed) && ...
    isempty(cfg.blank) && cfg.v(1) == 1 && isnan(cfg.v(2));
dict{5}.allow_nan = false;
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:Nonfinite');
file = write(folder, 'null_scalar.json', '{"x":null}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, ...
    {row('x', 'number')}, strict()), 'sootMosaic:CONFIG_READ:InvalidType');
cfg = UTILS.CONFIG_READ(file, ...
    {row('x', 'number or none', 'none_value', 'empty')}, strict());
ok = ok && isempty(cfg.x);
end

function ok = constraints(folder)
file = write(folder, 'constraints.json', '{"x":2}');
dict = {row('x', 'number', 'min', 1, 'max', 2, 'allowed', [1 2])};
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = cfg.x == 2;
dict{1}.max = 1;
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:OutOfRange');
dict{1}.max = 3;
dict{1}.allowed = [1 3];
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidValue');
file = write(folder, 'length.json', '{"x":[1,2]}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, ...
    {row('x', '3 numbers')}, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidLength');
file = write(folder, 'enum.json', '{"x":"on"}');
cfg = UTILS.CONFIG_READ(file, ...
    {row('x', 'text', 'allowed', {'on', 'off'})}, strict());
ok = ok && strcmp(cfg.x, 'on');
end

function ok = defaults(folder)
file = write(folder, 'defaults.json', '{}');
dict = {row('settings.flow_lpm', 'number', 'unit', 'L/min', 'default', 6), ...
    row('optional', 'text')};
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = cfg.settings.flow_lpm == 6 && ...
    near(cfg.si.settings.flow_lpm, 1e-4) && ~isfield(cfg, 'optional');
dict{end + 1} = row('required_value', 'number', 'required', true);
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:MissingKey');
file = write(folder, 'default_entries.json', '{"entries":[{"id":"a"}]}');
dict = {row('entries', 'list of objects'), row('entries[].id', 'text'), ...
    row('entries[].x', 'number', 'default', 4)};
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = ok && cfg.entries{1}.x == 4;
end

function ok = units(folder)
file = write(folder, 'units.json', ['{"flow_lpm":6,"size_nm":100,' ...
    '"pressure_kpa":101.325,"length_m":2,"time_s":3,' ...
    '"pressure_pa":100000,"temp_k":298,"density_kg_m3":1000,' ...
    '"mass_fg":0.267,"diameter":50}']);
keys = {'flow_lpm', 'size_nm', 'pressure_kpa', 'length_m', 'time_s', ...
    'pressure_pa', 'temp_k', 'density_kg_m3', 'mass_fg', 'diameter'};
unit = {'L/min', 'nm', 'kPa', 'm', 's', 'Pa', 'K', 'kg/m3', 'fg', 'nm'};
expected = [1e-4, 1e-7, 101325, 2, 3, 100000, 298, 1000, 2.67e-19, 5e-8];
dict = cell(size(keys));
for k = 1:numel(keys)
    dict{k} = row(keys{k}, 'number', 'unit', unit{k}, 'status', 'new');
end
dict{end}.status = 'keep';
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = true;
for k = 1:numel(keys), ok = near(cfg.si.(keys{k}), expected(k)) && ok; end
ok = ok && near(cfg.si.flow_lpm * 60000, cfg.flow_lpm) && ...
    near(cfg.si.size_nm / 1e-9, cfg.size_nm) && ...
    near(cfg.si.pressure_kpa / 1e3, cfg.pressure_kpa);
write(folder, 'units_overlay.json', '{"extends":"units.json"}');
next = UTILS.CONFIG_READ(fullfile(folder, 'units_overlay.json'), dict, strict());
ok = ok && isequal(cfg.si, next.si);
dict{1}.unit = 'm3/s';
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnitMismatch');
dict{1}.unit = 'unknown';
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnknownUnit');
si_units = {'m3/s', 'm/s', 'Pa s', 'kg/mol', 'J/K', '1/mol', ...
    'J/(mol K)', 'C', 'F/m', 'none', 'count', 'pt', 'dpi'};
file = write(folder, 'identity_unit.json', '{"value":2}');
for k = 1:numel(si_units)
    cfg = UTILS.CONFIG_READ(file, ...
        {row('value', 'number', 'unit', si_units{k})}, strict());
    ok = ok && cfg.si.value == 2;
end
file = write(folder, 'named_reference.json', '{"value_at_100_nm":510}');
cfg = UTILS.CONFIG_READ(file, ...
    {row('value_at_100_nm', 'number', 'unit', 'kg/m3')}, strict());
ok = ok && cfg.si.value_at_100_nm == 510;
end

function ok = aliases(folder)
dict = {row('short', 'number', 'alias_of', 'settings.value'), ...
    row('settings.value', 'number', 'default', 1)};
write(folder, 'alias_base.json', '{"short":2}');
file = write(folder, 'alias_overlay.json', ...
    '{"extends":"alias_base.json","short":3}');
[output, cfg] = evalc('UTILS.CONFIG_READ(file, dict, strict())');
ok = cfg.settings.value == 3 && ~isfield(cfg, 'short') && ...
    isscalar(strfind(output, 'is an alias of'));
file = write(folder, 'alias_canonical.json', ...
    '{"short":3,"settings":{"value":4}}');
[~, cfg] = evalc('UTILS.CONFIG_READ(file, dict, strict())');
ok = ok && cfg.settings.value == 4;
write(folder, 'alias_base.json', '{"settings":{"value":6}}');
file = write(folder, 'alias_overlay.json', ...
    '{"extends":"alias_base.json","short":7}');
[~, cfg] = evalc('UTILS.CONFIG_READ(file, dict, strict())');
ok = ok && cfg.settings.value == 7;
dict = {row('entries', 'list of objects'), row('entries[].id', 'text'), ...
    row('entries[].short', 'number', 'alias_of', 'entries[].value'), ...
    row('entries[].value', 'number')};
file = write(folder, 'alias_array.json', ...
    '{"entries":[{"id":"a","short":2},{"id":"b","short":3}]}');
[output, cfg] = evalc('UTILS.CONFIG_READ(file, dict, strict())');
ok = ok && cfg.entries{1}.value == 2 && cfg.entries{2}.value == 3 && ...
    ~isfield(cfg.entries{1}, 'short') && ...
    isscalar(strfind(output, 'is an alias of'));
end

function ok = unknown_keys(folder)
dict = {row('sampling.fraction', 'number')};
write(folder, 'unknown_base.json', '{"sampling":{"fracton":0.2}}');
file = write(folder, 'unknown.json', ...
    '{"extends":"unknown_base.json","sampling":{"fracton":0.3}}');
lastwarn('');
[output, cfg] = evalc('UTILS.CONFIG_READ(file, dict)');
[message, id] = lastwarn;
ok = cfg.sampling.fracton == 0.3 && ...
    strcmp(id, 'sootMosaic:CONFIG_READ:UnknownKey') && ...
    contains(message, 'sampling.fracton') && ...
    contains(message, 'sampling.fraction') && ...
    isscalar(strfind(output, 'Unknown key'));
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnknownKey');
dict = {row('entries', 'list of objects'), row('entries[].id', 'text')};
file = write(folder, 'unknown_array.json', '{"entries":[{"id":"a","x":1}]}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnknownKey');
end

function ok = member_names(folder)
names = {'bad-key', '_lead', '1number', 'has space', ...
    '\u0062ad-key', repmat('x', 1, namelengthmax + 1)};
ok = true;
for k = 1:numel(names)
    file = write(folder, 'bad_name.json', ['{"' names{k} '":1}']);
    ok = raises(@() UTILS.CONFIG_READ(file, {}, strict()), ...
        'sootMosaic:CONFIG_READ:InvalidName') && ok;
end
file = write(folder, 'nested_name.json', ...
    '{"entries":[{"id":"a","bad-key":1}]}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, {}, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidName');
file = write(folder, 'escaped_name.json', '{"\u0078":1}');
cfg = UTILS.CONFIG_READ(file, {row('x', 'number')}, strict());
ok = ok && cfg.x == 1;
end

function ok = versions(folder)
file = write(folder, 'version.json', '{}');
cfg = UTILS.CONFIG_READ(file, {}, strict());
ok = cfg.config_version == 1 && cfg.provenance.files.config_version == 1;
write(folder, 'version.json', '{"config_version":1}');
cfg = UTILS.CONFIG_READ(file, {}, strict());
ok = ok && cfg.config_version == 1;
write(folder, 'version.json', '{"config_version":2}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, {}, strict()), ...
    'sootMosaic:CONFIG_READ:UnsupportedVersion');
write(folder, 'version_overlay.json', ...
    '{"extends":"version.json","config_version":1}');
ok = ok && raises(@() UTILS.CONFIG_READ( ...
    fullfile(folder, 'version_overlay.json'), {}, strict()), ...
    'sootMosaic:CONFIG_READ:UnsupportedVersion');
for value = {'0', '1.5', 'null', '"1"'}
    write(folder, 'version.json', ['{"config_version":' value{1} '}']);
    ok = raises(@() UTILS.CONFIG_READ(file, {}, strict()), ...
        'sootMosaic:CONFIG_READ:InvalidVersion') && ok;
end
end

function ok = digests(folder)
base = write(folder, 'digest_base.json', '{"x":1}');
middle = write(folder, 'digest_middle.json', '{"extends":"digest_base.json"}');
file = write(folder, 'digest_local.json', '{"extends":"digest_middle.json","x":2}');
dictionary = write(folder, 'keys.json', ...
    '[{"path":"x","type":"number","unit":"none","required":true}]');
[cfg, p] = UTILS.CONFIG_READ(file, dictionary, strict());
ok = cfg.x == 2 && numel(p.files) == 3 && isequal(cfg.provenance, p);
if ~usejava('jvm')
    for k = 1:numel(p.files)
        ok = ok && isempty(p.files(k).sha256) && ...
            any(strcmp(p.files(k).notes, 'digest skipped, no JVM'));
    end
    ok = ok && isempty(p.dictionary.sha256) && ...
        any(strcmp(p.dictionary.notes, 'digest skipped, no JVM'));
    return
end
paths = {base, middle, file};
expected = {'5041bf1f713df204784353e82f6a4a535931cb64f1f4b4a5aeaffcb720918b22', ...
    '400d168fd8b0722006ce5895ee31fd026f2dc56809486e0db826fbb033249db8', ...
    '6751f84e4776f218ed2270b390e180ecc08060422fea1bc7f4c74ee878f4c454'};
for k = 1:numel(paths)
    ok = ok && strcmp(p.files(k).sha256, expected{k});
    ok = ok && strcmp(p.files(k).sha256, UTILS.FILE_SHA256(paths{k}));
    ok = ok && numel(p.files(k).sha256) == 64;
end
ok = ok && strcmp(p.dictionary.sha256, ...
    '318b22743c0826124b3a2e990cc99ab1c02308f0c9fee13cba65559912d28fe5');
ok = ok && strcmp(p.dictionary.sha256, UTILS.FILE_SHA256(dictionary));
write(folder, 'digest_base.json', '{"x":1,"comment":"note"}');
[~, next] = UTILS.CONFIG_READ(file, dictionary, strict());
ok = ok && ~strcmp(next.files(1).sha256, p.files(1).sha256) && ...
    strcmp(next.files(2).sha256, p.files(2).sha256);
end

function ok = json_rules(folder)
dict = {row('x', 'number'), row('obj', 'object'), ...
    row('entries', 'list of objects'), row('entries[].id', 'text')};
file = write(folder, 'comments.json', ['{"x":1,"comment":"note",' ...
    '"obj":{"comment":{"anything":1}},' ...
    '"entries":[{"id":"a","comment":null}]}']);
cfg = UTILS.CONFIG_READ(file, dict, strict());
ok = ~isfield(cfg, 'comment') && ~isfield(cfg.obj, 'comment') && ...
    ~isfield(cfg.entries{1}, 'comment');
bad = {'{"x":Infinity}', '{"x":1,}', '{"x":', '{"x":NaN}'};
bad = [bad, {'{"x":[1,]}', '{"x":01}', '{"x":+1}', ...
    '{"x":1 "obj":{}}', '{"x":"unterminated}', '[] []'}];
for k = 1:numel(bad)
    file = write(folder, 'syntax.json', bad{k});
    ok = raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
        'sootMosaic:CONFIG_READ:InvalidJSON') && ok;
end
file = write(folder, 'duplicate.json', '{"x":1,"x":2}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:DuplicateKey');
file = write(folder, 'reserved.json', '{"si":{}}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:ReservedKey');
file = write(folder, 'root_array.json', '[{"x":1}]');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidObject');
end

function ok = data_rules(~)
s = struct('data', 2, 'config', 1, 'campaign', 3, ...
    'registry', 4, 'profile', 5, 'derived', 6);
opts = struct('Path', 'flow_lpm', 'Reason', 'campaign record');
codes = {'D', 'D>C', 'C', 'C~D', 'R', 'P', 'W>D>C'};
expected = [2 2 1 1 4 5 3];
sources = {'data', 'data', 'config', 'config', 'registry', 'profile', 'campaign'};
ok = true;
for k = 1:numel(codes)
    [~, v, r] = evalc('UTILS.CONFIG_DATA_RULE(codes{k}, s, opts)');
    ok = ok && v == expected(k) && strcmp(r.source, sources{k}) && ...
        strcmp(r.code, codes{k}) && strcmp(r.path, 'flow_lpm');
    ok = ok && raises(@() UTILS.CONFIG_DATA_RULE(codes{k}, struct()), ...
        'sootMosaic:CONFIG_DATA_RULE:MissingValue');
end
[v, r] = UTILS.CONFIG_DATA_RULE('D>C', struct('config', 0));
ok = ok && v == 0 && r.from_config;
[v, r] = UTILS.CONFIG_DATA_RULE('W>D>C', struct('data', false));
ok = ok && isequal(v, false) && strcmp(r.source, 'data');
[v, r] = UTILS.CONFIG_DATA_RULE('W>D>C', struct('config', 1));
ok = ok && v == 1 && r.from_config;
[v, r] = UTILS.CONFIG_DATA_RULE('X', struct('derived', 6));
ok = ok && v == 6 && strcmp(r.source, 'derived');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('D', struct('config', 1)), ...
    'sootMosaic:CONFIG_DATA_RULE:MissingValue');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('X', s), ...
    'sootMosaic:CONFIG_DATA_RULE:ConfiguredDerived');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('W>D>C', s), ...
    'sootMosaic:CONFIG_DATA_RULE:MissingReason');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('other', s), ...
    'sootMosaic:CONFIG_DATA_RULE:UnknownCode');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('X', struct()), ...
    'sootMosaic:CONFIG_DATA_RULE:MissingValue');
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('D', struct('data', NaN)), ...
    'sootMosaic:CONFIG_DATA_RULE:Nonfinite');
end

function ok = tolerances(~)
opts = struct('Path', 'pressure_kpa', 'AbsTol', 1, 'RelTol', 0.01);
s = struct('data', [101 202], 'config', [100 200]);
lastwarn('');
[v, r] = UTILS.CONFIG_DATA_RULE('D>C', s, opts);
[~, id] = lastwarn;
ok = isequal(v, s.data) && ~r.comparisons.exceeds_tolerance && ...
    r.comparisons.different && isempty(id) && ...
    isequal(r.comparisons.limit, [1 2]);
s.data = [101.1 202];
lastwarn('');
[~, v, r] = evalc('UTILS.CONFIG_DATA_RULE(''C~D'', s, opts)');
[~, id] = lastwarn;
ok = ok && isequal(v, s.config) && r.comparisons.exceeds_tolerance && ...
    strcmp(id, 'sootMosaic:CONFIG_DATA_RULE:Mismatch') && ...
    isequal(r.comparisons.value_a, s.data) && ...
    isequal(r.comparisons.value_b, s.config);
s.campaign = [101.2 202];
opts.Reason = 'campaign record';
[~, v, r] = evalc('UTILS.CONFIG_DATA_RULE(''W>D>C'', s, opts)');
ok = ok && isequal(v, s.campaign) && numel(r.comparisons) == 3 && ...
    all([r.comparisons.different]) && strcmp(r.reason, opts.Reason);
opts.AbsTol = -1;
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('D>C', s, opts), ...
    'sootMosaic:CONFIG_DATA_RULE:InvalidInput');
[~, ~, r] = evalc('UTILS.CONFIG_DATA_RULE(''C~D'', struct(''data'', ''a'', ''config'', ''b''))');
ok = ok && r.comparisons.exceeds_tolerance;
end

function ok = si_values(folder)
file = write(folder, 'si_values.json', ['{"t":["x","y"],' ...
    '"o":{"q":1,"nested":{"v":[5],"nil":null}},"s":"abc",' ...
    '"a":[{"id":"a","q":4}],"b":true,"n":2,"i":3,' ...
    '"v":[1,2],"m":[[1,2],[3,4]],' ...
    '"nums":[1,2],"ints":[1,2],"tol":null,"seed":null}']);
dict = {row('t', 'list of text'), row('o', 'object'), row('s', 'text'), ...
    row('a', 'list of objects'), row('b', 'logical'), row('n', 'number'), ...
    row('i', 'integer'), row('v', 'vector'), row('m', 'matrix'), ...
    row('nums', 'numbers'), row('ints', 'integers'), ...
    row('tol', 'number or none'), row('seed', 'integer or empty')};
[~, cfg] = evalc('UTILS.CONFIG_READ(file, dict)');
ok = true;
for k = 1:numel(dict)
    key = dict{k}.path;
    ok = isequaln(cfg.si.(key), cfg.(key)) && ok;
end
ok = ok && isequal(cfg.si.t, {'x'; 'y'}) && cfg.si.o.q == 1 && ...
    cfg.si.o.nested.v == 5 && isempty(cfg.si.o.nested.nil) && ...
    cfg.si.a{1}.q == 4;
end

function ok = open_objects(folder)
file = write(folder, 'open.json', ...
    '{"o":{"free":1,"nested":{"text":"x","comment":"note"}}}');
dict = {row('o', 'object', 'open', true)};
lastwarn('');
cfg = UTILS.CONFIG_READ(file, dict, strict());
[~, id] = lastwarn;
ok = isempty(id) && isequal(cfg.si.o, cfg.o) && cfg.o.free == 1 && ...
    ~isfield(cfg.o.nested, 'comment');
dict{1}.open = false;
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnknownKey');
dict{1}.open = true;
dict{2} = row('o.free', 'number');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnknownKey');
file = write(folder, 'open_invalid.json', '{"o":{"bad-key":1}}');
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidName');
end

function ok = data_only(~)
lastwarn('');
[value, report] = UTILS.CONFIG_DATA_RULE('D', ...
    struct('data', 1, 'config', 5), struct('Path', 'p'));
[~, id] = lastwarn;
ok = value == 1 && strcmp(report.source, 'data') && ...
    ~report.from_config && isempty(report.comparisons) && isempty(id);
ok = ok && raises(@() UTILS.CONFIG_DATA_RULE('D', struct('config', 5)), ...
    'sootMosaic:CONFIG_DATA_RULE:MissingValue');
end

function ok = byte_order_mark(folder)
file = write(folder, 'bom.json', [uint8([239 187 191]), uint8('{"x":1}')]);
dict_file = write(folder, 'bom_keys.json', [uint8([239 187 191]), ...
    uint8('[{"path":"x","type":"number"}]')]);
[cfg, p] = UTILS.CONFIG_READ(file, dict_file, strict());
bom_note = {'Leading UTF-8 byte order mark skipped.'};
digest_notes = {};
if usejava('jvm')
    ok = strcmp(p.files.sha256, ...
        '8fdb1cc0bb1ffcb2b50c48b01162d5927130192b6ae39d472639fa32519284bb');
else
    ok = isempty(p.files.sha256) && isempty(p.dictionary.sha256);
    digest_notes = {'digest skipped, no JVM'};
end
ok = ok && cfg.x == 1 && ...
    isequal(p.files.notes, [bom_note digest_notes]) && ...
    isequal(p.dictionary.notes, [bom_note digest_notes]);
overlay = write(folder, 'bom_overlay.json', '{"extends":"bom.json"}');
[~, p] = UTILS.CONFIG_READ(overlay, dict_file, strict());
ok = ok && isequal(p.files(1).notes, [bom_note digest_notes]) && ...
    isequal(p.files(2).notes, digest_notes);
end

function ok = array_shapes(folder)
array = write(folder, 'one_array.json', '{"v":[5]}');
scalar = write(folder, 'one_scalar.json', '{"v":5}');
dict = {row('v', 'vector', 'length', 1, 'shape', [1 1])};
cfg = UTILS.CONFIG_READ(array, dict, strict());
ok = cfg.v == 5 && cfg.si.v == 5 && ...
    raises(@() UTILS.CONFIG_READ(scalar, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidType');
dict{1} = rmfield(dict{1}, 'length');
ok = ok && raises(@() UTILS.CONFIG_READ(scalar, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidType');
dict = {row('v', 'number', 'shape', [1 1])};
cfg = UTILS.CONFIG_READ(scalar, dict, strict());
ok = ok && cfg.v == 5 && ...
    raises(@() UTILS.CONFIG_READ(array, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidType');
for type = {'1 numbers', 'numbers', 'integers', 'matrix'}
    dict = {row('v', type{1}, 'length', 1)};
    cfg = UTILS.CONFIG_READ(array, dict, strict());
    ok = ok && cfg.v == 5 && ...
        raises(@() UTILS.CONFIG_READ(scalar, dict, strict()), ...
        'sootMosaic:CONFIG_READ:InvalidType');
end
matrix = write(folder, 'shape.json', '{"v":[[1,2],[3,4]]}');
dict = {row('v', 'matrix', 'shape', [2 2])};
cfg = UTILS.CONFIG_READ(matrix, dict, strict());
ok = ok && isequal(cfg.v, [1 2; 3 4]);
dict{1}.shape = [4 1];
ok = ok && raises(@() UTILS.CONFIG_READ(matrix, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidShape');
dict = {row('v', 'vector', 'length', 2)};
ok = ok && raises(@() UTILS.CONFIG_READ(array, dict, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidLength');
dict_file = write(folder, 'shape_keys.json', ...
    '[{"path":"v","type":"vector","length":1,"shape":[1,1]}]');
overlay = write(folder, 'shape_overlay.json', '{"extends":"one_array.json"}');
cfg = UTILS.CONFIG_READ(overlay, dict_file, strict());
ok = ok && cfg.v == 5;
write(folder, 'shape_overlay.json', '{"extends":"one_array.json","v":5}');
ok = ok && raises(@() UTILS.CONFIG_READ(overlay, dict_file, strict()), ...
    'sootMosaic:CONFIG_READ:InvalidType');
dict = {row('short', 'vector', 'alias_of', 'v'), ...
    row('v', 'vector', 'length', 1)};
file = write(folder, 'shape_alias.json', '{"short":[5]}');
[~, cfg] = evalc('UTILS.CONFIG_READ(file, dict, strict())');
ok = ok && cfg.v == 5;
dict_file = write(folder, 'shape_defaults.json', ...
    ['[{"path":"v","type":"vector","length":1,"default":[5]},' ...
    '{"path":"tol","type":"number or none","default":null}]']);
file = write(folder, 'shape_empty.json', '{}');
cfg = UTILS.CONFIG_READ(file, dict_file, strict());
ok = ok && cfg.v == 5 && isinf(cfg.si.tol);
end

function ok = micrograms(folder)
file = write(folder, 'micrograms.json', '{"mass_ugm3":25}');
ok = true;
for unit = {'ugm3', 'ug/m3', 'micrograms per m3'}
    dict = {row('mass_ugm3', 'number', 'unit', unit{1}, 'status', 'new')};
    cfg = UTILS.CONFIG_READ(file, dict, strict());
    ok = ok && near(cfg.si.mass_ugm3, 25e-9) && ...
        near(cfg.si.mass_ugm3 / 1e-9, cfg.mass_ugm3);
end
dict{1}.unit = 'kg/m3';
ok = ok && raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_READ:UnitMismatch');
end

function ok = missing_overlay_ids(folder)
write(folder, 'id_base.json', '{"entries":[{"id":"a","x":1}]}');
file = write(folder, 'id_missing.json', ...
    '{"extends":"id_base.json","entries":[{"x":9}]}');
dict = {row('entries', 'list of objects'), row('entries[].id', 'text'), ...
    row('entries[].x', 'number')};
ok = raises(@() UTILS.CONFIG_READ(file, dict, strict()), ...
    'sootMosaic:CONFIG_MERGE:MissingId');
ok = ok && raises(@() UTILS.CONFIG_MERGE( ...
    {struct('id', 'a', 'x', 1)}, {struct('x', 9); struct('x', 10)}), ...
    'sootMosaic:CONFIG_MERGE:MissingId');
end

function ok = digest_vectors(folder)
ok = true;
if ~usejava('jvm'), return; end
file = write(folder, 'digest_abc.txt', 'abc');
ok = strcmp(UTILS.FILE_SHA256(file), ...
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
end

function value = row(path, type, varargin)
value = struct('path', path, 'type', type);
for k = 1:2:numel(varargin), value.(varargin{k}) = varargin{k + 1}; end
end

function opts = strict()
opts = struct('Strict', true);
end

function file = write(folder, name, text)
file = fullfile(folder, name);
fid = fopen(file, 'wb');
if fid < 0
    error('sootMosaic:QA:ConfigReadFailed', 'Cannot write fixture %s.', name);
end
cleanup = onCleanup(@() fclose(fid));
if isa(text, 'uint8')
    fwrite(fid, text, 'uint8');
else
    fwrite(fid, text, 'char');
end
end

function ok = raises(fn, id)
ok = false;
try
    fn();
catch err
    ok = strcmp(err.identifier, id);
end
end

function ok = near(a, b)
ok = all(abs(a(:) - b(:)) <= 1e-12 * abs(b(:)));
end

function restore_warnings(state, message, id)
warning(state);
lastwarn(message, id);
end
