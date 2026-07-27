function d = output_dir()
%OUTPUT_DIR A WRITABLE folder for the generated spreadsheets.
%
%   In the compiled standalone, ctfroot is read-only, so the results are
%   written under the user's home folder instead of next to the executable.
%   From source, they go to the project's output/ folder as before.

    if isdeployed
        try
            home = char(java.lang.System.getProperty('user.home'));
        catch
            home = tempdir;
        end
        if isempty(home), home = tempdir; end
        d = fullfile(home, 'PowerDensityTool', 'output');
    else
        d = fullfile(pdpwr.util.data_root(), 'output');
    end
    if exist(d, 'dir') ~= 7
        try, mkdir(d); catch, end
    end
end
