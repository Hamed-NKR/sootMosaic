function result = STAT_RESPONSE(jacobian, resolution_1, weights_1)
% "STAT_RESPONSE" evaluates a statistic's linear response diagnostics.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     jacobian: One statistic derivative per row in its reporting scale
%     resolution_1: Resolution matrix per lambda node (-)
%     weights_1: Nonnegative node probabilities, normalized here (-)
% Outputs:
%     result: Averaging kernels, gain and squared cosine, diagnostics only
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eq. 26), posterior precision.
% Reimplementation. Gain and cosine are constructed from the...
%     ...averaging kernel (config/main_inv/DEFAULTS.md, section 13), not...
%     ...taken from that paper. Each...
%     ...Jacobian belongs to the complete statistic, including denominators.

if nargin < 3, weights_1 = ones(size(resolution_1, 3), 1); end
n = size(jacobian, 2);
if ~isnumeric(jacobian) || ~isreal(jacobian) || isempty(jacobian) || ...
        any(~isfinite(jacobian(:))) || ~isnumeric(resolution_1) || ...
        ~isreal(resolution_1) || size(resolution_1, 1) ~= n || ...
        size(resolution_1, 2) ~= n || any(~isfinite(resolution_1(:))) || ...
        ~isnumeric(weights_1) || ~isreal(weights_1) || ...
        numel(weights_1) ~= size(resolution_1, 3) || ...
        any(~isfinite(weights_1(:)) | weights_1(:) < 0) || ...
        sum(weights_1(:)) <= 0
    error('sootMosaic:STAT_RESPONSE:Input', ...
        'Require finite Jacobians, square responses and node weights.');
end
w = weights_1(:)/sum(weights_1(:));
r = zeros(n);
for k = 1:numel(w)
    r = r + w(k)*resolution_1(:, :, k);
end
kernel = jacobian*r;
length2 = sum(jacobian.^2, 2);
along = sum(kernel.*jacobian, 2);
response2 = sum(kernel.^2, 2);
gain = NaN(size(length2));
cosine = gain;
valid = length2 > 0;
gain(valid) = along(valid)./length2(valid);
valid = valid & response2 > 0;
cosine(valid) = along(valid).^2./(length2(valid).*response2(valid));
result = struct('kernel', kernel, 'gain_1', gain, ...
    'cosine_1', cosine, 'resolved_direction_1', valid, ...
    'diagnostic_only_1', true);
end
