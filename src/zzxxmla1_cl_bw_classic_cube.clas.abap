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
"! A standard (classic) InfoCube as a flat one. BW on a database other than HANA (SAP ASE) has no HANA-optimised
"! InfoCubes: a standard InfoCube's fact tables F and E hold one DIMID per dimension (KEY_<dimension>), and the
"! dimension tables (RSDDIME-TABLNM) the SIDs of its characteristics (SID_<characteristic>,
"! RSD_SIDNM_GET_FROM_IOBJNM); a line-item dimension's DIMID is the SID itself. The flat facts are a CDS view of both
"! fact tables (UNION ALL) joined to the dimensions: per characteristic its SID column under BW's name, per key figure
"! its field, the columns of a HANA-optimised InfoCube's fact table, so ZZXXMLA1_CL_BW_PROVIDER and
"! ZZXXMLA1_CL_BW_VIEW_GEN take the view as the cube's fact table and need nothing else. The package dimension is
"! left out (requests, record type, change run). The view (DDL ZZXXMLA1_K_<cube>, database view ZZXXMLA1Knnnnnnn) is
"! in $TMP and a row of ZZXXMLA1_VIEW of kind K; it is generated on first use and again when it is no longer active.
CLASS zzxxmla1_cl_bw_classic_cube DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_kind TYPE c LENGTH 1 VALUE 'K'.

    "! True for an active standard InfoCube (RSDCUBE type B, no subtype).
    CLASS-METHODS is_classic
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

    "! The database view of the flat facts of a standard InfoCube; with generate, generated if it is missing or
    "! inactive. Initial if the cube is no standard InfoCube, or if there is no view and generate is off.
    "! @raising zzxxmla1_cx_bw_provider | the view cannot be generated
    CLASS-METHODS flat_facts
      IMPORTING cube          TYPE csequence
                !generate     TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_bw_provider.

    "! The DDL source of the flat facts view (for tests and the generation).
    "! @raising zzxxmla1_cx_bw_provider | the cube has no fact table or no characteristic
    CLASS-METHODS ddl_source
      IMPORTING cube          TYPE csequence
                ddl_name      TYPE csequence
                view_name     TYPE csequence
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_bw_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_ddl_prefix TYPE string VALUE `ZZXXMLA1_K_`.
    CONSTANTS c_view_prefix TYPE string VALUE `ZZXXMLA1K`.

    TYPES:
      BEGIN OF ty_join,
        alias TYPE string,
        table TYPE string,
        key   TYPE string,   " the fact table's DIMID column
      END OF ty_join,
      ty_t_join TYPE STANDARD TABLE OF ty_join WITH EMPTY KEY.

    CLASS-METHODS table_fields
      IMPORTING !table        TYPE csequence
      RETURNING VALUE(result) TYPE string_table.

    "! The E table of a fact table: /BIC/FCUBE -> /BIC/ECUBE (BW's naming); initial if the DDIC has none.
    CLASS-METHODS e_table
      IMPORTING f_table       TYPE csequence
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS fail
      IMPORTING !text TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
ENDCLASS.



CLASS zzxxmla1_cl_bw_classic_cube IMPLEMENTATION.

  METHOD is_classic.
    DATA name TYPE rsinfocube.
    name = to_upper( cube ).
    SELECT SINGLE infocube FROM rsdcube
      WHERE infocube = @name AND objvers = 'A' AND cubetype = 'B' AND cubesubtype = @space
      INTO @DATA(found).
    result = xsdbool( sy-subrc = 0 AND found IS NOT INITIAL ).
  ENDMETHOD.

  METHOD flat_facts.
    IF is_classic( cube ) = abap_false.
      RETURN.
    ENDIF.
    DATA(name) = CONV zzxxmla1_view-object_name( to_upper( cube ) ).
    SELECT SINGLE view_name, ddl_name FROM zzxxmla1_view
      WHERE kind = @c_kind AND object_name = @name
      INTO @DATA(row).
    IF sy-subrc = 0.
      SELECT SINGLE tabname FROM dd02l WHERE tabname = @row-view_name AND as4local = 'A' INTO @DATA(active).
      IF sy-subrc = 0 AND active IS NOT INITIAL.
        result = row-view_name.
        RETURN.
      ENDIF.
    ENDIF.
    IF generate = abap_false.
      RETURN.
    ENDIF.

    " names: the DDL after the cube, the database view numbered (16 characters at most)
    DATA(ddl_name) = CONV ddlname( c_ddl_prefix && replace( val = to_upper( cube ) sub = `/` with = `_` occ = 0 ) ).
    DATA(view_name) = CONV string( row-view_name ).
    IF view_name IS INITIAL.
      SELECT view_name FROM zzxxmla1_view WHERE kind = @c_kind INTO TABLE @DATA(views).
      DATA(number) = lines( views ) + 1.
      DO.
        view_name = |{ c_view_prefix }{ number WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
        IF NOT line_exists( views[ view_name = view_name ] ).
          EXIT.
        ENDIF.
        number = number + 1.
      ENDDO.
    ENDIF.
    DATA(source) = ddl_source( cube = cube ddl_name = ddl_name view_name = view_name ).

    TRY.
        DATA(handler) = cl_dd_ddl_handler_factory=>create( ).
        handler->save( name         = ddl_name
                       put_state    = 'N'
                       ddddlsrcv_wa = VALUE #( ddlname    = ddl_name
                                               ddlanguage = sy-langu
                                               ddtext     = |BW classic InfoCube { name }: flat facts|
                                               source     = source ) ).
        cl_dd_ddl_handler=>if_dd_ddl_handler~write_tadir( objectname = ddl_name devclass = '$TMP' prid = -1 ).
        handler->activate( ddl_name ).
      CATCH cx_dd_ddl_exception INTO DATA(error).
        fail( |InfoCube { name }: the view of its flat facts cannot be generated: { error->get_text( ) }| ).
    ENDTRY.
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @view_name AND as4local = 'A' INTO @DATA(generated).
    IF sy-subrc <> 0 OR generated IS INITIAL.
      fail( |InfoCube { name }: the view { view_name } of its flat facts did not activate (DDL { ddl_name })| ).
    ENDIF.
    DATA(registry) = VALUE zzxxmla1_view( kind        = c_kind
                                          object_name = name
                                          view_name   = view_name
                                          ddl_name    = ddl_name
                                          changed_by  = sy-uname ).
    GET TIME STAMP FIELD registry-changed_at.
    DELETE FROM zzxxmla1_view WHERE kind = @c_kind AND object_name = @name.
    INSERT zzxxmla1_view FROM @registry.
    result = view_name.
  ENDMETHOD.

  METHOD ddl_source.
    DATA cube_name TYPE rsinfocube.
    DATA fact_table TYPE rsd_s_cube-facttab.
    DATA sid_column TYPE rs_char30.
    cube_name = to_upper( cube ).
    CALL FUNCTION 'RSD_FACTTAB_GET_FOR_CUBE'
      EXPORTING
        i_infocube = cube_name
      IMPORTING
        e_facttab  = fact_table
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0 OR fact_table IS INITIAL.
      fail( |InfoCube { cube_name } has no fact table| ).
    ENDIF.
    DATA(f_fields) = table_fields( fact_table ).

    " the dimensions (not the package dimension) with their characteristics
    SELECT dimension, linitfl, tablnm FROM rsddime
      WHERE infocube = @cube_name AND objvers = 'A' AND iobjtp <> 'DPA'
      ORDER BY posit ASCENDING
      INTO TABLE @DATA(dimensions).
    DATA(joins) = VALUE ty_t_join( ).
    DATA(columns) = VALUE string_table( ).
    LOOP AT dimensions INTO DATA(dimension).
      DATA(key) = |KEY_{ replace( val = dimension-dimension sub = `/` with = `` occ = 0 ) }|.
      IF NOT line_exists( f_fields[ table_line = key ] ).
        CONTINUE.
      ENDIF.
      SELECT d~iobjnm FROM rsddimeiobj AS d
        INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
        WHERE d~infocube = @cube_name AND d~dimension = @dimension-dimension AND d~objvers = 'A'
          AND ( o~iobjtp = 'CHA' OR o~iobjtp = 'TIM' OR o~iobjtp = 'UNI' )
        ORDER BY d~iobjnm ASCENDING
        INTO TABLE @DATA(characteristics).
      IF characteristics IS INITIAL.
        CONTINUE.
      ENDIF.
      IF dimension-linitfl = abap_true.
        " a line-item dimension: the fact table's key column is the SID of its one characteristic
        CLEAR sid_column.
        CALL FUNCTION 'RSD_SIDNM_GET_FROM_IOBJNM'
          EXPORTING
            i_iobjnm     = characteristics[ 1 ]-iobjnm
          IMPORTING
            e_sidfieldnm = sid_column
          EXCEPTIONS
            OTHERS       = 1.
        IF sy-subrc = 0 AND sid_column IS NOT INITIAL.
          APPEND |f.{ to_lower( key ) } as { to_lower( sid_column ) }| TO columns.
        ENDIF.
        CONTINUE.
      ENDIF.
      DATA(d_fields) = table_fields( dimension-tablnm ).
      DATA(alias) = |d{ lines( joins ) + 1 }|.
      DATA(used) = abap_false.
      LOOP AT characteristics INTO DATA(characteristic).
        CLEAR sid_column.
        CALL FUNCTION 'RSD_SIDNM_GET_FROM_IOBJNM'
          EXPORTING
            i_iobjnm     = characteristic-iobjnm
          IMPORTING
            e_sidfieldnm = sid_column
          EXCEPTIONS
            OTHERS       = 1.
        IF sy-subrc = 0 AND sid_column IS NOT INITIAL AND line_exists( d_fields[ table_line = sid_column ] ).
          APPEND |{ alias }.{ to_lower( sid_column ) } as { to_lower( sid_column ) }| TO columns.
          used = abap_true.
        ENDIF.
      ENDLOOP.
      IF used = abap_true.
        APPEND VALUE #( alias = alias table = to_lower( dimension-tablnm ) key = to_lower( key ) ) TO joins.
      ENDIF.
    ENDLOOP.
    IF columns IS INITIAL.
      fail( |InfoCube { cube_name }: no characteristic found in its dimensions| ).
    ENDIF.

    " the key figures: their fields in the fact table
    SELECT o~fieldnm FROM rsdcubeiobj AS c
      INNER JOIN rsdiobj AS o ON o~iobjnm = c~iobjnm AND o~objvers = 'A'
      WHERE c~infocube = @cube_name AND c~objvers = 'A' AND o~iobjtp = 'KYF'
      ORDER BY o~fieldnm ASCENDING
      INTO TABLE @DATA(key_figures).
    LOOP AT key_figures INTO DATA(key_figure).
      IF line_exists( f_fields[ table_line = CONV string( key_figure-fieldnm ) ] ).
        APPEND |f.{ to_lower( key_figure-fieldnm ) } as { to_lower( key_figure-fieldnm ) }| TO columns.
      ENDIF.
    ENDLOOP.

    " one branch per fact table: F (requests not compressed) and, where the DDIC has it, E (compressed)
    DATA(fact_tables) = VALUE string_table( ( to_lower( fact_table ) ) ).
    DATA(e_table) = e_table( fact_table ).
    IF e_table IS NOT INITIAL.
      APPEND to_lower( e_table ) TO fact_tables.
    ENDIF.
    DATA(branches) = VALUE string_table( ).
    LOOP AT fact_tables INTO DATA(table).
      DATA(branch) = |  select from { table } as f|.
      LOOP AT joins INTO DATA(join).
        branch = |{ branch }\n    inner join { join-table } as { join-alias } on { join-alias }.dimid = f.{ join-key }|.
      ENDLOOP.
      branch = |{ branch }\n  \{\n    { concat_lines_of( table = columns sep = |,\n    | ) }\n  \}|.
      APPEND branch TO branches.
    ENDLOOP.
    result = |@AbapCatalog.sqlViewName: '{ to_upper( view_name ) }'\n| &&
             |@AbapCatalog.compiler.compareFilter: true\n| &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED\n| &&
             |@EndUserText.label: 'BW classic InfoCube { cube_name }: flat facts'\n| &&
             |define view { to_lower( ddl_name ) } as\n| &&
             |{ concat_lines_of( table = branches sep = |\nunion all\n| ) }\n|.
  ENDMETHOD.

  METHOD table_fields.
    DATA(name) = CONV tabname( to_upper( table ) ).
    SELECT fieldname FROM dd03l
      WHERE tabname = @name AND as4local = 'A' AND fieldname NOT LIKE '.%'
      ORDER BY position ASCENDING
      INTO TABLE @DATA(fields).
    result = VALUE #( FOR f IN fields ( CONV string( f-fieldname ) ) ).
  ENDMETHOD.

  METHOD e_table.
    " the letter after the namespace: /BIC/F..., /BI0/F..., /ABC/F...
    DATA(name) = to_upper( f_table ).
    DATA(slash) = find( val = name sub = `/` off = 1 ).
    IF slash < 0 OR strlen( name ) <= slash + 1 OR substring( val = name off = slash + 1 len = 1 ) <> `F`.
      RETURN.
    ENDIF.
    DATA(candidate) = CONV tabname( |{ substring( val = name len = slash + 1 ) }E{ substring( val = name off = slash + 2 ) }| ).
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @candidate AND as4local = 'A' INTO @DATA(found).
    IF sy-subrc = 0.
      result = found.
    ENDIF.
  ENDMETHOD.

  METHOD fail.
    RAISE EXCEPTION TYPE zzxxmla1_cx_bw_provider EXPORTING error_message = text.
  ENDMETHOD.

ENDCLASS.
