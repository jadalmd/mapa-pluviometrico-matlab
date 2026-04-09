clear; clc; close all;

set(groot, 'defaultFigureColor', 'w', 'defaultAxesColor', 'w', ...
    'defaultAxesXColor', 'k', 'defaultAxesYColor', 'k', 'defaultTextColor', 'k');

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));

matCandidates = {
    fullfile(projectRoot, 'outputs', 'dados_hidro_br_mensal_real.mat')
    fullfile(projectRoot, 'dados_hidro_br_mensal_real.mat')
    fullfile(projectRoot, 'outputs', 'dados_hidro_br_mensal.mat')
    fullfile(projectRoot, 'dados_hidro_br_mensal.mat')
    'dados_hidro_br_mensal_real.mat'
    'dados_hidro_br_mensal.mat'
    };

[dataTbl, sourceMat] = loadUnipluMonthlyData(matCandidates);
dataTbl = cleanInputTable(dataTbl);

if isempty(dataTbl)
    error('No valid rows found after cleaning input data.');
end

availableYears = sort(unique(dataTbl.year));
if isempty(availableYears)
    error('Dataset has no valid years.');
end

intro_text = sprintf(['UNIPLU-BR HYDROLOGICAL DATA ANALYSIS TOOL\n\n', ...
    'Data Source: dados_hidro_br_mensal_real.mat\n', ...
    'Loaded File: %s\n', ...
    'Available Period: %d - %d\n\n', ...
    'Available Modules:\n\n', ...
    '[1] Spatial Distribution Maps (Statewide):\n', ...
    '    Creates annual spatial precipitation maps for a selected state\n', ...
    '    and period, plus a tangible data report for each year.\n\n', ...
    '[2] Time Series & Statistical Analysis:\n', ...
    '    Evaluates annual totals in statewide aggregated mode or\n', ...
    '    specific station mode, including trends and anomalies.\n', ...
    '    - Annual Hyetograph & Linear Trend\n', ...
    '    - Precipitation Anomalies\n', ...
    '    - Low-Pass Filter (5-year Moving Average)\n', ...
    '    - Mann-Kendall test (ktaub wrapper)']);

uiwait(msgbox(intro_text, 'Tool Information & Overview', 'help'));

menuOptions = {
    '[1] Spatial Distribution Maps (Statewide)'
    '[2] Time Series & Statistical Analysis'
    };

[idxMain, isConfirmed] = listdlg( ...
    'PromptString', 'Select the desired analysis module:', ...
    'SelectionMode', 'single', ...
    'ListString', menuOptions, ...
    'Name', 'Main Menu', ...
    'ListSize', [450, 120]);

if ~isConfirmed || isempty(idxMain)
    disp('Session terminated by user.');
    return;
end

switch idxMain
    case 1
        runSpatialDistributionModule(dataTbl);
    case 2
        runTimeSeriesModule(dataTbl);
end


function runSpatialDistributionModule(dataTbl)
states = sort(unique(dataTbl.state));

[idxState, okState] = listdlg( ...
    'PromptString', 'Select ONE STATE:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(states), ...
    'Name', 'State Selection', ...
    'ListSize', [300, 420]);

if ~okState || isempty(idxState)
    return;
end

selectedState = states(idxState);
stateData = dataTbl(dataTbl.state == selectedState, :);

availableYears = sort(unique(stateData.year));
if isempty(availableYears)
    errordlg('No years available for selected state.', 'Data Error');
    return;
end

[idxStart, okStart] = listdlg( ...
    'PromptString', 'Select START YEAR:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(availableYears)), ...
    'Name', 'Temporal Window Setup');

if ~okStart || isempty(idxStart)
    return;
end

startYear = availableYears(idxStart);
endCandidates = availableYears(availableYears >= startYear);

[idxEnd, okEnd] = listdlg( ...
    'PromptString', 'Select END YEAR:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(endCandidates)), ...
    'Name', 'Temporal Window Setup');

if ~okEnd || isempty(idxEnd)
    return;
end

endYear = endCandidates(idxEnd);
selectedYears = startYear:endYear;

figure('Name', sprintf('Spatial Distribution Maps - %s', selectedState), ...
    'Position', [100, 100, 1200, 720]);
tiledlayout('flow', 'TileSpacing', 'compact', 'Padding', 'compact');

report_text = sprintf('--- ANNUAL PRECIPITATION REPORT ---\n\n');

for i = 1:numel(selectedYears)
    thisYear = selectedYears(i);
    yearData = stateData(stateData.year == thisYear, :);
    stationYear = aggregateAnnualStationYear(yearData, 10);
    stationYear = stationYear(~isnan(stationYear.annual_total), :);

    if isempty(stationYear)
        report_text = [report_text, sprintf('YEAR %d:\n', thisYear)]; %#ok<AGROW>
        report_text = [report_text, sprintf('  State Average: n/a\n')]; %#ok<AGROW>
        report_text = [report_text, sprintf('  Rainiest Station: n/a\n')]; %#ok<AGROW>
        report_text = [report_text, sprintf('  Driest Station: n/a\n\n')]; %#ok<AGROW>

        ax = nexttile;
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('%d\nNo valid annual totals', thisYear), ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        continue;
    end

    [maxRain, maxIdx] = max(stationYear.annual_total);
    [minRain, minIdx] = min(stationYear.annual_total);
    meanRain = mean(stationYear.annual_total, 'omitnan');

    wetLabel = sprintf('%s (%s)', stationYear.city(maxIdx), stationYear.gauge_code(maxIdx));
    dryLabel = sprintf('%s (%s)', stationYear.city(minIdx), stationYear.gauge_code(minIdx));

    report_text = [report_text, sprintf('YEAR %d:\n', thisYear)]; %#ok<AGROW>
    report_text = [report_text, sprintf('  State Average: %.1f mm\n', meanRain)]; %#ok<AGROW>
    report_text = [report_text, sprintf('  Rainiest Station: %s (%.1f mm)\n', wetLabel, maxRain)]; %#ok<AGROW>
    report_text = [report_text, sprintf('  Driest Station: %s (%.1f mm)\n\n', dryLabel, minRain)]; %#ok<AGROW>

    ax = nexttile;
    drawAnnualSpatialMap(ax, stationYear, thisYear);
end

cb = colorbar;
cb.Layout.Tile = 'east';
cb.Label.String = 'Annual Total Precipitation (mm)';

uiwait(msgbox(report_text, 'Tangible Data: Maps Summary', 'help'));
end


function runTimeSeriesModule(dataTbl)
states = sort(unique(dataTbl.state));
[idxState, okState] = listdlg( ...
    'PromptString', 'Select ONE STATE:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(states), ...
    'Name', 'State Selection', ...
    'ListSize', [300, 420]);

if ~okState || isempty(idxState)
    return;
end

selectedState = states(idxState);
stateData = dataTbl(dataTbl.state == selectedState, :);

scopeChoice = questdlg('Choose analysis scope:', ...
    'Analysis Scope', ...
    'Statewide (Aggregated)', ...
    'Specific Station', ...
    'Statewide (Aggregated)');

if isempty(scopeChoice)
    return;
end

selectedGauge = "";
selectedLabel = "";
scopeData = stateData;

if strcmp(scopeChoice, 'Specific Station')
    stationMeta = unique(stateData(:, {'gauge_code', 'city'}), 'rows');
    stationLabels = stationMeta.city + " | " + stationMeta.gauge_code;

    [idxStation, okStation] = listdlg( ...
        'PromptString', 'Select ONE STATION:', ...
        'SelectionMode', 'single', ...
        'ListString', cellstr(stationLabels), ...
        'Name', 'Station Selection', ...
        'ListSize', [460, 420]);

    if ~okStation || isempty(idxStation)
        return;
    end

    selectedGauge = stationMeta.gauge_code(idxStation);
    selectedLabel = stationLabels(idxStation);
    scopeData = stateData(stateData.gauge_code == selectedGauge, :);
end

validYears = sort(unique(scopeData.year));
if isempty(validYears)
    errordlg('No years available for selected scope.', 'Data Error');
    return;
end

[idxStart, okStart] = listdlg( ...
    'PromptString', 'Select START YEAR:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(validYears)), ...
    'Name', 'Time Period');

if ~okStart || isempty(idxStart)
    return;
end

startYear = validYears(idxStart);
endCandidates = validYears(validYears >= startYear);

[idxEnd, okEnd] = listdlg( ...
    'PromptString', 'Select END YEAR:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(endCandidates)), ...
    'Name', 'Time Period');

if ~okEnd || isempty(idxEnd)
    return;
end

endYear = endCandidates(idxEnd);
periodData = scopeData(scopeData.year >= startYear & scopeData.year <= endYear, :);

if isempty(periodData)
    errordlg('No data found for selected period.', 'Data Error');
    return;
end

yearsVec = (startYear:endYear)';
annualByStation = aggregateAnnualStationYear(periodData, 10);

if strcmp(scopeChoice, 'Statewide (Aggregated)')
    annualTotals = nan(size(yearsVec));
    for i = 1:numel(yearsVec)
        y = yearsVec(i);
        vals = annualByStation.annual_total(annualByStation.year == y);
        if ~isempty(vals)
            annualTotals(i) = mean(vals, 'omitnan');
        end
    end
    baseTitle = "Statewide Aggregated - " + selectedState;
else
    annualTotals = nan(size(yearsVec));
    stationAnnual = annualByStation(annualByStation.gauge_code == selectedGauge, :);
    [tf, pos] = ismember(stationAnnual.year, yearsVec);
    annualTotals(pos(tf)) = stationAnnual.annual_total(tf);
    baseTitle = "Station " + selectedLabel;
end

longTermMean = mean(annualTotals, 'omitnan');
anomalies = annualTotals - longTermMean;
movingAvg = movmean(annualTotals, 5, 'omitnan');

valid = ~isnan(annualTotals);
[pValue, senSlope, trendLabel] = runKtaubSafe(yearsVec(valid), annualTotals(valid));

figure('Name', 'Time Series & Statistical Analysis', 'Position', [130, 100, 1000, 900]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
bar(ax1, yearsVec, annualTotals, 'FaceColor', [0.60 0.80 0.90], 'EdgeColor', 'none');
hold(ax1, 'on');
yline(ax1, longTermMean, 'k--', 'LTM', 'LineWidth', 1.4, 'LabelHorizontalAlignment', 'left');

if sum(valid) >= 2
    pfit = polyfit(yearsVec(valid), annualTotals(valid), 1);
    plot(ax1, yearsVec, polyval(pfit, yearsVec), 'r-', 'LineWidth', 1.5);
    legend(ax1, {'Annual Total', 'LTM', 'Linear Trend'}, 'Location', 'best');
else
    legend(ax1, {'Annual Total', 'LTM'}, 'Location', 'best');
end

title(ax1, sprintf('Annual Hyetograph | Kendall p-value = %s | Sen slope = %s mm/year', ...
    formatMetric(pValue), formatMetric(senSlope)));
ylabel(ax1, 'Precipitation (mm)');
grid(ax1, 'on');

ax2 = nexttile;
b = bar(ax2, yearsVec, anomalies, 'FaceColor', 'flat', 'EdgeColor', 'none');
posMask = anomalies >= 0;
negMask = anomalies < 0;
b.CData(posMask, :) = repmat([0.20 0.60 0.85], sum(posMask), 1);
b.CData(negMask, :) = repmat([0.85 0.30 0.30], sum(negMask), 1);
title(ax2, 'Precipitation Anomalies (Annual Total - LTM)');
ylabel(ax2, '\Delta Precipitation (mm)');
grid(ax2, 'on');

ax3 = nexttile;
plot(ax3, yearsVec, annualTotals, '-.', 'Color', [0.65 0.65 0.65], 'LineWidth', 1.2);
hold(ax3, 'on');
plot(ax3, yearsVec, movingAvg, 'k-', 'LineWidth', 2);
title(ax3, 'Low-Pass Filter (5-Year Moving Average)');
xlabel(ax3, 'Year');
ylabel(ax3, 'Precipitation (mm)');
legend(ax3, {'Original Signal', '5-year Moving Average'}, 'Location', 'best');
grid(ax3, 'on');

linkaxes([ax1, ax2, ax3], 'x');
xlim(ax1, [startYear - 0.5, endYear + 0.5]);

[maxAnnual, idxMax] = max(annualTotals);
[minAnnual, idxMin] = min(annualTotals);

if isempty(idxMax) || isnan(maxAnnual)
    wettestYearText = 'n/a';
else
    wettestYearText = sprintf('%d (%.1f mm)', yearsVec(idxMax), maxAnnual);
end

if isempty(idxMin) || isnan(minAnnual)
    driestYearText = 'n/a';
else
    driestYearText = sprintf('%d (%.1f mm)', yearsVec(idxMin), minAnnual);
end

report_text = sprintf('--- TIME SERIES REPORT ---\nPeriod: %d to %d\n\n', startYear, endYear);
report_text = [report_text, sprintf('Scope: %s\n', baseTitle)];
report_text = [report_text, sprintf('Long-Term Mean (LTM): %s mm\n', formatMetric(longTermMean))];
report_text = [report_text, sprintf('Wettest Year: %s\n', wettestYearText)];
report_text = [report_text, sprintf('Driest Year: %s\n', driestYearText)];
report_text = [report_text, sprintf('Kendall p-value: %s\n', formatMetric(pValue))];
report_text = [report_text, sprintf('Sen slope: %s mm/year\n', formatMetric(senSlope))];
report_text = [report_text, sprintf('Trend Interpretation: %s\n', trendLabel)];

uiwait(msgbox(report_text, 'Tangible Data: Time Series Summary', 'help'));

if strcmp(scopeChoice, 'Specific Station')
    [availability, availYears] = buildMonthlyAvailability(scopeData, startYear, endYear);

    figure('Name', 'Monthly Availability Heatmap', 'Position', [180, 150, 920, 430]);
    imagesc(availYears, 1:12, availability);
    set(gca, 'YDir', 'normal');
    yticks(1:12);
    yticklabels({'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'});
    xlabel('Year');
    ylabel('Month');
    title(sprintf('Data Availability (Present vs Missing) - %s', selectedLabel), 'Interpreter', 'none');
    colormap(gca, [0.85 0.35 0.35; 0.25 0.65 0.35]);
    caxis([0 1]);
    cb = colorbar;
    cb.Ticks = [0, 1];
    cb.TickLabels = {'Missing', 'Present'};
    grid on;
end
end


function drawAnnualSpatialMap(ax, stationYear, thisYear)
lon = stationYear.lon;
lat = stationYear.lat;
z = stationYear.annual_total;

lonValid = lon(~isnan(lon) & ~isnan(lat) & ~isnan(z));
latValid = lat(~isnan(lon) & ~isnan(lat) & ~isnan(z));
zValid = z(~isnan(lon) & ~isnan(lat) & ~isnan(z));

if numel(zValid) < 3 || numel(unique(lonValid)) < 2 || numel(unique(latValid)) < 2
    scatter(ax, lonValid, latValid, 60, zValid, 'filled', 'MarkerEdgeColor', 'k');
    title(ax, sprintf('%d (insufficient points for interpolation)', thisYear));
    xlabel(ax, 'Longitude');
    ylabel(ax, 'Latitude');
    grid(ax, 'on');
    axis(ax, 'tight');
    return;
end

lonMin = min(lonValid); lonMax = max(lonValid);
latMin = min(latValid); latMax = max(latValid);
padLon = max((lonMax - lonMin) * 0.08, 0.05);
padLat = max((latMax - latMin) * 0.08, 0.05);

xq = linspace(lonMin - padLon, lonMax + padLon, 120);
yq = linspace(latMin - padLat, latMax + padLat, 120);
[lonGrid, latGrid] = meshgrid(xq, yq);

F = scatteredInterpolant(lonValid, latValid, zValid, 'natural', 'none');
Z = F(lonGrid, latGrid);

if numel(lonValid) >= 3
    try
        hullIdx = convhull(lonValid, latValid);
        inMask = inpolygon(lonGrid, latGrid, lonValid(hullIdx), latValid(hullIdx));
        Z(~inMask) = NaN;
    catch
        % Keep bounding-box interpolation when convex hull fails.
    end
end

contourf(ax, lonGrid, latGrid, Z, 18, 'LineStyle', 'none');
hold(ax, 'on');
scatter(ax, lonValid, latValid, 22, 'k', 'filled', 'MarkerFaceAlpha', 0.35);

cmap = [ ...
    0.95 1.00 1.00
    0.75 0.93 0.98
    0.45 0.78 0.93
    0.22 0.57 0.83
    0.08 0.33 0.68
    0.04 0.15 0.45
    ];
colormap(ax, interp1(linspace(0, 1, size(cmap, 1)), cmap, linspace(0, 1, 256)));

xlabel(ax, 'Longitude');
ylabel(ax, 'Latitude');
title(ax, sprintf('%d', thisYear), 'FontWeight', 'bold');
grid(ax, 'on');
axis(ax, 'tight');
end


function [availability, yearsVec] = buildMonthlyAvailability(dataTbl, startYear, endYear)
yearsVec = startYear:endYear;
availability = zeros(12, numel(yearsVec));

for i = 1:height(dataTbl)
    y = dataTbl.year(i);
    m = dataTbl.month(i);
    r = dataTbl.rain_mm(i);

    if y < startYear || y > endYear || isnan(m) || m < 1 || m > 12
        continue;
    end

    yPos = find(yearsVec == y, 1, 'first');
    if isempty(yPos)
        continue;
    end

    if ~isnan(r)
        availability(m, yPos) = 1;
    end
end
end


function annualTbl = aggregateAnnualStationYear(dataTbl, minMonthsPerYear)
if isempty(dataTbl)
    annualTbl = table();
    return;
end

groups = findgroups(dataTbl.gauge_code, dataTbl.year);

validCount = splitapply(@(x) sum(~isnan(x)), dataTbl.rain_mm, groups);
rawSum = splitapply(@(x) sum(x, 'omitnan'), dataTbl.rain_mm, groups);
annualTotal = rawSum;
annualTotal(validCount < minMonthsPerYear) = NaN;

gauge = splitapply(@(x) x(1), dataTbl.gauge_code, groups);
year = splitapply(@(x) x(1), dataTbl.year, groups);
city = splitapply(@(x) x(1), dataTbl.city, groups);
state = splitapply(@(x) x(1), dataTbl.state, groups);
lat = splitapply(@(x) mean(x, 'omitnan'), dataTbl.lat, groups);
lon = splitapply(@(x) mean(x, 'omitnan'), dataTbl.lon, groups);

annualTbl = table(gauge, year, annualTotal, validCount, lat, lon, city, state, ...
    'VariableNames', {'gauge_code', 'year', 'annual_total', 'valid_months', 'lat', 'lon', 'city', 'state'});
end


function [tbl, sourcePath] = loadUnipluMonthlyData(matCandidates)
sourcePath = '';
raw = [];

for i = 1:numel(matCandidates)
    if isfile(matCandidates{i})
        raw = load(matCandidates{i});
        sourcePath = matCandidates{i};
        break;
    end
end

if isempty(sourcePath)
    error('MAT file not found. Expected dados_hidro_br_mensal_real.mat in standard paths.');
end

tbl = extractAsTable(raw);
if isempty(tbl) || ~istable(tbl)
    error('Could not parse dataset from MAT file: %s', sourcePath);
end
end


function tbl = extractAsTable(raw)
required = {'gauge_code', 'year', 'month', 'rain_mm', 'lat', 'long', 'city', 'state'};
tbl = table();

if all(isfield(raw, required))
    tbl = table(raw.gauge_code, raw.year, raw.month, raw.rain_mm, raw.lat, raw.long, raw.city, raw.state, ...
        'VariableNames', required);
    return;
end

fields = fieldnames(raw);

for i = 1:numel(fields)
    obj = raw.(fields{i});

    if istable(obj) && all(ismember(required, obj.Properties.VariableNames))
        tbl = obj(:, required);
        return;
    end

    if isstruct(obj) && isscalar(obj) && all(isfield(obj, required))
        tbl = table(obj.gauge_code, obj.year, obj.month, obj.rain_mm, obj.lat, obj.long, obj.city, obj.state, ...
            'VariableNames', required);
        return;
    end

    if isstruct(obj) && all(ismember(required, fieldnames(obj)))
        tbl = struct2table(obj);
        tbl = tbl(:, required);
        return;
    end
end

if ~isempty(fields)
    firstObj = raw.(fields{1});
    if isstruct(firstObj) && isscalar(firstObj)
        nestedFields = fieldnames(firstObj);
        for j = 1:numel(nestedFields)
            nestedObj = firstObj.(nestedFields{j});
            if istable(nestedObj) && all(ismember(required, nestedObj.Properties.VariableNames))
                tbl = nestedObj(:, required);
                return;
            end
        end
    end
end
end


function outTbl = cleanInputTable(tbl)
outTbl = tbl;

outTbl.gauge_code = normalizeText(toStringColumn(outTbl.gauge_code));
outTbl.city = normalizeText(toStringColumn(outTbl.city));
outTbl.state = normalizeText(toStringColumn(outTbl.state));

outTbl.year = toNumericColumn(outTbl.year);
outTbl.month = toNumericColumn(outTbl.month);
outTbl.rain_mm = toNumericColumn(outTbl.rain_mm);
outTbl.lat = toNumericColumn(outTbl.lat);
outTbl.lon = toNumericColumn(outTbl.long);

validRows = outTbl.gauge_code ~= "" & outTbl.state ~= "" & ...
    ~isnan(outTbl.year) & ~isnan(outTbl.month) & outTbl.month >= 1 & outTbl.month <= 12;

outTbl = outTbl(validRows, :);
outTbl = removevars(outTbl, 'long');
outTbl = sortrows(outTbl, {'state', 'gauge_code', 'year', 'month'});
end


function s = toStringColumn(x)
if isstring(x)
    s = x(:);
elseif ischar(x)
    s = string(cellstr(x));
elseif iscell(x)
    s = strings(numel(x), 1);
    for i = 1:numel(x)
        s(i) = string(x{i});
    end
elseif isnumeric(x) || islogical(x)
    s = string(x(:));
else
    s = string(x);
    s = s(:);
end
end


function s = normalizeText(s)
s = upper(strtrim(s));
s(ismissing(s)) = "";
end


function n = toNumericColumn(x)
if isnumeric(x) || islogical(x)
    n = double(x(:));
elseif isstring(x)
    n = str2double(x(:));
elseif ischar(x)
    n = str2double(string(cellstr(x)));
elseif iscell(x)
    n = nan(numel(x), 1);
    for i = 1:numel(x)
        n(i) = str2double(string(x{i}));
    end
else
    n = str2double(string(x));
    n = n(:);
end
end


function [pValue, senSlope, trendLabel] = runKtaubSafe(years, values)
pValue = NaN;
senSlope = NaN;
trendLabel = 'No significant trend';

if numel(values) < 3 || numel(years) ~= numel(values)
    return;
end

alpha = 0.05;
datain = [years(:), values(:)];

try
    [~, ~, h, sig, ~, ~, ~, sen] = ktaub(datain, alpha, 0);
    pValue = sig;
    senSlope = sen;
    trendLabel = mkTrendLabel(h, senSlope);
catch
    trendLabel = 'ktaub not available/incompatible';
end
end


function t = mkTrendLabel(h, senSlope)
if isnumeric(h) && h == 1
    if isfinite(senSlope) && senSlope > 0
        t = 'Increasing trend';
    elseif isfinite(senSlope) && senSlope < 0
        t = 'Decreasing trend';
    else
        t = 'Significant trend';
    end
else
    t = 'No significant trend';
end
end


function txt = formatMetric(v)
if isempty(v) || ~isfinite(v)
    txt = 'n/a';
else
    txt = sprintf('%.3f', v);
end
end
clear; clc; close all;

set(groot, 'defaultFigureColor', 'w', 'defaultAxesColor', 'w', ...
    'defaultAxesXColor', 'k', 'defaultAxesYColor', 'k', 'defaultTextColor', 'k');

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(scriptDir));

introText = sprintf([ ...
    'UNIPLU-BR Monthly Rainfall Analysis Tool\n\n', ...
    'This module works with monthly station data and provides:\n', ...
    '[1] Station map by selected state\n', ...
    '[2] Monthly availability matrix (month x year)\n', ...
    '[3] Monthly hyetograph\n', ...
    '[4] Annual totals with Mann-Kendall / Sen trend\n\n', ...
    'Now select the source MAT file and analysis options.']);
uiwait(msgbox(introText, 'UNIPLU-BR Tool', 'help'));

% Prefer real/full datasets first.
matCandidates = {
    fullfile(projectRoot, 'outputs', 'dados_hidro_br_mensal_real.mat')
    fullfile(projectRoot, 'dados_hidro_br_mensal_real.mat')
    fullfile(projectRoot, 'outputs', 'dados_hidro_br_mensal.mat')
    fullfile(projectRoot, 'dados_hidro_br_mensal.mat')
    'dados_hidro_br_mensal_real.mat'
    'dados_hidro_br_mensal.mat'
    };

existingMat = {};
for i = 1:numel(matCandidates)
    if isfile(matCandidates{i})
        existingMat{end+1,1} = matCandidates{i}; %#ok<SAGROW>
    end
end

if isempty(existingMat)
    error('No MAT file found. Expected dados_hidro_br_mensal*.mat in project root or outputs.');
end

% Remove duplicates while preserving order.
[~, ia] = unique(existingMat, 'stable');
existingMat = existingMat(sort(ia));

if numel(existingMat) > 1
    [idxMat, okMat] = listdlg(...
        'PromptString', 'Select the MAT source file:', ...
        'SelectionMode', 'single', ...
        'ListString', existingMat, ...
        'ListSize', [800, 220]);
    if ~okMat || isempty(idxMat)
        disp('Selection canceled. Exiting script.');
        return;
    end
    matFile = existingMat{idxMat};
else
    matFile = existingMat{1};
end

loadedData = load(matFile);
rootFields = fieldnames(loadedData);
if isempty(rootFields)
    error('MAT file has no variables: %s', matFile);
end

dataStruct = loadedData.(rootFields{1});

stateCol = normalizeTextColumn(toCellStrColumn(getFieldOrError(dataStruct, 'state')));
cityCol = normalizeTextColumn(toCellStrColumn(getFieldOrError(dataStruct, 'city')));
gaugeCodeCol = normalizeTextColumn(toCellStrColumn(getFieldOrError(dataStruct, 'gauge_code')));
yearCol = toNumericColumn(getFieldOrError(dataStruct, 'year'));
monthCol = toNumericColumn(getFieldOrError(dataStruct, 'month'));
rainCol = toNumericColumn(getFieldOrError(dataStruct, 'rain_mm'));
latCol = toNumericColumn(getFieldOrError(dataStruct, 'lat'));
lonCol = toNumericColumn(getFieldOrError(dataStruct, 'long'));

% Basic row validity.
validRows = ~cellfun(@isempty, stateCol) & ~cellfun(@isempty, gaugeCodeCol) & ...
    ~isnan(yearCol) & ~isnan(monthCol) & monthCol >= 1 & monthCol <= 12;

stateCol = stateCol(validRows);
cityCol = cityCol(validRows);
gaugeCodeCol = gaugeCodeCol(validRows);
yearCol = yearCol(validRows);
monthCol = monthCol(validRows);
rainCol = rainCol(validRows);
latCol = latCol(validRows);
lonCol = lonCol(validRows);

stateList = sort(unique(stateCol));
if isempty(stateList)
    error('No valid states found in file: %s', matFile);
end

if numel(stateList) <= 2
    uiwait(warndlg(sprintf(['Only %d state(s) found in selected MAT file.\n', ...
        'This usually means you selected a partial dataset.\n\nFile:\n%s'], numel(stateList), matFile), ...
        'Limited Coverage'));
end

[idxState, okState] = listdlg(...
    'PromptString', 'Select one state:', ...
    'SelectionMode', 'single', ...
    'ListString', stateList, ...
    'ListSize', [320, 420]);

if ~okState || isempty(idxState)
    disp('Selection canceled. Exiting script.');
    return;
end

selectedState = stateList{idxState};
maskState = strcmp(stateCol, selectedState);

stateGauge = gaugeCodeCol(maskState);
stateCity = cityCol(maskState);
stateLat = latCol(maskState);
stateLon = lonCol(maskState);

stationLabels = strcat(stateCity, ' | ', stateGauge);
[uniqueStations, ia] = unique(stationLabels, 'stable');
uniqueGauge = stateGauge(ia);

[idxStation, okStation] = listdlg(...
    'PromptString', sprintf('State %s selected. Now select one station:', selectedState), ...
    'SelectionMode', 'single', ...
    'ListString', uniqueStations, ...
    'ListSize', [550, 420]);

if ~okStation || isempty(idxStation)
    disp('Selection canceled. Exiting script.');
    return;
end

selectedGauge = uniqueGauge{idxStation};
maskStation = maskState & strcmp(gaugeCodeCol, selectedGauge);

stationYear = yearCol(maskStation);
stationMonth = monthCol(maskStation);
stationRain = rainCol(maskStation);

if isempty(stationYear)
    error('No rows found for selected station.');
end

availableYears = sort(unique(stationYear));
[idxStart, okStart] = listdlg(...
    'PromptString', 'Select START year:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(availableYears)), ...
    'ListSize', [260, 300]);
if ~okStart
    disp('Selection canceled. Exiting script.');
    return;
end

startYear = availableYears(idxStart);
endChoices = availableYears(availableYears >= startYear);
[idxEnd, okEnd] = listdlg(...
    'PromptString', 'Select END year:', ...
    'SelectionMode', 'single', ...
    'ListString', cellstr(string(endChoices)), ...
    'ListSize', [260, 300]);
if ~okEnd
    disp('Selection canceled. Exiting script.');
    return;
end

endYear = endChoices(idxEnd);
periodMask = stationYear >= startYear & stationYear <= endYear;
stationYear = stationYear(periodMask);
stationMonth = stationMonth(periodMask);
stationRain = stationRain(periodMask);

if isempty(stationYear)
    error('No data found in selected period.');
end

stationTime = datetime(stationYear, stationMonth, 1);
[stationTime, sortIdx] = sort(stationTime);
stationYear = stationYear(sortIdx);
stationMonth = stationMonth(sortIdx);
stationRain = stationRain(sortIdx);

years = sort(unique(stationYear));
availability = zeros(12, numel(years));
for i = 1:numel(stationRain)
    y = stationYear(i);
    m = stationMonth(i);
    yIdx = find(years == y, 1, 'first');
    if isempty(yIdx)
        continue;
    end
    availability(m, yIdx) = ~isnan(stationRain(i));
end

annualYears = years;
annualTotals = nan(size(annualYears));
annualCoverage = zeros(size(annualYears));
for i = 1:numel(annualYears)
    y = annualYears(i);
    vals = stationRain(stationYear == y);
    annualCoverage(i) = sum(~isnan(vals));
    % Less strict than 12/12 to avoid empty panels with sparse series.
    if annualCoverage(i) >= 10
        annualTotals(i) = sum(vals, 'omitnan');
    end
end

validAnnual = ~isnan(annualTotals);
[pValue, senSlope, trendLabel] = runKtaubSafe(annualYears(validAnnual), annualTotals(validAnnual));

ltmMonthly = mean(stationRain, 'omitnan');
[maxMonthVal, iMaxMonth] = max(stationRain);
[minMonthVal, iMinMonth] = min(stationRain);

if isempty(iMaxMonth) || isnan(maxMonthVal)
    wetMonthTxt = 'n/a';
else
    wetMonthTxt = sprintf('%s (%.1f mm)', datestr(stationTime(iMaxMonth), 'yyyy-mm'), maxMonthVal);
end

if isempty(iMinMonth) || isnan(minMonthVal)
    dryMonthTxt = 'n/a';
else
    dryMonthTxt = sprintf('%s (%.1f mm)', datestr(stationTime(iMinMonth), 'yyyy-mm'), minMonthVal);
end

reportTxt = sprintf([ ...
    'FILE: %s\n', ...
    'STATE: %s\n', ...
    'STATION: %s\n', ...
    'PERIOD: %d-%d\n\n', ...
    'Monthly LTM: %s mm\n', ...
    'Wettest month: %s\n', ...
    'Driest month: %s\n\n', ...
    'Annual MK p-value: %s\n', ...
    'Sen slope: %s mm/year\n', ...
    'Trend: %s'], ...
    matFile, selectedState, selectedGauge, startYear, endYear, ...
    formatMetric(ltmMonthly), wetMonthTxt, dryMonthTxt, ...
    formatMetric(pValue), formatMetric(senSlope), trendLabel);

figure('Color', 'w', 'Name', sprintf('UNIPLU-BR Panel | %s | %s', selectedState, selectedGauge));
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% Panel 1 - State station map
nexttile;
scatter(stateLon, stateLat, 24, [0.65 0.65 0.65], 'filled');
hold on;
selLat = unique(stateLat(strcmp(stateGauge, selectedGauge)));
selLon = unique(stateLon(strcmp(stateGauge, selectedGauge)));
if ~isempty(selLat) && ~isempty(selLon)
    scatter(selLon(1), selLat(1), 90, [0.85 0.20 0.20], 'filled', 'MarkerEdgeColor', 'k');
end
grid on;
xlabel('Longitude');
ylabel('Latitude');
title(sprintf('Station Map - %s', selectedState), 'Interpreter', 'none');
legend({'Other stations', 'Selected station'}, 'Location', 'best');

% Panel 2 - Availability matrix
nexttile;
imagesc(years, 1:12, availability);
set(gca, 'YDir', 'normal');
colormap(gca, [0.88 0.35 0.35; 0.27 0.64 0.35]);
caxis([0 1]);
cb = colorbar;
cb.Ticks = [0, 1];
cb.TickLabels = {'Missing', 'Available'};
yticks(1:12);
yticklabels({'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'});
xlabel('Year');
ylabel('Month');
title('Monthly Availability');

% Panel 3 - Monthly hyetograph
nexttile;
bar(stationTime, stationRain, 'FaceColor', [0.20 0.45 0.80], 'EdgeColor', 'none');
hold on;
yline(ltmMonthly, 'k--', 'LTM', 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
grid on;
xlabel('Time');
ylabel('Monthly Rain (mm)');
title('Monthly Hyetograph');

% Panel 4 - Annual totals and trend
nexttile;
plot(annualYears, annualTotals, '-o', 'LineWidth', 1.5, 'Color', [0.10 0.10 0.10], ...
    'MarkerFaceColor', [0.25 0.25 0.25]);
grid on;
xlabel('Year');
ylabel('Annual Rain (mm)');
title(sprintf('Annual Totals | MK p=%s | Sen=%s | %s', ...
    formatMetric(pValue), formatMetric(senSlope), trendLabel));

sgtitle(sprintf('%s | %s | %d-%d', selectedState, selectedGauge, startYear, endYear), 'Interpreter', 'none');
uiwait(msgbox(reportTxt, 'Analysis Summary', 'help'));


function val = getFieldOrError(s, fieldName)
if ~isfield(s, fieldName)
    error('Field "%s" not found in MAT struct.', fieldName);
end
val = s.(fieldName);
end


function c = toCellStrColumn(x)
if iscell(x)
    c = cell(size(x));
    for i = 1:numel(x)
        c{i} = stringifyScalar(x{i});
    end
    c = c(:);
elseif isstring(x)
    c = cellstr(x(:));
elseif ischar(x)
    c = cellstr(x);
else
    c = cell(size(x));
    for i = 1:numel(x)
        c{i} = stringifyScalar(x(i));
    end
    c = c(:);
end
end


function c = normalizeTextColumn(c)
for i = 1:numel(c)
    c{i} = upper(strtrim(c{i}));
end
end


function n = toNumericColumn(x)
if isnumeric(x) || islogical(x)
    n = double(x(:));
elseif iscell(x)
    n = nan(numel(x), 1);
    for i = 1:numel(x)
        n(i) = str2double(stringifyScalar(x{i}));
    end
else
    n = str2double(stringifyScalar(x));
    n = n(:);
end
end


function s = stringifyScalar(x)
if isstring(x)
    s = char(x);
elseif ischar(x)
    s = x;
elseif isnumeric(x) || islogical(x)
    s = num2str(x);
else
    s = char(string(x));
end
end


function [pValue, senSlope, trendLabel] = runKtaubSafe(years, values)
pValue = NaN;
senSlope = NaN;
trendLabel = 'No significant trend';

if numel(values) < 3 || numel(years) ~= numel(values)
    return;
end

alpha = 0.05;
datain = [years(:), values(:)];

try
    [~,~,h,sig,~,~,~,sen] = ktaub(datain, alpha, 0);
    pValue = sig;
    senSlope = sen;
    trendLabel = mkTrendLabel(h, senSlope);
catch
    trendLabel = 'ktaub not available/incompatible';
end
end


function t = mkTrendLabel(h, senSlope)
if isnumeric(h) && h == 1
    if isfinite(senSlope) && senSlope > 0
        t = 'Increasing trend';
    elseif isfinite(senSlope) && senSlope < 0
        t = 'Decreasing trend';
    else
        t = 'Significant trend';
    end
else
    t = 'No significant trend';
end
end


function out = formatMetric(v)
if isnan(v) || ~isfinite(v)
    out = 'n/a';
else
    out = sprintf('%.4g', v);
end
end
