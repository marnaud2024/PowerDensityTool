function ctx = tab_mosfet(app, which)
%TAB_MOSFET Build the MOSFET-I or MOSFET-II tab.

    L = pdpwr.ui.layout();
    titleStr = sprintf('MOSFET-%s', which);
    tab = uitab(app.TabGroup, 'Title', titleStr);
    ctx.tab = tab;

    % ---- LEFT: Input panel (full height) ----
    panel = uipanel(tab, 'Title', 'Calculation Parameters', 'FontWeight','bold', ...
        'Position', [L.inputPanel.x L.inputPanel.y L.inputPanel.w L.inputPanel.h]);

    fields = i_fieldList();
    ctx.spinners = struct();
    yTop = L.inputPanel.h - 30;
    for k = 1:numel(fields)
        f = fields(k);
        y = yTop - k * (L.spinnerRowHeight + L.spinnerRowSpacing);
        s = pdpwr.ui.spinner_row(panel, 10, y, f.label, f.default, ...
            'Limits', f.limits, 'Step', f.step);
        ctx.spinners.(f.name) = s;
    end
    yLast = yTop - (numel(fields)+1) * (L.spinnerRowHeight + L.spinnerRowSpacing);
    ctx.zvsCheckBox = uicheckbox(panel, ...
        'Position', [10, yLast, 350, L.spinnerRowHeight], ...
        'Text', 'Zero-Voltage Switching (cancels P_on)');

    % Mini tutorial at the bottom of the input panel
    tutY = yLast - 90;
    uilabel(panel, 'Position', [10, tutY+72, 360, 18], ...
        'Text', sprintf('How to use this tab (MOSFET-%s)', which), ...
        'FontWeight', 'bold', 'FontColor', [0.2 0.4 0.7]);
    uitextarea(panel, 'Position', [10, tutY, 360, 72], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontSize', 10, ...
        'Value', { ...
            '1. Set the operating conditions in the spinners above.', ...
            '2. Click "Calculate" - the app loops over every PLECS model in the catalog.', ...
            '3. Tick the filters in the four trees on the right.', ...
            '4. Click "Filter / Plot" to update chart + table + export to output/.'});

    % ---- TOP-MIDDLE: 4 filter trees with labels ----
    ctx.producerTree    = i_buildTree(tab, L.tree1, L.tree1Label, 'Device Producer', 'ProducerRoot', ...
        {'WolfSpeed','WolfSpeed'; 'GeneSiC','Genesic'; 'Other','OtherPM'});
    ctx.packageTree     = i_buildTree(tab, L.tree2, L.tree2Label, 'Package', 'PackageRoot', ...
        {'TO-247-3','TO2473'; 'TO-263-7','TO2637'; 'TO-247-4','TO2474'; ...
         'SOT-227','SOT227'; 'TO-247-4 Plus','TO2474Plus'; 'TOLL','TOLL'; ...
         'Other','OtherPack'});
    ctx.hsProducerTree  = i_buildTree(tab, L.tree3, L.tree3Label, 'Heatsink Producer', 'HSPR', ...
        {'HSDissipadores','HSDissipadores'; 'Semikron','Semikron'; 'Other','OtherPHS'});
    ctx.hsConvectionTree= i_buildTree(tab, L.tree4, L.tree4Label, 'Convection', 'CR', ...
        {'Natural','Natural'; 'Forced','Forced'; 'Other','OtherMethod'});

    % ---- TOP-RIGHT: Plot ----
    ctx.ax = uiaxes(tab, ...
        'Position', [L.plot.x L.plot.y L.plot.w L.plot.h]);
    title(ctx.ax, sprintf('%s - Heatsink Volume x Losses', titleStr));
    xlabel(ctx.ax, 'Heatsink Volume [cm^3]'); ylabel(ctx.ax, 'Losses [W]');
    grid(ctx.ax, 'on');

    % ---- MIDDLE: Buttons + status (callbacks assigned at the END) ----
    ctx.calcButton = uibutton(tab, 'push', ...
        'Position', [L.calcButton.x L.calcButton.y L.calcButton.w L.calcButton.h], ...
        'Text', 'Calculate');
    ctx.graphButton = uibutton(tab, 'push', ...
        'Position', [L.graphButton.x L.graphButton.y L.graphButton.w L.graphButton.h], ...
        'Text', 'Filter / Plot', 'Enable', 'off');
    ctx.statusLabel = uilabel(tab, ...
        'Position', [L.statusLabel.x L.statusLabel.y L.statusLabel.w L.statusLabel.h], ...
        'Text', 'Status: Idle');

    % ---- BOTTOM: Results table (with headers visible from start) ----
    ctx.tableCols = {'MOSFET','Producer','Heatsink','HS Producer','Power [W]','Length [mm]', ...
                    'Volume [cm3]','Block Volt [V]','Temp Elev [C]','Rth [C/W]','Package','Method','Air Speed'};
    ctx.table = uitable(tab, ...
        'Position', [L.table.x L.table.y L.table.w L.table.h], ...
        'ColumnName', ctx.tableCols, ...
        'Data', cell(0, numel(ctx.tableCols)));

    % ctx is now COMPLETE - assign callbacks so the closures capture every field.
    ctx.calcButton.ButtonPushedFcn  = @(~,~) i_on_calculate(app, ctx, which);
    ctx.graphButton.ButtonPushedFcn = @(~,~) i_on_filter(app, ctx, which);
end


function fields = i_fieldList()
    fields = struct( ...
        'name',    {'Vd','Vblock','Tj','Rg','Vgson','Ief','Ion','Ioff','D','DeltaI','fs','Ta','Hs','Q','Cm'}, ...
        'label',   { ...
            'Drain-Source Voltage (V)','Blocking Voltage (V)','Junction Temperature (C)', ...
            'Gate Resistor (Ohm)','Vgs on (V)','RMS Current (A)','Instant Current ON (A)', ...
            'Instant Current OFF (A)','Duty Cycle','Current Ripple (A)','Switching Frequency (kHz)', ...
            'Room Temperature (C)','HS Max Temperature (C)','Devices per HS','HS Max Length (mm)'}, ...
        'default', {800, 1200, 125, 7, 15, 9, 12, 12, 0.5, 3, 50, 55, 100, 6, 300}, ...
        'limits',  {[0 5000],[0 5000],[-55 200],[0 100],[0 25],[0 1000],[0 1000],[0 1000], ...
                    [0 1],[0 1000],[1 1000],[-40 80],[0 200],[1 100],[10 1000]}, ...
        'step',    {10,10,1,0.5,1,1,1,1,0.01,1,1,1,1,1,10});
end


function tree = i_buildTree(tab, pos, labelPos, titleText, rootData, items)
    uilabel(tab, 'Position', [labelPos.x labelPos.y labelPos.w labelPos.h], ...
        'Text', titleText, 'FontWeight', 'bold', 'FontSize', 11);
    tree = uitree(tab, 'checkbox', ...
        'Position', [pos.x pos.y pos.w pos.h]);
    root = uitreenode(tree, 'Text', titleText, 'NodeData', rootData);
    for k = 1:size(items,1)
        uitreenode(root, 'Text', items{k,1}, 'NodeData', items{k,2});
    end
    expand(tree);
end


function i_on_calculate(app, ctx, which)
    s = ctx.spinners;
    warns = i_validateInputs(s);
    if ~isempty(warns)
        sel = uiconfirm(app.UIFigure, ...
            sprintf('Warnings:\n - %s\n\nContinue?', strjoin(warns, sprintf('\n - '))), ...
            'Input warnings', 'Options',{'Continue','Cancel'}, 'DefaultOption','Cancel');
        if strcmp(sel,'Cancel'), return; end
    end

    ctx.calcButton.Enable  = 'off';
    ctx.graphButton.Enable = 'off';
    ctx.statusLabel.Text = 'Status: Loading PLECS models...';
    pd = uiprogressdlg(app.UIFigure, 'Title', sprintf('MOSFET %s', which), ...
        'Message', 'Loading PLECS models...', 'Indeterminate', 'off');

    try
        op = struct( ...
            'Vd', s.Vd.Value, 'Tj', s.Tj.Value, 'Rg', s.Rg.Value, 'Vgson', s.Vgson.Value, ...
            'I_RMS', s.Ief.Value, 'I_on', s.Ion.Value, 'I_off', s.Ioff.Value, ...
            'fs', s.fs.Value * 1000, 'softSwitching', ctx.zvsCheckBox.Value);
        Vblock = s.Vblock.Value;

        rootDir = i_root();
        mosfets = app.Catalog.mosfets;
        n = height(mosfets);

        records(n,1) = struct('PartNumber','','Producer','','Package','','Technology','', ...
                              'Vmax',0,'Pon',0,'Poff',0,'Pcond',0,'P_total',0);
        hasTech = ismember('Technology', mosfets.Properties.VariableNames);
        for i = 1:n
            pd.Value = i/n * 0.55;
            pd.Message = sprintf('Computing losses (%d / %d)', i, n);
            try
                vendor  = i_asChar(mosfets.Manufacturer(i));
                relPath = i_asChar(mosfets.XML_File(i));
                xmlPath = fullfile(rootDir, 'data', strrep(relPath,'/',filesep));
                plecsModel = pdpwr.util.plecs_load(xmlPath, vendor);
                Lm = pdpwr.loss.mosfet(plecsModel, op);
            catch
                Lm = struct('P_on',NaN,'P_off',NaN,'P_cond',NaN,'P_total',NaN);
            end
            records(i).PartNumber = i_asChar(mosfets.PartNumber(i));
            records(i).Producer   = i_asChar(mosfets.Manufacturer(i));
            records(i).Package    = i_asChar(mosfets.Package(i));
            if hasTech, records(i).Technology = i_asChar(mosfets.Technology(i)); else, records(i).Technology = 'SiC'; end
            records(i).Vmax       = double(mosfets.Vds_max_V(i));
            records(i).Pon        = Lm.P_on;
            records(i).Poff       = Lm.P_off;
            records(i).Pcond      = Lm.P_cond;
            records(i).P_total    = Lm.P_total;
        end

        pd.Value = 0.6; pd.Message = 'Dimensioning heatsinks...';
        hsOp = struct('Tj', s.Tj.Value, 'T_amb', s.Ta.Value, 'T_HS_max', s.Hs.Value, ...
                      'Qtdd', s.Q.Value, 'L_min', 0.001, 'L_max', s.Cm.Value, ...
                      'Rth_jc', 1, 'Rth_chs', 0.5);

        hsAll = repmat(struct( ...
            'PartNumber','','Producer','','Technology','','Heatsink','','HeatsinkProducer','', ...
            'PowerW',0,'Length_mm',0,'Volume_cm3',0,'BlockVolt_V',0, ...
            'Temp_Elev_C',0,'Rth_C_W',0,'Package','','Method','','AirSpeed','', ...
            'DevicesPerHS',0,'GroupLossW',0), 0, 1);

        survivors = 0;
        for methodId = 1:2
            if methodId == 1, hsOp.convection = 'Natural'; else, hsOp.convection = 'Forced'; end
            for i = 1:n
                if isnan(records(i).P_total) || records(i).P_total <= 0, continue; end
                if records(i).Vmax < Vblock, continue; end
                fits = pdpwr.design.heatsink(records(i).P_total, hsOp, app.Catalog.heatsinks);
                for f = 1:numel(fits)
                    hsAll(end+1) = struct( ...
                        'PartNumber', records(i).PartNumber, ...
                        'Producer',   records(i).Producer, ...
                        'Technology', records(i).Technology, ...
                        'Heatsink',   fits(f).profile, ...
                        'HeatsinkProducer', fits(f).manufacturer, ...
                        'PowerW',     records(i).P_total, ...
                        'Length_mm',  fits(f).length_mm, ...
                        'Volume_cm3', fits(f).volume_cm3, ...
                        'BlockVolt_V', records(i).Vmax, ...
                        'Temp_Elev_C', fits(f).ElevTemp, ...
                        'Rth_C_W',    fits(f).Rth_HA, ...
                        'Package',    records(i).Package, ...
                        'Method',     hsOp.convection, ...
                        'AirSpeed',   fits(f).air_speed, ...
                        'DevicesPerHS', hsOp.Qtdd, ...
                        'GroupLossW',   records(i).P_total * hsOp.Qtdd); %#ok<AGROW>
                end
                if ~isempty(fits), survivors = survivors + 1; end
            end
        end

        result.records = records;
        result.hsAll   = hsAll;
        app.set_results(sprintf('mosfet%s', which), result);

        cla(ctx.ax);
        if isempty(hsAll)
            ctx.statusLabel.Text = sprintf('Status: 0 / %d devices fit any HS. Click for details.', n);
            i_diagnoseEmpty(app, records, s);
        else
            i_drawScatter(ctx.ax, hsAll, false);
            ctx.statusLabel.Text = sprintf( ...
                'Status: %d devices, %d fit a HS, %d (device,HS,conv) combos generated', ...
                n, survivors, numel(hsAll));
            % Populate the table with the FULL set (filter button refines later)
            i_fillTable(ctx, hsAll);
        end

        ctx.graphButton.Enable = 'on';
        pd.Value = 1.0; pause(0.1);
    catch ME
        try, uialert(app.UIFigure, ME.message, sprintf('MOSFET %s failed', which)); catch, end
        try, ctx.statusLabel.Text = sprintf('Error: %s', ME.message); catch, end
    end
    try, close(pd); catch, end
    try, ctx.calcButton.Enable = 'on'; catch, end
end


function i_diagnoseEmpty(app, records, s)
    nValid = sum(arrayfun(@(r) ~isnan(r.P_total) && r.P_total > 0 && r.Vmax >= s.Vblock.Value, records));
    if nValid == 0
        uialert(app.UIFigure, sprintf(['No device passes Vblock=%g V. ' ...
            'Lower Vblock or pick higher-voltage devices.'], s.Vblock.Value), 'No device');
        return
    end
    medP = median([records.P_total], 'omitnan');
    T_HS_device = s.Tj.Value - medP * 1.5;
    if T_HS_device <= s.Ta.Value
        msg = sprintf(['Median loss = %.1f W -> case temp falls BELOW ambient.\n\n' ...
            'Reduce currents OR raise Tj OR increase Devices per HS (Q).'], medP);
    else
        Rth_req = (s.Hs.Value - s.Ta.Value) / (s.Q.Value * medP);
        msg = sprintf(['Median loss = %.1f W requires Rth_HA <= %.3f C/W.\n' ...
            'Catalog HSs do not reach this. Raise Q or HS Max Temp.'], medP, Rth_req);
    end
    uialert(app.UIFigure, msg, 'Why no heatsink fits');
end


function warns = i_validateInputs(s)
    warns = {};
    if s.Hs.Value <= s.Ta.Value, warns{end+1} = 'HS Max Temp <= Room Temp'; end
    if s.Tj.Value <= s.Ta.Value, warns{end+1} = 'Junction Temp <= Room Temp'; end
    if s.Vblock.Value > s.Vd.Value * 2, warns{end+1} = 'Vblock > 2*Vd (conservative)'; end
end


function i_on_filter(app, ctx, which)
    res = app.get_results(sprintf('mosfet%s', which));
    if isempty(res) || isempty(res.hsAll)
        uialert(app.UIFigure, 'Click "Calculate" first.', 'No data'); return
    end
    hsAll = res.hsAll;
    checked = i_collectChecked({ctx.producerTree, ctx.packageTree, ctx.hsProducerTree, ctx.hsConvectionTree});
    isChecked = @(id) any(strcmp(checked, id));

    pkgMap = containers.Map( ...
        {'TO2473','TO2637','TO2474','SOT227','TO2474Plus','TOLL'}, ...
        {'TO-247-3','TO-263-7','TO-247-4','SOT-227','TO-247-4 Plus (Wolfspeed)','TOLL (Wolfspeed)'});

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
        uialert(app.UIFigure, 'No candidate matches the current filters.', 'Filter empty'); return
    end
    cla(ctx.ax);
    i_drawScatter(ctx.ax, kept, true);
    i_fillTable(ctx, kept);

    folder = pdpwr.util.save_table(struct2table(kept), sprintf('mosfet_%s_heatsink', lower(which)));
    ctx.statusLabel.Text = sprintf('Status: %d combos - saved (xlsx+csv) to %s', numel(kept), folder);
end


function i_drawScatter(ax, hsAll, filtered)
    cla(ax); hold(ax, 'on');
    % One colour per semiconductor MATERIAL/technology (SiC today; ready for
    % Si / GaN if such parts are ever added to the catalog), mirroring how the
    % magnetics tabs colour by material. Producer stays in the datatip.
    techs = unique({hsAll.Technology});
    colors = lines(max(numel(techs),1));
    for t = 1:numel(techs)
        sub = hsAll(strcmp({hsAll.Technology}, techs{t}));
        % X = heatsink volume (the semiconductor volume itself is negligible),
        % Y = losses. Point nearest the origin = lowest volume AND loss.
        p = scatter(ax, [sub.Volume_cm3], [sub.PowerW], 28, ...
            'MarkerEdgeColor', colors(t,:), 'DisplayName', techs{t});
        p.DataTipTemplate.DataTipRows(1).Label = 'Vol[cm3]';
        p.DataTipTemplate.DataTipRows(2).Label = 'Loss[W]';
        % Compact datatip (full detail is in the table below). Short labels keep
        % the box narrow so it fits inside the plot area.
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
        title(ax, sprintf('MOSFET candidates (filtered, %d combos)', numel(hsAll)));
    else
        title(ax, sprintf('MOSFET candidates (all, %d combos)', numel(hsAll)));
    end
end


function i_fillTable(ctx, hsAll)
    data = cell(numel(hsAll), numel(ctx.tableCols));
    for i = 1:numel(hsAll)
        r = hsAll(i);
        data(i,:) = {r.PartNumber, r.Producer, r.Heatsink, r.HeatsinkProducer, ...
                     r.PowerW, r.Length_mm, r.Volume_cm3, r.BlockVolt_V, ...
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
