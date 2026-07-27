function folder = save_table(T, basename)
%SAVE_TABLE Write a results table to the output folder as BOTH .xlsx and .csv.
%
%   folder = pdpwr.util.save_table(T, basename)
%
%   T        - a MATLAB table with the results.
%   basename - file name WITHOUT extension, e.g. 'inductor_designs'.
%
%   Writes <output>/<basename>.xlsx and <output>/<basename>.csv (CSV is the most
%   portable format - opens in Excel, LibreOffice, Python/pandas, R, etc.) and
%   returns the output folder so the caller can show it to the user.
%
%   The output folder is pdpwr.util.output_dir(): the project's output/ from
%   source, or ~/PowerDensityTool/output from the compiled .exe.

    folder = pdpwr.util.output_dir();
    stem = fullfile(folder, basename);
    for ext = {'.xlsx', '.csv'}
        f = [stem ext{1}];
        if exist(f, 'file') == 2, try, delete(f); catch, end, end
        try
            writetable(T, f);
        catch
            % xlsx can fail if Excel/COM is unavailable in a deployed app; the
            % CSV still succeeds, which is enough for the user to keep the data.
        end
    end
end
