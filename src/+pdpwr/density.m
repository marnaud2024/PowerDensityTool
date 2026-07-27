function res = density(componentSets, opts)
%DENSITY Combine the chosen components and compute the two analysis views.
%
%   res = pdpwr.density(componentSets, opts)
%
%   componentSets - struct with the chosen components per family, each a table
%                   (or struct array) with at least .PowerW (single-device loss)
%                   and .Volume_cm3 (single-device volume). The multiplier for
%                   family X is given in field X_mult (how many the converter
%                   uses). Fields: .mosfetI .mosfetII .diode .inductor .transformer
%   opts - struct:
%       .P_final   - rated OUTPUT power of the converter [W]
%       .Metric    - 'output' (efficiency / power-density view, depends on
%                    input power) or 'loss' (losses / loss-density view,
%                    independent of input power - the legacy view).
%       For 'output':  .Eff_min [%]   .Dens_min [W/L]
%       For 'loss':    .Loss_max [W]  .LossDens_max [W/L]   (0 = accept any)
%
%   Returns (one entry per ACCEPTED combination):
%     res.eff       efficiency [%]   = (P_out - losses)/P_out  (same formula as
%                                      the original app2; depends on P_out)
%     res.powerDens power density [W/L] = P_out / Volume
%     res.loss      total converter losses [W]                (input-independent)
%     res.lossDens  loss density [W/L]  = losses / Volume     (legacy metric)
%     res.vol       total volume [cm^3]
%     res.idx       [Nx5] indices of (mosfetI, mosfetII, diode, inductor, trafo)
%     res.detail    Nx1 struct array with the chosen component identifiers
%     res.metric    echoes opts.Metric

    if ~isfield(opts, 'Metric'),       opts.Metric = 'output'; end
    if ~isfield(opts, 'Eff_min'),      opts.Eff_min = 0;       end
    if ~isfield(opts, 'Dens_min'),     opts.Dens_min = 0;      end
    if ~isfield(opts, 'Loss_max'),     opts.Loss_max = inf;    end
    if ~isfield(opts, 'LossDens_max'), opts.LossDens_max = inf; end
    isLoss = strcmpi(opts.Metric, 'loss');

    M1 = i_normalize(componentSets, 'mosfetI');
    M2 = i_normalize(componentSets, 'mosfetII');
    D  = i_normalize(componentSets, 'diode');
    L  = i_normalize(componentSets, 'inductor');
    Tr = i_normalize(componentSets, 'transformer');

    n1 = height(M1); n2 = height(M2); nD = height(D); nL = height(L); nT = height(Tr);
    if min([n1 n2 nD nL nT]) == 0
        res = i_empty(opts.Metric); return
    end

    fM1 = M1.Multiplier; fM2 = M2.Multiplier; fDi = D.Multiplier;
    fIn = L.Multiplier;  fTr = Tr.Multiplier;

    % MaxResults caps stored combinations (and the pre-allocation) so the
    % "All combinations" mode does not exhaust memory. inf = no cap.
    if ~isfield(opts, 'MaxResults'), opts.MaxResults = inf; end
    cap = n1 * n2 * nD * nL * nT;
    prealloc = cap;
    if isfinite(opts.MaxResults), prealloc = min(cap, opts.MaxResults); end
    maxN     = opts.MaxResults;
    eff      = zeros(prealloc, 1);
    powerDen = zeros(prealloc, 1);
    lossW    = zeros(prealloc, 1);
    lossDen  = zeros(prealloc, 1);
    volC     = zeros(prealloc, 1);
    idx      = zeros(prealloc, 5);
    detail(prealloc, 1).M1 = '';

    u = 0; stop = false;
    for a = 1:n1
        for b = 1:n2
            for c = 1:nD
                for d = 1:nL
                    for e = 1:nT
                        TotalL = fM1(a)*M1.PowerW(a) + fM2(b)*M2.PowerW(b) ...
                               + fDi(c)*D.PowerW(c)  + fIn(d)*L.PowerW(d) ...
                               + fTr(e)*Tr.PowerW(e);
                        TotalV = fM1(a)*M1.Volume_cm3(a) + fM2(b)*M2.Volume_cm3(b) ...
                               + fDi(c)*D.Volume_cm3(c)  + fIn(d)*L.Volume_cm3(d) ...
                               + fTr(e)*Tr.Volume_cm3(e);
                        if TotalV <= 0 || TotalL <= 0, continue; end

                        % Efficiency uses the SAME formula as the original app2
                        % power-density tab: eta = (P_final - losses)/P_final.
                        % Loss density (TotalL/Vol) is the legacy "Power Density"
                        % Y-axis; power density (P_final/Vol) is the alternative.
                        eta  = (opts.P_final - TotalL) / opts.P_final * 100;
                        pDen = opts.P_final / (TotalV * 0.001);
                        lDen = TotalL       / (TotalV * 0.001);

                        if isLoss
                            if TotalL > opts.Loss_max || lDen > opts.LossDens_max, continue; end
                        else
                            if eta < opts.Eff_min || pDen < opts.Dens_min, continue; end
                        end

                        u = u + 1;
                        eff(u)      = eta;
                        powerDen(u) = pDen;
                        lossW(u)    = TotalL;
                        lossDen(u)  = lDen;
                        volC(u)     = TotalV;
                        idx(u, :)   = [a, b, c, d, e];
                        detail(u).M1 = M1.Identifier(a);
                        detail(u).M2 = M2.Identifier(b);
                        detail(u).D  = D.Identifier(c);
                        detail(u).L  = L.Identifier(d);
                        detail(u).T  = Tr.Identifier(e);
                        if u >= maxN, stop = true; break; end
                    end
                    if stop, break; end
                end
                if stop, break; end
            end
            if stop, break; end
        end
        if stop, break; end
    end

    res = struct( ...
        'eff',      eff(1:u), ...
        'powerDens',powerDen(1:u), ...
        'loss',     lossW(1:u), ...
        'lossDens', lossDen(1:u), ...
        'vol',      volC(1:u), ...
        'idx',      idx(1:u, :), ...
        'detail',   detail(1:u), ...
        'metric',   opts.Metric);
end


function res = i_empty(metric)
    res = struct('eff', [], 'powerDens', [], 'loss', [], 'lossDens', [], ...
        'vol', [], 'idx', [], 'detail', struct([]), 'metric', metric);
end


function tbl = i_normalize(cs, fieldName)
% Coerce the input field into a table with the columns we need
    if ~isfield(cs, fieldName) || isempty(cs.(fieldName))
        tbl = table('Size', [0 4], ...
            'VariableTypes', {'string','double','double','double'}, ...
            'VariableNames', {'Identifier','PowerW','Volume_cm3','Multiplier'});
        return
    end
    src = cs.(fieldName);
    if istable(src)
        tbl = table();
        if ismember('Identifier', src.Properties.VariableNames)
            tbl.Identifier = string(src.Identifier);
        elseif ismember('Mosfet', src.Properties.VariableNames)
            tbl.Identifier = string(src.Mosfet);
        elseif ismember('Diode', src.Properties.VariableNames)
            tbl.Identifier = string(src.Diode);
        elseif ismember('Fabricante', src.Properties.VariableNames)
            tbl.Identifier = string(src.Fabricante);
        else
            tbl.Identifier = string((1:height(src))');
        end
        tbl.PowerW     = src.PowerW;
        if ismember('Volume_cm3', src.Properties.VariableNames)
            tbl.Volume_cm3 = src.Volume_cm3;
        elseif ismember('Vol', src.Properties.VariableNames)
            tbl.Volume_cm3 = src.Vol;
        elseif ismember('VolumeDoTrafoCm3', src.Properties.VariableNames)
            tbl.Volume_cm3 = src.VolumeDoTrafoCm3;
        else
            error('pdpwr:density:noVolume', 'Component %s has no volume column', fieldName);
        end
        if isfield(cs, [fieldName '_mult'])
            mult = cs.([fieldName '_mult']);
        else
            mult = 1;
        end
        tbl.Multiplier = mult * ones(height(tbl), 1);
    else
        % struct array fallback
        tbl = struct2table(src);
        tbl = i_normalize(struct(fieldName, tbl), fieldName);
    end
end
