function [x,exitflag,index,Lmodel,fluxes,info]=NECOM(themodel,parameters,X)

%{ 
Function: Nash Equilibria predictor for microbial COMunity

Input: 
themodel:          Microbial community model data struct
parameters:        Parameters struct containing information about intercellular interaction 
X                  vector of relative abundance for each community members

Output:
x                  solution of NECom
%}

% Jingyi Cai 2018.10

bigM=1000;
%-----------------------------------parameters preparation-----------------
n_all_model=sum((themodel.rxnSps>=1)); % total number of reactions for all species
m_all_model=sum((themodel.metSps>=1)); % total number of metabolites for all species
number_sps=length(themodel.spBm);% number of species

C=zeros(n_all_model,1);
C(themodel.spBm)=1; % objective vectors 


%reactions with unlimited lb 
lbInf1 = themodel.lb <= -(bigM-1);
themodel.lb(lbInf1)=-bigM;
%reactions with unlimited ub
ubInf1 = themodel.ub >=  (bigM-1);
themodel.ub(ubInf1)= bigM;

lb1=themodel.lb;
ub1=themodel.ub;
%--------------------------------------------------------------------------
Lmodel = start_Lmodel(); % initial modelling

% add reaction fluxes as variables
objvar=zeros(n_all_model,1);
lb=lb1(themodel.rxnSps>=1);
ub=ub1(themodel.rxnSps>=1);
vtype=char('C'*ones(1,n_all_model));
varnames=char(strcat('v_1_',themodel.rxns(themodel.rxnSps>=1)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);
history_length=0;
history_length_v_1=history_length;
current_length_v_1=history_length_v_1+n_all_model;
index.var.v1 = 1:n_all_model;
nVar = index.var.v1(end);



%SV = 0,mass balance constraint 
lhs=zeros(m_all_model,1);
S=themodel.S(themodel.metSps>=1,themodel.rxnSps>=1); % the stochiometric matrix
A=S;
rhs=zeros(m_all_model,1);
connames=char(strcat('MassBalance_', themodel.mets(find(themodel.metSps>=1))));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.mb1 = 1:m_all_model;
nCon = index.con.mb1(end);


%add mu_LB, the dual variable for lower bounds constraints of flux variables
objvar=zeros(n_all_model,1);
lb=zeros(n_all_model,1);
ub= inf(n_all_model,1);
vtype=char('C'*ones(1,n_all_model));
varnames=char(strcat('mu_LB_',themodel.rxns(1:n_all_model)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);

history_length=current_length_v_1;
history_length_mu_LB_1=history_length;
current_length_mu_LB_1=history_length_mu_LB_1+n_all_model;
index.var.muLmodel = nVar + 1 : nVar + n_all_model;
nVar = nVar + n_all_model;

%add mu_UB, the dual variable for upper bounds constraints of flux variables
objvar=zeros(n_all_model,1);
lb=zeros(n_all_model,1);
ub=inf(n_all_model,1);
vtype=char('C'*ones(1,n_all_model));
varnames=char(strcat('mu_UB_',themodel.rxns(1:n_all_model)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);

history_length=current_length_mu_LB_1;
history_length_mu_UB_1=history_length;
current_length_mu_UB_1=history_length_mu_UB_1+n_all_model;
index.var.muUP = nVar + 1 : nVar + n_all_model;
nVar = nVar + n_all_model;


%add lambda, the dual variable for the mass balance constraint SV=0
objvar=zeros(m_all_model,1);
lb=-inf(m_all_model,1);
ub=inf(m_all_model,1);
vtype=char('C'*ones(1,m_all_model));
varnames=char(strcat('lambda_',themodel.mets(themodel.metSps>=1), '_1'));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);

history_length=current_length_mu_UB_1;
history_length_lambda_1=history_length;
current_length_lambda_1=history_length_lambda_1+m_all_model;
index.var.lam1 = nVar + 1 : nVar + m_all_model;
nVar = nVar + m_all_model;


%--------------split the candidate crossfeeding rxns into export and uptake rxns-----------------------------
% add export flux variable Vut
objvar=zeros(parameters.numSub_ExRxn,1);
lb=zeros(parameters.numSub_ExRxn,1);
ub=inf(parameters.numSub_ExRxn,1);
vtype=char('C'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('vut_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);

history_length=current_length_lambda_1;
history_length_vut=history_length;
current_length_vut=history_length_vut+parameters.numSub_ExRxn;
index.var.vut = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;

% add import flux variable Vex
objvar=zeros(parameters.numSub_ExRxn,1);
lb=zeros(parameters.numSub_ExRxn,1);
ub=inf(parameters.numSub_ExRxn,1);
vtype=char('C'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('vex_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);

history_length=current_length_vut;
history_length_vex=history_length;
current_length_vex=history_length_vex+parameters.numSub_ExRxn;
index.var.vex = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;


%add constraints, V-V_ut+V_ex=0 or V=V_ut-V_ex for all candidate crossfeeding reactions

v_matrix=sparse(1:parameters.numSub_ExRxn,parameters.sub_indExSpi,ones(parameters.numSub_ExRxn,1),parameters.numSub_ExRxn,n_all_model);
v_ut_matrix=speye(parameters.numSub_ExRxn);
v_ex_matrix=speye(parameters.numSub_ExRxn);
lhs=zeros(parameters.numSub_ExRxn,1);
A=[v_matrix,sparse(parameters.numSub_ExRxn,history_length_vut-current_length_v_1),+v_ut_matrix,-v_ex_matrix];
rhs=zeros(parameters.numSub_ExRxn,1);
connames = char(strcat('V-V_ut+V_ex=0_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.splitV = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;

%-----------variables in dual problem----------------------------------------------------
objvar=zeros(parameters.numSub_ExRxn,1);
lb=-inf(parameters.numSub_ExRxn,1);
ub=zeros(parameters.numSub_ExRxn,1);
vtype=char('C'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('psi_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);
history_length=current_length_vex;
history_length_psi=history_length;
current_length_psi=history_length_psi+parameters.numSub_ExRxn;
index.var.psi = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;

objvar=zeros(parameters.numSub_ExRxn,1);
lb=zeros(parameters.numSub_ExRxn,1);
ub=inf(parameters.numSub_ExRxn,1);
vtype=char('C'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('omega_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);
history_length=current_length_psi;
history_length_omega=history_length;
current_length_omega=history_length_omega+parameters.numSub_ExRxn;
index.var.omega = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;

%-----------the binary variable delta--to realize max(0,(v_ex-v_ut)--------
objvar=zeros(parameters.numSub_ExRxn,1);
lb=zeros(parameters.numSub_ExRxn,1);
ub=ones(parameters.numSub_ExRxn,1);
vtype=char('B'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('delta_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);
history_length=current_length_omega;
history_length_delta=history_length;
current_length_delta=history_length_delta+parameters.numSub_ExRxn;
index.var.delta = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;

%---Xn*W+psi>=0----------------------------------------------
X_vector=sparse(1:parameters.numSub_ExRxn,1:parameters.numSub_ExRxn,X(parameters.sub_exSpi),parameters.numSub_ExRxn,parameters.numSub_ExRxn);
lhs=zeros(parameters.numSub_ExRxn,1);
A=[sparse(parameters.numSub_ExRxn,history_length_psi),speye(parameters.numSub_ExRxn),...
    X_vector,sparse(parameters.numSub_ExRxn,parameters.numSub_ExRxn)];
rhs=inf(parameters.numSub_ExRxn,1);
connames = char(strcat('Xn*W+psi=0_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.dualX = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;


psi_matrix=sparse(parameters.sub_indExSpi,1:parameters.numSub_ExRxn,ones(parameters.numSub_ExRxn,1),n_all_model,parameters.numSub_ExRxn);
matrix_mu=speye(n_all_model);
%S'lambda_1 + mu_UB-mu_LB + psi = c   
lhs=C;
A=[sparse(n_all_model,history_length_mu_LB_1),-matrix_mu,matrix_mu,...
        sparse(n_all_model,history_length_lambda_1-current_length_mu_UB_1),S',...
        sparse(n_all_model,history_length_psi-current_length_lambda_1),psi_matrix,...
        sparse(n_all_model,current_length_delta-current_length_psi)];
rhs=C;
connames=char(strcat('dual_',themodel.rxns(themodel.rxnSps>=1)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);   
index.con.dv = nCon + 1 : nCon + n_all_model;
nCon = nCon + n_all_model;

objvar=zeros(parameters.numSub_ExRxn,1);
lb=zeros(parameters.numSub_ExRxn,1);    
ub=inf(parameters.numSub_ExRxn,1);
vtype=char('C'*ones(1,parameters.numSub_ExRxn));
varnames=char(strcat('ub_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_variables(Lmodel,objvar,lb,ub,vtype,varnames);
history_length=current_length_delta;
history_length_ub=history_length;
current_length_ub=history_length_ub+parameters.numSub_ExRxn;
index.var.ub = nVar + 1 : nVar + parameters.numSub_ExRxn;
nVar = nVar + parameters.numSub_ExRxn;    
    

lhs=-inf(parameters.numSub_ExRxn,1);
A=[sparse(parameters.numSub_ExRxn,history_length_vut), X_vector,...
    sparse(parameters.numSub_ExRxn,history_length_ub-current_length_vut),-speye(parameters.numSub_ExRxn)];
rhs=zeros(parameters.numSub_ExRxn,1);
connames=char(strcat('Xn V_ut-ub<=0_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.VutBounds = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;

%--------------------------------------------------------------------------
%
X_vector_other=sparse(parameters.order_other,parameters.other_Ex_all,X(parameters.other_sp_ind),parameters.numSub_ExRxn,n_all_model);
lhs=-inf(parameters.numSub_ExRxn,1);
A=[-X_vector_other,...
    sparse(parameters.numSub_ExRxn,history_length_delta-current_length_v_1),...
    -bigM*speye(parameters.numSub_ExRxn),...
    speye(parameters.numSub_ExRxn)];
rhs=zeros(parameters.numSub_ExRxn,1);
connames=char(strcat('v_ut=max(0,v_oth)_1_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.v_max_select1 = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;


lhs=-inf(parameters.numSub_ExRxn,1);
A=[sparse(parameters.numSub_ExRxn,history_length_delta),bigM*speye(parameters.numSub_ExRxn)...
    speye(parameters.numSub_ExRxn)];
rhs=bigM*ones(parameters.numSub_ExRxn,1);
connames=char(strcat('v_ut=max(0,v_oth)_2_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.v_max_select2 = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;



lhs=zeros(parameters.numSub_ExRxn,1);
A=[-X_vector_other,...
    sparse(parameters.numSub_ExRxn,history_length_ub-current_length_v_1),...
    speye(parameters.numSub_ExRxn)];
rhs=inf(parameters.numSub_ExRxn,1);
connames= char(strcat('v_ut=max(0,v_oth)_3_',themodel.rxns(parameters.sub_indExSpi)));
Lmodel=add_constraints(Lmodel,lhs,A,rhs,connames);
index.con.v_max_select3 = nCon + 1 : nCon + parameters.numSub_ExRxn;
nCon = nCon + parameters.numSub_ExRxn;
%--------------------------------------------------------------------------

%mu_LB_1=0 for unlimited J
UnBounded_lb = find(lbInf1(1:n_all_model));
Lmodel.Model.ub(history_length_mu_LB_1+UnBounded_lb) = 0;
%mu_UB_1=0 for unlimited J
UnBounded_ub = find(ubInf1(1:n_all_model));
Lmodel.Model.ub(history_length_mu_UB_1+UnBounded_ub) = 0;    


parameters.limitednonzero_lb=find(abs(lb1)>1e-7&abs(lb1)<bigM-1);
parameters.limitednonzero_ub=find(abs(ub1)>1e-7&abs(ub1)<bigM-1);
parameters.X=X;

parameters.number_sps=number_sps;

% prepare the objective function
commandstr= 'fun = @(x) 0'  ;           
for h=1:number_sps
    commandstr=[commandstr,'+x(themodel.spBm(',num2str(h),'))'];
end
eval(commandstr)

% check if baron solver is exist

    % if No license for the Baron solver, one can try OPTI, a free platfrom provide multiple MINLP
    % slover, from http://www.inverseproblem.co.nz/OPTI/
    constr=NL_constraint(themodel,index,parameters);
    eval(constr)
    % if baron solver is not available, try Matlab solver fmincon
    A=Lmodel.Model.A;
    rl=Lmodel.Model.lhs;
    ru=Lmodel.Model.rhs;
    lb=Lmodel.Model.lb; % decision variable lower bounds
    ub=Lmodel.Model.ub; % decision variable upper bounds
    cl=zeros(number_sps,1);
    cu=zeros(number_sps,1);    
    vtype=Lmodel.Model.vtype; % 

if exist('baron');
    % the non-linear constraint
    startX=[];
    [x,fval,exitflag,info] = baron(fun,A,rl,ru,lb,ub,nlcon,cl,cu,vtype,startX,...
    baronset('filekp',1,'sense','max','NumSol',1,'MaxTime',10000));
elseif exist('opti');
    % using bonmin solver 
    startX=zeros(length(lb),1);% initial guesses
    opti_options=optiset('solver','bonmin','display','iter');
    theproblem=opti('sense',1,'fun',fun,'bounds',lb,ub,'lin',A,rl,ru,'nl',nlcon,cl,cu,'xtype',vtype,'options',opti_options);
    [x,fval,exitflag,info]=solve(theproblem,startX);
    % or using 
else
    error('MINLP solver not found, Open-source toolbox OPTI(www.inverseproblem.co.nz/OPTI/, for Windows only) are suggested')
end
if isempty(x)
    exitflag=-10;
    fluxes=[];
    info=[];
else
    fluxes=x(find(themodel.rxnSps>=1));
end


end    
    
function [c,ceq]=nonlinearCons

load tempInfo.mat
    constr=NL_constraint(themodel,index,parameters);
    eval(constr);
    ceq=nlcon;
    c=[];
end


function constr=NL_constraint(themodel,index,parameters)



limitednonzero_lb=parameters.limitednonzero_lb;
limitednonzero_ub=parameters.limitednonzero_ub;

limitednonzero_lbind=themodel.rxnSps(limitednonzero_lb);
limitednonzero_ubind=themodel.rxnSps(limitednonzero_ub);
number_sps=parameters.number_sps;
sub_exSpi=parameters.sub_exSpi;
sub_indExSpi=parameters.sub_indExSpi;


for i=1:number_sps
limitednonzero_lbs{i,1}=limitednonzero_lb(find(limitednonzero_lbind==i));
limitednonzero_ubs{i,1}=limitednonzero_ub(find(limitednonzero_ubind==i));
end


constr='nlcon=@(x)[';

lb1=themodel.lb;
ub1=themodel.ub;
spBm=themodel.spBm;
%for example
% eval('nlcon = @(x) [x(2391)+2.85*x(3907)-2.85*x(7738)-conNO2(i)*x(4171)+conNO2(i)*x(8002)
%-6.526e-05*x(9497)-6.526e-05*x(9498)-x(14396)*x(3738)*options.X(2);x(3660)-conGlc(i)*x(6259)
%-x(14397)*x(3695)*options.X(1)-x(14398)*x(3699)*options.X(1)]');

for i=1:number_sps
    
    % first the biomass reaction
    constr=strcat(constr,['x(',num2str(spBm(i)),')']);
    
    for k=1:length(limitednonzero_lbs{i,1})  
    % 
    itemlb=['+',['(',num2str(lb1(limitednonzero_lbs{i,1}(k))),')','*'] , ['x(',num2str(index.var.muLmodel(limitednonzero_lbs{i,1}(k))),')'] ];
    constr=strcat(constr,itemlb);
    end
    
    for k=1:length(limitednonzero_ubs{i,1})      
    itemub=['-',['(',num2str(ub1(limitednonzero_ubs{i,1}(k))),')','*'] , ['x(',num2str(index.var.muUP(limitednonzero_ubs{i,1}(k))),')'] ];
    constr=strcat(constr,itemub);
    end
    
%    
    indi=find(sub_exSpi==i);
    
    NL_term='';
    for p=1:numel(indi)
        omegaitem=['x(',num2str(index.var.omega(indi(p))),')'];
        ubstr=['x(',num2str(index.var.ub(indi(p))),')'];
        NL_term=[NL_term,'-',omegaitem,'*',ubstr];
    end

    constr=[constr,NL_term,';'];
    
end

    constr(end)=[];
    constr=[constr,'];'];
end








