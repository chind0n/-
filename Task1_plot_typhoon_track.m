%% Task 1: Plot typhoon-eye track on a real map basemap
% Run this script after Task.xlsx has typhoon-eye points.
% The plot uses longitude/latitude axes and labels every point by UTC time.

clear; clc;

%% User settings
projectRoot = fileparts(mfilename('fullpath'));
excelFile = fullfile(projectRoot, 'Task.xlsx');
dataRoot = fullfile(projectRoot, char([27599 22825 22235 20010 26102 21051]));

% Options:
%   'osmTiles'      : OpenStreetMap web-map tiles with real coastlines and labels.
%   'mmapCot'       : m_map projection + Himawari-8 COT distribution + coastlines.
%   'mmapCoastline' : m_map projection + coastlines only.
%   'satelliteCot'  : normal lon/lat axes + Himawari-8 COT image.
%   'coastline'     : normal lon/lat axes + coastline data.
baseMapType = 'osmTiles';

% Used only when baseMapType is 'osmTiles'. Higher zoom is more detailed but
% downloads more tiles. Zoom 6 is suitable for the western North Pacific track.
osmZoom = 6;
osmTileCacheDir = fullfile(projectRoot, 'osm_tile_cache');

% Add a South China Sea inset with a schematic nine-dash line.
showNineDashInset = true;
nineDashInsetLonLim = [105, 125];
nineDashInsetLatLim = [0, 25];
nineDashInsetZoom = 5;

% true: if m_map is missing, fall back to normal lon/lat axes instead of stopping.
% false: require m_map and stop with an error if it is not on the MATLAB path.
allowFallbackWithoutMMap = true;

% Used when baseMapType is 'mmapCot' or 'satelliteCot'. Leave empty to use
% the first nc file recorded in Task.xlsx. If that path is missing, the
% script uses the first .nc file in dataRoot.
baseNcFile = '';

% The COT matrix is displayed after transposition. Therefore PixelRow maps
% to longitude, and PixelCol maps to latitude.
recalculateLatLonFromPixel = true;
gridOriginLat = 60;
gridOriginLon = 80;
gridSpacingDeg = 0.05;

% Set labelEvery to 1 for all points, 2 for every other point, etc.
labelEvery = 1;
cropToTrack = true;
mapMarginDeg = 5;

% Task.xlsx can keep the full 2019-08-04 to 2019-08-14 track, but this
% figure only plots the analysis period requested for the report.
plotStartTimeUTC = datetime(2019, 8, 6, 0, 0, 0);
plotEndTimeUTC = datetime(2019, 8, 11, 23, 59, 59);
plotRangeTag = '0806_0811';
plotRangeLabel = sprintf('%s to %s UTC', ...
    datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), ...
    datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));

cotCandidates = {'CLOT', 'COT', 'cot', 'clot', 'Cloud_Optical_Thickness', ...
    'cloud_optical_thickness', 'CloudOpticalThickness'};

%% Read and prepare the typhoon-eye table
if ~isfile(excelFile)
    error('Cannot find Excel file: %s', excelFile);
end

trackTable = readtable(excelFile, 'VariableNamingRule', 'preserve');
if height(trackTable) == 0
    error('The Excel file has no track rows: %s', excelFile);
end

times = readUtcTimes(trackTable);

if recalculateLatLonFromPixel && hasAnyColumn(trackTable, {'PixelRow', 'Row'}) ...
        && hasAnyColumn(trackTable, {'PixelCol', 'Col'})
    pixelRow = readNumericColumn(trackTable, {'PixelRow', 'Row'});
    pixelCol = readNumericColumn(trackTable, {'PixelCol', 'Col'});
    latTrack = gridOriginLat - gridSpacingDeg * (pixelCol - 1);
    lonTrack = gridOriginLon + gridSpacingDeg * (pixelRow - 1);
else
    latTrack = readNumericColumn(trackTable, {'Latitude', 'Lat', 'lat'});
    lonTrack = readNumericColumn(trackTable, {'Longitude', 'Lon', 'lon'});
end

valid = isfinite(latTrack) & isfinite(lonTrack);
if any(~isnat(times))
    valid = valid & ~isnat(times);
    valid = valid & times >= plotStartTimeUTC & times <= plotEndTimeUTC;
end

trackTable = trackTable(valid, :);
times = times(valid);
latTrack = latTrack(valid);
lonTrack = lonTrack(valid);

if isempty(latTrack)
    error('No valid typhoon-eye points were found from %s to %s UTC.', ...
        datestr(plotStartTimeUTC, 'yyyy-mm-dd HH:MM'), datestr(plotEndTimeUTC, 'yyyy-mm-dd HH:MM'));
end

if any(~isnat(times))
    [times, order] = sort(times);
    latTrack = latTrack(order);
    lonTrack = lonTrack(order);
    trackTable = trackTable(order, :);
end

%% Prepare map extent and optional satellite basemap
mapLonLim = [min(lonTrack) - mapMarginDeg, max(lonTrack) + mapMarginDeg];
mapLatLim = [min(latTrack) - mapMarginDeg, max(latTrack) + mapMarginDeg];

requestedBaseMapType = baseMapType;
useMMap = any(strcmpi(baseMapType, {'mmapCot', 'mmapCoastline'}));

if useMMap && ~isMMapAvailable()
    if allowFallbackWithoutMMap
        if strcmpi(baseMapType, 'mmapCot')
            baseMapType = 'satelliteCot';
        else
            baseMapType = 'coastline';
        end

        warning(['m_map toolbox was not found on the MATLAB path. ', ...
            'Falling back from %s to %s. Install/add m_map to use the required m_map version.'], ...
            requestedBaseMapType, baseMapType);
    else
        assertMMapAvailable();
    end
end

useMMap = any(strcmpi(baseMapType, {'mmapCot', 'mmapCoastline'}));
needsSatellite = any(strcmpi(baseMapType, {'mmapCot', 'satelliteCot'}));
[outputPng, outputFig] = chooseOutputFiles(projectRoot, baseMapType, plotRangeTag);

if needsSatellite
    baseNcFile = chooseBaseNcFile(baseNcFile, trackTable, dataRoot);
    fprintf('Basemap nc file:\n%s\n', baseNcFile);

    info = ncinfo(baseNcFile);
    cotName = findNcVariable(info, cotCandidates, 'cloud optical thickness');
    cot = readNcClean(baseNcFile, cotName, 'cot');
    cot = squeeze(cot);

    plotData = makeCotDisplayData(cot);
    displayData = plotData.';
    [nRows, nCols] = size(cot);

    lonAxis = gridOriginLon + gridSpacingDeg * (0:nRows - 1);
    latAxis = gridOriginLat - gridSpacingDeg * (0:nCols - 1);

    if cropToTrack
        [lonAxis, latAxis, displayData] = cropRasterToExtent( ...
            lonAxis, latAxis, displayData, mapLonLim, mapLatLim);
    else
        mapLonLim = [min(lonAxis), max(lonAxis)];
        mapLatLim = [min(latAxis), max(latAxis)];
    end
else
    cotName = '';
    displayData = [];
    lonAxis = [];
    latAxis = [];
end

%% Plot basemap and UTC-labeled track
fig = figure('Color', 'w', 'Position', [80, 60, 1100, 850]);
ax = axes(fig);
labels = makeUtcLabels(times, trackTable);

if strcmpi(baseMapType, 'osmTiles')
    [xTrack, yTrack] = lonLatToWebMercatorPixels(lonTrack, latTrack, osmZoom);
    drawOsmTileBasemap(ax, mapLonLim, mapLatLim, osmZoom, osmTileCacheDir);
    hold(ax, 'on');
    [hOutline, hTrack, hStart, hEnd] = plotTrackWithProjectedAxes(ax, xTrack, yTrack, labels, labelEvery);
    addOsmAttribution(ax);
    mapTitle = 'Track of Typhoon Lekima on OpenStreetMap basemap';
elseif strcmpi(baseMapType, 'mmapCot')
    axes(ax);
    m_proj('mercator', 'lon', mapLonLim, 'lat', mapLatLim);
    [lonGrid, latGrid] = meshgrid(lonAxis, latAxis);
    m_pcolor(lonGrid, latGrid, displayData);
    shading flat;
    colormap(ax, turbo);
    cb = colorbar(ax);
    cb.Label.String = sprintf('log10(%s + 1)', cotName);
    applyRobustColorLimits(displayData);
    hold(ax, 'on');
    m_coast('color', [0.05 0.05 0.05], 'linewidth', 1.0);
    m_grid('box', 'fancy', 'tickdir', 'out', 'fontsize', 9);
    [hOutline, hTrack, hStart, hEnd] = plotTrackWithMMap(lonTrack, latTrack, labels, labelEvery);
    mapTitle = 'Typhoon Lekima eye track on Himawari-8 COT distribution with m\_map coastlines';
elseif strcmpi(baseMapType, 'mmapCoastline')
    axes(ax);
    set(ax, 'Color', [0.78 0.90 1.00]);
    m_proj('mercator', 'lon', mapLonLim, 'lat', mapLatLim);
    m_coast('patch', [0.86 0.84 0.74], 'edgecolor', [0.18 0.18 0.18], 'linewidth', 0.8);
    m_grid('box', 'fancy', 'tickdir', 'out', 'fontsize', 9);
    hold(ax, 'on');
    [hOutline, hTrack, hStart, hEnd] = plotTrackWithMMap(lonTrack, latTrack, labels, labelEvery);
    mapTitle = 'Typhoon Lekima eye track on m\_map coastline map';
elseif strcmpi(baseMapType, 'satelliteCot')
    imagesc(ax, lonAxis, latAxis, displayData);
    set(ax, 'YDir', 'normal');
    axis(ax, 'equal');
    axis(ax, 'tight');
    colormap(ax, turbo);
    cb = colorbar(ax);
    cb.Label.String = sprintf('log10(%s + 1)', cotName);
    applyRobustColorLimits(displayData);

    hold(ax, 'on');
    [hOutline, hTrack, hStart, hEnd] = plotTrackWithNormalAxes(ax, lonTrack, latTrack, labels, labelEvery);
    if cropToTrack
        xlim(ax, [min(lonTrack) - mapMarginDeg, max(lonTrack) + mapMarginDeg]);
        ylim(ax, [min(latTrack) - mapMarginDeg, max(latTrack) + mapMarginDeg]);
    end
    grid(ax, 'on');
    box(ax, 'on');
    xlabel(ax, 'Longitude (deg E)');
    ylabel(ax, 'Latitude (deg N)');
    mapTitle = 'Typhoon Lekima eye track on Himawari-8 COT basemap';
else
    drawCoastlineBasemap(ax, mapLonLim, mapLatLim);
    axis(ax, 'equal');

    hold(ax, 'on');
    [hOutline, hTrack, hStart, hEnd] = plotTrackWithNormalAxes(ax, lonTrack, latTrack, labels, labelEvery);

    if cropToTrack
        xlim(ax, [min(lonTrack) - mapMarginDeg, max(lonTrack) + mapMarginDeg]);
        ylim(ax, [min(latTrack) - mapMarginDeg, max(latTrack) + mapMarginDeg]);
    end

    grid(ax, 'on');
    box(ax, 'on');
    xlabel(ax, 'Longitude (deg E)');
    ylabel(ax, 'Latitude (deg N)');
    mapTitle = 'Typhoon Lekima eye track on coastline map';
end

title(ax, {mapTitle, ['UTC labels are from Task.xlsx; plot range: ', plotRangeLabel]}, ...
    'Interpreter', 'none');

legend(ax, [hOutline, hTrack, hStart, hEnd], ...
    {'Track outline', 'Eye track', 'Start', 'End'}, ...
    'Location', 'bestoutside');

if showNineDashInset
    addNineDashInset(fig, nineDashInsetLonLim, nineDashInsetLatLim, ...
        nineDashInsetZoom, osmTileCacheDir);
end

exportgraphics(fig, outputPng, 'Resolution', 300);
savefig(fig, outputFig);

fprintf('Saved track figure:\n%s\n%s\n', outputPng, outputFig);

%% Helper functions
function [outputPng, outputFig] = chooseOutputFiles(projectRoot, baseMapType, rangeTag)
    switch lower(baseMapType)
        case 'osmtiles'
            stem = 'typhoon_eye_track_osm_map';
        case 'mmapcot'
            stem = 'typhoon_eye_track_mmap_cot';
        case 'mmapcoastline'
            stem = 'typhoon_eye_track_mmap_coastline';
        case 'satellitecot'
            stem = 'typhoon_eye_track_satellite_cot';
        otherwise
            stem = 'typhoon_eye_track_coastline';
    end

    if nargin >= 3 && strlength(string(rangeTag)) > 0
        stem = [stem, '_', char(rangeTag)];
    end

    outputPng = fullfile(projectRoot, [stem, '.png']);
    outputFig = fullfile(projectRoot, [stem, '.fig']);
end

function drawOsmTileBasemap(ax, lonLim, latLim, zoomLevel, cacheDir)
    tileSize = 256;
    [xTileMin, xTileMax, yTileMin, yTileMax] = osmTileRange(lonLim, latLim, zoomLevel);
    nTileX = xTileMax - xTileMin + 1;
    nTileY = yTileMax - yTileMin + 1;
    mosaic = zeros(nTileY * tileSize, nTileX * tileSize, 3, 'uint8');

    for yTile = yTileMin:yTileMax
        for xTile = xTileMin:xTileMax
            tile = readOsmTile(zoomLevel, xTile, yTile, cacheDir);
            row1 = (yTile - yTileMin) * tileSize + 1;
            row2 = row1 + tileSize - 1;
            col1 = (xTile - xTileMin) * tileSize + 1;
            col2 = col1 + tileSize - 1;
            mosaic(row1:row2, col1:col2, :) = tile;
        end
    end

    xWorldLim = [xTileMin, xTileMax + 1] * tileSize;
    yWorldLim = [yTileMin, yTileMax + 1] * tileSize;
    image(ax, xWorldLim, yWorldLim, mosaic);
    set(ax, 'YDir', 'reverse');
    axis(ax, 'image');

    [xLeft, yBottom] = lonLatToWebMercatorPixels(lonLim(1), latLim(1), zoomLevel);
    [xRight, yTop] = lonLatToWebMercatorPixels(lonLim(2), latLim(2), zoomLevel);
    xlim(ax, [xLeft, xRight]);
    ylim(ax, [yTop, yBottom]);

    setWebMercatorDegreeTicks(ax, lonLim, latLim, zoomLevel);
    box(ax, 'on');
    grid(ax, 'on');
    set(ax, 'GridColor', [0.6 0.6 0.6], 'GridAlpha', 0.25);
    xlabel(ax, 'Longitude');
    ylabel(ax, 'Latitude');
end

function [xTileMin, xTileMax, yTileMin, yTileMax] = osmTileRange(lonLim, latLim, zoomLevel)
    nTiles = 2 ^ zoomLevel;
    latLim = max(min(latLim, 85.05112878), -85.05112878);
    lonLim = sort(lonLim);
    latLim = sort(latLim);

    xTileMin = floor((lonLim(1) + 180) / 360 * nTiles);
    xTileMax = floor((lonLim(2) + 180) / 360 * nTiles);
    yTileNorth = latToOsmTileY(latLim(2), zoomLevel);
    yTileSouth = latToOsmTileY(latLim(1), zoomLevel);

    xTileMin = max(0, min(nTiles - 1, xTileMin));
    xTileMax = max(0, min(nTiles - 1, xTileMax));
    yTileMin = max(0, min(nTiles - 1, min(yTileNorth, yTileSouth)));
    yTileMax = max(0, min(nTiles - 1, max(yTileNorth, yTileSouth)));
end

function yTile = latToOsmTileY(lat, zoomLevel)
    nTiles = 2 ^ zoomLevel;
    lat = max(min(lat, 85.05112878), -85.05112878);
    latRad = deg2rad(lat);
    yTile = floor((1 - log(tan(latRad) + sec(latRad)) / pi) / 2 * nTiles);
end

function tile = readOsmTile(zoomLevel, xTile, yTile, cacheDir)
    tileDir = fullfile(cacheDir, sprintf('%d', zoomLevel), sprintf('%d', xTile));
    tileFile = fullfile(tileDir, sprintf('%d.png', yTile));

    if ~isfile(tileFile)
        if ~exist(tileDir, 'dir')
            mkdir(tileDir);
        end

        tileUrl = sprintf('https://tile.openstreetmap.org/%d/%d/%d.png', zoomLevel, xTile, yTile);
        try
            opts = makeWebOptions();
            websave(tileFile, tileUrl, opts);
        catch ME
            error(['Cannot download OpenStreetMap tile:\n%s\n', ...
                'Check the internet connection, or run the script again after connecting to the network.\n', ...
                'Original error: %s'], ...
                tileUrl, ME.message);
        end
    end

    tile = imread(tileFile);
    if ndims(tile) == 2
        tile = repmat(tile, 1, 1, 3);
    elseif size(tile, 3) > 3
        tile = tile(:, :, 1:3);
    end

    if ~isa(tile, 'uint8')
        if isfloat(tile)
            tile = uint8(255 * tile);
        else
            tile = uint8(tile);
        end
    end
end

function opts = makeWebOptions()
    try
        opts = weboptions('Timeout', 30, ...
            'HeaderFields', {'User-Agent', 'MATLAB Typhoon Track Lab Script'});
    catch
        opts = weboptions('Timeout', 30);
    end
end

function [x, y] = lonLatToWebMercatorPixels(lon, lat, zoomLevel)
    tileSize = 256;
    worldSize = tileSize * 2 ^ zoomLevel;
    lat = max(min(lat, 85.05112878), -85.05112878);

    x = (lon + 180) / 360 * worldSize;
    sinLat = sind(lat);
    y = (0.5 - log((1 + sinLat) ./ (1 - sinLat)) / (4 * pi)) * worldSize;
end

function setWebMercatorDegreeTicks(ax, lonLim, latLim, zoomLevel)
    lonTicks = makeDegreeTicks(lonLim, 6);
    latTicks = makeDegreeTicks(latLim, 7);
    [xTicks, ~] = lonLatToWebMercatorPixels(lonTicks, repmat(mean(latLim), size(lonTicks)), zoomLevel);
    [~, yTicks] = lonLatToWebMercatorPixels(repmat(mean(lonLim), size(latTicks)), latTicks, zoomLevel);

    [xTicks, xOrder] = sort(xTicks);
    lonLabels = formatLonLabels(lonTicks);
    lonLabels = lonLabels(xOrder);

    [yTicks, yOrder] = sort(yTicks);
    latLabels = formatLatLabels(latTicks);
    latLabels = latLabels(yOrder);

    set(ax, 'XTick', xTicks, 'XTickLabel', cellstr(lonLabels));
    set(ax, 'YTick', yTicks, 'YTickLabel', cellstr(latLabels));
end

function ticks = makeDegreeTicks(lim, maxTickCount)
    lim = sort(lim);
    span = max(eps, lim(2) - lim(1));
    steps = [0.5, 1, 2, 5, 10, 15, 20];
    step = steps(find(steps >= span / maxTickCount, 1, 'first'));
    if isempty(step)
        step = steps(end);
    end

    firstTick = ceil(lim(1) / step) * step;
    lastTick = floor(lim(2) / step) * step;
    ticks = firstTick:step:lastTick;

    if isempty(ticks)
        ticks = mean(lim);
    end
end

function labels = formatLonLabels(ticks)
    labels = strings(size(ticks));
    for i = 1:numel(ticks)
        if ticks(i) >= 0
            labels(i) = sprintf('%g E', ticks(i));
        else
            labels(i) = sprintf('%g W', abs(ticks(i)));
        end
    end
end

function labels = formatLatLabels(ticks)
    labels = strings(size(ticks));
    for i = 1:numel(ticks)
        if ticks(i) >= 0
            labels(i) = sprintf('%g N', ticks(i));
        else
            labels(i) = sprintf('%g S', abs(ticks(i)));
        end
    end
end

function tf = isMMapAvailable()
    tf = isempty(missingMMapFunctions());
end

function assertMMapAvailable()
    missing = missingMMapFunctions();

    if ~isempty(missing)
        error(['m_map toolbox was not found on the MATLAB path. Missing: %s\n', ...
            'Install m_map or add it to the MATLAB path first, for example:\n', ...
            'addpath(genpath(''D:\\path\\to\\m_map''))'], strjoin(missing, ', '));
    end
end

function missing = missingMMapFunctions()
    requiredFunctions = {'m_proj', 'm_pcolor', 'm_coast', 'm_grid', 'm_plot', 'm_text'};
    missing = {};

    for i = 1:numel(requiredFunctions)
        if exist(requiredFunctions{i}, 'file') ~= 2
            missing{end + 1} = requiredFunctions{i}; %#ok<AGROW>
        end
    end
end

function [lonAxis, latAxis, raster] = cropRasterToExtent(lonAxis, latAxis, raster, lonLim, latLim)
    lonMask = lonAxis >= lonLim(1) & lonAxis <= lonLim(2);
    latMask = latAxis >= latLim(1) & latAxis <= latLim(2);

    if any(lonMask) && any(latMask)
        lonAxis = lonAxis(lonMask);
        latAxis = latAxis(latMask);
        raster = raster(latMask, lonMask);
    end

    if latAxis(1) > latAxis(end)
        latAxis = fliplr(latAxis);
        raster = flipud(raster);
    end
end

function [hOutline, hTrack, hStart, hEnd] = plotTrackWithMMap(lonTrack, latTrack, labels, labelEvery)
    hOutline = m_plot(lonTrack, latTrack, '-', 'Color', [1 1 1], 'LineWidth', 4);
    hTrack = m_plot(lonTrack, latTrack, '-o', ...
        'Color', [0.85 0 0], ...
        'MarkerFaceColor', [1 0.9 0.1], ...
        'MarkerEdgeColor', [0.25 0 0], ...
        'LineWidth', 2, ...
        'MarkerSize', 6);

    hStart = m_plot(lonTrack(1), latTrack(1), 'o', ...
        'MarkerSize', 8, ...
        'MarkerFaceColor', [0.1 0.8 0.2], ...
        'MarkerEdgeColor', 'k', ...
        'Color', 'k');
    hEnd = m_plot(lonTrack(end), latTrack(end), 'o', ...
        'MarkerSize', 8, ...
        'MarkerFaceColor', [0.9 0.1 0.9], ...
        'MarkerEdgeColor', 'k', ...
        'Color', 'k');

    for i = 1:labelEvery:numel(lonTrack)
        m_text(lonTrack(i) + 0.15, latTrack(i) + 0.15, labels(i), ...
            'FontSize', 8, ...
            'Color', 'k', ...
            'BackgroundColor', [1 1 1], ...
            'Margin', 1, ...
            'Interpreter', 'none');
    end
end

function [hOutline, hTrack, hStart, hEnd] = plotTrackWithProjectedAxes(ax, xTrack, yTrack, labels, labelEvery)
    hOutline = plot(ax, xTrack, yTrack, '-', 'Color', [1 1 1], 'LineWidth', 4);
    hTrack = plot(ax, xTrack, yTrack, '-o', ...
        'Color', [0.85 0 0], ...
        'MarkerFaceColor', [1 0.9 0.1], ...
        'MarkerEdgeColor', [0.25 0 0], ...
        'LineWidth', 2, ...
        'MarkerSize', 6);

    hStart = scatter(ax, xTrack(1), yTrack(1), 90, [0.1 0.8 0.2], 'filled', ...
        'MarkerEdgeColor', 'k');
    hEnd = scatter(ax, xTrack(end), yTrack(end), 90, [0.9 0.1 0.9], 'filled', ...
        'MarkerEdgeColor', 'k');

    for i = 1:labelEvery:numel(xTrack)
        text(ax, xTrack(i) + 10, yTrack(i) + 10, labels(i), ...
            'FontSize', 8, ...
            'Color', 'k', ...
            'BackgroundColor', [1 1 1], ...
            'Margin', 1, ...
            'Clipping', 'on', ...
            'Interpreter', 'none');
    end
end

function addOsmAttribution(ax)
    xLim = xlim(ax);
    yLim = ylim(ax);
    xPos = xLim(1) + 0.01 * diff(xLim);
    yPos = yLim(2) - 0.02 * diff(yLim);
    text(ax, xPos, yPos, '(C) OpenStreetMap contributors', ...
        'FontSize', 7, ...
        'Color', [0.2 0.2 0.2], ...
        'BackgroundColor', [1 1 1], ...
        'Margin', 1, ...
        'Clipping', 'on');
end

function addNineDashInset(fig, lonLim, latLim, zoomLevel, cacheDir)
    insetAx = axes(fig, 'Position', [0.66, 0.13, 0.23, 0.28]);
    drawOsmTileBasemap(insetAx, lonLim, latLim, zoomLevel, cacheDir);
    hold(insetAx, 'on');

    plotNineDashLineOnOsm(insetAx, zoomLevel);
    title(insetAx, 'South China Sea inset', 'FontSize', 8);
    xlabel(insetAx, '');
    ylabel(insetAx, '');
    set(insetAx, 'FontSize', 7, 'LineWidth', 0.8);

    [labelX, labelY] = lonLatToWebMercatorPixels(113.2, 7.0, zoomLevel);
    text(insetAx, labelX, labelY, 'Nine-dash line', ...
        'FontSize', 7, ...
        'Color', [0.75 0 0], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [1 1 1], ...
        'Margin', 1, ...
        'Clipping', 'on');
end

function plotNineDashLineOnOsm(ax, zoomLevel)
    dashSegments = nineDashLineSegments();

    for i = 1:numel(dashSegments)
        segment = dashSegments{i};
        [x, y] = lonLatToWebMercatorPixels(segment(:, 1), segment(:, 2), zoomLevel);
        plot(ax, x, y, '--', ...
            'Color', [0.85 0 0], ...
            'LineWidth', 2.0, ...
            'HandleVisibility', 'off');
    end
end

function dashSegments = nineDashLineSegments()
    % Schematic nine-dash line coordinates for a South China Sea inset.
    % Replace these with official map boundary data if your course provides it.
    dashSegments = {
        [109.3 20.4; 109.8 18.4], ...
        [110.1 16.2; 111.0 14.0], ...
        [111.8 12.0; 113.2 10.0], ...
        [114.2 8.2; 116.0 6.6], ...
        [117.4 5.4; 119.5 5.1], ...
        [121.0 6.5; 121.8 9.0], ...
        [121.6 11.6; 120.7 14.0], ...
        [119.8 16.3; 119.0 18.5], ...
        [118.0 20.2; 116.5 21.2]
    };
end

function [hOutline, hTrack, hStart, hEnd] = plotTrackWithNormalAxes(ax, lonTrack, latTrack, labels, labelEvery)
    hOutline = plot(ax, lonTrack, latTrack, '-', 'Color', [1 1 1], 'LineWidth', 4);
    hTrack = plot(ax, lonTrack, latTrack, '-o', ...
        'Color', [0.85 0 0], ...
        'MarkerFaceColor', [1 0.9 0.1], ...
        'MarkerEdgeColor', [0.25 0 0], ...
        'LineWidth', 2, ...
        'MarkerSize', 6);

    hStart = scatter(ax, lonTrack(1), latTrack(1), 90, [0.1 0.8 0.2], 'filled', ...
        'MarkerEdgeColor', 'k');
    hEnd = scatter(ax, lonTrack(end), latTrack(end), 90, [0.9 0.1 0.9], 'filled', ...
        'MarkerEdgeColor', 'k');

    for i = 1:labelEvery:numel(lonTrack)
        text(ax, lonTrack(i) + 0.15, latTrack(i) + 0.15, labels(i), ...
            'FontSize', 8, ...
            'Color', 'k', ...
            'BackgroundColor', [1 1 1], ...
            'Margin', 1, ...
            'Interpreter', 'none');
    end
end

function drawCoastlineBasemap(ax, lonLim, latLim)
    [coastLon, coastLat] = loadCoastlineData();

    set(ax, 'Color', [0.78 0.90 1.00]);
    hold(ax, 'on');

    patch(ax, ...
        [lonLim(1), lonLim(2), lonLim(2), lonLim(1)], ...
        [latLim(1), latLim(1), latLim(2), latLim(2)], ...
        [0.78 0.90 1.00], ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');

    plot(ax, coastLon, coastLat, ...
        'Color', [0.18 0.18 0.18], ...
        'LineWidth', 0.9, ...
        'HandleVisibility', 'off');

    xlim(ax, lonLim);
    ylim(ax, latLim);
end

function [coastLon, coastLat] = loadCoastlineData()
    try
        data = load('coastlines');
        coastLon = data.coastlon;
        coastLat = data.coastlat;
        return;
    catch
    end

    try
        data = load('coast');
        coastLon = data.long;
        coastLat = data.lat;
        return;
    catch
    end

    warning(['MATLAB coastline data was not found. Using a simplified ', ...
        'East Asia / western North Pacific coastline built into this script.']);
    [coastLon, coastLat] = fallbackEastAsiaCoastline();
end

function [coastLon, coastLat] = fallbackEastAsiaCoastline()
    % Simplified coastlines for the China coast, Korean Peninsula, Japan,
    % Taiwan, the Philippines, and nearby islands. This is only a map
    % reference layer for the typhoon-track figure.
    lines = {
        [105.0 10.5; 106.0 12.0; 107.5 14.5; 108.8 17.0; 109.5 18.8; ...
         108.5 20.3; 110.0 21.1; 111.5 21.4; 113.0 22.1; 114.3 22.4; ...
         115.8 22.8; 117.2 23.6; 118.6 24.6; 119.6 25.8; 120.4 27.2; ...
         121.2 28.6; 121.7 30.0; 121.4 31.4; 120.5 32.4; 120.1 33.3; ...
         120.7 34.5; 121.5 36.0; 122.2 37.3; 121.2 38.6; 119.8 39.2; ...
         118.4 39.0; 119.2 40.0; 121.0 40.6; 122.4 40.8; 124.1 40.0; ...
         125.5 38.8; 126.6 37.4; 127.5 35.8; 128.3 34.8; 129.4 35.4; ...
         129.7 37.0; 130.3 39.0; 131.0 41.0], ...
        [120.0 21.8; 120.6 22.5; 121.0 23.4; 121.5 24.4; 122.0 25.2; ...
         121.5 25.5; 120.9 24.9; 120.4 24.0; 120.0 23.0; 119.8 22.2; ...
         120.0 21.8], ...
        [130.0 31.0; 131.3 31.8; 132.0 33.0; 131.1 34.0; 129.8 33.2; ...
         129.4 32.0; 130.0 31.0], ...
        [132.0 33.8; 134.0 34.4; 136.0 34.9; 138.0 35.5; 139.6 36.4; ...
         140.8 38.0; 141.5 40.0; 141.0 41.2; 140.0 39.2; 139.0 37.0; ...
         137.0 35.5; 134.5 35.0; 132.0 33.8], ...
        [141.0 42.0; 143.0 42.5; 145.2 44.0; 144.2 45.5; 142.2 45.0; ...
         141.0 43.5; 141.0 42.0], ...
        [120.0 18.5; 121.5 18.2; 122.4 17.0; 122.0 15.5; 121.0 14.0; ...
         120.2 13.5; 119.8 15.5; 120.0 18.5], ...
        [122.0 13.0; 124.0 12.0; 125.2 10.0; 126.0 8.0; 125.0 6.2; ...
         123.2 6.0; 122.0 8.5; 121.0 10.5; 122.0 13.0], ...
        [109.0 7.0; 112.0 6.0; 115.0 5.2; 118.0 5.0; 120.0 3.0; ...
         119.0 1.0; 116.0 0.0; 113.0 1.0; 110.0 3.5; 109.0 7.0], ...
        [123.4 24.5; 124.2 25.2; 125.3 25.9; 126.6 26.5; 127.7 26.8; ...
         128.4 27.3; 129.5 28.0; 130.4 30.0]
    };

    coastLon = [];
    coastLat = [];
    for i = 1:numel(lines)
        coastLon = [coastLon; lines{i}(:, 1); NaN]; %#ok<AGROW>
        coastLat = [coastLat; lines{i}(:, 2); NaN]; %#ok<AGROW>
    end
end

function tf = hasAnyColumn(tableData, candidates)
    tf = ~isempty(findColumnName(tableData, candidates, false));
end

function values = readNumericColumn(tableData, candidates)
    name = findColumnName(tableData, candidates, true);
    raw = tableData.(name);
    if isnumeric(raw)
        values = double(raw);
    elseif isdatetime(raw)
        values = datenum(raw);
    else
        values = str2double(string(raw));
    end
    values = values(:);
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
        error('Cannot find any of these columns in Task.xlsx: %s', strjoin(candidates, ', '));
    end
end

function times = readUtcTimes(tableData)
    if hasAnyColumn(tableData, {'TimeUTC'})
        raw = tableData.(findColumnName(tableData, {'TimeUTC'}, true));
        times = parseDatetimeValues(raw);
        return;
    end

    if hasAnyColumn(tableData, {'DateUTC'}) && hasAnyColumn(tableData, {'HHMM'})
        dateRaw = string(tableData.(findColumnName(tableData, {'DateUTC'}, true)));
        hhmmRaw = tableData.(findColumnName(tableData, {'HHMM'}, true));
        if isnumeric(hhmmRaw)
            hhmmText = compose('%04.0f', hhmmRaw);
        else
            hhmmText = string(hhmmRaw);
            hhmmText = pad(hhmmText, 4, 'left', '0');
        end
        times = parseDatetimeValues(strtrim(dateRaw) + " " + hhmmText);
        return;
    end

    warning('No TimeUTC or DateUTC/HHMM columns were found. Points will use row labels.');
    times = NaT(height(tableData), 1);
end

function times = parseDatetimeValues(raw)
    if isdatetime(raw)
        times = raw(:);
        return;
    end

    if isnumeric(raw)
        times = datetime(raw(:), 'ConvertFrom', 'excel');
        return;
    end

    textValues = strtrim(string(raw(:)));
    times = NaT(size(textValues));
    formats = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', ...
        'yyyy/MM/dd HH:mm:ss', 'yyyy/MM/dd HH:mm', ...
        'yyyyMMdd HHmm', 'yyyy-MM-dd HHmm', 'yyyy/MM/dd HHmm'};

    for i = 1:numel(formats)
        idx = isnat(times) & strlength(textValues) > 0;
        if ~any(idx)
            break;
        end

        try
            times(idx) = datetime(textValues(idx), 'InputFormat', formats{i});
        catch
        end
    end

    idx = isnat(times) & strlength(textValues) > 0;
    if any(idx)
        try
            times(idx) = datetime(textValues(idx));
        catch
        end
    end
end

function labels = makeUtcLabels(times, tableData)
    labels = strings(numel(times), 1);

    if any(~isnat(times))
        for i = 1:numel(times)
            labels(i) = string(datestr(times(i), 'mm-dd HHMM')) + " UTC";
        end
        return;
    end

    if hasAnyColumn(tableData, {'HHMM'})
        hhmm = tableData.(findColumnName(tableData, {'HHMM'}, true));
        if isnumeric(hhmm)
            labels = compose('%04.0f UTC', hhmm);
        else
            labels = string(hhmm) + " UTC";
        end
    else
        labels = "Point " + string((1:height(tableData)).');
    end
end

function baseNcFile = chooseBaseNcFile(baseNcFile, tableData, dataRoot)
    if strlength(string(baseNcFile)) > 0
        baseNcFile = char(baseNcFile);
        if ~isfile(baseNcFile)
            error('baseNcFile does not exist: %s', baseNcFile);
        end
        return;
    end

    if hasAnyColumn(tableData, {'FileName'})
        fileColumn = string(tableData.(findColumnName(tableData, {'FileName'}, true)));
        for i = 1:numel(fileColumn)
            candidate = char(fileColumn(i));
            if isfile(candidate)
                baseNcFile = candidate;
                return;
            end
        end
    end

    files = listNcFiles(dataRoot);
    if isempty(files)
        error('No .nc files found under: %s', dataRoot);
    end

    files = sort(string(files));
    baseNcFile = char(files(1));
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

    error('Could not find %s variable. Check ncdisp(file) and add its name to candidates.', label);
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
    data(abs(data) > 1.0e30) = NaN;
    data(data < -1.0e20) = NaN;

    attrs = varInfo.Attributes;
    data = maskAttributeValues(data, attrs, {'_FillValue', 'missing_value'});
    data = maskValidRange(data, attrs);

    switch lower(kind)
        case 'cot'
            data = scalePackedCotIfNeeded(data, attrs);
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

    scaleFactor = scalarAttributeOrEmpty(getAttribute(attrs, 'scale_factor'));
    addOffset = scalarAttributeOrEmpty(getAttribute(attrs, 'add_offset'));

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
