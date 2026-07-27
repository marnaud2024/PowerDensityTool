function L = layout()
%LAYOUT Shared visual constants for the Power Density Tool tabs.
%
%   Window: 1180 x 720 (tab inner area ~ 1180 x 690).
%
%   Layout (the chart is the focus, so it is LARGE; the table is a compact
%   secondary view at the bottom):
%     Left column  (x=10..390):   input panel, full height 10..680
%     Right column (x=400..1170):
%       - Trees  : x=400..760, y=205..680 (filters / material selection)
%       - Plot   : x=770..1170, y=205..680 (LARGE, 400 x 475)
%       - Buttons: x=400.., y=168..196
%       - Table  : x=400..1170, y=10..160 (compact, ~5 rows)

    L = struct();
    L.windowWidth  = 1180;
    L.windowHeight = 720;

    % ---- LEFT COLUMN: input panel (full height) ----
    L.inputPanel = struct('x', 10, 'y', 10, 'w', 380, 'h', 670);

    L.spinnerLabelWidth = 205;
    L.spinnerFieldWidth = 130;
    L.spinnerRowHeight  = 22;
    L.spinnerRowSpacing = 2;

    % ---- RIGHT COLUMN ----

    % Filter trees occupy the left part of the right column (x=400..760).
    % 2x2 grid (with labels above) for the 4-filter tabs (MOSFET/Diode).
    L.tree1 = struct('x', 400, 'y', 470, 'w', 175, 'h', 185);
    L.tree2 = struct('x', 585, 'y', 470, 'w', 175, 'h', 185);
    L.tree3 = struct('x', 400, 'y', 235, 'w', 175, 'h', 200);
    L.tree4 = struct('x', 585, 'y', 235, 'w', 175, 'h', 200);
    L.tree1Label = struct('x', 400, 'y', 657, 'w', 175, 'h', 18);
    L.tree2Label = struct('x', 585, 'y', 657, 'w', 175, 'h', 18);
    L.tree3Label = struct('x', 400, 'y', 437, 'w', 175, 'h', 18);
    L.tree4Label = struct('x', 585, 'y', 437, 'w', 175, 'h', 18);

    % Wide single tree (inductor / transformer material selection)
    L.treeWide      = struct('x', 400, 'y', 205, 'w', 360, 'h', 450);
    L.treeWideLabel = struct('x', 400, 'y', 657, 'w', 360, 'h', 18);

    % Plot - LARGE (this is what the user reads)
    L.plot = struct('x', 770, 'y', 205, 'w', 400, 'h', 470);

    % Buttons + status row (just above the table)
    L.calcButton  = struct('x', 400, 'y', 168, 'w', 150, 'h', 28);
    L.graphButton = struct('x', 560, 'y', 168, 'w', 150, 'h', 28);
    L.statusLabel = struct('x', 720, 'y', 168, 'w', 450, 'h', 26);

    % Table - COMPACT secondary view at the bottom
    L.table = struct('x', 400, 'y', 10, 'w', 770, 'h', 150);

    L.headerColor = [0.94 0.94 0.94];
    L.accentColor = [0.93 0.69 0.13];
    L.titleFontSize = 14;
end
