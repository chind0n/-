%% Task 2-3: Plot cloud properties versus cloud-top temperature
% Input : Task2_profiles.xlsx from Task2_1_extract_cloud_profiles.m
% Output: Temperature-sorted table and cloud-property figures.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
profileExcel = fullfile(projectRoot, 'Task2_profiles.xlsx');
outputDir = fullfile(projectRoot, 'Task2_profile_figures');

% Plot only the mature-to-landfall analysis period.
plotStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
plotEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);
plotRangeTag = '0806_0811';
plotRangeLabel = sprintf('%s to %s UTC', ...
    datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
    datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));
sortedExcel = fullfile(projectRoot, ['Task2_profiles_sorted_by_temperature_', plotRangeTag, '.xlsx']);

% 'all', 'westEast', or 'southNorth'
directionFilter = 'all';
propertyList = {'COT', 'CER', 'CTH', 'CloudType'};

% Raw point-by-point lines are very noisy for satellite retrievals. The
% report figure uses temperature-bin representative values instead.
temperaturePlotMode = 'binnedMedian';  % 'binnedMedian' or 'raw'
temperatureBinWidth = 2;               % Kelvin
minPointsPerTemperatureBin = 8;

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Read sorted profile data
if ~isfile(profileExcel)
    error('Cannot find profile table. Run Task2_1_extract_cloud_profiles first: %s', profileExcel);
end

profiles = readProfilesForTemperature(profileExcel);

if ~ismember('TimeUTC', profiles.Properties.VariableNames)
    error(['The profile table must include TimeUTC to apply the ', ...
        '2019-08-06 to 2019-08-11 plot range. Run Task2_1_extract_cloud_profiles again.']);
end

profiles.TimeUTC = parseTimeValues(profiles.TimeUTC);
profiles.ProfileDirection = string(profiles.ProfileDirection);

rangeMask = profiles.TimeUTC >= plotStartTimeUTC & profiles.TimeUTC <= plotEndTimeUTC;
profiles = profiles(rangeMask, :);
if height(profiles) == 0
    error('No profile rows found from %s to %s.', ...
        datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
        datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));
end

if ~strcmpi(directionFilter, 'all')
    profiles = profiles(strcmpi(profiles.ProfileDirection, directionFilter), :);
end

valid = isfinite(profiles.CTT);
profiles = profiles(valid, :);
profiles = sortrows(profiles, 'CTT');

if height(profiles) == 0
    error('No valid CTT values were found.');
end

writetable(profiles, sortedExcel, 'Sheet', 'Profiles_ByCTT');
fprintf('Saved temperature-sorted profile table:\n%s\n', sortedExcel);

%% Plot cloud properties versus CTT
directions = unique(profiles.ProfileDirection, 'stable');
colors = lines(numel(directions));

fig = figure('Color', 'w', 'Position', [80, 60, 1050, 850]);
layout = tiledlayout(numel(propertyList), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, ['Cloud properties versus cloud-top temperature (', plotRangeLabel, ')'], ...
    'Interpreter', 'none');

for p = 1:numel(propertyList)
    property = propertyList{p};
    ax = nexttile;
    hold(ax, 'on');

    for d = 1:numel(directions)
        direction = directions(d);
        oneGroup = profiles(strcmpi(profiles.ProfileDirection, direction), :);
        y = oneGroup.(property);
        valid = isfinite(oneGroup.CTT) & isfinite(y);
        if ~any(valid)
            continue;
        end

        if strcmpi(temperaturePlotMode, 'binnedMedian')
            [cttPlot, yPlot] = binPropertyByTemperature( ...
                oneGroup.CTT(valid), y(valid), temperatureBinWidth, ...
                minPointsPerTemperatureBin, property);
            if isempty(cttPlot) || ~any(isfinite(yPlot))
                continue;
            end
            plot(ax, cttPlot, yPlot, '-o', ...
                'Color', colors(d, :), ...
                'MarkerFaceColor', colors(d, :), ...
                'MarkerSize', 4, ...
                'LineWidth', 1.6, ...
                'DisplayName', direction);
        else
            plot(ax, oneGroup.CTT(valid), y(valid), '.', ...
                'Color', colors(d, :), ...
                'MarkerSize', 5, ...
                'DisplayName', direction);
        end
    end

    grid(ax, 'on');
    ylabel(ax, propertyLabel(property));
    if p == numel(propertyList)
        xlabel(ax, 'Cloud-top temperature CTT');
    else
        set(ax, 'XTickLabel', []);
    end

    if p == 1
        legend(ax, 'Location', 'bestoutside');
    end
end

pngFile = fullfile(outputDir, ['Task2_cloud_properties_by_temperature_', plotRangeTag, '.png']);
figFile = fullfile(outputDir, ['Task2_cloud_properties_by_temperature_', plotRangeTag, '.fig']);
saveFigure(fig, pngFile, figFile);
fprintf('Saved figure:\n%s\n%s\n', pngFile, figFile);

%% Helper functions
function profiles = readProfilesForTemperature(profileExcel)
    try
        profiles = readtable(profileExcel, 'Sheet', 'Profiles_ByCTT', 'VariableNamingRule', 'preserve');
        return;
    catch
    end

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
            ctt = parseVector(compact.([prefix, '_CTT'])(i));
            n = numel(ctt);
            if n == 0
                continue;
            end

            newTable = table();
            if ismember('TimeUTC', compact.Properties.VariableNames)
                newTable.TimeUTC = repmat(compact.TimeUTC(i), n, 1);
            end
            newTable.ProfileDirection = repmat(string(directions{d}), n, 1);
            newTable.CTT = ctt(:);

            for p = 1:numel(properties)
                property = properties{p};
                if strcmp(property, 'CTT')
                    continue;
                end
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

function [binCenters, binnedValues] = binPropertyByTemperature(ctt, values, binWidth, minPoints, property)
    ctt = ctt(:);
    values = values(:);
    valid = isfinite(ctt) & isfinite(values);
    ctt = ctt(valid);
    values = values(valid);

    if isempty(ctt)
        binCenters = [];
        binnedValues = [];
        return;
    end

    edgeStart = floor(min(ctt) / binWidth) * binWidth;
    edgeEnd = ceil(max(ctt) / binWidth) * binWidth;
    edges = edgeStart:binWidth:edgeEnd;
    if numel(edges) < 2
        edges = [edgeStart, edgeStart + binWidth];
    end

    binCenters = edges(1:end-1).' + binWidth / 2;
    binnedValues = NaN(size(binCenters));

    for i = 1:numel(binCenters)
        if i == numel(binCenters)
            mask = ctt >= edges(i) & ctt <= edges(i + 1);
        else
            mask = ctt >= edges(i) & ctt < edges(i + 1);
        end

        if sum(mask) < minPoints
            continue;
        end

        if strcmpi(property, 'CloudType')
            binnedValues(i) = modeFinite(values(mask));
        else
            binnedValues(i) = medianFinite(values(mask));
        end
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

function label = propertyLabel(property)
    switch lower(property)
        case 'cot'
            label = 'COT';
        case 'cer'
            label = 'CER';
        case 'cth'
            label = 'CTH (km if original unit was meters)';
        case 'cloudtype'
            label = 'Cloud type';
        otherwise
            label = property;
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
