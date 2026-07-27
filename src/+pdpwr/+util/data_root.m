function root = data_root()
%DATA_ROOT Folder that CONTAINS the packaged 'data' and 'assets' folders.
%
%   Works both when running from source in MATLAB and when running as a
%   compiled standalone (.exe + MATLAB Runtime), where the packaged files are
%   extracted under ctfroot instead of the original source tree.
%
%   Use it as:  fullfile(pdpwr.util.data_root(), 'data', 'Catalog.xlsx')

    persistent cached
    if ~isempty(cached), root = cached; return; end

    if isdeployed
        % mcc places "-a <folder>" arguments under ctfroot, normally preserving
        % the folder name (ctfroot/data, ctfroot/assets). Verify, and if the
        % layout differs, locate the data folder by searching for Catalog.xlsx.
        root = ctfroot;
        if exist(fullfile(root, 'data'), 'dir') ~= 7
            hit = dir(fullfile(root, '**', 'Catalog.xlsx'));
            if ~isempty(hit)
                root = fileparts(hit(1).folder);   % parent of the 'data' folder
            end
        end
    else
        % src/+pdpwr/+util/data_root.m  ->  up 4 levels = project root
        root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    end
    cached = root;
end
