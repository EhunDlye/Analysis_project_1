%% 如果您首次运行或想查看相关信息，请移步本文件末尾readme
clear
clc
%%
groupIDordered = {'Before','After'}; % 按自己想要的顺序填入组名。英文单引号引起，英文逗号隔开
close_windows_after_run = {'on'}; % 不想要一个个关掉这十张图？输入'on'在运行完程序后一次性自动关掉它们！
numberdisplay = {'off'}; % 要不要在柱状图的柱子上标注数值？要的话请输入'on'
MAs_threshold_cell = 4;  % 要把microarousal定义为几个格子？
amp = 1; % Amplification，生成图片时整体放大的倍率。适用于组别特别多的情况（大于4时可考虑）
Triangle_Scatter_Group = 2; % 想要第几个（含）group后的散点变成三角形？

%REM_time_range_max = 2; % 图4 Total REM time in 的所有柱状图的纵坐标最大值
%REM_time_range_ticks = 0.5; % 图4 Total REM time in 的所有柱状图的ticks间距
%REM_episode_linechart_range_max = 15; %图5 Episode Number REM 折线图纵坐标最大值
%color_map_main = {};
%color_map_dot = {};
%color_map_error = {};


%% Time 预处理
% 【零、一些参数预设】
if ~exist('color_map_main', 'var')
    num_groups = length(groupIDordered);
    base_color_map_main = {[0.674, 0.788, 0.894], [0.95, 0.50, 0.447], [0.8824, 0.7608, 0.4196], [0.3176, 0.7216, 0.6745]}; % 定义颜色映射
    base_color_map_dot = {[0.294,0.490,0.702],[0.855,0.125,0.09],[0.7216, 0.6314, 0.0000],[0.020, 0.456, 0.687]}; % 定义颜色映射
    base_color_map_error = {[0.196,0.388,0.631],[0.811,0.063,0.039],[0.5922, 0.4510, 0.0000],[0.0196, 0.3294, 0.4706]};% 定义颜色映射
    
    %base_color_map_main = {[0.674, 0.788, 0.894], [0.95, 0.50, 0.447], [0.565, 0.949, 0.447], [0.949, 0.447, 0.851], [0.949, 0.761, 0.447]}; % 定义颜色映射
    %base_color_map_dot = {[0.294,0.490,0.702],[0.855,0.125,0.09],[0.090, 0.855, 0.129],[0.784, 0.090, 0.855],[0.855, 0.557, 0.090]}; % 定义颜色映射
    %base_color_map_error = {[0.196,0.388,0.631],[0.811,0.063,0.039],[0.000,0.753,0.059],[0.686,0.000,0.784],[0.757, 0.455, 0.020]};% 定义颜色映射
    % 根据 groupIDordered 的长度设置 color_map_main
    if num_groups >= 1 && num_groups <= 4
        color_map_main = base_color_map_main(1:num_groups);
        color_map_dot = base_color_map_dot(1:num_groups);
        color_map_error = base_color_map_error(1:num_groups);
    else
        error('你的组别也太多了，请自行设置颜色~');
    end
end
if ~exist("amp")
    amp = 1;
end

% 创建新文件夹
currentTime = datetime('now');
folderName = ['output_', datestr(currentTime, 'yyyymmdd_HHMMSS')];
mkdir(folderName);
% 【一、数据批量导入】

files = dir('*.xlsx');% 获取当前目录下所有非fragment结尾的.xlsx文件
files = files(~contains({files.name}, 'fragment'));
groupID = {};
for i = 1:length(files)
    filename = files(i).name;% 提取文件名
    file_identifier = matlab.lang.makeValidName(filename(1:end-5)); % 去掉文件扩展名，生成一个有效的标识符
    [time_percent_Wake, time_percent_NREM, time_percent_REM, num_mice] = extract_sleep_data(filename); % 调用函数提取数据
    variable_names = strcat("Mouse_", string(1:num_mice)); % 给小鼠编号
    % 检查num_mice是否为整数
    if mod(num_mice, 1) ~= 0
        error( '%s的行数错误~？',files(i).name);
    end
    % 动态生成变量名并添加后缀、保存数据
    eval(['time_percent_Wake_' file_identifier ' = array2table(time_percent_Wake, ''VariableNames'', variable_names);']);
    eval(['time_percent_NREM_' file_identifier ' = array2table(time_percent_NREM, ''VariableNames'', variable_names);']);
    eval(['time_percent_REM_' file_identifier ' = array2table(time_percent_REM, ''VariableNames'', variable_names);']);
    eval(['num_mice_' file_identifier ' = num_mice;']);
    groupID{end+1} = file_identifier;
end
clear time_percent_NREM time_percent_REM time_percent_Wake num_mice;

if ~isequal(sort(groupID), sort(groupIDordered))
    error(sprintf('groupIDordered 与 filename 不一致。可能是排序的时候名字写错了，或者文件名起错了，或者用的不是.xlsx文件~？\n请注意，matlab只接受字母、数字、下划线的组合；并且必须以字母开头。'));
end
% 检测长名字
long_names = cellfun(@(x) length(x) > 16, groupIDordered);
if any(long_names)
    error('检测到长度超过16个字符的group名，请缩短~ 因为excel表格对sheet名的长度有限制Q Q');
end
% 【二、time批量计算:每行的平均值和标准误】
state={'Wake','NREM','REM'}; % 小鼠有三种睡眠-觉醒状态
for i = 1:length(state)
    for j = 1:length(groupID)
        var_name = sprintf('time_percent_%s_%s', state{i}, groupID{j});% 动态生成变量名
        data = eval(var_name); % 使用 eval 获取对应变量的值
        data_array = table2array(data);  % 将 table 转换为数值数组
        avg_value = mean(data_array, 2); % 计算每行的平均值
        sem_value = std(data_array, 0, 2) / sqrt(size(data_array, 2)); % 计算每行的标准误
        avg_var_name = sprintf('time_percent_%s_%s_avg', state{i}, groupID{j}); % 动态生成变量名
        sem_var_name = sprintf('time_percent_%s_%s_sem', state{i}, groupID{j}); % 动态生成变量名
        % 使用 eval 保存计算结果到变量
        eval([avg_var_name ' = avg_value;']);
        eval([sem_var_name ' = sem_value;']);
    end
end

% 【三、time in certain hours 计算】

timerangename = {'1to4h', '1to6h', '1to8h', '1to12h', '13to24h', '1to24h'};  % 时间范围定义
timerange = {1:4, 1:6, 1:8, 1:12, 13:24, 1:24};  % 对应时间段的行范围
% 循环遍历所有状态、组和时间范围
for i = 1:length(state)
    for j = 1:length(groupID)
        for k = 1:length(timerangename)
            var_name = sprintf('time_percent_%s_%s', state{i}, groupID{j}); % 动态生成变量名
            data = table2array(eval(var_name)); % 获取对应变量的值并转换为数组
            data_range = data(timerange{k}, :); % 提取特定时间范围的数据

            avg_value = mean(data_range,1) / 100 * length(timerange{k}); % 计算时间范围内每列的平均值，乘以时间段
            result_var_name = sprintf('time_%s_%s_%s', timerangename{k}, state{i}, groupID{j}); % 动态生成结果变量名

            avgavg_value = mean(avg_value); % 计算时间每列平均值的平均值
            resultavg_var_name = sprintf('time_%s_%s_%s_avg', timerangename{k}, state{i}, groupID{j}); % 生成结果变量名

            avgsem_value = std(avg_value) / sqrt(length(avg_value)); % 计算时间每列平均值的SEM
            resultsem_var_name = sprintf('time_%s_%s_%s_sem', timerangename{k}, state{i}, groupID{j}); % 生成结果变量名

            eval([result_var_name ' = avg_value;']); % 使用 eval 保存每列的平均值
            eval([resultavg_var_name ' = avgavg_value;']); % 使用 eval 保存每列平均值的平均值
            eval([resultsem_var_name ' = avgsem_value;']); % 使用 eval 保存每列平均值的SEM
        end
    end
end

% 画图：Time 图1-4
%% 【图1】
figure;
left = 100;       % 调整图形窗口大小,以像素为单位
bottom = 100;     %
width = 410*amp;      % 宽度
height = 720*amp;     % 高度
set(gcf,'Name', 'Time(%) per hour', 'Position', [left, bottom, width, height]);% 将图形窗口大小设置为指定尺寸
for i = 1:length(state)
    subplot(3, 1, i);
    hold on;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('time_percent_%s_%s_avg', state{i}, groupIDordered{j}));
        sem_data = eval(sprintf('time_percent_%s_%s_sem', state{i}, groupIDordered{j}));
    % 绘制误差条图
        if j <= Triangle_Scatter_Group
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j}, 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        else
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j},'Marker', '^', 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        end
    end

    maxY = -inf;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('time_percent_%s_%s_avg', state{i}, groupIDordered{j}));
        sem_data = eval(sprintf('time_percent_%s_%s_sem', state{i}, groupIDordered{j}));
        max_current = max(avg_data + sem_data);  % 当前 avg_data + sem_data 的最大值
        if max_current > maxY
        maxY = max_current;
        end
    end
        % 改lim和ticks
        xlim([0,25]);
        if i <= 2
            if maxY < 100
            maxY = 100;
            end
        ylim([0,maxY]);
        ax = gca;
        ax.XTick = 0:2:24;
        ax.YTick = 0:25:100;
        else
        maxY = ceil(maxY / 5) * 5;
        ylim([0,maxY*1.2]);
        ax = gca;
        ax.XTick = 0:2:24;
        ax.YTick = 0:5:(maxY*1.2);
        end
    ax.XAxis.TickDirection = 'out';
    ax.XAxis.TickLength = [0.015, 0];
    ax.YAxis.TickDirection = 'out';
    ax.YAxis.TickLength = [0.015, 0];
    set(gca,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    hold off;

    title(sprintf('%s Time Percent in 24 hours', state{i}), 'Color', [0, 0, 0]);
    xlabel('Time (h)', 'Color', [0, 0, 0]);
    ylabel('Percentage (%)', 'Color', [0, 0, 0]);
    lgd = legend(groupIDordered,'Location', 'northeast');
    lgd.Position = [0.86, 1.24-0.3*i, 0.005, 0.005]; % 根据需要调整这些值
    set(lgd, 'Box', 'off');
end
bmpFileName = fullfile(folderName, '01_Time(%)_Per_Hour.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '01_Time(%)_Per_Hour.eps');
print(gcf, epsFileName, '-depsc');

%
%% 【图2-4】
timerangenamewithout4h = {'1to6h', '1to8h', '1to12h', '13to24h', '1to24h'};  % 时间范围定义
timerangeshownamewithout4h = {'1~6h', '1~8h', '1~12h', '13~24h', '1~24h'};  % 时间范围定义
timerangewithout4h = {1:6, 1:8, 1:12, 13:24, 1:24};  % 对应时间段的行范围
for i = 1:length(state)
    figure;
    set(gcf, 'Name', sprintf('Total %s Time in', state{i}));
    for j = 1:length(timerangenamewithout4h)
        subplot(1,5,j)
        hold on;
        for k = 1:length(groupIDordered)
            % 绘制每个柱子
            avg_data = eval(sprintf('time_%s_%s_%s_avg', timerangenamewithout4h{j}, state{i}, groupIDordered{k}));
            data_sem = eval(sprintf('time_%s_%s_%s_sem', timerangenamewithout4h{j}, state{i}, groupIDordered{k}));
            data = eval(sprintf('time_%s_%s_%s', timerangenamewithout4h{j}, state{i}, groupIDordered{k}));
            bar_handle = bar(k, avg_data, 'FaceColor', color_map_main{k}, 'BarWidth', 0.45);
            if exist('numberdisplay')
                if isequal(numberdisplay, {'on'})
                text(k, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
                end
            end
            bar_handle.EdgeColor = 'none';
            if k<=Triangle_Scatter_Group
                scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k});
            else
            scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k},'Marker', '^');
            end
            errorbar(k, [avg_data], zeros(0,2), [data_sem], 'Color',color_map_error{k},'CapSize', 3);
            set(gca,  'FontName', 'Arial', 'XTick', [1:k], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
            if length(groupIDordered) == 2 & k == 1
                data1 = data;
            elseif length(groupIDordered) == 2 & k == 2
                data2 = data;
            end
        end
    ylabel(sprintf('%s Time (h)', state{i}),'Color', [0, 0, 0]);
    title(timerangeshownamewithout4h{j},'Color', [0, 0, 0]);
    if length(groupIDordered) == 2
        % 计算显著性差异
        [h, p] = ttest2(data1, data2);
        if h == 1
            %disp('发现显著性差异');
                %fprintf('p 值为: %.4f\n', p);
        end
        % 在柱状图上添加 p 值
        %自定义p值标注位置%maxY = max([mean_control_1to2h, mean_PSNL_1to2h] + [se_control_1to2h, se_PSNL_1to2h]+ 5); 
        if i == 3 %单独设置一下REM的p位置
            if exist('REM_time_range_max')
                text(1.5,0.95*REM_time_range_max, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
            else
                text(1.5,0.95*ceil(length(timerangewithout4h{j})/6), sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
            end
        else
            text(1.5,0.95*length(timerangewithout4h{j}), sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
        end
    end
    ax = gca;
    if i == 3 %单独设置一下REM的纵坐标
        if exist('REM_time_range_max')
            ylim([0,REM_time_range_max]); 
            ax.YTick = 0:REM_time_range_ticks:REM_time_range_max;
        else
            ylim([0,ceil(length(timerangewithout4h{j})/6)]);
        end
    else
        ylim([0,length(timerangewithout4h{j})]);
        if length(timerangewithout4h{j}) == 24
            ax.YTick = 0:4:24;
        end
    end
    set(gca,'position', [(0.18*j-0.08) 0.20 0.129 0.68]);
    ax.Box = 'off';
    ax.XAxisLocation = 'bottom';
    ax.YAxisLocation = 'left';
    % 移除 x 轴上方的刻度线
    ax.YAxis.TickLength = [0.025, 0];
    ax.XAxis.TickLength = [0, 0];
    ax.YAxis.TickDirection = 'out';
    hold off;
    end
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(544 + 128*length(groupIDordered));      % 宽度
height = 200*amp;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, sprintf('0%d_Total_%s_Time_in.bmp',i+1,state{i}));
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, sprintf('0%d_Total_%s_Time_in.eps',i+1,state{i}));
print(gcf, epsFileName, '-depsc');
end

%% 写入sleep数据到 Excel 文件
% 【数据转换】
filename = 'data.xlsx';
fullFileName = fullfile(folderName, filename);
avg_vars = who('*_avg');
variable_names = {'avg'};
for i = 1:length(avg_vars)
    var_name = avg_vars{i}; 
    data = evalin('base', var_name);
    data_table = array2table(data, 'VariableNames', variable_names);
    assignin('base', var_name, data_table);
end
sem_vars = who('*_sem');
variable_names = {'sem'};
for i = 1:length(sem_vars)
    var_name = sem_vars{i}; 
    data = evalin('base', var_name);
    data_table = array2table(data, 'VariableNames', variable_names);
    assignin('base', var_name, data_table);
end
%
% 【写入数据】
timerangetitle = {'1-4h(hours)','1-6h(hours)','1-8h(hours)','1-12h(hours)','13-24h(hours)'};
for i = 1:length(groupIDordered)
    group_name = groupIDordered{i};
    num_mice = eval(sprintf('num_mice_%s', group_name));
    eval(sprintf('col_%s_avg = getExcelColumn(num_mice + 1);', group_name));
    eval(sprintf('col_%s_sem = getExcelColumn(num_mice + 2);', group_name));
    eval(sprintf('col_%s_sum = getExcelColumn(num_mice + 4);', group_name));
    eval(sprintf('col_%s_sumadd1 = getExcelColumn(num_mice + 5);', group_name));
    eval(sprintf('col_%s_sumtitle = getExcelColumn(num_mice + num_mice + 5);', group_name));
    eval(sprintf('col_%s_sumtitleadd1 = getExcelColumn(num_mice + num_mice + 6);', group_name));
    for j = 1:length(state)
        writecell({sprintf('%s', state{j})}, fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('A%d', 1 + (j-1) * 27));
        for k = 1:length(timerangetitle)
            writecell({'avg'}, fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle',groupIDordered{i})), 2 + 27 * (j-1)));
            writecell({'sem'}, fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1',groupIDordered{i})), 2 + 27 * (j-1)));
            writecell({sprintf('%s', timerangetitle{k})}, fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range',  sprintf('%s%d', eval(sprintf('col_%s_sum',groupIDordered{i})), k + 2 + 27 * (j-1)));
            writetable(eval(sprintf('time_%s_%s_%s_avg',timerangename{k},state{j},groupIDordered{i})) , fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle',groupIDordered{i})), k + 2 + 27 * (j-1)),'WriteVariableNames', false);
            writetable(eval(sprintf('time_%s_%s_%s_sem',timerangename{k},state{j},groupIDordered{i})) , fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1',groupIDordered{i})), k + 2 + 27 * (j-1)),'WriteVariableNames', false); % 啊，历史版本已经不见了，总有一天我要用github进行版本管理……
            writetable(eval(sprintf('time_percent_%s_%s',state{j},groupIDordered{i})), fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('A%d',2 + (j-1) * 27));
            writetable(eval(sprintf('time_percent_%s_%s_avg',state{j},groupIDordered{i})), fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_avg',groupIDordered{i})), 2 + 27 * (j-1)));
            writetable(eval(sprintf('time_percent_%s_%s_sem',state{j},groupIDordered{i})), fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sem',groupIDordered{i})), 2 + 27 * (j-1)));
            writematrix(eval(sprintf('time_%s_%s_%s',timerangename{k},state{j},groupIDordered{i})) , fullFileName, 'Sheet', sprintf('%s_time', groupIDordered{i}), 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumadd1',groupIDordered{i})), k + 2 + 27 * (j-1)));
        end
    end
end

%% duration等 预处理
% 【一、提取文件名和sheet名】
filesf = dir('*fragment.xlsx'); % 读取所有末尾是 fragment 的 .xlsx 文件
filenamef = cellfun(@(x) extractBefore(x, 'fragment.xlsx'), {filesf.name}, 'UniformOutput', false); % 去掉文件名中的 "fragment.xlsx" 部分
if ~isequal(sort(filenamef), sort(groupIDordered))
    error(sprintf('groupIDordered 与 fragmentfilename 不一致。可能是排序的时候名字写错了，或者文件名起错了，或者用的不是*fragment.xlsx文件~？\n请注意，matlab只接受字母、数字、下划线的组合；并且必须以字母开头。'));
end
for i = 1:length(groupIDordered);
    current_file = groupIDordered{i}; % 获取当前文件名
    sheet_names = sheetnames(sprintf('%sfragment.xlsx',current_file)); % 获取当前文件sheet名
    variable_name = sprintf('%sfragmentsheetNames', current_file); % 构建变量名，去掉 "fragment.xlsx" 扩展名
    assignin('base', variable_name, sheet_names); % 把变量写入变量名
    num_mice_fragment = numel(sheet_names); % 计算工作表数量
    assignin('base', sprintf('num_mice_%sfragment', current_file), num_mice_fragment); % 储存变量
end

% 【二、 预处理文件】
for i = 1:length(groupIDordered)
    num_mice_fragment = eval(sprintf('num_mice_%sfragment', groupIDordered{i}));
    for n = 1:num_mice_fragment
        data_n = xlsread(sprintf('%sfragment.xlsx',groupIDordered{i}), n, 'D:F');  % 读取第 n 个 sheet 的第 4、5、6 列数据
        if ~isequal(size(data_n), [17280, 3])
            error('%sfragment.xlsx 的第 %d 个 sheet 行数不对~？', groupIDordered{i}, n); % 检查有无错误
        end
        var_name = sprintf('transition_5s_%s_%d',groupIDordered{i},n);% 创建变量名
        assignin('base', var_name, data_n);% 将数据存储为 double 类型的变量

    end
end

% 【三、 count_mice_Yu_groupIDordered_24h】
% 遍历每个 groupIDordered 的组
for k = 1:length(groupIDordered)
    current_group = groupIDordered{k}; % 当前组名
    
    % 初始化 Index_i 和 Index_j
    eval(sprintf('Index_i = size(transition_5s_%s_1, 1) / 720;', current_group));
    eval(sprintf('Index_j = size(transition_5s_%s_1, 2);', current_group));
    
    % 初始化 COUNT 变量
    eval(sprintf('num_mice_fragment = num_mice_%sfragment;', current_group));
    eval(sprintf('episode_number_%s = zeros(Index_i, Index_j, num_mice_fragment);', current_group));
    
    % 遍历每只鼠
    for n = 1:num_mice_fragment
        % 动态构造变量名
        var_name = sprintf('transition_5s_%s_%d', current_group, n);
        data_n = eval(var_name);

        % 对数据进行处理
        for index_i = 1:Index_i
            for index_j = 1:Index_j
                data_group = data_n((1 + 720 * (index_i - 1)):(720 + 720 * (index_i - 1)), index_j)';
                n_a = size(data_group, 2);

                % 处理 [0 1 0] 和 [1 0 1]
                for x = 3:n_a
                    b(x, :) = [data_group(x - 2), data_group(x - 1), data_group(x)];
                    if isequal(b(x, :), [0 1 0])
                        b(x, :) = [0 0 0];
                        data_group(x - 1) = 0;
                    end
                end

                for x = 3:n_a
                    c(x, :) = [data_group(x - 2), data_group(x - 1), data_group(x)];
                    if isequal(c(x, :), [1 0 1])
                        c(x, :) = [1 1 1];
                        data_group(x - 1) = 1;
                    end
                end

                % 计算 COUNT
                episode_number_ = 0;
                array = find(data_group);
                n_array = length(array);
                array(n_array + 1) = 1e10; % 防止越界
                for x = 2:n_array
                    if array(x) - array(x + 1) < -1 && array(x) - array(x - 1) == 1
                        episode_number_ = episode_number_ + 1;
                    end
                end

                % 存储结果到 COUNT
                eval(sprintf('episode_number_%s(index_i, index_j, n) = episode_number_;', current_group));
            end
        end
    end

    % 动态处理 transition 数据
    for n = 1:num_mice_fragment
        var_name = sprintf('transition_5s_%s_%d', current_group, n);
        data = eval(var_name);
    Index_i1 = size(data, 1);
    data(Index_i1 + 1, :) = zeros(1, size(data, 2));
    data_temp = data;
    transition = zeros(3, 3, size(data, 2) / 3);
    Index_i = size(data, 1);
    Index_j = size(data, 2);

    for j = 1:size(data, 2) / 3
        data = data_temp(:, (1 + 3 * (j - 1)) : 3 * j);
        for i = 4:Index_i
            for index_j = 1:Index_j
                d(i, :) = [data(i - 3, index_j) data(i - 2, index_j) data(i - 1, index_j) data(i, index_j)];
                if isequal(d(i, :), [0 0 1 0])
                    d(i, :) = [0 0 0 0];
                    data(i - 1, index_j) = 0;
                elseif isequal(d(i, :), [0 1 0 0])
                    d(i, :) = [0 0 0 0];
                    data(i - 2, index_j) = 0;
                elseif isequal(d(i, :), [0 1 0 1])
                    d(i, :) = [0 0 0 1];
                    data(i - 2, index_j) = 0;
                end
            end
        end

        for i = 2:Index_i
            if isequal(data(i, :), [0 0 0])
                data(i, :) = data(i - 1, :);
            end
        end

        for i = 4:Index_i
            for index_j = 1:Index_j
                e(i, :) = [data(i - 3, index_j) data(i - 2, index_j) data(i - 1, index_j) data(i, index_j)];
                if isequal(e(i, :), [1 0 1 0])
                    e(i, :) = [1 1 1 0];
                    data(i - 2, index_j) = 1;
                elseif isequal(e(i, :), [1 0 1 1])
                    e(i, :) = [1 1 1 1];
                    data(i - 2, index_j) = 1;
                elseif isequal(e(i, :), [1 1 0 1])
                    e(i, :) = [1 1 1 1];
                    data(i - 1, index_j) = 1;
                end
            end
        end

        for i = 2:Index_i
            diff_data = data(i, :) - data(i - 1, :);
            if isequal(diff_data, [-1 1 0])
                transition(1, 2, j) = transition(1, 2, j) + 1;
            elseif isequal(diff_data, [-1 0 1])
                transition(1, 3, j) = transition(1, 3, j) + 1;
            elseif isequal(diff_data, [1 -1 0])
                transition(2, 1, j) = transition(2, 1, j) + 1;
            elseif isequal(diff_data, [0 -1 1])
                transition(2, 3, j) = transition(2, 3, j) + 1;
            elseif isequal(diff_data, [1 0 -1])
                transition(3, 1, j) = transition(3, 1, j) + 1;
            elseif isequal(diff_data, [0 1 -1])
                transition(3, 2, j) = transition(3, 2, j) + 1;
            end
        end
    end

        % 存储 transition 数据
        transition_var = sprintf('transition_%s_%d', current_group, n);
        assignin('base', transition_var, transition);
    end

    % 计算平均值
    eval(sprintf('transition_avg_%s = zeros(3, 3, size(transition_%s_1, 3));', current_group, current_group));
    for n = 1:num_mice_fragment
        transition_var = sprintf('transition_%s_%d', current_group, n);
        transition_data = eval(transition_var);
        eval(sprintf('transition_avg_%s = transition_avg_%s + transition_data;', current_group, current_group));
    end
    eval(sprintf('transition_avg_%s = transition_avg_%s / num_mice_fragment;', current_group, current_group));
end

% 【四、 count_mice_Yu_groupIDordered_1-12h】
% 遍历每个组
for k = 1:length(groupIDordered)
    current_group = groupIDordered{k}; % 当前组名
    
    % 循环遍历每只老鼠
    eval(sprintf('num_mice_fragment = num_mice_%sfragment;', current_group));
    for n = 1:num_mice_fragment
        % 动态获取变量名
        data_var = sprintf('transition_5s_%s_%d', current_group, n);
        data = eval(data_var);

        % 初始化变量
        Index_i1 = floor(size(data, 1) / 2);
        data(Index_i1 + 1, :) = zeros(1, size(data, 2));
        data_temp = data;
        transition = zeros(3, 3, size(data, 2) / 3);
        Index_i = floor(size(data, 1) / 2);
        Index_j = size(data, 2);

        for j = 1:size(data, 2) / 3
            data = data_temp(:, (1 + 3 * (j - 1)) : 3 * j);
            for i = 4:Index_i
                for index_j = 1:Index_j
                    d(i, :) = [data(i - 3, index_j), data(i - 2, index_j), data(i - 1, index_j), data(i, index_j)];
                    if isequal(d(i, :), [0 0 1 0])
                        d(i, :) = [0 0 0 0];
                        data(i - 1, index_j) = 0;
                    elseif isequal(d(i, :), [0 1 0 0])
                        d(i, :) = [0 0 0 0];
                        data(i - 2, index_j) = 0;
                    elseif isequal(d(i, :), [0 1 0 1])
                        d(i, :) = [0 0 0 1];
                        data(i - 2, index_j) = 0;
                    end
                end
            end

            for i = 2:Index_i
                if isequal(data(i, :), [0 0 0])
                    data(i, :) = data(i - 1, :);
                end
            end

            for i = 4:Index_i
                for index_j = 1:Index_j
                    e(i, :) = [data(i - 3, index_j), data(i - 2, index_j), data(i - 1, index_j), data(i, index_j)];
                    if isequal(e(i, :), [1 0 1 0])
                        e(i, :) = [1 1 1 0];
                        data(i - 2, index_j) = 1;
                    elseif isequal(e(i, :), [1 0 1 1])
                        e(i, :) = [1 1 1 1];
                        data(i - 2, index_j) = 1;
                    elseif isequal(e(i, :), [1 1 0 1])
                        e(i, :) = [1 1 1 1];
                        data(i - 1, index_j) = 1;
                    end
                end
            end

            for i = 2:Index_i
                diff_data = data(i, :) - data(i - 1, :);
                if isequal(diff_data, [-1 1 0])
                    transition(1, 2, j) = transition(1, 2, j) + 1;
                elseif isequal(diff_data, [-1 0 1])
                    transition(1, 3, j) = transition(1, 3, j) + 1;
                elseif isequal(diff_data, [1 -1 0])
                    transition(2, 1, j) = transition(2, 1, j) + 1;
                elseif isequal(diff_data, [0 -1 1])
                    transition(2, 3, j) = transition(2, 3, j) + 1;
                elseif isequal(diff_data, [1 0 -1])
                    transition(3, 1, j) = transition(3, 1, j) + 1;
                elseif isequal(diff_data, [0 1 -1])
                    transition(3, 2, j) = transition(3, 2, j) + 1;
                end
            end
        end

        % 动态生成变量名并保存 transition
        transition_var = sprintf('transition_1to12h_%s_%d', current_group, n);
        assignin('base', transition_var, transition);
    end

    % 初始化并计算平均值
    transition_avg_var = sprintf('transition_1to12h_avg_%s', current_group);
    eval(sprintf('%s = zeros(3, 3, size(transition_1to12h_%s_1, 3));', transition_avg_var, current_group));

    for n = 1:num_mice_fragment
        transition_var = sprintf('transition_1to12h_%s_%d', current_group, n);
        transition_data = eval(transition_var);
        eval(sprintf('%s = %s + transition_data;', transition_avg_var, transition_avg_var));
    end

    % 求平均
    eval(sprintf('%s = %s / num_mice_fragment;', transition_avg_var, transition_avg_var));
end

% 【五、 count_mice_Yu_groupIDordered_13-24h】
% 遍历每个组
for k = 1:length(groupIDordered)
    current_group = groupIDordered{k}; % 当前组名
    
    % 获取当前组的老鼠数量
    eval(sprintf('num_mice_fragment = num_mice_%sfragment;', current_group));
    
    % 循环处理每只老鼠的数据
    for n = 1:num_mice_fragment
        % 动态获取变量名
        data_var = sprintf('transition_5s_%s_%d', current_group, n);
        data = eval(data_var);

        % 获取数据行数的一半，向上取整，作为后半部分的开始索引
        Index_i1 = floor(size(data, 1) / 2) + 1;

        % 只保留数据的后半部分
        data = data(Index_i1:end, :);

        % 更新数据的大小
        data_temp = data;
        transition = zeros(3, 3, size(data, 2) / 3);
        Index_i = size(data, 1); % 后半部分的行数
        Index_j = size(data, 2); % 列数

        for j = 1:size(data, 2) / 3
            data = data_temp(:, (1 + 3 * (j - 1)) : 3 * j);
            for i = 4:Index_i
                for index_j = 1:Index_j
                    d(i, :) = [data(i - 3, index_j), data(i - 2, index_j), data(i - 1, index_j), data(i, index_j)];
                    if isequal(d(i, :), [0 0 1 0])
                        d(i, :) = [0 0 0 0];
                        data(i - 1, index_j) = 0;
                    elseif isequal(d(i, :), [0 1 0 0])
                        d(i, :) = [0 0 0 0];
                        data(i - 2, index_j) = 0;
                    elseif isequal(d(i, :), [0 1 0 1])
                        d(i, :) = [0 0 0 1];
                        data(i - 2, index_j) = 0;
                    end
                end
            end

            for i = 2:Index_i
                if isequal(data(i, :), [0 0 0])
                    data(i, :) = data(i - 1, :);
                end
            end

            for i = 4:Index_i
                for index_j = 1:Index_j
                    e(i, :) = [data(i - 3, index_j), data(i - 2, index_j), data(i - 1, index_j), data(i, index_j)];
                    if isequal(e(i, :), [1 0 1 0])
                        e(i, :) = [1 1 1 0];
                        data(i - 2, index_j) = 1;
                    elseif isequal(e(i, :), [1 0 1 1])
                        e(i, :) = [1 1 1 1];
                        data(i - 2, index_j) = 1;
                    elseif isequal(e(i, :), [1 1 0 1])
                        e(i, :) = [1 1 1 1];
                        data(i - 1, index_j) = 1;
                    end
                end
            end

            for i = 2:Index_i
                diff_data = data(i, :) - data(i - 1, :);
                if isequal(diff_data, [-1 1 0])
                    transition(1, 2, j) = transition(1, 2, j) + 1;
                elseif isequal(diff_data, [-1 0 1])
                    transition(1, 3, j) = transition(1, 3, j) + 1;
                elseif isequal(diff_data, [1 -1 0])
                    transition(2, 1, j) = transition(2, 1, j) + 1;
                elseif isequal(diff_data, [0 -1 1])
                    transition(2, 3, j) = transition(2, 3, j) + 1;
                elseif isequal(diff_data, [1 0 -1])
                    transition(3, 1, j) = transition(3, 1, j) + 1;
                elseif isequal(diff_data, [0 1 -1])
                    transition(3, 2, j) = transition(3, 2, j) + 1;
                end
            end
        end

        % 动态生成变量名并保存 transition
        transition_var = sprintf('transition_13to24h_%s_%d', current_group, n);
        assignin('base', transition_var, transition);
    end

    % 初始化并计算平均值
    transition_avg_var = sprintf('transition_13to24h_avg_%s', current_group);
    eval(sprintf('%s = zeros(3, 3, size(transition_13to24h_%s_1, 3));', transition_avg_var, current_group));

    for n = 1:num_mice_fragment
        transition_var = sprintf('transition_13to24h_%s_%d', current_group, n);
        transition_data = eval(transition_var);
        eval(sprintf('%s = %s + transition_data;', transition_avg_var, transition_avg_var));
    end

    % 求平均
    eval(sprintf('%s = %s / num_mice_fragment;', transition_avg_var, transition_avg_var));
end

% 【六、计算duration（min)】
for i = 1:length(groupIDordered)
    current_group = groupIDordered{i}; % 当前组名
    for j = 1:length(state)
        current_state = state{j}; % 当前状态名

        % 转换表格为数组
        time_percent_double_var = sprintf('time_percent_%s_%s_double', current_state, current_group);
        eval(sprintf('%s = table2array(time_percent_%s_%s);', time_percent_double_var, current_state, current_group));
        % 计算 duration_no
        duration_no_var = sprintf('duration_%s_%s_no', current_group, current_state);
        episode_number_var = sprintf('episode_number_%s', current_group);
        eval(sprintf('%s = %s ./ %s(:, j, :);', duration_no_var, time_percent_double_var, episode_number_var));
        eval(sprintf('%s = %s / 100 * 60;', duration_no_var, duration_no_var));
        % 初始化 duration 矩阵
        duration_var = sprintf('duration_%s_%s', current_group, current_state);
        num_mice_fragment_var = sprintf('num_mice_%sfragment', current_group);
        eval(sprintf('%s = zeros(24, %s);', duration_var, num_mice_fragment_var));
        for n = 1:eval(num_mice_fragment_var)
            eval(sprintf('%s(:, n) = %s(:, n, n);', duration_var, duration_no_var));% 提取第n个维度3的第n列
        end
        eval(sprintf('nan_idx = isnan(%s);', duration_var));% 处理 NaN 和 Inf
        eval(sprintf('inf_idx = isinf(%s);', duration_var));
        eval(sprintf('%s(nan_idx | inf_idx) = 0;', duration_var));
    end
end

% 【七、算所有episode & duration平均值】
for i = 1:length(groupIDordered)
    current_group = groupIDordered{i}; % 当前组名
    % 计算 episode_number 的平均值和标准误
    episode_number_avg_var = sprintf('episode_number_%s_avg', current_group);
    episode_number_var = sprintf('episode_number_%s', current_group);
    episode_number_sem_var = sprintf('episode_number_%s_sem', current_group);
    num_mice_fragment_var = sprintf('num_mice_%sfragment', current_group);
    % 计算平均值
    eval(sprintf('%s = mean(%s, 3);', episode_number_avg_var, episode_number_var));
    % 计算标准误
    eval(sprintf('%s = std(%s, 0, 3) / sqrt(%s);', episode_number_sem_var, episode_number_var, num_mice_fragment_var));

    % 遍历每个状态
    for j = 1:length(state)
        current_state = state{j}; % 当前状态名
        % 动态生成变量名
        duration_var = sprintf('duration_%s_%s', current_group, current_state);
        duration_filtered_var = sprintf('duration_%s_%s_filtered', current_group, current_state);
        duration_avg_var = sprintf('duration_%s_%s_avg', current_group, current_state);
        duration_sem_var = sprintf('duration_%s_%s_sem', current_group, current_state);
        % 创建掩码
        eval(sprintf('non_zero_mask = %s ~= 0;', duration_var));
        % 初始化 filtered duration
        eval(sprintf('%s = %s;', duration_filtered_var, duration_var));
        % 将零值替换为 NaN
        eval(sprintf('%s(~non_zero_mask) = NaN;', duration_filtered_var));
        % 计算平均值
        eval(sprintf('%s = nanmean(%s, 2);', duration_avg_var, duration_filtered_var));
        % 计算标准误
        eval(sprintf('%s = nanstd(%s, 0, 2) ./ sqrt(sum(~isnan(%s), 2));',duration_sem_var, duration_filtered_var, duration_filtered_var));
    end
end

% 【八、计算sleep lantency】
for i = 1:length(groupIDordered)
    current_group = groupIDordered{i}; % 当前组名
    for j = 2:length(state)
        current_state = state{j}; % 当前状态名
        % 初始化 sleeplatency 矩阵
        sleeplatency_var = sprintf('sleeplatency_%s_%s', current_state, current_group);
        num_mice_fragment_var = sprintf('num_mice_%sfragment', current_group);
        eval(sprintf('%s = zeros(%s, 1);', sleeplatency_var, num_mice_fragment_var));
        % 循环处理每个数据集
        for n = 1:eval(num_mice_fragment_var)
            % 动态生成变量名
            data_var = sprintf('transition_5s_%s_%d', current_group, n);
            data = eval(data_var);
            if j == 2
                indices = find(all(data == [0 1 0], 2), 1, 'first');% 找到每列第一个出现 [0 1 0] 的位置，就是NREM
            else
                indices = find(all(data == [0 0 1], 2), 1, 'first');
            end
            % 如果找到符合条件的行
            if ~isempty(indices)
                % 计算需要的数值
                eval(sprintf('%s(%d) = (indices - 1) * 5 / 60;', sleeplatency_var, n));
            else
                % 如果未找到，设置为 NaN
                eval(sprintf('%s(%d) = NaN;', sleeplatency_var, n));
            end
        end
    end
end
% 画图：Episode/duration 图5-10
%% 【图5 Number of episodes】
figure;
left = 100;       % 调整图形窗口大小,以像素为单位
bottom = 100;     %
width = 410*amp;      % 宽度
height = 720*amp;     % 高度
set(gcf,'Name', 'Episode Number', 'Position', [left, bottom, width, height]);% 将图形窗口大小设置为指定尺寸
for i = 1:length(state)
    subplot(3, 1, i);
    hold on;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('episode_number_%s_avg(:, i)', groupIDordered{j}));
        sem_data = eval(sprintf('episode_number_%s_sem(:, i)', groupIDordered{j}));
    % 绘制误差条图
        if j <= Triangle_Scatter_Group
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j}, 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        else
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j},'Marker', '^', 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        end
    end

    maxY = -inf;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('episode_number_%s_avg(:, i)', groupIDordered{j}));
        sem_data = eval(sprintf('episode_number_%s_sem(:, i)', groupIDordered{j}));
        max_current = max(avg_data + sem_data);  % 当前 avg_data + sem_data 的最大值
        if max_current > maxY
        maxY = max_current;
        end
    end
        % 改lim和ticks
        xlim([0,25]);
        if i <= 2
        maxY = ceil(maxY / 5) * 5;
        ylim([0,maxY]);
        ax = gca;
        ax.XTick = 0:2:24;
        ax.YTick = 0:10:maxY;
        else
        maxY = ceil(maxY / 5) * 5;
        ax = gca;
        ax.XTick = 0:2:24;
            if exist("REM_episode_linechart_range_max")
                ax.YTick = 0:5:(REM_episode_linechart_range_max);
                ylim([0,REM_episode_linechart_range_max]);
            else
                ax.YTick = 0:5:(maxY*1.1);
                ylim([0,maxY*1.1]);
            end
        end
    ax.XAxis.TickDirection = 'out';
    ax.XAxis.TickLength = [0.015, 0];
    ax.YAxis.TickDirection = 'out';
    ax.YAxis.TickLength = [0.015, 0];
    set(gca,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    hold off;

    title(sprintf('%s', state{i}), 'Color', [0, 0, 0]);
    xlabel('Time (h)', 'Color', [0, 0, 0]);
    ylabel('Episode Number', 'Color', [0, 0, 0]);
    lgd = legend(groupIDordered,'Location', 'northeast');
    lgd.Position = [0.86, 1.24-0.3*i, 0.005, 0.005]; % 根据需要调整这些值
    set(lgd, 'Box', 'off');
end
% 存图片
bmpFileName = fullfile(folderName, '05_Number_of_episodes.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '05_Number_of_episodes.eps');
print(gcf, epsFileName, '-depsc');;

%% 【图6 Episode duration】
figure;
left = 100;       % 调整图形窗口大小,以像素为单位
bottom = 100;     %
width = 410*amp;      % 宽度
height = 720*amp;     % 高度
set(gcf, 'Name', 'Episode Duration', 'Position', [left, bottom, width, height]);% 将图形窗口大小设置为指定尺寸
for i = 1:length(state)
    subplot(3, 1, i);
    hold on;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('duration_%s_%s_avg', groupIDordered{j}, state{i}));
        sem_data = eval(sprintf('duration_%s_%s_sem', groupIDordered{j}, state{i}));
    % 绘制误差条图
        if j <= Triangle_Scatter_Group
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j}, 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        else
        errorbar(1:24, avg_data, sem_data, '-o', 'Color', color_map_main{j},'Marker', '^', 'MarkerFaceColor', color_map_main{j}, 'LineWidth', 1, 'MarkerSize', 4, 'CapSize', 4);
        end
    end

    maxY = -inf;
    for j = 1:length(groupIDordered)
    % 使用 eval 获取 avg 和 sem 数据
        avg_data = eval(sprintf('duration_%s_%s_avg', groupIDordered{j}, state{i}));
        sem_data = eval(sprintf('duration_%s_%s_sem', groupIDordered{j}, state{i}));
        max_current = max(avg_data + sem_data);  % 当前 avg_data + sem_data 的最大值
        if max_current > maxY
        maxY = max_current;
        end
    end
        % 改lim和ticks
        xlim([0,25]);
        if i <= 1
        maxY = ceil(maxY / 5) * 5;
        ylim([0,maxY]);
        ax = gca;
        ax.XTick = 0:2:24;
            if maxY >= 20
            ax.YTick = 0:10:maxY;
            end
        elseif i <= 2
            maxY = ceil(maxY / 2) * 2;
            ylim([0,maxY]);
            ax = gca;
            ax.XTick = 0:2:24;
            %ax.YTick = 0:1:5;
        else
        maxY = ceil(maxY / 1) * 1;
        ylim([0,maxY]);
        ax = gca;
        ax.XTick = 0:2:24;
        ax.YTick = 0:1:maxY;
        end
    ax.XAxis.TickDirection = 'out';
    ax.XAxis.TickLength = [0.015, 0];
    ax.YAxis.TickDirection = 'out';
    ax.YAxis.TickLength = [0.015, 0];
    set(gca,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    hold off;

    title(sprintf('%s', state{i}), 'Color', [0, 0, 0]);
    xlabel('Time (h)', 'Color', [0, 0, 0]);
    ylabel('Duration (min)', 'Color', [0, 0, 0]);
    lgd = legend(groupIDordered,'Location', 'northeast');
    lgd.Position = [0.86, 1.24-0.3*i, 0.005, 0.005]; % 根据需要调整这些值
    set(lgd, 'Box', 'off');
end
% 存图片
bmpFileName = fullfile(folderName, '06_Episode_duration.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '06_Episode_duration.eps');
print(gcf, epsFileName, '-depsc');

%% 【图7 Total Number of transitions in】
% 前置运算
 % 生成空矩阵
transitionname = {'waketonrem', 'nremtowake', 'nremtorem', 'remtowake'};
transitionnametitle = {'Wake-NREM', 'NREM-Wake', 'NREM-REM', 'REM-Wake'};
transitionnameset = {'transition_data(1, 2)','transition_data(2,1)','transition_data(2, 3)','transition_data(3, 1)'};
statetime = {'1to12h', '13to24h'};
statetimename = {'1-12h','13-24h'};
for i = 1:length(groupIDordered)
    for j = 1:length(statetime)
        for k = 1:length(transitionname)
            transition_var = sprintf('transition_%s_%s_%s', statetime{j}, transitionname{k}, groupIDordered{i});% 动态生成变量名
            num_mice_fragment_var = sprintf('num_mice_%sfragment', groupIDordered{i}); % 获取当前组的数量
            num_mice_fragment = eval(num_mice_fragment_var); % 动态获取数量
            eval(sprintf('%s = zeros(%d, 1);', transition_var, num_mice_fragment));% 创建变量并初始化
        end
    end
end
 % 提取数据
for i = 1:length(groupIDordered)
    for j = 1:length(statetime)
        for k = 1:length(transitionname)
            num_mice_fragment_var = sprintf('num_mice_%sfragment', groupIDordered{i});% 获取当前组的鼠数量
            var_name = eval(num_mice_fragment_var); % 动态获取变量数量
            result_var_name = sprintf('transition_%s_%s_%s', statetime{j}, transitionname{k}, groupIDordered{i});% 初始化存储数据的数组
            eval(sprintf('%s = zeros(var_name, 1);', result_var_name));
            for n = 1:var_name
                % 动态生成变量名
                transition_var = sprintf('transition_%s_%s_%d', statetime{j}, groupIDordered{i}, n);
                    % 动态获取变量数据
                    transition_data = eval(transition_var);
                    % 提取第一行第二列数据并存储
                    extracted_value = eval(transitionnameset{k}); 
                    eval(sprintf('%s(%d) = extracted_value;', result_var_name, n));
            end
        end
    end
end
%
 % 计算平均值
for i = 1:length(groupIDordered)
    for k = 1:length(statetime)
        for j = 1:length(transitionname)
            % 动态生成变量名
            avg_var = sprintf('transition_%s_%s_%s_avg', statetime{k}, transitionname{j}, groupIDordered{i});
            sem_var = sprintf('transition_%s_%s_%s_sem', statetime{k}, transitionname{j}, groupIDordered{i});
            data_var = sprintf('transition_%s_%s_%s', statetime{k}, transitionname{j}, groupIDordered{i});
            num_mice_fragment_var = sprintf('num_mice_%sfragment', groupIDordered{i});
            eval(sprintf('%s = mean(%s, 1);', avg_var, data_var));% 计算均值
            eval(sprintf('%s = std(%s, 0, 1) / sqrt(%s);', sem_var, data_var, num_mice_fragment_var));% 计算标准误
        end
    end
end
%
% 画图
figure;
set(gcf, 'Name', 'Total Number of transitions in');
for i = 1:length(transitionname)
    all_values = [];
    for j = 1:length(statetime)
        for k = 1:length(groupIDordered)
            var_name = sprintf('transition_%s_%s_%s', statetime{j}, transitionname{i}, groupIDordered{k});
            var_data = eval(var_name);% 动态获取变量值
            all_values = [all_values; var_data(:)]; % 将数据添加到数组中
        end
    end
    maxY1 = max(all_values);% 找到最大值
    for j = 1:length(statetime)
        subplot(2, 4, (i + (j - 1) * 4));
        hold on;
        data_group = cell(1, length(groupIDordered));
        for k = 1:length(groupIDordered)
            % 动态生成变量名并获取数据
            avg_var_name = sprintf('transition_%s_%s_%s_avg', statetime{j}, transitionname{i}, groupIDordered{k});
            avg_var = sprintf('transition_%s_%s_%s', statetime{j}, transitionname{i}, groupIDordered{k});
            sem_var_name = sprintf('transition_%s_%s_%s_sem', statetime{j}, transitionname{i}, groupIDordered{k});
            avg_data = eval(avg_var_name); 
            data = eval(avg_var);
            sem_data = eval(sem_var_name); 
            bar_handle = bar(k, avg_data, 'FaceColor', color_map_main{k}, 'BarWidth', 0.45); % 画柱子
            if exist('numberdisplay')
                if isequal(numberdisplay, {'on'})
                text(k, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
                end
            end
            bar_handle.EdgeColor = 'none';
            if k<=Triangle_Scatter_Group
                scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k});
            else
            scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k},'Marker', '^');
            end
            errorbar(k, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{k}, 'CapSize', 3);
            if length(groupIDordered) == 2 & k == 1
                    data1 = data;
            elseif length(groupIDordered) == 2 & k == 2
                    data2 = data;
            end
        end
        
        ylabel('Number of transitions','Color', [0, 0, 0]);
        title_string = sprintf('%s %s', transitionnametitle{i}, statetimename{j});
        title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
        maxY1 = ceil(maxY1 / 50) * 50;
        ylim([0,maxY1+50]);
        if maxY1+50 >= 200
            ax = gca;
            ax.YTick = 0:100:(maxY1+50);
        end
        if length(groupIDordered) == 2
            [h, p] = ttest2(data1, data2);% 计算显著性差异
            if h == 1
                %disp('发现显著性差异');
                    %fprintf('p 值为: %.4f\n', p);
            end
            text(1.5,(maxY1+50)*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
        end
        set(gca,  'FontName', 'Arial', 'XTick', [1:k], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
        % 移除上方和右方的轴线
        set(gca,'position', [(0.07+(i-1)*0.242) (0.58-(j-1)*0.48) 0.1718 0.34]);
        ax = gca;
        ax.Box = 'off';
        ax.XAxisLocation = 'bottom';
        ax.YAxisLocation = 'left';
        ax.YAxis.TickLength = [0.025, 0];
        ax.XAxis.TickLength = [0, 0];
        ax.YAxis.TickDirection = 'out';
        hold off;
    end
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(406 + 97*length(groupIDordered));      % 宽度
height = amp*400;     % 高度

% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '07_Total_Number_of_transitions_in_.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '07_Total_Number_of_transitions_in_.eps');
print(gcf, epsFileName, '-depsc');

%% 【图8 Episode Number in】
% 前置计算
for i = 1:length(groupIDordered)
    var_1to12h = sprintf('episode_number_%s_1to12h', groupIDordered{i});
    eval(sprintf('%s = sum(episode_number_%s(1:12, :, :), 1);', var_1to12h, groupIDordered{i})); % 1-12
    var_13to24h = sprintf('episode_number_%s_13to24h', groupIDordered{i});
    eval(sprintf('%s = sum(episode_number_%s(13:24, :, :), 1);', var_13to24h, groupIDordered{i})); % 13-24
end
for i = 1:length(statetime)
     for j = 1:length(groupIDordered)
        for k = 1:length(state)
            eval_name_withoutstate = sprintf('episode_number_%s_%s', groupIDordered{j},statetime{i});
            eval_name = sprintf('episode_number_%s_%s_%s', groupIDordered{j},statetime{i},state{k});
            eval_name_avg = sprintf('episode_number_%s_%s_%s_avg', groupIDordered{j},statetime{i},state{k});
            eval_name_sem = sprintf('episode_number_%s_%s_%s_sem', groupIDordered{j},statetime{i},state{k});
            % 提取无状态数据并赋值到动态变量中
            eval(sprintf('%s = squeeze(%s(:, %d, :));', eval_name, eval_name_withoutstate, k));
            eval(sprintf('%s = mean(%s, 1);', eval_name_avg, eval_name)); % 计算均值
            eval(sprintf('%s = std(%s, 0, 1) / sqrt(size(%s, 1));', eval_name_sem, eval_name, eval_name)); % 计算标准误

        end
     end
end
%
% 画图
figure;
set(gcf, 'Name', 'Episode Number in');
for i = 1:length(state)
    all_values = [];
    for j = 1:length(statetime)
        for k = 1:length(groupIDordered)
            var_name = sprintf('episode_number_%s_%s_%s', groupIDordered{k}, statetime{j}, state{i});
            var_data = eval(var_name);% 动态获取变量值
            all_values = [all_values; var_data(:)]; % 将数据添加到数组中
        end
    end
    max_var_name = sprintf('max%s',state{i});
    eval(sprintf('%s = max(all_values);', max_var_name));
end
for i = 1:length(statetime)
    for j = 1:length(state)
        subplot(2, 3, ((i-1)*3 + j));
        hold on;
        for k = 1:length(groupIDordered)
            % 动态生成变量名并获取数据
            data = sprintf('episode_number_%s_%s_%s', groupIDordered{k}, statetime{i}, state{j});
            avg_var_name = sprintf('episode_number_%s_%s_%s_avg', groupIDordered{k}, statetime{i}, state{j});
            sem_var_name = sprintf('episode_number_%s_%s_%s_sem', groupIDordered{k}, statetime{i}, state{j});
            avg_data = eval(avg_var_name); 
            sem_data = eval(sem_var_name); 
            data = eval(data);
            bar_handle = bar(k, avg_data, 'FaceColor', color_map_main{k}, 'BarWidth', 0.45); % 画柱子
            if exist('numberdisplay')
                if isequal(numberdisplay, {'on'})
                text(k, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
                end
            end
            bar_handle.EdgeColor = 'none';
            if k<=Triangle_Scatter_Group
                scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k});
            else
            scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k},'Marker', '^');
            end
            errorbar(k, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{k}, 'CapSize', 3);
            if length(groupIDordered) == 2 & k == 1
                    data1 = data;
            elseif length(groupIDordered) == 2 & k == 2
                    data2 = data;
            end
        end
        ylabel('Episode Number','Color', [0, 0, 0]);
        title_string = sprintf('%s %s', statetimename{i}, state{j});
        title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
        max_var_name = eval(sprintf('max%s',state{j}));
        max_var_name = ceil(max_var_name / 25) * 25;
        ylim([0,max_var_name+25]);
        if max_var_name+25 >= 200
            ax = gca;
            ax.YTick = 0:100:(max_var_name+25);
        end
        if length(groupIDordered) == 2
            [h, p] = ttest2(data1, data2);% 计算显著性差异
            if h == 1
                %disp('发现显著性差异');
                    %fprintf('p 值为: %.4f\n', p);
            end
            text(1.5,(max_var_name+25)*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
        end
        set(gca,  'FontName', 'Arial', 'XTick', [1:k], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
        % 移除上方和右方的轴线
        set(gca,'position', [(0.15+(j-1)*0.27) (0.58-(i-1)*0.48) 0.1718 0.34]);
        ax = gca;
        ax.Box = 'off';
        ax.XAxisLocation = 'bottom';
        ax.YAxisLocation = 'left';
        ax.YAxis.TickLength = [0.025, 0];
        ax.XAxis.TickLength = [0, 0];
        ax.YAxis.TickDirection = 'out';
        hold off;
    end
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(409+95.5*length(groupIDordered));      % 宽度
height = amp*400;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '08_Episode_Number_in.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '08_Episode_Number_in.eps');
print(gcf, epsFileName, '-depsc');

%% 【图9 Episode Duration in】
% 前置运算
for i = 1:length(statetime)
    for j = 1:length(state)
        for k = 1:length(groupIDordered)
            var_name = sprintf('time_%s_%s_%s', statetime{i}, state{j}, groupIDordered{k});
            var_name_no = sprintf('time_%s_%s_%s_no', statetime{i}, state{j}, groupIDordered{k});
            eval(sprintf('%s = %s'';', var_name_no,var_name));
            ver_name_duration = sprintf('duration_%s_%s_%s',groupIDordered{k},state{j},statetime{i});
            ver_name_duration_avg = sprintf('duration_%s_%s_%s_avg',groupIDordered{k},state{j},statetime{i});
            ver_name_duration_sem = sprintf('duration_%s_%s_%s_sem',groupIDordered{k},state{j},statetime{i});
            ver_name_episode = sprintf('episode_number_%s_%s_%s',groupIDordered{k},statetime{i},state{j});
            eval(sprintf('%s = %s ./ %s *60;',ver_name_duration,var_name_no,ver_name_episode));
            eval(sprintf('%s = mean(%s);',ver_name_duration_avg,ver_name_duration));
            ver_name_num = sprintf('num_mice_%sfragment',groupIDordered{k});
            eval(sprintf('%s = std(%s) / sqrt(%s);',ver_name_duration_sem,ver_name_duration,ver_name_num))
        end
    end
end
% 画图
figure;
set(gcf, 'Name', 'Average Duration in');
for i = 1:length(state)
    all_values = [];
    for j = 1:length(statetime)
        for k = 1:length(groupIDordered)
            var_name = sprintf('duration_%s_%s_%s', groupIDordered{k}, state{i},statetime{j});
            var_data = eval(var_name);% 动态获取变量值
            all_values = [all_values; var_data(:)]; % 将数据添加到数组中
        end
    end
    max_var_name = sprintf('max%s',state{i});
    eval(sprintf('%s = max(all_values);', max_var_name));
end
for i = 1:length(statetime)
    for j = 1:length(state)
        subplot(2, 3, ((i-1)*3 + j));
        hold on;
        for k = 1:length(groupIDordered)
            % 动态生成变量名并获取数据
            data = sprintf('duration_%s_%s_%s', groupIDordered{k}, state{j},statetime{i});
            avg_var_name = sprintf('duration_%s_%s_%s_avg', groupIDordered{k}, state{j},statetime{i});
            sem_var_name = sprintf('duration_%s_%s_%s_sem', groupIDordered{k}, state{j},statetime{i});
            avg_data = eval(avg_var_name); 
            sem_data = eval(sem_var_name); 
            data = eval(data);
            bar_handle = bar(k, avg_data, 'FaceColor', color_map_main{k}, 'BarWidth', 0.45); % 画柱子
            if exist('numberdisplay')
                if isequal(numberdisplay, {'on'})
                text(k, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
                end
            end
            bar_handle.EdgeColor = 'none';
            if k<=Triangle_Scatter_Group
                scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k});
            else
            scatter(k, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{k},'Marker', '^');
            end
            errorbar(k, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{k}, 'CapSize', 3);
            if length(groupIDordered) == 2 & k == 1
                    data1 = data;
            elseif length(groupIDordered) == 2 & k == 2
                    data2 = data;
            end
        end
        ylabel('Episode Duration (min)','Color', [0, 0, 0]);
        title_string = sprintf('%s %s', statetimename{i}, state{j});
        title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
        max_var_name = eval(sprintf('max%s',state{j}));
        max_var_name = ceil(max_var_name) ;
        ylim([0,max_var_name]);
        %{
        if maxY1+50 >= 200
            ax = gca;
            ax.YTick = 0:100:(maxY1+50);
        end
        %}
        if length(groupIDordered) == 2
            [h, p] = ttest2(data1, data2);% 计算显著性差异
            if h == 1
                %disp('发现显著性差异');
                    %fprintf('p 值为: %.4f\n', p);
            end
            text(1.5,(max_var_name)*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
        end
        set(gca,  'FontName', 'Arial', 'XTick', [1:k], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
        % 移除上方和右方的轴线
        set(gca,'position', [(0.15+(j-1)*0.27) (0.58-(i-1)*0.48) 0.1718 0.34]);
        ax = gca;
        ax.Box = 'off';
        ax.XAxisLocation = 'bottom';
        ax.YAxisLocation = 'left';
        ax.YAxis.TickLength = [0.025, 0];
        ax.XAxis.TickLength = [0, 0];
        ax.YAxis.TickDirection = 'out';
        hold off;
    end
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(409+95.5*length(groupIDordered));      % 宽度
height = amp*400;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '09_Episode_duration_in.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '09_Episode_duration_in.eps');
print(gcf, epsFileName, '-depsc');
%
%% 【图10 Sleep Lantency】
% 前置运算
for i = 2:length(state)
    for j = 1:length(groupIDordered)
        var_name = sprintf('sleeplatency_%s_%s',state{i},groupIDordered{j});
        var_name_avg = sprintf('sleeplatency_%s_%s_avg',state{i},groupIDordered{j});
        var_name_sem = sprintf('sleeplatency_%s_%s_sem',state{i},groupIDordered{j});
        var_name_num = sprintf('num_mice_%sfragment',groupIDordered{j});
        eval(sprintf('%s = mean(%s);', var_name_avg, var_name));
        eval(sprintf('%s = std(%s) / sqrt(%s);', var_name_sem, var_name, var_name_num));
    end
end

% 画图
figure;
set(gcf, 'Name', 'Sleep lantency');
for i = 2:length(state)
    all_values = [];
    subplot(1, 2, (i-1));
    hold on;
    for j = 1:length(groupIDordered)
        % 动态生成变量名并获取数据
        var_name = sprintf('sleeplatency_%s_%s', state{i},groupIDordered{j});
        avg_var_name = sprintf('sleeplatency_%s_%s_avg', state{i},groupIDordered{j});
        sem_var_name = sprintf('sleeplatency_%s_%s_sem', state{i},groupIDordered{j});
        avg_data = eval(avg_var_name); 
        sem_data = eval(sem_var_name); 
        data = eval(var_name);
        bar_handle = bar(j, avg_data, 'FaceColor', color_map_main{j}, 'BarWidth', 0.45); % 画柱子
        if exist('numberdisplay')
            if isequal(numberdisplay, {'on'})
            text(j, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
            end
        end
        bar_handle.EdgeColor = 'none';
        if j<=Triangle_Scatter_Group
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j});
        else
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j},'Marker', '^');
        end
        errorbar(j, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{j}, 'CapSize', 3);
        if length(groupIDordered) == 2 & j == 1
                data1 = data;
        elseif length(groupIDordered) == 2 & j == 2
                data2 = data;
        end
        var_name = sprintf('sleeplatency_%s_%s', state{i},groupIDordered{j});
        var_data = eval(var_name);% 动态获取变量值
        all_values = [all_values; var_data(:)]; % 将数据添加到数组中
    end
    ylabel('Time (min)','Color', [0, 0, 0]);
    title_string = sprintf('%s Sleep Latency', state{i});
    title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
    maxY1 = max(all_values);
    maxY1 = ceil(maxY1 / 25) * 25;
    ylim([0,maxY1]);
    if maxY1+50 >= 200
        ax = gca;
        ax.YTick = 0:100:(maxY1+50);
    end
    if length(groupIDordered) == 2
        [h, p] = ttest2(data1, data2);% 计算显著性差异
        if h == 1
            %disp('发现显著性差异');
                %fprintf('p 值为: %.4f\n', p);
        end
        text(1.5,maxY1*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
    end
    
    set(gca,  'FontName', 'Arial', 'XTick', [1:j], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    % 移除上方和右方的轴线
    set(gca,'position', [(0.15+(i-2)*0.31) 0.10 0.21505 0.68]);
    ax = gca;
    ax.Box = 'off';
    ax.XAxisLocation = 'bottom';
    ax.YAxisLocation = 'left';
    ax.YAxis.TickLength = [0.025, 0];
    ax.XAxis.TickLength = [0, 0];
    ax.YAxis.TickDirection = 'out';
    hold off;
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(324.8 + 77.6*length(groupIDordered));      % 宽度
height = amp*200;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '10_Sleep_latency.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '10_Sleep_latency.eps');
print(gcf, epsFileName, '-depsc');

%% 【图11】MAs
% 前置运算
% 遍历每个组
for k = 1:length(groupIDordered)
    current_group = groupIDordered{k}; % 当前组名
    % 动态构造变量名，获取每组的num_mice_fragment
    num_mice_fragment = eval(sprintf('num_mice_%sfragment', current_group));
    % 遍历每只鼠
    for n = 1:num_mice_fragment
        MAs_row = [];            % 用于记录符合条件的行数
        % 动态构造每只鼠的变量名
        var_name = sprintf('transition_5s_%s_%d', current_group, n);
        % 使用 eval 函数获取变量的值
        data_n = eval(var_name);
        % 初始化状态和计数器
        state = false;  % 初始状态为false
        count = 0;      % 计数器初始化
        % 遍历每一行数据
        for i = 1:length(data_n)
            current_row = data_n(i, :);  % 当前行数据
            if ~state  % 如果状态是false
                if isequal(current_row, [1, 0, 0])  % 检测到[1, 0, 0]
                    state = true;  % 状态变为true
                    count = 1;     % 计数器从1开始
                end
            else  % 如果状态是true
                if isequal(current_row, [1, 0, 0])|| isequal(current_row, [0, 0, 0]) % 检测到[1, 0, 0]或者[0, 0, 0]
                    count = count + 1;  % 计数器增加
                else  % 如果变为其他
                    if count <= MAs_threshold_cell
                        MAs_row = [MAs_row; i];  % 记录当前行
                    end
                    state = false;  % 状态恢复为false
                    count = 0;      % 计数器重置
                end
            end
        end
        result = (MAs_row - MAs_threshold_cell) * 5;  % 向量化操作，直接计算

        % 将结果赋值给动态生成的变量名
        var_name = sprintf('MAs_%s_%d', current_group, n);  % 动态生成变量名
        eval([var_name ' = result;']);  % 使用eval将结果赋给生成的变量名
        
        % 将小于等于43200的部分存到 'MAs_1to12h_*_*' 变量中
        result_1to12h = result(result <= 43200);  % 获取小于等于43200的部分
        var_name_1to12h = sprintf('MAs_1to12h_%s_%d', current_group, n);
        eval([var_name_1to12h ' = result_1to12h;']);  % 将结果赋给 'MAs_1to12h_*_*'
        % 将结果的长度追加到目标变量而非覆盖写入
        var_name_1to12h_length = sprintf('MAs_1to12h_%s', current_group);
        length_value = length(result_1to12h); % 提取数据长度
        if ~exist(var_name_1to12h_length, 'var')% 如果目标变量不存在，则初始化为空数组
            assignin('base', var_name_1to12h_length, []); % 初始化为空数组
        end
        current_length_values = eval(var_name_1to12h_length);% 从工作区获取当前已有的长度值数组
        updated_length_values = [current_length_values, length_value];% 将当前长度值追加到数组中
        assignin('base', var_name_1to12h_length, updated_length_values);% 将更新后的数组存回目标变量

        % 将大于43200的部分存到 'MAs_13to24h_*_*' 变量中
        result_13to24h = result(result > 43200);  % 获取大于43200的部分
        var_name_13to24h = sprintf('MAs_13to24h_%s_%d', current_group, n);
        eval([var_name_13to24h ' = result_13to24h;']);  % 将结果赋给 'MAs_13to24h_*_*'
        % 将结果的长度追加到目标变量而非覆盖写入
        var_name_13to24h_length = sprintf('MAs_13to24h_%s', current_group);
        length_value = length(result_13to24h); % 提取数据长度
        if ~exist(var_name_13to24h_length, 'var')% 如果目标变量不存在，则初始化为空数组
            assignin('base', var_name_13to24h_length, []); % 初始化为空数组
        end
        current_length_values = eval(var_name_13to24h_length);% 从工作区获取当前已有的长度值数组
        updated_length_values = [current_length_values, length_value];% 将当前长度值追加到数组中
        assignin('base', var_name_13to24h_length, updated_length_values);% 将更新后的数组存回目标变量
    end
end
state={'Wake','NREM','REM'}; % 不小心把state这个变量名给用了，用完改写回来。
% 画图前前置运算
for i = 1:length(statetime)
    for j = 1:length(groupIDordered)
        var_name = sprintf('MAs_%s_%s', statetime{i},groupIDordered{j});
        var_name_avg = sprintf('MAs_%s_%s_avg',statetime{i},groupIDordered{j});
        var_name_sem = sprintf('MAs_%s_%s_sem',statetime{i},groupIDordered{j});
        var_name_num = sprintf('num_mice_%sfragment',groupIDordered{j});
        eval(sprintf('%s = mean(%s);', var_name_avg, var_name));
        eval(sprintf('%s = std(%s) / sqrt(%s);', var_name_sem, var_name, var_name_num));
    end
end

% 画图
figure;
set(gcf, 'Name', 'Micro arousals');
all_values = [];
for i = 1:length(statetime)
    subplot(1,2,i);
    hold on;
    for j = 1:length(groupIDordered)
        % 动态生成变量名并获取数据
        var_name = sprintf('MAs_%s_%s', statetime{i},groupIDordered{j});
        avg_var_name = sprintf('MAs_%s_%s_avg', statetime{i},groupIDordered{j});
        sem_var_name = sprintf('MAs_%s_%s_sem', statetime{i},groupIDordered{j});
        avg_data = eval(avg_var_name); 
        sem_data = eval(sem_var_name); 
        data = eval(var_name);
        bar_handle = bar(j, avg_data, 'FaceColor', color_map_main{j}, 'BarWidth', 0.45); % 画柱子
        if exist('numberdisplay')
            if isequal(numberdisplay, {'on'})
            text(j, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
            end
        end
        bar_handle.EdgeColor = 'none';
        if j<=Triangle_Scatter_Group
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j});
        else
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j},'Marker', '^');
        end
        errorbar(j, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{j}, 'CapSize', 3);
        if length(groupIDordered) == 2 & j == 1
                data1 = data;
        elseif length(groupIDordered) == 2 & j == 2
                data2 = data;
        end
        var_name = sprintf('MAs_%s_%s', statetime{i},groupIDordered{j});
        var_data = eval(var_name);% 动态获取变量值
        all_values = [all_values; var_data(:)]; % 将数据添加到数组中
    end
    ylabel('MAs','Color', [0, 0, 0]);
    title_string = sprintf('%s', statetime{i});
    title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
    maxY1 = max(all_values);
    maxY1 = ceil(maxY1 / 25) * 25 / 0.97;
    ylim([0,maxY1]);
    if length(groupIDordered) == 2
        [h, p] = ttest2(data1, data2);% 计算显著性差异
        if h == 1
            %disp('发现显著性差异');
                %fprintf('p 值为: %.4f\n', p);
        end
        text(1.5,maxY1*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
    end
    set(gca,  'FontName', 'Arial', 'XTick', [1:j], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    % 移除上方和右方的轴线
    set(gca,'position', [(0.15+(i-1)*0.31) 0.10 0.21505 0.68]);
    ax = gca;
    ax.Box = 'off';
    ax.XAxisLocation = 'bottom';
    ax.YAxisLocation = 'left';
    ax.YAxis.TickLength = [0.025, 0];
    ax.XAxis.TickLength = [0, 0];
    ax.YAxis.TickDirection = 'out';
    hold off;
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(324.8 + 77.6*length(groupIDordered));      % 宽度
height = amp*200;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '11_MAs.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '11_MAs.eps');
print(gcf, epsFileName, '-depsc');

%% 【图12】MAs/NREM
% 前置运算
for i = 1:length(statetime)
    for j = 1:length(groupIDordered)
        % 动态生成目标变量名
        var_name = sprintf('MAs_div_NREM_%s_%s', statetime{i}, groupIDordered{j});
        var_name_MAs = sprintf('MAs_%s_%s', statetime{i}, groupIDordered{j});
        var_name_NREM = sprintf('time_%s_NREM_%s', statetime{i}, groupIDordered{j});
        % 获取已有变量的值
        MAs_value = eval(var_name_MAs);     % MAs 对应的值
        NREM_value = eval(var_name_NREM);  % NREM 对应的值
        % 计算并将值赋给新生成的变量名
        if NREM_value ~= 0  % 避免除以零的情况
            new_value = MAs_value ./ NREM_value;
        else
            new_value = NaN;  % 如果 NREM 为 0，则赋值为 NaN
        end
        % 将结果赋值到新生成的变量名
        assignin('base', var_name, new_value); % 动态在工作区中创建变量
    end
end

% 画图前前置运算
for i = 1:length(statetime)
    for j = 1:length(groupIDordered)
        var_name = sprintf('MAs_div_NREM_%s_%s', statetime{i},groupIDordered{j});
        var_name_avg = sprintf('MAs_div_NREM_%s_%s_avg',statetime{i},groupIDordered{j});
        var_name_sem = sprintf('MAs_div_NREM_%s_%s_sem',statetime{i},groupIDordered{j});
        var_name_num = sprintf('num_mice_%sfragment',groupIDordered{j});
        eval(sprintf('%s = mean(%s);', var_name_avg, var_name));
        eval(sprintf('%s = std(%s) / sqrt(%s);', var_name_sem, var_name, var_name_num));
    end
end

% 画图
figure;
set(gcf, 'Name', 'Microarousals/NREM (h)');
all_values = [];
for i = 1:length(statetime)
    subplot(1,2,i);
    hold on;
    for j = 1:length(groupIDordered)
        % 动态生成变量名并获取数据
        var_name = sprintf('MAs_div_NREM_%s_%s', statetime{i},groupIDordered{j});
        avg_var_name = sprintf('MAs_div_NREM_%s_%s_avg', statetime{i},groupIDordered{j});
        sem_var_name = sprintf('MAs_div_NREM_%s_%s_sem', statetime{i},groupIDordered{j});
        avg_data = eval(avg_var_name); 
        sem_data = eval(sem_var_name); 
        data = eval(var_name);
        bar_handle = bar(j, avg_data, 'FaceColor', color_map_main{j}, 'BarWidth', 0.45); % 画柱子
        if exist('numberdisplay')
            if isequal(numberdisplay, {'on'})
            text(j, 0, sprintf('%.2f', avg_data), 'FontSize', 8, 'HorizontalAlignment', 'center');
            end
        end
        bar_handle.EdgeColor = 'none';
        if j<=Triangle_Scatter_Group
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j});
        else
            scatter(j, data, 13,'filled', 'jitter', 'on', 'jitterAmount', 0.15,'MarkerEdgeColor','none','MarkerFaceColor',color_map_dot{j},'Marker', '^');
        end
        errorbar(j, avg_data, zeros(0,2),sem_data, 'Color', color_map_error{j}, 'CapSize', 3);
        if length(groupIDordered) == 2 & j == 1
                data1 = data;
        elseif length(groupIDordered) == 2 & j == 2
                data2 = data;
        end
        var_name = sprintf('MAs_div_NREM_%s_%s', statetime{i},groupIDordered{j});
        var_data = eval(var_name);% 动态获取变量值
        all_values = [all_values; var_data(:)]; % 将数据添加到数组中
    end
    ylabel('MAs/NREM (h)','Color', [0, 0, 0]);
    title_string = sprintf('%s', statetime{i});
    title(title_string, 'FontSize', 7.8,'Color', [0, 0, 0]);
    maxY1 = max(all_values);
    maxY1 = ceil(maxY1 / 5) * 5 *1.05;
    ylim([0,maxY1]);
    if length(groupIDordered) == 2
        [h, p] = ttest2(data1, data2);% 计算显著性差异
        if h == 1
            %disp('发现显著性差异');
                %fprintf('p 值为: %.4f\n', p);
        end
        text(1.5,maxY1*0.97, sprintf('p = %.4f', p), 'FontSize', 8, 'HorizontalAlignment', 'center');
    end
    set(gca,  'FontName', 'Arial', 'XTick', [1:j], 'XTickLabel',groupIDordered,'XColor', [0, 0, 0], 'YColor', [0, 0, 0]);
    % 移除上方和右方的轴线
    set(gca,'position', [(0.15+(i-1)*0.31) 0.10 0.21505 0.68]);
    ax = gca;
    ax.Box = 'off';
    ax.XAxisLocation = 'bottom';
    ax.YAxisLocation = 'left';
    ax.YAxis.TickLength = [0.025, 0];
    ax.XAxis.TickLength = [0, 0];
    ax.YAxis.TickDirection = 'out';
    hold off;
end
% 设置左下角位置 (left, bottom)，宽度和高度
left = 100;       % 以像素为单位
bottom = 100;     % 以像素为单位
width = amp*(324.8 + 77.6*length(groupIDordered));      % 宽度
height = amp*200;     % 高度
% 将图形窗口大小设置为指定尺寸
set(gcf, 'Position', [left, bottom, width, height]);
bmpFileName = fullfile(folderName, '12_MAs_div_NREM.bmp');
saveas(gcf, bmpFileName, 'bmp');
epsFileName = fullfile(folderName, '12_MAs_div_NREM.eps');
print(gcf, epsFileName, '-depsc');

%% 写入episode~数据到 Excel 文件
% 【fragment episode number数据】
% 数据转换
for i = 1:length(groupIDordered)
    for j = 1:length(state)
        ver_name = sprintf('episode_number_%s_%s',groupIDordered{i},state{j});
        ver_name_avg = sprintf('episode_number_%s_%s_avg',groupIDordered{i},state{j});
        ver_name_sem = sprintf('episode_number_%s_%s_sem',groupIDordered{i},state{j});
        eval(sprintf('%s = squeeze(episode_number_%s(:, %d, :));', ver_name, groupIDordered{i},j))
        eval(sprintf('%s = (episode_number_%s_avg(:, %d));',ver_name_avg, groupIDordered{i},j))
        eval(sprintf('%s = (episode_number_%s_sem(:, %d));',ver_name_sem, groupIDordered{i},j))
        variable_names = {'avg'};
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name_avg,ver_name_avg))
        variable_names = {'sem'};
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name_sem,ver_name_sem))
        eval(sprintf('variable_names = strcat("Mouse_", string(1:num_mice_%sfragment));',groupIDordered{i}))
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name,ver_name))
    end
    eval(sprintf('col_%s_avg = getExcelColumn(num_mice_%s + 1); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sem = getExcelColumn(num_mice_%s + 2); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sum = getExcelColumn(num_mice_%s + 4); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumadd1 = getExcelColumn(num_mice_%s + 5); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumtitle = getExcelColumn(num_mice_%s + num_mice_%s + 5); ',groupIDordered{i},groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumtitleadd1 = getExcelColumn(num_mice_%s + num_mice_%s + 6); ',groupIDordered{i},groupIDordered{i},groupIDordered{i}))
end

% 写入数据
for i = 1:length(groupIDordered)
    sheetname = sprintf('%s_episode_number',groupIDordered{i});
    for j = 1:length(state)
        writecell({state{j}}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('A%d',1 + (j-1) * 27));
        writetable(eval(sprintf('episode_number_%s_%s',groupIDordered{i},state{j})), fullFileName,'Sheet',sheetname,'Range',sprintf('A%d',2 + (j-1) * 27));
        writetable(eval(sprintf('episode_number_%s_%s_avg',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_avg', groupIDordered{i})), 2 + (j-1) * 27));
        writetable(eval(sprintf('episode_number_%s_%s_sem',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sem', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'avg'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'sem'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'1-12h'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum', groupIDordered{i})), 3 + (j-1) * 27));
        writecell({'13-24h'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_1to12h_%s''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumadd1', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_13to24h_%s''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumadd1', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_1to12h_%s_avg''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_13to24h_%s_avg''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_1to12h_%s_sem''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('episode_number_%s_13to24h_%s_sem''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 4 + (j-1) * 27));
    end
end

% 【fragment episode number数据】
% 数据转换
for i = 1:length(groupIDordered)
    for j = 1:length(state)
        ver_name = sprintf('duration_%s_%s',groupIDordered{i},state{j});
        ver_name_avg = sprintf('duration_%s_%s_avg',groupIDordered{i},state{j});
        ver_name_sem = sprintf('duration_%s_%s_sem',groupIDordered{i},state{j});
        variable_names = {'avg'};
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name_avg,ver_name_avg))
        variable_names = {'sem'};
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name_sem,ver_name_sem))
        eval(sprintf('variable_names = strcat("Mouse_", string(1:num_mice_%sfragment));',groupIDordered{i}))
        eval(sprintf('%s = array2table(%s, ''VariableNames'', variable_names'');',ver_name,ver_name))
    end
    eval(sprintf('col_%s_avg = getExcelColumn(num_mice_%s + 1); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sem = getExcelColumn(num_mice_%s + 2); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sum = getExcelColumn(num_mice_%s + 4); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumadd1 = getExcelColumn(num_mice_%s + 5); ',groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumtitle = getExcelColumn(num_mice_%s + num_mice_%s + 5); ',groupIDordered{i},groupIDordered{i},groupIDordered{i}))
    eval(sprintf('col_%s_sumtitleadd1 = getExcelColumn(num_mice_%s + num_mice_%s + 6); ',groupIDordered{i},groupIDordered{i},groupIDordered{i}))
end
%
% 写入数据
for i = 1:length(groupIDordered)
    sheetname = sprintf('%s_duration',groupIDordered{i});
    for j = 1:length(state)
        writecell({state{j}}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('A%d',1 + (j-1) * 27));
        writetable(eval(sprintf('duration_%s_%s',groupIDordered{i},state{j})), fullFileName,'Sheet',sheetname,'Range',sprintf('A%d',2 + (j-1) * 27));
        writetable(eval(sprintf('duration_%s_%s_avg',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_avg', groupIDordered{i})), 2 + (j-1) * 27));
        writetable(eval(sprintf('duration_%s_%s_sem',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sem', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'avg'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'sem'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 2 + (j-1) * 27));
        writecell({'1-12h (min)'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum', groupIDordered{i})), 3 + (j-1) * 27));
        writecell({'13-24h (min)'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_1to12h''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumadd1', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_13to24h''',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumadd1', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_1to12h_avg',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_13to24h_avg',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitle', groupIDordered{i})), 4 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_1to12h_sem',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 3 + (j-1) * 27));
        writematrix(eval(sprintf('duration_%s_%s_13to24h_sem',groupIDordered{i},state{j})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d', eval(sprintf('col_%s_sumtitleadd1', groupIDordered{i})), 4 + (j-1) * 27));
    end
end

% 【episode transition数据】
% 写入数据
for i = 1:length(groupIDordered)
    eval(sprintf('col_%s_sum = char(''A'');',groupIDordered{i}));
    eval(sprintf('col_%s_avg = getExcelColumn(num_mice_%s + 1);',groupIDordered{i} ,groupIDordered{i}))
    eval(sprintf('col_%s_sem = getExcelColumn(num_mice_%s + 2);',groupIDordered{i} ,groupIDordered{i}))
    eval(sprintf('variable_names = strcat("Mouse_", string(1:num_mice_%sfragment));',groupIDordered{i}))
    sheetname = sprintf('%s_transtion',groupIDordered{i});
    for j = 1:length(transitionname)
        writecell({variable_names}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('B%d',1+(j-1)*5));
        writematrix(sprintf('%s',transitionnametitle{j}), fullFileName, 'Sheet', sheetname, 'Range', sprintf('A%d',1+(j-1)*5));
        writecell({'1-12h'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum',groupIDordered{i})),2+(j-1)*5));
        writecell({'13-24h'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sum',groupIDordered{i})),3+(j-1)*5));
        writecell({'avg'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_avg',groupIDordered{i})),1+(j-1)*5));
        writecell({'sem'}, fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sem',groupIDordered{i})),1+(j-1)*5));
        writematrix(eval(sprintf('transition_1to12h_%s_%s''',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('B%d',2+(j-1)*5));
        writematrix(eval(sprintf('transition_13to24h_%s_%s''',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('B%d',3+(j-1)*5));
        writematrix(eval(sprintf('transition_1to12h_%s_%s_avg',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_avg',groupIDordered{i})),2+(j-1)*5));
        writematrix(eval(sprintf('transition_13to24h_%s_%s_avg',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_avg',groupIDordered{i})),3+(j-1)*5));
        writematrix(eval(sprintf('transition_1to12h_%s_%s_sem',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sem',groupIDordered{i})),2+(j-1)*5));
        writematrix(eval(sprintf('transition_13to24h_%s_%s_sem',transitionname{j},groupIDordered{i})), fullFileName, 'Sheet', sheetname, 'Range', sprintf('%s%d',eval(sprintf('col_%s_sem',groupIDordered{i})),3+(j-1)*5));
        
    end
end

% 【Sleep lantency 数据】
% 写入数据
for i = 1:length(groupIDordered)
    sheetname = sprintf('%s_lantency',groupIDordered{i});
    num = eval(sprintf('num_mice_%sfragment',groupIDordered{i}));
    writematrix(eval(sprintf('sleeplatency_NREM_%s',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','A2');
    writecell({'NREM Sleep Lantency（min)'}, fullFileName, 'Sheet', sheetname, 'Range', 'A1');
    writecell({'NREM Sleep Lantency Avg（min)'}, fullFileName, 'Sheet', sheetname, 'Range', 'C1');
    writematrix(eval(sprintf('sleeplatency_NREM_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','C2');
    writecell({'NREM Sleep Lantency sem'}, fullFileName, 'Sheet', sheetname, 'Range', 'D1');
    writematrix(eval(sprintf('sleeplatency_NREM_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','D2');
    writecell({'REM Sleep Lantency（min)'}, fullFileName, 'Sheet',sheetname, 'Range', ['A',num2str(num + 3)]);
    writematrix(eval(sprintf('sleeplatency_REM_%s',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['A',num2str(num + 4)]);
    writecell({'REM Sleep Lantency Avg（min)'}, fullFileName, 'Sheet',sheetname, 'Range', ['C',num2str(num + 3)]);
    writematrix(eval(sprintf('sleeplatency_REM_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['C',num2str(num + 4)]);
    writecell({'REM Sleep Lantency sem'}, fullFileName, 'Sheet',sheetname, 'Range', ['D',num2str(num + 3)]);
    writematrix(eval(sprintf('sleeplatency_REM_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['D',num2str(num + 4)]);
end

% 【MAs 数据】
% 写入数据
for i = 1:length(groupIDordered)
    sheetname = sprintf('%s_MAs',groupIDordered{i});
    num = eval(sprintf('num_mice_%sfragment',groupIDordered{i}));
    writematrix(eval(sprintf('MAs_1to12h_%s''',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','A2');
    writecell({'MAs 1to12h'}, fullFileName, 'Sheet', sheetname, 'Range', 'A1');
    writecell({'MAs 1to12h Avg'}, fullFileName, 'Sheet', sheetname, 'Range', 'C1');
    writematrix(eval(sprintf('MAs_1to12h_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','C2');
    writecell({'MAs 1to12h sem'}, fullFileName, 'Sheet', sheetname, 'Range', 'D1');
    writematrix(eval(sprintf('MAs_1to12h_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','D2');
    writecell({'MAs 13to24h'}, fullFileName, 'Sheet',sheetname, 'Range', ['A',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_13to24h_%s''',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['A',num2str(num + 4)]);
    writecell({'MAs 13to24h Avg'}, fullFileName, 'Sheet',sheetname, 'Range', ['C',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_13to24h_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['C',num2str(num + 4)]);
    writecell({'MAs 13to24h sem'}, fullFileName, 'Sheet',sheetname, 'Range', ['D',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_13to24h_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['D',num2str(num + 4)]);
end
% 【MAs_div_NREM 数据】
% 写入数据
for i = 1:length(groupIDordered)
    sheetname = sprintf('%s_MAs_div_NREM',groupIDordered{i});
    num = eval(sprintf('num_mice_%sfragment',groupIDordered{i}));
    writematrix(eval(sprintf('MAs_div_NREM_1to12h_%s''',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','A2');
    writecell({'MAs_div_NREM 1to12h'}, fullFileName, 'Sheet', sheetname, 'Range', 'A1');
    writecell({'MAs_div_NREM 1to12h Avg'}, fullFileName, 'Sheet', sheetname, 'Range', 'C1');
    writematrix(eval(sprintf('MAs_div_NREM_1to12h_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','C2');
    writecell({'MAs_div_NREM 1to12h sem'}, fullFileName, 'Sheet', sheetname, 'Range', 'D1');
    writematrix(eval(sprintf('MAs_div_NREM_1to12h_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range','D2');
    writecell({'MAs_div_NREM 13to24h'}, fullFileName, 'Sheet',sheetname, 'Range', ['A',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_div_NREM_13to24h_%s''',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['A',num2str(num + 4)]);
    writecell({'MAs_div_NREM 13to24h Avg'}, fullFileName, 'Sheet',sheetname, 'Range', ['C',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_div_NREM_13to24h_%s_avg',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['C',num2str(num + 4)]);
    writecell({'MAs_div_NREM 13to24h sem'}, fullFileName, 'Sheet',sheetname, 'Range', ['D',num2str(num + 3)]);
    writematrix(eval(sprintf('MAs_div_NREM_13to24h_%s_sem',groupIDordered{i})), fullFileName,'Sheet',sheetname,'Range',['D',num2str(num + 4)]);
end
if exist('close_windows_after_run')
    if isequal(close_windows_after_run, {'on'})
        close all
    end
end
disp('数据已成功导出到 data.xlsx 文件中,可以打开查看了。');  % 意思是在这句话弹出前不要打开xlsx文件，会导致文件写入失败fish[fi] 
%% 用到的一些自定义function
% function1 提取文件内容
function [Wake_time_percent, NREM_time_percent, REM_time_percent, num_mice] = extract_sleep_data(filename)
    % 读取 Excel 文件
    [data, ~, ~] = xlsread(filename);

    % 计算小鼠的数量
    num_mice = (size(data, 1) + 2) / 32;

    % 初始化提取的数据矩阵
    Wake_time_percent = [];
    NREM_time_percent = [];
    REM_time_percent = [];

    % 遍历每只小鼠
    for i = 1:num_mice
        % 计算当前小鼠的数据行索引
        start_row = (i - 1) * 32 + 7;
        end_row = start_row + 23;

        % 提取数据
        Wake_data = data(start_row:end_row, 10);
        NREM_data = data(start_row:end_row, 11);
        REM_data = data(start_row:end_row, 12);

        % 竖着排列并添加到结果矩阵中
        Wake_time_percent = [Wake_time_percent, Wake_data];
        NREM_time_percent = [NREM_time_percent, NREM_data];
        REM_time_percent = [REM_time_percent, REM_data];
    end
end

% function2 生成Excel列号
function col_letter = getExcelColumn(n)
    n = n + 1;  % 调整列号为从1开始
    col_letter = '';  % 初始化为空字符串
    
    while n > 0
        REMainder = mod((n - 1), 26);
        col_letter = [char(REMainder + 'A') col_letter];  % 拼接当前字符
        n = floor((n - 1) / 26);  % 更新列号
    end
end
%% README
%{
Readme
============================================================
使用前说明 2024-06-24 
============================================================

本代码可一键输出包括“01_Time(%)_Per_Hour”、“02_Total_Wake_Time_in~”、“03_Total_NREM_Time_in”、“04_Total_REM_Time_in”、“05_Number_of_episodes”、“06_Episode_duration”、“07_Total_Number_of_transitions_in_”、“08_Episode_Number_in”、“09_Episode_duration_in”、“10_Sleep_latency”在内的数据，并生成十张图。
同时会把部分结果生成在xlsx文件中，正式发表时可取用另外做图。其实在变量里也都有原数据。

0）使用spike7导出睡眠数据，包括睡眠时间数据和睡眠碎片化数据。注意睡眠时间数据要首尾相接依次放在一起，睡眠碎片化数据要以与睡眠时间数据一样的顺序依次放在每个sheet中，不要有空表格。
    将数据和本文件置于同一目录下。
1）在groupIDordered = {};处，按想要的顺序填写你的组别名，注意需与.xlsx文件名一致，大小写匹配。
  （可选）：修改下方的一些预设参数。不改也无所谓
2）点击运行，静待图片和数据生成。

* 注：目前只适用于24h（86400s）的数据
* 注：分析时默认是unpaired ttest，想做paired ttest需善用control+H将"ttest2"变为"ttest"
* 注：原始数据文件必须为.xlsx文件。 输出文件夹名：output_运行代码时的时间
* 注：务必在"可以打开查看了"的提示后，再打开输出data。否则会因为没有写入权限而发生错误

感谢使用。不会写代码，很多不熟悉，写完感觉已变成屎山 (← 现在稍微不是很屎山了)。 如有问题，请联系：quch2023@ion.ac.cn
============================================================
更新日志
[2024-06-24] 修改了当episodenumber为0时，可能出现的episodeduration为NaN或inf问题，现在它们都按0计算了。（episodeduration会整体稍短一点点）
[2024-07-26] 修改了当episodenumber为0时，可能出现的episodeduration为NaN或inf问题，现在它们都直接舍弃了。
[2024-08] 统一了变量名，修了图片输出格式，现在会同时输出矢量图了。修改了.xls文件的输出。以及N多排版问题，已经无法记清有多少了。现在会对一些极端的数据情况的包容性更好。
[2024-10-07] 更改了当每组数据大于10时会报错的bug。现在一个组的n可以超乎想象的大。
[2024-11-22] 史诗级更新。运用循环缩短了代码长度，并且可适用于大于等于一的多个组别的数据，但只有在两组时，会进行ttest分析。
             所有柱状图大小一致。并且当组别为4时，生成的柱状图为正方形。
             加入了预设颜色，如果不指定颜色的话会应用预设颜色。字体设置为黑色。增加多个检查区。
[2025-01-23] 改了上一版code引入的一个bug。加入了三角形scatter设置。
[2025-01-24] 加入了图11和图12，microarousals的计算。
[2025-03-15] 永久保留了三角形scatter的设置，放入开头的预设参数中了。
============================================================
by qch，感谢Dr.Yu 和 xyt、wqy、xmy、wjx提出的修改意见。

%}