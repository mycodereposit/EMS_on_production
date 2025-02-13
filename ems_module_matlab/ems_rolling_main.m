clc;clear;
pv_capacity  = 50;                   % Solar panel installation capacity in kWp (int) 

% TOU_CHOICE = 'smart1';             % Choice for TOU
% TOU_CHOICE = 'nosell';
TOU_CHOICE = 'THcurrent';

%% DA parameters 
% ---- DA parameters ----
PARAM_DA.Horizon     = 3*24*60; 
PARAM_DA.Resolution  = 15;
PARAM_DA.PV_capacity = pv_capacity;
PARAM_DA.TOU_CHOICE  = TOU_CHOICE;
PARAM_DA.weight_energyfromgrid = 0;
PARAM_DA.weight_energycost = 1;
PARAM_DA.weight_profit = 0;
PARAM_DA.weight_multibatt = 1;
PARAM_DA.weight_chargebatt = 1;
PARAM_DA.weight_smoothcharge  = 0.3;

% Battery parameters
PARAM_DA.battery.charge_effiency = [0.95 0.95]; %bes charge eff
PARAM_DA.battery.discharge_effiency = [0.95*0.93 0.95*0.93]; %  bes discharge eff note inverter eff 0.93-0.96
PARAM_DA.battery.discharge_rate = [30 30]; % kW max discharge rate
PARAM_DA.battery.charge_rate = [30 30]; % kW max charge rate
PARAM_DA.battery.actual_capacity = [125 125]; % kWh soc_capacity 
PARAM_DA.battery.initial = [50 50]; % userdefined int 0-100 %
PARAM_DA.battery.min = [20 20]; %min soc userdefined int 0-100 %
PARAM_DA.battery.max = [80 80]; %max soc userdefined int 0-100 %
PARAM_DA.battery.num_batt = length(PARAM_DA.battery.actual_capacity);
%end of batt
%% HA parameters 
% ---- HA parameters ----
PARAM_HA.Horizon     = 1*60; 
PARAM_HA.Resolution  = 5;
PARAM_HA.PV_capacity = pv_capacity;
PARAM_HA.TOU_CHOICE  = TOU_CHOICE;
PARAM_HA.weight_energyfromgrid = 0;
PARAM_HA.weight_energycost = 1;
PARAM_HA.weight_profit = 0;
PARAM_HA.weight_multibatt = 1;
PARAM_HA.weight_chargebatt = 0.07;
PARAM_HA.weight_smoothcharge  = 0.06;
PARAM_HA.weight_Pnetdiff = 0.1;
PARAM_HA.weight_Pchgdiff = 0.3;
PARAM_HA.weight_Pdchgdiff  = 0.2;

% Battery parameters
PARAM_HA.battery.charge_effiency = [0.95 0.95]; %bes charge eff
PARAM_HA.battery.discharge_effiency = [0.95*0.93 0.95*0.93]; %  bes discharge eff note inverter eff 0.93-0.96
PARAM_HA.battery.discharge_rate = [30 30]; % kW max discharge rate
PARAM_HA.battery.charge_rate = [30 30]; % kW max charge rate
PARAM_HA.battery.actual_capacity = [125 125]; % kWh soc_capacity 
PARAM_HA.battery.initial = [50 50]; % userdefined int 0-100 %
PARAM_HA.battery.min = [20 20]; %min soc userdefined int 0-100 %
PARAM_HA.battery.max = [80 80]; %max soc userdefined int 0-100 %
PARAM_HA.battery.num_batt = length(PARAM_HA.battery.actual_capacity);
%end of batt
%% read predict load and solar profile
root_folder = 'C:/Users/User/Desktop/VSCpython/opt_test/input_data/predict/'; % change this line to your Path
load_DA = readtable(strcat(root_folder,'load_Dayahead_20230302_20231228.csv'),VariableNamingRule="preserve");
load_HA = readtable(strcat(root_folder,'load_Intraday_20230301_20231230.csv'),VariableNamingRule="preserve");
pv_DA = readtable(strcat(root_folder,'pv_Dayahead_20230102_20231228.csv'),VariableNamingRule="preserve");
pv_HA = readtable(strcat(root_folder,'pv_Intraday_20230101_20231231.csv'),VariableNamingRule="preserve");
%% scale PV
pv_scaling_factor = pv_capacity/8;
pv_DA(:,2:end) = pv_DA(:,2:end).*pv_scaling_factor;
pv_HA(:,2:end) = pv_HA(:,2:end).*pv_scaling_factor;
%%
Num_days = 4;
initial_date = datetime('2023-11-01');
First_time_init = true;
% the DA TOU is the same every day
[PARAM_DA.Buy_rate,PARAM_DA.Sell_rate] = getBuySellrate(initial_date, ...
                                                           PARAM_DA.Resolution, ...
                                                            PARAM_DA.Horizon, ...
                                                            TOU_CHOICE);
for day = 0:Num_days-1
    PARAM_DA.start_date = initial_date + days(day);
    % note predict load and solar can be < 0 and will be replace with 0
    % i.e. max(0,Power)
    PARAM_DA.PV = max(0, table2array(pv_DA(pv_DA.ds == PARAM_DA.start_date,2:end) )');
    PARAM_DA.PL = max(0, table2array(load_DA(load_DA.ds == PARAM_DA.start_date,2:end) )');
    
    if day == 0
        PARAM_DA.battery.initial = [50 50];
    else
        PARAM_DA.battery.initial = DA_solution.soc(97,:);
    end
    fprintf('begin optimizing day %d',day)
    DA_solution = ems_econ_opt(PARAM_DA);
    date_col = PARAM_DA.start_date:minutes(PARAM_DA.Resolution):PARAM_DA.start_date + days(3);
    % manually retrieve solution as struct can not be concat
    retrieved_DA_solution = table(date_col(1:end-1)', ...
                              DA_solution.PARAM.PV, ...
                              DA_solution.PARAM.PL, ...
                              DA_solution.PARAM.Buy_rate, ...
                              DA_solution.PARAM.Sell_rate, ...
                              DA_solution.Pchg, ...
                              DA_solution.Pdchg, ...
                              DA_solution.s, ...
                              DA_solution.soc(1:end-1,:), ...
                              DA_solution.u, ...
                              DA_solution.xchg, ...
                              DA_solution.xdchg, ...
                              DA_solution.Pnet);
    retrieved_DA_solution.Properties.VariableNames = {'datetime','PV','PL','Buy_rate','Sell_rate',...
                                                       'Pchg','Pdchg','s','soc','u','xchg','xdchg','Pnet' };

    if day == 0       
        DA_solution_list = retrieved_DA_solution(1:96,:);
    else        
        DA_solution_list = [DA_solution_list;retrieved_DA_solution(1:96,:)];
    end
    fprintf('finish optimizing day %d',day)
    for i = 0:287
        PARAM_HA.start_date = PARAM_DA.start_date + minutes(5*i);
        PARAM_HA.end_date = PARAM_HA.start_date + minutes(PARAM_HA.Horizon);
        PARAM_HA.PV = max(0, table2array(pv_HA(pv_HA.ds == PARAM_HA.start_date,2:end) )');
        PARAM_HA.PL = max(0, table2array(load_HA(load_HA.ds == PARAM_HA.start_date,2:end) )');
        windowed_DA_plan = retrieved_DA_solution((retrieved_DA_solution.datetime >= PARAM_HA.start_date - minutes(10)) ...
                                   & (retrieved_DA_solution.datetime < PARAM_HA.end_date),:  );
        PARAM_HA.Pchg = windowed_DA_plan.Pchg(:,1);
        PARAM_HA.Pdchg = windowed_DA_plan.Pdchg(:,1);
        PARAM_HA.Pnet = windowed_DA_plan.Pnet(:,1);
        [PARAM_HA.Buy_rate,PARAM_HA.Sell_rate] = getBuySellrate(PARAM_HA.start_date, ...
                                                           PARAM_HA.Resolution, ...
                                                            PARAM_HA.Horizon, ...
                                                            TOU_CHOICE);
        if First_time_init
             PARAM_HA.battery.initial = [50 50];
             First_time_init = false;
        else
             PARAM_HA.battery.initial = HA_solution.soc(2,:);
        end
        fprintf('begin optimizing day %d step %d',day,i)
        HA_solution = ems_rolling(PARAM_HA,5*i);
        retrieved_HA_solution = table(PARAM_HA.start_date, ...
                              HA_solution.PARAM.PV(1,:), ...
                              HA_solution.PARAM.PL(1,:), ...
                              HA_solution.PARAM.Buy_rate(1,:), ...
                              HA_solution.PARAM.Sell_rate(1,:), ...
                              HA_solution.Pchg(1,:), ...
                              HA_solution.Pdchg(1,:), ...
                              HA_solution.s(1,:), ...
                              HA_solution.soc(1,:), ...
                              HA_solution.u(1,:), ...
                              HA_solution.xchg(1,:), ...
                              HA_solution.xdchg(1,:), ...
                              HA_solution.Pnet(1,:));
        retrieved_HA_solution.Properties.VariableNames = {'datetime','PV','PL','Buy_rate','Sell_rate',...
                                                       'Pchg','Pdchg','s','soc','u','xchg','xdchg','Pnet' };
        if day == 0 && i == 0
            HA_solution_list = retrieved_HA_solution;
        else
            HA_solution_list = [HA_solution_list;retrieved_HA_solution];
        end
        
        fprintf('finish optimizing day %d step %d',day,i)
    end
end

writetable(HA_solution_list,'solution/HA_solution.csv');
writetable(DA_solution_list,'solution/DA_solution.csv');






