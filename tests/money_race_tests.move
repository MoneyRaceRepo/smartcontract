#[test_only]
module money_race::money_race_tests {
    use money_race::money_race::{Self, AdminCap, Room, Vault, PlayerPosition};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self};

    /* =========================
        TEST CONSTANTS
    ==========================*/

    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0x1;
    const PLAYER2: address = @0x2;

    const DEPOSIT_AMOUNT: u64 = 1000;
    const TOTAL_PERIODS: u64 = 5;
    const PERIOD_LENGTH_MS: u64 = 86400000; // 1 day in milliseconds
    const START_TIME_MS: u64 = 1000000000;

    /* =========================
        HELPER FUNCTIONS
    ==========================*/

    fun setup_test(): Scenario {
        let mut scenario = ts::begin(ADMIN);
        {
            money_race::init_for_testing(ts::ctx(&mut scenario));
        };
        scenario
    }

    fun create_and_share_room(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let (room, vault) = money_race::create_room(
                TOTAL_PERIODS,
                DEPOSIT_AMOUNT,
                1, // strategy_id
                START_TIME_MS,
                PERIOD_LENGTH_MS,
                ts::ctx(scenario)
            );

            money_race::share_room(room);
            money_race::share_vault(vault);
        };
    }

    fun mint_coin(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }

    /* =========================
        TEST: CREATE ROOM
    ==========================*/

    #[test]
    fun test_create_room_success() {
        let mut scenario = setup_test();

        ts::next_tx(&mut scenario, ADMIN);
        {
            let (room, vault) = money_race::create_room(
                TOTAL_PERIODS,
                DEPOSIT_AMOUNT,
                1,
                START_TIME_MS,
                PERIOD_LENGTH_MS,
                ts::ctx(&mut scenario)
            );

            money_race::share_room(room);
            money_race::share_vault(vault);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: START ROOM
    ==========================*/

    #[test]
    fun test_start_room_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);

            money_race::start_room(&admin_cap, &mut room);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_start_room_already_started() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room first time
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);

            money_race::start_room(&admin_cap, &mut room);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Try to start again (should fail)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);

            money_race::start_room(&admin_cap, &mut room);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: JOIN ROOM
    ==========================*/

    #[test]
    fun test_join_room_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(
                &room,
                &mut vault,
                &clock,
                coin,
                ts::ctx(&mut scenario)
            );

            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_join_room_not_started() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Try to join without starting (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(
                &room,
                &mut vault,
                &clock,
                coin,
                ts::ctx(&mut scenario)
            );

            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 8)]
    fun test_join_room_after_period_0() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Try to join in period 1 (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(
                &room,
                &mut vault,
                &clock,
                coin,
                ts::ctx(&mut scenario)
            );

            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun test_join_room_wrong_amount() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Try to join with wrong amount (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT + 100, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(
                &room,
                &mut vault,
                &clock,
                coin,
                ts::ctx(&mut scenario)
            );

            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: DEPOSIT
    ==========================*/

    #[test]
    fun test_deposit_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player deposits in period 1
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_deposit_same_period_twice() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins in period 0
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player deposits in period 1
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Try to deposit in same period again (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS + 1000);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: FINALIZE ROOM
    ==========================*/

    #[test]
    fun test_finalize_room_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Finalize room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);

            money_race::finalize_room(&admin_cap, &mut room, 100);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 7)]
    fun test_finalize_room_zero_weight() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Try to finalize with zero weight (should fail)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);

            money_race::finalize_room(&admin_cap, &mut room, 0);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: FUND REWARD POOL
    ==========================*/

    #[test]
    fun test_fund_reward_pool_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);

            let coin = mint_coin(5000, ts::ctx(&mut scenario));
            money_race::fund_reward_pool(&admin_cap, &mut vault, coin);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: CLAIM ALL (PRINCIPAL + REWARD)
    ==========================*/

    #[test]
    fun test_claim_all_success() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins (1 deposit)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player makes 2 more deposits (total 3 deposits)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS * 2);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Fund reward pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let coin = mint_coin(6000, ts::ctx(&mut scenario));
            money_race::fund_reward_pool(&admin_cap, &mut vault, coin);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(vault);
        };

        // Finalize room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::finalize_room(&admin_cap, &mut room, 3);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Claim all (should get 3 * DEPOSIT_AMOUNT principal + reward)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);

            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_claim_all_room_not_finished() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Try to claim all without finalizing (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);

            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_claim_all_twice() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Fund reward pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let coin = mint_coin(2000, ts::ctx(&mut scenario));
            money_race::fund_reward_pool(&admin_cap, &mut vault, coin);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(vault);
        };

        // Finalize room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::finalize_room(&admin_cap, &mut room, 1);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Claim all first time
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Try to claim again (should fail)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    /* =========================
        TEST: COMPLETE GAME FLOW
    ==========================*/

    #[test]
    fun test_complete_game_flow_multiple_players() {
        let mut scenario = setup_test();
        create_and_share_room(&mut scenario);

        // Start room
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::start_room(&admin_cap, &mut room);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player 1 joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER1);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player 2 joins
        ts::next_tx(&mut scenario, PLAYER2);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            let player_pos = money_race::join_room(&room, &mut vault, &clock, coin, ts::ctx(&mut scenario));
            transfer::public_transfer(player_pos, PLAYER2);

            clock::destroy_for_testing(clock);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player 1 deposits in period 1 and 2
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
            clock::set_for_testing(&mut clock, START_TIME_MS + PERIOD_LENGTH_MS * 2);

            let coin = mint_coin(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
            money_race::deposit(&room, &mut vault, &mut player_pos, &clock, coin);

            clock::destroy_for_testing(clock);
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Fund reward pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let coin = mint_coin(10000, ts::ctx(&mut scenario));
            money_race::fund_reward_pool(&admin_cap, &mut vault, coin);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(vault);
        };

        // Finalize room (player 1: 3 deposits, player 2: 1 deposit, total weight: 4)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut room = ts::take_shared<Room>(&scenario);
            money_race::finalize_room(&admin_cap, &mut room, 4);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(room);
        };

        // Player 1 claims all (principal: 3000 + reward: 7500 = 10,500)
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        // Player 2 claims all (principal: 1000 + reward: 2500 = 3,500)
        ts::next_tx(&mut scenario, PLAYER2);
        {
            let room = ts::take_shared<Room>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let mut player_pos = ts::take_from_sender<PlayerPosition>(&scenario);
            money_race::claim_all(&room, &mut vault, &mut player_pos, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, player_pos);
            ts::return_shared(room);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }
}
