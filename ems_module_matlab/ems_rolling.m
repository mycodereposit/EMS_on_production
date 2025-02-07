function sol = ems_econ_opt(PARAM,minute) 
    %%% This function is used to solve optimization problem, consisting 3 parts. 
    %%% (I) Define optimization variables.
    %%% (II) Define constraints.
    %%% (III) Call the solver and save parameters.
    
    % Set optimization solving time. 
    % options = optimoptions('intlinprog','MaxTime',40);
    
    if rem(PARAM.Horizon, PARAM.Resolution) % Check if the optimization horizon and resolution are compatible.
        error('horizon must be a multiple of resolution')            
    end
    if (PARAM.weight_energyfromgrid < 0 ) ||  (PARAM.weight_energycost < 0) || (PARAM.weight_profit < 0 ) || (PARAM.weight_multibatt  < 0) || (PARAM.weight_chargebatt < 0) || (PARAM.weight_smoothcharge < 0 ) 
        error('Weights must >= 0')
    end
    if  PARAM.weight_energyfromgrid + PARAM.weight_profit + PARAM.weight_energycost > 1
        error('You can only choose one of the three energy objectives')   
    end
    if (PARAM.weight_multibatt > 0 ) && (PARAM.battery.num_batt == 1)
        error('The number of battery must >= 2 to use this objective')
    end
    length_optimvar = PARAM.Horizon/PARAM.Resolution; % Length of optimization variable.
    
    % Change the unit of Resolution from (minute => hour) to be used in Expense calculation.
    minutes_in_hour = 60;
    resolution_in_hour = PARAM.Resolution/minutes_in_hour;

    Pnet =      optimvar('Pnet',length_optimvar,'LowerBound',-inf,'UpperBound',inf);
    Pdchg =     optimvar('Pdchg',length_optimvar,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',inf);
    xdchg =     optimvar('xdchg',length_optimvar,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',1,'Type','integer');
    Pchg =      optimvar('Pchg',length_optimvar,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',inf);
    xchg =      optimvar('xchg',length_optimvar,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',1,'Type','integer');
    soc =       optimvar('soc',length_optimvar+1,PARAM.battery.num_batt,'LowerBound',ones(length_optimvar+1,PARAM.battery.num_batt).*PARAM.battery.min,'UpperBound',ones(length_optimvar+1,PARAM.battery.num_batt).*PARAM.battery.max);
    % upper bound for Power diff between HA and DA solution
    uPnet = optimvar('uPnet',length_optimvar,'LowerBound',0,'UpperBound',inf);
    uPchg = optimvar('uPchg',length_optimvar,'LowerBound',0,'UpperBound',inf);
    uPdchg =  optimvar('uPdchg',length_optimvar,'LowerBound',0,'UpperBound',inf);
    % Define optimization variable corresponding to the main cost

    if PARAM.weight_energyfromgrid > 0
        % u is the upper bound of the energy unit.
        u = optimvar('u', length_optimvar, 'LowerBound', 0, 'UpperBound', inf);  
        total_obj = sum(u);       
    elseif PARAM.weight_energycost > 0
        % u is the upper bound of the expense.
        u = optimvar('u', length_optimvar, 'LowerBound', 0, 'UpperBound', inf);   
        total_obj = sum(u);       
    elseif PARAM.weight_profit > 0
        % u is the upper bound of the profit.
        u = optimvar('u', length_optimvar, 'LowerBound', -inf, 'UpperBound', inf); 
        total_obj = sum(u);      
    end
    if PARAM.weight_multibatt > 0 % Add soc diff objective
        % Define optimvar for 'multibatt' objective
        % s = Upper bound of |SoC diff| 
        % for 2 batt use batt difference for >= 3 batt use central soc
        if PARAM.battery.num_batt == 2
            s =         optimvar('s',length_optimvar,'LowerBound',0,'UpperBound',inf);
            total_obj = total_obj + PARAM.weight_multibatt*sum(s,'all'); % Add soc diff objective           
          
        elseif PARAM.battery.num_batt >= 3
            s =         optimvar('s',length_optimvar,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',inf);
            central_soc = optimvar('central_soc',length_optimvar,'LowerBound',0,'UpperBound',inf);
            total_obj = total_obj + PARAM.weight_multibatt*sum(s,'all');           
        end
    end
    if PARAM.weight_chargebatt > 0  
        % Add term for 'chargebatt' objective
        %for i = 1:PARAM.battery.num_batt
            total_obj = total_obj + PARAM.weight_chargebatt*sum(sum((PARAM.battery.max.*(ones(length_optimvar+1,PARAM.battery.num_batt)) - soc) ...
                                ./(ones(length_optimvar+1,PARAM.battery.num_batt).*(PARAM.battery.max - PARAM.battery.min)),2));  
    
        %end
    end
    if PARAM.weight_smoothcharge > 0 % Add non fluctuation charge and discharge objective
        % Define optimvars for 'smoothcharge' objective
        % upper_bound_Pchg is Upper bound of |Pchg(t)-Pchg(t-1)| objective
        % upper_bound_Pdchg is Upper bound of |Pdchg(t)-Pdchg(t-1)| objective
        upper_bound_Pchg = optimvar('upper_bound_Pchg',length_optimvar-1,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',inf);      
        upper_bound_Pdchg = optimvar('upper_bound_Pdchg',length_optimvar-1,PARAM.battery.num_batt,'LowerBound',0,'UpperBound',inf);        
        % Add non fluctuation charge and discharge objective.
        % Assume that the weight is equal for both Pchg and Pdchg.
        total_obj = total_obj + PARAM.weight_smoothcharge * (sum(upper_bound_Pchg,'all') + sum(upper_bound_Pdchg,'all')); 
       
    end
    total_obj = total_obj + PARAM.weight_Pnetdiff*sum(uPnet)...
                + PARAM.weight_Pchgdiff*sum(uPchg)...
                + PARAM.weight_Pdchgdiff*sum(uPdchg);
    %-------------------------- assign cost function -----------------------
    prob =      optimproblem('Objective', total_obj);

     % Define optimization variable corresponding to the main cost
    if PARAM.weight_energyfromgrid > 0       
        prob.Constraints.epicons1 = -resolution_in_hour*Pnet - u <= 0;
    elseif PARAM.weight_energycost > 0          
        %--constraint for buying electricity
        prob.Constraints.epicons1 = -resolution_in_hour*PARAM.Buy_rate.*Pnet - u <= 0;
    elseif PARAM.weight_profit > 0       
        %--constraint for buying/selling electricity
        prob.Constraints.epicons1 = -resolution_in_hour*PARAM.Buy_rate.*Pnet - u <= 0;
        prob.Constraints.epicons2 = -resolution_in_hour*PARAM.Sell_rate.*Pnet - u <= 0;
    end
    if PARAM.weight_multibatt > 0 % Add soc diff objective
        % Define optimvar for 'multibatt' objective
        % s = Upper bound of |SoC diff| 
        % for 2 batt use batt difference for >= 3 batt use central soc
        if PARAM.battery.num_batt == 2                     
            prob.Constraints.battdeviate1 = soc(2:length_optimvar+1,1) - soc(2:length_optimvar+1,2) <= s;
            prob.Constraints.battdeviate2 = -s <= soc(2:length_optimvar+1,1) - soc(2:length_optimvar+1,2);
        elseif PARAM.battery.num_batt >= 3     
            prob.Constraints.battdeviate1 = soc(2:length_optimvar+1,:) - central_soc.*ones(length_optimvar,PARAM.battery.num_batt) <= s.*ones(length_optimvar,PARAM.battery.num_batt);
            prob.Constraints.battdeviate2 = -s.*ones(length_optimvar,PARAM.battery.num_batt) <= soc(2:length_optimvar+1,:) - central_soc.*ones(length_optimvar,PARAM.battery.num_batt);
        end
    end  

    if PARAM.weight_smoothcharge > 0 % Add non fluctuation charge and discharge objective           
        % %-- Constraint non fluctuating charge and discharge
        % abs(Pchg(t)-Pchg(t-1)) <= upper_bound_Pchg
        prob.Constraints.non_fluct_Pchg_con1 = Pchg(1:end-1,:)-Pchg(2:end,:) <= upper_bound_Pchg;
        prob.Constraints.non_fluct_Pchg_con2 = -upper_bound_Pchg <= Pchg(1:end-1,:)-Pchg(2:end,:);
        % abs(Pdchg(t)-Pdchg(t-1)) <= upper_bound_Pdchg
        prob.Constraints.non_fluct_Pdchg_con1 = Pdchg(1:end-1,:)-Pdchg(2:end,:) <= upper_bound_Pdchg;
        prob.Constraints.non_fluct_Pdchg_con2 = -upper_bound_Pdchg <= Pdchg(1:end-1,:)-Pdchg(2:end,:);
    end
    
    % Constraint part
    % DA tracking constraints
    DAtrack = optimconstr(length_optimvar,6);
    if mod(minute,15) == 10
        for i = 0:3
            DAtrack(3*i+1:3*(i+1),1) = Pchg(3*i+1:3*(i+1),1) - PARAM.Pchg(i+1) <= uPchg(3*i+1:3*(i+1),1);
            DAtrack(3*i+1:3*(i+1),2) = - uPchg(3*i+1:3*(i+1),1) <= Pchg(3*i+1:3*(i+1),1) - PARAM.Pchg(i+1);
            
            DAtrack(3*i+1:3*(i+1),3) = Pdchg(3*i+1:3*(i+1),1) - PARAM.Pdchg(i+1) <= uPdchg(3*i+1:3*(i+1),1);
            DAtrack(3*i+1:3*(i+1),4) = - uPdchg(3*i+1:3*(i+1),1) <= Pdchg(3*i+1:3*(i+1),1) - PARAM.Pdchg(i+1);
            
            DAtrack(3*i+1:3*(i+1),5) = Pnet(3*i+1:3*(i+1),1) - PARAM.Pnet(i+1) <= uPnet(3*i+1:3*(i+1),1);
            DAtrack(3*i+1:3*(i+1),6) = - uPnet(3*i+1:3*(i+1),1) <= Pnet(3*i+1:3*(i+1),1) - PARAM.Pnet(i+1);
        end
    elseif mod(minute,15) == 0
        % add constraint to first 10 minutes
        DAtrack(1:2,1) = Pchg(1:2,1) - PARAM.Pchg(1) <= uPchg(1:2,1);
        DAtrack(1:2,2) = - uPchg(1:2,1) <= Pchg(1:2,1) - PARAM.Pchg(1);
        DAtrack(1:2,3) = Pdchg(1:2,1) - PARAM.Pdchg(1) <= uPdchg(1:2,1);
        DAtrack(1:2,4) = - uPdchg(1:2,1) <= Pdchg(1:2,1) - PARAM.Pdchg(1);
        DAtrack(1:2,5) = Pnet(1:2,1) - PARAM.Pnet(1) <= uPnet(1:2,1);
        DAtrack(1:2,6) = - uPnet(1:2,1) <= Pnet(1:2,1) - PARAM.Pnet(1);
        % add constraint to last 5 minutes
        DAtrack(end,1) = Pchg(end,1) - PARAM.Pchg(end) <= uPchg(end,1);
        DAtrack(end,2) = - uPchg(end,1) <= Pchg(end,1) - PARAM.Pchg(end);
        DAtrack(end,3) = Pdchg(end,1) - PARAM.Pdchg(end) <= uPdchg(end,1);
        DAtrack(end,4) = - uPdchg(end,1) <= Pdchg(end,1) - PARAM.Pdchg(end);
        DAtrack(end,5) = Pnet(end,1) - PARAM.Pnet(end) <= uPnet(end,1);
        DAtrack(end,6) = - uPnet(end,1) <= Pnet(end,1) - PARAM.Pnet(end);
        for i = 0:2
            DAtrack(3*i+3:3*(i+1)+2,1) = Pchg(3*i+3:3*(i+1)+2,1) - PARAM.Pchg(i+2) <= uPchg(3*i+3:3*(i+1)+2,1);
            DAtrack(3*i+3:3*(i+1)+2,2) = - uPchg(3*i+3:3*(i+1)+2,1) <= Pchg(3*i+3:3*(i+1)+2,1) - PARAM.Pchg(i+2);
            DAtrack(3*i+3:3*(i+1)+2,3) = Pdchg(3*i+3:3*(i+1)+2,1) - PARAM.Pdchg(i+2) <= uPdchg(3*i+3:3*(i+1)+2,1);
            DAtrack(3*i+3:3*(i+1)+2,4) = - uPdchg(3*i+3:3*(i+1)+2,1) <= Pdchg(3*i+3:3*(i+1)+2,1) - PARAM.Pdchg(i+2);
            DAtrack(3*i+3:3*(i+1)+2,5) = Pnet(3*i+3:3*(i+1)+2,1) - PARAM.Pnet(i+2) <= uPnet(3*i+3:3*(i+1)+2,1);
            DAtrack(3*i+3:3*(i+1)+2,6) = - uPnet(3*i+3:3*(i+1)+2,1) <= Pnet(3*i+3:3*(i+1)+2,1) - PARAM.Pnet(i+2);
        end
    elseif mod(minute,15) == 5
        % add constraint to first 5 minutes
        DAtrack(1,1) = Pchg(1,1) - PARAM.Pchg(1) <= uPchg(1,1);
        DAtrack(1,2) = - uPchg(1,1) <= Pchg(1,1) - PARAM.Pchg(1);
        DAtrack(1,3) = Pdchg(1,1) - PARAM.Pdchg(1) <= uPdchg(1,1);
        DAtrack(1,4) = - uPdchg(1,1) <= Pdchg(1,1) - PARAM.Pdchg(1);
        DAtrack(1,5) = Pnet(1,1) - PARAM.Pnet(1) <= uPnet(1,1);
        DAtrack(1,6) = - uPnet(1,1) <= Pnet(1,1) - PARAM.Pnet(1);
        % add constraint to last 10 minutes
        DAtrack(end-1:end,1) = Pchg(end-1:end,1) - PARAM.Pchg(end) <= uPchg(end-1:end,1);
        DAtrack(end-1:end,2) = - uPchg(end-1:end,1) <= Pchg(end-1:end,1) - PARAM.Pchg(end);
        DAtrack(end-1:end,3) = Pdchg(end-1:end,1) - PARAM.Pdchg(end) <= uPdchg(end-1:end,1);
        DAtrack(end-1:end,4) = - uPdchg(end-1:end,1) <= Pdchg(end-1:end,1) - PARAM.Pdchg(end);
        DAtrack(end-1:end,5) = Pnet(end-1:end,1) - PARAM.Pnet(end) <= uPnet(end-1:end,1);
        DAtrack(end-1:end,6) = - uPnet(end-1:end,1) <= Pnet(end-1:end,1) - PARAM.Pnet(end);
        for i = 0:2
            DAtrack(3*i+2:3*(i+1)+1,1) = Pchg(3*i+2:3*(i+1)+1,1) - PARAM.Pchg(i+2) <= uPchg(3*i+2:3*(i+1)+1,1);
            DAtrack(3*i+2:3*(i+1)+1,2) = - uPchg(3*i+2:3*(i+1)+1,1) <= Pchg(3*i+2:3*(i+1)+1,1) - PARAM.Pchg(i+2);
            DAtrack(3*i+2:3*(i+1)+1,3) = Pdchg(3*i+2:3*(i+1)+1,1) - PARAM.Pdchg(i+2) <= uPdchg(3*i+2:3*(i+1)+1,1);
            DAtrack(3*i+2:3*(i+1)+1,4) = - uPdchg(3*i+2:3*(i+1)+1,1) <= Pdchg(3*i+2:3*(i+1)+1,1) - PARAM.Pdchg(i+2);
            DAtrack(3*i+2:3*(i+1)+1,5) = Pnet(3*i+2:3*(i+1)+1,1) - PARAM.Pnet(i+2) <= uPnet(3*i+2:3*(i+1)+1,1);
            DAtrack(3*i+2:3*(i+1)+1,6) = - uPnet(3*i+2:3*(i+1)+1,1) <= Pnet(3*i+2:3*(i+1)+1,1) - PARAM.Pnet(i+2);
        end
    end    
    prob.Constraints.DAtrack = DAtrack;

    %--battery constraint

    prob.Constraints.chargeconsbatt = Pchg <= xchg.*(ones(length_optimvar,PARAM.battery.num_batt).*PARAM.battery.charge_rate);
    
    prob.Constraints.dischargeconsbatt = Pdchg   <= xdchg.*(ones(length_optimvar,PARAM.battery.num_batt).*PARAM.battery.discharge_rate);
    
    prob.Constraints.NosimultDchgAndChgbatt = xchg + xdchg >= 0;
    
    prob.Constraints.NosimultDchgAndChgconsbatt1 = xchg + xdchg <= 1;
    
    %--Pnet constraint
    prob.Constraints.powercons = Pnet == PARAM.PV + sum(Pdchg,2) - PARAM.PL - sum(Pchg,2);
    
    %end of static constraint part
    
    %--soc dynamic constraint 
    soccons = optimconstr(length_optimvar+1,PARAM.battery.num_batt);
    
    soccons(1,1:PARAM.battery.num_batt) = soc(1,1:PARAM.battery.num_batt)  == PARAM.battery.initial ;
    for j = 1:PARAM.battery.num_batt
        soccons(2:length_optimvar+1,j) = soc(2:length_optimvar+1,j)  == soc(1:length_optimvar,j) + ...
                                 (PARAM.battery.charge_effiency(:,j)*100*resolution_in_hour/PARAM.battery.actual_capacity(:,j))*Pchg(1:length_optimvar,j) ...
                                    - (resolution_in_hour*100/(PARAM.battery.discharge_effiency(:,j)*PARAM.battery.actual_capacity(:,j)))*Pdchg(1:length_optimvar,j);
        
    end
    prob.Constraints.soccons = soccons;
    
    %---solve for optimal sol
    %[sol, ~, exitflag] = solve(prob,'Options',options);
    [sol, ~, exitflag] = solve(prob);
    sol.exitflag = exitflag;
    sol.PARAM = PARAM;    
end
