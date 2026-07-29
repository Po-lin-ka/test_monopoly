create or replace package body monopoly as
   function participant_game (
      pid number
   ) return number is
      g number;
   begin
      select "ID_ИГРЫ"
        into g
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = pid;
      return g;
   exception
      when no_data_found then
         raise_application_error(
            -20001,
            'Участник не найден'
         );
   end;
   procedure add_action (
      p_game_id        number,
      p_participant_id number default null,
      p_cell_id        number default null,
      p_action_code    varchar2,
      p_amount         number default null,
      p_event_text     varchar2 default null
   ) is
      n number;
   begin
      if p_participant_id is not null then
         select count(*)
           into n
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = p_participant_id
            and "ID_ИГРЫ" = p_game_id;
         if n = 0 then
            raise_application_error(
               -20002,
               'Участник не относится к игре'
            );
         end if;
      end if;
      if p_cell_id is not null then
         select count(*)
           into n
           from "КЛЕТКИ"
          where "ID_КЛЕТКИ" = p_cell_id;
         if n = 0 then
            raise_application_error(
               -20003,
               'Клетка не найдена'
            );
         end if;
      end if;
      insert into "ЖУРНАЛ_ДЕЙСТВИЙ" (
         "ID_ИГРЫ",
         "ID_УЧАСТНИКА",
         "ID_КЛЕТКИ",
         "КОД_ДЕЙСТВИЯ",
         "СУММА",
         "ТЕКСТ_СОБЫТИЯ",
         "ДАТА_ВРЕМЯ"
      ) values
         ( p_game_id,
           p_participant_id,
           p_cell_id,
           p_action_code,
           p_amount,
           p_event_text,
           sysdate );
      update "ИГРЫ"
         set
         "ВЕРСИЯ_СОСТОЯНИЯ" = "ВЕРСИЯ_СОСТОЯНИЯ" + 1
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure return_properties_to_bank (
      p_participant_id number
   ) is
   begin
      update "ВЛАДЕНИЯ"
         set "ID_ВЛАДЕЛЬЦА" = null,
             "КОЛВО_ДОМОВ" = 0,
             "ЗАЛОЖЕНА" = 0
       where "ID_ВЛАДЕЛЬЦА" = p_participant_id;
   end;
   procedure enter_debt_or_bankruptcy (
      p_participant_id number
   ) is
      g         number;
      bal       number;
      available number;
   begin
      g := participant_game(p_participant_id);
      select "БАЛАНС"
        into bal
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      if bal >= 0 then
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = g;
         return;
      end if;
      select count(*)
        into available
        from "ВЛАДЕНИЯ"
       where "ID_ВЛАДЕЛЬЦА" = p_participant_id
         and ( "КОЛВО_ДОМОВ" > 0
          or ( "ЗАЛОЖЕНА" = 0
         and "КОЛВО_ДОМОВ" = 0 ) );
      if available = 0 then
         declare_bankruptcy(
            p_participant_id,
            c_bankruptcy_debt_timeout
         );
      else
         update "ИГРЫ"
            set "КОД_СОСТОЯНИЯ_ХОДА" = 'ПОКРЫТИЕ_ДОЛГА',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate
          where "ID_ИГРЫ" = g;
      end if;
   end;

   procedure register_user (
      p_login    varchar2,
      p_password varchar2
   ) is
      password_hash "ПОЛЬЗОВАТЕЛИ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      if trim(p_login) is null
      or p_password is null
      or length(p_password) = 0 then
         raise_application_error(
            -20010,
            'Логин и пароль обязательны'
         );
      end if;
      select rawtohex(standard_hash(
         p_password,
         'SHA256'
      ))
        into password_hash
        from dual;
      insert into "ПОЛЬЗОВАТЕЛИ" (
         "ЛОГИН",
         "ПАРОЛЬ_ХЭШ",
         "ДАТА_РЕГИСТРАЦИИ"
      ) values
         ( trim(p_login),
           password_hash,
           sysdate );
   exception
      when dup_val_on_index then
         raise_application_error(
            -20011,
            'Логин уже занят'
         );
   end;
   function authenticate_user (
      p_login    varchar2,
      p_password varchar2
   ) return number is
      id            number;
      password_hash "ПОЛЬЗОВАТЕЛИ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      select rawtohex(standard_hash(
         p_password,
         'SHA256'
      ))
        into password_hash
        from dual;
      select "ID_ПОЛЬЗОВАТЕЛЯ"
        into id
        from "ПОЛЬЗОВАТЕЛИ"
       where "ЛОГИН" = trim(p_login)
         and "ПАРОЛЬ_ХЭШ" = password_hash;
      return id;
   exception
      when no_data_found then
         raise_application_error(
            -20012,
            'Неверный логин или пароль'
         );
   end;

   procedure create_game (
      p_user_id       number,
      p_game_name     varchar2,
      p_max_players   number default 4,
      p_room_password varchar2 default null,
      p_game_id       out number
   ) is
      n                  number;
      start_id           number;
      room_password_hash "ИГРЫ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      if p_max_players not between 2 and 4 then
         raise_application_error(
            -20020,
            'Количество игроков: 2–4'
         );
      end if;
      if trim(p_game_name) is null then
         raise_application_error(
            -20021,
            'Название обязательно'
         );
      end if;
      select count(*)
        into n
        from "ПОЛЬЗОВАТЕЛИ"
       where "ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id;
      if n = 0 then
         raise_application_error(
            -20022,
            'Пользователь не найден'
         );
      end if;
      select count(*)
        into n
        from "УЧАСТНИКИ" u
        join "ИГРЫ" g
      on g."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
         and g."КОД_СТАТУСА_ИГРЫ" in ( 'ОЖИДАНИЕ',
                                       'ПРОВЕРКА_ГОТОВНОСТИ',
                                       'АКТИВНА' )
         and u."КОД_СТАТУСА_УЧАСТНИКА" in ( 'В_ЛОББИ',
                                            'АКТИВЕН' );
      if n > 0 then
         raise_application_error(
            -20023,
            'Пользователь уже в незавершённой игре'
         );
      end if;
      select "ID_КЛЕТКИ"
        into start_id
        from "КЛЕТКИ"
       where "ПОЗИЦИЯ" = 1;
      if p_room_password is null then
         room_password_hash := null;
      else
         select rawtohex(standard_hash(
            p_room_password,
            'SHA256'
         ))
           into room_password_hash
           from dual;
      end if;
      insert into "ИГРЫ" (
         "ID_ХОСТА",
         "КОД_СТАТУСА_ИГРЫ",
         "НАЗВАНИЕ",
         "ПАРОЛЬ_ХЭШ",
         "ДАТА_СОЗДАНИЯ",
         "МАКС_ИГРОКОВ"
      ) values
         ( p_user_id,
           'ОЖИДАНИЕ',
           trim(p_game_name),
           room_password_hash,
           sysdate,
           p_max_players )
      returning "ID_ИГРЫ" into p_game_id;
      insert into "УЧАСТНИКИ" (
         "ID_ИГРЫ",
         "ID_ПОЛЬЗОВАТЕЛЯ",
         "ID_ПОЗИЦИИ",
         "БАЛАНС",
         "КОД_СТАТУСА_УЧАСТНИКА",
         "ГОТОВ",
         "КОЛ_ТАЙМАУТОВ"
      ) values
         ( p_game_id,
           p_user_id,
           start_id,
           c_start_balance,
           'В_ЛОББИ',
           0,
           0 );
   end;
   function list_waiting_games return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for select g."ID_ИГРЫ",
                         g."НАЗВАНИЕ",
                         g."МАКС_ИГРОКОВ",
                         count(
                                 case
                                    when u."КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ' then
                                       1
                                 end
                              ) "ЗАНЯТО",
                         case
                            when g."ПАРОЛЬ_ХЭШ" is null then
                                    0
                            else
                               1
                         end "ЕСТЬ_ПАРОЛЬ"
                                from "ИГРЫ" g
                                left join "УЧАСТНИКИ" u
                              on u."ID_ИГРЫ" = g."ID_ИГРЫ"
                   where g."КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ'
                   group by g."ID_ИГРЫ",
                            g."НАЗВАНИЕ",
                            g."МАКС_ИГРОКОВ",
                            g."ПАРОЛЬ_ХЭШ",
                            g."ДАТА_СОЗДАНИЯ"
                  having count(
                     case
                        when u."КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ' then
                           1
                     end
                  ) < g."МАКС_ИГРОКОВ"
                   order by g."ДАТА_СОЗДАНИЯ" desc;
      return rc;
   end;
   procedure join_game (
      p_user_id       number,
      p_game_id       number,
      p_room_password varchar2 default null
   ) is      st                    varchar2(40);
      h                     varchar2(255);
      mx                    number;
      n                     number;
      sid                   number;
      ps                    varchar2(40);
      pid                   number;
      entered_password_hash "ИГРЫ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      if p_room_password is null then
         entered_password_hash := null;
      else
         select rawtohex(standard_hash(
            p_room_password,
            'SHA256'
         ))
           into entered_password_hash
           from dual;
      end if;
      select "КОД_СТАТУСА_ИГРЫ",
             "ПАРОЛЬ_ХЭШ",
             "МАКС_ИГРОКОВ"
        into
         st,
         h,
         mx
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if st <> 'ОЖИДАНИЕ' then
         raise_application_error(
            -20030,
            'Комната недоступна'
         );
      end if;
      if
         h is not null
         and h <> entered_password_hash
      then
         raise_application_error(
            -20031,
            'Неверный пароль'
         );
      end if;
      select count(*)
        into n
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if n >= mx then
         raise_application_error(
            -20032,
            'Комната заполнена'
         );
      end if;
      select count(*)
        into n
        from "УЧАСТНИКИ" u
        join "ИГРЫ" g
      on g."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
         and g."ID_ИГРЫ" <> p_game_id
         and g."КОД_СТАТУСА_ИГРЫ" in ( 'ОЖИДАНИЕ',
                                       'ПРОВЕРКА_ГОТОВНОСТИ',
                                       'АКТИВНА' )
         and u."КОД_СТАТУСА_УЧАСТНИКА" in ( 'В_ЛОББИ',
                                            'АКТИВЕН' );
      if n > 0 then
         raise_application_error(
            -20033,
            'Пользователь уже в другой игре'
         );
      end if;
      select "ID_КЛЕТКИ"
        into sid
        from "КЛЕТКИ"
       where "ПОЗИЦИЯ" = 1;
      begin
         select "ID_УЧАСТНИКА",
                "КОД_СТАТУСА_УЧАСТНИКА"
           into
            pid,
            ps
           from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = p_game_id
            and "ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
         for update;
         if ps = 'ИСКЛЮЧЕН' then
            raise_application_error(
               -20034,
               'Повторный вход запрещён'
            );
         end if;
         if ps <> 'ПОКИНУЛ' then
            raise_application_error(
               -20035,
               'Вы уже в комнате'
            );
         end if;
         update "УЧАСТНИКИ"
            set "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ',
                "ГОТОВ" = 0,
                "ОЧЕРЕДЬ_ХОДА" = null,
                "КОЛ_ТАЙМАУТОВ" = 0,
                "БАЛАНС" = c_start_balance,
                "ID_ПОЗИЦИИ" = sid
          where "ID_УЧАСТНИКА" = pid;
      exception
         when no_data_found then
            insert into "УЧАСТНИКИ" (
               "ID_ИГРЫ",
               "ID_ПОЛЬЗОВАТЕЛЯ",
               "ID_ПОЗИЦИИ",
               "БАЛАНС",
               "КОД_СТАТУСА_УЧАСТНИКА"
            ) values
               ( p_game_id,
                 p_user_id,
                 sid,
                 c_start_balance,
                 'В_ЛОББИ' );
      end;
   end;
   procedure abandon_waiting_game (
      p_user_id number,
      p_game_id number
   ) is
      h  number;
      st varchar2(40);
   begin
      select "ID_ХОСТА",
             "КОД_СТАТУСА_ИГРЫ"
        into
         h,
         st
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if h <> p_user_id
      or st not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(
            -20040,
            'Нельзя забросить игру'
         );
      end if;
      update "ИГРЫ"
         set "КОД_СТАТУСА_ИГРЫ" = 'ЗАБРОШЕНА',
             "ДАТА_ЗАВЕРШЕНИЯ" = sysdate,
             "ID_ТЕКУЩЕГО_УЧАСТНИКА" = null,
             "КОД_СОСТОЯНИЯ_ХОДА" = null
       where "ID_ИГРЫ" = p_game_id;
      update "УЧАСТНИКИ"
         set "КОД_СТАТУСА_УЧАСТНИКА" = 'ПОКИНУЛ',
             "ГОТОВ" = 0
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      add_action(
         p_game_id,
         null,
         null,
         'ИГРА_ЗАБРОШЕНА',
         null
      );
   end;
   procedure leave_lobby (
      p_participant_id number
   ) is
      g   number;
      usr number;
      h   number;
      st  varchar2(40);
   begin
      select u."ID_ИГРЫ",
             u."ID_ПОЛЬЗОВАТЕЛЯ",
             x."ID_ХОСТА",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         g,
         usr,
         h,
         st
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if usr = h then
         abandon_waiting_game(
            usr,
            g
         );
         return;
      end if;
      if st not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(
            -20041,
            'Игра уже началась'
         );
      end if;
      update "УЧАСТНИКИ"
         set "КОД_СТАТУСА_УЧАСТНИКА" = 'ПОКИНУЛ',
             "ГОТОВ" = 0
       where "ID_УЧАСТНИКА" = p_participant_id;
      if st = 'ПРОВЕРКА_ГОТОВНОСТИ' then
         update "ИГРЫ"
            set
            "КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ'
          where "ID_ИГРЫ" = g;
         update "УЧАСТНИКИ"
            set
            "ГОТОВ" = 0
          where "ID_ИГРЫ" = g
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      end if;
   end;
   procedure kick_participant (
      p_host_user_id   number,
      p_participant_id number
   ) is
      g  number;
      h  number;
      tu number;
      st varchar2(40);
   begin
      select u."ID_ИГРЫ",
             x."ID_ХОСТА",
             u."ID_ПОЛЬЗОВАТЕЛЯ",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         g,
         h,
         tu,
         st
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if h <> p_host_user_id then
         raise_application_error(
            -20042,
            'Только хост может исключать'
         );
      end if;
      if tu = h then
         raise_application_error(
            -20043,
            'Нельзя исключить хоста'
         );
      end if;
      if st not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(
            -20044,
            'Игра уже началась'
         );
      end if;
      update "УЧАСТНИКИ"
         set "КОД_СТАТУСА_УЧАСТНИКА" = 'ИСКЛЮЧЕН',
             "ГОТОВ" = 0
       where "ID_УЧАСТНИКА" = p_participant_id;
      add_action(
         g,
         p_participant_id,
         null,
         'ИСКЛЮЧЕНИЕ_УЧАСТНИКА',
         null
      );
      if st = 'ПРОВЕРКА_ГОТОВНОСТИ' then
         update "ИГРЫ"
            set
            "КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ'
          where "ID_ИГРЫ" = g;
         update "УЧАСТНИКИ"
            set
            "ГОТОВ" = 0
          where "ID_ИГРЫ" = g
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      end if;
   end;
   procedure request_start (
      p_game_id      number,
      p_host_user_id number
   ) is
      h  number;
      st varchar2(40);
      n  number;
      hp number;
   begin
      select "ID_ХОСТА",
             "КОД_СТАТУСА_ИГРЫ"
        into
         h,
         st
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if h <> p_host_user_id
      or st <> 'ОЖИДАНИЕ' then
         raise_application_error(
            -20045,
            'Запуск недоступен'
         );
      end if;
      select count(*)
        into n
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if n < 2 then
         raise_application_error(
            -20046,
            'Нужно минимум два игрока'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "ГОТОВ" = 0
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      select "ID_УЧАСТНИКА"
        into hp
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "ID_ПОЛЬЗОВАТЕЛЯ" = p_host_user_id;
      update "УЧАСТНИКИ"
         set
         "ГОТОВ" = 1
       where "ID_УЧАСТНИКА" = hp;
      update "ИГРЫ"
         set
         "КОД_СТАТУСА_ИГРЫ" = 'ПРОВЕРКА_ГОТОВНОСТИ'
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure set_ready (
      p_participant_id number,
      p_ready          number
   ) is
      g     number;
      st    varchar2(40);
      n     number;
      ready number;
   begin
      if p_ready not in ( 0,
                          1 ) then
         raise_application_error(
            -20047,
            'Готовность: 0 или 1'
         );
      end if;
      select u."ID_ИГРЫ",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         g,
         st
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if st not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(
            -20048,
            'Готовность сейчас недоступна'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "ГОТОВ" = p_ready
       where "ID_УЧАСТНИКА" = p_participant_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if sql%rowcount = 0 then
         raise_application_error(
            -20049,
            'Участник не находится в комнате'
         );
      end if;
      if p_ready = 1 then
         add_action(
            g,
            p_participant_id,
            null,
            'ПОДТВЕРЖДЕНИЕ_ГОТОВНОСТИ',
            null
         );
      end if;
      select count(*),
             nvl(
                sum("ГОТОВ"),
                0
             )
        into
         n,
         ready
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if
         n >= 2
         and ready = n
      then
         update "ИГРЫ"
            set "КОД_СТАТУСА_ИГРЫ" = 'ПРОВЕРКА_ГОТОВНОСТИ',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate
          where "ID_ИГРЫ" = g;
      else
         update "ИГРЫ"
            set "КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = null
          where "ID_ИГРЫ" = g;
      end if;
   end;
   procedure start_game (
      p_game_id      number,
      p_host_user_id number
   ) is      h        number;
      st       varchar2(40);
      n        number;
      ready    number;
      first_id number;
      ownn     number;
   begin
      select "ID_ХОСТА",
             "КОД_СТАТУСА_ИГРЫ"
        into
         h,
         st
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if h <> p_host_user_id
      or st <> 'ПРОВЕРКА_ГОТОВНОСТИ' then
         raise_application_error(
            -20050,
            'Игра не готова'
         );
      end if;
      select count(*),
             sum("ГОТОВ")
        into
         n,
         ready
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if n not between 2 and 4
      or ready <> n then
         raise_application_error(
            -20051,
            'Не все готовы'
         );
      end if;
      select count(*)
        into ownn
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = p_game_id;
      if ownn > 0 then
         raise_application_error(
            -20052,
            'Игра уже инициализирована'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "ОЧЕРЕДЬ_ХОДА" = null
       where "ID_ИГРЫ" = p_game_id;
      merge into "УЧАСТНИКИ" u
      using (
         select "ID_УЧАСТНИКА",
                row_number()
                over(
                    order by dbms_random.value,
                             "ID_УЧАСТНИКА"
                ) rn
           from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = p_game_id
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ'
      ) s on ( u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА" )
      when matched then update
      set u."ОЧЕРЕДЬ_ХОДА" = s.rn,
          u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН',
          u."БАЛАНС" = floor(c_start_balance / n),
          u."КОЛ_ТАЙМАУТОВ" = 0,
          u."ГОТОВ" = 1;
      insert into "ВЛАДЕНИЯ" (
         "ID_ИГРЫ",
         "ID_КЛЕТКИ",
         "ID_ВЛАДЕЛЬЦА",
         "КОЛВО_ДОМОВ",
         "ЗАЛОЖЕНА"
      )
         select p_game_id,
                "ID_КЛЕТКИ",
                null,
                0,
                0
           from "КЛЕТКИ"
          where "ТИП" in ( 'Улица',
                           'Коммунальная' );
      select "ID_УЧАСТНИКА"
        into first_id
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "ОЧЕРЕДЬ_ХОДА" = 1;
      update "ИГРЫ"
         set "КОД_СТАТУСА_ИГРЫ" = 'АКТИВНА',
             "ДАТА_СТАРТА" = sysdate,
             "ID_ТЕКУЩЕГО_УЧАСТНИКА" = first_id,
             "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate,
             "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_БРОСКА',
             "ВЕРСИЯ_СОСТОЯНИЯ" = "ВЕРСИЯ_СОСТОЯНИЯ" + 1
       where "ID_ИГРЫ" = p_game_id;
   end;

   function get_game_state (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for select g."ID_ИГРЫ",
                         g."НАЗВАНИЕ",
                         g."КОД_СТАТУСА_ИГРЫ",
                         sg."НАИМЕНОВАНИЕ" "СТАТУС_ИГРЫ",
                         g."КОД_СОСТОЯНИЯ_ХОДА",
                         sh."НАИМЕНОВАНИЕ" "СОСТОЯНИЕ_ХОДА",
                         g."ID_ТЕКУЩЕГО_УЧАСТНИКА",
                         g."ID_ПОБЕДИТЕЛЯ",
                         g."ВРЕМЯ_НАЧАЛА_ХОДА",
                         g."ДАТА_СТАРТА",
                         g."ДАТА_ЗАВЕРШЕНИЯ",
                         g."ID_ХОСТА",
                         g."МАКС_ИГРОКОВ",
                         g."ВЕРСИЯ_СОСТОЯНИЯ",
                         (
                                 select max(a."ID_АУКЦИОНА")
                                   from "АУКЦИОНЫ" a
                                  where a."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                              ) "ID_АУКЦИОНА",
                         (
                                 select max(ca."НАЗВАНИЕ") keep(dense_rank last order by a."ID_АУКЦИОНА")
                                   from "АУКЦИОНЫ" a
                                   join "КЛЕТКИ" ca
                                 on ca."ID_КЛЕТКИ" = a."ID_КЛЕТКИ"
                                  where a."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                              ) "АУКЦИОН_КЛЕТКА",
                         (
                                 select max(a."СТАРТ_ЦЕНА") keep(dense_rank last order by a."ID_АУКЦИОНА")
                                   from "АУКЦИОНЫ" a
                                  where a."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                              ) "СТАРТ_ЦЕНА",
                         (
                                 select max(s."СУММА")
                                   from "СТАВКИ" s
                                   join "АУКЦИОНЫ" a
                                 on a."ID_АУКЦИОНА" = s."ID_АУКЦИОНА"
                                  where a."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                                    and s."ID_УЧАСТНИКА" = me."ID_УЧАСТНИКА"
                              ) "МОЯ_СТАВКА",
                         (
                                 select max(j."ТЕКСТ_СОБЫТИЯ") keep(dense_rank last order by j."ID_ДЕЙСТВИЯ")
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                  where j."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and j."КОД_ДЕЙСТВИЯ" = 'КАРТА_ШАНСА'
                                    and j."ID_ДЕЙСТВИЯ" > nvl(
                                    (
                                       select max(jd."ID_ДЕЙСТВИЯ")
                                         from "ЖУРНАЛ_ДЕЙСТВИЙ" jd
                                        where jd."ID_ИГРЫ" = g."ID_ИГРЫ"
                                          and jd."КОД_ДЕЙСТВИЯ" = 'БРОСОК_КУБИКА'
                                    ),
                                    0
                                 )
                              ) "ПОСЛЕДНЯЯ_КАРТА_ШАНСА",
                         case
                            when g."КОД_СТАТУСА_ИГРЫ" = 'ПРОВЕРКА_ГОТОВНОСТИ' then
                                    greatest(
                                       0,
                                       ceil(c_ready_seconds -(sysdate - g."ВРЕМЯ_НАЧАЛА_ХОДА") * 86400)
                                    )
                         end "СЕКУНД_ДО_СТАРТА",
                         case
                            when g."КОД_СТАТУСА_ИГРЫ" = 'АКТИВНА'
                                    and g."ВРЕМЯ_НАЧАЛА_ХОДА" is not null then
                                    greatest(
                                       0,
                                       ceil(c_turn_minutes * 60 -(sysdate - g."ВРЕМЯ_НАЧАЛА_ХОДА") * 86400)
                                    )
                         end "СЕКУНД_ХОДА",
                         (
                                 select max(j."СУММА") keep(dense_rank last order by j."ID_ДЕЙСТВИЯ")
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                  where j."ID_ИГРЫ" = g."ID_ИГРЫ"
                                    and j."КОД_ДЕЙСТВИЯ" = 'БРОСОК_КУБИКА'
                              ) "ПОСЛЕДНИЙ_КУБИК"
                                from "УЧАСТНИКИ" me
                                join "ИГРЫ" g
                              on g."ID_ИГРЫ" = me."ID_ИГРЫ"
                                join "СТАТУСЫ_ИГР" sg
                              on sg."КОД_СТАТУСА_ИГРЫ" = g."КОД_СТАТУСА_ИГРЫ"
                                left join "СОСТОЯНИЯ_ХОДА" sh
                              on sh."КОД_СОСТОЯНИЯ_ХОДА" = g."КОД_СОСТОЯНИЯ_ХОДА"
                   where me."ID_УЧАСТНИКА" = p_participant_id;
      return rc;
   end;
   function get_game_participants (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
      g  number;
   begin
      g := participant_game(p_participant_id);
      open rc for select u."ID_УЧАСТНИКА",
                         u."ID_ПОЛЬЗОВАТЕЛЯ",
                         p."ЛОГИН",
                         u."БАЛАНС",
                         c."ПОЗИЦИЯ",
                         c."НАЗВАНИЕ" "КЛЕТКА",
                         u."ОЧЕРЕДЬ_ХОДА",
                         u."КОД_СТАТУСА_УЧАСТНИКА",
                         s."НАИМЕНОВАНИЕ" "СТАТУС",
                         u."ГОТОВ",
                         u."КОЛ_ТАЙМАУТОВ"
                                from "УЧАСТНИКИ" u
                                join "ПОЛЬЗОВАТЕЛИ" p
                              on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                                join "КЛЕТКИ" c
                              on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
                                join "СТАТУСЫ_УЧАСТНИКОВ" s
                              on s."КОД_СТАТУСА_УЧАСТНИКА" = u."КОД_СТАТУСА_УЧАСТНИКА"
                   where u."ID_ИГРЫ" = g
                   order by nvl(
                     u."ОЧЕРЕДЬ_ХОДА",
                     99
                  ),
                            u."ID_УЧАСТНИКА";
      return rc;
   end;
   function get_board_state (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
      g  number;
   begin
      g := participant_game(p_participant_id);
      open rc for select c."ID_КЛЕТКИ",
                         c."ПОЗИЦИЯ",
                         c."НАЗВАНИЕ",
                         c."ТИП",
                         c."ЦВЕТОВАЯ_ГРУППА",
                         c."ЦЕНА_ПОКУПКИ",
                         c."ЦЕНА_ПОКУПКИ" "БАЗОВАЯ_РЕНТА",
                         ceil(c."ЦЕНА_ПОКУПКИ" * 1.25) "РЕНТА_1_ДОМ",
                         ceil(c."ЦЕНА_ПОКУПКИ" * 1.50) "РЕНТА_2_ДОМА",
                         ceil(c."ЦЕНА_ПОКУПКИ" * 1.75) "РЕНТА_ОТЕЛЬ",
                         ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) "ЦЕНА_ДОМА",
                         case
                            when c."ТИП" = 'Старт' then
                                    c_start_bonus
                         end "БОНУС_СТАРТА",
                         v."ID_ВЛАДЕНИЯ",
                         v."ID_ВЛАДЕЛЬЦА",
                         op."ЛОГИН" "ВЛАДЕЛЕЦ",
                         v."КОЛВО_ДОМОВ",
                         v."ЗАЛОЖЕНА",
                         case
                            when c."ТИП" = 'Улица'
                                    and v."ID_ВЛАДЕЛЬЦА" is not null
                                    and (
                                    select count(*)
                                      from "ВЛАДЕНИЯ" vx
                                      join "КЛЕТКИ" cx
                                    on cx."ID_КЛЕТКИ" = vx."ID_КЛЕТКИ"
                                     where vx."ID_ИГРЫ" = g
                                       and vx."ID_ВЛАДЕЛЬЦА" = v."ID_ВЛАДЕЛЬЦА"
                                       and vx."ЗАЛОЖЕНА" = 0
                                       and cx."ЦВЕТОВАЯ_ГРУППА" = c."ЦВЕТОВАЯ_ГРУППА"
                                 ) = (
                                    select count(*)
                                      from "КЛЕТКИ" cg
                                     where cg."ТИП" = 'Улица'
                                       and cg."ЦВЕТОВАЯ_ГРУППА" = c."ЦВЕТОВАЯ_ГРУППА"
                                 ) then
                                    2
                            else
                               1
                         end "МНОЖИТЕЛЬ_ГРУППЫ"
                                from "КЛЕТКИ" c
                                left join "ВЛАДЕНИЯ" v
                              on v."ID_КЛЕТКИ" = c."ID_КЛЕТКИ"
                                 and v."ID_ИГРЫ" = g
                                left join "УЧАСТНИКИ" ou
                              on ou."ID_УЧАСТНИКА" = v."ID_ВЛАДЕЛЬЦА"
                                left join "ПОЛЬЗОВАТЕЛИ" op
                              on op."ID_ПОЛЬЗОВАТЕЛЯ" = ou."ID_ПОЛЬЗОВАТЕЛЯ"
                   order by c."ПОЗИЦИЯ";
      return rc;
   end;
   function get_player_properties (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for select v."ID_ВЛАДЕНИЯ",
                         c."ID_КЛЕТКИ",
                         c."НАЗВАНИЕ",
                         c."ТИП",
                         v."КОЛВО_ДОМОВ",
                         v."ЗАЛОЖЕНА",
                         c."ЦЕНА_ПОКУПКИ",
                         floor(c."ЦЕНА_ПОКУПКИ" / 2) "ЗАЛОГОВАЯ_СТОИМОСТЬ",
                         floor(nvl(
                                 c."ЦЕНА_ПОКУПКИ",
                                 0
                              ) * 0.25 / 2) "СТОИМОСТЬ_ПРОДАЖИ_УРОВНЯ",
                         ceil(c."ЦЕНА_ПОКУПКИ" *(1 + c_mortgage_interest)) "СТОИМОСТЬ_ВЫКУПА",
                         case
                            when v."ЗАЛОЖЕНА" = 0
                                    and v."КОЛВО_ДОМОВ" = 0 then
                                    1
                            else
                               0
                         end "МОЖНО_ЗАЛОЖИТЬ"
                                from "ВЛАДЕНИЯ" v
                                join "КЛЕТКИ" c
                              on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
                   where v."ID_ВЛАДЕЛЬЦА" = p_participant_id
                   order by c."ПОЗИЦИЯ";
      return rc;
   end;
   function get_active_auction (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
      g  number;
   begin
      g := participant_game(p_participant_id);
      open rc for select a."ID_АУКЦИОНА",
                         a."ID_КЛЕТКИ",
                         c."НАЗВАНИЕ",
                         a."СТАРТ_ЦЕНА",
                         a."ДАТА_НАЧАЛА",
                         s."ID_УЧАСТНИКА",
                         p."ЛОГИН",
                         s."СУММА",
                         s."ДАТА_ВРЕМЯ"
                                from "АУКЦИОНЫ" a
                                join "КЛЕТКИ" c
                              on c."ID_КЛЕТКИ" = a."ID_КЛЕТКИ"
                                left join "СТАВКИ" s
                              on s."ID_АУКЦИОНА" = a."ID_АУКЦИОНА"
                                left join "УЧАСТНИКИ" u
                              on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
                                left join "ПОЛЬЗОВАТЕЛИ" p
                              on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                   where a."ID_ИГРЫ" = g
                     and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                   order by s."СУММА" desc nulls last,
                            s."ДАТА_ВРЕМЯ";
      return rc;
   end;
   procedure roll_and_move (
      p_participant_id number,
      p_dice           out number
   ) is      g     number;
      cur   number;
      state varchar2(40);
      gst   varchar2(40);
      bal   number;
      pos   number;
      np    number;
      cell  number;
      bonus number := 0;
      n     number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА",
             x."КОД_СТАТУСА_ИГРЫ",
             u."БАЛАНС",
             c."ПОЗИЦИЯ"
        into
         g,
         cur,
         state,
         gst,
         bal,
         pos
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if gst <> 'АКТИВНА'
      or cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_БРОСКА'
      or bal < 0 then
         raise_application_error(
            -20060,
            'Бросок запрещён'
         );
      end if;
      select count(*)
        into n
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if n > 0 then
         raise_application_error(
            -20061,
            'Идёт аукцион'
         );
      end if;
      p_dice := trunc(dbms_random.value(
         1,
         7
      ));
      np := mod(
         pos - 1 + p_dice,
         12
      ) + 1;
      if pos - 1 + p_dice >= 12 then
         bonus := c_start_bonus;
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" + bonus
          where "ID_УЧАСТНИКА" = p_participant_id;
      end if;
      select "ID_КЛЕТКИ"
        into cell
        from "КЛЕТКИ"
       where "ПОЗИЦИЯ" = np;
      update "УЧАСТНИКИ"
         set
         "ID_ПОЗИЦИИ" = cell
       where "ID_УЧАСТНИКА" = p_participant_id;
      add_action(
         g,
         p_participant_id,
         null,
         'БРОСОК_КУБИКА',
         p_dice
      );
      add_action(
         g,
         p_participant_id,
         cell,
         'ПОСЕЩЕНИЕ_КЛЕТКИ',
         null
      );
      if bonus > 0 then
         add_action(
            g,
            p_participant_id,
            cell,
            'БОНУС_СТАРТА',
            bonus
         );
      end if;
      process_cell(
         p_participant_id,
         p_dice
      );
   end;
   procedure process_cell (
      p_participant_id number,
      p_dice           number
   ) is      g     number;
      cell  number;
      typ   varchar2(30);
      grp   varchar2(20);
      owner number;
      mort  number;
      lvl   number;
   begin
      select u."ID_ИГРЫ",
             u."ID_ПОЗИЦИИ",
             c."ТИП",
             c."ЦВЕТОВАЯ_ГРУППА"
        into
         g,
         cell,
         typ,
         grp
        from "УЧАСТНИКИ" u
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if typ = 'Старт' then
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = g;
      elsif typ = 'Шанс' then
         apply_chance(
            p_participant_id,
            p_dice
         );
      else
         select "ID_ВЛАДЕЛЬЦА",
                "ЗАЛОЖЕНА",
                "КОЛВО_ДОМОВ"
           into
            owner,
            mort,
            lvl
           from "ВЛАДЕНИЯ"
          where "ID_ИГРЫ" = g
            and "ID_КЛЕТКИ" = cell;
         if owner is null then
            update "ИГРЫ"
               set
               "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_ПОКУПКИ'
             where "ID_ИГРЫ" = g;
         elsif owner <> p_participant_id then
            if mort = 1 then
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
                where "ID_ИГРЫ" = g;
            else
               pay_rent(
                  p_participant_id,
                  cell,
                  p_dice
               );
            end if;
         else
            if
               typ = 'Улица'
               and mort = 0
               and lvl < 3
            then
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
                where "ID_ИГРЫ" = g;
            else
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
                where "ID_ИГРЫ" = g;
            end if;
         end if;
      end if;
   end;
   procedure advance_to_next_player (
      p_game_id number
   ) is
      cur number;
      ord number;
      nxt number;
   begin
      select "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into cur
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      select "ОЧЕРЕДЬ_ХОДА"
        into ord
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = cur;
      begin
         select "ID_УЧАСТНИКА"
           into nxt
           from (
            select "ID_УЧАСТНИКА"
              from "УЧАСТНИКИ"
             where "ID_ИГРЫ" = p_game_id
               and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
               and "ОЧЕРЕДЬ_ХОДА" > ord
             order by "ОЧЕРЕДЬ_ХОДА"
         )
          where rownum = 1;
      exception
         when no_data_found then
            select "ID_УЧАСТНИКА"
              into nxt
              from (
               select "ID_УЧАСТНИКА"
                 from "УЧАСТНИКИ"
                where "ID_ИГРЫ" = p_game_id
                  and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
                order by "ОЧЕРЕДЬ_ХОДА"
            )
             where rownum = 1;
      end;
      update "ИГРЫ"
         set "ID_ТЕКУЩЕГО_УЧАСТНИКА" = nxt,
             "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate,
             "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_БРОСКА'
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure end_turn (
      p_game_id number
   ) is      state varchar2(40);
      cur   number;
      bal   number;
      n     number;
      st    varchar2(40);
   begin
      select "КОД_СОСТОЯНИЯ_ХОДА",
             "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         state,
         cur
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if state <> 'ЗАВЕРШЕНИЕ_ХОДА' then
         raise_application_error(
            -20062,
            'Ход не завершён'
         );
      end if;
      select "БАЛАНС"
        into bal
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = cur
      for update;
      if bal < 0 then
         raise_application_error(
            -20063,
            'Сначала покройте долг'
         );
      end if;
      select count(*)
        into n
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if n > 0 then
         raise_application_error(
            -20064,
            'Аукцион не завершён'
         );
      end if;
      finish_or_continue(p_game_id);
      select "КОД_СТАТУСА_ИГРЫ"
        into st
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if st = 'АКТИВНА' then
         advance_to_next_player(p_game_id);
      end if;
   end;

   procedure buy_property (
      p_participant_id number,
      p_cell_id        number
   ) is      g     number;
      cur   number;
      state varchar2(40);
      owner number;
      price number;
      bal   number;
      typ   varchar2(30);
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         g,
         cur,
         state,
         bal
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(
            -20070,
            'Покупка недоступна'
         );
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             c."ЦЕНА_ПОКУПКИ",
             c."ТИП"
        into
         owner,
         price,
         typ
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = g
         and v."ID_КЛЕТКИ" = p_cell_id
      for update;
      if owner is not null
      or typ not in ( 'Улица',
                      'Коммунальная' )
      or bal < price then
         raise_application_error(
            -20071,
            'Клетку нельзя купить'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - price
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "ID_ВЛАДЕЛЬЦА" = p_participant_id
       where "ID_ИГРЫ" = g
         and "ID_КЛЕТКИ" = p_cell_id;
      add_action(
         g,
         p_participant_id,
         p_cell_id,
         'ПОКУПКА_СОБСТВЕННОСТИ',
         price
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = g;
   end;
   procedure decline_purchase (
      p_participant_id number,
      p_cell_id        number
   ) is
      g     number;
      cur   number;
      state varchar2(40);
      owner number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         g,
         cur,
         state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(
            -20073,
            'Отказ недоступен'
         );
      end if;
      select "ID_ВЛАДЕЛЬЦА"
        into owner
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = g
         and "ID_КЛЕТКИ" = p_cell_id
      for update;
      if owner is not null then
         raise_application_error(
            -20074,
            'Клетка уже куплена'
         );
      end if;
      add_action(
         g,
         p_participant_id,
         p_cell_id,
         'ОТКАЗ_ОТ_ПОКУПКИ',
         null
      );
      start_auction(
         g,
         p_cell_id
      );
   end;
   function calculate_rent (
      p_ownership_id number,
      p_dice         number
   ) return number is      typ    varchar2(30);
      grp    varchar2(20);
      mort   number;
      lvl    number;
      rent   number;
      owner  number;
      g      number;
      n      number;
      totaln number;
   begin
      select c."ТИП",
             c."ЦВЕТОВАЯ_ГРУППА",
             v."ЗАЛОЖЕНА",
             v."КОЛВО_ДОМОВ",
             v."ID_ВЛАДЕЛЬЦА",
             v."ID_ИГРЫ",
             ceil(c."ЦЕНА_ПОКУПКИ" *(1 + v."КОЛВО_ДОМОВ" * 0.25))
        into
         typ,
         grp,
         mort,
         lvl,
         owner,
         g,
         rent
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" = p_ownership_id;
      if mort = 1 then
         return 0;
      end if;
      if typ = 'Коммунальная' then
         select count(*)
           into n
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ИГРЫ" = g
            and v."ID_ВЛАДЕЛЬЦА" = owner
            and v."ЗАЛОЖЕНА" = 0
            and c."ТИП" = 'Коммунальная';
         return p_dice *
            case
               when n >= 2 then
                  50
               else
                  25
            end;
      end if;
      select count(*)
        into totaln
        from "КЛЕТКИ"
       where "ТИП" = 'Улица'
         and "ЦВЕТОВАЯ_ГРУППА" = grp;
      select count(*)
        into n
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = g
         and v."ID_ВЛАДЕЛЬЦА" = owner
         and v."ЗАЛОЖЕНА" = 0
         and c."ТИП" = 'Улица'
         and c."ЦВЕТОВАЯ_ГРУППА" = grp;
      return nvl(
         rent,
         0
      ) *
         case
            when totaln > 0
               and n = totaln then
               2
            else
               1
         end;
   end;
   procedure pay_rent (
      p_participant_id number,
      p_cell_id        number,
      p_dice           number
   ) is
      g     number;
      oid   number;
      owner number;
      mort  number;
      rent  number;
   begin
      g := participant_game(p_participant_id);
      select "ID_ВЛАДЕНИЯ",
             "ID_ВЛАДЕЛЬЦА",
             "ЗАЛОЖЕНА"
        into
         oid,
         owner,
         mort
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = g
         and "ID_КЛЕТКИ" = p_cell_id
      for update;
      if owner is null
      or owner = p_participant_id
      or mort = 1 then
         raise_application_error(
            -20075,
            'Аренда не требуется'
         );
      end if;
      rent := calculate_rent(
         oid,
         p_dice
      );
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - rent
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + rent
       where "ID_УЧАСТНИКА" = owner;
      add_action(
         g,
         p_participant_id,
         p_cell_id,
         'ОПЛАТА_АРЕНДЫ',
         rent
      );
      enter_debt_or_bankruptcy(p_participant_id);
   end;
   procedure apply_chance (
      p_participant_id number,
      p_dice           number
   ) is      g           number;
      cid         number;
      target      number;
      typ         "КАРТЫ_ШАНСА"."ТИП_ЭФФЕКТА"%type;
      amt         number;
      txt         "КАРТЫ_ШАНСА"."ТЕКСТ_СОБЫТИЯ"%type;
      chance_cell number;
      oldpos      number;
      newpos      number;
      bal         number;
      bonus       number;
   begin
      g := participant_game(p_participant_id);
      select "ID_ПОЗИЦИИ"
        into chance_cell
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      select "ID_КАРТЫ",
             "ID_ЦЕЛЕВОЙ_КЛЕТКИ",
             "ТИП_ЭФФЕКТА",
             "СУММА_ИЗМЕНЕНИЯ",
             "ТЕКСТ_СОБЫТИЯ"
        into
         cid,
         target,
         typ,
         amt,
         txt
        from (
         select "ID_КАРТЫ",
                "ID_ЦЕЛЕВОЙ_КЛЕТКИ",
                "ТИП_ЭФФЕКТА",
                "СУММА_ИЗМЕНЕНИЯ",
                "ТЕКСТ_СОБЫТИЯ"
           from "КАРТЫ_ШАНСА"
          order by dbms_random.value
      )
       where rownum = 1;

      add_action(
         g,
         p_participant_id,
         chance_cell,
         'КАРТА_ШАНСА',
         amt,
         txt
      );
      if typ = 'Премия' then
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" + amt
          where "ID_УЧАСТНИКА" = p_participant_id;
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = g;
      elsif typ = 'Штраф' then
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" - amt
          where "ID_УЧАСТНИКА" = p_participant_id;
         enter_debt_or_bankruptcy(p_participant_id);
      else
         select c."ПОЗИЦИЯ"
           into oldpos
           from "УЧАСТНИКИ" u
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
          where u."ID_УЧАСТНИКА" = p_participant_id;
         select "ПОЗИЦИЯ"
           into newpos
           from "КЛЕТКИ"
          where "ID_КЛЕТКИ" = target;
         if newpos <= oldpos then
            bonus := c_start_bonus;
            update "УЧАСТНИКИ"
               set
               "БАЛАНС" = "БАЛАНС" + bonus
             where "ID_УЧАСТНИКА" = p_participant_id;
            add_action(
               g,
               p_participant_id,
               target,
               'БОНУС_СТАРТА',
               bonus
            );
         end if;
         update "УЧАСТНИКИ"
            set
            "ID_ПОЗИЦИИ" = target
          where "ID_УЧАСТНИКА" = p_participant_id;
         add_action(
            g,
            p_participant_id,
            target,
            'ПОСЕЩЕНИЕ_КЛЕТКИ',
            null
         );
         process_cell(
            p_participant_id,
            p_dice
         );
      end if;
   end;
   function owns_full_color_group (
      p_participant_id number,
      p_color_group    varchar2
   ) return number is
      g      number;
      totaln number;
      owned  number;
   begin
      g := participant_game(p_participant_id);
      select count(*)
        into totaln
        from "КЛЕТКИ"
       where "ТИП" = 'Улица'
         and "ЦВЕТОВАЯ_ГРУППА" = p_color_group;
      select count(*)
        into owned
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = g
         and c."ЦВЕТОВАЯ_ГРУППА" = p_color_group
         and c."ТИП" = 'Улица'
         and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
         and v."ЗАЛОЖЕНА" = 0;
      return
         case
            when totaln > 0
               and totaln = owned then
               1
            else
               0
         end;
   end;
   procedure build_house (
      p_participant_id number,
      p_cell_id        number
   ) is      g     number;
      cur   number;
      state varchar2(40);
      typ   varchar2(30);
      owner number;
      mort  number;
      lvl   number;
      price number;
      bal   number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         g,
         cur,
         state,
         bal
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      select c."ТИП",
             ceil(c."ЦЕНА_ПОКУПКИ" * 0.25),
             v."ID_ВЛАДЕЛЬЦА",
             v."ЗАЛОЖЕНА",
             v."КОЛВО_ДОМОВ"
        into
         typ,
         price,
         owner,
         mort,
         lvl
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = g
         and v."ID_КЛЕТКИ" = p_cell_id
      for update;
      if cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
      or typ <> 'Улица'
      or owner <> p_participant_id
      or mort <> 0
      or lvl >= 3
      or bal < price then
         raise_application_error(
            -20080,
            'Для следующего улучшения недостаточно денег или оно недоступно'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - price
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "КОЛВО_ДОМОВ" = "КОЛВО_ДОМОВ" + 1
       where "ID_ИГРЫ" = g
         and "ID_КЛЕТКИ" = p_cell_id;
      add_action(
         g,
         p_participant_id,
         p_cell_id,
         'ПОКУПКА_УЛУЧШЕНИЯ',
         price
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = g;
   end;
   procedure decline_improvement (
      p_participant_id number,
      p_cell_id        number
   ) is
      g     number;
      cur   number;
      state varchar2(40);
      owner number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         g,
         cur,
         state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      select "ID_ВЛАДЕЛЬЦА"
        into owner
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = g
         and "ID_КЛЕТКИ" = p_cell_id;
      if cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
      or owner <> p_participant_id then
         raise_application_error(
            -20081,
            'Отказ недоступен'
         );
      end if;
      add_action(
         g,
         p_participant_id,
         p_cell_id,
         'ОТКАЗ_ОТ_УЛУЧШЕНИЯ',
         null
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = g;
   end;
   procedure sell_buildings (
      p_participant_id number,
      p_ownership_id   number,
      p_count          number
   ) is      g      number;
      cur    number;
      state  varchar2(40);
      cell   number;
      owner  number;
      lvl    number;
      mort   number;
      price  number;
      typ    varchar2(30);
      amount number;
      bal    number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         g,
         cur,
         state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state not in ( 'ОЖИДАНИЕ_БРОСКА',
                        'ПОКРЫТИЕ_ДОЛГА' ) then
         raise_application_error(
            -20082,
            'Продажа недоступна'
         );
      end if;
      select v."ID_КЛЕТКИ",
             v."ID_ВЛАДЕЛЬЦА",
             v."КОЛВО_ДОМОВ",
             v."ЗАЛОЖЕНА",
             ceil(c."ЦЕНА_ПОКУПКИ" * 0.25),
             c."ТИП"
        into
         cell,
         owner,
         lvl,
         mort,
         price,
         typ
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" = p_ownership_id
         and v."ID_ИГРЫ" = g
      for update;
      if owner <> p_participant_id
      or typ <> 'Улица'
      or mort <> 0
      or p_count <> 1
      or lvl < 1 then
         raise_application_error(
            -20083,
            'За одно действие продаётся один текущий уровень'
         );
      end if;
      amount := floor(price / 2);
      update "ВЛАДЕНИЯ"
         set
         "КОЛВО_ДОМОВ" = "КОЛВО_ДОМОВ" - 1
       where "ID_ВЛАДЕНИЯ" = p_ownership_id;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + amount
       where "ID_УЧАСТНИКА" = p_participant_id;
      add_action(
         g,
         p_participant_id,
         cell,
         'ПРОДАЖА_ПОСТРОЕК',
         amount
      );
      if state = 'ПОКРЫТИЕ_ДОЛГА' then
         enter_debt_or_bankruptcy(p_participant_id);
      end if;
   end;
   procedure mortgage_properties (
      p_participant_id number,
      p_ownership_ids  number_list
   ) is      g     number;
      cur   number;
      state varchar2(40);
      total number := 0;
      n     number;
      bal   number;
   begin
      if p_ownership_ids is null
      or p_ownership_ids.count = 0 then
         raise_application_error(
            -20084,
            'Список пуст'
         );
      end if;
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         g,
         cur,
         state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state <> 'ПОКРЫТИЕ_ДОЛГА' then
         raise_application_error(
            -20085,
            'Залог разрешён только для покрытия отрицательного баланса'
         );
      end if;
      select count(*),
             nvl(
                sum(floor(c."ЦЕНА_ПОКУПКИ" / 2)),
                0
             )
        into
         n,
         total
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" in (
         select column_value
           from table ( p_ownership_ids )
      )
         and v."ID_ИГРЫ" = g
         and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
         and v."ЗАЛОЖЕНА" = 0
         and v."КОЛВО_ДОМОВ" = 0;
      if n <> p_ownership_ids.count then
         raise_application_error(
            -20086,
            'Некоторые объекты нельзя заложить'
         );
      end if;
      for r in (
         select v."ID_ВЛАДЕНИЯ" oid,
                v."ID_КЛЕТКИ" cell,
                floor(c."ЦЕНА_ПОКУПКИ" / 2) amount
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ВЛАДЕНИЯ" in (
            select column_value
              from table ( p_ownership_ids )
         )
      ) loop
         update "ВЛАДЕНИЯ"
            set
            "ЗАЛОЖЕНА" = 1
          where "ID_ВЛАДЕНИЯ" = r.oid;
         add_action(
            g,
            p_participant_id,
            r.cell,
            'ЗАЛОГ_СОБСТВЕННОСТИ',
            r.amount
         );
      end loop;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + total
       where "ID_УЧАСТНИКА" = p_participant_id;
      enter_debt_or_bankruptcy(p_participant_id);
   end;
   procedure resolve_debt (
      p_participant_id number,
      p_mortgage_ids   number_list,
      p_sale_ids       number_list
   ) is      g     number;
      cur   number;
      state varchar2(40);
      total number := 0;
      n     number;
      bal   number;
      mc    number := 0;
      sc    number := 0;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         g,
         cur,
         state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state <> 'ПОКРЫТИЕ_ДОЛГА' then
         raise_application_error(
            -20120,
            'Управление долгом сейчас недоступно'
         );
      end if;
      if p_mortgage_ids is not null then
         mc := p_mortgage_ids.count;
      end if;
      if p_sale_ids is not null then
         sc := p_sale_ids.count;
      end if;
      if mc + sc = 0 then
         raise_application_error(
            -20121,
            'Ничего не выбрано'
         );
      end if;
      if mc > 0 then
         select count(*),
                nvl(
                   sum(floor(c."ЦЕНА_ПОКУПКИ" / 2)),
                   0
                )
           into
            n,
            total
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ВЛАДЕНИЯ" in (
            select column_value
              from table ( p_mortgage_ids )
         )
            and v."ID_ИГРЫ" = g
            and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
            and v."ЗАЛОЖЕНА" = 0
            and v."КОЛВО_ДОМОВ" = 0;
         if n <> mc then
            raise_application_error(
               -20122,
               'Некоторые объекты нельзя заложить'
            );
         end if;
      end if;
      if sc > 0 then
         select count(*),
                total + nvl(
                   sum(floor(ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) / 2)),
                   0
                )
           into
            n,
            total
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ВЛАДЕНИЯ" in (
            select column_value
              from table ( p_sale_ids )
         )
            and v."ID_ИГРЫ" = g
            and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
            and v."ЗАЛОЖЕНА" = 0
            and v."КОЛВО_ДОМОВ" > 0
            and c."ТИП" = 'Улица';
         if n <> sc then
            raise_application_error(
               -20123,
               'Некоторые постройки нельзя продать'
            );
         end if;
      end if;
      if mc > 0 then
         for r in (
            select v."ID_ВЛАДЕНИЯ" oid,
                   v."ID_КЛЕТКИ" cell,
                   floor(c."ЦЕНА_ПОКУПКИ" / 2) amount
              from "ВЛАДЕНИЯ" v
              join "КЛЕТКИ" c
            on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
             where v."ID_ВЛАДЕНИЯ" in (
               select column_value
                 from table ( p_mortgage_ids )
            )
         ) loop
            update "ВЛАДЕНИЯ"
               set
               "ЗАЛОЖЕНА" = 1
             where "ID_ВЛАДЕНИЯ" = r.oid;
            add_action(
               g,
               p_participant_id,
               r.cell,
               'ЗАЛОГ_СОБСТВЕННОСТИ',
               r.amount
            );
         end loop;
      end if;
      if sc > 0 then
         for r in (
            select v."ID_ВЛАДЕНИЯ" oid,
                   v."ID_КЛЕТКИ" cell,
                   floor(ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) / 2) amount
              from "ВЛАДЕНИЯ" v
              join "КЛЕТКИ" c
            on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
             where v."ID_ВЛАДЕНИЯ" in (
               select column_value
                 from table ( p_sale_ids )
            )
         ) loop
            update "ВЛАДЕНИЯ"
               set
               "КОЛВО_ДОМОВ" = "КОЛВО_ДОМОВ" - 1
             where "ID_ВЛАДЕНИЯ" = r.oid;
            add_action(
               g,
               p_participant_id,
               r.cell,
               'ПРОДАЖА_ПОСТРОЕК',
               r.amount
            );
         end loop;
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + total
       where "ID_УЧАСТНИКА" = p_participant_id;
      enter_debt_or_bankruptcy(p_participant_id);
   end;
   procedure redeem_property (
      p_participant_id number,
      p_ownership_id   number
   ) is      g      number;
      cur    number;
      state  varchar2(40);
      owner  number;
      mort   number;
      price  number;
      cell   number;
      bal    number;
      amount number;
      n      number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         g,
         cur,
         state,
         bal
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if cur <> p_participant_id
      or state <> 'ОЖИДАНИЕ_БРОСКА'
      or bal < 0 then
         raise_application_error(
            -20087,
            'Снятие залога недоступно'
         );
      end if;
      select count(*)
        into n
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if n > 0 then
         raise_application_error(
            -20088,
            'Идёт аукцион'
         );
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             v."ЗАЛОЖЕНА",
             c."ЦЕНА_ПОКУПКИ",
             v."ID_КЛЕТКИ"
        into
         owner,
         mort,
         price,
         cell
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" = p_ownership_id
         and v."ID_ИГРЫ" = g
      for update;
      amount := ceil(price *(1 + c_mortgage_interest));
      if owner <> p_participant_id
      or mort <> 1
      or bal < amount then
         raise_application_error(
            -20089,
            'Для выкупа нужно 110% первоначальной цены'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - amount
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "ЗАЛОЖЕНА" = 0
       where "ID_ВЛАДЕНИЯ" = p_ownership_id;
      add_action(
         g,
         p_participant_id,
         cell,
         'СНЯТИЕ_ЗАЛОГА',
         amount
      );
   end;
   procedure start_auction (
      p_game_id number,
      p_cell_id number
   ) is
      n     number;
      price number;
      owner number;
      state varchar2(40);
   begin
      select "КОД_СОСТОЯНИЯ_ХОДА"
        into state
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(
            -20090,
            'Аукцион нельзя начать'
         );
      end if;
      select count(*)
        into n
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if n > 0 then
         raise_application_error(
            -20091,
            'Другой аукцион активен'
         );
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             c."ЦЕНА_ПОКУПКИ"
        into
         owner,
         price
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = p_game_id
         and v."ID_КЛЕТКИ" = p_cell_id
      for update;
      if owner is not null then
         raise_application_error(
            -20092,
            'Клетка куплена'
         );
      end if;
      insert into "АУКЦИОНЫ" (
         "ID_ИГРЫ",
         "ID_КЛЕТКИ",
         "КОД_СТАТУСА_АУКЦИОНА",
         "СТАРТ_ЦЕНА",
         "ДАТА_НАЧАЛА"
      ) values
         ( p_game_id,
           p_cell_id,
           'АКТИВЕН',
           floor(price / 2),
           sysdate );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ПРОВЕДЕНИЕ_АУКЦИОНА'
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure make_bid (
      p_auction_id     number,
      p_participant_id number,
      p_amount         number
   ) is      g        number;
      st       varchar2(40);
      startp   number;
      started  date;
      pg       number;
      ps       varchar2(40);
      bal      number;
      init     number;
      eligible number;
      answered number;
   begin
      select "ID_ИГРЫ",
             "КОД_СТАТУСА_АУКЦИОНА",
             "СТАРТ_ЦЕНА",
             "ДАТА_НАЧАЛА"
        into
         g,
         st,
         startp,
         started
        from "АУКЦИОНЫ"
       where "ID_АУКЦИОНА" = p_auction_id
      for update;
      select u."ID_ИГРЫ",
             u."КОД_СТАТУСА_УЧАСТНИКА",
             u."БАЛАНС",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         pg,
         ps,
         bal,
         init
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if st <> 'АКТИВЕН'
      or pg <> g
      or ps <> 'АКТИВЕН'
      or p_participant_id = init then
         raise_application_error(
            -20093,
            'Ставка недоступна'
         );
      end if;
      if sysdate >= started + c_auction_seconds / 86400 then
         raise_application_error(
            -20094,
            'Время истекло'
         );
      end if;
      if
         p_amount <> 0
         and ( p_amount < startp
         or p_amount > bal )
      then
         raise_application_error(
            -20095,
            'Ставка должна быть от стартовой цены до вашего баланса'
         );
      end if;
      merge into "СТАВКИ" s
      using (
         select p_auction_id a,
                p_participant_id p,
                p_amount m
           from dual
      ) x on ( s."ID_АУКЦИОНА" = x.a
         and s."ID_УЧАСТНИКА" = x.p )
      when matched then update
      set s."СУММА" = x.m,
          s."ДАТА_ВРЕМЯ" = sysdate
      when not matched then
      insert (
         "ID_АУКЦИОНА",
         "ID_УЧАСТНИКА",
         "СУММА",
         "ДАТА_ВРЕМЯ" )
      values
         ( x.a,
           x.p,
           x.m,
           sysdate );
      select count(*)
        into eligible
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and "ID_УЧАСТНИКА" <> init;
      select count(*)
        into answered
        from "СТАВКИ" s
        join "УЧАСТНИКИ" u
      on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
       where s."ID_АУКЦИОНА" = p_auction_id
         and u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and s."ID_УЧАСТНИКА" <> init;
      if
         eligible > 0
         and answered = eligible
      then
         close_auction(p_auction_id);
      end if;
   end;
   procedure close_auction (
      p_auction_id number
   ) is      g        number;
      cell     number;
      st       varchar2(40);
      started  date;
      init     number;
      winner   number := null;
      amount   number := null;
      eligible number;
      answered number;
   begin
      select a."ID_ИГРЫ",
             a."ID_КЛЕТКИ",
             a."КОД_СТАТУСА_АУКЦИОНА",
             a."ДАТА_НАЧАЛА",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         g,
         cell,
         st,
         started,
         init
        from "АУКЦИОНЫ" a
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = a."ID_ИГРЫ"
       where a."ID_АУКЦИОНА" = p_auction_id
      for update;
      if st <> 'АКТИВЕН' then
         return;
      end if;
      select count(*)
        into eligible
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and "ID_УЧАСТНИКА" <> init;
      select count(*)
        into answered
        from "СТАВКИ" s
        join "УЧАСТНИКИ" u
      on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
       where s."ID_АУКЦИОНА" = p_auction_id
         and u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and s."ID_УЧАСТНИКА" <> init;
      if
         sysdate < started + c_auction_seconds / 86400
         and not (
            eligible > 0
            and answered = eligible
         )
      then
         raise_application_error(
            -20096,
            'Аукцион ещё идёт'
         );
      end if;
      begin
         select "ID_УЧАСТНИКА",
                "СУММА"
           into
            winner,
            amount
           from (
            select s."ID_УЧАСТНИКА",
                   s."СУММА"
              from "СТАВКИ" s
              join "УЧАСТНИКИ" u
            on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
             where s."ID_АУКЦИОНА" = p_auction_id
               and s."СУММА" > 0
               and s."ID_УЧАСТНИКА" <> init
               and u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
               and u."БАЛАНС" >= s."СУММА"
             order by s."СУММА" desc,
                      s."ДАТА_ВРЕМЯ",
                      s."ID_СТАВКИ"
         )
          where rownum = 1;
      exception
         when no_data_found then
            null;
      end;
      if winner is not null then
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" - amount
          where "ID_УЧАСТНИКА" = winner;
         update "ВЛАДЕНИЯ"
            set
            "ID_ВЛАДЕЛЬЦА" = winner
          where "ID_ИГРЫ" = g
            and "ID_КЛЕТКИ" = cell;
         update "АУКЦИОНЫ"
            set "ID_ПОБЕДИТЕЛЯ" = winner,
                "ФИНАЛ_ЦЕНА" = amount,
                "КОД_СТАТУСА_АУКЦИОНА" = 'ЗАВЕРШЕН',
                "ДАТА_ОКОНЧАНИЯ" = sysdate
          where "ID_АУКЦИОНА" = p_auction_id;
         add_action(
            g,
            winner,
            cell,
            'АУКЦИОН',
            amount
         );
      else
         update "АУКЦИОНЫ"
            set "КОД_СТАТУСА_АУКЦИОНА" = 'НЕ_СОСТОЯЛСЯ',
                "ДАТА_ОКОНЧАНИЯ" = sysdate
          where "ID_АУКЦИОНА" = p_auction_id;
         add_action(
            g,
            null,
            cell,
            'АУКЦИОН',
            null
         );
      end if;
      advance_to_next_player(g);
   end;
   procedure handle_timeout (
      p_game_id number
   ) is
      pid number;
      cnt number;
      bal number;
      gst varchar2(40);
   begin
      select "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into pid
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      select "КОЛ_ТАЙМАУТОВ"
        into cnt
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = pid
      for update;
      if cnt >= 1 then
         update "УЧАСТНИКИ"
            set
            "КОЛ_ТАЙМАУТОВ" = 2
          where "ID_УЧАСТНИКА" = pid;
         add_action(
            p_game_id,
            pid,
            null,
            'ТАЙМ_АУТ',
            null
         );
         declare_bankruptcy(
            pid,
            c_bankruptcy_second_timeout
         );
      else
         update "УЧАСТНИКИ"
            set "КОЛ_ТАЙМАУТОВ" = 1,
                "БАЛАНС" = "БАЛАНС" - c_timeout_penalty
          where "ID_УЧАСТНИКА" = pid;
         add_action(
            p_game_id,
            pid,
            null,
            'ТАЙМ_АУТ',
            c_timeout_penalty
         );
         select "БАЛАНС"
           into bal
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = pid;
         if bal < 0 then
            enter_debt_or_bankruptcy(pid);
         else
            advance_to_next_player(p_game_id);
         end if;
      end if;
   end;
   procedure check_game_timer (
      p_game_id number
   ) is      state   varchar2(40);
      started date;
      gst     varchar2(40);
      aid     number;
      pid     number;
      host_id number;
   begin
      select "КОД_СОСТОЯНИЯ_ХОДА",
             "ВРЕМЯ_НАЧАЛА_ХОДА",
             "КОД_СТАТУСА_ИГРЫ",
             "ID_ТЕКУЩЕГО_УЧАСТНИКА",
             "ID_ХОСТА"
        into
         state,
         started,
         gst,
         pid,
         host_id
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if gst = 'ПРОВЕРКА_ГОТОВНОСТИ' then
         if
            started is not null
            and sysdate >= started + c_ready_seconds / 86400
         then
            start_game(
               p_game_id,
               host_id
            );
         end if;
         return;
      end if;
      if gst <> 'АКТИВНА' then
         return;
      end if;
      if
         state in ( 'ОЖИДАНИЕ_БРОСКА',
                    'ОЖИДАНИЕ_ПОКУПКИ',
                    'ОЖИДАНИЕ_УЛУЧШЕНИЯ',
                    'ЗАВЕРШЕНИЕ_ХОДА' )
         and sysdate >= started + c_turn_minutes / 1440
      then
         handle_timeout(p_game_id);
      elsif
         state = 'ПОКРЫТИЕ_ДОЛГА'
         and sysdate >= started + c_turn_minutes / 1440
      then
         declare_bankruptcy(
            pid,
            c_bankruptcy_debt_timeout
         );
      elsif state = 'ПРОВЕДЕНИЕ_АУКЦИОНА' then
         begin
            select "ID_АУКЦИОНА"
              into aid
              from "АУКЦИОНЫ"
             where "ID_ИГРЫ" = p_game_id
               and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
            close_auction(aid);
         exception
            when no_data_found then
               null;
            when others then
               if sqlcode = -20096 then
                  null;
               else
                  raise;
               end if;
         end;
      end if;
   end;
   procedure finish_game (
      p_game_id   number,
      p_winner_id number default null
   ) is
      st varchar2(40);
      n  number;
   begin
      select "КОД_СТАТУСА_ИГРЫ"
        into st
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id
      for update;
      if st in ( 'ЗАВЕРШЕНА',
                 'ЗАБРОШЕНА' ) then
         return;
      end if;
      if p_winner_id is not null then
         select count(*)
           into n
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = p_winner_id
            and "ID_ИГРЫ" = p_game_id;
         if n = 0 then
            raise_application_error(
               -20100,
               'Победитель из другой игры'
            );
         end if;
      end if;
      update "ИГРЫ"
         set "КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА',
             "ДАТА_ЗАВЕРШЕНИЯ" = sysdate,
             "ID_ПОБЕДИТЕЛЯ" = p_winner_id,
             "ID_ТЕКУЩЕГО_УЧАСТНИКА" = null,
             "КОД_СОСТОЯНИЯ_ХОДА" = null,
             "ВРЕМЯ_НАЧАЛА_ХОДА" = null
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure finish_or_continue (
      p_game_id number
   ) is
      n      number;
      winner number;
   begin
      select count(*)
        into n
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН';
      if n = 1 then
         select "ID_УЧАСТНИКА"
           into winner
           from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = p_game_id
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН';
         finish_game(
            p_game_id,
            winner
         );
      elsif n = 0 then
         finish_game(
            p_game_id,
            null
         );
      end if;
   end;
   procedure declare_bankruptcy (
      p_participant_id number,
      p_reason         varchar2
   ) is
      g     number;
      bal   number;
      cur   number;
      avail number;
      gst   varchar2(40);
   begin
      if p_reason not in ( c_bankruptcy_voluntary,
                           c_bankruptcy_debt_timeout,
                           c_bankruptcy_second_timeout ) then
         raise_application_error(
            -20101,
            'Неизвестная причина'
         );
      end if;
      select u."ID_ИГРЫ",
             u."БАЛАНС",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         g,
         bal,
         cur
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if p_reason = c_bankruptcy_voluntary then
         if bal >= 0 then
            raise_application_error(
               -20102,
               'Нет долга'
            );
         end if;
         select count(*)
           into avail
           from "ВЛАДЕНИЯ"
          where "ID_ВЛАДЕЛЬЦА" = p_participant_id
            and ( "КОЛВО_ДОМОВ" > 0
             or ( "ЗАЛОЖЕНА" = 0
            and "КОЛВО_ДОМОВ" = 0 ) );
         if avail > 0 then
            raise_application_error(
               -20103,
               'Осталось доступное имущество'
            );
         end if;
      end if;
      update "УЧАСТНИКИ"
         set
         "КОД_СТАТУСА_УЧАСТНИКА" = 'БАНКРОТ'
       where "ID_УЧАСТНИКА" = p_participant_id;
      return_properties_to_bank(p_participant_id);
      add_action(
         g,
         p_participant_id,
         null,
         'БАНКРОТСТВО',
         bal
      );
      finish_or_continue(g);
      select "КОД_СТАТУСА_ИГРЫ"
        into gst
        from "ИГРЫ"
       where "ID_ИГРЫ" = g;
      if
         gst = 'АКТИВНА'
         and cur = p_participant_id
      then
         advance_to_next_player(g);
      end if;
   end;
   procedure leave_active_game (
      p_participant_id number
   ) is
      g   number;
      cur number;
      gst varchar2(40);
      n   number;
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         g,
         cur,
         gst
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if gst <> 'АКТИВНА' then
         raise_application_error(
            -20104,
            'Игра не активна'
         );
      end if;
      select count(*)
        into n
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = g
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if n > 0 then
         raise_application_error(
            -20105,
            'Нельзя выйти во время аукциона'
         );
      end if;
      update "УЧАСТНИКИ"
         set
         "КОД_СТАТУСА_УЧАСТНИКА" = 'БАНКРОТ'
       where "ID_УЧАСТНИКА" = p_participant_id;
      return_properties_to_bank(p_participant_id);
      add_action(
         g,
         p_participant_id,
         null,
         'ВЫХОД_УЧАСТНИКА',
         null
      );
      add_action(
         g,
         p_participant_id,
         null,
         'БАНКРОТСТВО',
         null
      );
      finish_or_continue(g);
      select "КОД_СТАТУСА_ИГРЫ"
        into gst
        from "ИГРЫ"
       where "ID_ИГРЫ" = g;
      if
         gst = 'АКТИВНА'
         and cur = p_participant_id
      then
         advance_to_next_player(g);
      end if;
   end;
   procedure disconnect_player (
      p_participant_id number
   ) is
      g   number;
      cur number;
      gst varchar2(40);
   begin
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         g,
         cur,
         gst
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id
      for update;
      if gst <> 'АКТИВНА' then
         return;
      end if;
      update "УЧАСТНИКИ"
         set
         "КОД_СТАТУСА_УЧАСТНИКА" = 'БАНКРОТ'
       where "ID_УЧАСТНИКА" = p_participant_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН';
      if sql%rowcount = 0 then
         return;
      end if;
      return_properties_to_bank(p_participant_id);
      add_action(
         g,
         p_participant_id,
         null,
         'ВЫХОД_УЧАСТНИКА',
         null
      );
      add_action(
         g,
         p_participant_id,
         null,
         'БАНКРОТСТВО',
         null
      );
      finish_or_continue(g);
      select "КОД_СТАТУСА_ИГРЫ"
        into gst
        from "ИГРЫ"
       where "ID_ИГРЫ" = g;
      if
         gst = 'АКТИВНА'
         and cur = p_participant_id
      then
         advance_to_next_player(g);
      end if;
   end;
   procedure send_message (
      p_participant_id number,
      p_text           varchar2
   ) is
      ps varchar2(40);
      gs varchar2(40);
   begin
      if trim(p_text) is null then
         raise_application_error(
            -20110,
            'Пустое сообщение'
         );
      end if;
      select u."КОД_СТАТУСА_УЧАСТНИКА",
             g."КОД_СТАТУСА_ИГРЫ"
        into
         ps,
         gs
        from "УЧАСТНИКИ" u
        join "ИГРЫ" g
      on g."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if ps not in ( 'В_ЛОББИ',
                     'АКТИВЕН' )
      or gs = 'ЗАБРОШЕНА' then
         raise_application_error(
            -20111,
            'Чат недоступен'
         );
      end if;
      insert into "ЧАТ" (
         "ID_УЧАСТНИКА",
         "ТЕКСТ",
         "ДАТА_ВРЕМЯ"
      ) values
         ( p_participant_id,
           trim(p_text),
           sysdate );
   end;
   function get_chat (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
      g  number;
      ps varchar2(40);
   begin
      select "ID_ИГРЫ",
             "КОД_СТАТУСА_УЧАСТНИКА"
        into
         g,
         ps
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      if ps not in ( 'В_ЛОББИ',
                     'АКТИВЕН' ) then
         raise_application_error(
            -20112,
            'Чат недоступен'
         );
      end if;
      open rc for select c."ID_СООБЩЕНИЯ",
                         p."ЛОГИН",
                         c."ТЕКСТ",
                         c."ДАТА_ВРЕМЯ"
                              from "ЧАТ" c
                              join "УЧАСТНИКИ" u
                            on u."ID_УЧАСТНИКА" = c."ID_УЧАСТНИКА"
                              join "ПОЛЬЗОВАТЕЛИ" p
                            on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                  where u."ID_ИГРЫ" = g
                  order by c."ДАТА_ВРЕМЯ",
                           c."ID_СООБЩЕНИЯ";
      return rc;
   end;
   function get_action_log (
      p_participant_id number
   ) return sys_refcursor is
      rc sys_refcursor;
      g  number;
   begin
      g := participant_game(p_participant_id);
      open rc for select *
                                from (
                                 select j."ID_ДЕЙСТВИЯ",
                                        j."ДАТА_ВРЕМЯ",
                                        j."КОД_ДЕЙСТВИЯ",
                                        t."НАИМЕНОВАНИЕ" "ДЕЙСТВИЕ",
                                        p."ЛОГИН",
                                        c."НАЗВАНИЕ" "КЛЕТКА",
                                        j."СУММА",
                                        case
                                           when j."КОД_ДЕЙСТВИЯ" = 'ОПЛАТА_АРЕНДЫ' then
                                              (
                                                 select op."ЛОГИН"
                                                   from "ВЛАДЕНИЯ" v
                                                   join "УЧАСТНИКИ" ou
                                                 on ou."ID_УЧАСТНИКА" = v."ID_ВЛАДЕЛЬЦА"
                                                   join "ПОЛЬЗОВАТЕЛИ" op
                                                 on op."ID_ПОЛЬЗОВАТЕЛЯ" = ou."ID_ПОЛЬЗОВАТЕЛЯ"
                                                  where v."ID_ИГРЫ" = j."ID_ИГРЫ"
                                                    and v."ID_КЛЕТКИ" = j."ID_КЛЕТКИ"
                                              )
                                        end "ПОЛУЧАТЕЛЬ"
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                   left join "УЧАСТНИКИ" u
                                 on u."ID_УЧАСТНИКА" = j."ID_УЧАСТНИКА"
                                   left join "ПОЛЬЗОВАТЕЛИ" p
                                 on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                                   left join "КЛЕТКИ" c
                                 on c."ID_КЛЕТКИ" = j."ID_КЛЕТКИ"
                                   join "ТИПЫ_ДЕЙСТВИЙ" t
                                 on t."КОД_ДЕЙСТВИЯ" = j."КОД_ДЕЙСТВИЯ"
                                  where j."ID_ИГРЫ" = g
                                  order by j."ID_ДЕЙСТВИЯ" desc
                              )
                   where rownum <= 80
                   order by "ID_ДЕЙСТВИЯ";
      return rc;
   end;

   procedure get_game_snapshot (
      p_participant_id  number,
      p_last_action_id  number,
      p_last_message_id number,
      p_known_version   number,
      p_include_static  number,
      p_state           out sys_refcursor,
      p_players         out sys_refcursor,
      p_cells           out sys_refcursor,
      p_ownerships      out sys_refcursor,
      p_actions         out sys_refcursor,
      p_chat            out sys_refcursor
   ) is
      g                number;
      current_revision number;
   begin
      g := participant_game(p_participant_id);
      check_game_timer(g);
      select "ВЕРСИЯ_СОСТОЯНИЯ"
        into current_revision
        from "ИГРЫ"
       where "ID_ИГРЫ" = g;
      p_state := get_game_state(p_participant_id);
      p_players := get_game_participants(p_participant_id);
      open p_cells for select c."ID_КЛЕТКИ",
                              c."ПОЗИЦИЯ",
                              c."НАЗВАНИЕ",
                              c."ТИП",
                              c."ЦВЕТОВАЯ_ГРУППА",
                              c."ЦЕНА_ПОКУПКИ",
                              c."ЦЕНА_ПОКУПКИ" "БАЗОВАЯ_РЕНТА",
                              ceil(c."ЦЕНА_ПОКУПКИ" * 1.25) "РЕНТА_1_ДОМ",
                              ceil(c."ЦЕНА_ПОКУПКИ" * 1.50) "РЕНТА_2_ДОМА",
                              ceil(c."ЦЕНА_ПОКУПКИ" * 1.75) "РЕНТА_ОТЕЛЬ",
                              ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) "ЦЕНА_ДОМА",
                              case
                                 when c."ТИП" = 'Старт' then
                                              c_start_bonus
                              end "БОНУС_СТАРТА"
                                          from "КЛЕТКИ" c
                        where p_include_static = 1
                        order by c."ПОЗИЦИЯ";

      open p_ownerships for select v."ID_КЛЕТКИ",
                                   v."ID_ВЛАДЕНИЯ",
                                   v."ID_ВЛАДЕЛЬЦА",
                                   p."ЛОГИН" "ВЛАДЕЛЕЦ",
                                   v."КОЛВО_ДОМОВ",
                                   v."ЗАЛОЖЕНА",
                                   case
                                      when c."ТИП" = 'Улица'
                                                      and v."ID_ВЛАДЕЛЬЦА" is not null
                                                      and (
                                                      select count(*)
                                                        from "ВЛАДЕНИЯ" vx
                                                        join "КЛЕТКИ" cx
                                                      on cx."ID_КЛЕТКИ" = vx."ID_КЛЕТКИ"
                                                       where vx."ID_ИГРЫ" = g
                                                         and vx."ID_ВЛАДЕЛЬЦА" = v."ID_ВЛАДЕЛЬЦА"
                                                         and vx."ЗАЛОЖЕНА" = 0
                                                         and cx."ЦВЕТОВАЯ_ГРУППА" = c."ЦВЕТОВАЯ_ГРУППА"
                                                   ) = (
                                                      select count(*)
                                                        from "КЛЕТКИ" cg
                                                       where cg."ТИП" = 'Улица'
                                                         and cg."ЦВЕТОВАЯ_ГРУППА" = c."ЦВЕТОВАЯ_ГРУППА"
                                                   ) then
                                                      2
                                      else
                                         1
                                   end "МНОЖИТЕЛЬ_ГРУППЫ"
                                                  from "ВЛАДЕНИЯ" v
                                                  join "КЛЕТКИ" c
                                                on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
                                                  left join "УЧАСТНИКИ" u
                                                on u."ID_УЧАСТНИКА" = v."ID_ВЛАДЕЛЬЦА"
                                                  left join "ПОЛЬЗОВАТЕЛИ" p
                                                on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                            where v."ID_ИГРЫ" = g
                              and current_revision <> nvl(
                              p_known_version,
                              -1
                           );

      open p_actions for select j."ID_ДЕЙСТВИЯ",
                                j."ДАТА_ВРЕМЯ",
                                j."КОД_ДЕЙСТВИЯ",
                                t."НАИМЕНОВАНИЕ" "ДЕЙСТВИЕ",
                                p."ЛОГИН",
                                c."НАЗВАНИЕ" "КЛЕТКА",
                                j."СУММА",
                                j."ТЕКСТ_СОБЫТИЯ",
                                case
                                   when j."КОД_ДЕЙСТВИЯ" = 'ОПЛАТА_АРЕНДЫ' then
                                                (
                                                   select op."ЛОГИН"
                                                     from "ВЛАДЕНИЯ" v
                                                     join "УЧАСТНИКИ" ou
                                                   on ou."ID_УЧАСТНИКА" = v."ID_ВЛАДЕЛЬЦА"
                                                     join "ПОЛЬЗОВАТЕЛИ" op
                                                   on op."ID_ПОЛЬЗОВАТЕЛЯ" = ou."ID_ПОЛЬЗОВАТЕЛЯ"
                                                    where v."ID_ИГРЫ" = j."ID_ИГРЫ"
                                                      and v."ID_КЛЕТКИ" = j."ID_КЛЕТКИ"
                                                )
                                end "ПОЛУЧАТЕЛЬ"
                                            from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                            left join "УЧАСТНИКИ" u
                                          on u."ID_УЧАСТНИКА" = j."ID_УЧАСТНИКА"
                                            left join "ПОЛЬЗОВАТЕЛИ" p
                                          on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                                            left join "КЛЕТКИ" c
                                          on c."ID_КЛЕТКИ" = j."ID_КЛЕТКИ"
                                            join "ТИПЫ_ДЕЙСТВИЙ" t
                                          on t."КОД_ДЕЙСТВИЯ" = j."КОД_ДЕЙСТВИЯ"
                         where j."ID_ИГРЫ" = g
                           and j."ID_ДЕЙСТВИЯ" > nvl(
                           p_last_action_id,
                           0
                        )
                         order by j."ID_ДЕЙСТВИЯ";

      open p_chat for select ch."ID_СООБЩЕНИЯ",
                             p."ЛОГИН",
                             ch."ТЕКСТ",
                             ch."ДАТА_ВРЕМЯ"
                                      from "ЧАТ" ch
                                      join "УЧАСТНИКИ" u
                                    on u."ID_УЧАСТНИКА" = ch."ID_УЧАСТНИКА"
                                      join "ПОЛЬЗОВАТЕЛИ" p
                                    on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                      where u."ID_ИГРЫ" = g
                        and ch."ID_СООБЩЕНИЯ" > nvl(
                        p_last_message_id,
                        0
                     )
                      order by ch."ID_СООБЩЕНИЯ";
   end;
   function get_player_stats (
      p_user_id number
   ) return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for with played as (
                                 select u."ID_УЧАСТНИКА",
                                        u."ID_ИГРЫ",
                                        g."ID_ПОБЕДИТЕЛЯ"
                                   from "УЧАСТНИКИ" u
                                   join "ИГРЫ" g
                                 on g."ID_ИГРЫ" = u."ID_ИГРЫ"
                                  where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                                    and u."ОЧЕРЕДЬ_ХОДА" is not null
                                    and g."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                              ),fav as (
                                 select c."НАЗВАНИЕ",
                                        count(*) cnt,
                                        row_number()
                                        over(
                                            order by count(*) desc,
                                                     c."ПОЗИЦИЯ"
                                        ) rn
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                   join "УЧАСТНИКИ" u
                                 on u."ID_УЧАСТНИКА" = j."ID_УЧАСТНИКА"
                                   join "КЛЕТКИ" c
                                 on c."ID_КЛЕТКИ" = j."ID_КЛЕТКИ"
                                   join "ИГРЫ" g
                                 on g."ID_ИГРЫ" = j."ID_ИГРЫ"
                                  where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                                    and j."КОД_ДЕЙСТВИЯ" = 'ПОСЕЩЕНИЕ_КЛЕТКИ'
                                    and g."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                                  group by c."НАЗВАНИЕ",
                                           c."ПОЗИЦИЯ"
                              )
                              select p."ЛОГИН",
                                     count(pl."ID_ИГРЫ") "КОЛИЧЕСТВО_ИГР",
                                     nvl(
                                        sum(
                                           case
                                              when pl."ID_ПОБЕДИТЕЛЯ" = pl."ID_УЧАСТНИКА" then
                                                 1
                                              else
                                                 0
                                           end
                                        ),
                                        0
                                     ) "ПОБЕДЫ",
                                     case
                                        when count(pl."ID_ИГРЫ") = 0 then
                                           0
                                        else
                                           round(
                                              100 * sum(
                                                 case
                                                    when pl."ID_ПОБЕДИТЕЛЯ" = pl."ID_УЧАСТНИКА" then
                                                       1
                                                    else
                                                       0
                                                 end
                                              ) / count(pl."ID_ИГРЫ"),
                                              2
                                           )
                                     end "ПРОЦЕНТ_ПОБЕД",
                                     (
                                        select "НАЗВАНИЕ"
                                          from fav
                                         where rn = 1
                                     ) "ЛЮБИМАЯ_КЛЕТКА"
                                from "ПОЛЬЗОВАТЕЛИ" p
                                left join played pl
                              on 1 = 1
                   where p."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                   group by p."ЛОГИН";
      return rc;
   end;
   function get_leaderboard return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for select p."ID_ПОЛЬЗОВАТЕЛЯ",
                         p."ЛОГИН",
                         count(g."ID_ИГРЫ") "ИГРЫ",
                         nvl(
                                 sum(
                                    case
                                       when g."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                          1
                                       else
                                          0
                                    end
                                 ),
                                 0
                              ) "ПОБЕДЫ",
                         case
                            when count(g."ID_ИГРЫ") = 0 then
                                    0
                            else
                               round(
                                       100 * sum(
                                          case
                                             when g."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                                1
                                             else
                                                0
                                          end
                                       ) / count(g."ID_ИГРЫ"),
                                       2
                                    )
                         end "ПРОЦЕНТ"
                                from "ПОЛЬЗОВАТЕЛИ" p
                                left join "УЧАСТНИКИ" u
                              on u."ID_ПОЛЬЗОВАТЕЛЯ" = p."ID_ПОЛЬЗОВАТЕЛЯ"
                                 and u."ОЧЕРЕДЬ_ХОДА" is not null
                                left join "ИГРЫ" g
                              on g."ID_ИГРЫ" = u."ID_ИГРЫ"
                                 and g."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                   group by p."ID_ПОЛЬЗОВАТЕЛЯ",
                            p."ЛОГИН"
                   order by "ПРОЦЕНТ" desc,
                            "ПОБЕДЫ" desc,
                            "ИГРЫ" desc,
                            p."ЛОГИН";
      return rc;
   end;
   function get_game_history (
      p_user_id number
   ) return sys_refcursor is
      rc sys_refcursor;
   begin
      open rc for select g."ID_ИГРЫ",
                         g."НАЗВАНИЕ",
                         g."ДАТА_СТАРТА",
                         g."ДАТА_ЗАВЕРШЕНИЯ",
                         u."БАЛАНС" "ИТОГОВЫЙ_БАЛАНС",
                         u."КОД_СТАТУСА_УЧАСТНИКА",
                         wp."ЛОГИН" "ПОБЕДИТЕЛЬ",
                         case
                            when g."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                    'Победа'
                            else
                               'Поражение'
                         end "РЕЗУЛЬТАТ"
                                from "УЧАСТНИКИ" u
                                join "ИГРЫ" g
                              on g."ID_ИГРЫ" = u."ID_ИГРЫ"
                                left join "УЧАСТНИКИ" wu
                              on wu."ID_УЧАСТНИКА" = g."ID_ПОБЕДИТЕЛЯ"
                                left join "ПОЛЬЗОВАТЕЛИ" wp
                              on wp."ID_ПОЛЬЗОВАТЕЛЯ" = wu."ID_ПОЛЬЗОВАТЕЛЯ"
                   where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                     and u."ОЧЕРЕДЬ_ХОДА" is not null
                     and g."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                   order by g."ДАТА_ЗАВЕРШЕНИЯ" desc;
      return rc;
   end;
end monopoly;
/
SHOW ERRORS PACKAGE BODY monopoly;