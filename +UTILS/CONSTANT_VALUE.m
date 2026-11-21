function value = CONSTANT_VALUE(constants, name)
% "CONSTANT_VALUE" reads a physical constant by its table name.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     constants: Physical constants table
%     name: Name of the requested constant
% ----------------------------------------------------------------------- %
%
% Outputs:
%     value: Scalar value, using the fixed row order for unnamed tables
% ----------------------------------------------------------------------- %

if ~istable(constants) || ...
        ~any(strcmp(constants.Properties.VariableNames, 'Value'))
    error('sootMosaic:CONSTANT_VALUE:InvalidTable', ...
        'Physical constants must be a table with a Value column.');
end
if ~isempty(constants.Properties.RowNames)
    row = find(strcmp(constants.Properties.RowNames, name));
elseif any(strcmp(constants.Properties.VariableNames, 'Name'))
    row = find(strcmp(constants.Name, name));
else
    names = {'rho_bc', 'M_air', 'kb', 'Na', 'Ru'};
    row = find(strcmp(names, name));
end
if numel(row) ~= 1 || row > height(constants)
    error('sootMosaic:CONSTANT_VALUE:MissingConstant', ...
        'The physical constants table must contain one %s value.', name);
end
value = constants.Value(row);
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value <= 0
    error('sootMosaic:CONSTANT_VALUE:InvalidConstant', ...
        'Physical constant %s must be positive and finite.', name);
end
end
