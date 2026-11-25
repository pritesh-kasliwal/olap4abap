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
"! The key date of a request (docs/sap-ase.md, Key date): the date BW's time-dependent hierarchies are served at
"! (ZZXXMLA1_CL_SCHEMA=>set_key_date), as BW's queries take one (today unless given). An XMLA request names it as the
"! property KeyDate (Discover or Execute Properties), else the endpoint's URL as the parameter keyDate
"! (/zzxxmla1?keyDate=2024-06-15), else it is today. YYYY-MM-DD or YYYYMMDD; another value is a fault of the request.
"! The views' time-dependent attributes and texts stay at 9999-12-31 (ZZXXMLA1_CL_BW_VIEW_GEN, generated views).
CLASS zzxxmla1_cl_key_date DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_property TYPE string VALUE `KeyDate`.

    "! The key date of a request: property (the value of the XMLA property KeyDate), else url_value (the URL's
    "! parameter keyDate), else today.
    "! @raising cx_abap_datfm | a value that is no date
    CLASS-METHODS of_request
      IMPORTING property      TYPE csequence OPTIONAL
                url_value     TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE d
      RAISING   cx_abap_datfm.

    "! A date given as YYYY-MM-DD or YYYYMMDD, blanks ignored; initial for an empty value.
    CLASS-METHODS parse
      IMPORTING value         TYPE csequence
      RETURNING VALUE(result) TYPE d
      RAISING   cx_abap_datfm.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cl_key_date IMPLEMENTATION.

  METHOD of_request.
    result = parse( property ).
    IF result IS INITIAL.
      result = parse( url_value ).
    ENDIF.
    IF result IS INITIAL.
      result = sy-datum.
    ENDIF.
  ENDMETHOD.

  METHOD parse.
    DATA(text) = condense( val = replace( val = value sub = `-` with = `` occ = 0 ) del = ` ` ).
    IF text IS INITIAL.
      RETURN.
    ENDIF.
    IF strlen( text ) <> 8 OR text CN `0123456789`.
      RAISE EXCEPTION TYPE cx_abap_datfm_format_unknown.
    ENDIF.
    result = text.
    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date                      = result
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_abap_datfm_invalid_date.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
