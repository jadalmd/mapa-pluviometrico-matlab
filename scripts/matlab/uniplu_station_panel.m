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
