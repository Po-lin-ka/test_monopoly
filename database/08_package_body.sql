create or replace package body monopoly as
   c_bankruptcy_debt_timeout constant varchar2(100) := 'ИСТЕКЛО_ВРЕМЯ_ПОКРЫТИЯ_ДОЛГА';
   c_bankruptcy_second_timeout constant varchar2(100) := 'ПОВТОРНЫЙ_ТАЙМ_АУТ';
   procedure add_action (
      p_game_id        number,
      p_participant_id number default null,
      p_cell_id        number default null,
      p_action_code    varchar2,
      p_amount         number default null,
      p_event_text     varchar2 default null
   );
   procedure return_properties_to_bank (
      p_participant_id number
   );
   procedure enter_debt_or_bankruptcy (
      p_participant_id number
   );
   procedure start_game (
      p_game_id      number,
      p_host_user_id number
   );
   procedure process_cell (
      p_participant_id number,
      p_dice           number
   );
   procedure advance_to_next_player (
      p_game_id number
   );
   function calculate_rent (
      p_ownership_id number,
      p_dice         number
   ) return number;
   procedure pay_rent (
      p_participant_id number,
      p_cell_id        number,
      p_dice           number
   );
   procedure apply_chance (
      p_participant_id number,
      p_dice           number
   );
   procedure start_auction (
      p_game_id number,
      p_cell_id number
   );
   procedure close_auction (
      p_auction_id number,
      p_force boolean default false
   );
   procedure handle_timeout (
      p_game_id number
   );
   procedure check_game_timer (
      p_game_id number
   );
   procedure finish_game (
      p_game_id   number,
      p_winner_id number default null
   );
   procedure finish_or_continue (
      p_game_id number
   );
   procedure declare_bankruptcy (
      p_participant_id number,
      p_reason         varchar2
   );

   procedure process_properties (
      p_participant_id number,
      p_mortgage_ids number_list,
      p_sale_ids number_list,
      p_sale_before_roll boolean default false
   );

   function participant_game (
      v_participant_id number
   ) return number is
      v_game_id number;
   begin
      select "ID_ИГРЫ"
        into v_game_id
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = v_participant_id;
      return v_game_id;
   exception
      when no_data_found then
         raise_application_error(-20001, 'Участник не найден');
   end;
   -- Все изменения одной партии сначала блокируют её строку.
   procedure lock_game(p_game_id number) is
      v_game_id number;
   begin
      select "ID_ИГРЫ" into v_game_id
        from "ИГРЫ" where "ID_ИГРЫ" = p_game_id
        for update;
   end;

   procedure lock_user(p_user_id number) is
      v_user_id number;
   begin
      select "ID_ПОЛЬЗОВАТЕЛЯ" into v_user_id
        from "ПОЛЬЗОВАТЕЛИ" where "ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
        for update;
   exception
      when no_data_found then
         raise_application_error(-20022, 'Пользователь не найден');
   end;

   function lock_participant_game(p_participant_id number) return number is
      v_game_id number;
   begin
      v_game_id := participant_game(p_participant_id);
      lock_game(v_game_id);
      return v_game_id;
   end;

   -- Вызывается после блокировки игры, до любых изменений команды.
   -- Штраф и переход хода выполняет snapshot отдельной транзакцией.
   procedure require_turn_time(p_game_id number) is
      v_game_status varchar2(40);
      v_turn_state varchar2(40);
      v_started date;
   begin
      select "КОД_СТАТУСА_ИГРЫ", "КОД_СОСТОЯНИЯ_ХОДА", "ВРЕМЯ_НАЧАЛА_ХОДА"
        into v_game_status, v_turn_state, v_started
        from "ИГРЫ" where "ID_ИГРЫ" = p_game_id;
      if v_game_status = 'АКТИВНА'
         and v_turn_state in ('ОЖИДАНИЕ_БРОСКА', 'ОЖИДАНИЕ_ПОКУПКИ',
                              'ОЖИДАНИЕ_УЛУЧШЕНИЯ', 'ЗАВЕРШЕНИЕ_ХОДА',
                              'ПОКРЫТИЕ_ДОЛГА')
         and sysdate >= v_started + c_turn_minutes / 1440 then
         raise_application_error(-20125, 'Время хода истекло. Обновите состояние игры');
      end if;
   end;

   function require_current_player(p_participant_id number) return number is
      v_game_id number;
      v_count number;
   begin
      v_game_id := lock_participant_game(p_participant_id);
      select count(*) into v_count
        from "ИГРЫ" games join "УЧАСТНИКИ" u
          on u."ID_УЧАСТНИКА" = games."ID_ТЕКУЩЕГО_УЧАСТНИКА"
       where games."ID_ИГРЫ" = v_game_id
         and games."КОД_СТАТУСА_ИГРЫ" = 'АКТИВНА'
         and u."ID_УЧАСТНИКА" = p_participant_id
         and u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН';
      if v_count = 0 then
         raise_application_error(-20124, 'Действие доступно только текущему активному игроку');
      end if;
      require_turn_time(v_game_id);
      return v_game_id;
   end;

   procedure add_action (
      p_game_id        number,
      p_participant_id number default null,
      p_cell_id        number default null,
      p_action_code    varchar2,
      p_amount         number default null,
      p_event_text     varchar2 default null
   ) is
      v_count number;
   begin
      if p_participant_id is not null then
         select count(*)
           into v_count
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = p_participant_id
            and "ID_ИГРЫ" = p_game_id;
         if v_count = 0 then
            raise_application_error(-20002, 'Участник не относится к игре');
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
      v_game_id number;
      v_balance number;
      available number;
   begin
      v_game_id := participant_game(p_participant_id);
      select "БАЛАНС"
        into v_balance
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      if v_balance >= 0 then
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = v_game_id;
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
         -- По правилам проекта частичное погашение даёт новый срок.
         update "ИГРЫ"
            set "КОД_СОСТОЯНИЯ_ХОДА" = 'ПОКРЫТИЕ_ДОЛГА',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate
          where "ID_ИГРЫ" = v_game_id;
      end if;
   end;

   procedure register_user (
      p_login    varchar2,
      p_password varchar2
   ) is
      password_hash "ПОЛЬЗОВАТЕЛИ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      if trim(p_login) is null
      or p_password is null then
         raise_application_error(-20010, 'Логин и пароль обязательны');
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
         raise_application_error(-20011, 'Логин уже занят');
   end;
   function authenticate_user (
      p_login    varchar2,
      p_password varchar2
   ) return number is
      id number;
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
         raise_application_error(-20012, 'Неверный логин или пароль');
   end;

   procedure create_game (
      p_user_id       number,
      p_game_name     varchar2,
      p_max_players   number default 4,
      p_room_password varchar2 default null,
      p_game_id       out number
   ) is
      v_count number;
      start_id number;
      room_password_hash "ИГРЫ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      lock_user(p_user_id);
      if p_max_players is null or p_max_players <> trunc(p_max_players)
      or p_max_players not between 2 and 4 then
         raise_application_error(-20020, 'Количество игроков: 2–4');
      end if;
      if trim(p_game_name) is null then
         raise_application_error(-20021, 'Название обязательно');
      end if;
      select count(*)
        into v_count
        from "УЧАСТНИКИ" u
        join "ИГРЫ" games
      on games."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
         and games."КОД_СТАТУСА_ИГРЫ" in ( 'ОЖИДАНИЕ',
                                       'ПРОВЕРКА_ГОТОВНОСТИ',
                                       'АКТИВНА' )
         and u."КОД_СТАТУСА_УЧАСТНИКА" in ( 'В_ЛОББИ',
                                            'АКТИВЕН' );
      if v_count > 0 then
         raise_application_error(-20023, 'Пользователь уже в незавершённой игре');
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
           c_start_fund,
           'В_ЛОББИ',
           0,
           0 );
   end;
   function list_waiting_games return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for select games."ID_ИГРЫ",
                         games."НАЗВАНИЕ",
                         games."МАКС_ИГРОКОВ",
                         count(
                                 case
                                    when u."КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ' then
                                       1
                                 end
                              ) "ЗАНЯТО",
                         case
                            when games."ПАРОЛЬ_ХЭШ" is null then
                                    0
                            else
                               1
                         end "ЕСТЬ_ПАРОЛЬ"
                                from "ИГРЫ" games
                                left join "УЧАСТНИКИ" u
                              on u."ID_ИГРЫ" = games."ID_ИГРЫ"
                   where games."КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ'
                   group by games."ID_ИГРЫ",
                            games."НАЗВАНИЕ",
                            games."МАКС_ИГРОКОВ",
                            games."ПАРОЛЬ_ХЭШ",
                            games."ДАТА_СОЗДАНИЯ"
                  having count(
                     case
                        when u."КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ' then
                           1
                     end
                  ) < games."МАКС_ИГРОКОВ"
                   order by games."ДАТА_СОЗДАНИЯ" desc;
      return v_result;
   end;
   procedure join_game (
      p_user_id       number,
      p_game_id       number,
      p_room_password varchar2 default null
   ) is
      v_status varchar2(40);
      v_room_password_hash varchar2(255);
      v_max_players number;
      v_count number;
      v_start_cell_id number;
      v_player_status varchar2(40);
      v_participant_id number;
      entered_password_hash "ИГРЫ"."ПАРОЛЬ_ХЭШ"%type;
   begin
      lock_user(p_user_id);
      lock_game(p_game_id);
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
         v_status,
         v_room_password_hash,
         v_max_players
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_status <> 'ОЖИДАНИЕ' then
         raise_application_error(-20030, 'Комната недоступна');
      end if;
      if
         v_room_password_hash is not null
         and (entered_password_hash is null or v_room_password_hash <> entered_password_hash)
      then
         raise_application_error(-20031, 'Неверный пароль');
      end if;
      select count(*)
        into v_count
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if v_count >= v_max_players then
         raise_application_error(-20032, 'Комната заполнена');
      end if;
      select count(*)
        into v_count
        from "УЧАСТНИКИ" u
        join "ИГРЫ" games
      on games."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
         and games."ID_ИГРЫ" <> p_game_id
         and games."КОД_СТАТУСА_ИГРЫ" in ( 'ОЖИДАНИЕ',
                                       'ПРОВЕРКА_ГОТОВНОСТИ',
                                       'АКТИВНА' )
         and u."КОД_СТАТУСА_УЧАСТНИКА" in ( 'В_ЛОББИ',
                                            'АКТИВЕН' );
      if v_count > 0 then
         raise_application_error(-20033, 'Пользователь уже в другой игре');
      end if;
      select "ID_КЛЕТКИ"
        into v_start_cell_id
        from "КЛЕТКИ"
       where "ПОЗИЦИЯ" = 1;
      begin
         select "ID_УЧАСТНИКА",
                "КОД_СТАТУСА_УЧАСТНИКА"
           into
            v_participant_id,
            v_player_status
           from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = p_game_id
            and "ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id;
         if v_player_status = 'ИСКЛЮЧЕН' then
            raise_application_error(-20034, 'Повторный вход запрещён');
         end if;
         if v_player_status <> 'ПОКИНУЛ' then
            raise_application_error(-20035, 'Вы уже в комнате');
         end if;
         update "УЧАСТНИКИ"
            set "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ',
                "ГОТОВ" = 0,
                "ОЧЕРЕДЬ_ХОДА" = null,
                "КОЛ_ТАЙМАУТОВ" = 0,
                "БАЛАНС" = c_start_fund,
                "ID_ПОЗИЦИИ" = v_start_cell_id
          where "ID_УЧАСТНИКА" = v_participant_id;
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
                 v_start_cell_id,
                 c_start_fund,
                 'В_ЛОББИ' );
      end;
   end;
   procedure abandon_waiting_game (
      p_user_id number,
      p_game_id number
   ) is
      v_host_user_id number;
      v_status varchar2(40);
   begin
      lock_game(p_game_id);
      select "ID_ХОСТА",
             "КОД_СТАТУСА_ИГРЫ"
        into
         v_host_user_id,
         v_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if p_user_id is null or v_host_user_id <> p_user_id
      or v_status not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(-20040, 'Нельзя забросить игру');
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
      v_game_id number;
      v_user_id number;
      v_host_user_id number;
      v_status varchar2(40);
   begin
      v_game_id := lock_participant_game(p_participant_id);
      select u."ID_ИГРЫ",
             u."ID_ПОЛЬЗОВАТЕЛЯ",
             x."ID_ХОСТА",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         v_game_id,
         v_user_id,
         v_host_user_id,
         v_status
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_user_id = v_host_user_id then
         abandon_waiting_game(
            v_user_id,
            v_game_id
         );
         return;
      end if;
      if v_status not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(-20041, 'Игра уже началась');
      end if;
      update "УЧАСТНИКИ"
         set "КОД_СТАТУСА_УЧАСТНИКА" = 'ПОКИНУЛ',
             "ГОТОВ" = 0
       where "ID_УЧАСТНИКА" = p_participant_id;
      if v_status = 'ПРОВЕРКА_ГОТОВНОСТИ' then
         update "ИГРЫ"
            set
            "КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ'
          where "ID_ИГРЫ" = v_game_id;
         update "УЧАСТНИКИ"
            set
            "ГОТОВ" = 0
          where "ID_ИГРЫ" = v_game_id
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      end if;
   end;
   procedure set_ready (
      p_participant_id number,
      p_ready          number
   ) is
      v_game_id number;
      v_status varchar2(40);
      v_count number;
      ready number;
   begin
      v_game_id := lock_participant_game(p_participant_id);
      if p_ready is null or p_ready not in ( 0,
                          1 ) then
         raise_application_error(-20047, 'Готовность: 0 или 1');
      end if;
      select u."ID_ИГРЫ",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         v_game_id,
         v_status
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_status not in ( 'ОЖИДАНИЕ',
                     'ПРОВЕРКА_ГОТОВНОСТИ' ) then
         raise_application_error(-20048, 'Готовность сейчас недоступна');
      end if;
      update "УЧАСТНИКИ"
         set
         "ГОТОВ" = p_ready
       where "ID_УЧАСТНИКА" = p_participant_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if sql%rowcount = 0 then
         raise_application_error(-20049, 'Участник не находится в комнате');
      end if;
      if p_ready = 1 then
         add_action(
            v_game_id,
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
         v_count,
         ready
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = v_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if
         v_count >= 2
         and ready = v_count
      then
         update "ИГРЫ"
            set "КОД_СТАТУСА_ИГРЫ" = 'ПРОВЕРКА_ГОТОВНОСТИ',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate
          where "ID_ИГРЫ" = v_game_id;
      else
         update "ИГРЫ"
            set "КОД_СТАТУСА_ИГРЫ" = 'ОЖИДАНИЕ',
                "ВРЕМЯ_НАЧАЛА_ХОДА" = null
          where "ID_ИГРЫ" = v_game_id;
      end if;
   end;
   procedure start_game (
      p_game_id      number,
      p_host_user_id number
   ) is
      v_host_user_id number;
      v_status varchar2(40);
      v_count number;
      ready number;
      first_id number;
      turn_number number := 0;
   begin
      select "ID_ХОСТА",
             "КОД_СТАТУСА_ИГРЫ"
        into
         v_host_user_id,
         v_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_host_user_id <> p_host_user_id
      or v_status <> 'ПРОВЕРКА_ГОТОВНОСТИ' then
         raise_application_error(-20050, 'Игра не готова');
      end if;
      select count(*),
             sum("ГОТОВ")
        into
         v_count,
         ready
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ';
      if v_count not between 2 and 4
      or ready <> v_count then
         raise_application_error(-20051, 'Не все готовы');
      end if;
      update "УЧАСТНИКИ"
         set
         "ОЧЕРЕДЬ_ХОДА" = null
       where "ID_ИГРЫ" = p_game_id;
      for player in (
         select "ID_УЧАСТНИКА" from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = p_game_id and "КОД_СТАТУСА_УЧАСТНИКА" = 'В_ЛОББИ'
          order by dbms_random.value, "ID_УЧАСТНИКА"
      ) loop
         turn_number := turn_number + 1;
         update "УЧАСТНИКИ"
            set "ОЧЕРЕДЬ_ХОДА" = turn_number,
                "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН',
                "БАЛАНС" = floor(c_start_fund / v_count),
                "КОЛ_ТАЙМАУТОВ" = 0, "ГОТОВ" = 1,
                "ПОСЛЕДНЯЯ_СВЯЗЬ" = sysdate
          where "ID_УЧАСТНИКА" = player."ID_УЧАСТНИКА";
      end loop;
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
             "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_БРОСКА'
       where "ID_ИГРЫ" = p_game_id;
   end;

   function get_game_state (
      p_participant_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for select games."ID_ИГРЫ",
                         games."НАЗВАНИЕ",
                         games."КОД_СТАТУСА_ИГРЫ",
                         sg."НАИМЕНОВАНИЕ" "СТАТУС_ИГРЫ",
                         games."КОД_СОСТОЯНИЯ_ХОДА",
                         sh."НАИМЕНОВАНИЕ" "СОСТОЯНИЕ_ХОДА",
                         games."ID_ТЕКУЩЕГО_УЧАСТНИКА",
                         games."ID_ПОБЕДИТЕЛЯ",
                         games."ВРЕМЯ_НАЧАЛА_ХОДА",
                         games."ДАТА_СТАРТА",
                         games."ДАТА_ЗАВЕРШЕНИЯ",
                         games."ID_ХОСТА",
                         games."МАКС_ИГРОКОВ",
                         a."ID_АУКЦИОНА",
                         ca."НАЗВАНИЕ" "АУКЦИОН_КЛЕТКА",
                         a."СТАРТ_ЦЕНА",
                         bid."СУММА" "МОЯ_СТАВКА",
                         (
                                 select max(j."ТЕКСТ_СОБЫТИЯ") keep(dense_rank last order by j."ID_ДЕЙСТВИЯ")
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                  where j."ID_ИГРЫ" = games."ID_ИГРЫ"
                                    and j."КОД_ДЕЙСТВИЯ" = 'КАРТА_ШАНСА'
                                    and j."ID_ДЕЙСТВИЯ" > nvl(
                                    (
                                       select max(jd."ID_ДЕЙСТВИЯ")
                                         from "ЖУРНАЛ_ДЕЙСТВИЙ" jd
                                        where jd."ID_ИГРЫ" = games."ID_ИГРЫ"
                                          and jd."КОД_ДЕЙСТВИЯ" = 'БРОСОК_КУБИКА'
                                    ),
                                    0
                                 )
                              ) "ПОСЛЕДНЯЯ_КАРТА_ШАНСА",
                         case
                            when games."КОД_СТАТУСА_ИГРЫ" = 'ПРОВЕРКА_ГОТОВНОСТИ' then
                                    greatest(
                                       0,
                                       ceil(c_ready_seconds -(sysdate - games."ВРЕМЯ_НАЧАЛА_ХОДА") * 86400)
                                    )
                         end "СЕКУНД_ДО_СТАРТА",
                         case
                            when games."КОД_СТАТУСА_ИГРЫ" = 'АКТИВНА'
                                    and games."ВРЕМЯ_НАЧАЛА_ХОДА" is not null then
                                    greatest(
                                       0,
                                       ceil(c_turn_minutes * 60 -(sysdate - games."ВРЕМЯ_НАЧАЛА_ХОДА") * 86400)
                                    )
                         end "СЕКУНД_ХОДА",
                         (
                                 select max(j."СУММА") keep(dense_rank last order by j."ID_ДЕЙСТВИЯ")
                                   from "ЖУРНАЛ_ДЕЙСТВИЙ" j
                                  where j."ID_ИГРЫ" = games."ID_ИГРЫ"
                                    and j."КОД_ДЕЙСТВИЯ" = 'БРОСОК_КУБИКА'
                              ) "ПОСЛЕДНИЙ_КУБИК"
                                from "УЧАСТНИКИ" me
                                join "ИГРЫ" games
                              on games."ID_ИГРЫ" = me."ID_ИГРЫ"
                                join "СТАТУСЫ_ИГР" sg
                              on sg."КОД_СТАТУСА_ИГРЫ" = games."КОД_СТАТУСА_ИГРЫ"
                                left join "СОСТОЯНИЯ_ХОДА" sh
                              on sh."КОД_СОСТОЯНИЯ_ХОДА" = games."КОД_СОСТОЯНИЯ_ХОДА"
                                left join "АУКЦИОНЫ" a
                              on a."ID_ИГРЫ" = games."ID_ИГРЫ" and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                                left join "КЛЕТКИ" ca on ca."ID_КЛЕТКИ" = a."ID_КЛЕТКИ"
                                left join "СТАВКИ" bid on bid."ID_АУКЦИОНА" = a."ID_АУКЦИОНА"
                                 and bid."ID_УЧАСТНИКА" = me."ID_УЧАСТНИКА"
                   where me."ID_УЧАСТНИКА" = p_participant_id;
      return v_result;
   end;
   function get_game_participants (
      p_participant_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
      v_game_id number;
   begin
      v_game_id := participant_game(p_participant_id);
      open v_result for select u."ID_УЧАСТНИКА",
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
                   where u."ID_ИГРЫ" = v_game_id
                   order by nvl(
                     u."ОЧЕРЕДЬ_ХОДА",
                     99
                  ),
                            u."ID_УЧАСТНИКА";
      return v_result;
   end;
   function get_player_properties (
      p_participant_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for select v."ID_ВЛАДЕНИЯ",
                         c."ID_КЛЕТКИ",
                         c."НАЗВАНИЕ",
                         c."ТИП",
                         v."КОЛВО_ДОМОВ",
                         v."ЗАЛОЖЕНА",
                         c."ЦЕНА_ПОКУПКИ",
                         floor(c."ЦЕНА_ПОКУПКИ" / 2) "ЗАЛОГОВАЯ_СТОИМОСТЬ",
                         floor(ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) / 2) "СТОИМОСТЬ_ПРОДАЖИ_УРОВНЯ",
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
      return v_result;
   end;
   function get_active_auction (
      p_participant_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
      v_game_id number;
   begin
      v_game_id := participant_game(p_participant_id);
      open v_result for select a."ID_АУКЦИОНА",
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
                   where a."ID_ИГРЫ" = v_game_id
                     and a."КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН'
                   order by s."СУММА" desc nulls last,
                            s."ДАТА_ВРЕМЯ";
      return v_result;
   end;
   procedure roll_and_move (
      p_participant_id number,
      p_dice           out number
   ) is
      v_game_id number;
      v_turn_state varchar2(40);
      v_balance number;
      v_position number;
      v_new_position number;
      v_cell_id number;
      bonus number := 0;
   begin
      v_game_id := require_current_player(p_participant_id);
      select x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС",
             c."ПОЗИЦИЯ"
        into
         v_turn_state,
         v_balance,
         v_position
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_БРОСКА'
      or v_balance < 0 then
         raise_application_error(-20060, 'Бросок запрещён');
      end if;
      p_dice := trunc(dbms_random.value(
         1,
         7
      ));
      v_new_position := mod(
         v_position - 1 + p_dice,
         12
      ) + 1;
      if v_position - 1 + p_dice >= 12 then
         bonus := c_start_bonus;
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" + bonus
          where "ID_УЧАСТНИКА" = p_participant_id;
      end if;
      select "ID_КЛЕТКИ"
        into v_cell_id
        from "КЛЕТКИ"
       where "ПОЗИЦИЯ" = v_new_position;
      update "УЧАСТНИКИ"
         set
         "ID_ПОЗИЦИИ" = v_cell_id
       where "ID_УЧАСТНИКА" = p_participant_id;
      add_action(
         v_game_id,
         p_participant_id,
         null,
         'БРОСОК_КУБИКА',
         p_dice
      );
      add_action(
         v_game_id,
         p_participant_id,
         v_cell_id,
         'ПОСЕЩЕНИЕ_КЛЕТКИ',
         null
      );
      if bonus > 0 then
         add_action(
            v_game_id,
            p_participant_id,
            v_cell_id,
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
   ) is
      v_game_id number;
      v_cell_id number;
      v_cell_type varchar2(30);
      v_owner_id number;
      v_mortgaged number;
      v_level number;
   begin
      select u."ID_ИГРЫ",
             u."ID_ПОЗИЦИИ",
             c."ТИП"
        into
         v_game_id,
         v_cell_id,
         v_cell_type
        from "УЧАСТНИКИ" u
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_cell_type = 'Старт' then
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = v_game_id;
      elsif v_cell_type = 'Шанс' then
         apply_chance(
            p_participant_id,
            p_dice
         );
      else
         select "ID_ВЛАДЕЛЬЦА",
                "ЗАЛОЖЕНА",
                "КОЛВО_ДОМОВ"
           into
            v_owner_id,
            v_mortgaged,
            v_level
           from "ВЛАДЕНИЯ"
          where "ID_ИГРЫ" = v_game_id
            and "ID_КЛЕТКИ" = v_cell_id;
         if v_owner_id is null then
            update "ИГРЫ"
               set
               "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_ПОКУПКИ'
             where "ID_ИГРЫ" = v_game_id;
         elsif v_owner_id <> p_participant_id then
            if v_mortgaged = 1 then
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
                where "ID_ИГРЫ" = v_game_id;
            else
               pay_rent(
                  p_participant_id,
                  v_cell_id,
                  p_dice
               );
            end if;
         else
            if
               v_cell_type = 'Улица'
               and v_mortgaged = 0
               and v_level < 3
            then
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
                where "ID_ИГРЫ" = v_game_id;
            else
               update "ИГРЫ"
                  set
                  "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
                where "ID_ИГРЫ" = v_game_id;
            end if;
         end if;
      end if;
   end;
   procedure advance_to_next_player (
      p_game_id number
   ) is
      v_current_player_id number;
      v_turn_order number;
      v_next_player_id number;
   begin
      select "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into v_current_player_id
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      select "ОЧЕРЕДЬ_ХОДА"
        into v_turn_order
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = v_current_player_id;
      begin
         select "ID_УЧАСТНИКА"
           into v_next_player_id
           from (
            select "ID_УЧАСТНИКА"
              from "УЧАСТНИКИ"
             where "ID_ИГРЫ" = p_game_id
               and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
               and "ОЧЕРЕДЬ_ХОДА" > v_turn_order
             order by "ОЧЕРЕДЬ_ХОДА"
         )
          where rownum = 1;
      exception
         when no_data_found then
            select "ID_УЧАСТНИКА"
              into v_next_player_id
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
         set "ID_ТЕКУЩЕГО_УЧАСТНИКА" = v_next_player_id,
             "ВРЕМЯ_НАЧАЛА_ХОДА" = sysdate,
             "КОД_СОСТОЯНИЯ_ХОДА" = 'ОЖИДАНИЕ_БРОСКА'
       where "ID_ИГРЫ" = p_game_id;
   end;
   procedure end_turn (
      p_game_id number
   ) is
      v_turn_state varchar2(40);
      v_current_player_id number;
      v_balance number;
      v_status varchar2(40);
   begin
      lock_game(p_game_id);
      require_turn_time(p_game_id);
      select "КОД_СОСТОЯНИЯ_ХОДА",
             "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         v_turn_state,
         v_current_player_id
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_turn_state is null or v_turn_state <> 'ЗАВЕРШЕНИЕ_ХОДА' then
         raise_application_error(-20062, 'Ход не завершён');
      end if;
      select "БАЛАНС"
        into v_balance
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = v_current_player_id;
      if v_balance < 0 then
         raise_application_error(-20063, 'Сначала покройте долг');
      end if;
      finish_or_continue(p_game_id);
      select "КОД_СТАТУСА_ИГРЫ"
        into v_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_status = 'АКТИВНА' then
         advance_to_next_player(p_game_id);
      end if;
   end;

   procedure buy_property (
      p_participant_id number
   ) is
      current_cell_id number;
      v_game_id number;
      v_turn_state varchar2(40);
      v_owner_id number;
      v_price number;
      v_balance number;
      v_cell_type varchar2(30);
   begin
      v_game_id := require_current_player(p_participant_id);
      select u."ID_ПОЗИЦИИ", x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         current_cell_id,
         v_turn_state,
         v_balance
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(-20070, 'Покупка недоступна');
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             c."ЦЕНА_ПОКУПКИ",
             c."ТИП"
        into
         v_owner_id,
         v_price,
         v_cell_type
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = v_game_id
         and v."ID_КЛЕТКИ" = current_cell_id;
      if v_owner_id is not null
      or v_cell_type not in ( 'Улица',
                      'Коммунальная' )
      or v_balance < v_price then
         raise_application_error(-20071, 'Клетку нельзя купить');
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - v_price
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "ID_ВЛАДЕЛЬЦА" = p_participant_id
       where "ID_ИГРЫ" = v_game_id
         and "ID_КЛЕТКИ" = current_cell_id;
      add_action(
         v_game_id,
         p_participant_id,
         current_cell_id,
         'ПОКУПКА_СОБСТВЕННОСТИ',
         v_price
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = v_game_id;
   end;
   procedure decline_purchase (
      p_participant_id number
   ) is
      current_cell_id number;
      v_game_id number;
      v_turn_state varchar2(40);
      v_owner_id number;
   begin
      v_game_id := require_current_player(p_participant_id);
      select u."ID_ПОЗИЦИИ", x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         current_cell_id,
         v_turn_state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(-20073, 'Отказ недоступен');
      end if;
      select "ID_ВЛАДЕЛЬЦА"
        into v_owner_id
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = v_game_id
         and "ID_КЛЕТКИ" = current_cell_id;
      if v_owner_id is not null then
         raise_application_error(-20074, 'Клетка уже куплена');
      end if;
      add_action(
         v_game_id,
         p_participant_id,
         current_cell_id,
         'ОТКАЗ_ОТ_ПОКУПКИ',
         null
      );
      start_auction(
         v_game_id,
         current_cell_id
      );
   end;
   function calculate_rent (
      p_ownership_id number,
      p_dice         number
   ) return number is
      v_cell_type    varchar2(30);
      v_color_group varchar2(20);
      v_mortgaged number;
      rent number;
      v_owner_id number;
      v_game_id number;
      v_count number;
      v_group_count number;
   begin
      select c."ТИП",
             c."ЦВЕТОВАЯ_ГРУППА",
             v."ЗАЛОЖЕНА",
             v."ID_ВЛАДЕЛЬЦА",
             v."ID_ИГРЫ",
             ceil(c."ЦЕНА_ПОКУПКИ" *(1 + v."КОЛВО_ДОМОВ" * 0.25))
        into
         v_cell_type,
         v_color_group,
         v_mortgaged,
         v_owner_id,
         v_game_id,
         rent
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" = p_ownership_id;
      if v_mortgaged = 1 then
         return 0;
      end if;
      if v_cell_type = 'Коммунальная' then
         select count(*)
           into v_count
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ИГРЫ" = v_game_id
            and v."ID_ВЛАДЕЛЬЦА" = v_owner_id
            and v."ЗАЛОЖЕНА" = 0
            and c."ТИП" = 'Коммунальная';
         return p_dice *
            case
               when v_count >= 2 then
                  50
               else
                  25
            end;
      end if;
      select count(*)
        into v_group_count
        from "КЛЕТКИ"
       where "ТИП" = 'Улица'
         and "ЦВЕТОВАЯ_ГРУППА" = v_color_group;
      select count(*)
        into v_count
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = v_game_id
         and v."ID_ВЛАДЕЛЬЦА" = v_owner_id
         and v."ЗАЛОЖЕНА" = 0
         and c."ТИП" = 'Улица'
         and c."ЦВЕТОВАЯ_ГРУППА" = v_color_group;
      return nvl(
         rent,
         0
      ) *
         case
            when v_group_count > 0
               and v_count = v_group_count then
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
      v_game_id number;
      v_ownership_id number;
      v_owner_id number;
      v_mortgaged number;
      rent number;
      recipient_login "ПОЛЬЗОВАТЕЛИ"."ЛОГИН"%type;
   begin
      v_game_id := participant_game(p_participant_id);
      select "ID_ВЛАДЕНИЯ",
             "ID_ВЛАДЕЛЬЦА",
             "ЗАЛОЖЕНА"
        into
         v_ownership_id,
         v_owner_id,
         v_mortgaged
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = v_game_id
         and "ID_КЛЕТКИ" = p_cell_id;
      if v_owner_id is null
      or v_owner_id = p_participant_id
      or v_mortgaged = 1 then
         raise_application_error(-20075, 'Аренда не требуется');
      end if;
      rent := calculate_rent(
         v_ownership_id,
         p_dice
      );
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - rent
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + rent
       where "ID_УЧАСТНИКА" = v_owner_id;
      select p."ЛОГИН" into recipient_login
        from "УЧАСТНИКИ" u join "ПОЛЬЗОВАТЕЛИ" p
          on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
       where u."ID_УЧАСТНИКА" = v_owner_id;
      add_action(
         v_game_id,
         p_participant_id,
         p_cell_id,
         'ОПЛАТА_АРЕНДЫ',
         rent,
         recipient_login
      );
      enter_debt_or_bankruptcy(p_participant_id);
   end;
   procedure apply_chance (
      p_participant_id number,
      p_dice           number
   ) is
      v_game_id number;
      target number;
      v_cell_type         "КАРТЫ_ШАНСА"."ТИП_ЭФФЕКТА"%type;
      v_card_amount number;
      v_card_text         "КАРТЫ_ШАНСА"."ТЕКСТ_СОБЫТИЯ"%type;
      chance_cell number;
      v_old_position number;
      v_new_position number;
      bonus number;
   begin
      v_game_id := participant_game(p_participant_id);
      select "ID_ПОЗИЦИИ"
        into chance_cell
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      select "ID_ЦЕЛЕВОЙ_КЛЕТКИ",
             "ТИП_ЭФФЕКТА",
             "СУММА_ИЗМЕНЕНИЯ",
             "ТЕКСТ_СОБЫТИЯ"
        into
         target,
         v_cell_type,
         v_card_amount,
         v_card_text
        from (
         select "ID_ЦЕЛЕВОЙ_КЛЕТКИ",
                "ТИП_ЭФФЕКТА",
                "СУММА_ИЗМЕНЕНИЯ",
                "ТЕКСТ_СОБЫТИЯ"
           from "КАРТЫ_ШАНСА"
          order by dbms_random.value
      )
       where rownum = 1;

      add_action(
         v_game_id,
         p_participant_id,
         chance_cell,
         'КАРТА_ШАНСА',
         v_card_amount,
         v_card_text
      );
      if v_cell_type = 'Премия' then
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" + v_card_amount
          where "ID_УЧАСТНИКА" = p_participant_id;
         update "ИГРЫ"
            set
            "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
          where "ID_ИГРЫ" = v_game_id;
      elsif v_cell_type = 'Штраф' then
         update "УЧАСТНИКИ"
            set
            "БАЛАНС" = "БАЛАНС" - v_card_amount
          where "ID_УЧАСТНИКА" = p_participant_id;
         enter_debt_or_bankruptcy(p_participant_id);
      else
         select c."ПОЗИЦИЯ"
           into v_old_position
           from "УЧАСТНИКИ" u
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = u."ID_ПОЗИЦИИ"
          where u."ID_УЧАСТНИКА" = p_participant_id;
         select "ПОЗИЦИЯ"
           into v_new_position
           from "КЛЕТКИ"
          where "ID_КЛЕТКИ" = target;
         if v_new_position <= v_old_position then
            bonus := c_start_bonus;
            update "УЧАСТНИКИ"
               set
               "БАЛАНС" = "БАЛАНС" + bonus
             where "ID_УЧАСТНИКА" = p_participant_id;
            add_action(
               v_game_id,
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
            v_game_id,
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
   procedure build_house (
      p_participant_id number
   ) is
      current_cell_id number;
      v_game_id number;
      v_turn_state varchar2(40);
      v_cell_type varchar2(30);
      v_owner_id number;
      v_mortgaged number;
      v_level number;
      v_price number;
      v_balance number;
   begin
      v_game_id := require_current_player(p_participant_id);
      select u."ID_ПОЗИЦИИ", x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         current_cell_id,
         v_turn_state,
         v_balance
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      select c."ТИП",
             ceil(c."ЦЕНА_ПОКУПКИ" * 0.25),
             v."ID_ВЛАДЕЛЬЦА",
             v."ЗАЛОЖЕНА",
             v."КОЛВО_ДОМОВ"
        into
         v_cell_type,
         v_price,
         v_owner_id,
         v_mortgaged,
         v_level
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = v_game_id
         and v."ID_КЛЕТКИ" = current_cell_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
      or v_cell_type <> 'Улица'
      or v_owner_id is null
      or v_owner_id <> p_participant_id
      or v_mortgaged <> 0
      or v_level >= 3
      or v_balance < v_price then
         raise_application_error(-20080, 'Для следующего улучшения недостаточно денег или оно недоступно');
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - v_price
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "КОЛВО_ДОМОВ" = "КОЛВО_ДОМОВ" + 1
       where "ID_ИГРЫ" = v_game_id
         and "ID_КЛЕТКИ" = current_cell_id;
      add_action(
         v_game_id,
         p_participant_id,
         current_cell_id,
         'ПОКУПКА_УЛУЧШЕНИЯ',
         v_price
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = v_game_id;
   end;
   procedure decline_improvement (
      p_participant_id number
   ) is
      current_cell_id number;
      v_game_id number;
      v_turn_state varchar2(40);
      v_owner_id number;
   begin
      v_game_id := require_current_player(p_participant_id);
      select u."ID_ПОЗИЦИИ", x."КОД_СОСТОЯНИЯ_ХОДА"
        into
         current_cell_id,
         v_turn_state
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      select "ID_ВЛАДЕЛЬЦА"
        into v_owner_id
        from "ВЛАДЕНИЯ"
       where "ID_ИГРЫ" = v_game_id
         and "ID_КЛЕТКИ" = current_cell_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_УЛУЧШЕНИЯ'
      or v_owner_id is null
      or v_owner_id <> p_participant_id then
         raise_application_error(-20081, 'Отказ недоступен');
      end if;
      add_action(
         v_game_id,
         p_participant_id,
         current_cell_id,
         'ОТКАЗ_ОТ_УЛУЧШЕНИЯ',
         null
      );
      update "ИГРЫ"
         set
         "КОД_СОСТОЯНИЯ_ХОДА" = 'ЗАВЕРШЕНИЕ_ХОДА'
       where "ID_ИГРЫ" = v_game_id;
   end;
   procedure sell_buildings (
      p_participant_id number,
      p_ownership_id number
   ) is
   begin
      process_properties(p_participant_id, number_list(), number_list(p_ownership_id), true);
   end;
   procedure resolve_debt (
      p_participant_id number,
      p_mortgage_ids number_list,
      p_sale_ids number_list
   ) is
   begin
      process_properties(p_participant_id, p_mortgage_ids, p_sale_ids);
   end;
   procedure process_properties (
      p_participant_id number,
      p_mortgage_ids   number_list,
      p_sale_ids       number_list,
      p_sale_before_roll boolean default false
   ) is
      v_game_id number;
      v_turn_state varchar2(40);
      v_total number := 0;
      v_count number;
      v_mortgage_count number := 0;
      v_sale_count number := 0;
   begin
      v_game_id := require_current_player(p_participant_id);
      select "КОД_СОСТОЯНИЯ_ХОДА" into v_turn_state
        from "ИГРЫ" where "ID_ИГРЫ" = v_game_id;
      if v_turn_state is null
      or (v_turn_state <> 'ПОКРЫТИЕ_ДОЛГА'
          and not (p_sale_before_roll and v_turn_state = 'ОЖИДАНИЕ_БРОСКА')) then
         raise_application_error(-20120, 'Управление долгом сейчас недоступно');
      end if;
      if p_mortgage_ids is not null then
         v_mortgage_count := p_mortgage_ids.count;
      end if;
      if p_sale_ids is not null then
         v_sale_count := p_sale_ids.count;
      end if;
      if v_mortgage_count + v_sale_count = 0 then
         raise_application_error(-20121, 'Ничего не выбрано');
      end if;
      if v_mortgage_count > 0 then
         select count(*),
                nvl(
                   sum(floor(c."ЦЕНА_ПОКУПКИ" / 2)),
                   0
                )
           into
            v_count,
            v_total
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ВЛАДЕНИЯ" in (
            select column_value
              from table ( p_mortgage_ids )
         )
            and v."ID_ИГРЫ" = v_game_id
            and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
            and v."ЗАЛОЖЕНА" = 0
            and v."КОЛВО_ДОМОВ" = 0;
         if v_count <> v_mortgage_count then
            raise_application_error(-20122, 'Некоторые объекты нельзя заложить');
         end if;
      end if;
      if v_sale_count > 0 then
         select count(*),
                v_total + nvl(
                   sum(floor(ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) / 2)),
                   0
                )
           into
            v_count,
            v_total
           from "ВЛАДЕНИЯ" v
           join "КЛЕТКИ" c
         on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
          where v."ID_ВЛАДЕНИЯ" in (
            select column_value
              from table ( p_sale_ids )
         )
            and v."ID_ИГРЫ" = v_game_id
            and v."ID_ВЛАДЕЛЬЦА" = p_participant_id
            and v."ЗАЛОЖЕНА" = 0
            and v."КОЛВО_ДОМОВ" > 0
            and c."ТИП" = 'Улица';
         if v_count <> v_sale_count then
            raise_application_error(-20123, 'Некоторые постройки нельзя продать');
         end if;
      end if;
      if v_mortgage_count > 0 then
         for r in (
            select v."ID_ВЛАДЕНИЯ" v_ownership_id,
                   v."ID_КЛЕТКИ" v_cell_id,
                   floor(c."ЦЕНА_ПОКУПКИ" / 2) v_amount
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
             where "ID_ВЛАДЕНИЯ" = r.v_ownership_id;
            add_action(
               v_game_id,
               p_participant_id,
               r.v_cell_id,
               'ЗАЛОГ_СОБСТВЕННОСТИ',
               r.v_amount
            );
         end loop;
      end if;
      if v_sale_count > 0 then
         for r in (
            select v."ID_ВЛАДЕНИЯ" v_ownership_id,
                   v."ID_КЛЕТКИ" v_cell_id,
                   floor(ceil(c."ЦЕНА_ПОКУПКИ" * 0.25) / 2) v_amount
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
             where "ID_ВЛАДЕНИЯ" = r.v_ownership_id;
            add_action(
               v_game_id,
               p_participant_id,
               r.v_cell_id,
               'ПРОДАЖА_ПОСТРОЕК',
               r.v_amount
            );
         end loop;
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" + v_total
       where "ID_УЧАСТНИКА" = p_participant_id;
      if v_turn_state = 'ПОКРЫТИЕ_ДОЛГА' then
         enter_debt_or_bankruptcy(p_participant_id);
      end if;
   end;
   procedure redeem_property (
      p_participant_id number,
      p_ownership_id   number
   ) is
      v_game_id number;
      v_turn_state varchar2(40);
      v_owner_id number;
      v_mortgaged number;
      v_price number;
      v_cell_id number;
      v_balance number;
      v_amount number;
   begin
      v_game_id := require_current_player(p_participant_id);
      select x."КОД_СОСТОЯНИЯ_ХОДА",
             u."БАЛАНС"
        into
         v_turn_state,
         v_balance
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_turn_state is null
      or v_turn_state <> 'ОЖИДАНИЕ_БРОСКА'
      or v_balance < 0 then
         raise_application_error(-20087, 'Снятие залога недоступно');
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             v."ЗАЛОЖЕНА",
             c."ЦЕНА_ПОКУПКИ",
             v."ID_КЛЕТКИ"
        into
         v_owner_id,
         v_mortgaged,
         v_price,
         v_cell_id
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ВЛАДЕНИЯ" = p_ownership_id
         and v."ID_ИГРЫ" = v_game_id;
      v_amount := ceil(v_price *(1 + c_mortgage_interest));
      if v_owner_id is null
      or v_owner_id <> p_participant_id
      or v_mortgaged <> 1
      or v_balance < v_amount then
         raise_application_error(-20089, 'Для выкупа нужно 110% первоначальной цены');
      end if;
      update "УЧАСТНИКИ"
         set
         "БАЛАНС" = "БАЛАНС" - v_amount
       where "ID_УЧАСТНИКА" = p_participant_id;
      update "ВЛАДЕНИЯ"
         set
         "ЗАЛОЖЕНА" = 0
       where "ID_ВЛАДЕНИЯ" = p_ownership_id;
      add_action(
         v_game_id,
         p_participant_id,
         v_cell_id,
         'СНЯТИЕ_ЗАЛОГА',
         v_amount
      );
   end;
   procedure start_auction (
      p_game_id number,
      p_cell_id number
   ) is
      v_price number;
      v_owner_id number;
      v_turn_state varchar2(40);
   begin
      select "КОД_СОСТОЯНИЯ_ХОДА"
        into v_turn_state
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_turn_state is null or v_turn_state <> 'ОЖИДАНИЕ_ПОКУПКИ' then
         raise_application_error(-20090, 'Аукцион нельзя начать');
      end if;
      select v."ID_ВЛАДЕЛЬЦА",
             c."ЦЕНА_ПОКУПКИ"
        into
         v_owner_id,
         v_price
        from "ВЛАДЕНИЯ" v
        join "КЛЕТКИ" c
      on c."ID_КЛЕТКИ" = v."ID_КЛЕТКИ"
       where v."ID_ИГРЫ" = p_game_id
         and v."ID_КЛЕТКИ" = p_cell_id;
      if v_owner_id is not null then
         raise_application_error(-20092, 'Клетка куплена');
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
           floor(v_price / 2),
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
   ) is
      v_game_id number;
      v_status varchar2(40);
      v_start_price number;
      started date;
      v_player_game_id number;
      v_player_status varchar2(40);
      v_balance number;
      v_initiator_id number;
   begin
      select "ID_ИГРЫ" into v_game_id from "АУКЦИОНЫ" where "ID_АУКЦИОНА" = p_auction_id;
      lock_game(v_game_id);
      select "ID_ИГРЫ",
             "КОД_СТАТУСА_АУКЦИОНА",
             "СТАРТ_ЦЕНА",
             "ДАТА_НАЧАЛА"
        into
         v_game_id,
         v_status,
         v_start_price,
         started
        from "АУКЦИОНЫ"
       where "ID_АУКЦИОНА" = p_auction_id;
      select u."ID_ИГРЫ",
             u."КОД_СТАТУСА_УЧАСТНИКА",
             u."БАЛАНС",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         v_player_game_id,
         v_player_status,
         v_balance,
         v_initiator_id
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_status <> 'АКТИВЕН'
      or v_player_game_id <> v_game_id
      or v_player_status <> 'АКТИВЕН'
      or p_participant_id = v_initiator_id then
         raise_application_error(-20093, 'Ставка недоступна');
      end if;
      if sysdate >= started + c_auction_seconds / 86400 then
         raise_application_error(-20094, 'Время истекло');
      end if;
      if p_amount is null or p_amount <> trunc(p_amount) then
         raise_application_error(-20095, 'Укажите целую сумму ставки');
      end if;
      if
         p_amount <> 0
         and ( p_amount < v_start_price
         or p_amount > v_balance )
      then
         raise_application_error(-20095, 'Ставка должна быть от стартовой цены до вашего баланса');
      end if;
      update "СТАВКИ" set "СУММА" = p_amount, "ДАТА_ВРЕМЯ" = sysdate
       where "ID_АУКЦИОНА" = p_auction_id and "ID_УЧАСТНИКА" = p_participant_id;
      if sql%rowcount = 0 then
         insert into "СТАВКИ" ("ID_АУКЦИОНА", "ID_УЧАСТНИКА", "СУММА")
         values (p_auction_id, p_participant_id, p_amount);
      end if;
      close_auction(p_auction_id);
   end;
   procedure close_auction (
      p_auction_id number,
      p_force boolean default false
   ) is
      v_game_id number;
      v_cell_id number;
      v_status varchar2(40);
      started date;
      v_initiator_id number;
      winner number := null;
      v_amount number := null;
      game_status varchar2(40);
      eligible number;
      answered number;
   begin
      select a."ID_ИГРЫ",
             a."ID_КЛЕТКИ",
             a."КОД_СТАТУСА_АУКЦИОНА",
             a."ДАТА_НАЧАЛА",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         v_game_id,
         v_cell_id,
         v_status,
         started,
         v_initiator_id
        from "АУКЦИОНЫ" a
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = a."ID_ИГРЫ"
       where a."ID_АУКЦИОНА" = p_auction_id;
      if v_status <> 'АКТИВЕН' then
         return;
      end if;
      select count(*)
        into eligible
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = v_game_id
         and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and "ID_УЧАСТНИКА" <> v_initiator_id;
      select count(*)
        into answered
        from "СТАВКИ" s
        join "УЧАСТНИКИ" u
      on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
       where s."ID_АУКЦИОНА" = p_auction_id
         and u."КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
         and s."ID_УЧАСТНИКА" <> v_initiator_id;
      if
         not p_force and sysdate < started + c_auction_seconds / 86400
         and not (
            eligible > 0
            and answered = eligible
         )
      then
         return;
      end if;
      begin
         select "ID_УЧАСТНИКА",
                "СУММА"
           into
            winner,
            v_amount
           from (
            select s."ID_УЧАСТНИКА",
                   s."СУММА"
              from "СТАВКИ" s
              join "УЧАСТНИКИ" u
            on u."ID_УЧАСТНИКА" = s."ID_УЧАСТНИКА"
             where s."ID_АУКЦИОНА" = p_auction_id
               and s."СУММА" > 0
               and s."ID_УЧАСТНИКА" <> v_initiator_id
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
            "БАЛАНС" = "БАЛАНС" - v_amount
          where "ID_УЧАСТНИКА" = winner;
         update "ВЛАДЕНИЯ"
            set
            "ID_ВЛАДЕЛЬЦА" = winner
          where "ID_ИГРЫ" = v_game_id
            and "ID_КЛЕТКИ" = v_cell_id;
         update "АУКЦИОНЫ"
            set "ID_ПОБЕДИТЕЛЯ" = winner,
                "ФИНАЛ_ЦЕНА" = v_amount,
                "КОД_СТАТУСА_АУКЦИОНА" = 'ЗАВЕРШЕН',
                "ДАТА_ОКОНЧАНИЯ" = sysdate
          where "ID_АУКЦИОНА" = p_auction_id;
         add_action(
            v_game_id,
            winner,
            v_cell_id,
            'АУКЦИОН',
            v_amount
         );
      else
         update "АУКЦИОНЫ"
            set "КОД_СТАТУСА_АУКЦИОНА" = 'НЕ_СОСТОЯЛСЯ',
                "ДАТА_ОКОНЧАНИЯ" = sysdate
          where "ID_АУКЦИОНА" = p_auction_id;
         add_action(
            v_game_id,
            null,
            v_cell_id,
            'АУКЦИОН',
            null
         );
      end if;
      select "КОД_СТАТУСА_ИГРЫ" into game_status from "ИГРЫ" where "ID_ИГРЫ" = v_game_id;
      if game_status = 'АКТИВНА' then
         advance_to_next_player(v_game_id);
      end if;
   end;
   procedure handle_timeout (
      p_game_id number
   ) is
      v_participant_id number;
      v_timeout_count number;
      v_balance number;
   begin
      select "ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into v_participant_id
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      select "КОЛ_ТАЙМАУТОВ"
        into v_timeout_count
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = v_participant_id;
      if v_timeout_count >= 1 then
         update "УЧАСТНИКИ"
            set
            "КОЛ_ТАЙМАУТОВ" = 2
          where "ID_УЧАСТНИКА" = v_participant_id;
         add_action(
            p_game_id,
            v_participant_id,
            null,
            'ТАЙМ_АУТ',
            null
         );
         declare_bankruptcy(
            v_participant_id,
            c_bankruptcy_second_timeout
         );
      else
         update "УЧАСТНИКИ"
            set "КОЛ_ТАЙМАУТОВ" = 1,
                "БАЛАНС" = "БАЛАНС" - c_timeout_penalty
          where "ID_УЧАСТНИКА" = v_participant_id;
         add_action(
            p_game_id,
            v_participant_id,
            null,
            'ТАЙМ_АУТ',
            c_timeout_penalty
         );
         select "БАЛАНС"
           into v_balance
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = v_participant_id;
         if v_balance < 0 then
            enter_debt_or_bankruptcy(v_participant_id);
         else
            advance_to_next_player(p_game_id);
         end if;
      end if;
   end;
   procedure check_game_timer (
      p_game_id number
   ) is
      v_turn_state varchar2(40);
      started date;
      v_game_status varchar2(40);
      v_auction_id number;
      v_participant_id number;
      host_id number;
   begin
      lock_game(p_game_id);
      select "КОД_СОСТОЯНИЯ_ХОДА",
             "ВРЕМЯ_НАЧАЛА_ХОДА",
             "КОД_СТАТУСА_ИГРЫ",
             "ID_ТЕКУЩЕГО_УЧАСТНИКА",
             "ID_ХОСТА"
        into
         v_turn_state,
         started,
         v_game_status,
         v_participant_id,
         host_id
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_game_status = 'ПРОВЕРКА_ГОТОВНОСТИ' then
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
      if v_game_status <> 'АКТИВНА' then
         return;
      end if;
      if
         v_turn_state in ( 'ОЖИДАНИЕ_БРОСКА',
                    'ОЖИДАНИЕ_ПОКУПКИ',
                    'ОЖИДАНИЕ_УЛУЧШЕНИЯ',
                    'ЗАВЕРШЕНИЕ_ХОДА' )
         and sysdate >= started + c_turn_minutes / 1440
      then
         handle_timeout(p_game_id);
      elsif
         v_turn_state = 'ПОКРЫТИЕ_ДОЛГА'
         and sysdate >= started + c_turn_minutes / 1440
      then
         declare_bankruptcy(
            v_participant_id,
            c_bankruptcy_debt_timeout
         );
      elsif v_turn_state = 'ПРОВЕДЕНИЕ_АУКЦИОНА' then
         begin
            select "ID_АУКЦИОНА"
              into v_auction_id
              from "АУКЦИОНЫ"
             where "ID_ИГРЫ" = p_game_id
               and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
            close_auction(v_auction_id);
         exception
            when no_data_found then
               null;
         end;
      end if;
   end;
   procedure finish_game (
      p_game_id   number,
      p_winner_id number default null
   ) is
      v_status varchar2(40);
      v_count number;
   begin
      select "КОД_СТАТУСА_ИГРЫ"
        into v_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = p_game_id;
      if v_status in ( 'ЗАВЕРШЕНА',
                 'ЗАБРОШЕНА' ) then
         return;
      end if;
      if p_winner_id is not null then
         select count(*)
           into v_count
           from "УЧАСТНИКИ"
          where "ID_УЧАСТНИКА" = p_winner_id
            and "ID_ИГРЫ" = p_game_id;
         if v_count = 0 then
            raise_application_error(-20100, 'Победитель из другой игры');
         end if;
      end if;
      update "АУКЦИОНЫ"
         set "КОД_СТАТУСА_АУКЦИОНА" = 'НЕ_СОСТОЯЛСЯ', "ДАТА_ОКОНЧАНИЯ" = sysdate
       where "ID_ИГРЫ" = p_game_id and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
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
      v_count number;
      winner number;
   begin
      select count(*), min("ID_УЧАСТНИКА") into v_count, winner
        from "УЧАСТНИКИ"
       where "ID_ИГРЫ" = p_game_id and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН';
      if v_count = 1 then
         finish_game(
            p_game_id,
            winner
         );
      elsif v_count = 0 then
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
      v_game_id number;
      v_balance number;
      v_current_player_id number;
      v_game_status varchar2(40);
   begin
      if p_reason is null or p_reason not in ( c_bankruptcy_debt_timeout,
                           c_bankruptcy_second_timeout ) then
         raise_application_error(-20101, 'Неизвестная причина');
      end if;
      select u."ID_ИГРЫ",
             u."БАЛАНС",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА"
        into
         v_game_id,
         v_balance,
         v_current_player_id
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      update "УЧАСТНИКИ"
         set
         "КОД_СТАТУСА_УЧАСТНИКА" = 'БАНКРОТ'
       where "ID_УЧАСТНИКА" = p_participant_id;
      return_properties_to_bank(p_participant_id);
      add_action(
         v_game_id,
         p_participant_id,
         null,
         'БАНКРОТСТВО',
         v_balance
      );
      finish_or_continue(v_game_id);
      select "КОД_СТАТУСА_ИГРЫ"
        into v_game_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = v_game_id;
      if
         v_game_status = 'АКТИВНА'
         and v_current_player_id = p_participant_id
      then
         advance_to_next_player(v_game_id);
      end if;
   end;
   procedure leave_active_game (
      p_participant_id number
   ) is
      v_game_id number;
      v_game_status varchar2(40);
      v_count number;
   begin
      v_game_id := lock_participant_game(p_participant_id);
      select "КОД_СТАТУСА_ИГРЫ" into v_game_status
        from "ИГРЫ" where "ID_ИГРЫ" = v_game_id;
      if v_game_status <> 'АКТИВНА' then
         raise_application_error(-20104, 'Игра не активна');
      end if;
      select count(*)
        into v_count
        from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = v_game_id
         and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if v_count > 0 then
         raise_application_error(-20105, 'Нельзя выйти во время аукциона');
      end if;
      disconnect_player(p_participant_id);
   end;
   procedure disconnect_player (
      p_participant_id number
   ) is
      v_game_id number;
      v_current_player_id number;
      v_game_status varchar2(40);
      auction_id number;
   begin
      v_game_id := lock_participant_game(p_participant_id);
      select u."ID_ИГРЫ",
             x."ID_ТЕКУЩЕГО_УЧАСТНИКА",
             x."КОД_СТАТУСА_ИГРЫ"
        into
         v_game_id,
         v_current_player_id,
         v_game_status
        from "УЧАСТНИКИ" u
        join "ИГРЫ" x
      on x."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      update "УЧАСТНИКИ"
         set
         "КОД_СТАТУСА_УЧАСТНИКА" = 'ПОКИНУЛ'
       where "ID_УЧАСТНИКА" = p_participant_id
         and "КОД_СТАТУСА_УЧАСТНИКА" in ('АКТИВЕН', 'БАНКРОТ');
      if sql%rowcount = 0 then
         return;
      end if;
      if v_game_status <> 'АКТИВНА' then
         return;
      end if;
      return_properties_to_bank(p_participant_id);
      add_action(
         v_game_id,
         p_participant_id,
         null,
         'ВЫХОД_УЧАСТНИКА',
         null
      );
      add_action(
         v_game_id,
         p_participant_id,
         null,
         'БАНКРОТСТВО',
         null
      );
      finish_or_continue(v_game_id);
      select "КОД_СТАТУСА_ИГРЫ"
        into v_game_status
        from "ИГРЫ"
       where "ID_ИГРЫ" = v_game_id;
      if v_game_status <> 'АКТИВНА' then
         return;
      end if;
      select max("ID_АУКЦИОНА") into auction_id from "АУКЦИОНЫ"
       where "ID_ИГРЫ" = v_game_id and "КОД_СТАТУСА_АУКЦИОНА" = 'АКТИВЕН';
      if auction_id is not null then
         -- Инициатор остаётся текущим до закрытия торгов.
         -- При выходе другого игрока проверяем, ответили ли все оставшиеся.
         close_auction(auction_id, v_current_player_id = p_participant_id);
      elsif v_current_player_id = p_participant_id then
         advance_to_next_player(v_game_id);
      end if;
   end;
   procedure send_message (
      p_participant_id number,
      p_text           varchar2
   ) is
      v_game_id number;
      v_player_status varchar2(40);
      gs varchar2(40);
   begin
      v_game_id := lock_participant_game(p_participant_id);
      if trim(p_text) is null then
         raise_application_error(-20110, 'Пустое сообщение');
      end if;
      select u."КОД_СТАТУСА_УЧАСТНИКА",
             games."КОД_СТАТУСА_ИГРЫ"
        into
         v_player_status,
         gs
        from "УЧАСТНИКИ" u
        join "ИГРЫ" games
      on games."ID_ИГРЫ" = u."ID_ИГРЫ"
       where u."ID_УЧАСТНИКА" = p_participant_id;
      if v_player_status not in ( 'В_ЛОББИ',
                     'АКТИВЕН', 'БАНКРОТ' )
      or gs = 'ЗАБРОШЕНА' then
         raise_application_error(-20111, 'Чат недоступен');
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
      v_result sys_refcursor;
      v_game_id number;
      v_player_status varchar2(40);
   begin
      select "ID_ИГРЫ",
             "КОД_СТАТУСА_УЧАСТНИКА"
        into
         v_game_id,
         v_player_status
        from "УЧАСТНИКИ"
       where "ID_УЧАСТНИКА" = p_participant_id;
      if v_player_status not in ( 'В_ЛОББИ',
                     'АКТИВЕН', 'БАНКРОТ' ) then
         raise_application_error(-20112, 'Чат недоступен');
      end if;
      open v_result for select c."ID_СООБЩЕНИЯ",
                         p."ЛОГИН",
                         c."ТЕКСТ",
                         c."ДАТА_ВРЕМЯ"
                              from "ЧАТ" c
                              join "УЧАСТНИКИ" u
                            on u."ID_УЧАСТНИКА" = c."ID_УЧАСТНИКА"
                              join "ПОЛЬЗОВАТЕЛИ" p
                            on p."ID_ПОЛЬЗОВАТЕЛЯ" = u."ID_ПОЛЬЗОВАТЕЛЯ"
                  where u."ID_ИГРЫ" = v_game_id
                  order by c."ДАТА_ВРЕМЯ",
                           c."ID_СООБЩЕНИЯ";
      return v_result;
   end;
   function get_action_log (
      p_participant_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
      v_game_id number;
   begin
      v_game_id := participant_game(p_participant_id);
      open v_result for select *
                                from (
                                 select j."ID_ДЕЙСТВИЯ",
                                        j."ДАТА_ВРЕМЯ",
                                        j."КОД_ДЕЙСТВИЯ",
                                        t."НАИМЕНОВАНИЕ" "ДЕЙСТВИЕ",
                                        p."ЛОГИН",
                                        c."НАЗВАНИЕ" "КЛЕТКА",
                                        j."СУММА",
                                        case
                                           when j."КОД_ДЕЙСТВИЯ" = 'ОПЛАТА_АРЕНДЫ' then j."ТЕКСТ_СОБЫТИЯ"
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
                                  where j."ID_ИГРЫ" = v_game_id
                                  order by j."ID_ДЕЙСТВИЯ" desc
                              )
                   where rownum <= 80
                   order by "ID_ДЕЙСТВИЯ";
      return v_result;
   end;

   -- Вызывается клиентом только для собственного участника.
   -- Блокировка игры сериализует heartbeat, выход и определение победителя.
   procedure heartbeat(p_participant_id number) is
      v_game_id number;
      v_status varchar2(40);
      v_connected number;
      v_now date := sysdate;
   begin
      v_game_id := lock_participant_game(p_participant_id);
      v_now := sysdate;
      select "КОД_СТАТУСА_ИГРЫ" into v_status
        from "ИГРЫ" where "ID_ИГРЫ" = v_game_id;
      if v_status = 'АКТИВНА' then
         select count(*) into v_connected from "УЧАСТНИКИ"
          where "ID_ИГРЫ" = v_game_id
            and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
            and "ПОСЛЕДНЯЯ_СВЯЗЬ" > v_now - c_disconnect_seconds / 86400;
         -- Если отсутствовали все, нельзя объявлять последнего в цикле победителем.
         if v_connected = 0 then
            finish_game(v_game_id, null);
         end if;
         for player in (
            select "ID_УЧАСТНИКА" from "УЧАСТНИКИ"
             where "ID_ИГРЫ" = v_game_id
               and "КОД_СТАТУСА_УЧАСТНИКА" = 'АКТИВЕН'
               and "ПОСЛЕДНЯЯ_СВЯЗЬ" <= v_now - c_disconnect_seconds / 86400
             order by "ID_УЧАСТНИКА"
         ) loop
            disconnect_player(player."ID_УЧАСТНИКА");
         end loop;
      end if;
      -- Проверяем истечение срока ДО обновления: исключённый не воскресает.
      update "УЧАСТНИКИ" set "ПОСЛЕДНЯЯ_СВЯЗЬ" = v_now
       where "ID_УЧАСТНИКА" = p_participant_id
         and "КОД_СТАТУСА_УЧАСТНИКА" in ('В_ЛОББИ', 'АКТИВЕН', 'БАНКРОТ');
   end;

   procedure get_game_snapshot (
      p_participant_id  number,
      p_last_action_id  number,
      p_last_message_id number,
      p_state           out sys_refcursor,
      p_players         out sys_refcursor,
      p_cells           out sys_refcursor,
      p_ownerships      out sys_refcursor,
      p_actions         out sys_refcursor,
      p_chat            out sys_refcursor
   ) is
      v_game_id number;
   begin
      v_game_id := participant_game(p_participant_id);
      heartbeat(p_participant_id);
      check_game_timer(v_game_id);
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
                                                       where vx."ID_ИГРЫ" = v_game_id
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
                            where v."ID_ИГРЫ" = v_game_id;

      open p_actions for select j."ID_ДЕЙСТВИЯ",
                                j."ДАТА_ВРЕМЯ",
                                j."КОД_ДЕЙСТВИЯ",
                                t."НАИМЕНОВАНИЕ" "ДЕЙСТВИЕ",
                                p."ЛОГИН",
                                c."НАЗВАНИЕ" "КЛЕТКА",
                                j."СУММА",
                                j."ТЕКСТ_СОБЫТИЯ",
                                case
                                   when j."КОД_ДЕЙСТВИЯ" = 'ОПЛАТА_АРЕНДЫ' then j."ТЕКСТ_СОБЫТИЯ"
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
                         where j."ID_ИГРЫ" = v_game_id
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
                      where u."ID_ИГРЫ" = v_game_id
                        and exists (select 1 from "УЧАСТНИКИ" reader
                                     where reader."ID_УЧАСТНИКА" = p_participant_id
                                       and reader."КОД_СТАТУСА_УЧАСТНИКА" in ('В_ЛОББИ', 'АКТИВЕН', 'БАНКРОТ'))
                        and ch."ID_СООБЩЕНИЯ" > nvl(
                        p_last_message_id,
                        0
                     )
                      order by ch."ID_СООБЩЕНИЯ";
   end;
   function get_player_stats (
      p_user_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for with played as (
                                 select u."ID_УЧАСТНИКА",
                                        u."ID_ИГРЫ",
                                        games."ID_ПОБЕДИТЕЛЯ"
                                   from "УЧАСТНИКИ" u
                                   join "ИГРЫ" games
                                 on games."ID_ИГРЫ" = u."ID_ИГРЫ"
                                  where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                                    and u."ОЧЕРЕДЬ_ХОДА" is not null
                                    and games."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                              ),fav as (
                                 select c."НАЗВАНИЕ",
                                        count(*) visit_count,
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
                                   join "ИГРЫ" games
                                 on games."ID_ИГРЫ" = j."ID_ИГРЫ"
                                  where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                                    and j."КОД_ДЕЙСТВИЯ" = 'ПОСЕЩЕНИЕ_КЛЕТКИ'
                                    and games."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
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
      return v_result;
   end;
   function get_leaderboard return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for select p."ID_ПОЛЬЗОВАТЕЛЯ",
                         p."ЛОГИН",
                         count(games."ID_ИГРЫ") "ИГРЫ",
                         nvl(
                                 sum(
                                    case
                                       when games."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                          1
                                       else
                                          0
                                    end
                                 ),
                                 0
                              ) "ПОБЕДЫ",
                         case
                            when count(games."ID_ИГРЫ") = 0 then
                                    0
                            else
                               round(
                                       100 * sum(
                                          case
                                             when games."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                                1
                                             else
                                                0
                                          end
                                       ) / count(games."ID_ИГРЫ"),
                                       2
                                    )
                         end "ПРОЦЕНТ"
                                from "ПОЛЬЗОВАТЕЛИ" p
                                left join "УЧАСТНИКИ" u
                              on u."ID_ПОЛЬЗОВАТЕЛЯ" = p."ID_ПОЛЬЗОВАТЕЛЯ"
                                 and u."ОЧЕРЕДЬ_ХОДА" is not null
                                left join "ИГРЫ" games
                              on games."ID_ИГРЫ" = u."ID_ИГРЫ"
                                 and games."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                   group by p."ID_ПОЛЬЗОВАТЕЛЯ",
                            p."ЛОГИН"
                   order by "ПРОЦЕНТ" desc,
                            "ПОБЕДЫ" desc,
                            "ИГРЫ" desc,
                            p."ЛОГИН";
      return v_result;
   end;
   function get_game_history (
      p_user_id number
   ) return sys_refcursor is
      v_result sys_refcursor;
   begin
      open v_result for select games."ID_ИГРЫ",
                         games."НАЗВАНИЕ",
                         games."ДАТА_СТАРТА",
                         games."ДАТА_ЗАВЕРШЕНИЯ",
                         u."БАЛАНС" "ИТОГОВЫЙ_БАЛАНС",
                         u."КОД_СТАТУСА_УЧАСТНИКА",
                         wp."ЛОГИН" "ПОБЕДИТЕЛЬ",
                         case
                            when games."ID_ПОБЕДИТЕЛЯ" = u."ID_УЧАСТНИКА" then
                                    'Победа'
                            else
                               'Поражение'
                         end "РЕЗУЛЬТАТ"
                                from "УЧАСТНИКИ" u
                                join "ИГРЫ" games
                              on games."ID_ИГРЫ" = u."ID_ИГРЫ"
                                left join "УЧАСТНИКИ" wu
                              on wu."ID_УЧАСТНИКА" = games."ID_ПОБЕДИТЕЛЯ"
                                left join "ПОЛЬЗОВАТЕЛИ" wp
                              on wp."ID_ПОЛЬЗОВАТЕЛЯ" = wu."ID_ПОЛЬЗОВАТЕЛЯ"
                   where u."ID_ПОЛЬЗОВАТЕЛЯ" = p_user_id
                     and u."ОЧЕРЕДЬ_ХОДА" is not null
                     and games."КОД_СТАТУСА_ИГРЫ" = 'ЗАВЕРШЕНА'
                   order by games."ДАТА_ЗАВЕРШЕНИЯ" desc;
      return v_result;
   end;
end monopoly;
/
