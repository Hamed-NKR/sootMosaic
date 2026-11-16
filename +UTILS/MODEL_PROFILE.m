function [model, known] = MODEL_PROFILE(name, stage)
% "MODEL_PROFILE" returns the model options of a named profile for one...
%     ...simulation stage and the model names known to the loaders.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     name: Profile name, 'current' (present default models) or...
%         ...'article1_7658971' (models of commit 7658971, used for the...
%         ...first article)
%     stage: Simulation stage, 'LD1' or 'LD2'
% ----------------------------------------------------------------------- %
%
% Outputs:
%     model: Model options structure, saved with every result
%         profile: Profile name
%         fluid_properties: Property model of TRANSP.FLPROPS
%         slip_correction: Slip correction model of TRANSP.CUNNINGHAM
%         mobility: Mobility method of TRANSP.MOBIL
%         continuum_diameter: Continuum diameter of TRANSP.DIAMOBIL
%         root_solve: Root solve of TRANSP.DIAMOBIL
%         projection: Projected area method of TRANSP.MOBIL
%         proj_cache: Reuse of the areas of unchanged aggregates
%         proj_points: Sampling points per orientation
%         proj_orientations: Orientations per aggregate
%         proj_replicates: Rotated direction sets (isotropic)
%         proj_tol: Largest relative standard error of an isotropic...
%             ...area before a warning (Inf for no check)
%         knudsen_diagnostics: Recording of the pair and...
%             ...nearest-neighbor Knudsen numbers of TRANSP.KNUDSEN
%     known: Lists of known model names
%         fluid_properties: ~ property models of TRANSP.FLPROPS
%         mobility: ~ mobility methods of TRANSP.MOBIL ('continuum' is...
%             ...the earlier name of 'sorensen_eq17')
%         slip_correction: ~ slip correction models of TRANSP.CUNNINGHAM
%         continuum_diameter: ~ continuum diameters of TRANSP.DIAMOBIL
%         root_solve: ~ root solves of TRANSP.DIAMOBIL
%         projection: ~ projected area methods of TRANSP.MOBIL
% ----------------------------------------------------------------------- %

known.fluid_properties = {'sutherland', 'flame', 'room'};
known.mobility = {'sorensen_eq17', 'continuum', 'sorensen_backbone', ...
    'interp', 'free_molecular'};
known.slip_correction = {'kim2005', 'per_caller_7658971'};
known.continuum_diameter = {'sorensen_backbone', 'fixed_075dg'};
known.root_solve = {'bracketed', 'start_point_7658971'};
known.projection = {'isotropic', 'euler_7658971'};

if ~(ischar(name) || isStringScalar(name)) || isempty(name)
    error('sootMosaic:MODEL_PROFILE:UnknownProfile', ...
        'The model profile must be current or article1_7658971.')
end
if ~(ischar(stage) || isStringScalar(stage)) || ...
        ~any(strcmp(char(stage), {'LD1', 'LD2'}))
    error('sootMosaic:MODEL_PROFILE:UnknownStage', ...
        'The simulation stage must be LD1 or LD2.')
end
name = char(name);
stage = char(stage);

% Setting the default models of each profile
switch name
    case 'current'
        fluid_properties = 'sutherland'; % Properties at the fluid T and p
        slip_correction = 'kim2005'; % One slip correction in every caller
        mobility = 'interp'; % Adjusted sphere in both stages
        continuum_diameter = 'sorensen_backbone'; % Eqs. 17, 18a and 18b
        root_solve = 'bracketed'; % Root between the two limits
        projection = 'isotropic'; % Uniform rotations, shifted grid
        proj_cache = true; % Areas of unchanged aggregates reused
        proj_points = 1024; % 32 x 32 grid
        proj_orientations = 64; % Four sets of 16 directions
        proj_replicates = 4;
        proj_tol = 0.01; % Relative standard error of the area
        knudsen_diagnostics = true; % Pair and nearest-neighbor Kn
    case 'article1_7658971'
        if strcmp(stage, 'LD1')
            fluid_properties = 'flame'; % Preset for 1700 K and 101325 Pa
            mobility = 'sorensen_eq17'; % Eq. 17 at every N
        else
            fluid_properties = 'room'; % Preset for 293.15 K and 101325 Pa
            mobility = 'interp'; % Adjusted sphere
        end
        slip_correction = 'per_caller_7658971'; % Constants of each caller
        continuum_diameter = 'fixed_075dg'; % 0.75 dg at every N
        root_solve = 'start_point_7658971'; % fzero from one start point
        projection = 'euler_7658971'; % PAR.PROJECTION at every call
        proj_cache = false;
        proj_points = 100;
        proj_orientations = 5;
        proj_replicates = 1;
        proj_tol = Inf; % No check
        knudsen_diagnostics = false; % No Knudsen diagnostics
    otherwise
        error('sootMosaic:MODEL_PROFILE:UnknownProfile', ['Unknown model ', ...
            'profile %s. Known profiles are current and ', ...
            'article1_7658971.'], name)
end

model = struct('profile', name, 'fluid_properties', fluid_properties, ...
    'slip_correction', slip_correction, 'mobility', mobility, ...
    'continuum_diameter', continuum_diameter, 'root_solve', root_solve, ...
    'projection', projection, 'proj_cache', proj_cache, 'proj_points', ...
    proj_points, 'proj_orientations', proj_orientations, ...
    'proj_replicates', proj_replicates, 'proj_tol', proj_tol, ...
    'knudsen_diagnostics', knudsen_diagnostics);

end
