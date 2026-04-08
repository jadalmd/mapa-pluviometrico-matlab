clear; clc; close all;

% Load MAT file and extract the first struct found in it.
matFile = 'dados_hidro_br_mensal.mat';
if ~isfile(matFile)
    error('File not found: %s', matFile);
end

loadedData = load(matFile);
rootFields = fieldnames(loadedData);
if isempty(rootFields)
    error('MAT file has no variables: %s', matFile);
end

dataStruct = loadedData.(rootFields{1});

stateCol = toCellStrColumn(getFieldOrError(dataStruct, 'state'));
cityCol = toCellStrColumn(getFieldOrError(dataStruct, 'city'));
networkCol = toCellStrColumn(getFieldOrError(dataStruct, 'network')); %#ok<NASGU>
gaugeCodeRaw = getFieldOrError(dataStruct, 'gauge_code');
gaugeCodeCol = toCellStrColumn(gaugeCodeRaw);
yearCol = toNumericColumn(getFieldOrError(dataStruct, 'year'));
monthCol = toNumericColumn(getFieldOrError(dataStruct, 'month'));
rainCol = toNumericColumn(getFieldOrError(dataStruct, 'rain_mm'));

% Prompt user to select a state.
stateList = unique(stateCol, 'stable');
[idxState, okState] = listdlg(...
    'PromptString', 'Select one state:', ...
    'SelectionMode', 'single', ...
    'ListString', stateList, ...
    'ListSize', [300, 400]);

if ~okState || isempty(idxState)
    disp('Selection canceled. Exiting script.');
    return;
end

selectedState = stateList{idxState};
maskState = strcmp(stateCol, selectedState);

stateGauge = gaugeCodeCol(maskState);
stateCity = cityCol(maskState);

% Build station labels with city + gauge code for context.
stationLabels = strcat(stateCity, ' | ', stateGauge);
[uniqueStations, ia] = unique(stationLabels, 'stable');
uniqueGauge = stateGauge(ia);

[idxStation, okStation] = listdlg(...
    'PromptString', sprintf('State %s selected. Now select one station:', selectedState), ...
    'SelectionMode', 'single', ...
    'ListString', uniqueStations, ...
    'ListSize', [500, 400]);

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
    error('No rows found for the selected station.');
end

% Build monthly datetime for plotting.
stationTime = datetime(stationYear, stationMonth, 1);
[stationTime, sortIdx] = sort(stationTime);
stationYear = stationYear(sortIdx);
stationMonth = stationMonth(sortIdx);
stationRain = stationRain(sortIdx);

figure('Color', 'w', 'Name', 'UNIPLU-BR Station Panel');
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% ---- Panel 1: Data availability map (months x years) ----
nexttile;
years = unique(stationYear(~isnan(stationYear)));
if isempty(years)
    years = unique(stationYear);
end
years = sort(years);

availability = zeros(12, numel(years));
for i = 1:numel(stationRain)
    y = stationYear(i);
    m = stationMonth(i);
    if isnan(y) || isnan(m) || m < 1 || m > 12
        continue;
    end
    yIdx = find(years == y, 1, 'first');
    if isempty(yIdx)
        continue;
    end
    if ~isnan(stationRain(i))
        availability(m, yIdx) = 1;
    else
        availability(m, yIdx) = 0;
    end
end

imagesc(years, 1:12, availability);
set(gca, 'YDir', 'normal');
colormap(gca, [0.85 0.33 0.33; 0.27 0.64 0.35]);
caxis([0 1]);
cb = colorbar;
cb.Ticks = [0, 1];
cb.TickLabels = {'Missing/NaN', 'Available'};
yticks(1:12);
yticklabels({'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'});
xlabel('Year');
ylabel('Month');
title(sprintf('Data Availability - Station %s (%s)', selectedGauge, selectedState), 'Interpreter', 'none');

% ---- Panel 2: Monthly hyetograph ----
nexttile;
bar(stationTime, stationRain, 'FaceColor', [0.20 0.45 0.80], 'EdgeColor', 'none');
ylabel('Monthly Rain (mm)');
xlabel('Time');
grid on;
title('Monthly Precipitation (Hyetograph)');

% ---- Panel 3: Annual totals and trend ----
nexttile;
annualYears = unique(stationYear);
annualYears = annualYears(~isnan(annualYears));
annualYears = sort(annualYears);
annualTotals = nan(size(annualYears));

for i = 1:numel(annualYears)
    y = annualYears(i);
    yMask = stationYear == y;
    yearVals = stationRain(yMask);

    % Strict annual rule: require all 12 months and no NaN months.
    if numel(yearVals) < 12 || any(isnan(yearVals))
        annualTotals(i) = NaN;
    else
        annualTotals(i) = sum(yearVals);
    end
end

plot(annualYears, annualTotals, '-o', 'LineWidth', 1.5, 'Color', [0.10 0.10 0.10], ...
    'MarkerFaceColor', [0.25 0.25 0.25]);
grid on;
xlabel('Year');
ylabel('Annual Rain (mm)');

validMaskAnnual = ~isnan(annualTotals);
[pValue, senSlope, trendLabel] = runKtaubSafe(annualYears(validMaskAnnual), annualTotals(validMaskAnnual));

pText = formatMetric(pValue);
senText = formatMetric(senSlope);
if ~isempty(trendLabel)
    title(sprintf('Annual Totals | MK p=%s | Sen=%s mm/year | %s', pText, senText, trendLabel));
else
    title(sprintf('Annual Totals | MK p=%s | Sen=%s mm/year', pText, senText));
end


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
trendLabel = '';

if numel(values) < 3 || numel(years) ~= numel(values)
    return;
end

alpha = 0.05;
datain = [years(:), values(:)];

% ktaub in this repository expects datain as [time, value].
try
    [~,~,h,sig,~,~,~,sen] = ktaub(datain, alpha, 0);
    pValue = sig;
    senSlope = sen;
    trendLabel = mkTrendLabel(h, senSlope);
    return;
catch
end

try
    [~,~,h,sig,~,~,~,sen] = ktaub(datain, alpha);
    pValue = sig;
    senSlope = sen;
    trendLabel = mkTrendLabel(h, senSlope);
catch
    trendLabel = 'ktaub not available or incompatible';
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
