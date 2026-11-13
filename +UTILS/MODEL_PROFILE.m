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
%     known: Lists of known model names
%         fluid_properties: ~ property models of TRANSP.FLPROPS
%         mobility: ~ mobility methods of TRANSP.MOBIL
%         slip_correction: ~ slip correction models of TRANSP.CUNNINGHAM
% ----------------------------------------------------------------------- %

known.fluid_properties = {'sutherland', 'flame', 'room'};
known.mobility = {'continuum', 'interp'};
known.slip_correction = {'kim2005', 'per_caller_7658971'};

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
    case 'article1_7658971'
        if strcmp(stage, 'LD1')
            fluid_properties = 'flame'; % Preset for 1700 K and 101325 Pa
        else
            fluid_properties = 'room'; % Preset for 293.15 K and 101325 Pa
        end
        slip_correction = 'per_caller_7658971'; % Constants of each caller
    otherwise
        error('sootMosaic:MODEL_PROFILE:UnknownProfile', ['Unknown model ', ...
            'profile %s. Known profiles are current and ', ...
            'article1_7658971.'], name)
end

model = struct('profile', name, 'fluid_properties', fluid_properties, ...
    'slip_correction', slip_correction);

end
