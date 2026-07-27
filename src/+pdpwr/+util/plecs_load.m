function model = plecs_load(xmlPath, vendor)
%PLECS_LOAD Parse a PLECS thermal-model XML file for a SiC MOSFET.
%
%   model = pdpwr.util.plecs_load(xmlPath)
%   model = pdpwr.util.plecs_load(xmlPath, vendor)
%
%   xmlPath - path to the PLECS XML file
%   vendor  - 'GeneSiC' or 'Wolfspeed'. If omitted, auto-detected from the
%             XML <Package vendor="..."> attribute.
%
%   Returns a struct:
%     .vendor       'GeneSiC' or 'Wolfspeed'
%     .partNumber   string
%     .vendor_default_Rg  default external gate resistor [ohm]
%     .Eon(I, Vd, T, Rg)   griddedInterpolant + formula, [J]
%     .Eoff(I, Vd, T, Rg)  same, [J]
%     .Vdrop(I, Vgs, T)    forward voltage drop, [V]
%
%   For Wolfspeed body diodes, see pdpwr.util.plecs_load_body.

    if exist(xmlPath, 'file') ~= 2
        error('pdpwr:plecsXmlMissing', 'PLECS file not found: %s', xmlPath);
    end

    doc = xmlread(xmlPath);

    if nargin < 2 || isempty(vendor)
        pkgNodes = doc.getElementsByTagName('Package');
        if pkgNodes.getLength == 0
            error('pdpwr:plecsBadXml', 'No <Package> element in %s', xmlPath);
        end
        vendor = char(pkgNodes.item(0).getAttribute('vendor'));
        if isempty(vendor), vendor = 'Unknown'; end
    end

    [~, baseName] = fileparts(xmlPath);
    model.vendor     = vendor;
    model.partNumber = baseName;

    rgDefault = i_extractRgDefault(doc);
    model.vendor_default_Rg = rgDefault;

    switch lower(vendor)
        case 'genesic'
            model = i_loadGeneSiC(doc, model, rgDefault);
        case 'wolfspeed'
            model = i_loadWolfspeed(doc, model);
        otherwise
            error('pdpwr:unknownVendor', 'Unknown PLECS vendor "%s" in %s', vendor, xmlPath);
    end
end


function rgDefault = i_extractRgDefault(doc)
% Return external gate resistor default value, or NaN if not present.
    rgDefault = NaN;
    varNodes = doc.getElementsByTagName('Variable');
    for k = 0:(varNodes.getLength - 1)
        node = varNodes.item(k);
        nameNode = node.getElementsByTagName('Name');
        if nameNode.getLength == 0, continue; end
        if strcmpi(char(nameNode.item(0).getTextContent), 'Rg')
            defNode = node.getElementsByTagName('DefaultValue');
            if defNode.getLength > 0
                rgDefault = str2double(char(defNode.item(0).getTextContent));
            end
            return
        end
    end
end


function model = i_loadGeneSiC(doc, model, rgDefault)
% GeneSiC parts use <CustomTables> with 6 sub-tables:
%   1: Vds(I, Vgs)   [Table2D, mV] - conduction voltage drop
%   2: Rds(T, Vgs)   [Table2D, mOhm] - conduction resistance temperature
%   3: BodyDiode(I, T, Vgs)  [Table3D] - reverse conduction
%   4: TurnOn k_Rg(Rg)       [Table1D]
%   5: TurnOff k_Rg(Rg)      [Table1D]
%   6: TurnOn k_T(T)         [Table1D]
% Plus <TurnOnLoss>/<TurnOffLoss> with Esw(I, V, T) [J]

    tables = i_parseCustomTables(doc);
    [eonInterp, eonCurrent, eonVoltage, eonTemperature] = i_parseSwitchingLoss(doc, 'TurnOnLoss');
    [eoffInterp, ~, ~, ~] = i_parseSwitchingLoss(doc, 'TurnOffLoss');

    rgD = rgDefault;
    if isnan(rgD), rgD = 2.5; end  % GeneSiC datasheet typical default

    % Build closures
    model.Eon = @(I, Vd, T, Rg) eonInterp(I, Vd, clipTo(T, eonTemperature)) ...
        .* (tables(4).interp(Rg) ./ tables(4).interp(rgD)) ...
        .* (tables(6).interp(T) ./ tables(6).interp(25));

    model.Eoff = @(I, Vd, T, Rg) eoffInterp(I, Vd, clipTo(T, eonTemperature)) ...
        .* (tables(5).interp(Rg) ./ tables(5).interp(rgD));

    % Vds(I, Vgs) * Rds_temp_factor(T, Vgs) / Rds_temp_factor(25, Vgs)
    model.Vdrop = @(I, Vgs, T) tables(1).interp(I, Vgs) ...
        .* (tables(2).interp(T, Vgs) ./ tables(2).interp(25, Vgs));

    model.BodyDiode_Vdrop = @(I, T, Vgs) tables(3).interp(I, T, Vgs);

    model.tables = tables;
    model.eonCurrent = eonCurrent;
    model.eonVoltage = eonVoltage;
    model.eonTemperature = eonTemperature;
end


function model = i_loadWolfspeed(doc, model)
% Wolfspeed parts use direct <TurnOnLoss>/<TurnOffLoss> with Formula and
% Esw(I, V, T) table. <ConductionLoss> has Vds(I, T).
    [eonInterp, eonCurrent, eonVoltage, eonTemperature, eonFormula] = i_parseSwitchingLoss(doc, 'TurnOnLoss');
    [eoffInterp,    ~,         ~,         ~,           eoffFormula] = i_parseSwitchingLoss(doc, 'TurnOffLoss');
    [vdsInterp, ~, ~] = i_parseConductionLoss(doc);

    model.Eon  = @(I, Vd, T, Rg) eonFormula( eonInterp( I, Vd, clipTo(T, eonTemperature)), Rg );
    model.Eoff = @(I, Vd, T, Rg) eoffFormula( eoffInterp(I, Vd, clipTo(T, eonTemperature)), Rg );

    model.Vdrop = @(I, Vgs, T) vdsInterp(I, T);

    model.eonCurrent = eonCurrent;
    model.eonVoltage = eonVoltage;
    model.eonTemperature = eonTemperature;
end


function tables = i_parseCustomTables(doc)
% Parse all <CustomTables>/Table1D|Table2D|Table3D children.
% Returns a struct array, one per child, with fields:
%   .name, .order ('Table1D'/'2D'/'3D'), .XAxis, .YAxis, .ZAxis, .Data, .interp
    customNodes = doc.getElementsByTagName('CustomTables');
    if customNodes.getLength == 0
        tables = struct([]);
        return
    end
    children = customNodes.item(0).getChildNodes;
    tables(1) = struct('name', '', 'order', '', 'XAxis', [], 'YAxis', [], 'ZAxis', [], 'Data', [], 'interp', []);
    w = 0;
    for j = 0:(children.getLength - 1)
        ch = children.item(j);
        if ch.getNodeType ~= ch.ELEMENT_NODE, continue; end
        order = char(ch.getNodeName);
        if ~ismember(order, {'Table1D', 'Table2D', 'Table3D'}), continue; end
        w = w + 1;
        nameNode = ch.getElementsByTagName('Name');
        nm = '';
        if nameNode.getLength > 0
            nm = char(nameNode.item(0).getTextContent);
        end
        xAxis = i_readAxis(ch, 'XAxis', 0);
        tables(w).name  = nm;
        tables(w).order = order;
        tables(w).XAxis = xAxis;
        switch order
            case 'Table1D'
                fv = i_readAxis(ch, 'FunctionValues', 0);
                tables(w).Data = fv;
                if numel(xAxis) >= 2
                    f = griddedInterpolant(xAxis(:), fv(:), 'linear', 'nearest');
                    tables(w).interp = @(x) f(x);
                else
                    v = fv(1);
                    tables(w).interp = @(x) v * ones(size(x));
                end
            case 'Table2D'
                yAxis = i_readAxis(ch, 'YAxis', 0);
                tables(w).YAxis = yAxis;
                fvNodes = ch.getElementsByTagName('FunctionValues');
                Data = zeros(numel(xAxis), numel(yAxis));
                for i = 1:numel(yAxis)
                    row = i_readAxis(fvNodes.item(0), 'YDimension', i-1);
                    Data(:, i) = row(:);
                end
                tables(w).Data = Data;
                if numel(xAxis) >= 2 && numel(yAxis) >= 2
                    [X, Y] = ndgrid(xAxis, yAxis);
                    f = griddedInterpolant(X, Y, Data, 'linear', 'nearest');
                    tables(w).interp = @(x, y) f(x, y);
                elseif numel(xAxis) >= 2
                    f = griddedInterpolant(xAxis(:), Data(:, 1), 'linear', 'nearest');
                    tables(w).interp = @(x, y) f(x);
                elseif numel(yAxis) >= 2
                    f = griddedInterpolant(yAxis(:), Data(1, :)', 'linear', 'nearest');
                    tables(w).interp = @(x, y) f(y);
                else
                    v = Data(1, 1);
                    tables(w).interp = @(x, y) v * ones(size(x));
                end
            case 'Table3D'
                yAxis = i_readAxis(ch, 'YAxis', 0);
                zAxis = i_readAxis(ch, 'ZAxis', 0);
                tables(w).YAxis = yAxis;
                tables(w).ZAxis = zAxis;
                fvNodes = ch.getElementsByTagName('FunctionValues');
                zNodes = fvNodes.item(0).getElementsByTagName('ZDimension');
                Data = zeros(numel(xAxis), numel(yAxis), numel(zAxis));
                for k = 1:numel(zAxis)
                    for i = 1:numel(yAxis)
                        row = i_readAxis(zNodes.item(k-1), 'YDimension', i-1);
                        Data(:, i, k) = row(:);
                    end
                end
                tables(w).Data = Data;
                if numel(xAxis) >= 2 && numel(yAxis) >= 2 && numel(zAxis) >= 2
                    [X, Y, Z] = ndgrid(xAxis, yAxis, zAxis);
                    f = griddedInterpolant(X, Y, Z, Data, 'linear', 'nearest');
                    tables(w).interp = @(x, y, z) f(x, y, z);
                elseif numel(zAxis) < 2
                    Data2 = reshape(Data(:, :, 1), numel(xAxis), numel(yAxis));
                    if numel(xAxis) >= 2 && numel(yAxis) >= 2
                        [X, Y] = ndgrid(xAxis, yAxis);
                        f = griddedInterpolant(X, Y, Data2, 'linear', 'nearest');
                        tables(w).interp = @(x, y, z) f(x, y);
                    else
                        v = Data2(1, 1);
                        tables(w).interp = @(x, y, z) v * ones(size(x));
                    end
                else
                    v = Data(1, 1, 1);
                    tables(w).interp = @(x, y, z) v * ones(size(x));
                end
        end
    end
end


function [interp, currentAxis, voltageAxis, temperatureAxis, formula] = i_parseSwitchingLoss(doc, tag)
% Parse <TurnOnLoss>/<TurnOffLoss> -> 3D griddedInterpolant + formula closure
    formula = @(E, Rg) E;     % default identity if no <Formula>
    nodes = doc.getElementsByTagName(tag);
    if nodes.getLength == 0
        interp = [];
        currentAxis = []; voltageAxis = []; temperatureAxis = [];
        return
    end
    n = nodes.item(0);

    fNode = n.getElementsByTagName('Formula');
    if fNode.getLength > 0
        formulaText = strtrim(char(fNode.item(0).getTextContent));
        if ~isempty(formulaText)
            % Wolfspeed XMLs use 'Rgon' for TurnOnLoss and 'Rgoff' for TurnOffLoss
            % (the legacy ExtractMosfetDataWS.m does the same). Build an anonymous
            % function whose Rg-argument has the right name.
            if strcmpi(tag, 'TurnOnLoss')
                argName = 'Rgon';
            elseif strcmpi(tag, 'TurnOffLoss')
                argName = 'Rgoff';
            else
                argName = 'Rg';
            end
            formula = str2func(sprintf('@(E,%s) %s', argName, formulaText));
        end
    end

    currentAxis     = i_readAxis(n, 'CurrentAxis', 0);
    voltageAxis     = i_readAxis(n, 'VoltageAxis', 0);
    temperatureAxis = i_readAxis(n, 'TemperatureAxis', 0);

    energyNode = n.getElementsByTagName('Energy').item(0);
    scaleAttr = energyNode.getAttribute('scale');
    if scaleAttr.length() == 0
        scale = 1;
    else
        scale = str2double(char(scaleAttr));
    end

    tempNodes = energyNode.getElementsByTagName('Temperature');
    Data = zeros(numel(currentAxis), numel(voltageAxis), numel(temperatureAxis));
    for j = 1:numel(temperatureAxis)
        for i = 1:numel(voltageAxis)
            row = i_readAxis(tempNodes.item(j-1), 'Voltage', i-1) * scale;
            Data(:, i, j) = row(:);
        end
    end
    % griddedInterpolant requires >= 2 points per dimension. If T axis is
    % singleton (GeneSiC: T axis = [25] only, temperature scaling is done
    % via separate CustomTables) drop the T dimension and build a 2D
    % interpolant in (I, V), then re-wrap it with a T-ignoring shim.
    if numel(temperatureAxis) < 2
        Data2 = squeeze(Data(:, :, 1));
        % squeeze on (n,m,1) -> (n,m) - keep as 2D
        if size(Data2, 1) ~= numel(currentAxis) || size(Data2, 2) ~= numel(voltageAxis)
            Data2 = reshape(Data(:, :, 1), numel(currentAxis), numel(voltageAxis));
        end
        [I2, V2] = ndgrid(currentAxis, voltageAxis);
        interp2D = griddedInterpolant(I2, V2, Data2, 'linear', 'nearest');
        % Caller still expects E(I, V, T) - ignore T silently
        interp = @(I, V, T) interp2D(I, V);
    else
        [I, V, T] = ndgrid(currentAxis, voltageAxis, temperatureAxis);
        interp = griddedInterpolant(I, V, T, Data, 'linear', 'nearest');
    end
end


function [interp, currentAxis, temperatureAxis] = i_parseConductionLoss(doc)
% Parse <ConductionLoss> -> 2D griddedInterpolant Vds(I, T) for Wolfspeed
    nodes = doc.getElementsByTagName('ConductionLoss');
    if nodes.getLength == 0
        interp = [];
        currentAxis = [];
        temperatureAxis = [];
        return
    end
    n = nodes.item(0);
    currentAxis     = i_readAxis(n, 'CurrentAxis', 0);
    temperatureAxis = i_readAxis(n, 'TemperatureAxis', 0);
    vdsNode = n.getElementsByTagName('VoltageDrop').item(0);
    Data = zeros(numel(currentAxis), numel(temperatureAxis));
    for i = 1:numel(temperatureAxis)
        row = i_readAxis(vdsNode, 'Temperature', i-1);
        Data(:, i) = row(:);
    end
    if numel(currentAxis) < 2 || numel(temperatureAxis) < 2
        % Degenerate (one-axis only) - wrap as a function that returns the
        % single value or 1D-interpolates whichever axis is multi-valued.
        if numel(temperatureAxis) < 2 && numel(currentAxis) < 2
            v = Data(1,1);
            interp = @(I, T) v * ones(size(I));
        elseif numel(temperatureAxis) < 2
            f1 = griddedInterpolant(currentAxis(:), Data(:,1), 'linear', 'nearest');
            interp = @(I, T) f1(I);
        else
            f1 = griddedInterpolant(temperatureAxis(:), Data(1,:)', 'linear', 'nearest');
            interp = @(I, T) f1(T);
        end
    else
        [I, T] = ndgrid(currentAxis, temperatureAxis);
        interp = griddedInterpolant(I, T, Data, 'linear', 'nearest');
    end
end


function axisVals = i_readAxis(parent, tagName, idx)
% Read text content of `parent`'s `idx`th child with tag `tagName`, split
% by whitespace, parse as doubles. Empty/whitespace prefix is stripped.
    childList = parent.getElementsByTagName(tagName);
    if childList.getLength <= idx
        axisVals = [];
        return
    end
    txt = char(childList.item(idx).getTextContent);
    txt = strtrim(txt);
    parts = regexp(txt, '\s+', 'split');
    axisVals = str2double(parts);
end


function y = clipTo(x, axis)
% Clamp x to [min(axis), max(axis)] to keep griddedInterpolant in range
    y = max(min(x, max(axis)), min(axis));
end
