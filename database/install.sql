SET DEFINE OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

@01_drop_objects.sql
@02_create_tables.sql
@03_insert_dictionaries.sql
@04_insert_cells.sql
@05_insert_chance_cards.sql
@06_create_types.sql
@07_package_spec.sql
@08_package_body.sql

COMMIT;

PROMPT Установка завершена.
