SET SERVEROUTPUT ON
DECLARE u1 NUMBER; u2 NUMBER; g NUMBER;
BEGIN
 BEGIN monopoly.register_user('test_user_1','123'); EXCEPTION WHEN OTHERS THEN NULL; END;
 BEGIN monopoly.register_user('test_user_2','123'); EXCEPTION WHEN OTHERS THEN NULL; END;
 u1:=monopoly.authenticate_user('test_user_1','123'); u2:=monopoly.authenticate_user('test_user_2','123');
 monopoly.create_game(u1,'Тестовая игра',2,NULL,g); monopoly.join_game(u2,g,NULL); monopoly.request_start(g,u1);
 UPDATE "УЧАСТНИКИ" SET "ГОТОВ"=1 WHERE "ID_ИГРЫ"=g; monopoly.start_game(g,u1); COMMIT;
 DBMS_OUTPUT.PUT_LINE('Создана тестовая игра ID='||g);
END;
/
SELECT COUNT(*) AS cells_count FROM "КЛЕТКИ";
SELECT COUNT(*) AS cards_count FROM "КАРТЫ_ШАНСА";
SELECT object_name,status FROM user_objects WHERE object_name='MONOPOLY';
