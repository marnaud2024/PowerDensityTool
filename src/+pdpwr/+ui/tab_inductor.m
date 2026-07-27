function ctx = tab_inductor(app)
%TAB_INDUCTOR Inductor design sweep tab.

    L = pdpwr.ui.layout();
    tab = uitab(app.TabGroup, 'Title', 'Inductor');
    ctx.tab = tab;

    panel = uipanel(tab, 'Title', 'Project Parameters', 'FontWeight','bold', ...
        'Position', [L.inputPanel.x L.inputPanel.y L.inputPanel.w L.inputPanel.h]);
    rows = i_fieldList();
    ctx.spinners = struct();
    yTop = L.inputPanel.h - 30;
    for k = 1:numel(rows)
        f = rows(k);
        y = yTop - k * (L.spinnerRowHeight + L.spinnerRowSpacing);
        s = pdpwr.ui.spinner_row(panel, 10, y, f.label, f.default, ...
            'Limits', f.limits, 'Step', f.step);
        ctx.spinners.(f.name) = s;
    end
    yLast = yTop - (numel(rows)+1) * (L.spinnerRowHeight + L.spinnerRowSpacing);
    tutH = 140;
    tutY = max(12, yLast - tutH);
    uilabel(panel, 'Position', [10, tutY+tutH, 360, 18], ...
        'Text', 'How to use the Inductor tab', 'FontWeight','bold', 'FontColor',[0.2 0.4 0.7]);
    uitextarea(panel, 'Position', [10, tutY, 360, tutH], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontSize', 10, ...
        'Value', { ...
            '1. Set the project parameters above.', ...
            '2. Click "Calculate" to sweep ALL materials (Magnetics + Magmattec), the same way the MOSFET tab sweeps every device. Each material gets its own colour in the chart.', ...
            '3. Tick materials in the tree and click "Filter / Plot" to keep only those; the chart and table update (and clear if nothing matches).', ...
            'Note: Inductor Voltage is the voltage ACROSS the filter inductor (tens to hundreds of V), not the dc bus.'});

    % Material tree (wide column on the right)
    uilabel(tab, 'Position', [L.treeWideLabel.x L.treeWideLabel.y L.treeWideLabel.w L.treeWideLabel.h], ...
        'Text', 'Material selection (Magnetics + Magmattec)', ...
        'FontWeight','bold', 'FontSize', 11);
    ctx.materialTree = uitree(tab, 'checkbox', ...
        'Position', [L.treeWide.x L.treeWide.y L.treeWide.w L.treeWide.h]);
    rootMag = uitreenode(ctx.materialTree, 'Text', 'Magnetics', 'NodeData', 'MagneticsRoot');
    for m = {'Kool Mu','KoolMu'; 'MPP','MPP'; 'High Flux','HighFlux'; ...
             'XFlux','XFlux'; 'Kool Mu MAX','KoolMuMAX'; 'Kool Mu Hf','KoolMuHf'; ...
             'Edge','Edge'}'
        uitreenode(rootMag, 'Text', m{1}, 'NodeData', m{2});
    end
    rootMmt = uitreenode(ctx.materialTree, 'Text', 'Magmattec', 'NodeData', 'MagmattecRoot');
    for code = {'002','026','034','052'}
        uitreenode(rootMmt, 'Text', sprintf('MMT %s', code{1}), 'NodeData', ['MMT' code{1}]);
    end
    expand(ctx.materialTree);

    ctx.ax = uiaxes(tab, 'Position', [L.plot.x L.plot.y L.plot.w L.plot.h]);
    title(ctx.ax, 'Inductor designs - Volume x Losses');
    xlabel(ctx.ax, 'Volume [cm^3]'); ylabel(ctx.ax, 'Losses [W]');
    grid(ctx.ax, 'on');

    ctx.calcButton = uibutton(tab, 'push', ...
        'Position', [L.calcButton.x L.calcButton.y L.calcButton.w L.calcButton.h], ...
        'Text', 'Calculate');
    ctx.graphButton = uibutton(tab, 'push', ...
        'Position', [L.graphButton.x L.graphButton.y L.graphButton.w L.graphButton.h], ...
        'Text', 'Filter / Plot', 'Enable', 'off');
    % How many points to plot: ALL valid designs, or just the best per core.
    uilabel(tab, 'Position', [716, 170, 40, 22], 'Text', 'Show:', 'FontWeight','bold');
    ctx.showDropdown = uidropdown(tab, 'Position', [756, 168, 122, 26], ...
        'Items', {'All designs','Best per core'}, 'Value', 'All designs');
    ctx.statusLabel = uilabel(tab, ...
        'Position', [884, L.statusLabel.y, 286, L.statusLabel.h], ...
        'Text', 'Status: Idle');

    ctx.tableCols = {'Material','Core ID','mu','N','Nparal','Volume [cm3]','Losses [W]','Ku','DeltaT [C]','fs [kHz]','Stacks'};
    ctx.table = uitable(tab, ...
        'Position', [L.table.x L.table.y L.table.w L.table.h], ...
        'ColumnName', ctx.tableCols, ...
        'Data', cell(0, numel(ctx.tableCols)));

    % ctx complete - assign callbacks now.
    ctx.calcButton.ButtonPushedFcn  = @(~,~) i_on_calculate(app, ctx);
    ctx.graphButton.ButtonPushedFcn = @(~,~) i_on_filter(app, ctx);
end


function f = i_fieldList()
    f = struct( ...
        'name',    {'Vd','ILmed','fs_min','fs_max','IL_min','IL_max','J_min','J_max', ...
                    'kumin','kumax','dTmax','Tamb','AWG','stacks','MaxLoss','MaxVol'}, ...
        'label',   { ...
            'Inductor Voltage (V)', 'Average Current (A)', ...
            'Min Switching Freq (kHz)', 'Max Switching Freq (kHz)', ...
            'Min Ripple Fraction', 'Max Ripple Fraction', ...
            'Min Current Density (A/cm2)', 'Max Current Density (A/cm2)', ...
            'Min Window Util (Ku)', 'Max Window Util (Ku)', ...
            'Max Temp Rise (C)', 'Ambient Temperature (C)', ...
            'Wire Gauge AWG', 'Max Stacks', ...
            'Max Losses (W)', 'Max Volume (cm3)'}, ...
        'default', {300, 14, 40, 60, 0.1, 0.25, 250, 500, 0.05, 0.5, 80, 55, 16, 1, 200, 3000}, ...
        'limits',  {[0 5000],[0 1000],[1 500],[1 500],[0 1],[0 1],[50 1000],[50 1000], ...
                    [0 1],[0 1],[10 200],[-40 80],[10 44],[1 5],[10 5000],[100 50000]}, ...
        'step',    {10, 1, 1, 1, 0.05, 0.05, 10, 10, 0.05, 0.05, 5, 1, 1, 1, 10, 100});
end


function i_on_calculate(app, ctx)
    s = ctx.spinners;
    if s.fs_min.Value >= s.fs_max.Value
        uialert(app.UIFigure,'Min frequency must be < max frequency','Invalid range'); return
    end
    if s.IL_min.Value >= s.IL_max.Value
        uialert(app.UIFigure,'Min ripple must be < max ripple','Invalid range'); return
    end

    ctx.calcButton.Enable = 'off';
    ctx.graphButton.Enable = 'off';
    ctx.statusLabel.Text = 'Status: Loading cores...';
    pd = uiprogressdlg(app.UIFigure, 'Title','Inductor sweep', ...
        'Message','Loading cores...','Indeterminate','off');

    try
        wire = pdpwr.util.awg_props(s.AWG.Value, app.Catalog.awg);
        D = struct( ...
            'Vd', s.Vd.Value, 'ILmed', s.ILmed.Value, 'kumin', s.kumin.Value, ...
            'kumax', s.kumax.Value, 'DeltaTmax', s.dTmax.Value, ...
            'J_min', s.J_min.Value, 'J_max', s.J_max.Value, ...
            'temp_ambiente', s.Tamb.Value, ...
            'r_awg', wire.r_ohm_m, 'Aawg', wire.A_cm2, 'Dextawg', wire.D_cm, ...
            'MaxLoss', s.MaxLoss.Value, 'MaxVol', s.MaxVol.Value);

        % Same pattern as MOSFET/Diode: CALCULATE sweeps EVERY material in the
        % catalog (the tree is NOT read here). The material tree is applied
        % later by the "Filter / Plot" button. This keeps a single consistent
        % workflow across all tabs.
        allMaterials = i_allMaterials();
        allCores = {};
        skipped = 0;
        for t = 1:numel(allMaterials)
            tag = allMaterials{t};
            cores = i_coresForMaterial(app.Catalog, tag, s.stacks.Value);
            for c = 1:numel(cores)
                if i_isBadCore(cores(c))
                    skipped = skipped + 1;
                    continue
                end
                cores(c).MaterialTag = tag;
                allCores{end+1} = cores(c); %#ok<AGROW>
            end
        end
        nCores = numel(allCores);
        if nCores == 0
            uialert(app.UIFigure,'No valid cores found in catalog for the selected materials.','Catalog empty');
            try, close(pd); catch, end
            try, ctx.calcButton.Enable = 'on'; catch, end
            return
        end

        fs_vec     = (s.fs_min.Value:10:s.fs_max.Value) * 1000;
        ripple_vec = s.IL_min.Value:0.05:s.IL_max.Value;
        J_vec      = s.J_min.Value:50:s.J_max.Value;
        nInner = numel(fs_vec) * numel(ripple_vec) * numel(J_vec);
        totalEvals = nCores * nInner;
        ctx.statusLabel.Text = sprintf('Status: %d cores x %d ops = %d evaluations (%d cores skipped: bad data)', ...
            nCores, nInner, totalEvals, skipped);
        if totalEvals > 400000
            sel = uiconfirm(app.UIFigure, ...
                sprintf(['Going to evaluate %d combinations.\n' ...
                         'This may take a minute. Tip: widen the J / ripple\n' ...
                         'steps or narrow the frequency range to reduce it.\n\nContinue?'], totalEvals), ...
                'Heavy sweep','Options',{'Continue','Cancel'},'DefaultOption','Continue');
            if strcmp(sel,'Cancel')
                try, close(pd); catch, end
                try, ctx.calcButton.Enable = 'on'; catch, end
                return
            end
        end

        designs = cell(1,0);
        evalCount = 0;
        reasons = containers.Map('KeyType','char','ValueType','double');
        for cIdx = 1:nCores
            core = allCores{cIdx};
            for fs = fs_vec
                for ripple = ripple_vec
                    for J = J_vec
                        D.fs      = fs;
                        D.DeltaIL = ripple * D.ILmed;
                        D.IL_max  = D.DeltaIL;
                        D.L       = D.Vd / (4 * fs * D.DeltaIL);
                        D.ILef    = D.ILmed * sqrt(1 + (D.DeltaIL/D.ILmed)^2 / 12);
                        D.J       = J;
                        try
                            proj = pdpwr.design.inductor(D, core);
                        catch
                            proj = struct('N', NaN, 'reason', 'error');
                        end
                        evalCount = evalCount + 1;
                        if ~isnan(proj.N)
                            proj.MaterialTag = core.MaterialTag;
                            designs{end+1} = proj; %#ok<AGROW>
                        elseif isfield(proj, 'reason')
                            if isKey(reasons, proj.reason)
                                reasons(proj.reason) = reasons(proj.reason) + 1;
                            else
                                reasons(proj.reason) = 1;
                            end
                        end
                    end
                end
            end
            if mod(cIdx, max(1, floor(nCores/50))) == 0
                try
                    pd.Value = min(0.95, 0.05 + 0.9*cIdx/nCores);
                    pd.Message = sprintf('Core %d / %d  -  valid so far: %d', cIdx, nCores, numel(designs));
                catch
                end
                drawnow limitrate
            end
        end

        if isempty(designs)
            reasonStr = i_formatReasons(reasons);
            ctx.statusLabel.Text = sprintf('Status: 0 valid / %d. %s', evalCount, strrep(reasonStr, newline, '  '));
            uialert(app.UIFigure, sprintf( ...
                ['No valid design out of %d combinations.\n\n' ...
                 'Rejection breakdown:\n%s\n\n' ...
                 'Adjust based on the dominant reason:\n' ...
                 '  Ku>kumax        -> raise Max Window Util OR bigger cores\n' ...
                 '  mu_rolloff<30   -> core saturates: lower current, raise mu_r,\n' ...
                 '                     or raise ripple (lowers required L)\n' ...
                 '  DeltaT>max      -> raise Max Temp Rise\n' ...
                 '  Ptotal>MaxLoss / Vol>MaxVol -> relax those caps'], ...
                 evalCount, reasonStr), 'No designs');
            try, close(pd); catch, end
            try, ctx.calcButton.Enable = 'on'; catch, end
            return
        end

        try, pd.Value = 0.96; pd.Message = 'Sorting and rendering...'; catch, end
        designsArr = [designs{:}];
        [~, order] = sort([designsArr.Ptotal]);
        designsArr = designsArr(order);
        app.set_results('inductor', struct('records', designsArr));

        % Show ALL valid designs (default) or just the best of each core.
        [shown, capMsg] = i_applyShow(designsArr, ctx.showDropdown.Value);
        ctx.statusLabel.Text = sprintf('Status: %d valid / %d eval (%.1f%%)%s', ...
            numel(designsArr), evalCount, 100*numel(designsArr)/evalCount, capMsg);

        i_drawScatter(ctx.ax, shown, 'all');
        i_fillTable(ctx, shown);
        ctx.graphButton.Enable = 'on';

        pdpwr.util.save_table(i_toTable(designsArr), 'inductor_designs');   % full set -> xlsx+csv
        try, pd.Value = 1.0; catch, end
        pause(0.1);
    catch ME
        try, uialert(app.UIFigure, ME.message, 'Inductor sweep failed'); catch, end
        try, ctx.statusLabel.Text = sprintf('Error: %s', ME.message); catch, end
    end
    try, close(pd); catch, end
    try, ctx.calcButton.Enable = 'on'; catch, end
end


function i_on_filter(app, ctx)
    res = app.get_results('inductor');
    if isempty(res) || isempty(res.records)
        uialert(app.UIFigure,'Click "Calculate" first.','No data'); return
    end
    designsArr = res.records;
    checked = i_collectChecked(ctx.materialTree);
    if isempty(checked)
        uialert(app.UIFigure,'Tick at least one material in the tree to filter.','No filter'); return
    end
    mask = false(1, numel(designsArr));
    for i = 1:numel(designsArr)
        mask(i) = any(strcmp(designsArr(i).MaterialTag, checked));
    end
    kept = designsArr(mask);
    if isempty(kept)
        % Clear the chart and table so the empty result is explicit.
        cla(ctx.ax); ctx.table.Data = cell(0, numel(ctx.tableCols));
        ctx.statusLabel.Text = 'Status: 0 designs match the selected materials';
        uialert(app.UIFigure,'No design with the selected materials.','Filter empty'); return
    end
    [shown, capMsg] = i_applyShow(kept, ctx.showDropdown.Value);
    i_drawScatter(ctx.ax, shown, 'filtered');
    i_fillTable(ctx, shown);
    ctx.statusLabel.Text = sprintf('Status: %d designs match%s', numel(kept), capMsg);
    kept = shown;

    pdpwr.util.save_table(i_toTable(kept), 'inductor_designs_filtered');
end


function i_drawScatter(ax, designs, mode)
    cla(ax);
    hold(ax,'on');
    tags = unique({designs.MaterialTag});
    colors = lines(numel(tags));
    for t = 1:numel(tags)
        idx = strcmp({designs.MaterialTag}, tags{t});
        sub = designs(idx);
        sc = scatter(ax, [sub.Vol], [sub.Ptotal], 35, ...
            'MarkerEdgeColor', colors(t,:), 'DisplayName', i_matLabel(tags{t}));
        sc.DataTipTemplate.DataTipRows(1).Label = 'Vol[cm3]';
        sc.DataTipTemplate.DataTipRows(2).Label = 'Loss[W]';
        % Compact datatip (full detail is in the table below).
        extra = [ ...
            dataTipTextRow('Mat',  {sub.MaterialTag}); ...
            dataTipTextRow('Core', {sub.ID}); ...
            dataTipTextRow('mu',   [sub.mi]); ...
            dataTipTextRow('N',    [sub.N]); ...
            dataTipTextRow('Ku',   [sub.Ku]); ...
            dataTipTextRow('fkHz', [sub.fs]/1000) ];
        sc.DataTipTemplate.DataTipRows(end+1:end+numel(extra)) = extra;
    end
    legend(ax,'Location','best');
    hold(ax,'off');
    if strcmp(mode,'filtered')
        title(ax, sprintf('Inductor designs (filtered, %d)', numel(designs)));
    else
        title(ax, sprintf('Inductor designs (%d)', numel(designs)));
    end
end


function i_fillTable(ctx, designs)
    data = cell(numel(designs), numel(ctx.tableCols));
    for i = 1:numel(designs)
        d = designs(i);
        data(i,:) = {d.MaterialTag, d.ID, d.mi, d.N, d.Nparal, d.Vol, d.Ptotal, d.Ku, d.DeltaT, d.fs/1000, d.Stacks};
    end
    ctx.table.Data = data;
end


function best = i_bestPerCore(designsArr)
    % Keep only the lowest-loss design of each distinct core
    % (key = Material|CoreID|Stacks). Designs already sorted by Ptotal asc,
    % so the FIRST time a key appears it is already the best for that core.
    seen = containers.Map('KeyType','char','ValueType','logical');
    keep = false(1, numel(designsArr));
    for i = 1:numel(designsArr)
        d = designsArr(i);
        key = sprintf('%s|%s|%d', d.MaterialTag, i_asChar(d.ID), d.Stacks);
        if ~isKey(seen, key)
            seen(key) = true;
            keep(i) = true;
        end
    end
    best = designsArr(keep);
end


function [shown, capMsg] = i_applyShow(designsArr, mode)
% Choose which designs to plot/table: ALL of them (default) or the best of each
% distinct core. "All" is capped at ALL_CAP points (lowest-loss kept) so a very
% large sweep never freezes the chart/table.
    ALL_CAP = 15000;
    if startsWith(mode, 'Best')
        shown = i_bestPerCore(designsArr);
        capMsg = sprintf(' (best of each of %d cores)', numel(shown));
    else
        shown = designsArr;
        if numel(shown) > ALL_CAP
            [~, o] = sort([shown.Ptotal]);
            shown = shown(o(1:ALL_CAP));
            capMsg = sprintf(' (all; %d lowest-loss of %d plotted)', ALL_CAP, numel(designsArr));
        else
            capMsg = sprintf(' (all %d shown)', numel(shown));
        end
    end
end


function T = i_toTable(designs)
    n = numel(designs);
    M = struct( ...
        'Material',    {{designs.MaterialTag}'}, ...
        'CoreID',      {{designs.ID}'}, ...
        'mu',          {[designs.mi]'}, ...
        'N',           {[designs.N]'}, ...
        'Nparal',      {[designs.Nparal]'}, ...
        'Volume_cm3',  {[designs.Vol]'}, ...
        'Losses_W',    {[designs.Ptotal]'}, ...
        'Ku',          {[designs.Ku]'}, ...
        'DeltaT_C',    {[designs.DeltaT]'}, ...
        'fs_kHz',      {[designs.fs]'/1000}, ...
        'Stacks',      {[designs.Stacks]'});
    T = struct2table(M);
    T = T(1:n, :);
end


function str = i_formatReasons(reasons)
    if isempty(reasons) || reasons.Count == 0
        str = '  (no reasons recorded)'; return
    end
    keys = reasons.keys;
    counts = cellfun(@(k) reasons(k), keys);
    [counts, order] = sort(counts, 'descend');
    keys = keys(order);
    lines = cell(1, numel(keys));
    for i = 1:numel(keys)
        lines{i} = sprintf('  %-16s : %d', keys{i}, counts(i));
    end
    str = strjoin(lines, newline);
end


function tf = i_isBadCore(c)
% Returns true if any of the essential geometry fields is NaN / non-positive.
    if isnan(c.le_mm) || c.le_mm <= 0,   tf = true; return; end
    if isnan(c.Ae_mm2) || c.Ae_mm2 <= 0, tf = true; return; end
    if isnan(c.Vol_mm3) || c.Vol_mm3 <= 0, tf = true; return; end
    if isnan(c.OD_mm) || c.OD_mm <= 0,   tf = true; return; end
    if isnan(c.ID_mm) || c.ID_mm <= 0,   tf = true; return; end
    if isnan(c.HT_mm) || c.HT_mm <= 0,   tf = true; return; end
    if isnan(c.mi_rel) || c.mi_rel <= 0, tf = true; return; end
    tf = false;
end


function cores = i_coresForMaterial(catalog, tag, maxStacks)
    cores = repmat(i_emptyCore(), 0, 1);
    isMagmattec = startsWith(tag, 'MMT');
    if isMagmattec
        materialCode = extractAfter(tag, 'MMT');
        rows = catalog.magmattec(strcmp(catalog.magmattec.Material, ['MMT' materialCode]), :);
        for i = 1:height(rows)
            for st = 1:maxStacks
                c = i_emptyCore();
                c.id = i_asChar(rows.Product(i));
                c.mi_rel = i_magmattecMu(materialCode);
                c.AL0_nHesp2 = rows.AL_nHesp2(i);
                c.le_mm  = rows.Le_mm(i);
                c.Ae_mm2 = rows.Ae_mm2(i);
                c.Vol_mm3 = rows.Ve_mm3(i) * st;
                c.OD_mm = rows.OD_mm(i);
                c.ID_mm = rows.ID_mm(i);
                c.HT_mm = rows.HT_mm(i) * st;
                c.stacks = st;
                c.pcore_fn = @(fs_kHz, Bpk_G) pdpwr.loss.pcore_magmattec(materialCode, fs_kHz, Bpk_G);
                cores(end+1,1) = c; %#ok<AGROW>
            end
        end
    else
        materialName = i_magneticsName(tag);
        rows = catalog.magnetics(strcmp(catalog.magnetics.Material, materialName), :);
        for i = 1:height(rows)
            for st = 1:maxStacks
                c = i_emptyCore();
                c.id = i_asChar(rows.PartNumber(i));
                c.mi_rel = rows.Permeability(i);
                c.le_mm  = rows.Le_mm(i);
                c.Ae_mm2 = rows.Ae_mm2(i);
                c.Vol_mm3 = rows.Ve_mm3(i) * st;
                c.OD_mm = rows.OD_mm(i);
                c.ID_mm = rows.ID_mm(i);
                c.HT_mm = rows.HT_mm(i) * st;
                c.stacks = st;
                % Per-material, per-permeability curve-fit coefficients so each
                % material uses its OWN core-loss and roll-off curve. Legacy
                % hardcoded MPP-40 for all -> made every material near-identical.
                k = i_curveFitCoeffs(catalog, materialName, rows.Permeability(i));
                c.mi_a = k(1); c.mi_b = k(2); c.mi_c = k(3);
                c.P_a  = k(4); c.P_b  = k(5); c.P_c  = k(6);
                cores(end+1,1) = c; %#ok<AGROW>
            end
        end
    end
end


function k = i_curveFitCoeffs(catalog, materialName, permeability)
% Returns [mi_a mi_b mi_c P_a P_b P_c] for (materialName, permeability),
% matching the exact permeability or the nearest one for that material.
% Falls back to the legacy MPP-40 fit only if the material is absent.
    k = [0.01, 2.702e-8, 2.511, 146.94, 2.103, 1.357];   % legacy MPP-40 fallback
    if ~isfield(catalog, 'curvefit') || isempty(catalog.curvefit), return; end
    T = catalog.curvefit;
    sel = strcmp(string(T.Material), materialName);
    if ~any(sel), return; end
    sub = T(sel, :);
    [~, idx] = min(abs(sub.Permeability - permeability));   % nearest permeability
    k = [sub.mi_a(idx), sub.mi_b(idx), sub.mi_c(idx), ...
         sub.P_a(idx),  sub.P_b(idx),  sub.P_c(idx)];
end


function lbl = i_matLabel(tag)
% Human-readable legend label for an inductor material tag.
    switch char(string(tag))
        case 'KoolMu',    lbl = 'Kool Mu';
        case 'MPP',       lbl = 'MPP';
        case 'HighFlux',  lbl = 'High Flux';
        case 'XFlux',     lbl = 'XFlux';
        case 'KoolMuMAX', lbl = 'Kool Mu MAX';
        case 'KoolMuHf',  lbl = 'Kool Mu Hf';
        case 'Edge',      lbl = 'Edge';
        otherwise
            t = char(string(tag));
            if startsWith(t, 'MMT')
                lbl = ['MMT ' extractAfter(t, 'MMT')];   % MMT052 -> MMT 052
            else
                lbl = t;
            end
    end
end


function mats = i_allMaterials()
% Every material the inductor sweep evaluates (Magnetics + Magmattec).
    mats = {'KoolMu','MPP','HighFlux','XFlux','KoolMuMAX','KoolMuHf','Edge', ...
            'MMT002','MMT026','MMT034','MMT052'};
end


function n = i_magneticsName(tag)
    switch tag
        case 'KoolMu',    n = 'Kool Mu';
        case 'MPP',       n = 'MPP';
        case 'HighFlux',  n = 'High Flux';
        case 'XFlux',     n = 'XFlux';
        case 'KoolMuMAX', n = 'Kool Mu MAX';
        case 'KoolMuHf',  n = 'Kool Mu Hf';
        case 'Edge',      n = 'Edge';
        otherwise,        n = tag;
    end
end


function mu = i_magmattecMu(code)
    switch code
        case '002', mu = 10;
        case '026', mu = 75;
        case '034', mu = 33;
        case '052', mu = 75;
        otherwise,  mu = 50;
    end
end


function c = i_emptyCore()
    c = struct('id','','mi_rel',NaN,'le_mm',NaN,'Ae_mm2',NaN,'Vol_mm3',NaN, ...
               'OD_mm',NaN,'ID_mm',NaN,'HT_mm',NaN,'stacks',1, ...
               'AL0_nHesp2',[],'pcore_fn',[], ...
               'P_a',NaN,'P_b',NaN,'P_c',NaN, ...
               'mi_a',NaN,'mi_b',NaN,'mi_c',NaN, ...
               'MaterialTag','');
end


function ids = i_collectChecked(tree)
    nodes = tree.CheckedNodes;
    ids = cell(1,0);
    for n = 1:numel(nodes)
        nd = char(nodes(n).NodeData);
        if endsWith(nd,'Root'), continue; end
        ids{end+1} = nd; %#ok<AGROW>
    end
end


function s = i_asChar(v)
    if istable(v), v = v{1,1}; end
    if iscell(v),       v = v{1};        end
    if isstring(v),     s = char(v);     return; end
    if isnumeric(v) || islogical(v), s = num2str(v); return; end   % numeric id -> "9928", not char(9928)
    s = char(v);
end


function r = i_root()
    r = pdpwr.util.data_root();   % source tree OR ctfroot (compiled .exe)
end
