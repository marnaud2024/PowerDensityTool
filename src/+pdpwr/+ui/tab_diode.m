function ctx = tab_diode(app)
%TAB_DIODE Diode tab.

    L = pdpwr.ui.layout();
    tab = uitab(app.TabGroup, 'Title', 'Diode');
    ctx.tab = tab;

    panel = uipanel(tab, 'Title', 'Calculation Parameters', 'FontWeight','bold', ...
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
    tutY = yLast - 90;
    uilabel(panel, 'Position', [10, tutY+72, 360, 18], ...
        'Text', 'How to use the Diode tab', 'FontWeight','bold', 'FontColor',[0.2 0.4 0.7]);
    uitextarea(panel, 'Position', [10, tutY, 360, 72], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontSize', 10, ...
        'Value', { ...
            '1. Set operating conditions in the spinners above.', ...
            '2. Click "Calculate" - loops over all 138 diodes in catalog.', ...
            '3. Tick filters in the four trees on the right.', ...
            '4. Click "Filter / Plot" to refine + export to output/.'});

    ctx.producerTree    = i_buildTree(tab, L.tree1, L.tree1Label, 'Device Producer', 'ProducerRoot', ...
        {'WolfSpeed','WolfSpeed'; 'GeneSiC','Genesic'; 'Other','OtherPM'});
    ctx.packageTree     = i_buildTree(tab, L.tree2, L.tree2Label, 'Package', 'PackageRoot', ...
        {'TO-252-2','TO2522'; 'TO-220-2','TO2202'; 'SOT-227','SOT227'; ...
         'TO-220-FP','TO220FP'; 'TO-243-7','TO2437'; 'TO-263-7','TO2637'; ...
         'TO-247-2','TO2472'; 'TO-247-3','TO2473'; 'DO-214','DO214'; 'Other','OtherPack'});
    ctx.hsProducerTree  = i_buildTree(tab, L.tree3, L.tree3Label, 'Heatsink Producer', 'HSPR', ...
        {'HSDissipadores','HSDissipadores'; 'Semikron','Semikron'; 'Other','OtherPHS'});
    ctx.convectionTree  = i_buildTree(tab, L.tree4, L.tree4Label, 'Convection', 'CR', ...
        {'Natural','Natural'; 'Forced','Forced'; 'Other','OtherMethod'});

    ctx.ax = uiaxes(tab, 'Position', [L.plot.x L.plot.y L.plot.w L.plot.h]);
    title(ctx.ax, 'Diode candidates - Heatsink Volume x Losses');
    xlabel(ctx.ax, 'Heatsink Volume [cm^3]'); ylabel(ctx.ax, 'Losses [W]');
    grid(ctx.ax, 'on');

    ctx.calcButton = uibutton(tab, 'push', ...
        'Position', [L.calcButton.x L.calcButton.y L.calcButton.w L.calcButton.h], ...
        'Text', 'Calculate');
    ctx.graphButton = uibutton(tab, 'push', ...
        'Position', [L.graphButton.x L.graphButton.y L.graphButton.w L.graphButton.h], ...
        'Text', 'Filter / Plot', 'Enable', 'off');
    ctx.statusLabel = uilabel(tab, ...
        'Position', [L.statusLabel.x L.statusLabel.y L.statusLabel.w L.statusLabel.h], ...
        'Text', 'Status: Idle');

    ctx.tableCols = {'Diode','Producer','Heatsink','HS Producer','Power [W]','Length [mm]', ...
                    'Volume [cm3]','Max Volt [V]','Max Curr [A]','Temp Elev [C]','Rth [C/W]','Package','Method','Air Speed'};
    ctx.table = uitable(tab, ...
        'Position', [L.table.x L.table.y L.table.w L.table.h], ...
        'ColumnName', ctx.tableCols, ...
        'Data', cell(0, numel(ctx.tableCols)));

    % ctx complete - assign callbacks now so closures capture every field.
    ctx.calcButton.ButtonPushedFcn  = @(~,~) i_on_calculate(app, ctx);
    ctx.graphButton.ButtonPushedFcn = @(~,~) i_on_filter(app, ctx);
end


function f = i_fieldList()
    f = struct( ...
        'name',    {'Tj','Vblock','Imax','Ief','Im','D','DeltaI','fs','Ta','Hs','Q','Cm'}, ...
        'label',   { ...
            'Junction Temperature (C)', 'Blocking Voltage (V)', 'Maximum Current (A)', ...
            'RMS Current (A)','Average Current (A)', 'Duty Cycle','Current Ripple (A)', ...
            'Switching Frequency (kHz)','Room Temperature (C)','HS Max Temperature (C)', ...
            'Devices per HS','HS Max Length (mm)'}, ...
        'default', {125,650,30,17,10,0.5,3,50,55,100,6,300}, ...
        'limits',  {[-55 200],[0 5000],[0 1000],[0 1000],[0 1000],[0 1],[0 1000], ...
                    [1 1000],[-40 80],[0 200],[1 100],[10 1000]}, ...
        'step',    {1,10,1,1,1,0.01,1,1,1,1,1,10});
end


function tree = i_buildTree(tab, pos, labelPos, titleText, rootData, items)
    uilabel(tab, 'Position', [labelPos.x labelPos.y labelPos.w labelPos.h], ...
        'Text', titleText, 'FontWeight', 'bold', 'FontSize', 11);
    tree = uitree(tab, 'checkbox', 'Position', [pos.x pos.y pos.w pos.h]);
    root = uitreenode(tree, 'Text', titleText, 'NodeData', rootData);
    for k = 1:size(items,1)
        uitreenode(root, 'Text', items{k,1}, 'NodeData', items{k,2});
    end
    expand(tree);
end


function i_on_calculate(app, ctx)
    s = ctx.spinners;
    if s.Hs.Value <= s.Ta.Value
        uialert(app.UIFigure,'HS Max Temp must be > Room Temp','Invalid input'); return
    end
    if s.Tj.Value <= s.Ta.Value
        uialert(app.UIFigure,'Junction Temp must be > Room Temp','Invalid input'); return
    end

    ctx.calcButton.Enable = 'off';
    ctx.graphButton.Enable = 'off';
    ctx.statusLabel.Text = 'Status: Computing diode losses...';
    pd = uiprogressdlg(app.UIFigure, 'Title','Diodes','Message','Computing conduction losses...','Indeterminate','off');

    try
        op = struct('Tj', s.Tj.Value, 'I_RMS', s.Ief.Value, 'I_avg', s.Im.Value);
        diodes = app.Catalog.diodes;
        n = height(diodes);
        rec(n,1) = struct('PartNumber','','Producer','','Package','','Technology','', ...
                          'Vmax',0,'Imax',0,'P_cond',0,'PerLeg',false);
        hasTech = ismember('Technology', diodes.Properties.VariableNames);
        for i = 1:n
            row = table2struct(diodes(i,:));
            try, Ld = pdpwr.loss.diode(row, op);
            catch, Ld = struct('P_cond',NaN,'PerLeg',false);
            end
            rec(i).PartNumber = i_asChar(row.PartNumber);
            rec(i).Producer   = i_asChar(row.Manufacturer);
            rec(i).Package    = i_asChar(row.Package);
            if hasTech, rec(i).Technology = i_asChar(row.Technology); else, rec(i).Technology = 'SiC'; end
            rec(i).Vmax       = double(row.Vrev_V);
            rec(i).Imax       = double(row.I_A);
            rec(i).P_cond     = Ld.P_cond;
            rec(i).PerLeg     = Ld.PerLeg;
            pd.Value = 0.4 * i/n;
        end

        pd.Value = 0.5; pd.Message = 'Dimensioning heatsinks...';
        hsOp = struct('Tj',s.Tj.Value,'T_amb',s.Ta.Value,'T_HS_max',s.Hs.Value, ...
                      'Qtdd',s.Q.Value,'L_min',0.001,'L_max',s.Cm.Value, ...
                      'Rth_jc',1,'Rth_chs',0.5);
        hsAll = repmat(struct( ...
            'PartNumber','','Producer','','Technology','','Heatsink','','HeatsinkProducer','', ...
            'PowerW',0,'Length_mm',0,'Volume_cm3',0,'MaxVolt_V',0,'MaxCurr_A',0, ...
            'Temp_Elev_C',0,'Rth_C_W',0,'Package','','Method','','AirSpeed','', ...
            'DevicesPerHS',0,'GroupLossW',0), 0, 1);
        survivors = 0;
        for methodId = 1:2
            if methodId == 1, hsOp.convection='Natural'; else, hsOp.convection='Forced'; end
            for i = 1:n
                if isnan(rec(i).P_cond) || rec(i).P_cond <= 0, continue; end
                if rec(i).Vmax < s.Vblock.Value, continue; end
                if rec(i).Imax < s.Imax.Value,   continue; end
                fits = pdpwr.design.heatsink(rec(i).P_cond, hsOp, app.Catalog.heatsinks);
                for f = 1:numel(fits)
                    hsAll(end+1) = struct( ...
                        'PartNumber', rec(i).PartNumber, 'Producer', rec(i).Producer, ...
                        'Technology', rec(i).Technology, ...
                        'Heatsink', fits(f).profile, 'HeatsinkProducer', fits(f).manufacturer, ...
                        'PowerW', rec(i).P_cond, 'Length_mm', fits(f).length_mm, ...
                        'Volume_cm3', fits(f).volume_cm3, 'MaxVolt_V', rec(i).Vmax, ...
                        'MaxCurr_A', rec(i).Imax, 'Temp_Elev_C', fits(f).ElevTemp, ...
                        'Rth_C_W', fits(f).Rth_HA, 'Package', rec(i).Package, ...
                        'Method', hsOp.convection, 'AirSpeed', fits(f).air_speed, ...
                        'DevicesPerHS', hsOp.Qtdd, 'GroupLossW', rec(i).P_cond * hsOp.Qtdd); %#ok<AGROW>
                end
                if ~isempty(fits), survivors = survivors + 1; end
            end
        end

        app.set_results('diode', struct('records', rec, 'hsAll', hsAll));
        cla(ctx.ax);
        if isempty(hsAll)
            ctx.statusLabel.Text = sprintf('Status: 0 / %d diodes fit any HS.', n);
            i_diagnoseEmpty(app, rec, s);
        else
            i_drawScatter(ctx.ax, hsAll, false);
            ctx.statusLabel.Text = sprintf('Status: %d diodes, %d fit, %d combos generated', ...
                n, survivors, numel(hsAll));
            i_fillTable(ctx, hsAll);
        end
        ctx.graphButton.Enable = 'on';
        pd.Value = 1.0; pause(0.1);
    catch ME
        try, uialert(app.UIFigure, ME.message, 'Diode calculation failed'); catch, end
        try, ctx.statusLabel.Text = sprintf('Error: %s', ME.message); catch, end
    end
    try, close(pd); catch, end
    try, ctx.calcButton.Enable = 'on'; catch, end
end


function i_diagnoseEmpty(app, rec, s)
    medP = median([rec.P_cond],'omitnan');
    T_HS = s.Tj.Value - medP * 1.5;
    if T_HS <= s.Ta.Value
        msg = sprintf(['Median P_cond = %.1f W -> case temp falls below ambient.\n' ...
            'Reduce currents OR raise Tj.'], medP);
    else
        msg = sprintf(['Median P_cond = %.1f W. No HS profile reaches required Rth.\n' ...
            'Increase Devices per HS or HS Max Temp.'], medP);
    end
    uialert(app.UIFigure, msg, 'Why no heatsink fits');
end


function i_on_filter(app, ctx)
    res = app.get_results('diode');
    if isempty(res) || isempty(res.hsAll)
        uialert(app.UIFigure,'Click Calculate first.','No data'); return
    end
    hsAll = res.hsAll;
    pkgMap = containers.Map( ...
        {'TO2522','TO2202','SOT227','TO220FP','TO2637','TO2437','TO2473','TO2472','DO214'}, ...
        {'TO-252-2','TO-220-2','SOT-227','TO-220-FP','TO-263-7','TO-243-7','TO-247-3','TO-247-2','DO-214'});
    checked = i_collectChecked({ctx.producerTree, ctx.packageTree, ctx.hsProducerTree, ctx.convectionTree});
    isChecked = @(id) any(strcmp(checked, id));

    keep = false(numel(hsAll),1);
    for i = 1:numel(hsAll)
        r = hsAll(i);
        pok = (isChecked('WolfSpeed') && strcmp(r.Producer,'Wolfspeed')) || ...
              (isChecked('Genesic')   && strcmp(r.Producer,'GeneSiC'))   || ...
              (isChecked('OtherPM')   && ~ismember(r.Producer,{'Wolfspeed','GeneSiC'}));
        if ~pok, continue; end
        kn = false;
        for kk = pkgMap.keys
            if isChecked(kk{1}) && strcmp(r.Package, pkgMap(kk{1})), kn = true; break; end
        end
        if ~(kn || (isChecked('OtherPack') && ~ismember(r.Package, pkgMap.values))), continue; end
        hok = (isChecked('HSDissipadores') && strcmp(r.HeatsinkProducer,'HSDissipadores')) || ...
              (isChecked('Semikron')       && strcmp(r.HeatsinkProducer,'Semikron'))       || ...
              (isChecked('OtherPHS')       && ~ismember(r.HeatsinkProducer,{'HSDissipadores','Semikron'}));
        if ~hok, continue; end
        mok = (isChecked('Natural') && strcmp(r.Method,'Natural')) || ...
              (isChecked('Forced')  && strcmp(r.Method,'Forced'))  || ...
              (isChecked('OtherMethod') && ~ismember(r.Method,{'Natural','Forced'}));
        if ~mok, continue; end
        keep(i) = true;
    end
    kept = hsAll(keep);
    if isempty(kept)
        cla(ctx.ax); ctx.table.Data = cell(0, numel(ctx.tableCols));
        ctx.statusLabel.Text = 'Status: 0 candidates match the current filters';
        uialert(app.UIFigure,'No candidate matches filters.','Filter empty'); return
    end
    cla(ctx.ax);
    i_drawScatter(ctx.ax, kept, true);
    i_fillTable(ctx, kept);

    folder = pdpwr.util.save_table(struct2table(kept), 'diode_heatsink');
    ctx.statusLabel.Text = sprintf('Status: %d combos - saved (xlsx+csv) to %s', numel(kept), folder);
end


function i_drawScatter(ax, hsAll, filtered)
    cla(ax); hold(ax, 'on');
    % One colour per diode MATERIAL/technology (SiC today; ready for Si / GaN),
    % mirroring how the magnetics tabs colour by material. Producer in datatip.
    techs = unique({hsAll.Technology});
    colors = lines(max(numel(techs),1));
    for t = 1:numel(techs)
        sub = hsAll(strcmp({hsAll.Technology}, techs{t}));
        % X = heatsink volume (diode volume is negligible), Y = losses.
        p = scatter(ax, [sub.Volume_cm3], [sub.PowerW], 28, ...
            'MarkerEdgeColor', colors(t,:), 'DisplayName', techs{t});
        p.DataTipTemplate.DataTipRows(1).Label = 'Vol[cm3]';
        p.DataTipTemplate.DataTipRows(2).Label = 'Loss[W]';
        % Compact datatip (full detail is in the table below).
        extra = [ ...
            dataTipTextRow('Part',  {sub.PartNumber}); ...
            dataTipTextRow('Mat',   {sub.Technology}); ...
            dataTipTextRow('Pkg',   {sub.Package}); ...
            dataTipTextRow('HS',    {sub.Heatsink}); ...
            dataTipTextRow('Cool',  {sub.Method}); ...
            dataTipTextRow('Dev/HS',[sub.DevicesPerHS]) ];
        p.DataTipTemplate.DataTipRows(end+1:end+numel(extra)) = extra;
    end
    hold(ax, 'off'); grid(ax, 'on'); legend(ax, 'Location', 'best');
    if filtered
        title(ax, sprintf('Diode candidates (filtered, %d combos)', numel(hsAll)));
    else
        title(ax, sprintf('Diode candidates (all, %d combos)', numel(hsAll)));
    end
end


function i_fillTable(ctx, hsAll)
    data = cell(numel(hsAll), numel(ctx.tableCols));
    for i = 1:numel(hsAll)
        r = hsAll(i);
        data(i,:) = {r.PartNumber, r.Producer, r.Heatsink, r.HeatsinkProducer, ...
                     r.PowerW, r.Length_mm, r.Volume_cm3, r.MaxVolt_V, r.MaxCurr_A, ...
                     r.Temp_Elev_C, r.Rth_C_W, r.Package, r.Method, r.AirSpeed};
    end
    ctx.table.Data = data;
end


function ids = i_collectChecked(treeList)
    ids = {};
    for t = 1:numel(treeList)
        nodes = treeList{t}.CheckedNodes;
        for n = 1:numel(nodes)
            nd = char(nodes(n).NodeData);
            if endsWith(nd,'Root') || endsWith(nd,'PR') || endsWith(nd,'CR'), continue; end
            ids{end+1} = nd; %#ok<AGROW>
        end
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
