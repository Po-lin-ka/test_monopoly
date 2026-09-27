-- Удаление объектов проекта под пользователем KS2318_03.
-- SQL Developer: выполнить как скрипт (F5).
-- ВНИМАНИЕ: таблицы удаляются вместе с данными без возможности ROLLBACK.
-- Пакет удаляется вместе с телом. Пользователь и остальные объекты сохраняются.
SET SERVEROUTPUT ON;

BEGIN
  IF USER <> 'KS2318_03' THEN
    RAISE_APPLICATION_ERROR(-20001,
      'Нужно подключиться под KS2318_03. Сейчас: ' || USER);
  END IF;

  FOR p IN (
    SELECT object_name
    FROM user_objects
    WHERE object_type = 'PACKAGE'
      AND object_name = 'MONOPOLY'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP PACKAGE KS2318_03.MONOPOLY';
    DBMS_OUTPUT.PUT_LINE('Удалён пакет MONOPOLY');
  END LOOP;

  FOR t IN (
    SELECT table_name
    FROM user_tables
    WHERE table_name IN (
      'СТАТУСЫ_ИГР',
      'СТАТУСЫ_УЧАСТНИКОВ',
      'СТАТУСЫ_АУКЦИОНОВ',
      'ТИПЫ_ДЕЙСТВИЙ',
      'СОСТОЯНИЯ_ХОДА',
      'ПОЛЬЗОВАТЕЛИ',
      'КЛЕТКИ',
      'ИГРЫ',
      'УЧАСТНИКИ',
      'КАРТЫ_ШАНСА',
      'ВЛАДЕНИЯ',
      'АУКЦИОНЫ',
      'СТАВКИ',
      'ЖУРНАЛ_ДЕЙСТВИЙ',
      'ЧАТ'
    )
  ) LOOP
    EXECUTE IMMEDIATE
      'DROP TABLE KS2318_03."' || t.table_name ||
      '" CASCADE CONSTRAINTS PURGE';
    DBMS_OUTPUT.PUT_LINE('Удалена таблица ' || t.table_name);
  END LOOP;

  FOR t IN (
    SELECT type_name
    FROM user_types
    WHERE type_name = 'NUMBER_LIST'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TYPE KS2318_03.NUMBER_LIST';
    DBMS_OUTPUT.PUT_LINE('Удалён тип NUMBER_LIST');
  END LOOP;
END;
/

-- Объекты, оставшиеся у подключённого пользователя.
SELECT object_type, object_name
FROM user_objects
ORDER BY object_type, object_name;
