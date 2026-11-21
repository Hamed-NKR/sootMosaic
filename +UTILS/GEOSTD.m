function gsd = GEOSTD(x, flag, dim)
% "GEOSTD" computes the geometric standard deviation of positive data.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     x: Positive data, vector, matrix or N-D array (-)
%     flag: 1 normalizes by N (default), 0 by N-1, where N is the sample
%         size. The built-in STD uses 0 by default (-)
%     dim: Dimension to operate along, default first non-singleton (-)
% Output:
%     gsd: Geometric standard deviation along dim (-)
% ----------------------------------------------------------------------- %
% Method: Geometric standard deviation of a log-normal sample, the...
%     ...exponential of the standard deviation of the logarithms...
%     ...(Limpert et al., 2001, BioScience 51(5), 341-352).
%
% Example: UTILS.GEOSTD([1.5, 2, 3, 4.5]) returns the value along the...
%     ...first non-singleton dimension with normalization by N.
%
% Zeros give log(0) = -Inf and a NaN result. Class support is the one of...
%     ...LOG, STD and EXP (double and single).

if nargin < 1
    error('geostd:notEnoughInputs', ...
        'This function requires at least one input.');
end
if any(x(:) < 0)
    error('geostd:badData', 'All data values must be positive.');
end

if nargin < 2 || isempty(flag); flag = 1; end

if nargin < 3 || isempty(dim)
    dim = find(size(x) ~= 1, 1);
    if isempty(dim); dim = 1; end
end

% The logarithm of zero is only a step of the calculation, not a warning.
prev = warning('off', 'MATLAB:log:logOfZero');
cleaner = onCleanup(@() warning(prev));

gsd = exp(std(log(x), flag, dim));

end
