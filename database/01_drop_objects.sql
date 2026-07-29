BEGIN
  BEGIN EXECUTE IMMEDIATE 'DROP PACKAGE monopoly'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP TYPE number_list FORCE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN (
    'NETWORK_TEST_MESSAGES','ЧАТ','ЖУРНАЛ_ДЕЙСТВИЙ','СТАВКИ','АУКЦИОНЫ','ВЛАДЕНИЯ','КАРТЫ_ШАНСА','УЧАСТНИКИ','ИГРЫ','КЛЕТКИ','ПОЛЬЗОВАТЕЛИ','СОСТОЯНИЯ_ХОДА','ТИПЫ_ДЕЙСТВИЙ','СТАТУСЫ_АУКЦИОНОВ','СТАТУСЫ_УЧАСТНИКОВ','СТАТУСЫ_ИГР')) LOOP
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE "'||t.table_name||'" CASCADE CONSTRAINTS PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
END;
/
