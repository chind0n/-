%% Task 3-2: Plot typhoon-center cloud properties versus time
% Input : Task3_center_cloud_stats_0806_0811.xlsx from Task3_1_extract_center_cloud_stats.m
% Output: Time-series figures of mean/median cloud properties near the typhoon center.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
plotRangeTag = '0806_0811';
statsExcel = fullfile(projectRoot, ['Task3_center_cloud_stats_', plotRangeTag, '.xlsx']);
outputDir = fullfile(projectRoot, 'Task3_center_cloud_figures');

plotStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
plotEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);

% Main continuous properties. CloudType is plotted separately as a class code.
continuousProperties = {'COT', 'CER', 'CTT', 'CTH'};

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Read Task 3 statistics
if ~isfile(statsExcel)
    error('Cannot find Task 3 statistics table. Run Task3_1_extract_center_cloud_stats first: %s', statsExcel);
end

statsTable = readtable(statsExcel, 'Sheet', 'Center_10x10_Stats', ...
    'VariableNamingRule', 'preserve');
if height(statsTable) == 0
    error('Task 3 statistics table is empty: %s', statsExcel);
end

statsTable.TimeUTC = parseTimeValues(statsTable.TimeUTC);
rangeMask = statsTable.TimeUTC >= plotStartTimeUTC & statsTable.TimeUTC <= plotEndTimeUTC;
statsTable = statsTable(rangeMask, :);
statsTable = sortrows(statsTable, 'TimeUTC');

if height(statsTable) == 0
    error('No Task 3 statistics rows found in the selected time range.');
end

%% Plot mean and median time series
fig = figure('Color', 'w', 'Position', [80, 45, 1150, 900]);
layout = tiledlayout(numel(continuousProperties), 1, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, 'Typhoon-center 10x10-pixel cloud properties versus UTC time', ...
    'Interpreter', 'none');

for p = 1:numel(continuousProperties)
    property = continuousProperties{p};
    ax = nexttile;
    hold(ax, 'on');

    meanName = [property, '_Mean'];
    medianName = [property, '_Median'];
    requireColumns(statsTable, {meanName, medianName});

    plot(ax, statsTable.TimeUTC, statsTable.(meanName), '-o', ...
        'Color', [0.10 0.32 0.70], ...
        'MarkerFaceColor', [0.10 0.32 0.70], ...
        'MarkerSize', 4, ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Mean');
    plot(ax, statsTable.TimeUTC, statsTable.(medianName), '--s', ...
        'Color', [0.82 0.30 0.12], ...
        'MarkerFaceColor', [0.82 0.30 0.12], ...
        'MarkerSize', 4, ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Median');

    grid(ax, 'on');
    box(ax, 'on');
    ylabel(ax, propertyLabel(property));
    xlim(ax, [plotStartTimeUTC, plotEndTimeUTC]);
    xtickformat(ax, 'MM-dd HH:mm');

    if p == 1
        legend(ax, 'Location', 'bestoutside');
    end

    if p == numel(continuousProperties)
        xlabel(ax, 'UTC time');
    else
        set(ax, 'XTickLabel', []);
    end
end

pngFile = fullfile(outputDir, ['Task3_center_cloud_mean_median_', plotRangeTag, '.png']);
figFile = fullfile(outputDir, ['Task3_center_cloud_mean_median_', plotRangeTag, '.fig']);
saveFigure(fig, pngFile, figFile);
fprintf('Saved Task 3 mean/median time-series figure:\n%s\n%s\n', pngFile, figFile);

%% Plot cloud type as a class code
if all(ismember({'CloudType_Mode', 'CloudType_Median'}, statsTable.Properties.VariableNames))
    fig = figure('Color', 'w', 'Position', [100, 80, 1050, 430]);
    ax = axes(fig);
    hold(ax, 'on');

    stairs(ax, statsTable.TimeUTC, statsTable.CloudType_Mode, '-', ...
        'Color', [0.10 0.32 0.70], ...
        'LineWidth', 1.8, ...
        'DisplayName', 'Mode');
    plot(ax, statsTable.TimeUTC, statsTable.CloudType_Median, 'o--', ...
        'Color', [0.82 0.30 0.12], ...
        'MarkerFaceColor', [0.82 0.30 0.12], ...
        'MarkerSize', 4, ...
        'LineWidth', 1.3, ...
        'DisplayName', 'Median');

    grid(ax, 'on');
    box(ax, 'on');
    xlim(ax, [plotStartTimeUTC, plotEndTimeUTC]);
    xtickformat(ax, 'MM-dd HH:mm');
    xlabel(ax, 'UTC time');
    ylabel(ax, 'Cloud type code');
    title(ax, 'Typhoon-center cloud type code versus UTC time', ...
        'Interpreter', 'none');
    legend(ax, 'Location', 'bestoutside');

    pngFile = fullfile(outputDir, ['Task3_center_cloud_type_', plotRangeTag, '.png']);
    figFile = fullfile(outputDir, ['Task3_center_cloud_type_', plotRangeTag, '.fig']);
    saveFigure(fig, pngFile, figFile);
    fprintf('Saved Task 3 cloud-type time-series figure:\n%s\n%s\n', pngFile, figFile);
end

%% Helper functions
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

function requireColumns(tableData, columns)
    names = string(tableData.Properties.VariableNames);
    missing = strings(0, 1);
    for i = 1:numel(columns)
        if ~any(strcmp(names, columns{i}))
            missing(end + 1, 1) = string(columns{i}); %#ok<AGROW>
        end
    end

    if ~isempty(missing)
        error('The statistics table is missing columns: %s', strjoin(missing, ', '));
    end
end

function label = propertyLabel(property)
    switch lower(property)
        case 'cot'
            label = 'COT';
        case 'cer'
            label = 'CER';
        case 'ctt'
            label = 'CTT (K)';
        case 'cth'
            label = 'CTH (km if original unit was meters)';
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
