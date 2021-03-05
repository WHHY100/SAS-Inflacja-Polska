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

data tab_previous_period;
 retain id;
 set tab_previous_period;
 id = _n_;
 Indeks_lancuchowy_poprzedni = lag(Indeks_lancuchowy);
 if id = 1 then Indeks_jednopodstawowy = Indeks_lancuchowy;
 else Pole_obliczeniowe = round((Indeks_lancuchowy * Indeks_lancuchowy_poprzedni)/100);
 Pole_obliczeniowe_poprzednie = lag(Pole_obliczeniowe);
run;