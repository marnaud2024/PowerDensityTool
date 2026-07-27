function catalog = load_catalog(catalogPath)
%LOAD_CATALOG Read Catalog.xlsx into a structured catalog.
%
%   catalog = pdpwr.util.load_catalog()
%   catalog = pdpwr.util.load_catalog(catalogPath)
%
%   Returns a struct with one field per sheet:
%     .mosfets   - table  (Manufacturer, PartNumber, Package, Vds_max_V, XML_File, Has_BodyDiode_XML)
%     .diodes    - table  (Manufacturer, PartNumber, Package, Vrev_V, I_A, Rd_a..c, Vto_a..c, PerLeg)
%     .heatsinks - table  (Manufacturer, Profile, ProfileNum, Rth_natural_CW, Rth_forced_CW, Height_mm, Width_mm, Convection_Notes)
%     .magmattec - table  (Material, Product, Code, AL_nHesp2, OD/ID/HT_mm, Le_mm, Ae_mm2, Ve_mm3, As_mm2, Mass_g)
%     .magnetics - table  (Material, PartNumber, Permeability, AL_nHesp2, Le_mm, Ae_mm2, Ve_mm3, OD_mm, ID_mm, HT_mm)
%     .trafos    - table  (Material, PartNumber, AL_nHesp2, geometry, Manufacturer, Geometry)
%     .steinmetz - table  (MaterialID, Material, alpha, beta, k, c1_T, c2_T, c3_T, k_iGSE)
%     .awg       - table  (AWG, r_awg_ohm_per_m, Aawg_cm2, Dext_cm)
%     .path      - char   absolute path to the Catalog.xlsx that was loaded

    if nargin < 1 || isempty(catalogPath)
        % data_root() works from source AND from the compiled .exe (ctfroot).
        catalogPath = fullfile(pdpwr.util.data_root(), 'data', 'Catalog.xlsx');
    end

    if exist(catalogPath, 'file') ~= 2
        error('pdpwr:catalogNotFound', 'Catalog.xlsx not found at: %s', catalogPath);
    end

    opts = detectImportOptions(catalogPath, 'Sheet', 'MOSFETs_PLECS');
    catalog.mosfets   = readtable(catalogPath, setvartype(opts, opts.VariableNames(strcmp(opts.VariableTypes,'char')), 'string'));

    catalog.diodes    = readtable(catalogPath, 'Sheet', 'Diodes');
    catalog.heatsinks = readtable(catalogPath, 'Sheet', 'Heatsinks');
    catalog.magmattec = readtable(catalogPath, 'Sheet', 'Cores_Magmattec');
    catalog.magnetics = readtable(catalogPath, 'Sheet', 'Cores_Magnetics');
    catalog.trafos    = readtable(catalogPath, 'Sheet', 'Cores_Trafos');
    catalog.steinmetz = readtable(catalogPath, 'Sheet', 'Steinmetz');
    catalog.awg       = readtable(catalogPath, 'Sheet', 'AWG_Table');
    % Per-material, per-permeability curve-fit coefficients (Magnetics):
    % roll-off mi_a/mi_b/mi_c and core-loss P_a/P_b/P_c. Used by the inductor
    % so each material uses its OWN curve instead of one shared (MPP-40) fit.
    catalog.curvefit  = readtable(catalogPath, 'Sheet', 'Magnetics_CurveFit');

    catalog.path = catalogPath;
end
