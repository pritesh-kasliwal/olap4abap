*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! FoodMart as plain tables, for a system without BW on HANA (SAP ASE): fills ZZXXMLA1_FMSALES (the facts) and the
"! dimension tables ZZXXMLA1_FMPROD, _FMCUST, _FMSTORE, _FMPROMO and _FMDATE from the data classes
"! ZZXXMLA1_CL_FM_DATA_* (scripts/generate-foodmart-abap.py; third-party data, not part of the repository, so they are
"! called dynamically). The tables have the columns of the BW cube ZFMSALES's fact table and views, keyed by the
"! FoodMart ids as its SIDs, so reference/schema/FoodmartASE.xml is FoodmartBW.xml on these tables.
"! Run in ADT (F9): deletes the tables' rows, loads them and prints the row counts and the totals of the measures.
CLASS zzxxmla1_cl_fm_ase_load DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    "! Loads all tables; returns a line per table with its row count.
    CLASS-METHODS load
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_record TYPE STANDARD TABLE OF string_table WITH EMPTY KEY.

    "! The records of a data class, each split into its fields (a trailing empty field is missing: read with OPTIONAL).
    CLASS-METHODS records
      IMPORTING suffix        TYPE string
      RETURNING VALUE(result) TYPE ty_t_record.

    CLASS-METHODS field
      IMPORTING !record       TYPE string_table
                !index        TYPE i
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS number
      IMPORTING !record       TYPE string_table
                !index        TYPE i
      RETURNING VALUE(result) TYPE i.
ENDCLASS.



CLASS zzxxmla1_cl_fm_ase_load IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    TRY.
        LOOP AT load( ) INTO DATA(line).
          out->write( line ).
        ENDLOOP.
        SELECT SUM( units ) AS units, SUM( scost ) AS scost, SUM( ssales ) AS ssales
          FROM zzxxmla1_fmsales
          INTO @DATA(totals).
        out->write( |Totals: unit sales { totals-units }, store cost { totals-scost }, store sales { totals-ssales }| ).
      CATCH cx_root INTO DATA(error).
        out->write( |Error: { error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD load.
    DATA sales TYPE STANDARD TABLE OF zzxxmla1_fmsales WITH EMPTY KEY.
    DATA products TYPE STANDARD TABLE OF zzxxmla1_fmprod WITH EMPTY KEY.
    DATA customers TYPE STANDARD TABLE OF zzxxmla1_fmcust WITH EMPTY KEY.
    DATA stores TYPE STANDARD TABLE OF zzxxmla1_fmstore WITH EMPTY KEY.
    DATA promotions TYPE STANDARD TABLE OF zzxxmla1_fmpromo WITH EMPTY KEY.
    DATA days TYPE STANDARD TABLE OF zzxxmla1_fmdate WITH EMPTY KEY.

    " product_id, product_name, brand_name, product_subcategory, product_category, product_department, product_family
    LOOP AT records( `PRODUCT` ) INTO DATA(r).
      APPEND VALUE #( sid = number( record = r index = 1 ) zfmpname = field( record = r index = 2 )
                      zfmbrand = field( record = r index = 3 ) zfmsubct = field( record = r index = 4 )
                      zfmcateg = field( record = r index = 5 ) zfmdept = field( record = r index = 6 )
                      zfmfamily = field( record = r index = 7 ) ) TO products.
    ENDLOOP.
    " customer_id, fullname, country, state_province, city, gender, marital_status, education, yearly_income
    LOOP AT records( `CUSTOMER` ) INTO r.
      APPEND VALUE #( sid = number( record = r index = 1 ) zfmcname = field( record = r index = 2 )
                      zfmcntry = field( record = r index = 3 ) zfmstate = field( record = r index = 4 )
                      zfmcity = field( record = r index = 5 ) zfmgendr = field( record = r index = 6 )
                      zfmmarit = field( record = r index = 7 ) zfmedu = field( record = r index = 8 )
                      zfmincom = field( record = r index = 9 ) ) TO customers.
    ENDLOOP.
    " store_id, store_name, store_country, store_state, store_city, store_type, store_manager, store_sqft,
    " grocery_sqft, frozen_sqft, meat_sqft, coffee_bar, store_street_address
    LOOP AT records( `STORE` ) INTO r.
      APPEND VALUE #( sid = number( record = r index = 1 ) zfmsname = field( record = r index = 2 )
                      zfmcntry = field( record = r index = 3 ) zfmstate = field( record = r index = 4 )
                      zfmcity = field( record = r index = 5 ) zfmstype = field( record = r index = 6 )
                      zfmmgr = field( record = r index = 7 ) zfmsqft_int = number( record = r index = 8 )
                      zfmgsqft_int = number( record = r index = 9 ) zfmfsqft_int = number( record = r index = 10 )
                      zfmmsqft_int = number( record = r index = 11 ) zfmcoffe = field( record = r index = 12 )
                      zfmaddr = field( record = r index = 13 ) ) TO stores.
    ENDLOOP.
    " promotion_id, promotion_name, media_type
    LOOP AT records( `PROMO` ) INTO r.
      APPEND VALUE #( sid = number( record = r index = 1 ) zfmprnam = field( record = r index = 2 )
                      zfmmedia = field( record = r index = 3 ) ) TO promotions.
    ENDLOOP.
    " time_id, the_date, the_day, the_month, the_year, day_of_month, week_of_year, month_of_year, fiscal_period,
    " quarter
    LOOP AT records( `TIME` ) INTO r.
      APPEND VALUE #( sid = number( record = r index = 1 ) zfmthedt = field( record = r index = 2 )
                      zfmdaynm = field( record = r index = 3 ) zfmmonnm = field( record = r index = 4 )
                      zfmyear_int = number( record = r index = 5 ) zfmdayom_int = number( record = r index = 6 )
                      zfmweek_int = number( record = r index = 7 ) zfmmonth_int = number( record = r index = 8 )
                      zfmfiscp = field( record = r index = 9 ) zfmqtr = field( record = r index = 10 ) ) TO days.
    ENDLOOP.
    " product_id, time_id, customer_id, promotion_id, store_id, store_sales, store_cost, unit_sales
    LOOP AT records( `SALES` ) INTO r.
      APPEND VALUE #( rec = sy-tabix sid_zfmprod = number( record = r index = 1 )
                      sid_zfmdate = number( record = r index = 2 ) sid_zfmcust = number( record = r index = 3 )
                      sid_zfmpromo = number( record = r index = 4 ) sid_zfmstore = number( record = r index = 5 )
                      ssales = field( record = r index = 6 ) scost = field( record = r index = 7 )
                      units = field( record = r index = 8 ) ) TO sales.
    ENDLOOP.

    DELETE FROM zzxxmla1_fmsales.
    DELETE FROM zzxxmla1_fmprod.
    DELETE FROM zzxxmla1_fmcust.
    DELETE FROM zzxxmla1_fmstore.
    DELETE FROM zzxxmla1_fmpromo.
    DELETE FROM zzxxmla1_fmdate.
    INSERT zzxxmla1_fmprod FROM TABLE @products.
    INSERT zzxxmla1_fmcust FROM TABLE @customers.
    INSERT zzxxmla1_fmstore FROM TABLE @stores.
    INSERT zzxxmla1_fmpromo FROM TABLE @promotions.
    INSERT zzxxmla1_fmdate FROM TABLE @days.
    INSERT zzxxmla1_fmsales FROM TABLE @sales.
    COMMIT WORK.

    result = VALUE #( ( |ZZXXMLA1_FMSALES: { lines( sales ) } rows| )
                      ( |ZZXXMLA1_FMPROD: { lines( products ) } rows| )
                      ( |ZZXXMLA1_FMCUST: { lines( customers ) } rows| )
                      ( |ZZXXMLA1_FMSTORE: { lines( stores ) } rows| )
                      ( |ZZXXMLA1_FMPROMO: { lines( promotions ) } rows| )
                      ( |ZZXXMLA1_FMDATE: { lines( days ) } rows| ) ).
  ENDMETHOD.

  METHOD records.
    DATA chunks TYPE string_table.
    DATA(class_name) = |ZZXXMLA1_CL_FM_DATA_{ suffix }|.
    CALL METHOD (class_name)=>('GET_CHUNKS')
      RECEIVING
        rt_chunk = chunks.
    LOOP AT chunks INTO DATA(chunk).
      SPLIT chunk AT `~` INTO TABLE DATA(lines).
      LOOP AT lines INTO DATA(line).
        APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<record>).
        SPLIT line AT `|` INTO TABLE <record>.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD field.
    result = VALUE #( record[ index ] OPTIONAL ).
  ENDMETHOD.

  METHOD number.
    DATA(text) = field( record = record index = index ).
    result = COND #( WHEN text IS INITIAL THEN 0 ELSE CONV i( text ) ).
  ENDMETHOD.

ENDCLASS.
