/*Czyszczenie worka z poprzednich tabel tymczasowych*/
proc datasets noprint library=WORK kill; run; quit;

%let amount = 500;
/*Sciezka do csv - dane z rządowego portalu*/
%let path = 'https://api.dane.gov.pl/resources/28395,kwartalne-wskazniki-cen-towarow-i-usug-konsumpcyjnych-od-1995-roku/csv';
/*Definiowanie pliku tymczasowego z odpowiednim kodowaniem*/
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

/*Makro do wybrania odpowiednich wartosci z csv*/
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

/*Uśrednienia inflacji w ujęciu rocznym z poszczególnych kwartałów*/
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

/*Obliczanie indeksy jednopodstawowego - poprzedni jednopodstawowy * obecny łańcuchowy*/
%macro createSingleBaseIndex(tab);
 %do i = 1 %to &maxId;
  %if &i = 1 %then %do;
   proc sql noprint;
    select indeks_lancuchowy_cpi into: valueIndex from &tab where id = 1;
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
     select indeks_lancuchowy_cpi into: dependentIndex from &tab where 
     id = &i
   ;quit;
   
   proc sql;
    insert into tab_single_base_index (id, Indeks_jednopodstawowy_cpi) VALUES
    (&i, %sysfunc(round(%sysevalf((&preValBaseIndex * &dependentIndex)/100), .01)))
   ;quit;
  %end;
 %end;
 
 proc sort data=&tab;
 by id;
 run;
 
 proc sort data=tab_single_base_index;
 by id;
 run;
%mend;

%createSingleBaseIndex(tab_dependent_index);

data tab_inflation;
 merge tab_dependent_index tab_single_base_index;
 by id;
 id = id + 1;
run;

proc sql noprint;
 select min(rok) - 1 into: prevYear from tab_inflation
;quit;

proc sql;
 insert into tab_inflation(id, Rok, indeks_lancuchowy_cpi) VALUES
 (1, &prevYear, 100)
;quit;

data tab_inflation;
 set tab_inflation;
 Wartosc_w_poczatkowym_roku = &amount;
 Realna_sila_nabywcza = round(
 	(Wartosc_w_poczatkowym_roku / coalesce(Indeks_jednopodstawowy_cpi, Indeks_lancuchowy_cpi)) * 100, 0.1
 );
 Procent_sily_nabywczej = round((Realna_sila_nabywcza/Wartosc_w_poczatkowym_roku) * 100, 0.1);
 Utrata_wartosci = &amount - Realna_sila_nabywcza;
 if rok >= 2016 then flaga_500 = 1;
 else flaga_500 = 0;
run;

/*Tabela z podsumowanymi wynikami*/
proc sort data = tab_inflation;
by id;
run;

/*Badanie wplywu 500+ na srednia inflacje - poczatek programu w roku 2016*/
data tab_inflation_500;
 set tab_inflation;
 where flaga_500 = 1;
 keep Id Indeks_lancuchowy_cpi;
 rename id = id_rel_field_inflation;
run;

data tab_inflation_500;
 retain id;
 set tab_inflation_500;
 id = _n_;
run;

proc sql noprint;
 select max(id) into: maxid from tab_inflation_500
;quit;

%createSingleBaseIndex(tab_inflation_500);

data tab_inflation_500;
 merge tab_inflation_500 tab_single_base_index;
 by id;
 drop id indeks_lancuchowy_cpi;
 rename id_rel_field_inflation = id indeks_jednopodstawowy_cpi = indeks_jednopodstawowy_cpi_500;
run;

proc sort data = tab_inflation_500;
by id;
run;

data tab_inflation;
 merge tab_inflation tab_inflation_500;
 by id;
 If rok = 2015 then Realna_sila_nabywcza_500 = &amount;
 If rok = 2015 then Utrata_wartosci_500 = 0;
 If flaga_500 = 1 Then Realna_sila_nabywcza_500 = round((&amount/indeks_jednopodstawowy_cpi_500) * 100, 0.1);
 If flaga_500 = 1 Then Utrata_wartosci_500 = round(&amount - Realna_sila_nabywcza_500, 0.1);
run;