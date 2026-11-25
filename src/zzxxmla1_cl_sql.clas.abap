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
"! Native SQL on the database of the system (HANA; SAP ASE through the dialect methods is_hana, limit, to_string,
"! columns_sql, grouping_sets_supported) through ADBC, as the reference runs its SQL through JDBC: the engine
"! builds the statements itself (docs/mvp-scope.md, schema decision). Every column is read as a string; a number
"! arrives in its plain form with the scale of its type, as Java's BigDecimal.toString writes it (1997 for INTEGER or
"! DECIMAL(31,0), 2.500000 for 2.5 as DECIMAL(28,6)).
CLASS zzxxmla1_cl_sql DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_row TYPE STANDARD TABLE OF string_table WITH EMPTY KEY.
    "! The values bound to the parameters (?) of a statement, one per parameter in their order. HANA reuses a plan
    "! only for the same statement text, so a statement run often with other single values binds them
    "! (docs/next-steps.md, Statements and HANA's plan cache).
    TYPES ty_t_param TYPE STANDARD TABLE OF REF TO data WITH EMPTY KEY.

    "! The statements query has run since the last reset_statistics, and their time in microseconds (the trace of a
    "! call records them, ZZXXMLA1_CL_TRACE).
    CLASS-DATA statement_count TYPE i READ-ONLY.
    CLASS-DATA statement_time TYPE int8 READ-ONLY.
    "! Set: query keeps each statement with its rows and microseconds in statement_log (for measurements and the
    "! trace of a call), a statement that fails with its error and no rows.
    CLASS-DATA log_statements TYPE abap_bool.
    "! What the caller is doing while statements are logged, kept with each statement: a phase (the MDX engine: the
    "! slicer, an axis, the cells; ZZXXMLA1_CL_MDX_EXPLAIN) and a node of what it evaluates (0: none). The caller sets
    "! and restores them; reset_statistics clears them.
    CLASS-DATA log_phase TYPE string.
    CLASS-DATA log_node TYPE i.
    TYPES:
      BEGIN OF ty_logged,
        sql   TYPE string,
        rows  TYPE i,
        time  TYPE int8,
        error TYPE string,
        phase TYPE string,
        node  TYPE i,
      END OF ty_logged.
    CLASS-DATA statement_log TYPE STANDARD TABLE OF ty_logged WITH EMPTY KEY READ-ONLY.

    "! The rows of a query with the given number of columns, each row the values of its columns in order. A database
    "! error raises ZZXXMLA1_CX_SQL (unchecked).
    CLASS-METHODS query
      IMPORTING !sql          TYPE string
                !columns      TYPE i
                !params       TYPE ty_t_param OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_row.
    "! Fetches the rows of a query into a standard table of a structure with a component per column, in their order
    "! (ADBC converts each value to its component's type): a reader of many rows (a grid's statement has some hundred
    "! thousand) reads them typed, not copied into a table per row as query gives them. A database error raises
    "! ZZXXMLA1_CX_SQL (unchecked).
    CLASS-METHODS fetch
      IMPORTING !sql    TYPE string
                !rows   TYPE REF TO data
                !params TYPE ty_t_param OPTIONAL.
    "! Runs a statement that changes data (INSERT, UPDATE, DELETE) and returns the number of rows it changed; the
    "! caller commits. A database error raises ZZXXMLA1_CX_SQL (unchecked).
    CLASS-METHODS execute
      IMPORTING !sql          TYPE string
                !params       TYPE ty_t_param OPTIONAL
      RETURNING VALUE(result) TYPE i.
    "! Sets statement_count and statement_time to 0, empties statement_log and clears log_phase and log_node.
    CLASS-METHODS reset_statistics.
    "! An identifier as a quoted SQL identifier, e.g. "/BIC/FZFMSALES".
    CLASS-METHODS quote
      IMPORTING identifier    TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! A value as a SQL string literal, e.g. 'O''Brien'.
    CLASS-METHODS literal
      IMPORTING value         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The condition that a column holds a key as query reads it: equal to it, or for an empty key NULL or empty (a
    "! NULL column is read as an empty string; the column may be a number, so the empty case compares its text).
    CLASS-METHODS key_condition
      IMPORTING column        TYPE csequence
                key           TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The condition that a column holds one of the keys (a ListColumnPredicate): key_condition for one key, else an IN
    "! list of the keys that are not empty, ORed with the empty case if one is.
    CLASS-METHODS keys_condition
      IMPORTING column        TYPE csequence
                keys          TYPE string_table
      RETURNING VALUE(result) TYPE string.

    " SQL dialect. The engine writes HANA's SQL; on another database of the SAP system (SAP ASE) the few constructs
    " that differ are written by these methods. The database is sy-dbsys, a system field: asking costs nothing.
    "! True on HANA (sy-dbsys HDB), false on any other database (SAP ASE: SYBASE).
    CLASS-METHODS is_hana
      RETURNING VALUE(result) TYPE abap_bool.
    "! True where the database groups by GROUPING SETS with GROUPING_ID (HANA). Elsewhere the callers read each
    "! grouping set with a statement of its own, as the reference does.
    CLASS-METHODS grouping_sets_supported
      RETURNING VALUE(result) TYPE abap_bool.
    "! The clause that limits a statement's rows, with a leading blank: HANA ` LIMIT n OFFSET m`, ASE
    "! ` ROWS LIMIT n OFFSET m`; no offset for 0.
    CLASS-METHODS limit
      IMPORTING !limit        TYPE i
                !offset       TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE string.
    "! An expression converted to a string: HANA TO_NVARCHAR( x ), ASE CAST( x AS VARCHAR(n) ).
    CLASS-METHODS to_string
      IMPORTING expression    TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! A statement giving per column of the named tables and views of the schema its table name, column name, data
    "! type in HANA's names (NVARCHAR, DECIMAL, INTEGER, BIGINT, DOUBLE, DATE, ...) and, with with_size, its scale
    "! and length as strings. names: the SQL literals of the names, comma separated.
    CLASS-METHODS columns_sql
      IMPORTING names         TYPE string
                with_size     TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_ase_string_length TYPE i VALUE 1333.
    "! The statement as statement_log keeps it: with the bound values after it (/* ? = -2, 5 */).
    CLASS-METHODS logged_text
      IMPORTING !sql          TYPE string
                !params       TYPE ty_t_param
      RETURNING VALUE(result) TYPE string.
    "! Records a statement that ran: statement_count, statement_time and, while statements are logged, statement_log.
    CLASS-METHODS record
      IMPORTING !sql    TYPE string
                !params TYPE ty_t_param
                !rows   TYPE i
                !time   TYPE int8
                !error  TYPE string OPTIONAL.
ENDCLASS.



CLASS zzxxmla1_cl_sql IMPLEMENTATION.

  METHOD query.
    " the rows are fetched into a table of a structure with one string component per column
    DATA(components) = VALUE cl_abap_structdescr=>component_table( ).
    DO columns TIMES.
      APPEND VALUE #( name = |C{ sy-index }| type = cl_abap_elemdescr=>get_string( ) ) TO components.
    ENDDO.
    DATA(table_type) = cl_abap_tabledescr=>create( cl_abap_structdescr=>create( components ) ).
    DATA rows TYPE REF TO data.
    CREATE DATA rows TYPE HANDLE table_type.
    fetch( sql = sql rows = rows params = params ).
    FIELD-SYMBOLS <rows> TYPE STANDARD TABLE.
    ASSIGN rows->* TO <rows>.
    " each row's values appended to its line of the result in place, not to a table of its own copied there
    LOOP AT <rows> ASSIGNING FIELD-SYMBOL(<row>).
      APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<values>).
      DO columns TIMES.
        ASSIGN COMPONENT sy-index OF STRUCTURE <row> TO FIELD-SYMBOL(<value>).
        APPEND <value> TO <values>.
      ENDDO.
    ENDLOOP.
    FREE <rows>.
  ENDMETHOD.

  METHOD fetch.
    FIELD-SYMBOLS <rows> TYPE STANDARD TABLE.
    ASSIGN rows->* TO <rows>.
    GET RUN TIME FIELD DATA(started).
    TRY.
        DATA(statement) = NEW cl_sql_statement( ).
        LOOP AT params INTO DATA(param).
          statement->set_param( param ).
        ENDLOOP.
        DATA(result_set) = statement->execute_query( sql ).
        result_set->set_param_table( rows ).
        result_set->next_package( ).
        result_set->close( ).
      CATCH cx_sql_exception INTO DATA(error).
        GET RUN TIME FIELD DATA(failed).
        record( sql = sql params = params rows = 0 time = failed - started error = error->get_text( ) ).
        RAISE EXCEPTION TYPE zzxxmla1_cx_sql
          EXPORTING
            statement     = logged_text( sql = sql params = params )
            error_message = error->get_text( )
            previous      = error.
    ENDTRY.
    GET RUN TIME FIELD DATA(stopped).
    record( sql = sql params = params rows = lines( <rows> ) time = stopped - started ).
  ENDMETHOD.

  METHOD execute.
    GET RUN TIME FIELD DATA(started).
    TRY.
        DATA(statement) = NEW cl_sql_statement( ).
        LOOP AT params INTO DATA(param).
          statement->set_param( param ).
        ENDLOOP.
        result = statement->execute_update( sql ).
      CATCH cx_sql_exception INTO DATA(error).
        GET RUN TIME FIELD DATA(failed).
        record( sql = sql params = params rows = 0 time = failed - started error = error->get_text( ) ).
        RAISE EXCEPTION TYPE zzxxmla1_cx_sql
          EXPORTING
            statement     = logged_text( sql = sql params = params )
            error_message = error->get_text( )
            previous      = error.
    ENDTRY.
    GET RUN TIME FIELD DATA(stopped).
    record( sql = sql params = params rows = result time = stopped - started ).
  ENDMETHOD.

  METHOD record.
    IF error IS INITIAL.
      statement_count = statement_count + 1.
      statement_time = statement_time + time.
    ENDIF.
    IF log_statements = abap_true.
      APPEND VALUE #( sql   = logged_text( sql = sql params = params )
                      rows  = rows
                      time  = time
                      error = error
                      phase = log_phase
                      node  = log_node ) TO statement_log.
    ENDIF.
  ENDMETHOD.

  METHOD logged_text.
    IF params IS INITIAL.
      result = sql.
      RETURN.
    ENDIF.
    DATA(values) = VALUE string_table( ).
    LOOP AT params INTO DATA(param).
      ASSIGN param->* TO FIELD-SYMBOL(<value>).
      APPEND |{ <value> }| TO values.
    ENDLOOP.
    result = |{ sql } /* ? = { concat_lines_of( table = values sep = `, ` ) } */|.
  ENDMETHOD.

  METHOD reset_statistics.
    CLEAR: statement_count, statement_time, statement_log, log_phase, log_node.
  ENDMETHOD.

  METHOD quote.
    result = `"` && replace( val = identifier sub = `"` with = `""` occ = 0 ) && `"`.
  ENDMETHOD.

  METHOD literal.
    result = `'` && replace( val = value sub = `'` with = `''` occ = 0 ) && `'`.
  ENDMETHOD.

  METHOD is_hana.
    result = xsdbool( sy-dbsys(3) = 'HDB' ).
  ENDMETHOD.

  METHOD grouping_sets_supported.
    result = is_hana( ).
  ENDMETHOD.

  METHOD limit.
    result = COND #( WHEN is_hana( ) = abap_true THEN | LIMIT { limit }| ELSE | ROWS LIMIT { limit }| ) &&
             COND #( WHEN offset > 0 THEN | OFFSET { offset }| ).
  ENDMETHOD.

  METHOD to_string.
    result = COND #( WHEN is_hana( ) = abap_true THEN |TO_NVARCHAR( { expression } )|
                     ELSE |CAST( { expression } AS VARCHAR({ c_ase_string_length }) )| ).
  ENDMETHOD.

  METHOD columns_sql.
    IF is_hana( ) = abap_true.
      DATA(size) = COND string( WHEN with_size = abap_true THEN `, TO_NVARCHAR( SCALE ), TO_NVARCHAR( LENGTH )` ).
      result = |SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE_NAME{ size } FROM SYS.TABLE_COLUMNS | &&
               |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME IN ( { names } ) UNION ALL | &&
               |SELECT VIEW_NAME, COLUMN_NAME, DATA_TYPE_NAME{ size } FROM SYS.VIEW_COLUMNS | &&
               |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME IN ( { names } )|.
      RETURN.
    ENDIF.
    " SAP ASE: the catalog of the database (tables U and views V of the SAP schema), its type names as HANA's
    DATA(type_name) = `CASE LOWER( t.name ) ` &&
      `WHEN 'varchar' THEN 'NVARCHAR' WHEN 'univarchar' THEN 'NVARCHAR' WHEN 'nvarchar' THEN 'NVARCHAR' ` &&
      `WHEN 'char' THEN 'NVARCHAR' WHEN 'unichar' THEN 'NVARCHAR' WHEN 'nchar' THEN 'NVARCHAR' ` &&
      `WHEN 'text' THEN 'NCLOB' WHEN 'unitext' THEN 'NCLOB' ` &&
      `WHEN 'decimal' THEN 'DECIMAL' WHEN 'numeric' THEN 'DECIMAL' WHEN 'decimaln' THEN 'DECIMAL' ` &&
      `WHEN 'numericn' THEN 'DECIMAL' WHEN 'int' THEN 'INTEGER' WHEN 'intn' THEN 'INTEGER' ` &&
      `WHEN 'bigint' THEN 'BIGINT' WHEN 'smallint' THEN 'SMALLINT' WHEN 'tinyint' THEN 'TINYINT' ` &&
      `WHEN 'float' THEN 'DOUBLE' WHEN 'floatn' THEN 'DOUBLE' WHEN 'double precision' THEN 'DOUBLE' ` &&
      `WHEN 'real' THEN 'REAL' WHEN 'date' THEN 'DATE' WHEN 'daten' THEN 'DATE' ` &&
      `WHEN 'varbinary' THEN 'VARBINARY' WHEN 'binary' THEN 'VARBINARY' WHEN 'image' THEN 'BLOB' ` &&
      `ELSE UPPER( t.name ) END`.
    result = |SELECT o.name, c.name, { type_name }| &&
             COND string( WHEN with_size = abap_true
                          THEN |, CAST( COALESCE( c.scale, 0 ) AS VARCHAR(10) ), CAST( c.length AS VARCHAR(10) )| ) &&
             | FROM syscolumns c INNER JOIN sysobjects o ON o.id = c.id| &&
             | INNER JOIN systypes t ON t.usertype = c.usertype| &&
             | WHERE o.type IN ( 'U', 'V' ) AND o.name IN ( { names } )|.
  ENDMETHOD.

  METHOD key_condition.
    IF key IS INITIAL.
      result = |COALESCE( { to_string( column ) }, '' ) = ''|.
    ELSE.
      result = |{ column } = { literal( key ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD keys_condition.
    IF lines( keys ) = 1.
      result = key_condition( column = column key = keys[ 1 ] ).
      RETURN.
    ENDIF.
    DATA(literals) = VALUE string_table( FOR k IN keys WHERE ( table_line IS NOT INITIAL ) ( literal( k ) ) ).
    DATA(conditions) = VALUE string_table( ).
    IF literals IS NOT INITIAL.
      APPEND |{ column } IN ( { concat_lines_of( table = literals sep = `, ` ) } )| TO conditions.
    ENDIF.
    IF line_exists( keys[ table_line = `` ] ).
      APPEND key_condition( column = column key = `` ) TO conditions.
    ENDIF.
    result = |( { concat_lines_of( table = conditions sep = ` OR ` ) } )|.
  ENDMETHOD.

ENDCLASS.
