function params_const = CONSTANTS_TABLE(constants)
% "CONSTANTS_TABLE" builds the named physical constants table.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     constants: Resolved SI constants section (optional, fixed profile)
% ----------------------------------------------------------------------- %
%
% Outputs:
%     params_const: Five physical constants with names and units
% ----------------------------------------------------------------------- %

if nargin < 1 || isempty(constants)
    profile = UTILS.MODEL_DEFAULTS('article1_7658971');
    constants = profile.constants;
end

Name = {'rho_bc'; 'M_air'; 'kb'; 'Na'; 'Ru'};
Value = [constants.rho_bc_kg_m3; constants.m_air_kg_mol; ...
    constants.kb_j_k; constants.na_mol_inv; constants.ru_j_mol_k];
Unit = {'kg/m3'; 'kg/mol'; 'j/k'; 'mol^-1'; 'j/mol.k'};
Description = {'Black Carbon bulk density'; 'Air molar mass'; ...
    'Boltzmann constant'; 'Avogadro constant'; 'Universal gas constant'};
params_const = table(Name, Value, Unit, Description, 'RowNames', Name);
end
