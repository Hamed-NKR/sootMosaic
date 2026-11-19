function result = LAMBDA_XCHECK(a, b, l, lambda_cm3)
% "LAMBDA_XCHECK" evaluates three regularization checks on a supplied grid.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     a, b: Kernel and column observation whitened using OBS_VARIANCE
%     l: Full-column-rank dimensionless prior operator (-)
%     lambda_cm3: Positive increasing penalty scales, at least 3 (cm^3)
% Outputs:
%     result: Grid, residual, prior, GCV and signed curvature curves;...
%         ...selected scales (cm^3), with NaN for an undefined choice
% ----------------------------------------------------------------------- %
% Method: Golub et al. (1979), generalized cross-validation;
%     ...Hansen (2000), log residual versus log prior curvature;
%     ...Groetsch (1984, Eq. 3.3.3), discrepancy principle.
% Reimplementation from the published methods specified in design 48.
% Choices use the unconstrained linear smoother and never replace evidence.
% D6 also needs changes of reported statistics and is completed by DIAGNOSE.

if ~isnumeric(a) || ~isreal(a) || ~ismatrix(a) || isempty(a) || ...
        any(~isfinite(a(:))) || ~isnumeric(b) || ~isreal(b) || ...
        ~isequal(size(b), [size(a, 1), 1]) || any(~isfinite(b)) || ...
        ~isnumeric(l) || ~isreal(l) || ~ismatrix(l) || ...
        size(l, 2) ~= size(a, 2) || size(l, 1) < size(l, 2) || ...
        any(~isfinite(l(:))) || ~isnumeric(lambda_cm3) || ...
        ~isreal(lambda_cm3) || ~isvector(lambda_cm3) || ...
        numel(lambda_cm3) < 3 || any(~isfinite(lambda_cm3)) || ...
        any(lambda_cm3 <= 0) || any(diff(lambda_cm3(:)) <= 0)
    error('sootMosaic:LAMBDA_XCHECK:Input', ...
        'Require compatible finite arrays and an increasing scale grid.');
end
a = double(a); b = double(b); l = double(l);
[~, r] = qr(full(l), 0);
if rcond(r) <= eps
    error('sootMosaic:LAMBDA_XCHECK:Prior', 'Require a proper prior.');
end
[u, s, ~] = svd(full(a/r), 'econ');
k = min(size(a));
s = diag(s(1:k, 1:k));
u = u(:, 1:k);
y = u'*b;
orthogonal = norm(b-u*y)^2;
if k == size(a, 1), orthogonal = 0; end
lambda_cm3 = double(lambda_cm3(:));
n = numel(lambda_cm3);
residual = zeros(n, 1);
prior = zeros(n, 1);
gcv = zeros(n, 1);
curvature = NaN(n, 1);
m = size(a, 1);
logs = zeros(k+(m > k), 1);
if m > k, logs(end) = log(m-k); end
for j = 1:n
    lambda = lambda_cm3(j);
    h = hypot(s, lambda);
    f = (s./h).^2;
    g = (lambda./h).^2;
    residual(j) = orthogonal + sum((g.*y).^2);
    prior(j) = sum(((s./h).*(y./h)).^2);
    % Normalizing residual filters before squaring for GCV
    d = log(s)-log(lambda);
    logg = -2*max(d, 0)-log1p(exp(-2*abs(d)));
    logs(1:k) = logg;
    peak = max(logs);
    logt = peak+log(sum(exp(logs-peak)));
    gcv(j) = m*sum((exp(logg-logt).*y).^2);
    if orthogonal > 0
        gcv(j) = gcv(j)+m*exp(log(orthogonal)-2*logt);
    end
    % Differentiating with respect to log lambda for the signed corner
    gp = 2*f.*g;
    gpp = 4*f.*g.*(f-g);
    rp = 2*sum(g.*gp.*y.^2);
    rpp = 2*sum((gp.^2+g.*gpp).*y.^2);
    terms = ((s./h).*(y./h)).^2;
    pp = sum(-4*g.*terms);
    ppp = sum((16*g.^2-8*f.*g).*terms);
    if residual(j) > 0 && prior(j) > 0
        dx = rp/(2*residual(j));
        dy = pp/(2*prior(j));
        ddx = (rpp/residual(j)-(rp/residual(j))^2)/2;
        ddy = (ppp/prior(j)-(pp/prior(j))^2)/2;
        speed = hypot(dx, dy);
        if speed > 0
            curvature(j) = (dy*ddx-dx*ddy)/speed^3;
        end
    end
end
[~, ig] = min(gcv);
if all(~isfinite(gcv)), lg = NaN; else, lg = lambda_cm3(ig); end
eligible = find(isfinite(curvature) & curvature > 0);
eligible = eligible(eligible > 1 & eligible < n);
lc = NaN;
if ~isempty(eligible)
    [~, ic] = max(curvature(eligible));
    lc = lambda_cm3(eligible(ic));
end
id = find(residual <= m, 1, 'last');
ld = NaN;
if ~isempty(id), ld = lambda_cm3(id); end
result = struct('lambda_cm3', lambda_cm3, 'residual2_1', residual, ...
    'prior2_cm6_inv', prior, 'gcv_1', gcv, 'curvature_1', curvature, ...
    'gcv_lambda_cm3', lg, 'lcurve_lambda_cm3', lc, ...
    'discrepancy_lambda_cm3', ld, ...
    'discrepancy_bracketed_1', ~isempty(id) && id < n, ...
    'gcv_edge_1', ig == 1 || ig == n);
end
