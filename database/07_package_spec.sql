create or replace package monopoly as
   c_start_balance constant number := 1200;
   c_start_bonus constant number := 100;
   c_timeout_penalty constant number := 50;
   c_turn_minutes constant number := 2;
   c_auction_seconds constant number := 30;
   c_ready_seconds constant number := 10;
   c_mortgage_interest constant number := 0.10;
   c_bankruptcy_voluntary constant varchar2(100) := 'ДОБРОВОЛЬНО';
   c_bankruptcy_debt_timeout constant varchar2(100) := 'ИСТЕКЛО_ВРЕМЯ_ПОКРЫТИЯ_ДОЛГА';
   c_bankruptcy_second_timeout constant varchar2(100) := 'ПОВТОРНЫЙ_ТАЙМ_АУТ';
   procedure register_user (
      p_login    in varchar2,
      p_password in varchar2
   );
   function authenticate_user (
      p_login    in varchar2,
      p_password in varchar2
   ) return number;
   procedure create_game (
      p_user_id       in number,
      p_game_name     in varchar2,
      p_max_players   in number default 4,
      p_room_password in varchar2 default null,
      p_game_id       out number
   );
   function list_waiting_games return sys_refcursor;
   procedure join_game (
      p_user_id       in number,
      p_game_id       in number,
      p_room_password in varchar2 default null
   );
   procedure leave_lobby (
      p_participant_id in number
   );
   procedure abandon_waiting_game (
      p_user_id in number,
      p_game_id in number
   );
   procedure set_ready (
      p_participant_id in number,
      p_ready          in number
   );
   procedure start_game (
      p_game_id      in number,
      p_host_user_id in number
   );
   function get_game_state (
      p_participant_id in number
   ) return sys_refcursor;
   function get_game_participants (
      p_participant_id in number
   ) return sys_refcursor;
   function get_board_state (
      p_participant_id in number
   ) return sys_refcursor;
   function get_player_properties (
      p_participant_id in number
   ) return sys_refcursor;
   function get_active_auction (
      p_participant_id in number
   ) return sys_refcursor;
   procedure get_game_snapshot (
      p_participant_id  in number,
      p_last_action_id  in number,
      p_last_message_id in number,
      p_known_version   in number,
      p_include_static  in number,
      p_state           out sys_refcursor,
      p_players         out sys_refcursor,
      p_cells           out sys_refcursor,
      p_ownerships      out sys_refcursor,
      p_actions         out sys_refcursor,
      p_chat            out sys_refcursor
   );
   procedure roll_and_move (
      p_participant_id in number,
      p_dice           out number
   );
   procedure process_cell (
      p_participant_id in number,
      p_dice           in number
   );
   procedure end_turn (
      p_game_id in number
   );
   procedure advance_to_next_player (
      p_game_id in number
   );
   procedure buy_property (
      p_participant_id in number,
      p_cell_id        in number
   );
   procedure decline_purchase (
      p_participant_id in number,
      p_cell_id        in number
   );
   function calculate_rent (
      p_ownership_id in number,
      p_dice         in number
   ) return number;
   procedure pay_rent (
      p_participant_id in number,
      p_cell_id        in number,
      p_dice           in number
   );
   procedure apply_chance (
      p_participant_id in number,
      p_dice           in number
   );
   function owns_full_color_group (
      p_participant_id in number,
      p_color_group    in varchar2
   ) return number;
   procedure build_house (
      p_participant_id in number,
      p_cell_id        in number
   );
   procedure decline_improvement (
      p_participant_id in number,
      p_cell_id        in number
   );
   procedure sell_buildings (
      p_participant_id in number,
      p_ownership_id   in number,
      p_count          in number
   );
   procedure mortgage_properties (
      p_participant_id in number,
      p_ownership_ids  in number_list
   );
   procedure redeem_property (
      p_participant_id in number,
      p_ownership_id   in number
   );
   procedure resolve_debt (
      p_participant_id in number,
      p_mortgage_ids   in number_list,
      p_sale_ids       in number_list
   );
   procedure start_auction (
      p_game_id in number,
      p_cell_id in number
   );
   procedure make_bid (
      p_auction_id     in number,
      p_participant_id in number,
      p_amount         in number
   );
   procedure close_auction (
      p_auction_id in number
   );
   procedure check_game_timer (
      p_game_id in number
   );
   procedure handle_timeout (
      p_game_id in number
   );
   procedure leave_active_game (
      p_participant_id in number
   );
   procedure disconnect_player (
      p_participant_id in number
   );
   procedure declare_bankruptcy (
      p_participant_id in number,
      p_reason         in varchar2
   );
   procedure finish_or_continue (
      p_game_id in number
   );
   procedure finish_game (
      p_game_id   in number,
      p_winner_id in number default null
   );
   procedure send_message (
      p_participant_id in number,
      p_text           in varchar2
   );
   function get_chat (
      p_participant_id in number
   ) return sys_refcursor;
   function get_action_log (
      p_participant_id in number
   ) return sys_refcursor;
   function get_player_stats (
      p_user_id in number
   ) return sys_refcursor;
   function get_leaderboard return sys_refcursor;
   function get_game_history (
      p_user_id in number
   ) return sys_refcursor;
   procedure add_action (
      p_game_id        in number,
      p_participant_id in number default null,
      p_cell_id        in number default null,
      p_action_code    in varchar2,
      p_amount         in number default null,
      p_event_text     in varchar2 default null
   );
   procedure return_properties_to_bank (
      p_participant_id in number
   );
end monopoly;
/