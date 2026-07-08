%% Task 3-1: Extract cloud-property statistics around the typhoon center
% Input : Task.xlsx from Task 1 and matching Himawari-8 L2 cloud product nc files.
% Output: Task3_center_cloud_stats_0806_0811.xlsx with 10x10-pixel mean/median values.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
centerExcel = fullfile(projectRoot, 'Task.xlsx');
dataRoot = fullfile(projectRoot, char([27599 22825 22235 20010 26102 21051]));
plotRangeTag = '0806_0811';
outputExcel = fullfile(projectRoot, ['Task3_center_cloud_stats_', plotRangeTag, '.xlsx']);

% The PPT requires at least four times per day. These should match Task 1.
targetTimes = {'0100', '0300', '0500', '0700'};

% Analyze only the stage requested for the report.
plotStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
plotEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);

% PPT requirement: typhoon-center surrounding daytime 10x10 pixels.
windowSizePixels = 10;

% Himawari full-disk grid used in this experiment after the transpose fix.
gridOriginLat = 60;
gridOriginLon = 80;
gridSpacingDeg = 0.05;

% Variable-name candidates. Add names here if ncdisp shows different names.
varCandidates.COT = {'CLOT', 'COT', 'cot', 'clot', 'Cloud_Optical_Thickness', ...
    'cloud_optical_thickness', 'CloudOpticalThickness'};
varCandidates.CER = {'CLER', 'CER', 'cer', 'clre', 'Cloud_Effective_Radius', ...
    'cloud_effective_radius', 'CloudEffectiveRadius', 'REF'};
varCandidates.CTT = {'CLTT', 'CTT', 'ctt', 'Cloud_Top_Temperature', ...
    'cloud_top_temperature', 'CloudTopTemperature'};
varCandidates.CTH = {'CLTH', 'CTH', 'cth', 'Cloud_Top_Height', ...
    'cloud_top_height', 'CloudTopHeight'};
varCandidates.CloudType = {'CLTYPE', 'CLT', 'cloud_type', 'Cloud_Type', ...
    'CloudType', 'CTYPE'};

properties = {'COT', 'CER', 'CTT', 'CTH', 'CloudType'};

%% Read and filter typhoon centers
if ~isfile(centerExcel)
    error('Cannot find Task 1 center table: %s', centerExcel);
end

centerTable = readtable(centerExcel, 'VariableNamingRule', 'preserve');
if height(centerTable) == 0
    error('Task.xlsx has no typhoon-center rows.');
end

centerTable = normalizeCenterTable(centerTable);
centerTable = sortrows(centerTable, 'TimeUTC');

timeMask = centerTable.TimeUTC >= plotStartTimeUTC & centerTable.TimeUTC <= plotEndTimeUTC;
if ~isempty(targetTimes)
    timeMask = timeMask & ismember(string(centerTable.HHMM), string(targetTimes));
end
centerTable = centerTable(timeMask, :);

if height(centerTable) == 0
    error('No typhoon-center rows found in the selected Task 3 time range.');
end

warnIfDailyTimesAreMissing(centerTable, targetTimes);

%% Extract 10x10-pixel regional statistics
recordCells = {};
uniqueFiles = unique(string(centerTable.FileName), 'stable');

for f = 1:numel(uniqueFiles)
    originalFile = char(uniqueFiles(f));
    file = originalFile;
    if ~isfile(file)
        file = resolveNcFile(file, dataRoot);
    end

    fprintf('\nReading nc file:\n%s\n', file);
    cloud = readCloudProperties(file, varCandidates);
    [nRows, nCols] = size(cloud.COT);

    rowsForFile = find(strcmp(string(centerTable.FileName), string(uniqueFiles(f))));
    for ii = 1:numel(rowsForFile)
        centerIdx = rowsForFile(ii);
        row0 = round(centerTable.PixelRow(centerIdx));
        col0 = round(centerTable.PixelCol(centerIdx));

        if row0 < 1 || row0 > nRows || col0 < 1 || col0 > nCols
            warning('Center row/col is outside the data array. Skipping %s.', ...
                string(centerTable.TimeUTC(centerIdx)));
            continue;
        end

        rowWindow = centeredWindowIndices(row0, nRows, windowSizePixels);
        colWindow = centeredWindowIndices(col0, nCols, windowSizePixels);

        record = buildBaseRecord(centerTable(centerIdx, :), file, row0, col0, ...
            rowWindow, colWindow, gridOriginLat, gridOriginLon, gridSpacingDeg);

        for p = 1:numel(properties)
            property = properties{p};
            stats = summarizeRegion(cloud.(property), rowWindow, colWindow);
            record.([property, '_Mean']) = stats.Mean;
            record.([property, '_Median']) = stats.Median;
            record.([property, '_ValidCount']) = stats.ValidCount;
            record.([property, '_ValidFraction']) = stats.ValidFraction;

            if strcmpi(property, 'CloudType')
                record.CloudType_Mode = stats.Mode;
            end
        end

        recordCells{end + 1, 1} = record; %#ok<SAGROW>
        fprintf('Extracted %s UTC, center row=%d col=%d, region=%dx%d pixels.\n', ...
            datestr(record.TimeUTC, 'yyyy-mm-dd HH:MM'), row0, col0, ...
            numel(rowWindow), numel(colWindow));
    end
end

if isempty(recordCells)
    error('No center-region cloud statistics were extracted.');
end

statsTable = struct2table(vertcat(recordCells{:}));
statsTable = sortrows(statsTable, 'TimeUTC');
settingsTable = buildSettingsTable(plotStartTimeUTC, plotEndTimeUTC, ...
    targetTimes, windowSizePixels, gridOriginLat, gridOriginLon, gridSpacingDeg);

if isfile(outputExcel)
    delete(outputExcel);
end
writetable(statsTable, outputExcel, 'Sheet', 'Center_10x10_Stats');
writetable(settingsTable, outputExcel, 'Sheet', 'Settings');

fprintf('\nSaved Task 3 center-region statistics:\n%s\n', outputExcel);
fprintf('Rows in Center_10x10_Stats: %d\n', height(statsTable));

%% Helper functions
function record = buildBaseRecord(centerRow, file, row0, col0, rowWindow, colWindow, ...
        gridOriginLat, gridOriginLon, gridSpacingDeg)
    centerLat = gridOriginLat - gridSpacingDeg * (col0 - 1);
    centerLon = gridOriginLon + gridSpacingDeg * (row0 - 1);

    latValues = gridOriginLat - gridSpacingDeg * (colWindow - 1);
    lonValues = gridOriginLon + gridSpacingDeg * (rowWindow - 1);

    record.TimeUTC = centerRow.TimeUTC;
    record.TimeTextUTC = string(datestr(centerRow.TimeUTC, 'yyyy-mm-dd HH:MM'));
    record.DateUTC = string(centerRow.DateUTC);
    record.HHMM = string(centerRow.HHMM);
    record.FileName = string(file);
    record.CenterPixelRow = row0;
    record.CenterPixelCol = col0;
    record.CenterLatitude = centerLat;
    record.CenterLongitude = centerLon;
    record.WindowSizePixels = numel(rowWindow) * numel(colWindow);
    record.RowStart = rowWindow(1);
    record.RowEnd = rowWindow(end);
    record.ColStart = colWindow(1);
    record.ColEnd = colWindow(end);
    record.LatitudeMin = min(latValues);
    record.LatitudeMax = max(latValues);
    record.LongitudeMin = min(lonValues);
    record.LongitudeMax = max(lonValues);
end

function idx = centeredWindowIndices(centerIdx, maxIdx, windowSize)
    if maxIdx <= windowSize
        idx = (1:maxIdx).';
        return;
    end

    before = floor((windowSize - 1) / 2);
    after = windowSize - before - 1;
    startIdx = centerIdx - before;
    endIdx = centerIdx + after;

    if startIdx < 1
        endIdx = endIdx + (1 - startIdx);
        startIdx = 1;
    end
    if endIdx > maxIdx
        startIdx = startIdx - (endIdx - maxIdx);
        endIdx = maxIdx;
    end

    startIdx = max(1, startIdx);
    endIdx = min(maxIdx, endIdx);
    idx = (startIdx:endIdx).';
end

function stats = summarizeRegion(data, rowWindow, colWindow)
    values = data(rowWindow, colWindow);
    values = values(:);
    finiteValues = values(isfinite(values));

    stats.ValidCount = numel(finiteValues);
    stats.ValidFraction = numel(finiteValues) / numel(values);
    stats.Mean = meanFinite(finiteValues);
    stats.Median = medianFinite(finiteValues);
    stats.Mode = modeFinite(finiteValues);
end

function value = meanFinite(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = mean(values);
    end
end

function value = medianFinite(values)
    values = sort(values(isfinite(values)));
    if isempty(values)
        value = NaN;
        return;
    end

    n = numel(values);
    if mod(n, 2) == 1
        value = values((n + 1) / 2);
    else
        value = 0.5 * (values(n / 2) + values(n / 2 + 1));
    end
end

function value = modeFinite(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = mode(values);
    end
end

function settingsTable = buildSettingsTable(startTime, endTime, targetTimes, ...
        windowSizePixels, gridOriginLat, gridOriginLon, gridSpacingDeg)
    items = [
        "AnalysisTimeRangeUTC"
        "TargetTimesUTC"
        "CenterRegion"
        "GridOriginLatitude"
        "GridOriginLongitude"
        "GridSpacingDegree"
        "LatitudeFormula"
        "LongitudeFormula"
        ];
    values = [
        string(datestr(startTime, 'yyyy-mm-dd HH:MM')) + " to " + string(datestr(endTime, 'yyyy-mm-dd HH:MM'))
        strjoin(string(targetTimes), ", ")
        string(sprintf('%dx%d pixels around the typhoon center', windowSizePixels, windowSizePixels))
        string(gridOriginLat)
        string(gridOriginLon)
        string(gridSpacingDeg)
        "lat = 60 - 0.05 * (PixelCol - 1)"
        "lon = 80 + 0.05 * (PixelRow - 1)"
        ];
    settingsTable = table(items, values, 'VariableNames', {'Item', 'Value'});
end

function warnIfDailyTimesAreMissing(centerTable, targetTimes)
    if isempty(targetTimes)
        return;
    end

    dayValues = unique(dateshift(centerTable.TimeUTC, 'start', 'day'));
    for i = 1:numel(dayValues)
        mask = dateshift(centerTable.TimeUTC, 'start', 'day') == dayValues(i);
        foundTimes = unique(string(centerTable.HHMM(mask)));
        missingTimes = setdiff(string(targetTimes), foundTimes);
        if ~isempty(missingTimes)
            warning('Date %s is missing target times: %s', ...
                datestr(dayValues(i), 'yyyy-mm-dd'), strjoin(missingTimes, ', '));
        end
    end
end

function centerTable = normalizeCenterTable(centerTable)
    centerTable.TimeUTC = parseTimeColumn(centerTable, 'TimeUTC');
    centerTable.PixelRow = readNumericColumn(centerTable, {'PixelRow', 'Row'});
    centerTable.PixelCol = readNumericColumn(centerTable, {'PixelCol', 'Col'});

    if hasAnyColumn(centerTable, {'DateUTC'})
        centerTable.DateUTC = string(centerTable.(findColumnName(centerTable, {'DateUTC'}, true)));
    else
        centerTable.DateUTC = string(datestr(centerTable.TimeUTC, 'yyyymmdd'));
    end

    if hasAnyColumn(centerTable, {'HHMM'})
        raw = centerTable.(findColumnName(centerTable, {'HHMM'}, true));
        if isnumeric(raw)
            centerTable.HHMM = string(compose('%04.0f', raw));
        else
            centerTable.HHMM = pad(strtrim(string(raw)), 4, 'left', '0');
        end
    else
        centerTable.HHMM = string(datestr(centerTable.TimeUTC, 'HHMM'));
    end

    if hasAnyColumn(centerTable, {'FileName'})
        centerTable.FileName = string(centerTable.(findColumnName(centerTable, {'FileName'}, true)));
    else
        centerTable.FileName = strings(height(centerTable), 1);
    end
end

function cloud = readCloudProperties(file, varCandidates)
    info = ncinfo(file);

    cotName = findNcVariable(info, varCandidates.COT, 'cloud optical thickness');
    cloud.COT = readNcClean(file, cotName, 'cot');
    baseSize = size(cloud.COT);

    cloud.CER = readOptionalCloudVariable(file, info, varCandidates.CER, 'cer', baseSize);
    cloud.CTT = readOptionalCloudVariable(file, info, varCandidates.CTT, 'ctt', baseSize);
    cloud.CTH = readOptionalCloudVariable(file, info, varCandidates.CTH, 'cth', baseSize);
    cloud.CloudType = readOptionalCloudVariable(file, info, varCandidates.CloudType, 'cloudtype', baseSize);
end

function data = readOptionalCloudVariable(file, info, candidates, kind, baseSize)
    varName = findNcVariableOptional(info, candidates);
    if isempty(varName)
        warning('Cannot find variable for %s. Filling this property with NaN.', kind);
        data = NaN(baseSize);
        return;
    end

    data = readNcClean(file, varName, kind);
    data = alignDataSize(data, baseSize, kind);
end

function data = alignDataSize(data, baseSize, label)
    data = squeeze(data);
    if isequal(size(data), baseSize)
        return;
    end
    if ismatrix(data) && isequal(size(data.'), baseSize)
        data = data.';
        return;
    end
    warning('%s has size [%s], expected [%s]. Filling with NaN.', ...
        label, num2str(size(data)), num2str(baseSize));
    data = NaN(baseSize);
end

function data = readNcClean(file, varName, kind)
    varInfo = ncinfo(file, varName);
    raw = ncread(file, varName);
    rawClass = class(raw);
    data = double(squeeze(raw));

    attrs = varInfo.Attributes;
    data = maskAttributeValues(data, attrs, {'_FillValue', 'missing_value'});
    data(abs(data) > 1.0e30) = NaN;
    data(data < -1.0e20) = NaN;

    data = applyScaleOffsetIfNeeded(data, attrs, rawClass, kind);
    data = maskValidRange(data, attrs);
    data = cleanByKind(data, kind);
end

function data = applyScaleOffsetIfNeeded(data, attrs, rawClass, kind)
    scaleFactor = scalarAttributeOrEmpty(getAttribute(attrs, 'scale_factor'));
    addOffset = scalarAttributeOrEmpty(getAttribute(attrs, 'add_offset'));

    if isempty(scaleFactor)
        return;
    end
    if isempty(addOffset)
        addOffset = 0;
    end

    finiteData = data(isfinite(data));
    if isempty(finiteData)
        return;
    end

    shouldScale = isintegerType(rawClass) || max(abs(finiteData)) > plausibleMaxBeforeScale(kind);
    if shouldScale
        data = data .* scaleFactor + addOffset;
    end
end

function tf = isintegerType(className)
    tf = any(strcmp(className, {'int8', 'uint8', 'int16', 'uint16', ...
        'int32', 'uint32', 'int64', 'uint64'}));
end

function value = plausibleMaxBeforeScale(kind)
    switch lower(kind)
        case 'cot'
            value = 300;
        case 'cer'
            value = 200;
        case 'ctt'
            value = 400;
        case 'cth'
            value = 50000;
        case 'cloudtype'
            value = 50;
        otherwise
            value = Inf;
    end
end

function data = cleanByKind(data, kind)
    switch lower(kind)
        case 'cot'
            data(data < 0 | data > 300) = NaN;
        case 'cer'
            data(data < 0 | data > 200) = NaN;
        case 'ctt'
            data(data < 100 | data > 400) = NaN;
        case 'cth'
            data(data < 0 | data > 50000) = NaN;
            finiteData = data(isfinite(data));
            if ~isempty(finiteData) && percentileValue(finiteData, 95) > 1000
                data = data / 1000; % meters to kilometers.
            end
        case 'cloudtype'
            data(data < 0 | data > 50) = NaN;
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

function varName = findNcVariable(info, candidates, label)
    varName = findNcVariableOptional(info, candidates);
    if isempty(varName)
        error('Could not find %s variable. Use ncdisp(file) and add its name to candidates.', label);
    end
end

function varName = findNcVariableOptional(info, candidates)
    allNames = collectNcVariableNames(info, '');
    varName = '';

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

function file = resolveNcFile(file, dataRoot)
    [~, name, ext] = fileparts(file);
    targetName = [name, ext];
    matches = dir(fullfile(dataRoot, '**', targetName));
    if isempty(matches)
        error('Cannot find nc file: %s', file);
    end
    file = fullfile(matches(1).folder, matches(1).name);
end

function timeValues = parseTimeColumn(tableData, columnName)
    raw = tableData.(findColumnName(tableData, {columnName}, true));
    if isdatetime(raw)
        timeValues = raw(:);
    elseif isnumeric(raw)
        timeValues = datetime(raw(:), 'ConvertFrom', 'excel');
    else
        textValues = strtrim(string(raw(:)));
        timeValues = NaT(size(textValues));
        formats = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', ...
            'yyyy/MM/dd HH:mm:ss', 'yyyy/MM/dd HH:mm', ...
            'yyyyMMdd HHmm', 'yyyy-MM-dd HHmm', 'yyyy/MM/dd HHmm'};
        for i = 1:numel(formats)
            idx = isnat(timeValues) & strlength(textValues) > 0;
            if ~any(idx)
                break;
            end
            try
                timeValues(idx) = datetime(textValues(idx), 'InputFormat', formats{i});
            catch
            end
        end
        idx = isnat(timeValues) & strlength(textValues) > 0;
        if any(idx)
            try
                timeValues(idx) = datetime(textValues(idx));
            catch
            end
        end
    end
end

function values = readNumericColumn(tableData, candidates)
    raw = tableData.(findColumnName(tableData, candidates, true));
    if isnumeric(raw)
        values = double(raw);
    else
        values = str2double(string(raw));
    end
    values = values(:);
end

function tf = hasAnyColumn(tableData, candidates)
    tf = ~isempty(findColumnName(tableData, candidates, false));
end

function name = findColumnName(tableData, candidates, mustExist)
    names = string(tableData.Properties.VariableNames);
    name = '';
    for i = 1:numel(candidates)
        idx = find(strcmpi(names, candidates{i}), 1);
        if ~isempty(idx)
            name = char(names(idx));
            return;
        end
    end
    if mustExist
        error('Cannot find any of these columns: %s', strjoin(candidates, ', '));
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

function p = percentileValue(values, percent)
    values = sort(values(:));
    values = values(isfinite(values));
    if isempty(values)
        p = NaN;
        return;
    end

    idx = max(1, min(numel(values), round(percent / 100 * numel(values))));
    p = values(idx);
end
