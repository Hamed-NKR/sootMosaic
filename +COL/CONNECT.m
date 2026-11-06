function [pp1, pp2, colstat] = CONNECT(pp1, pp2)
% "CONNECT" joins two approaching aggregates toward the minimum distance...
%   ...between their primaries after checking a sticking criterion.
% ----------------------------------------------------------------------- %
% 
% Inputs/Outputs:
%   pp1: Primary particle info array for aggregate 1
%   pp2: ~ for aggregate 2
%   colstat: Collision status variable (1: collided, 0: not collided)
% ----------------------------------------------------------------------- %

n_pp1 = size(pp1, 1); % Number of primary particles within aggregate 1
n_pp2 = size(pp2, 1); % ~ aggregate 2
pp1_temp = repelem(pp1, n_pp2, 1);
pp2_temp = repmat(pp2, n_pp1, 1);

dist_pp = sqrt(sum((pp1_temp(:,3:5) - pp2_temp(:,3:5)).^2, 2)) -...
    (pp1_temp(:,2) + pp2_temp(:,2)) ./ 2; % List of distances of primary...
        % ...particle centers
ind_cnt = find(dist_pp == min(dist_pp), 1); % Finding pairs with minimum...
    % ...distance
if dist_pp(ind_cnt) <= max(pp1_temp(ind_cnt,2), pp2_temp(ind_cnt,2))
    colstat = 1;
    ind_cnt = [ind_cnt, pp1_temp(ind_cnt,1), pp2_temp(ind_cnt,1)];
        % Adding the index numbers of the nearest pair in the...
            % ...overlapping matrix
    ind_cnt = [ind_cnt, find(pp1(:,1) == ind_cnt(2)),...
        find(pp2(:,1) == ind_cnt(3))]; % Adding the actual indices of...
            % ...primaries
    
    % Moving the aggregates to the point-touching status
    dr = pp2(ind_cnt(5), 3:5) - pp1(ind_cnt(4), 3:5);
    norm_dr = sqrt(sum(dr.^2, 2));
    dr1 = dr ./ 2 - pp1(ind_cnt(4), 2) .* dr ./ (2 .* norm_dr);
    dr2 = - dr ./ 2 + pp2(ind_cnt(5), 2) .* dr ./ (2 .* norm_dr);
    pp1(:, 3:5) = pp1(:, 3:5) + repmat(dr1, n_pp1, 1);
    pp2(:, 3:5) = pp2(:, 3:5) + repmat(dr2, n_pp2, 1);

    % Backing off along the contact axis while other primary pairs still...
        % ...overlap, which only happens for an interpenetrating start, so...
        % ...a start with no overlap is left exactly as before. Pair (i,j)...
        % ...overlaps for relative translations t in (t_lo, t_hi), the...
        % ...roots of |s_ij + t e| = (d_i + d_j) / 2, and the smallest...
        % ...t >= 0 outside all these intervals, within the round-off...
        % ...margin, is reached by jumping to the largest t_hi among the...
        % ...intervals that contain t. As in the move above, the selected...
        % ...pair must not have coincident centers.
    if dist_pp(ind_cnt(1)) < 0
        e_dr = dr ./ norm_dr; % Unit vector of the contact axis
        s_pp = repmat(pp2(:,3:5), n_pp1, 1) - repelem(pp1(:,3:5), n_pp2, 1);
            % Center-to-center vectors of all cross pairs after the move
        b_pp = s_pp * e_dr';
        sq_pp = sqrt(max(b_pp.^2 - sum(s_pp.^2, 2) +...
            ((pp1_temp(:,2) + pp2_temp(:,2)) ./ 2).^2, 0));
        t_lo = - b_pp - sq_pp;
        t_hi = - b_pp + sq_pp;
        tol_t = 1e-13 * max(pp1_temp(:,2) + pp2_temp(:,2)); % Round-off margin
        t_bo = 0;
        ind_ovr = (t_lo < t_bo - tol_t) & (t_hi > t_bo + tol_t);
        while any(ind_ovr)
            t_bo = max(t_hi(ind_ovr));
            ind_ovr = (t_lo < t_bo - tol_t) & (t_hi > t_bo + tol_t);
        end
        if t_bo > 0
            pp1(:, 3:5) = pp1(:, 3:5) - repmat(t_bo .* e_dr ./ 2, n_pp1, 1);
            pp2(:, 3:5) = pp2(:, 3:5) + repmat(t_bo .* e_dr ./ 2, n_pp2, 1);
        end
    end
else
    colstat = 0;
end

end
