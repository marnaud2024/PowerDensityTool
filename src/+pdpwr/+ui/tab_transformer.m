function ctx = tab_transformer(app)
%TAB_TRANSFORMER Transformer design sweep tab.

    L = pdpwr.ui.layout();
    tab = uitab(app.TabGroup, 'Title', 'Transformer');
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
    tutH = 116;
    tutY = max(12, yLast - tutH);
    uilabel(panel, 'Position', [10, tutY+tutH, 360, 18], ...
        'Text', 'How to use the Transformer tab', 'FontWeight','bold', 'FontColor',[0.2 0.4 0.7]);
    uitextarea(panel, 'Position', [10, tutY, 360, tutH], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontSize', 10, ...
        'Value', { ...
            '1. Set parameters. "Faraday Constant (k)" is the k in Np = Vd*1e4/(k*Bm*fs*Ae): 4=square wave, 4.44=sine, 9=this 3-level inverter.', ...
            '2. Click Calculate to sweep ALL materials (R/P/F/T via Steinmetz; TDK N.. via neural net; 139). Each material is a colour.', ...
            '3. Tick materials + "Filter / Plot" to keep only those. If all are rejected, the popup shows WHY (Ku, DeltaT, Volume...).'});

    uilabel(tab, 'Position', [L.treeWideLabel.x L.treeWideLabel.y L.treeWideLabel.w L.treeWideLabel.h], ...
        'Text', 'Material selection', 'FontWeight','bold', 'FontSize', 11);
    ctx.materialTree = uitree(tab, 'checkbox', ...
        'Position', [L.treeWide.x L.treeWide.y L.treeWide.w L.treeWide.h]);
    rootMag = uitreenode(ctx.materialTree, 'Text', 'Magnetics', 'NodeData', 'MagRoot');
    for m = {'R','P','F','T'}
        uitreenode(rootMag, 'Text', m{1}, 'NodeData', m{1});
    end
    rootTDK = uitreenode(ctx.materialTree, 'Text', 'TDK (neural net)', 'NodeData', 'TDKRoot');
    for m = {'N27','N41','N49','N72','N87','N92','N95','N97'}
        uitreenode(rootTDK, 'Text', m{1}, 'NodeData', m{1});
    end
    rootMag2 = uitreenode(ctx.materialTree, 'Text', 'Other', 'NodeData', 'OtherRoot');
    uitreenode(rootMag2, 'Text', '139', 'NodeData', '139');
    expand(ctx.materialTree);

    ctx.ax = uiaxes(tab, 'Position', [L.plot.x L.plot.y L.plot.w L.plot.h]);
    title(ctx.ax, 'Transformer designs - Volume x Losses');
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

    ctx.tableCols = {'Material','Core','Geometry','Parallel','Np','Ns','Volume [cm3]', ...
                     'Pcore [W]','Pcond [W]','Ptotal [W]','DeltaT [C]','Bm [T]','Ku'};
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
        'name', {'Vd','Vo','n','Ipef','fs','kFaraday','Parallel','Bmin','Bmax','Bstep', ...
                 'Jmin','Jmax','Jstep','AWG','Tamb','DeltaTmax','kumin','kumax','Pmax','Vmax'}, ...
        'label',{ ...
            'Primary DC Voltage (V)','Output Voltage (V)','Turns Ratio (Ns/Np)','Primary RMS Current (A)', ...
            'Switching Frequency (Hz)','Faraday Constant (k)','Max Cores in Parallel','Min Peak B (T)','Max Peak B (T)', ...
            'B Increment (T)','Min Current Density (A/cm2)','Max Current Density (A/cm2)', ...
            'J Increment (A/cm2)','Wire Gauge AWG','Ambient Temperature (C)','Max Temp Rise (C)', ...
            'Min Window Util (Ku)','Max Window Util (Ku)','Max Losses (W)','Max Volume (cm3)'}, ...
        'default',{600,920,1.2,5,50000,9,2,0.05,0.30,0.05,250,500,50,16,55,80,0.05,0.6,200,3000}, ...
        'limits', {[0 5000],[0 5000],[0.01 50],[0 1000],[1000 1e6],[0.1 100],[1 10], ...
                   [0.01 0.5],[0.01 0.5],[0.01 0.2],[50 1000],[50 1000],[10 200],[10 44],[-40 80], ...
                   [10 200],[0 1],[0 1],[10 5000],[10 50000]}, ...
        'step',   {10,10,0.05,1,1000,0.5,1,0.01,0.01,0.01,10,10,10,1,1,5,0.05,0.05,10,10});
end


function i_on_calculate(app, ctx)
    ctx.calcButton.Enable = 'off';
    ctx.graphButton.Enable = 'off';
    ctx.statusLabel.Text = 'Status: Loading...';
    pd = uiprogressdlg(app.UIFigure, 'Title','Transformer sweep', ...
        'Message','Loading...','Indeterminate','off');

    warnStateA = warning('off', 'MATLAB:integral:MinStepSize');
    warnStateB = warning('off', 'MATLAB:integral:NonFiniteValue');
    cleanup = onCleanup(@() warning([warnStateA warnStateB])); %#ok<NASGU>

    try
        s = ctx.spinners;
        wire = pdpwr.util.awg_props(s.AWG.Value, app.Catalog.awg);
        try
            net = pdpwr.util.load_neural_net();
            net.materialIndex = struct('R',1,'P',2,'F',3,'T',4, ...
                'N27',5,'N41',6,'N49',7,'N72',8,'N87',9, ...
                'N92',10,'N95',11,'N97',12,'M139',13);
            netAvailable = true;
        catch
            netAvailable = false;
            net = [];
        end

        % Same pattern as MOSFET/Diode: CALCULATE sweeps EVERY material; the
        % tree is applied later by "Filter / Plot".
        allMats = i_allMaterials();

        D = i_buildDataStruct(s, wire);
        designs = {};
        nProjects = 0;
        reasons = containers.Map('KeyType','char','ValueType','double');

        for matIdx = 1:numel(allMats)
            mat = allMats{matIdx};
            stein = i_steinmetzRow(app.Catalog.steinmetz, mat);
            if isempty(stein), continue; end
            isTDK = any(strcmp(mat,{'N27','N41','N49','N72','N87','N92','N95','N97'}));
            if isTDK && ~netAvailable, continue; end

            opts = struct('gseEnabled', false);
            if isTDK
                opts.neuralNet = net;
                opts.neuralNet.materialIdx = net.materialIndex.(mat);
            end
            cores = i_coresForMaterial(app.Catalog.trafos, mat, s.Parallel.Value);
            nCores = numel(cores);
            for c = 1:nCores
                for Bm = s.Bmin.Value:s.Bstep.Value:s.Bmax.Value
                    for J = s.Jmin.Value:s.Jstep.Value:s.Jmax.Value
                        D.Bm = Bm; D.J = J;
                        try
                            proj = pdpwr.design.transformer(D, cores(c), stein, opts);
                        catch
                            proj = struct('Np', NaN, 'reason', 'error');
                        end
                        nProjects = nProjects + 1;
                        if ~isnan(proj.Np)
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
                if mod(c, max(1, floor(nCores/30))) == 0
                    try
                        pd.Value = min(0.85, 0.1 + 0.8*((matIdx-1)/numel(allMats) + c/(nCores*numel(allMats))));
                        pd.Message = sprintf('%s: core %d/%d, valid so far: %d', mat, c, nCores, numel(designs));
                    catch
                    end
                end
            end
            drawnow limitrate
        end

        if isempty(designs)
            reasonStr = i_formatReasons(reasons);
            uialert(app.UIFigure, sprintf(['All %d candidates rejected.\n\n' ...
                'Rejection breakdown:\n%s\n\n' ...
                'Use the dominant reason above to adjust:\n' ...
                '  Ku>kumax -> raise Max Window Util OR use bigger cores\n' ...
                '  Ku<kumin -> lower Min Window Util OR smaller cores\n' ...
                '  Vol>Vmax -> raise Max Volume\n' ...
                '  DeltaT>max -> raise Max Temp Rise\n' ...
                '  Ptrafo>Pmax -> raise Max Losses'], nProjects, reasonStr), 'No designs');
            ctx.statusLabel.Text = sprintf('Status: 0 valid / %d. %s', nProjects, strrep(reasonStr, newline, '  '));
            try, close(pd); catch, end; try, ctx.calcButton.Enable='on'; catch, end; return
        end

        try, pd.Value = 0.96; pd.Message = 'Sorting and rendering...'; catch, end
        designsArr = [designs{:}];
        [~, order] = sort([designsArr.Ptrafo]);
        designsArr = designsArr(order);
        app.set_results('transformer', struct('records', designsArr));

        % Show ALL valid designs (default) or just the best of each core.
        [shown, capMsg] = i_applyShow(designsArr, ctx.showDropdown.Value);
        ctx.statusLabel.Text = sprintf('Status: %d valid / %d (%.1f%%)%s', ...
            numel(designsArr), nProjects, 100*numel(designsArr)/nProjects, capMsg);

        i_drawScatter(ctx.ax, shown, 'all');
        i_fillTable(ctx, shown);
        ctx.graphButton.Enable = 'on';

        pdpwr.util.save_table(i_toTable(designsArr), 'transformer_designs');   % full set -> xlsx+csv

        try, pd.Value=1.0; catch, end
        pause(0.1);
    catch ME
        try, uialert(app.UIFigure, ME.message, 'Transformer sweep failed'); catch, end
        try, ctx.statusLabel.Text = sprintf('Error: %s', ME.message); catch, end
    end
    try, close(pd); catch, end
    try, ctx.calcButton.Enable='on'; catch, end
end


function i_on_filter(app, ctx)
    res = app.get_results('transformer');
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
        mask(i) = any(strcmp(designsArr(i).Material, checked));
    end
    kept = designsArr(mask);
    if isempty(kept)
        cla(ctx.ax); ctx.table.Data = cell(0, numel(ctx.tableCols));
        ctx.statusLabel.Text = 'Status: 0 designs match the selected materials';
        uialert(app.UIFigure,'No design with the selected materials.','Filter empty'); return
    end
    % Narrow the cached set to the selected materials, so the Power Density tab
    % combines only what is shown here. Click Calculate to bring every material back.
    app.set_results('transformer', struct('records', kept));
    [shown, capMsg] = i_applyShow(kept, ctx.showDropdown.Value);
    i_drawScatter(ctx.ax, shown, 'filtered');
    i_fillTable(ctx, shown);
    ctx.statusLabel.Text = sprintf('Status: %d designs match%s', numel(kept), capMsg);
    kept = shown;

    pdpwr.util.save_table(i_toTable(kept), 'transformer_designs_filtered');
end


function i_drawScatter(ax, designs, mode)
    cla(ax); hold(ax,'on');
    mats = unique({designs.Material});
    colors = lines(numel(mats));
    for t = 1:numel(mats)
        idx = strcmp({designs.Material}, mats{t});
        sub = designs(idx);
        sc = scatter(ax, [sub.VolTotal], [sub.Ptrafo], 35, ...
            'MarkerEdgeColor', colors(t,:), 'DisplayName', i_matLabel(mats{t}));
        sc.DataTipTemplate.DataTipRows(1).Label = 'Vol[cm3]';
        sc.DataTipTemplate.DataTipRows(2).Label = 'Loss[W]';
        % Compact datatip (full detail is in the table below).
        extra = [ ...
            dataTipTextRow('Mat',  {sub.Material}); ...
            dataTipTextRow('Core', {sub.Size}); ...
            dataTipTextRow('Geom', {sub.Geometry}); ...
            dataTipTextRow('Np',   [sub.Np]); ...
            dataTipTextRow('Ns',   [sub.Ns]); ...
            dataTipTextRow('Bm[T]',[sub.Bm]); ...
            dataTipTextRow('Ku',   [sub.Ku]) ];
        sc.DataTipTemplate.DataTipRows(end+1:end+numel(extra)) = extra;
    end
    legend(ax,'Location','best');
    hold(ax,'off');
    if strcmp(mode,'filtered')
        title(ax, sprintf('Transformer designs (filtered, %d)', numel(designs)));
    else
        title(ax, sprintf('Transformer designs (%d)', numel(designs)));
    end
end


function i_fillTable(ctx, designs)
    data = cell(numel(designs), numel(ctx.tableCols));
    for i = 1:numel(designs)
        d = designs(i);
        data(i,:) = {d.Material, d.Size, d.Geometry, d.ParallelCores, d.Np, d.Ns, ...
                     d.VolTotal, d.PnucleoSE, d.Pcond, d.Ptrafo, d.DeltaT, d.Bm, d.Ku};
    end
    ctx.table.Data = data;
end


function T = i_toTable(designs)
    M = struct( ...
        'Material', {{designs.Material}'}, ...
        'Core',     {{designs.Size}'}, ...
        'Geometry', {{designs.Geometry}'}, ...
        'ParallelCores', {[designs.ParallelCores]'}, ...
        'Np', {[designs.Np]'}, 'Ns', {[designs.Ns]'}, ...
        'VolumeCm3', {[designs.VolTotal]'}, ...
        'PcoreW',    {[designs.PnucleoSE]'}, ...
        'PcondW',    {[designs.Pcond]'}, ...
        'PtotalW',   {[designs.Ptrafo]'}, ...
        'DeltaTC',   {[designs.DeltaT]'}, ...
        'BmT',       {[designs.Bm]'}, ...
        'Ku',        {[designs.Ku]'});
    T = struct2table(M);
end


function lbl = i_matLabel(code)
% Human-readable legend label for a transformer material code (the raw codes
% R/P/F/T/N../139 look cryptic in the colour legend).
    code = char(string(code));
    if any(strcmp(code, {'R','P','F','T'}))
        lbl = ['Magnetics ' code];
    elseif startsWith(code, 'N')
        lbl = ['TDK ' code];
    elseif strcmp(code, '139')
        lbl = 'Magmattec 139';
    else
        lbl = code;
    end
end


function best = i_bestPerCore(designsArr)
    % Keep only the lowest-loss design of each distinct core
    % (key = Material|Core|ParallelCores). designsArr is sorted by Ptrafo asc,
    % so the first occurrence of each key is already its best design.
    seen = containers.Map('KeyType','char','ValueType','logical');
    keep = false(1, numel(designsArr));
    for i = 1:numel(designsArr)
        d = designsArr(i);
        key = sprintf('%s|%s|%d', d.Material, i_asChar(d.Size), d.ParallelCores);
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
            [~, o] = sort([shown.Ptrafo]);
            shown = shown(o(1:ALL_CAP));
            capMsg = sprintf(' (all; %d lowest-loss of %d plotted)', ALL_CAP, numel(designsArr));
        else
            capMsg = sprintf(' (all %d shown)', numel(shown));
        end
    end
end


function mats = i_allMaterials()
% Every transformer material the sweep evaluates.
    mats = {'R','P','F','T','N27','N41','N49','N72','N87','N92','N95','N97','139'};
end


function str = i_formatReasons(reasons)
% Turn the rejection-reason Map into a sorted "reason : count" multiline string.
    if isempty(reasons) || reasons.Count == 0
        str = '  (no reasons recorded)';
        return
    end
    keys = reasons.keys;
    counts = cellfun(@(k) reasons(k), keys);
    [counts, order] = sort(counts, 'descend');
    keys = keys(order);
    lines = cell(1, numel(keys));
    for i = 1:numel(keys)
        lines{i} = sprintf('  %-12s : %d', keys{i}, counts(i));
    end
    str = strjoin(lines, newline);
end


function D = i_buildDataStruct(s, wire)
    D = struct();
    D.Vd = s.Vd.Value; D.Vo = s.Vo.Value; D.n = s.n.Value;
    D.Ipef = s.Ipef.Value; D.Isef = D.Ipef / D.n;
    D.fs = s.fs.Value; D.Ts = 1/D.fs;
    D.kFaraday = s.kFaraday.Value;   % k in Np = Vd*1e4/(k*Bm*fs*Ae) (user-set)
    D.kumin = s.kumin.Value; D.kumax = s.kumax.Value;
    D.DeltaTmax = s.DeltaTmax.Value; D.T = s.Tamb.Value;
    D.Dfio = wire.D_cm; D.Afio = wire.A_cm2;
    D.Rfio = wire.r_ohm_m * 1e-2;
    D.Rcfio = D.Rfio * (1 + 0.0038*(D.T - 20));
    D.D = D.Vo / (2 * D.Vd * D.n);
    D.D2 = 1 - D.D;
    D.Pnucleomax = s.Pmax.Value; D.Vmax = s.Vmax.Value;
end


function cores = i_coresForMaterial(trafoTable, material, parallelMax)
    rows = trafoTable(strcmp(string(trafoTable.Material), material), :);
    cores = repmat(i_emptyCore(), 0, 1);
    for i = 1:height(rows)
        for p = 1:parallelMax
            c = i_emptyCore();
            c.partNumber   = i_asChar(rows.PartNumber(i));
            c.geometry     = i_asChar(rows.Geometry(i));
            if isempty(c.partNumber) || strcmpi(c.partNumber,'NaN')
                % Some ALL-MODELS cores have no catalogue part number; build a
                % readable label from geometry + effective area instead of "NaN".
                c.partNumber = sprintf('%s-Ae%.2f', c.geometry, rows.Ae_mm2(i)*0.01);
            end
            c.manufacturer = i_asChar(rows.Manufacturer(i));
            c.parallel     = p;
            c.Ae_cm2 = rows.Ae_mm2(i) * 0.01 * p;
            c.Ve_cm3 = rows.Ve_mm3(i) * 0.001 * p;
            c.Ap_cm4 = rows.WaAc_cm4(i) * p;
            c.OD_cm  = rows.OD_mm(i) * 0.1;
            c.ID_cm  = rows.ID_mm(i) * 0.1;
            c.H_cm   = rows.Height_mm(i) * 0.1 * p;
            c.Length_cm    = rows.Length_mm(i) * 0.1;
            c.LegLength_cm = rows.LegLength_mm(i) * 0.1;
            cores(end+1,1) = c; %#ok<AGROW>
        end
    end
end


function stein = i_steinmetzRow(steinmetzTable, material)
    % string() keeps matching robust whether the Material column was read as
    % text or numeric (the '139' Magmattec id reads as a number from Excel).
    idx = find(strcmp(string(steinmetzTable.Material), material), 1);
    if isempty(idx), stein = []; return; end
    stein = table2struct(steinmetzTable(idx,:));
end


function c = i_emptyCore()
    c = struct('partNumber','','manufacturer','','geometry','','parallel',1, ...
               'Ae_cm2',NaN,'Ve_cm3',NaN,'Ap_cm4',NaN,'OD_cm',NaN,'ID_cm',NaN, ...
               'H_cm',NaN,'Length_cm',NaN,'LegLength_cm',NaN);
end


function ids = i_collectChecked(tree)
    nodes = tree.CheckedNodes;
    ids = cell(1,0);
    for n = 1:numel(nodes)
        nd = char(nodes(n).NodeData);
        if endsWith(nd,'Root') || strcmp(nd,'OtherRoot'), continue; end
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
