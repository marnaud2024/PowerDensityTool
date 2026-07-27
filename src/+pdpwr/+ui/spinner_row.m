function s = spinner_row(parent, x, y, labelText, defaultValue, varargin)
%SPINNER_ROW Build a label + spinner pair side by side and return the spinner.
%
%   s = pdpwr.ui.spinner_row(parent, x, y, label, default, 'Limits', [lo hi], 'Step', step)

    L = pdpwr.ui.layout();
    h = L.spinnerRowHeight;

    uilabel(parent, ...
        'Position', [x, y, L.spinnerLabelWidth, h], ...
        'Text', labelText, ...
        'HorizontalAlignment', 'right', ...
        'FontSize', 11);

    spinPos = [x + L.spinnerLabelWidth + 6, y, L.spinnerFieldWidth, h];
    s = uispinner(parent, 'Position', spinPos, 'Value', defaultValue, varargin{:});
end
