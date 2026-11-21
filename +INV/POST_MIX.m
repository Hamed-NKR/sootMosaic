function [center, covariance] = POST_MIX(centers, covariances, weights_1)
% "POST_MIX" combines conditional moments by the law of total variance.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     centers: One conditional center per column, in a common physical unit
%     covariances: One conditional covariance per page, in that unit squared
%     weights_1: Nonnegative component probabilities, normalized here (-)
% Outputs:
%     center: Mixture center in the input unit
%     covariance: Within-component plus between-component covariance
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part II, Eqs. 25-26) for conditional...
%     ...moments; law of total variance for the hyperparameter mixture.
% Reimplementation. For delta statistics the inputs are values and pushed...
%     ...covariances at each constrained mode, not Gaussian state means.
% Kernel draws have equal outer weights; lambda probabilities normalize...
%     ...inside each draw. Shared campaign draws retain joint columns.

if ~isnumeric(centers) || ~isreal(centers) || isempty(centers) || ...
        any(~isfinite(centers(:))) || ~isnumeric(covariances) || ...
        ~isreal(covariances) || any(~isfinite(covariances(:))) || ...
        ~isnumeric(weights_1) || ~isreal(weights_1) || ...
        ~isvector(weights_1) || any(~isfinite(weights_1)) || ...
        any(weights_1 < 0) || sum(weights_1) <= 0
    error('sootMosaic:POST_MIX:Input', ...
        'Require finite moments and positive weight sum.');
end
[n, m] = size(centers);
if numel(weights_1) ~= m || size(covariances, 1) ~= n || ...
        size(covariances, 2) ~= n || size(covariances, 3) ~= m
    error('sootMosaic:POST_MIX:Shape', ...
        'Require one covariance and weight per center.');
end
w = weights_1(:)/sum(weights_1);
center = centers*w;
covariance = zeros(n);
for k = 1:m
    c = covariances(:, :, k);
    if norm(c-c', 'fro') > 1e-10*norm(c, 'fro') || ...
            min(eig((c+c')/2)) < -1e-10*norm(c, 2)
        error('sootMosaic:POST_MIX:Covariance', ...
            'Require symmetric nonnegative covariances.');
    end
    delta = centers(:, k)-center;
    covariance = covariance + w(k)*(c+delta*delta');
end
covariance = (covariance+covariance')/2;
end
