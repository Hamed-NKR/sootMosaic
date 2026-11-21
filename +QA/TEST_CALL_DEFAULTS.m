function report = TEST_CALL_DEFAULTS()
% "TEST_CALL_DEFAULTS" checks call defaults against literal fixtures.
% ----------------------------------------------------------------------- %
%
% Outputs:
%     report: Case names and pass flags. Failures use...
%         ...sootMosaic:QA:CallDefaultsFailed
% ----------------------------------------------------------------------- %

expected = struct('mtd', 'continuum', ...
    'continuum_diameter', 'fixed_075dg', ...
    'root_solve', 'start_point_7658971', ...
    'projection', 'euler_7658971', 'proj_cache', false, ...
    'proj_points', 100, 'proj_orientations', 5, 'proj_replicates', 1, ...
    'proj_tol', Inf, 'proj_warned', false, ...
    'slip', 'per_caller_7658971', 'c_dt', 1, ...
    'step_frac', 0.5, 'step_policy', 'warn', 'step_warned', false);
defaults = UTILS.CALL_DEFAULTS();
names = {'mobility literals', 'sampling literals', 'fluid literals', ...
    'call without options', 'empty options', 'explicit options'};
pass = false(size(names));
pass(1) = isequal(defaults.mobil, expected);
pass(2) = isequal(defaults.lnsampling, struct('sigma_d', 1.4, 'n_bin', 10));
pass(3) = isequal(defaults.flprops, struct('amb', 'flame'));
pars = struct('n', 1, 'dg', 30e-9, 'pp', {{[1, 30e-9, 0, 0, 0]}});
fl = struct('temp', 1700, 'mu', 5.647e-5, 'lambda', 4.98e-7);
constants = table([1.86e3; 28.97e-3; 1.381e-23; 6.022e23; 8.314], ...
    'VariableNames', {'Value'});
[p0, o0] = TRANSP.MOBIL(pars, fl, constants);
[p1, o1] = TRANSP.MOBIL(pars, fl, constants, expected);
pass(4) = isequal(p0, p1) && isequal(o0, o1);
empty = struct();
fields = fieldnames(expected);
for k = 1:numel(fields), empty.(fields{k}) = []; end
[p2, o2] = TRANSP.MOBIL(pars, fl, constants, empty);
pass(5) = isequal(p0, p2) && isequal(o0, o2);
explicit = struct('mtd', 'sorensen_eq17', 'c_dt', 0.25, ...
    'step_frac', 0.1, 'step_policy', 'cap');
[~, options] = TRANSP.MOBIL(pars, fl, constants, explicit);
pass(6) = strcmp(options.mtd, 'sorensen_eq17') && ...
    options.c_dt == 0.25 && options.step_frac == 0.1 && ...
    strcmp(options.step_policy, 'cap');
report = struct('name', names(:), 'pass', num2cell(pass(:)));
if ~all(pass)
    error('sootMosaic:QA:CallDefaultsFailed', '%s', strjoin(names(~pass), ', '));
end
end
