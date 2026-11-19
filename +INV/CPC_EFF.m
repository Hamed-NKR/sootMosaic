function [eta, info] = CPC_EFF(dm_m, cfg)
% "CPC_EFF" supplies unity efficiency within a sourced mobility bound.
% ----------------------------------------------------------------------- %
% Inputs:
%     dm_m: Mobility diameters, any shape (m)
%     cfg: Resolved configuration with cpc.unity_bound_min_diameter_nm,
%         unity_bound_max_deficit (-) and unity_bound_citation (text)
% Outputs:
%     eta: Unity with the shape of dm_m (-)
%     info: Efficiency deficit bound, citation and lower diameter (m)
% Method: Johnson et al. (2018, Eq. 8); owner Q-N8 point 5.

try
    cpc = cfg.si.cpc;
    start = cpc.unity_bound_min_diameter_nm;
    deficit = cpc.unity_bound_max_deficit;
    citation = cfg.cpc.unity_bound_citation;
    model = cfg.cpc.efficiency_model;
catch
    fail('UncharacterizedEfficiency', ...
        'Unity efficiency requires a sourced bound covering the requested mobility diameters.');
end
if ~strcmp(model, 'unity') || ~isempty(cfg.cpc.efficiency_file)
    fail('InvalidModel', 'This hook implements the unity approximation only.');
end
if ~isnumeric(start) || ~isreal(start) || ~isscalar(start) || ...
        ~isfinite(start) || start <= 0 || ...
        ~isnumeric(deficit) || ~isreal(deficit) || ~isscalar(deficit) || ...
        ~isfinite(deficit) || deficit < 0 || deficit > 1 || ...
        ~ischar(citation) || ~isrow(citation) || isempty(strtrim(citation))
    fail('UncharacterizedEfficiency', ...
        'Unity efficiency requires a sourced bound covering the requested mobility diameters.');
end
if ~isnumeric(dm_m) || ~isreal(dm_m) || isempty(dm_m) || ...
        any(~isfinite(dm_m(:))) || any(dm_m(:) <= 0)
    fail('OutsideRange', 'Diameters must be positive and finite.');
end
if any(dm_m(:) < start)
    fail('UncharacterizedEfficiency', ...
        'Unity efficiency requires a sourced bound covering the requested mobility diameters.');
end
eta = ones(size(dm_m));
info = struct('approximation', true, 'margin_quantified', true, ...
    'unity_margin_ratio', deficit, 'start_m', start, 'citation', citation, ...
    'label', 'Unity counting efficiency with a sourced deficit bound');
end

function fail(reason, message)
error(['sootMosaic:CPC_EFF:' reason], '%s', message);
end
