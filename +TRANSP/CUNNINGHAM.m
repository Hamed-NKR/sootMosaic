function cc = CUNNINGHAM(d, lambda, model, caller)
% "CUNNINGHAM" calculates the slip (Cunningham) correction factor of...
%     ...particles in a gas.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     d: Particle diameter (m)
%     lambda: Gas mean free path (m)
%     model: Slip correction model, 'kim2005' or 'per_caller_7658971'
%     caller: Calling function, 'MOBIL', 'DIAMOBIL', 'AERODYN' or...
%         ...'TABGEN', needed by 'per_caller_7658971' only
% ----------------------------------------------------------------------- %
%
% Outputs:
%     cc: Slip correction factor (-)
% ----------------------------------------------------------------------- %
%
% 'kim2005' is cc = 1 + Kn (1.165 + 0.483 exp(-0.997 / Kn)) with Kn = 2...
%     ...lambda / d (README reference 7, Eqs. 2 and 34), fitted with the...
%     ...mean free path of 67.3 nm at 296.15 K and 101325 Pa that...
%     ...TRANSP.FLPROPS scales. It is the same in every caller.
% 'per_caller_7658971' keeps the form and constants each caller used at...
%     ...commit 7658971, evaluated in the same order of operations.
%     MOBIL: 1.254, 0.4 and 1.1 with Kn = 2 lambda / d.
%     DIAMOBIL: the 'kim2005' form.
%     AERODYN: the 'kim2005' constants evaluated at Kn = d with d in m,...
%         ...so cc - 1 is below 2e-6 for d up to 1 micrometer.
%     TABGEN: 1 + (2 lambda / d) (1.257 + 0.4 exp(-0.55 d / lambda)) with...
%         ...d in nm and lambda in m as TABGEN passes them, so cc - 1 is...
%         ...below 2e-8 for d from 10 nm.
% ----------------------------------------------------------------------- %

if ~(ischar(model) || isStringScalar(model))
    error('sootMosaic:CUNNINGHAM:UnknownModel', ['The slip correction ', ...
        'model must be kim2005 or per_caller_7658971.'])
end

switch char(model)
    case 'kim2005'
        kn = 2 * lambda ./ d; % Knudsen number (-)
        cc = 1 + kn .* (1.165 + 0.483 * exp(-0.997 ./ kn));

    case 'per_caller_7658971'
        if nargin < 4 || ~(ischar(caller) || isStringScalar(caller))
            caller = '';
        end
        switch char(caller)
            case 'MOBIL'
                kn = 2 * lambda ./ d;
                cc = 1 + kn .* (1.254 + 0.4 * exp(-1.1 ./ kn));
            case 'DIAMOBIL'
                kn = 2 * lambda ./ d;
                cc = 1 + kn .* (1.165 + 0.483 * exp(-0.997 ./ kn));
            case 'AERODYN'
                cc = 1 + d .* (1.165 + 0.483 * exp(-0.997 ./ d));
            case 'TABGEN'
                cc = 1 + (2 * lambda ./ d) .* (1.257 + 0.4 * ...
                    exp(-0.55 * d / lambda));
            otherwise
                error('sootMosaic:CUNNINGHAM:UnknownCaller', ['The ', ...
                    'per_caller_7658971 model needs the caller MOBIL, ', ...
                    'DIAMOBIL, AERODYN or TABGEN.'])
        end

    otherwise
        error('sootMosaic:CUNNINGHAM:UnknownModel', ['Unknown slip ', ...
            'correction model %s. Known models are kim2005 and ', ...
            'per_caller_7658971.'], char(model))
end

end
