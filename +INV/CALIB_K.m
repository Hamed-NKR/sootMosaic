function [k, u_rel, in_range, flagged_share, provenance] = CALIB_K(dm_m, cfg)
% "CALIB_K" evaluates the tandem density calibration factor k(dm).
% ----------------------------------------------------------------------- %
%
% Inputs:
%     dm_m: Positive mobility diameters, any shape (m)
%     cfg: Resolved +INV configuration. The factor, its range, its...
%         ...uncertainty and its source are read from...
%         ...cfg.si.calibration.k_dm
% ----------------------------------------------------------------------- %
%
% Outputs:
%     k: Calibration factor, with the shape of dm_m. A measured effective...
%         ...density is divided by k once (-)
%     u_rel: Relative one-sigma uncertainty of k, systematic per campaign,...
%         ...doubled outside the calibrated range, NaN when none is...
%         ...configured (-)
%     in_range: True where dm_m lies inside the calibrated range
%     flagged_share: Share of the diameters outside the calibrated range (-)
%     provenance: Registry entry, form, coefficients, range, reference...
%         ...material and density, operating condition and the source of...
%         ...the uncertainty
% ----------------------------------------------------------------------- %
% Method: Perraud, Smith and Olfert (2023, supplement Fig. S5), k as the...
%     ...measured over the material density of a reference aerosol;...
%     ...Kiasadegh et al. (2026, Eqs. 33 and 34), division of the...
%     ...effective density by k; Sapkota et al. (2025, SI Sec. S3 and...
%     ...Fig. S3), PEG points and the fit k = 1.27 - 3.598 dm^-0.8376...
%     ...with dm in nm.
% Provenance: earlier calibration code was read as a model of the...
%     ...density-ratio correction of Perraud, Smith and Olfert (2023) and...
%     ...Kiasadegh et al. (2026, Eqs. 33-34), no code text adopted.
% Reimplementation. A data file holds either PEG points (dm_nm, k) or a...
%     ...3 x 3 covariance of offset, coefficient and exponent. Points give...
%     ...the covariance s^2 (J'J)^-1 with J the Jacobian of the published...
%     ...form at the published coefficients and s^2 the residual scatter...
%     ...about the published curve over n - 3 degrees of freedom; the...
%     ...coefficients stay those of the published fit.

if ~isnumeric(dm_m) || ~isreal(dm_m) || isempty(dm_m) || ...
        any(~isfinite(dm_m(:))) || any(dm_m(:) <= 0)
    fail('InvalidDiameters', ...
        'Mobility diameters (m) must be positive and finite.');
end
if ~isstruct(cfg) || ~isscalar(cfg) || ~isfield(cfg, 'si') || ...
        ~isfield(cfg.si, 'calibration') || ...
        ~isfield(cfg.si.calibration, 'k_dm')
    fail('InvalidConfig', 'Pass the resolved +INV configuration.');
end
c = cfg.si.calibration.k_dm;
coefficients = [c.offset, c.coefficient, c.exponent];
range_m = double(c.range_nm(:).');
if ~isnumeric(coefficients) || numel(coefficients) ~= 3 || ...
        any(~isfinite(coefficients)) || numel(range_m) ~= 2 || ...
        any(~isfinite(range_m)) || range_m(1) <= 0 || ...
        range_m(2) <= range_m(1) || ~isscalar(c.diameter_unit_nm) || ...
        ~(c.diameter_unit_nm > 0)
    fail('InvalidConfig', ...
        'The factor needs its coefficients, range and unit.');
end
if ~strcmp(c.out_of_range, 'flag')
    fail('OutOfRangePolicy', ...
        'calibration.k_dm.out_of_range supports flag only.');
end
dm_m = double(dm_m);
unit_m = c.diameter_unit_nm;
range_nm = range_m / unit_m;
provenance = struct('enabled', logical(c.enabled), ...
    'source_id', c.source_id, 'registry', registry_entry(c.source_id), ...
    'form', 'k = offset + coefficient * (dm / 1 nm)^exponent', ...
    'offset', coefficients(1), 'coefficient', coefficients(2), ...
    'exponent', coefficients(3), 'range_nm', range_nm, ...
    'out_of_range', c.out_of_range, ...
    'out_of_range_uncertainty_factor', 2, ...
    'reference_material', c.reference_material, ...
    'reference_density_kg_m3', c.reference_density_kg_m3, ...
    'operating_condition', c.operating_condition, ...
    'uncertainty_kind', 'relative one sigma, systematic per campaign', ...
    'uncertainty_source', 'none', 'uncertainty_configured', ...
    c.uncertainty, 'data_file', c.data_file, 'data_file_sha256', '', ...
    'parameter_covariance', [], 'n_points', 0, 'residual_sd', NaN, ...
    'citations', {{ ...
    'Perraud, Smith and Olfert (2023), doi:10.1080/02786826.2023.2176739', ...
    'Sapkota et al. (2025), SI Sec. S3, doi:10.1080/02786826.2025.2519093', ...
    'Sapkota et al. (2025), doi:10.1080/02786826.2025.2541649', ...
    'Kiasadegh et al. (2026), Eqs. 33 and 34'}});
if ~provenance.enabled
    k = ones(size(dm_m));
    u_rel = zeros(size(dm_m));
    in_range = true(size(dm_m));
    flagged_share = 0;
    provenance.uncertainty_source = 'disabled';
    return
end

% Evaluating the published form in its diameter unit
d = dm_m / unit_m;
[k, jacobian] = factor_form(d, coefficients);
if any(~isfinite(k(:))) || any(k(:) <= 0)
    fail('FactorRange', ...
        'The factor is not positive at these diameters (k <= 0).');
end
in_range = dm_m >= range_m(1) & dm_m <= range_m(2);
flagged_share = nnz(~in_range) / numel(in_range);

% Selecting the uncertainty, a data file before the configured value
if ~isempty(c.data_file)
    [covariance, info] = data_covariance(c.data_file, coefficients);
    provenance.uncertainty_source = info.source;
    provenance.data_file_sha256 = info.sha256;
    provenance.parameter_covariance = covariance;
    provenance.n_points = info.n_points;
    provenance.residual_sd = info.residual_sd;
    se = sqrt(max(sum((jacobian * covariance) .* jacobian, 2), 0));
    u_rel = reshape(se, size(k)) ./ k;
elseif ~isempty(c.uncertainty)
    u = c.uncertainty;
    if ~isnumeric(u) || ~isscalar(u) || ~isfinite(u) || u < 0 || u >= 1
        fail('InvalidUncertainty', ...
            'calibration.k_dm.uncertainty must lie in [0, 1).');
    end
    provenance.uncertainty_source = 'config';
    u_rel = u * ones(size(k));
else
    u_rel = NaN(size(k));
end
u_rel(~in_range) = provenance.out_of_range_uncertainty_factor * ...
    u_rel(~in_range);
end

function [k, jacobian] = factor_form(d, p)
% "factor_form" evaluates k and its parameter derivatives at diameters d.
power = d(:) .^ p(3);
k = reshape(p(1) + p(2) * power, size(d));
jacobian = [ones(numel(d), 1), power, p(2) * power .* log(d(:))];
end

function [covariance, info] = data_covariance(file, p)
% "data_covariance" reads calibration points or a parameter covariance.
root = fileparts(fileparts(mfilename('fullpath')));
if isempty(regexp(file, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
    file = fullfile(root, 'data', file);
end
if ~isfile(file)
    fail('MissingDataFile', ['Calibration data file not found: ' file]);
end
info = struct('source', '', 'sha256', '', 'n_points', 0, ...
    'residual_sd', NaN);
if usejava('jvm'), info.sha256 = UTILS.FILE_SHA256(file); end
[~, ~, ext] = fileparts(file);
switch lower(ext)
    case '.mat'
        loaded = load(file);
    case '.csv'
        loaded = read_points(file);
    otherwise
        fail('InvalidDataFile', 'Use a .mat or .csv calibration file.');
end
if isfield(loaded, 'covariance')
    covariance = double(loaded.covariance);
    if ~isequal(size(covariance), [3 3]) || ...
            any(~isfinite(covariance(:))) || ...
            norm(covariance - covariance.', 1) > ...
            1e-12 * max(1, norm(covariance, 1)) || ...
            min(eig((covariance + covariance.') / 2)) < ...
            -1e-12 * max(1, norm(covariance, 1))
        fail('InvalidDataFile', ...
            'The covariance must be a symmetric 3 x 3 nonnegative matrix.');
    end
    covariance = (covariance + covariance.') / 2;
    info.source = 'data_file_covariance';
    return
end
if ~isfield(loaded, 'dm_nm') || ~isfield(loaded, 'k')
    fail('InvalidDataFile', 'A data file needs dm_nm and k, or covariance.');
end
d = double(loaded.dm_nm(:));
y = double(loaded.k(:));
if numel(d) ~= numel(y) || numel(d) <= 3 || ...
        any(~isfinite([d; y])) || any(d <= 0)
    fail('InvalidDataFile', ...
        'Points need matching finite dm_nm > 0 and k, more than three.');
end
[f, jacobian] = factor_form(d, p);
residual = y - f;
information = jacobian.' * jacobian;
if rcond(information) < 1e3 * eps
    fail('InvalidDataFile', ...
        'The points do not determine the three parameters.');
end
dof = numel(d) - 3;
s2 = (residual.' * residual) / dof;
covariance = s2 * (information \ eye(3));
covariance = (covariance + covariance.') / 2;
info.source = 'data_file_points';
info.n_points = numel(d);
info.residual_sd = sqrt(s2);
end

function loaded = read_points(file)
% "read_points" reads the numeric columns dm_nm and k of a point file.
fid = fopen(file, 'r');
if fid < 0, fail('InvalidDataFile', ['Cannot open ' file]); end
close_file = onCleanup(@() fclose(fid));
line = fgetl(fid);
if ~ischar(line), fail('InvalidDataFile', 'The point file is empty.'); end
header = strtrim(strsplit(line, ','));
columns = textscan(fid, repmat('%f', 1, numel(header)), ...
    'Delimiter', ',', 'CollectOutput', true);
clear close_file
index_d = find(strcmp(header, 'dm_nm'), 1);
index_k = find(strcmp(header, 'k'), 1);
if isempty(index_d) || isempty(index_k)
    fail('InvalidDataFile', 'A point file needs columns dm_nm and k.');
end
values = columns{1};
loaded = struct('dm_nm', values(:, index_d), 'k', values(:, index_k));
end

function entry = registry_entry(id)
% "registry_entry" reads the tracked data-source entry named by source_id.
root = fileparts(fileparts(mfilename('fullpath')));
folder = fullfile(root, 'config', 'sources');
registry = UTILS.CONFIG_READ(fullfile(folder, 'sources.json'), ...
    fullfile(folder, 'sources.keys.json'), struct('Strict', false));
if ~ischar(id) || isempty(id) || ~isfield(registry, id) || ...
        any(strcmp(id, {'si', 'provenance', 'config_version'}))
    fail('UnknownSource', 'calibration.k_dm.source_id is not registered.');
end
entry = registry.(id);
entry.id = id;
end

function fail(reason, message)
error(['sootMosaic:CALIB_K:' reason], '%s', message);
end
