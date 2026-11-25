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
"! Smoke test of the engine on the database of the system without the ICF node: XMLA requests on catalog ZFOODMART
"! (on SAP ASE the plain FoodMart tables, reference/schema/FoodmartASE.xml) handed to ZZXXMLA1_CL_XMLA_HANDLER, and
"! per request its fault or a short form of its answer (the members of the axes and the cell values). Run in ADT (F9).
CLASS zzxxmla1_cl_ase_smoke DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_catalog TYPE string VALUE `ZFOODMART`.

    "! The answer of the handler to an Execute of the statement (or a Discover of the rowset), as text.
    CLASS-METHODS call
      IMPORTING !statement    TYPE string OPTIONAL
                !rowset       TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE string.

    "! Short form of an answer: its fault, or the captions of its members and the formatted values of its cells, or
    "! the cube names of a rowset.
    CLASS-METHODS summary
      IMPORTING answer        TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_ase_smoke IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( |Database: { sy-dbsys }, HANA dialect: { zzxxmla1_cl_sql=>is_hana( ) }| ).
    out->write( |MDSCHEMA_CUBES: { summary( call( rowset = `MDSCHEMA_CUBES` ) ) }| ).
    DATA(statements) = VALUE string_table(
      ( `SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON COLUMNS FROM [ZFMSALES]` )
      ( `SELECT {[Measures].[Unit Sales]} ON COLUMNS, [Store].[Store Country].Members ON ROWS FROM [ZFMSALES]` )
      ( `SELECT NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS, ` &&
        `NON EMPTY [Product].[Product Family].Members * [Customers].[Country].Members ON ROWS FROM [ZFMSALES]` )
      ( `SELECT {[Measures].[Store Cost]} ON COLUMNS, [Time].[1997].Children ON ROWS FROM [ZFMSALES] ` &&
        `WHERE [Store].[USA].[CA]` )
      ( `SELECT NON EMPTY TopCount([Product].[Brand Name].Members, 3, [Measures].[Unit Sales]) ON ROWS, ` &&
        `{[Measures].[Unit Sales]} ON COLUMNS FROM [ZFMSALES]` )
      ( `SELECT NON EMPTY ( ({DrilldownLevel({[Customers]},,,INCLUDE_CALC_MEMBERS)}) * ` &&
        `{{[Measures].[Unit Sales], [Measures].[Store Sales]}}) DIMENSION PROPERTIES PARENT_UNIQUE_NAME, ` &&
        `HIERARCHY_UNIQUE_NAME, CHILDREN_CARDINALITY, MEMBER_TYPE, MEMBER_VALUE ON COLUMNS, ` &&
        `NON EMPTY ( ({DrilldownLevel({[Product]},,,INCLUDE_CALC_MEMBERS)}) ) DIMENSION PROPERTIES ` &&
        `PARENT_UNIQUE_NAME, HIERARCHY_UNIQUE_NAME, CHILDREN_CARDINALITY, MEMBER_TYPE, MEMBER_VALUE ON ROWS ` &&
        `FROM [ZFMSALES] CELL PROPERTIES VALUE, FORMAT_STRING, FORMATTED_VALUE` ) ).
    LOOP AT statements INTO DATA(statement).
      out->write( |{ statement }| ).
      out->write( |  => { summary( call( statement = statement ) ) }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD call.
    DATA(body) = COND string(
      WHEN rowset IS NOT INITIAL
      THEN |<Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>{ rowset }</RequestType>| &&
           |<Restrictions><RestrictionList><CATALOG_NAME>{ c_catalog }</CATALOG_NAME></RestrictionList>| &&
           |</Restrictions><Properties><PropertyList><Catalog>{ c_catalog }</Catalog></PropertyList></Properties>| &&
           |</Discover>|
      ELSE |<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"><Command><Statement>| &&
           |{ escape( val = statement format = cl_abap_format=>e_xml_text ) }</Statement></Command>| &&
           |<Properties><PropertyList><Catalog>{ c_catalog }</Catalog><Format>Multidimensional</Format>| &&
           |<AxisFormat>TupleFormat</AxisFormat></PropertyList></Properties></Execute>| ).
    DATA(request) = |<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">| &&
                    |<SOAP-ENV:Body>{ body }</SOAP-ENV:Body></SOAP-ENV:Envelope>|.
    DATA(answer) = NEW zzxxmla1_cl_xmla_handler( )->handle( request = request url = `http://localhost/zzxxmla1` ).
    result = answer-body.
    LOOP AT answer-parts INTO DATA(part).
      result = result && cl_abap_codepage=>convert_from( source = part codepage = `UTF-8` ).
    ENDLOOP.
  ENDMETHOD.

  METHOD summary.
    FIND REGEX `<faultstring>([^<]*)` IN answer SUBMATCHES DATA(fault).
    IF sy-subrc = 0.
      result = |FAULT: { fault }|.
      RETURN.
    ENDIF.
    DATA(parts) = VALUE string_table( ).
    FIND ALL OCCURRENCES OF REGEX `<CUBE_NAME>([^<]*)` IN answer RESULTS DATA(cubes).
    LOOP AT cubes INTO DATA(cube).
      APPEND |cube { substring( val = answer off = cube-submatches[ 1 ]-offset len = cube-submatches[ 1 ]-length ) }|
             TO parts.
    ENDLOOP.
    FIND ALL OCCURRENCES OF REGEX `<Caption>([^<]*)` IN answer RESULTS DATA(captions).
    LOOP AT captions INTO DATA(caption) TO 12.
      APPEND substring( val = answer off = caption-submatches[ 1 ]-offset len = caption-submatches[ 1 ]-length )
             TO parts.
    ENDLOOP.
    FIND ALL OCCURRENCES OF REGEX `<FmtValue>([^<]*)` IN answer RESULTS DATA(values).
    APPEND |{ lines( captions ) } members, { lines( values ) } cells:| TO parts.
    LOOP AT values INTO DATA(value) TO 12.
      APPEND substring( val = answer off = value-submatches[ 1 ]-offset len = value-submatches[ 1 ]-length ) TO parts.
    ENDLOOP.
    result = concat_lines_of( table = parts sep = ` \| ` ).
    IF result IS INITIAL.
      result = substring( val = answer len = nmin( val1 = strlen( answer ) val2 = 400 ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
