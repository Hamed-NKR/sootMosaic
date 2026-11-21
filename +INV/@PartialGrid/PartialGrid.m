classdef PartialGrid < INV.Grid
% "PartialGrid" retains selected whole cells of a rectangular grid.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     full: Full INV.Grid with one or two coordinates
%     keep: Logical mask in the full grid column order (-)
% Outputs:
%     obj: Retained centers, boundaries, widths and adjacency. The edges...
%         ...and nodes refer to the full rectangle; missing lists its gaps
% ----------------------------------------------------------------------- %
% Method: Sipkens et al. (2020, part I, Sec. 2.2).
% Repository: https://github.com/tsipkens/bidias
% Commit: fa318b8c6b48b1b4f28bacb7713aba15ba43d52d
% License: MIT License.
% Code citation: Sipkens et al. (2020), doi:10.17632/sg2zj5yrvr.3.
% Adopted from @PartialGrid/PartialGrid.m.
% Modified 18 Nov 2026: package scope and explicit center mask; whole-cell...
%     ...density bounds replace line cuts and fractional boundary cells....
%     ...Conversions retain multiple columns; plotting methods omitted.
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
        missing = []
        retained = []
    end
    methods
        function obj = PartialGrid(full, keep)
            obj = obj@INV.Grid();
            if ~isa(full, 'INV.Grid') || isa(full, 'INV.PartialGrid') || ...
                    ~islogical(keep) || ~isvector(keep) || ...
                    numel(keep) ~= full.Ne || ~any(keep)
                error('sootMosaic:PartialGrid:Mask', ...
                    'Require a full grid and a nonempty logical cell mask.');
            end
            obj.discrete = full.discrete;
            obj.dim = full.dim;
            obj.span = full.span;
            obj.ne = full.ne;
            obj.edges = full.edges;
            obj.nodes = full.nodes;
            obj.missing = find(~keep(:));
            obj.retained = find(keep(:));
            obj.elements = full.elements(keep, :);
            obj.nelements = full.nelements(keep, :);
            obj.adj = full.adj(keep, keep);
            obj.Ne = nnz(keep);
        end

        function out = partial2full(obj, x)
            if size(x, 1) ~= obj.Ne
                error('sootMosaic:PartialGrid:Shape', 'Require one row per retained cell.');
            end
            out = zeros(prod(obj.ne), size(x, 2));
            out(obj.retained, :) = x;
        end

        function x = full2partial(obj, x)
            if size(x, 1) ~= prod(obj.ne)
                error('sootMosaic:PartialGrid:Shape', 'Require one row per full cell.');
            end
            x = x(obj.retained, :);
        end

        function x = vectorize(obj, x)
            if numel(x) == obj.Ne
                x = x(:);
            elseif numel(x) == prod(obj.ne)
                x = obj.full2partial(x(:));
            else
                error('sootMosaic:PartialGrid:Shape', ...
                    'Require one value per retained or full-grid cell.');
            end
        end

        function x = reshape(obj, x)
            x = obj.partial2full(x);
            sz = obj.ne;
            if obj.dim == 1, sz = [sz, 1]; end
            x = reshape(x, sz);
        end
    end
end
