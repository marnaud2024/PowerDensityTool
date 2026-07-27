classdef PowerDensityApp < matlab.apps.AppBase
%POWERDENSITYAPP Main interactive application.
%
%   app = PowerDensityApp()      % opens the UI
%
%   Replaces the legacy app2.mlapp without `evalin('base', 'run(...)')`,
%   delegating all calculation to functions in the +pdpwr package.
%
%   Tabs:
%     1. MOSFET I    - calculate switching+conduction losses for SET 1 of switches
%     2. MOSFET II   - same, for SET 2 (independent of Set 1 - no shared globals)
%     3. Diode       - SiC Schottky conduction losses + heatsink dimensioning
%     4. Inductor    - Magnetics + Magmattec sweep with corrected Bpk equation
%     5. Transformer - Magnetics SE+GSE / TDK neural network / Magmattec
%     6. Density     - 5-D combination, eta vs power density (P_out/Vol metric)
%     7. About       - credits and version info

    properties (Access = public)
        UIFigure   matlab.ui.Figure
        TabGroup   matlab.ui.container.TabGroup
        Catalog    struct       % loaded once on startup
    end

    properties (Access = private)
        % Per-tab handles (created lazily by build_<tab>_tab)
        MosfetITab    struct
        MosfetIITab   struct
        DiodeTab      struct
        InductorTab   struct
        TransformerTab struct
        DensityTab    struct

        % Cached results of the latest run on each tab. Used by the density
        % tab to combine the four families. Empty until the user clicks the
        % "Calculate" button on the corresponding tab.
        Results = struct( ...
            'mosfetI',     [], ...
            'mosfetII',    [], ...
            'diode',       [], ...
            'inductor',    [], ...
            'transformer', [] );
    end

    methods (Access = public)
        function app = PowerDensityApp()
            % Build UI in invisible state, then show
            app.UIFigure = uifigure('Visible', 'off', ...
                'Position', [100 100 1180 720], ...
                'Name', 'Power Density Tool');

            try
                app.Catalog = pdpwr.util.load_catalog();
            catch ME
                % The figure must be visible for uialert; in a fresh standalone
                % a failed catalog load would otherwise crash with the cryptic
                % "Figure handle 'Visible' value must be 'on'" error.
                app.UIFigure.Visible = 'on';
                uialert(app.UIFigure, ME.message, 'Failed to load Catalog.xlsx');
                rethrow(ME);
            end

            app.build_tab_group();
            app.MosfetITab     = pdpwr.ui.tab_mosfet(app, 'I');
            app.MosfetIITab    = pdpwr.ui.tab_mosfet(app, 'II');
            app.DiodeTab       = pdpwr.ui.tab_diode(app);
            app.InductorTab    = pdpwr.ui.tab_inductor(app);
            app.TransformerTab = pdpwr.ui.tab_transformer(app);
            app.DensityTab     = pdpwr.ui.tab_density(app);
            app.build_about_tab();

            registerApp(app, app.UIFigure);
            app.UIFigure.Visible = 'on';

            if nargout == 0, clear app; end
        end

        function delete(app)
            delete(app.UIFigure);
        end

        function set_results(app, tabName, value)
            % Hook used by tabs to publish their latest run for the Density tab
            app.Results.(tabName) = value;
        end

        function r = get_results(app, tabName)
            r = app.Results.(tabName);
        end
    end

    methods (Access = private)
        function build_tab_group(app)
            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Position', [0 0 app.UIFigure.Position(3) app.UIFigure.Position(4)]);
        end

        function build_about_tab(app)
            tab = uitab(app.TabGroup, 'Title', 'About');
            lbl = uilabel(tab, ...
                'Position', [40 480 1100 200], ...
                'Text', sprintf([ ...
                    'Power Density Tool\n\n' ...
                    'Power-density and efficiency estimator for isolated DC-DC converters,\n' ...
                    'developed at the GPEC group, Federal University of Ceara (UFC).\n\n' ...
                    ['Authors: Adolfo Jose M. F. Araujo, Joao Felipe X. P. Lima, Davi C. Amorim,\n' ...
                     'Joao Rodrigo Arnaud da Cruz, Samanta Gadelha Barbosa,\n' ...
                     'Demercil de S. Oliveira Junior.\n\n'] ...
                    'Runs inside MATLAB or as a standalone Windows build (MATLAB Compiler).\n\n' ...
                    ['Catalog: %d MOSFETs, %d diodes, %d heatsinks, ' ...
                     '%d inductor-core entries (Magnetics, one per core+permeability), ' ...
                     '%d transformer cores.']], ...
                    height(app.Catalog.mosfets), height(app.Catalog.diodes), ...
                    height(app.Catalog.heatsinks), height(app.Catalog.magnetics), ...
                    height(app.Catalog.trafos)), ...
                'FontSize', 14, 'WordWrap', 'on');
            assert(isvalid(lbl));

            try
                logo = uiimage(tab, 'Position', [780 40 320 240], ...
                    'ImageSource', fullfile(pdpwr.util.data_root(), 'assets', 'logo_gpec.png'));
                assert(isvalid(logo));
            catch
                % logo optional - silent if missing
            end
        end
    end
end


function r = i_root()
% Project root - this file lives in src/, so go up one level
    thisFile = mfilename('fullpath');
    r = fileparts(fileparts(thisFile));
end
