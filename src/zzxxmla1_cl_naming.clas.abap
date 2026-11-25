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
"! The naming of hierarchies, the reference's property mondrian.olap.SsasCompatibleNaming, per data source: its
"! DataSourceInfo in /WEB-INF/datasources.xml names SsasCompatibleNaming=true (docs/sap-ase.md, SSAS naming).
"! Off (the default, the reference's): a hierarchy is [Dimension] when it has the dimension's name, else
"! [Dimension.Hierarchy], and [Dimension].[Name] is a level of the default hierarchy before a hierarchy of that name.
"! On (SSAS's): every hierarchy is [Dimension].[Hierarchy], members and levels carry it ([Time].[Time].[1997]), and
"! [Dimension].[Name] is the hierarchy of that name before a level. [Measures] keeps its name. Clients that build
"! names from the rowsets, as SSAS names them, need it on (the Syncfusion pivot in OLAP mode); Excel works either way.
"! ZZXXMLA1_CL_XMLA_HANDLER sets it for each request, before the schema is read.
CLASS zzxxmla1_cl_naming DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_property TYPE string VALUE `SsasCompatibleNaming`.

    "! True while SSAS naming is on.
    CLASS-METHODS ssas
      RETURNING VALUE(result) TYPE abap_bool.

    CLASS-METHODS set_ssas
      IMPORTING !on TYPE abap_bool.

    "! Whether a DataSourceInfo (the data source's connect string, pairs name=value separated by ;) switches SSAS
    "! naming on: SsasCompatibleNaming=true, names and values in any case.
    CLASS-METHODS ssas_in_data_source_info
      IMPORTING data_source_info TYPE csequence
      RETURNING VALUE(result)    TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA ssas_on TYPE abap_bool.
ENDCLASS.



CLASS zzxxmla1_cl_naming IMPLEMENTATION.

  METHOD ssas.
    result = ssas_on.
  ENDMETHOD.

  METHOD set_ssas.
    ssas_on = on.
  ENDMETHOD.

  METHOD ssas_in_data_source_info.
    SPLIT data_source_info AT `;` INTO TABLE DATA(pairs).
    LOOP AT pairs INTO DATA(pair).
      SPLIT pair AT `=` INTO DATA(name) DATA(value).
      IF to_upper( condense( name ) ) = to_upper( c_property ) AND to_upper( condense( value ) ) = `TRUE`.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
