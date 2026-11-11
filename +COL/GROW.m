function [pars, timetable] = GROW(pars, opts, timetable)
% "GROW" monitors collision of particles and updates the particle...
%     ...structure based on the post-aggregation data.
% ----------------------------------------------------------------------- %
% 
% Input/Output:
%     pars: Particle info structure/class
%     opts.dom_size specifies the optional periodic domain size (3...
%         ...elements, structure input only). When given, collisions are...
%         ...searched between periodic images of the aggregates, so pairs...
%         ...touching across a face of the domain are merged as in the...
%         ...interior.
% ----------------------------------------------------------------------- %

% initialize option input if not given
if ~exist('opts', 'var')
    opts = struct();
end

if (~isfield(opts, 'indupdate')) || isempty(opts.indupdate)
    opts.indupdate = 'on'; % default to update agg indices after collision
end

opts_indupdate = opts.indupdate;

% set default for collision mechanism
if (~isfield(opts, 'col')) || isempty(opts.col)
    opts.col = 'agg'; % default to be aggregation/agglomeration, not coalescense
end

% Periodic domain size, empty for a search without periodic images
if isfield(opts, 'dom_size') && ~isempty(opts.dom_size)
    if (numel(opts.dom_size) ~= 3) || any(~(opts.dom_size(:) > 0)) ||...
            any(~isfinite(opts.dom_size(:)))
        error('sootMosaic:GROW:InvalidDomainSize', ['opts.dom_size must ',...
            'hold three positive finite values.'])
    end
    if isa(pars, 'AGG')
        error('sootMosaic:GROW:DomainSizeAGG', ['opts.dom_size is supported ',...
            'for the particle structure only, not for AGG objects.'])
    end
    dom_size = reshape(opts.dom_size, 1, 3);
else
    dom_size = [];
end

% Total number of (independent) particles
if isa(pars, 'AGG')
    n_par = length(pars);
else
    n_par = size(pars.n, 1);
end

% Compiling/copying properties locally
dmax = cat(1, pars.dmax); % Maximum distance within the aggregates from...
    % ...their center of mass
r = cat(1, pars.r);

% timetable.preoverlap = [timetable.preoverlap; clock];

ind_pairs = nchoosek(1 : n_par, 2); % Making particle pair indices
d_pairs = [dmax(ind_pairs(:,1)), dmax(ind_pairs(:,2))]; % Pair of sizes
r_pairs = [r(ind_pairs(:,1),:), r(ind_pairs(:,2),:)]; % Pair of coordinates

% Moving the second center of each pair to its periodic image nearest to...
    % ...the first one (minimum image convention). Pairs with no shift keep...
    % ...their coordinates exactly.
if ~isempty(dom_size)
    for ax = 1 : 3
        r_pairs(:,3+ax) = r_pairs(:,3+ax) + dom_size(ax) .*...
            round((r_pairs(:,ax) - r_pairs(:,3+ax)) ./ dom_size(ax));
    end
end

% Checking overlapping
ovrs = COL.OVR(r_pairs, d_pairs);

% timetable.postoverlap = [timetable.postoverlap; clock];

% Updating the location of overlapped particles
if any(ovrs == 1)
    
    ind_chk = ind_pairs(ovrs == 1, :); % Indices of colliding pairs
    n_chk = size(ind_chk,1); % Number of colliding pairs
    wrap_img = false; % Whether a pair was merged across a periodic face
    
    for i = 1 : n_chk
        if ind_chk(i,1) ~= ind_chk(i,2)
            
%             timetable.preconnect = [timetable.preconnect; clock];
            % Sticking the two colliding particles
            if isa(pars, 'AGG')
                pp1 = AGG.COMPILEPP(pars(ind_chk(i,1)));
                pp2 = AGG.COMPILEPP(pars(ind_chk(i,2)));
                [pp1, pp2, colstat] = COL.CONNECT(pp1, pp2);
                pars(ind_chk(i,1)).r = pp1(:,3:5);
                pars(ind_chk(i,2)).r = pp2(:,3:5);
            else
                % Periodic images of the second aggregate, nearest to the...
                    % ...first one first. The primaries of the second...
                    % ...aggregate are moved by the box vector of an image...
                    % ...before the primary-level contact search, so the...
                    % ...merged aggregate is contiguous. The first image...
                    % ...that is captured is joined.
                if isempty(dom_size)
                    dr_imgs = [0, 0, 0];
                else
                    dr_imgs = IMAGES(pars.pp{ind_chk(i,1)},...
                        pars.r(ind_chk(i,1),:), pars.pp{ind_chk(i,2)},...
                        pars.r(ind_chk(i,2),:), dom_size);
                end
                for i_img = 1 : size(dr_imgs, 1)
                    pp_img = pars.pp(ind_chk(i,2));
                    if any(dr_imgs(i_img,:) ~= 0)
                        pp_img = PAR.TRANSLATE(pp_img,...
                            pars.r(ind_chk(i,2),:), pars.n(ind_chk(i,2)),...
                            dr_imgs(i_img,:));
                    end
                    [pp1_cnt, pp2_cnt, colstat] = COL.CONNECT(...
                        pars.pp{ind_chk(i,1)}, pp_img{1});
                    if colstat
                        pars.pp{ind_chk(i,1)} = pp1_cnt;
                        pars.pp{ind_chk(i,2)} = pp2_cnt;
                        if any(dr_imgs(i_img,:) ~= 0)
                            wrap_img = true; % Merged center may lie outside
                        end
                        break
                    end
                end
            end
%             timetable.postconnect = [timetable.postconnect; clock];
            
%             % Initializing collision status variable (1 --> collided,...
%                 % ...0 --> uncollided)
%             if ~exist('colstat', 'var'); colstat = 1; end
            
%             timetable.preunite = [timetable.preunite; clock];
            if colstat
                
                % Merging the particles info
                [pars, ind_new] = COL.UNITE(pars, [ind_chk(i,1),...
                    ind_chk(i,2)], opts.col);

                % Updating the general overlap checking indices after...
                    % ...each unification
                for j = 1 : n_chk
                    ind_chk(j,1) = ind_new(find(ind_new(:,1) ==...
                        ind_chk(j,1), 1), 2);
                    ind_chk(j,2) = ind_new(find(ind_new(:,1) ==...
                        ind_chk(j,2), 1), 2);
                end
            end
%             timetable.postunite = [timetable.postunite; clock];
            
        end
    end
    
    % Wrapping centers back into the domain after a merge across a face,...
        % ...centers inside the domain are left unchanged
    if wrap_img
        pars = TRANSP.PBC(dom_size', pars);
    end
    
    if ismember(opts_indupdate, {'ON', 'On', 'on'})
        for k = 1 : length(pars.n)
            pars.pp{k}(:,6) = k;
        end
    end
end


end

function dr_imgs = IMAGES(pp1, r1, pp2, r2, dom_size)
% "IMAGES" lists the periodic shifts of aggregate 2 that can bring it...
%     ...within capture range of aggregate 1, ordered by center distance.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%     pp1, pp2: Primary particle info arrays of the two aggregates
%     r1, r2: Their center of mass locations
%     dom_size: Periodic domain size (1*3)
% ----------------------------------------------------------------------- %
% 
% Output:
%     dr_imgs: Translation vectors of aggregate 2 (N*3), the nearest...
%         ...image first
% ----------------------------------------------------------------------- %

dr_c = r1 - r2; % Center displacement
dr_imgs = dom_size .* round(dr_c ./ dom_size); % Nearest image

% Largest center distance that allows a capture, the two bounding...
    % ...radii plus the capture window of COL.CONNECT (one primary diameter)
reach = max(sqrt(sum((pp1(:,3:5) - r1) .^ 2, 2)) + pp1(:,2) ./ 2) +...
    max(sqrt(sum((pp2(:,3:5) - r2) .^ 2, 2)) + pp2(:,2) ./ 2) +...
    max([pp1(:,2); pp2(:,2)]);

% Only pairs that can reach half the domain or more need further images,...
    % ...all other pairs keep the nearest image alone. The reach can...
    % ...exceed one domain length, so each axis is searched over all...
    % ...image offsets whose residual displacement lies within the reach.
if reach >= min(dom_size) / 2
    e_c = dr_c - dr_imgs; % Residual displacement in the nearest image
    n_lo = min(ceil((e_c - reach) ./ dom_size), 0);
    n_hi = max(floor((e_c + reach) ./ dom_size), 0);
    [o_x, o_y, o_z] = ndgrid(n_lo(1) : n_hi(1), n_lo(2) : n_hi(2),...
        n_lo(3) : n_hi(3));
    o_all = [o_x(:), o_y(:), o_z(:)];
    dr_all = dr_imgs + o_all .* dom_size;
    dist_all = sqrt(sum((dr_c - dr_all) .^ 2, 2));
    dist_all(all(o_all == 0, 2)) = -1; % The nearest image stays first
    [dist_all, ind_srt] = sort(dist_all);
    dr_imgs = dr_all(ind_srt(dist_all <= reach), :);
end

end
