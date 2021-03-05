proc datasets noprint library=WORK kill; run; quit;

%let path = 'https://api.dane.gov.pl/resources/28395,kwartalne-wskazniki-cen-towarow-i-usug-konsumpcyjnych-od-1995-roku/csv';
filename csv temp ENCODING=UTF8;

proc http method="GET" url=&path out=csv;

proc import datafile = csv
 out = work.entry_table
 dbms = CSV;
 delimiter = ',';
run;

data entry_table;
 set entry_table;
 rename VAR3 = Typ_okres VAR5 = Kwartal VAR6 = Indeks_lancuchowy;
run;

%macro cleanData(condition, finName);
data tab_previous;
 set entry_table;
 Typ_okres = trim(COMPBL(lowcase(Typ_okres)));
run;

data &finName;
 set tab_previous;
 where Typ_okres contains(&condition);
run;

proc sort data = &finName;
 by Rok Kwartal;
run;
%mend;

%cleanData('analogiczny okres', tab_previous_year);
%cleanData('okres poprzedni', tab_previous_period);
%cleanData('grudzień roku poprzedniego', tab_dec_last_year);

proc sql;
 create table tab_inflation_by_year as
 select
 	Rok
 	,round(mean(Indeks_lancuchowy), .01) as Indeks_lancuchowy_cpi
 from tab_previous_period
 group by Rok
 order by rok
;quit;

data tab_dependent_index;
 retain id;
 set tab_inflation_by_year;
 id = _n_;
run;

proc sql noprint;
 select max(id) into: maxid from tab_dependent_index
;quit;

%macro createSingleBaseIndex;
 %do i = 1 %to &maxId;
  %if &i = 1 %then %do;
   proc sql noprint;
    select indeks_lancuchowy_cpi into: valueIndex from tab_dependent_index where id = 1;
   ;quit;
   
   proc sql;
    create table tab_single_base_index
    (
     id integer,
     Indeks_jednopodstawowy_cpi decimal
    )
   ;quit;
   
   proc sql;
    insert into tab_single_base_index (id, Indeks_jednopodstawowy_cpi) VALUES
    (&i, &valueIndex)
   ;quit;
  %end;
  %else %do;
   proc sql noprint;
    select indeks_jednopodstawowy_cpi into: preValBaseIndex from tab_single_base_index where 
    id = %eval(&i - 1)
   ;quit;
   
    proc sql noprint;
     select indeks_lancuchowy_cpi into: dependentIndex from tab_dependent_index where 
     id = &i
   ;quit;
   
   proc sql;
    insert into tab_single_base_index (id, Indeks_jednopodstawowy_cpi) VALUES
    (&i, %sysfunc(round(%sysevalf((&preValBaseIndex * &dependentIndex)/100), .01)))
   ;quit;
  %end;
 %end;
 
 proc sort data=tab_dependent_index;
 by id;
 run;
 
 proc sort data=tab_single_base_index;
 by id;
 run;
%mend;

%createSingleBaseIndex;

data tab_inflation;
merge tab_dependent_index tab_single_base_index;
by id;
id = id + 1;
run;