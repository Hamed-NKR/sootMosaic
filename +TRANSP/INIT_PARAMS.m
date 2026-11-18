function [params_ud, params_const] = INIT_PARAMS(fname, constants)
% "INIT_PARAMS" reads domain parameters and builds physical constants.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     fname: Parameter file basename in inputs
%     constants: Resolved SI constants section (optional, fixed profile)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     params_ud: Domain, particle and fluid parameter table
%     params_const: Named physical constants table
% ----------------------------------------------------------------------- %

% Defining the constant physical parameters used in the soot aggregation...
    % ...problem
if nargin < 2, constants = []; end
params_const = UTILS.CONSTANTS_TABLE(constants);

% Importing the user-defined parameters of domain, particle and flow

% Extracting user data from the input file
f_adrs = strcat('inputs\', fname, '.txt');
f_id = fopen(f_adrs,'r');
import_data = textscan(f_id,'%s%f%s%s','Headerlines',2,...
    'Delimiter','\t','MultipleDelimsAsOne',1);
fclose(f_id);

Name = import_data{1,1};
Value = import_data{1,2};
Unit = import_data{1,3};
Description = import_data{1,4};
params_ud = table(Name, Value, Unit, Description); % The table of...
    % ...user-defined parameters
    % NOTE: See the "Description" column in the input file for more info...
        % ...on these parameters.

end

