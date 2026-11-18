function [value, report] = CONFIG_DATA_RULE(code, sources, opts)
% "CONFIG_DATA_RULE" selects a value and reports source differences.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     code: D, D>C, C, C~D, R, P, W>D>C or X
%     sources: Structure with optional data, config, campaign, registry,...
%         ...profile and derived values, all in the same units. A missing...
%         ...field or [] means unavailable; zero and false are values
%     opts: Optional structure with Path (empty), AbsTol (0), RelTol (0)...
%         ...and Reason (empty). A campaign value requires a nonempty reason
% ----------------------------------------------------------------------- %
%
% Outputs:
%     value: Selected value. D requires data; D>C falls back to config;...
%         ...C and C~D require config; R requires registry; P requires...
%         ...profile; W>D>C selects campaign, data, then config; X requires...
%         ...a derived value and refuses a configured value
%     report: Path, code, source, value, from_config, reason, tolerance and...
%         ...comparisons. Each comparison records both sources and values,...
%         ...their difference and whether it exceeds the tolerance
% ----------------------------------------------------------------------- %
%
% Numeric differences use abs(a-b) > max(AbsTol, RelTol*abs(b)), with b...
%     ...the configured expectation, or the lower-precedence value for a...
%     ...campaign comparison. Shapes must agree. Text and logical values...
%     ...use exact equality. D ignores config, including any mismatch,...
%     ...without comparison or warning. D>C compares data with config when...
%     ...both exist; C~D compares config with data. W>D>C reports every pair...
%     ...and warns for differences beyond tolerance. Missing sources stop.
% ----------------------------------------------------------------------- %

if nargin < 3, opts = struct(); end
if ~isstruct(opts) || ~isscalar(opts)
    error('sootMosaic:CONFIG_DATA_RULE:InvalidInput', ...
        'Rule options must be a scalar structure.');
end
path = option(opts, 'Path', '');
abs_tol = option(opts, 'AbsTol', 0);
rel_tol = option(opts, 'RelTol', 0);
reason = option(opts, 'Reason', '');
if ~isstruct(sources) || ~isscalar(sources) || ...
        ~tolerance(abs_tol) || ~tolerance(rel_tol)
    error('sootMosaic:CONFIG_DATA_RULE:InvalidInput', ...
        'Sources must be an object and tolerances finite nonnegative scalars.');
end
switch char(code)
    case 'D'
        order = {'data'};
    case 'D>C'
        order = {'data', 'config'};
    case {'C', 'C~D'}
        order = {'config'};
    case 'R'
        order = {'registry'};
    case 'P'
        order = {'profile'};
    case 'W>D>C'
        order = {'campaign', 'data', 'config'};
    case 'X'
        if available(sources, 'config')
            error('sootMosaic:CONFIG_DATA_RULE:ConfiguredDerived', ...
                'Derived quantity %s cannot be configured.', path);
        end
        order = {'derived'};
    otherwise
        error('sootMosaic:CONFIG_DATA_RULE:UnknownCode', ...
            'Unknown data rule %s for %s.', char(code), path);
end
selected = '';
for k = 1:numel(order)
    if available(sources, order{k}), selected = order{k}; break; end
end
if isempty(selected)
    error('sootMosaic:CONFIG_DATA_RULE:MissingValue', ...
        'No source supplies %s under rule %s.', path, char(code));
end
if strcmp(selected, 'campaign') && ...
        ~(ischar(reason) && isrow(reason) && ~isempty(strtrim(reason)))
    error('sootMosaic:CONFIG_DATA_RULE:MissingReason', ...
        'Campaign value for %s requires a reason.', path);
end
value = sources.(selected);
if isnumeric(value) && (~isreal(value) || any(~isfinite(value(:))))
    error('sootMosaic:CONFIG_DATA_RULE:Nonfinite', ...
        'Selected value for %s must be finite and real.', path);
end
comparisons = struct('source_a', {}, 'source_b', {}, 'value_a', {}, ...
    'value_b', {}, 'difference', {}, 'limit', {}, 'different', {}, ...
    'exceeds_tolerance', {});
pairs = cell(0, 2);
if any(strcmp(code, {'D>C', 'C~D'}))
    pairs = {'data', 'config'};
elseif strcmp(code, 'W>D>C')
    pairs = {'campaign', 'data'; 'campaign', 'config'; 'data', 'config'};
end
for k = 1:size(pairs, 1)
    a = pairs{k, 1};
    b = pairs{k, 2};
    if ~available(sources, a) || ~available(sources, b), continue; end
    va = sources.(a);
    vb = sources.(b);
    different = ~isequaln(va, vb);
    if isnumeric(va) && isnumeric(vb) && isequal(size(va), size(vb))
        if ~isreal(va) || ~isreal(vb) || ...
                any(~isfinite(va(:))) || any(~isfinite(vb(:)))
            error('sootMosaic:CONFIG_DATA_RULE:Nonfinite', ...
                'Compared values for %s must be finite and real.', path);
        end
        delta = abs(va - vb);
        limit = max(abs_tol, rel_tol * abs(vb));
        exceeds = any(delta(:) > limit(:));
    else
        delta = [];
        limit = [];
        exceeds = different;
    end
    comparisons(end + 1, 1) = struct('source_a', a, 'source_b', b, ...
        'value_a', {va}, 'value_b', {vb}, 'difference', delta, ...
        'limit', limit, 'different', different, ...
        'exceeds_tolerance', exceeds); %#ok<AGROW>
    if exceeds
        warning('sootMosaic:CONFIG_DATA_RULE:Mismatch', ...
            '%s differs between %s and %s; rule %s selects %s.', ...
            path, a, b, char(code), selected);
    end
end
report = struct('path', path, 'code', char(code), 'source', selected, ...
    'value', {value}, 'from_config', strcmp(selected, 'config'), ...
    'reason', reason, 'abs_tol', abs_tol, 'rel_tol', rel_tol, ...
    'comparisons', comparisons);
end

function yes = available(sources, name)
yes = isfield(sources, name) && ~isempty(sources.(name));
end

function yes = tolerance(value)
yes = isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && value >= 0;
end

function value = option(opts, key, fallback)
if isfield(opts, key), value = opts.(key); else, value = fallback; end
end
