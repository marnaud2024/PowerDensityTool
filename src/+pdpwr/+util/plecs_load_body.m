function bd = plecs_load_body(xmlPath)
%PLECS_LOAD_BODY Parse a Wolfspeed body-diode/schottky-diode PLECS XML.
%
%   bd = pdpwr.util.plecs_load_body(xmlPath)
%
%   Returns a struct:
%     .partNumber    string
%     .Vdrop(I, T)   2D griddedInterpolant for body-diode forward drop [V]

    if exist(xmlPath, 'file') ~= 2
        error('pdpwr:plecsXmlMissing', 'Body-diode PLECS file not found: %s', xmlPath);
    end

    doc = xmlread(xmlPath);
    [~, baseName] = fileparts(xmlPath);
    bd.partNumber = baseName;

    condNodes = doc.getElementsByTagName('ConductionLoss');
    if condNodes.getLength == 0
        error('pdpwr:plecsBadBody', '<ConductionLoss> missing in body-diode file %s', xmlPath);
    end
    n = condNodes.item(0);

    currentAxis     = i_readAxis(n, 'CurrentAxis', 0);
    temperatureAxis = i_readAxis(n, 'TemperatureAxis', 0);
    vdsNode = n.getElementsByTagName('VoltageDrop').item(0);
    Data = zeros(numel(currentAxis), numel(temperatureAxis));
    for i = 1:numel(temperatureAxis)
        row = i_readAxis(vdsNode, 'Temperature', i-1);
        Data(:, i) = row(:);
    end
    [I, T] = ndgrid(currentAxis, temperatureAxis);
    bd.Vdrop = griddedInterpolant(I, T, Data, 'linear', 'nearest');
    bd.currentAxis = currentAxis;
    bd.temperatureAxis = temperatureAxis;
end


function axisVals = i_readAxis(parent, tagName, idx)
    childList = parent.getElementsByTagName(tagName);
    if childList.getLength <= idx
        axisVals = [];
        return
    end
    txt = strtrim(char(childList.item(idx).getTextContent));
    parts = regexp(txt, '\s+', 'split');
    axisVals = str2double(parts);
end
