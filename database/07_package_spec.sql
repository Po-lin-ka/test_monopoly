create or replace package monopoly as
   c_start_fund constant number := 1200;
   c_start_bonus constant number := 100;
   c_timeout_penalty constant number := 50;
   c_turn_minutes constant number := 2;
   c_auction_seconds constant number := 30;
   c_ready_seconds constant number := 10;
   c_mortgage_interest constant number := 0.10;
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
   procedure end_turn (
      p_game_id in number
   );
   procedure buy_property (
      p_participant_id in number
   );
   procedure decline_purchase (
      p_participant_id in number
   );
   procedure build_house (
      p_participant_id in number
   );
   procedure decline_improvement (
      p_participant_id in number
   );
   procedure sell_buildings (
      p_participant_id in number,
      p_ownership_id   in number
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
   procedure make_bid (
      p_auction_id     in number,
      p_participant_id in number,
      p_amount         in number
   );
   procedure leave_active_game (
      p_participant_id in number
   );
   procedure disconnect_player (
      p_participant_id in number
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
end monopoly;
/
