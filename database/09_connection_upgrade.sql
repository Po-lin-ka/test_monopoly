-- Обновление без удаления таблиц и данных. Повторный запуск допустим.
DECLARE
   v_count NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_count FROM user_tab_columns
    WHERE table_name = 'УЧАСТНИКИ' AND column_name = 'ПОСЛЕДНЯЯ_СВЯЗЬ';
   IF v_count = 0 THEN
      EXECUTE IMMEDIATE 'ALTER TABLE "УЧАСТНИКИ" ADD ("ПОСЛЕДНЯЯ_СВЯЗЬ" DATE DEFAULT SYSDATE NOT NULL)';
   END IF;
END;
/
