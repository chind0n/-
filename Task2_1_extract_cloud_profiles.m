%% Task 2-1: Extract cloud-property profiles through the typhoon center
% Input : Task.xlsx from Task 1 and matching Himawari-8 L2 cloud product nc files.
% Output: Task2_profiles.xlsx with profile position and cloud properties.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
centerExcel = fullfile(projectRoot, 'Task.xlsx');
dataRoot = fullfile(projectRoot, char([27599 22825 22235 20010 26102 21051]));
outputExcel = fullfile(projectRoot, 'Task2_profiles.xlsx');

% Task 2 analysis period. Task 1 may contain the full 2019-08-04 to
% 2019-08-14 track, but profile analysis uses only 2019-08-06 to 2019-08-11.
analysisStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
analysisEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);

% Extract both cross sections through every center.
% westEast:   varies longitude at fixed latitude.
% southNorth: varies latitude at fixed longitude.
profileDirections = {'westEast', 'southNorth'};
halfWidthPixels = 160;       % 160 pixels = 8 degrees around the center.

% The workbook is compact by default: the main profile table keeps only
% columns needed for plotting and analysis. Set true only if you also need
% the full debug table with file names and center row/column repeated.
writeDetailedProfileSheet = false;

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

%% Read typhoon centers from Task.xlsx
if ~isfile(centerExcel)
    error('Cannot find Task 1 center table: %s', centerExcel);
end

centerTable = readtable(centerExcel, 'VariableNamingRule', 'preserve');
if height(centerTable) == 0
    error('Task.xlsx has no typhoon-center rows.');
end

centerTable = normalizeCenterTable(centerTable);
centerTable = sortrows(centerTable, 'TimeUTC');
centerTable = centerTable(centerTable.TimeUTC >= analysisStartTimeUTC ...
    & centerTable.TimeUTC <= analysisEndTimeUTC, :);
if height(centerTable) == 0
    error('No Task 1 typhoon-center rows found from %s to %s UTC.', ...
        datestr(analysisStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
        datestr(analysisEndTimeUTC, 'yyyy-mm-dd HH:MM'));
end

%% Extract profiles
allProfiles = table();
uniqueFiles = unique(string(centerTable.FileName), 'stable');

for f = 1:numel(uniqueFiles)
    file = char(uniqueFiles(f));
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
            warning('Center row/col is outside the data array. Skipping %s.', string(centerTable.TimeUTC(centerIdx)));
            continue;
        end

        for d = 1:numel(profileDirections)
            direction = profileDirections{d};
            profile = extractOneProfile(cloud, row0, col0, direction, halfWidthPixels, ...
                centerTable(centerIdx, :), gridOriginLat, gridOriginLon, gridSpacingDeg);
            if isempty(allProfiles)
                allProfiles = profile;
            else
                allProfiles = [allProfiles; profile]; %#ok<AGROW>
            end
        end
    end
end

if height(allProfiles) == 0
    error('No profiles were extracted. Check Task.xlsx and nc file paths.');
end

allProfiles = sortrows(allProfiles, {'TimeUTC', 'ProfileDirection', 'SampleIndex'});
profiles = buildLeanProfileTable(allProfiles);
profilesByTemperature = profiles(isfinite(profiles.CTT), :);
profilesByTemperature = sortrows(profilesByTemperature, 'CTT');
profileMetadata = buildProfileMetadataTable(allProfiles, halfWidthPixels);

if isfile(outputExcel)
    delete(outputExcel);
end

writetable(profiles, outputExcel, 'Sheet', 'Profiles');
writetable(profilesByTemperature, outputExcel, 'Sheet', 'Profiles_ByCTT');
writetable(profileMetadata, outputExcel, 'Sheet', 'Profile_Metadata');

if writeDetailedProfileSheet
    writetable(allProfiles, outputExcel, 'Sheet', 'Profiles_Detailed');
end

fprintf('\nSaved profile table:\n%s\n', outputExcel);
fprintf('Rows in Profiles: %d\n', height(profiles));
fprintf('Rows in Profiles_ByCTT: %d\n', height(profilesByTemperature));
fprintf('Rows in Profile_Metadata: %d\n', height(profileMetadata));
if writeDetailedProfileSheet
    fprintf('Rows in Profiles_Detailed: %d\n', height(allProfiles));
end

%% Helper functions
function profiles = buildLeanProfileTable(allProfiles)
    profiles = allProfiles(:, {'TimeUTC', 'ProfileDirection', 'SampleIndex', ...
        'DistanceKm', 'Latitude', 'Longitude', 'COT', 'CER', 'CTT', 'CTH', 'CloudType'});
end

function metadata = buildProfileMetadataTable(allProfiles, halfWidthPixels)
    keyColumns = {'TimeUTC', 'TimeTextUTC', 'DateUTC', 'HHMM', 'FileName', ...
        'ProfileDirection', 'CenterPixelRow', 'CenterPixelCol'};
    keys = unique(allProfiles(:, keyColumns), 'rows', 'stable');
    records = repmat(struct(), height(keys), 1);

    for i = 1:height(keys)
        mask = allProfiles.TimeUTC == keys.TimeUTC(i) ...
            & strcmpi(allProfiles.ProfileDirection, keys.ProfileDirection(i));
        oneProfile = allProfiles(mask, :);
        oneProfile = sortrows(oneProfile, 'SampleIndex');

        records(i).TimeUTC = keys.TimeUTC(i);
        records(i).TimeTextUTC = string(keys.TimeTextUTC(i));
        records(i).DateUTC = string(keys.DateUTC(i));
        records(i).HHMM = string(keys.HHMM(i));
        records(i).ProfileDirection = string(keys.ProfileDirection(i));
        records(i).FileName = string(keys.FileName(i));
        records(i).CenterPixelRow = keys.CenterPixelRow(i);
        records(i).CenterPixelCol = keys.CenterPixelCol(i);
        records(i).CenterLatitude = 60 - 0.05 * (keys.CenterPixelCol(i) - 1);
        records(i).CenterLongitude = 80 + 0.05 * (keys.CenterPixelRow(i) - 1);
        records(i).HalfWidthPixels = halfWidthPixels;
        records(i).PointCount = height(oneProfile);
        records(i).StartLatitude = oneProfile.Latitude(1);
        records(i).StartLongitude = oneProfile.Longitude(1);
        records(i).EndLatitude = oneProfile.Latitude(end);
        records(i).EndLongitude = oneProfile.Longitude(end);
    end

    metadata = struct2table(records);
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

function profile = extractOneProfile(cloud, row0, col0, direction, halfWidthPixels, ...
        centerRow, gridOriginLat, gridOriginLon, gridSpacingDeg)
    [nRows, nCols] = size(cloud.COT);

    switch lower(direction)
        case 'westeast'
            rows = (max(1, row0 - halfWidthPixels):min(nRows, row0 + halfWidthPixels)).';
            cols = repmat(col0, numel(rows), 1);
            signedOffsetPixels = rows - row0;
            lat0 = gridOriginLat - gridSpacingDeg * (col0 - 1);
            distanceKm = signedOffsetPixels * gridSpacingDeg * 111.32 * cosd(lat0);
            directionText = repmat("westEast", numel(rows), 1);
        case 'southnorth'
            cols = (max(1, col0 - halfWidthPixels):min(nCols, col0 + halfWidthPixels)).';
            rows = repmat(row0, numel(cols), 1);
            signedOffsetPixels = col0 - cols; % positive means north of center.
            distanceKm = signedOffsetPixels * gridSpacingDeg * 111.32;
            directionText = repmat("southNorth", numel(cols), 1);
        otherwise
            error('Unknown profile direction: %s', direction);
    end

    sampleIndex = (1:numel(rows)).';
    lat = gridOriginLat - gridSpacingDeg * (cols - 1);
    lon = gridOriginLon + gridSpacingDeg * (rows - 1);
    idx = sub2ind(size(cloud.COT), rows, cols);

    profile = table( ...
        repmat(centerRow.TimeUTC, numel(rows), 1), ...
        repmat(string(datestr(centerRow.TimeUTC, 'yyyy-mm-dd HH:MM')), numel(rows), 1), ...
        repmat(string(centerRow.DateUTC), numel(rows), 1), ...
        repmat(string(centerRow.HHMM), numel(rows), 1), ...
        repmat(string(centerRow.FileName), numel(rows), 1), ...
        directionText, sampleIndex, signedOffsetPixels, distanceKm, ...
        rows, cols, lat, lon, ...
        cloud.COT(idx), cloud.CER(idx), cloud.CTT(idx), cloud.CTH(idx), cloud.CloudType(idx), ...
        repmat(row0, numel(rows), 1), repmat(col0, numel(rows), 1), ...
        'VariableNames', {'TimeUTC', 'TimeTextUTC', 'DateUTC', 'HHMM', 'FileName', ...
        'ProfileDirection', 'SampleIndex', 'OffsetPixels', 'DistanceKm', ...
        'PixelRow', 'PixelCol', 'Latitude', 'Longitude', ...
        'COT', 'CER', 'CTT', 'CTH', 'CloudType', 'CenterPixelRow', 'CenterPixelCol'});
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
    tf = any(strcmp(className, {'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'}));
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
