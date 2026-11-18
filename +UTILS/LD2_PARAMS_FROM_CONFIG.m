function [params_domain, params_const, fl] = LD2_PARAMS_FROM_CONFIG( ...
        domain_cfg, fluid_cfg, constants)
% "LD2_PARAMS_FROM_CONFIG" builds domain and fluid parameters.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     domain_cfg: Domain settings
%     fluid_cfg: Fluid temperature and pressure
%     constants: Resolved SI constants section (optional, fixed profile)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     params_domain: Domain parameter table
%     params_const: Named physical constants table
%     fl: Fluid structure
% ----------------------------------------------------------------------- %

if nargin < 1 || ~isstruct(domain_cfg)
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:MissingDomain', ...
        'transport.domain must be a struct.');
end
if nargin < 2 || ~isstruct(fluid_cfg)
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:MissingFluid', ...
        'transport.fluid must be a struct.');
end

volume_fraction = require_scalar_field(domain_cfg, 'volume_fraction', ...
    'transport.domain.volume_fraction');
domain_size = require_vector_field(domain_cfg, 'size', 3, ...
    'transport.domain.size');
temperature = require_scalar_field(fluid_cfg, 'temperature', ...
    'transport.fluid.temperature');
pressure = require_scalar_field(fluid_cfg, 'pressure', ...
    'transport.fluid.pressure');

Name = {'volf'; 'dom_size(1)'; 'dom_size(2)'; 'dom_size(3)'};
Value = [volume_fraction; domain_size(:)];
Unit = {'[-]'; '[m]'; '[m]'; '[m]'};
Description = {'Particle volume fraction'; 'Computational domain length'; ...
    'Computational domain width'; 'Computational domain height'};
params_domain = table(Name, Value, Unit, Description);

if nargin < 3, constants = []; end
params_const = UTILS.CONSTANTS_TABLE(constants);

fl = struct('size', domain_size(:), 'temp', temperature, 'p', pressure, ...
    'mu', [], 'lambda', []);

end

function out = require_scalar_field(src, field_name, label)
%REQUIRE_SCALAR_FIELD Read and validate a numeric scalar field.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:MissingScalar', ...
        'The LD2 config is missing %s.', label);
end

out = double(src.(field_name));
if ~isscalar(out) || ~isfinite(out)
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:InvalidScalar', ...
        'The LD2 config field %s must be a finite numeric scalar.', label);
end

end

function out = require_vector_field(src, field_name, expected_len, label)
%REQUIRE_VECTOR_FIELD Read and validate a numeric vector field.

if ~isfield(src, field_name) || isempty(src.(field_name))
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:MissingVector', ...
        'The LD2 config is missing %s.', label);
end

out = double(src.(field_name));
out = reshape(out, 1, []);
if numel(out) ~= expected_len || any(~isfinite(out))
    error('sootMosaic:LD2_PARAMS_FROM_CONFIG:InvalidVector', ...
        'The LD2 config field %s must be a finite numeric vector of length %d.', ...
        label, expected_len);
end

end
