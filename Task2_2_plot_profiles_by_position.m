%% Task 2-2: Plot cloud properties along profile position
% Input : Task2_profiles.xlsx from Task2_1_extract_cloud_profiles.m
% Output: Single-time profile figures for selected UTC times.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
profileExcel = fullfile(projectRoot, 'Task2_profiles.xlsx');
outputDir = fullfile(projectRoot, 'Task2_profile_figures');

directionsToPlot = {'westEast', 'southNorth'};
singleTimePropertyList = {'COT', 'CTT', 'CTH'};
lineWidth = 1.6;

% Single-time profile figures. These are the three stages requested for the
% report: development, pre-landfall/mature, and landfall stage.
singleProfileTimesUTC = [
    datetime(2019, 8, 6, 1, 0, 0)
    datetime(2019, 8, 8, 1, 0, 0)
    datetime(2019, 8, 10, 1, 0, 0)
];
timeMatchToleranceMinutes = 1;

% Plot only the mature-to-landfall analysis period.
plotStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
plotEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);
plotRangeTag = '0806_0811';
plotRangeLabel = sprintf('%s to %s UTC', ...
    datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
    datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Read profiles
if ~isfile(profileExcel)
    error('Cannot find profile table. Run Task2_1_extract_cloud_profiles first: %s', profileExcel);
end

profiles = readProfilesForPlot(profileExcel);
profiles.TimeUTC = parseTimeValues(profiles.TimeUTC);
profiles.ProfileDirection = string(profiles.ProfileDirection);

rangeMask = profiles.TimeUTC >= plotStartTimeUTC & profiles.TimeUTC <= plotEndTimeUTC;
profiles = profiles(rangeMask, :);
if height(profiles) == 0
    error('No profile rows found from %s to %s.', ...
        datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
        datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));
end

availableTimes = unique(profiles.TimeUTC(~isnat(profiles.TimeUTC)));
availableTimes = sort(availableTimes);
singleProfileTimesUTC = matchRequestedTimes( ...
    singleProfileTimesUTC, availableTimes, timeMatchToleranceMinutes);

%% Single-time profile figures
for t = 1:numel(singleProfileTimesUTC)
    timeUTC = singleProfileTimesUTC(t);
    fig = figure('Color', 'w', 'Position', [60, 40, 1250, 850]);
    layout = tiledlayout(numel(singleTimePropertyList), numel(directionsToPlot), ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, sprintf('Cloud-property profiles at %s UTC', ...
        datestr(timeUTC, 'yyyy-mm-dd HH:MM')), 'Interpreter', 'none');

    for p = 1:numel(singleTimePropertyList)
        property = singleTimePropertyList{p};

        for d = 1:numel(directionsToPlot)
            direction = directionsToPlot{d};
            ax = nexttile;
            oneProfile = profiles(profiles.TimeUTC == timeUTC & ...
                strcmpi(profiles.ProfileDirection, direction), :);

            plotSingleProfile(ax, oneProfile, property, direction, lineWidth);

            if p == 1
                title(ax, directionTitle(direction), 'Interpreter', 'none');
            end
            if p == numel(singleTimePropertyList)
                xlabel(ax, distanceLabel(direction));
            else
                set(ax, 'XTickLabel', []);
            end
            ylabel(ax, propertyLabel(property));
        end
    end

    fileTag = datestr(timeUTC, 'mmdd_HHMM');
    pngFile = fullfile(outputDir, sprintf('Task2_single_time_profile_%s_UTC.png', fileTag));
    figFile = fullfile(outputDir, sprintf('Task2_single_time_profile_%s_UTC.fig', fileTag));
    saveFigure(fig, pngFile, figFile);
    fprintf('Saved single-time profile figure:\n%s\n%s\n', pngFile, figFile);
end

%% Helper functions
function matchedTimes = matchRequestedTimes(requestedTimes, availableTimes, toleranceMinutes)
    matchedTimes = NaT(size(requestedTimes));
    toleranceDays = minutes(toleranceMinutes);

    for i = 1:numel(requestedTimes)
        if isempty(availableTimes)
            continue;
        end

        [dt, idx] = min(abs(availableTimes - requestedTimes(i)));
        if dt <= toleranceDays
            matchedTimes(i) = availableTimes(idx);
        else
            warning('Requested time %s UTC was not found within %.1f minutes. Skipping it.', ...
                datestr(requestedTimes(i), 'yyyy-mm-dd HH:MM'), toleranceMinutes);
        end
    end

    matchedTimes = matchedTimes(~isnat(matchedTimes));
    matchedTimes = unique(matchedTimes, 'stable');

    if isempty(matchedTimes)
        error('None of the requested single-profile times were found in Task2_profiles.xlsx.');
    end
end

function plotSingleProfile(ax, oneProfile, property, direction, lineWidth)
    if height(oneProfile) == 0
        showNoDataMessage(ax, 'No profile data');
        return;
    end

    oneProfile = sortrows(oneProfile, 'DistanceKm');
    x = oneProfile.DistanceKm;
    y = oneProfile.(property);

    if ~any(isfinite(y))
        showNoDataMessage(ax, ['No valid ', property]);
        return;
    end

    plot(ax, x, y, '-', 'Color', [0.10 0.32 0.70], 'LineWidth', lineWidth);
    grid(ax, 'on');
    box(ax, 'on');
    xline(ax, 0, 'k--', 'Center', ...
        'LabelVerticalAlignment', 'bottom', ...
        'HandleVisibility', 'off');
    xlim(ax, profileDistanceLimits(direction));
    applyRobustYLimits(ax, y);
end

function showNoDataMessage(ax, message)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, message, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 11, ...
        'Color', [0.35 0.35 0.35]);
end

function limits = profileDistanceLimits(direction)
    switch lower(direction)
        case {'westeast', 'southnorth'}
            limits = [-800, 800];
        otherwise
            limits = [-800, 800];
    end
end

function label = directionTitle(direction)
    switch lower(direction)
        case 'westeast'
            label = 'West-East profile';
        case 'southnorth'
            label = 'South-North profile';
        otherwise
            label = direction;
    end
end

function profiles = readProfilesForPlot(profileExcel)
    try
        profiles = readtable(profileExcel, 'Sheet', 'Profiles', 'VariableNamingRule', 'preserve');
        return;
    catch
    end

    try
        profiles = readtable(profileExcel, 'Sheet', 'Profiles_Detailed', 'VariableNamingRule', 'preserve');
        return;
    catch
    end

    compact = readtable(profileExcel, 'Sheet', 'Profiles_Compact', 'VariableNamingRule', 'preserve');
    profiles = expandCompactProfiles(compact);
end

function profiles = expandCompactProfiles(compact)
    profiles = table();
    prefixes = {'WE', 'SN'};
    directions = {'westEast', 'southNorth'};
    properties = {'COT', 'CER', 'CTT', 'CTH', 'CloudType'};

    for i = 1:height(compact)
        for d = 1:numel(prefixes)
            prefix = prefixes{d};
            distance = parseVector(compact.([prefix, '_DistanceKm'])(i));
            n = numel(distance);
            if n == 0
                continue;
            end

            newTable = table();
            newTable.TimeUTC = repmat(compact.TimeUTC(i), n, 1);
            newTable.ProfileDirection = repmat(string(directions{d}), n, 1);
            newTable.SampleIndex = (1:n).';
            newTable.DistanceKm = distance(:);

            for p = 1:numel(properties)
                property = properties{p};
                values = parseVector(compact.([prefix, '_', property])(i));
                newTable.(property) = padVector(values, n);
            end

            if isempty(profiles)
                profiles = newTable;
            else
                profiles = [profiles; newTable]; %#ok<AGROW>
            end
        end
    end
end

function values = parseVector(raw)
    if iscell(raw)
        raw = raw{1};
    end

    rawText = strtrim(string(raw));
    if strlength(rawText) == 0 || ismissing(rawText)
        values = [];
        return;
    end

    values = str2double(split(rawText, ';'));
end

function values = padVector(values, n)
    values = values(:);
    if numel(values) < n
        values(end + 1:n, 1) = NaN;
    elseif numel(values) > n
        values = values(1:n);
    end
end

function applyRobustYLimits(ax, values)
    values = values(isfinite(values));
    if isempty(values)
        return;
    end

    lo = min(values);
    hi = max(values);
    if lo == hi
        padding = max(abs(lo) * 0.05, 1);
    else
        padding = 0.05 * (hi - lo);
    end
    ylim(ax, [lo - padding, hi + padding]);
end

function label = propertyLabel(property)
    switch lower(property)
        case 'cot'
            label = 'COT';
        case 'cer'
            label = 'CER';
        case 'ctt'
            label = 'CTT';
        case 'cth'
            label = 'CTH (km if original unit was meters)';
        case 'cloudtype'
            label = 'Cloud type';
        otherwise
            label = property;
    end
end

function label = distanceLabel(direction)
    switch lower(direction)
        case 'westeast'
            label = 'Distance from center (km; west negative, east positive)';
        case 'southnorth'
            label = 'Distance from center (km; south negative, north positive)';
        otherwise
            label = 'Distance from center (km)';
    end
end

function timeValues = parseTimeValues(raw)
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

function saveFigure(fig, pngFile, figFile)
    try
        exportgraphics(fig, pngFile, 'Resolution', 300);
    catch
        saveas(fig, pngFile);
    end
    savefig(fig, figFile);
end
