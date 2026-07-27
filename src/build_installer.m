function build_installer(runtimeMode)
%BUILD_INSTALLER One-command build of the Power Density Tool standalone + installer.
%
%   build_installer            % default: 'web' runtime (small installer)
%   build_installer('web')     % installer downloads the MATLAB Runtime at
%                              % install time (needs internet on the user's PC)
%   build_installer('included')% installer EMBEDS the Runtime (offline, ~2-4 GB,
%                              % slow to build) - fully autonomous
%
%   Requires the MATLAB Compiler (check with license('test','Compiler')).
%   Output:
%     ../build/setup/MyAppInstaller.exe   <- the ONLY thing to distribute.
%   The intermediate build/app (raw .exe) is created then DELETED, because the
%   bare .exe proved unreliable on some machines and must be INSTALLED.
%
%   Re-run after any code/catalog change to regenerate everything. The old
%   build is wiped first, so no stale installer ever lingers.

    if nargin < 1 || isempty(runtimeMode), runtimeMode = 'web'; end
    runtimeMode = validatestring(runtimeMode, {'web','included'});

    here = fileparts(mfilename('fullpath'));   % ...\src
    root = fileparts(here);                    % ...\PowerDensityTool

    mainFile = fullfile(here, 'PowerDensityApp.m');
    addFiles = { fullfile(here,'+pdpwr'), ...
                 fullfile(here,'+test'), ...
                 fullfile(root,'data'), ...
                 fullfile(root,'assets') };
    outStandalone = fullfile(root,'build','app');     % the runnable .exe
    outInstaller  = fullfile(root,'build','setup');   % the installer for other PCs

    % --- Wipe the previous build so no OLD .exe is left behind ---
    for d = {outStandalone, outInstaller}
        if exist(d{1}, 'dir') == 7
            fprintf('   Removing previous build: %s\n', d{1});
            try, rmdir(d{1}, 's'); catch, end
        end
    end

    fprintf('[1/2] Compiling standalone application...\n');
    buildResults = compiler.build.standaloneApplication( mainFile, ...
        'AdditionalFiles', addFiles, ...
        'ExecutableName',  'PowerDensityApp', ...
        'OutputDir',       outStandalone, ...
        'Verbose',         'on');

    fprintf('[2/2] Packaging installer (RuntimeDelivery = %s)...\n', runtimeMode);
    if strcmp(runtimeMode,'included')
        rt = 'installer';
        % The OFFLINE installer must embed the MATLAB Runtime, which has to be
        % downloaded to this machine once (~2-4 GB, needs internet). After that
        % the produced installer is fully offline-distributable.
        try
            fprintf('   Ensuring MATLAB Runtime installer is available (may download ~2-4 GB)...\n');
            compiler.runtime.download;
        catch dlErr
            warning('build_installer:runtime', ...
                ['Could not download the MATLAB Runtime (%s).\n' ...
                 'Falling back to the WEB installer (downloads the Runtime on the ' ...
                 'user PC at install time).'], dlErr.message);
            rt = 'web';
        end
    else
        rt = 'web';
    end
    compiler.package.installer( buildResults, ...
        'ApplicationName', 'Power Density Tool', ...
        'AuthorName',      'Joao Rodrigo Arnaud da Cruz', ...
        'Version',         '1.0', ...
        'RuntimeDelivery', rt, ...
        'OutputDir',       outInstaller);

    % The installer already contains the whole application, so REMOVE the raw
    % build/app folder: the bare .exe proved unreliable on some machines (it
    % must be properly INSTALLED via the installer). The only distributable left
    % is therefore build/setup/MyAppInstaller.exe.
    if exist(outStandalone, 'dir') == 7
        try, rmdir(outStandalone, 's'); catch, end
    end

    fprintf('\nDONE. Distribute this installer:\n  %s\n', ...
        fullfile(outInstaller, 'MyAppInstaller.exe'));
end
