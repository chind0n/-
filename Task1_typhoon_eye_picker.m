 %% Task 1: Pick typhoon-eye positions from Himawari-8 L2 cloud products
% Usage:
% 1. Change only dataRoot below if your data folder changes.
% 2. Run this script in Matlab.
% 3. For each cloud optical thickness image:
%    - use the figure toolbar to zoom/pan to the typhoon eye,
%    - return to the Command Window and press any key,
%    - click the typhoon-eye center once.
%    Press Enter instead of clicking to skip the current file.
% 4. Every picked point is written to Task.xlsx immediately.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
dataRoot = fullfile(projectRoot, '每天四个时刻');   % <-- Folder that contains the copied .nc files.
outputExcel = fullfile(projectRoot, 'Task.xlsx');
selectedFolderName = char([27599 22825 22235 20010 26102 21051]);
dataRoot = fullfile(projectRoot, selectedFolderName);

% The PPT requires at least 4 times per day. Empty {} means process all .nc files.
targetTimes = {'0100', '0300', '0500', '0700'};

% Optional date filter. Use 'yyyymmdd', or leave '' to process all dates.
startDate = '20190804';
endDate = '20190814';

% false: append to existing Task.xlsx and de-duplicate by FileName.
% true : rebuild Task.xlsx from this run only.
resetOutput = false;

% Keep this false while you are learning the data. If true, the next image
% opens near the previous click, which can look all blue when the center moves.
usePreviousWindow = false;
windowHalfWidth = 280;   % pixels/columns
windowHalfHeight = 280;  % pixels/rows

%% Variable-name candidates for this Himawari-8 product
latCandidates = {'latitude', 'lat', 'Latitude', 'LAT'};
lonCandidates = {'longitude', 'lon', 'Longitude', 'LON'};
cotCandidates = { ...
    'CLOT', 'cot', 'COT', 'cloud_optical_thickness', ...
    'Cloud_Optical_Thickness', 'cld_optical_thickness', 'tau', 'TAU'};

resultColumns = { ...
    'TimeUTC', 'PixelRow', 'PixelCol', 'Latitude', 'Longitude', ...
    'DateUTC', 'HHMM', 'FileName', 'MouseButton'};

%% Find and filter files
records = buildFileRecords(dataRoot, targetTimes, startDate, endDate);

if isempty(records)
    error('No matching .nc files were found under: %s', dataRoot);
end

fprintf('Found %d matching files under:\n%s\n\n', numel(records), dataRoot);
fprintf('Output Excel:\n%s\n\n', outputExcel);
fprintf('Close Task.xlsx in Excel before continuing, otherwise Matlab may not be able to write it.\n');
input('Press Enter to start picking typhoon-eye centers...', 's');

%% Process each file interactively
resultTable = loadExistingResultTable(outputExcel, resultColumns, resetOutput);
lastRow = NaN;
lastCol = NaN;

for k = 1:numel(records)
    file = records(k).FullName;
    timeText = records(k).TimeText;

    fprintf('\n[%d/%d] %s\n%s\n', k, numel(records), timeText, file);

    try
        info = ncinfo(file);
        latName = findNcVariable(info, latCandidates, 'latitude');
        lonName = findNcVariable(info, lonCandidates, 'longitude');
        cotName = findNcVariable(info, cotCandidates, 'cloud optical thickness');

        lat = readNcClean(file, latName, 'coordinate');
        lon = readNcClean(file, lonName, 'coordinate');
        cot = readNcClean(file, cotName, 'cot');
        cot = squeeze(cot);
        plotData = makeCotDisplayData(cot);
        displayData = plotData.';

        [lat, lon] = alignCoordinatesToData(lat, lon, cot);
        [nRows, nCols] = size(cot);
        [displayRows, displayCols] = size(displayData);
        printDataStats(cotName, cot, plotData);

        fig = figure('Name', sprintf('Pick eye: %s', timeText), 'Color', 'w');
        imagesc(displayData);
        axis image;
        colormap(jet);
        colorbar;
        title({ ...
            sprintf('%s  |  transposed log10(%s + 1), for display only', timeText, cotName), ...
            'Zoom/pan with the toolbar, press any key in Command Window, then click the eye center. Press Enter to skip.'}, ...
            'Interpreter', 'none');
        xlabel('Data row');
        ylabel('Data column');
        applyRobustColorLimits(displayData);

        if usePreviousWindow && isfinite(lastRow) && isfinite(lastCol)
            x1 = max(1, lastRow - windowHalfWidth);
            x2 = min(displayCols, lastRow + windowHalfWidth);
            y1 = max(1, lastCol - windowHalfHeight);
            y2 = min(displayRows, lastCol + windowHalfHeight);
            xlim([x1, x2]);
            ylim([y1, y2]);
            hold on;
            plot(lastRow, lastCol, 'wo', 'MarkerSize', 12, 'LineWidth', 1.5);
            plot(lastRow, lastCol, 'k+', 'MarkerSize', 12, 'LineWidth', 1.5);
        end

        zoom on;
        fprintf('Use the figure toolbar to zoom/pan, then return here and press any key.\n');
        pause;
        zoom off;

        fprintf('Click the typhoon-eye center in the figure, or press Enter to skip this file.\n');
        [x, y, button] = ginput(1);

        if isempty(x) || isempty(y)
            fprintf('Skipped.\n');
            close(fig);
            continue;
        end

        displayCol = round(x);
        displayRow = round(y);

        if displayRow < 1 || displayRow > displayRows || displayCol < 1 || displayCol > displayCols
            warning('Clicked point is outside the data array. Skipping this file.');
            close(fig);
            continue;
        end

        row = displayCol;
        col = displayRow;
        [latEye, lonEye] = lookupLatLon(lat, lon, row, col);

        hold on;
        plot(displayCol, displayRow, 'rx', 'MarkerSize', 14, 'LineWidth', 2);
        drawnow;

        fprintf('Clicked display x=%d, y=%d -> data row=%d, col=%d, lat=%.6f, lon=%.6f\n', ...
            displayCol, displayRow, row, col, latEye, lonEye);

        newRow = table( ...
            string(timeText), row, col, latEye, lonEye, string(records(k).DateText), ...
            string(records(k).HHMM), string(file), button, 'VariableNames', resultColumns);

        resultTable = mergeTablesByFileName(resultTable, newRow);
        resultTable = sortrows(resultTable, 'TimeUTC');
        saveResultTable(outputExcel, resultTable, dataRoot);

        lastRow = row;
        lastCol = col;
        close(fig);

    catch ME
        if exist('fig', 'var') && isvalid(fig)
            close(fig);
        end
        warning('Failed to process file:\n%s\nReason: %s', file, ME.message);
        printErrorStack(ME);
    end
end

fprintf('\nFinished. Current result rows in Task.xlsx: %d\n', height(resultTable));

%% Local functions
function records = buildFileRecords(dataRoot, targetTimes, startDate, endDate)
    files = listNcFiles(dataRoot);
    records = struct('FullName', {}, 'DateText', {}, 'HHMM', {}, 'TimeNum', {}, 'TimeText', {});

    for i = 1:numel(files)
        [~, name, ext] = fileparts(files{i});
        token = regexp([name, ext], 'NC_H08_(\d{8})_(\d{4})_', 'tokens', 'once');
        if isempty(token)
            continue;
        end

        dateText = token{1};
        hhmm = token{2};

        if ~isempty(targetTimes) && ~ismember(hhmm, targetTimes)
            continue;
        end
        if ~isempty(startDate) && str2double(dateText) < str2double(startDate)
            continue;
        end
        if ~isempty(endDate) && str2double(dateText) > str2double(endDate)
            continue;
        end

        timeNum = datenum([dateText, hhmm], 'yyyymmddHHMM');
        records(end + 1).FullName = files{i}; %#ok<AGROW>
        records(end).DateText = dateText;
        records(end).HHMM = hhmm;
        records(end).TimeNum = timeNum;
        records(end).TimeText = datestr(timeNum, 'yyyy-mm-dd HH:MM');
    end

    if ~isempty(records)
        [~, order] = sort([records.TimeNum]);
        records = records(order);
    end
end

function files = listNcFiles(rootDir)
    files = {};
    listing = dir(rootDir);

    for i = 1:numel(listing)
        name = listing(i).name;
        if strcmp(name, '.') || strcmp(name, '..')
            continue;
        end

        fullName = fullfile(rootDir, name);
        if listing(i).isdir
            files = [files; listNcFiles(fullName)]; %#ok<AGROW>
        else
            [~, ~, ext] = fileparts(name);
            if strcmpi(ext, '.nc')
                files{end + 1, 1} = fullName; %#ok<AGROW>
            end
        end
    end
end

function varName = findNcVariable(info, candidates, label)
    allNames = collectNcVariableNames(info, '');

    for i = 1:numel(candidates)
        idx = find(strcmpi(allNames, candidates{i}), 1);
        if ~isempty(idx)
            varName = allNames{idx};
            return;
        end
    end

    for i = 1:numel(candidates)
        for j = 1:numel(allNames)
            if contains(lower(allNames{j}), lower(candidates{i}))
                varName = allNames{j};
                return;
            end
        end
    end

    error('Could not find %s variable. Check ncdisp(file) and add its name to the candidate list.', label);
end

function names = collectNcVariableNames(info, prefix)
    names = {};

    for i = 1:numel(info.Variables)
        names{end + 1, 1} = [prefix, info.Variables(i).Name]; %#ok<AGROW>
    end

    for g = 1:numel(info.Groups)
        groupPrefix = [prefix, '/', info.Groups(g).Name, '/'];
        names = [names; collectNcVariableNames(info.Groups(g), groupPrefix)]; %#ok<AGROW>
    end
end

function data = readNcClean(file, varName, kind)
    varInfo = ncinfo(file, varName);
    data = double(squeeze(ncread(file, varName)));
    data = double(squeeze(data));

    data(abs(data) > 1.0e30) = NaN;
    data(data < -1.0e20) = NaN;

    attrs = varInfo.Attributes;
    data = maskAttributeValues(data, attrs, {'_FillValue', 'missing_value'});
    data = maskValidRange(data, attrs);

    switch lower(kind)
        case 'cot'
            data = scalePackedCotIfNeeded(data, attrs);
            % COT is normally non-negative and usually below a few hundred.
            % Very large values are almost always packed fill values.
            data(data < 0 | data > 300) = NaN;
        case 'coordinate'
            data(abs(data) > 1000) = NaN;
    end
end

function data = scalePackedCotIfNeeded(data, attrs)
    finiteData = data(isfinite(data));
    if isempty(finiteData) || max(finiteData) <= 300
        return;
    end

    scaleFactor = getAttribute(attrs, 'scale_factor');
    addOffset = getAttribute(attrs, 'add_offset');

    scaleFactor = scalarAttributeOrEmpty(scaleFactor);
    addOffset = scalarAttributeOrEmpty(addOffset);

    if isempty(addOffset)
        addOffset = 0;
    end

    if ~isempty(scaleFactor) && abs(scaleFactor) < 1
        scaled = data .* scaleFactor + addOffset;
        scaledFinite = scaled(isfinite(scaled));
        if ~isempty(scaledFinite) && max(scaledFinite) <= 300
            data = scaled;
        end
    end
end

function data = maskAttributeValues(data, attrs, attrNames)
    for i = 1:numel(attrNames)
        value = getAttribute(attrs, attrNames{i});
        if isempty(value) || ~isnumeric(value)
            continue;
        end

        values = double(value(:));
        for j = 1:numel(values)
            data(data == values(j)) = NaN;
        end
    end
end

function data = maskValidRange(data, attrs)
    validRange = getAttribute(attrs, 'valid_range');
    validMin = getAttribute(attrs, 'valid_min');
    validMax = getAttribute(attrs, 'valid_max');

    if isnumeric(validRange) && numel(validRange) >= 2
        lo = double(min(validRange(:)));
        hi = double(max(validRange(:)));
        data(data < lo | data > hi) = NaN;
        return;
    end

    validMin = scalarAttributeOrEmpty(validMin);
    validMax = scalarAttributeOrEmpty(validMax);

    if ~isempty(validMin)
        data(data < validMin) = NaN;
    end
    if ~isempty(validMax)
        data(data > validMax) = NaN;
    end
end

function value = getAttribute(attrs, attrName)
    value = [];
    for i = 1:numel(attrs)
        if strcmpi(attrs(i).Name, attrName)
            value = attrs(i).Value;
            return;
        end
    end
end

function value = scalarAttributeOrEmpty(value)
    if isempty(value) || ~isnumeric(value)
        value = [];
        return;
    end

    value = double(value(:));
    value = value(isfinite(value));

    if isempty(value)
        value = [];
    else
        value = value(1);
    end
end

function plotData = makeCotDisplayData(cot)
    plotData = cot;
    plotData(plotData < 0 | plotData > 300) = NaN;
    plotData = log10(plotData + 1);
end

function printDataStats(varName, cot, plotData)
    raw = cot(isfinite(cot));
    shown = plotData(isfinite(plotData));

    if isempty(raw)
        fprintf('%s has no finite COT values after cleaning. This file is probably unusable.\n', varName);
        return;
    end

    nonZero = raw(raw > 0);
    fprintf('%s cleaned stats: valid=%d, nonzero=%d, min=%g, max=%g\n', ...
        varName, numel(raw), numel(nonZero), min(raw), max(raw));

    if isempty(shown) || max(shown) <= min(shown)
        fprintf('Display data has almost no contrast; this image may look all blue.\n');
    else
        fprintf('Display uses log10(COT+1): min=%g, max=%g\n', min(shown), max(shown));
    end
end

function data = cleanNumeric(data)
    data = double(squeeze(data));
    data(abs(data) > 1.0e30) = NaN;
    data(data < -1.0e20) = NaN;
end

function [lat, lon] = alignCoordinatesToData(lat, lon, data)
    lat = squeeze(lat);
    lon = squeeze(lon);

    if ismatrix(lat) && ~isequal(size(lat), size(data)) && isequal(size(lat'), size(data))
        lat = lat';
    end

    if ismatrix(lon) && ~isequal(size(lon), size(data)) && isequal(size(lon'), size(data))
        lon = lon';
    end
end

function [latEye, lonEye] = lookupLatLon(~, ~, row, col)
    gridOriginLat = 60;
    gridOriginLon = 80;
    gridSpacingDeg = 0.05;

    latEye = gridOriginLat - gridSpacingDeg * (col - 1);
    lonEye = gridOriginLon + gridSpacingDeg * (row - 1);
end

function applyRobustColorLimits(data)
    valid = data(isfinite(data));
    if isempty(valid)
        return;
    end

    positive = valid(valid > 0);
    if ~isempty(positive)
        valid = positive;
    end

    valid = sort(valid(:));
    n = numel(valid);
    lo = 0;
    hi = valid(min(n, max(1, round(0.995 * n))));

    if ~(isfinite(hi) && hi > lo)
        hi = max(valid);
    end

    if isfinite(lo) && isfinite(hi) && hi > lo
        caxis([lo, hi]);
    end
end

function resultTable = loadExistingResultTable(outputExcel, resultColumns, resetOutput)
    if resetOutput || ~isfile(outputExcel)
        resultTable = emptyResultTable(resultColumns);
        return;
    end

    try
        resultTable = readtable(outputExcel, 'TextType', 'string');
    catch
        resultTable = emptyResultTable(resultColumns);
        return;
    end

    if width(resultTable) == 0 || height(resultTable) == 0
        resultTable = emptyResultTable(resultColumns);
        return;
    end

    oldNames = resultTable.Properties.VariableNames;
    oldNames(strcmp(oldNames, 'Row')) = {'PixelRow'};
    oldNames(strcmp(oldNames, 'Col')) = {'PixelCol'};
    resultTable.Properties.VariableNames = oldNames;

    if ~isequal(resultTable.Properties.VariableNames, resultColumns)
        error(['Existing Task.xlsx has columns that do not match this script. ', ...
            'Move or rename it, or set resetOutput = true.']);
    end

    resultTable.TimeUTC = string(resultTable.TimeUTC);
    resultTable.DateUTC = string(resultTable.DateUTC);
    resultTable.HHMM = string(resultTable.HHMM);
    resultTable.FileName = string(resultTable.FileName);
end

function resultTable = emptyResultTable(resultColumns)
    resultTable = table( ...
        strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
        'VariableNames', resultColumns);
end

function saveResultTable(outputExcel, resultTable, dataRoot)
    try
        writetable(resultTable, outputExcel);
        fprintf('Saved %d rows to %s\n', height(resultTable), outputExcel);
    catch ME
        backupFile = fullfile(dataRoot, ['Task_autosave_', datestr(now, 'yyyymmdd_HHMMSS'), '.xlsx']);
        writetable(resultTable, backupFile);
        error(['Could not write Task.xlsx, probably because it is open in Excel.\n', ...
            'I saved a backup instead:\n%s\nOriginal write error: %s'], backupFile, ME.message);
    end
end

function printErrorStack(ME)
    if isempty(ME.stack)
        return;
    end

    fprintf('Error location stack:\n');
    for i = 1:numel(ME.stack)
        fprintf('  %s, line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
end

function allTable = mergeTablesByFileName(oldTable, newTable)
    if width(oldTable) == 0
        allTable = newTable;
        return;
    end

    if ~isequal(oldTable.Properties.VariableNames, newTable.Properties.VariableNames)
        error('Existing Task.xlsx has columns that do not match this script output.');
    end

    if ~ismember('FileName', oldTable.Properties.VariableNames)
        allTable = [oldTable; newTable];
        return;
    end

    allTable = [oldTable; newTable];
    fileNames = cellstr(string(allTable.FileName));
    keep = false(height(allTable), 1);

    for i = height(allTable):-1:1
        if ~any(strcmp(fileNames{i}, fileNames(i + 1:end)))
            keep(i) = true;
        end
    end

    allTable = allTable(keep, :);
end
