classdef Grid
% "Grid" discretizes one or two coordinates into rectangular cells.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     span_edges: Center spans, one [low high] row per dimension, or a...
%         ...cell of increasing center vectors in the coordinate unit
%     ne: Number of centers per coordinate, at least two (-)
%     discrete: log (default) or linear
% Outputs:
%     obj: Centers in edges, cell boundaries in nodes, vectorized...
%         ...centers in elements, boundaries in nelements and adjacency
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Sec. 2.2).
% Repository: https://github.com/tsipkens/bidias
% Commit: fa318b8c6b48b1b4f28bacb7713aba15ba43d52d
% License: MIT License.
% Code citation: Sipkens et al. (2020), doi:10.17632/sg2zj5yrvr.3.
% Adopted from @Grid/Grid.m.
% Modified 18 Nov 2026: package scope, 1D support, validated coordinates,...
%     ...preallocated adjacency and quadrature; plotting and interpolation...
%     ...methods omitted. The upstream edges name denotes cell centers.
% MIT License
%
% Copyright (c) 2019 Timothy A. Sipkens
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

    properties (SetAccess = protected)
        discrete = 'log'
        dim = 0
        span = []
        ne = []
        Ne = 0
        edges = {}
        nodes = {}
        elements = []
        nelements = []
        adj = []
    end
    methods
        function obj = Grid(span_edges, ne, discrete)
            if nargin == 0, return; end
            if nargin < 3 || isempty(discrete), discrete = 'log'; end
            if strcmp(discrete, 'logarithmic'), discrete = 'log'; end
            if ~any(strcmp(discrete, {'log', 'linear'}))
                error('sootMosaic:Grid:Spacing', 'Use log or linear spacing.');
            end
            obj.discrete = discrete;
            if iscell(span_edges)
                centers = span_edges(:).';
            else
                if nargin < 2 || ~isnumeric(span_edges) || ...
                        ~isreal(span_edges) || size(span_edges, 2) ~= 2 || ...
                        any(~isfinite(span_edges(:))) || ...
                        any(span_edges(:, 2) <= span_edges(:, 1)) || ...
                        ~isnumeric(ne) || ~isreal(ne) || ...
                        numel(ne) ~= size(span_edges, 1) || ...
                        any(~isfinite(ne(:)) | ne(:) < 2 | ne(:) ~= fix(ne(:)))
                    error('sootMosaic:Grid:Span', 'Require spans and cell counts.');
                end
                if strcmp(discrete, 'log') && any(span_edges(:) <= 0)
                    error('sootMosaic:Grid:Span', 'Log coordinates must be positive.');
                end
                centers = cell(1, numel(ne));
                for k = 1:numel(ne)
                    if strcmp(discrete, 'log')
                        centers{k} = logspace(log10(span_edges(k, 1)), ...
                            log10(span_edges(k, 2)), ne(k));
                    else
                        centers{k} = linspace(span_edges(k, 1), ...
                            span_edges(k, 2), ne(k));
                    end
                end
            end
            obj.dim = numel(centers);
            if ~ismember(obj.dim, [1, 2])
                error('sootMosaic:Grid:Dimension', 'Require one or two coordinates.');
            end
            obj.ne = zeros(1, obj.dim);
            obj.span = zeros(obj.dim, 2);
            obj.nodes = cell(1, obj.dim);
            obj.edges = cell(1, obj.dim);
            for k = 1:obj.dim
                c = centers{k};
                if ~isnumeric(c) || ~isreal(c) || ~isvector(c) || ...
                        numel(c) < 2 || any(~isfinite(c)) || any(diff(c) <= 0)
                    error('sootMosaic:Grid:Centers', 'Require increasing finite centers.');
                end
                c = double(c(:).');
                obj.ne(k) = numel(c);
                obj.span(k, :) = c([1, end]);
                obj.edges{k} = c;
                if strcmp(discrete, 'log')
                    if any(c <= 0)
                        error('sootMosaic:Grid:Centers', 'Log centers must be positive.');
                    end
                    c = log10(c);
                end
                mid = (c(1:end-1) + c(2:end))/2;
                bounds = [2*c(1)-mid(1), mid, 2*c(end)-mid(end)];
                if strcmp(discrete, 'log'), bounds = 10.^bounds; end
                obj.nodes{k} = bounds;
            end
            obj.Ne = prod(obj.ne);
            if obj.dim == 1
                obj.elements = obj.edges{1}(:);
                obj.nelements = [obj.nodes{1}(1:end-1).', obj.nodes{1}(2:end).'];
            else
                [a, b] = ndgrid(obj.edges{1}, obj.edges{2});
                obj.elements = [a(:), b(:)];
                [a, b] = ndgrid(obj.nodes{1}(1:end-1), obj.nodes{2}(1:end-1));
                [c, d] = ndgrid(obj.nodes{1}(2:end), obj.nodes{2}(2:end));
                obj.nelements = [a(:), c(:), b(:), d(:)];
            end
            ij = zeros(2*obj.dim*obj.Ne, 2);
            count = 0;
            for j = 1:obj.Ne
                for k = 1:obj.dim
                    stride = prod(obj.ne(1:k-1));
                    sub = mod(floor((j-1)/stride), obj.ne(k)) + 1;
                    if sub < obj.ne(k)
                        ij(count+(1:2), :) = [j, j+stride; j+stride, j];
                        count = count+2;
                    end
                end
            end
            obj.adj = sparse(ij(1:count, 1), ij(1:count, 2), ...
                ones(count, 1), obj.Ne, obj.Ne);
        end

        function [area, w1, w2] = dr(obj)
            % Integrating in log10 coordinates or in linear coordinates
            w = zeros(obj.Ne, obj.dim);
            for k = 1:obj.dim
                b = obj.nelements(:, 2*k-1:2*k);
                if strcmp(obj.discrete, 'log'), b = log10(b); end
                w(:, k) = b(:, 2)-b(:, 1);
            end
            area = prod(w, 2);
            w1 = w(:, 1);
            w2 = ones(obj.Ne, 1);
            if obj.dim == 2, w2 = w(:, 2); end
        end

        function x = reshape(obj, x)
            if numel(x) ~= obj.Ne
                error('sootMosaic:Grid:Shape', 'One value per cell is required.');
            end
            sz = obj.ne;
            if obj.dim == 1, sz = [sz, 1]; end
            x = reshape(x, sz);
        end

        function x = vectorize(obj, x)
            if numel(x) ~= obj.Ne
                error('sootMosaic:Grid:Shape', 'One value per cell is required.');
            end
            x = x(:);
        end

        function out = partial(obj, keep)
            out = INV.PartialGrid(obj, keep);
        end

        function l = l1(obj)
            % Forming one difference per neighboring pair
            [i, j] = find(triu(obj.adj));
            n = numel(i);
            l = sparse([(1:n)'; (1:n)'], [i; j], ...
                [-ones(n, 1); ones(n, 1)], n, obj.Ne);
        end

        function l = l2(obj)
            l = obj.adj - spdiags(sum(obj.adj, 2), 0, obj.Ne, obj.Ne);
        end
    end
end
