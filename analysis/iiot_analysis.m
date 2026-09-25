%% 
%% IIoT Node - WiFi Performance Analysis
% Reads directly from iiot_data_2026-06-27T16-52-39.csv

clear; clc; close all;

%% ── Load CSV ──────────────────────────────────────

data = readtable('iiot_data_2026-06-27T16-52-39.csv', ...
    'Delimiter', ',', 'ReadVariableNames', true);

data.rssi    = data.rssi_dbm;
data.latency = data.tx_latency_ms;

data.time = datetime(data.timestamp, 'InputFormat', ...
    'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', 'TimeZone', 'UTC');

data.t_sec = seconds(data.time - data.time(1));

fprintf('Loaded %d rows\n', height(data));
fprintf('Session: %s -> %s\n', ...
    string(data.time(1)), string(data.time(end)));

%% ── Segment by distance campaign ─────────────────

seg_bounds = {
    30,   120,  1;
    120,  180,  2;
    180,  240,  3;
    240,  300,  4;
    300,  360,  5;
};

dist_m   = zeros(length(seg_bounds), 1);
rssi_avg = zeros(length(seg_bounds), 1);
rssi_std = zeros(length(seg_bounds), 1);

for i = 1:length(seg_bounds)
    t0 = seg_bounds{i,1};
    t1 = seg_bounds{i,2};
    d  = seg_bounds{i,3};
    mask = data.t_sec >= t0 & data.t_sec < t1;
    seg_rssi = data.rssi(mask);
    dist_m(i)   = d;
    rssi_avg(i) = mean(seg_rssi);
    rssi_std(i) = std(double(seg_rssi));
    fprintf('d=%dm | n=%4d | RSSI=%.1f +/- %.1f dBm\n', ...
        d, sum(mask), rssi_avg(i), rssi_std(i));
end

%% ── ITU-R Indoor Path Loss Model ─────────────────

N       = 28;
d0      = 1.0;
RSSI_d0 = rssi_avg(1);
itu_model = @(d) RSSI_d0 - N .* log10(d ./ d0);

fprintf('\nITU-R Model: N = %d\n', N);
fprintf('RSSI at d0=1m: %.1f dBm\n', RSSI_d0);

seg_colors = [
    0.00 0.45 0.70;
    0.85 0.33 0.10;
    0.47 0.67 0.19;
    0.49 0.18 0.56;
    0.93 0.69 0.13;
];
seg_labels = {'1m','2m','3m','4m','5m'};

%% ── Figure 1: RSSI vs Distance + ITU-R ───────────

figure('Position', [100 100 700 500], 'Color', 'white');

d_smooth = linspace(0.5, 6, 300);
rssi_itu = itu_model(d_smooth);

errorbar(dist_m, rssi_avg, rssi_std, 'o', ...
    'Color',           [0.13 0.59 0.95], ...
    'MarkerFaceColor', [0.13 0.59 0.95], ...
    'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6, ...
    'DisplayName', 'Measured RSSI');
hold on;
plot(d_smooth, rssi_itu, '-', ...
    'Color', [0.96 0.26 0.21], 'LineWidth', 2, ...
    'DisplayName', sprintf('ITU-R Indoor Model (N=%d)', N));

xlabel('Distance (m)',  'FontSize', 13);
ylabel('RSSI (dBm)',    'FontSize', 13);
title({'RSSI vs Distance', 'ITU-R Indoor Path Loss Model'}, ...
    'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'southwest', 'FontSize', 11);
grid on; grid minor;
xlim([0 6]);
set(gca, 'FontSize', 11);

exportgraphics(gcf, 'plot1_rssi_vs_distance.png', 'Resolution', 150);
fprintf('Saved plot1_rssi_vs_distance.png\n');

%% ── Figure 2: RSSI over Time Segmented ───────────

figure('Position', [100 100 900 500], 'Color', 'white');
hold on;

for i = 1:length(seg_bounds)
    t0 = seg_bounds{i,1};
    t1 = seg_bounds{i,2};
    d  = seg_bounds{i,3};
    mask = data.t_sec >= t0 & data.t_sec < t1;
    seg_t = data.t_sec(mask);
    seg_r = double(data.rssi(mask));
    avg_r = mean(seg_r);

    patch([t0 t1 t1 t0], [-100 -100 -38 -38], seg_colors(i,:), ...
        'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    scatter(seg_t, seg_r, 10, seg_colors(i,:), 'filled', ...
        'DisplayName', sprintf('%s: %.0f dBm', seg_labels{i}, avg_r));

    xline(t0, '--', 'Color', seg_colors(i,:), 'LineWidth', 1.2, ...
        'Alpha', 0.7, 'HandleVisibility', 'off');

    text((t0+t1)/2, -40, seg_labels{i}, ...
        'HorizontalAlignment', 'center', 'FontSize', 10, ...
        'FontWeight', 'bold', 'Color', seg_colors(i,:));
    text((t0+t1)/2, -43, sprintf('%.0f dBm', avg_r), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, ...
        'Color', seg_colors(i,:));
end

xlabel('Time (seconds)', 'FontSize', 13);
ylabel('RSSI (dBm)',     'FontSize', 13);
title({'RSSI over Time', 'Segmented by Distance'}, ...
    'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'eastoutside', 'FontSize', 10);
ylim([-100 -37]);
xlim([0 400]);
grid on;
set(gca, 'FontSize', 11);

exportgraphics(gcf, 'plot2_rssi_over_time.png', 'Resolution', 150);
fprintf('Saved plot2_rssi_over_time.png\n');

%% ── Figure 3: TX Latency Distribution ────────────

figure('Position', [100 100 700 500], 'Color', 'white');

lat = double(data.latency);
lat = lat(lat > 0 & lat < 50);
lat_mean = mean(lat);

histogram(lat, 'BinEdges', 0.5:1:(max(lat)+0.5), ...
    'FaceColor', [0.30 0.69 0.31], ...
    'EdgeColor', 'white', 'FaceAlpha', 0.85);
hold on;
xline(lat_mean, '-', sprintf('Mean %.1f ms', lat_mean), ...
    'Color', [1 0.6 0], 'LineWidth', 2, 'FontSize', 10, ...
    'LabelVerticalAlignment', 'bottom');

xlabel('Latency (ms)', 'FontSize', 13);
ylabel('Count',        'FontSize', 13);
title({'TX Latency Distribution', 'ESP32 MQTT Publish Time'}, ...
    'FontSize', 14, 'FontWeight', 'bold');
grid on;
xlim([0 15]);
set(gca, 'FontSize', 11);

fprintf('\nTX Latency Statistics:\n');
fprintf('Mean = %.1f ms\n', lat_mean);
fprintf('Max  = %.1f ms\n', max(lat));
fprintf('%% under 5ms = %.1f%%\n', 100*mean(lat < 5));
fprintf('%% under 10ms = %.1f%%\n', 100*mean(lat < 10));

exportgraphics(gcf, 'plot3_latency.png', 'Resolution', 150);
fprintf('Saved plot3_latency.png\n');