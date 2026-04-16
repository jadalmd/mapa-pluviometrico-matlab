clear; clc; close all;

% Visual Settings (Forces light mode for clean exports)
set(groot, 'defaultFigureColor', 'w', 'defaultAxesColor', 'w', ...
           'defaultAxesXColor', 'k', 'defaultAxesYColor', 'k', 'defaultTextColor', 'k');

%% 1. DATA LOADING & STRICT FILTERING
if ~isfile('dados_hidro_pb.mat')
    error('File dados_hidro_pb.mat not found. Please ensure the workspace file is in the directory.');
end
load('dados_hidro_pb.mat'); 

% STRICT FILTER: Only allow complete hydrological years (1994 to 2025)
valid_idx = dados_completos.Ano >= 1994 & dados_completos.Ano <= 2025;
dados_completos = dados_completos(valid_idx, :);
available_years = sort(unique(dados_completos.Ano));

%% 2. INTRODUCTION & TOOL OVERVIEW
% Fix for the blank space bug: Use a single string with explicit newlines
intro_text = sprintf(['HYDROLOGICAL DATA ANALYSIS TOOL - PARAIBA STATE\n\n', ...
    'Data Source: AESA (Total Annual Precipitation)\n', ...
    'Valid Period: 1994 - 2025 (Partial/Missing years excluded)\n\n', ...
    'Available Modules:\n\n', ...
    '[1] Spatial Distribution Maps:\n', ...
    '    Visualizes the spatial variability of rainfall. Includes a tangible\n', ...
    '    data report showing the rainiest/driest municipalities per year.\n\n', ...
    '[2] Time Series & Statistical Analysis:\n', ...
    '    Evaluates the temporal behavior of rainfall (Statewide or Municipal).\n', ...
    '    Provides exact historical means and identifies extreme years.\n', ...
    '    - Annual Hyetographs & Linear Trends.\n', ...
    '    - Precipitation Anomalies (departures from LTM).\n', ...
    '    - Low-Pass Filter (5-year Moving Average).\n', ...
    '    - Non-parametric Trend Detection (Kendall''s Tau).']);

uiwait(msgbox(intro_text, 'Tool Information & Overview', 'help'));

%% 3. MAIN INTERFACE LOOP
continuar_executando = true;

while continuar_executando
    
    menu_options = {
        '1. Spatial Distribution Maps (Interpolated Grids)', ...
        '2. Time Series & Statistical Analysis (State/Municipalities)'
    };
    
    [idx_analysis, is_confirmed] = listdlg('PromptString', 'Select the desired modules (Use Ctrl for multiple):', ...
                                           'SelectionMode', 'multiple', ...
                                           'ListString', menu_options, ...
                                           'Name', 'Main Menu', 'ListSize', [400, 100]);

    % If user clicks Cancel or closes the window, break the loop
    if ~is_confirmed
        disp('Session terminated by user. Tool closed.');
        continuar_executando = false;
        break;
    end

    %% MODULE 1: SPATIAL DISTRIBUTION MAPS & DATA REPORT
    if ismember(1, idx_analysis)
        str_years = string(available_years);
        [idx_start_map, conf_start_map] = listdlg('PromptString', 'Select the STARTING YEAR for the maps:', ...
                                                  'SelectionMode', 'single', ...
                                                  'ListString', cellstr(str_years), 'Name', 'Temporal Window Setup');
        if conf_start_map
            start_year_map = available_years(idx_start_map);
            max_allowed_year = min(start_year_map + 9, max(available_years));
            
            valid_end_years = available_years(available_years >= start_year_map & available_years <= max_allowed_year);
            [idx_end_map, conf_end_map] = listdlg('PromptString', sprintf('Select the ENDING YEAR (Max: %d):', max_allowed_year), ...
                                                  'SelectionMode', 'single', ...
                                                  'ListString', cellstr(string(valid_end_years)), 'Name', 'Temporal Window Setup');
            
            if conf_end_map
                end_year_map = valid_end_years(idx_end_map);
                map_years = start_year_map:end_year_map;
                
                figure('Name', 'Spatial Distribution Maps', 'Position', [100, 100, 1000, 600]);
                drawnow; % Forces MATLAB to render the figure window immediately
                tiledlayout('flow', 'TileSpacing', 'compact', 'Padding', 'compact');
                
                custom_colors = [0.95 1 1; 0.6 0.9 1; 0.3 0.7 0.9; 0.1 0.4 0.8; 0 0.1 0.5; 0.2 0 0.3];
                smooth_cmap = interp1(linspace(0, 1, 6), custom_colors, linspace(0, 1, 256));
                
                report_text = sprintf('--- ANNUAL PRECIPITATION REPORT ---\n\n');
                
                for i = 1:length(map_years)
                    current_year = map_years(i);
                    field_name = sprintf('ano_%d', current_year);
                    
                    % Extract tangible data for the report
                    year_data = dados_completos(dados_completos.Ano == current_year, :);
                    if ~isempty(year_data)
                        [max_rain, max_idx] = max(year_data.Precipitacao);
                        [min_rain, min_idx] = min(year_data.Precipitacao);
                        mean_rain = mean(year_data.Precipitacao, 'omitnan');
                        
                        report_text = [report_text, sprintf('YEAR %d:\n', current_year)];
                        report_text = [report_text, sprintf('  State Average: %.1f mm\n', mean_rain)];
                        report_text = [report_text, sprintf('  Rainiest: %s (%.1f mm)\n', year_data.Municipio{max_idx}, max_rain)];
                        report_text = [report_text, sprintf('  Driest: %s (%.1f mm)\n\n', year_data.Municipio{min_idx}, min_rain)];
                    end
                    
                    % Plotting the map
                    if isfield(malhas_chuva, field_name)
                        ax_map = nexttile;
                        
                        Z = malhas_chuva.(field_name);
                        if isvector(Z), Z = reshape(Z, size(lon_grid)); end
                        
                        contourf(ax_map, lon_grid, lat_grid, Z, 30, 'LineStyle', 'none'); 
                        hold(ax_map, 'on');
                        plot(ax_map, lon_borda, lat_borda, 'k-', 'LineWidth', 1);
                        
                        colormap(ax_map, smooth_cmap); 
                        title(ax_map, num2str(current_year), 'FontWeight', 'bold'); 
                        
                        axis(ax_map, 'on'); grid(ax_map, 'on');
                        xlabel(ax_map, 'Longitude'); ylabel(ax_map, 'Latitude');
                        daspect(ax_map, [1 1 1]); 
                    end
                end
                cb = colorbar; cb.Layout.Tile = 'east'; cb.Label.String = 'Total Precipitation (mm)';
                
                uiwait(msgbox(report_text, 'Tangible Data: Maps Summary', 'help'));
            end
        end
    end

    %% MODULE 2: TIME SERIES, STATS & DATA REPORT
    if ismember(2, idx_analysis)
        
        % FIRST STEP: Define the spatial scope to determine available years
        scope_choice = questdlg('Analyze the aggregated State signal or specific Municipalities?', ...
                                'Analysis Scope', 'Statewide (Aggregated)', 'Specific Municipalities', 'Statewide (Aggregated)');
        
        if ~isempty(scope_choice)
            is_single_series = false;
            chosen_muns = {};
            
            if strcmp(scope_choice, 'Statewide (Aggregated)')
                valid_years = available_years;
                is_single_series = true;
                base_title = 'Statewide Average - Paraíba';
            else
                mun_list = sort(unique(dados_completos.Municipio));
                [idx_m, conf_m] = listdlg('PromptString', 'Select Municipality(ies):', ...
                                          'SelectionMode', 'multiple', ...
                                          'ListString', mun_list, 'Name', 'Location Selection', 'ListSize', [250, 300]);
                if conf_m
                    chosen_muns = mun_list(idx_m);
                    
                    % Check which years actually have valid data for the selected municipalities
                    valid_idx = ismember(dados_completos.Municipio, chosen_muns) & ~isnan(dados_completos.Precipitacao);
                    valid_years = sort(unique(dados_completos.Ano(valid_idx)));
                    
                    if isempty(valid_years)
                        errordlg('No valid precipitation data found for the selected municipality(ies).', 'Data Error');
                        conf_m = false; % Skip to end of module
                    elseif length(chosen_muns) == 1
                        is_single_series = true;
                        base_title = sprintf('Municipality: %s', chosen_muns{1});
                    end
                end
            end
            
            % SECOND STEP: Ask for time period using List Dialogs based ONLY on valid years
            if (strcmp(scope_choice, 'Statewide (Aggregated)') || conf_m) && ~isempty(valid_years)
                str_valid_years = cellstr(string(valid_years));
                [idx_start, conf_start] = listdlg('PromptString', 'Select START Year:', ...
                                                  'SelectionMode', 'single', ...
                                                  'ListString', str_valid_years, 'Name', 'Start Year');
                if conf_start
                    ts_start = valid_years(idx_start);
                    
                    valid_end_years = valid_years(valid_years >= ts_start);
                    [idx_end, conf_end] = listdlg('PromptString', 'Select END Year:', ...
                                                  'SelectionMode', 'single', ...
                                                  'ListString', cellstr(string(valid_end_years)), 'Name', 'End Year');
                    if conf_end
                        ts_end = valid_end_years(idx_end);
                        
                        % Filter data for the selected period
                        filtered_data = dados_completos(dados_completos.Ano >= ts_start & dados_completos.Ano <= ts_end, :);
                        time_vector = (ts_start:ts_end)';
                        
                        report_text = sprintf('--- TIME SERIES REPORT ---\nPeriod: %d to %d\n\n', ts_start, ts_end);
                        
                        if strcmp(scope_choice, 'Statewide (Aggregated)')
                            grouped_data = groupsummary(filtered_data, 'Ano', 'mean', 'Precipitacao');
                            t = grouped_data.Ano;
                            P = grouped_data.mean_Precipitacao;
                            
                            % Tangible Data (Statewide)
                            long_term_mean = mean(P, 'omitnan');
                            [max_p, max_idx] = max(P);
                            [min_p, min_idx] = min(P);
                            
                            report_text = [report_text, sprintf('SCOPE: Statewide Average\n')];
                            report_text = [report_text, sprintf('Long-Term Mean (LTM): %.1f mm\n', long_term_mean)];
                            report_text = [report_text, sprintf('Wettest Year: %d (%.1f mm)\n', t(max_idx), max_p)];
                            report_text = [report_text, sprintf('Driest Year: %d (%.1f mm)\n', t(min_idx), min_p)];
                            
                        else
                            if length(chosen_muns) == 1
                                % Single municipality: Fix duplicate XData by aggregating stations within the city
                                mun_data = filtered_data(strcmp(filtered_data.Municipio, chosen_muns{1}), :);
                                mun_grouped = groupsummary(mun_data, 'Ano', 'mean', 'Precipitacao');
                                t = mun_grouped.Ano;
                                P = mun_grouped.mean_Precipitacao;
                                
                                % Tangible Data (Single Mun)
                                long_term_mean = mean(P, 'omitnan');
                                [max_p, max_idx] = max(P);
                                [min_p, min_idx] = min(P);
                                
                                report_text = [report_text, sprintf('SCOPE: %s\n', chosen_muns{1})];
                                report_text = [report_text, sprintf('Long-Term Mean (LTM): %.1f mm\n', long_term_mean)];
                                report_text = [report_text, sprintf('Wettest Year: %d (%.1f mm)\n', t(max_idx), max_p)];
                                report_text = [report_text, sprintf('Driest Year: %d (%.1f mm)\n', t(min_idx), min_p)];
                                
                            else
                                % Multiple municipalities: Aggregating to prevent XData duplicates
                                rain_matrix = NaN(length(time_vector), length(chosen_muns));
                                for m = 1:length(chosen_muns)
                                    mun_data = filtered_data(strcmp(filtered_data.Municipio, chosen_muns{m}), :);
                                    mun_grouped = groupsummary(mun_data, 'Ano', 'mean', 'Precipitacao');
                                    
                                    [~, positions] = ismember(mun_grouped.Ano, time_vector);
                                    rain_matrix(positions, m) = mun_grouped.mean_Precipitacao;
                                    
                                    % Tangible Data (Multiple Mun)
                                    ltm_mun = mean(mun_grouped.mean_Precipitacao, 'omitnan');
                                    report_text = [report_text, sprintf('- %s LTM: %.1f mm\n', chosen_muns{m}, ltm_mun)];
                                end
                                
                                figure('Name', 'Inter-municipal Comparison', 'Position', [200, 200, 800, 500]);
                                drawnow;
                                plot(time_vector, rain_matrix, '-o', 'LineWidth', 1.5, 'MarkerSize', 5);
                                title('Annual Precipitation Evolution (Comparison)');
                                xlabel('Year'); ylabel('Total Precipitation (mm)');
                                legend(chosen_muns, 'Location', 'best'); grid on;
                                xlim([min(time_vector)-1, max(time_vector)+1]);
                            end
                        end
                        
                        % SINGLE SERIES DASHBOARD
                        if is_single_series
                            anomalies = P - long_term_mean;
                            moving_avg = movmean(P, 5, 'omitnan'); 
                            
                            try
                                [tau, p_val] = taub(t, P); 
                                report_text = [report_text, sprintf('\nKendall''s Tau: %.3f (p-value: %.3f)\n', tau, p_val)];
                            catch
                                tau = NaN; p_val = NaN;
                            end
                            
                            sig_string = 'Not Significant';
                            if p_val < 0.05, sig_string = 'Significant (p < 0.05)'; end
                            
                            figure('Name', 'Time Series & Trend Analysis', 'Position', [150, 100, 900, 800]);
                            drawnow;
                            tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                            
                            % 1. Hyetograph
                            ax1 = nexttile;
                            bar(ax1, t, P, 'FaceColor', [0.6 0.8 0.9], 'EdgeColor', 'none'); hold on;
                            yline(ax1, long_term_mean, 'k--', 'Long-Term Mean', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
                            
                            % Only fit trend if there are at least 2 points
                            valid_pts = ~isnan(P);
                            if sum(valid_pts) >= 2
                                p_fit = polyfit(t(valid_pts), P(valid_pts), 1);
                                plot(ax1, t, polyval(p_fit, t), 'r-', 'LineWidth', 1.5);
                                legend(ax1, {'Annual Total', 'LTM', 'Linear Trend'}, 'Location', 'best');
                            else
                                legend(ax1, {'Annual Total', 'LTM'}, 'Location', 'best');
                            end
                            
                            title(ax1, {sprintf('Annual Hyetograph - %s', base_title); ...
                                        sprintf('Kendall''s Test: \\tau = %.3f | p-value = %.3f (%s)', tau, p_val, sig_string)});
                            ylabel(ax1, 'Precipitation (mm)'); grid(ax1, 'on'); 
                            
                            % 2. Anomalies
                            ax2 = nexttile;
                            b = bar(ax2, t, anomalies, 'FaceColor', 'flat', 'EdgeColor', 'none');
                            b.CData(anomalies >= 0, :) = repmat([0.2 0.6 0.8], sum(anomalies >= 0), 1); 
                            b.CData(anomalies < 0, :) = repmat([0.8 0.3 0.3], sum(anomalies < 0), 1);   
                            title(ax2, 'Precipitation Anomalies (Departures from LTM)');
                            ylabel(ax2, '\Delta Precipitation (mm)'); grid(ax2, 'on');
                            
                            % 3. Low-Pass Filter
                            ax3 = nexttile;
                            plot(ax3, t, P, 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'LineStyle', '-.'); hold on;
                            plot(ax3, t, moving_avg, 'k-', 'LineWidth', 2);
                            title(ax3, 'Low-Pass Filter (5-Year Moving Average)');
                            xlabel(ax3, 'Year'); ylabel(ax3, 'Precipitation (mm)');
                            legend(ax3, {'Original Signal', 'Filtered Signal'}, 'Location', 'best'); grid(ax3, 'on');
                            
                            linkaxes([ax1, ax2, ax3], 'x');
                            xlim([min(time_vector)-1, max(time_vector)+1]);
                        end
                        
                        uiwait(msgbox(report_text, 'Tangible Data: Time Series Summary', 'help'));
                    end
                end
            end
        end
    end
    
    % Small pause to ensure MATLAB finishes processing UI events before looping
    pause(0.1);

end % End of while loop