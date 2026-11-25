# olap4abap on SAP ASE (BW without HANA)

olap4abap is built and tested on BW on HANA. This fork adds what it takes to run it on an SAP system whose database
is SAP ASE (Sybase), checked on NetWeaver 7.52 SP04 with BW 7.52 and SAP ASE 16.0 SP03. Everything runs on HANA as
before: the database is asked once per statement (`sy-dbsys`, a system field) and only the few constructs that
differ are written differently.

## What differs on ASE and how it is handled

| HANA construct | Where | On ASE |
|---|---|---|
| `LIMIT n OFFSET m` | member paging (`ZZXXMLA1_CL_MODEL`), native TopCount, drill-through (`ZZXXMLA1_CL_MDX_FACTS`) | `ROWS LIMIT n OFFSET m` (`ZZXXMLA1_CL_SQL=>limit`) |
| `TO_NVARCHAR( x )` | empty keys, label conditions | `CAST( x AS VARCHAR(1333) )` (`ZZXXMLA1_CL_SQL=>to_string`) |
| `SYS.TABLE_COLUMNS`, `SYS.VIEW_COLUMNS`, `CURRENT_SCHEMA` | column types of dimension tables and drill-through | `syscolumns` / `sysobjects` / `systypes`, type names as HANA's (`ZZXXMLA1_CL_SQL=>columns_sql`) |
| `GROUP BY GROUPING SETS`, `GROUPING_ID` | the cell reader's one statement per batch; cells first (`grid`) | each pattern read with a statement of its own, as the reference reads them; cells first skipped (the evaluator's way, same answer) (`ZZXXMLA1_CL_SQL=>grouping_sets_supported`) |

Not ported (HANA only): the copies of BW hierarchies (`ZZXXMLA1_CL_BW_HIERARCHY_COPY`: `ROW_NUMBER() OVER`, `WITH`)
and the check of analysis authorisations in SQL (`ZZXXMLA1_CL_BW_AUTH_SQL`). On ASE a schema names no BW hierarchy;
the clinic setup creates BW's hierarchies but does not tick them.

Checked with the SQL constructs SAP ASE accepts through ADBC: `||`, `LPAD`, `DUMMY`, `NULLIF`, `COALESCE`,
`LOWER ... LIKE`, derived tables and quoted names like `"/BIC/FZCLVISIT"` work as on HANA; `LIMIT`, `TO_NVARCHAR`,
`ROW_NUMBER() OVER`, `GROUPING SETS` and `WITH` do not.

## Standard InfoCubes

BW on ASE has no HANA-optimised InfoCubes. A standard InfoCube keeps a DIMID per dimension in its fact tables F and
E (`KEY_<dimension>`) and the SIDs of the characteristics in the dimension tables (`RSDDIME-TABLNM`); a line-item
dimension's DIMID is the SID. `ZZXXMLA1_CL_BW_CLASSIC_CUBE` generates a CDS view of the flat facts (DDL
`ZZXXMLA1_K_<cube>`, database view `ZZXXMLA1Knnnnnnn`, in `$TMP`, a row of `ZZXXMLA1_VIEW` of kind `K`): F and E
(`UNION ALL`) joined to the dimension tables, per characteristic its SID column under BW's name
(`RSD_SIDNM_GET_FROM_IOBJNM`), per key figure its field, without the package dimension. These are the columns of a
HANA-optimised InfoCube's fact table, so `ZZXXMLA1_CL_BW_PROVIDER` (which now lists and reads standard InfoCubes) and
`ZZXXMLA1_CL_BW_VIEW_GEN` take the view as the cube's fact table and nothing else changes: the proposal, accept,
the characteristics' views and the engine. Reading a cube generates the view; listing providers does not.

Checked: on `0D_NW_C01` the view gives the F table's rows and totals; the clinic InfoCube `ZCLVISIT` (created by the
setup, standard on ASE) is proposed, accepted and answers MDX through XMLA (its measures equal the fact table's sums).

## aDSOs

olap4abap reads a cube-type aDSO through its reporting view (`CL_RSO_ADSO=>GET_TABLNM`), which needs no SQL of HANA.
On the system checked, `CL_RSO_ADSO_API=>CREATE` (what the clinic and wide setups use) fails inside the API with a
null reference whatever the input, so the setup creates no aDSO there. An aDSO made in the BW Modeling Tools can be
proposed and accepted as on HANA; not checked yet on ASE.

## FoodMart without BW

`reference/schema/FoodmartASE.xml` is `FoodmartBW.xml` on plain tables: the facts in `ZZXXMLA1_FMSALES` (measures
`UNITS`, `SCOST`, `SSALES`) and the dimensions in `ZZXXMLA1_FMPROD`, `_FMCUST`, `_FMSTORE`, `_FMPROMO`, `_FMDATE`,
keyed by `SID` = the FoodMart id, with the columns of the BW cube's views. Same catalog (`ZFOODMART`), cube
(`ZFMSALES`), dimensions and names, so the FoodMart test statements apply; there is no member of SID 0.

1. `python scripts/export-foodmart-csv.py <hsqldb-foodmart.jar>` and `python scripts/generate-foodmart-abap.py`
   (third-party data: the CSVs and data classes stay out of the repository).
2. Create the classes `ZZXXMLA1_CL_FM_DATA_*` from `data/foodmart-abap/` and activate them.
3. Run `ZZXXMLA1_CL_FM_ASE_LOAD` (F9): loads the six tables and prints FoodMart's totals (unit sales 266,773, store
   cost 225,627.2336, store sales 565,238.13).
4. Write `reference/schema/datasources-ase.xml` as `/WEB-INF/datasources.xml` and `FoodmartASE.xml` as
   `/WEB-INF/schema/FoodmartASE.xml` (`ZZXXMLA1_CL_FILES=>write`, as `scripts/sap-files.py put` does).
5. Run `ZZXXMLA1_CL_ASE_SMOKE` (F9): XMLA requests to `ZZXXMLA1_CL_XMLA_HANDLER` without the ICF node, the answers
   in short.

## SSAS naming (any database)

The reference names hierarchies with `SsasCompatibleNaming=false` (`[Customers]`, `[Time.Weekly]`,
`[Time].[1997]`; `docs/next-steps.md`, Later). Clients that build names from the rowsets as SSAS names them, such as
the Syncfusion pivot in OLAP mode, cannot place such hierarchies. `ZZXXMLA1_CL_NAMING` switches SSAS naming on per
data source: its `DataSourceInfo` in `/WEB-INF/datasources.xml` names `SsasCompatibleNaming=true`, e.g.
`<DataSourceInfo>Provider=olap4abap;SsasCompatibleNaming=true</DataSourceInfo>` (writing the file clears the
Discover cache). `ZZXXMLA1_CL_XMLA_HANDLER` sets it for each request. With it on:

- every hierarchy is `[Dimension].[Hierarchy]` (`ZZXXMLA1_CL_MODEL=>hierarchy_unique_name`), `[Measures]` excepted,
  so members and levels carry it: `[Customers].[Customers].[USA]`, `[Time].[Time].[1997].[Q1]`;
- `[Dimension].[Name]` resolves to the hierarchy of that name before a level of the default hierarchy, as the
  reference's `DimensionBase.lookupChild` does with the property on (`ZZXXMLA1_CL_MDX_SCHEMA_READER`);
- a member's or level's hierarchy in a rowset restriction is its first two segments (`ZZXXMLA1_CL_XMLA_HANDLER`);
- `MEMBER_VALUE` among the `DIMENSION PROPERTIES` is written (the member's name), as SSAS writes it; the reference
  skips it and so does olap4abap with the switch off.

Off (the default) nothing changes, so the captured cases and the Mondrian test statements keep their expectations.
Not done: a dimension of several hierarchies named without its hierarchy, and the other differences the reference's
measurement lists (`docs/next-steps.md`); checked with FoodMart and the clinic InfoCube in the Syncfusion pivot.

## Installing on NetWeaver 7.52

The package activates on 7.52 without changes (ABAP Doc and other warnings only). The tables' abapGit files were
created there as DDL (`define table`) from the XML; the package `$ZZXXMLA1` with the ADT packages API, media type
`application/vnd.sap.adt.packages.v1+xml`. The ICF service `/zzxxmla1` (handler `ZZXXMLA1_MAIN_ENDPOINT`) is created
in SICF as on HANA.
