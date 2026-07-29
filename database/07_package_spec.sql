CREATE OR REPLACE PACKAGE monopoly AS
 c_start_balance CONSTANT NUMBER:=1200; c_timeout_penalty CONSTANT NUMBER:=50; c_turn_minutes CONSTANT NUMBER:=2; c_auction_seconds CONSTANT NUMBER:=30; c_ready_seconds CONSTANT NUMBER:=10; c_mortgage_interest CONSTANT NUMBER:=0.10;
 c_bankruptcy_voluntary CONSTANT VARCHAR2(100) := 'ДОБРОВОЛЬНО';
 c_bankruptcy_debt_timeout CONSTANT VARCHAR2(100) := 'ИСТЕКЛО_ВРЕМЯ_ПОКРЫТИЯ_ДОЛГА';
 c_bankruptcy_second_timeout CONSTANT VARCHAR2(100) := 'ПОВТОРНЫЙ_ТАЙМ_АУТ';
 PROCEDURE register_user(p_login IN VARCHAR2,p_password IN VARCHAR2); FUNCTION authenticate_user(p_login IN VARCHAR2,p_password IN VARCHAR2) RETURN NUMBER;
 PROCEDURE create_game(p_user_id IN NUMBER,p_game_name IN VARCHAR2,p_max_players IN NUMBER DEFAULT 4,p_room_password IN VARCHAR2 DEFAULT NULL,p_game_id OUT NUMBER);
 FUNCTION list_waiting_games RETURN SYS_REFCURSOR; PROCEDURE join_game(p_user_id IN NUMBER,p_game_id IN NUMBER,p_room_password IN VARCHAR2 DEFAULT NULL);
 PROCEDURE leave_lobby(p_participant_id IN NUMBER); PROCEDURE abandon_waiting_game(p_user_id IN NUMBER,p_game_id IN NUMBER); PROCEDURE kick_participant(p_host_user_id IN NUMBER,p_participant_id IN NUMBER);
 PROCEDURE request_start(p_game_id IN NUMBER,p_host_user_id IN NUMBER); PROCEDURE set_ready(p_participant_id IN NUMBER,p_ready IN NUMBER); PROCEDURE start_game(p_game_id IN NUMBER,p_host_user_id IN NUMBER);
 FUNCTION get_game_state(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR; FUNCTION get_game_participants(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR; FUNCTION get_board_state(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR; FUNCTION get_player_properties(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR; FUNCTION get_active_auction(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR;
 PROCEDURE roll_and_move(p_participant_id IN NUMBER,p_dice OUT NUMBER); PROCEDURE process_cell(p_participant_id IN NUMBER,p_dice IN NUMBER); PROCEDURE end_turn(p_game_id IN NUMBER); PROCEDURE advance_to_next_player(p_game_id IN NUMBER);
 PROCEDURE buy_property(p_participant_id IN NUMBER,p_cell_id IN NUMBER); PROCEDURE decline_purchase(p_participant_id IN NUMBER,p_cell_id IN NUMBER); FUNCTION calculate_rent(p_ownership_id IN NUMBER,p_dice IN NUMBER) RETURN NUMBER; PROCEDURE pay_rent(p_participant_id IN NUMBER,p_cell_id IN NUMBER,p_dice IN NUMBER); PROCEDURE apply_chance(p_participant_id IN NUMBER,p_dice IN NUMBER);
 FUNCTION owns_full_color_group(p_participant_id IN NUMBER,p_color_group IN VARCHAR2) RETURN NUMBER; PROCEDURE build_house(p_participant_id IN NUMBER,p_cell_id IN NUMBER); PROCEDURE decline_improvement(p_participant_id IN NUMBER,p_cell_id IN NUMBER); PROCEDURE sell_buildings(p_participant_id IN NUMBER,p_ownership_id IN NUMBER,p_count IN NUMBER);
 PROCEDURE mortgage_properties(p_participant_id IN NUMBER,p_ownership_ids IN number_list); PROCEDURE redeem_property(p_participant_id IN NUMBER,p_ownership_id IN NUMBER);
 PROCEDURE resolve_debt(p_participant_id IN NUMBER,p_mortgage_ids IN number_list,p_sale_ids IN number_list);
 PROCEDURE start_auction(p_game_id IN NUMBER,p_cell_id IN NUMBER); PROCEDURE make_bid(p_auction_id IN NUMBER,p_participant_id IN NUMBER,p_amount IN NUMBER); PROCEDURE close_auction(p_auction_id IN NUMBER);
 PROCEDURE check_game_timer(p_game_id IN NUMBER); PROCEDURE handle_timeout(p_game_id IN NUMBER);
 PROCEDURE leave_active_game(p_participant_id IN NUMBER); PROCEDURE disconnect_player(p_participant_id IN NUMBER); PROCEDURE declare_bankruptcy(p_participant_id IN NUMBER,p_reason IN VARCHAR2); PROCEDURE finish_or_continue(p_game_id IN NUMBER); PROCEDURE finish_game(p_game_id IN NUMBER,p_winner_id IN NUMBER DEFAULT NULL);
 PROCEDURE send_message(p_participant_id IN NUMBER,p_text IN VARCHAR2); FUNCTION get_chat(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR;
 FUNCTION get_action_log(p_participant_id IN NUMBER) RETURN SYS_REFCURSOR;
 FUNCTION get_player_stats(p_user_id IN NUMBER) RETURN SYS_REFCURSOR; FUNCTION get_leaderboard RETURN SYS_REFCURSOR; FUNCTION get_game_history(p_user_id IN NUMBER) RETURN SYS_REFCURSOR;
 PROCEDURE add_action(p_game_id IN NUMBER,p_participant_id IN NUMBER DEFAULT NULL,p_cell_id IN NUMBER DEFAULT NULL,p_action_code IN VARCHAR2,p_amount IN NUMBER DEFAULT NULL); PROCEDURE return_properties_to_bank(p_participant_id IN NUMBER);
END monopoly;
/
